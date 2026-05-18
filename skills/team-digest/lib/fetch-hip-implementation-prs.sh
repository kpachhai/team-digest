#!/usr/bin/env bash
# fetch-hip-implementation-prs.sh - for one HIP on one date, search for PRs and
# commits in configured orgs that reference the HIP.
#
# Usage: fetch-hip-implementation-prs.sh <hip-number> <YYYY-MM-DD> [comma-separated-orgs]
#   e.g. fetch-hip-implementation-prs.sh 1137 2026-05-06 hiero-ledger
#
# Output: JSON object { hip, prs: [...], commits: [...] }.

set -euo pipefail

HIP_NUMBER="${1:?usage: fetch-hip-implementation-prs.sh <hip-number> <YYYY-MM-DD> [orgs] [--since-iso ISO]}"
TARGET_DATE="${2:?usage: fetch-hip-implementation-prs.sh <hip-number> <YYYY-MM-DD> [orgs] [--since-iso ISO]}"
shift 2
ORGS_RAW="hiero-ledger"
SINCE_OVERRIDE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --since-iso)
      SINCE_OVERRIDE="${2:?--since-iso requires an ISO 8601 timestamp}"
      shift 2
      ;;
    *)
      ORGS_RAW="$1"
      shift
      ;;
  esac
done

# F4 (iteration 4): SINCE can be overridden to widen the per-HIP search window
# beyond the digest day. Default = digest day start.
SINCE="${SINCE_OVERRIDE:-${TARGET_DATE}T00:00:00Z}"
UNTIL="${TARGET_DATE}T23:59:59Z"

IFS=',' read -ra ORGS <<< "$ORGS_RAW"

PRS_ALL='[]'
COMMITS_ALL='[]'

for ORG in "${ORGS[@]}"; do
  ORG=$(echo "$ORG" | tr -d ' ')
  PR_PAGE=$(gh search prs "HIP-$HIP_NUMBER" "org:$ORG" --updated="$SINCE..$UNTIL" \
    --json repository,number,title,state,author,url,body --limit 20 2>/dev/null || echo '[]')
  COMMIT_PAGE=$(gh search commits "HIP-$HIP_NUMBER" "org:$ORG" \
    --committer-date="$SINCE..$UNTIL" \
    --json repository,sha,commit,url --limit 20 2>/dev/null || echo '[]')
  PRS_ALL=$(jq -s '.[0] + .[1]' <(echo "$PRS_ALL") <(echo "$PR_PAGE"))
  COMMITS_ALL=$(jq -s '.[0] + .[1]' <(echo "$COMMITS_ALL") <(echo "$COMMIT_PAGE"))
done

# Pass JSON via env vars (avoid heredoc bash-interpolation of `$` or backticks
# embedded in PR bodies).
HIP_NUMBER="$HIP_NUMBER" PRS_ALL="$PRS_ALL" COMMITS_ALL="$COMMITS_ALL" \
python3 - <<'PY'
import json, os, re, sys

hip_n = int(os.environ['HIP_NUMBER'])
prs_raw = json.loads(os.environ.get('PRS_ALL', '[]') or '[]')
commits_raw = json.loads(os.environ.get('COMMITS_ALL', '[]') or '[]')


def strip_md(body, cap=150):
    body = body or ''
    body = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', body)
    body = re.sub(r'!\[[^\]]*\]\([^)]+\)', '', body)
    body = re.sub(r'<!--.*?-->', '', body, flags=re.DOTALL)
    return body[:cap].replace('\n', ' ').strip()


prs = [
    {
        'repo': pr.get('repository', {}).get('name', ''),
        'number': pr.get('number'),
        'title': pr.get('title', ''),
        'state': (pr.get('state', '') or '').upper(),
        'author': (pr.get('author') or {}).get('login', '?'),
        'url': pr.get('url', ''),
        'body_excerpt': strip_md(pr.get('body', '')),
        # Mechanism B: per-HIP gh search hit; the search query was HIP-N,
        # so any returned PR mentions the HIP explicitly. High confidence.
        'confidence': 'high',
        'source': 'mech_b',
        'per_source': {'mech_b': {'confidence': 'high', 'reason': 'per_hip_search_hit'}},
    }
    for pr in prs_raw[:20]
]
commits = [
    {
        'repo': c.get('repository', {}).get('name', ''),
        'sha': (c.get('sha') or '')[:7],
        'subject': (c.get('commit', {}).get('message') or '').split('\n', 1)[0][:150],
        'author': (c.get('commit', {}).get('author', {}).get('name') or '?'),
        'url': c.get('url', ''),
        # Same justification as PRs: gh search for HIP-N returned this commit.
        'confidence': 'high',
        'source': 'mech_b',
        'per_source': {'mech_b': {'confidence': 'high', 'reason': 'per_hip_search_hit'}},
    }
    for c in commits_raw[:20]
]
print(json.dumps({'hip': hip_n, 'prs': prs, 'commits': commits}, indent=2))
PY
