
;
;	FakeOS
;	Include this file to include FakeOS
;

%include "ivt.asm" as ivt
%include "terminal.asm" as term
%include "handlers.asm" as hand
%include "privdma.asm" as dma
%include "stdio_files.asm" as stdio_files

%define CHAR_BUFFER_SIZE 16
%define CHAR_BACKSPACE 0x08
%define CHAR_NEWLINE 0x0A

%define TRUE_RESET_ADDR 0xF007_0000

%PRIVILAGED

stdio_state_input_echo:		db 1
stdio_state_include_ansi:	db 1
stdio_state_blocking:		db 1
stdio_state_use_file:		db 0
dma_heap_ptr:				dp 0


; none init(u32 dram_start, u32 dram_size)
;	Initializes FakeOS
init:
	PUSH BP
	MOVW BP, SP
	
	; init DMA
	PUSH ptr [BP + 12]
	PUSH ptr [BP + 8]
	CALL dma.init
	ADD SP, 8
	MOVW [dma_heap_ptr], D:A
	
	; init terminal
	CALL term.init_terminal
	
	; init stdin file
	CALL stdio_files.init_file
	
	; unprivilege user, enable interrupts
	; Setup an IRET to unprivilage the user without MPFing
	; BP and IP are in the right place already
	LEA D:A, [SP + 8]	; SP on return
	PUSHW D:A
	PUSH F
	PUSH word 0x0001	; PF = out-of-interrupt, unprivilaged, interrupts enabled
	IRET



; none enable_interrupts()
enable_interrupts:
	PUSH A
	MOV A, PF
	OR A, 1
	MOV PF, A
	POP A
	RET



; none disable_interrupts()
disable_interrupts:
	PUSH A
	MOV A, PF
	AND A, 0xFFFE
	MOV PF, A
	POP A
	RET



; 0000 Exit
syscall_exit:
	; Reset
	MOV [TRUE_RESET_ADDR], AL
	HLT



; 0001 Defer
syscall_defer:
	CALL enable_interrupts
	HLT
	CALL disable_interrupts
	RET



; 0010 Memory Allocate
syscall_memory_allocate:
	PUSHW B:C
	
	PUSHW B:C
	PUSHW ptr [dma_heap_ptr]
	CALL dma.malloc
	ADD SP, 8
	
	POPW B:C
	RET



; 0011 Clear Allocate
syscall_clear_allocate:
	PUSHW B:C
	
	PUSHW B:C
	PUSHW ptr [dma_heap_ptr]
	CALL dma.calloc
	ADD SP, 8
	
	POPW B:C
	RET



; 0012 Re-Allocate
syscall_re_allocate:
	PUSHW B:C
	
	PUSHW B:C
	PUSHW J:I
	PUSHW ptr [dma_heap_ptr]
	CALL dma.realloc
	ADD SP, 12
	
	POPW B:C
	RET



; 0013 Clear Re-Allocate
syscall_clear_re_allocate:
	PUSHW B:C
	
	PUSHW B:C
	PUSHW J:I
	PUSHW ptr [dma_heap_ptr]
	CALL dma.rcalloc
	ADD SP, 12
	
	POPW B:C
	RET



; 0014 Free
syscall_free:
	PUSHW B:C
	
	PUSHW B:C
	PUSHW ptr [dma_heap_ptr]
	CALL dma.free
	ADD SP, 8
	
	POPW B:C
	RET



; 0020 Open File
syscall_open_file:
	RET



; 0021 Close File
syscall_close_file:
	RET



; 0022 Read File
syscall_read_file:
	PUSH C
	PUSHW J:I
	PUSHW L:K
	
	; check special case file handles
	CMP D, 3
	JAE .not_special
	
	; only STDIN can be read
	CMP D, 0
	JNE .ret_err
	
	; what are we reading from
	CMP byte [stdio_state_use_file], 0
	JNZ read_file_file
	JMP read_file_terminal
	
.not_special:
.ret_err:
	MOVW D:A, 0
	MOV B, -1
	JMP .ret

.ret_ok:
	MOV B, 0
.ret:
	POPW L:K
	POPW J:I
	POP C
	RET



