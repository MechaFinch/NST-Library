
;
; Testing Shell
; Terminal via stdio testing
;

%include "fakeos.asm" as os
%include "terminal.asm" as term

%define SYSCALL INT 0x20

%define OS_EXIT		0x0000
%define OS_DEFER	0x0001

%define OS_MALLOC	0x0010
%define OS_CALLOC	0x0011
%define OS_REALLOC	0x0012
%define OS_RCALLOC	0x0013
%define OS_FREE		0x0014

%define OS_FILE_OPEN	0x0020
%define OS_FILE_CLOSE	0x0021
%define OS_FILE_READ	0x0022
%define OS_FILE_WRITE	0x0023
%define OS_FILE_SEEK	0x0024
%define OS_FILE_GETPOS	0x0025

%define OS_STDIN	0
%define OS_STDOUT	1
%define OS_STDERR	2

string_hello:	db "Hello, World!", 0x0A, ">"
string_hello_after:
string_gohome:	db 0x1B, "[H"
string_gohome_after:
string_goin:	db 0x1B, "[1;1f"
string_goin_after:

input_buffer:	resb 320 / 8

entry:
	; get OS running
	CALL os.init
.start:
	
	; hello world
	MOV A, OS_FILE_WRITE
	MOV D, OS_STDOUT
	MOVW B:C, string_hello_after - string_hello
	MOVW J:I, string_hello
	SYSCALL
	
	; echo characters
.loop:
	; read from stdin
	MOV A, OS_FILE_READ
	MOVW B:C, 320 / 8
	MOV D, OS_STDIN
	MOVW J:I, input_buffer
	SYSCALL
	
	; did we actually get anything
	CMP A, 0
	JZ .loop
	
	; remove trailing newline if present
	MOV D, 0
	CMP byte [J:I + A - 1], 0x0A
	CMOVE D, 1
	SUB A, D
	MOV D, 0
	
	CMP A, 0
	JZ .toin
	
	MOVW L:K, D:A
	
	; move to first line
	MOV A, OS_FILE_WRITE
	MOVW B:C, string_gohome_after - string_gohome
	MOV D, OS_STDOUT
	MOVW J:I, string_gohome
	SYSCALL
	
	; echo
	MOV A, OS_FILE_WRITE
	MOVW B:C, L:K
	MOV D, OS_STDOUT
	MOVW J:I, input_buffer
	SYSCALL
	
	; move to input line
.toin:
	MOV A, OS_FILE_WRITE
	MOVW B:C, string_goin_after - string_goin
	MOV D, OS_STDOUT
	MOVW J:I, string_goin
	SYSCALL
	
	JMP .loop
