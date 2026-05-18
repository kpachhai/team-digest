#!/usr/bin/env bash
# fetch-hip-timeline-correlations.sh - Strategy 3 (Timeline Correlation) for
# HIP-to-code mapping.
#
# Usage: fetch-hip-timeline-correlations.sh <YYYY-MM-DD>
#
# Emits a JSON array of MatchRecord-shaped entries on stdout for PRs in
# implementation_orgs that plausibly implement HIPs that moved status TODAY,
# using keyword overlap from the HIP title (+ a HIP-category-to-repo tiebreaker
# map when overlap is 1-2 tokens).
#
# Per-strategy config (from hip_tracking.strategy3.*, with defaults):
#   max_correlation_hips: 10
#   per_org_search_budget: 10
#   noise_ceiling_commits_per_day: 20
#   category_to_repos: { HTS: [...], HCS: [...], ... }
#
# Helper purity: pure shell + jq + inline python heredoc. No MCP calls.
# 429 / secondary-rate-limit responses get exponential backoff (1s/2s/4s,
# max 3 retries); a still-failing org emits a single s3_skipped record and
# the helper continues - it does NOT crash the digest.

set -euo pipefail

DATE_LABEL="${1:?usage: fetch-hip-timeline-correlations.sh <YYYY-MM-DD>}"

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"

CONFIG_JSON="$(bash "$LIB_DIR/load-config.sh" team-digest)"

