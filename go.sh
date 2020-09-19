#!/bin/bash

set -e
set -u
set -o pipefail


img_name="quay.io/conorsch/kernel-builder"
kernel_dir="/tmp/kernels"
mkdir -p "$kernel_dir"
docker build -t "$img_name" .
docker run -it \
    -e GRSECURITY_USERNAME \
    -e GRSECURITY_PASSWORD \
    -e GRSECURITY \
    -v /tmp/kernels:/output \
    "$img_name"

echo "Build complete. Packages can be found at:"
find "$kernel_dir" -type f | sort
