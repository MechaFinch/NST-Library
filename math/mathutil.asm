;
; STANDARD LIBRARY - MATH
; ASSEMBLY UTILITIES
; NOT NSTL COMPATIBLE
;
; Functions
;	mulu32(u32 a, u32 b): u64		32x32 unsigned multiply
;	muls32(i32 a, i32 b): i64		32x32 signed multiply
;	divmu32(u32 a, u32 b): u64		32x32 unsigned division (a / b)
;	divms32(i32 a, i32 b): i64		32x32 signed division (a / b)
;	to_hex_string(u16 num): u32		Converts a 16 bit value to a 4 byte ascii string of its hex
;

%libname mathutil

mulu32_high:
	PUSH BP
	MOV BP, SP
	
	PUSHW ptr [BP + 12]
	PUSHW ptr [BP + 8]
	CALL mulu32
	ADD SP, 8
	
	MOVW D:A, B:C
	POPW BP
	RET

; u64 mulu32(u32 a, u32 b)
; Returns a * b in B:C:D:A. Unsigned.
mulu32:
	PUSH BP
	MOV BP, SP
	PUSHW J:I
	
	; original implementation: 16 instructions, missed uppermost carries
	; 2nd implementation: 14 instructions, missed uppermost carries
	; this implementation: 14 instructions, includes uppermost carries
	; low dword = (alow*blow) + (alow*bhigh lower << 16) + (ahigh*blow lower << 16)
	; high dword = (ahigh*bhigh) + (alow*bhigh upper) + (ahigh*blow upper) + carries
	
	MOV A, [BP + 8]		; D:A = alow*blow
	MOV I, A
	MULH D:A, [BP + 12]
	MOV C, [BP + 10]	; B:C = ahigh*bhigh
	MULH B:C, [BP + 14]
	
	MULH J:I, [BP + 14]	; J:I = alow*bhigh
	
	ADD D, I	; add to result
	ADC C, J
	ICC B
	
	MOV I, [BP + 10]	; J:I = ahigh*blow
	MULH J:I, [BP + 12]
	
	
	ADD D, I	; add to result
	ADC C, J
	ICC B
	
	POPW J:I
	POPW BP
	RET



muls32_high:
	PUSH BP
	MOV BP, SP
	
	PUSHW ptr [BP + 12]
	PUSHW ptr [BP + 8]
	CALL muls32
	ADD SP, 8
	
	MOVW D:A, B:C
	POPW BP
	RET

; i64 muls32(i32 a, i32 b)
; Returns a * b in B:C:D:A. Signed.
muls32:
	PUSH BP
	MOV BP, SP
	PUSHW J:I
	
	; make arguments positive
	; B = 1 if result negative
	MOV B, 0
	CMP byte [BP + 11], 0
	JGE .a_pos
	
	NEGW ptr [BP + 8]
	MOV B, 1

.a_pos:
	CMP byte [BP + 15], 0
	JGE .b_pos
	
	NEGW ptr [BP + 12]
	XOR BL, 1

.b_pos:
	PUSH B
	
	; multiply, copied from mulu32
	MOV A, [BP + 8]		; D:A = alow*blow
	MOV I, A
	MULH D:A, [BP + 12]
	MOV C, [BP + 10]	; B:C = ahigh*bhigh
	MULH B:C, [BP + 14]
	
	MULH J:I, [BP + 14]	; J:I = alow*bhigh
	
	ADD D, I	; add to result
	ADC C, J
	ICC B
	
	MOV I, [BP + 10]	; J:I = ahigh*blow
	MULH J:I, [BP + 12]
	
	
	ADD D, I	; add to result
	ADC C, J
	ICC B
	
	; correct sign of result
	POP I
	CMP I, 0
	JE .r_pos
	
	NOT B
	NOT C
	NEGW D:A
	ICCW B:C
	
.r_pos:
	POPW J:I
	POPW BP
	RET



divu32:
	JMP divmu32

