#!/bin/sh
#
# Optware setup script for Android
# Copyright (c) 2012 Paul Sokolovsky <pfalcon@users.sourceforge.net>
# Lincense: GPLv3, http://www.gnu.org/licenses/gpl.html
#

#set -x

OPTWARE_DIR=/data/local/optware
WRITABLE_DIR=/data/local

tmp_dir=$WRITABLE_DIR/optware.tmp
cs08q1_fname=arm-2008q1-126-arm-none-linux-gnueabi-i686-pc-linux-gnu.tar.bz2
libc_path=arm-2008q1/arm-none-linux-gnueabi/libc/lib
libc_libs="ld-2.5.so ld-linux.so.3 \
      libc-2.5.so libc.so.6 \
      libm-2.5.so libm.so.6 \
      librt-2.5.so librt.so.1 \
      libpthread-2.5.so libpthread.so.0 \
      libresolv-2.5.so libresolv.so.2 \
      libdl-2.5.so libdl.so.2 \
      libnss_dns-2.5.so libnss_dns.so.2 \
      "

#
# On-target (device) commands
#

t_cp () {
    # copy file on a device
    adb shell su -c "cat $1 >$2"
}

t_cd_ln () {
    local dir=$1
    shift
    adb shell su -c "cd $dir; ln $*"
}

t_chmod () {
    adb shell su -c "chmod $*"
}

t_mkdir_p () {
    # This doesn't complain if dir exists, but can't create intermediate dirs
    adb shell su -c "ls $1 2>/dev/null || mkdir $1"
}

extract_libc () {
    local list=""
    while [ -n "$1" ]; do
        list="$list $libc_path/$1"
        shift
        shift
    done
    tar xfj $cs08q1_fname $list
}

install_system_lib () {
    echo "Installing system lib: $1"
    adb push $libc_path/$1 $tmp_dir
    t_cp $tmp_dir/$1 /lib/$1
    t_chmod 0755 /lib/$1
    t_cd_ln /lib/ -s $1 $2
}

install_libc () {
    t_mkdir_p $OPTWARE_DIR/rootlib
    t_cd_ln . -s $OPTWARE_DIR/rootlib /lib

    while [ -n "$1" ]; do
        local lib=$1
        shift
        local symlink=$1
        shift
        install_system_lib $lib $symlink
    done
}

install_bin () {
    echo "Installing /opt/bin/$1"
    t_cp $tmp_dir/bin/$1 /opt/bin/$1
    t_chmod 755 /opt/bin/$1
}

install_ipkg () {
    adb push opt $tmp_dir

    t_mkdir_p /opt/bin
    t_mkdir_p /opt/lib

    install_bin ipkg

    t_cp $tmp_dir/lib/libipkg.so.0.0.0 /opt/lib/libipkg.so.0.0.0
    t_cd_ln /opt/lib/ -s libipkg.so.0.0.0 libipkg.so.0
    t_cd_ln /opt/lib/ -s libipkg.so.0.0.0 libipkg.so
}

if [ ! -f $cs08q1_fname ]; then
    echo "You need CodeSourcery ARM-Linux toolchain: $cs08q1_fname"
    exit 1
fi


feed=http://ipkg.nslu2-linux.org/feeds/optware/cs08q1armel/cross/stable
# ipk_name=`wget -qO- $feed/Packages | awk '/^Filename: ipkg-opt/ {print $2}'`
#wget -c http://ipkg.nslu2-linux.org/feeds/optware/cs08q1armel/cross/stable/ipkg-opt_0.99.163-10_arm.ipk
#http://ipkg.nslu2-linux.org/feeds/optware/cs08q1armel/cross/stable/wget_1.12-2_arm.ipk
ipkg_fname=ipkg-opt_0.99.163-10_arm.ipk
# wget $feed/$ipk_name

adb shell su -c "mount -o rw,remount rootfs /"

# Start from scratch
echo "== (Re)initializing optware environment =="
adb shell su -c "rm -r $OPTWARE_DIR"
adb shell su -c "rm /lib"
adb shell su -c "rm /bin"
adb shell su -c "rm /opt"

