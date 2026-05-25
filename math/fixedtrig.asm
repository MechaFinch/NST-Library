
;
; STANDARD LIBRARY - MATH
; FIXED POINT TRIG
; ASSEMBLY IMPLEMENTATION
;
; Trigonomotry functions for 16 and 32 bit fixed point
; Functions taking an angle do so in radians
;

%libname fxt

%include "fixedpoint.asm" as fxp

%define cord88_k		0x009B
%define cord88_pi		0x0324
%define cord88_pi_2		0x0192
%define cord88_3pi_2	0x04B6
%define cord88_2pi		0x0648

; none cord88(i16 pointer dest, i16 a)
; Places sin(a) in dest[0], cos(a) in dest[1]
cord88:
	PUSHW BP
	MOVW BP, SP
	
	PUSHW J:I
	PUSHW L:K
	
	; Get into (-2pi, 2pi)
	MOVS D:A, [BP + 12]		; D:A = sx a
	DIVMS D:A, cord88_2pi	; A = a mod 2pi
	MOV A, D
	
	; Get a in the range (-pi/2, pi/2)
	; If a is in [3pi/2, 2pi] a = a - 2pi
	; If a is in [pi/2, 3pi/2] a = pi - a & set negate-cos flag
	; If a is in [-pi/2, pi/2] we're fine
	; If a is in [-3pi/2, -pi/2] a = -pi - a & set negate-cos flag
	; If a is in [-2pi, -3pi/2] a = a + 2pi
	
	MOV A, [BP + 12]	; A = a
	MOV L, 0			; L = flag
	
	MOV B, A			; B = |a|
	NEG B
	CMOVS B, A
	
	; what are we doing
	CMP B, cord88_pi_2
	JLE .a_ok
	CMP B, cord88_3pi_2
	JG .sub_2pi

.sub_from_pi:
	; a = (+/- pi) - a
	XCHG A, B
	CMP B, 0
	MOV A, cord88_pi
	CMOVS A, 0 - cord88_pi
	SUB A, B
	
	; set negate-cos flag
	MOV L, 1
	JMP .a_ok

.sub_2pi:
	; a = a +/- 2pi
	CMP A, 0
	MOV B, 0 - cord88_2pi
	CMOVS B, cord88_2pi
	ADD A, B
	
.a_ok:
	; A = alpha
	; B = theta
	; C = y
	; D = x
	; I = index
	; L = flag
	MOVZ B:C, 0
	MOV D, 0x0100	; 1.0
	
	MOV I, 0
.loop:
	; J = x >> i
	; K = y >> i
	MOV J, D
	MOV K, C
	
	SAR J, I
	SAR K, I

	; sigma = 1 if alpha > theta else -1
	CMP A, B
	JLE .sigma_negative

.sigma_positive:
	; theta += table
	; y>>i subtracted from x
	; x>>i added to y
	ADD B, [.table + I*2]
	SUB D, K
	ADD C, J
	JMP .inc

.sigma_negative:
	; theta -= table
	; y>>i added to x
	; x>>i subtracted from y
	SUB B, [.table + I*2]
	ADD D, K
	SUB C, J
	
.inc:
	INC I
	CMP I, 8
	JB .loop
	
	; J:I = dest
	MOVW J:I, [BP + 8]
	
	; multiply y by K, move to sine part of dest
	MULSH B:C, cord88_k
	MOV [J:I + 0], CH
	MOV [J:I + 1], BL
	
	; correct x if negate-cos flag set
	MOV C, D
	NEG C
	CMP L, 0
	CMOVNE D, C
	
	; multiply x by K, move to cosine part of dest
	MULSH C:D, cord88_k
	MOV [J:I + 2], DH
	MOV [J:I + 3], CL
	
.ret:
	POPW L:K
	POPW J:I
	POPW BP
	RET

.table:
	dw 0x000000C9, 0x00000076, 0x0000003E, 0x0000001F, 0x0000000F, 0x00000007, 0x00000003, 0x00000001

; i16 sin88(i16 a)
; Returns sin(a)
sin88:
	; destination on stack, 4 bytes
	PUSHW D:A
	MOVW D:A, SP
	
	; [SP + 8]	a
	; [SP + 4]	return address
	; [SP]		sincos dest
	PUSH word [SP + 8]
	CALL cord88
	POP B		; get a out of the way
	POPW D:A	; get sin(a) in A, D = cos(a) but we don't care
	RET

; i16 sin88(i16 a)
; Returns cos(a)
cos88:
	; destination on stack, 4 bytes
	PUSHW D:A
	MOVW D:A, SP
	
	; [SP + 8]	a
	; [SP + 4]	return address
	; [SP]		sincos dest
	PUSH word [SP + 8]
	CALL cord88
	POP B		; get a out of the way
	POP B		; get cos(a) in A, B = sin(a) but we don't care
	POP A
	RET

