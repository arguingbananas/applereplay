# patches/linapple-stretch-speedup.patch must not change a single pixel:
# tests/stretch-harness.cpp is built against upstream's VideoStretch.cpp and
# against the patched one, and their per-case checksums must match. Also checks
# that stretching bands of whole row blocks matches the full frame, which the
# changed-rows drawing in linapple-sdl2-window-surface.patch relies on.
# Builds with the toolchain in env/root (env/run); i386 too if out/devroot exists.
L=$PROJECT/out/src/linapple
[ -d "$L/.git" ] || skip "no out/src/linapple (run ./build.sh)"
[ -x "$PROJECT/env/root/bin/sh" ] || skip "no toolchain (run env/bootstrap.sh)"

T=$SCRATCH/stretch
rm -rf "$T"
mkdir -p "$T/upstream" "$T/patched"
git -C "$L" archive HEAD src | tar -x -C "$T/upstream"
git -C "$L" archive HEAD src | tar -x -C "$T/patched"
# A repo of its own: inside this project's repo, git apply would silently
# skip every file, and the test would compare upstream with itself.
git init -q "$T/patched"
check "the speedup patch applies to upstream" \
    git -C "$T/patched" apply "$PROJECT/patches/linapple-stretch-speedup.patch"
check "and really changed VideoStretch.cpp" sh -c "
    ! cmp -s '$T/upstream/src/frontends/common/VideoStretch.cpp' '$T/patched/src/frontends/common/VideoStretch.cpp' &&
    grep -q 'struct SrcStep' '$T/patched/src/frontends/common/VideoStretch.cpp'"

# One harness binary per VideoStretch.cpp, built in a given environment.
build() {  # build ENVCMD DIR NAME
    $1 sh -c "g++ -std=c++11 -O2 -I $2/src \
        /work/tests/stretch-harness.cpp $2/src/frontends/common/VideoStretch.cpp \
        -o $2/$3"
}
W=/work/out/test/stretch
check "the harness builds against upstream" build "$PROJECT/env/run" "$W/upstream" harness
check "the harness builds against the patch" build "$PROJECT/env/run" "$W/patched" harness
"$T/upstream/harness" > "$T/upstream.txt"
"$T/patched/harness" > "$T/patched.txt"
check "604 cases ran" sh -c "[ \$(wc -l < '$T/patched.txt') = 604 ]"
check "every case gives the same pixels as upstream (x86_64)" cmp "$T/upstream.txt" "$T/patched.txt"
check "bands of whole blocks match the full frame at 768, 720 and 672 lines" "$T/patched/harness" bands

# The same on the box's own architecture, where the original 64-bit division
# lived, if a devroot is unpacked.
if [ -x "$PROJECT/out/devroot/usr/bin/g++" ]; then
    in_devroot() {  # the devroot sees $T as /usr/local/src/linapple
        DEVROOT_SRC=$T DEVROOT_BUILD=$T/devbuild "$PROJECT/env/devroot" run sh -c "
            cp /dev/stdin /tmp/h.cpp && g++ -std=c++11 -O2 -I $1/src /tmp/h.cpp \
                $1/src/frontends/common/VideoStretch.cpp -o $1/harness32 && $1/harness32" \
            < "$PROJECT/tests/stretch-harness.cpp"
    }
    mkdir -p "$T/devbuild"
    in_devroot /usr/local/src/linapple/upstream > "$T/upstream32.txt" 2>"$T/err32.log"
    in_devroot /usr/local/src/linapple/patched > "$T/patched32.txt" 2>>"$T/err32.log"
    check "every case gives the same pixels as upstream (i386, as on the box)" sh -c "
        [ -s '$T/patched32.txt' ] && cmp '$T/upstream32.txt' '$T/patched32.txt'"
    check "and the same as on x86_64" cmp "$T/patched.txt" "$T/patched32.txt"
else
    echo "  skip  i386 comparison (no out/devroot; run env/devroot init)"
fi

rm -rf "$T"
