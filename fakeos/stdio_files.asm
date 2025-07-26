
;
; FakeOS STDIO Files
; Handles input from file 0
;

; DiskBuffer controller
%define DISK_BASE_ADDR	0xF006_0000
%define DISK_RW_OFFS	0
%define DISK_FILE_OFFS	2
%define DISK_SECT_OFFS	4
%define DISK_BUFF_OFFS	8

%PRIVILAGED

; Buffer & State
file_index:		dp 0
buffer:		resb 1024



; none init_file()
; Reset the file
init_file:
	PUSH BP
	MOVW BP, SP
	
	MOVW D:A, 0
	MOVW [file_index], D:A
	
	; Read sector 0
	PUSH word 0
	CALL read_sector
	POP A
	
	POPW BP
	RET

; u8 read_byte()
; Reads 1 byte.
read_byte:
	PUSH BP
	MOVW BP, SP
	
	MOVW B:C, [file_index]	; get index in file
	MOV D, C				; get index in sector
	AND D, 0x3FF
	MOV AL, [buffer + D]	; get byte
	
	CMP AL, 0	; 0 = EOF = no increment
	JE .no_read
	
	INC C					; increment index in file
	ICC B
	MOVW [file_index], B:C
	
	INC D
	TST D, 0x400	; did we roll to a new sector?
	JZ .no_read
	
	; New sector.
	PUSH AL
	SHR B, 1		; shift right 10 to get sector
	RCR C, 1
	SHR B, 1
	RCR C, 1
	PUSH BL
	PUSH CH
	CALL read_sector
	POP C
	POP AL

.no_read:
	POPW BP
	RET

; none read_sector(u16 sector)
; Read the given sector into the buffer
read_sector:
	PUSH BP
	MOVW BP, SP
	
	MOVW D:A, DISK_BASE_ADDR
	
	; set buffer
	MOVW B:C, buffer
	MOVW [D:A + DISK_BUFF_OFFS], B:C
	
	; set file & sector
	MOV B, [BP + 8]
	MOV C, 0
	MOV [D:A + DISK_FILE_OFFS], C
	MOV [D:A + DISK_SECT_OFFS], B
	
	; read
	MOV AL, [D:A + DISK_RW_OFFS]
	
	POPW BP
	RET
