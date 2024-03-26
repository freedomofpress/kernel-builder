#!/bin/bash
set -euxo pipefail


# Patching with grsecurity is disabled by default.
# Can be renabled vai env var or cli flag.
GRSECURITY="${GRSECURITY:-}"
LINUX_VERSION="${LINUX_VERSION:-}"
LINUX_MAJOR_VERSION="${LINUX_MAJOR_VERSION:-}"
LINUX_CUSTOM_CONFIG="${LINUX_CUSTOM_CONFIG:-/config}"
LOCALVERSION="${LOCALVERSION:-}"
export SOURCE_DATE_EPOCH
export SOURCE_DATE_EPOCH_FORMATTED=$(date -R -d @$SOURCE_DATE_EPOCH)
export KBUILD_BUILD_TIMESTAMP
export DEB_BUILD_TIMESTAMP
# Get the current Debian codename so we can vary based on version
eval "export $(cat /etc/os-release | grep CODENAME)"
export VERSION_CODENAME

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
    echo "Looking up latest release of $LINUX_MAJOR_VERSION from kernel.org"
    LINUX_VERSION="$(curl -s https://www.kernel.org/ | grep -m1 -F "$LINUX_MAJOR_VERSION" -A1 | head -n1 | grep -oP '[\d\.]+')"
fi

# 5.15.120 -> 5
FOLDER="$(cut -d. -f1 <<< "$LINUX_VERSION").x"
echo "Fetching Linux kernel source $LINUX_VERSION"
wget https://cdn.kernel.org/pub/linux/kernel/v${FOLDER}/linux-${LINUX_VERSION}.tar.{xz,sign}

echo "Extracting Linux kernel source $LINUX_VERSION"
xz -d -T 0 -v linux-${LINUX_VERSION}.tar.xz
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

# Generate the orig tarball
#tar --use-compress-program="xz -T 0" -cf ../linux-upstream_${LINUX_VERSION}-grsec-${LOCALVERSION}.orig.tar.xz .
tar -cf - . | pigz > ../linux-upstream_${LINUX_VERSION}-grsec-${LOCALVERSION}.orig.tar.gz

echo "Copying in our debian/"
cp -R /debian debian

export PACKAGE_VERSION="${LINUX_VERSION}-grsec-${LOCALVERSION}-1"
export DEBARCH="amd64"

cat debian/control.in | envsubst > debian/control
echo "" >> debian/control
if [[ "$LOCALVERSION" = "-workstation" ]]; then
    echo "Generating d/control for workstation"
    cat debian/control.workstation | envsubst >> debian/control
else
    echo "Generating d/control for server"
    cat debian/control.server | envsubst >> debian/control
fi
cat debian/changelog.in | envsubst > debian/changelog

cat <<EOF > debian/rules.vars
ARCH := x86
KERNELRELEASE := ${LINUX_VERSION}
EOF

echo "Building Linux kernel source $LINUX_VERSION"

# TODO set parallel build here
dpkg-buildpackage -uc -us

echo "Storing build artifacts for $LINUX_VERSION"
if [[ -d /output ]]; then
    rsync -a --info=progress2 ../*.{buildinfo,changes,dsc,deb,tar.gz} /output/
fi
