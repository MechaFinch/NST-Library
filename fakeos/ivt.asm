
;
;	FakeOS Interrupt Vector Table
;

%include "handlers.asm" as h

%PRIVILAGED
%org 0

reset:		dp null				; 0x00	0
nmi:		dp null				; 0x01	1
keyup:		dp h.keyup			; 0x02	2
keydown:	dp h.keydown		; 0x03	3
			repeat 4, dp null	; 		4-7
gpf:		dp h.gpf			; 0x08	8
mpf:		dp h.mpf			; 0x08	9
			repeat 2, dp null	; 		10-11
rtc:		dp h.rtc			; 0x0C	12
diverr:		dp h.diverr			; 0x0D	13
segfault:	dp h.segfault		; 0x0E	14
de:			dp h.de				; 0x0F	15
			repeat 16, dp null	;		16-31
syscall:	dp h.syscall		; 0x20	32

padding:	repeat (255 - 32), dp null

null:
	IRET