MAX_HIPS=$(echo "$CONFIG_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(((d.get("hip_tracking") or {}).get("strategy3") or {}).get("max_correlation_hips",10))')
BUDGET=$(echo "$CONFIG_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(((d.get("hip_tracking") or {}).get("strategy3") or {}).get("per_org_search_budget",10))')
NOISE_CEILING=$(echo "$CONFIG_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(((d.get("hip_tracking") or {}).get("strategy3") or {}).get("noise_ceiling_commits_per_day",20))')
CATEGORY_MAP=$(echo "$CONFIG_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps(((d.get("hip_tracking") or {}).get("strategy3") or {}).get("category_to_repos",{})))')
ORGS=$(echo "$CONFIG_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("\n".join((d.get("hip_tracking") or {}).get("implementation_orgs") or []))')

if [ -z "$ORGS" ]; then
  echo "WARN: hip_tracking.implementation_orgs is empty; Strategy 3 has no orgs to scan" >&2
  echo "[]"
  exit 0
fi

# Compute past-7d window for PR creation filter
if command -v gdate >/dev/null 2>&1; then
  WINDOW_START=$(gdate -u -d "$DATE_LABEL - 7 days" "+%Y-%m-%d")
else
  WINDOW_START=$(date -u -j -v-7d -f "%Y-%m-%d" "$DATE_LABEL" "+%Y-%m-%d")
fi
WINDOW_END="$DATE_LABEL"

# Step 1: get today's status-changed HIPs (with valid prev_status)
HIPS_RAW=$(bash "$LIB_DIR/fetch-hip-updates.sh" "$DATE_LABEL" 2>/dev/null || echo '[]')

STATUS_CHANGED_HIPS=$(echo "$HIPS_RAW" | jq '[.[] | select(.status_changed == true and .prev_status != null and .prev_status != "Unknown" and (.prev_status | length > 0))]')
NUM_HIPS=$(echo "$STATUS_CHANGED_HIPS" | jq 'length')
if [ "$NUM_HIPS" -eq 0 ]; then
  # Nothing to correlate
  echo "[]"
  exit 0
fi
# Cap at MAX_HIPS
STATUS_CHANGED_HIPS=$(echo "$STATUS_CHANGED_HIPS" | jq --argjson cap "$MAX_HIPS" '.[:$cap]')

# Step 2: extract keywords per HIP via python (stopwords + len >= 4 + cap 5)
HIPS_WITH_KEYWORDS=$(STATUS_CHANGED_HIPS="$STATUS_CHANGED_HIPS" python3 - <<'PY'
import json, os, re

STOPWORDS = {
    "the", "and", "for", "with", "from", "this", "that", "have", "into",
    "than", "more", "less", "such", "also", "when", "while", "where",
    "what", "which", "after", "before", "during", "implement",
    "implementation", "support", "supported", "supports", "add", "adds",
    "new", "update", "updates", "fix", "fixes", "change", "changes",
    "improve", "improves", "introduce", "introduces", "make", "makes",
    "feature", "features", "service", "services", "based", "using",
    "hedera", "hiero", "hip",
}

data = json.loads(os.environ["STATUS_CHANGED_HIPS"])
for hip in data:
    title = (hip.get("title") or "")
    tokens = re.findall(r"[A-Za-z]{4,}", title)
    keywords = []
    seen = set()
    for t in tokens:
        tl = t.lower()
        if tl in STOPWORDS or tl in seen:
            continue
        seen.add(tl)
        keywords.append(tl)
        if len(keywords) >= 5:
            break
    hip["_keywords"] = keywords
print(json.dumps(data))
PY
)

# Step 3: batched per-org search. Build one query per org combining HIP-N OR keywords.
RESULTS_FILE=$(mktemp)
ERR_FILE=$(mktemp)
trap 'rm -f "$RESULTS_FILE" "$ERR_FILE"' EXIT
echo "[]" > "$RESULTS_FILE"

# Build the OR query string once (shared across orgs)
QUERY=$(HIPS_WITH_KEYWORDS="$HIPS_WITH_KEYWORDS" python3 - <<'PY'
import json, os
hips = json.loads(os.environ["HIPS_WITH_KEYWORDS"])
parts = set()
for hip in hips:
    n = hip.get("hip") or hip.get("hip_number") or hip.get("number")
    if n is not None:
        parts.add(f'"HIP-{n}"')
    for kw in hip.get("_keywords", []):
        parts.add(f'"{kw}"')
if not parts:
    print("")
else:
    print(" OR ".join(sorted(parts)))
PY
)

if [ -z "$QUERY" ]; then
  echo "[]"
  exit 0
fi

while IFS= read -r ORG; do
  [ -z "$ORG" ] && continue

  CALL_COUNT=0
  ATTEMPT=1
  PRS_RAW=""
  while [ "$ATTEMPT" -le 3 ]; do
    if [ "$CALL_COUNT" -ge "$BUDGET" ]; then
      echo "WARN: Strategy 3: per-org budget ($BUDGET) reached for $ORG before completion" >&2
      break
    fi
    if PRS_RAW=$(gh search prs "$QUERY" \
        --owner "$ORG" \
        --created="$WINDOW_START..$WINDOW_END" \
        --json number,repository,title,body,labels,author,createdAt,updatedAt,url \
        --limit 100 2>"$ERR_FILE"); then
      CALL_COUNT=$((CALL_COUNT + 1))
      break
    fi
    # On failure, inspect error type
    if grep -qi "secondary rate limit\|rate limit\|429" "$ERR_FILE"; then
      SLEEP_SEC=$((2 ** (ATTEMPT - 1)))
      echo "WARN: Strategy 3: rate-limit on $ORG attempt $ATTEMPT; backoff ${SLEEP_SEC}s" >&2
      sleep "$SLEEP_SEC"
      ATTEMPT=$((ATTEMPT + 1))
      continue
    fi
    # Non-rate-limit error - emit skipped record and move on
    echo "WARN: Strategy 3: gh search failed for $ORG: $(cat "$ERR_FILE" | head -2 | tr '\n' ' ')" >&2
    PRS_RAW="[]"
    break
  done

  if [ "$ATTEMPT" -gt 3 ]; then
    # All retries exhausted - emit skipped record
    SKIP_REC=$(jq -n --arg org "$ORG" '{
      hip_id: "ALL",
      repo: ("\($org)/_meta"),
      pr_number: 0,
      confidence: "low",
      sources: ["s3_skipped"],
      per_source: { s3_skipped: { confidence: "low", reason: "rate_limit_after_3_retries" } }
    }')
    existing=$(cat "$RESULTS_FILE")
    jq -n --argjson e "$existing" --argjson r "$SKIP_REC" '$e + [$r]' > "$RESULTS_FILE.new" && mv "$RESULTS_FILE.new" "$RESULTS_FILE"
    continue
  fi

  [ -z "$PRS_RAW" ] && PRS_RAW="[]"

  # Step 4: score each PR against each HIP (keyword overlap + category tiebreak)
  SCORED=$(HIPS_WITH_KEYWORDS="$HIPS_WITH_KEYWORDS" \
           PRS_RAW="$PRS_RAW" \
           CATEGORY_MAP="$CATEGORY_MAP" \
           ORG="$ORG" \
           python3 - <<'PY'
import json, os, re

hips = json.loads(os.environ["HIPS_WITH_KEYWORDS"])
prs = json.loads(os.environ.get("PRS_RAW", "[]") or "[]")
category_map_raw = json.loads(os.environ.get("CATEGORY_MAP", "{}") or "{}")
org = os.environ["ORG"]


def classify_hip_category(hip):
    """Map a HIP to a category string for the tiebreak map. Best-effort."""
    title = (hip.get("title") or "").lower()
    cat = (hip.get("category") or "").upper()
    typ = (hip.get("type") or "").upper()
    # Direct match first
    if cat in category_map_raw:
        return cat
    # Heuristic mapping from title tokens. Order matters - check
    # infrastructure-specific terms (Block Node, Relay) before broader
    # service categories so they win the tiebreaker for the right repos.
    if any(t in title for t in ["block node", "block stream", "block streaming"]):
        return "Block Node"
    if any(t in title for t in ["json-rpc", "json rpc", "jsonrpc", "relay"]):
        return "Relay"
    if any(t in title for t in ["token service", "hts", "token "]):
        return "HTS"
    if any(t in title for t in ["consensus service", "hcs", "topic "]):
        return "HCS"
    if any(t in title for t in ["smart contract", "hss", "evm", "hooks"]):
        return "HSS"
    if "mirror" in title or "rest api" in title:
        return "Mirror Node"
    if "sdk" in title:
        return "SDK"
    return ""


def tokenize(text):
    return set(t.lower() for t in re.findall(r"[A-Za-z]{4,}", text or ""))


out = []
for pr in prs:
    repo_full = (pr.get("repository") or {}).get("nameWithOwner") or ""
    pr_num = pr.get("number")
    if not repo_full or pr_num is None:
        continue
    pr_text = (pr.get("title") or "") + " " + " ".join(
        (l.get("name") or "") if isinstance(l, dict) else str(l)
        for l in (pr.get("labels") or [])
    )
    pr_tokens = tokenize(pr_text)
    for hip in hips:
        kws = set(hip.get("_keywords", []))
        overlap = pr_tokens & kws
        if not overlap:
            continue
        hip_n = hip.get("hip") or hip.get("hip_number") or hip.get("number")
        if hip_n is None:
            continue
        hip_id = f"HIP-{hip_n}"
        if len(overlap) >= 3:
            confidence = "medium"
            reason = "keyword_overlap_3plus"
            category_tiebreak = None
        else:
            # 1-2 overlap: category tiebreak
            hip_cat = classify_hip_category(hip)
            cat_repos = category_map_raw.get(hip_cat, []) if hip_cat else []
            if repo_full in cat_repos:
                confidence = "low"
                reason = "keyword_overlap_1or2_plus_category_tiebreak"
                category_tiebreak = hip_cat
            else:
                # No tiebreak match - drop
                continue
        out.append({
            "hip_id": hip_id,
            "repo": repo_full,
            "pr_number": pr_num,
            "confidence": confidence,
            "sources": ["s3"],
            "per_source": {"s3": {"confidence": confidence, "reason": reason}},
            "pr_title": pr.get("title") or "",
            "pr_state": (pr.get("state") or "").upper() if pr.get("state") else "",
            "pr_author": (pr.get("author") or {}).get("login", "") if isinstance(pr.get("author"), dict) else "",
            "pr_url": pr.get("url") or "",
            "matched_keywords": sorted(overlap),
            "category_tiebreak": category_tiebreak,
        })

print(json.dumps(out))
PY
)

  # Apply noise ceiling: count commits per repo on digest day for the PRs we have
  REPOS_IN_SCORED=$(echo "$SCORED" | jq -r '[.[] | .repo] | unique | .[]')
  while IFS= read -r REPO_FULL; do
    [ -z "$REPO_FULL" ] && continue
    if ! COMMIT_COUNT=$(gh api "repos/$REPO_FULL/commits?since=${DATE_LABEL}T00:00:00Z&until=${DATE_LABEL}T23:59:59Z&per_page=100" --jq 'length' 2>/dev/null); then
      COMMIT_COUNT=0
    fi
    if [ "$COMMIT_COUNT" -gt "$NOISE_CEILING" ]; then
      SCORED=$(echo "$SCORED" | jq --arg repo "$REPO_FULL" --argjson ceiling "$NOISE_CEILING" '
        map(if .repo == $repo then (
          .confidence = "low"
          | .per_source.s3.confidence = "low"
          | .per_source.s3.reason = ("high-volume area (>" + ($ceiling | tostring) + " commits/day, downgraded)")
        ) else . end)')
    fi
  done <<< "$REPOS_IN_SCORED"

  # Append SCORED into RESULTS_FILE
  existing=$(cat "$RESULTS_FILE")
  jq -n --argjson e "$existing" --argjson s "$SCORED" '$e + $s' > "$RESULTS_FILE.new" && mv "$RESULTS_FILE.new" "$RESULTS_FILE"

done <<< "$ORGS"

# Sidecar: also write to $TEAM_DIGEST_MATCHES_DIR if set, so the wrapper's
# consolidator can read Strategy 3 records deterministically.
if [ -n "${TEAM_DIGEST_MATCHES_DIR:-}" ]; then
  mkdir -p "$TEAM_DIGEST_MATCHES_DIR" 2>/dev/null && \
    cp "$RESULTS_FILE" "$TEAM_DIGEST_MATCHES_DIR/strategy3.json" 2>/dev/null && \
    echo "(structured strategy3 sidecar: $TEAM_DIGEST_MATCHES_DIR/strategy3.json)" >&2 || \
    echo "WARN: failed to write strategy3 sidecar to $TEAM_DIGEST_MATCHES_DIR" >&2
fi

cat "$RESULTS_FILE"
