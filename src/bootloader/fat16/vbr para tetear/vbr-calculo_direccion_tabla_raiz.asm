[bits 16]
[org 0x7E00]        ; El MBR del paso anterior cargó este sector en la dirección 0x7E00

%define ENDL  0x0D,0x0A

entry_point:
    jmp short start ; Salto corto (2 bytes) para saltar el bloque BPB
    nop             ; Relleno obligatorio de 1 byte (0x90)

; =============================================================================
;  BLOQUE DE PARÁMETROS DEL BIOS (BPB) - Obligatorio para sistemas FAT16
; =============================================================================
bpbOEMName           db "MSDOS5.0"   ; Nombre del formateador (8 bytes)
bpbBytesPerSec       dw 0X0200       ; Bytes por sector (Estándar)
bpbSecsPerClust      db 0x04         ; Sectores por clúster (Ej: 2KB por clúster)
bpbResSectors        dw 0x0004       ; Sectores reservados antes de la FAT (Normalmente 1: este VBR)
bpbFATs              db 0x02         ; Cantidad de tablas FAT (Por redundancia)
bpbRootDirEnts       dw 0x0200       ; Entradas máx en directorio raíz (Normalmente 512 en FAT16)
bpbSectors           dw 0xA000       ; Sectores totales en el volumen (0 si es > 32MB)
bpbMedia             db 0xF8         ; Descriptor de medio (0xF8 = Disco Duro Fijo)
bpbSecsPerFat        dw 0x0028       ; Tamaño de cada tabla FAT en sectores
bpbSecsPerTrack      dw 0x0020       ; Sectores por pista (Para direccionamiento CHS)
bpbHeads             dw 0x0002       ; Cabezas del disco (Para direccionamiento CHS)
bpbHiddenSectors     dd 0x00000000   ; Sectores ocultos antes de la partición (Copiado del MBR)
bpbHugeSectors       dd 0x00000000   ; Sectores totales si bpbSectors era 0 (> 32MB)

; --- Extensión del BPB para FAT16 ---
bsDriveNumber        db 0x80         ; Número de unidad de disco (0x80 = Primer HDD)
bsUnused             db 0x00         ; Reservado
bsBootSignature      db 0x29         ; Firma de arranque extendida
bsVolumeID           dd 0x12345678   ; Número de serie del volumen
bsVolumeLabel        db "MI_SISTEMA " ; Etiqueta del volumen (11 bytes)
bsFileSystemType     db "FAT16###"   ; Tipo de sistema de archivos (8 bytes)

; =============================================================================
;  CÓDIGO DE EJECUCIÓN (AQUÍ CAE EL JUMP DEL PRINCIPIO)
; =============================================================================

start:
    ; Configuración segura de registros de segmento
    db 0x33,0xC0   ; xor ax, ax pero xor r, m/r y no xor r/m, r que es db 0x31,0xC0
    cli
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00                  ; Configura la pila
    sti

    ; Mensaje de bienvenida del VBR
    mov si, msg_bienvenida
    call print_string
    ; Leer el BPB del sector actual (ya cargado en memoria) y mostrar sus campos
    ; Posicion de la raiz de la FAT16 = (bpbResSectors + bpbFATs * bpbSecsPerFat) * bpbBytesPerSec + Posicion de vbr (0x7E00)
    
    ; Calcular la posición de la raíz del sistema de archivos
    mov bx, [bpbResSectors]         ; Sectores reservados
    mov al, [bpbFATs]               ; Número de tablas FAT
    mul byte [bpbSecsPerFat]        ; Sectores por tabla FAT                          ; ax = bpbResSectors * bpbSecsPerFat
    add ax, bx                      ; ax = bpbResSectors + (bpbFATs * bpbSecsPerFat)
    mul word [bpbBytesPerSec]       ; ax = (bpbResSectors + bpbFATs * bpbSecsPerFat) * bpbBytesPerSec
    add ax, 0x7E00                  ; ax = Posición de la raíz del sistema de archivos
    adc dx, 0                       ; Suma de acarreo si es necesario
    mov si, ax                      ; SI apunta a la raíz del sistema de archivos   
    push ax
    mov al, dh
    call print_0x
    call print_number
    mov al, dl
    call print_number
    pop dx
    mov al, dh
    call print_number
    mov al, dl
    call print_number
    call print_ENDL
    jmp hang


print_number:
    ; Convierte el número en AX a cadena decimal y la imprime
    push ax
    push cx
    mov cl, al
    mov ah, 0x0E
    and al, 0xF0
    shr al, 4
    call print_digit
    mov al, cl
    and al, 0x0F
    call print_digit
    pop cx
    pop ax
    ret

print_digit:
   cmp al, 10
    jl .skip
    sub al, 10
    add al, 'A'
    jmp .print
.skip:
    add al, '0'
.print:
    int 0x10
    ret

print_0x:
    push ax
    mov al, '0'
    mov ah, 0x0E
    int 0x10
    mov al, 'x'
    int 0x10
    pop ax
    ret

print_string_prefixed:
    ; Imprime una cadena de longitud CL desde DS:SI
    push cx
    push si
.print_loop:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    loop .print_loop
.done:
    pop si
    pop cx
    ret

print_ENDL:
    mov ah, 0x0E
    mov al, 0x0D
    int 0x10
    mov al, 0x0A
    int 0x10
    ret

hang:
    cli
    hlt
    jmp hang

; --- Subrutina: Imprimir Cadena en Pantalla ---
print_string:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp print_string
.done:
    ret

msg_bienvenida:     db "VBR", ENDL, 0

; Relleno estricto para alcanzar los 510 bytes
times 510-($-$$) db 0
; Firma de arranque obligatoria (Bytes 511 y 512)
dw 0xAA55

buffer:
