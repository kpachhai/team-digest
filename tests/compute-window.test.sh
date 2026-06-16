#!/usr/bin/env bash
# Unit tests for skills/team-digest/lib/compute-window.sh (digest window resolver).
# Pure shell + python date math; no network, no MCP.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib-assert.sh"
H="$(cd "$DIR/.." && pwd)/skills/team-digest/lib/compute-window.sh"

# --- Single explicit date ---
out=$(bash "$H" 2026-05-04)
assert_contains "single -> WINDOW_START" "WINDOW_START=2026-05-04" "$out"
assert_contains "single -> WINDOW_END"   "WINDOW_END=2026-05-04" "$out"
assert_contains "single -> WINDOW_LABEL bare date" "WINDOW_LABEL=2026-05-04" "$out"
assert_contains "single -> IS_RANGE=0"   "IS_RANGE=0" "$out"
assert_contains "single -> START"        "START=2026-05-04T00:00:00Z" "$out"
assert_contains "single -> END"          "END=2026-05-04T23:59:59Z" "$out"
assert_contains "single -> DATE_LABEL alias" "DATE_LABEL=2026-05-04" "$out"

# --- Range via A..B ---
out=$(bash "$H" 2026-06-08..2026-06-14)
assert_contains "range -> WINDOW_START" "WINDOW_START=2026-06-08" "$out"
assert_contains "range -> WINDOW_END"   "WINDOW_END=2026-06-14" "$out"
assert_contains "range -> WINDOW_LABEL"  "WINDOW_LABEL=2026-06-08..2026-06-14" "$out"
assert_contains "range -> IS_RANGE=1"    "IS_RANGE=1" "$out"
assert_contains "range -> START ts"      "START=2026-06-08T00:00:00Z" "$out"
assert_contains "range -> END ts"        "END=2026-06-14T23:59:59Z" "$out"
assert_contains "range -> DATE_LABEL == start" "DATE_LABEL=2026-06-08" "$out"

# --- Range via --from/--to (weekly parity) ---
out=$(bash "$H" --from 2026-06-08 --to 2026-06-14)
assert_contains "--from/--to -> WINDOW_LABEL" "WINDOW_LABEL=2026-06-08..2026-06-14" "$out"
assert_contains "--from/--to -> IS_RANGE=1"   "IS_RANGE=1" "$out"

# --- --days N: last N days ending yesterday; shape + 1-day spread ---
out=$(bash "$H" --days 3)
ws=$(echo "$out" | sed -n 's/^WINDOW_START=//p'); we=$(echo "$out" | sed -n 's/^WINDOW_END=//p')
spread=$(python3 -c "from datetime import date
a=date.fromisoformat('$ws'); b=date.fromisoformat('$we'); print((b-a).days)")
assert_eq "--days 3 -> 2-day spread (inclusive 3 days)" "2" "$spread"
assert_contains "--days 3 -> IS_RANGE=1" "IS_RANGE=1" "$out"

# --- --days 1 collapses to a single day ---
out=$(bash "$H" --days 1)
assert_contains "--days 1 -> IS_RANGE=0" "IS_RANGE=0" "$out"

# --- Default (no arg) = yesterday UTC, single day ---
out=$(bash "$H")
label=$(echo "$out" | sed -n 's/^WINDOW_LABEL=//p')
case "$label" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) pass "default -> YYYY-MM-DD shape" ;;
  *) fail "default -> YYYY-MM-DD shape" "got [$label]" ;;
esac
assert_contains "default -> IS_RANGE=0" "IS_RANGE=0" "$out"
today=$(date -u +%Y-%m-%d)
if [ "$label" \< "$today" ]; then pass "default -> earlier than today"; else fail "default earlier than today" "label=$label today=$today"; fi

# --- Error cases (non-zero exit) ---
bash "$H" 2026-5-4 >/dev/null 2>&1;          assert_eq "single-digit date errors" 1 "$?"
bash "$H" 20260504 >/dev/null 2>&1;          assert_eq "no-dashes date errors"    1 "$?"
bash "$H" not-a-date >/dev/null 2>&1;        assert_eq "non-date arg errors"      1 "$?"
bash "$H" 2026-13-99 >/dev/null 2>&1;        assert_eq "impossible date now errors (python validation)" 1 "$?"
bash "$H" 2026-06-14..2026-06-08 >/dev/null 2>&1; assert_eq "end-before-start errors" 1 "$?"
bash "$H" --from 2026-06-08 >/dev/null 2>&1; assert_eq "--from without --to errors" 1 "$?"
bash "$H" --days 0 >/dev/null 2>&1;          assert_eq "--days 0 errors"          1 "$?"
bash "$H" --days x >/dev/null 2>&1;          assert_eq "--days non-int errors"    1 "$?"
bash "$H" 2026-06-09 --from 2026-06-08 --to 2026-06-14 >/dev/null 2>&1; assert_eq "mixing modes errors" 1 "$?"
bash "$H" 2026-05-04 extra >/dev/null 2>&1;  assert_eq "extra positional errors"  1 "$?"

summary
