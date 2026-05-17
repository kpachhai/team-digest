#!/usr/bin/env bash
# fetch-github-issues.sh - fetch issues updated in the date window for an org.
#
# Usage: fetch-github-issues.sh <org> <start-iso> <end-iso>
#   e.g. fetch-github-issues.sh your-org 2026-05-04T00:00:00Z 2026-05-04T23:59:59Z
#
# Output: human-readable summary on stdout, grouped by repo. Each issue
# line includes state, number, title, author handle, html_url, and a
# 150-char description excerpt (markdown links/images/comments stripped
# before truncation).

set -euo pipefail

ORG="${1:?usage: fetch-github-issues.sh <org> <start-iso> <end-iso>}"
START="${2:?usage: fetch-github-issues.sh <org> <start-iso> <end-iso>}"
END="${3:?usage: fetch-github-issues.sh <org> <start-iso> <end-iso>}"

_py=$(mktemp /tmp/gh-issues-XXXXXX.py)
trap 'rm -f "$_py"' EXIT
cat > "$_py" <<'PY'
import json, os, re, subprocess, sys

data = json.load(sys.stdin)
if not data:
    print('(no issues updated in window)')
    sys.exit(0)

if len(data) >= 100:
    print('WARNING: gh search returned 100 results (the --limit cap). Some issues may be missing - consider narrowing the org or date.', file=sys.stderr)

# Mechanism A: HIP cross-reference annotation, gated on TEAM_DIGEST_HIP_ENABLED.
hip_enabled = os.environ.get('TEAM_DIGEST_HIP_ENABLED', '1') == '1'
extract_helper = os.path.expanduser('~/.claude/skills/team-digest/lib/extract-hip-refs.sh')
hip_helper_available = hip_enabled and os.path.exists(extract_helper)

def extract_hips(text):
    """Pipe text through extract-hip-refs.sh, return list of HIP numbers."""
    if not hip_helper_available or not text:
        return []
    try:
        result = subprocess.run(
            ['bash', extract_helper],
            input=text, capture_output=True, text=True, timeout=5,
        )
        if result.returncode != 0:
            return []
        return json.loads(result.stdout.strip() or '[]')
    except Exception:
        return []

repos = {}
for issue in data:
    repos.setdefault(issue['repository']['name'], []).append(issue)

for repo in sorted(repos):
    issues = repos[repo]
    print(f'## {repo} ({len(issues)} issues)')
    for issue in issues:
        raw_body = issue.get('body') or ''
        # Strip markdown noise before truncating so the 150-char excerpt
        # carries information density, not formatting.
        body = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', raw_body)     # [text](url) -> text
        body = re.sub(r'!\[[^\]]*\]\([^)]+\)', '', body)             # ![alt](url) -> (drop)
        body = re.sub(r'<!--.*?-->', '', body, flags=re.DOTALL)      # HTML comments -> (drop)
        body = body[:150].replace('\n', ' ').strip()
        author = (issue.get('author') or {}).get('login', '?')
        state = issue.get('state', '?').upper()
        title = issue['title']
        print(f'  [{state}] #{issue["number"]} {title}')
        print(f'    Author: @{author}')
        print(f'    URL: {issue["url"]}')
        if body:
            print(f'    Description: {body}')
        hips = extract_hips(f'{title}\n{raw_body}')
        if hips:
            hip_list = ', '.join(f'HIP-{n}' for n in hips)
            print(f'    Linked HIPs: {hip_list}')
        print()
PY

gh search issues \
  --owner="$ORG" \
  --updated="${START}..${END}" \
  --json repository,title,state,author,number,body,url,labels \
  --limit 100 \
  | python3 "$_py"
