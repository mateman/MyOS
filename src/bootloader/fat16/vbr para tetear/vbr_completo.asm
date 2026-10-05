[bits 16]
[org 0x7E00]        ; El MBR del paso anterior cargó este sector en la dirección 0x7E00

%define ENDL  0x0D,0x0A

entry_point:
    jmp short start ; Salto corto (2 bytes) para saltar el bloque BPB
    nop             ; Relleno obligatorio de 1 byte (0x90)

; =============================================================================
;  BLOQUE DE PARÁMETROS DEL BIOS (BPB) - Obligatorio para sistemas FAT16
;  OJO: este bloque tiene que mantener EXACTAMENTE el mismo layout/tamaño
;  (62 bytes) que el que genera mkfs.fat, porque tu instalador solo copia
;  con dd los primeros 3 bytes + todo lo que hay desde el byte 62 en
;  adelante. Los valores de acá adentro son solo para que NASM calcule
;  bien los offsets de [bpb.Campo] - nunca se graban en el disco real.
; =============================================================================
bpb:
.OEMName           db "MSDOS5.0"   ; Nombre del formateador (8 bytes)
.BytesPerSec       dw 0X0200       ; Bytes por sector (Estándar)
.SecsPerClust      db 0x04         ; Sectores por clúster
.ResSectors        dw 0x0004       ; Sectores reservados antes de la FAT
.FATs              db 0x02         ; Cantidad de tablas FAT
.RootDirEnts       dw 0x0200       ; Entradas máx en directorio raíz
.Sectors           dw 0xA000       ; Sectores totales en el volumen (0 si es > 32MB)
.Media             db 0xF8         ; Descriptor de medio (0xF8 = Disco Duro Fijo)
.SecsPerFat        dw 0x0028       ; Tamaño de cada tabla FAT en sectores
.SecsPerTrack      dw 0x0020       ; Sectores por pista (CHS, no usado con LBA)
.Heads             dw 0x0002       ; Cabezas del disco (CHS, no usado con LBA)
.HiddenSectors     dd 0x0000003F   ; LBA de inicio de partición (lo pisa mkfs -h)
.HugeSectors       dd 0x00000000   ; Sectores totales si bpbSectors era 0 (> 32MB)

; --- Extensión del BPB para FAT16 ---
bs:
.DriveNumber        db 0x80         ; Número de unidad de disco (0x80 = Primer HDD)
.Unused             db 0x00         ; Reservado
.BootSignature      db 0x29         ; Firma de arranque extendida
.VolumeID           dd 0x12345678   ; Número de serie del volumen
.VolumeLabel        db "MI_SISTEMA " ; Etiqueta del volumen (11 bytes)
.FileSystemType     db "FAT16###"   ; Tipo de sistema de archivos (8 bytes)

; =============================================================================
;  CÓDIGO DE EJECUCIÓN (AQUÍ CAE EL JUMP DEL PRINCIPIO)
; =============================================================================

start:
    db 0x33,0xC0        ; xor ax, ax
    cli
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov si, msg_bienvenida
    call print_string

    ; ---- 1) Cargar la FAT completa en fat_buffer ----
    xor eax, eax
    mov ax, [bpb.ResSectors]
    add eax, [bpb.HiddenSectors]
    movzx ecx, word [bpb.SecsPerFat]
    mov bx, fat_buffer
    call leer_lba

    ; ---- 2) Calcular LBA del Root Dir y cargarlo en root_dir_buffer ----
    ; LBA_RootDir = HiddenSectors + ResSectors + (FATs * SecsPerFat)
    xor eax, eax
    mov al, [bpb.FATs]
    movzx ecx, word [bpb.SecsPerFat]
    mul ecx                             ; eax = FATs * SecsPerFat
    add eax, [bpb.HiddenSectors]
    movzx ecx, word [bpb.ResSectors]
    add eax, ecx                        ; eax = LBA absoluto del root dir
    mov [root_dir_lba], eax

    ; Tamaño del root dir en sectores = (RootDirEnts * 32) / BytesPerSec
    movzx eax, word [bpb.RootDirEnts]
    shl eax, 5
    movzx ecx, word [bpb.BytesPerSec]
    xor edx, edx
    div ecx
    mov [root_dir_sectors_qty], ax

    ; data_sector_start = LBA_RootDir + root_dir_sectors_qty (donde arranca el cluster 2)
    mov ax, [root_dir_lba]
    add ax, [root_dir_sectors_qty]
    mov [data_sector_start], ax

    mov eax, [root_dir_lba]
    movzx ecx, word [root_dir_sectors_qty]
    mov bx, root_dir_buffer
    call leer_lba

    ; ---- 3) Buscar KERNEL.BIN en el root dir ----
    call buscar_archivo         ; deja [cluster_actual] seteado si lo encuentra

    ; ---- 4) Seguir la cadena de clusters y cargarlo en memoria ----
    call cargar_archivo

    mov si, msg_ok
    call print_string
    jmp hang

