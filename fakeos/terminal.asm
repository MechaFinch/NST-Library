
;
; FakeOS Terminal
; Uses text drawing to do terminal things
; 

%include "simvideo/gutil.asm" as gutil
%include "simvideo/text.asm" as text

%define VBUFFER_START 0xF002_0000

; Terminal State
%define STATE_NORMAL			0
%define STATE_ANSI_START		1
%define STATE_ANSI_ARG_0		2
%define STATE_ANSI_ARG_1		3
%define STATE_ANSI_ARG_2		4
%define STATE_ANSI_ARG_3		5

%define TERMINAL_WIDTH (320 / 8)
%define TERMINAL_HEIGHT (240 / 8)

%define CHAR_BACKSPACE 0x08
%define CHAR_TAB 0x09
%define CHAR_NEWLINE 0x0A
%define CHAR_ESCAPE 0x1B

current_state:		db STATE_NORMAL
ansi_arg_0:			db 0
ansi_arg_1:			db 0
ansi_arg_2:			db 0
ansi_arg_3:			db 0
ansi_private_mode:	db 0
cursor_x:			db 0
cursor_y:			db 0
color_foreground:	db 0xFF
color_background:	db 0x01
character_cursor:	db '_'
draw_cursor:		db 1
min_x:				db 0
min_y:				db 0
max_x:				db TERMINAL_WIDTH - 1
max_y:				db TERMINAL_HEIGHT - 1



; none init_terminal()
; Resets the terminal
init_terminal:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	PUSH K
	
	; reset state & cursor
	MOV AL, STATE_NORMAL
	MOV [current_state], AL
	
	MOV AL, [min_x]
	MOV [cursor_x], AL
	MOV AL, [min_y]
	MOV [cursor_y], AL
	
	; reset palette
	MOVW D:A, 0
	MOV C, 0
	MOV I, 4
	
.rloop:
	MOV J, 8

.gloop:
	MOV K, 8

.bloop:
	PUSH D
	PUSH A
	PUSH CL
	CALL gutil.set_color
	ADD SP, 5
	
	INC C
	ADD AL, 0x24
	DEC K
	JNZ .bloop
	
	MOV AL, 0
	ADD AH, 0x24
	DEC J
	JNZ .gloop
	
	MOV AH, 0
	ADD D, 0x55
	DEC I
	JNZ .rloop
	
	; specific colors
	; non-transparent black
	PUSH ptr 0
	PUSH byte 1
	CALL gutil.set_color
	
	; perfect white
	PUSH ptr 0xFFFF_FFFF
	PUSH byte 0xFF
	CALL gutil.set_color
	
	; clear screen
	PUSH byte 0
	CALL clear_screen
	ADD SP, 11
	
	POP K
	POP J
	POP I
	POP BP
	RET



; u8 send_character(u8 char)
; Send a character to the terminal
; Returns 1 if character is part of an ANSI escape sequence, 0 otherwise
send_character:
	PUSH BP
	MOVW BP, SP
	
	PUSH byte 0 ; return value
	
	PUSH I
	PUSH J
	
	; what state are we in
	MOVZ A, [current_state]
	JMPA [.state_table + A*4]

.state_table:
	dp .is_normal		; 00	STATE_NORMAL
	dp .is_ansi_start	; 01	STATE_ANSI_START
	dp .is_ansi_arg_0	; 02	STATE_ANSI_ARG_0
	dp .is_ansi_arg_1	; 03	STATE_ANSI_ARG_1
	dp .is_ansi_arg_2	; 04	STATE_ANSI_ARG_2
	dp .is_ansi_arg_3	; 05	STATE_ANSI_ARG_3

.is_normal:
	; normal state. Check special characters
	MOV AL, [BP + 8]
	CMP AL, CHAR_ESCAPE
	JE .char_is_escape
	
	CMP AL, CHAR_BACKSPACE
	JE .char_is_backspace
	
	CMP AL, CHAR_TAB
	JE .char_is_tab
	
	CMP AL, CHAR_NEWLINE
	JE .char_is_newline
	
	CALL sub_normal_char
	JMP .ret
	
.char_is_escape:
	; start of escape sequence
	MOV AL, 1	; char is part of escape sequence
	MOV [BP - 1], AL
	
	MOV AL, STATE_ANSI_START
	MOV [current_state], AL
	JMP .ret

