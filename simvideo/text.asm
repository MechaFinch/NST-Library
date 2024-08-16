
;
; STANDARD LIBRARY - SIM VIDEO
; TEXT
; ASSEMBLY IMPLEMENTATION
;

%libname text

%define VBUFFER_START 0xF002_0000
%define CHARSET_START 0xF003_4000

%define CHARSIZE 8

%define ROWS_PIXELS 240
%define ROWS_CHARS (ROWS_PIXELS / CHARSIZE)
%define COLS_PIXELS 320
%define COLS_CHARS (COLS_PIXELS / CHARSIZE)

; none a_char(u8 chr, u8 fgc, u8 bgc, u8 row, u8 col)
; draws a grid-aligned character to the given position
a_char:
	PUSH BP
	MOV BP, SP
	
	; check bounds
	CMP byte [BP + 11], 0
	JL .fret
	CMP byte [BP + 12], 0
	JL .fret
	CMP byte [BP + 11], ROWS_CHARS
	JGE .fret
	CMP byte [BP + 12], COLS_CHARS
	JGE .fret
	
	PUSH I
	PUSH J
	PUSH K
	PUSH L
	
	; compute character pointer to A:B
	MOVZ B, [BP + 8]
	SHL B, 3
	LEA A:B, [CHARSET_START + B]
	
	; compute color data to C:D
	MOV C, [BP + 9]
	MOV DL, CH
	MOV DH, DL
	MOV CH, CL
	;PSUB8 C, D
	
	; compute screen pointer to BP
	MOVZ I, [BP + 11] ; row
	MOVZ K, [BP + 12] ; col
	MULH J:I, COLS_PIXELS * CHARSIZE
	SHL K, 3
	LEA BP, [J:I + K + VBUFFER_START]
	
	; get character data
	MOVW J:I, [A:B + 0]
	MOVW L:K, [A:B + 4]
	
	; draw character
	CALL sub_char
	
	POP L
	POP K
	POP J
	POP I
.fret:
	POP BP
	RET

; none a_string(u8* str, u16 len, u8 fgc, u8 bgc, u8 row, u8 col)
; draws a string to the gievn position
a_string:
	PUSH BP
	MOV BP, SP
	PUSH I
	PUSH J
	PUSH K
	PUSH L
	
	; compute color data to C:D
	MOV C, [BP + 14]
	MOV DL, CH
	MOV DH, DL
	MOV CH, CL
	;PSUB8 C, D
	
	; put counter & pointer on the stack
	PUSH word [BP + 12]
	PUSH word [BP + 12]
	PUSH word [BP + 10]
	PUSH word [BP + 8]
	
	; compute screen pointer to BP
	MOVZ I, [BP + 16] ; row
	MOVZ K, [BP + 17] ; col
	MULH J:I, COLS_PIXELS * CHARSIZE
	SHL K, 3
	LEA BP, [J:I + K + VBUFFER_START]
	
.loop:
	; get character data
	MOVW A:B, [SP]
	LEA J:I, [A:B + 1]
	MOVW [SP], J:I
	
	MOVZ A, [A:B]
	
	; is it a newline
	CMP A, 0x0A
	JNE .not_newline
	
.newline:
	MOV A, [SP + 6] ; line length - remaining = printed
	SUB A, [SP + 4]
	SUB [SP + 6], A ; line length - printed - 1 = new remaining
	DEC word [SP + 6]
	SHL A, 3
	NEG A
	LEA BP, [BP + A + (COLS_PIXELS*CHARSIZE)]
	JMP .next
	
.not_newline:
	SHL A, 3
	MOVW J:I, [CHARSET_START + A + 0]
	MOVW L:K, [CHARSET_START + A + 4]
	
	; draw character
	CALL sub_char
	
	LEA BP, [BP + 8]
.next:
	DEC word [SP + 4]
	JNZ .loop
	
	ADD SP, 8
	
	POP L
	POP K
	POP J
	POP I
	POP BP
	RET



; none a_number(u32 n, u8 base, boolean signed, u8 pad_length, u8 digit_pad, u8 sign_pad, u8 fgc, u8 bgc, u8 row, u8 col)
a_number:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	PUSH K
	PUSH L
	
	; make sure base is positive
	CMP byte [BP + 12], 0
	JLE .ret
	
	; D:A = n
	MOVW D:A, [BP + 8]
	
	; if signed, make positive and include +/-/pad
	
	; handle zero
	
	; if not zero, push digit and divide
	
	; print padding
	
	; print digits
	
.ret:
	POP L
	POP K
	POP J
	POP I
	POP BP
	RET


	
; subroutine char
; draws a char
; INPUT
; B		n/a (clobbered)
; C		foreground in both CH and CL
; D		background in both DH and DL
; IJKL	character data (clobbered)
; BP	screen pointer
sub_char:
	MOV B, 0

	; is background transparent
	CMP D, 0
	JZ .start_tbg
	
	; is foreground transparent
	CMP C, 0
	JZ .loop_tfg

	; no transparency
.loop_nt:
	PCMP8 I, 0
	PCMOV8S [BP + B + 0], C
	PCMOV8NS [BP + B + 0], D
	SHL I, 1
	
	PCMP8 J, 0
	PCMOV8S [BP + B + 2], C
	PCMOV8NS [BP + B + 2], D
	SHL J, 1
	
	PCMP8 K, 0
	PCMOV8S [BP + B + 4], C
	PCMOV8NS [BP + B + 4], D
	SHL K, 1
	
	PCMP8 L, 0
	PCMOV8S [BP + B + 6], C
	PCMOV8NS [BP + B + 6], D
	SHL L, 1
	
	ADD B, COLS_PIXELS
	CMP B, (COLS_PIXELS * 8)
	JNE .loop_nt
	RET
	
	; transparent background
.start_tbg:
	CMP C, 0
	JZ .no_draw
	
.loop_tbg:
	PCMP8 I, 0
	PCMOV8S [BP + B + 0], C
	SHL I, 1
	
	PCMP8 J, 0
	PCMOV8S [BP + B + 2], C
	SHL J, 1
	
	PCMP8 K, 0
	PCMOV8S [BP + B + 4], C
	SHL K, 1
	
	PCMP8 L, 0
	PCMOV8S [BP + B + 6], C
	SHL L, 1
	
	ADD B, COLS_PIXELS
	CMP B, (COLS_PIXELS * 8)
	JNE .loop_tbg
.no_draw:
	RET
	
	; transparent foreground
.loop_tfg:
	PCMP8 I, 0
	PCMOV8NS [BP + B + 0], D
	SHL I, 1
	
	PCMP8 J, 0
	PCMOV8NS [BP + B + 2], D
	SHL J, 1
	
	PCMP8 K, 0
	PCMOV8NS [BP + B + 4], D
	SHL K, 1
	
	PCMP8 L, 0
	PCMOV8NS [BP + B + 6], D
	SHL L, 1
	
	ADD B, COLS_PIXELS
	CMP B, (COLS_PIXELS * 8)
	JNE .loop_tfg
	RET