
;
; STANDARD LIBRARY - DATA STRUCTURES
; VEC
;

%libname vec

%include "memory/dma.asm" as dma
%include "math/mathutil.asm" as mutil

%define VEC_TS_DATA_OFFS	0
%define VEC_TS_LEN_OFFS		4
%define VEC_TS_CAP_OFFS		8
%define VEC_TS_DSIZE_OFFS	12
%define VEC_TS_SIZE			13



; vec_t create(u32 cap, u8 dsize)
; Creates a vector with capacity cap
create:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	
	; malloc vec_ts structure
	PUSH ptr VEC_TS_SIZE
	CALLA dma.malloc
	MOVW J:I, D:A
	
	; malloc data
	PUSH ptr 0
	PUSH byte [BP + 12]	; dsize
	PUSH word [BP + 10]	; cap
	PUSH word [BP + 8]
	CALLA mutil.mulu32
	
	PUSH D
	PUSH A
	CALLA dma.malloc
	ADD SP, 17
	
	; set fields
	MOVW [J:I + VEC_TS_DATA_OFFS], D:A
	MOVW D:A, 0
	MOVW [J:I + VEC_TS_LEN_OFFS], D:A
	MOVW D:A, [BP + 8]
	MOVW [J:I + VEC_TS_CAP_OFFS], D:A
	MOV AL, [BP + 12]
	MOVW [J:I + VEC_TS_DSIZE_OFFS], AL
	
	; return
	MOVW D:A, J:I
	
	POP J
	POP I
	POP BP
	RET



; none destroy(vec_t v)
; Destroys a vector
destroy:
	PUSH BP
	MOVW BP, SP
	
	PUSH J
	PUSH I
	
	MOVW J:I, [BP + 8]
	MOVW D:A, [J:I + VEC_TS_DATA_OFFS]
	PUSH D
	PUSH A
	CALLA dma.free
	
	PUSH J
	PUSH I
	CALLA dma.free
	ADD SP, 8
	
	POP I
	POP J
	
	POP BP
	RET



; subroutine grow
;	J:I	= vector struct pointer
;	L:K = new size
;	clobbers A, B, C, D
sub_grow:
	; resize policy: 1.5x size until >= new size
	MOVW D:A, [J:I + VEC_TS_CAP_OFFS]

.loop:
	; D:A *= 1.5
	MOVW B:C, D:A
	SHR B, 1
	RCR C, 1
	ADD A, C
	ADC D, B
	
	; are we good
	CMP D, L
	JB .loop
	JA .ok
	CMP A, K
	JB .loop

.ok:
	; D:A = new cap
	MOVW [J:I + VEC_TS_CAP_OFFS], D:A
	
	; D:A = size in bytes
	; 9 bytes
	PUSH ptr 0
	PUSH byte [J:I + VEC_TS_DSIZE_OFFS]
	PUSH D
	PUSH A
	CALLA mutil.mulu32
	
	; realloc
	PUSH D
	PUSH A
	PUSH word [J:I + VEC_TS_DATA_OFFS + 2]
	PUSH word [J:I + VEC_TS_DATA_OFFS]
	CALLA dma.realloc
	ADD SP, 17
	
	RET



; subroutine place
;	D:A = index
;	J:I = vec pointer
;	L:K = data pointer
;	clobbers A, B, C, D, I, J, K, L
sub_place:
	; compute pointer in data area
	PUSH ptr 0
	PUSH byte [J:I + VEC_TS_DSIZE_OFFS]
	PUSH D
	PUSH A
	CALLA mutil.mulu32
	ADD SP, 9
	
	; D:A = data
	; C = bytes to copy
	; J:I = vec contents pointer
	; L:K = data pointer
	MOVZ C, [J:I + VEC_TS_DSIZE_OFFS]
	MOVW J:I, [J:I + VEC_TS_DATA_OFFS]
	ADD I, A
	ADC J, D
	
	CMP C, 4
	JB .less4
.loop:
	MOVW D:A, [L:K]
	MOVW [J:I], D:A
	
	ADD K, 4
	ICC L
	ADD I, 4
	ICC J

	SUB C, 4
	JAE .loop

.less4:
	PUSH I
	MOV I, C
	MOV CL, [IP + I + $table]
	POP I
	JMP CL
.table:
	db @.c0
	db @.c1
	db @.c2
	db @.c3

.c3:
	MOV A, [L:K]
	MOV [J:I], A
	MOV AL, [L:K + 2]
	MOV [J:I + 2], AL
	JMP .c0

.c2:
	MOV A, [L:K]
	MOV [J:I], A
	JMP .c0

.c1:
	MOV AL, [L:K]
	MOV [J:I], AL

