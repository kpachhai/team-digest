#!/usr/bin/env bash
# Unit tests for compute-month-window.sh. Pure shell; no network, no MCP.
set -uo pipefail

HELPER="$(cd "$(dirname "$0")/.." && pwd)/skills/team-monthly/lib/compute-month-window.sh"
PASS=0; FAIL=0

# check <description> <args...> ; expected single KEY=VALUE line in $EXPECT
check() {
  local desc="$1"; shift
  local got; got="$(bash "$HELPER" "$@" 2>/dev/null)"
  if echo "$got" | grep -qxF "$EXPECT"; then
    PASS=$((PASS+1)); echo "ok   - $desc"
  else
    FAIL=$((FAIL+1)); echo "FAIL - $desc"; echo "   want line: $EXPECT"; echo "   got:"; echo "$got" | sed 's/^/     /'
  fi
}

# Explicit YYYY-MM
EXPECT="MONTH_START=2026-05-01"; check "2026-05 start" 2026-05
EXPECT="MONTH_END=2026-05-31";   check "2026-05 end (31-day)" 2026-05
EXPECT="MONTH_LABEL=2026-05";    check "2026-05 label" 2026-05
EXPECT="MONTH_NAME='May 2026'";  check "2026-05 name (eval-safe quoted)" 2026-05

# Leap February
EXPECT="MONTH_END=2024-02-29";   check "leap Feb end" 2024-02
# Non-leap February
EXPECT="MONTH_END=2025-02-28";   check "non-leap Feb end" 2025-02

# Date-containing-month
EXPECT="MONTH_START=2026-05-01"; check "date in month -> month start" 2026-05-14
EXPECT="MONTH_END=2026-05-31";   check "date in month -> month end" 2026-05-14

# Custom range parity
EXPECT="MONTH_LABEL=2026-04-15_to_2026-05-20"; check "custom range label" --from 2026-04-15 --to 2026-05-20
EXPECT="MONTH_START=2026-04-15"; check "custom range start" --from 2026-04-15 --to 2026-05-20

# Weekly span (first Monday .. last Sunday inside the month)
# June 2026: Jun 1 is a Monday, Jun 30 is a Tuesday -> span 06-01..06-28
EXPECT="WEEKLY_SPAN_START=2026-06-01"; check "June weekly-span start (Jun 1 is Mon)" 2026-06
EXPECT="WEEKLY_SPAN_END=2026-06-28";   check "June weekly-span end (last Sunday)" 2026-06
EXPECT="HAS_FULL_WEEK=1";              check "June has a full week" 2026-06
# May 2026: May 1 is Fri, May 31 is Sun -> first Monday 05-04, last Sunday 05-31
EXPECT="WEEKLY_SPAN_START=2026-05-04"; check "May weekly-span start (first Mon)" 2026-05
EXPECT="WEEKLY_SPAN_END=2026-05-31";   check "May weekly-span end (May 31 is Sun)" 2026-05
# Custom range too small for any full Mon-Sun week
EXPECT="HAS_FULL_WEEK=0";              check "sub-week range has no full week" --from 2026-06-09 --to 2026-06-11
EXPECT="WEEKLY_SPAN_START=";           check "sub-week range emits empty span start" --from 2026-06-09 --to 2026-06-11

# Bad input exits non-zero
if bash "$HELPER" 2026-13 >/dev/null 2>&1; then FAIL=$((FAIL+1)); echo "FAIL - month 13 should error"; else PASS=$((PASS+1)); echo "ok   - month 13 errors"; fi
if bash "$HELPER" --from 2026-05-20 --to 2026-04-15 >/dev/null 2>&1; then FAIL=$((FAIL+1)); echo "FAIL - reversed range should error"; else PASS=$((PASS+1)); echo "ok   - reversed range errors"; fi

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
