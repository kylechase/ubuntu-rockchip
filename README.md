## Overview

[![Latest GitHub Release](https://img.shields.io/github/release/Joshua-Riek/ubuntu-rockchip.svg?label=Latest%20Release)](https://github.com/Joshua-Riek/ubuntu-rockchip/releases/latest)
[![Total GitHub Downloads](https://img.shields.io/github/downloads/Joshua-Riek/ubuntu-rockchip/total.svg?&color=E95420&label=Total%20Downloads)](https://github.com/Joshua-Riek/ubuntu-rockchip/releases)
[![Nightly GitHub Build](https://github.com/Joshua-Riek/ubuntu-rockchip/actions/workflows/nightly.yml/badge.svg)](https://github.com/Joshua-Riek/ubuntu-rockchip/actions/workflows/nightly.yml)

Ubuntu Rockchip is a community project porting Ubuntu to Rockchip hardware with the goal of providing a stable and fully functional environment.

## Highlights

* Available for both Ubuntu 22.04 LTS (with Rockchip Linux 5.10) and Ubuntu 24.04 LTS (with Rockchip Linux 6.1)
* Package management via apt using the official Ubuntu repositories
* Receive all updates and changes through apt
* Desktop first-run wizard for user setup and configuration
* 3D hardware acceleration support via panfork
* Fully working GNOME desktop using wayland
* Chromium browser with smooth 4k youtube video playback
* MPV video player capable of smooth 4k video playback

## Installation

Make sure you use a good, reliable, and fast SD card. For example, suppose you encounter boot or stability troubles. Most of the time, this is due to either an insufficient power supply or related to your SD card (bad card, bad card reader, something went wrong when burning the image, or the card is too slow).

Download the Ubuntu image for your specific board from the latest [release](https://github.com/Joshua-Riek/ubuntu-rockchip/releases) on GitHub or from the dedicated download [website](https://joshua-riek.github.io/ubuntu-rockchip-download/). Then write the xz compressed image (no previous unpacking necessary) to your SD card using [USBimager](https://bztsrc.gitlab.io/usbimager/) or [balenaEtcher](https://www.balena.io/etcher) since, unlike other tools, these can validate burning results, saving you from corrupted SD card contents.

## Boot the System

Insert your SD card into the slot on the board and power on the device. The first boot may take up to two minutes, so please be patient.

## Login Information

For Ubuntu Server you will be able to login through HDMI, a serial console connection, or SSH. The predefined user is `ubuntu` and the password is `ubuntu`.

For Ubuntu Desktop you must connect through HDMI and follow the setup-wizard.

## Ubuntu 26.04 LTS on the Turing RK1

This fork adds an Ubuntu 26.04 LTS (Resolute Raccoon) server image for the
Turing RK1, built differently from the other suites:

* **Mainline kernel.** There is no vendor kernel for 26.04: `linux-rockchip` has
  no resolute branch and the `jjriek/rockchip` ppa stops at 25.04. The image
  therefore runs the kernel from the Ubuntu archive (`linux-image-generic`,
  7.0), which carries the upstream Turing RK1 device tree
  (`rockchip/rk3588-turing-rk1.dtb`) and the mainline RK3588 drivers. Hardware
  that only the vendor kernel supports, the video encoders and decoders above
  all, is not available.
* **No ppa.** The `ubuntu-server-rockchip` metapackage and the
  `ubuntu-rockchip-settings` packages are ppa only, so the suite config lists
  the equivalent package set and
  `config/livecd-rootfs/hooks/020-ubuntu-rockchip-tweaks.chroot` ships the few
  configuration files those packages carried. `u-boot-menu` comes from the
  archive, which has the `/etc/kernel/cmdline` support this project relies on.
* **Rootfs built with the livecd-rootfs of the suite.** The older suites use a
  fork of livecd-rootfs pinned to 24.04; 26.04 installs livecd-rootfs from the
  archive instead and patches a copy of it with the hook above. The build host
  has to run the same suite as the image, so builds run on an `ubuntu-26.04`
  runner, or in a container.
* **U-Boot is built from source**, since there is no ppa package for it, which
  is why `--launchpad` is rejected for this suite. U-Boot 2024.01 needs one
  extra patch to compile against the swig of 26.04.
* **The kernel is unwrapped at build time.** 26.04 builds the arm64 kernel with
  `CONFIG_EFI_ZBOOT`, so `/boot/vmlinuz-*` is a PE32+ EFI application with the
  real kernel held compressed inside it. U-Boot boots with `booti`, which only
  takes a bare arm64 Image, and refuses the wrapper with `Bad Linux ARM64 Image
  magic!`. `scripts/config-image.sh` unwraps it with
  `overlay/usr/lib/ubuntu-rockchip/extract-efi-zboot`, and
  `/etc/kernel/postinst.d/zz-efi-zboot-extract` does the same for every kernel
  installed later, so an upgrade does not leave an unbootable image behind.
* **The serial console comes last on the kernel command line.** The kernel makes
  the console named last `/dev/console`, and this board is normally headless, so
  with `console=tty1` last every userspace message, the login prompt and any
  emergency shell included, goes to the dummy console instead of the BMC serial
  port.
* **dracut, not initramfs-tools.** 26.04 generates the initramfs with dracut, so
  the image ships a zstd initrd. The kernel decompresses it
  (`CONFIG_RD_ZSTD=y`), U-Boot does not, so this is fine; the `COMPRESS=gzip`
  drop-in the settings package used to install has no effect under dracut.

* **Time sync works on a network without internet.** chrony is seeded with the
  DHCP advertised NTP server: it reads those from `/run/chrony-dhcp`, which its
  own packaging fills in from a dhclient hook, and these images do DHCP with
  systemd-networkd, so `overlay/etc/networkd-dispatcher/` carries a hook that
  writes it instead. The Ubuntu pools are NTS only, and chrony's default
  `authselectmode` of mix turns those into *required* sources once an
  unauthenticated one exists, so a board that cannot reach them stays
  unsynchronised with the local server excluded from selection;
  `/etc/chrony/conf.d/50-ubuntu-rockchip-authselect.conf` takes authentication
  out of the selection. The pools keep their `prefer` option, so they still win
  wherever they are reachable.

The `ubuntu-rockchip-install` helper, which copies a running system to eMMC or
NVMe, is part of the ppa only settings package and is not in these images.

The resulting image was booted on a Turing RK1 in a Turing Pi board: eMMC,
the serial console, ethernet, cloud-init, the root filesystem growing on first
boot, apparmor and snapd all work on the stock 26.04 kernel.

Only the server flavor is enabled. The desktop images still expect the panfork
and rockchip multimedia ppas, which have no 26.04 packages.

## Building

The build has to run on the same Ubuntu suite as the image. `scripts/build-in-docker.sh`
takes care of that, and works on any Linux host with docker, `qemu-user-static`
registered in `binfmt_misc` and the `loop` module available:

```shell
./scripts/build-in-docker.sh --board=turing-rk1 --suite=resolute --flavor=server
```

On an Ubuntu host of the matching release, `build.sh` can be called directly:

```shell
sudo ./build.sh --board=turing-rk1 --suite=resolute --flavor=server
```

The compressed image lands in `images/`. The serial console on the RK1 is
`ttyS9` at 115200 baud, which is what the Turing Pi BMC exposes.

To debug a boot without hand editing an image, `KERNEL_CMDLINE_EXTRA` is
appended to the kernel command line at build time:

```shell
KERNEL_CMDLINE_EXTRA="rd.info rd.shell systemd.journald.forward_to_console=1" \
    ./scripts/build-in-docker.sh --board=turing-rk1 --suite=resolute --flavor=server
```

One caveat for local builds: the snap preseeding stage of livecd-rootfs mounts
the apparmor feature set of the build host into the chroot, so it only works on
a host whose kernel has apparmor enabled. On a host without it (Arch, for
example) `lb build` fails at that point, the build continues with a complete
but snapless rootfs, and the log says so. Images built on the `ubuntu-26.04`
runner get the seeded snaps.

## Installing to another disk

`ubuntu-rockchip-install` copies the running system onto another disk, which
replaces the helper of the same name from the ppa only settings package:

```shell
sudo ubuntu-rockchip-install --boot=current /dev/nvme0n1
```

`--boot` decides where the kernel, the initrd and the extlinux config end up:

* `target`, the default, puts them on the target disk, which the bootloader has
  to be able to read. The installer chroots into the new system to write its
  extlinux config.
* `current` keeps them on the disk the board boots from and has the installed
  system mount that disk at `/mnt/bootdisk`, with `/mnt/bootdisk/boot` bind
  mounted over `/boot`, so a later kernel update still lands where the
  bootloader reads it.

The Turing RK1 needs `--boot=current` for an NVMe target: its U-Boot does not
bring up the PCIe link, so it cannot read a kernel from the drive even though
Linux uses it fine. The boot rom cannot load a bootloader from NVMe either, so
U-Boot always stays on the eMMC or the SPI flash; it is only written to the
target for sd and eMMC targets, and `--bootloader` or `--no-bootloader` override
that.

## Support the Project

There are a few things you can do to support the project:

* Star the repository and follow me on GitHub
* Share and upvote on sites like Twitter, Reddit, and YouTube
* Report any bugs, glitches, or errors that you find (some bugs I may not be able to fix)
* Sponsor me on GitHub; any contribution will be greatly appreciated

These things motivate me to continue development and provide validation that my work is appreciated. Thanks in advance!

---
> Ubuntu is a trademark of Canonical Ltd. Rockchip is a trademark of Fuzhou Rockchip Electronics Co., Ltd. The Ubuntu Rockchip project is not affiliated with Canonical Ltd or Fuzhou Rockchip Electronics Co., Ltd. All other product names, logos, and brands are property of their respective owners. The Ubuntu name is owned by [Canonical Limited](https://ubuntu.com/).
