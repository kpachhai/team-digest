#!/usr/bin/env bash
# fetch-github-prs.sh - fetch PRs updated in the date window for an org.
#
# Usage: fetch-github-prs.sh <org> <start-iso> <end-iso>
#   e.g. fetch-github-prs.sh your-org 2026-05-04T00:00:00Z 2026-05-04T23:59:59Z
#
# Output: human-readable summary on stdout, grouped by repo. Each PR line
# includes state, number, title, author handle, html_url, mergedAt (when set),
# and a 150-char description excerpt. The skill consumes this output as
# plain text.
#
# F5 side effect: if $TEAM_DIGEST_MATCHES_DIR is set in the environment, the
# helper also writes a structured Mech A match-records JSON file at
# $TEAM_DIGEST_MATCHES_DIR/mech_a-prs-<org>.json with one entry per
# (hip_id, repo, pr_number) tuple. This file is consumed by SKILL.md
# Phase 3d to build the canonical matches.json deterministically (no
# context-held re-extraction required).

set -euo pipefail

ORG="${1:?usage: fetch-github-prs.sh <org> <start-iso> <end-iso>}"
START="${2:?usage: fetch-github-prs.sh <org> <start-iso> <end-iso>}"
END="${3:?usage: fetch-github-prs.sh <org> <start-iso> <end-iso>}"

_py=$(mktemp /tmp/gh-prs-XXXXXX.py)
trap 'rm -f "$_py"' EXIT
cat > "$_py" <<'PY'
import json, os, re, subprocess, sys

data = json.load(sys.stdin)
if not data:
    print('(no PRs updated in window)')
    sys.exit(0)

if len(data) >= 100:
    print('WARNING: gh search returned 100 results (the --limit cap). Some PRs may be missing - consider narrowing the org or date.', file=sys.stderr)

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
for pr in data:
    repos.setdefault(pr['repository']['name'], []).append(pr)

# F5: structured Mech A match records emitted to disk when
# $TEAM_DIGEST_MATCHES_DIR is set. The helper has reliable in-process state
# (the gh JSON + extract_hips output), so writing here is more robust than
# asking the skill body to re-parse the text output.
mech_a_records = []
org_name = os.environ.get('TEAM_DIGEST_GH_ORG', '')

for repo in sorted(repos):
    prs = repos[repo]
    print(f'## {repo} ({len(prs)} PRs)')
    for pr in prs:
        raw_body = pr.get('body') or ''
        # Strip markdown noise before truncating so the 150-char excerpt
        # carries information density, not formatting.
        body = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', raw_body)     # [text](url) -> text
        body = re.sub(r'!\[[^\]]*\]\([^)]+\)', '', body)             # ![alt](url) -> (drop)
        body = re.sub(r'<!--.*?-->', '', body, flags=re.DOTALL)      # HTML comments -> (drop)
        body = body[:150].replace('\n', ' ').strip()
        author = (pr.get('author') or {}).get('login', '?')
        state = pr.get('state', '?').upper()
        title = pr['title']
        # closedAt is set when the PR is merged or closed; updatedAt is always
        # populated. For our purposes (distinguish "active today" from "active
        # earlier in lookback window") closedAt is the better date when set,
        # falling through to updatedAt for still-open PRs.
        closed_at = pr.get('closedAt') or ''
        updated_at = pr.get('updatedAt') or ''
        activity_date = (closed_at or updated_at)[:10]
        print(f'  [{state}] #{pr["number"]} {title}')
        print(f'    Author: @{author}')
        print(f'    URL: {pr["url"]}')
        if activity_date:
            label = 'Closed' if closed_at else 'Updated'
            print(f'    {label}: {activity_date}')
        if body:
            print(f'    Description: {body}')
        hips = extract_hips(f'{title}\n{raw_body}')
        if hips:
            # Mech A always emits high confidence: an explicit HIP-N token in
            # PR title or body, filtered through the known-HIPs index.
            hip_list = ', '.join(f'HIP-{n} (high)' for n in hips)
            print(f'    Linked HIPs: {hip_list}')
            # F5: structured record for the canonical matches.json.
            repo_full = pr.get('repository', {}).get('nameWithOwner') or f'{org_name}/{repo}'
            for n in hips:
                mech_a_records.append({
                    'hip_id': f'HIP-{n}',
                    'repo': repo_full,
                    'pr_number': pr['number'],
                    'confidence': 'high',
                    'sources': ['mech_a'],
                    'per_source': {'mech_a': {'confidence': 'high', 'reason': 'regex_annotation'}},
                    'pr_title': title,
                    'pr_state': state,
                    'pr_author': author,
                    'pr_url': pr['url'],
                    'pr_closed_at': closed_at[:10] if closed_at else None,
                    'pr_updated_at': updated_at[:10] if updated_at else None,
                })
        print()

# F5 side-effect: emit structured Mech A records to a known location so the
# skill's Phase 3d can read them deterministically instead of re-parsing the
# text output above.
matches_dir = os.environ.get('TEAM_DIGEST_MATCHES_DIR', '')
if matches_dir:
    try:
        os.makedirs(matches_dir, exist_ok=True)
        out_path = os.path.join(matches_dir, f'mech_a-prs-{org_name or "unknown-org"}.json')
        with open(out_path, 'w') as f:
            json.dump(mech_a_records, f, indent=2)
        print(f'(structured mech_a sidecar: {out_path}, {len(mech_a_records)} record(s))', file=sys.stderr)
    except Exception as e:
        print(f'WARN: failed to write mech_a sidecar to {matches_dir}: {e}', file=sys.stderr)
PY

gh search prs \
  --owner="$ORG" \
  --updated="${START}..${END}" \
  --json repository,title,state,author,number,body,url,labels,closedAt,updatedAt \
  --limit 100 \
  | TEAM_DIGEST_GH_ORG="$ORG" python3 "$_py"
