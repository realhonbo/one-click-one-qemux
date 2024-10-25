#!/bin/bash

echo '=========== COMPILE ENVIRONMENT INITALIZING ============>'

# build 环境
echo yes | sudo apt install build-essential
echo yes | sudo apt install cmake
echo yes | sudo apt install gdb
echo yes | sudo apt install clang
echo yes | sudo apt install clangd
echo yes | sudo apt install clang-tidy
echo yes | sudo apt install gcc-arm-linux-gnueabihf
echo yes | sudo apt install gcc-arm-linux-gnueabi
echo yes | sudo apt install gcc-aarch64-linux-gnu
echo yes | sudo apt install gdb-multiarch
echo yes | sudo apt install bear
echo yes | sudo apt install texinfo
echo yes | sudo apt install lzop
echo yes | sudo apt install net-tools
echo yes | sudo apt install xinetd
echo yes | sudo apt install tftp tftp-hpa tftpd-hpa
echo yes | sudo apt install dwarves

# QEMU 环境
echo yes | sudo apt install libsdl1.2-dev libsdl2-dev # qemu配置需要
echo yes | sudo apt install flex bison libncurses-dev libelf-dev libssl-dev u-boot-tools bc xz-utils
echo yes | sudo apt install fakeroot 
echo yes | sudo apt install pkg-config
echo yes | sudo apt install ninja-build

sudo apt-cache search pixman
echo yes | sudo apt install libpixman-1-dev

read -p  "qemu : 选择默认版本v4.2 [y] || 慢慢编译v7.2 [n]" input
case $input in
        [yY]* | "")
                # 选择软件源中的qemu - v4
                echo yes | sudo apt install qemu-system
                ;;
        [nN]*)
                # 自由选择qemu版本
                wget https://download.qemu.org/qemu-7.2.0.tar.xz
                tar xvJf qemu-7.2.0.tar.xz
                cd qemu-7.2.0
                ./configure
                make
                sudo make install
                ;;
        *)
                echo '选择不进行后续配置'
                exit  
                ;;      
esac

echo '=========== COMPILE LINUX KERNEL ============>'

cd /home
sudo mkdir qemux
sudo chmod 777 qemux
cd qemux
mkdir kernel
cd kernel
wget https://mirrors.tuna.tsinghua.edu.cn/kernel/v5.x/linux-5.10.99.tar.xz
tar -xvf linux-5.10.99.tar.xz
cd linux-5.10.99
sed -i '370d' Makefile
sed -i '370a ARCH ?= arm\n CROSS_COMPILE = arm-linux-gnueabi-' Makefile # 注意修改arch时不要有空格

make vexpress_defconfig

# 依据核心数调配编译线程, 默认12 线程
make zImage  -j12
make modules -j12
make dtbs    -j12
make LOADADDR=0x60003000 uImage  -j12

cp arch/arm/boot/zImage /home/qemux/
cp arch/arm/boot/uImage /home/qemux/
cp arch/arm/boot/dts/vexpress-v2p-ca9.dtb /home/qemux/

cd /home/qemux
touch start.sh
chmod 777 start.sh
echo ' ' >> start.sh
sed -i '1a qemu-system-arm \\\
        -M vexpress-a9 \\\
        -m 512M \\\
        -kernel zImage \\\
        -dtb vexpress-v2p-ca9.dtb \\\
        -nographic \\\
        -append "console=ttyAMA0"' start.sh

echo '=========== MAKE ROOT FILE SYSTEM ============>'

cd /home/qemux
mkdir filesys
cd filesys
wget https://busybox.net/downloads/busybox-1.35.0.tar.bz2
tar -xvf busybox-1.35.0.tar.bz2
cd busybox-1.35.0
sudo mkdir -p /home/nfs
sudo chmod 777 /home/nfs/

sed -i '190d' Makefile
sed -i '190a ARCH ?= arm\n CROSS_COMPILE = arm-linux-gnueabi-' Makefile # v0.93

echo ' 正在加载菜单... '
echo ' 通过 [y/n]或[y/n/m] 选取 ... '
echo ' 选取 Settings —68行-> [*] vi-style line editing commands (New) '
echo ' 更改 Settings —43行-> Destination path for 'make install' 为 /home/nfs '

read -p "记住之后请回车确认" input
case $input in
        *) ;;
esac
echo '按错了不要慌, 请去github中查看README'
sleep 3

make menuconfig

# 编译安装
make install -j8

# 动态链接库
cd /home/nfs
mkdir lib
cd /usr/arm-linux-gnueabi/lib
cp *.so* /home/nfs/lib -d