read_file_terminal:
	; read from terminal until buffer full or newline
	; D:A = count
	; B:C = max
	; J:I = output buffer
	; L:K = input buffer
	; [BP - 1] = nonzero if single character read -> characters like backspace get returned
	PUSHW BP
	MOVW BP, SP
	SUB SP, 1
	
	; record in [BP - 1] if we're reading exactly 1 character
	MOV A, 0
	MOV [BP - 1], AL
	
	CMP B, 0
	JNE .entry_size_not_1
	CMP C, 1
	JNE .entry_size_not_1
	
	MOV [BP - 1], CL

.entry_size_not_1:
	
	MOVW D:A, 0
	MOVW L:K, hand.char_buffer
.term_read_loop:
	; how many more
	CMP B, 0
	JNE .more_to_read
	CMP C, 0
	JZ .none_to_read

.more_to_read:
	; do we have chars to read
	CMP byte [hand.char_buf_available], 0
	JA .term_read_get
	
	; no
	CMP byte [stdio_state_blocking], 0
	JE .ret_ok
	CALL enable_interrupts
	HLT
	CALL disable_interrupts
	JMP .more_to_read
	
.term_read_get:
	; a char is available, read it
	PUSHW D:A
	
	MOVZ D, [hand.char_buf_read_index]
	MOV AL, [L:K + D]
	
	INC D		; inc read index
	CMP D, CHAR_BUFFER_SIZE
	CMOVAE D, 0
	MOV [hand.char_buf_read_index], DL
	
	DEC byte [hand.char_buf_available]	; decrement available input count
	
	; pre-echo special cases
	; when reading exactly 1 character, backspace is treated like a normal character
	CMP byte [BP - 1], 0
	JNE .pre_echo_not_backspace
	CMP AL, CHAR_BACKSPACE
	JE .pre_echo_is_backspace
	CMP AL, CHAR_BACKSPACE | 0x80
	JNE .pre_echo_not_backspace
	
.pre_echo_is_backspace:
	; backspace. don't echo if there's nothing to remove
	XCHGW D:A, [SP]
	CMP D, 0
	JNZ .pre_echo_backspace_has_stuff
	CMP A, 0
	JNZ .pre_echo_backspace_has_stuff
	
	; nothing.
	XCHGW D:A, [SP]
	JMP .read_no_echo

.pre_echo_backspace_has_stuff:
	XCHGW D:A, [SP]
	JMP .pre_echo_done

.pre_echo_not_backspace:
	
	; echo if applicable
.pre_echo_done:
	CMP byte [stdio_state_input_echo], 0
	JZ .read_no_echo
	
	; interrupts are not enabled for this opeartion as this code is not re-entrant
	PUSH A
	PUSHW B:C
	AND AL, 0x7F
	PUSH AL
	CALL term.send_character
	ADD SP, 1
	
	; ZF clear if was escape sequence and ansi not included in echo
	AND AL, [stdio_state_include_ansi]
	
	POPW B:C
	POP A
	
	JZ .read_no_echo
	
	; don't include char in input
	POPW D:A
	JMP .term_read_loop
	
.read_no_echo:
	CMP byte [stdio_state_input_echo], 0
	JZ .ignore_special
	AND AL, 0x7F
	
	; special cases
	; backspace isn't special when reading exactly 1 character
	CMP byte [BP - 1], 0
	JNE .read_not_backspace
	CMP AL, CHAR_BACKSPACE
	JNE .read_not_backspace
	
	; backspace. decrement buffer index
	POPW D:A
	
	; make sure there's stuff to delete
	CMP D, 0
	JNZ .term_backspace_has_stuff
	CMP A, 0
	JZ .term_read_loop

.term_backspace_has_stuff:	
	DECW J:I	; dec write addr
	DECW D:A	; dec amount read
	INCW B:C	; inc amount to read
	
	JMP .term_read_loop
	
.read_not_backspace:
	CMP AL, CHAR_NEWLINE
	JNE .read_not_newline
	
	; newline. stop reading additional stuff
	MOV [J:I], AL
	
	POPW D:A
	INCW D:A	; inc readd addr
	
	MOVW B:C, 0	; no more write
	JMP .term_read_loop

.read_not_newline:
.ignore_special:
	MOV [J:I], AL

	POPW D:A
	
	INCW J:I	; inc write addr
	INCW D:A	; inc amount read
	DECW B:C	; dec amount to read
	
	JMP .term_read_loop

.none_to_read:
	MOV B, 0
	
.ret:
	ADD SP, 1
	POPW BP
	JMP syscall_read_file.ret

.ret_ok:
	ADD SP, 1
	POPW BP
	JMP syscall_read_file.ret_ok



