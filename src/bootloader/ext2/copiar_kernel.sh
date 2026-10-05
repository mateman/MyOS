#!/bin/bash
# Copia (o reemplaza) kernel.bin dentro de la particion ext2 de disk.img,
# montando por loop device con el offset correcto, y verifica el resultado.
set -e

IMG=${1:-disk.img}
KERNEL_SRC=${2:-kernel.bin}     # el archivo real que queres meter adentro
PART_START_SECTOR=63

if [ ! -f "$KERNEL_SRC" ]; then
    echo "No existe $KERNEL_SRC (pasalo como segundo argumento)"
    exit 1
fi

OFFSET=$((PART_START_SECTOR * 512))
LOOPDEV=$(sudo losetup --find --show -o $OFFSET "$IMG")
echo "Particion montada como $LOOPDEV (offset $OFFSET)"

MNT=/mnt/ext2_kernel_tmp
sudo mkdir -p $MNT
sudo mount "$LOOPDEV" "$MNT"

sudo cp "$KERNEL_SRC" "$MNT/kernel.bin"

echo "---- Contenido de la raiz del filesystem ----"
ls -la "$MNT"

sudo umount "$MNT"
sudo losetup -d "$LOOPDEV"

echo "Listo. kernel.bin copiado dentro de $IMG"
