
; 
; STANDARD LIBRARY - SIM VIDEO
; SHAPES
; ASM IMPLEMENTATION
;

%libname shapes

%define VBUFFER_START 0xF002_0000

%define ROWS_PIXELS 240
%define COLS_PIXELS 320

; none pixel(i16 x, i16 y, u8 fgc)
; plots a pixel at the given coordinates
pixel:
	PUSH BP
	MOV BP, SP
	
	MOVW D:A, VBUFFER_START
	MOV C, [BP + 10] ; y * width
	MULSH B:C, COLS_PIXELS
	ADDW D:A, B:C
	ADD A, [BP + 8]
	ICC D
	
	STI D:A, byte [BP + 12]
	
	POP BP
	RET

; none freeline(i16 x1, i16 y1, i16 x2, i16 y2, u8 fgc)
; draws a freeform line from (x1, y1) to (x2, y2) in the fgc
freeline:
	PUSH BP
	MOV BP, SP
	
	PUSHW J:I
	PUSHW L:K
	
	; A = y1
	; B = y2
	; C = x2
	; D = x1
	MOVW D:A, [BP + 8]
	XCHG D, A
	MOVW B:C, [BP + 12]
	
	; determine what subroutine to call and how
	; absolute value
	; A = abs(y2 - y1)
	; B = y2 - y1
	; C = x2 - x1
	; D = abs(x2 - x1)
	SUB B, A
	MOV A, B
	NEG A
	CMOVS A, B
	
	SUB C, D
	MOV D, C
	NEG D
	CMOVS D, C
	
	CMP A, D
	JGE .quadhigh
	
	; low half. x1 > x2 if (x2 - x1) sign set
	; bresenham's: shallow slope
	; A = yi
	; B = dy
	; C = dx 2*(dy - dx)
	; D = D
	; J:I = pointer, tmp y
	; K = counter (abs(x2 - x1))
	; L = tmp x, y increment in buffer
	MOV K, D
	CMP C, 0 ; if sign set, x1 > x2 -> swap points
	JNS .low_no_rev
	
	NEG B ; -dy
	NEG C ; -dx
	MOV I, [BP + 14] ; y2
	MOV L, [BP + 12] ; x2
	JMP .draw_low

.low_no_rev:
	MOV I, [BP + 10] ; y1
	MOV L, [BP + 8]	 ; x1

.draw_low:
	; yi = 1 if dy pos else -1
	; dy = abs(dy)
	XCHG A, B
	SAR A, 15
	OR A, 1
	
	; D = 2dy - dx
	MOV D, B
	SHL D, 1
	SUB D, C
	
	; J:I = start pos
	MULH J:I, COLS_PIXELS
	ADD I, L
	ADC J, (VBUFFER_START / 0x1_0000)
	
	; AL = color
	; L = yi
	MOV L, A
	MOV AL, [BP + 16]
	
	; C = 2 * (dy - dx)
	NEG C
	ADD C, B
	SHL C, 1
	
	; B = 2 * dy
	SHL B, 1
	
	; loop by counter
.low_loop:
	; place pixel
	STI J:I, AL
	
	CMP D, 0
	JLE .no_y_change
	
	CMP L, 0
	JS .yi_neg
	
	ADDW J:I, COLS_PIXELS	; y += yi
	JMP .yi_pos
	
.yi_neg:
	SUBW J:I, COLS_PIXELS
	
.yi_pos:
	ADD D, C ; D += 2 * (dy - dx)
	
	DEC K
	JNS .low_loop
	JMP .done
	
.no_y_change:
	ADD D, B ; D += 2 * dy

	DEC K
	JNS .low_loop
	JMP .done

	; high half, y1 > y2 if sign set
	; bresenhams: steep slope
	; A = xi
	; B = dy (dx - dy)
	; C = dx
	; D = D
	; J:I = pointer, tmp y
	; K = counter
	; L = tmp x
.quadhigh:
	MOV K, A ; counter = abs(y2 - y1)
	CMP B, 0
	JNS .high_no_rev
	
	NEG B ; -dy
	NEG C ; -dx
	MOV I, [BP + 14] ; y2
	MOV L, [BP + 12] ; x2
	JMP .draw_high

