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
if [ "$n" -eq 0 ]; then
    echo "Nothing to fix: Debian has no security fixes that the $packages packages in the recorded image lack."
    exit 0
fi

# "CVE-2024-0727 libssl3 (fixed)" -> per package, its CVEs.
echo "Debian has fixed **$n** vulnerabilities in packages of the recorded image since it was built."
echo
echo "| Package | Fixed vulnerabilities |"
echo "| --- | --- |"
awk '{ count[$2]++; ids[$2] = ids[$2] (ids[$2] ? ", " : "") $1 }
     END { for (p in count) print "| `" p "` | " count[p] ": " ids[p] " |" }' "$found" | sort
echo
echo "What to do: rebuild (\`./build.sh && ./mkimage.sh\`), check it, run \`env/vuln-check --record\`"
echo "and commit \`docs/image-packages.status\`. A box that is already running gets the same fixes"
echo "from \`sudo apt update && sudo apt upgrade\`; see SECURITY.md."
echo
echo "Details for each identifier: https://security-tracker.debian.org/tracker/"
exit 1
