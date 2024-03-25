#!/usr/bin/env python3
import argparse
import logging
import os
import re
import requests
import subprocess
import sys
from requests.auth import HTTPBasicAuth


GRSECURITY_PATCH_TYPES = [
    # stable6 corresponds to the long-term 5.15 kernel, good until Q4 2025
    "stable6",
    # stable9 corresponds to the long-term 6.6 kernel, good until Q4 2026
    "stable9",
]


logging.basicConfig(
    format="%(asctime)s %(levelname)-8s %(message)s",
    level=logging.INFO,
    datefmt="%Y-%m-%d %H:%M:%S",
)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--patch-type",
        action="store",
        default=os.environ.get("GRSECURITY_PATCH_TYPE", "stable6"),
        choices=GRSECURITY_PATCH_TYPES,
        help="Which channel to use for kernel & patch; affects kernel version",
    )
    parser.add_argument(
        "--print-version",
        action="store_true",
        default=False,
        help="Dump kernel version required for specified patch type, then exit",
    )
    args = parser.parse_args()
    return args


class GrsecurityPatch:
    def __init__(self, patch_type):
        if patch_type not in GRSECURITY_PATCH_TYPES:
            raise RuntimeError(f"Invalid --patch-type: '{patch_type}'")
        self.patch_type = patch_type
        self.download_prefix = (
            "https://grsecurity.net/download-restrict/download-redirect.php?file="
        )

        self.grsecurity_username = os.environ.get("GRSECURITY_USERNAME")
        self.grsecurity_password = os.environ.get("GRSECURITY_PASSWORD")
        self.requests_auth = HTTPBasicAuth(self.grsecurity_username, self.grsecurity_password)

    @property
    def patch_name(self):
        patch_name_url = "https://grsecurity.net/latest_{}_patch".format(self.patch_type)
        r = requests.get(patch_name_url)
        r.raise_for_status()
        patch_name = r.content.rstrip().decode("utf-8")
        return patch_name

    @property
    def kernel_version(self):
        """
        Each grsecurity patch is intended for a specific kernel version.
        Extract that kernel version from the name of the patch file.
        """
        grsec_filename_regex = re.compile(
            r"""
                                          grsecurity-
                                          (?P<grsecurity_version>\d+\.\d+)-
                                          (?P<linux_kernel_version>\d+\.\d+\.\d+)-
                                          (?P<grsecurity_patch_timestamp>\d{12})\.patch
                                          """,
            re.VERBOSE,
        )
        name_parts = re.match(grsec_filename_regex, self.patch_name).groupdict()
        return name_parts["linux_kernel_version"]

    @property
    def patch_url(self):
        patch_url = self.download_prefix + self.patch_name
        return patch_url

    @property
    def patch_content(self):
        patch_file = "/tmp/" + self.patch_name
        with open(patch_file) as f:
            patch_content = f.read()
        return patch_content

    def download(self):
        """
        Downloads patch and verifies it.
        """
        for fname in [self.patch_name, self.patch_name + ".sig"]:
            url = self.download_prefix + fname
            dest_file = "/tmp/" + fname
            if os.path.exists(dest_file):
                continue
            download_file(url, dest_file, auth=self.requests_auth)

    def verify(self):
        """
        Performs gpg verification of the detached signature file
        for the patch. Assumes public key is already present in keyring.
        """
        patch_file = "/tmp/" + self.patch_name
        sig_file = patch_file + ".sig"
        cmd = "gpgv --keyring /pubkeys/spender.gpg {} {}".format(sig_file, patch_file).split()
        with open(os.devnull, "w") as f:
            subprocess.check_call(cmd, stdout=f, stderr=f)


def download_file(url, dest_file, auth=None):
    """
    Substitues for curl. Does not clobber files.
    """
    if not os.path.exists(dest_file):
        with requests.get(url, stream=True, auth=auth) as r:
            r.raise_for_status()
            with open(dest_file, "wb") as f:
                for chunk in r.iter_content(chunk_size=8192):
                    f.write(chunk)


def main():
    args = parse_args()
    grsec_config = GrsecurityPatch(args.patch_type)
    logging.debug(f"Found grsec patch for type {args.patch_type}")
    if args.print_version:
        print(grsec_config.kernel_version)
        return 0

    if not ("GRSECURITY_USERNAME" in os.environ and "GRSECURITY_PASSWORD" in os.environ):
        logging.error("Credentials not found, set GRSECURITY_USERNAME & GRSECURITY_PASSWORD")
        return 1

    logging.debug("Fetching grsecurity patch")
    grsec_config.download()
    logging.debug("Verifying grsecurity patch")
    grsec_config.verify()
    print(grsec_config.patch_content)


if __name__ == "__main__":
    sys.exit(main())
