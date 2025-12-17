#!/usr/bin/env python3
"""
Upload built kernels to internal storage, build-logs, and apt-test

Assumes you have the infrastructure, build-logs, and securedrop-apt-test
repositories checked out and fresh kernels in build/. Then it'll sign and
upload the tarball internally, copy the build metadata to build-logs and commit
and then copy the debs to apt-test and commit.

Nothing will be pushed publicly, it'll print the commands to do so.
"""

import shutil
import subprocess
from datetime import datetime
from pathlib import Path

from debian import deb822

VERSION_MAPPING = {"core": {"6.6": "noble"}, "workstation": {"6.6": "bookworm"}}

IS_QUBES = Path("/usr/share/qubes/marker-vm").exists()
BUILD_PATH = Path(__file__).parent / "build"
APT_TEST_REPO = Path(__file__).parent.parent / "securedrop-apt-test"
BUILDLOGS_REPO = Path(__file__).parent.parent / "build-logs"
INFRASTRUCTURE_REPO = Path(__file__).parent.parent / "infrastructure"


def infra_source_tarballs(*args):
    return subprocess.check_output(
        ["poetry", "run", "./tools/source-tarballs"] + list(args), cwd=INFRASTRUCTURE_REPO
    )


def upload_orig_if_needed(orig: str):
    already_uploaded = infra_source_tarballs("list").decode().splitlines()
    if orig in already_uploaded:
        print(f"Tarball already uploaded: {orig}")
        return
    # Check if we need to sign it
    sig_path = BUILD_PATH / (orig + ".sig")
    if not sig_path.exists():
        print(f"Signing {orig}")
        gpg = "qubes-gpg-client-wrapper" if IS_QUBES else "gpg"
        sig = subprocess.check_output([gpg, "--detach-sig", "--armor", orig], cwd=BUILD_PATH)
        sig_path.write_bytes(sig)
    print(f"Uploading {orig}")
    # output goes to stderr so it'll get printed to the user
    infra_source_tarballs("upload", (BUILD_PATH / orig).absolute())


def find_file(files, kind, func):
    for file in files:
        if func(file):
            return file
    raise RuntimeError(f"Unable to find {kind}")


def copy_build_logs(buildinfo, build_log, is_workstation, kernel_version):
    year = datetime.now().year
    buildinfo_dir = BUILDLOGS_REPO / "buildinfo" / str(year)
    if not buildinfo_dir.exists():
        buildinfo_dir.mkdir()
    buildinfo_dest = buildinfo_dir / buildinfo
    if buildinfo_dest.exists():
        raise RuntimeError(f"{buildinfo} already exists??")
    shutil.copy2(BUILD_PATH / buildinfo, buildinfo_dest)
    flavor = "workstation" if is_workstation else "core"
    buildlog_dir = BUILDLOGS_REPO / flavor
    shutil.copy2(BUILD_PATH / build_log, buildlog_dir / build_log)
    subprocess.check_call(
        ["git", "add", buildinfo_dest, buildlog_dir / build_log], cwd=BUILDLOGS_REPO
    )
    subprocess.check_call(
        ["git", "commit", "-m", f"Adding build metadata for Linux {kernel_version} ({flavor})"],
        cwd=BUILDLOGS_REPO,
    )


def copy_debs(files, is_workstation, major_version, kernel_version):
    flavor = "workstation" if is_workstation else "core"
    distro = VERSION_MAPPING[flavor][major_version]

    dests = []

    for file in files:
        if file.endswith(".deb") and "-libc-dev" not in file and "-dbg" not in file:
            dest = APT_TEST_REPO / flavor / distro / file
            if dest.exists():
                raise RuntimeError(f"{file} already exists??")
            print(f"Copying {file} -> {flavor}/{distro}")
            shutil.copy2(BUILD_PATH / file, dest)
            dests.append(dest)

    current_branch = (
        subprocess.check_output(["git", "branch", "--show-current"], cwd=APT_TEST_REPO)
        .decode()
        .strip()
    )
    wanted_branch = f"linux-{kernel_version}"
    if current_branch != wanted_branch:
        subprocess.check_call(["git", "checkout", "-b", wanted_branch], cwd=APT_TEST_REPO)
    subprocess.check_call(["git", "add"] + dests, cwd=APT_TEST_REPO)
    subprocess.check_call(
        ["git", "commit", "-m", f"Adding Linux {kernel_version} ({flavor}) packages"],
        cwd=APT_TEST_REPO,
    )


def process_changes(changes: deb822.Changes):
    files = [item["name"] for item in changes["Checksums-Sha256"]]
    orig = find_file(files, "orig tarball", lambda f: f.endswith(".orig.tar.xz"))
    upload_orig_if_needed(orig)
    major_version = ".".join(changes["Version"].split(".")[:2])
    kernel_version = changes["Version"].split("-", 1)[0]
    is_workstation = "workstation" in orig
    log_pattern = f"-securedrop-{'workstation' if is_workstation else 'core'}-{major_version}.log"
    buildinfo = find_file(files, "buildinfo", lambda f: f.endswith(".buildinfo"))
    # the build log is not in .changes, so need to look in the BUILD_PATH directly
    build_log = find_file(
        BUILD_PATH.glob("*.log"), "build log", lambda f: f.name.endswith(log_pattern)
    ).name
    copy_build_logs(buildinfo, build_log, is_workstation, kernel_version)
    # Copy the packages over
    copy_debs(files, is_workstation, major_version, kernel_version)


def main():
    changes = BUILD_PATH.glob("*.changes")
    for change in changes:
        print(f"Processing {change.name}")
        with change.open() as f:
            deb_changes = deb822.Changes(f)
        process_changes(deb_changes)
    print("Source tarballs uploaded and all commits prepared. Next steps:")
    print("")
    print("git -C ../build-logs push")
    print("git -C ../securedrop-apt-test push")
    print("")
    print("Then open a PR in the securedrop-apt-test repository!")


if __name__ == "__main__":
    main()
