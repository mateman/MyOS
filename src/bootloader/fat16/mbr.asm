[bits 16]           ; El procesador inicia en Modo Real de 16 bits
[org 0x7C00]        ; El BIOS siempre carga el MBR en la dirección 0x7C00

%define ENDL  0x0D,0x0A

start:
    cli             ; Desactiva interrupciones temporalmente
    xor ax, ax      ; Limpia el registro AX (AX = 0)
    mov ds, ax      ; Configura Segmento de Datos en 0
    mov es, ax      ; Configura Segmento Extra en 0
    mov ss, ax      ; Configura Segmento de Pila en 0
    mov sp, 0x7C00  ; Coloca la pila justo debajo del MBR
    sti             ; Reactiva interrupciones

    ; 1. BUSCAR LA PARTICIÓN ACTIVA
    mov si, table_particiones ; SI apunta al inicio de la tabla
    mov cx, 4                 ; El bucle revisará las 4 particiones primarias

bucle_buscar:
    mov al, [si]              ; Lee el primer byte (indicador de arranque)
    test al, 0x80             ; ¿El bit 7 está activo? (0x80 = Activa/Bootable)
    jnz particion_encontrada  ; Si es activa, salta a cargarla
    add si, 16                ; Si no, avanza 16 bytes (tamaño de cada entrada)
    loop bucle_buscar         ; Repite hasta revisar las 4

    ; Si ninguna es activa, muestra error y se detiene
    mov si, msg_no_activa
    call imprimir_texto
    jmp halt_sistema

particion_encontrada:
    ; 2. CARGAR EL PRIMER SECTOR (VBR) DE LA PARTICIÓN ACTIVA
    ; Usamos la Interrupción 0x13 del BIOS (Función 0x02: Leer Sectores)
    mov ah, 0x02              ; Función BIOS: Leer sectores del disco
    mov al, 1                 ; Cantidad de sectores a leer (1 sector = 512 bytes)
    
    ; Dirección de destino en memoria (ES:BX -> 0x0000:0x7E00)
    ; Lo cargamos justo después del MBR para no sobrescribirlo
    mov bx, 0x7E00            
    
    ; Dirección CHS del sector de inicio (se extrae de la tabla de particiones)
    mov dh, [si + 1]          ; Cabeza (Head)
    mov cl, [si + 2]          ; Sector y Cilindro alto
    mov ch, [si + 3]          ; Cilindro bajo
    ; DL contiene el número de unidad (ya lo pasa el BIOS automáticamente, ej: 0x80)

    int 0x13                  ; Llama a la interrupción del BIOS
    jc error_lectura          ; Si el flag de acarreo (Carry) se activa, hubo error

    ; 3. TRANSFERIR EL CONTROL AL SISTEMA OPERATIVO
    ; Saltamos a la dirección de memoria donde cargamos el VBR (0x7E00)
    ; El VBR se encargará de cargar el resto del Kernel del SO
    mov si, msg_hello
    call imprimir_texto
    jmp 0x0000:0x7E00

error_lectura:
    mov si, msg_error_disco
    call imprimir_texto

halt_sistema:
    hlt                       ; Detiene la CPU
    jmp halt_sistema          ; Bucle infinito de seguridad

; --- FUNCIÓN AUXILIAR PARA IMPRIMIR EN PANTALLA ---
imprimir_texto:
    mov ah, 0x0E              ; Función BIOS: Telepuntero (escribir caracter)
.bucle_caracter:
    lodsb                     ; Carga el siguiente byte de SI en AL e incrementa SI
    cmp al, 0                 ; ¿Llegamos al final de la cadena (0)?
    je .fin
    int 0x10                  ; Interrupción de video del BIOS
    jmp .bucle_caracter
.fin:
    ret
; --- MENSAJES DE Bienvenida ---
msg_hello: db 'MyOS Bootloader', ENDL, 0 ;'Run...', ENDL, 0

; --- MENSAJES DE ERROR ---
msg_no_activa    db "No hay particion activa.", 13, 10, 0
msg_error_disco  db "Error al leer el disco.", 13, 10, 0

; --- RELLENO Y TABLA DE PARTICIONES ---
; El MBR debe medir exactamente 512 bytes. 
; Rellenamos con ceros hasta el byte 446.
times 446-($-$$) db 0

table_particiones:
    ; Entrada 1 (Ejemplo: Partición Activa de 10MB)
    db 0x80        ; [0] Estado: 0x80 = Activa (Bootable)
    db 0x01, 0x01, 0x00 ; [1-3] CHS de inicio (Cabeza 1, Sector 1, Cilindro 0)
    db 0x06        ; [4] Tipo de partición (Ej: 0x06 = FAT16)
    db 0xFE, 0x3F, 0x01 ; [5-7] CHS de fin
    dd 63          ; [8-11] LBA de inicio (Sectores ocultos antes de la partición)
    dd 20480       ; [12-15] Número total de sectores en la partición

    ; Entrada 2 (Vacía)
    times 16 db 0
    ; Entrada 3 (Vacía)
    times 16 db 0
    ; Entrada 4 (Vacía)
    times 16 db 0

; Firma de arranque obligatoria del MBR (Bytes 511 y 512)
dw 0xAA55