.char_is_backspace:
	; Erase cursor
	CALL sub_clear_cursor

	; Go back one
	MOV AL, [cursor_y]
	MOV AH, [cursor_x]
	
	MOV BL, AH
	DEC AH
	CMP BL, [min_x]
	CMOVE AH, [max_x]
	MOV [cursor_x], AH
	JNE .backspace_cursor
	
	MOV BL, AL
	DEC AL
	CMP BL, [min_y]
	CMOVE AL, BL
	MOV [cursor_y], AL

.backspace_cursor:
	CMP byte [draw_cursor], 0
	JZ .backspace_space
	CALL sub_draw_cursor_fast
	JMP .ret

.backspace_space:
	CALL sub_clear_space
	JMP .ret

.char_is_tab:
	; emit spaces until x is a multiple of 4
	MOV AL, ' '
	CALL sub_normal_char
	
	MOV AL, [cursor_x]
	AND AL, 0x03
	JNZ .char_is_tab
	JMP .ret

.char_is_newline:
	; erase cursor
	CALL sub_clear_cursor
	
	; move to next line
.what:
	MOV AL, [cursor_y]
	INC AL
	CMP AL, [max_y]
	CMOVA AL, [max_y]
	MOV [cursor_y], AL
	JBE .newline_no_scroll
	
	PUSH A
	CALL sub_scroll_up
	POP A

.newline_no_scroll:
	MOV AH, [min_x]
	MOV [cursor_x], AH
	
	CALL sub_draw_cursor_fast
	JMP .ret

.is_ansi_start:
	MOV AL, 1	; char is part of escape sequence
	MOV [BP - 1], AL
	
	; ANSI start. Character determines action or state change
	MOV AL, [BP + 8]
	
	CMP AL, '['	; control sequence introducer. Clear arg 0 and enter STATE_ANSI_ARG_0
	JNE .ansi_start_not_csi
	
	MOV A, 0
	MOV AH, STATE_ANSI_ARG_0
	MOV [current_state], AH
	MOV [ansi_arg_0], AL
	JMP .ret
	
.ansi_start_not_csi:
	CMP AL, 'M'	; move cursor up one line. enter STATE_NORMAL
	JNE .ansi_start_not_m
	
	CALL sub_clear_cursor
	CMP byte [cursor_y], 0
	JNE .ansi_move_up_one_dec

	CALL sub_scroll_down
	JMP .ansi_move_up_one_nodec

.ansi_move_up_one_dec:
	DEC byte [cursor_y]

.ansi_move_up_one_nodec:
	CALL sub_draw_cursor
	JMP .ret_normal

.ansi_start_not_m:
	; not a valid sequence. Enter STATE_NORMAL
	JMP .ret_normal

	; ANSI numeric arguments. Place the appropriate pointer in J:I and jump to a general purpose routine
.is_ansi_arg_0:
	MOVW J:I, ansi_arg_0
	JMP .is_ansi_arg
	
.is_ansi_arg_1:
	MOVW J:I, ansi_arg_1
	JMP .is_ansi_arg
	
.is_ansi_arg_2:
	MOVW J:I, ansi_arg_2
	JMP .is_ansi_arg
	
.is_ansi_arg_3:
	MOVW J:I, ansi_arg_3
	JMP .is_ansi_arg

.is_ansi_arg:
	MOV AL, 1	; char is part of escape sequence
	MOV [BP - 1], AL
	
	; ANSI argument.
	; If a digit, multiply arg by 10 and add digit value
	; If a semicolon, move to next argument state
	; If another character, perform appropriate operation and enter STATE_NORMAL
	MOV AL, [BP + 8]
	CMP AL, ';'
	JNE .ansi_arg_not_semi
	
	; semicolon. Next argument
	CMP byte [current_state], STATE_ANSI_ARG_3	; too many args = end
	JAE .ret_normal
	
	INC byte [current_state]	; arg states are sequential
	INC I						; args are sequential in memory (clear it)
	ICC J
	MOV AL, 0
	MOV [J:I], AL
	JMP .ret

