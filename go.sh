#!/bin/bash

set -e
set -u
set -o pipefail


img_name="quay.io/conorsch/kernel-builder"
mkdir -p /tmp/kernels
docker build -t "$img_name" .
docker run -it \
    -e GRSECURITY_USERNAME \
    -e GRSECURITY_PASSWORD \
    -e GRSECURITY=1 \
    -v /tmp/kernels:/output \
    "$img_name"
