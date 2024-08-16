
;
;	FakeOS Interrupt Vector Table
;

%include "handlers.asm" as h

%org 0

reset:		dp null				; 0x00	0
nmi:		dp null				; 0x01	1
keyup:		dp h.keyup			; 0x02	2
keydown:	dp h.keydown		; 0x03	3
			repeat 4, dp null	; 		4-7
segfault:	dp h.segfault		; 0x08	8
			repeat 3, dp null	; 		9-11
rtc:		dp h.rtc			; 0x0C	12
			repeat 3, dp null	; 		13-15
gpf:		dp h.gpf			; 0x10	16
mpf:		dp h.mpf			; 0x11	17
			repeat 14, dp null	;		18-31
syscall:	dp h.syscall		; 0x20	32

padding:	repeat (255 - 32), dp null

null:
	IRET
