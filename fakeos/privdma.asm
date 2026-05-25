
;
; STANDARD LIBRARY - MEMORY
; DYNAMIC MEMORY ALLOCATOR
; ASM IMPLEMENTATION
; Privileged copy
;
; Re-written cause previous version(s) are poorly tested and broken
;

%libname pdma

%PRIVILEGED

;
; Memory Layout
;	Free Block
;		field					bytes		notes
;		size/status word		4			31:2 = size; 1 = 1 iff prev. block allocated; 0 = 0
;		next free block pointer	4
;		prev free block pointer	4
;		space					size - 12
;		footer size word		4			31:2 = size; 1:0 = 0
;	Allocated block
;		field					bytes		notes
;		size/status word		4			31:2 = size; 1 = 1 iff prev. block allocated; 0 = 1
;		data					size
;
;	Allocator
;		field				bytes	notes
;		heap start			4		allocator + 20
;		heap size			4
;		#bytes allocated	4		excludes headers
;		#bytes free			4		excludes headers
;		free list head		4
;

%define FREE_HEAD_SIZE_OFFS	0
%define FREE_HEAD_NEXT_OFFS	4
%define FREE_HEAD_PREV_OFFS	8
%define FREE_HEAD_SIZE		12
%define MIN_BLOCK_SIZE (FREE_HEAD_SIZE + 4)

%define ALLOCATED_HEAD_SIZE_OFFS	0
%define ALLOCATED_HEAD_SIZE			4

%define ALLOC_HEAP_START_OFFS		0
%define ALLOC_HEAP_SIZE_OFFS		4
%define ALLOC_ALLOCATED_OFFS		8
%define ALLOC_FREE_OFFS				12
%define ALLOC_FREE_LIST_HEAD_OFFS	16
%define ALLOC_SIZE					20

; init(heap_start: ptr, heap_size: u32): allocator_t
; Create a heap with the given start address
init:
	PUSH BP
	MOV BP, SP
	
	PUSHW J:I
	PUSHW L:K
	PUSHW XP
	PUSHW YP
	
	; D:A = allocator = heap start
	MOVW D:A, [BP + 8]
	
	; B:C = heap start = allocator + alloc size + alignment
	MOVW B:C, D:A
	ADDW B:C, ALLOC_SIZE
	
	TST CL, 0x03
	JZ .heap_start_ok
	
	AND CL, 0xFC
	ADDW B:C, 4
	
.heap_start_ok:
	MOVW [D:A + ALLOC_HEAP_START_OFFS], B:C
	
	; J:I = heap size = allocator + heap_size - heap start
	MOVW J:I, D:A
	ADDW J:I, [BP + 12]
	SUBW J:I, B:C
	MOVW [D:A + ALLOC_HEAP_SIZE_OFFS], J:I
	
	; L:K = free = heap size - 16 (first header + end-of-heap block)
	MOVW L:K, J:I
	SUBW L:K, 16
	MOVW [D:A + ALLOC_FREE_OFFS], L:K
	
	; free list head = heap start
	MOVW [D:A + ALLOC_FREE_LIST_HEAD_OFFS], B:C
	
	; initialize end-of-heap block
	; starts at heap start + free + 4
	MOVW YP, L:K
	ADDW YP, B:C
	ADDW YP, 4
	
	; size_status = size 0; prev free; allocated (such that it does not get merged)
	MOVW XP, 1
	MOVW [YP + FREE_HEAD_SIZE_OFFS], XP
	
	; next = 0
	MOVW XP, 0
	MOVW [YP + FREE_HEAD_NEXT_OFFS], XP
	
	; prev = first header
	MOVW [YP + FREE_HEAD_PREV_OFFS], B:C
	
	; initialize first block
	; size_status = free | 0x02
	OR K, 0x0002
	MOVW [B:C + FREE_HEAD_SIZE_OFFS], L:K
	
	; next free block = end-of-heap block
	MOVW [B:C + FREE_HEAD_NEXT_OFFS], YP
	
	; prev free block = allocator.free_list_head - next_offs such that
	; setting <most recent block>.prev.next sets free list head
	MOVW J:I, D:A
	ADDW J:I, ALLOC_FREE_LIST_HEAD_OFFS - FREE_HEAD_NEXT_OFFS
	MOVW [B:C + FREE_HEAD_PREV_OFFS], J:I
	
	; allocated = 0
	MOVW [D:A + ALLOC_ALLOCATED_OFFS], XP
	
	POPW YP
	POPW XP
	POPW L:K
	POPW J:I
	POP BP
	RET



