#!/usr/bin/env bash
# fetch-hip-release-refs.sh - Strategy 2 (Release-Note Analysis) for HIP-to-code mapping.
#
# Usage:
#   fetch-hip-release-refs.sh <YYYY-MM-DD> [--backfill N] [--force-backfill]
#
# Emits a JSON array of MatchRecord-shaped entries on stdout. For each release
# published in the window across implementation_orgs repos, extracts HIP-N
# references from the release tag/name (confidence: high) and body
# (confidence: medium), then attributes them to PRs by parsing `(#NNN)` tokens
# from the release's compare-against-prev-tag commits.
#
# Per-strategy config (from hip_tracking.strategy2.*, with defaults):
#   max_refs_per_release: 50
#   max_backfill_days: 30
#   max_pr_attribution_lookups_per_release: 10
#
# Helper purity: pure shell + jq + inline python heredoc. No MCP calls.
# Errors don't abort - each repo's failures are counted and reported on stderr.

set -euo pipefail

DATE_LABEL="${1:?usage: fetch-hip-release-refs.sh <YYYY-MM-DD> [--backfill N] [--force-backfill]}"
shift || true
BACKFILL_DAYS=0
FORCE_BACKFILL=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --backfill)
      BACKFILL_DAYS="${2:?--backfill requires a number}"
      shift 2
      ;;
    --force-backfill)
      FORCE_BACKFILL=1
      shift
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"

CONFIG_JSON="$(bash "$LIB_DIR/load-config.sh" team-digest)"

