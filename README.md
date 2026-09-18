<P><h2><B><I>My-OS</I></B></h2> Pretende ser un proyecto de sistema operativo para aprender como funciona uno.</P>
<P></P>
<P>---------------------------------- Readme del commit 1a85db07ea35d49b71808d73d2cc1d0835186258 </P>
<P><B><I>boot.asm</I></B>    es el proyecto de bootloader</P>
<P><B><I>kernel.asm</I></B>  es el nucleo del sistema, intentare desarrollarlo como microkernel</P>
<P><B><I>main_floppy</I></B> es la imagen del sistema ya instalado para poder probarlo con qemu, virtualbox o vmware</P>
<P>----------------------------------------------------------------------------------------------</P>
<P></P>
<P>--------------------------------- Readme del &uacuteltimo commit</P>
<P><B><I>bootloader/fat12/boot-fat12.asm</I></B> es el bootloader a colocar en el primer sector de un floppy</P>
<P>Mientras que para en fat16 tengo dos archivos, uno el mir que se coloca en el primer sector del disco y el vbr que se coloca en el primer sector de la participación&oacuten que booteara el sistema</P>
<P><B><I>bootloader/fat16/mbr.asm</I></B> en el final de este se encuentra la tabla primaria de particiones y la primera partici&oacuten comienza en el sector 63</P>
<P><B><I>bootloader/fat16/vbr.asm</I></B> este se coloca en la primer partici&oacuten en dos partes, por un lado los primeros 3 bytes y por otro desde el byte 62 hasta el 512, y esto es para no pisar la tabla BPB puesta por el programa que formateo la participación&oacuten</P>
<P><B><I>kernel/</I></B> tengo tres modelos de kernel básicos para probar que el bootloader carga un SO, estoy usando el kernel2.asm como principal en la prueba </P>
<P><B><I>MyOS_floppy.img y MyOS_hard_disk.img</I></B> son las imagenes del sistema ya instalado para poder probarlo con qemu, virtualbox o vmware</P>
<P><B><I>run.sh</I></B> es un script para ejecutar una maquina qemu </P>
<P>---------------------------------------------------------------------------------------------</P>
