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

# Python scripts must run on the box's Python, 3.11 (Debian 12), so compile
# them with the devroot's copy of it: newer syntax would pass on the build host
# and fail there. Each script also refuses to start on anything older.
pyscripts=$(git ls-files | grep -v '^src/' | while read -r f; do
    [ -f "$f" ] && head -c 30 "$f" | grep -q '^#!/usr/bin/env python3' && echo "$f"; done)
check "every Python script checks for Python 3.11 or newer" sh -c '
    for f; do grep -q "sys.version_info < (3, 11)" "$f" || { echo "$f"; exit 1; }; done' sh $pyscripts
# pyflakes: unused imports and variables, undefined names. Like shellcheck,
# only env's copy, so everyone checks with the same version.
if [ -x env/root/usr/bin/pyflakes3 ]; then
    check "pyflakes (env) finds nothing" env/run pyflakes3 $pyscripts
else
    echo "  skip  pyflakes (not in env/root: env/run apt-get -o APT::Sandbox::User=root install python3-pyflakes)"
fi
if [ -x out/devroot/usr/bin/python3.11 ]; then
    P=$SCRATCH/py311
    rm -rf "$P"; mkdir -p "$P"
    for f in $pyscripts; do mkdir -p "$P/$(dirname "$f")"; cp "$f" "$P/$f"; done
    check "the Python scripts compile with Python 3.11, the box's ($(echo $pyscripts | wc -w) of them)" \
        env DEVROOT_SRC="$P" DEVROOT_BUILD="$P/build" env/devroot run python3.11 -c '
import sys
for f in sys.argv[1:]:
    compile(open(f).read(), f, "exec")' $pyscripts
    rm -rf "$P"
