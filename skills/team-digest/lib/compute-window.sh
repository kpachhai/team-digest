#!/usr/bin/env bash
# compute-window.sh - resolve a date argument to digest window timestamps.
#
# Usage:
#   compute-window.sh             # use yesterday in UTC
#   compute-window.sh 2026-05-04  # use the specified date
#
# Output (stdout, KEY=VALUE lines suitable for `eval`):
#   DATE_LABEL=2026-05-04
#   START=2026-05-04T00:00:00Z
#   END=2026-05-04T23:59:59Z
#
# Exit non-zero on invalid input. Errors go to stderr.

set -euo pipefail

DATE_ARG="${1:-}"

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

echo "DATE_LABEL=$DATE_LABEL"
echo "START=${DATE_LABEL}T00:00:00Z"
echo "END=${DATE_LABEL}T23:59:59Z"
