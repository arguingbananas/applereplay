# linapple's VideoStretch, as the image builds it (the pinned commit plus
# patches/): stretching bands of whole row blocks must match the full frame,
# which the changed-rows drawing in patches/linapple-changed-rows.patch relies
# on, and tests/stretch-harness.cpp's 839 cases must give the same pixels on
# x86_64 and on the box's i386. (The division-free stretch that harness was
# written to check is upstream since linapple#373.)
# Builds with the toolchain in env/root (env/run); i386 too if out/devroot exists.
L=$PROJECT/out/src/linapple
[ -d "$L/.git" ] || skip "no out/src/linapple (run ./build.sh)"
[ -x "$PROJECT/env/root/bin/sh" ] || skip "no toolchain (run env/bootstrap.sh)"

T=$SCRATCH/stretch
rm -rf "$T"
mkdir -p "$T/image"
git -C "$L" archive HEAD | tar -x -C "$T/image"
# A repo of its own: inside this project's repo, git apply would silently
# skip every file.
git init -q "$T/image"
check "patches/ apply to the pinned commit" sh -c "
    for p in '$PROJECT'/patches/linapple-*.patch; do git -C '$T/image' apply \"\$p\" || exit 1; done"

W=/work/out/test/stretch
check "the harness builds" "$PROJECT/env/run" sh -c "g++ -std=c++11 -O2 -I $W/image/src \
    /work/tests/stretch-harness.cpp $W/image/src/frontends/common/VideoStretch.cpp \
    -o $W/image/harness"
"$T/image/harness" > "$T/x86_64.txt"
check "839 cases ran" sh -c "[ \$(wc -l < '$T/x86_64.txt') = 839 ]"
check "bands of whole blocks match the full frame at 768, 720 and 672 lines" "$T/image/harness" bands

# The same on the box's own architecture, if a devroot is unpacked.
if [ -x "$PROJECT/out/devroot/usr/bin/g++" ]; then
    mkdir -p "$T/devbuild"
    # The devroot sees $T as /usr/local/src/linapple.
    DEVROOT_SRC=$T DEVROOT_BUILD=$T/devbuild "$PROJECT/env/devroot" run sh -c "
        cd /usr/local/src/linapple && cp /dev/stdin /tmp/h.cpp &&
        g++ -std=c++11 -O2 -I image/src /tmp/h.cpp \
            image/src/frontends/common/VideoStretch.cpp -o image/harness32 &&
        image/harness32 > i386.txt && { image/harness32 bands; echo \$? > bands32.rc; }" \
        < "$PROJECT/tests/stretch-harness.cpp" > "$T/bands32.txt" 2> "$T/err32.log"
    check "on i386 (as on the box) every case gives the same pixels as on x86_64" sh -c "
        [ -s '$T/i386.txt' ] && cmp '$T/x86_64.txt' '$T/i386.txt' || { cat '$T/err32.log'; exit 1; }"
    check "and the bands match the full frame there too" sh -c "[ \"\$(cat '$T/bands32.rc' 2>/dev/null)\" = 0 ]"
else
    echo "  skip  i386 comparison (no out/devroot; run env/devroot init)"
fi

rm -rf "$T"