; malloc(heap: allocator_t, n: u32): ptr
; Allocate n bytes in the heap
; Returns a pointer to the allocated space
; If n bytes cannot be allocated, returns 0
malloc:
	PUSH BP
	MOVW BP, SP
	
	PUSHW J:I
	PUSHW L:K
	PUSHW XP
	
	; Align n to 4 bytes and a minimum of 12
	; D:A = aligned n
	PUSHW ptr [BP + 12]
	CALL align
	ADD SP, 4
	
	; Search the free list for a block with size >= n
	MOVW J:I, [BP + 8]							; J:I = heap
	MOVW J:I, [J:I + ALLOC_FREE_LIST_HEAD_OFFS]	; J:I = free list head
	
.search_loop:
	; Get size/status
	MOVW L:K, [J:I + FREE_HEAD_SIZE_OFFS]	; L:K = size
	AND K, 0xFFFC
	
	; Did we reach the end without finding anything?
	CMPW L:K, 0
	JE .no_block
	
	; Is this block big enough
	CMPW L:K, D:A
	JAE .block_found
	
	; No, get next
	MOVW J:I, [J:I + FREE_HEAD_NEXT_OFFS]
	JMP .search_loop
	
.no_block:
	MOVW D:A, 0
	JMP .ret

.block_found:
	; We have a free block. Splice it out of the free list.
	; J:I = block
	; L:K = size
	; XP = n
	MOVW XP, D:A
	
	PUSH byte 1
	PUSHW J:I
	CALL splice_out
	ADD SP, 5
	
	; If the block is sufficiently large, cut it in two and splice the remainder into the free list
	MOVW B:C, L:K	; B:C = size - n
	SUBW B:C, XP
	CMPW B:C, MIN_BLOCK_SIZE + ALLOCATED_HEAD_SIZE	; allocated size = n + allocated head size
	JB .no_split
	
	; Split block in two
	PUSHW B:C		; save size - n
	
	; Make current block size n
	MOVZ B:C, [J:I + FREE_HEAD_SIZE_OFFS]	; B:C = current status
	AND C, 0x0003
	ADDW B:C, XP							; B:C = new size-status
	MOVW [J:I + FREE_HEAD_SIZE_OFFS], B:C
	
	; Make new block
	MOVW D:A, J:I							; D:A = new block ptr
	ADDW D:A, XP
	ADDW D:A, ALLOCATED_HEAD_SIZE
	
	POPW B:C								; B:C = new block size/status
	SUBW B:C, ALLOCATED_HEAD_SIZE
	OR CL, 0x02
	MOVW [D:A + FREE_HEAD_SIZE_OFFS], B:C
	
	; Splice in
	PUSHW D:A
	PUSHW ptr [BP + 8]
	CALL splice_in
	ADD SP, 8
	
	; bookkeeping - allocated head size less bytes free due to header
	MOVW D:A, [BP + 8]
	SUBW ptr [D:A + ALLOC_FREE_OFFS], ALLOCATED_HEAD_SIZE

.no_split:
	; bookkeeping - size less bytes free; size more bytes allocated
	MOVW D:A, [J:I + FREE_HEAD_SIZE_OFFS]	; D:A = real size
	AND AL, 0xFC
	
	MOVW B:C, [BP + 8]
	ADDW [B:C + ALLOC_ALLOCATED_OFFS], D:A
	SUBW [B:C + ALLOC_FREE_OFFS], D:A

	; Return resulting block
	LEA D:A, [J:I + ALLOCATED_HEAD_SIZE]
	
