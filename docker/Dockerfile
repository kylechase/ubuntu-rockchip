# Build environment for ubuntu-rockchip. The image has to run the same Ubuntu
# suite as the image being built, since the rootfs is bootstrapped with the
# livecd-rootfs, live-build and debootstrap of that suite.
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# The legacy suites build livecd-rootfs from source, which needs deb-src
RUN set -eux; \
    if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
        sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources; \
    else \
        sed -i 's/^deb \(.*\)$/deb \1\ndeb-src \1/' /etc/apt/sources.list; \
    fi

RUN apt-get update && apt-get install -y --no-install-recommends \
        bc \
        binfmt-support \
        bison \
        build-essential \
        ca-certificates \
        cpio \
        curl \
        dctrl-tools \
        debhelper \
        debootstrap \
        device-tree-compiler \
        distro-info \
        dosfstools \
        dpkg-dev \
        fakeroot \
        fdisk \
        flex \
        gcc-aarch64-linux-gnu \
        gdisk \
        git \
        gnupg \
        kmod \
        libfdt-dev \
        libpython3-dev \
        libssl-dev \
        lsb-release \
        mtools \
        parted \
        python-is-python3 \
        python3 \
        python3-pyelftools \
        python3-setuptools \
        qemu-user \
        rsync \
        swig \
        u-boot-tools \
        udev \
        uuid-runtime \
        xz-utils \
        zstd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /ubuntu-rockchip
ENTRYPOINT []
