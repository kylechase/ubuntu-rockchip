# shellcheck shell=bash

export BOARD_NAME="Turing RK1"
export BOARD_MAKER="Turing Machines"
export BOARD_SOC="Rockchip RK3588"
export BOARD_CPU="ARM Cortex A76 / A55"
export UBOOT_PACKAGE="u-boot-turing-rk3588"
export UBOOT_RULES_TARGET="turing-rk1-rk3588"
export COMPATIBLE_SUITES=("jammy" "noble" "oracular" "plucky" "resolute")
export COMPATIBLE_FLAVORS=("server" "desktop")

function config_image_hook__turing-rk1() {
    local rootfs="$1"
    local suite="$3"

    if [ "${suite}" == "jammy" ] || [ "${suite}" == "noble" ]; then
        # Install panfork
        chroot "${rootfs}" add-apt-repository -y ppa:jjriek/panfork-mesa
        chroot "${rootfs}" apt-get update
        chroot "${rootfs}" apt-get -y install mali-g610-firmware
        chroot "${rootfs}" apt-get -y dist-upgrade

        # Install libmali blobs alongside panfork
        chroot "${rootfs}" apt-get -y install libmali-g610-x11

        # Install the rockchip camera engine
        chroot "${rootfs}" apt-get -y install camera-engine-rkaiq-rk3588

        # The RK1 uses UART9 for console output
        sed -i 's/console=ttyS2,1500000/console=ttyS9,115200/g' "${rootfs}/etc/kernel/cmdline"
    elif [ "${suite}" == "oracular" ]; then
        sed -i 's/console=ttyS2,1500000/console=ttyS0,115200/g' "${rootfs}/etc/kernel/cmdline"
    elif [ "${suite}" == "resolute" ]; then
        # The mainline device tree keeps the uart numbering of the SoC, so the
        # console the Turing Pi BMC is wired to is ttyS9 (stdout-path in
        # rk3588-turing-rk1.dts is serial9:115200n8).
        #
        # The serial console has to come last, the kernel makes the console
        # named last /dev/console and everything userspace prints goes there.
        # This board is normally headless, so with tty1 last all of that, the
        # login prompt and any emergency shell included, would be written to
        # the dummy console and lost.
        sed -i 's/console=ttyS2,1500000 console=tty1/console=tty1 console=ttyS9,115200/g' \
            "${rootfs}/etc/kernel/cmdline"
    fi

    return 0
}