.ret:
	POPW XP
	POPW L:K
	POPW J:I
	POPW BP
	RET



; free(heap: allocator_t, block: ptr): none
; Free a block
free:
	PUSH BP
	MOVW BP, SP
	
	PUSHW J:I
	PUSHW L:K
	
	MOVW J:I, [BP + 12]				; J:I = block
	SUBW J:I, ALLOCATED_HEAD_SIZE
	MOVW L:K, [BP + 8]				; L:K = heap
	
	; bookkeeping - size more bytes free, size less bytes allocated
	MOVW D:A, [J:I + FREE_HEAD_SIZE_OFFS]	; D:A = size/status
	AND AL, 0xFC							; D:A = size
	
	ADDW [L:K + ALLOC_FREE_OFFS], D:A		; free += size
	SUBW [L:K + ALLOC_ALLOCATED_OFFS], D:A	; allocated -= size
	
	; splice into free list
	PUSHW J:I
	PUSHW ptr [BP + 8]
	CALL splice_in
	ADD SP, 8
	
	; Merge upper block if appropriate
	LEA D:A, [J:I + ALLOCATED_HEAD_SIZE]	; D:A = upper ptr
	MOVW B:C, [J:I + FREE_HEAD_SIZE_OFFS]
	AND CL, 0xFC
	ADDW D:A, B:C
	
	MOV CL, 0x01
	TST byte [D:A + FREE_HEAD_SIZE_OFFS], CL	; allocated?
	JNZ .upper_allocated
	
	; Merge upper
	PUSHW D:A
	PUSHW J:I
	CALL merge
	ADD SP, 8
	
	; bookkeeping - allocated head size more bytes free
	ADDW ptr [L:K + ALLOC_FREE_OFFS], ALLOCATED_HEAD_SIZE
	
	; Merge lower block if appropriate
.upper_allocated:
	MOV CL, 0x02
	TST byte [J:I + FREE_HEAD_SIZE_OFFS], CL	; allocated?
	JNZ .lower_allocated

	LEA D:A, [J:I - 4]							; D:A = lower ptr
	SUBW D:A, [D:A]
	
	; Merge lower
	PUSHW J:I
	PUSHW D:A
	CALL merge
	ADD SP, 8
	
	; bookkeeping - allocated head size more bytes free
	ADDW ptr [L:K + ALLOC_FREE_OFFS], ALLOCATED_HEAD_SIZE

.lower_allocated:
	POPW L:K
	POPW J:I
	POPW BP
	RET



; realloc(heap: allocator_t, block: ptr, n: u32): ptr
; re-allocate a block to a new size, copying the data as needed and returning a new pointer
realloc:
	PUSH BP
	MOVW BP, SP
	
	PUSHW J:I
	PUSHW L:K
	PUSHW XP
	
	; align desired size
	; D:A = desired size
	PUSHW ptr [BP + 16]
	CALL align
	ADD SP, 4
	
	MOVW J:I, [BP + 12]						; J:I = block
	SUBW J:I, ALLOCATED_HEAD_SIZE
	MOVW B:C, [J:I + FREE_HEAD_SIZE_OFFS]	; B:C = size
	AND CL, 0xFC
	
	; If the desired size is equal to the current size, no action
	CMPW D:A, B:C
	JE .return_block
	JA .desired_larger
	
	; If the desired size is less than the current size, and there is enough space to create a new
	; free block, split the block
	SUBW B:C, D:A				; B:C = actual - desired
	CMPW B:C, MIN_BLOCK_SIZE	; can we split?
	JB .return_block			; return unchanged if not enough difference to split
	
	; Split block
	; Bookkeeping - (actual - desired) - header size more bytes free; (actual - desired) bytes less allocated
	MOVW XP, [BP + 8]						; XP = heap
	SUBW [XP + ALLOC_ALLOCATED_OFFS], B:C	; update #bytes allocated
	SUBW B:C, ALLOCATED_HEAD_SIZE			; B:C = upper block size
	ADDW [XP + ALLOC_FREE_OFFS], B:C		; update #bytes free
	
	; Resize lower block
	MOVW L:K, D:A							; L:K = lower block size
	MOV DL, [J:I + FREE_HEAD_SIZE_OFFS]		; get current lower block status
	AND DL, 0x03
	OR AL, DL								; put in new lower block status
	MOV D, L
	MOVW [J:I + FREE_HEAD_SIZE_OFFS], D:A	; place new lower block size/status
	
	; Create upper block
	ADDW J:I, L:K							; J:I = upper block ptr
	ADDW J:I, ALLOCATED_HEAD_SIZE
	
	OR CL, 0x02								; B:C = upper block size/status = size | prev allocated
	MOVW [J:I + FREE_HEAD_SIZE_OFFS], B:C	; place size/status
	
	; Splice upper into free list
	PUSHW J:I
	PUSHW XP
	CALL splice_in
	ADD SP, 8
	
	JMP .return_block
	