remu32:
	PUSH BP
	MOV BP, SP
	
	PUSHW ptr [BP + 12]
	PUSHW ptr [BP + 8]
	CALL divmu32
	ADD SP, 8
	
.done:
	MOVW D:A, B:C
	POPW BP
	RET

; divmu(u32 a, u32 b): u64
; Returns a / b in D:A and a % b in B:C. Unsigned
divmu32:
	PUSH BP
	MOVW BP, SP
	
	; check trivial cases
	MOVW D:A, [BP + 8]
	MOVW B:C, [BP + 12]
	
	; check div by zero
	CMP C, 0
	JNZ .nonzero
	CMP B, 0
	JNZ .wont_fit
	
.divzero:
	MOVW D:A, 0
	POP BP
	RET

.nonzero:
	; check if it fits in DIVM
	CMP B, 0
	JNZ .wont_fit
	
	; it might
	DIVM D:A, C
	JC .wont_fit
	
	; it fit!
	MOV C, D	; remainder in C
	MOV B, 0	; zero high words
	MOV D, 0
.retsmall:
	POP BP
	RET

.wont_fit:
	; doesn't fit in DIVM
	
	PUSH word 33	; bit counter @ bp - 2
	
	PUSH I
	PUSH J
	PUSH K
	PUSH L

	; D:A = quotient
	; B:C = remainder
	; J:I = dividend
	; L:K = divisor
	; [BP - 1] bit count
	; shift dividend left into remainder
	; if the divisor can be subtracted from the remainder, do so
	; if the divisor was subtracted, shift a 1 into the quotient, and a 0 otherwise
	; continue until all bits processed
	MOVW J:I, [BP + 8]
	MOVW L:K, B:C
	MOVW D:A, 0
	MOVW B:C, 0

	; fast loop until first 1
.floop:
	DEC byte [BP - 2]
	SHL I, 1
	RCL J, 1
	JNC .floop
	JMP .start
	
.loop:
	; shift quotient as its done anyways
	SHL A, 1
	RCL D, 1
	
	; shift dividend into remainder
	SHL I, 1	; dividend
	RCL J, 1
.start:
	RCL C, 1	; remainder
	RCL B, 1
	
	; can we subtract
	PUSH B
	PUSH C
	
	SUB C, K
	SBB B, L
	JC .no_subtract
	
	; discard saved remainder
	ADD SP, 4
	
	; shift 1 into quotient
	OR A, 1
	JMP .next

.no_subtract:
	POP C
	POP B
	
	; shift 0 into quotient (nop)

.next:
	; continue until bits processed
	DEC byte [BP - 2]
	JNZ .loop
	
	; done
.done:
	POP L
	POP K
	POP J
	POP I
	
	ADD SP, 2
	
	POP BP
	RET



divs32:
	JMP divms32

rems32:
	PUSH BP
	MOV BP, SP
	
	PUSHW ptr [BP + 12]
	PUSHW ptr [BP + 8]
	CALL divms32
	ADD SP, 8
	
	MOVW D:A, B:C
	POPW BP
	RET

; divms32(i32 a, i32 b): i64
; Returns a / b in D:A and a % b in B:C. Signed
divms32:
	PUSH BP
	MOVW BP, SP

	; make A and B positive
	; call divmu
	; fix signs
	;			rem			quot
	;	a+ b+	rem			quot
	;	a+ b-	rem			-quot
	;	a- b+	-rem		-quot
	;	a- b-	-rem		quot
	
	CMP byte [BP + 11], 0	; BL = sign(a)
	MOV B, 0
	CMOVS BL, 1
	JNS .a_pos
	
	NEGW ptr [BP + 8]

.a_pos:
	CMP byte [BP + 15], 0	; BH = sign(b)
	CMOVS BH, 1
	JNS .b_pos
	
	NEGW ptr [BP + 12]
	
