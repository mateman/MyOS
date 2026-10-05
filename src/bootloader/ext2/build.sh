#!/bin/bash
# Arma una imagen de disco con:
#   - MBR real (mbr.asm) en el sector 0
#   - particion ext2 empezando en LBA 63 (como indica table_particiones)
#   - Stage1 (VBR) en LBA 63, Stage2 en LBA 64..79
#   - kernel.bin copiado a la raiz del ext2
set -e

nasm -f bin mbr.asm -o mbr.bin
nasm -f bin vbr.asm -o vbr.bin
nasm -f bin stage2.asm -o stage2.bin

IMG=disk.img
dd if=/dev/zero of=$IMG bs=512 count=20543   # 63 + 20480, como en table_particiones

# ---- Formatear SOLO la particion (offset 63*512 = 32256 bytes) ----
OFFSET=$((63 * 512))
LOOPDEV=$(sudo losetup --find --show -o $OFFSET "$IMG")
sudo mkfs.ext2 -F -b 1024 -I 128 "$LOOPDEV"

#
echo "kernel de prueba" > kernel.bin
sudo debugfs -w -R "write kernel.bin kernel.bin" "$LOOPDEV"

sudo losetup -d "$LOOPDEV"

# ---- Escribir el MBR en el sector 0 (la tabla de particiones y la
#      firma ya estan armadas a mano en mbr.asm, con LBA=63) ----
dd if=mbr.bin of=$IMG bs=512 count=1 conv=notrunc

# ---- Escribir Stage1 (VBR) en LBA 63, PISANDO el bootsector que dejo
#      mkfs.ext2 ahi (los primeros 512 bytes de una particion ext2 son
#      parte del "boot block" reservado, no los usa el filesystem) ----
dd if=vbr.bin of=$IMG bs=512 seek=63 conv=notrunc

# ---- Escribir Stage2 en LBA 1..16 (16 sectores = 8KB) ----
# Este es el "hueco" entre el MBR (sector 0) y el inicio de la
# particion (sector 63): esos sectores no los usa ni el MBR ni ext2,
# asi que Stage2 no colisiona con el superbloque ni con ningun dato.
dd if=stage2.bin of=$IMG bs=512 seek=1 conv=notrunc

echo "Imagen lista: $IMG"
echo "Probar con: qemu-system-i386 -drive format=raw,file=$IMG"