MAX_REFS_PER_RELEASE=$(echo "$CONFIG_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(((d.get("hip_tracking") or {}).get("strategy2") or {}).get("max_refs_per_release",50))')
MAX_BACKFILL_DAYS=$(echo "$CONFIG_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(((d.get("hip_tracking") or {}).get("strategy2") or {}).get("max_backfill_days",30))')
MAX_PR_LOOKUPS=$(echo "$CONFIG_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(((d.get("hip_tracking") or {}).get("strategy2") or {}).get("max_pr_attribution_lookups_per_release",10))')

if [ "$BACKFILL_DAYS" -gt "$MAX_BACKFILL_DAYS" ] && [ "$FORCE_BACKFILL" != "1" ]; then
  echo "ERROR: --backfill $BACKFILL_DAYS exceeds default cap of $MAX_BACKFILL_DAYS; pass --force-backfill to override" >&2
  exit 1
fi
if [ "$BACKFILL_DAYS" -gt "$MAX_BACKFILL_DAYS" ]; then
  echo "WARN: --backfill $BACKFILL_DAYS days (forced override of cap $MAX_BACKFILL_DAYS)" >&2
fi

# Compute window. End = end of digest day; start = digest day - backfill days.
END="${DATE_LABEL}T23:59:59Z"
if command -v gdate >/dev/null 2>&1; then
  START_DATE=$(gdate -u -d "$DATE_LABEL - $BACKFILL_DAYS days" "+%Y-%m-%d")
else
  # BSD date (macOS)
  START_DATE=$(date -u -j -v-${BACKFILL_DAYS}d -f "%Y-%m-%d" "$DATE_LABEL" "+%Y-%m-%d")
fi
START="${START_DATE}T00:00:00Z"

ORGS=$(echo "$CONFIG_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("\n".join((d.get("hip_tracking") or {}).get("implementation_orgs") or []))')

if [ -z "$ORGS" ]; then
  echo "WARN: hip_tracking.implementation_orgs is empty; Strategy 2 has no orgs to scan" >&2
  echo "[]"
  exit 0
fi

errcount=0
errfile=$(mktemp)
trap 'rm -f "$errfile"' EXIT

# Accumulator file for MatchRecords - python script appends to it.
RESULTS_FILE=$(mktemp)
trap 'rm -f "$errfile" "$RESULTS_FILE"' EXIT
echo "[]" > "$RESULTS_FILE"

while IFS= read -r ORG; do
  [ -z "$ORG" ] && continue
  # List all repos in the org
  if ! REPOS_JSON=$(gh api "orgs/$ORG/repos" --paginate 2>"$errfile"); then
    echo "WARN: failed to list repos for org $ORG" >&2
    errcount=$((errcount + 1))
    continue
  fi
  REPOS=$(echo "$REPOS_JSON" | jq -r '.[].name')
  while IFS= read -r REPO; do
    [ -z "$REPO" ] && continue
    if ! RELEASES_JSON=$(gh api "repos/$ORG/$REPO/releases" 2>"$errfile"); then
      errcount=$((errcount + 1))
      continue
    fi
    # Filter to window
    WINDOW_RELEASES=$(echo "$RELEASES_JSON" | jq --arg start "$START" --arg end "$END" '[.[] | select(.published_at >= $start and .published_at <= $end)]')
    NUM=$(echo "$WINDOW_RELEASES" | jq 'length')
    [ "$NUM" -eq 0 ] && continue

    # For each release, process
    INDEX=0
    while [ "$INDEX" -lt "$NUM" ]; do
      RELEASE=$(echo "$WINDOW_RELEASES" | jq ".[$INDEX]")
      INDEX=$((INDEX + 1))

      TAG=$(echo "$RELEASE" | jq -r '.tag_name // ""')
      NAME=$(echo "$RELEASE" | jq -r '.name // ""')
      BODY=$(echo "$RELEASE" | jq -r '.body // ""')
      URL=$(echo "$RELEASE" | jq -r '.html_url // ""')

      # Extract HIPs from tag+name (in_tag = high), and body (in_body = medium).
      TAG_NAME_INPUT="${TAG} ${NAME}"
      HIPS_IN_TAG=$(printf '%s' "$TAG_NAME_INPUT" | bash "$LIB_DIR/extract-hip-refs.sh")
      HIPS_IN_BODY=$(printf '%s' "$BODY" | bash "$LIB_DIR/extract-hip-refs.sh")

      # Find previous release tag for compare lookup
      PREV_TAG=$(echo "$RELEASES_JSON" | jq -r --arg this_at "$(echo "$RELEASE" | jq -r '.published_at')" '
        [.[] | select(.published_at < $this_at)] | sort_by(.published_at) | reverse | .[0].tag_name // ""')

      # Fetch compare commits if previous tag exists. Otherwise PR_NUMBERS stays empty.
      PR_NUMBERS="[]"
      if [ -n "$PREV_TAG" ] && [ "$PREV_TAG" != "null" ]; then
        if COMPARE_JSON=$(gh api "repos/$ORG/$REPO/compare/$PREV_TAG...$TAG" 2>"$errfile"); then
          PR_NUMBERS=$(echo "$COMPARE_JSON" | python3 -c '
import json, re, sys
d = json.load(sys.stdin)
commits = d.get("commits", [])
prs = []
seen = set()
for c in commits:
    msg = (c.get("commit", {}) or {}).get("message", "") or ""
    # Look for "(#NNN)" trailing on subject line (GitHub default merge format).
    for m in re.finditer(r"\(#(\d{1,6})\)", msg):
        n = int(m.group(1))
        if n in seen:
            continue
        seen.add(n)
        prs.append(n)
print(json.dumps(prs))
')
        else
          errcount=$((errcount + 1))
        fi
      fi

      # Build MatchRecords via python (avoids shell quoting issues with PR-body
      # bash interpolation - same pattern as fetch-hip-implementation-prs.sh).
      HIPS_IN_TAG="$HIPS_IN_TAG" \
      HIPS_IN_BODY="$HIPS_IN_BODY" \
      PR_NUMBERS="$PR_NUMBERS" \
      TAG="$TAG" URL="$URL" REPO_FULL="$ORG/$REPO" \
      MAX_REFS_PER_RELEASE="$MAX_REFS_PER_RELEASE" \
      MAX_PR_LOOKUPS="$MAX_PR_LOOKUPS" \
      RESULTS_FILE="$RESULTS_FILE" \
      python3 - <<'PY'
import json, os, sys

hips_in_tag = json.loads(os.environ.get("HIPS_IN_TAG", "[]") or "[]")
hips_in_body = json.loads(os.environ.get("HIPS_IN_BODY", "[]") or "[]")
prs = json.loads(os.environ.get("PR_NUMBERS", "[]") or "[]")
tag = os.environ.get("TAG", "")
url = os.environ.get("URL", "")
repo_full = os.environ.get("REPO_FULL", "")
max_refs = int(os.environ.get("MAX_REFS_PER_RELEASE", "50"))
max_pr_lookups = int(os.environ.get("MAX_PR_LOOKUPS", "10"))

# Dedup HIPs - in_tag wins precedence over in_body for the same number.
hips_in_tag_set = set(hips_in_tag)
hips_combined = list(dict.fromkeys(hips_in_tag + [h for h in hips_in_body if h not in hips_in_tag_set]))
if len(hips_combined) > max_refs:
    print(f"[Notice] {repo_full} release {tag}: {len(hips_combined)} HIPs in release refs, capping at {max_refs}", file=sys.stderr)
    hips_combined = hips_combined[:max_refs]

prs_capped = prs[:max_pr_lookups]

records = []
for hip_n in hips_combined:
    is_in_tag = hip_n in hips_in_tag_set
    confidence = "high" if is_in_tag else "medium"
    reason = "in_tag" if is_in_tag else "in_body"
    if not prs_capped:
        # No PR attribution available - emit a release-level record with pr_number 0.
        # Downstream merge can still surface this in verbose mode.
        records.append({
            "hip_id": f"HIP-{hip_n}",
            "repo": repo_full,
            "pr_number": 0,
            "confidence": confidence,
            "sources": ["s2"],
            "per_source": {"s2": {"confidence": confidence, "reason": f"{reason}_no_pr_attribution"}},
            "release_tag": tag,
            "release_url": url,
        })
        continue
    for pr_n in prs_capped:
        records.append({
            "hip_id": f"HIP-{hip_n}",
            "repo": repo_full,
            "pr_number": pr_n,
            "confidence": confidence,
            "sources": ["s2"],
            "per_source": {"s2": {"confidence": confidence, "reason": reason}},
            "release_tag": tag,
            "release_url": url,
        })

# Append to results file
existing = json.load(open(os.environ["RESULTS_FILE"]))
existing.extend(records)
json.dump(existing, open(os.environ["RESULTS_FILE"], "w"))
PY
    done
  done <<< "$REPOS"
done <<< "$ORGS"

if [ "$errcount" -gt 0 ]; then
  echo "WARN: $errcount errors during Strategy 2 release-note analysis (rate limit, auth, or missing endpoints)" >&2
fi

cat "$RESULTS_FILE"
