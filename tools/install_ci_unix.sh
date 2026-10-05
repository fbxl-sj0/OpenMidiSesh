#!/bin/sh
# Project: OpenSesh
# File: tools/install_ci_unix.sh
# Purpose: provision a native compiler inside disposable CI guests.
# Responsibilities: install host tools and only hash-verified compiler packages.
# This file does not provision a developer workstation or a persistent server.

set -eu
[ "${GITHUB_ACTIONS:-}" = true ] || {
    echo 'This provisioner is restricted to ephemeral GitHub Actions jobs.' >&2
    exit 1
}
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
as_root() {
    if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}
case "$(uname -s)" in
    Linux)
        # The existing Linux provisioner has independently pinned DEB identities.
        bash "$root/tools/install_ci_freebasic.sh"
        apt-get install -y --no-install-recommends xvfb xauth
        exit 0
        ;;
    FreeBSD)
        target=freebsd
        as_root pkg install -y bash coreutils curl python312 gcc binutils \
            libffi libX11 libXext libXpm libXrandr libXrender mesa-libs \
            ncurses xorg-vfbserver xauth
        ;;
    NetBSD)
        target=netbsd
        as_root pkgin -y update
        as_root pkgin -y install bash coreutils curl python312 gcc12 \
            libffi libX11 libXext libXpm libXrandr libXrender MesaLib \
            ncurses modular-xorg-server xauth
        ;;
    OpenBSD)
        target=openbsd
        as_root pkg_add -I bash coreutils curl python%3.12 gcc-11.2.0p19 g++-11.2.0p19 libffi
        ;;
    Haiku)
        target=haiku
        pkgman install -y python312 curl libffi_devel ncurses6_devel
        ;;
    *) echo 'Unsupported native CI host.' >&2; exit 1 ;;
esac

python=python3
if ! command -v "$python" >/dev/null 2>&1; then python=python3.12; fi
download_root=$(mktemp -d "${TMPDIR:-/tmp}/opensesh-toolchain.XXXXXXXX")
trap 'rm -rf -- "$download_root"' EXIT
"$python" "$root/tools/fetch_ci_toolchain.py" "$target" "$download_root"
case "$target" in
    freebsd) as_root pkg add "$download_root/"*.pkg ;;
    netbsd) as_root pkg_add "$download_root/"*.tgz ;;
    openbsd) as_root pkg_add -D unsigned "$download_root/"*.tgz ;;
    haiku) pkgman install -y "$download_root/"*.hpkg ;;
esac
fbc -version

# end of tools/install_ci_unix.sh
