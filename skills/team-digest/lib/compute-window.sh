#!/usr/bin/env bash
# compute-window.sh - resolve a date argument to digest window timestamps.
#
# Usage:
#   compute-window.sh                              # use yesterday in UTC
#   compute-window.sh 2026-05-04                   # use the specified date
#   compute-window.sh 2026-05-04 --lookback-days 7 # also emit a wider window start
#
# Output (stdout, KEY=VALUE lines suitable for `eval`):
#   DATE_LABEL=2026-05-04
#   START=2026-05-04T00:00:00Z
#   END=2026-05-04T23:59:59Z
#   LOOKBACK_START=2026-05-04T00:00:00Z   # == START when --lookback-days is 0 or omitted
#   LOOKBACK_DAYS=0                        # echo of N so callers can render it
#
# Exit non-zero on invalid input. Errors go to stderr.
#
# LOOKBACK_START is the wider-window start for the GitHub PR/issue scan.
# When --lookback-days N > 0, LOOKBACK_START =
# (DATE_LABEL - N days) T00:00:00Z so `fetch-github-prs.sh org $LOOKBACK_START $END`
# surfaces PRs merged earlier in the week. Default N=0 preserves daily-cron
# behavior; daily-only digests pass $START. Backfill / weekly-catchup runs
# pass $LOOKBACK_START.

set -euo pipefail

DATE_ARG=""
LOOKBACK_DAYS=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --lookback-days)
      LOOKBACK_DAYS="${2:?--lookback-days requires N}"
      shift 2
      ;;
    *)
      if [ -z "$DATE_ARG" ]; then
        DATE_ARG="$1"
        shift
      else
        echo "ERROR: unexpected arg '$1'" >&2
        exit 1
      fi
      ;;
  esac
done

if [ -n "$DATE_ARG" ]; then
  if ! echo "$DATE_ARG" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    echo "ERROR: invalid date format '$DATE_ARG'. Use YYYY-MM-DD." >&2
    exit 1
  fi
  DATE_LABEL="$DATE_ARG"
else
  # macOS uses BSD date (-v); Linux uses GNU date (-d).
  DATE_LABEL=$(date -u -v-1d +%Y-%m-%d 2>/dev/null || date -u -d 'yesterday' +%Y-%m-%d)
fi

if ! echo "$LOOKBACK_DAYS" | grep -qE '^[0-9]+$'; then
  echo "ERROR: --lookback-days must be a non-negative integer; got '$LOOKBACK_DAYS'" >&2
  exit 1
fi

if [ "$LOOKBACK_DAYS" -gt 0 ]; then
  # macOS BSD date (-v) / Linux GNU date (-d) fallback.
  LOOKBACK_DATE=$(date -u -j -v-${LOOKBACK_DAYS}d -f "%Y-%m-%d" "$DATE_LABEL" "+%Y-%m-%d" 2>/dev/null \
    || date -u -d "$DATE_LABEL - $LOOKBACK_DAYS days" +%Y-%m-%d)
else
  LOOKBACK_DATE="$DATE_LABEL"
fi

echo "DATE_LABEL=$DATE_LABEL"
echo "START=${DATE_LABEL}T00:00:00Z"
echo "END=${DATE_LABEL}T23:59:59Z"
echo "LOOKBACK_START=${LOOKBACK_DATE}T00:00:00Z"
echo "LOOKBACK_DAYS=$LOOKBACK_DAYS"