adb shell rm -r $tmp_dir
adb shell mkdir $tmp_dir

t_mkdir_p $OPTWARE_DIR
t_cd_ln . -s $OPTWARE_DIR /opt


echo "== Installing libc =="
#extract_libc $libc_libs
install_libc $libc_libs

echo "== Installing bootstrap ipkg =="
rm -rf opt
tar -xOzf $ipkg_fname ./data.tar.gz | tar -xzf -
install_ipkg

echo "== Installing bootstrap wget =="
rm -rf opt
tar -xOzf wget_1.12-2_arm.ipk ./data.tar.gz | tar -xzf -
adb push opt $tmp_dir
install_bin wget

echo "== Installing bootstrap busybox =="
rm -rf opt
tar -xOzf busybox-base_1.10.3-1_arm.ipk ./data.tar.gz | tar -xzf -
adb push opt $tmp_dir
install_bin busybox

echo "== Initializing bootstrap /bin =="
t_mkdir_p $OPTWARE_DIR/rootbin
t_cd_ln . -s $OPTWARE_DIR/rootbin /bin
# We need sane shell as /bin/sh
t_cd_ln /bin -s /opt/bin/busybox sh
# We need minimal set of sane shell commands to run update-alternatives
# script to properly (re)install busybox itself
t_cd_ln /bin -s /opt/bin/busybox echo
t_cd_ln /bin -s /opt/bin/busybox rm
t_cd_ln /bin -s /opt/bin/busybox sed
t_cd_ln /bin -s /opt/bin/busybox mkdir
t_cd_ln /bin -s /opt/bin/busybox head
t_cd_ln /bin -s /opt/bin/busybox sort
t_cd_ln /bin -s /opt/bin/busybox dirname
t_cd_ln /bin -s /opt/bin/busybox ln

echo "== Configuring package feed =="
t_mkdir_p /opt/etc
t_mkdir_p /opt/etc/ipkg
adb shell su -c "echo src cross $feed >/opt/etc/ipkg/feeds.conf"

echo "== Configuring domain name resolution =="
adb shell su -c "echo nameserver 8.8.8.8 >/opt/etc/resolv.conf"
# On a normal Android system, /etc is symlink to /system/etc, but just in case...
t_mkdir_p /etc
# but for normal system, we need to remount /system
adb shell su -c "mount -o rw,remount /system /system"
adb shell su -c "rm /etc/resolv.conf"
t_cd_ln . -s /opt/etc/resolv.conf /etc/resolv.conf
adb shell su -c "mount -o ro,remount /system /system"

echo "== Creating optware init script =="
adb shell su -c "echo #!/system/bin/sh >/opt/optware-init.sh"
adb shell su -c "echo 'ls /opt >/dev/null 2>&1 && exit' >>/opt/optware-init.sh"
adb shell su -c "echo echo Reinitializing optware rootfs links >>/opt/optware-init.sh"
adb shell su -c "echo mount -o rw,remount rootfs / >>/opt/optware-init.sh"
adb shell su -c "echo ln -s $OPTWARE_DIR /opt >>/opt/optware-init.sh"
adb shell su -c "echo ln -s $OPTWARE_DIR/rootlib /lib >>/opt/optware-init.sh"
adb shell su -c "echo ln -s $OPTWARE_DIR/rootbin /bin >>/opt/optware-init.sh"
adb shell su -c "echo mount -o ro,remount rootfs / >>/opt/optware-init.sh"
t_chmod 0755 /opt/optware-init.sh

echo "== Creating optware startup script =="
adb shell su -c "echo #!/system/bin/sh >/opt/optware.sh"
adb shell su -c "echo 'ls /opt >/dev/null 2>&1 ||' su -c $OPTWARE_DIR/optware-init.sh >>/opt/optware.sh"
adb shell su -c "echo export PATH=/opt/sbin:/opt/bin:/bin:/system/bin >>/opt/optware.sh"
adb shell su -c "echo /bin/sh >>/opt/optware.sh"
t_chmod 0755 /opt/optware.sh

adb shell su -c "mount -o ro,remount rootfs /"

echo "Optware for Android installation complete."
echo "To start opware session, execute /opt/optware.sh"
