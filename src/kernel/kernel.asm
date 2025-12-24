org 0x0
bits 16


; Code goes in the text section
SECTION .TEXT

main:
	; setup data segments
	mov ax,cs	; can't write ds/es directly
	mov ds, ax
	mov es, ax
	mov ax, 0
	; print message
	mov si, hello
    call puts
	
puts:
	; save registers we will modify
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
	int 0x00
	pop ax
	ret

; Define variables in the data section
SECTION .DATA
	hello:     db 'Hello world!',0



