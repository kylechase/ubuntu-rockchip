#!/bin/bash

set -eE 
trap 'echo Error: in $0 on line $LINENO' ERR

if [ "$(id -u)" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

cd "$(dirname -- "$(readlink -f -- "$0")")" && cd ..
project_dir="$(pwd)"
mkdir -p build && cd build

if [[ -z ${SUITE} ]]; then
    echo "Error: SUITE is not set"
    exit 1
fi

# shellcheck source=/dev/null
source "../config/suites/${SUITE}.sh"

if [[ -z ${FLAVOR} ]]; then
    echo "Error: FLAVOR is not set"
    exit 1
fi

# shellcheck source=/dev/null
source "../config/flavors/${FLAVOR}.sh"

if [[ -f ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64.rootfs.tar.xz ]]; then
    exit 0
fi

# Debootstrap only ships a script for the suites it knew about when it was
# packaged, newer suites are bootstrapped with the generic ubuntu script
if [ ! -e "/usr/share/debootstrap/scripts/${SUITE}" ]; then
    ln -s gutsy "/usr/share/debootstrap/scripts/${SUITE}"
fi

if [ "${LIVECD_ROOTFS_SOURCE}" == "archive" ]; then
    # Suites without a rockchip PPA are built with the livecd-rootfs of the
    # suite itself, which means the build host has to run that same suite
    apt-get update
    apt-get install -y livecd-rootfs

    livecd_rootfs_dir="$(pwd)/livecd-rootfs"
    rm -rf "${livecd_rootfs_dir}"
    cp -a /usr/share/livecd-rootfs "${livecd_rootfs_dir}"

    hooks_dir="${livecd_rootfs_dir}/live-build/ubuntu-cpc/hooks.d"

    # Rockchip specific rootfs tweaks, these also stand in for the PPA only
    # ubuntu-rockchip-settings packages
    install -m 755 "${project_dir}/config/livecd-rootfs/hooks/020-ubuntu-rockchip-tweaks.chroot" \
        "${hooks_dir}/chroot/020-ubuntu-rockchip-tweaks.chroot"
    mkdir -p "${livecd_rootfs_dir}/live-build/ubuntu/hooks"
    ln -sf "../../ubuntu-cpc/hooks.d/chroot/020-ubuntu-rockchip-tweaks.chroot" \
        "${livecd_rootfs_dir}/live-build/ubuntu/hooks/020-ubuntu-rockchip-tweaks.chroot"

    # These two hooks configure an image for the cloud or for ubuntu-image:
    # they install a grub config, overwrite /etc/fstab and seed cloud-init from
    # a partition label that scripts/build-image.sh does not create
    rm -f "${hooks_dir}/chroot/999-cpc-fixes.chroot"
    rm -f "${hooks_dir}/chroot/999-ubuntu-image-customization.chroot"

    # The disk image is assembled by scripts/build-image.sh, so no image target
    # of livecd-rootfs has to run
    : > "${hooks_dir}/base/series/none"

    export LIVECD_ROOTFS_ROOT="${livecd_rootfs_dir}"
    auto_dir="${livecd_rootfs_dir}/live-build/auto"
else
    pushd .

    tmp_dir=$(mktemp -d)
    cd "${tmp_dir}" || exit 1

    # Clone the livecd rootfs fork
    git clone https://github.com/Joshua-Riek/livecd-rootfs
    cd livecd-rootfs || exit 1

    # Install build deps
    apt-get update
    apt-get build-dep . -y

    # Build the package
    dpkg-buildpackage -us -uc

    # Install the custom livecd rootfs package
    apt-get install ../livecd-rootfs_*.deb --assume-yes --allow-downgrades --allow-change-held-packages
    dpkg -i ../livecd-rootfs_*.deb
    apt-mark hold livecd-rootfs

    rm -rf "${tmp_dir}"

    popd

    # Query the system to locate livecd-rootfs auto script installation path
    auto_dir="$(dpkg -L livecd-rootfs | grep "auto$")"
fi

mkdir -p live-build && cd live-build

cp -r "${auto_dir}" auto

# Ubuntu 26.04 dropped the statically linked qemu binaries, the binfmt_misc
# handler of the build host is what actually runs the arm64 binaries
qemu_aarch64="$(command -v qemu-aarch64-static || command -v qemu-aarch64)"
if [ -z "${qemu_aarch64}" ]; then
    echo "Error: no qemu-aarch64 binary was found, install qemu-user"
    exit 1
fi

set +e

export ARCH=arm64
export IMAGEFORMAT=none
export IMAGE_TARGETS=none

# Populate the configuration directory for live build
lb config \
    --architecture arm64 \
    --bootstrap-qemu-arch arm64 \
    --bootstrap-qemu-static "${qemu_aarch64}" \
    --archive-areas "main restricted universe multiverse" \
    --parent-archive-areas "main restricted universe multiverse" \
    --mirror-bootstrap "http://ports.ubuntu.com" \
    --parent-mirror-bootstrap "http://ports.ubuntu.com" \
    --mirror-chroot-security "http://ports.ubuntu.com" \
    --parent-mirror-chroot-security "http://ports.ubuntu.com" \
    --mirror-binary-security "http://ports.ubuntu.com" \
    --parent-mirror-binary-security "http://ports.ubuntu.com" \
    --mirror-binary "http://ports.ubuntu.com" \
    --parent-mirror-binary "http://ports.ubuntu.com" \
    --keyring-packages ubuntu-keyring \
    --linux-flavours "${KERNEL_FLAVOR}"

if [ "${SUITE}" == "noble" ] || [ "${SUITE}" == "jammy" ]; then
    # Pin rockchip package archives
    (
        echo "Package: *"
        echo "Pin: release o=LP-PPA-jjriek-rockchip"
        echo "Pin-Priority: 1001"
        echo ""
        echo "Package: *"
        echo "Pin: release o=LP-PPA-jjriek-rockchip-multimedia"
        echo "Pin-Priority: 1001"
    ) > config/archives/extra-ppas.pref.chroot
fi

if [ "${SUITE}" == "noble" ]; then
    # Ignore custom ubiquity package (mistake i made, uploaded to wrong ppa)
    (
        echo "Package: oem-*"
        echo "Pin: release o=LP-PPA-jjriek-rockchip-multimedia"
        echo "Pin-Priority: -1"
        echo ""
        echo "Package: ubiquity*"
        echo "Pin: release o=LP-PPA-jjriek-rockchip-multimedia"
        echo "Pin-Priority: -1"

    ) > config/archives/extra-ppas-ignore.pref.chroot
fi

# Snap packages to install
for snap in ${SEEDED_SNAPS:-snapd/classic=stable core22/classic=stable lxd/classic=stable}; do
    echo "${snap}"
done > config/seeded-snaps

# Generic packages to install
echo "software-properties-common" > config/package-lists/my.list.chroot

if [ "${PROJECT}" == "ubuntu" ]; then
    # Specific packages to install for ubuntu desktop
    for package in ${ROOTFS_PACKAGES_DESKTOP:-ubuntu-desktop-rockchip oem-config-gtk ubiquity-frontend-gtk ubiquity-slideshow-ubuntu localechooser-data}; do
        echo "${package}"
    done >> config/package-lists/my.list.chroot
else
    # Specific packages to install for ubuntu server
    for package in ${ROOTFS_PACKAGES_SERVER:-ubuntu-server-rockchip}; do
        echo "${package}"
    done >> config/package-lists/my.list.chroot
fi

# Build the rootfs
lb build
lb_status=$?

set -eE 

if [ ${lb_status} -ne 0 ]; then
    # The late stages of lb build preseed snaps, which needs an apparmor
    # enabled build host. The rootfs itself is complete at that point, so only
    # bail out if something is actually missing from it.
    echo "Warning: lb build exited with status ${lb_status}"
    if [ ! -x chroot/usr/bin/apt ] || [ -z "$(find chroot/boot -name 'vmlinuz-*' -print -quit)" ]; then
        echo "Error: the root filesystem is incomplete"
        exit 1
    fi
    echo "Warning: the root filesystem looks complete, continuing without preseeded snaps"
fi

# Tar the entire rootfs
(cd chroot/ &&  tar -p -c --sort=name --xattrs ./*) | xz -3 -T0 > "ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64.rootfs.tar.xz"
mv "ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64.rootfs.tar.xz" ../
