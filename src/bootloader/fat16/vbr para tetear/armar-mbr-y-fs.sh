if [ -z "$1" ]; then
    echo "Este script sirve para crear el sector mbr dentro de una imagen de disco"
    echo "Ejemplo: $0 archivo-mbr.asm archivo-disco.img"
else
    dd if=/dev/zero of=$2 bs=512 count=20543
    nasm -f bin $1 -o mbr.bin
    dd if=mbr.bin of=$2 bs=512 count=1 conv=notrunc
    mkfs.vfat -F 16 --offset 63 -h 63 -n My_OS $2 20480
fi