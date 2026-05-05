#!/usr/bin/env bash
# fetch-gh-commits.sh - fetch commits to a GitHub repo on a target date,
# optionally restricted to a path prefix.
#
# Usage: fetch-gh-commits.sh <owner/repo> <YYYY-MM-DD> [path]
#   e.g. fetch-gh-commits.sh ethereum/EIPs 2026-05-04 EIPS
#
# Use case: feeds that don't have RSS (notably the EIPs spec set, which
# is git-versioned, not a publication). Watching commits to specific
# paths captures both new specs and material edits in one query.
#
# Output: JSON array on stdout of `[{sha, message, author, date, url}]`,
# one entry per commit whose author date falls on the target date (UTC).
# `message` is truncated to the first line (subject) so the digest can
# summarize cheaply. Empty array `[]` if no matches. Errors go to stderr.

set -euo pipefail

REPO="${1:?usage: fetch-gh-commits.sh <owner/repo> <YYYY-MM-DD> [path]}"
TARGET_DATE="${2:?usage: fetch-gh-commits.sh <owner/repo> <YYYY-MM-DD> [path]}"
PATH_FILTER="${3:-}"

since="${TARGET_DATE}T00:00:00Z"
until="${TARGET_DATE}T23:59:59Z"

_args=(-X GET "repos/$REPO/commits" -f "since=$since" -f "until=$until" -f "per_page=100")
if [ -n "$PATH_FILTER" ]; then
  _args+=(-f "path=$PATH_FILTER")
fi

_py=$(mktemp /tmp/fetch-gh-commits-XXXXXX.py)
trap 'rm -f "$_py"' EXIT
cat > "$_py" <<'PY'
import json, sys

raw = sys.stdin.read().strip()
if not raw:
    print("[]")
    sys.exit(0)

try:
    data = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"WARN: gh api commits returned non-JSON: {e}", file=sys.stderr)
    print("[]")
    sys.exit(0)

if not isinstance(data, list):
    print("[]")
    sys.exit(0)

out = []
for c in data:
    msg = (c.get("commit", {}).get("message") or "").split("\n", 1)[0].strip()
    out.append({
        "sha": (c.get("sha") or "")[:7],
        "message": msg[:200],
        "author": (c.get("commit", {}).get("author", {}).get("name") or "?"),
        "date": (c.get("commit", {}).get("author", {}).get("date") or "")[:10],
        "url": c.get("html_url") or "",
    })

print(json.dumps(out, ensure_ascii=False, indent=2))
PY

gh api --paginate "${_args[@]}" | python3 "$_py"
