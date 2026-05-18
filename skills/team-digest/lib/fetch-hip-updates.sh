#!/usr/bin/env bash
# fetch-hip-updates.sh - fetch HIPs touched on a target date, with status-change
# detection and proposal-PR awareness.
#
# Usage: fetch-hip-updates.sh <YYYY-MM-DD>
#
# Output: JSON array on stdout. Each element has:
#   { hip, title, status, prev_status?, status_changed, type, category,
#     primary_author, abstract_excerpt, raw_url, discussions_url,
#     source ("main" | "proposal_pr"), last_touched_commit?, proposal_pr_number? }
# Empty array `[]` if no HIPs touched and no proposal PRs in the window.

set -euo pipefail

TARGET_DATE="${1:?usage: fetch-hip-updates.sh <YYYY-MM-DD>}"
REPO="hiero-ledger/hiero-improvement-proposals"
PATH_PREFIX="HIP"
SINCE="${TARGET_DATE}T00:00:00Z"
UNTIL="${TARGET_DATE}T23:59:59Z"

# Step 1: list commits in the window that touched the HIP path.
# Use query-string-in-URL form. The `-f path=HIP -f since=...` form returns
# 404 because gh treats `path` as a special routing token. Direct URL query
# string works. Also: no --paginate (it concatenates arrays as `[][]`, which
# is invalid JSON; daily HIP commit volume fits in one default page).
COMMITS_URL="repos/$REPO/commits?since=$SINCE&until=$UNTIL&path=$PATH_PREFIX&per_page=100"
COMMITS_JSON=$(gh api "$COMMITS_URL" 2>/dev/null || echo '[]')

# Step 2: also fetch open PRs against the HIP repo updated in the window (proposal PRs).
PROPOSAL_PRS_JSON=$(gh search prs --repo="$REPO" --updated="$SINCE..$UNTIL" --state=open \
  --json number,title,url,author,headRefOid,body --limit 20 2>/dev/null || echo '[]')

# Pass JSON to python via env vars (NOT heredoc interpolation - bash would
# re-expand $/backticks inside an unquoted heredoc and corrupt the JSON).
COMMITS_JSON="$COMMITS_JSON" PROPOSAL_PRS_JSON="$PROPOSAL_PRS_JSON" \
HIP_REPO="$REPO" HIP_PATH_PREFIX="$PATH_PREFIX" \
python3 - <<'PY'
import base64, json, os, re, subprocess, sys

repo = os.environ['HIP_REPO']
path_prefix = os.environ['HIP_PATH_PREFIX']
commits = json.loads(os.environ.get('COMMITS_JSON', '[]') or '[]')
proposal_prs = json.loads(os.environ.get('PROPOSAL_PRS_JSON', '[]') or '[]')

HIP_FILE_RE = re.compile(
    rf'^{re.escape(path_prefix)}/hip-(\d{{1,4}})\.md$', re.IGNORECASE
)


def parse_frontmatter(content):
    """Parse YAML-ish frontmatter from a HIP file. Returns dict of lowercase keys."""
    m = re.match(r'^---\n(.*?)\n---\n', content, re.DOTALL)
    if not m:
        return {}
    fm = {}
    for line in m.group(1).splitlines():
        if ':' in line:
            k, _, v = line.partition(':')
            fm[k.strip().lower()] = v.strip()
    return fm


def extract_abstract(content):
    """First paragraph after '## Abstract' heading, capped at 300 chars."""
    m = re.search(
        r'^##\s+abstract\s*\n+(.+?)(\n##|\n\Z)',
        content, re.MULTILINE | re.DOTALL | re.IGNORECASE,
    )
    if not m:
        return ''
    return m.group(1).strip().replace('\n', ' ')[:300]


def gh_api(path):
    """Run gh api, return parsed JSON or None on error."""
    try:
        r = subprocess.run(
            ['gh', 'api', path], capture_output=True, text=True, timeout=15,
        )
        if r.returncode != 0:
            return None
        return json.loads(r.stdout)
    except Exception:
        return None


