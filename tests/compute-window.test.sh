#!/usr/bin/env bash
# Unit tests for skills/team-digest/lib/compute-window.sh (daily date window).
# Pure shell + date math; no network, no MCP.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib-assert.sh"
H="$(cd "$DIR/.." && pwd)/skills/team-digest/lib/compute-window.sh"

# --- Explicit date, no lookback ---
out=$(bash "$H" 2026-05-04)
assert_contains "explicit date -> DATE_LABEL" "DATE_LABEL=2026-05-04" "$out"
assert_contains "explicit date -> START"      "START=2026-05-04T00:00:00Z" "$out"
assert_contains "explicit date -> END"        "END=2026-05-04T23:59:59Z" "$out"
assert_contains "no lookback -> LOOKBACK_START == START" "LOOKBACK_START=2026-05-04T00:00:00Z" "$out"
assert_contains "no lookback -> LOOKBACK_DAYS=0" "LOOKBACK_DAYS=0" "$out"

# --- Lookback widens the start backward by N days ---
out=$(bash "$H" 2026-05-04 --lookback-days 7)
assert_contains "lookback 7 -> LOOKBACK_START back 7 days" "LOOKBACK_START=2026-04-27T00:00:00Z" "$out"
assert_contains "lookback 7 -> END unchanged"              "END=2026-05-04T23:59:59Z" "$out"
assert_contains "lookback 7 -> LOOKBACK_DAYS echoed"       "LOOKBACK_DAYS=7" "$out"

# --- Lookback crossing a month boundary (Mar 1 - 3 days = Feb 26) ---
out=$(bash "$H" 2026-03-01 --lookback-days 3)
assert_contains "lookback crosses month boundary" "LOOKBACK_START=2026-02-26T00:00:00Z" "$out"

# --- Default (no arg) = yesterday UTC: assert shape, and that it is before today ---
out=$(bash "$H")
label=$(echo "$out" | sed -n 's/^DATE_LABEL=//p')
case "$label" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) pass "default arg -> YYYY-MM-DD shape" ;;
  *) fail "default arg -> YYYY-MM-DD shape" "got [$label]" ;;
esac
today=$(date -u +%Y-%m-%d)
if [ "$label" \< "$today" ]; then pass "default arg -> earlier than today (yesterday)"; else fail "default arg -> earlier than today" "label=$label today=$today"; fi

# --- Error cases (non-zero exit) ---
# NOTE: compute-window.sh validates date FORMAT only (regex), not calendar validity -
# unlike compute-week-window.sh / compute-month-window.sh, which parse via python strptime.
# The tests below pin that current behavior; semantic date validation is a known gap
# (documented in tests/README.md).
bash "$H" 2026-5-4 >/dev/null 2>&1;          assert_eq "single-digit (out-of-format) date errors" 1 "$?"
bash "$H" 20260504 >/dev/null 2>&1;          assert_eq "no-dashes date errors"         1 "$?"
bash "$H" not-a-date >/dev/null 2>&1;        assert_eq "non-date arg errors"           1 "$?"
bash "$H" 2026-05-04 extra >/dev/null 2>&1;  assert_eq "unexpected extra arg errors"   1 "$?"
bash "$H" 2026-05-04 --lookback-days x >/dev/null 2>&1; assert_eq "non-integer lookback errors" 1 "$?"

# Characterize the format-only gap: an impossible-but-format-valid date is ACCEPTED.
out=$(bash "$H" 2026-13-99); code=$?
assert_eq "format-valid-but-impossible date is accepted (format-only check; known gap)" "0" "$code"
assert_contains "...and echoed verbatim as DATE_LABEL" "DATE_LABEL=2026-13-99" "$out"

summary