.desired_larger:
	; D:A = desired size
	; B:C = current size
	; J:I = block
	
	; If the desired size is larger than the current size, and the subsequent block is free, and has
	; enough space to fit the desired size, expand into the subsequent block
	MOVW L:K, J:I							; L:K = next block ptr
	ADDW L:K, B:C
	ADDW L:K, ALLOCATED_HEAD_SIZE
	
	MOVW XP, D:A							; XP = desired size
	MOVW D:A, [L:K + FREE_HEAD_SIZE_OFFS]	; D:A = next block size/status
	TST AL, 0x01							; is the block free
	JNZ .cant_merge
	
	AND AL, 0xFC							; D:A = max merged size = next block size + current block size + header size
	ADDW D:A, B:C
	ADDW D:A, ALLOCATED_HEAD_SIZE
	
	CMPW D:A, XP							; is there enough for desired size?
	JB .cant_merge
	
	; Is there enough space to split the upper block
	SUBW D:A, XP				; D:A = remaining size = max size - desired size
	CMPW D:A, MIN_BLOCK_SIZE	; can we split?
	JB .merge_no_split
	
	; There's enough space to split
	; Make new upper upper block, then merge upper and lower
	; splice upper out of free list (done now in case of overlap)
	MOVW XP, D:A	; XP = remaining size
	PUSH byte 0		; splice_out(upper, false)
	PUSHW L:K
	CALL splice_out
	ADD SP, 5
	
	; get new upper size
	MOVW D:A, [L:K + FREE_HEAD_SIZE_OFFS]	; D:A = current upper size
	AND AL, 0xFC
	SUBW D:A, XP							; D:A = new upper size = current - remaining
	
	; bookkeeping
	ADDW D:A, ALLOCATED_HEAD_SIZE			; D:A = change in alloc/free
	MOVW B:C, [BP + 8]						; B:C = heap
	ADDW [B:C + ALLOC_ALLOCATED_OFFS], D:A	; bookkeeping
	SUBW [B:C + ALLOC_FREE_OFFS], D:A
	SUBW D:A, ALLOCATED_HEAD_SIZE			; D:A = new upper size
	
	; place new upper size/status
	MOVW [L:K + FREE_HEAD_SIZE_OFFS], D:A	; place size. status doesn't matter cause it'll get merged
	
	; make upper upper block
	ADDW D:A, L:K							; D:A = upper upper ptr = upper ptr + upper size + head size
	ADDW D:A, ALLOCATED_HEAD_SIZE
	
	MOVW B:C, XP							; B:C = upper upper size/status = (remaining - head size) | prev allocated
	SUBW B:C, ALLOCATED_HEAD_SIZE
	OR CL, 0x02
	
	MOVW [D:A + FREE_HEAD_SIZE_OFFS], B:C	; place upper upper size/status
	
	; splice upper upper into free list
	PUSHW D:A
	PUSHW ptr [BP + 8]
	CALL splice_in
	ADD SP, 8
	JMP .merge_blocks

