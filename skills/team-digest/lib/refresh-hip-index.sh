#!/usr/bin/env bash
# refresh-hip-index.sh - refresh the known-HIPs index used to filter false-positive
# HIP regex matches in extract-hip-refs.sh.
#
# Usage: refresh-hip-index.sh
#
# Idempotent: if ~/.config/team-digest/hip-numbers.txt exists and was modified
# within the last 7 days, exits 0 silently. Otherwise calls the GitHub API
# to list files in HIP/ of hiero-ledger/hiero-improvement-proposals and
# rewrites the index file.
#
# On API failure: if the index file already exists, prints a one-line warning
# to stderr and exits 0 (use the stale file). If no file exists, exits non-zero.

set -euo pipefail

INDEX_FILE="$HOME/.config/team-digest/hip-numbers.txt"
INDEX_DIR="$(dirname "$INDEX_FILE")"
MAX_AGE_DAYS=7

# Check existing file freshness.
if [ -f "$INDEX_FILE" ]; then
  # macOS-compatible mtime check using stat -f; fall back to find -mtime on linux.
  if stat -f '%m' "$INDEX_FILE" > /dev/null 2>&1; then
    mtime=$(stat -f '%m' "$INDEX_FILE")
    now=$(date +%s)
    age_days=$(( (now - mtime) / 86400 ))
  else
    # Linux fallback
    age_days=$(find "$INDEX_FILE" -mtime +"$MAX_AGE_DAYS" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$age_days" = "0" ]; then age_days=0; else age_days=$((MAX_AGE_DAYS + 1)); fi
  fi
  if [ "$age_days" -lt "$MAX_AGE_DAYS" ]; then
    exit 0
  fi
fi

mkdir -p "$INDEX_DIR"

# Fetch all files in HIP/ via the contents API. Paginate to handle 100+ HIPs.
if ! json=$(gh api repos/hiero-ledger/hiero-improvement-proposals/contents/HIP --paginate 2>/dev/null); then
  if [ -f "$INDEX_FILE" ]; then
    echo "WARN: refresh-hip-index.sh failed to fetch updated HIP list; using stale index." >&2
    exit 0
  else
    echo "ERROR: refresh-hip-index.sh failed and no existing index file at $INDEX_FILE." >&2
    exit 1
  fi
fi

# Extract HIP numbers from filenames matching hip-N.md.
echo "$json" | python3 -c '
import json, sys, re
data = json.load(sys.stdin)
nums = set()
for entry in data:
    if entry.get("type") != "file":
        continue
    name = entry.get("name", "")
    m = re.match(r"^hip-(\d{1,4})\.md$", name, re.IGNORECASE)
    if m:
        nums.add(int(m.group(1)))
for n in sorted(nums):
    print(n)
' > "$INDEX_FILE"

count=$(wc -l < "$INDEX_FILE" | tr -d ' ')
echo "Refreshed HIP index: $count HIPs known."
