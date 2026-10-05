[bits 16]
[org 0x7E00]        ; El MBR del paso anterior cargó este sector en la dirección 0x7E00

%define ENDL  0x0D,0x0A

entry_point:
    jmp short start ; Salto corto (2 bytes) para saltar el bloque BPB
    nop             ; Relleno obligatorio de 1 byte (0x90)

; =============================================================================
;  BLOQUE DE PARÁMETROS DEL BIOS (BPB) - Obligatorio para sistemas FAT16
; =============================================================================
bpb:
.OEMName           db "MSDOS5.0"   ; Nombre del formateador (8 bytes)
.BytesPerSec       dw 0X0200       ; Bytes por sector (Estándar)
.SecsPerClust      db 0x04         ; Sectores por clúster (Ej: 2KB por clúster)
.ResSectors        dw 0x0004       ; Sectores reservados antes de la FAT (Normalmente 1: este VBR)
.FATs              db 0x02         ; Cantidad de tablas FAT (Por redundancia)
.RootDirEnts       dw 0x0200       ; Entradas máx en directorio raíz (Normalmente 512 en FAT16)
.Sectors           dw 0xA000       ; Sectores totales en el volumen (0 si es > 32MB)
.Media             db 0xF8         ; Descriptor de medio (0xF8 = Disco Duro Fijo)
.SecsPerFat        dw 0x0028       ; Tamaño de cada tabla FAT en sectores
.SecsPerTrack      dw 0x0020       ; Sectores por pista (Para direccionamiento CHS)
.Heads             dw 0x0002       ; Cabezas del disco (Para direccionamiento CHS)
.HiddenSectors     dd 0x0000003F   ; Sectores ocultos antes de la partición (Copiado del MBR)
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
    db 0x33,0xC0   ; xor ax, ax pero xor r, m/r y no xor r/m, r que es db 0x31,0xC0
    cli
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov si, msg_bienvenida
    call print_string

    ; ---- Si quiero leer la LBA de la FAT uso el siguiente codigo ----;
    ; LBA_FAT = HiddenSectors + ResSectors 
  ;  xor eax, eax
  ;  mov ax, [bpb.ResSectors]
  ;  add eax, [bpb.HiddenSectors]
  ;  mov [dap_packet.lba_value], eax
  ;  mov dword [dap_packet.lba_value+4], 0
  ;  mov ax, [bpb.SecsPerFat]
  ;  mov [dap_packet.block_count], ax
  ;  call cargar_fat_hd

    ; ---- LBA del directorio raíz (NUEVO) ----
    ; LBA_RootDir = HiddenSectors + ResSectors + (FATs * SecsPerFat)
    xor eax, eax
    mov al, [bpb.FATs]                  ; eax = cantidad de FATs (2)
    movzx ecx, word [bpb.SecsPerFat]    ; ecx = sectores por FAT (40)
    mul ecx                             ; eax = FATs * SecsPerFat  (ojo: mul de 32 bits usa edx:eax)
    add eax, [bpb.HiddenSectors]
    movzx ecx, word [bpb.ResSectors]
    add eax, ecx
    mov [dap_packet.lba_value], eax
    mov dword [dap_packet.lba_value+4], 0

    ; Tamaño del root dir en sectores = (RootDirEnts * 32) / BytesPerSec
    movzx eax, word [bpb.RootDirEnts]
    shl eax, 5                          ; * 32  (cada entrada = 32 bytes)
    movzx ecx, word [bpb.BytesPerSec]
    xor edx, edx
    div ecx                             ; eax = sectores que ocupa el root dir
    mov [dap_packet.block_count], ax

    call cargar_fat_hd                  ; misma rutina: solo lee lo que diga el DAP e imprime buffer

    call list_files
    jmp hang

; --- Recorre el root dir (ya cargado en 0x8000) e imprime nombre + cluster ---
list_files:
    mov di, buffer              ; primera entrada del root dir
    mov cx, [bpb.RootDirEnts]   ; cantidad total de entradas a revisar (512)

.next_entry:
    push cx

    cmp byte [di], 0x00
    je .done                    ; 0x00 = fin del directorio
    cmp byte [di], 0xE5
    je .skip                    ; entrada borrada

    mov al, [di+11]
    cmp al, 0x0F
    je .skip                    ; entrada de nombre largo (LFN), no es la real
    test al, 0x08
    jnz .skip                   ; etiqueta de volumen, no es un archivo

    ; --- Imprimir nombre (11 bytes crudos: "NOMBRE  EXT") ---
    mov si, di
    mov cx, 11
    call print_string_prefixed

    mov al, ' '
    mov ah, 0x0E
    int 0x10
    mov al, '-'
    int 0x10
    mov al, ' '
    int 0x10

    ; --- Imprimir cluster inicial en hex ---
    mov ax, [di+26]
    call print_hex16
    call print_ENDL

