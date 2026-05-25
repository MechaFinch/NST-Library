
;
; STANDARD LIBRARY - MEMORY
; DYNAMIC MEMORY ALLOCATOR
; ASM IMPLEMENTATION
;
; Manually compiled version of dma.nstl so that it can be used in assembly projects
;

%libname dma

%define FREE_HEADER_SIZE_STATUS_OFFS	0
%define FREE_HEADER_NEXT_OFFS			4
%define FREE_HEADER_PREV_OFFS			8
%define FREE_HEADER_SIZE				12

%define HEAP_CONTROL_HEAP_SIZE_OFFS			0
%define HEAP_CONTROL_ALLOCATED_BYTES_OFFS	4
%define HEAP_CONTROL_FREE_BYTES_OFFS		8
%define HEAP_CONTROL_ALLOCATED_BLOCKS_OFFS	12
%define HEAP_CONTROL_FREE_BLOCKS_OFFS		14
%define HEAP_CONTROL_FREE_LIST_HEAD_OFFS	16
%define HEAP_CONTROL_SIZE					20

heap: resb HEAP_CONTROL_SIZE

; init(ptr heap_start, u32 max_size): none
; initializes the heap
init:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	PUSH K
	PUSH L

	; create initial block
	MOVW J:I, [BP + 8]	; heap start
	MOVW L:K, heap
	
	MOVW D:A, 2
	MOVW [J:I + FREE_HEADER_SIZE_STATUS_OFFS], D:A
	MOVW B:C, 0
	MOVW [J:I + FREE_HEADER_NEXT_OFFS], B:C
	MOVW D:A, L:K
	ADD A, HEAP_CONTROL_FREE_LIST_HEAD_OFFS - 4
	ICC D
	MOVW [J:I + FREE_HEADER_PREV_OFFS], D:A
	MOVW [J:I + FREE_HEADER_SIZE], B:C
	
	; heap control
	MOVW D:A, [BP + 12]
	MOVW [L:K + HEAP_CONTROL_HEAP_SIZE_OFFS], D:A
	MOVW [L:K + HEAP_CONTROL_ALLOCATED_BYTES_OFFS], B:C
	MOVW [L:K + HEAP_CONTROL_ALLOCATED_BLOCKS_OFFS], B:C
	INC C
	MOVW [L:K + HEAP_CONTROL_FREE_BLOCKS_OFFS], B:C
	MOVW [L:K + HEAP_CONTROL_FREE_LIST_HEAD_OFFS], J:I
	
	SUB A, (FREE_HEADER_SIZE + 4)
	DCC D
	MOVW [L:K + HEAP_CONTROL_FREE_BYTES_OFFS], D:A
	
	POP L
	POP K
	POP J
	POP I
	POP BP
	RET



; malloc(u32 n): ptr
; allocates n bytes, returning a pointer to the block contents
malloc:
	PUSH BP
	MOVW BP, SP
	
	; 0 = no allocation
	MOVW D:A, 0
	CMP word [BP + 8], 0
	JNZ .nonz
	CMP word [BP + 10], 0
	JZ .fret
	
.nonz:
	PUSH I
	PUSH J
	PUSH K
	PUSH L
	
	; align (n in D:A)
	PUSH word [BP + 10]
	PUSH word [BP + 8]
	CALL align
	ADD SP, 4
	
	MOVW J:I, heap	; current_block
	MOVW J:I, [J:I + HEAP_CONTROL_FREE_LIST_HEAD_OFFS]

.search_list:
	; get current size/status
	MOVW B:C, [J:I + FREE_HEADER_SIZE_STATUS_OFFS]
	MOV L, C
	AND CL, 0xFC	; B:C = size
	AND L, 0x0003	; L = status
	
	CMP B, 0
	JNZ .search_nonz
	CMP C, 0
	JZ .search_end
	
.search_nonz:
	CMP B, D
	JB .search_next
	JA .search_found
	CMP C, A
	JAE .search_found

.search_next:
	MOVW J:I, [J:I + FREE_HEADER_NEXT_OFFS]
	JMP .search_list

	; block found
