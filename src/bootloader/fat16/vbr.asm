[bits 16]
[org 0x7E00]        ; El MBR del paso anterior cargo este sector en la direccion 0x7E00

%define ENDL  0x0D,0x0A

entry_point:
    jmp short start ; Salto corto (2 bytes) para saltar el bloque BPB
    nop             ; Relleno obligatorio de 1 byte (0x90)

; =============================================================================
;  BLOQUE DE PARAMETROS DEL BIOS (BPB) - Obligatorio para sistemas FAT16
;  OJO: este bloque tiene que mantener EXACTAMENTE el mismo layout/tamano
;  (62 bytes) que el que genera mkfs.fat, porque el instalador solo copia
;  con dd los primeros 3 bytes + todo lo que hay desde el byte 62 en
;  adelante. Los valores de aca adentro son solo para que NASM calcule
;  bien los offsets de [bpb.Campo] - nunca se graban en el disco real.
; =============================================================================
bpb:
.OEMName           db "MSDOS5.0"   ; Nombre del formateador (8 bytes)
.BytesPerSec       dw 0X0200       ; Bytes por sector
.SecsPerClust      db 0x04         ; Sectores por cluster
.ResSectors        dw 0x0004       ; Sectores reservados antes de la FAT
.FATs              db 0x02         ; Cantidad de tablas FAT
.RootDirEnts       dw 0x0200       ; Entradas max en directorio raiz
.Sectors           dw 0xA000       ; Sectores totales (0 si es > 32MB)
.Media             db 0xF8         ; Descriptor de medio
.SecsPerFat        dw 0x0028       ; Tamano de cada tabla FAT en sectores
.SecsPerTrack      dw 0x0020       ; No usado con LBA
.Heads             dw 0x0002       ; No usado con LBA
.HiddenSectors     dd 0x0000003F   ; LBA de inicio de particion (lo pisa mkfs -h)
.HugeSectors       dd 0x00000000   ; Sectores totales si Sectors era 0

; --- Extension del BPB para FAT16 ---
bs:
.DriveNumber        db 0x80         ; 0x80 = Primer HDD
.Unused             db 0x00
.BootSignature      db 0x29
.VolumeID           dd 0x12345678
.VolumeLabel        db "MI_SISTEMA " ; 11 bytes
.FileSystemType     db "FAT16###"    ; 8 bytes

; =============================================================================
;  CODIGO DE EJECUCION
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
    ; LBA_FAT = HiddenSectors + ResSectors  (16 bits alcanza de sobra:
    ; el disco tiene bien menos de 65536 sectores en total)
    mov ax, [bpb.ResSectors]
    add ax, [bpb.HiddenSectors]
    mov cx, [bpb.SecsPerFat]
    mov bx, fat_buffer
    call leer_lba

    ; ---- 2) LBA del Root Dir = HiddenSectors + ResSectors + FATs*SecsPerFat
    movzx ax, byte [bpb.FATs]
    mov cx, [bpb.SecsPerFat]
    mul cx                              ; ax = FATs * SecsPerFat
    add ax, [bpb.HiddenSectors]
    add ax, [bpb.ResSectors]
    mov [root_dir_lba], ax

    ; Tamano del root dir en sectores = (RootDirEnts * 32) / BytesPerSec
    mov ax, [bpb.RootDirEnts]
    shl ax, 5
    mov cx, [bpb.BytesPerSec]
    xor dx, dx
    div cx
    mov [root_dir_sectors_qty], ax

    ; data_sector_start = LBA_RootDir + root_dir_sectors_qty (cluster 2)
    mov ax, [root_dir_lba]
    add ax, [root_dir_sectors_qty]
    mov [data_sector_start], ax

    mov ax, [root_dir_lba]
    mov cx, [root_dir_sectors_qty]
    mov bx, root_dir_buffer
    call leer_lba

    ; ---- 3) Buscar KERNEL.BIN en el root dir ----
    call buscar_archivo         ; deja [cluster_actual] seteado si lo encuentra

    ; ---- 4) Seguir la cadena de clusters y cargarlo en memoria ----
    call cargar_archivo
    jmp hang

