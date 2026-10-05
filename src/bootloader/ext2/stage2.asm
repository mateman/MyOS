; =========================================================
; STAGE2 - Parser ext2 (real mode, cargado en 0x0000:0x8000)
; Busca /kernel.bin en el directorio raiz y lo carga en 0x1000:0000
;
; Reescrito para evitar juegos de push/pop propensos a error:
; los valores intermedios se guardan en variables de memoria
; en vez de en la pila o en registros que deban sobrevivir a
; llamadas a INT 13h (que puede pisar SI/DI/AX/DX/BX).
; =========================================================

    BITS 16
    ORG 0x8000

; ---------------------------------------------------------
; Offsets de estructuras ext2
; ---------------------------------------------------------
SB_MAGIC_OFF        equ 56
SB_LOG_BLKSZ_OFF    equ 24
SB_INODES_PER_GRP   equ 40
SB_FIRST_DATA_BLK   equ 20
SB_REV_LEVEL_OFF    equ 76
SB_INODE_SIZE_OFF   equ 88
; NOTA: se lee s_inode_size dinamicamente (ver abajo), pero se sigue
; asumiendo que la tabla de descriptores de grupo (BGDT) entra en UN
; solo bloque. Para volumenes con muchos grupos hay que leer varios
; bloques de la BGDT.

BGD_INODE_TABLE_OFF equ 8       ; dentro de cada descriptor de 32 bytes

INODE_BLOCK_OFF     equ 40      ; offset de i_block[15] dentro del inodo

ROOT_INODE          equ 2
KERNEL_LOAD_SEG     equ 0x1000  ; kernel.bin se carga en 0x1000:0000

PART_LBA_ADDR       equ 0x0500  ; LBA de inicio de la particion (lo deja Stage1)

; ---------------------------------------------------------
; Buffers de trabajo (fuera del rango de codigo, en el mismo segmento)
; ---------------------------------------------------------
SUPERBLOCK   equ 0x9000   ; 1024 bytes
BGDTABLE     equ 0x9400   ; tabla de descriptores de grupo (1 bloque)
BLOCKBUF     equ 0xA000   ; buffer generico para 1 bloque de datos
INODEBUF     equ 0xB000   ; buffer para 1 bloque de la tabla de inodos

; ---------------------------------------------------------
; Punto de entrada
; ---------------------------------------------------------
entry_stage2:
    mov [boot_drive], dl

    ; ---- 1. Leer el superbloque ----
    ; Esta al byte 1024 DESDE EL INICIO DE LA PARTICION (sector 2
    ; relativo a ella), asi que hay que sumarle el LBA de inicio
    ; de la particion para obtener el LBA absoluto del disco.
    mov eax, [PART_LBA_ADDR]
    add eax, 2
    mov ecx, 2                 ; 2 sectores = 1024 bytes
    mov bx, SUPERBLOCK
    call read_sectors

    mov ax, [SUPERBLOCK + SB_MAGIC_OFF]
    cmp ax, 0xEF53
    jne fatal_superblock

    ; ---- 2. Tamano de bloque y sectores por bloque ----
    mov eax, [SUPERBLOCK + SB_LOG_BLKSZ_OFF]
    mov cl, al
    mov eax, 1024
    shl eax, cl                 ; block_size = 1024 << s_log_block_size
    mov [block_size], eax
    shr eax, 9                  ; / 512 = sectores por bloque
    mov [sectors_per_block], eax

    ; ---- 2b. Tamano de inodo: dinamico si s_rev_level >= 1 (siempre
    ;          el caso con mkfs moderno), sino fijo en 128 (revision 0) ----
    mov eax, [SUPERBLOCK + SB_REV_LEVEL_OFF]
    or eax, eax
    jnz .dynamic_inode_size
    mov dword [inode_size], 128
    jmp .inode_size_done
.dynamic_inode_size:
    movzx eax, word [SUPERBLOCK + SB_INODE_SIZE_OFF]
    mov [inode_size], eax
