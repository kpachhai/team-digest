#!/usr/bin/env bash
# consolidate-matches.sh - merge per-strategy match-record JSONs into the
# canonical matches.json. Replaces the in-Claude-context Phase 3b merge that
# F4 surfaced as unreliable under high-volume PR scans.
#
# Usage: consolidate-matches.sh <matches-dir> [<output-path>]
#
# Reads all *.json files in <matches-dir> (mech_a-prs-*.json,
# mech_a-issues-*.json, mech_b.json, strategy2.json, strategy3.json) and any
# other strategy file dropped there, dedups on (hip_id, repo, pr_number) with
# MAX-confidence rule (high > medium > low), unions sources[] and per_source
# maps, and emits the merged array to stdout (or <output-path> if given).
#
# F5 (iteration 5): this helper IS the canonical source of matches.json. The
# previous design relied on the skill body to hold the merged list across
# many Step 2.3 → Step 5 phases; with high PR volume that became lossy.
# This helper is deterministic - no Claude context-holding required.
#
# Empty <matches-dir> or a dir with no JSON files yields `[]`.

set -euo pipefail

MATCHES_DIR="${1:?usage: consolidate-matches.sh <matches-dir> [<output-path>]}"
OUTPUT_PATH="${2:-}"

if [ ! -d "$MATCHES_DIR" ]; then
  if [ -n "$OUTPUT_PATH" ]; then
    echo "[]" > "$OUTPUT_PATH"
  else
    echo "[]"
  fi
  exit 0
fi

MATCHES_DIR="$MATCHES_DIR" OUTPUT_PATH="$OUTPUT_PATH" python3 - <<'PY'
import json, os, sys
from pathlib import Path

matches_dir = Path(os.environ["MATCHES_DIR"])
output_path = os.environ.get("OUTPUT_PATH") or ""

CONF_RANK = {"high": 3, "medium": 2, "low": 1}


def normalize_record(r):
    """Lift one record into the canonical MatchRecord shape. Tolerant of
    helper-specific extras (release_tag, matched_keywords, pr_*, etc.) -
    they pass through unchanged. Required keys: hip_id, repo, pr_number,
    confidence, sources, per_source."""
    if not isinstance(r, dict):
        return None
    if "hip_id" not in r or "repo" not in r:
        return None
    # pr_number may be 0 (release-level) or null - both valid; normalize to int 0.
    try:
        pr_n = int(r.get("pr_number") or 0)
    except Exception:
        pr_n = 0
    out = dict(r)
    out["pr_number"] = pr_n
    out.setdefault("sources", [])
    out.setdefault("per_source", {})
    out.setdefault("confidence", "low")
    return out


def max_confidence(a, b):
    return a if CONF_RANK.get(a, 0) >= CONF_RANK.get(b, 0) else b


# Read every .json file under matches-dir (including mech_b.json, strategy2.json,
# strategy3.json, and the mech_a-prs-*.json / mech_a-issues-*.json sidecars).
merged_by_key = {}
files_read = []
for jpath in sorted(matches_dir.glob("*.json")):
    files_read.append(jpath.name)
    try:
        with open(jpath) as f:
            payload = json.load(f)
    except Exception as e:
        print(f"WARN: skipping {jpath.name}: {e}", file=sys.stderr)
        continue

    # The Mech B helper emits {hip, prs: [...], commits: [...]}; everything else
    # emits a flat array of MatchRecords. Normalize both shapes.
    records = []
    if isinstance(payload, list):
        records = payload
    elif isinstance(payload, dict):
        # Mech B shape: lift each PR/commit into a MatchRecord.
        hip_n = payload.get("hip")
        hip_id = f"HIP-{hip_n}" if hip_n is not None else None
        for pr in payload.get("prs", []) or []:
            if not isinstance(pr, dict):
                continue
            # Mech B PR records have repo (short name), number, title, state,
            # author, url, body_excerpt, confidence, source, per_source.
            rec = dict(pr)
            if hip_id and "hip_id" not in rec:
                rec["hip_id"] = hip_id
            # Promote "number" -> "pr_number" and "repo" stays as-is.
            if "pr_number" not in rec and "number" in rec:
                rec["pr_number"] = rec["number"]
            # Normalize sources/per_source from the singular fields the helper emits.
            if "source" in rec and "sources" not in rec:
                rec["sources"] = [rec["source"]]
            if rec.get("source") and "per_source" not in rec:
                rec["per_source"] = {rec["source"]: {"confidence": rec.get("confidence", "high")}}
            records.append(rec)
        for commit in payload.get("commits", []) or []:
            # Commits don't have pr_number; skip for the matches.json dedup table.
            # (Commits surface in the digest narrative via the helper's stdout; not
            # part of the canonical PR-keyed matches index.)
            continue

    for r in records:
        rec = normalize_record(r)
        if rec is None:
            continue
        key = (rec["hip_id"], rec["repo"], rec["pr_number"])
        if key not in merged_by_key:
            merged_by_key[key] = rec
        else:
            existing = merged_by_key[key]
            existing["sources"] = sorted(set((existing.get("sources") or []) + (rec.get("sources") or [])))
            existing_per = existing.get("per_source") or {}
            existing_per.update(rec.get("per_source") or {})
            existing["per_source"] = existing_per
            existing["confidence"] = max_confidence(existing.get("confidence", "low"), rec.get("confidence", "low"))
            # Pass-through richer display-relevant fields when the new record
            # has them and the existing record doesn't.
            for k in ("pr_title", "pr_state", "pr_author", "pr_url",
                      "pr_closed_at", "pr_updated_at", "pr_merged_at",
                      "release_tag", "release_url",
                      "matched_keywords", "category_tiebreak"):
                if k in rec and not existing.get(k):
                    existing[k] = rec[k]


merged = sorted(merged_by_key.values(), key=lambda r: (r["hip_id"], r["repo"], r["pr_number"]))

out = json.dumps(merged, indent=2)
if output_path:
    with open(output_path, "w") as f:
        f.write(out)
    print(f"Wrote {len(merged)} merged records to {output_path}", file=sys.stderr)
    print(f"  sources covered: {sorted(set(s for r in merged for s in (r.get('sources') or [])))}", file=sys.stderr)
    print(f"  files read: {len(files_read)}", file=sys.stderr)
else:
    print(out)
PY
