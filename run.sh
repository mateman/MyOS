if [ -z "$1" ]; then
    echo "Para ejecutar una imagen de diskette ingresar $0 fat12"
    echo "Para ejecutar una imagen de disco con fat 16 ingresar $0 fat16"
else
    if [ $1 = "fat12" ]; then
        qemu-system-i386 -drive format=raw,file=./build/MyOS_floppy.img,if=floppy -boot a -monitor stdio 
    
    elif [ $1 = "fat16" ]; then
       qemu-system-i386 ./build/MyOS_hard_disk.img 
    else
        echo "Opción no válida. Ingrese fat12 o fat16"
    fi
fi