.merge_no_split:
	; bookkeeping prior to full merge
	; D:A = remaining size
	; B:C = current size
	; J:I = block
	; L:K = next block ptr
	; XP = desired size
	MOVW D:A, [BP + 8]						; D:A = heap
	MOVW B:C, [L:K + FREE_HEAD_SIZE_OFFS]	; B:C = upper size
	AND CL, 0xFC
	
	SUBW [D:A + ALLOC_FREE_OFFS], B:C		; next block size less bytes free
	ADDW B:C, 4
	ADDW [D:A + ALLOC_ALLOCATED_OFFS], B:C	; next block size + head size more bytes allocated

.merge_blocks:
	; merge the two blocks
	; J:I = lower
	; L:K = upper
	PUSHW L:K
	PUSHW J:I
	CALL merge
	ADD SP, 8
	
	JMP .return_block
	
.cant_merge:
	; D:A = --
	; B:C = current block size
	; J:I = current block ptr
	; L:K = next block ptr
	; XP = desired size
	
	; If the desired size is larger than the current size, and the subsequent block is not free or is too small,
	; allocate a new block with the desired size and copy to that block
	PUSHW B:C
	
	PUSHW XP			; D:A = new block = malloc(heap, desired)
	PUSHW ptr [BP + 8]
	CALL malloc
	ADD SP, 8
	
	POPW B:C
	
	; did we actually allocate
	CMPW D:A, 0
	JE .ret
	
	; Copy from old to new
	; B:C = #bytes to copy
	LEA L:K, [J:I + ALLOCATED_HEAD_SIZE]	; L:K = source
	LEA XP, [D:A + ALLOCATED_HEAD_SIZE]		; XP = dest
	
	XCHGW J:I, B:C		; J:I = #bytes, B:C = original block
	
.copy_loop:
	CMPW J:I, 16
	JAE .copy_16
	JMP word [IP + I]
	
	dw @.copy_0
	dw 0
	dw @.copy_4
	dw 0
	dw @.copy_8
	dw 0
	dw @.copy_12
	dw 0
	
.copy_16:
	STIW XP, ptr [L:K + 0]
	STIW XP, ptr [L:K + 4]
	STIW XP, ptr [L:K + 8]
	STIW XP, ptr [L:K + 12]
	
	ADDW L:K, 16
	SUBW J:I, 16
	JNZ .copy_loop
	
.copy_12:
	STIW XP, ptr [L:K + 0]
	STIW XP, ptr [L:K + 4]
	STIW XP, ptr [L:K + 8]
	JMP .free
	
.copy_8:
	STIW XP, ptr [L:K + 0]
	STIW XP, ptr [L:K + 4]
	JMP .free
	
.copy_4:
	STIW XP, ptr [L:K + 0]

.copy_0:
.free:
	; free original block
	PUSHW D:A
	
	ADDW B:C, ALLOCATED_HEAD_SIZE	; header -> contents
	PUSHW B:C
	PUSHW ptr [BP + 8]
	CALL free
	ADD SP, 8
	
	POPW D:A
	JMP .ret
	
.return_block:
	MOVW D:A, [BP + 12]

.ret:
	POPW XP
	POPW L:K
	POPW J:I
	POPW BP
	RET



; calloc(heap: allocator_t, n: u32): ptr
; Allocate n bytes on a heap, clearing them to zero and returning a pointer to it
calloc:
	PUSH BP
	MOVW BP, SP
	
	PUSHW J:I
	PUSHW L:K
	
	; get aligned size
	PUSHW ptr [BP + 12]
	CALL align
	ADD SP, 4
	
	MOVW L:K, D:A	; L:K = #bytes to clear
	
	; Allocate
	PUSHW ptr [BP + 12]
	PUSHW ptr [BP + 8]
	CALL malloc
	ADD SP, 8
	
	; did we actually allocate
	CMPW D:A, 0
	JE .ret
	
	; fill with zeros
	PUSHW D:A
	
	PUSHW L:K
	PUSHW J:I
	CALL clear
	ADD SP, 8
	
	POP D:A
	
