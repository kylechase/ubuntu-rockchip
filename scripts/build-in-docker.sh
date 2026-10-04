#!/bin/bash

set -eE
trap 'echo Error: in $0 on line $LINENO' ERR

cd "$(dirname -- "$(readlink -f -- "$0")")" && cd ..
project_dir="$(pwd)"

usage() {
cat << HEREDOC
Usage: $0 --board=[turing-rk1] --suite=[resolute] --flavor=[server]

Runs build.sh inside a container running the same Ubuntu suite as the image
being built, so the build host does not have to be that release of Ubuntu, or
Ubuntu at all. All arguments are passed through to build.sh.

The host kernel still does the work, so it needs:
  * binfmt_misc registered for aarch64 (the qemu-user-static package)
  * the loop module available, the container assembles the disk image
HEREDOC
}

if [ "$#" -eq 0 ]; then
    usage
    exit 1
fi

suite=""
args=("$@")
while [ "$#" -gt 0 ]; do
    case "${1}" in
        -h|--help)
            usage
            exit 0
            ;;
        -s=*|--suite=*)
            suite="${1#*=}"
            shift
            ;;
        -s|--suite)
            suite="${2}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [ -z "${suite}" ]; then
    echo "Error: --suite is required"
    exit 1
fi

if [ ! -e "config/suites/${suite}.sh" ]; then
    echo "Error: \"${suite}\" is an unsupported suite"
    exit 1
fi

# shellcheck source=/dev/null
source "config/suites/${suite}.sh"

docker="${DOCKER:-docker}"
if ! command -v "${docker}" > /dev/null; then
    echo "Error: ${docker} was not found, set DOCKER= to the container runtime to use"
    exit 1
fi

if [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    echo "Error: the host has no binfmt_misc handler for aarch64 binaries"
    echo "Install qemu-user-static (or qemu-user-static-binfmt) on the host and"
    echo "make sure systemd-binfmt is running"
    exit 1
fi

if [ ! -e /dev/loop-control ]; then
    echo "Error: /dev/loop-control is missing, run 'modprobe loop' on the host"
    exit 1
fi

base_image="${BUILD_DOCKER_IMAGE:-ubuntu:24.04}"
image="ubuntu-rockchip-build:${base_image//[:\/]/-}"

echo "Building ${image} from ${base_image}"
"${docker}" build --build-arg "BASE_IMAGE=${base_image}" -t "${image}" docker

echo "Running build.sh in ${image}"
exec "${docker}" run --rm --privileged \
    -e "KERNEL_CMDLINE_EXTRA=${KERNEL_CMDLINE_EXTRA:-}" \
    -v /dev:/dev \
    -v "${project_dir}:/ubuntu-rockchip" \
    -w /ubuntu-rockchip \
    "${image}" \
    ./build.sh "${args[@]}"