read_file_file:
	; read from file until buffer full, newline, or EOF
	; B:C = max
	; J:I = output buffer
	; L:K = count
	MOVW L:K, 0
	
.read_loop:
	; how many more
	CMP B, 0
	JNE .more_to_read
	CMP C, 0
	JE .none_to_read

.more_to_read:
	; Read byte to AL
	PUSHW B:C
	CALL stdio_files.read_byte
	POPW B:C
	
	; If EOF, don't include and just return
	CMP AL, 0
	JE .none_to_read
	
	; include in output
	MOV [J:I], AL
	INCW J:I
	INCW L:K
	DECW B:C
	
	; continue if not newline
	CMP AL, CHAR_NEWLINE
	JNE .read_loop

.none_to_read:
	MOV B, 0
	MOVW D:A, L:K
	JMP syscall_read_file.ret
	



; 0023 Write File
syscall_write_file:
	PUSH C
	PUSHW J:I
	PUSHW L:K
	
	; check special case file handles
	CMP D, 3
	JAE .not_special
	
	; only STDOUT can be written
	CMP D, 1
	JNE .ret_err
	
	; B:C = chars to print
	; J:I = buffer pointer
	; L:K = count of printed
	MOVW L:K, 0
.print_loop:
	; how many more
	CMP B, 0
	JNE .more_to_write
	CMP C, 0
	JE .none_to_write

.more_to_write:
	; send char
	CALL enable_interrupts	; allow interrupts during long operations
	PUSHW B:C
	PUSH byte [J:I]
	CALL term.send_character
	ADD SP, 1
	POPW B:C
	CALL disable_interrupts
	
	INCW J:I	; inc buffer ptr
	INCW L:K	; inc number printed
	DECW B:C	; dec number to print
	
	JMP .print_loop

.none_to_write:
	MOVW D:A, L:K
	MOV B, 0
	JMP .ret
	
.not_special:
.ret_err:
	MOVW D:A, 0
	MOV B, -1
	
.ret:
	POPW L:K
	POPW J:I
	POP C
	RET



; 0024 Seek File
syscall_seek_file:
	; D = file
	; C = mode
	; J:I = val
	PUSH C
	MOVW [stdio_files.file_index], J:I
	
	MOVW D:A, J:I
	SHR D, 1
	RCR A, 1
	SHR D, 1
	RCR A, 1
	PUSH DL
	PUSH AH
	CALL stdio_files.read_sector
	POP A
	
	MOVW D:A, J:I
	MOV B, 0
	POP C
	RET



; 0025 Get File Position
syscall_get_file_pos:
	RET



; 0026 Change File Attributes
syscall_change_file_attr:
	PUSH C
	
	; if stdin, change echo param
	CMP D, 3
	JAE .not_special
	
	CMP D, 0
	JNE .ret_err
	
	MOV CH, CL
	
	AND CL, 0x01	; bit 0 = echo on/off
	MOV [stdio_state_input_echo], CL
	
	SHR CH, 1
	MOV CL, CH
	NOT CL			; inverted for fast check
	AND CL, 0x01	; bit 1 = include escape sequences
	MOV [stdio_state_include_ansi], CL
	
	SHR CH, 1
	MOV CL, CH
	AND CL, 0x01	; bit 2 = blocking mode
	MOV [stdio_state_blocking], CL
	
	SHR CH, 1
	MOV CL, CH
	AND CL, 0x01	; bit 3 = input source
	MOV [stdio_state_use_file], CL
	
	JMP .ret

.not_special:
.ret_err:
	MOV A, -1

.ret:
	POP C
	RET



; UTILITIES
; Not 'official' syscalls
; Present until more general methods available
; The following three function bodies were in os.asm, but require privilage and are thus here
syscall_util_get_term_pos:
	MOV AL, [term.cursor_x]
	MOV AH, [term.cursor_y]
	RET
	
syscall_util_get_term_area:
	MOV DH, [term.min_y]
	MOV DL, [term.min_x]
	MOV AH, [term.max_y]
	MOV AL, [term.max_x]
	PSUB8 A, D
	PINC8 A
	RET
	
syscall_util_get_key_state:
	MOVZ A, [SP + 4]
	MOV AL, [hand.key_state_table + A]
	RET

syscall_util_get_millis:
	MOVW D:A, [hand.rtc_ticks]
	RET