.search_found:
	; downsize the block
	; n and size aren't needed after, so not saved
	PUSH D		; push n
	PUSH A
	PUSH word 0	; push status
	PUSH L
	PUSH B		; push size
	PUSH C
	PUSH J
	PUSH I
	CALL downsize
	ADD SP, 16
	
	; splice out of the free list
	PUSH J
	PUSH I
	CALL splice_out
	ADD SP, 4
	
	; mark as allocated, mark next block
	MOVW B:C, [J:I + FREE_HEADER_SIZE_STATUS_OFFS]	; next_header
	AND CL, 0xFC
	ADD C, 4
	ICC B
	ADD C, I
	ADC B, J
	
	MOV AL, 0x01
	OR byte [J:I + FREE_HEADER_SIZE_STATUS_OFFS], AL	; current_block->size_status |= 1
	INC AL
	OR byte [B:C + FREE_HEADER_SIZE_STATUS_OFFS], AL	; next_header->size_status |= 2

	JMP .sret

	; block not found
.search_end:
	; extend heap
	PUSH L
	MOVW L:K, D:A	; L:K = n
	ADD A, I		; current_block + n + 4
	ADC D, J
	ADD A, 4
	ICC D
	
	; set new_end_of_heap
	MOVW B:C, 2
	MOVW [D:A + FREE_HEADER_SIZE_STATUS_OFFS], B:C
	MOVS C, 0
	MOVW [D:A + FREE_HEADER_NEXT_OFFS], B:C
	MOVW B:C, [J:I + FREE_HEADER_PREV_OFFS] ; B:C = current_block->prev
	MOVW [D:A + FREE_HEADER_PREV_OFFS], B:C
	
	; update prev last block
	MOVW [B:C + FREE_HEADER_NEXT_OFFS], D:A
	
	; setup returned block
	MOVW B:C, 0
	MOVW [J:I + FREE_HEADER_NEXT_OFFS], B:C
	MOVW [J:I + FREE_HEADER_PREV_OFFS], B:C
	
	POP C	; n or status or 1
	OR K, C
	OR K, 1
	MOVW [J:I + FREE_HEADER_SIZE_STATUS_OFFS], L:K
	
.sret:
	MOVW D:A, J:I	; return current_block + 4
	ADD A, 4
	ICC D
	
	POP L
	POP K
	POP J
	POP I
	
.fret:
	POP BP
	RET



; calloc(u32 n): ptr
; allocate n bytes on the heap, clearing them to zero and returning a pointer to the block
calloc:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	PUSH K
	PUSH L
	
	MOVW J:I, [BP + 8]
	
	; call malloc
	PUSH J
	PUSH I
	CALL malloc
	ADD SP, 4
	
	; clear block
	MOVW B:C, D:A
	MOV L, 0
	JMP .clearcmp
.clear_loop:
	MOVZ [B:C], L
	ADD C, 4
	ICC B
	
.clearcmp:
	SUB I, 4
	DCC J
	JNS .clear_loop
	
	POP L
	POP K
	POP J
	POP I
	
	POP BP
	RET



; realloc(ptr block, u32 n): ptr
; re-allocates a block to a new size, copying data as needed and returning a new pointer
realloc:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	PUSH K
	PUSH L
	
	; D:A = new_size = align(n)
	PUSH word [BP + 14]
	PUSH word [BP + 12]
	CALL align
	ADD SP, 4
	
	; B:C = old_header = block - 4
	MOVW B:C, [BP + 8]
	SUB C, 4
	DCC B
	
	; J:I = old_size, K = old_status
	MOVW J:I, [B:C]
	MOV K, I
	AND K, 0x0003
	AND I, 0xFFFC
	
	; is size is unchanged, return. if old size is greater, downsize it
	CMP J, D
	JA .old_larger
	JB .old_smaller
	CMP I, A
	JE .rblock
	JB .old_smaller

.old_larger:
	; downsize(old_header, old_size, old_status, new_size)
	PUSH D
	PUSH A
	PUSH word 0
	PUSH K
	PUSH J
	PUSH I
	PUSH B
	PUSH C
	CALL downsize
	ADD SP, 16
	
.rblock:
	MOVW D:A, [BP + 8]
	JMP .ret

.old_smaller:
	; allocate new block
	PUSH D
	PUSH A
	CALL malloc
	ADD SP, 4
	
	PUSH D ; save new block
	PUSH A
	
	; copy data
	; J:I = counter, L:K = source, D:A = dest, B:C = passthrough
	MOVW L:K, [BP + 8]
	JMP .copycmp
.copyloop:
	MOVW B:C, [L:K]
	MOVW [D:A], B:C
	
	ADD K, 4
	ICC L
	ADD A, 4
	ICC D
	
