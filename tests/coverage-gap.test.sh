#!/usr/bin/env bash
# Unit tests for coverage-gap.sh. Pure shell; no network, no MCP.
set -uo pipefail

. "$(dirname "$0")/lib-assert.sh"
HELPER="$(cd "$(dirname "$0")/.." && pwd)/skills/team-digest/lib/coverage-gap.sh"

run() {
  # run <window-start> <window-end> <stdin>  -> echoes helper stdout; sets RC
  local ws="$1" we="$2" input="$3"
  OUT="$(printf '%s' "$input" | bash "$HELPER" --window-start "$ws" --window-end "$we" 2>/dev/null)"
  RC=$?
}

# --- The headline case: 2 range pages cover a 7-day week ---
run 2026-06-08 2026-06-14 $'2026-06-08 2026-06-11\n2026-06-12 2026-06-14\n'
assert_contains "two ranges cover the week -> 0 missing" "MISSING_COUNT=0" "$OUT"
assert_contains "two ranges -> 7 window days" "WINDOW_DAYS=7" "$OUT"
assert_eq "two ranges -> exit 0" "0" "$RC"

# --- One range page covers the whole week ---
run 2026-06-08 2026-06-14 $'2026-06-08 2026-06-14\n'
assert_contains "single 7-day range -> 0 missing" "MISSING_COUNT=0" "$OUT"

# --- Seven single-day dailies cover the week ---
run 2026-06-08 2026-06-14 $'2026-06-08\n2026-06-09\n2026-06-10\n2026-06-11\n2026-06-12\n2026-06-13\n2026-06-14\n'
assert_contains "seven single days -> 0 missing" "MISSING_COUNT=0" "$OUT"

# --- Weekend gap: 5 weekday dailies, Sat+Sun missing ---
run 2026-06-08 2026-06-14 $'2026-06-08\n2026-06-09\n2026-06-10\n2026-06-11\n2026-06-12\n'
assert_contains "weekday-only -> 2 missing" "MISSING_COUNT=2" "$OUT"
assert_contains "weekday-only -> names the missing days" "MISSING_DATES=2026-06-13 2026-06-14" "$OUT"

# --- A single mid-week gap ---
run 2026-06-08 2026-06-14 $'2026-06-08 2026-06-10\n2026-06-12 2026-06-14\n'
assert_contains "mid-week gap -> 1 missing" "MISSING_COUNT=1" "$OUT"
assert_contains "mid-week gap -> the right day" "MISSING_DATES=2026-06-11" "$OUT"

# --- Overlapping ranges + out-of-window noise are handled ---
run 2026-06-08 2026-06-14 $'2026-06-01 2026-06-10\n2026-06-09 2026-06-14\n2026-07-01 2026-07-09\n'
assert_contains "overlap + out-of-window -> 0 missing" "MISSING_COUNT=0" "$OUT"

# --- Empty input: nothing covered ---
run 2026-06-08 2026-06-14 ""
assert_contains "no ranges -> all 7 missing" "MISSING_COUNT=7" "$OUT"

# --- Blank lines and comments are ignored ---
run 2026-06-08 2026-06-14 $'# header\n\n2026-06-08 2026-06-14\n'
assert_contains "comments/blanks ignored -> 0 missing" "MISSING_COUNT=0" "$OUT"

# --- Bad input -> exit 2 ---
printf '2026-06-14 2026-06-08\n' | bash "$HELPER" --window-start 2026-06-08 --window-end 2026-06-14 >/dev/null 2>&1
assert_eq "range end before start -> exit 2" "2" "$?"
printf '' | bash "$HELPER" --window-start 2026-06-08 --window-end 2026-06-07 >/dev/null 2>&1
assert_eq "window end before start -> exit 2" "2" "$?"
printf 'not-a-date\n' | bash "$HELPER" --window-start 2026-06-08 --window-end 2026-06-14 >/dev/null 2>&1
assert_eq "malformed range -> exit 2" "2" "$?"
bash "$HELPER" --window-start 2026-06-08 >/dev/null 2>&1
assert_eq "missing --window-end -> exit 2" "2" "$?"

summary
