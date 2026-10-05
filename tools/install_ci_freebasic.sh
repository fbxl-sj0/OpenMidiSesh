#!/usr/bin/env bash
# Project: OpenSesh
# File: tools/install_ci_freebasic.sh
# Purpose: provision the reviewed FreeBASIC packages in an ephemeral CI runner.
# Responsibilities: verify download bytes before installing native build tools.
# This file does not configure a developer workstation or a service host.

set -eu
if [ "${GITHUB_ACTIONS:-}" != true ] || [ "$(id -u)" -ne 0 ]; then
    echo 'Run this provisioner only as root in an ephemeral GitHub Actions container.' >&2
    exit 1
fi
if [ "$(uname -m)" != x86_64 ]; then
    echo 'The reviewed CI packages require Linux x86_64.' >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl git python3 \
    gcc binutils libc6-dev libx11-dev libxext-dev libxpm-dev libxrandr-dev \
    libxrender-dev libasound2-dev libgl1-mesa-dev libffi-dev libgmp-dev libncurses-dev

download_root=$(mktemp -d /tmp/opensesh-ci-toolchain.XXXXXXXX)
trap 'rm -rf -- "$download_root"' EXIT
base_url=https://github.com/jasonkfirth/fbc/releases/download/v1.20.4
packages=(
    'f1ac655e11a1ba0d5eb2d3e457d89c62dbc263d9470fedb0c76e5cfa120df73b freebasic-bindings_1.20.4-3_all.deb'
    '3851d786930f96e8a0e3d2c639517c7c4033d2fa677065e2a51d6722faf60cfb freebasic-dev_1.20.4-3_all.deb'
    '68a6424b444ffeab1d3313c2280d30f12653fd210d08c47b994cb6bd7e58ba2f freebasic-runtime_1.20.4-3_all.deb'
    'e87ec88154daee837b54f5a7b2efa0f0afffd9dd589a7f08b2ddcc2cdf25f020 freebasic_1.20.4-3_amd64.deb'
)
for package in "${packages[@]}"; do
    expected_sha=${package%% *}
    filename=linux-matrix-linux-ubuntu-resolute-amd64-${package#* }
    curl --fail --location --retry 3 "$base_url/$filename" -o "$download_root/$filename"
    printf '%s  %s\n' "$expected_sha" "$download_root/$filename" | sha256sum --check --status
done
apt-get install -y --no-install-recommends "$download_root/"*.deb
fbc -version

# end of tools/install_ci_freebasic.sh
