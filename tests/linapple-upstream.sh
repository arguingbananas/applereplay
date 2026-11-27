# Upstream linapple's own test suite (doctest, run by ctest), on what the image
# ships: build.sh's pinned commit plus patches/, built in the devroot (the
# box's Debian 12 i386, its compiler and SDL2) with the image's options plus
# BUILD_TESTING. Release, as in the image and in upstream's CI.
# The build directory persists in out/test/linapple-upstream: upstream builds
# each test from source, about 8,200 objects, so the first run takes about 30
# minutes on 8 cores; later runs rebuild only what changed.
L=$PROJECT/out/src/linapple
[ -d "$L/.git" ] || skip "no out/src/linapple (run ./build.sh)"
[ -x "$PROJECT/out/devroot/usr/bin/cmake" ] || skip "no devroot (run env/devroot init)"
cd "$PROJECT" || exit 1

# Upstream fetches doctest from GitHub while configuring, and the devroot has
# no network, so a pinned copy of the one header it needs is kept in out/.
DOCTEST_VERSION=v2.4.11
DOCTEST_SHA256=44faa038e9c3f9728efbda143748d01124ea0a27f4bf78f35a15d8fab2e039fb
DOCTEST=$PROJECT/out/doctest-$DOCTEST_VERSION/doctest.h
if [ ! -f "$DOCTEST" ]; then
    mkdir -p "$(dirname "$DOCTEST")"
    curl -fsSL --max-time 60 -o "$DOCTEST.part" \
        "https://raw.githubusercontent.com/doctest/doctest/$DOCTEST_VERSION/doctest/doctest.h" ||
        skip "no copy of doctest in out/, and it couldn't be downloaded"
    mv "$DOCTEST.part" "$DOCTEST"
fi
check "doctest is the pinned $DOCTEST_VERSION" sh -c \
    "echo '$DOCTEST_SHA256  $DOCTEST' | sha256sum -c --quiet" || exit 1

ref=$(sed -n 's/^LINAPPLE_REF=\${LINAPPLE_REF:-\(.*\)}$/\1/p' build.sh)
check "out/src/linapple is at build.sh's pinned commit" \
    sh -c "[ \"\$(git -C '$L' rev-parse HEAD)\" = '$ref' ]" || exit 1

T=$SCRATCH/linapple-upstream
N=$T/new
rm -rf "$N"
mkdir -p "$N" "$T/src" "$T/build"
git -C "$L" archive HEAD | tar -x -C "$N"
# A repo of its own: inside this project's repo, git apply would silently
# skip every file.
git init -q "$N"
check "the patches apply to upstream, in order" sh -c "
    for p in '$PROJECT'/patches/linapple-*.patch; do git -C '$N' apply \"\$p\" || exit 1; done" || exit 1
rm -rf "$N/.git"
mkdir -p "$N/_doctest/doctest"
cp "$DOCTEST" "$N/_doctest/doctest/"
# Only files whose contents changed are rewritten, so their timestamps tell
# make what to rebuild. build-sdl2 is where the devroot mounts the build tree.
rsync -rc --delete --exclude=/build-sdl2 "$N/" "$T/src/"
rm -rf "$N"

in_devroot() {
    DEVROOT_SRC=$T/src DEVROOT_BUILD=$T/build "$PROJECT/env/devroot" run sh -euc "
        cd /usr/local/src/linapple/build-sdl2
        $1"
}
# The image's options (hooks/customize.sh), plus the tests.
in_devroot "
    cmake .. -DFRONTEND=sdl2 -DENABLE_FTP=OFF -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_STRICT_WARNINGS=OFF -DBUILD_TESTING=ON \
        -DDOCTEST_INCLUDE_DIR=/usr/local/src/linapple/_doctest/doctest >cfg.log 2>&1 ||
        { tail -30 cfg.log; exit 1; }
    cmake --build . -j$(nproc) >build.log 2>&1" || true
check "upstream's tests build (log: out/test/linapple-upstream/build/build.log)" sh -c "
    [ -f '$T/build/cfg.log' ] && grep -q 'Generating done' '$T/build/cfg.log' || { tail -30 '$T/build/cfg.log'; exit 1; }
    ! grep -q -E 'Error [0-9]|error:' '$T/build/build.log' || { grep -m5 -E 'error:|Error [0-9]' '$T/build/build.log'; exit 1; }" || exit 1

in_devroot "ctest -j$(nproc) --output-on-failure >ctest.log 2>&1" || true
summary=$(grep -E 'tests passed, [0-9]+ tests failed' "$T/build/ctest.log")
check "upstream's tests pass (${summary:-no summary}; log: out/test/linapple-upstream/build/ctest.log)" \
    sh -c "echo '$summary' | grep -q '^100% tests passed, 0 tests failed' || { grep -E 'Failed|\\*\\*\\*' '$T/build/ctest.log'; exit 1; }"