.b_pos:
	PUSH B
	
	PUSHW ptr [BP + 12]
	PUSHW ptr [BP + 8]
	CALL divmu32
	ADD SP, 8
	
	XCHG B, [SP]			; BH = sign(b), BL = sign(a)
	PCMP8 B, 0x0101			; compare sign bytes individually
	POP B					; B = remainder high
	JZ.E8 .ok				; a+ b+ (each zero)
	JNZ.E8 .a_neg_b_neg		; a- b- (each nonzero)
	JZ .a_pos_b_neg			; a+ b- (BL zero -> BH nonzero)
	
	; a- b+ (BL nonzero -> BH zero)
.a_neg_b_pos:
	NEGW D:A	; quot = -quot
	NEGW B:C	; rem = -rem
	JMP .ok
	
.a_neg_b_neg:
	NEGW B:C	; rem = -rem
	JMP .ok

.a_pos_b_neg:
	NEGW D:A ; quot = -quot
	
.ok:
	POP BP
	RET
	


; u32 to_hex_string(u16 num)
; Converts the given number to a hex string
to_hex_string:
	PUSH BP
	MOVW BP, SP
	
	MOV A, [BP + 8]			; get num
	PMULH4 D:A, 0x1111		; nybbles of num -> bytes of D:A
	
	MOVW B:C, 0x3030_3030	; "0000" in B:C
	
	PCMP8 D, 0x0A0A			; Check for A-F in D
	PCMOV8AE B, 0x3737		; setup for A-F in D
	
	PCMP8 A, 0x0A0A			; same in A
	PCMOV8AE C, 0x3737
	
	ADDW D:A, B:C			; convert bytes -> chars (won't overflow -> not packed)
	
	POPW BP
	RET



; u16 from_hex_string(u32 str)
; Converets the given number from a capitalized hex string
from_hex_string:
	PUSH BP
	MOVW BP, SP
	
	MOVW D:A, [BP + 8]		; get string
	
	MOVW B:C, 0x30303030	; Setup B:C for 0-9 -> 0-9
	
	PCMP8 D, 0x4141			; Check for A-F
	PCMOV8AE B, 0x3737		; Setup A-F -> 10-15
	
	PCMP8 A, 0x4141			; Same in A
	PCMOV8AE C, 0x3737
	
	SUBW D:A, B:C			; Characters -> nybbles
	
	XCHG AH, DL				; A = low nybbles correct, upper nybbles clear, D = upper nybbles shifted right 4
	SHL D, 4				; D = upper nybbles correct
	OR A, D					; A = number
	
	POPW BP
	RET
	
	
	
	; Lowercase to Uppercase of 4 bytes, straight line code, 10 instructions, 40 bytes
	; D:A = 4 bytes of chars
	MOVW B:C, 0			; 2 Setup B:C
	
	PCMP8 D, 0x6161		; 4 Check >=a
	PCMOV8AE B, 0x5656	; 5 Setup lower -> upper for >=a
	PCMP8 D, 0x7B7B		; 4 Check >={
	PCMOV8AE B, 0x0000	; 5 Un-set lower -> upper for >={
	
	PCMP8 A, 0x6161		; 4 Same with A/C
	PCMOV8AE C, 0x5656	; 5
	PCMP8 A, 0x7B7B		; 4
	PCMOV8AE C, 0x0000	; 5
	
	SUBW D:A, B:C		; 2 Perform lower -> upper
	
	; Lowercase to uppercase of 4 bytes, branching, 20 instructions, 52 bytes
	; best	8 instructions	20 bytes	4 taken branches
	; avg	11 instructions	27 bytes	3 taken branches
	; worst	20 instructions	52 bytes	0 taken branches
	; D:A = 4 bytes of chars
	CMP AL, 0x61	; 3
	JB .b1			; 2 75.00% taken
	CMP AL, 0x7B	; 3
	JNB .b1			; 2 18.75% taken
	SUB AL, 0x56	; 3
	; repeat for each byte
