#!/usr/bin/env bash
# Source-integrity and baseline-integrity check for the predicates SDK.
#
# Three questions, all answerable without a compiler and without a network:
#
#   1. Does src/predicates.c still hash to the digest UPSTREAM.md records?
#   2. Is Shewchuk's public-domain dedication still present in the source, in
#      NOTICE.md and in README.md?
#   3. Does every upstream byte this package carries still match the per-file
#      baseline in UPSTREAM-BASELINE.sha256 -- and is that baseline complete,
#      that is, does it account for every carried path, so that a file which is
#      neither upstream nor declared fork work cannot pass unnoticed?
#
# This is a provenance gate, not a build gate. Nothing here compiles, links or
# runs; it is the check that a future edit to the canonical file cannot pass as
# a routine change, and that the record of what upstream *is* cannot quietly
# stop covering the tree. The same checks are performed by the `provenance`
# job in .github/workflows/verify.yml, which calls this script rather than
# carrying a second copy of the same greps, which is a drift risk with nothing
# to detect the drift.
#
# Usage: tools/check-provenance.sh   (from the repository root)
#
# SPDX-License-Identifier: LicenseRef-PublicDomain

set -euo pipefail

cd "$(dirname "$0")/.."

record=UPSTREAM-BASELINE.sha256
failures=0

fail() {
    echo "provenance: $1" >&2
    failures=$((failures + 1))
}

# ---------------------------------------------------------------------------
# 1. the digest UPSTREAM.md records
# ---------------------------------------------------------------------------
# The first 64-hex-digit run in UPSTREAM.md is the recorded SHA256 of
# src/predicates.c. Nothing may be inserted above that line that hashes like a
# digest; see the note in UPSTREAM.md.
expected=$(grep -oE '[0-9a-f]{64}' UPSTREAM.md | head -1)
if [ -z "$expected" ]; then
    echo "UPSTREAM.md records no 64-hex-digit checksum to compare against" >&2
    exit 1
fi

actual=$(sha256sum src/predicates.c | cut -d' ' -f1)
if [ "$expected" != "$actual" ]; then
    fail "src/predicates.c is not the file UPSTREAM.md records"
    echo "  expected $expected" >&2
    echo "  actual   $actual" >&2
    echo "If this is an intentional re-sync, update UPSTREAM.md, NOTICE.md and" >&2
    echo "CHANGELOG.md in the same commit." >&2
else
    echo "src/predicates.c matches the recorded upstream checksum: $actual"
fi

# ---------------------------------------------------------------------------
# 2. the grant
# ---------------------------------------------------------------------------
# The grant lives in the header of the C file. It has to survive in the source,
# and it has to be reproduced somewhere a reader finds without opening C.
for file in src/predicates.c NOTICE.md; do
    if ! grep -q "Placed in the public domain by" "$file"; then
        fail "the public-domain notice is missing from $file"
    fi
done
if ! grep -q "Public domain" README.md; then
    fail "README.md does not state the public-domain terms"
fi
if [ "$failures" -eq 0 ]; then
    echo "the public-domain notice is present in the source, the notice and the readme"
fi

# ---------------------------------------------------------------------------
# 3. the per-file baseline, and whether it is complete
# ---------------------------------------------------------------------------
if [ ! -s "$record" ]; then
    fail "$record is missing or empty; there is no baseline to check"
