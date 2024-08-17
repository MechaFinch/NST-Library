
;
;	OS
;	NSTL wrapper functions for OS calls
;	This file imports fakeos for emulator use
;

%include "fakeos.asm" as fos

%define SYSCALL INT 0x20
%define OS_EXIT 		0x0001
%define OS_DEFER		0x0002
%define OS_MALLOC		0x0010
%define OS_CALLOC		0x0011
%define OS_REALLOC		0x0012
%define OS_RCALLOC		0x0013
%define OS_FREE			0x0014
%define OS_OPEN_FILE	0x0020
%define OS_CLOSE_FILE	0x0021
%define OS_READ_FILE	0x0022
%define OS_WRITE_FILE	0x0023
%define OS_SEEK_FILE	0x0024
%define OS_GET_FILE_POS	0x0025
%define OS_SET_FILE_ATT	0x0026
%define OS_STDIN		0
%define OS_STDOUT		1
%define OS_STDERR		2

errno: dp 1

; none init()
; Init the os
init:
	CALL fos.init
	RET

; none exit()
; Exits the program
exit:
	MOV A, OS_EXIT
	SYSCALL
	RET

; none defer()
; Defers execution
defer:
	MOV A, OS_DEFER
	SYSCALL
	RET

; ptr malloc(u32 n)
; Allocate n bytes of memory
malloc:
	PUSHW BP
	MOVW BP, SP
	
	MOVW C:D, [BP + 8]
	MOV A, OS_MALLOC
	SYSCALL
	
	POPW BP
	RET

; ptr calloc(u32 n)
; Allocate n bytes of memory & clear them to zero
calloc:
	PUSHW BP
	MOVW BP, SP
	
	MOVW C:D, [BP + 8]
	MOV A, OS_CALLOC
	SYSCALL
	
	POPW BP
	RET

; ptr realloc(ptr block, u32 n)
; Re-allocate a block to n bytes.
realloc:
	PUSHW BP
	MOVW BP, SP
	PUSHW J:I
	
	MOVW C:D, [BP + 12]
	MOVW J:I, [BP + 8]
	MOV A, OS_REALLOC
	SYSCALL
	
	POPW J:I
	POPW BP
	RET

; ptr rcalloc(ptr block, u32 n)
; Re-allocate and clear a block
rcalloc:
	PUSHW BP
	MOVW BP, SP
	PUSHW J:I
	
	MOVW C:D, [BP + 12]
	MOVW J:I, [BP + 8]
	MOV A, OS_RCALLOC
	SYSCALL
	
	POPW J:I
	POPW BP
	RET

; none free(ptr block)
; Free a block
free:
	PUSHW BP
	MOVW BP, SP
	
	MOVW C:D, [BP + 8]
	MOV A, OS_FREE
	SYSCALL
	
	POPW BP
	RET

; u16 open_file(u16 flags, u16 name_len, ptr name_ptr)
; Returns handle ID or -1
; Sets _os.errno
open_file:
	PUSHW BP
	MOVW BP, SP
	PUSHW J:I
	
	MOVW C:D, [BP + 8]
	MOVW J:I, [BP + 12]
	MOV A, OS_OPEN_FILE
	SYSCALL
	MOVS [errno], B
	
	POPW J:I
	POPW BP
	RET

; none close_file(u16 handle_id)
close_file:
	PUSHW BP
	MOVW BP, SP
	
	MOV D, [BP + 8]
	MOV A, OS_CLOSE_FILE
	SYSCALL
	
	POPW BP
	RET

; u32 read_file(u16 handler_id, u32 buffer_length, ptr buffer_ptr) 
; Returns number of bytes read
; Sets _os.errno
read_file:
	PUSHW BP
	MOVW BP, SP
	PUSHW J:I
	
	MOV D, [BP + 8]
	MOVW B:C, [BP + 10]
	MOVW J:I, [BP + 14]
	MOV A, OS_READ_FILE
	SYSCALL
	MOVS [errno], B
	
	POPW J:I
	POPW BP
	RET

; u32 write_file(u16 handle_id, u32 buffer_length, ptr buffer_ptr)
; Returns number of bytes written
; Sets _os.errno
write_file:
	PUSHW BP
	MOVW BP, SP
	PUSHW J:I
	
	MOV D, [BP + 8]
	MOVW B:C, [BP + 10]
	MOVW J:I, [BP + 14]
	MOV A, OS_WRITE_FILE
	SYSCALL
	MOVS [errno], B
	
	POPW J:I
	POPW BP
	RET

; u32 seek_file(u16 handle_id, u16 flags, u32 value)
; Returns resulting position in file
; Sets _os.errno
seek_file:
	PUSHW BP
	MOVW BP, SP
	PUSHW J:I
	
	MOVW C:D, [BP + 8]
	MOVW J:I, [BP + 12]
	MOV A, OS_SEEK_FILE
	SYSCALL
	MOVS [errno], B
	
	POPW J:I
	POPW BP
	RET

; none get_file_pos(u16 handle_id, u32 pointer read_ptr, u32 pointer write_ptr)
; Returns head positions in argument pointers
; Sets _os.errno
get_file_pos:
	PUSHW BP
	MOVW BP, SP
	PUSHW J:I
	
	MOV D, [BP + 8]
	MOV A, OS_GET_FILE_POS
	SYSCALL
	
	MOVS [errno], I
	MOVW J:I, [BP + 10]
	MOVW [J:I], D:A
	MOVW J:I, [BP + 14]
	MOVW [J:I], B:C
	
	POPW J:I
	POPW BP
	RET

; none change_file_attr(u16 handle_id, u16 flags)
; Sets _os.errno
change_file_attr:
	PUSHW BP
	MOVW BP, SP
	
	MOVW C:D, [BP + 8]
	MOV A, OS_SET_FILE_ATT
	SYSCALL
	MOVS [errno], A
	
	POPW BP
	RET
