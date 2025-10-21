
;
; Hashtable
; Assembly implementation
;

%include "fakeos/os.asm" as os

%define TABLE_BUCKET_MASK	0
%define TABLE_BUCKET_ARRAY	2
%define TABLE_HASHER		6
%define TABLE_COMPARER		10
%define TABLE_SIZE			14

%define ENTRY_KEY	0
%define ENTRY_VALUE	4
%define ENTRY_NEXT	8
%define ENTRY_SIZE	12



; hashtable_t create(u16 max_buckets, ptr hasher, ptr comparer)
create:
	PUSH BP
	MOVW BP, SP
	PUSHW J:I
	
	; determine number of buckets
	; J = buckets
	MOV J, 1
	JMP .buckets_cmp
	
.buckets_loop:
	; buckets gets buckets << 1
	SHL J, 1
	
	; while buckets <= max_buckets
.buckets_cmp:
	CMP J, [BP + 8]
	JNA .bucekts_loop
	
	; buckets gets buckets >> 1
	SHR J, 1
	
	; Create table structure
	; D:A = table gets (call _os.malloc with sizeof hashtable_s)
	PUSHW ptr TABLE_SIZE
	CALL os.malloc
	ADD SP, 4
	
	; table.bucket_mask gets (buckets - 1) as u32
	MOV C, J
	DEC C
	MOVW [D:A + TABLE_BUCKET_MASK], C
	
	; table.bucket_array gets (call _os.malloc with (sizeof ptr) * (buckets as u32))
	PUSHW D:A
	
	LEA B:C, [J*4 + 0]
	PUSHW B:C
	CALL os.malloc
	ADD SP, 4
	
	POPW B:C
	MOVW [B:C + TABLE_BUCKET_ARRAY], D:A
	
	; table.hasher gets hasher
	MOVW D:A, [BP + 10]
	MOVW [B:C + TABLE_HASHER], D:A
	
	; table.comparer gets comparer
	MOVW D:A, [BP + 14]
	MOVW [B:C + TABLE_COMPARER], D:A
	
	; Mark buckets as empty
	; D:A = 0
	; B:C = table.bucket_array
	; I = i
	; J = buckets
	PUSHW B:C
	MOVW B:C, [B:C + TABLE_BUCKET_ARRAY]
	MOVW D:A, 0
	MOV I, 0
	JMP .empty_cmp
	
.empty_loop:
	MOVW [B:C + I*4], D:A

.empty_cmp:
	CMP I, J
	JB .empty_loop
	
	POPW D:A	; return table
	POPW J:I
	POP BP
	RET