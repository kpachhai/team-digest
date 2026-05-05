#!/usr/bin/env bash
# compute-week-window.sh - resolve a week or arbitrary date range to timestamps.
#
# Three input forms:
#   compute-week-window.sh                          # last full ISO week (Mon-Sun)
#   compute-week-window.sh 2026-05-04               # the ISO week containing this date
#   compute-week-window.sh --from F --to T          # arbitrary date range (inclusive)
#
# The --from/--to form supports any window - useful for catching up after a
# missed week, post-conference recaps, sprint summaries, or future monthly /
# quarterly rollups built on this same skill.
#
# Output (stdout, KEY=VALUE for `eval`):
#   WEEK_START=2026-05-04         # date (inclusive)
#   WEEK_END=2026-05-10           # date (inclusive)
#   WEEK_LABEL=2026-W19           # ISO week label, OR "2026-04-25_to_2026-05-03" for custom ranges
#   START=2026-05-04T00:00:00Z    # ISO timestamp for start of WEEK_START UTC
#   END=2026-05-10T23:59:59Z      # ISO timestamp for end of WEEK_END UTC
#
# Errors go to stderr; exits 1 on bad input.

set -euo pipefail

FROM=""
TO=""
DATE_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --from)
      FROM="${2:-}"
      if [ -z "$FROM" ]; then echo "ERROR: --from requires a YYYY-MM-DD value" >&2; exit 1; fi
      shift 2
      ;;
    --to)
      TO="${2:-}"
      if [ -z "$TO" ]; then echo "ERROR: --to requires a YYYY-MM-DD value" >&2; exit 1; fi
      shift 2
      ;;
    *)
      DATE_ARG="$1"
      shift
      ;;
  esac
done

if [ -n "$FROM" ] && [ -z "$TO" ]; then
  echo "ERROR: --from requires --to" >&2; exit 1
fi
if [ -z "$FROM" ] && [ -n "$TO" ]; then
  echo "ERROR: --to requires --from" >&2; exit 1
fi
if { [ -n "$FROM" ] || [ -n "$TO" ]; } && [ -n "$DATE_ARG" ]; then
  echo "ERROR: cannot mix --from/--to with a positional date arg" >&2; exit 1
fi

python3 - "$FROM" "$TO" "$DATE_ARG" <<'PY'
import sys
from datetime import datetime, timedelta, timezone

frm, to, single = sys.argv[1], sys.argv[2], sys.argv[3]

def parse(s, label):
    try:
        return datetime.strptime(s, "%Y-%m-%d").date()
    except ValueError:
        print(f"ERROR: invalid {label} '{s}'. Use YYYY-MM-DD.", file=sys.stderr)
        sys.exit(1)

if frm and to:
    # Explicit range - take it as given, no week-snapping
    start = parse(frm, "--from")
    end = parse(to, "--to")
    if end < start:
        print(f"ERROR: --to ({end}) is before --from ({start})", file=sys.stderr)
        sys.exit(1)
    week_label = f"{start.isoformat()}_to_{end.isoformat()}"
elif single:
    # Single date - snap to its ISO week (Mon-Sun)
    ref = parse(single, "date")
    weekday = ref.weekday()  # Mon=0..Sun=6
    start = ref - timedelta(days=weekday)
    end = start + timedelta(days=6)
    iso_year, iso_week, _ = start.isocalendar()
    week_label = f"{iso_year}-W{iso_week:02d}"
else:
    # Default - last full ISO week ending the most recent Sunday
    today_utc = datetime.now(timezone.utc).date()
    days_since_sunday = (today_utc.weekday() + 1) % 7 or 7
    last_sunday = today_utc - timedelta(days=days_since_sunday)
    start = last_sunday - timedelta(days=last_sunday.weekday())
    end = start + timedelta(days=6)
    iso_year, iso_week, _ = start.isocalendar()
    week_label = f"{iso_year}-W{iso_week:02d}"

print(f"WEEK_START={start.isoformat()}")
print(f"WEEK_END={end.isoformat()}")
print(f"WEEK_LABEL={week_label}")
print(f"START={start.isoformat()}T00:00:00Z")
print(f"END={end.isoformat()}T23:59:59Z")
PY
