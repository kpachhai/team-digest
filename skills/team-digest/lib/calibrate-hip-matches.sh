#!/usr/bin/env bash
# calibrate-hip-matches.sh - Measure precision/recall/F1 of HIP-to-code
# matching strategies against the strategy-independent labeled set.
#
# Two modes:
#
#   calibrate-hip-matches.sh --baseline <dry-run-output-file>
#     Reads ~/.config/team-digest/hip-code-mapper-labeled-set.json + the
#     <dry-run-output-file>'s companion <...>-matches.json. Computes precision,
#     recall, F1 per strategy AND overall. Writes
#     ~/.config/team-digest/hip-calibration-baseline.json with timestamp.
#
#   calibrate-hip-matches.sh --current-only [dry-run-output-file]
#     Emits ~/.config/team-digest/hip-calibration-current.json with the
#     per-strategy match count distribution from the latest run (or the
#     supplied output's companion matches.json). If a baseline exists and is
#     >180 days old, emits a warn-once on stderr. Designed to be called from
#     SKILL.md Step 2.3 finalize.
#
# The labeled set is the source of truth for is_implementation; this helper
# never re-labels.

set -euo pipefail

MODE="${1:?usage: calibrate-hip-matches.sh --baseline <dry-run-output> | --current-only [dry-run-output]}"
shift || true

LABELED_SET="$HOME/.config/team-digest/hip-code-mapper-labeled-set.json"
BASELINE_FILE="$HOME/.config/team-digest/hip-calibration-baseline.json"
CURRENT_FILE="$HOME/.config/team-digest/hip-calibration-current.json"

case "$MODE" in
  --baseline)
    DRY_RUN_OUTPUT="${1:?--baseline requires a dry-run output file path}"
    if [ ! -f "$LABELED_SET" ]; then
      echo "ERROR: labeled set not found at $LABELED_SET; run T2 (build-labeled-set) first" >&2
      exit 1
    fi
    MATCHES_JSON="${DRY_RUN_OUTPUT%.md}-matches.json"
    if [ ! -f "$MATCHES_JSON" ]; then
      echo "ERROR: matches JSON not found at $MATCHES_JSON. Step 2.3 emits this file alongside the dry-run safety file; ensure the dry-run was iteration-2 aware." >&2
      exit 1
    fi
    LABELED_SET="$LABELED_SET" \
    MATCHES_JSON="$MATCHES_JSON" \
    BASELINE_FILE="$BASELINE_FILE" \
    TARGET_REPO="$(cd "$(dirname "$0")/../../.." && pwd)" \
    python3 - <<'PY'
import datetime, json, os, subprocess, sys

labeled_path = os.environ["LABELED_SET"]
matches_path = os.environ["MATCHES_JSON"]
out_path = os.environ["BASELINE_FILE"]
target_repo = os.environ["TARGET_REPO"]

with open(labeled_path) as f:
    labeled = [e for e in json.load(f) if "_meta" not in e]

with open(matches_path) as f:
    matches = json.load(f)

labeled_positives = {(e["hip_id"], e["repo"], int(e["pr_number"])): True
                     for e in labeled if e["is_implementation"]}
labeled_negatives = {(e["hip_id"], e["repo"], int(e["pr_number"])): False
                     for e in labeled if not e["is_implementation"]}

per_strategy = {}
for strategy in ["mech_a", "mech_b", "s2", "s3", "s4"]:
    strategy_keys = set()
    for m in matches:
        srcs = m.get("sources") or []
        # s2_in_tag / s2_in_body collapse under "s2" for per-strategy counting.
        # s3_skipped doesn't count for s3 precision (it's a control record).
        match_strategy = strategy
        if strategy == "s2" and (("s2_in_tag" in srcs) or ("s2_in_body" in srcs) or ("s2" in srcs)):
            strategy_keys.add((m["hip_id"], m["repo"], int(m.get("pr_number") or 0)))
        elif strategy in srcs:
            strategy_keys.add((m["hip_id"], m["repo"], int(m.get("pr_number") or 0)))
    tp = sum(1 for k in labeled_positives if k in strategy_keys)
    fn = sum(1 for k in labeled_positives if k not in strategy_keys)
    fp = sum(1 for k in strategy_keys if k in labeled_negatives)
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0
    per_strategy[strategy] = {
        "tp": tp, "fp": fp, "fn": fn,
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "f1": round(f1, 4),
    }

# Overall: all strategies merged (any match anywhere = positive)
all_keys = {(m["hip_id"], m["repo"], int(m.get("pr_number") or 0)) for m in matches}
tp = sum(1 for k in labeled_positives if k in all_keys)
fn = sum(1 for k in labeled_positives if k not in all_keys)
fp = sum(1 for k in all_keys if k in labeled_negatives)
precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0

