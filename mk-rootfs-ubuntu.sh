#!/bin/bash -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common/chip.sh"
rk_ubuntu_load_chip

TARGET="${TARGET:-desktop}"

# Directory contains the target rootfs
TARGET_ROOTFS_DIR="binary"

case "${ARCH:-$1}" in
	arm|arm32|armhf)
		ARCH=armhf
		;;
	*)
		ARCH=arm64
		;;
esac

echo -e "\033[36m Building for $ARCH \033[0m"

if [ ! -e ubuntu-rootfs.tar.gz ]; then
    echo "\033[41;36m Run mk-base-ubuntu.sh first \033[0m"
    exit -1
fi

finish() 
{
    ./ch-mount.sh -u "$TARGET_ROOTFS_DIR" >/dev/null 2>&1 || true
    exit -1
}
trap finish ERR

echo -e "\033[47;36m Extract image \033[0m"
sudo rm -rf $TARGET_ROOTFS_DIR
sudo tar -xpf ubuntu-rootfs.tar.gz

# packages folder
sudo mkdir -p $TARGET_ROOTFS_DIR/packages
if [ -d "$RK_UBUNTU_PACKAGES_DIR/$ARCH" ]; then
    sudo cp -rpf "$RK_UBUNTU_PACKAGES_DIR/$ARCH"/. $TARGET_ROOTFS_DIR/packages
else
    echo "Missing packages directory: $RK_UBUNTU_PACKAGES_DIR/$ARCH"
    exit 1
fi

# common overlay folder
if [ -d "$RK_UBUNTU_COMMON_OVERLAY_DIR" ]; then
    sudo cp -rpf "$RK_UBUNTU_COMMON_OVERLAY_DIR"/. $TARGET_ROOTFS_DIR/
fi

# chip overlay folder
if [ -d "$RK_UBUNTU_OVERLAY_DIR" ]; then
    sudo cp -rpf "$RK_UBUNTU_OVERLAY_DIR"/. $TARGET_ROOTFS_DIR/
fi

# overlay-firmware folder
if [ -d "$RK_UBUNTU_OVERLAY_FIRMWARE_DIR" ]; then
    sudo cp -rpf "$RK_UBUNTU_OVERLAY_FIRMWARE_DIR"/. $TARGET_ROOTFS_DIR/
fi

# overlay-debug folder
# adb, video, camera  test file
if [ -d "$RK_UBUNTU_OVERLAY_DEBUG_DIR" ]; then
    sudo cp -rpf "$RK_UBUNTU_OVERLAY_DEBUG_DIR"/. $TARGET_ROOTFS_DIR/
fi

# Prevent dpkg interactive dialogues
export DEBIAN_FRONTEND=noninteractive

echo -e "\033[36m Change root.....................\033[0m"
if [ "$ARCH" == "armhf" ]; then
    sudo cp /usr/bin/qemu-arm-static $TARGET_ROOTFS_DIR/usr/bin/
elif [ "$ARCH" == "arm64"  ]; then
    sudo cp /usr/bin/qemu-aarch64-static $TARGET_ROOTFS_DIR/usr/bin/
fi

./ch-mount.sh -m "$TARGET_ROOTFS_DIR"

ID=$(stat --format %u $TARGET_ROOTFS_DIR)

cat << EOF | sudo chroot $TARGET_ROOTFS_DIR

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export APT_GET="apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
export APT_INSTALL="\${APT_GET} install -fy --allow-downgrades"
RKAIQ_DEB="$RK_UBUNTU_RKAIQ_DEB"
GPU_DEBS="$RK_UBUNTU_GPU_DEBS"
VERSION="${VERSION:-release}"

# Fixup owners
if [ "$ID" -ne 0 ]; then
       find / -user $ID -exec chown -h 0:0 {} \;
fi
for u in \$(ls /home/); do
	chown -h -R \$u:\$u /home/\$u
done

ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

apt-get update
\${APT_GET} upgrade -y

chmod o+x /usr/lib/dbus-1.0/dbus-daemon-launch-helper
chmod +x /etc/rc.local

\${APT_GET} purge initramfs-tools -y

\${APT_INSTALL} dialog toilet u-boot-tools edid-decode logrotate
if [[ "$TARGET" == "desktop" ]]; then
    \${APT_INSTALL} gdisk 
    #Desktop background picture
    #ln -sf /usr/share/xfce4/backdrops/lubancat-wallpaper.png /usr/share/backgrounds/warty-final-ubuntu.png
elif [ "$TARGET" == "base" ]; then
    \${APT_INSTALL} bluez bluez-tools
fi

echo -e "\033[47;36m ----- power management ----- \033[0m"
\${APT_INSTALL} pm-utils triggerhappy bsdmainutils
cp /etc/Powermanager/triggerhappy.service  /lib/systemd/system/triggerhappy.service
sed -i "s/#HandlePowerKey=.*/HandlePowerKey=ignore/" /etc/systemd/logind.conf

