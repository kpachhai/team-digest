#!/usr/bin/env bash
# compute-window.sh - resolve a digest window (single day or range) to timestamps.
#
# Forms:
#   compute-window.sh                          # yesterday (UTC), single day
#   compute-window.sh 2026-06-09               # that single day
#   compute-window.sh 2026-06-08..2026-06-14   # inclusive range
#   compute-window.sh --from 2026-06-08 --to 2026-06-14   # inclusive range (weekly parity)
#   compute-window.sh --days 3                 # last 3 days, ending yesterday
#
# Output (stdout, KEY=VALUE for `eval`):
#   WINDOW_START=2026-06-08
#   WINDOW_END=2026-06-14
#   WINDOW_LABEL=2026-06-08..2026-06-14   # bare date when single day
#   IS_RANGE=1                            # 0 when single day
#   START=2026-06-08T00:00:00Z
#   END=2026-06-14T23:59:59Z
#   DATE_LABEL=2026-06-08                 # alias == WINDOW_START (single-day back-compat)
#
# All multi-day behavior is explicit per-run; there is no hidden backfill.
# Exit non-zero on invalid input. Errors to stderr.
set -euo pipefail

FROM=""; TO=""; DAYS=""; DATE_ARG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --from) FROM="${2:?--from requires YYYY-MM-DD}"; shift 2 ;;
    --to)   TO="${2:?--to requires YYYY-MM-DD}"; shift 2 ;;
    --days) DAYS="${2:?--days requires N}"; shift 2 ;;
    *)
      if [ -z "$DATE_ARG" ]; then DATE_ARG="$1"; shift
      else echo "ERROR: unexpected arg '$1'" >&2; exit 1; fi
      ;;
  esac
done

python3 - "$FROM" "$TO" "$DAYS" "$DATE_ARG" <<'PY'
import sys, re
from datetime import datetime, timedelta, timezone

frm, to, days, single = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def parse(s, label):
    # Strict format (reject single-digit / no-dash) AND calendar validity.
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", s):
        sys.exit(f"ERROR: invalid {label} '{s}'. Use YYYY-MM-DD.")
    try:
        return datetime.strptime(s, "%Y-%m-%d").date()
    except ValueError:
        sys.exit(f"ERROR: invalid {label} '{s}'. Use YYYY-MM-DD.")

modes = sum(bool(x) for x in [(frm or to), days, single])
if modes > 1:
    sys.exit("ERROR: choose ONE of: positional date | A..B | --from/--to | --days N")
if (frm and not to) or (to and not frm):
    sys.exit("ERROR: --from and --to must be used together")

today = datetime.now(timezone.utc).date()

if frm and to:
    start, end = parse(frm, "--from"), parse(to, "--to")
elif days:
    if not re.fullmatch(r"[0-9]+", days) or int(days) < 1:
        sys.exit(f"ERROR: --days must be a positive integer; got '{days}'")
    end = today - timedelta(days=1)
    start = end - timedelta(days=int(days) - 1)
elif single:
    if ".." in single:
        a, _, b = single.partition("..")
        start, end = parse(a, "range start"), parse(b, "range end")
    else:
        start = end = parse(single, "date")
else:
    start = end = today - timedelta(days=1)

if end < start:
    sys.exit(f"ERROR: window end ({end}) is before start ({start})")

is_range = 1 if end != start else 0
label = f"{start.isoformat()}..{end.isoformat()}" if is_range else start.isoformat()

print(f"WINDOW_START={start.isoformat()}")
print(f"WINDOW_END={end.isoformat()}")
print(f"WINDOW_LABEL={label}")
print(f"IS_RANGE={is_range}")
print(f"START={start.isoformat()}T00:00:00Z")
print(f"END={end.isoformat()}T23:59:59Z")
print(f"DATE_LABEL={start.isoformat()}")
PY
