if [ -z "$1" ]; then
    echo "Este script sirve para crear el sector vbr dentro de una imagen de disco"
    echo "Ejemplo: $0 archivo-vbr.asm archivo-disco.img"
else
    nasm -f bin $1 -o vbr.bin
    dd if=vbr.bin of=$2 bs=1 count=3 seek=32256 conv=notrunc
    dd if=vbr.bin of=$2 bs=1 skip=62 seek=32318 conv=notrunc
fi