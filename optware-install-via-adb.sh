#!/bin/sh
#
# Optware setup script for Android
# Copyright (c) 2012 Paul Sokolovsky <pfalcon@users.sourceforge.net>
# Lincense: GPLv3, http://www.gnu.org/licenses/gpl.html
#
# Optware binary packages repository (aka feed):
# http://ipkg.nslu2-linux.org/feeds/optware/cs08q1armel/cross/stable
#
# Optware source code Subversion repository:
# svn co http://svn.nslu2-linux.org/svnroot/optware/trunk/
#

#set -x

OPTWARE_DIR=/data/local/optware
WRITABLE_DIR=/data/local

FEED=http://ipkg.nslu2-linux.org/feeds/optware/cs08q1armel/cross/stable

# DO NOT edit anything below this line unless you know what you are doing

tmp_dir=$WRITABLE_DIR/optware.tmp
cs08q1_url=https://sourcery.mentor.com/sgpp/lite/arm/portal/package2549/public/arm-none-linux-gnueabi/arm-2008q1-126-arm-none-linux-gnueabi-i686-pc-linux-gnu.tar.bz2
cs08q1_fname=$(basename $cs08q1_url)
libc_path=arm-2008q1/arm-none-linux-gnueabi/libc
libc_libs="lib/ld-2.5.so ld-linux.so.3 \
      lib/libc-2.5.so libc.so.6 \
      lib/libm-2.5.so libm.so.6 \
      lib/librt-2.5.so librt.so.1 \
      lib/libpthread-2.5.so libpthread.so.0 \
      lib/libresolv-2.5.so libresolv.so.2 \
      lib/libdl-2.5.so libdl.so.2 \
      lib/libnss_dns-2.5.so libnss_dns.so.2 \
      lib/libutil-2.5.so libutil.so.1 \
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

t_remount_rw () {
    adb shell su -c "mount -o rw,remount $1 $1"
}

t_remount_ro () {
    adb shell su -c "mount -o ro,remount $1 $1"
}

extract_libc () {
    if [ ! -d $(echo $libc_path | sed -e 's%/.*%%') ]; then
        echo Extracting $cs08q1_fname
        tar xfj $cs08q1_fname $list
    fi
}

install_system_lib () {
    local f=$(basename $1)
    echo "Installing system lib: $f"
    adb push $libc_path/$1 $tmp_dir
    t_cp $tmp_dir/$f /lib/$f
    t_chmod 0755 /lib/$f
    t_cd_ln /lib/ -s $f $2
}

