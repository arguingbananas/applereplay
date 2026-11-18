#!/bin/sh
# Runs inside the target rootfs (chroot) as mmdebstrap's last customize step.
# build.sh stages everything it needs in $STAGE first.
set -eu

STAGE=/var/tmp/stage
export DEBIAN_FRONTEND=noninteractive

echo "== overlay"
# Copied before the kernel install so its initramfs is built with RESUME=none.
cp -r --no-preserve=ownership "$STAGE/overlay/." /
chmod 0440 /etc/sudoers.d/apple
mkdir -p /boot/atv
# The boot splash (Plymouth) shows the boot logo. In place before the kernel
# install, whose initramfs takes the theme along.
install -m 644 "$STAGE/BootLogo.png" /usr/share/plymouth/themes/applereplay/BootLogo.png

echo "== kernel"
# Debian's newest i386 kernel. 6.1.192-1 crashed in ext4 and the image was
# pinned to 6.1.190 until 6.1.192-2, which Debian says fixes it (docs/NOTES.md,
# Kernel);
# tests/known-bad-kernels keeps a listed version out of the image. Setting
# KERNEL_PACKAGE to one version's package pins it again
# (.github/kernel-pin-check.sh reads it).
KERNEL_PACKAGE=linux-image-686-pae
apt-get install -y --no-install-recommends "$KERNEL_PACKAGE"
ls /boot/vmlinuz-* /boot/initrd.img-*

echo "== user apple"
groups=""
for g in video audio input render plugdev; do
    if getent group "$g" >/dev/null; then groups="$groups${groups:+,}$g"; fi
done
useradd --create-home --shell /bin/bash --groups "$groups" apple
# '*' = no password, but not locked, so SSH key logins still work.
usermod -p '*' apple
cat > /home/apple/.bash_profile <<'EOF'
[ -f ~/.bashrc ] && . ~/.bashrc
if [ "$(tty)" = /dev/tty1 ] && [ ! -e /etc/totalreplay/no-kiosk ]; then
    exec /usr/local/bin/totalreplay-kiosk
fi
EOF
# No "Last login" or Debian's notice on the console as the kiosk starts.
touch /home/apple/.hushlogin
install -d -m 700 /home/apple/.ssh
install -m 600 "$STAGE/authorized_keys" /home/apple/.ssh/authorized_keys
chown -R apple:apple /home/apple

echo "== SSH host keys (kept in out/hostkeys so known_hosts survives rebuilds)"
rm -f /etc/ssh/ssh_host_*
install -m 600 "$STAGE"/hostkeys/ssh_host_*_key /etc/ssh/
install -m 644 "$STAGE"/hostkeys/ssh_host_*_key.pub /etc/ssh/

echo "== linapple (sdl2 for the X kiosk, sdl1 as the fbcon fallback)"
rm -rf /usr/local/src/linapple
cp -r --no-preserve=ownership "$STAGE/linapple" /usr/local/src/linapple
cd /usr/local/src/linapple
for fe in sdl2 sdl1; do
    cmake -S . -B build-$fe -DFRONTEND=$fe -DBUILD_TESTING=OFF -DENABLE_FTP=OFF \
        -DCMAKE_BUILD_TYPE=Release -DENABLE_STRICT_WARNINGS=OFF
    cmake --build build-$fe -j"$(nproc)"
    install -m 755 build-$fe/linapple /usr/local/bin/linapple-$fe
done
cd /
# The first stick shipped a linapple whose libraries weren't installed.
for bin in /usr/local/bin/linapple-*; do
    if ldd "$bin" | grep 'not found'; then echo "$bin: missing libraries" >&2; exit 1; fi
done
# sudo fps: linapple's frame rate and CPU use, measured without perf.
install -m 755 "$STAGE/fps" /usr/local/bin/fps
# The default when the session can't work out a size for the screen itself
# (overlay's screen-factor does that at startup, and gives the same on 720
# lines). Windowed at 1.75x (980x672) on the firmware's 1280x720 screen, leaving 24
# black lines above and below: many TVs overscan 720p, and the one this was
# tuned on has no setting to stop it. Fullscreen would try to switch modes,
# which the firmware framebuffer can't.
# The directory is made here, not as an empty one in overlay/: git doesn't
# keep empty directories, and a fresh clone then failed at this point.
install -d /etc/totalreplay
# Caps Lock Mode 1: the Apple's own Caps Lock, down at startup as on a real
# IIe, so letters reach the Apple as capitals unless Caps Lock is pressed.
# Many older programs take only capitals (a "(Y/N)" prompt ignoring "y").
# In the default mode (0) linapple copies the keyboard's Caps Lock state,
# which X starts with off. The Caps Lock key still toggles it; Shift always
# gives a capital.
sed -e 's/^Screen factor = .*/Screen factor = 1.75/' \
    -e 's/^Caps Lock Mode = .*/Caps Lock Mode = 1/' \
    /usr/local/src/linapple/res/linapple.conf > /etc/totalreplay/linapple.conf
grep -qx 'Screen factor = 1.75' /etc/totalreplay/linapple.conf
grep -qx 'Fullscreen = 0' /etc/totalreplay/linapple.conf
grep -qx 'Caps Lock Mode = 1' /etc/totalreplay/linapple.conf

echo "== Total Replay"
install -d /var/games/apple2
install -m 644 "$STAGE/total-replay.hdv" /var/games/apple2/total-replay.hdv
# Total Replay saves preferences and high scores back to its disk image.
chown -R apple:apple /var/games/apple2

echo "== services"
install -d -m 2755 -g systemd-journal /var/log/journal
systemctl enable applereplay-fb-wc.service applereplay-hdmi-audio.service ssh.service avahi-daemon.service systemd-timesyncd.service networking.service
# The firewall: overlay/etc/nftables.conf (SSH, mDNS and ping in; everything out).
systemctl enable nftables.service
# A kiosk shouldn't be running apt in the background.
systemctl mask apt-daily.timer apt-daily-upgrade.timer
# The boot splash: applereplay-splash-end shows the address on it and ends it
# just before the login on tty1, in place of Plymouth's own services.
systemctl enable applereplay-splash-end.service
systemctl mask plymouth-quit.service plymouth-quit-wait.service

apt-get clean
rm -rf "$STAGE"
# mmdebstrap copied in the build host's resolv.conf; dhclient writes the real one.
rm -f /etc/resolv.conf
