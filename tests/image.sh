# What ./build.sh and ./mkimage.sh produced: catches build mistakes before a
# stick is written. Reads out/rootfs.tar, out/com.apple.Boot.plist and
# out/totalreplay.img; the partition checks use the toolchain (env/run).
[ -f "$PROJECT/out/rootfs.tar" ] || skip "no out/rootfs.tar (run ./build.sh)"

T=$SCRATCH/image
rm -rf "$T"
mkdir -p "$T/root"
# One pass over the tarball for the files we look at.
tar -x -f "$PROJECT/out/rootfs.tar" -C "$T/root" --wildcards \
    ./etc/hostname ./etc/asound.conf ./etc/X11 ./etc/totalreplay \
    ./etc/ssh/sshd_config.d ./etc/systemd/system ./etc/modprobe.d ./etc/nftables.conf \
    './home/apple/.ssh/authorized_keys' './usr/local/bin/*' './usr/local/sbin/*' \
    ./usr/bin/hda-verb './boot/vmlinuz-*' 2>/dev/null
R=$T/root

# The image is only worth checking against the repo if it was built after
# the last change to anything that goes into it.
newer=$(cd "$PROJECT" && git ls-files build.sh hooks overlay patches tools |
    while read -r f; do [ "$f" -nt out/rootfs.tar ] && echo "$f"; done)
check "out/rootfs.tar is newer than every build input (else run ./build.sh)" \
    sh -c '[ -z "$1" ] || { echo "changed since the build: $1"; exit 1; }' sh "$(echo $newer)"
cd "$R"

check "the hostname is applereplay" grep -qx applereplay etc/hostname
check "X uses fbdev with no shadow framebuffer, and no nouveau config" sh -c '
    grep -q "Option \"ShadowFB\" \"false\"" etc/X11/xorg.conf.d/20-fbdev.conf &&
    ! [ -e etc/X11/xorg.conf.d/20-nouveau.conf ]'
check "linapple is windowed at 1.75x" sh -c '
    grep -qx "Screen factor = 1.75" etc/totalreplay/linapple.conf &&
    grep -qx "Fullscreen = 0" etc/totalreplay/linapple.conf'
check "HDMI (card 0 device 3) is the default sound output" \
    grep -qx 'defaults.pcm.device 3' etc/asound.conf
