#!/bin/bash
set -e
set -u
set -o pipefail


# Use explicit version if declared, otherwise default to latest stable
LINUX_VERSION="${LINUX_VERSION:-}"
if [[ -z "$LINUX_VERSION" ]]; then
    LINUX_VERSION="$(curl -s https://www.kernel.org/ | grep -m1 -F stable: -A1 | tail -n1 | grep -oP '[\d\.]+')"
fi
LINUX_MAJOR_VERSION="$(cut -d. -f1 <<< "$LINUX_VERSION")"

# If there's no output directory, then deb packages will be
# lost in the ephemeral container.
if [[ ! -d /output ]]; then
    echo "WARNING: Output directory /output not found" >&2
    echo "WARNING: to save packages, you must mount /output as a volume" >&2
    exit 1
fi

echo "Fetching Linux kernel source $LINUX_VERSION"
wget https://cdn.kernel.org/pub/linux/kernel/v${LINUX_MAJOR_VERSION}.x/linux-${LINUX_VERSION}.tar.xz
xz -d -v linux-${LINUX_VERSION}.tar.xz
tar -xf linux-${LINUX_VERSION}.tar
cd linux-${LINUX_VERSION}

if [[ -e /config ]]; then
    cp /config .config
fi

make olddefconfig
VCPUS="$(nproc)"

make -j $VCPUS deb-pkg

if [[ -d /output ]]; then
    rsync -a --info=progress2 *.deb /output/
fi
