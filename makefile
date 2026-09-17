ASM = nasm
CC=gcc

SRC_DIR = src
BUILD_DIR = build
TOOLS_DIR=tools

.PHONY: all floppy_image hard_disk_image kernel bootloader clean always

all: bootloader-fat12 bootloader-fat16 kernel floppy_image hard_disk_image
fat16: bootloader-fat16 kernel hard_disk_image
fat12: bootloader-fat12 kernel floppy_image 

# Create Floppy image
floppy_image: $(BUILD_DIR)/MyOS_floppy.img
$(BUILD_DIR)/MyOS_floppy.img: bootloader-fat12 kernel
	dd if=/dev/zero of=$(BUILD_DIR)/MyOS_floppy.img bs=512 count=2880
	mkfs.vfat -F 12 -n "MyOS" $(BUILD_DIR)/MyOS_floppy.img
	dd if=$(BUILD_DIR)/boot-fat12.bin of=$(BUILD_DIR)/MyOS_floppy.img conv=notrunc
	
	mcopy -i $(BUILD_DIR)/MyOS_floppy.img $(BUILD_DIR)/main.bin "::main.bin"
	mcopy -i $(BUILD_DIR)/MyOS_floppy.img $(BUILD_DIR)/kernel.bin "::kernel.bin"
	mcopy -i $(BUILD_DIR)/MyOS_floppy.img test.txt "::test.txt"

# Create Hard Disk image
hard_disk_image: $(BUILD_DIR)/MyOS_hard_disk.img
$(BUILD_DIR)/MyOS_hard_disk.img: bootloader-fat16 kernel
	dd if=/dev/zero of=$(BUILD_DIR)/MyOS_hard_disk.img bs=512 count=20543
	dd if=$(BUILD_DIR)/mbr-fat16.bin of=$(BUILD_DIR)/MyOS_hard_disk.img bs=512 count=1 conv=notrunc
	mkfs.vfat -F 16 --offset 63 -h 63 -n My_OS $(BUILD_DIR)/MyOS_hard_disk.img 20480
	dd if=$(BUILD_DIR)/vbr-fat16.bin of=$(BUILD_DIR)/MyOS_hard_disk.img bs=1 count=3 seek=32256 conv=notrunc
	dd if=$(BUILD_DIR)/vbr-fat16.bin of=$(BUILD_DIR)/MyOS_hard_disk.img bs=1 skip=62 seek=32318 conv=notrunc

	mcopy -i $(BUILD_DIR)/MyOS_hard_disk.img@@32256 $(BUILD_DIR)/main.bin "::main.bin"
	mcopy -i $(BUILD_DIR)/MyOS_hard_disk.img@@32256 $(BUILD_DIR)/kernel.bin "::kernel.bin"
	mcopy -i $(BUILD_DIR)/MyOS_hard_disk.img@@32256 test.txt "::test.txt"


# Create Bootloader para floppy
bootloader-fat12: $(BUILD_DIR)/boot-fat12.bin
$(BUILD_DIR)/boot-fat12.bin: always
	$(ASM) -f bin $(SRC_DIR)/bootloader/fat12/boot-fat12.asm -o $(BUILD_DIR)/boot-fat12.bin

# Create Bootloader para imagen de hd
bootloader-fat16: $(BUILD_DIR)/boot-fat16.bin
$(BUILD_DIR)/boot-fat16.bin: always
	$(ASM) -f bin $(SRC_DIR)/bootloader/fat16/mbr.asm -o $(BUILD_DIR)/mbr-fat16.bin
	$(ASM) -f bin $(SRC_DIR)/bootloader/fat16/vbr.asm -o $(BUILD_DIR)/vbr-fat16.bin

# Create Kernel
kernel: $(BUILD_DIR)/kernel.bin
$(BUILD_DIR)/kernel.bin: always
	$(ASM) -f bin $(SRC_DIR)/kernel/kernel2.asm -o $(BUILD_DIR)/kernel.bin
	$(ASM) -f bin $(SRC_DIR)/kernel/kernel.asm -o $(BUILD_DIR)/main.bin

# Tools
tools_fat: $(BUILD_DIR)/tools/fat
$(BUILD_DIR)/tools/fat: always $(TOOLS_DIR)/fat/fat.c
	mkdir -p $(BUILD_DIR)/tools
	$(CC) -g -o $(BUILD_DIR)/tools/fat $(TOOLS_DIR)/fat/fat.c

# Always
always:
	mkdir -p $(BUILD_DIR)

# Erase 
clean:
	rm -rf $(BUILD_DIR)/*