# kernel-builder

A suite of tools to build a Debian-packaged Linux kernel, optionally patched with [grsecurity]
for the [SecureDrop](https://securedrop.org/) project.

## Prerequistes

* Docker
* GNU make

## Using

Select which config flavor you want to build and run `make <config>`. The script will
automatically fetch the most recent Linux version for that flavor, patch if necessary,
and leave built packages in `./build/`.

## Enabling grsecurity patches

You must have a [grsecurity subscription] in order to fetch the patches for use in building.
Export your credentials:

```
export GRSECURITY_USERNAME=foo
export GRSECURITY_PASSWORD=bar
export GRSECURITY=1
make <config>
```

The resulting packages will use the grsecurity patch set. If you're working on SecureDrop,
request these credentials from a team member, and store them securely
in your password manager.

## Building kernels in Qubes

Here's how to set up a build environment in [Qubes], suitable for use with [SecureDrop].
The build requires `docker`, so make sure your TemplateVM has docker configured.

```
qvm-create sd-kernel-builder --template debian-11 --label purple
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
```

The build output will automatically be captured in a log file.

## Release

Packages are first placed on apt-test.freedom.press for [QA testing and validation](https://developers.securedrop.org/en/latest/kernel.html), and then promoted to apt.freedom.press.

⚠️ Before you add a package to one of our apt repos, you *must* upload the kernel source tarball internally following the instructions below.

1. Add a detached signature to the kernel source tarball using a staff (`*@freedom.press`) GPG key.
2. Now hop over to our private wiki page on how to use a script to upload the kernel source tarball internally and verify that your upload was successful.
3. You can now propose your packages for inclusion in the `apt-test` repository.
4. After QA, the same kernel packages on `apt-test` can be promoted to prod.

## Architecture

This builds on the `make deb-pkg` command in Linux. The upstream command dynamically
generates a `debian/` directory and then executes it. Instead, we prepare and commit
the `debian/` directory so we can customize the packages and add in our metadata.
Our `debian/rules` is roughly the same as what would be generated, except it has some compat
to handle different versions. Future updates of major kernel versions may require adjusting
`debian/rules` if upstream has also made changes.

## Reproducible builds
In the spirit of [reproducible builds], this repo attempts to make fully reproducible
kernel images. There are some catches, however: certain kernel config options (notably
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
scripts to compile custom kernels for SecureDrop or non-SecureDrop projects.

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