; =============================================================================
;  BÚSQUEDA DE ARCHIVO POR NOMBRE EN EL ROOT DIR YA CARGADO
; =============================================================================
buscar_archivo:
    mov di, root_dir_buffer
    mov cx, [bpb.RootDirEnts]

.next:
    push cx
    cmp byte [di], 0x00
    je .no_encontrado            ; 0x00 = fin del directorio
    cmp byte [di], 0xE5
    je .skip                     ; entrada borrada

    mov al, [di+11]              ; byte de atributos
    test al, 0x08
    jnz .skip                    ; etiqueta de volumen, no es un archivo
    cmp al, 0x0F
    je .skip                     ; entrada de nombre largo (LFN)

    push di
    mov si, kernel_filename
    mov cx, 11
    repe cmpsb
    pop di
    je .encontrado

.skip:
    add di, 32                   ; siguiente entrada (32 bytes cada una)
    pop cx
    loop .next

.no_encontrado:
    mov si, msg_no_encontrado
    call print_string
    jmp hang

.encontrado:
    pop cx
    mov ax, [di+26]               ; cluster inicial (offset 26-27 de la entrada)
    mov [cluster_actual], ax
    ret

; =============================================================================
;  CARGA DEL ARCHIVO SIGUIENDO LA CADENA DE CLUSTERS EN LA FAT
; =============================================================================
KERNEL_SEG equ 0x1000             ; segmento destino, lejos del VBR (0x1000:0000)

cargar_archivo:
    mov ax, KERNEL_SEG
    mov es, ax
    xor bx, bx                    ; ES:BX = puntero de escritura

.siguiente_cluster:
    ; LBA = data_sector_start + (cluster - 2) * SecsPerClust
    mov ax, [cluster_actual]
    sub ax, 2
    xor cx, cx
    mov cl, [bpb.SecsPerClust]
    mul cx
    add ax, [data_sector_start]
    movzx eax, ax

    movzx ecx, byte [bpb.SecsPerClust]   ; sectores a leer = 1 cluster
    call leer_lba

    ; avanzar el puntero ES:BX lo que se acaba de leer
    xor ax, ax
    mov al, [bpb.SecsPerClust]
    mul word [bpb.BytesPerSec]     ; dx:ax = bytes de este cluster
    add bx, ax
    jnc .sin_overflow
    mov ax, es
    add ax, 0x1000                 ; cruzó el límite de 64KB, avanzar segmento
    mov es, ax
.sin_overflow:

    ; buscar el siguiente cluster en la FAT ya cargada en fat_buffer
    mov ax, [cluster_actual]
    shl ax, 1                      ; cada entrada FAT16 = 2 bytes
    mov si, fat_buffer
    add si, ax
    mov ax, [si]
    mov [cluster_actual], ax

    cmp ax, 0xFFF8                 ; 0xFFF8-0xFFFF = fin de cadena
    jae .fin_archivo
    jmp .siguiente_cluster

.fin_archivo:
    ret