.ansi_arg_not_semi:
	CMP AL, '0'
	JB .ret_normal			; neither a digit nor valid terminator
	CMP AL, '9'
	JA .ansi_arg_not_digit	; not a digit
	
	; digit. Accumulate argument
	MOV BL, [J:I]
	MUL BL, 10
	ADD BL, AL
	SUB BL, '0'
	MOV [J:I], BL
	JMP .ret

.ansi_arg_not_digit:
	; sequence terminators
	CMP AL, 'm'	; SGR 
	JE ansi_select_graphic_rendition
	
	CMP AL, 'H'	; set cursor position
	JE ansi_cursor_set_pos
	
	CMP AL, 'f'
	JE ansi_cursor_set_pos
	
	CMP AL, 'A'	; move cursor up
	JE ansi_cursor_move_up
	
	CMP AL, 'B'	; move cursor down
	JE ansi_cursor_move_down
	
	CMP AL, 'J'	; J-erase functions
	JE ansi_erase_j
	
	CMP AL, '?'	; private modes
	JE ansi_start_private_mode
	
	CMP AL, 'l'	; l-functions
	JE ansi_func_l
	
	CMP AL, 'h'	; h-functions
	JE ansi_func_h
	
	JMP .ret_normal

.ret_normal:
	MOV AL, STATE_NORMAL
	MOV [current_state], AL
	
.ret:
	POP J
	POP I
	POP AL
	POP BP
	RET