.copycmp:
	SUB I, 4
	DCC J
	JNS .copyloop
	
	POP A ; restore new block to return
	POP D
	
.ret:
	POP L
	POP K
	POP J
	POP I
	
	POP BP
	RET



; rcalloc(ptr block, u32 n): ptr
; re-allocate a block to a new size, copying data as needed and clearing any new space, returning the new pointer
rcalloc:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	PUSH K
	
	; J:I = new_size = align(n)
	MOVW J:I, [BP + 12]
	PUSH J
	PUSH I
	CALL align
	ADD SP, 4
	
	PUSH D	; save new_size
	PUSH A
	
	; B:C = old_size = [block - 4] & ~3
	MOVW B:C, [BP + 8]
	MOVW D:A, B:C
	SUB C, 4
	DCC B
	MOVW B:C, [B:C]
	AND CL, 0xFC
	
	; D:A = new_block = realloc(block, n)
	PUSH J	; push n
	PUSH I
	PUSH D	; push block
	PUSH A
	CALL realloc
	ADD SP, 8
	
	POP I	; recover new_size
	POP J
	
	PUSH D	; save new_block
	PUSH A
	
	; while old_size < new_size, clear new block
	ADD A, C	; seek to end of old
	ADC D, B
	
	SUB I, C	; how much do we clear
	SBB J, B
	
	MOV K, 0
	JMP .cmp
.copy:
	MOVZ [D:A], K	; clear
	
	ADD A, 4		; inc ptr & dec counter
	ICC D
	
.cmp:
	SUB I, 4
	DCC J
	JNS .copy
	
.done:
	POP A	; recover new_block
	POP D
	
	POP K
	POP J
	POP I
	
	POP BP
	RET



; free(ptr block): none
; frees a block
free:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	PUSH K
	PUSH L
	
	MOVW J:I, [BP + 8]	; block header ptr
	SUB I, 4
	DCC J
	
	; ensure block is allocated
	CMP byte [J:I], 0
	JE .ret
	
	; splice into free list
	MOVW L:K, [J:I]	; block_size
	MOV A, K		; status
	AND K, 0xFFFC
	AND AL, 0xFE
	
	PUSH word 0	; push status
	PUSH A
	PUSH J		; push block header ptr
	PUSH I
	CALL splice_in
	ADD SP, 8
	
	; mark size @ end & clear next's prev alloc bit
	MOVW D:A, J:I
	ADD A, K
	ADC D, L
	MOVW [D:A], L:K
	MOVW B:C, [D:A + 4]			; get next size/status
	AND CL, 0xFD				; clear prev alloc bit
	XCHG CL, [D:A + 4]
	
	; merge with adjacent free blocks
	MOV L, [J:I]
	AND L, 0x0002
	MOVW L:K, J:I
	JNZ .no_prev_merge
	
	; D:A: next_header
	; B:C: next size/status
	; J:I: block header ptr
	; L:K low_header
	
	; merge with previous
	MOVW L:K, [J:I - 4]	; L:K = block - [block - 4] - 4
	NOT L
	NEG K
	DCC L
	ADD K, I
	ADC L, J
	SUB K, 4
	DCC L
	
	PUSH A	; save
	PUSH B
	PUSH C
	PUSH D
	
	PUSH J	; push block
	PUSH I
	PUSH L	; push low_header
	PUSH K
	CALL merge
	ADD SP, 8
	
	POP D
	POP C
	POP B
	POP A
	
.no_prev_merge:
	CMP B, 0		; is next block a real block
	JB .ret
	JA .next_merge
	CMP C, 3
	JBE .ret
	AND CL, 0x01	; is it free
	JNZ .ret

.next_merge:
	; merge with next
	PUSH D
	PUSH A
	PUSH L
	PUSH K
	CALL merge
	ADD SP, 8
	
.ret:
	POP L
	POP K
	POP J
	POP I
	
	POP BP
	RET



; align(u32 n): u32
; Alignes a value to 4 bytes
align:
	PUSH BP
	MOVW BP, SP
	
	MOVW D:A, [BP + 8]
	
	CMP D, 0
	JA .good
	CMP A, 12
	JAE .good
	
	; < 12 = set to min size
	MOVW D:A, 12
	POP BP
	RET

.good:
	; if low two bits clear, we good
	TST AL, 0x03
	JZ .ok
	
	; otherwise, align
	AND AL, 0xFC
	ADD A, 4
	ICC D

.ok:
	POP BP
	RET



