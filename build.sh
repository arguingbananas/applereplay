#!/bin/sh
# Build the Total Replay Apple TV root filesystem, rootless:
#   out/rootfs.tar           the whole root filesystem
#   out/boot/vmlinuz,initrd  its kernel and initramfs, for mach_kernel
#
#   ./build.sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/out
SUITE=bookworm
LINAPPLE_REPO=https://github.com/linappleii/linapple
LINAPPLE_REF=${LINAPPLE_REF:-0b22441e91cb95cb813193195187d02db7227bd0}

PACKAGES="
systemd-sysv udev dbus kmod initramfs-tools zstd
ifupdown isc-dhcp-client iproute2 iputils-ping openssh-server
avahi-daemon libnss-mdns systemd-timesyncd sudo
less nano procps pciutils usbutils evtest alsa-utils alsa-tools libdrm-tests
xserver-xorg-core xserver-xorg-legacy
xserver-xorg-video-fbdev xserver-xorg-input-libinput xinit x11-xserver-utils xterm
libsdl2-2.0-0 libsdl1.2debian libsdl-image1.2 libzip4 libcurl4
build-essential cmake pkg-config imagemagick
libzip-dev libcurl4-openssl-dev zlib1g-dev libsdl2-dev libsdl1.2-dev libsdl-image1.2-dev
"

die() { echo "build.sh: $*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "run as your normal user, not root"
[ -f "$HERE/assets/total-replay.hdv" ] || die "missing assets/total-replay.hdv"
mkdir -p "$OUT/ssh" "$OUT/src" "$OUT/boot" "$OUT/hostkeys/etc/ssh"

# Our login key, and the box's SSH host keys. Both persist across rebuilds.
[ -f "$OUT/ssh/totalreplay_ed25519" ] ||
    ssh-keygen -q -t ed25519 -N '' -C totalreplay -f "$OUT/ssh/totalreplay_ed25519"
ssh-keygen -A -f "$OUT/hostkeys"

if [ "$(git -C "$OUT/src/linapple" rev-parse HEAD 2>/dev/null)" != "$LINAPPLE_REF" ]; then
    rm -rf "$OUT/src/linapple"
    git init -q "$OUT/src/linapple"
    git -C "$OUT/src/linapple" fetch -q --depth 1 "$LINAPPLE_REPO" "$LINAPPLE_REF"
    git -C "$OUT/src/linapple" checkout -q FETCH_HEAD
fi
# Upstream only builds on 64-bit; patches/ makes it build for i386.
git -C "$OUT/src/linapple" reset -q --hard
git -C "$OUT/src/linapple" clean -qfdx
for p in "$HERE"/patches/linapple-*.patch; do git -C "$OUT/src/linapple" apply "$p"; done

# mmdebstrap unpacks the whole system under $TMPDIR. On a disk dpkg syncs every
# file; in RAM the build takes half the time (156 s against 309 s on an SSD).
# So use /dev/shm when it has room, unless TMPDIR is already set. The peak is
# 1.8 GB.
if [ -z "${TMPDIR:-}" ] && [ "$(df --output=fstype /dev/shm 2>/dev/null | tail -1)" = tmpfs ] &&
    [ "$(df --output=avail -BG /dev/shm | tail -1 | tr -dc 0-9)" -ge 4 ]; then
    export TMPDIR=/dev/shm
fi

# mmdebstrap's namespace root may not be able to enter your home directory
# (mode 750 is common), so apt gets the Debian keys from a world-readable copy.
# Project files go in through the sync-in/upload hooks, which run as us.
KEYRING=$(mktemp -d)
trap 'rm -rf "$KEYRING"' EXIT
cp "$HERE"/env/keyring/*.asc "$KEYRING/"
chmod -R a+rX "$KEYRING"

STAGE=/var/tmp/stage
COMPONENTS="main contrib non-free non-free-firmware"
rm -f "$OUT/rootfs.tar" "$OUT/boot/vmlinuz" "$OUT/boot/initrd"

mmdebstrap \
    --mode=unshare \
    --arch=i386 \
    --variant=minbase \
    --keyring="$KEYRING" \
    --include="$(echo $PACKAGES | tr ' ' ',')" \
    --customize-hook="mkdir -p \"\$1$STAGE/overlay\" \"\$1$STAGE/hostkeys\" \"\$1$STAGE/linapple\"" \
    --customize-hook="sync-in '$HERE/overlay' $STAGE/overlay" \
    --customize-hook="sync-in '$OUT/hostkeys/etc/ssh' $STAGE/hostkeys" \
    --customize-hook="sync-in '$OUT/src/linapple' $STAGE/linapple" \
    --customize-hook="upload '$OUT/ssh/totalreplay_ed25519.pub' $STAGE/authorized_keys" \
    --customize-hook="upload '$HERE/assets/total-replay.hdv' $STAGE/total-replay.hdv" \
    --customize-hook="upload '$HERE/tools/fps' $STAGE/fps" \
    --customize-hook="upload '$HERE/hooks/customize.sh' $STAGE/customize.sh" \
    --customize-hook='chroot "$1" sh /var/tmp/stage/customize.sh' \
    --customize-hook="download /vmlinuz '$OUT/boot/vmlinuz'" \
    --customize-hook="download /initrd.img '$OUT/boot/initrd'" \
    "$SUITE" "$OUT/rootfs.tar" \
    "deb http://deb.debian.org/debian $SUITE $COMPONENTS" \
    "deb http://deb.debian.org/debian $SUITE-updates $COMPONENTS" \
    "deb http://security.debian.org/debian-security $SUITE-security $COMPONENTS"

echo
echo "Built $OUT/rootfs.tar ($(file -b "$OUT/boot/vmlinuz" | grep -o 'version [^ ]*'))"
echo "Next: ./mkimage.sh"