.skip:
    add di, 32                  ; siguiente entrada (32 bytes cada una)
    pop cx
    loop .next_entry
    ret

.done:
    pop cx
    ret

; --- Subrutina: Imprimir contenido de AX como 4 dígitos hexadecimales (reusa tu print_number existente)
print_hex16:
    push ax
    mov al, ah
    call print_number
    pop ax
    call print_number
    ret

; --- Subrutina: Convierte el número en Al en número ASCII y la imprime ---
print_number:
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

; --- Subrutina: Imprimir dígito hexadecimal (0-9, A-F) ---
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

; --- Subrutina: Imprimir cadena de longitud "CL" desde DS:SI  ---
print_string_prefixed:
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

; --- Subrutina: Imprimir para armar 0x que antecede al número en hexadecimal --
print_0x:
    push ax
    mov ax, 0x0E30  ; '0' en al y 0x0E en ah para imprimir
    int 0x10
    mov al, 'x'
    int 0x10
    pop ax
    ret

; --- Subrutina: Imprimir salto de línea (CR+LF) ---
print_ENDL:
    mov ax, 0x0E0D   ; 0x0E0D = carriage return y 0x0E para imprimir
    int 0x10
    mov al, 0x0A    ; 0x0A = line feed
    int 0x10
    ret

; --- Subrutina: Carga la FAT desde el disco duro usando LBA y lo copiaen buffer ---
cargar_fat_hd:
    mov ah, 0x42        ; Función 42h: Lectura extendida LBA
    mov dl, [bs.DriveNumber]        ; Unidad 0x80 = Primer disco rígido
    mov si, dap_packet  ; DS:SI debe apuntar a la estructura DAP en memoria
    
    int 0x13            ; Llamada a la BIOS
    jc error_lectura    ; Si el Carry Flag está activo, hubo error
    ret

error_lectura:
    mov si, buffer
    mov cl, 0xFF
    call print_string_prefixed
    call print_ENDL
    mov si, msg_error_disk
    call print_string
    jmp hang

; Subrutina: Detener el sistema (loop infinito)
hang:
    cli
    hlt
    jmp hang


align 4
dap_packet:
    .packet_size     db 0x10             ; Tamaño del paquete DAP (siempre 16 bytes o 0x10)
    .reserved        db 0x00             ; Reservado (siempre 0)
    .block_count     dw 0x0000           ; Cantidad de sectores a leer (ajusta según tu FAT)
    .transfer_buffer dd buffer           ; Desplazamiento destino (Offset) -> 0x0000
    .lba_value       dq 0x00000043       ; LBA inicial de la FAT (Sector de inicio en el disco, ej: 1)


msg_error_disk: db "Error al leer el disco", ENDL, 0
msg_bienvenida:     db "VBR", ENDL, 0

; Relleno estricto para alcanzar los 510 bytes
times 510-($-$$) db 0
; Firma de arranque obligatoria (Bytes 511 y 512)
boot_signature dw 0xAA55

buffer:


;***********************************;
; Reads a series of sectors         ;
; Parameters:                       ;
;   dl => bootdrive                 ;
;   ax => sectors count             ;
;   ebx => address to load to       ;
;   ecx => LBA address              ;
; Returns:                          ;
;   cf => set if error              ;
;***********************************;
ReadSectorsLBA:
    mov [LBA_Packet.block_count], ax
    mov [LBA_Packet.transfer_buffer], ebx
    mov [LBA_Packet.lba_value], ecx
    mov si, LBA_Packet
    mov ah, 0x42    ; Read sectors function
    int 0x13
    ret

align 4
LBA_Packet:
    .packet_size     db 0x10 ; use_transfer_64 ? 10h : 18h
    .reserved        db 0x00 ; always zero    
    .block_count      dw 0x00 ; number of sectors to read
    .transfer_buffer dd 0x00 ; address to load in ram
    .lba_value       dq 0x00 ; LBA addres value   


;****************************;
; Loads FAT table to FAT_SEG ;
;****************************;
LoadFAT:
    ; clear registers
    xor ax, ax
    xor ecx, ecx
    xor ebx, ebx
    xor dx, dx

    ; compute size of FAT and store in "ax" 
    mov ax, WORD [bpb.SecsPerFat]        ; sectors used by FAT

    ; compute location of FAT and store in "ecx"
    mov cx, WORD [bpb.ResSectors]
    add ecx, 2048                       ; temporary code for first partition

    ; read FAT into memory at FAT_SEG
    mov dl, [bs.DriveNumber]
    mov bx, WORD FAT_SEG
    call ReadSectorsLBA
    ret

FAT_SEG equ 0x1260

times 1024-($-$$) db 0
