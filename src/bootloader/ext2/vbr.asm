
; =========================================================
; STAGE1 - VBR (512 bytes, se ejecuta en 0x0000:0x7E00
; porque asi lo carga el MBR de esta imagen)
; Único trabajo: leer el Stage2 (que vive en sectores fijos,
; justo después del VBR) y saltar a él.
; NO entiende ext2. Eso lo hace el Stage2.
;
; El MBR nos entrega en SI un puntero a la entrada de la
; tabla de particiones activa (ver mbr.asm parcheado). De ahi
; sacamos el LBA de inicio de la particion (offset 8, 4 bytes)
; y lo guardamos en PART_LBA_ADDR para que tambien lo use Stage2.
; =========================================================

    BITS 16
    ORG 0x7E00

%define ENDL  0x0D,0x0A

PART_LBA_ADDR equ 0x0500   ; direccion baja compartida con Stage2

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    ; SS:SP ya vienen configurados por el MBR (0x0000:0x7C00), no hace falta tocarlos
    sti

    ; --- Mostrar mensaje de bienvenida --- 
    mov di, msg_bienvenida
    call print_string

    mov [boot_drive], dl        ; BIOS/MBR dejan el drive de boot en DL

    ; ---- Leer LBA de inicio de la particion desde la entrada que nos paso el MBR ----
    mov eax, [si + 8]
    mov [PART_LBA_ADDR], eax

    ; ---- Cargar Stage2 usando INT 13h extendido (LBA) ----
    ; IMPORTANTE: Stage2 NO va en "inicio_particion + 1", porque ahi
    ; esta el superbloque de ext2 (byte 1024 = sector 2 relativo a la
    ; particion; el VBR solo deja libre 1 sector antes de chocar con el).
    ; En cambio, Stage2 vive en el "hueco" entre el MBR (sector 0) y el
    ; inicio de la particion (sector 63): sectores 1..62, que nadie usa.
    ; Por eso el LBA es un valor ABSOLUTO FIJO (no depende de donde
    ; arranque la particion).
    mov dword [dap_lba], 1
    mov si, dap
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    jc  disk_error

    ; Saltar a Stage2 (cargado en 0x0000:0x8000)
    jmp 0x0000:0x8000

disk_error:
    mov di, msg_err
    call print_string
    jmp halt_sistema

halt_sistema:
    hlt
    jmp halt_sistema

; --- Imprimir cadena terminada en 0 desde DS:DI ---
print_string:
    mov al, [di]
    inc di
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp print_string
.done:
    ret

boot_drive: db 0
msg_bienvenida:    db "Run VBR", ENDL, 0
msg_err:    db "Disk read error", ENDL, 0

; Disk Address Packet para INT 13h/AH=42h
dap:
    db 0x10          ; tamaño del DAP
    db 0              ; reservado
    dw 16             ; número de sectores a leer (Stage2 = 16 sectores = 8KB)
    dw 0x8000         ; offset destino
    dw 0x0000         ; segmento destino
dap_lba:
    dd 0              ; LBA inicial absoluto (se calcula en tiempo de ejecucion)
    dd 0              ; parte alta (no usada, discos <2TB)

    times 510-($-$$) db 0
    dw 0xAA55
