#!/bin/bash
set -e
set -u
set -o pipefail


# Patching with grsecurity is disabled by default.
# Can be renabled vai env var or cli flag.
GRSECURITY="${GRSECURITY:-}"
LINUX_VERSION="${LINUX_VERSION:-}"
LINUX_MAJOR_VERSION="${LINUX_MAJOR_VERSION:-}"
LINUX_CUSTOM_CONFIG="${LINUX_CUSTOM_CONFIG:-/config}"
LOCALVERSION="${LOCALVERSION:-}"
export SOURCE_DATE_EPOCH
export KBUILD_BUILD_TIMESTAMP
export DEB_BUILD_TIMESTAMP

if [[ $# > 0 ]]; then
    x="$1"
    shift
    if [[ "$x" = "--grsecurity" ]]; then
        GRSECURITY=1
    else
        echo "Usage: $0 [--grsecurity]"
        exit 1
    fi
fi

# If there's no output directory, then deb packages will be
# lost in the ephemeral container.
if [[ ! -d /output && ! -w /output ]]; then
    echo "WARNING: Output directory /output not found" >&2
    echo "WARNING: to save packages, you must mount /output as a volume" >&2
    exit 1
fi

if [[ -n "$GRSECURITY" && "$GRSECURITY" = "1" ]]; then
    LINUX_VERSION="$(/usr/local/bin/grsecurity-urls.py --print-version)"
    echo "Will include grsecurity patch for kernel $LINUX_VERSION"
    /usr/local/bin/grsecurity-urls.py > /patches-grsec/grsec
else
    echo "Skipping grsecurity patch set"
fi

if [[ -z "$LINUX_VERSION" ]]; then
    if [[ -z "$LINUX_MAJOR_VERSION" ]]; then
        echo "ERROR: \$LINUX_MAJOR_VERSION must be set"
        exit 1
    fi
    # Get the latest patch version of this version series from kernel.org
    LINUX_VERSION="$(curl -s https://www.kernel.org/ | grep -m1 -F "$LINUX_MAJOR_VERSION" -A1 | head -n1 | grep -oP '[\d\.]+')"
fi

# 5.15.120 -> 5
FOLDER="$(cut -d. -f1 <<< "$LINUX_VERSION").x"
echo "Fetching Linux kernel source $LINUX_VERSION"
wget https://cdn.kernel.org/pub/linux/kernel/v${FOLDER}/linux-${LINUX_VERSION}.tar.{xz,sign}

echo "Extracting Linux kernel source $LINUX_VERSION"
xz -d -v linux-${LINUX_VERSION}.tar.xz
gpgv --keyring /pubkeys/kroah_hartman.gpg linux-${LINUX_VERSION}.tar.sign linux-${LINUX_VERSION}.tar
tar -xf linux-${LINUX_VERSION}.tar
cd linux-${LINUX_VERSION}

if [[ -e "$LINUX_CUSTOM_CONFIG" ]]; then
    echo "Copying custom config for kernel source $LINUX_VERSION"
    cp "$LINUX_CUSTOM_CONFIG" .config
fi

if [[ -e /patches-grsec && -n "$GRSECURITY" && "$GRSECURITY" = "1" ]]; then
    echo "Applying grsec patches for kernel source $LINUX_VERSION"
    find /patches-grsec -maxdepth 1 -type f -exec patch -p 1 -i {} \;
fi

echo "Copying in our mkdebian"
cp /usr/local/bin/mkdebian scripts/package/mkdebian

if [[ "$LOCALVERSION" = "-workstation" ]]; then
    echo "Copying in our securedrop-workstation-grsec"
    mkdir -p debian/securedrop-workstation-grsec
    cp -Rv /securedrop-workstation-grsec/* debian/securedrop-workstation-grsec/
else
    echo "Copying in our securedrop-grsec"
    mkdir -p debian/securedrop-grsec
    cp -Rv /securedrop-grsec/* debian/securedrop-grsec/
fi

echo "Building Linux kernel source $LINUX_VERSION"
make olddefconfig

VCPUS="$(nproc)"
make EXTRAVERSION="-1" -j $VCPUS deb-pkg

echo "Storing build artifacts for $LINUX_VERSION"
if [[ -d /output ]]; then
    rsync -a --info=progress2 ../*.{buildinfo,changes,dsc,deb,tar.gz} /output/
fi
