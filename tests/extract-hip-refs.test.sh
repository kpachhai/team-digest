#!/usr/bin/env bash
# Unit tests for skills/team-digest/lib/extract-hip-refs.sh (text -> HIP numbers).
# Pure (no network). Uses TEAM_DIGEST_HIP_INDEX to pin the known-HIPs index.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib-assert.sh"
H="$(cd "$DIR/.." && pwd)/skills/team-digest/lib/extract-hip-refs.sh"

NOINDEX="/tmp/team-digest-test-noindex-$$"   # guaranteed-absent -> degraded mode (no filter)
rm -f "$NOINDEX"

# --- Degraded mode (no index): all match forms, dedup, blocklist, sort ---
text='see HIP-1137 and HIP 1140, HIP_1137 dup, hiero-improvement-proposals/blob/main/HIP/hip-1056.md, HIP-0000 placeholder, HIP-9999'
out=$(printf '%s' "$text" | TEAM_DIGEST_HIP_INDEX="$NOINDEX" bash "$H")
assert_eq "degraded: forms+dedup+blocklist+sort" "[1056, 1137, 1140]" "$out"

# --- Blocklisted numbers (0, 9999) are always rejected ---
out=$(printf 'HIP-0000 HIP-9999' | TEAM_DIGEST_HIP_INDEX="$NOINDEX" bash "$H")
assert_eq "blocklist only -> empty" "[]" "$out"

# --- No matches -> empty array ---
out=$(printf 'nothing relevant here' | TEAM_DIGEST_HIP_INDEX="$NOINDEX" bash "$H")
assert_eq "no matches -> []" "[]" "$out"

# --- 5-digit HIP numbers are supported (HIP-10000+) ---
out=$(printf 'HIP-10000 landed' | TEAM_DIGEST_HIP_INDEX="$NOINDEX" bash "$H")
assert_eq "5-digit HIP supported" "[10000]" "$out"

# --- Index filter: only numbers present in the index survive ---
IDX="/tmp/team-digest-test-idx-$$.txt"
printf '1137\n1056\n' > "$IDX"
out=$(printf 'HIP-1137 HIP-1140 HIP-1056 HIP-2000' | TEAM_DIGEST_HIP_INDEX="$IDX" bash "$H")
assert_eq "index filter keeps only known HIPs" "[1056, 1137]" "$out"

# --- Index filter with zero overlap -> empty ---
out=$(printf 'HIP-7777 HIP-8888' | TEAM_DIGEST_HIP_INDEX="$IDX" bash "$H")
assert_eq "index filter, no overlap -> []" "[]" "$out"
rm -f "$IDX"

summary
