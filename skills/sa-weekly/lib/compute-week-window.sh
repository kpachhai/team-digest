#!/usr/bin/env bash
# compute-week-window.sh - resolve a date arg to the ISO week (Mon-Sun) timestamps.
#
# Usage:
#   compute-week-window.sh             # the last full week (previous Mon-Sun in UTC)
#   compute-week-window.sh 2026-05-04  # the ISO week containing this date
#
# Output (stdout, KEY=VALUE lines suitable for `eval`):
#   WEEK_START=2026-05-04         # Monday of the week (date)
#   WEEK_END=2026-05-10           # Sunday of the week (date)
#   WEEK_LABEL=2026-W19           # ISO 8601 week label (year-Wxx)
#   START=2026-05-04T00:00:00Z    # ISO timestamp for the start of Monday UTC
#   END=2026-05-10T23:59:59Z      # ISO timestamp for the end of Sunday UTC
#
# Errors go to stderr; exits 1 on bad input.

set -euo pipefail

DATE_ARG="${1:-}"

python3 - "$DATE_ARG" <<'PY'
import sys
from datetime import datetime, timedelta, timezone

arg = sys.argv[1] if len(sys.argv) > 1 else ""

if arg:
    try:
        ref = datetime.strptime(arg, "%Y-%m-%d").date()
    except ValueError:
        print(f"ERROR: invalid date '{arg}'. Use YYYY-MM-DD.", file=sys.stderr)
        sys.exit(1)
else:
    # Default: pick a reference date that lives inside the LAST full ISO week
    # (Monday-Sunday). If today is Monday, the last full week ended yesterday.
    today_utc = datetime.now(timezone.utc).date()
    # Days back to the most recent Sunday: weekday() is Mon=0..Sun=6
    days_since_sunday = (today_utc.weekday() + 1) % 7 or 7
    ref = today_utc - timedelta(days=days_since_sunday)

# Snap ref to its ISO week (Mon-Sun)
weekday = ref.weekday()  # Mon=0..Sun=6
monday = ref - timedelta(days=weekday)
sunday = monday + timedelta(days=6)
iso_year, iso_week, _ = monday.isocalendar()

print(f"WEEK_START={monday.isoformat()}")
print(f"WEEK_END={sunday.isoformat()}")
print(f"WEEK_LABEL={iso_year}-W{iso_week:02d}")
print(f"START={monday.isoformat()}T00:00:00Z")
print(f"END={sunday.isoformat()}T23:59:59Z")
PY
