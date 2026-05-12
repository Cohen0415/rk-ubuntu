#!/bin/bash -e

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

GPU_STACK="${RK_UBUNTU_GPU_STACK:-panfrost}"
case "$GPU_STACK" in
    panfrost|libmali)
        ;;
    *)
        echo "Unsupported RK_UBUNTU_GPU_STACK: $GPU_STACK"
        echo "Supported values: panfrost, libmali"
        exit 1
        ;;
esac
echo -e "\033[36m GPU stack: $GPU_STACK \033[0m"

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
sudo cp -rpf packages/$ARCH/* $TARGET_ROOTFS_DIR/packages

# overlay folder
sudo cp -rpf overlay/* $TARGET_ROOTFS_DIR/

# overlay-firmware folder
sudo cp -rpf overlay-firmware/* $TARGET_ROOTFS_DIR/

# overlay-debug folder
# adb, video, camera  test file
sudo cp -rpf overlay-debug/* $TARGET_ROOTFS_DIR/

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
export APT_INSTALL="apt-get install -fy --allow-downgrades"
GPU_STACK="$GPU_STACK"

# Fixup owners
if [ "$ID" -ne 0 ]; then
       find / -user $ID -exec chown -h 0:0 {} \;
fi
for u in \$(ls /home/); do
	chown -h -R \$u:\$u /home/\$u
done

ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

apt-get update
apt-get upgrade -y

chmod o+x /usr/lib/dbus-1.0/dbus-daemon-launch-helper
chmod +x /etc/rc.local

apt purge initramfs-tools -y

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
echo "\$GPU_STACK" > /etc/gpu-stack
if [ "\$GPU_STACK" = "panfrost" ]; then
    apt-get purge -y 'libmali*' || true
    \${APT_INSTALL} libegl-mesa0 libgl1-mesa-dri libglx-mesa0 libgles2 libdrm2 libdrm-common
else
    \${APT_INSTALL} /packages/libmali/libmali-bifrost-g52-g13p0-x11-wayland-gbm_1.9-1_arm64.deb
fi

echo -e "\033[47;36m ----------- AIQ  ----------- \033[0m"
\${APT_INSTALL} /packages/rkaiq/camera_engine_rkaiq_rk3568_arm64.deb    

echo -e "\033[47;36m ----------- RGA  ----------- \033[0m"
\${APT_INSTALL} /packages/rga2/*.deb

if [[ "$TARGET" == "desktop" ]]; then
    echo -e "\033[47;36m ------ Setup Video---------- \033[0m"
    \${APT_INSTALL} gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-plugins-ugly gstreamer1.0-tools gstreamer1.0-alsa \
    gstreamer1.0-plugins-base-apps

    \${APT_INSTALL} /packages/mpp/*
    \${APT_INSTALL} /packages/gst-rkmpp/*.deb
    \${APT_INSTALL} /packages/gstreamer/*.deb
elif [ "$TARGET" == "base" ]; then
    echo -e "\033[47;36m ------ Setup Video---------- \033[0m"
    \${APT_INSTALL} /packages/mpp/*
    \${APT_INSTALL} /packages/gst-rkmpp/*.deb
fi

if [[ "$TARGET" == "desktop" ]]; then
    echo -e "\033[47;36m ----- Install Xserver------- \033[0m"
    if [ "\$GPU_STACK" = "panfrost" ]; then
        \${APT_INSTALL} xserver-common xserver-xorg-core xserver-xorg-legacy
    else
        \${APT_INSTALL} /packages/xserver/*.deb
        apt-mark hold xserver-common xserver-xorg-core xserver-xorg-legacy xserver-xorg-dev
    fi
fi

if [[ "$TARGET" == "desktop" ]]; then
    echo -e "\033[47;36m ----- Install Camera ------- \033[0m"
    \${APT_INSTALL} cheese v4l-utils

    echo -e "\033[47;36m ----- Wayland/Weston ------- \033[0m"
    \${APT_INSTALL} libseat-dev
    \${APT_INSTALL} /packages/wayland/*.deb

    # echo -e "\033[47;36m ------ Install openbox ----- \033[0m"
    # \${APT_INSTALL} /packages/openbox/*.deb

    echo -e "\033[47;36m ------ update chromium ----- \033[0m"
    \${APT_INSTALL} /packages/chromium/*.deb
    if [ "\$GPU_STACK" = "panfrost" ]; then
        # The Rockchip chromium binary is linked against libmali, but the
        # desktop stack must stay on Mesa/Panfrost. Keep the libmali runtime
        # private to chromium by placing it in chromium's own library path.
        mkdir -p /tmp/libmali-chromium
        dpkg-deb -x /packages/libmali/libmali-bifrost-g52-g13p0-x11-wayland-gbm_1.9-1_arm64.deb /tmp/libmali-chromium
        cp -a /tmp/libmali-chromium/usr/lib/aarch64-linux-gnu/libmali.so* /usr/lib/chromium/
        cp -a /tmp/libmali-chromium/usr/lib/aarch64-linux-gnu/libmali-hook.so* /usr/lib/chromium/
        rm -rf /tmp/libmali-chromium
    fi

    # echo -e "\033[47;36m --------- firefox-esr ------ \033[0m"
    # \${APT_INSTALL} /packages/firefox/*.deb
fi

echo -e "\033[47;36m ------- Install libdrm ------ \033[0m"
if [ "\$GPU_STACK" = "panfrost" ]; then
    \${APT_INSTALL} libdrm2 libdrm-common
else
    \${APT_INSTALL} /packages/libdrm/*.deb
fi

if [[ "$TARGET" == "desktop" ]]; then
    if [ "\$GPU_STACK" = "libmali" ]; then
        echo -e "\033[47;36m ------ libdrm-cursor -------- \033[0m"
        \${APT_INSTALL} /packages/libdrm-cursor/*.deb
    fi
fi

if [ -e "/usr/lib/aarch64-linux-gnu" ]; then
    echo -e "\033[47;36m ------- move rknpu2 --------- \033[0m"
    mv /packages/rknpu2/rknpu2.tar  /
fi

echo -e "\033[47;36m ----- Install rktoolkit ----- \033[0m"
\${APT_INSTALL} /packages/rktoolkit/*.deb

apt autoremove -y

# mark package to hold
apt list --upgradable | cut -d/ -f1 | xargs apt-mark hold

echo -e "\033[47;36m ------- Custom Script ------- \033[0m"
systemctl mask systemd-networkd-wait-online.service
systemctl mask NetworkManager-wait-online.service
systemctl disable hostapd
rm /lib/systemd/system/wpa_supplicant@.service
if [ "\$GPU_STACK" = "panfrost" ]; then
    systemctl disable rockchip.service || true
    rm -f /etc/systemd/system/sysinit.target.wants/rockchip.service
fi

echo -e "\033[47;36m  ---------- Clean ----------- \033[0m"
if [ "\$GPU_STACK" = "libmali" ] && [ -e "/usr/lib/arm-linux-gnueabihf/dri" ] ;
then
    # Only preload libdrm-cursor for X
    sed -i "1aexport LD_PRELOAD=/usr/lib/arm-linux-gnueabihf/libdrm-cursor.so.1" /usr/bin/X
    cd /usr/lib/arm-linux-gnueabihf/dri/
    cp kms_swrast_dri.so swrast_dri.so rockchip_dri.so /
    rm /usr/lib/arm-linux-gnueabihf/dri/*.so
    mv /*.so /usr/lib/arm-linux-gnueabihf/dri/
elif [ "\$GPU_STACK" = "libmali" ] && [ -e "/usr/lib/aarch64-linux-gnu/dri" ];
then
    # Only preload libdrm-cursor for X
    sed -i "1aexport LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libdrm-cursor.so.1" /usr/bin/X
    cd /usr/lib/aarch64-linux-gnu/dri/
    cp kms_swrast_dri.so swrast_dri.so rockchip_dri.so /
    rm /usr/lib/aarch64-linux-gnu/dri/*.so
    mv /*.so /usr/lib/aarch64-linux-gnu/dri/
    rm /etc/profile.d/qt.sh
elif [ "\$GPU_STACK" = "panfrost" ]; then
    rm -f /etc/X11/xorg.conf.d/*rockchip* /usr/share/X11/xorg.conf.d/*rockchip*
    find /etc/X11/xorg.conf.d /usr/share/X11/xorg.conf.d -type f \
        -exec grep -l "RockchipDRM\\|FlipFB\\|NoEDID" {} \; 2>/dev/null | \
        xargs -r rm -f

    # RK3568 VOP2 can reject the hardware cursor/flip format used by the
    # generic modesetting driver, which causes cursor movement flicker.
    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/xorg.conf.d/20-panfrost-modesetting.conf <<'XORGEOF'
Section "Device"
    Identifier  "Panfrost Modesetting"
    Driver      "modesetting"
    Option      "AccelMethod"    "glamor"
    Option      "DRI"            "2"
    Option      "PageFlip"       "false"
    Option      "SWcursor"       "true"
EndSection
XORGEOF
fi

rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/
rm -rf /packages/
rm -rf /boot/*

EOF
trap - ERR
./ch-mount.sh -u "$TARGET_ROOTFS_DIR"