; =============================================================================
;  RUTINAS DE IMPRESIÓN
; =============================================================================
print_number:
    ; Convierte el número en AL a cadena hexadecimal y la imprime
    push ax
    push cx
    mov cl, al
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
    add al, 0x37 ; Convierte a letra A-F para valores mayores a 9
    jmp .print
.skip:
    add al, 0x30 ; Convierte a dígito ASCII 0x30=='0'
.print:
    mov ah, 0x0E
    int 0x10
    ret

print_string_prefixed:
    ; Imprime una cadena de longitud CL desde DS:SI
    push cx
    push si
    push ax
.print_loop:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    loop .print_loop
.done:
    pop ax
    pop si
    pop cx
    ret

; --- Subrutina: Imprimir Cadena en Pantalla (terminada en 0) ---
print_string:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp print_string
.done:
    ret

print_0x:
    push ax
    mov ax, 0x0E30  ; '0' en al y 0x0E en ah para imprimir
    int 0x10
    mov al, 'x'
    int 0x10
    pop ax
    ret

print_ENDL:
    mov ax, 0x0E0D   ; 0x0E0D = carriage return y 0x0E para imprimir
    int 0x10
    mov al, 0x0A     ; 0x0A = line feed
    int 0x10
    ret

hang:
    cli
    hlt
    jmp hang

; =============================================================================
;  LECTURA GENÉRICA DE SECTORES POR LBA (INT 13h AH=42h)
;  Entrada: EAX = LBA absoluto, ECX = cantidad de sectores, ES:BX = destino
; =============================================================================
leer_lba:
    mov [dap_packet.lba_value], eax
    mov dword [dap_packet.lba_value+4], 0
    mov [dap_packet.block_count], cx
    mov [dap_packet.transfer_buffer], bx
    mov [dap_packet.transfer_buffer+2], es

    mov ah, 0x42
    mov dl, [bs.DriveNumber]
    mov si, dap_packet
    int 0x13
    jc error_lectura
    ret

error_lectura:
    mov si, msg_error_disk
    call print_string
    jmp hang

align 4
dap_packet:
    .packet_size     db 0x10   ; Tamaño del paquete DAP (siempre 16 bytes)
    .reserved        db 0x00
    .block_count     dw 0      ; se pisa siempre antes de usar
    .transfer_buffer dw 0, 0   ; offset, segmento - se pisan siempre antes de usar
    .lba_value       dq 0      ; se pisa siempre antes de usar

; =============================================================================
;  CADENAS DE TEXTO Y VARIABLES DE TRABAJO
; =============================================================================
kernel_filename:    db "KERNEL  BIN"    ; 8+3 sin punto, relleno con espacios

msg_bienvenida:      db "VBR", ENDL, 0
msg_error_disk:      db "Error al leer el disco", ENDL, 0
msg_no_encontrado:   db "KERNEL.BIN no encontrado", ENDL, 0
msg_ok:              db "KERNEL.BIN cargado en 0x1000:0000", ENDL, 0

root_dir_lba:         dd 0
root_dir_sectors_qty: dw 0
data_sector_start:    dw 0
cluster_actual:       dw 0

; Relleno estricto para alcanzar los 510 bytes
times 510-($-$$) db 0
; Firma de arranque obligatoria (Bytes 511 y 512)
boot_signature dw 0xAA55

; =============================================================================
;  DIRECCIONES DE BUFFERS EN MEMORIA
;  Son constantes de dirección (equ), NO reservan bytes en el archivo del
;  VBR - la memoria ahí ya existe (RAM libre), simplemente le decimos al
;  código dónde escribir. Se llenan en tiempo de ejecución con los reads.
;  root_dir_buffer: 0x8000 a 0xBFFF (32 sectores = 0x4000 bytes)
;  fat_buffer:      0xC000 a 0x10FFF (40 sectores = 0x5000 bytes)
; =============================================================================
root_dir_buffer equ 0x8000
fat_buffer      equ 0xC000