else
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    grep -v '^#' "$record" >"$tmp/manifest.sha256"
    sed -n 's/^# fork-owned-file: //p' "$record" >"$tmp/fork-files"
    sed -n 's/^# fork-owned-prefix: //p' "$record" >"$tmp/fork-prefixes"
    sed -n 's/^# must-not-exist: //p' "$record" >"$tmp/must-not-exist"
    sed -n 's/^# pin-echo: //p' "$record" >"$tmp/pin-echoes"

    # 3a. the carried upstream bytes
    if sha256sum -c --quiet --strict "$tmp/manifest.sha256" >"$tmp/manifest.log" 2>&1; then
        :
    else
        sed 's/^/  /' "$tmp/manifest.log" >&2
        fail "a carried upstream file does not match the baseline, or is missing"
    fi

    manifest_count=$(wc -l <"$tmp/manifest.sha256")
    divergence_count=$(grep -c '^# divergence: ' "$record" || true)

    # 3b. the counts in the record are the counts in the file
    stated_total=$(sed -n 's/^# count: carried upstream paths in this baseline = //p' "$record")
    [ "$stated_total" = "$manifest_count" ] ||
        fail "the record claims $stated_total carried upstream paths and lists $manifest_count"

    stated_identical=$(sed -n 's/^# count: byte-identical to the pin = //p' "$record")
    [ "$stated_identical" = "$manifest_count" ] ||
        fail "the record claims $stated_identical byte-identical paths and lists $manifest_count"

    stated_div=$(sed -n 's/^# count: recorded divergences from the pin = //p' "$record")
    [ "$stated_div" = "$divergence_count" ] ||
        fail "the record claims $stated_div divergences and records $divergence_count"

    # The one area this upstream scope has.
    stated_src=$(sed -n 's/^# area: src = //p' "$record")
    actual_src=$(cut -c67- "$tmp/manifest.sha256" | awk '/^src\// { n++ } END { print n + 0 }')
    [ "$stated_src" = "$actual_src" ] ||
        fail "the record claims $stated_src paths under src/ and lists $actual_src"

    # 3c. coverage in the other direction: nothing carried is unaccounted for
    find . \( -name .git -o -name .zig-cache -o -name zig-out \) -prune -o -type f -print |
        sed 's#^\./##' | LC_ALL=C sort >"$tmp/carried"
    cut -c67- "$tmp/manifest.sha256" >"$tmp/manifest.paths"
    cat "$tmp/manifest.paths" "$tmp/fork-files" | LC_ALL=C sort -u >"$tmp/known"

    awk 'NR == FNR { pfx[$0] = 1; next }
         {
             path = $0
             drop = 0
             for (p in pfx) {
                 n = length(p)
                 if (length(path) >= n && substr(path, 1, n) == p) { drop = 1; break }
             }
             if (!drop) print path
         }' "$tmp/fork-prefixes" "$tmp/carried" >"$tmp/carried.not-prefix"

    LC_ALL=C comm -23 "$tmp/carried.not-prefix" "$tmp/known" >"$tmp/unaccounted"
    if [ -s "$tmp/unaccounted" ]; then
        sed 's/^/  /' "$tmp/unaccounted" >&2
        fail "a carried path is neither upstream nor declared fork-owned; if it is fork work, add it as a 'fork-owned-file:' or 'fork-owned-prefix:' line in $record"
    fi

    carried_fork=$(( $(wc -l <"$tmp/carried") - manifest_count ))
    stated_fork=$(sed -n 's/^# count: fork-owned paths carried alongside (excluded below) = //p' "$record")
    [ "$stated_fork" = "$carried_fork" ] ||
        fail "the record claims $stated_fork fork-owned carried paths and the tree carries $carried_fork"

    while read -r path; do
        [ -n "$path" ] || continue
        [ -f "$path" ] || fail "$record declares $path fork-owned but the file is not in the tree"
    done <"$tmp/fork-files"

    # 3d. paths the record says must not exist, and pins UPSTREAM.md must share
    while read -r path; do
        [ -n "$path" ] || continue
        if [ -e "$path" ]; then
            fail "$path must not exist: upstream ships no README to preserve under that name, and $record says so"
        fi
    done <"$tmp/must-not-exist"

    while read -r line; do
        [ -n "$line" ] || continue
        # The value is what precedes the parenthetical explanation, so a pin
        # whose value contains spaces is checked whole rather than by its
        # first word.
        value=${line%% (*}
        value=${value% }
        grep -Fq "$value" UPSTREAM.md ||
            fail "$value is pinned in $record but UPSTREAM.md does not state it"
    done <"$tmp/pin-echoes"

    if [ "$failures" -eq 0 ]; then
        echo "upstream baseline verified: $manifest_count carried upstream path(s), $carried_fork fork-owned paths accounted for"
    fi
fi

# ---------------------------------------------------------------------------
if [ "$failures" -ne 0 ]; then
    echo "provenance: $failures check(s) failed" >&2
    exit 1
fi

echo "provenance checks passed"