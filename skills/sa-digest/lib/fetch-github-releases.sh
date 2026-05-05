#!/usr/bin/env bash
# fetch-github-releases.sh - fetch releases published in the date window for an org.
#
# Usage: fetch-github-releases.sh <org> <start-iso>
#   e.g. fetch-github-releases.sh hiero-ledger 2026-05-04T00:00:00Z
#
# Output: one line per release on stdout, format:
#   <repo>: <tag-name> - <release-name> (<YYYY-MM-DD>) <html_url>
#
# Iterates every repo in the org via gh api pagination. For each repo,
# fetches the releases endpoint and filters by published_at via jq using
# --arg (no shell interpolation into the jq filter).
#
# Per-repo errors are counted but do not abort. At the end, if any repo
# errored, a single WARN line is written to stderr summarizing the count.
# This catches the silent-failure case where a rate-limit or auth issue
# would otherwise look identical to "this repo has no releases."

set -euo pipefail

ORG="${1:?usage: fetch-github-releases.sh <org> <start-iso>}"
START="${2:?usage: fetch-github-releases.sh <org> <start-iso>}"

errcount=0
errfile=$(mktemp)
trap 'rm -f "$errfile"' EXIT

# Use process substitution so the loop body runs in the parent shell -
# otherwise `errcount` updates would be lost in a subshell.
while IFS= read -r repo; do
  [ -z "$repo" ] && continue
  if ! json=$(gh api "repos/$ORG/$repo/releases" 2>"$errfile"); then
    errcount=$((errcount + 1))
    continue
  fi
  # Filter via jq with --arg for safe value passing. The jq program
  # selects releases at-or-after $start and emits the formatted line.
  printf '%s' "$json" | jq -r \
    --arg start "$START" \
    --arg repo  "$repo" \
    '[.[] | select(.published_at >= $start)]
     | .[]
     | "\($repo): \(.tag_name) - \(.name // "no title") (\(.published_at[:10])) \(.html_url)"'
done < <(gh api "orgs/$ORG/repos" --paginate --jq '.[].name')

if [ "$errcount" -gt 0 ]; then
  echo "WARN: $errcount repo(s) in $ORG returned errors during release scan (rate limit, auth, or releases endpoint disabled)" >&2
fi
