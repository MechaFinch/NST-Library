
;
;	FakeOS
;	Include this file to include FakeOS
;

%include "memory/dma.asm" as dma

%include "ivt.asm" as ivt
%include "terminal.asm" as term
%include "handlers.asm" as hand

%define CHAR_BUFFER_SIZE 16
%define CHAR_BACKSPACE 0x08
%define CHAR_NEWLINE 0x0A

%define TRUE_RESET_ADDR 0xF007_0000

stdio_state_input_echo:		db 1
stdio_state_include_ansi:	db 1
stdio_state_blocking:		db 1



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
	
	; init terminal
	CALL term.init_terminal
	
	; unprivilege user, enable interrupts
	MOV PF, 0x0001
	
	POP BP
	RET



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
	PUSH C
	
	PUSH C
	PUSH D
	CALL dma.malloc
	ADD SP, 4
	
	POP C
	RET



; 0011 Clear Allocate
syscall_clear_allocate:
	PUSH C
	
	PUSH C
	PUSH D
	CALL dma.calloc
	ADD SP, 4
	
	POP C
	RET



; 0012 Re-Allocate
syscall_re_allocate:
	PUSH C
	
	PUSH C
	PUSH D
	PUSH J
	PUSH I
	CALL dma.realloc
	ADD SP, 8
	
	POP C
	RET



; 0013 Clear Re-Allocate
syscall_clear_re_allocate:
	PUSH C
	
	PUSH C
	PUSH D
	PUSH J
	PUSH I
	CALL dma.rcalloc
	ADD SP, 8
	
	POP C
	RET



; 0014 Free
syscall_free:
	PUSH C
	
	PUSH C
	PUSH D
	CALL dma.free
	ADD SP, 4
	
	POP C
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
	PUSH I
	PUSH J
	PUSH K
	PUSH L
	
	; check special case file handles
	CMP D, 3
	JAE .not_special
	
	; only STDIN can be read
	CMP D, 0
	JNE .ret_err
	
	; read from terminal until buffer full or newline
	; D:A = count
	; B:C = max
	; J:I = output buffer
	; L:K = input buffer
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
	PUSH D
	PUSH A
	
	MOVZ D, [hand.char_buf_read_index]
	MOV AL, [L:K + D]
	
	INC D		; inc read index
	CMP D, CHAR_BUFFER_SIZE
	CMOVAE D, 0
	MOV [hand.char_buf_read_index], DL
	
	DEC byte [hand.char_buf_available]	; decrement available input count
	
	; pre-echo special cases
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
	PUSH B
	PUSH C
	PUSH AL
	CALL term.send_character
	ADD SP, 1
	
	; ZF clear if was escape sequence and ansi not included in echo
	AND AL, [stdio_state_include_ansi]
	
	POP C
	POP B
	POP A
	
	JZ .read_no_echo
	
	; don't include char in input
	POP A
	POP D
	JMP .term_read_loop
	
.read_no_echo:
	CMP byte [stdio_state_input_echo], 0
	JZ .ignore_special
	AND AL, 0x7F
	
	; special cases
	CMP AL, CHAR_BACKSPACE
	JNE .read_not_backspace
	
	; backspace. decrement buffer index
	POP A
	POP D
	
	; make sure there's stuff to delete
	CMP D, 0
	JNZ .term_backspace_has_stuff
	CMP A, 0
	JZ .term_read_loop

.term_backspace_has_stuff:	
	DEC I	; dec write addr
	DCC J
	
	DEC A	; dec amount read
	DCC D
	
	INC C	; inc amount to read
	ICC B
	
	JMP .term_read_loop
	
.read_not_backspace:
	CMP AL, CHAR_NEWLINE
	JNE .read_not_newline
	
	; newline. stop reading additional stuff
	MOV [J:I], AL
	
	POP A
	POP D
	
	INC A	; inc readd addr
	ICC D	; write addr not inc as no more write
	
	MOVW B:C, 0	; no more write
	JMP .term_read_loop

.read_not_newline:
.ignore_special:
	MOV [J:I], AL

	POP A
	POP D
	
	INC I		; inc write addr
	ICC J
	
	INC A		; inc amount read
	ICC D
	
	DEC C		; dec amount to read
	DCC B
	
	JMP .term_read_loop

.none_to_read:
	MOV B, 0
	JMP .ret
	
.not_special:
.ret_err:
	MOVW D:A, 0
	MOV B, -1

.ret_ok:
	MOV B, 0
.ret:
	POP L
	POP K
	POP J
	POP I
	POP C
	RET



; 0023 Write File
syscall_write_file:
	PUSH C
	PUSH I
	PUSH J
	PUSH K
	PUSH L
	
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
	PUSH B
	PUSH C
	PUSH byte [J:I]
	CALL term.send_character
	ADD SP, 1
	POP C
	POP B
	CALL disable_interrupts
	
	INC I	; inc buffer ptr
	ICC J
	
	INC K	; inc number printed
	ICC L
	
	DEC C	; dec number to print
	DCC B
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
	POP L
	POP K
	POP J
	POP I
	POP C
	RET



; 0024 Seek File
syscall_seek_file:
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
	
	JMP .ret

.not_special:
.ret_err:
	MOV A, -1

.ret:
	POP C
	RET
