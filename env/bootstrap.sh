#!/bin/sh
# Create the build toolchain in env/root (Debian trixie amd64), rootless.
# Re-run to rebuild it from scratch. Enter it with env/run.
set -eu

ENV=$(cd "$(dirname "$0")" && pwd)
ROOT=$ENV/root
TAR=$ENV/root.tar

PACKAGES="
build-essential clang make git ca-certificates curl file xxd
autoconf automake libtool pkgconf uuid-dev libssl-dev
flex bison bc libelf-dev kmod cpio zstd xz-utils python3
gdisk dosfstools mtools e2fsprogs libarchive13t64 7zip bmap-tools
"

die() { echo "bootstrap.sh: $*" >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || die "run as your normal user, not root"

# Ubuntu and Mint don't ship Debian's archive keys; env/keyring holds the
# .asc files from Debian's debian-archive-keyring 2025.1 package. mmdebstrap's
# namespace root may not be able to enter your home directory (mode 750 is
# common), so hand apt a copy in /tmp.
KEYRING=$(mktemp -d)
trap 'rm -rf "$KEYRING"' EXIT
cp "$ENV"/keyring/*.asc "$KEYRING/"
chmod -R a+rX "$KEYRING"

mmdebstrap \
    --mode=unshare \
    --variant=apt \
    --keyring="$KEYRING" \
    --include="$(echo $PACKAGES | tr ' ' ',')" \
    trixie "$TAR"

case "$ROOT" in */env/root) rm -rf "$ROOT" ;; *) die "refusing to delete $ROOT" ;; esac
mkdir -p "$ROOT"
# Extracting as a normal user makes every file ours; env/run maps us to root inside.
tar -x -f "$TAR" -C "$ROOT" --exclude='./dev/*'
rm -f "$TAR"

echo "Toolchain ready in $ROOT. Next: env/build-cctools.sh"
