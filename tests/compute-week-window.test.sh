#!/usr/bin/env bash
# Unit tests for skills/team-weekly/lib/compute-week-window.sh (ISO week resolver).
# Pure shell + date math; no network, no MCP.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib-assert.sh"
H="$(cd "$DIR/.." && pwd)/skills/team-weekly/lib/compute-week-window.sh"

# --- A Monday resolves to its ISO week (Mon..Sun) ---
out=$(bash "$H" 2026-05-04)
assert_contains "Monday -> WEEK_START (Mon)" "WEEK_START=2026-05-04" "$out"
assert_contains "Monday -> WEEK_END (Sun)"   "WEEK_END=2026-05-10" "$out"
assert_contains "Monday -> WEEK_LABEL"        "WEEK_LABEL=2026-W19" "$out"
assert_contains "Monday -> START ts"          "START=2026-05-04T00:00:00Z" "$out"
assert_contains "Monday -> END ts"            "END=2026-05-10T23:59:59Z" "$out"

# --- A Sunday in the same week resolves to the same Mon..Sun window ---
out=$(bash "$H" 2026-05-10)
assert_contains "Sunday -> same WEEK_START" "WEEK_START=2026-05-04" "$out"
assert_contains "Sunday -> same WEEK_END"   "WEEK_END=2026-05-10" "$out"
assert_contains "Sunday -> same label"      "WEEK_LABEL=2026-W19" "$out"

# --- A midweek date resolves to its containing week ---
out=$(bash "$H" 2026-05-07)
assert_contains "midweek -> WEEK_START (Mon)" "WEEK_START=2026-05-04" "$out"
assert_contains "midweek -> WEEK_END (Sun)"   "WEEK_END=2026-05-10" "$out"

# --- Custom range (no week snapping); label is <from>_to_<to> ---
out=$(bash "$H" --from 2026-04-25 --to 2026-05-03)
assert_contains "range -> WEEK_START = from" "WEEK_START=2026-04-25" "$out"
assert_contains "range -> WEEK_END = to"     "WEEK_END=2026-05-03" "$out"
assert_contains "range -> label"             "WEEK_LABEL=2026-04-25_to_2026-05-03" "$out"

# --- Default (no arg) = last full ISO week: shape checks ---
out=$(bash "$H")
label=$(echo "$out" | sed -n 's/^WEEK_LABEL=//p')
case "$label" in
  [0-9][0-9][0-9][0-9]-W[0-9][0-9]) pass "default -> ISO-week label shape" ;;
  *) fail "default -> ISO-week label shape" "got [$label]" ;;
esac
# WEEK_START must be a Monday and WEEK_END the following Sunday (7-day span).
ws=$(echo "$out" | sed -n 's/^WEEK_START=//p'); we=$(echo "$out" | sed -n 's/^WEEK_END=//p')
dow=$(python3 -c "import datetime,sys; print(datetime.date.fromisoformat(sys.argv[1]).weekday())" "$ws")
assert_eq "default -> WEEK_START is Monday (weekday 0)" "0" "$dow"
span=$(python3 -c "import datetime,sys; a=datetime.date.fromisoformat(sys.argv[1]); b=datetime.date.fromisoformat(sys.argv[2]); print((b-a).days)" "$ws" "$we")
assert_eq "default -> 7-day span (Mon..Sun)" "6" "$span"

# --- Error cases ---
bash "$H" 2026-13-99 >/dev/null 2>&1;                       assert_eq "invalid date errors" 1 "$?"
bash "$H" --from 2026-05-10 --to 2026-05-01 >/dev/null 2>&1; assert_eq "reversed range errors" 1 "$?"
bash "$H" 2026-05-04 --from 2026-05-01 --to 2026-05-07 >/dev/null 2>&1; assert_eq "mixing positional + range errors" 1 "$?"
bash "$H" --from 2026-05-01 >/dev/null 2>&1;                 assert_eq "--from without --to errors" 1 "$?"

summary
