[org 0x00] ; bootloader offset
    mov bp, 0x9000 ; set the stack
    mov sp, bp

    mov bx, MSG_REAL_MODE
    call print ; This will be written after the BIOS messages
    mov ah, 0x03    ; set cursor position
    mov bh, 0x0     ; page number
    int 0x10        ; call video interrupt to set cursor position
    mov [col], dl
    mov [row], dh
; Aqui comienza el codigo que me dice donde esta el cursor o puntero para poder referenciar a esa posicion en pantalla, lo guardo en col y row para luego usarlo en modo protegido    
    mov ah,0x03
    mov bh,0x0
    int 0x10
    call print_nl
    ;mov dx, 0x12fe
    mov dx, cs ; we will print the code segment value, which should be 0x0000 in real mode
    call print_hex
    call print_nl
    mov dx, ds ; we will print the data segment value, which should also be 0x0000 in real mode
    call print_hex
; Fin del código de impresión, ahora vamos a cargar la GDT y luego cambiar a modo protegido
    call switch_to_pm
    jmp $ ; this will actually never be executed

%include "./src/include/print16.asm"
%include "./src/include/32bit-gdt.asm"
%include "./src/include/print32.asm"
%include "./src/include/32bit-switch.asm"

[bits 32]
BEGIN_PM: ; after the switch we will get here
    mov ebx, MSG_PROT_MODE
    mov edx, 0x0
    mov dl, [col]
    mov dh, [row]
    call print_string_pm ; Note that this will be written at the top left corner
    jmp $

MSG_REAL_MODE db "Started in 16-bit real mode", 0
MSG_PROT_MODE db "Loaded 32-bit protected mode", 0
col db 0
row db 0
