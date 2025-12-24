bits 16
org 0x0

; En 0xB800 se encuentra la memoria de video para modo texto
; Cada carácter ocupa 2 bytes: 1 byte para el código ASCII y 1 byte para el atributo (color)
; Por ejemplo, para escribir en la primera posición de la pantalla:
; Dirección = 0xB800:0000

; La int 16 se usa para leer entradas del teclado, recibiendo el carácter en AL y en Ah el scan-code de la tecla pulsada
; vale ver https://es.wikipedia.org/wiki/Int_16h
; La int 10 se usa para operaciones de video, como mover el cursor, colocando la posición en DH (fila) y DL (columna)
; vale ver https://es.wikipedia.org/wiki/Int_10h

start:
    mov ax, 0x0  ; Segmento base
    mov ds, ax      ; Configura segmento de datos
    mov ax, 0xB800  ; Segmento de memoria de video
    mov es, ax      ; Configura segmento de video
 
         ;Obtener la posición actaual del cursor
    mov dh, 10        ; Fila inicial
    mov dl, 0        ; Columna inicial
    
        mov [cursor_row], dh ; Guardar la fila en memoria
        mov [cursor_col], dl ; Guardar la columna en memoria

        call set_cursor
    
    ; Calcula la nueva posición en memoria de video
        call calcular_nueva_pos
        
        call escribir_bienvenida

        mov dh, [cursor_row]  ; Restaurar fila
        mov dl, [cursor_col]  ; Restaurar columna
    
    ; Incrementar la fila por 1
    mov dh, 11       ; Fila inicial
    mov dl, 0        ; Columna inicial

        mov [cursor_row], dh ; Guardar la fila en memoria
        mov [cursor_col], dl ; Guardar la columna en memoria

    call set_cursor  ; Actualizar el cursor en el hardware
    
    ; Calcular la nueva posición en memoria de video
        call calcular_nueva_pos
        
        call escribir_prompt

        mov dh, [cursor_row]  ; Restaurar fila
        mov dl, [cursor_col]  ; Restaurar columna

    ; Incrementar la fila por 1
    mov dh,11       ; Fila inicial
    mov dl, cursor_pos - prompt_msg - 1 ; Columna inicial
        
        mov [cursor_row], dh        ; Guardar la fila en memoria
        mov [cursor_col], dl        ; Guardar la columna en memoria   
    
    call set_cursor   ; Actualizar el cursor en el hardware
    
    ; Calcular la nueva posición en memoria de video
        call calcular_nueva_pos 

    shell_loop:
        ; Capturar entrada del usuario carácter por carácter
        mov ah, 0x00       ; BIOS: Leer teclado
        int 0x16           ; Esperar entrada

        ; Detectar tecla ESC (0x1B)
        cmp al, 0x1B       ; ¿Es ESC?
        je ignorar_tecla   ; Si es ESC, no hacer nada y saltar al bucle

        ; Detectar tecla Suprimir (0x53)
        cmp ah, 0x53       ; ¿Es la tecla Suprimir?
        je ignorar_tecla   ; Si si, ignora la acción

        ; Detectar la tecla Tab (código 09h)
        cmp al, 0x09       ; ¿Es la tecla Tab?
        je ignorar_tecla    ; Si es Tab, ignora la acción
        
        ; Detectar Inicio/Home (0x47)
        cmp ah, 0x47        ; Códigopara Inicio
        je ignorar_tecla    ; Si es Home, ignora la acción

        ; Detectar tecla End/Fin (0x4F)
        cmp ah, 0x4F        ; Código para Fin
        je ignorar_tecla    ; Si es Fin, ignora la acción

        ; Detectar RePag/PageUp (0x49)
        cmp ah, 0x49        ; Código para RePag
        je ignorar_tecla    ; Si es RePag, ignora la acción 

        ; Detectar AvPag/PageDown (0x51)
        cmp ah, 0x51        ; Código para AvPag 
        je ignorar_tecla    ; Si es AvPag, ignora la acción

        ; Detectar flecha arriba (0x48)
        cmp ah, 0x48        ; Código para flecha arriba
        je ignorar_tecla    ; Si es flecha arriba, ignora la acción 

        ; Detectar flecha izquierda (0x4B)
        cmp ah, 0x4B        ; Código para flecha izquierda
        je ignorar_tecla    ; Si es flecha izquierda, ignora la acción

        ; Detectar flecha derecha (0x4D)
        cmp ah, 0x4D        ; Código para flecha derecha
        je ignorar_tecla    ; Si es flecha derecha, ignora la acción

        ; Detectar flecha abajo (0x50)
        cmp ah, 0x50        ; Código para flecha abajo  
        je ignorar_tecla    ; Si es flecha abajo, ignora la acción

        ; Detectar Retroceso/Backspace (0x08)
        cmp al, 0x08        ; ¿Es Retroceso?
        je borrar_caracter  ; Llama a la rutina de borrado

        ; Detectar Enter (0x0D)
        cmp al, 0x0D        ; ¿Es Enter?
        je process_enter    ; Si es Enter, procesar entrada

        ; Mostrar carácter en pantalla
        mov ah,0x07         ; Atributo blanco sobre negro
        stosw               ; Escribir carácter y atributo en [ES:DI]
            mov dh, [cursor_row]     ; Restaurar fila
            mov dl, [cursor_col]     ; Restaurar columna

        add dl, 1                ; Mover a la siguiente columna
        cmp dl, 80               ; ¿Llegamos al final de la fila?
        jl .no_wrap
            ; Si es así, mover a la siguiente fila
            mov dl, 0            ; Reiniciar columna
            cmp dh, 24             ; ¿Estamos en la última fila (24)?
            jl .sin_prompt
                ; Si estamos en la última fila, desplazar todo hacia arriba
               push si
                push di
                push ds
                mov ax, 0xB800  ; Segmento de memoria de video
                mov ds, ax      ; Pongo DS=ES para mover con movsw
                mov si, 160     ; Inicio del mensaje del prompt
                mov di, 0 ; Inicio de la segunda fila
                mov cx, 24 * 80 * 2 ; Número de bytes a mover (filas restantes)
                rep movsw              ; Mover filas hacia arriba  
                ; Limpiar la última fila
                mov cx, 80             ; Número de columnas
                mov al, ' '            ; Carácter espacio
                mov ah, 0x07           ; Atributo blanco sobre negro 
                stosw
                pop ds
                pop di
                pop si
                jmp .no_wrap
