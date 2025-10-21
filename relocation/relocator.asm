
;
; Relocator
;

%include "fakeos/os.asm" as os

%define PROGRAM_INFO_CODE	0
%define PROGRAM_INFO_ENTRY	4

; program_info relocate(fn* file_supplier)
relocate:
	PUSH BP
	MOVW BP, SP
	
	
	
	POP BP
	RET