.ret:
	POPW L:K
	POPW J:I
	POPW BP
	RET



; rcalloc(heap: allocator_t, block: ptr, n: u32): ptr
; re-allocates block to be n bytes, clearing new data first
rcalloc:
	PUSH BP
	MOVW BP, SP
	
	PUSHW J:I
	PUSHW L:K
	
	; get aligned size
	PUSHW ptr [BP + 16]
	CALL align
	ADD SP, 4
	
	MOVW L:K, D:A							; L:K = new size
	MOVW J:I, [BP + 12]						; J:I = original size
	MOVW J:I, [J:I + FREE_HEAD_SIZE_OFFS - ALLOCATED_HEAD_SIZE]
	
	; realloc block
	PUSHW ptr [BP + 16]
	PUSHW ptr [BP + 12]
	PUSHW ptr [BP + 8]
	CALL realloc
	ADD SP, 12
	
	; clear new bytes if applicable
	CMPW J:I, L:K
	JAE .no_clear
	
	SUBW L:K, J:I	; L:K = #bytes to clear = new size - original size
	ADDW J:I, D:A	; J:I = new bytes ptr = new block ptr + original size
	
	PUSHW D:A
	
	PUSHW L:K
	PUSHW J:I
	CALL clear
	ADD SP, 8
	
	POPW D:A
	
.no_clear:
	POPW L:K
	POPW J:I
	POPW BP
	RET



; clear(start: ptr, size: ptr): none
; Clears size bytes starting at start to zero
clear:
	PUSH BP
	MOVW BP, SP
	
	PUSHW J:I
	
	MOVW D:A, 0			; D:A = 0
	MOVW B:C, [BP + 8]	; B:C = ptr
	MOVW J:I, [BP + 12]	; J:I = #bytes
	
.clear_loop:
	CMPW J:I, 16
	JAE .clear_16
	JMP word [IP + I]
	
	dw @.clear_0
	dw 0
	dw @.clear_4
	dw 0
	dw @.clear_8
	dw 0
	dw @.clear_12
	dw 0

.clear_16:
	STIW B:C, D:A
	STIW B:C, D:A
	STIW B:C, D:A
	STIW B:C, D:A
	
	SUBW J:I, 16
	JNZ .clear_loop

.clear_12:	STIW B:C, D:A
.clear_8:	STIW B:C, D:A
.clear_4:	STIW B:C, D:A
.clear_0:
	
	POPW J:I
	POPW BP
	RET



; merge(lower: ptr, upper: ptr): none
; Merge blocks lower and upper
; Upper must be free. Lower may be free or allocated
merge:
	PUSH BP
	MOVW BP, SP
	
	PUSHW J:I
	
	; splice upper out of free list
	PUSH byte 0
	PUSHW ptr [BP + 12]
	CALL splice_out
	ADD SP, 5
	
	; add upper.size + head size to lower.size
	MOVW D:A, [BP + 12]
	MOVW B:C, [D:A + FREE_HEAD_SIZE_OFFS]	; B:C = upper.size
	AND CL, 0xFC
	ADDW B:C, ALLOCATED_HEAD_SIZE
	
	MOVW D:A, [BP + 8]
	ADDW B:C, [D:A + FREE_HEAD_SIZE_OFFS]	; get upadated size/status
	MOVW [D:A + FREE_HEAD_SIZE_OFFS], B:C	; place at lower.size
	
	; update footer/next header
	MOVW J:I, B:C									; J:I = size
	AND I, 0xFFFC
	ADDW D:A, J:I									; D:A = next block header - head size
	
	AND CL, 0x01									; CL = lower free?
	CMOVWZ [D:A + ALLOCATED_HEAD_SIZE - 4], J:I	; place footer if lower free
	SHL CL, 1										; CL = prev alloc/free bit
	OR [D:A + ALLOCATED_HEAD_SIZE], CL				; set prev alloc/free bit
	
	POPW J:I
	POPW BP
	RET