install_system_bin () {
    local f=$(basename $1)
    echo "Installing system bin: $1"
    adb push $libc_path/$1 $tmp_dir
    t_cp $tmp_dir/$f /bin/$f
    t_chmod 0755 /bin/$f
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

fetch_package_index () {
    if [ ! -f Packages ]; then
        echo "Downloading Optware package index"
        wget -q $FEED/Packages
    else
        echo "Using cached Optware package index"
    fi
}

get_package_fname () {
    awk "/^Filename: ${1}_/ {print \$2}" Packages
}

fetch_package () {
    if [ -z "$1" ]; then
        echo "Unexpected error: package '$1' not found in index"
        exit 1
    fi
    if [ ! -f "$1" ]; then
        echo "Downloading Optware package $1"
        wget -q $FEED/$1
    else
        echo "Using cached package $1"
    fi
}

fetch_toolchain () {
    if [ ! -f $cs08q1_fname ]; then
        echo "You need CodeSourcery ARM-Linux toolchain release 2008q1: $cs08q1_fname"
        echo "if you have this file on your system already, press Ctrl-C now and copy"
        echo "it into the current directory. Otherwise, press Enter to download it (65MB)."
        read
        wget $cs08q1_url
    fi
}

optware_uninstall () {
    adb shell su -c "rm -r $OPTWARE_DIR"
    adb shell su -c "rm /lib"
    adb shell su -c "rm /bin"
    adb shell su -c "rm /opt"
    adb shell su -c "rm /tmp"
    adb shell rm -r $tmp_dir
}

#
# Main code
#

if [ "$1" == "" ]; then
    echo "This script installs NSLU Optware on an Android device connected using ADB"
    echo "Usage: $0 install|uninstall"
    exit 1
fi

if [ "$1" == "uninstall" ]; then
    t_remount_rw /
    optware_uninstall
    t_remount_ro /
    exit
fi


fetch_toolchain
fetch_package_index
ipkg_fname=$(get_package_fname ipkg-opt)
wget_fname=$(get_package_fname wget)
busybox_fname=$(get_package_fname busybox-base)
fetch_package $ipkg_fname
fetch_package $wget_fname
fetch_package $busybox_fname

t_remount_rw /

# Start from scratch
echo "== (Re)initializing optware environment =="
optware_uninstall

adb shell rm -r $tmp_dir
adb shell mkdir $tmp_dir

t_mkdir_p $OPTWARE_DIR
t_cd_ln . -s $OPTWARE_DIR /opt

t_mkdir_p $OPTWARE_DIR/rootbin
t_cd_ln . -s $OPTWARE_DIR/rootbin /bin

t_mkdir_p $OPTWARE_DIR/tmp
t_cd_ln . -s $OPTWARE_DIR/tmp /tmp

echo "== Installing libc =="
extract_libc
install_libc $libc_libs
install_system_bin usr/bin/ldd

echo "== Installing bootstrap ipkg =="
rm -rf opt
tar -xOzf $ipkg_fname ./data.tar.gz | tar -xzf -
install_ipkg

echo "== Installing bootstrap wget =="
rm -rf opt
tar -xOzf $wget_fname ./data.tar.gz | tar -xzf -
adb push opt $tmp_dir
install_bin wget

echo "== Installing bootstrap busybox =="
rm -rf opt
tar -xOzf $busybox_fname ./data.tar.gz | tar -xzf -
adb push opt $tmp_dir
install_bin busybox

adb shell rm -r $tmp_dir

echo "== Initializing bootstrap /bin =="
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
adb shell su -c "echo src cross $FEED >/opt/etc/ipkg/feeds.conf"

echo "== Configuring domain name resolution =="
adb shell su -c "echo nameserver 8.8.8.8 >/opt/etc/resolv.conf"
# On a normal Android system, /etc is symlink to /system/etc, but just in case...
t_mkdir_p /etc
# but for normal system, we need to remount /system
t_remount_rw /system
adb shell su -c "rm /etc/resolv.conf"
t_cd_ln . -s /opt/etc/resolv.conf /etc/resolv.conf

echo "== Configuring /etc/mtab =="
t_cd_ln . -s /proc/mounts /etc/mtab
t_remount_ro /system

echo "== Creating optware init script =="
adb shell su -c "echo #!/system/bin/sh >/opt/optware-init.sh"
adb shell su -c "echo 'ls /opt >/dev/null 2>&1 && exit' >>/opt/optware-init.sh"
adb shell su -c "echo echo Reinitializing optware rootfs links >>/opt/optware-init.sh"
adb shell su -c "echo mount -o rw,remount rootfs / >>/opt/optware-init.sh"
adb shell su -c "echo ln -s $OPTWARE_DIR /opt >>/opt/optware-init.sh"
adb shell su -c "echo ln -s $OPTWARE_DIR/rootlib /lib >>/opt/optware-init.sh"
adb shell su -c "echo ln -s $OPTWARE_DIR/rootbin /bin >>/opt/optware-init.sh"
adb shell su -c "echo ln -s $OPTWARE_DIR/tmp /tmp >>/opt/optware-init.sh"
adb shell su -c "echo mount -o ro,remount rootfs / >>/opt/optware-init.sh"
t_chmod 0755 /opt/optware-init.sh

echo "== Creating optware startup script =="
adb shell su -c "echo #!/system/bin/sh >/opt/optware.sh"
adb shell su -c "echo 'ls /opt >/dev/null 2>&1 ||' su -c $OPTWARE_DIR/optware-init.sh >>/opt/optware.sh"
adb shell su -c "echo export PATH=/opt/sbin:/opt/bin:/bin:/system/bin >>/opt/optware.sh"
adb shell su -c "echo /bin/sh >>/opt/optware.sh"
t_chmod 0755 /opt/optware.sh

t_remount_ro /

echo "Optware for Android installation complete."
echo "To start optware session, execute /opt/optware.sh"