try:
    # Try the script-relative ../../../ first (works when helper runs from
    # the repo's skills/team-digest/lib/). Falls through to "unknown" when
    # the helper is installed at ~/.claude/skills/team-digest/lib/ - that
    # path's .. .. .. lands in ~/.claude/ which is not a git repo.
    sha = subprocess.check_output(
        ["git", "-C", target_repo, "rev-parse", "HEAD"],
        stderr=subprocess.DEVNULL,
    ).decode().strip()
except Exception:
    sha = "unknown"

baseline = {
    "captured_at": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None).isoformat() + "Z",
    "labeled_set_size": len(labeled),
    "labeled_set_positives": len(labeled_positives),
    "labeled_set_negatives": len(labeled_negatives),
    "baseline_team_digest_sha": sha,
    "matches_source": matches_path,
    "per_strategy": per_strategy,
    "overall": {
        "tp": tp, "fp": fp, "fn": fn,
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "f1": round(f1, 4),
    },
}

with open(out_path, "w") as f:
    json.dump(baseline, f, indent=2)

print(f"Baseline written: precision={precision:.4f} recall={recall:.4f} f1={f1:.4f}")
print(f"  Strategies: " + ", ".join(
    f"{s}=f1:{per_strategy[s]['f1']:.2f}/p:{per_strategy[s]['precision']:.2f}/r:{per_strategy[s]['recall']:.2f}"
    for s in ["mech_a", "mech_b", "s2", "s3", "s4"]
))

# Phase 1 acceptance gate
ok_recall = recall >= 0.7
ok_missed = fn <= 5
if ok_recall and ok_missed:
    print(f"Phase 1 acceptance: PASS (recall {recall:.2f} >= 0.7 AND missed {fn} <= 5)")
else:
    reasons = []
    if not ok_recall:
        reasons.append(f"recall {recall:.2f} < 0.7")
    if not ok_missed:
        reasons.append(f"missed {fn} >= 5")
    print(f"Phase 1 acceptance: FAIL ({'; '.join(reasons)}) - Phase 2 (Strategy 4) is unlocked", file=sys.stderr)
PY
    ;;

  --current-only)
    DRY_RUN_OUTPUT="${1:-}"
    if [ -n "$DRY_RUN_OUTPUT" ]; then
      MATCHES_JSON="${DRY_RUN_OUTPUT%.md}-matches.json"
    else
      MATCHES_JSON=""
    fi
    if [ -n "$MATCHES_JSON" ] && [ -f "$MATCHES_JSON" ]; then
      MATCHES_JSON="$MATCHES_JSON" CURRENT_FILE="$CURRENT_FILE" python3 - <<'PY'
import datetime, json, os

matches_path = os.environ["MATCHES_JSON"]
out_path = os.environ["CURRENT_FILE"]
with open(matches_path) as f:
    matches = json.load(f)

dist = {}
for strategy in ["mech_a", "mech_b", "s2", "s3", "s4", "s3_skipped"]:
    by_conf = {}
    for m in matches:
        srcs = m.get("sources") or []
        present = (strategy in srcs) or (strategy == "s2" and (("s2_in_tag" in srcs) or ("s2_in_body" in srcs)))
        if not present:
            continue
        per = (m.get("per_source") or {}).get(strategy, {})
        c = per.get("confidence", m.get("confidence", "unknown"))
        by_conf[c] = by_conf.get(c, 0) + 1
    if by_conf:
        dist[strategy] = by_conf

current = {
    "captured_at": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None).isoformat() + "Z",
    "matches_source": matches_path,
    "per_strategy_match_counts": dist,
}
with open(out_path, "w") as f:
    json.dump(current, f, indent=2)
print(f"Current snapshot written: {dist}")
PY
    fi
    # Baseline-age warn
    if [ -f "$BASELINE_FILE" ]; then
      BASELINE_FILE="$BASELINE_FILE" python3 - <<'PY'
import datetime, json, os, sys
b = json.load(open(os.environ["BASELINE_FILE"]))
b_at = datetime.datetime.fromisoformat(b["captured_at"].rstrip("Z"))
age_days = (datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) - b_at).days
if age_days > 180:
    print(f"[WARN] HIP calibration baseline is {age_days} days old (> 6 months). Consider re-running `calibrate-hip-matches.sh --baseline <dry-run>`.", file=sys.stderr)
PY
    fi
    ;;

  *)
    echo "ERROR: unknown mode: $MODE" >&2
    echo "Usage: $0 --baseline <dry-run-output> | --current-only [dry-run-output]" >&2
    exit 1
    ;;
esac