.sin_prompt:
            inc dh                ; Incrementar fila
.no_wrap:
            mov [cursor_row], dh ; Guardar la fila en memoria
            mov [cursor_col], dl ; Guardar la columna en memoria

           call set_cursor       ; Actualizar el cursor en el hardware
           call calcular_nueva_pos
        jmp shell_loop          ; Repetir bucle

    process_enter:

            mov dh, [cursor_row]    ; Restaurar fila
            mov dl, [cursor_col]    ; Restaurar columna

        cmp dh, 24              ; ¿Estamos en la última fila (24)?
        jl .not_last_row
            ; Si estamos en la última fila, desplazar todo hacia arriba
            push si
            push di
            push ds
            mov ax, 0xB800  ; Segmento de memoria de video
            mov ds, ax      ; Pongo DS=ES para mover con movsw
            mov si, 160     ; Inicio del mensaje del prompt
            mov di, 0 ; Inicio de la segunda fila
            mov cx, 24 * 80 * 2 ; Número de bytes a mover (filas restantes)
            rep movsw              ; Mover filas hacia arriba  
            ; Limpiar la última fila
            mov cx, 80             ; Número de columnas
            mov al, ' '            ; Carácter espacio
            mov ah, 0x07           ; Atributo blanco sobre negro 
            stosw
            pop ds
            pop di
            pop si
            jmp .escribir_p 

.not_last_row:
        ; incrementar la fila por 1
        add dh, 1               ; Incrementar la fila actual en 1    

            mov [cursor_row], dh    ; Guardar la fila en memoria

.escribir_p:
        mov dl, 0               ; Reiniciar columna

            mov [cursor_col], dl    ; Guardar la columna en memoria
        
        call set_cursor         ; Actualiza el cursor en memoria

        ; Calcula la nueva posición en memoria de video
            Call calcular_nueva_pos

        ; Dibujar el nuevo prompt
        call escribir_prompt

            mov dh, [cursor_row]    ; Restaurar fila
            mov dl, [cursor_col]    ; Restaurar columna
        
        ; Incrementar fila por 1
        mov dl, cursor_pos - prompt_msg - 1 ; Columna inicial
            mov [cursor_row], dh        ; Guardar la fila en memoria
            mov [cursor_col], dl        ; Guardar la columna en memoria
            call calcular_nueva_pos

        call set_cursor         ; Actualizar el cursor del hardware

        ; Calcular la nueva posición en memoria de video

        jmp shell_loop          ; Repetir bucle

