## Introduction

A set of shell scripts that will build GNU/Linux distribution rootfs image
for rockchip platform.

## Multi-chip layout

This repository keeps chip-specific Ubuntu resources under `chips/<chip>/`.

```
chips/
  rk3568/
    chip.conf
    apt-lists/
    post-install.d/
    packages/arm64/
    overlay/
    overlay-firmware/
    overlay-debug/
  rk3576/
    chip.conf
  rk3588/
    chip.conf

versions/
  22.04/
    sources.list

common/
  apt-lists/
  overlay/
  post-install.d/
```

When multiple chips are present, `mk-base-ubuntu.sh` and `mk-rootfs-ubuntu.sh`
show a chip selection menu in an interactive terminal. You can also select a
chip non-interactively:

```
RK_UBUNTU_CHIP=rk3568 UBUNTU_VERSION=22.04 TARGET=desktop ARCH=arm64 ./mk-base-ubuntu.sh
RK_UBUNTU_CHIP=rk3568 TARGET=desktop ARCH=arm64 ./mk-rootfs-ubuntu.sh
TARGET=desktop ./mk-image.sh
```

`UBUNTU_VERSION` defaults to `22.04`, `TARGET` defaults to `desktop`, and
`ARCH` defaults to `arm64` when they are not provided.

To add rk3576 or rk3588, put its packages, package install lists, post-install
hooks, and overlays under the matching `chips/<chip>/` directory.

Ubuntu release-specific files belong under `versions/<ubuntu-version>/`, for
example `versions/22.04/sources.list`.

Shared rootfs overlay files belong under `common/overlay/`. The build copies
`common/overlay/` first, then copies `chips/<chip>/overlay/` so chip-specific
files can override common defaults.

## Package install lists

`mk-rootfs-ubuntu.sh` installs packages from list files instead of hard-coding
chip package paths in the main script.

```
common/apt-lists/common.list
common/apt-lists/base.list
common/apt-lists/desktop.list
chips/<chip>/apt-lists/common.list
chips/<chip>/apt-lists/base.list
chips/<chip>/apt-lists/desktop.list
```

Each non-empty line starts with an action:

```
apt package-name another-package
deb /packages/some-dir/*.deb
dpkg /packages/some-dir/*.deb
dpkg-force-overwrite /packages/some-dir/*.deb
debug-deb /packages/glmark2/*.deb
hold package-name
purge package-name
extract /packages/rknpu2/rknpu2.tar /
```

Use `apt` for repository packages, `deb` for local `.deb` packages that apt can
resolve, `dpkg` when a package set must be reinstalled in place, and
`dpkg-force-overwrite` for package sets that intentionally overwrite files from
existing packages.

Non-package fixups belong in `common/post-install.d/*.sh` or
`chips/<chip>/post-install.d/*.sh`. For example, rk3576 uses hooks for camera
3A file placement and Wi-Fi/BT package layout cleanup.

## Available Distro

* Debian 11 (Bullseye-X11 and Wayland)~~

```
sudo apt-get install binfmt-support qemu-user-static
sudo dpkg -i ubuntu-build-service/packages/*
sudo apt-get install -f
```

## Usage for 32bit Debian 11 (Bullseye-32)

### Building debian system from linaro

Building a base debian system by ubuntu-build-service from linaro.

```
	RELEASE=bullseye TARGET=base ARCH=armhf ./mk-base-debian.sh
```

Building a desktop debian system by ubuntu-build-service from linaro.

```
	RELEASE=bullseye TARGET=desktop ARCH=armhf ./mk-base-debian.sh
```

### Building overlay with rockchip audio/video hardware accelerated

- Building with overlay with rockchip debian rootfs:

```
	RELEASE=bullseye ARCH=armhf ./mk-rootfs.sh
```

- Building with overlay with rockchip debug debian rootfs:

```
	VERSION=debug ARCH=armhf ./mk-rootfs-bullseye.sh
```

### Creating roofs image

Creating the ext4 image(linaro-rootfs.img):

```
	./mk-image.sh
```

---

## Usage for 64bit Debian 11 (Bullseye-64)

### Building debian system from linaro

Building a base debian system by ubuntu-build-service from linaro.

```
	RELEASE=bullseye TARGET=desktop ARCH=arm64 ./mk-base-debian.sh
```

### Building overlay with rockchip audio/video hardware accelerated

- Building the rk-debian rootfs

```
	RELEASE=bullseye ARCH=arm64 ./mk-rootfs.sh
```

- Building the rk-debain rootfs with debug

```
	VERSION=debug ARCH=arm64 ./mk-rootfs-bullseye.sh
```

### Creating roofs image

Creating the ext4 image(linaro-rootfs.img):

```
	./mk-image.sh
```
---

## Cross Compile for ARM Debian

[Docker + Multiarch](http://opensource.rock-chips.com/wiki_Cross_Compile#Docker)

## Package Code Base

Please apply [those patches](https://github.com/rockchip-linux/rk-rootfs-build/tree/master/packages-patches) to release code base before rebuilding!

## License information

Please see [debian license](https://www.debian.org/legal/licenses/)

## FAQ

- noexec or nodev issue
noexec or nodev issue /usr/share/debootstrap/functions: line 1450:
../rootfs/ubuntu-build-service/bullseye-desktop-arm64/chroot/test-dev-null:
Permission denied E: Cannot install into target
...
mounted with noexec or nodev

Solution: mount -o remount,exec,dev xxx (xxx is the mount place), then rebuild it.
