#!/usr/bin/env bash
# fetch-github-issues.sh - fetch issues updated in the date window for an org.
#
# Usage: fetch-github-issues.sh <org> <start-iso> <end-iso>
#   e.g. fetch-github-issues.sh your-org 2026-05-04T00:00:00Z 2026-05-04T23:59:59Z
#
# Output: human-readable summary on stdout, grouped by repo. Each issue
# line includes state, number, title, author handle, html_url, and a
# 200-char description excerpt.

set -euo pipefail

ORG="${1:?usage: fetch-github-issues.sh <org> <start-iso> <end-iso>}"
START="${2:?usage: fetch-github-issues.sh <org> <start-iso> <end-iso>}"
END="${3:?usage: fetch-github-issues.sh <org> <start-iso> <end-iso>}"

_py=$(mktemp /tmp/gh-issues-XXXXXX.py)
trap 'rm -f "$_py"' EXIT
cat > "$_py" <<'PY'
import json, sys

data = json.load(sys.stdin)
if not data:
    print('(no issues updated in window)')
    sys.exit(0)

if len(data) >= 100:
    print('WARNING: gh search returned 100 results (the --limit cap). Some issues may be missing - consider narrowing the org or date.', file=sys.stderr)

repos = {}
for issue in data:
    repos.setdefault(issue['repository']['name'], []).append(issue)

for repo in sorted(repos):
    issues = repos[repo]
    print(f'## {repo} ({len(issues)} issues)')
    for issue in issues:
        body = (issue.get('body') or '')[:200].replace('\n', ' ').strip()
        author = (issue.get('author') or {}).get('login', '?')
        state = issue.get('state', '?').upper()
        print(f'  [{state}] #{issue["number"]} {issue["title"]}')
        print(f'    Author: @{author}')
        print(f'    URL: {issue["url"]}')
        if body:
            print(f'    Description: {body}')
        print()
PY

gh search issues \
  --owner="$ORG" \
  --updated="${START}..${END}" \
  --json repository,title,state,author,number,body,url,labels \
  --limit 100 \
  | python3 "$_py"
