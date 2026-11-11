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

# Judged by the median second, not the mean: Total Replay's attract mode has
# brief dips (full-screen transitions at 56-57 fps, disk loads, and one mean
# of 53.2 over 20 s that is still unexplained; see docs/NOTES.md), while the
# regressions seen so far lasted: 11 and 38 fps all the time, 52-54 through
# minutes of attract mode. A dip shorter than 15 s can't move the median. The lowest
# second is shown so a dip stays visible; the counts stay in out/test/fps.txt.
box 'sudo fps -s 30' > "$SCRATCH/fps.txt" 2>&1
median=$(sed -n 's/^Per second: median \([0-9]*\), lowest \([0-9]*\) .*/\1/p' "$SCRATCH/fps.txt")
lowest=$(sed -n 's/^Per second: median \([0-9]*\), lowest \([0-9]*\) .*/\2/p' "$SCRATCH/fps.txt")
check "linapple's median second over 30 s has 58 frames or more (median ${median:-?}, lowest ${lowest:-?})" \
    sh -c "[ '${median:-0}' -ge 58 ] || { cat '$SCRATCH/fps.txt'; exit 1; }"
