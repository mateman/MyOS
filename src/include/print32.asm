[bits 32] ; using 32-bit protected mode

; this is how constants are defined
VIDEO_MEMORY equ 0xb8000
WHITE_ON_BLACK equ 0x0f ; the color byte for each character

print_string_pm:
    pusha
        mov al, dh              ; Al = file actual
        xor ah,ah               ; Limpiar Ah
        mov cx, 160             ; 160 bytes por fila (80 columnas * 2 bytes por caracter)
        mul cx                  ; Ax = fila * 160 (desplazamiento de fila)

        ; Calcular el desplazamiento de columna
        xor dh,dh               ; Limpiar Dh
        shl dx, 1               ; DX = columna * 2 (cada carácter ocupa 2 bytes)
add dx, ax                  ; Dx = desplazamiento total (fila * 160 + columna * 2)
    add edx, VIDEO_MEMORY ; Edx = dirección de memoria de video para el carácter
print_string_pm_loop:
    mov al, [ebx] ; [ebx] is the address of our character
    mov ah, WHITE_ON_BLACK

    cmp al, 0 ; check if end of string
    je print_string_pm_done

    mov [edx], ax ; store character + attribute in video memory
    add ebx, 1 ; next char
    add edx, 2 ; next video memory position

    jmp print_string_pm_loop

print_string_pm_done:
    popa
    ret
