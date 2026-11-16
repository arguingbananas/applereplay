#!/bin/sh
# What the daily GitHub workflow runs (.github/workflows/kernel-pin.yml).
# While hooks/customize.sh pins the kernel to one version, asks Debian's
# archive whether a newer i386 kernel is out that tests/known-bad-kernels
# doesn't list, i.e. whether the pin can go, and writes a report.
#   .github/kernel-pin-check.sh [Packages-file...]   > report.md
# With arguments, reads those Packages files instead of Debian's (for tests).
# Exits 0 with nothing to do, 1 when a kernel to unpin to is out, 2 if the
# check itself failed.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
pinned=$(sed -n 's/^KERNEL_PACKAGE=//p' "$here/hooks/customize.sh")
[ -n "$pinned" ] || { echo "kernel-pin-check: no KERNEL_PACKAGE in hooks/customize.sh" >&2; exit 2; }
if [ "$pinned" = linux-image-686-pae ]; then
    echo "The kernel isn't pinned (hooks/customize.sh installs linux-image-686-pae); nothing to check."
    exit 0
fi

packages=$(mktemp)
trap 'rm -f "$packages"' EXIT
if [ $# -gt 0 ]; then
    cat "$@" > "$packages"
else
    for url in https://security.debian.org/debian-security/dists/bookworm-security/main/binary-i386/Packages.xz \
        https://deb.debian.org/debian/dists/bookworm/main/binary-i386/Packages.xz; do
        curl -fsSL "$url" | xz -dc >> "$packages" ||
            { echo "kernel-pin-check: couldn't read $url" >&2; exit 2; }
    done
fi

# The newest version of a package across the Packages files.
newest() {
    awk -v p="$1" '$0 == "Package: " p { f = 1 } f && /^Version:/ { print $2; f = 0 }' "$packages" |
        while read -r v; do
            if [ -z "${best:-}" ] || dpkg --compare-versions "$v" gt "$best"; then best=$v; fi
            echo "$best"
        done | tail -n 1
}
latest=$(newest linux-image-686-pae)
have=$(newest "$pinned")
[ -n "$latest" ] && [ -n "$have" ] ||
    { echo "kernel-pin-check: Debian lists no linux-image-686-pae or $pinned for i386" >&2; exit 2; }

if ! dpkg --compare-versions "$latest" gt "$have"; then
    echo "The image is pinned to $pinned ($have), and Debian has nothing newer for i386."
    exit 0
fi
bad=$(grep -v '^#' "$here/tests/known-bad-kernels" | awk -v v="$latest" '$1 == v { $1 = ""; sub(/^ +/, ""); print }')
if [ -n "$bad" ]; then
    echo "The image is pinned to $pinned ($have). Debian's newest i386 kernel, $latest, is"
    echo "listed in tests/known-bad-kernels: $bad"
    exit 0
fi

cat <<EOF
Debian has an i386 kernel newer than the pinned one that tests/known-bad-kernels doesn't list:
\`linux-image-686-pae\` **$latest** (the image is pinned to \`$pinned\`, $have).

To unpin (docs/NOTES.md, "Kernel pinned to 6.1.190"): put \`linux-image-686-pae\` back in
hooks/customize.sh, rebuild, write the stick, run \`TEST_BOX=1 tests/run\` (the ext4
reproducer must pass), then \`env/vuln-check --record\`. If the new kernel fails, add it to
tests/known-bad-kernels instead.

This issue closes itself after either change reaches main.
EOF
exit 1
