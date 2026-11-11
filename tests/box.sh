# Health of the running Apple TV, over SSH. Only with TEST_BOX=1; it only
# reads (plus ~20 s of `sudo fps`), so a game in progress keeps running.
[ "${TEST_BOX:-}" = 1 ] || skip "the Apple TV (set TEST_BOX=1)"

# TEST_BOX=1 asks for the box, so an unreachable one is a failure, not a skip.
check "the Apple TV answers over SSH ($BOX_HOST)" box true || exit 1
box '
    echo "host $(hostname)"
    echo "cmdline $(cat /proc/cmdline)"
    echo "nouveau $(grep -c "^nouveau " /proc/modules)"
    echo "fb $(cat /proc/fb)"
    for s in applereplay-fb-wc applereplay-hdmi-audio ssh; do echo "svc $s $(systemctl is-active $s)"; done
    echo "failed $(systemctl --failed --no-legend | wc -l)"
    echo "mtrr $(sudo grep -c write-combining /proc/mtrr)"
    echo "stream $(head -1 /proc/asound/card0/pcm3p/sub0/status)"
    echo "dig1 $(sudo hda-verb /dev/snd/hwC0D1 0x02 0xf0d 0 2>/dev/null | sed -n "s/value = //p")"
    echo "chans $(sudo hda-verb /dev/snd/hwC0D1 0x02 0xf2d 0 2>/dev/null | sed -n "s/value = //p")"
    echo "xshadow $(grep -c "\"ShadowFB\" \"false\"" /var/log/Xorg.0.log)"
    echo "linapple $(pgrep -x linapple-sdl2 | wc -l)"
' > "$SCRATCH/box.txt" 2>&1
B=$SCRATCH/box.txt
has() { grep -qx "$1" "$B"; }

check "it's applereplay" has "host applereplay"
check "nouveau is blacklisted and not loaded; X has the firmware framebuffer" sh -c "
    grep -q '^cmdline .*modprobe.blacklist=nouveau' '$B' && grep -qx 'nouveau 0' '$B' &&
    grep -q '^fb 0 EFI VGA' '$B'"
check "its services are running and none have failed" sh -c "
    grep -qx 'svc applereplay-fb-wc active' '$B' && grep -qx 'svc applereplay-hdmi-audio active' '$B' &&
    grep -qx 'svc ssh active' '$B' && grep -qx 'failed 0' '$B'"
check "the framebuffer is write-combining" grep -q '^mtrr [1-9]' "$B"
check "linapple is running with X's shadow framebuffer off" sh -c "
    grep -qx 'linapple 1' '$B' && grep -q '^xshadow [1-9]' '$B'"
check "HDMI audio is streaming with digital out on, in stereo" sh -c "
    grep -qx 'stream state: RUNNING' '$B' && grep -qx 'dig1 0x1' '$B' && grep -qx 'chans 0x1' '$B'"

# 55, not 60: full-screen transitions in Total Replay's attract mode (a title
# screen drawn in across the whole screen) run at 56-57 fps; see docs/NOTES.md.
# Every regression seen so far was far lower (11, 38, 52-54 fps).
box 'sudo fps 20' > "$SCRATCH/fps.txt" 2>&1
check "linapple runs at 55 fps or more over 20 s ($(sed -n 's/.*: \([0-9.]*\) fps.*/\1/p' "$SCRATCH/fps.txt") fps)" \
    awk '/fps/ { if ($6 + 0 >= 55) ok = 1 } END { exit !ok }' "$SCRATCH/fps.txt"
