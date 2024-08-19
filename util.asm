
;
; STANDARD LIBRARY - GENERAL
; UTILITIES
; Assembly Implementation
;

%libname util

; funciton_descriptor structure defines
%define FUNCTION_DESCRIPTOR_FUNC_PTR	0
%define FUNCTION_DESCRIPTOR_ARG_SIZE	4
%define FUNCTION_DESCRIPTOR_RET_SIZE	5

buffer_screen:
	MOV A, 1
	MOV [0xF003_FFFC], AL
	RET

unbuffer_screen:
	MOV A, 0
	MOV [0xF003_FFFC], AL
	RET

; none memcopy(ptr source, ptr dest, u32 length)
memcopy:
	PUSHW BP
	MOVW BP, SP
	PUSHW J:I
	PUSHW L:K
	
	; D:A = data
	; B:C = source
	; J:I = dest
	; L:K = length
	MOVW B:C, [BP + 8]
	MOVW J:I, [BP + 12]
	MOVW L:K, [BP + 16]
	JMP .cmp
	
.loop:
	MOVW D:A, [B:C]
	MOVW [J:I], D:A
	
	ADD C, 4
	ICC B
	ADD I, 4
	ICC J
	
	SUB K, 4
	DCC L
	
.cmp:
	CMP L, 0
	JNZ .loop
	CMP K, 4
	JAE .loop
	JMP byte [IP + K]
	db @.zero
	db @.one
	db @.two
	db @.three

.three:
	MOV A, [B:C]
	MOV [J:I], A
	MOV AL, [B:C + 2]
	MOV [J:I + 2], AL
	JMP .zero

.two:
	MOV A, [B:C]
	MOV [J:I], A
	JMP .zero
	
.one:
	MOV AL, [B:C]
	MOV [J:I], AL
	
.zero:	
	POPW L:K
	POPW J:I
	POPW BP
	RET

; none halt()
; halts
halt:
	HLT
	RET

; u16 mulh8(u8 a, u8 b)
; returns MULH A, B
mulh8:
	MOV AL, [SP + 4]
	MULH A, [SP + 5]
	RET

; i16 mulsh8(i8 a, i8 b)
; returns MULSH A, B
mulsh8:
	MOV AL, [SP + 4]
	MULSH A, [SP + 5]
	RET

; u32 mulh16(u16 a, u16 b)
; returns MULH A, B
mulh16:
	MOV A, [SP + 4]
	MULH D:A, [SP + 6]
	RET

; i32 mulsh16(i16 a, i16 b)
; returns MULSH A, B
mulsh16:
	MOV A, [SP + 4]
	MULH D:A, [SP + 6]
	RET

; u8 mod8(u8 a, u8 b)
; returns a % b
mod8:
	MOVZ A, [SP + 4]
	DIVM A, [SP + 5]
	MOV AL, AH
	RET

; i8 mods8(i8 a, i8 b)
; returns a % b
mods8:
	MOVS A, [SP + 4]
	DIVMS A, [SP + 5]
	MOV AL, AH
	RET

; u16 mod16(u16 a, u16 b)
; returns a % b
mod16:
	MOVZ D:A, [SP + 4]
	DIVM D:A, [SP + 6]
	MOV A, D
	RET

; i16 mods16(i16 a, i16 b)
; returns a % b
mods16:
	MOVS D:A, [SP + 4]
	DIVMS D:A, [SP + 6]
	MOV A, D
	RET

; u8 abs8(i8 a)
; returns |a|
abs8:
	MOV AL, [SP + 4]
	MOV AH, AL
	NOT AL
	CMOVS AL, AH
	RET

; u16 abs16(i16 a)
; returns |a|
abs16:
	MOV A, [SP + 4]
	MOV B, A
	NOT A
	CMOVS A, B
	RET

; u32 abs32(i32 a)
abs32:
	MOVW D:A, [SP + 4]
	MOVW B:C, D:A
	NOT D
	NEG A
	ICC D
	CMOVS D, B
	CMOVS C, A
	RET

; u16 enable_interrupts()
; enables interrupts, returning the previous value of PF
enable_interrupts:
	MOV A, PF
	MOV B, A
	OR B, 1
	MOV PF, B
	RET

; u16 disable_interrupts()
; disables interrupts, returning the previous value of PF
disable_interrupts:
	MOV A, PF
	MOV B, A
	AND B, 0xFFFE
	MOV PF, B
.r:
	RET

; none set_pf(u16 pf)
; sets PF to the given value
set_pf:
	MOV PF, [SP + 4]
	RET

; u16 get_pf()
; returns PF
get_pf:
	MOV A, PF
	RET


; ptr atomic_call(function_descriptor* desc, u8* args)
; calls the described function with arguments in the args buffer, returning its return value.
; interrupts are disabled for the duration of the function.
atomic_call:
	PUSH BP
	MOV BP, SP
	
	PUSH I
	PUSH J
	
	; mask interrupts
	MOV A, PF
	PUSH A
	AND A, 0xFFFE
	MOV PF, A
	
	; push arguments
	MOVW B:C, [BP + 8]
	MOV D, [B:C + FUNCTION_DESCRIPTOR_ARG_SIZE]
	MOVW J:I, [BP + 12]
	JMP .arg_cmp

.arg_loop:
	PUSH byte [J:I]
	INC I
	ICC J

	DEC D
.arg_cmp:
	CMP D, 0
	JNE .arg_loop
	
	; make call
	MOVW J:I, B:C ; caller saved
	CALLA [B:C + FUNCTION_DESCRIPTOR_FUNC_PTR]
	
	; fix SP
	MOVZ C, [J:I + FUNCTION_DESCRIPTOR_ARG_SIZE]
	LEA SP, [SP + C]
	
	; unmask interrupts & return
	POP PF
	
	POP I
	POP BP
	RET