else
    echo "  skip  Python 3.11 compile check (no out/devroot; run env/devroot init)"
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
# The splash's blocks and characters, like the logo, come from a script.
check "the boot splash's images are what logo/make-splash.py draws" sh -c "
    rm -rf '$SCRATCH/splash' && mkdir -p '$SCRATCH/splash' &&
    python3 '$PROJECT/logo/make-splash.py' '$SCRATCH/splash' &&
    T='$PROJECT/overlay/usr/share/plymouth/themes/applereplay' &&
    [ \"\$(ls '$SCRATCH/splash')\" = \"\$(cd \"\$T\" && ls *.png)\" ] &&
    for f in '$SCRATCH'/splash/*.png; do cmp -s \"\$f\" \"\$T/\$(basename \"\$f\")\" || { echo \"differs: \$f\"; exit 1; }; done"
check "the overlay has no empty directories (git drops them, so a clone would lack them)" \
    sh -c "[ -z \"\$(find '$PROJECT/overlay' -type d -empty)\" ]"
# The image gets each overlay file with the mode it has here.
check "every script in the overlay is executable" sh -c "
    for f in \$(grep -rl '^#!/bin/sh' '$PROJECT/overlay'); do
        [ -x \"\$f\" ] || { echo \"not executable: \$f\"; exit 1; }
    done"
# The weekly check on GitHub reads this list; an empty or mangled one would
# pass there for the wrong reason.
check "docs/image-packages.status lists installed packages with versions" sh -c "
    n=\$(grep -c '^Package: ' '$PROJECT/docs/image-packages.status') && [ \"\$n\" -gt 300 ] &&
    [ \"\$(grep -c '^Version: ' '$PROJECT/docs/image-packages.status')\" -eq \"\$n\" ] &&
    grep -q '^Package: linux-image-6\.' '$PROJECT/docs/image-packages.status'"
check "the vulnerability report says nothing to fix for none, and lists packages and fails for some" sh -c "
    : > '$SCRATCH/none.txt' && sh '$PROJECT/.github/vuln-report.sh' '$SCRATCH/none.txt' | grep -q '^Nothing to fix' &&
    printf 'CVE-2024-0727 libssl3 (fixed)\nCVE-2023-5678 libssl3 (fixed)\nCVE-2024-1 zlib1g (fixed)\n' > '$SCRATCH/some.txt' &&
    ! sh '$PROJECT/.github/vuln-report.sh' '$SCRATCH/some.txt' > '$SCRATCH/report.md' &&
    grep -q 'fixed \*\*3\*\* vulnerabilities' '$SCRATCH/report.md' &&
    grep -q '^| .libssl3. | 2: CVE-2023-5678, CVE-2024-0727 |' '$SCRATCH/report.md' &&
    seq -f 'CVE-2026-%g linux-libc-dev (fixed)' 1000 1012 > '$SCRATCH/many.txt' &&
    ! sh '$PROJECT/.github/vuln-report.sh' '$SCRATCH/many.txt' > '$SCRATCH/report.md' &&
    grep -q '^| .linux-libc-dev. | 13: CVE-2026-1000, .*CVE-2026-1009, and 3 more |' '$SCRATCH/report.md'"
# The recorded list's kernel and kernel headers: the report must point out
# when they differ (a held-back kernel), and stay quiet when they match.
image_kernel=$(awk '/^Package: linux-image-[0-9]/ { f = 1 } f && /^Version:/ { print $2; exit }' "$PROJECT/docs/image-packages.status")
headers=$(awk '/^Package: linux-libc-dev$/ { f = 1 } f && /^Version:/ { print $2; exit }' "$PROJECT/docs/image-packages.status")
check "the vulnerability report notes a kernel held back from its headers ($image_kernel vs $headers)" sh -c "
    sh '$PROJECT/.github/vuln-report.sh' '$SCRATCH/none.txt' > '$SCRATCH/report.md'
    if [ '$image_kernel' = '$headers' ]; then ! grep -q 'kernel is' '$SCRATCH/report.md'
    else grep -q \"kernel is $image_kernel, but kernel fixes are counted against linux-libc-dev\" '$SCRATCH/report.md'; fi"
# The daily kernel pin check on GitHub, against made-up archive listings.
check "the kernel pin check is quiet while Debian's newest kernel is known to be bad, and speaks up for a newer one" sh -c "
    if grep -qx 'KERNEL_PACKAGE=linux-image-686-pae' '$PROJECT/hooks/customize.sh'; then
        sh '$PROJECT/.github/kernel-pin-check.sh' | grep -q \"isn't pinned\"; exit; fi
    pinned=\$(sed -n 's/^KERNEL_PACKAGE=//p' '$PROJECT/hooks/customize.sh')
    bad=\$(grep -v '^#' '$PROJECT/tests/known-bad-kernels' | awk 'NR == 1 { print \$1 }')
    printf 'Package: %s\nVersion: 6.1.0-1\n\nPackage: linux-image-686-pae\nVersion: %s\n' \"\$pinned\" \"\$bad\" > '$SCRATCH/bad.pkgs' &&
    sh '$PROJECT/.github/kernel-pin-check.sh' '$SCRATCH/bad.pkgs' | grep -q 'listed in tests/known-bad-kernels' &&
    printf '\nPackage: linux-image-686-pae\nVersion: 99.0-1\n' | cat '$SCRATCH/bad.pkgs' - > '$SCRATCH/new.pkgs' &&
    ! sh '$PROJECT/.github/kernel-pin-check.sh' '$SCRATCH/new.pkgs' > '$SCRATCH/pin.md' &&
    grep -q '\*\*99.0-1\*\*' '$SCRATCH/pin.md'"
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
# All four parts, so version numbers like 10.0.0 don't match.
private_ip='\b(10\.[0-9]+|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+\b'
personal_email='@(gmail|yahoo|outlook|hotmail|icloud)\.'
no_leaks() {
    ! { git grep -nE '/home/[a-z]+' -- . ':!env/keyring' | grep -v '/home/apple'
        git grep -nE "$private_ip|$personal_email" -- . ':!env/keyring' ':!tests/static.sh'
      } | grep .
}
check "no home paths, private IPs or personal email addresses are tracked" no_leaks
# Host names can't be listed here without publishing them, so they come from
# this machine (its own name) and from out/private-names (one per line, for
# other machines; out/ is never committed). Commit messages not yet pushed are
# public too once they are. Names a fresh install gives are skipped.
{ hostname; hostname -s; cat "$PROJECT/out/private-names" 2>/dev/null; } |
    tr 'A-Z' 'a-z' | grep -vxE '|localhost|debian|ubuntu|fedora|raspberrypi|applereplay' |
    sort -u > "$SCRATCH/private-names"
no_host_names() {
    [ -s "$SCRATCH/private-names" ] || return 0
    ! { git grep -n -i -w -F -f "$SCRATCH/private-names" -- . ':!env/keyring'
        git log --branches --not --remotes --format='%h %s%n%b' |
            grep -i -w -F -f "$SCRATCH/private-names"
      } | grep .
}
check "no host names (this machine's, out/private-names) in tracked files or unpushed commit messages" no_host_names