# 设备节点
cd /home/nfs
mkdir dev
cd dev
sudo mknod -m 666 tty1 c 4 1
sudo mknod -m 666 tty2 c 4 2
sudo mknod -m 666 tty3 c 4 3
sudo mknod -m 666 tty4 c 4 4
sudo mknod -m 666 console c 5 1
sudo mknod -m 666 null c 1 3

# 初始化进程
cd /home/nfs
mkdir -p etc/init.d
cd etc/init.d
touch rcS
chmod 777 rcS
echo '#!/bin/sh' >> rcS
echo 'PATH=/bin:/sbin:/usr/bin:/usr/sbin' >> rcS
echo 'export LD_LIBRARY_PATH=/lib:/usr/lib' >> rcS
echo '/bin/mount -n -t ramfs ramfs /var' >> rcS
echo '/bin/mount -n -t ramfs ramfs /tmp' >> rcS
echo '/bin/mount -n -t sysfs none /sys' >> rcS
echo '/bin/mount -n -t ramfs none /dev' >> rcS
echo '/bin/mkdir /var/tmp' >> rcS
echo '/bin/mkdir /var/modules' >> rcS
echo '/bin/mkdir /var/run' >> rcS
echo '/bin/mkdir /var/log' >> rcS
echo '/bin/mkdir -p /dev/pts' >> rcS
echo '/bin/mkdir -p /dev/shm' >> rcS
echo '/sbin/mdev -s' >> rcS
echo '/bin/mount -a' >> rcS
echo 'echo "                                     "' >> rcS
echo 'echo "==== vexpress board initalizing ====>"' >> rcS
echo 'echo "                                     "' >> rcS

# 设置文件系统
cd /home/nfs/etc
touch fstab
echo 'proc    /proc           proc    defaults        0       0' >> fstab
echo 'none    /dev/pts        devpts  mode=0622       0       0' >> fstab
echo 'mdev    /dev            ramfs   defaults        0       0' >> fstab
echo 'sysfs   /sys            sysfs   defaults        0       0' >> fstab
echo 'tmpfs   /dev/shm        tmpfs   defaults        0       0' >> fstab
echo 'tmpfs   /dev            tmpfs   defaults        0       0' >> fstab
echo 'tmpfs   /mnt            tmpfs   defaults        0       0' >> fstab
echo 'var     /dev            tmpfs   defaults        0       0' >> fstab
echo 'ramfs   /dev            ramfs   defaults        0       0' >> fstab

# 初始化脚本
cd /home/nfs/etc
touch inittab
echo '::sysinit:/etc/init.d/rcS' >> inittab
echo '::askfirst:-/bin/sh' >> inittab
echo '::ctrlaltdel:/bin/umount -a -r' >> inittab

# 环境变量
cd /home/nfs/etc
touch profile
echo 'USER="root"' >> profile
echo 'LOGNAME=$USER' >> profile
echo 'export HOSTNAME=`cat /etc/sysconfig/HOSTNAME`' >> profile # 修正hostname解析问题
echo 'export USER=root' >> profile
echo 'export HOME=/root' >> profile
echo 'export PS1="[$USER@$HOSTNAME \W]\# "' >> profile
echo 'PATH=/bin:/sbin:/usr/bin:/usr/sbin' >> profile
echo 'LD_LIBRARY_PATH=/lib:/usr/lib:$LD_LIBRARY_PATH' >> profile
echo 'export PATH LD_LIBRARY_PATH' >> profile

# 主机名
cd /home/nfs/etc
mkdir sysconfig
cd sysconfig
echo 'vexpress' >>  HOSTNAME

# 其他dirs
cd /home/nfs
mkdir mnt proc root sys tmp var

# 封装root并挂载
cd /home/
sudo mkdir temp
sudo dd if=/dev/zero of=rootfs.ext3 bs=1M count=32
sudo mkfs.ext3 rootfs.ext3
sudo mount -t ext3 rootfs.ext3 temp/ -o loop
sudo cp -r nfs/* temp/
sudo umount temp
sudo mv rootfs.ext3 qemux
cd /home/qemux
sudo rm start.sh
touch start.sh
chmod 777 start.sh
echo ' ' >> start.sh
sudo sed -i '1a qemu-system-arm \\\
        -M vexpress-a9 \\\
        -m 512M \\\
        -kernel zImage \\\
        -dtb vexpress-v2p-ca9.dtb \\\
        -nographic \\\
        -append "root=/dev/mmcblk0 rw console=ttyAMA0" \\\
        -sd rootfs.ext3' start.sh

echo '=========== new lab environment is built ============>'	