def fetch_file_content(file_path, ref=None):
    """Fetch a file from the HIP repo at an optional ref. Returns decoded string."""
    suffix = f'?ref={ref}' if ref else ''
    data = gh_api(f'repos/{repo}/contents/{file_path}{suffix}')
    if not data or data.get('type') != 'file' or not data.get('content'):
        return ''
    if data.get('encoding') == 'base64':
        return base64.b64decode(data['content']).decode('utf-8', errors='replace')
    return data['content']


# Step 1: which HIP files were touched, by which commit.
touched = {}
for commit in commits:
    sha = commit.get('sha', '')
    parents = commit.get('parents') or []
    parent_sha = parents[0].get('sha') if parents else None
    author = (
        (commit.get('author') or {}).get('login')
        or commit.get('commit', {}).get('author', {}).get('name', '?')
    )
    detail = gh_api(f'repos/{repo}/commits/{sha}')
    if not detail:
        continue
    for f in detail.get('files', []):
        m = HIP_FILE_RE.match(f.get('filename', ''))
        if not m:
            continue
        hip_n = int(m.group(1))
        touched[hip_n] = {
            'file_path': f['filename'],
            'last_sha': sha,
            'parent_sha': parent_sha,
            'primary_author': author,
        }

# Step 2: build entries for main-branch HIPs.
entries = []
for hip_n, meta in sorted(touched.items()):
    content = fetch_file_content(meta['file_path'])
    if not content:
        continue
    fm = parse_frontmatter(content)
    status = fm.get('status', 'Unknown')
    prev_status = None
    if meta['parent_sha']:
        parent_content = fetch_file_content(meta['file_path'], ref=meta['parent_sha'])
        if parent_content:
            parent_fm = parse_frontmatter(parent_content)
            parent_status = parent_fm.get('status', None)
            if parent_status and parent_status != status:
                prev_status = parent_status
    entries.append({
        'hip': hip_n,
        'title': fm.get('title', '').strip('"\''),
        'status': status,
        'prev_status': prev_status,
        'status_changed': prev_status is not None,
        'type': fm.get('type', 'Unknown'),
        'category': fm.get('category', 'Unknown'),
        'primary_author': meta['primary_author'],
        'abstract_excerpt': extract_abstract(content),
        'raw_url': f'https://github.com/{repo}/blob/main/{meta["file_path"]}',
        'discussions_url': fm.get('discussions-to') or None,
        'source': 'main',
        'last_touched_commit': meta['last_sha'][:7],
    })

# Step 3: process proposal PRs that touch HIP files not yet on main.
seen_hips = {e['hip'] for e in entries}
for pr in proposal_prs:
    pr_num = pr.get('number')
    head_sha = pr.get('headRefOid', '')
    if not pr_num:
        continue
    files = gh_api(f'repos/{repo}/pulls/{pr_num}/files') or []
    for f in files:
        m = HIP_FILE_RE.match(f.get('filename', ''))
        if not m:
            continue
        hip_n = int(m.group(1))
        if hip_n in seen_hips:
            continue
        content = fetch_file_content(f['filename'], ref=head_sha) if head_sha else ''
        if not content:
            continue
        fm = parse_frontmatter(content)
        entries.append({
            'hip': hip_n,
            'title': fm.get('title', '').strip('"\''),
            'status': 'Proposed (PR open)',
            'prev_status': None,
            'status_changed': False,
            'type': fm.get('type', 'Unknown'),
            'category': fm.get('category', 'Unknown'),
            'primary_author': (pr.get('author') or {}).get('login', '?'),
            'abstract_excerpt': extract_abstract(content),
            'raw_url': pr['url'],
            'discussions_url': fm.get('discussions-to') or None,
            'source': 'proposal_pr',
            'proposal_pr_number': pr_num,
        })

print(json.dumps(entries, indent=2))
PY
