#!/usr/bin/env bash
# fetch-github-prs.sh - fetch PRs updated in the date window for an org.
#
# Usage: fetch-github-prs.sh <org> <start-iso> <end-iso>
#   e.g. fetch-github-prs.sh your-org 2026-05-04T00:00:00Z 2026-05-04T23:59:59Z
#
# Output: human-readable summary on stdout, grouped by repo. Each PR line
# includes state, number, title, author handle, html_url, and a 200-char
# description excerpt. The skill consumes this output as plain text.

set -euo pipefail

ORG="${1:?usage: fetch-github-prs.sh <org> <start-iso> <end-iso>}"
START="${2:?usage: fetch-github-prs.sh <org> <start-iso> <end-iso>}"
END="${3:?usage: fetch-github-prs.sh <org> <start-iso> <end-iso>}"

_py=$(mktemp /tmp/gh-prs-XXXXXX.py)
trap 'rm -f "$_py"' EXIT
cat > "$_py" <<'PY'
import json, sys

data = json.load(sys.stdin)
if not data:
    print('(no PRs updated in window)')
    sys.exit(0)

if len(data) >= 100:
    print('WARNING: gh search returned 100 results (the --limit cap). Some PRs may be missing - consider narrowing the org or date.', file=sys.stderr)

repos = {}
for pr in data:
    repos.setdefault(pr['repository']['name'], []).append(pr)

for repo in sorted(repos):
    prs = repos[repo]
    print(f'## {repo} ({len(prs)} PRs)')
    for pr in prs:
        body = (pr.get('body') or '')[:200].replace('\n', ' ').strip()
        author = (pr.get('author') or {}).get('login', '?')
        state = pr.get('state', '?').upper()
        print(f'  [{state}] #{pr["number"]} {pr["title"]}')
        print(f'    Author: @{author}')
        print(f'    URL: {pr["url"]}')
        if body:
            print(f'    Description: {body}')
        print()
PY

gh search prs \
  --owner="$ORG" \
  --updated="${START}..${END}" \
  --json repository,title,state,author,number,body,url,labels \
  --limit 100 \
  | python3 "$_py"
