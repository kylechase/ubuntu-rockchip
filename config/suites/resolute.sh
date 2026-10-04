# shellcheck shell=bash

export RELASE_NAME="Ubuntu 26.04 LTS (Resolute Raccoon)"
export RELASE_VERSION="26.04"

# There is no vendor kernel for this suite: linux-rockchip has no resolute
# branch and the jjriek PPAs stop at plucky. Mainline is used instead, since
# the stock Ubuntu kernel carries the Turing RK1 device tree
# (rockchip/rk3588-turing-rk1.dtb) and supports the RK3588 well enough.
export KERNEL_SOURCE="archive"
export KERNEL_FLAVOR="generic"

# Build the rootfs with the livecd-rootfs of this suite, patched with the hook
# in config/livecd-rootfs, instead of the noble era fork the older suites use.
export LIVECD_ROOTFS_SOURCE="archive"

# No rockchip PPA is published for this suite
export EXTRA_PPAS=""

# Only the leaf snaps are listed, livecd-rootfs seeds their bases
export SEEDED_SNAPS="snapd/classic=stable lxd/classic=stable"

# The ubuntu-rockchip metapackages are PPA only, so spell out what
# ubuntu-server-rockchip would have pulled in. The settings packages are
# replaced by config/livecd-rootfs/hooks/020-ubuntu-rockchip-tweaks.chroot
export ROOTFS_PACKAGES_SERVER="ubuntu-server u-boot-menu u-boot-tools mtd-utils
chrony fake-hwclock curl git htop openssh-server lm-sensors bluez usb-modeswitch
usb-modeswitch-data wireless-regdb rfkill wpasupplicant"

# Only the server flavor is supported for now, the desktop images still expect
# the panfork and rockchip multimedia PPAs
export SUITE_FLAVORS=("server")

# The rootfs has to be bootstrapped by a host that knows this suite
export BUILD_RUNNER="ubuntu-26.04"
export BUILD_DOCKER_IMAGE="ubuntu:26.04"
