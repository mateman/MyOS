# VBR + ext2: cargar kernel.bin

## Por qué dos etapas

Un VBR mide 512 bytes. Restando la tabla de particiones (si aplica) y la
firma `0xAA55`, quedan ~446-510 bytes útiles. Ahí no entra un parser de
ext2 (superbloque, descriptores de grupo, inodos, entradas de directorio,
bloques indirectos...). Por eso **todo bootloader real que arranca desde
ext2 (GRUB incluido) usa una segunda etapa**: el VBR solo sabe leer N
sectores fijos por LBA y saltar ahí. El código que realmente entiende
ext2 vive en esa segunda etapa, que puede ocupar varios KB.

## Estructuras de ext2 que necesitás

1. **Superbloque** (1024 bytes, siempre en el byte 1024 del volumen,
   sin importar el tamaño de bloque):
   - `s_magic` (offset 56, 2 bytes) = `0xEF53` → valida que es ext2.
   - `s_log_block_size` (offset 24) → `block_size = 1024 << valor`.
   - `s_inodes_per_group` (offset 40).
   - `s_first_data_block` (offset 20) → 1 si block_size=1024, 0 si es mayor.
   - `s_rev_level` / `s_inode_size` → en revisión 0 el inodo mide
     siempre 128 bytes; en revisión 1 puede ser otro tamaño (leer offset 88).

2. **Tabla de descriptores de grupo (BGDT)**: empieza en el bloque
   `first_data_block + 1`. Cada descriptor mide 32 bytes; el campo que te
   importa es `bg_inode_table` (offset 8), el bloque donde arranca la
   tabla de inodos de ese grupo.

3. **Inodo**: para llegar al inodo N:
   ```
   group  = (N-1) / inodes_per_group
   index  = (N-1) % inodes_per_group
   tabla  = BGDT[group].bg_inode_table
   offset = index * inode_size
   ```
   El inodo raíz siempre es el **número 2**.
   Dentro del inodo, `i_block[0..11]` son 12 punteros directos a bloques
   de datos, `i_block[12]` es un puntero indirecto simple (un bloque
   lleno de más punteros), `i_block[13]` doble indirecto, `i_block[14]`
   triple indirecto.

4. **Entradas de directorio**: los bloques de datos de un inodo-directorio
   contienen una lista de entradas con formato:
   `inode(4) + rec_len(2) + name_len(1) + file_type(1) + nombre(variable)`.
   Se recorren sumando `rec_len` hasta cubrir todo el bloque.

## Limitaciones del código de ejemplo (`stage1.asm` / `stage2.asm`)

- Solo resuelve **bloques directos** (hasta 12 × block_size, p. ej. 48 KB
  con bloques de 4 KB). Para kernels más grandes hay que resolver también
  el indirecto simple (leer ese bloque como un array de punteros de 4
  bytes y repetir la lectura por cada uno).
- Asume `inode_size = 128` fijo. Para volúmenes creados con parámetros no
  default hay que leer `s_inode_size` del superbloque.
- No maneja subdirectorios (busca `kernel.bin` solo en la raíz).
- Carga el kernel en modo real a `0x1000:0000`; si tu kernel espera modo
  protegido y una dirección física alta, vas a necesitar además: habilitar
  A20, armar una GDT mínima, y saltar a protected mode antes o después de
  copiar el kernel.
- El manejo de errores es mínimo (solo imprime un mensaje y cuelga).

## Layout final en disco (con MBR real y partición en LBA 63)

```
LBA 0        : MBR (mbr.asm) — tabla de particiones + bootstrap
LBA 1..16    : Stage2 (stage2.asm) — en el "hueco" entre el MBR y la
               particion, que ni el MBR ni ext2 usan
LBA 17..62   : libre
LBA 63       : inicio de la particion = Stage1 / VBR (stage1.asm)
LBA 65..66   : superbloque de ext2 (byte 1024 de la particion)
LBA 67+      : resto del filesystem ext2
```

**Por qué Stage2 NO va pegado al VBR (LBA 64):** ext2 solo reserva 1024
bytes (2 sectores) antes del superbloque — el VBR ocupa el primero, así
que queda apenas **1 sector libre** (512 bytes) antes de chocar con el
superbloque real. Un Stage2 de 8 KB no entra ahí. La solución (igual a
la que usa GRUB con su `core.img`) es aprovechar el espacio entre el MBR
y el inicio de la partición — con la partición en LBA 63 quedan los
sectores 1 a 62 completamente libres — y poner ahí el Stage2, en un LBA
absoluto fijo que no depende de dónde arranca la partición.

## Probar

```bash
sudo apt install nasm qemu-system-x86 e2fsprogs
chmod +x build2.sh
./build2.sh
qemu-system-i386 -drive format=raw,file=disk.img
```