.inode_size_done:

    ; ---- 3. Leer la tabla de descriptores de grupo (BGDT) ----
    ; Vive en el bloque (first_data_block + 1)
    mov eax, [SUPERBLOCK + SB_FIRST_DATA_BLK]
    inc eax
    call block_to_lba
    mov ecx, [sectors_per_block]
    mov bx, BGDTABLE
    call read_sectors

    ; ---- 4. Cargar el inodo raiz (inodo 2) ----
    mov eax, ROOT_INODE
    call load_inode              ; copia el inodo a 'cur_inode'

    ; ---- 5. Buscar "kernel.bin" en el directorio raiz ----
    call find_in_directory        ; si lo encuentra: CF=0, [target_inode] = numero
    jc fatal_notfound

    ; ---- 6. Cargar el inodo del kernel y sus bloques de datos ----
    mov eax, [target_inode]
    call load_inode
    call load_file_blocks

    ; ---- 7. Saltar al kernel ----
    mov dl, [boot_drive]
    jmp KERNEL_LOAD_SEG:0x0000

; ---------------------------------------------------------
; Tres mensajes de error distintos, para poder diagnosticar
; exactamente cual de las tres cosas fallo.
; ---------------------------------------------------------
fatal_disk:
    mov si, msg_disk
    jmp print_halt

fatal_superblock:
    mov si, msg_superblock
    jmp print_halt

fatal_notfound:
    mov si, msg_notfound
    ; cae en print_halt

print_halt:
.pr:
    lodsb
    or al, al
    jz .h
    mov ah, 0x0E
    int 0x10
    jmp .pr
.h:
    hlt
    jmp .h

msg_disk:       db "ext2: error leyendo el disco (INT 13h fallo)", 0
msg_superblock: db "ext2: superbloque invalido (magic != 0xEF53, revisar offset/particion)", 0
msg_notfound:   db "ext2: kernel.bin NO existe en el directorio raiz", 0
boot_drive: db 0

; ---------------------------------------------------------
; Variables de estado (memoria, no pila)
; ---------------------------------------------------------
block_size:         dd 0
sectors_per_block:  dd 0
inode_size:         dd 0
cur_inode:          times 128 db 0
target_inode:       dd 0

tmp_group:          dd 0
tmp_index:          dd 0
tmp_table_block:    dd 0
tmp_inode_off:      dd 0    ; offset en bytes del inodo dentro del bloque leido

dir_blk_idx:        dw 0
dir_remaining:      dw 0

kernel_blk_idx:     dw 0
kernel_write_off:   dw 0

KERNEL_NAME:        db "kernel.bin"
KERNEL_NAME_LEN     equ 10

; ---------------------------------------------------------
; block_to_lba: EAX = numero de bloque ext2 (relativo a la particion)
;               -> EAX = LBA absoluto del disco
; ---------------------------------------------------------
block_to_lba:
    push edx
    mov edx, [sectors_per_block]
    mul edx
    add eax, [PART_LBA_ADDR]
    pop edx
    ret

; ---------------------------------------------------------
; load_inode: EAX = numero de inodo -> copia 128 bytes a 'cur_inode'
;
;   group  = (inodo-1) / inodes_per_group
;   index  = (inodo-1) % inodes_per_group
;   tabla  = BGDT[group].bg_inode_table   (bloque)
;   offset_bytes = index * 128
;   bloque_abs   = tabla + (offset_bytes / block_size)
;   offset_local = offset_bytes % block_size
;
; Limitacion: asume que la BGDT completa entra en un solo bloque
; (valido para volumenes chicos/medianos con pocos grupos).
; ---------------------------------------------------------
load_inode:
    dec eax
    xor edx, edx
    mov ecx, [SUPERBLOCK + SB_INODES_PER_GRP]
    div ecx
    mov [tmp_group], eax
    mov [tmp_index], edx

    ; direccion del descriptor de grupo = BGDTABLE + group*32
    mov ebx, [tmp_group]
    shl ebx, 5
    add ebx, BGDTABLE
    mov eax, [ebx + BGD_INODE_TABLE_OFF]
    mov [tmp_table_block], eax

    ; offset en bytes del inodo dentro de la tabla de inodos
    ; (usa el inode_size real, no un valor fijo)
    mov eax, [tmp_index]
    mul dword [inode_size]       ; edx:eax = index * inode_size (edx se descarta,
                                  ; se vuelve a poner en 0 en la siguiente division)

    xor edx, edx
    mov ecx, [block_size]
    div ecx                      ; eax = bloque relativo dentro de la tabla
                                  ; edx = offset dentro de ese bloque
    mov [tmp_inode_off], edx

    add eax, [tmp_table_block]   ; bloque absoluto que contiene el inodo
    call block_to_lba
    mov ecx, [sectors_per_block]
    mov bx, INODEBUF
    call read_sectors

    ; copiar 128 bytes desde INODEBUF+offset hacia cur_inode
    mov si, INODEBUF
    add si, word [tmp_inode_off]  ; offset < block_size, entra en 16 bits
    mov di, cur_inode
    mov cx, 128
    rep movsb
    ret

