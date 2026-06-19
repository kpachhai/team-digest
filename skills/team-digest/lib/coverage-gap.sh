#!/usr/bin/env bash
# coverage-gap.sh - given a date window and a set of covered ranges, report
# which days in the window are NOT covered by any range.
#
# This is the deterministic core of the weekly/monthly coverage gate: the
# skills query Notion for the digest pages overlapping a window, then pipe each
# page's date range here to learn whether every day is accounted for. A single
# multi-day (range) page legitimately covers all of its days, so 2 pages can
# cover a 7-day week.
#
# Usage:
#   coverage-gap.sh --window-start YYYY-MM-DD --window-end YYYY-MM-DD < ranges
#
# stdin: one covered range per line, "START [END]" (whitespace-separated).
#   - END omitted -> single day (END = START), e.g. a single-day daily digest.
#   - Blank lines and lines beginning with '#' are ignored.
#   - Dates outside the window are fine; they're clamped.
#
# Output (stdout, KEY=VALUE for `eval`):
#   WINDOW_DAYS=7
#   COVERED_DAYS=5
#   MISSING_COUNT=2
#   MISSING_DATES=2026-06-13 2026-06-14   # space-separated, chronological; empty if none
#
# Exit status: 0 on valid input (whether or not gaps exist - gaps are a normal
# result, not an error). 2 on bad arguments or malformed input.
set -euo pipefail

WINDOW_START=""
WINDOW_END=""
while [ $# -gt 0 ]; do
  case "$1" in
    --window-start) WINDOW_START="${2:-}"; shift 2 ;;
    --window-end)   WINDOW_END="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "ERROR: unexpected arg '$1'" >&2; exit 2 ;;
  esac
done

if [ -z "$WINDOW_START" ] || [ -z "$WINDOW_END" ]; then
  echo "ERROR: --window-start and --window-end are required (YYYY-MM-DD)." >&2
  exit 2
fi

RANGES="$(cat)"

WINDOW_START="$WINDOW_START" WINDOW_END="$WINDOW_END" RANGES="$RANGES" python3 - <<'PY'
import os, sys, re
from datetime import datetime, timedelta

def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)

def parse(s, label):
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", s or ""):
        die(f"ERROR: invalid {label} '{s}'. Use YYYY-MM-DD.")
    try:
        return datetime.strptime(s, "%Y-%m-%d").date()
    except ValueError:
        die(f"ERROR: invalid {label} '{s}'. Use YYYY-MM-DD.")

win_start = parse(os.environ["WINDOW_START"], "--window-start")
win_end = parse(os.environ["WINDOW_END"], "--window-end")
if win_end < win_start:
    die(f"ERROR: --window-end ({win_end}) is before --window-start ({win_start}).")

# Build the set of all days in the window.
window_days = set()
d = win_start
while d <= win_end:
    window_days.add(d)
    d += timedelta(days=1)

covered = set()
for raw in os.environ["RANGES"].splitlines():
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    parts = line.split()
    start = parse(parts[0], "range start")
    end = parse(parts[1], "range end") if len(parts) > 1 else start
    if end < start:
        die(f"ERROR: range end ({end}) before start ({start}).")
    # Clamp to the window and mark covered days.
    cur = max(start, win_start)
    stop = min(end, win_end)
    while cur <= stop:
        covered.add(cur)
        cur += timedelta(days=1)

missing = sorted(window_days - covered)
print(f"WINDOW_DAYS={len(window_days)}")
print(f"COVERED_DAYS={len(window_days & covered)}")
print(f"MISSING_COUNT={len(missing)}")
print("MISSING_DATES=" + " ".join(d.isoformat() for d in missing))
PY