echo -e "\033[47;36m ----------- GPU  ----------- \033[0m"
if ls /packages/libgpgerror/*.deb >/dev/null 2>&1; then
    \${APT_INSTALL} /packages/libgpgerror/*.deb
fi
if ls /packages/libgcrypt20/*.deb >/dev/null 2>&1; then
    \${APT_INSTALL} /packages/libgcrypt20/*.deb
fi
for deb in \$GPU_DEBS; do
    if [ -e "\$deb" ]; then
        \${APT_INSTALL} "\$deb"
    fi
done
if ls /packages/libdrm/*.deb >/dev/null 2>&1; then
    \${APT_INSTALL} /packages/libdrm/*.deb
fi

echo -e "\033[47;36m ----------- AIQ  ----------- \033[0m"
if [ -n "\$RKAIQ_DEB" ] && [ -e "\$RKAIQ_DEB" ]; then
    \${APT_INSTALL} "\$RKAIQ_DEB"
fi

echo -e "\033[47;36m ----------- RGA  ----------- \033[0m"
if ls /packages/rga2/*.deb >/dev/null 2>&1; then
    \${APT_INSTALL} /packages/rga2/*.deb
fi

if [[ "$TARGET" == "desktop" ]]; then
    echo -e "\033[47;36m ------ Setup Video---------- \033[0m"
    \${APT_INSTALL} gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-plugins-ugly gstreamer1.0-tools gstreamer1.0-alsa \
    gstreamer1.0-plugins-base-apps

    if ls /packages/mpp/*.deb >/dev/null 2>&1; then
        \${APT_INSTALL} /packages/mpp/*.deb
    fi
    if ls /packages/gst-rkmpp/*.deb >/dev/null 2>&1; then
        \${APT_INSTALL} /packages/gst-rkmpp/*.deb
    fi
    if ls /packages/gstreamer/*.deb >/dev/null 2>&1; then
        \${APT_INSTALL} /packages/gstreamer/*.deb
    fi
elif [ "$TARGET" == "base" ]; then
    echo -e "\033[47;36m ------ Setup Video---------- \033[0m"
    if ls /packages/mpp/*.deb >/dev/null 2>&1; then
        \${APT_INSTALL} /packages/mpp/*.deb
    fi
    if ls /packages/gst-rkmpp/*.deb >/dev/null 2>&1; then
        \${APT_INSTALL} /packages/gst-rkmpp/*.deb
    fi
fi

if [[ "$TARGET" == "desktop" ]]; then
    echo -e "\033[47;36m ---- Reinstall GStreamer ---- \033[0m"
    if ls /packages/gstreamer/*.deb >/dev/null 2>&1; then
        dpkg -i /packages/gstreamer/*.deb || \${APT_GET} install -f -y
    fi
    if ls /packages/gst-plugins-base1.0/*.deb >/dev/null 2>&1; then
        dpkg -i /packages/gst-plugins-base1.0/*.deb || \${APT_GET} install -f -y
    fi
    if ls /packages/gst-plugins-good1.0/*.deb >/dev/null 2>&1; then
        dpkg -i /packages/gst-plugins-good1.0/*.deb || \${APT_GET} install -f -y
    fi
    if ls /packages/gst-plugins-bad1.0/*.deb >/dev/null 2>&1; then
        dpkg -i --force-overwrite /packages/gst-plugins-bad1.0/*.deb || \${APT_GET} install -f -y
    fi
fi

if [[ "$TARGET" == "desktop" ]]; then
    echo -e "\033[47;36m ----- Install Xserver------- \033[0m"
    if ls /packages/xserver/*.deb >/dev/null 2>&1; then
        \${APT_INSTALL} /packages/xserver/*.deb
        apt-mark hold xserver-common xserver-xorg-core xserver-xorg-legacy xserver-xorg-dev
    fi
fi

if [[ "$TARGET" == "desktop" ]]; then
    echo -e "\033[47;36m ----- Install Camera ------- \033[0m"
    \${APT_INSTALL} cheese v4l-utils
    if ls /packages/libv4l/*.deb >/dev/null 2>&1; then
        \${APT_INSTALL} /packages/libv4l/*.deb
    fi
    if ls /packages/rkisp/*.deb >/dev/null 2>&1; then
        \${APT_INSTALL} /packages/rkisp/*.deb
    fi
    if [ -d /etc/3A ]; then
        mkdir -p /etc/iqfiles
        [ -d /etc/3A/bin ] && mv /etc/3A/bin/* /usr/bin/ 2>/dev/null || true
        [ -d /etc/3A/iqfiles ] && mv /etc/3A/iqfiles/* /etc/iqfiles/ 2>/dev/null || true
        rm -rf /etc/3A
    fi

    echo -e "\033[47;36m ----- Wayland/Weston ------- \033[0m"
    \${APT_INSTALL} libseat-dev
    \${APT_INSTALL} /packages/wayland/*.deb

    # echo -e "\033[47;36m ------ Install openbox ----- \033[0m"
    # \${APT_INSTALL} /packages/openbox/*.deb

    echo -e "\033[47;36m ------ update chromium ----- \033[0m"
    if ls /packages/chromium/*.deb >/dev/null 2>&1; then
        \${APT_INSTALL} /packages/chromium/*.deb
    fi
    \${APT_GET} purge tilix -y || true

    # echo -e "\033[47;36m --------- firefox-esr ------ \033[0m"
    # \${APT_INSTALL} /packages/firefox/*.deb
fi

if [[ "$TARGET" == "desktop" ]]; then
    if ls /packages/libdrm-cursor/*.deb >/dev/null 2>&1; then
        echo -e "\033[47;36m ------ libdrm-cursor -------- \033[0m"
        \${APT_INSTALL} /packages/libdrm-cursor/*.deb
    fi
fi

echo -e "\033[47;36m ----- Install Wi-Fi/BT ------ \033[0m"
if ls /packages/rkwifibt/*.deb >/dev/null 2>&1; then
    \${APT_INSTALL} /packages/rkwifibt/*.deb
    mkdir -p /vendor/etc
    if [ ! -e /vendor/etc/firmware ]; then
        ln -s /system/etc/firmware /vendor/etc/firmware
    fi
    [ -e /etc/wifi/rkwifibt.sh ] && mv /etc/wifi/rkwifibt.sh /etc/init.d/
    [ -e /etc/wifi/rk_wifi_init ] && mv /etc/wifi/rk_wifi_init /usr/bin/
    rm -rf /etc/wifi
fi

if [ "$VERSION" = "debug" ] && ls /packages/glmark2/*.deb >/dev/null 2>&1; then
    echo -e "\033[47;36m ------ Install glmark ------- \033[0m"
    \${APT_INSTALL} /packages/glmark2/*.deb
fi

if [ -e "/usr/lib/aarch64-linux-gnu" ] && [ -e /packages/rknpu2/rknpu2.tar ]; then
    echo -e "\033[47;36m ------- install rknpu2 ------- \033[0m"
    tar -xvf /packages/rknpu2/rknpu2.tar -C /
fi

echo -e "\033[47;36m ----- Install rktoolkit ----- \033[0m"
if ls /packages/rktoolkit/*.deb >/dev/null 2>&1; then
    \${APT_INSTALL} /packages/rktoolkit/*.deb
fi

\${APT_GET} autoremove -y

# mark package to hold
apt list --upgradable | cut -d/ -f1 | xargs apt-mark hold

echo -e "\033[47;36m ------- Custom Script ------- \033[0m"
systemctl mask systemd-networkd-wait-online.service
systemctl mask NetworkManager-wait-online.service
systemctl disable hostapd || true
systemctl enable rkwifibt.service || true
rm -f /lib/systemd/system/wpa_supplicant@.service

echo -e "\033[47;36m  ---------- Clean ----------- \033[0m"
if [ -n "\$GPU_DEBS" ] && [ -e "/usr/lib/arm-linux-gnueabihf/dri" ] ;
then
    # Only preload libdrm-cursor for X
    if [ -e /usr/bin/X ]; then
        sed -i "1aexport LD_PRELOAD=/usr/lib/arm-linux-gnueabihf/libdrm-cursor.so.1" /usr/bin/X
    fi
    cd /usr/lib/arm-linux-gnueabihf/dri/
    cp kms_swrast_dri.so swrast_dri.so rockchip_dri.so /
    rm /usr/lib/arm-linux-gnueabihf/dri/*.so
    mv /*.so /usr/lib/arm-linux-gnueabihf/dri/
elif [ -n "\$GPU_DEBS" ] && [ -e "/usr/lib/aarch64-linux-gnu/dri" ];
then
    # Only preload libdrm-cursor for X
    if [ -e /usr/bin/X ]; then
        sed -i "1aexport LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libdrm-cursor.so.1" /usr/bin/X
    fi
    cd /usr/lib/aarch64-linux-gnu/dri/
    cp kms_swrast_dri.so swrast_dri.so rockchip_dri.so /
    rm /usr/lib/aarch64-linux-gnu/dri/*.so
    mv /*.so /usr/lib/aarch64-linux-gnu/dri/
    rm /etc/profile.d/qt.sh
fi

rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/
rm -rf /packages/
rm -rf /boot/*

EOF
trap - ERR
./ch-mount.sh -u "$TARGET_ROOTFS_DIR"
