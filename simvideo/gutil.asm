
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
	
	MOVW D:A, PALETTE_START
	MOVW B:C, [BP + 8]
	MOV I, (256 * 3) / 16

.loop:
	STIW D:A, [B:C + 0]
	STIW D:A, [B:C + 4]
	STIW D:A, [B:C + 8]
	STIW D:A, [B:C + 12]
	
	ADDW B:C, 16
	DEC I
	JNZ .loop
	
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
	
	PUSHW J:I
	
	; D:A = data
	; B:C = counter
	; J:I = addr
	MOV AL, [BP + 8]
	MOV AH, AL
	MOV D, A
	
	MOVW B:C, 320 * 240
	MOVW J:I, VBUFFER_START

.loop:
	STIW J:I, D:A
	STIW J:I, D:A
	STIW J:I, D:A
	STIW J:I, D:A
	STIW J:I, D:A
	STIW J:I, D:A
	STIW J:I, D:A
	STIW J:I, D:A
	
	SUBW B:C, 32	
	JNZ .loop
	
	POPW J:I	
	POP BP
	RET
	


; scroll_up(u8 n, u8 bgc): none
; scrolls the screen down by n pixels
scroll_up:
	PUSH BP
	MOVW BP, SP
	
	PUSHW J:I
	PUSHW L:K
	
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
	SUBW J:I, D:A
	
	; compute copy counter to B:C
	MOV C, 240
	SUB C, B
	MULH B:C, 320
	
	; don't copy if the screen is being cleared
	CMP byte [BP + 8], byte 240
	JAE .clear
	
	; copy
.copyloop:
	STIW L:K, [J:I + 0]
	STIW L:K, [J:I + 4]
	STIW L:K, [J:I + 8]
	STIW L:K, [J:I + 12]
	STIW L:K, [J:I + 16]
	STIW L:K, [J:I + 20]
	STIW L:K, [J:I + 24]
	STIW L:K, [J:I + 28]
	
	ADDW J:I, 32
	SUBW B:C, 32
	JNZ .copyloop
	
	; clear
.clear:
	; recover offset from J:I
	SUBW J:I, L:K
	
	; get bgc
	MOV AL, [BP + 9]
	MOV AH, AL
	MOV D, A
	
.clearloop:
	STIW L:K, D:A
	STIW L:K, D:A
	STIW L:K, D:A
	STIW L:K, D:A
	STIW L:K, D:A
	STIW L:K, D:A
	STIW L:K, D:A
	STIW L:K, D:A
	
	SUBW J:I, 32
	JNZ .clearloop
	
	POPW L:K
	POPW J:I
	
	POP BP
	RET



; scroll_down(u8 n, u8 bgc): none
; scrolls the screen up by n pixels
scroll_down:
	PUSH BP
	MOVW BP, SP
	
	PUSHW J:I
	PUSHW L:K
	
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
	SUBW J:I, D:A
	
	; compute copy counter to B:C
	MOV C, 240
	SUB C, B
	MULH B:C, 320
	
	; don't copy if the screen is being cleared
	CMP byte [BP + 8], byte 240
	JAE .clear
	
	; copy
	ADDW L:K, 32 + 4	; + worsize instead of - copysize; setup for DSTW
.copyloop:
	DSTW L:K, [J:I + 28]
	DSTW L:K, [J:I + 24]
	DSTW L:K, [J:I + 20]
	DSTW L:K, [J:I + 16]
	DSTW L:K, [J:I + 12]
	DSTW L:K, [J:I + 8]
	DSTW L:K, [J:I + 4]
	DSTW L:K, [J:I + 0]
	
	SUBW J:I, 32
	SUBW B:C, 32
	JNZ .copyloop
	
	; clear
.clear:
	; recover offset from L:K & J:I
	SUBW L:K, 32 + 4
	MOVW D:A, L:K
	SUBW L:K, J:I
	MOVW J:I, D:A
	
	; get bgc
	MOV AL, [BP + 9]
	MOV AH, AL
	MOV D, A

	ADDW J:I, 32 + 4	; setup for DSTW
.clearloop:
	DSTW J:I, D:A
	DSTW J:I, D:A
	DSTW J:I, D:A
	DSTW J:I, D:A
	DSTW J:I, D:A
	DSTW J:I, D:A
	DSTW J:I, D:A
	DSTW J:I, D:A
	
	SUBW L:K, 32
	JNZ .clearloop
	
	POPW L:K
	POPW J:I
	POP BP
	RET
