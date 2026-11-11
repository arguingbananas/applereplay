# env/devroot: unpack the image's system, build linapple in it, install it.
# Works on scratch copies in out/test, so the real out/devroot and the linapple
# source are left alone. Needs out/rootfs.tar from ./build.sh.
[ -f "$PROJECT/out/rootfs.tar" ] || skip "no out/rootfs.tar (run ./build.sh)"
[ -d "$PROJECT/out/src/linapple/src" ] || skip "no out/src/linapple (run ./build.sh)"

T=$SCRATCH/dr
rm -rf "$T"
mkdir -p "$T"
cp -a "$PROJECT/out/src/linapple" "$T/src"
export DEVROOT=$T/devroot DEVROOT_BUILD=$T/build DEVROOT_SRC=$T/src
D=$PROJECT/env/devroot

check "init unpacks the image's system" $D init
check "inside is i386 Debian 12 and uname says i686" sh -c '
    [ "$($0 run dpkg --print-architecture)" = i386 ] &&
    [ "$($0 run uname -m)" = i686 ] &&
    $0 run grep -qx "VERSION_ID=\"12\"" /etc/os-release' $D
check "the image's own linapple build tree is left out" \
    sh -c '[ -z "$(ls -A "$DEVROOT/usr/local/src/linapple")" ]'

check "build succeeds" sh -c "$D build >'$T/build.log' 2>&1"
check "it's a 32-bit x86 executable" sh -c "file '$T/build/linapple' | grep -q 'ELF 32-bit.*Intel 80386'"
check "it's byte-identical to the image's linapple-sdl2" \
    cmp "$T/build/linapple" "$DEVROOT/usr/local/bin/linapple-sdl2"

check "rebuilding with no changes compiles nothing" sh -c "
    $D build >'$T/build.log' 2>&1 && [ \"\$(grep -c 'Building CXX object' '$T/build.log')\" = 0 ]"
touch "$T/src/src/frontends/common/VideoStretch.cpp"
check "changing one file recompiles only that file" sh -c "
    $D build >'$T/build.log' 2>&1 && [ \"\$(grep -c 'Building CXX object' '$T/build.log')\" = 1 ]"

touch -d 2000-01-01 "$DEVROOT/.devroot-from"
check "build warns when out/rootfs.tar is newer than the devroot" sh -c "
    $D build 2>&1 | grep -q 'newer than the devroot'"

mkdir "$T/precious"
check "init refuses to delete a directory not named devroot" sh -c "
    ! DEVROOT='$T/precious' $D init 2>'$T/err.log' && grep -q refusing '$T/err.log' && [ -d '$T/precious' ]"
check "an unknown command fails and prints the usage" sh -c "
    ! $D frobnicate 2>'$T/err.log' && grep -q 'env/devroot init' '$T/err.log'"

if [ "${TEST_BOX:-}" = 1 ]; then
    if check "the Apple TV answers over SSH ($BOX_HOST)" box true; then
        { $D install "$BOX_HOST" && sleep 20 &&
            box 'sha256sum /usr/local/bin/linapple-sdl2; pgrep -x linapple-sdl2'
        } > "$T/box.log" 2>&1
        check "install puts the binary on the box and the kiosk comes back" sh -c "
            grep -q \"\$(sha256sum < '$T/build/linapple' | cut -d' ' -f1)\" '$T/box.log' &&
            grep -qE '^[0-9]+\$' '$T/box.log' || { cat '$T/box.log'; exit 1; }"
    fi
else
    echo "  skip  install on the box (set TEST_BOX=1)"
fi

rm -rf "$T"
