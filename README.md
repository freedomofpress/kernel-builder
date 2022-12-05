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
export GRSECURITY=1
make
```

The resulting packages will used the patch set. If you're working on SecureDrop,
request these credentials from a team member, and store them securely
in your password manager.

## Using a custom kernel config

Since the build uses docker, the host machine's kernel and config are visible
to the build environment, and will be included via `make olddefconfig` prior
to building. If you wish to provide a different kernel config, mount the file
at `/config` inside the container. It will be copied into place prior to building.
Note that `make olddefconfig` will be run regardless to ensure the latest
options have been applied.

## Building kernels in Qubes

Here's how to set up a build environment in [Qubes], suitable for use with [SecureDrop].
The build requires `docker`, so make sure your TemplateVM has docker configured.

```
qvm-create sd-kernel-builder --template debian-10 --label purple
qvm-prefs sd-kernel-builder vcpus $(nproc)
qvm-volume resize sd-kernel-builder:private 50G

```

Then add the following customization to the AppVM to ensure
the private volume [bind-dir](https://www.qubes-os.org/doc/bind-dirs/)
is used for the build:

```
sudo mkdir -p /rw/config/qubes-bind-dirs.d
echo "binds+=( '/var/lib/docker' )" | sudo tee -a /rw/config/qubes-bind-dirs.d/50_user.conf
```

And reboot the AppVM. Otherwise, you will need a large system partition.
Finally, make sure you've got the [grsec env vars](##enabling-grsecurity-patches)
exported in your environment, or set in e.g. `~/grsec-env`, as below. Now build:

```
rm -rf ~/kernel-builder
git clone https://github.com/freedomofpress/kernel-builder
cd kernel-builder
source ~/grsec-env # credentials for grsecurity access
make securedrop-workstation # to build Workstation kernels
# grab a coffee or tea, builds take ~1h with 4 cores.
sha256sum build/*
# then copy the terminal history from your emulator and store build log,
# e.g. via Edit->Select All in gnome-terminal
```

## Release

Development/staging packages are placed on apt-test.freedom.press for installation in Debian-based TemplateVMs, and production packages are placed on apt.freedom.press.

⚠️ Before you add a package to one of our apt repos, you *must* upload the kernel source tarball to our S3 bucket following the instructions below.

1. Add a detached signature to the kernel source tarball using a staff (`*@freedom.press`) GPG key.
2. If you do not have an AWS account and you are a maintainer, ask someone from the infrastructure team to set one up for you. They will provide you with instructions on where and how your credentials should be stored in Qubes.
3. Now hop over to our private wiki page on how to use a script to upload the kernel source tarball to our S3 bucket and verify that your upload was successful. There, you'll also learn how to later respond to a source request email sent to `source-offer@freedom.press`.
4. Now you can submit a `securedrop-workstation-grsec` changelog PR in `securedrop-debian-packaging` and a .deb LFS PR to https://github.com/freedomofpress/securedrop-dev-packages-lfs, which another maintainer reviews and merges, thereby deploying the new packages to https://apt-test.freedom.press.
5. After QA, the same kernel packages on `apt-test` can be promoted to prod by submitting a .deb LFS PR to https://github.com/freedomofpress/securedrop-debian-packages-lfs.

## Reproducible builds
In the spirit of [reproducible builds], this repo attempts to make fully reproducible
kernel images. There are some catches, however: a custom kernel patch is included
to munge the changelog timestamp, and certain kernel config options (notably 
`CONFIG_GCC_PLUGIN_RANDSTRUCT` or `CONFIG_GRKERNSEC_RANDSTRUCT`) will prevent reproducibility.
For more info, see the [kernel docs on reproducibility].

Additionally, the script to fetch grsecurity patches works by choosing the most recent patch
available. If you wish to rebuild an older kernel version, you'll need to rebuild from the
original source tarball, and set environment variables such as `SOURCE_DATE_EPOCH`. Even then,
structure randomization may prevent an identical build.

## Building your own kernel
Please see the [SOURCE_OFFER] for details on how to get the source for kernels we've published. If
you've received a source tarball, you should be able to treat it the same as an upstream
kernel tarball. If you're unsure how to build from source, the documentation from the [kernelnewbies.org]
site may be useful.

Note that despite using the same exact source, your kernel will not be bit-for-bit identical to the published
SecureDrop kernels because of the above-mentioned randomization of struct fields.

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
[Qubes]: https://qubes-os.org
[SOURCE_OFFER]: https://github.com/freedomofpress/securedrop/blob/develop/SOURCE_OFFER
[kernelnewbies.org]: https://kernelnewbies.org/KernelBuild
