#!/usr/bin/env python3
import hashlib
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import jinja2
import requests


def render_template(filename, context):
    template_content = Path(f"{filename}.j2").read_text()
    template = jinja2.Template(template_content)
    rendered_content = template.render(context)
    Path(filename).write_text(rendered_content)


def derive_seed(release, purpose):
    """
    Because our kernels are public, using a random seed doesn't provide any hardening
    but it interferes with reproducibility. Instead we use a deterministic seed.
    """
    return hashlib.sha256(f"{release}-{purpose}".encode()).hexdigest()


def pin_build_seeds(srcdir, release):
    """
    Override various scripts that reach for randomness with values based on our
    deterministic seed instead.
    """
    print("Pinning build seeds for", release)
    # randstruct: scripts/basic/Makefile calls this with the seed file and the
    # hashed-seed header as $1 and $2. Same 64 hex chars as `od -t x8 -N 32`.
    randstruct = srcdir / "scripts/gen-randstruct-seed.sh"
    if not randstruct.exists():
        print(f"ERROR: {randstruct} not found, cannot pin the randstruct seed")
        sys.exit(1)
    randstruct.write_text(
        "#!/bin/sh\n"
        "# SPDX-License-Identifier: GPL-2.0\n"
        "# Seed pinned by kernel-builder for reproducibility; see derive_seed().\n"
        f'SEED="{derive_seed(release, "randstruct")}"\n'
        'echo "$SEED" > "$1"\n'
        'HASH=$(echo -n "$SEED" | sha256sum | cut -d" " -f1)\n'
        'echo "#define RANDSTRUCT_HASHED_SEED \\"$HASH\\"" > "$2"\n'
    )

    # type_canary (grsecurity only): writes the header to stdout. The original
    # emits four ULL words from 32 bytes of urandom, then an 8-char hash of them.
    type_canary = srcdir / "scripts/gcc-plugins/gen-type_canary.sh"
    if type_canary.exists():
        digest = bytes.fromhex(derive_seed(release, "type_canary"))
        words = ", ".join(
            f"0x{int.from_bytes(digest[i : i + 8], 'big'):016x}ULL" for i in range(0, 32, 8)
        )
        type_canary.write_text(
            "#!/bin/sh\n"
            "# SPDX-License-Identifier: GPL-2.0\n"
            "# Seed pinned by kernel-builder for reproducibility; see derive_seed().\n"
            f'RAND=" {words} "\n'
            'HASH=$(echo "$RAND" | sha256sum | cut -d" " -f1 | tr -d " \\n" | cut -c1-8)\n'
            "cat<<EOF\n"
            "/*\n"
            " * Automatically generated file, do not edit!\n"
            " */\n"
            "\n"
            "#define TYPE_CANARY_SEED_INIT\t{ $RAND }\n"
            '#define TYPE_CANARY_SEED_HASH\t"$HASH"\n'
            "EOF\n"
        )