; =============================================================================
;  BUSQUEDA DE ARCHIVO POR NOMBRE EN EL ROOT DIR YA CARGADO
; =============================================================================
buscar_archivo:
    mov di, root_dir_buffer
    mov cx, [bpb.RootDirEnts]

.next:
    push cx
    cmp byte [di], 0x00
    je .no_encontrado             ; 0x00 = fin del directorio
    cmp byte [di], 0xE5
    je .skip                      ; entrada borrada

    mov al, [di+11]                ; atributos
    test al, 0x08
    jnz .skip                      ; etiqueta de volumen
    cmp al, 0x0F
    je .skip                       ; entrada de nombre largo (LFN)

    push di
    mov si, kernel_filename
    mov cx, 11
    repe cmpsb
    pop di
    je .encontrado

.skip:
    add di, 32
    pop cx
    loop .next

.no_encontrado:
    mov si, msg_err
    call print_string
    jmp hang

.encontrado:
    pop cx
    mov ax, [di+26]                 ; cluster inicial
    mov [cluster_actual], ax
    ret

; =============================================================================
;  CARGA DEL ARCHIVO SIGUIENDO LA CADENA DE CLUSTERS EN LA FAT
; =============================================================================
KERNEL_SEG equ 0x1000

cargar_archivo:
    mov ax, KERNEL_SEG
    mov es, ax
    xor bx, bx

.siguiente_cluster:
    ; LBA = data_sector_start + (cluster - 2) * SecsPerClust
    mov ax, [cluster_actual]
    sub ax, 2
    movzx cx, byte [bpb.SecsPerClust]
    mul cx
    add ax, [data_sector_start]
    call leer_lba                    ; ax=LBA, cx=SecsPerClust, es:bx=destino

    ; avanzar el puntero es:bx lo que se acaba de leer
    movzx ax, byte [bpb.SecsPerClust]
    mul word [bpb.BytesPerSec]
    add bx, ax
    jnc .sin_overflow
    mov ax, es
    add ax, 0x1000
    mov es, ax
.sin_overflow:

    ; siguiente cluster en la FAT ya cargada en fat_buffer
    mov ax, [cluster_actual]
    shl ax, 1                        ; cada entrada FAT16 = 2 bytes
    mov si, fat_buffer
    add si, ax
    mov ax, [si]
    mov [cluster_actual], ax

    cmp ax, 0xFFF8                   ; fin de cadena
    jb .siguiente_cluster
    jmp 0x1000:0x0000                     ; saltar a kernel cargado
    ret

; --- Imprimir cadena terminada en 0 desde DS:SI ---
print_string:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp print_string
.done:
    ret

hang:
    cli
    hlt
    jmp hang

; =============================================================================
;  LECTURA GENERICA DE SECTORES POR LBA (INT 13h AH=42h)
;  Entrada: AX = LBA (16 bits), CX = cantidad de sectores, ES:BX = destino
; =============================================================================
leer_lba:
    movzx eax, ax
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
    mov si, msg_err
    call print_string
    jmp hang

dap_packet:
    .packet_size     db 0x10
    .reserved        db 0x00
    .block_count     dw 0
    .transfer_buffer dw 0, 0
    .lba_value       dq 0

; =============================================================================
;  CADENAS Y VARIABLES
; =============================================================================
msg_bienvenida:    db "Run VBR", ENDL, 0
kernel_filename:  db "KERNEL  BIN"   ; 8+3, sin punto
msg_err:          db "Err", ENDL, 0  ; sirve para disco y archivo no encontrado

root_dir_lba:         dw 0
root_dir_sectors_qty: dw 0
data_sector_start:    dw 0
cluster_actual:       dw 0

; Relleno estricto para alcanzar los 510 bytes
times 510-($-$$) db 0
; Firma de arranque obligatoria (Bytes 511 y 512)
boot_signature dw 0xAA55

; =============================================================================
;  DIRECCIONES DE BUFFERS EN MEMORIA (constantes, no ocupan bytes del VBR)
;  root_dir_buffer: 0x8000-0xBFFF (32 sectores)
;  fat_buffer:      0xC000-0x10FFF (40 sectores)
; =============================================================================
root_dir_buffer equ 0x8000
fat_buffer      equ 0xC000