; Con print_string se recorre el vector con la leyenda a escribir en pantalla hasta encontrar el byte nulo o 0x00
    print_string:
        mov al, [cs:si]     ; Cargar el caracter apuntado por SI en AL
        inc si
        or al, al        ; ¿Fin de cadena?
        jz .done         ; Si Al == 0, terminar
        stosw
        jmp print_string ; Siguiente caracter
    .done:
        ret

    escribir_prompt:
        ; Escribir "MyOS>" en pantalla
        mov si, prompt_msg
        mov ah, 0x07        ; Atributo Blanco sobre Negro
        call print_string
        ret


    escribir_bienvenida:
        ; Escribir mensaje carácter por carácter
        mov si, bienvenida_msg
        mov ah, 0x07        ; Atributo Blanco sobre Negro
        call print_string
        ret

    set_cursor:
        ; Configurar el cursor en hardware usando cursor_row y cursor_col
        mov dh, [cursor_row]    ; Cargar fila desde cursor_row
        mov dl, [cursor_col]    ; Cargar columna deade cursor_col
        mov ah, 0x02            ; Función BIOS; Configurar posición del cursor
        xor bh, bh              ; página de texto 0
        int 0x10                ; llamar a BIOS para mover el cursor
        ret
    
    calcular_nueva_pos:
        ; Calcular el desplazamiento de file
        mov al, [cursor_row]    ; Al = file actual
        xor ah,ah               ; Limpiar Ah
        mov cx, 160             ; 160 bytes por fila (80 columnas * 2 bytes por caracter)
        mul cx                  ; Ax = fila * 160 (desplazamiento de fila)

        ; Calcular el desplazamiento de columna
        mov dl, [cursor_col]    ; Dl = columna actual
        xor dh,dh               ; Limpiar Dh
        mov bx, dx              ; Bx = columna actual
        shl bx, 1               ; Bx = columna * 2 (cada carácter ocupa 2 bytes)

        ; Sumar los desplazamientos
        add ax, bx              ; Ax = posición absoluta en memoria de video
        mov di, ax              ; DI apunta a la posición calculada

        ret

    ignorar_tecla:
        ; No hacer nada, simplemente volver al bucle
        jmp shell_loop

    no_update_max:
        call set_cursor         ; Actualizar el cursor en el hardware

        jmp shell_loop          ; Repetir bucle

    borrar_caracter:
        cmp byte [cursor_col], cursor_pos - prompt_msg - 1 ; ¿Esta al principio del prompt?
        jbe shell_loop          ; Si esta al principio, no moverse
            call borrar_izquierda
            jmp shell_loop

    borrar_izquierda:
        ; Verificar si estamos al inicio del prompt (columna 9)
        mov dl, [cursor_col]
        cmp dl, cursor_pos - prompt_msg - 1 ; ¿Esta al principio del prompt?
        jbe shell_loop           ; Si es el inicio, no hace nada
            
        ; Retroceder una posición en cursor_col
        dec dl                   ; Retroceder una posción
        mov [cursor_col], dl     ; Guardar la nuea posiciónen cursor_col
    
        ; Calcular la nueva posición en memoria (DI)
        call calcular_nueva_pos

        ; Sobrescribir con espacio a posición actual
        mov al, ' '              ; Carácter espacio en blanco
        mov ah, 0x07             ; Atributo blanco sobre negro
        mov [es:di], al          ; Escribir espacio en el primer byte
        mov [es:di+1], ah        ; Escribir atributo en el segundo byte

        ; Actualizar el cursor en hardware
        call set_cursor

        ret

    escribir_caracter_con_cursor:
        push ax             ; Guardar Ax
        push bx             ; Guardar Bx
        push di             ; Guardar Di

        ; Calcular posición actual si no esta sincronizada
        call calcular_nueva_pos     ; Asegurar que DI esta actualizado

        ; Configurar el segmento de video
        mov ax, 0xB800     ; Segmento de memoria d video
        mov es, ax         ; Mover el segmento a ES

        ; Escribir el caracter en posición calculada
        mov [es:di], al    ; Escribir el carácter en el primer byte
        mov ah, 0x07       ; Atributo blanco sobre negro
        mov [es:di+1], ah  ; Escribir el atributo en el segundo byte

        pop di             ; Restaurar Di
        pop bx             ; Restaurar Bx
        pop ax             ; Restaurar Ax
        ret

    halt:
        hlt                 ; Detener la CPU
        jmp halt            ; Bucle infinito
bienvenida_msg db 0xAD, "Bienvenido al kernel MyOS!", 0x00  ; Mensaje de bienvenida
prompt_msg db "MyOS>", 0x00  ; Mensaje del prompt
cursor_pos dw 0        ; Variable para guardar la posición actual del cursor
cursor_row db 0        ; Variable para guardar la fila del cursor
cursor_col db 0        ; Variable para guardar la columna del cursor
cursor_max db 9        ; Posición máxima alcanzada en la fila