def main():  # noqa: PLR0915
    # Whether to use grsecurity patches
    grsecurity = os.environ.get("GRSECURITY") == "1"
    # Desired specific Linux version to download (e.g. "5.15.100")
    linux_version = os.environ.get("LINUX_VERSION")
    # Desired Linux major version to download (e.g. "5.15", "6.6")
    linux_major_version = os.environ.get("LINUX_MAJOR_VERSION")
    # Local version flavor, e.g. "securedrop", "workstation", "tiny"
    local_version = os.environ["LOCALVERSION"]
    # Increment if we need to build the same specific version again (e.g. metapackage changes)
    build_version = os.environ.get("BUILD_VERSION", "1")

    source_date_epoch = os.environ["SOURCE_DATE_EPOCH"]
    source_date_epoch_formatted = subprocess.check_output(
        ["/bin/date", "-R", "-d", f"@{source_date_epoch}"], text=True
    ).strip()
    for line in Path("/etc/os-release").read_text().splitlines():
        if line.startswith("VERSION_CODENAME="):
            version_codename = line.split("=")[1].strip()
            break

    # Check output directory
    if not os.path.isdir("/output") or not os.access("/output", os.W_OK):
        print("WARNING: Output directory /output not found or not writable")
        print("WARNING: To save packages, you must mount /output as a volume")
        sys.exit(1)

    # Fetch grsecurity patchset if desired
    if grsecurity:
        # TODO: invoke this through normal Python means
        linux_version = subprocess.check_output(
            ["/usr/local/bin/grsecurity-urls.py", "--print-version"], text=True
        ).strip()
        print("Will include grsecurity patch for kernel", linux_version)
        with open("/patches-grsec/grsec", "wb") as f:
            # TODO: invoke this through normal Python means
            subprocess.run(["/usr/local/bin/grsecurity-urls.py"], stdout=f, check=True)
    else:
        print("Skipping grsecurity patch set")

    # If we're don't have a kernel version yet, look it up
    if not linux_version:
        if not linux_major_version:
            print("ERROR: $LINUX_MAJOR_VERSION must be set")
            sys.exit(1)
        print(f"Looking up latest release of {linux_major_version} from kernel.org")
        response = requests.get("https://www.kernel.org/")  # noqa: S113
        response.raise_for_status()
        linux_version = re.search(
            rf"<strong>({re.escape(linux_major_version)}\.(\d+?))</strong>",
            response.text,
        ).group(1)

    # Fetch Linux kernel source
    folder = linux_version.split(".")[0] + ".x"
    print(f"Fetching Linux kernel source {linux_version}")
    subprocess.check_call(
        [
            "/usr/bin/wget",
            f"https://cdn.kernel.org/pub/linux/kernel/v{folder}/linux-{linux_version}.tar.xz",
        ]
    )
    subprocess.check_call(
        [
            "/usr/bin/wget",
            f"https://cdn.kernel.org/pub/linux/kernel/v{folder}/linux-{linux_version}.tar.sign",
        ]
    )
    print(f"Extracting Linux kernel source {linux_version}")
    # We'll reuse the original tarball if we're not patching it
    keep_xz = ["--keep"] if not grsecurity else []
    subprocess.check_call(
        ["/usr/bin/xz", "-d", "-T", "0", "-v", f"linux-{linux_version}.tar.xz"] + keep_xz
    )
    subprocess.check_call(
        [
            "/usr/bin/gpgv",
            "--keyring",
            "/pubkeys/kroah_hartman.gpg",
            f"linux-{linux_version}.tar.sign",
            f"linux-{linux_version}.tar",
        ]
    )
    shutil.unpack_archive(f"linux-{linux_version}.tar")

    # Apply grsec patches
    if grsecurity:
        print(f"Applying grsec patches for kernel source {linux_version}")
        subprocess.check_call(
            ["/usr/bin/patch", "-p", "1", "-i", "/patches-grsec/grsec"],
            cwd=f"linux-{linux_version}",
        )

    # If we applied grsec patches, we need to generate a new orig tarball,
    # otherwise we can re-use the upstream one
    linux_build_version = f"{linux_version}-{build_version}"
    version_suffix = ("grsec-" if grsecurity else "") + local_version
    release = f"{linux_build_version}-{version_suffix}"
    orig_tarball = f"linux-upstream_{release}.orig.tar.xz"
    pin_build_seeds(Path(f"linux-{linux_version}"), release)
    if grsecurity:
        print("Generating orig tarball")
        subprocess.check_call(
            [
                "/bin/tar",
                "--use-compress-program=xz -T 0",
                "-cf",
                orig_tarball,
                f"linux-{linux_version}",
            ]
        )
    else:
        shutil.copy(f"linux-{linux_version}.tar.xz", orig_tarball)

    os.chdir(f"linux-{linux_version}")
    # Copy debian/
    print(f"Setting up our debian/ tree for Linux {linux_major_version}")
    shutil.copytree("/debian", "debian")
    shutil.move(f"debian/rules-{linux_major_version}", "debian/rules")

    template_variables = {
        "linux_build_version": linux_build_version,
        "source_date_epoch_formatted": source_date_epoch_formatted,
        "version_suffix": version_suffix,
        "build_version": build_version,
        "version_codename": version_codename,
        "debarch": "amd64",
        "kernelarch": "x86",
        "local_version": local_version,
    }

    render_template("debian/control", template_variables)
    render_template("debian/changelog", template_variables)
    render_template("debian/rules.vars", template_variables)

    # Copy custom /config
    print("Copying custom config for kernel source", linux_version)
    shutil.copy("/config", "debian/kconfig")

    # Building Linux kernel source
    print("Building Linux kernel source", linux_version)
    env = os.environ.copy()
    # inject our deterministic seed for latent_entropy plugin
    env["KCFLAGS"] = f"-frandom-seed={derive_seed(release, 'latent_entropy')}"
    subprocess.check_call(
        ["/usr/bin/dpkg-buildpackage", "-uc", "-us"],
        env=env,
    )

    os.chdir("..")
    # Storing build artifacts
    print("Storing build artifacts for", linux_version)
    # Because Python doesn't support brace-fnmatch globbing
    extensions = ["buildinfo", "changes", "dsc", "deb", "tar.xz"]
    artifacts = []
    for extension in extensions:
        artifacts.extend(Path(".").glob(f"*.{extension}"))
    for artifact in artifacts:
        print(f"Copying {artifact}...")
        shutil.copy(str(artifact), "/output")


if __name__ == "__main__":
    main()
