#!/bin/sh
# What the weekly GitHub workflow runs (.github/workflows/vulnerabilities.yml).
# Asks Debian's security tracker which vulnerabilities in the recorded image
# (docs/image-packages.status) Debian has fixed since, and writes a report.
#   .github/vuln-report.sh [debsecan-output]   > report.md
# With an argument, uses that file instead of running debsecan (for tests).
# Exits 0 with nothing to fix, 1 with something, 2 if the check itself failed.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
list=$here/docs/image-packages.status
[ -s "$list" ] || { echo "vuln-report: no $list" >&2; exit 2; }

found=$(mktemp)
trap 'rm -f "$found"' EXIT
if [ $# -gt 0 ]; then
    sort "$1" > "$found"
else
    debsecan --suite bookworm --only-fixed --format summary --status "$list" > "$found.raw" ||
        { rm -f "$found.raw"; echo "vuln-report: debsecan failed" >&2; exit 2; }
    sort "$found.raw" > "$found"
    rm -f "$found.raw"
fi

n=$(grep -c . "$found" || true)
packages=$(grep -c "^Package:" "$list")

# debsecan counts kernel fixes against linux-libc-dev, the kernel's headers,
# not the kernel package itself. When the kernel is held back (see
# tests/known-bad-kernels), the two differ and the kernel's missing fixes
# can't be counted, so say so.
version() { awk -v p="$1" '$0 ~ "^Package: " p "$" { f = 1 } f && /^Version:/ { print $2; exit }' "$list"; }
kernel=$(version 'linux-image-[0-9][^ ]*')
headers=$(version 'linux-libc-dev')
kernel_note() {
    if [ -n "$kernel" ] && [ -n "$headers" ] && [ "$kernel" != "$headers" ]; then
        echo
        echo "Note: the image's kernel is $kernel, but kernel fixes are counted against linux-libc-dev"
        echo "$headers, so whatever Debian fixed between the two isn't listed here. The kernel is"
        echo "held back on purpose while a newer one is listed in tests/known-bad-kernels."
    fi
}

if [ "$n" -eq 0 ]; then
    echo "Nothing to fix: Debian has no security fixes that the $packages packages in the recorded image lack."
    kernel_note
    exit 0
fi

# "CVE-2024-0727 libssl3 (fixed)" -> per package, its CVEs.
echo "Debian has fixed **$n** vulnerabilities in packages of the recorded image since it was built."
echo
echo "| Package | Fixed vulnerabilities |"
echo "| --- | --- |"
# At most ten identifiers per package: a kernel update can fix a thousand.
awk '{ count[$2]++; if (count[$2] <= 10) ids[$2] = ids[$2] (ids[$2] ? ", " : "") $1 }
     END { for (p in count) print "| `" p "` | " count[p] ": " ids[p] (count[p] > 10 ? ", and " count[p] - 10 " more" : "") " |" }' "$found" | sort
echo
echo "What to do: rebuild (\`./build.sh && ./mkimage.sh\`), check it, run \`env/vuln-check --record\`"
echo "and commit \`docs/image-packages.status\`. A box that is already running gets the same fixes"
echo "from \`sudo apt update && sudo apt upgrade\`, except the kernel's: the box boots the kernel built"
echo "into mach_kernel on its boot partition, so a kernel fix needs a new image (\`linux-libc-dev\` here"
echo "stands for the kernel). See SECURITY.md."
echo
echo "Details for each identifier: https://security-tracker.debian.org/tracker/"
kernel_note
exit 1
