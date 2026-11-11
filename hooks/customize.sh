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

echo "== kernel"
apt-get install -y --no-install-recommends linux-image-686-pae
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
sed -e 's/^Screen factor = .*/Screen factor = 1.75/' \
    /usr/local/src/linapple/res/linapple.conf > /etc/totalreplay/linapple.conf
grep -qx 'Screen factor = 1.75' /etc/totalreplay/linapple.conf
grep -qx 'Fullscreen = 0' /etc/totalreplay/linapple.conf

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

apt-get clean
rm -rf "$STAGE"
# mmdebstrap copied in the build host's resolv.conf; dhclient writes the real one.
rm -f /etc/resolv.conf
