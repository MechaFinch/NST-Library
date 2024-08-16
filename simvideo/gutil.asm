
;
; STANDARD LIBRARY - SIMVIDEO
; GRAPHICS UTILITIES
; ASM IMPLEMENTATION
;

%libname gutil

%define VBUFFER_START 0xF002_0000
%define PALETTE_START (VBUFFER_START + (320 * 240))

; none set_palette(u8* palette)
; copies the palette
set_palette:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH L
	PUSH K
	
	MOVW L:K, PALETTE_START
	MOVW B:C, [BP + 8]
	MOV I, (256 * 3) / 16
	
.loop:
	MOVW D:A, [B:C + 0]
	MOVW [L:K + 0], D:A
	MOVW D:A, [B:C + 4]
	MOVW [L:K + 4], D:A
	MOVW D:A, [B:C + 8]
	MOVW [L:K + 8], D:A
	MOVW D:A, [B:C + 12]
	MOVW [L:K + 12], D:A
	
	ADD K, 16
	ICC L
	ADD C, 16
	ICC B
	DEC I
	JNZ .loop

	POP K
	POP L
	POP I
	POP BP
	RET



; none set_color(u8 index, color24 color)
; sets a single color
set_color:
set_color_bytes:
	PUSH BP
	MOVW BP, SP
	
	MOVW D:A, [BP + 9]
	MOVZ B, [BP + 8]
	MUL B, 3
	MOV [PALETTE_START + B + 0], A
	MOV [PALETTE_START + B + 2], DL
	
	POP BP
	RET



; clear_screen(u8 bgc): none
; clears the screen with the given color
clear_screen:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	
	; D:A = data
	; B:C = counter
	; J:I = addr
	MOV AL, [BP + 8]
	MOV AH, AL
	MOV D, A
	
	MOVW B:C, 320 * 240
	MOVW J:I, VBUFFER_START

.loop:
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
	DCC B
	
	JNZ .loop
	CMP C, 0
	JNZ .loop
	
	POP J
	POP I
	
	POP BP
	RET
	


; scroll_up(u8 n, u8 bgc): none
; scrolls the screen down by n pixels
scroll_up:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	PUSH K
	PUSH L
	
	; Copy data with offset (n * -320)
	; Start at VBUFFER_START + |offset| (offset always negative)
	; Copy (320 * (240 - n)) bytes
	; Clear abs(offset) more bytes
	
	; D:A = offset, data
	; B:C = counter
	; J:I = source
	; L:K = dest
	
	; compute offset to D:A
	MOVZ A, [BP + 8]
	MOV B, A
	MULSH D:A, -320
	
	; compute start
	; source = VBUFFER_START + |offset|
	; dest = VBUFFER_START
	MOVW J:I, VBUFFER_START
	MOVW L:K, J:I
	SUB I, A
	SBB J, D
	
	; compute copy counter to B:C
	MOV C, 240
	SUB C, B
	MULH B:C, 320
	
	; don't copy if the screen is being cleared
	CMP byte [BP + 8], byte 240
	JAE .clear
	
	; copy
.copyloop:
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
	DCC B
	JNZ .copyloop
	CMP C, 0
	JNZ .copyloop
	
	; clear
.clear:
	; recover offset from J:I
	SUB I, K
	SBB J, L
	
	; get bgc
	MOV AL, [BP + 9]
	MOV AH, AL
	MOV D, A
	
.clearloop:
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
	
	SUB I, 32
	DCC J
	JNZ .clearloop
	CMP I, 0
	JNZ .clearloop
	
	POP L
	POP K
	POP J
	POP I
	
	POP BP
	RET



; scroll_down(u8 n, u8 bgc): none
; scrolls the screen up by n pixels
scroll_down:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	PUSH K
	PUSH L
	
	; Copy data with offset (n * 320)
	; Start at VBUFFER_START + (320 * 240) - copysize - offset
	; Copy (320 * (240 - n)) bytes
	; Clear offset more bytes starting from offset
	
	; D:A = offset, data
	; B:C = counter
	; J:I = source
	; L:K = dest
	
	; compute offset to D:A
	MOVZ A, [BP + 8]
	MOV B, A
	MULH D:A, 320
	
	; compute start
	; source = VBUFFER_START + (320 * 240) - copysize - offset
	; dest = VBUFFER_START + (320 * 240) - copysize
	MOVW J:I, VBUFFER_START + (320 * 240) - 32
	MOVW L:K, J:I
	SUB I, A
	SBB J, D
	
	; compute copy counter to B:C
	MOV C, 240
	SUB C, B
	MULH B:C, 320
	
	; don't copy if the screen is being cleared
	CMP byte [BP + 8], byte 240
	JAE .clear
	
	; copy
.copyloop:
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
	
	SUB I, 32
	DCC J
	SUB K, 32
	DCC L
	
	SUB C, 32
	DCC B
	JNZ .copyloop
	CMP C, 0
	JNZ .copyloop
	
	; clear
.clear:
	; recover offset from L:K & J:I
	MOVW D:A, L:K
	SUB K, I
	SBB L, J
	MOVW J:I, D:A
	
	; get bgc
	MOV AL, [BP + 9]
	MOV AH, AL
	MOV D, A

.clearloop:
	MOVW [J:I + 0], D:A
	MOVW [J:I + 4], D:A
	MOVW [J:I + 8], D:A
	MOVW [J:I + 12], D:A
	MOVW [J:I + 16], D:A
	MOVW [J:I + 20], D:A
	MOVW [J:I + 24], D:A
	MOVW [J:I + 28], D:A
	
	SUB I, 32
	DCC J
	
	SUB K, 32
	DCC L
	JNZ .clearloop
	CMP K, 0
	JNZ .clearloop
	
	POP L
	POP K
	POP J
	POP I
	
	POP BP
	RET
