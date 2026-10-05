sudo apt update && sudo apt install nasm -y
nasm -f bin mbr.asm -o mbr.bin
nasm -f bin vbr.asm -o vbr.bin
dd if=/dev/zero of=disco_virtual.img bs=512 count=20543
dd if=mbr.bin of=disco_virtual.img bs=512 count=1 conv=notrunc
dd if=vbr.bin of=disco_virtual.img bs=512 count=1 seek=63 conv=notrunc
fdisk -l disco_virtual.img