check "the box's services are enabled" sh -c '
    for s in applereplay-fb-wc applereplay-hdmi-audio ssh avahi-daemon systemd-timesyncd nftables; do
        ls etc/systemd/system/*.wants/$s.service >/dev/null 2>&1 || { echo "$s not enabled"; exit 1; }
    done'
check "apt's background timers are masked" sh -c '
    [ "$(readlink etc/systemd/system/apt-daily.timer)" = /dev/null ] &&
    [ "$(readlink etc/systemd/system/apt-daily-upgrade.timer)" = /dev/null ]'
check "SSH takes keys only, never root" sh -c '
    grep -qx "PasswordAuthentication no" etc/ssh/sshd_config.d/*.conf &&
    grep -qx "PermitRootLogin no" etc/ssh/sshd_config.d/*.conf'
check "the firewall drops what it doesn't name, and names SSH and mDNS" sh -c '
    grep -q "hook input priority filter; policy drop;" etc/nftables.conf &&
    grep -qx " *tcp dport 22 accept" etc/nftables.conf &&
    grep -qx " *udp dport 5353 accept" etc/nftables.conf'
check "the root services are confined to the one capability each needs" sh -c '
    grep -qx "CapabilityBoundingSet=CAP_SYS_ADMIN" etc/systemd/system/applereplay-fb-wc.service &&
    grep -qx "CapabilityBoundingSet=CAP_SYS_RAWIO" etc/systemd/system/applereplay-hdmi-audio.service &&
    for u in applereplay-fb-wc applereplay-hdmi-audio; do
        grep -qx "ProtectSystem=strict" etc/systemd/system/$u.service &&
        grep -qx "NoNewPrivileges=yes" etc/systemd/system/$u.service || exit 1
    done'
check "linapple is built without its FTP client (no libcurl)" sh -c '
    for b in usr/local/bin/linapple-sdl2 usr/local/bin/linapple-sdl1; do
        if grep -q "libcurl\.so" "$b"; then echo "$b links libcurl"; exit 1; fi
    done'
check "apple's authorized key is out/ssh's public key" \
    cmp home/apple/.ssh/authorized_keys "$PROJECT/out/ssh/totalreplay_ed25519.pub"
check "linapple (sdl2 and sdl1), fps, the kiosk and the services' scripts are installed" sh -c '
    for f in usr/local/bin/linapple-sdl2 usr/local/bin/linapple-sdl1 usr/local/bin/fps \
             usr/local/bin/totalreplay-kiosk usr/local/sbin/applereplay-fb-wc \
             usr/local/sbin/applereplay-hdmi-audio usr/bin/hda-verb; do
        [ -x "$f" ] || { echo "missing $f"; exit 1; }
    done'
check "out/boot/vmlinuz is the image's kernel" sh -c "
    for k in boot/vmlinuz-*; do cmp -s \"\$k\" '$PROJECT/out/boot/vmlinuz' && exit 0; done; exit 1"

P=$PROJECT/out/com.apple.Boot.plist
root_uuid=$(sed -n 's/^ROOT_PARTUUID=//p' "$PROJECT/mkimage.sh")
if [ -f "$P" ]; then
    check "the kernel flags blacklist nouveau and name the root partition" sh -c "
        grep -q 'modprobe.blacklist=nouveau' '$P' && grep -q 'root=PARTUUID=$root_uuid' '$P'"
else
    echo "  skip  boot plist (no out/com.apple.Boot.plist; run ./mkimage.sh)"
fi

I=$PROJECT/out/totalreplay.img
if [ -f "$I" ] && [ -x "$PROJECT/env/root/bin/sh" ]; then
    check "partition 1 is an Apple TV recovery partition" sh -c "
        '$PROJECT/env/run' sgdisk -i 1 /work/out/totalreplay.img |
            grep -qi 'Partition GUID code: 5265636F-7665-11AA-AA11-00306543ECAC'"
    check "partition 2 has the PARTUUID the kernel flags expect" sh -c "
        '$PROJECT/env/run' sgdisk -i 2 /work/out/totalreplay.img | grep -qi 'unique GUID: $root_uuid'"
    check "the boot partition holds boot.efi, mach_kernel, the plist and Dummy.kext" sh -c "
        '$PROJECT/env/run' mdir -b -i /work/out/totalreplay.img@@1M ::/ > '$T/boot.txt' &&
        for f in boot.efi mach_kernel com.apple.Boot.plist System; do
            grep -q \"/\$f\" '$T/boot.txt' || { echo \"missing \$f\"; exit 1; }
        done &&
        '$PROJECT/env/run' mdir -b -i /work/out/totalreplay.img@@1M ::/System/Library/Extensions |
            grep -q Dummy.kext"
    check "the boot partition's mach_kernel and plist are the built ones" sh -c "
        '$PROJECT/env/run' mtype -i /work/out/totalreplay.img@@1M ::/com.apple.Boot.plist |
            cmp -s - '$P' &&
        '$PROJECT/env/run' sh -c 'mcopy -n -i /work/out/totalreplay.img@@1M ::/mach_kernel /tmp/mk && cat /tmp/mk' |
            cmp -s - '$PROJECT/out/mach_kernel'"
    check "the bmap matches the image" sh -c "
        grep -q \"<ImageSize> \$(stat -c %s '$I') </ImageSize>\" '$PROJECT/out/totalreplay.bmap'"
else
    echo "  skip  image checks (no out/totalreplay.img or no toolchain)"
fi

cd "$PROJECT"
rm -rf "$T"
