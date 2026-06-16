#!/usr/bin/env bash
# team-weekly-guarded.sh - guard wrapper for team-weekly-run.sh
#
# Runs team-weekly-run.sh only if a daily digest ran successfully in the
# past 7 days. Prevents empty weekly synthesis when daily digests have been
# failing or were not scheduled on some days.
#
# All arguments are forwarded to team-weekly-run.sh unchanged.

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

DIGEST_LOG="${TEAM_DIGEST_LOG:-$HOME/.local/log/team-digest.log}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$DIGEST_LOG" ]; then
  echo "[weekly-guard] Daily digest log not found ($DIGEST_LOG). Skipping weekly synthesis."
  exit 0
fi

# Check each of the past 7 days for a [gate] PASS in the daily log.
# The log has "=== YYYY-MM-DD HH:MM:SS ===" section headers; awk extracts
# the section for each date and checks for a PASS line within it.
found=0
for i in 1 2 3 4 5 6 7; do
  d=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "$i days ago" +%Y-%m-%d 2>/dev/null || true)
  [ -z "$d" ] && continue
  if awk -v d="$d" \
    '$0 ~ ("=== " d) { in_s=1; next }
     /^=== / && in_s    { exit }
     in_s && /\[gate\] PASS/ { found=1; exit }
     END { exit !found }' "$DIGEST_LOG" 2>/dev/null; then
    echo "[weekly-guard] Found successful daily digest for $d. Proceeding with weekly synthesis."
    found=1
    break
  fi
done

if [ "$found" -eq 0 ]; then
  echo "[weekly-guard] No successful daily digest found in the past 7 days. Skipping weekly synthesis."
  exit 0
fi

exec "$SCRIPT_DIR/team-weekly-run.sh" "$@"
