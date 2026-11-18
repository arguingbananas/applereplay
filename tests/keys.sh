# tools/keys, the virtual keyboard that drives Total Replay over SSH: its key
# names here, and on the box (TEST_BOX=1) that the keyboard appears and goes.
K=$PROJECT/tools/keys

check "key names map to the kernel's codes (1 is 2, 0 is 11, Q 16, A 30, Z 44, F1 59, F12 88, keypad 7 71)" sh -c "
    [ \"\$(python3 '$K' --print 1 0 q a z f1 f12 kp7 | tr '\n' ' ')\" = '2 11 16 30 44 59 88 71 ' ]"
check "capitals are typed with Shift, + holds keys together, and 2.5s waits" sh -c "
    [ \"\$(python3 '$K' --print A KAR ctrl+f10 2.5s | tr '\n' ' ')\" = '42 30 42 37 42 30 42 19 29 68 2.5 ' ]"
check "an unknown key name is refused (exit 2) before anything is typed" sh -c "
    python3 '$K' --print enter nosuchkey; [ \$? -eq 2 ]"
check "--monkey sends no function keys, Alt or Ctrl (which save, quit or change the video mode)" python3 -c "
import importlib.machinery, importlib.util
l = importlib.machinery.SourceFileLoader('keys', '$K')
m = importlib.util.module_from_spec(importlib.util.spec_from_loader('keys', l))
l.exec_module(m)
bad = {m.KEYS[n] for n in m.KEYS if n.startswith('f') and n[1:].isdigit()} | {m.KEYS['alt'], m.KEYS['ctrl']}
assert not bad & {c for k in m.PLAY for c in m.parse([k])[0]}, 'a forbidden key in PLAY'"

if [ "${TEST_BOX:-}" = 1 ]; then
    box 'cat > /tmp/applereplay-keys' < "$K"
    check "on the box, the virtual keyboard appears while keys runs and is gone after" box '
        sudo python3 /tmp/applereplay-keys 3s & sleep 2
        grep -q "applereplay-keys" /proc/bus/input/devices || exit 1
        wait; ! grep -q "applereplay-keys" /proc/bus/input/devices'
fi