.high_no_rev:
	MOV I, [BP + 10] ; y1
	MOV L, [BP + 8]  ; x1
	
.draw_high:
	; xi = 1 if dx pos else -1
	; dx = abs(dx)
	CMP C, 0
	CMOVNS A, 1
	CMOVS A, -1
	MOV C, D
	
	; D = 2dx - dy
	SHL D, 1
	SUB D, B
	
	; J:I = start pos
	MULH J:I, COLS_PIXELS
	ADD I, L
	ADC J, (VBUFFER_START / 0x1_0000)
	
	; AL = color
	; L = xi
	MOV L, A
	MOV AL, [BP + 16]
	
	; B = 2 * (dx - dy)
	NEG B
	ADD B, C
	SHL B, 1
	
	; C = 2 * dx
	SHL C, 1
	
	; loop by counter
.high_loop:
	; place pixel
	MOV [J:I], AL
	ADDW J:I, COLS_PIXELS
	
	CMP D, 0
	JLE .no_x_change
	
	CMP L, 0
	JS .xi_neg
	
	INCW J:I
	JMP .xi_pos
	
.xi_neg:
	DECW J:I
	
.xi_pos:
	ADD D, B
	DEC K
	JNS .high_loop
	JMP .done

.no_x_change:
	ADD D, C
	DEC K
	JNS .high_loop
	
.done:
	POPW L:K
	POPW J:I
	POP BP
	RET

; none hlineus(i16 x1, i16 y1, i16 x2, u8 fgc)
; draws a horizontal line from (x1, y1) to (x2, y1) in the fgc without bounds checks
hlineus:
	PUSH BP
	MOV BP, SP
	
	PUSHW J:I
	PUSH K
	
	MOVW D:A, [BP + 8]
	MOV B, [BP + 12]
	JMP hline.ready

; none hline(i16 x1, i16 y1, i16 x2, u8 fgc)
; draws a horizontal line from (x1, y1) to (x2, y1) in the fgc
hline:
	; check/clip such that things are on screen
	PUSH BP
	MOV BP, SP
	
	PUSHW J:I
	PUSH K
	
	; D = y1
	; A = x1
	MOVW D:A, [BP + 8] 
	CMP D, ROWS_PIXELS
	JGE .done
	CMP D, 0
	JL .done

	; B = x2
	MOV B, [BP + 12]
	CMP A, COLS_PIXELS
	JGE .x1_oob
	CMP A, 0
	JL .x1_oob
	
	; x1 in bounds. if x2 oob, clip
	CMP B, COLS_PIXELS
	JGE .x2_oob
	CMP B, 0
	JL .x2_oob
	
	; both in bounds
	JMP .none_oob
	
	; x1 oob. if x2 oob, draw nothing, otherwise clip x1
.x1_oob:
	CMP B, COLS_PIXELS
	JGE .done
	CMP B, 0
	JL .done
	
	; clip - x1 is either right (> COLS_PIXELS) or left (< zero) of the screen
	CMP A, 0
	CMOVG A, COLS_PIXELS - 1
	CMOVL A, 0
	JMP .none_oob
	
.x2_oob:
	CMP B, 0
	CMOVG B, COLS_PIXELS - 1
	CMOVL B, 0
	
	; make sure x1<x2
.none_oob:
	CMP A, B
	JL .ready
	XCHG A, B

	; good to go
	; D = y1
	; A = x1
	; B = x2
.ready:
	; B = x2 - x1
	SUB B, A
	
	; D:A = start address
	MOV C, A
	MOV A, COLS_PIXELS
	MULH D:A, D
	ADD A, C
	ADC D, (VBUFFER_START / 0x1_0000)
	
	; J:I = FGC in all bytes
	MOV CL, [BP + 14]
	MOV CH, CL
	MOV I, C
	MOV J, C
	
	MOV K, B
	INC K
	CMP K, 16
	JL .last

.fast_loop:
	STIW D:A, J:I
	STIW D:A, J:I
	STIW D:A, J:I
	STIW D:A, J:I
	
	SUB K, 16
	CMP K, 16
	JGE .fast_loop