; \[[...l
; l-functions
ansi_func_l:
	CMP byte [ansi_private_mode], 0
	JZ .ret
	MOV AL, 0
	MOV [ansi_private_mode], AL
	
	CMP byte [ansi_arg_0], 25
	JNE .ret
	
	; make cursor invisible
	CALL sub_clear_cursor
	MOV AL, 0
	MOV [draw_cursor], AL

.ret:
	JMP send_character.ret_normal



; \[[...h
; h-functions
ansi_func_h:
	CMP byte [ansi_private_mode], 0
	JZ .ret
	MOV AL, 0
	MOV [ansi_private_mode], AL
	
	CMP byte [ansi_arg_0], 25
	JNE .ret
	
	; make cursor visible
	MOV AL, 1
	MOV [draw_cursor], AL
	CALL sub_draw_cursor

.ret:
	JMP send_character.ret_normal



; \[[?
; Private mode
ansi_start_private_mode:
	MOV AL, 1
	MOV [ansi_private_mode], AL
	JMP send_character.ret



; \[[...A
; Move up n lines
ansi_cursor_move_up:
	CALL sub_clear_cursor
	
	MOV AL, [cursor_y]
	SUB AL, [ansi_arg_0]
	CALL sub_clamp_y
	MOV [cursor_y], AL
	
	CALL sub_draw_cursor
	JMP send_character.ret_normal



; \[[...B
; Move down n lines
ansi_cursor_move_down:
	CALL sub_clear_cursor
	
	MOV AL, [cursor_y]
	ADD AL, [ansi_arg_0]
	CALL sub_clamp_y
	MOV [cursor_y], AL
	
	CALL sub_draw_cursor
	JMP send_character.ret_normal



; \[[...H
; \[[...f
; Set cursor position
ansi_cursor_set_pos:
	; if we have 2 args, set pos
	; if we have 1 or 0 args, set 0,0
	CMP byte [current_state], STATE_ANSI_ARG_1
	JAE .has_arg
	
	MOV A, 0
	JMP .move_cursor

.has_arg:
	MOV AL, [ansi_arg_0]
	MOV AH, [ansi_arg_1]

	; erase cursor, move cursor, draw cursor
.move_cursor:
	PUSH A
	CALL sub_clear_cursor
	POP A
	CALL sub_clamp_x
	CALL sub_clamp_y
	MOV [cursor_x], AH
	MOV [cursor_y], AL
	CALL sub_draw_cursor_fast
	JMP send_character.ret_normal



; \[[...J
; Erase functions (J)
ansi_erase_j:
	; arg determines function
	CMP byte [ansi_arg_0], 2
	JE .erase_entire_screen
	JMP send_character.ret_normal

.erase_entire_screen:
	PUSH byte [color_background]
	CALL clear_screen
	ADD SP, 1
	JMP send_character.ret_normal



; subroutine clamp_y
; Clamps cursor y in AL
sub_clamp_y:
	CMP AL, [min_y]
	CMOVB AL, [min_y]
	CMP AL, [max_y]
	CMOVA AL, [max_y]
	RET
	
; subroutine clamp_x
; Clamps cursor x in AH
sub_clamp_x:
	CMP AH, [min_x]
	CMOVB AH, [min_x]
	CMP AH, [max_x]
	CMOVA AH, [max_x]
	RET



; \[[...m
; Graphics attributes
ansi_select_graphic_rendition:
	; what are we doing
	MOV AL, [ansi_arg_0]
	
	CMP AL, 0	; 0 = reset
	JE .reset
	
	CMP AL, 30	; 1-29 not implemented
	JB .ret
	CMP AL, 38
	JB .foreground_table	; 30-37 = 8 color foreground
	JE .foreground_custom	; 38 = 256 color foreground
	
	CMP AL, 40
	JB .foreground_default	; 39 = default foreground
	CMP AL, 48
	JB .background_table	; 40-47 = 8 color background
	JE .background_custom	; 48 = 256 color background
	
	CMP AL, 49
	JE .background_default	; 49 = default background
	JMP .ret				; 50+ = not implemented

.reset:
	; bgc = 0x01
	; fgc = 0xFF
	MOV A, 0x01FF
	MOV [color_background], AH
	MOV [color_foreground], AL
	JMP .ret

.foreground_table:
	SUB AL, 30
	MOVZ A, AL
	MOV AL, [.color_table + A]
	JMP .set_foreground

.foreground_custom:
	; make sure we have a second arg
	CMP byte [current_state], STATE_ANSI_ARG_1
	JB .cret
	MOV AL, [ansi_arg_1]
	JMP .set_foreground

.foreground_default:
	MOV AL, 0xFF

.set_foreground:
	MOV [color_foreground], AL
	JMP .ret

.background_table:
	SUB AL, 40
	MOVZ A, AL
	MOV AL, [.color_table + A]
	JMP .set_background

.background_custom:
	; make sure we have a second arg
	CMP byte [current_state], STATE_ANSI_ARG_1
	JB .cret
	MOV AL, [ansi_arg_1]
	JMP .set_background

.background_default:
	MOV AL, 0x01

.set_background:
	MOV [color_background], AL
	
.ret:
	CALL sub_draw_cursor	; redraw the cursor to reflect new graphics
.cret:
	JMP send_character.ret_normal

.color_table:
	db 0b00_000_001, 0b11_000_000, 0b00_111_000, 0b11_111_000, 0b00_000_111, 0b11_000_111, 0b00_111_111, 0b11_111_111



; subroutine normal_char
; prints the character in AL
sub_normal_char:
	; print to the terminal
	PUSH byte [cursor_x]
	PUSH byte [cursor_y]
	PUSH byte [color_background]
	PUSH byte [color_foreground]
	PUSH AL
	CALL text.a_char
	ADD SP, 5
	
	; update cursor
	MOV AL, [cursor_y]
	MOV AH, [cursor_x]
	INC AH
	CMP AH, [max_x]
	CMOVA AH, [min_x]
	MOV [cursor_x], AH
	JBE .print_cursor
	
	INC AL
	CMP AL, [max_y]
	CMOVA AL, [max_y]
	MOV [cursor_y], AL
	JB .print_cursor
	
	PUSH A
	PUSH byte [color_background]
	PUSH byte 8
	CALL scroll_up
	ADD SP, 2
	POP A
	
.print_cursor:
	; print cursor & return
	JMP sub_draw_cursor_fast



; subroutine clear_cursor
; Prints a space at the current cursor position
sub_clear_cursor:
	CMP byte [draw_cursor], 0
	JNE sub_clear_space
	RET



; subroutine clear_space
; Prints a space at the current cursor position without checking cursor drawing mode
sub_clear_space:
	PUSH byte [cursor_x]
	PUSH byte [cursor_y]
	PUSH byte [color_background]
	PUSH byte [color_foreground]
	PUSH byte ' '
	CALL text.a_char
	ADD SP, 5
	RET



; subroutine draw_cursor
; Prints the cursor character at the cursor position
sub_draw_cursor:
	CMP byte [draw_cursor], 0
	JE .ret
	PUSH byte [cursor_x]
	PUSH byte [cursor_y]
	PUSH byte [color_background]
	PUSH byte [color_foreground]
	PUSH byte [character_cursor]
	CALL text.a_char
	ADD SP, 5
.ret:
	RET



; subroutine draw_cursor_fast
; Prints the cursor character at the position in A
sub_draw_cursor_fast:
	CMP byte [draw_cursor], 0
	JE .ret
	PUSH A
	PUSH byte [color_background]
	PUSH byte [color_foreground]
	PUSH byte [character_cursor]
	CALL text.a_char
	ADD SP, 5
.ret:
	RET



; subroutine scroll_up
; Scrolls up one row
sub_scroll_up:
	PUSH byte [color_background]
	PUSH byte 8
	CALL scroll_up
	ADD SP, 2
	RET



; subroutine scroll_down
; Scrolls down one row
sub_scroll_down:
	PUSH byte [color_background]
	PUSH byte 8
	CALL scroll_down
	ADD SP, 2
	RET



; none scroll_up(u8 n, u8 color)
; Scroll the screen area up by n pixels
scroll_up:
	PUSHW BP
	MOVW BP, SP
	SUB SP, 4
	PUSHW J:I
	PUSHW L:K
	
	; check bounds
	CMP byte [BP + 8], 0	; if n = 0, no work to do
	JZ .do_nothing
	
	MOV AL, [max_y]			; if n >= sceen area height = (max_y - min_y + 1) * 8, clear screen
	SUB AL, [min_y]
	INC AL
	SHL AL, 3
	CMP AL, [BP + 8]
	JA .do_scroll
	
	PUSH byte [BP + 9]
	CALL clear_screen
	ADD SP, 1
	JMP .ret

.do_scroll:
	
	; D:A = data
	; B = line counter
	; C = pixel counter
	; J:I = source
	; L:K = dest
	; [BP - 2] = pixels/line
	; [BP - 4] = newline offset
	
	; start dest address = VBUFFER_START + (min_y * 320 * 8) + (min_x * 8)
	MOVW L:K, VBUFFER_START	; VBUFFER_START	
	MOVZ A, [min_y]			; min_y * 320 * 8
	MULH D:A, 320 * 8
	ADD K, A
	ADC L, D
	
	MOVZ A, [min_x]			; min_x * 8
	SHL A, 3
	ADD K, A
	ICC L
	
	; start source addres = start dest address + (n * 320)
	MOVZ A, [BP + 8]
	MULH D:A, 320
	MOVW J:I, L:K
	ADD I, A
	ADC J, D
	
	; #pixels/line = (max_x - min-x + 1) * 8
	MOV AL, [max_x]
	SUB AL, [min_x]
	INC A
	MULH A, 8
	MOV [BP - 2], A
	
	; newline offset = 320 - pixels/line
	MOV D, 320
	SUB D, A
	MOV [BP - 4], D
	
	; #lines to copy = ((max_y - min-y + 1) * 8) - n
	MOV BL, [max_y]
	SUB BL, [min_y]
	INC BL
	MULH B, 8
	SUB BL, [BP + 8]
	DCC BH
	
	; get going
.line_copy_loop:
	MOV C, [BP - 2]
	
	; copy 4 characters worth
.pixel_copy_loop_32:
	CMP C, 32
	JB .pixel_copy_loop_short
	MOVW D:A, [J:I + 0]
	MOVW [L:K + 0], D:A
	MOVW D:A, [J:I + 4]
	MOVW [L:K + 4], D:A
	MOVW D:A, [J:I + 8]
	MOVW [L:K + 8], D:A
	MOVW D:A, [J:I + 12]
	MOVW [L:K + 12], D:A
	MOVW D:A, [J:I + 16]
	MOVW [L:K + 16], D:A
	MOVW D:A, [J:I + 20]
	MOVW [L:K + 20], D:A
	MOVW D:A, [J:I + 24]
	MOVW [L:K + 24], D:A
	MOVW D:A, [J:I + 28]
	MOVW [L:K + 28], D:A
	
	ADD I, 32
	ICC J
	ADD K, 32
	ICC L
	SUB C, 32
	JNZ .pixel_copy_loop_32
	JMP .line_copy_done

.pixel_copy_loop_short:
	MOVW D:A, [J:I + 0]
	MOVW [L:K + 0], D:A
	MOVW D:A, [J:I + 4]
	MOVW [L:K + 4], D:A
	
	ADD I, 8
	ICC J
	ADD K, 8
	ICC L
	SUB C, 8
	JNZ .pixel_copy_loop_short

	; done with the line
.line_copy_done:
	ADD I, [BP - 4]
	ICC J
	ADD K, [BP - 4]
	ICC L
	DEC B
	JNZ .line_copy_loop
	
	; clear remaining n lines
	MOVZ B, [BP + 8]
	MOV AL, [BP + 9]
	MOV AH, AL
	MOV D, A
	MOVW J:I, [BP - 4]

.line_clear_loop:
	MOV C, J
	
	; clear 4 characters worth
.pixel_clear_loop_32:
	CMP C, 32
	JB .pixel_clear_loop_short
	MOVW [L:K + 0], D:A
	MOVW [L:K + 4], D:A
	MOVW [L:K + 8], D:A
	MOVW [L:K + 12], D:A
	MOVW [L:K + 16], D:A
	MOVW [L:K + 20], D:A
	MOVW [L:K + 24], D:A
	MOVW [L:K + 28], D:A
	
	ADD K, 32
	ICC L
	SUB C, 32
	JNZ .pixel_clear_loop_32
	JMP .line_clear_done

.pixel_clear_loop_short:
	MOVW [L:K + 0], D:A
	MOVW [L:K + 4], D:A
	
	ADD K, 8
	ICC L
	SUB C, 8
	JNZ .pixel_clear_loop_short

	; done with the line
.line_clear_done:
	ADD K, I
	ICC L
	DEC B
	JNZ .line_clear_loop
	
.do_nothing:
.ret:
	POPW L:K
	POPW J:I
	ADD SP, 4
	POPW BP
	RET



; none scroll_down(u8 n, u8 color)
; Scroll the screen area down by n pixels
scroll_down:
	PUSHW BP
	MOVW BP, SP
	
	POPW BP
	RET



; none clear_screen(u8 color)
; Fills the screen area with color
clear_screen:
	PUSHW BP
	MOVW BP, SP
	PUSHW J:I
	PUSHW L:K
	
	; D:A = data
	; J:I = address
	; B = line counter
	; C = pixel counter
	; K = newline offset
	; L = pixels/line
	
	; start address = VBUFFER_START + (min_y * 320 * 8) + (min_x * 8)
	MOVW J:I, VBUFFER_START
	MOVZ A, [min_y]
	MULH D:A, (320 * 8)
	ADD I, A
	ADC J, D
	MOVZ A, [min_x]
	MULH D:A, 8
	ADD I, A
	ADC J, D
	
	; #pixels/line = (max_x - min-x + 1) * 8
	MOV AL, [max_x]
	SUB AL, [min_x]
	INC A
	MULH A, 8
	MOV L, A
	
	; newline offset = 320 - pixels/line
	MOV K, 320
	SUB K, L
	
	; #lines to clear = (max_y - min-y + 1) * 8
	MOV BL, [max_y]
	SUB BL, [min_y]
	INC BL
	MULH B, 8
	
	; data = all color
	MOV AL, [BP + 8]
	MOV AH, AL
	MOV D, A
	
	; get going
.line_loop:
	MOV C, L

	; clear 4 characters worth
.pixel_loop_32:
	CMP C, 32
	JB .pixel_loop_short
	MOVW [J:I + 0], D:A
	MOVW [J:I + 4], D:A
	MOVW [J:I + 8], D:A
	MOVW [J:I + 12], D:A
	MOVW [J:I + 16], D:A
	MOVW [J:I + 20], D:A
	MOVW [J:I + 24], D:A
	MOVW [J:I + 28], D:A
	
	ADD I, 32
	ICC J
	SUB C, 32
	JNZ .pixel_loop_32
	JMP .line_done
	
	; clear 1 character worth
.pixel_loop_short:
	MOVW [J:I + 0], D:A
	MOVW [J:I + 4], D:A
	
	ADD I, 8
	ICC J
	SUB C, 8
	JNZ .pixel_loop_short
	
	; done with the line
.line_done:
	LEA J:I, [J:I + K]	; next line
	DEC B
	JNZ .line_loop
	
	POPW L:K
	POPW J:I
	POPW BP
	RET
