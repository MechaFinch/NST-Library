
;
;	FakeOS Fault Handling
;

%include "terminal.asm" as term

%PRIVILAGED

%macro print(str_start, str_end):
	MOV A, 0x23
	MOV D, 1
	MOVW B:C, str_end - str_start
	MOVW J:I, str_start
	INT 0x20
%endmacro

%macro print_reg(offs):
	PUSH word [SP + offs]
	CALL print16
	ADD SP, 2
%endmacro

%macro print_mem(offs):
	PUSH word [L:K + offs]
	CALL print8
	ADD SP, 2
	print(str_space, str_space_a)
%endmacro

; none report_state()
; Report machine state at the time of a fault
; Must be called with nothing on the stack except interrupt state
report_state:
	PUSHW XP
	PUSHW YP
	PUSHA
	
	; 46	IP
	; 42	BP
	; 38	SP
	; 36	F
	; 34	PF
	; 30	return address
	; 26	XP
	; 22	YP
	; 20	D
	; 18	A
	; 16	B
	; 14	C
	; 12	J
	; 10	I
	; 8		L
	; 6		K
	; 4		Interrupt F
	; 0		Interrupt BP
	
	print(str_head, str_head_a)
	
	print(str_r16s, str_r16s_a)
	print_reg(18)
	print(str_space, str_space_a)
	print_reg(16)
	print(str_space, str_space_a)
	print_reg(14)
	print(str_space, str_space_a)
	print_reg(20)
	
	print(str_space, str_space_a)
	print_reg(10)
	print(str_space, str_space_a)
	print_reg(12)
	print(str_space, str_space_a)
	print_reg(6)
	print(str_space, str_space_a)
	print_reg(8)
	
	print(str_r32s, str_r32s_a)
	print_reg(28)
	print_reg(26)
	print(str_space2, str_space2_a)
	print_reg(24)
	print_reg(22)
	print(str_space2, str_space2_a)
	print_reg(44)
	print_reg(42)
	print(str_space2, str_space2_a)
	print_reg(40)
	print_reg(38)
	
	print(str_specs, str_specs_a)
	print_reg(48)
	print_reg(46)
	print(str_space2, str_space2_a)
	print_reg(36)
	print(str_space, str_space_a)
	print_reg(34)
	
	print(str_inst, str_inst_a)
	MOVW L:K, [SP + 40]	; get IP
	print_mem(0)
	print_mem(1)
	print_mem(2)
	print_mem(3)
	print_mem(4)
	print_mem(5)
	print_mem(6)
	print_mem(7)
	
	print(str_inter, str_inter_a)
	PUSHW BP
	print_reg(2)
	print_reg(0)
	print(str_space2, str_space_a)
	print_reg(4)
	
	
	POPA
	POPW YP
	POPW XP
	RET



; none print16(u16 v)
; Print v in 4 hex chars
print16:
	PUSH BP
	MOV BP, SP
	
	MOV A, [BP + 8]
	PMULH4 D:A, 0x1111		; 0xABCD -> 0x0A0B0C0D
	
	PCMP8 A, 0x0A0A			; number to digit/letter
	PCMOV8AE B, 0x3737
	PCMOV8B B, 0x3030
	
	PCMP8 D, 0x0A0A			; same for D
	PCMOV8AE B, 0x3737
	PCMOV8B B, 0x3030
	
	ADDW D:A, B:C			; won't overflow; don't need packed
	
	XCHG DH, AL				; reverse bytes
	XCHG DL, AH
	
	MOVW [.buffer], D:A		; place & print
	print(.buffer, .buffer_a)
	
	POP BP
	RET

.buffer:
	resb 4
.buffer_a:



; none print8(u8 v)
; Print v in 2 hex chars
print8:
	PUSH BP
	MOV BP, SP
	
	MOV A, [BP + 8]
	PMULH4 D:A, 0x1111		; 0xABCD -> 0x0A0B0C0D
	
	PCMP8 A, 0x0A0A			; number to digit/letter
	PCMOV8AE B, 0x3737
	PCMOV8B B, 0x3030
	ADD A, B
	
	XCHG AH, AL
	
	MOV [.buffer], A		; place & print
	print(.buffer, .buffer_a)
	
	POP BP
	RET

.buffer:
	resb 2
.buffer_a:

str_space: db " "
str_space_a:
str_space2: db "  "
str_space2_a:
str_head: db 0x1B, "[3;1fState"
str_head_a:
str_r16s: db 0x1B, "[4;1fA    B    C    D    I    J    K    L", 0x1B, "[5;1f"
str_r16s_a:
str_r32s: db 0x1B, "[6;1fXP        YP        BP        SP", 0x1B, "[7;1f"
str_r32s_a:
str_specs: db 0x1B, "[8;1fIP        F    PF", 0x1B, "[9;1f"
str_specs_a:
str_inst: db 0x1B, "[11;1fInstruction", 0x1B, "[12;1f"
str_inst_a:
str_inter: db 0x1B, "[14;1fInt. BP   Int. F", 0x1B, "[15;1f"
str_inter_a:
