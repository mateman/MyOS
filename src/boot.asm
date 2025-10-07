org 0x7c00
bits 16

%define ENDL  0x0D,0x0A

start:
	jmp main

; Prints a string to the screen
; Params:
;		ds:si points to string
puts:
	; save registers we will modify
	push si
	push ax

.loop:
	lodsb	;loads next charcter in al
	or al, al ;verify if next character is null?
	jz .done   ; if al is 0 then end print
	mov ah, 0x0e  ; write character in TTY mode
	mov bh, 0  ; page number (text modes)
	int 0x10   ; call bios interrupt
    jmp .loop

.done:
	pop ax
	pop si
	ret

main:
	; setup data segments
	mov ax,0	; can't write ds/es directly
	mov ds, ax
	mov es, ax
	
	; setup stack
	mov ss, ax
	mov sp, 0x7c00   ; stack grows downwards from where we are loaded in memory

	; print message
	mov si, msg_hello
	call puts
	hlt

.halt:
	jmp .halt

	
msg_hello: db 'MyOS Bootloader', ENDL, 'Run...', ENDL, 0

times 510-($-$$) db 0
dw 0AA55h