.last:
	JMP byte [IP + K]
	db @.d0
	db @.d1
	db @.d2
	db @.d3
	db @.d4
	db @.d5
	db @.d6
	db @.d7
	db @.d8
	db @.d9
	db @.dA
	db @.dB
	db @.dC
	db @.dD
	db @.dE
	db @.dF

.dC:
	STIW D:A, J:I
.d8:
	STIW D:A, J:I
.d4:
	STIW D:A, J:I
	JMP .done

.dD:
	STIW D:A, J:I
.d9:
	STIW D:A, J:I
.d5:
	STIW D:A, J:I
	STI D:A, CL
	JMP .done

.dE:
	STIW D:A, J:I
.dA:
	STIW D:A, J:I
.d6:
	STIW D:A, J:I
.d2:
	STI D:A, C
	JMP .done

.dF:
	STIW D:A, J:I
.dB:
	STIW D:A, J:I
.d7:
	STIW D:A, J:I
.d3:
	STI D:A, C
.d1:
	STI D:A, CL
	
.d0:
.done:
	POP K
	POPW J:I
	POP BP
	RET

; none vlineus((i16 x1, i16 y1, i16 y2, u8 fgc)
; draws a vertical line from (x1, y1) to (x1, y2) in the fgc without bounds checks
vlineus:
	PUSH BP
	MOV BP, SP
	
	PUSH K
	
	MOVW D:A, [BP + 8]
	MOV B, [BP + 12]
	JMP vline.ready

; none vline(i16 x1, i16 y1, i16 y2, u8 fgc)
; draws a vertical line from (x1, y1) to (x1, y2) in the fgc
vline:
	PUSH BP
	MOV BP, SP
	
	PUSH K
	
	; check/clip such that things are on screen
	; D = y1
	; A = x1
	; B = y2
	MOVW D:A, [BP + 8]
	CMP A, COLS_PIXELS
	JGE .done
	CMP A, 0
	JL .done
	
	MOV B, [BP + 12]
	CMP D, ROWS_PIXELS
	JGE .y1_oob
	CMP D, 0
	JL .y1_oob
	
	; y1 in bounds. if y2 oob, clip
	CMP B, ROWS_PIXELS
	JGE .y2_oob
	CMP B, 0
	JL .y2_oob
	
	; both in bounds
	JMP .none_oob

	; y1 oob. if y2 oob, draw nothing, otherwise clip y1
.y1_oob:
	CMP B, ROWS_PIXELS
	JGE .done
	CMP B, 0
	JL .done
	
	; clip y1
	CMP D, 0
	CMOVG D, ROWS_PIXELS - 1
	CMOVL D, 0
	JMP .none_oob

.y2_oob:
	CMP B, 0
	CMOVG B, ROWS_PIXELS - 1
	CMOVL B, 0

	; ensure y1 < y2
.none_oob:
	CMP D, B
	JL .ready
	XCHG D, B

	; good to go
.ready:
	; B = y2 - y1
	; D:A = start address
	; CL = fgc
	SUB B, D
	
	MOV C, A
	MOV A, COLS_PIXELS
	MULH D:A, D
	ADD A, C
	ADC D, (VBUFFER_START / 0x1_0000)
	
	MOV CL, [BP + 14]
	
	MOV K, B
	INC K
	CMP K, 8
	JL .last
	
.fast_loop:
	MOV [D:A + 0 * COLS_PIXELS], CL
	MOV [D:A + 1 * COLS_PIXELS], CL
	MOV [D:A + 2 * COLS_PIXELS], CL
	MOV [D:A + 3 * COLS_PIXELS], CL
	MOV [D:A + 4 * COLS_PIXELS], CL
	MOV [D:A + 5 * COLS_PIXELS], CL
	MOV [D:A + 6 * COLS_PIXELS], CL
	MOV [D:A + 7 * COLS_PIXELS], CL
	
	ADDW D:A, 8 * COLS_PIXELS
	SUB K, 8
	CMP K, 8
	JGE .fast_loop

.last:
	JMP byte [IP + K]
	db @.d0
	db @.d1
	db @.d2
	db @.d3
	db @.d4
	db @.d5
	db @.d6
	db @.d7

.d7:
	MOV [D:A + 6 * COLS_PIXELS], CL
.d6:
	MOV [D:A + 5 * COLS_PIXELS], CL
.d5:
	MOV [D:A + 4 * COLS_PIXELS], CL
.d4:
	MOV [D:A + 3 * COLS_PIXELS], CL
.d3:
	MOV [D:A + 2 * COLS_PIXELS], CL
.d2:
	MOV [D:A + 1 * COLS_PIXELS], CL
.d1:
	MOV [D:A + 0 * COLS_PIXELS], CL
.d0:
.done:
	POP K
	POP BP
	RET

; none outline_rect(i16 x1, i16 y1, i16 w, i16 h, u8 fgc)
; draws the outline of a rectangle in the fgc
; top left at (x1, y1)
outline_rect:
	PUSH BP
	MOV BP, SP
	
	PUSHW J:I
	PUSHW L:K
	
	; check and clip bounds
	; I = x1
	; J = y1
	; K = w, x2
	; L = h, y2
	MOVW J:I, [BP + 8]
	MOVW L:K, [BP + 12]
	
	ADD K, I
	ADD L, J
	DEC K
	DEC L
	
	; if x2 < 0 or x1 > width, definitely off screen
	CMP K, 0
	JL .done
	CMP I, COLS_PIXELS
	JGE .done
	
	; same with y and height
	CMP L, 0
	JL .done
	CMP J, ROWS_PIXELS
	JGE .done
	
	; clip to bounds
	CMP I, 0
	CMOVL I, 0
	
	CMP J, 0
	CMOVL J, 0
	
	CMP K, COLS_PIXELS - 1
	CMOVG K, COLS_PIXELS - 1
	
	CMP L, ROWS_PIXELS - 1
	CMOVG L, ROWS_PIXELS - 1
	
	; hline top
	PUSH byte [BP + 16]
	PUSH K
	PUSHW J:I
	CALL hlineus
	
	; hline bottom
	PUSH byte [BP + 16]
	PUSH K
	PUSH L
	PUSH I
	CALL hlineus
	
	; vline left
	PUSH byte [BP + 16]
	PUSH L
	PUSHW J:I
	CALL vlineus
	
	; vline right
	PUSH byte [BP + 16]
	PUSH L
	PUSH J
	PUSH K
	CALL vlineus
	
	ADD SP, 28
	
.done:
	POPW L:K
	POPW J:I
	POP BP
	RET

; none fill_rect(i16 x1, i16 y1, i16 w, i16 h, u8 fgc)
; fills a rectangle in the fgc
; top left at (x1, y1)
fill_rect:
	PUSH BP
	MOV BP, SP
	
	PUSHW J:I
	PUSHW L:K
	
	; check and clip bounds
	; I = x1
	; J = y1
	; K = w, x2
	; L = h, y2
	MOVW J:I, [BP + 8]
	MOVW L:K, [BP + 12]
	
	ADD K, I
	ADD L, J
	DEC K
	DEC L
	
	; if x2 < 0 or x1 > width, definitely off screen
	CMP K, 0
	JL .done
	CMP I, COLS_PIXELS
	JGE .done
	
	; same with y and height
	CMP L, 0
	JL .done
	CMP J, ROWS_PIXELS
	JGE .done
	
	; clip to bounds
	CMP I, 0
	CMOVL I, 0
	
	CMP J, 0
	CMOVL J, 0
	
	CMP K, COLS_PIXELS - 1
	CMOVG K, COLS_PIXELS - 1
	
	CMP L, ROWS_PIXELS - 1
	CMOVG L, ROWS_PIXELS - 1
	
	; for each y, hline
	SUB L, J
.loop:
	PUSH byte [BP + 16]
	PUSH K
	PUSHW J:I
	CALL hlineus
	ADD SP, 7
	
	INC J
	DEC L
	JNS .loop
	
.done:
	POPW L:K
	POPW J:I
	POP BP
	RET
	