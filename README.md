# kernel-builder

A small suite of tools to build a Linux kernel, optionally patched with [grsecurity].

## Getting started

Make sure you have docker installed. Then just run `make`.
The script will look up the most recent stable Linux version from https://www.kernel.org
and build that. Artifacts will be available in `./build/` afterward.

## Enabling grsecurity patches

You must have a [grsecurity subscription] in order to fetch the patches for use in building.
Export your credentials:

```
export GRSECURITY_USERNAME=foo
export GRSECURITY_PASSWORD=bar
make
```

The resulting packages will used the patch set.

## Including arbitrary patches

You can mount in any set of patches to be applied to the kernel
source prior to building. Store the patches in a directory,
such as `./patches/`, and those will be mounted into the container at `/patches/`.
The build script will loop over all files in that dir and apply each
patch prior to building.

## Using a custom kernel config

Since the build uses docker, the host machine's kernel and config are visible
to the build environment, and will be included via `make olddefconfig` prior
to building. If you wish to provide a different kernel config, mount the file
at `/config` inside the container. It will be copied into place prior to building.
Note that `make olddefconfig` will be run regardless to ensure the latest
options have been applied.

## Reproducibile builds
In the spirit of [reproducible builds], this repo attempts to make fully reproducible
kernel images. There are some catches, however: a custom kernel patch is included
to munge the changelog timestamp, and certain kernel config options (notably 
`CONFIG_GCC_PLUGIN_RANDSTRUCT` or `CONFIG_GRKERNSEC_RANDSTRUCT`) will prevent reproducibility.
For more info, see the [kernel docs on reproducibility].

Additionally, the script to fetch grsecurity patches works by choosing the most recent patch
available. If you wish to rebuild an older kernel version, you'll need to rebuild from the
original source tarball, and set environment variables such as `SOURCE_DATE_EPOCH`. Even then,
structure randomization may prevent an identical build.

## References

These configurations were developed by [Freedom of the Press Foundation] for
use in all [SecureDrop] instances. Experienced sysadmins can leverage these
roles to compile custom kernels for SecureDrop or non-SecureDrop projects.

The logic here is intended to supersede the legacy build logic at
https://github.com/freedomofpress/ansible-role-grsecurity-build/.

[Freedom of the Press Foundation]: https://freedom.press
[SecureDrop]: https://securedrop.org
[grsecurity]: https://grsecurity.net/
[grsecurity subscription]: https://grsecurity.net/business_support.php
[reproducible builds]: https://reproducible-builds.org/
[kernel docs on reproducibility]: https://www.kernel.org/doc/html/latest/kbuild/reproducible-builds.html
