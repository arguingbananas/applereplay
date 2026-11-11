# Checks that need no build: scripts parse, patches apply, the overlay's
# services point at files that exist, and nothing private is tracked by git.
cd "$PROJECT"

# Every tracked shell script (by its #! line), except the submodule.
scripts=$(git ls-files | grep -v '^src/' | while read -r f; do
    [ -f "$f" ] && head -c 20 "$f" | grep -q '^#!/bin/sh' && echo "$f"; done)
check "the shell scripts parse ($(echo $scripts | wc -w) of them)" sh -c '
    for f; do sh -n "$f" || exit 1; done' sh $scripts
# Prefer the build environment's shellcheck: newer versions add warnings, so
# everyone should check with the same one.
if [ -x env/root/usr/bin/shellcheck ]; then
    check "shellcheck (env) finds no warnings" env/run shellcheck -S warning $scripts
elif command -v shellcheck >/dev/null; then
    check "shellcheck (host) finds no warnings" shellcheck -S warning $scripts
else
    echo "  skip  shellcheck (not installed)"
fi

check "each overlay service's ExecStart exists in the overlay or the image" sh -c '
    for u in overlay/etc/systemd/system/*.service; do
        exe=$(sed -n "s/^ExecStart=\([^ ]*\).*/\1/p" "$u")
        [ -z "$exe" ] && continue
        case $exe in /usr/local/*) [ -x "overlay$exe" ] || { echo "$u: $exe"; exit 1; } ;; esac
    done'
check "the HDMI audio service needs hda-verb, and build.sh installs alsa-tools" \
    grep -q '^less .* alsa-tools' build.sh

L=$PROJECT/out/src/linapple
if [ -d "$L/.git" ]; then
    ref=$(sed -n 's/^LINAPPLE_REF=\${LINAPPLE_REF:-\(.*\)}$/\1/p' build.sh)
    check "out/src/linapple is at build.sh's pinned commit" \
        sh -c "[ \"\$(git -C '$L' rev-parse HEAD)\" = '$ref' ]"
    T=$SCRATCH/static
    rm -rf "$T"
    mkdir -p "$T"
    git -C "$L" archive HEAD | tar -x -C "$T"
    # A repo of its own: inside this project's repo, git apply would silently
    # skip every file.
    git init -q "$T"
    check "the patches apply to upstream, in order" sh -c "
        for p in '$PROJECT'/patches/linapple-*.patch; do git -C '$T' apply \"\$p\" || exit 1; done"
    check "out/src/linapple has no edits beyond patches/ (save them as patches first)" \
        diff -r -q -x 'build-*' -x '.git*' "$T" "$L"
    rm -rf "$T"
else
    echo "  skip  patch checks (no out/src/linapple; run ./build.sh)"
fi

# boot.efi is known to show an 8-bit RGB PNG of 640x360; nothing else was tried.
check "logo/BootLogo.png is what logo/make-logo.py draws: 640x360, 8-bit RGB, not interlaced" sh -c "
    python3 '$PROJECT/logo/make-logo.py' | cmp -s - '$PROJECT/logo/BootLogo.png' &&
    [ \"\$(od -A n -t u1 -j 16 -N 13 '$PROJECT/logo/BootLogo.png' | tr -s ' ')\" = ' 0 0 2 128 0 0 1 104 8 2 0 0 0' ]"
check "the overlay has no empty directories (git drops them, so a clone would lack them)" \
    sh -c "[ -z \"\$(find '$PROJECT/overlay' -type d -empty)\" ]"
# Which files they are, not whether yours match: build.sh and mkimage.sh warn about that.
check "assets.sha256 names the four files the build takes from assets/" sh -c "
    [ \"\$(grep -cE '^[0-9a-f]{64}  assets/' '$PROJECT/assets.sha256')\" -eq 4 ] &&
    [ \"\$(wc -l < '$PROJECT/assets.sha256')\" -eq 4 ] &&
    grep -q ' assets/total-replay\.hdv\$' '$PROJECT/assets.sha256' &&
    grep -q ' assets/atv-boot/boot\.efi\$' '$PROJECT/assets.sha256'"
check "git ignores build output, keys, assets and personal notes" \
    git check-ignore out/ssh/totalreplay_ed25519 out/hostkeys assets/total-replay.hdv \
        assets/atv-boot/boot.efi env/root CLAUDE.local.md
check "no private keys are tracked" sh -c "! git grep -l 'PRIVATE KEY' -- . ':!env/keyring' ':!tests/static.sh'"
# Paths on the box (/home/apple) are fine; anyone else's home, a private IP
# or a personal email address is not.
private_ip='\b(10|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+\b'
personal_email='@(gmail|yahoo|outlook|hotmail|icloud)\.'
no_leaks() {
    ! { git grep -nE '/home/[a-z]+' -- . ':!env/keyring' | grep -v '/home/apple'
        git grep -nE "$private_ip|$personal_email" -- . ':!env/keyring' ':!tests/static.sh'
      } | grep .
}
check "no home paths, private IPs or personal email addresses are tracked" no_leaks