; ---------------------------------------------------------
; find_in_directory: recorre los bloques directos de 'cur_inode'
; (debe ser un directorio) buscando KERNEL_NAME.
; Encontrado -> CF=0, [target_inode] = numero de inodo.
; No encontrado / fin de bloques -> CF=1.
; ---------------------------------------------------------
find_in_directory:
    mov word [dir_blk_idx], 0
.next_block:
    mov bx, [dir_blk_idx]
    cmp bx, 12                    ; solo bloques directos (0..11)
    jae .not_found

    mov si, cur_inode
    add si, INODE_BLOCK_OFF
    shl bx, 2
    add si, bx
    mov eax, [si]                 ; numero de bloque de este directorio
    or eax, eax
    jz .not_found

    call block_to_lba
    mov ecx, [sectors_per_block]
    mov bx, BLOCKBUF
    call read_sectors

    mov di, BLOCKBUF
    mov ax, [block_size]
    mov [dir_remaining], ax
.entry_loop:
    cmp word [dir_remaining], 0
    jbe .block_done

    mov eax, [di]                 ; numero de inodo de la entrada
    movzx bx, byte [di+6]         ; name_len
    or eax, eax
    jz .skip_entry                ; entrada vacia (inodo 0)

    cmp bx, KERNEL_NAME_LEN
    jne .skip_entry

    push di
    push si
    add di, 8                     ; puntero al nombre dentro de la entrada
    mov si, KERNEL_NAME
    mov cx, KERNEL_NAME_LEN
    repe cmpsb
    pop si
    pop di
    jne .skip_entry

    mov [target_inode], eax
    clc
    ret

.skip_entry:
    movzx ax, word [di+4]         ; rec_len
    or ax, ax
    jz .block_done
    sub [dir_remaining], ax
    add di, ax
    jmp .entry_loop

.block_done:
    inc word [dir_blk_idx]
    jmp .next_block

.not_found:
    stc
    ret

; ---------------------------------------------------------
; load_file_blocks: lee los bloques directos de 'cur_inode'
; (ya recargado con el inodo del kernel) a KERNEL_LOAD_SEG:0000
;
; Limitacion: solo maneja los 12 punteros directos. Alcanza para
; archivos de hasta 12*block_size (48 KB con bloques de 4 KB).
; Para kernels mas grandes hay que resolver ademas el indirecto
; simple en i_block[12] (un bloque lleno de punteros de 4 bytes).
; ---------------------------------------------------------
load_file_blocks:
    mov ax, KERNEL_LOAD_SEG
    mov es, ax
    mov word [kernel_blk_idx], 0
    mov word [kernel_write_off], 0
.next:
    mov bx, [kernel_blk_idx]
    cmp bx, 12
    jae .done

    mov si, cur_inode
    add si, INODE_BLOCK_OFF
    shl bx, 2
    add si, bx
    mov eax, [si]
    or eax, eax
    jz .done

    call block_to_lba
    mov ecx, [sectors_per_block]
    mov bx, [kernel_write_off]    ; offset dentro de ES (KERNEL_LOAD_SEG)
    call read_sectors_es

    mov ax, [block_size]
    add [kernel_write_off], ax
    inc word [kernel_blk_idx]
    jmp .next
.done:
    ret

; ---------------------------------------------------------
; read_sectors:    EAX=LBA absoluto, ECX=cant. sectores, BX=offset
;                  destino dentro de DS (que se mantiene en 0)
; read_sectors_es: igual, pero el offset BX es dentro de ES
;                  (usado para cargar el kernel en KERNEL_LOAD_SEG)
; Ambas usan INT 13h/AH=42h (LBA extendido).
; ---------------------------------------------------------
read_sectors:
    mov [dap.lba], eax
    mov [dap.count], cx
    mov [dap.off], bx
    mov ax, ds
    mov [dap.seg], ax
    jmp do_read

read_sectors_es:
    mov [dap.lba], eax
    mov [dap.count], cx
    mov [dap.off], bx
    mov ax, es
    mov [dap.seg], ax

do_read:
    mov si, dap
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    jc fatal_disk
    ret

dap:
    db 0x10
    db 0
.count: dw 0
.off:   dw 0
.seg:   dw 0
.lba:   dd 0
        dd 0

    times 8192-($-$$) db 0   ; padding a 16 sectores (8 KB), igual que en Stage1
