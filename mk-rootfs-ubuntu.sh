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

# apt package lists
sudo mkdir -p "$TARGET_ROOTFS_DIR/tmp/rk-ubuntu-apt-lists/common" "$TARGET_ROOTFS_DIR/tmp/rk-ubuntu-apt-lists/chip"
if [ -d "$RK_UBUNTU_COMMON_APT_LISTS_DIR" ]; then
    sudo cp -rpf "$RK_UBUNTU_COMMON_APT_LISTS_DIR"/. "$TARGET_ROOTFS_DIR/tmp/rk-ubuntu-apt-lists/common/"
fi
if [ -d "$RK_UBUNTU_APT_LISTS_DIR" ]; then
    sudo cp -rpf "$RK_UBUNTU_APT_LISTS_DIR"/. "$TARGET_ROOTFS_DIR/tmp/rk-ubuntu-apt-lists/chip/"
fi

# post-install hooks
sudo mkdir -p "$TARGET_ROOTFS_DIR/tmp/rk-ubuntu-post-install.d/common" "$TARGET_ROOTFS_DIR/tmp/rk-ubuntu-post-install.d/chip"
if [ -d "$RK_UBUNTU_COMMON_POST_INSTALL_DIR" ]; then
    sudo cp -rpf "$RK_UBUNTU_COMMON_POST_INSTALL_DIR"/. "$TARGET_ROOTFS_DIR/tmp/rk-ubuntu-post-install.d/common/"
fi
if [ -d "$RK_UBUNTU_POST_INSTALL_DIR" ]; then
    sudo cp -rpf "$RK_UBUNTU_POST_INSTALL_DIR"/. "$TARGET_ROOTFS_DIR/tmp/rk-ubuntu-post-install.d/chip/"
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

install_deb_glob()
{
    local pattern="\$1"
    if compgen -G "\$pattern" >/dev/null; then
        \${APT_INSTALL} \$pattern
    fi
}

install_dpkg_glob()
{
    local pattern="\$1"
    if compgen -G "\$pattern" >/dev/null; then
        dpkg -i \$pattern || \${APT_GET} install -f -y
    fi
}

install_dpkg_force_overwrite_glob()
{
    local pattern="\$1"
    if compgen -G "\$pattern" >/dev/null; then
        dpkg -i --force-overwrite \$pattern || \${APT_GET} install -f -y
    fi
}

process_apt_list()
{
    local list_file="\$1"
    local line action args src dst

    [ -f "\$list_file" ] || return 0
    echo -e "\033[47;36m ---- Apt list: \$list_file ---- \033[0m"

    while IFS= read -r line || [ -n "\$line" ]; do
        line="\${line%%#*}"
        line="\$(printf '%s' "\$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//')"
        [ -n "\$line" ] || continue

        action="\${line%%[[:space:]]*}"
        if [ "\$action" = "\$line" ]; then
            args=""
        else
            args="\${line#"\$action"}"
            args="\$(printf '%s' "\$args" | sed 's/^[[:space:]]*//')"
        fi

        case "\$action" in
            apt)
                [ -n "\$args" ] && \${APT_INSTALL} \$args
                ;;
            deb)
                [ -n "\$args" ] && install_deb_glob "\$args"
                ;;
            dpkg)
                [ -n "\$args" ] && install_dpkg_glob "\$args"
                ;;
            dpkg-force-overwrite)
                [ -n "\$args" ] && install_dpkg_force_overwrite_glob "\$args"
                ;;
            debug-deb)
                if [ "\$VERSION" = "debug" ] && [ -n "\$args" ]; then
                    install_deb_glob "\$args"
                fi
                ;;
            hold)
                [ -n "\$args" ] && apt-mark hold \$args
                ;;
            purge)
                [ -n "\$args" ] && \${APT_GET} purge -y \$args || true
                ;;
            extract)
                read -r src dst << EXTRACT_ARGS
\$args
EXTRACT_ARGS
                dst="\${dst:-/}"
                if [ -n "\$src" ] && [ -e "\$src" ]; then
                    tar -xvf "\$src" -C "\$dst"
                fi
                ;;
            *)
                echo "Unknown apt-list action '\$action' in \$list_file: \$line" >&2
                exit 1
                ;;
        esac
    done < "\$list_file"
}

run_post_install_hooks()
{
    local hook

    for hook in /tmp/rk-ubuntu-post-install.d/common/*.sh /tmp/rk-ubuntu-post-install.d/chip/*.sh; do
        [ -f "\$hook" ] || continue
        echo -e "\033[47;36m ---- Post install: \$hook ---- \033[0m"
        bash "\$hook"
    done
}

process_apt_list /tmp/rk-ubuntu-apt-lists/common/common.list
process_apt_list /tmp/rk-ubuntu-apt-lists/chip/common.list
if [[ "$TARGET" == "desktop" ]]; then
    process_apt_list /tmp/rk-ubuntu-apt-lists/common/desktop.list
    process_apt_list /tmp/rk-ubuntu-apt-lists/chip/desktop.list
elif [ "$TARGET" == "base" ]; then
    process_apt_list /tmp/rk-ubuntu-apt-lists/common/base.list
    process_apt_list /tmp/rk-ubuntu-apt-lists/chip/base.list
fi

run_post_install_hooks

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
if compgen -G "/usr/lib/arm-linux-gnueabihf/libmali*.so*" >/dev/null && [ -e "/usr/lib/arm-linux-gnueabihf/dri" ] ;
then
    # Only preload libdrm-cursor for X
    if [ -e /usr/bin/X ]; then
        sed -i "1aexport LD_PRELOAD=/usr/lib/arm-linux-gnueabihf/libdrm-cursor.so.1" /usr/bin/X
    fi
    cd /usr/lib/arm-linux-gnueabihf/dri/
    cp kms_swrast_dri.so swrast_dri.so rockchip_dri.so /
    rm /usr/lib/arm-linux-gnueabihf/dri/*.so
    mv /*.so /usr/lib/arm-linux-gnueabihf/dri/
elif compgen -G "/usr/lib/aarch64-linux-gnu/libmali*.so*" >/dev/null && [ -e "/usr/lib/aarch64-linux-gnu/dri" ];
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
rm -rf /tmp/rk-ubuntu-apt-lists/
rm -rf /tmp/rk-ubuntu-post-install.d/
rm -rf /boot/*

EOF
trap - ERR
./ch-mount.sh -u "$TARGET_ROOTFS_DIR"
