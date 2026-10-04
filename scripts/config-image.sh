#!/bin/bash

set -eE 
trap 'echo Error: in $0 on line $LINENO' ERR

if [ "$(id -u)" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

cd "$(dirname -- "$(readlink -f -- "$0")")" && cd ..
mkdir -p build && cd build

if [[ -z ${BOARD} ]]; then
    echo "Error: BOARD is not set"
    exit 1
fi

# shellcheck source=/dev/null
source "../config/boards/${BOARD}.sh"

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

if [[ ${LAUNCHPAD} != "Y" ]]; then
    uboot_package="$(basename "$(find u-boot-"${BOARD}"_*.deb | sort | tail -n1)")"
    if [ ! -e "$uboot_package" ]; then
        echo 'Error: could not find the u-boot package'
        exit 1
    fi
fi

# Suites that take the kernel from the Ubuntu archive have none of these
if [[ ${LAUNCHPAD} != "Y" && ${KERNEL_SOURCE} != "archive" ]]; then
    linux_image_package="$(basename "$(find linux-image-*.deb | sort | tail -n1)")"
    if [ ! -e "$linux_image_package" ]; then
        echo "Error: could not find the linux image package"
        exit 1
    fi

    linux_headers_package="$(basename "$(find linux-headers-*.deb | sort | tail -n1)")"
    if [ ! -e "$linux_headers_package" ]; then
        echo "Error: could not find the linux headers package"
        exit 1
    fi

    linux_modules_package="$(basename "$(find linux-modules-*.deb | sort | tail -n1)")"
    if [ ! -e "$linux_modules_package" ]; then
        echo "Error: could not find the linux modules package"
        exit 1
    fi

    linux_buildinfo_package="$(basename "$(find linux-buildinfo-*.deb | sort | tail -n1)")"
    if [ ! -e "$linux_buildinfo_package" ]; then
        echo "Error: could not find the linux buildinfo package"
        exit 1
    fi

    linux_rockchip_headers_package="$(basename "$(find linux-rockchip-headers-*.deb | sort | tail -n1)")"
    if [ ! -e "$linux_rockchip_headers_package" ]; then
        echo "Error: could not find the linux rockchip headers package"
        exit 1
    fi
fi

setup_mountpoint() {
    local mountpoint="$1"

    if [ ! -c /dev/mem ]; then
        mknod -m 660 /dev/mem c 1 1
        chown root:kmem /dev/mem
    fi

    mount dev-live -t devtmpfs "$mountpoint/dev"
    mount devpts-live -t devpts -o nodev,nosuid "$mountpoint/dev/pts"
    mount proc-live -t proc "$mountpoint/proc"
    mount sysfs-live -t sysfs "$mountpoint/sys"
    mount securityfs -t securityfs "$mountpoint/sys/kernel/security"
    # Provide more up to date apparmor features, matching target kernel
    # cgroup2 mount for LP: 1944004
    mount -t cgroup2 none "$mountpoint/sys/fs/cgroup"
    mount -t tmpfs none "$mountpoint/tmp"
    mount -t tmpfs none "$mountpoint/var/lib/apt/lists"
    mount -t tmpfs none "$mountpoint/var/cache/apt"
    mv "$mountpoint/etc/resolv.conf" resolv.conf.tmp
    cp /etc/resolv.conf "$mountpoint/etc/resolv.conf"
    mv "$mountpoint/etc/nsswitch.conf" nsswitch.conf.tmp
    sed 's/systemd//g' nsswitch.conf.tmp > "$mountpoint/etc/nsswitch.conf"
}

teardown_mountpoint() {
    # Reverse the operations from setup_mountpoint
    local mountpoint
    mountpoint=$(realpath "$1")

    # ensure we have exactly one trailing slash, and escape all slashes for awk
    mountpoint_match=$(echo "$mountpoint" | sed -e's,/$,,; s,/,\\/,g;')'\/'
    # sort -r ensures that deeper mountpoints are unmounted first
    awk </proc/self/mounts "\$2 ~ /$mountpoint_match/ { print \$2 }" | LC_ALL=C sort -r | while IFS= read -r submount; do
        mount --make-private "$submount"
        umount "$submount"
    done
    mv resolv.conf.tmp "$mountpoint/etc/resolv.conf"
    mv nsswitch.conf.tmp "$mountpoint/etc/nsswitch.conf"
}

# Prevent dpkg interactive dialogues
export DEBIAN_FRONTEND=noninteractive

# Override localisation settings to address a perl warning
export LC_ALL=C

# Debootstrap options
chroot_dir=rootfs
overlay_dir=../overlay

# Extract the compressed root filesystem
rm -rf ${chroot_dir} && mkdir -p ${chroot_dir}
tar -xpJf "ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64.rootfs.tar.xz" -C ${chroot_dir}

# Mount the root filesystem
setup_mountpoint $chroot_dir

# Update packages
chroot $chroot_dir apt-get update
chroot $chroot_dir apt-get -y upgrade
    
# Run config hook to handle board specific changes
if [[ $(type -t config_image_hook__"${BOARD}") == function ]]; then
    config_image_hook__"${BOARD}" "${chroot_dir}" "${overlay_dir}" "${SUITE}"
fi 

# Download and install U-Boot
if [[ ${LAUNCHPAD} == "Y" ]]; then
    chroot ${chroot_dir} apt-get -y install "u-boot-${BOARD}"
else
    cp "${uboot_package}" ${chroot_dir}/tmp/
    chroot ${chroot_dir} dpkg -i "/tmp/${uboot_package}"
    chroot ${chroot_dir} apt-mark hold "$(echo "${uboot_package}" | sed -rn 's/(.*)_[[:digit:]].*/\1/p')"
fi

# Install the Linux kernel built by scripts/build-kernel.sh, suites that use the
# kernel from the Ubuntu archive keep the one the rootfs was built with
if [[ ${LAUNCHPAD} != "Y" && ${KERNEL_SOURCE} != "archive" ]]; then
    cp "${linux_image_package}" "${linux_headers_package}" "${linux_modules_package}" "${linux_buildinfo_package}" "${linux_rockchip_headers_package}" ${chroot_dir}/tmp/
    chroot ${chroot_dir} /bin/bash -c "apt-get -y purge \$(dpkg --list | grep -Ei 'linux-image|linux-headers|linux-modules|linux-rockchip' | awk '{ print \$2 }')"
    chroot ${chroot_dir} /bin/bash -c "dpkg -i /tmp/{${linux_image_package},${linux_modules_package},${linux_buildinfo_package},${linux_rockchip_headers_package}}"
    chroot ${chroot_dir} apt-mark hold "$(echo "${linux_image_package}" | sed -rn 's/(.*)_[[:digit:]].*/\1/p')"
    chroot ${chroot_dir} apt-mark hold "$(echo "${linux_modules_package}" | sed -rn 's/(.*)_[[:digit:]].*/\1/p')"
    chroot ${chroot_dir} apt-mark hold "$(echo "${linux_buildinfo_package}" | sed -rn 's/(.*)_[[:digit:]].*/\1/p')"
    chroot ${chroot_dir} apt-mark hold "$(echo "${linux_rockchip_headers_package}" | sed -rn 's/(.*)_[[:digit:]].*/\1/p')"
fi

# chrony takes the NTP servers handed out by DHCP from /run/chrony-dhcp, which
# its packaging fills in from a dhclient hook. These images do DHCP with
# systemd-networkd, so without a networkd-dispatcher hook that directory stays
# empty and a time server advertised by DHCP, often the only one reachable on
# an isolated network, is ignored.
if [ -f "${chroot_dir}/etc/chrony/chrony.conf" ] && \
   [ -d "${chroot_dir}/etc/networkd-dispatcher" ] && \
   ! chroot "${chroot_dir}" dpkg-query -W -f='${Status}' isc-dhcp-client 2>/dev/null | grep -q "^install ok installed"; then
    install -D -m 755 "${overlay_dir}/usr/lib/ubuntu-rockchip/networkd-ntp-servers" \
        "${chroot_dir}/usr/lib/ubuntu-rockchip/networkd-ntp-servers"
    install -D -m 755 "${overlay_dir}/etc/networkd-dispatcher/routable.d/50-chrony-dhcp-ntp" \
        "${chroot_dir}/etc/networkd-dispatcher/routable.d/50-chrony-dhcp-ntp"
    install -D -m 755 "${overlay_dir}/etc/networkd-dispatcher/off.d/50-chrony-dhcp-ntp" \
        "${chroot_dir}/etc/networkd-dispatcher/off.d/50-chrony-dhcp-ntp"
    echo "Installed the networkd to chrony hook for DHCP provided NTP servers"

    # Adding that unauthenticated source makes chrony require the NTS pools,
    # which leaves a board that cannot reach them unsynchronised even with a
    # working local server, so take authentication out of the selection
    install -D -m 644 "${overlay_dir}/etc/chrony/conf.d/50-ubuntu-rockchip-authselect.conf" \
        "${chroot_dir}/etc/chrony/conf.d/50-ubuntu-rockchip-authselect.conf"
fi

# Extra kernel parameters, for debugging a board without editing an image
if [[ -n ${KERNEL_CMDLINE_EXTRA} ]]; then
    echo -n " ${KERNEL_CMDLINE_EXTRA}" >> "${chroot_dir}/etc/kernel/cmdline"
    echo "Appended to the kernel command line: ${KERNEL_CMDLINE_EXTRA}"
fi

# Ubuntu builds the arm64 kernel as an EFI zboot image, which U-Boot cannot
# boot with booti, so unwrap it into a bare Image. The kernel postinst hook
# keeps doing that for every kernel installed later.
if [[ ${KERNEL_SOURCE} == "archive" ]]; then
    install -D -m 755 "${overlay_dir}/usr/lib/ubuntu-rockchip/extract-efi-zboot" \
        "${chroot_dir}/usr/lib/ubuntu-rockchip/extract-efi-zboot"
    install -D -m 755 "${overlay_dir}/etc/kernel/postinst.d/zz-efi-zboot-extract" \
        "${chroot_dir}/etc/kernel/postinst.d/zz-efi-zboot-extract"

    for kernel in "${chroot_dir}"/boot/vmlinuz-*; do
        [ -e "${kernel}" ] || continue
        chroot "${chroot_dir}" /etc/kernel/postinst.d/zz-efi-zboot-extract "${kernel##*/vmlinuz-}"
    done
fi

# Update the initramfs
chroot ${chroot_dir} update-initramfs -u

# Remove packages
chroot ${chroot_dir} apt-get -y clean
chroot ${chroot_dir} apt-get -y autoclean
chroot ${chroot_dir} apt-get -y autoremove

# Umount the root filesystem
teardown_mountpoint $chroot_dir

# Compress the root filesystem and then build a disk image
cd ${chroot_dir} && tar -cpf "../ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64-${BOARD}.rootfs.tar" . && cd .. && rm -rf ${chroot_dir}
../scripts/build-image.sh "ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64-${BOARD}.rootfs.tar"
rm -f "ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64-${BOARD}.rootfs.tar"