.c0:
	RET



; subroutine idx_ptr
;	D:A = index
;	J:I = vec pointer
;	clobbers A, B, C, D
;	Result in D:A
sub_idx_ptr:
	; compute pointer in data area
	PUSH ptr 0
	PUSH byte [J:I + VEC_TS_DSIZE_OFFS]
	PUSH D
	PUSH A
	CALLA mutil.mulu32
	ADD SP, 9
	
	ADD A, I
	ADC D, J
	RET



; none set(vec_t v, u32 i, ptr data)
; Sets an element in the vector
; Capacity may be increased
set:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	PUSH K
	PUSH L
	
	MOVW J:I, [BP + 8]
	MOVW D:A, [J:I + VEC_TS_CAP_OFFS]
	MOVW B:C, [BP + 12]
	CMP B, D
	JA .cap_ok
	JB .cap_bad
	CMP C, A
	JA .cap_ok

.cap_bad:
	; not enough capacity, realloc
	PUSH B
	PUSH C
	
	MOVW L:K, B:C
	INC K
	ICC L
	CALL sub_grow
	
	; pop i to D:A, L:K = data
	POP A
	POP D
	MOVW L:K, [BP + 16]
	CALL sub_place
	
	POP L
	POP K
	POP J
	POP I
	
	POP BP
	RET



; ptr get(vec_t v, u32 i)
; Returns a pointer to the ith element
; 0 on out-of-bounds
; Volatile with respect to set, remove, append, resize, push
get:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	
	; check bounds
	MOVW D:A, [BP + 12]
	CMP [J:I + VEC_TS_LEN_OFFS + 2], D
	JA .ok
	JB .bad
	CMP [J:I + VEC_TS_LEN_OFFS], A
	JA .ok
	
.bad:
	MOVW D:A, 0
	JMP .ret
	
.ok:
	; get pointer
	MOVW J:I, [BP + 8]
	CALL sub_idx_ptr
	
.ret:
	POP J
	POP I
	
	POP BP
	RET



; none remove(vec_t v, u32 i)
; Destructively removes an element from the vector (overwriting with subsequent elements)
remove:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	PUSH K
	PUSH L
	
	; is the index in bounds
	MOVW J:I, [BP + 8]
	MOVW D:A, [BP + 12]
	
	MOVW B:C, [J:I + VEC_TS_LEN_OFFS]
	CMP B, D
	JA .ok
	JB .ret
	CMP C, A
	JA .ok
	JMP .ret
	
	; # elements to copy in L:K
	SUB C, A
	SBB B, D
	MOVW L:K, B:C
	
	; get ptr in L:K, # bytes to copy in D:A
	CALL sub_idx_ptr
	XCHG L:K, D:A
	CALL sub_idx_ptr
	
	; decrement size
	DEC word [J:I + VEC_TS_LEN_OFFS]
	DCC word [J:I + VEC_TS_LEN_OFFS + 2]
	
	; copy
	; D:A = # bytes to copy
	; B:C = data
	; J:I = pointer to copy from
	; L:K = pointer to copy to
	MOVW B:C, L:K
	ADD CL, [J:I + VEC_TS_DSIZE_OFFS]
	ICC CH
	ICC B
	MOVw J:I, B:C
	
	CMP D, 0
	JA .loop
	CMP A, 4
	JB .less4
.loop:
	MOVW B:C, [J:I]
	MOVW [L:K], B:C
	
	ADD I, 4
	ICC J
	ADD K, 4
	ICC L

	SUB A, 4
	DCC D
	
	CMP D, 0
	JA .loop
	CMP A, 4
	JAE .loop
	
.less4:
	; todo
	PUSH I
	MOV I, A
	MOV CL, [IP + I + $table]
	POP I
	JMP CL
.table:
	db @.c0
	db @.c1
	db @.c2
	db @.c3

.c3:
	MOV C, [J:I]
	MOV [L:K], C
	MOV CL, [J:I + 2]
	MOV [L:K + 2], CL
	JMP .c0
	
.c2:
	MOV C, [J:I]
	MOV [L:K], C
	JMP .c0
	
.c1:
	MOV CL, [J:I]
	MOV [L:K], CL
	
.c0:
	
.ret:
	POP L
	POP K
	POP J
	POP I
	
	POP BP
	RET



; none append(vec_t v, ptr data)
; Appends an element to the vector
; Capacity may be increased
append:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	
	MOVW J:I, [BP + 8]
	
	; do we have spare capacity
	MOVW D:A, [J:I + VEC_TS_LEN_OFFS]
	
	
	POP J
	POP I
	
	POP BP
	RET
