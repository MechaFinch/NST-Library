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
	
	MOVW D:A, 0
	SUBW D:A, [BP + 8]
	MOVW [BP + 8], D:A
	MOV B, 1

.a_pos:
	CMP byte [BP + 15], 0
	JGE .b_pos
	
	MOVW D:A, 0
	SUBW D:A, [BP + 12]
	MOVW [BP + 12], D:A
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
	NOT D
	NEG A
	ICC D
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
	
	NOT word [BP + 10]
	NEG word [BP + 8]
	ICC word [BP + 10]

.a_pos:
	CMP byte [BP + 15], 0
	CMOVS BH, 1
	JNS .b_pos
	
	NOT word [BP + 14]
	NEG word [BP + 12]
	ICC word [BP + 14]
	
.b_pos:
	PUSH B
	
	PUSH word [BP + 14]
	PUSH word [BP + 12]
	PUSH word [BP + 10]
	PUSH word [BP + 8]
	CALL divmu32
	ADD SP, 8
	
	XCHG B, [SP]
	CMP B, 0x0000	; a+ b+
	JMP .ok
	CMP B, 0x0001	; a+ b-
	JMP .a_pos_b_neg
	CMP B, 0x0100	; a- b+
	JMP .a_neg_b_pos
	
	; a- b-
.a_neg_b_neg:
	; rem = -rem
	NOT word [SP]
	NEG C
	ICC word [SP]
	JMP .ok

.a_pos_b_neg:
	; quot = -quot
	NOT D
	NEG A
	ICC D
	JMP .ok

.a_neg_b_pos:
	; quot = -quot
	NOT D
	NEG A
	ICC D
	
	; rem = -rem
	NOT word [SP]
	NEG C
	ICC word [SP]
	
.ok:
	POP B
	POP BP
	RET
	
	
	
; u32 to_hex_string(u16 num)
; Converts the given number to a hex string
to_hex_string:
	PUSH BP
	MOV BP, SP
	
	MOV D, [BP + 8]
	MOV CL, DL
	AND CL, 0x0F
	CALL .sub_to_char
	MOV AL, BL
	
	MOV CL, DL
	SHR CL, 4
	CALL .sub_to_char
	MOV AH, BL
	
	MOV CL, DH
	AND CL, 0x0F
	CALL .sub_to_char
	MOV DL, BL
	
	MOV CL, DH
	SHR CL, 4
	CALL .sub_to_char
	MOV DH, BL
	
	POP BP
	RET
	
.sub_to_char:
	; converts CL to its character in BL
	MOV BL, 0x30
	CMP CL, 0x0A
	CMOVAE BL, 0x41 - 0x0A
	ADD BL, CL
	RET
