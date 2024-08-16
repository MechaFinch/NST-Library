
;
; FakeOS Terminal
; Uses text drawing to do terminal things
; 

%include "simvideo/gutil.asm" as gutil
%include "simvideo/text.asm" as text

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
cursor_x:			db 0
cursor_y:			db 0
color_foreground:	db 0xFF
color_background:	db 0x01
character_cursor:	db '_'



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
	
	MOVW D:A, 0
	MOV [cursor_x], AL
	MOV [cursor_y], AL
	
	; reset palette
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
	CALL gutil.clear_screen
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
	CMP BL, 0
	CMOVE AH, TERMINAL_WIDTH - 1
	MOV [cursor_x], AH
	JNE .backspace_cursor
	
	MOV BL, AL
	DEC AL
	CMP BL, 0
	CMOVE AL, BL
	MOV [cursor_y], AL

.backspace_cursor:
	CALL sub_draw_cursor_fast
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
	MOV AL, [cursor_y]
	INC AL
	CMP AL, TERMINAL_HEIGHT
	CMOVB [cursor_y], AL
	JB .newline_no_scroll
	
	PUSH A
	CALL sub_scroll_up
	POP A

.newline_no_scroll:
	MOV AH, 0
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
	CALL sub_clamp_x
	CALL sub_clamp_y

	; erase cursor, move cursor, draw cursor
.move_cursor:
	PUSH A
	CALL sub_clear_cursor
	POP A
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
	CALL gutil.clear_screen
	ADD SP, 1
	JMP send_character.ret_normal



; subroutine clamp_y
; Clamps cursor y in AL
sub_clamp_y:
	CMP AL, 0
	CMOVL AL, 0
	CMP AL, TERMINAL_HEIGHT - 1
	CMOVG AL, TERMINAL_HEIGHT - 1
	RET
	
; subroutine clamp_x
; Clamps cursor x in AH
sub_clamp_x:
	CMP AH, 0
	CMOVL AH, 0
	CMP AH, TERMINAL_WIDTH - 1
	CMOVG AH, TERMINAL_WIDTH - 1
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
	CMP AH, TERMINAL_WIDTH
	CMOVNB AH, 0
	MOV [cursor_x], AH
	JB .print_cursor
	
	INC AL
	CMP AL, TERMINAL_HEIGHT
	CMOVB [cursor_y], AL
	JB .print_cursor
	
	PUSH A
	PUSH byte [color_background]
	PUSH byte 8
	CALL gutil.scroll_up
	ADD SP, 2
	POP A
	
.print_cursor:
	; print cursor & return
	JMP sub_draw_cursor_fast



; subroutine clear_cursor
; Prints a space at the current cursor position
sub_clear_cursor:
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
	PUSH byte [cursor_x]
	PUSH byte [cursor_y]
	PUSH byte [color_background]
	PUSH byte [color_foreground]
	PUSH byte [character_cursor]
	CALL text.a_char
	ADD SP, 5
	RET



; subroutine draw_cursor_fast
; Prints the cursor character at the position in A
sub_draw_cursor_fast:
	PUSH A
	PUSH byte [color_background]
	PUSH byte [color_foreground]
	PUSH byte [character_cursor]
	CALL text.a_char
	ADD SP, 5
	RET



; subroutine scroll_up
; Scrolls up one row
sub_scroll_up:
	PUSH byte [color_background]
	PUSH byte 8
	CALL gutil.scroll_up
	ADD SP, 2
	RET



; subroutine scroll_down
; Scrolls down one row
sub_scroll_down:
	PUSH byte [color_background]
	PUSH byte 8
	CALL gutil.scroll_down
	ADD SP, 2
	RET
