#!/usr/bin/env bash
# extract-hip-refs.sh - extract HIP numbers from text on stdin.
#
# Usage: <text> | extract-hip-refs.sh
#   e.g. echo "this references HIP-1137 and HIP-1140" | extract-hip-refs.sh
#
# Output: JSON array of HIP numbers, deduplicated, sorted ascending.
# Empty array `[]` if no matches.
#
# Filtering: if the known-HIPs index file exists at
# ~/.config/team-digest/hip-numbers.txt, only numbers in the index are emitted.
# If the index file is missing, all regex matches are emitted (degraded mode).
#
# Regexes matched:
#   1. \bhip[-_ ]?(\d{1,4})\b (case-insensitive) - HIP-1137, HIP 1137, HIP_1137, hip1137
#   2. hiero-improvement-proposals/blob/[^/]+/HIP/hip-(\d{1,4})\.md - blob URL form

set -euo pipefail

INDEX_FILE="$HOME/.config/team-digest/hip-numbers.txt"

# Capture stdin into a shell variable so the python3 heredoc below can read it
# via the environment. python3 - <<'PY' consumes stdin for the script body
# itself, so sys.stdin.read() inside the heredoc would see EOF immediately.
INPUT_TEXT="$(cat)"

INPUT_TEXT="$INPUT_TEXT" python3 - "$INDEX_FILE" <<'PY'
import json, os, re, sys

index_file = sys.argv[1]

# Load the known-HIPs index if present. Empty set means "no filter."
known = set()
try:
    with open(index_file) as f:
        for line in f:
            line = line.strip()
            if line.isdigit():
                known.add(int(line))
except FileNotFoundError:
    pass

text = os.environ.get('INPUT_TEXT', '')

found = set()

# Pattern 1: HIP-N, HIP_N, HIP N, HIPN
for m in re.finditer(r'\bhip[-_ ]?(\d{1,4})\b', text, re.IGNORECASE):
    found.add(int(m.group(1)))

# Pattern 2: blob URL
for m in re.finditer(r'hiero-improvement-proposals/blob/[^/]+/HIP/hip-(\d{1,4})\.md', text, re.IGNORECASE):
    found.add(int(m.group(1)))

# Filter against known-HIPs index. If the index is empty (file missing), pass through.
if known:
    found &= known

print(json.dumps(sorted(found)))
PY
