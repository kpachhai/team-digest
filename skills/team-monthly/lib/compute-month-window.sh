#!/usr/bin/env bash
# compute-month-window.sh - resolve a calendar month (or arbitrary range) to timestamps.
#
# Input forms:
#   compute-month-window.sh                  # last full calendar month
#   compute-month-window.sh 2026-05          # that calendar month
#   compute-month-window.sh 2026-05-14       # the calendar month containing this date
#   compute-month-window.sh --from F --to T  # arbitrary range (inclusive) - parity with weekly
#
# Output (stdout, KEY=VALUE for `eval`):
#   MONTH_START=2026-05-01
#   MONTH_END=2026-05-31
#   MONTH_LABEL=2026-05            # custom range: <from>_to_<to>
#   MONTH_NAME=May 2026            # human label for prose/title (custom range: "<from> to <to>")
#   START=2026-05-01T00:00:00Z
#   END=2026-05-31T23:59:59Z
#   WEEKLY_SPAN_START=2026-05-04   # first Monday on/after MONTH_START
#   WEEKLY_SPAN_END=2026-05-31     # last Sunday on/before MONTH_END
#   HAS_FULL_WEEK=1                # 1 if a full Mon-Sun week fits inside the window, else 0
#
# WEEKLY_SPAN_* bound the in-month full weeks the monthly coverage gate expects a
# Weekly digest for; boundary days outside the span are covered by dailies. When
# HAS_FULL_WEEK=0 the span keys are emitted empty (no full week in the window).
#
# Both dailies and weeklies are later queried with date in [MONTH_START, MONTH_END].
# Errors to stderr; exits 1 on bad input.
set -euo pipefail

FROM=""; TO=""; ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM="${2:-}"; [ -z "$FROM" ] && { echo "ERROR: --from requires YYYY-MM-DD" >&2; exit 1; }; shift 2 ;;
    --to)   TO="${2:-}";   [ -z "$TO" ]   && { echo "ERROR: --to requires YYYY-MM-DD" >&2; exit 1; }; shift 2 ;;
    *) ARG="$1"; shift ;;
  esac
done
if [ -n "$FROM" ] && [ -z "$TO" ]; then echo "ERROR: --from requires --to" >&2; exit 1; fi
if [ -z "$FROM" ] && [ -n "$TO" ]; then echo "ERROR: --to requires --from" >&2; exit 1; fi
if { [ -n "$FROM" ] || [ -n "$TO" ]; } && [ -n "$ARG" ]; then echo "ERROR: cannot mix --from/--to with a positional arg" >&2; exit 1; fi

python3 - "$FROM" "$TO" "$ARG" <<'PY'
import sys, calendar
from datetime import date, datetime, timedelta, timezone

frm, to, arg = sys.argv[1], sys.argv[2], sys.argv[3]

def parse_ymd(s, label):
    try:
        return datetime.strptime(s, "%Y-%m-%d").date()
    except ValueError:
        print(f"ERROR: invalid {label} '{s}'. Use YYYY-MM-DD.", file=sys.stderr); sys.exit(1)

def month_bounds(y, m):
    start = date(y, m, 1)
    end = date(y, m, calendar.monthrange(y, m)[1])
    return start, end

if frm and to:
    start = parse_ymd(frm, "--from"); end = parse_ymd(to, "--to")
    if end < start:
        print(f"ERROR: --to ({end}) is before --from ({start})", file=sys.stderr); sys.exit(1)
    label = f"{start.isoformat()}_to_{end.isoformat()}"
    name = f"{start.isoformat()} to {end.isoformat()}"
elif arg:
    # Accept YYYY-MM or YYYY-MM-DD
    try:
        if len(arg) == 7:
            y, m = int(arg[:4]), int(arg[5:7])
            if arg[4] != "-" or not (1 <= m <= 12):
                raise ValueError
        else:
            d = parse_ymd(arg, "date"); y, m = d.year, d.month
    except ValueError:
        print(f"ERROR: invalid month/date '{arg}'. Use YYYY-MM or YYYY-MM-DD.", file=sys.stderr); sys.exit(1)
    start, end = month_bounds(y, m)
    label = f"{y:04d}-{m:02d}"
    name = f"{calendar.month_name[m]} {y}"
else:
    today = datetime.now(timezone.utc).date()
    first_this = today.replace(day=1)
    last_prev = first_this - timedelta(days=1)
    start, end = month_bounds(last_prev.year, last_prev.month)
    label = f"{last_prev.year:04d}-{last_prev.month:02d}"
    name = f"{calendar.month_name[last_prev.month]} {last_prev.year}"

# Weekly span: first Monday on/after start, last Sunday on/before end. These
# bound the full Mon-Sun weeks contained in the window; the monthly coverage
# gate requires a Weekly digest for this span and leaves the boundary days
# (before the first Monday / after the last Sunday) to daily coverage.
days_to_monday = (7 - start.weekday()) % 7  # Mon=0
first_monday = start + timedelta(days=days_to_monday)
last_sunday = end - timedelta(days=(end.weekday() + 1) % 7)  # Sun=6 -> 0 back
has_full_week = first_monday <= last_sunday

print(f"MONTH_START={start.isoformat()}")
print(f"MONTH_END={end.isoformat()}")
print(f"MONTH_LABEL={label}")
# MONTH_NAME contains a space ("May 2026"), so single-quote it for `eval` safety.
print(f"MONTH_NAME='{name}'")
print(f"START={start.isoformat()}T00:00:00Z")
print(f"END={end.isoformat()}T23:59:59Z")
print(f"WEEKLY_SPAN_START={first_monday.isoformat() if has_full_week else ''}")
print(f"WEEKLY_SPAN_END={last_sunday.isoformat() if has_full_week else ''}")
print(f"HAS_FULL_WEEK={'1' if has_full_week else '0'}")
PY