; downsize(ptr header, u32 old_size, u32 old_status, u32 new_size): none
; downsizes an existing block, splicing the new left-over block into the free list
downsize:
	PUSH BP
	MOVW BP, SP
	
	; is there enough space for a new block
	MOVW D:A, [BP + 12]	; D:A = new_block_size = old_size - new_size - 4
	SUB A, [BP + 20]
	SBB D, [BP + 22]
	JNZ .ok
	CMP A, 16
	JAE .ok
	
	; not enough space
	POP BP
	RET

.ok:
	; there's enough space
	SUB A, 4	; finish computing new_block_size
	DCC D
	
	PUSH I
	PUSH J
	PUSH K
	PUSH L
	
	MOVW L:K, D:A	; new_block_size
	
	; modify existing block
	MOVW J:I, [BP + 8]	; J:I = header
	MOVW B:C, [BP + 20]	; new_size | old_status
	OR CL, [BP + 16]
	MOVW [J:I], B:C
	
	; place new block
	MOVW B:C, J:I	; header + new_size + 4
	ADD C, [BP + 20]
	ADC B, [BP + 20]
	ADD C, 4
	ICC B
	
	; splice new block into free list
	PUSH B
	PUSH C
	
	PUSH L
	PUSH K
	PUSH B
	PUSH C
	CALL splice_in
	ADD SP, 8
	
	POP C
	POP B
	
	; update headers
	ADD I, [BP + 12]	; header + old_size
	ADC J, [BP + 14]
	
	MOVW [J:I], L:K
	MOVW D:A, [BP + 20]
	MOVW [B:C - 4], D:A
	
	POP L
	POP K
	POP J
	POP I
	
	POP BP
	RET



; merge(ptr low_header, ptr high_header): none
; merges two free blocks
merge:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	PUSH K
	PUSH L
	
	MOVW J:I, [BP + 8]	; low_header
	MOVW L:K, [BP + 12]	; high_header

	; splice them out of the free list
	PUSH J
	PUSH I
	CALL splice_out
	
	PUSH L
	PUSH K
	CALL splice_out
	ADD SP, 8
	
	; create new block
	MOVW D:A, [J:I + FREE_HEADER_SIZE_STATUS_OFFS]	; D:A = low size
	MOVZ B, AL	; low status
	AND AL, 0xFC
	AND BL, 0x03
	
	MOVW L:K, [L:K + FREE_HEADER_SIZE_STATUS_OFFS]	; L:K = new size = low_size + high_size + 4
	AND K, 0xFFFC
	ADD K, 4
	ICC L
	ADD K, A
	ADC L, D
	
	MOVW D:A, J:I
	ADD A, K	; new_marker = low_header + new_size
	ADC D, L
	MOVW [D:A], L:K
	
	; splice it into the free list
	OR K, B
	
	PUSH L
	PUSH K
	PUSH J
	PUSH I
	CALL splice_in
	ADD SP, 8
	
	POP L
	POP K
	POP J
	POP I
	
	POP BP
	RET



; splice_in(ptr new_block, u32 size_status): none
; splices a block into the free list
splice_in:
	PUSH BP
	MOVW BP, SP
	
	PUSH I
	PUSH J
	
	MOVW B:C, [BP + 8]	; new_block
	MOVW D:A, [BP + 12]	; size_status
	MOVW [B:C + FREE_HEADER_SIZE_STATUS_OFFS], D:A
	MOVW D:A, heap
	ADD A, HEAP_CONTROL_FREE_LIST_HEAD_OFFS - 4
	MOVW [B:C + FREE_HEADER_PREV_OFFS], D:A
	MOVW J:I, [D:A + 4]
	MOVW [B:C + FREE_HEADER_NEXT_OFFS], J:I
	
	MOVW [J:I + FREE_HEADER_PREV_OFFS], B:C
	MOVW [D:A + 4], B:C
	
	POP J
	POP I
	
	POP BP
	RET



; splice_out(ptr block): none
; splices a block out of the free list
splice_out:
	PUSH BP
	MOVW BP, SP
	
	MOVW D:A, [BP + 8]
	MOVW B:C, [D:A + FREE_HEADER_NEXT_OFFS]
	MOVW D:A, [D:A + FREE_HEADER_PREV_OFFS]
	
	MOVW [B:C + FREE_HEADER_PREV_OFFS], D:A
	MOVW [D:A + FREE_HEADER_NEXT_OFFS], B:C
	
	POP BP
	RET