; splice_in(heap: allocator_t, block: ptr): none
; Splice block into the free list, marking it as free
splice_in:
	PUSH BP
	MOVW BP, SP
	
	PUSHW J:I
	PUSHW L:K
	
	MOVW J:I, [BP + 8]	; J:I = heap
	MOVW B:C, [BP + 12]	; B:C = block
	
	; splice into free list
	MOVW D:A, [J:I + ALLOC_FREE_LIST_HEAD_OFFS]	; D:A = free list head
	
	MOVW [D:A + FREE_HEAD_PREV_OFFS], B:C		; head.prev = block
	MOVW [B:C + FREE_HEAD_NEXT_OFFS], D:A		; block.next = head
	MOVW [J:I + ALLOC_FREE_LIST_HEAD_OFFS], B:C	; free list head = block
	
	; block.prev = ptr such that block.prev.next = free list head
	ADDW J:I, ALLOC_FREE_LIST_HEAD_OFFS - FREE_HEAD_NEXT_OFFS
	MOVW [B:C + FREE_HEAD_PREV_OFFS], J:I
	
	; mark as free in header
	MOV AL, 0xFE
	AND [B:C + FREE_HEAD_SIZE_OFFS], AL
	
	; mark as free in next block
	MOVW J:I, [B:C + FREE_HEAD_SIZE_OFFS]						; J:I = block size
	AND I, 0xFFFC
	MOVW L:K, B:C
	ADDW L:K, J:I												; L:K = upper ptr - head size
	
	MOV AL, 0xFD
	AND [L:K + FREE_HEAD_SIZE_OFFS + ALLOCATED_HEAD_SIZE], AL	; mark as free in next
	
	MOVW [L:K + ALLOCATED_HEAD_SIZE - 4], J:I					; place block size footer
	
	POPW L:K
	POPW J:I
	POPW BP
	RET



; splice_out(block: ptr, alloc: boolean): none
; Splice block out of the free list, marking it as allocated if appropriate
splice_out:
	PUSH BP
	MOVW BP, SP
	
	PUSHW J:I
	
	; Get size
	MOVW J:I, [BP + 8]						; J:I = block ptr
	MOVW D:A, [J:I + FREE_HEAD_SIZE_OFFS]	; D:A = size
	AND AL, 0xFC
	
	; Mark as allocated
	CMP byte [BP + 12], 0
	JE .no_alloc
	
	MOV BL, 0x01								; mark as allocated in header
	OR byte [J:I + FREE_HEAD_SIZE_OFFS], BL
	
	SHL BL, 1									; mark as allocated in next block
	ADDW D:A, J:I
	OR byte [D:A + ALLOCATED_HEAD_SIZE + FREE_HEAD_SIZE_OFFS], BL
	
.no_alloc:
	; Splice
	; block.prev.next = block.next
	; block.next.prev = block.prev
	MOVW D:A, [J:I + FREE_HEAD_NEXT_OFFS]	; D:A = block.next
	MOVW B:C, [J:I + FREE_HEAD_PREV_OFFS]	; B:C = block.prev
	MOVW [D:A + FREE_HEAD_PREV_OFFS], B:C	; block.next.prev = block.prev
	MOVW [B:C + FREE_HEAD_NEXT_OFFS], D:A	; block.prev.next = block.next
	
	POPW J:I
	POPW BP
	RET



; align(s: u32): u32
; Align a size to be at least 12 and a multiple of 4
align:
	PUSH BP
	MOVW BP, SP
	
	MOVW D:A, [BP + 8]	; D:A = s
	CMPW D:A, 12
	JL .minimum
	
	TST AL, 0x03		; is it aligned
	JZ .ok
	
	AND AL, 0xFC		; no - align
	ADDW D:A, 4
	
.ok:
	POP BP
	RET

.minimum:
	MOVW D:A, 12
	
	POP BP
	RET
