#!/bin/sh
# Turn build.sh's output into a complete flash drive image, rootless:
#   out/mach_kernel        atv-linux-loader with out/boot/vmlinuz + initrd inside
#   out/totalreplay.img    GPT: 1 = Apple TV boot (FAT), 2 = ext4 root
#   out/totalreplay.bmap   which blocks hold data, so bmaptool skips the rest
#
#   ./mkimage.sh           then write it with: sudo bmaptool copy out/totalreplay.img /dev/sdX
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/out
ROOT_SIZE_MIB=${ROOT_SIZE_MIB:-6144}
BOOT_SIZE_MIB=511

# Fixed so the kernel command line and fstab never need to change.
BOOT_PARTUUID=4196de2a-2dbd-4da4-9c16-c922a6f0b1dc
ROOT_PARTUUID=b632a136-1138-4ea8-9ead-c8891c82dcac
ROOT_FSUUID=5bbf8fa5-79ee-442f-9f55-f039bfc02107
ATV_RECOVERY_TYPE=5265636f-7665-11aa-aa11-00306543ecac

# modprobe.blacklist=nouveau: keep the 1280x720 screen Apple's firmware set up.
# When nouveau sets a mode, the HDMI transmitter sends YCbCr that the TV takes
# for RGB, so black comes out purple.
# init_on_alloc=0: Debian zeroes every page it hands out; a small CPU cost here.
KERNEL_FLAGS="root=PARTUUID=$ROOT_PARTUUID ro video=vesafb net.ifnames=0 consoleblank=0 init_on_alloc=0 modprobe.blacklist=nouveau"

die() { echo "mkimage.sh: $*" >&2; exit 1; }
for f in rootfs.tar boot/vmlinuz boot/initrd; do
    [ -f "$OUT/$f" ] || die "missing out/$f, run ./build.sh first"
done
# The boot files you fetch yourself (see the README). assets.sha256 has the ones
# this was tested with; others may work, so a different file is only a warning.
for f in boot.efi System/Library/Extensions/Dummy.kext/Contents/Info.plist \
    System/Library/Extensions/Dummy.kext/Contents/MacOS/DummyKext; do
    [ -f "$HERE/assets/atv-boot/$f" ] || die "missing assets/atv-boot/$f"
done
(cd "$HERE" && grep ' assets/atv-boot/' assets.sha256 | sha256sum -c --quiet - >&2) ||
    echo "mkimage.sh: warning: the files above aren't the ones in assets.sha256" >&2

echo "== mach_kernel"
rm -rf "$OUT/loader"
cp -r "$HERE/src/atv-linux-loader" "$OUT/loader"
"$HERE/env/run" make -s -C /work/out/loader KERNEL=../boot/vmlinuz INITRAMFS=../boot/initrd
mv "$OUT/loader/mach_kernel" "$OUT/mach_kernel"
rm -rf "$OUT/loader"

cat > "$OUT/com.apple.Boot.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Background Color</key>
    <integer>0</integer>
    <key>Kernel</key>
    <string>mach_kernel</string>
    <key>Kernel Flags</key>
    <string>$KERNEL_FLAGS</string>
</dict>
</plist>
EOF

echo "== image"
rm -f "$OUT/totalreplay.img" "$OUT/totalreplay.bmap" "$OUT/boot.fat" "$OUT/root.ext4"
"$HERE/env/run" sh -eu -c "
    cd /work/out

    mkfs.vfat -n BOOT -C boot.fat $((BOOT_SIZE_MIB * 1024)) >/dev/null
    mcopy -s -i boot.fat /work/assets/atv-boot/boot.efi /work/assets/atv-boot/System \
        mach_kernel com.apple.Boot.plist ::/

    mke2fs -q -t ext4 -L debian-root -U $ROOT_FSUUID -d rootfs.tar root.ext4 ${ROOT_SIZE_MIB}M

    truncate -s $((1 + BOOT_SIZE_MIB + ROOT_SIZE_MIB + 1))M totalreplay.img
    sgdisk -o \
        -n 1:1M:+${BOOT_SIZE_MIB}M -t 1:$ATV_RECOVERY_TYPE -c 1:boot -u 1:$BOOT_PARTUUID \
        -n 2:0:+${ROOT_SIZE_MIB}M -t 2:8300 -c 2:debian-root -u 2:$ROOT_PARTUUID \
        totalreplay.img >/dev/null
    dd if=boot.fat of=totalreplay.img bs=1M seek=1 conv=notrunc,sparse status=none
    dd if=root.ext4 of=totalreplay.img bs=1M seek=$((1 + BOOT_SIZE_MIB)) conv=notrunc,sparse status=none
    rm boot.fat root.ext4
    sgdisk -p totalreplay.img
    sgdisk -i 2 totalreplay.img | grep -qi 'unique GUID: $ROOT_PARTUUID' || { echo 'partition table missing' >&2; exit 1; }

    # The image is sparse (dd conv=sparse above), so the bmap lists only real data.
    bmaptool -q create -o totalreplay.bmap totalreplay.img
"

echo
echo "Built $OUT/totalreplay.img ($(du -h "$OUT/totalreplay.img" | cut -f1) of data)"
echo "Write it with: sudo bmaptool copy $OUT/totalreplay.img /dev/sdX"
