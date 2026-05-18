#!/usr/bin/env bash
# calibrate-hip-matches.sh - Measure precision/recall/F1 of HIP-to-code
# matching strategies against the strategy-independent labeled set.
#
# Two modes:
#
#   calibrate-hip-matches.sh --baseline <dry-run-output-file>
#     Reads ~/.config/team-digest/hip-code-mapper-labeled-set.json + the
#     <dry-run-output-file>'s companion <...>-matches.json. Computes
#     precision/recall/F1 per strategy AND overall. Writes
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
    shift
    WINDOW_START=""
    WINDOW_END=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --window-start) WINDOW_START="${2:?--window-start requires YYYY-MM-DD}"; shift 2 ;;
        --window-end)   WINDOW_END="${2:?--window-end requires YYYY-MM-DD}"; shift 2 ;;
        *) echo "ERROR: unknown --baseline arg: $1" >&2; exit 1 ;;
      esac
    done
    if [ ! -f "$LABELED_SET" ]; then
      echo "ERROR: labeled set not found at $LABELED_SET; build it first (see docs/hip-tracking.md Calibration section)" >&2
      exit 1
    fi
    MATCHES_JSON="${DRY_RUN_OUTPUT%.md}-matches.json"
    if [ ! -f "$MATCHES_JSON" ]; then
      echo "ERROR: matches JSON not found at $MATCHES_JSON. The wrapper emits this file alongside the dry-run safety file via consolidate-matches.sh; ensure the dry-run completed successfully." >&2
      exit 1
    fi
    LABELED_SET="$LABELED_SET" \
    MATCHES_JSON="$MATCHES_JSON" \
    BASELINE_FILE="$BASELINE_FILE" \
    WINDOW_START="$WINDOW_START" \
    WINDOW_END="$WINDOW_END" \
    TARGET_REPO="$(cd "$(dirname "$0")/../../.." && pwd)" \
    python3 - <<'PY'
import datetime, json, os, subprocess, sys

labeled_path = os.environ["LABELED_SET"]
matches_path = os.environ["MATCHES_JSON"]
out_path = os.environ["BASELINE_FILE"]
target_repo = os.environ["TARGET_REPO"]
window_start = os.environ.get("WINDOW_START") or None
window_end = os.environ.get("WINDOW_END") or None
window_active = bool(window_start and window_end)

with open(labeled_path) as f:
    labeled_all = [e for e in json.load(f) if "_meta" not in e]

with open(matches_path) as f:
    matches = json.load(f)


def in_window(entry):
    """Return True if the entry's pr_merged_at OR any
    attributed_to_releases date falls in the window. Entries without any
    date are treated as in-scope by default (back-compat).

    The attributed_to_releases list captures Strategy 2's semantic - a PR
    may have merged before the window but be attributed to a release
    published in the window. Without this, S2's true positives are
    systematically under-counted because pr_merged_at is too narrow."""
    if not window_active:
        return True
    candidate_dates = []
    merged_at = entry.get("pr_merged_at")
    if merged_at:
        candidate_dates.append(merged_at)
    attributions = entry.get("attributed_to_releases") or []
    for d in attributions:
        if d:
            candidate_dates.append(d)
    if not candidate_dates:
        return True  # back-compat: no date metadata -> assume in scope
    return any(window_start <= d <= window_end for d in candidate_dates)


# Two label sets per "lens":
#   - is_implementation: production-codebase code change (today's narrow def)
#   - is_useful_signal:  worth surfacing in the digest (broader; includes
#                         HIP-doc-update PRs which are signal but not impl)
# Each lens has its own positives + negatives + in-window filter.
def build_labels(lens_field):
    positives = set()
    negatives = set()
    for e in labeled_all:
        key = (e["hip_id"], e["repo"], int(e["pr_number"]))
        if not in_window(e):
            continue
        val = e.get(lens_field)
        if val is True:
            positives.add(key)
        elif val is False:
            negatives.add(key)
        # If lens_field is missing on this entry, skip (no opinion).
    return positives, negatives


def compute_metrics(strategy_keys, positives, negatives):
    tp = sum(1 for k in positives if k in strategy_keys)
    fn = sum(1 for k in positives if k not in strategy_keys)
    fp = sum(1 for k in strategy_keys if k in negatives)
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0
    return {"tp": tp, "fp": fp, "fn": fn,
            "precision": round(precision, 4),
            "recall": round(recall, 4),
            "f1": round(f1, 4)}


def collect_strategy_keys(matches, strategy):
    keys = set()
    for m in matches:
        srcs = m.get("sources") or []
        present = (strategy in srcs)
        if strategy == "s2":
            present = present or ("s2_in_tag" in srcs) or ("s2_in_body" in srcs)
        if present:
            keys.add((m["hip_id"], m["repo"], int(m.get("pr_number") or 0)))
    return keys


# Three views: full labeled set; per-lens (impl); per-lens (useful_signal).
lenses = {
    "implementation": ("is_implementation",),
    "useful_signal":  ("is_useful_signal",),
}

per_lens = {}
for lens_name, (field,) in lenses.items():
    positives, negatives = build_labels(field)
    per_strategy = {}
    for strategy in ["mech_a", "mech_b", "s2", "s3", "s4"]:
        s_keys = collect_strategy_keys(matches, strategy)
        per_strategy[strategy] = compute_metrics(s_keys, positives, negatives)
    all_keys = {(m["hip_id"], m["repo"], int(m.get("pr_number") or 0)) for m in matches}
    overall = compute_metrics(all_keys, positives, negatives)
    per_lens[lens_name] = {
        "lens_field": field,
        "positives_count": len(positives),
        "negatives_count": len(negatives),
        "per_strategy": per_strategy,
        "overall": overall,
    }

try:
    sha = subprocess.check_output(
        ["git", "-C", target_repo, "rev-parse", "HEAD"],
        stderr=subprocess.DEVNULL,
    ).decode().strip()
except Exception:
    sha = "unknown"

baseline = {
    "captured_at": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None).isoformat() + "Z",
    "labeled_set_size": len(labeled_all),
    "window_start": window_start,
    "window_end": window_end,
    "window_active": window_active,
    "baseline_team_digest_sha": sha,
    "matches_source": matches_path,
    "lenses": per_lens,
}

with open(out_path, "w") as f:
    json.dump(baseline, f, indent=2)

# Pretty-print
print(f"Baseline written to {out_path}")
print(f"  Window: {('[' + window_start + ', ' + window_end + ']') if window_active else '(full labeled set, no date filter)'}")
for lens_name, lens_data in per_lens.items():
    o = lens_data["overall"]
    print(f"  Lens '{lens_name}' ({lens_data['positives_count']} pos, {lens_data['negatives_count']} neg): "
          f"p={o['precision']:.2f} r={o['recall']:.2f} f1={o['f1']:.2f} (tp={o['tp']} fp={o['fp']} fn={o['fn']})")
    for s, m in lens_data["per_strategy"].items():
        if m["tp"] + m["fp"] + m["fn"] == 0:
            continue
        print(f"    {s:>8}: p={m['precision']:.2f} r={m['recall']:.2f} f1={m['f1']:.2f} (tp={m['tp']} fp={m['fp']} fn={m['fn']})")

# Acceptance gate: uses the broader useful_signal lens
useful = per_lens["useful_signal"]["overall"]
ok_recall = useful["recall"] >= 0.7
ok_missed = useful["fn"] <= 5
if ok_recall and ok_missed:
    print(f"Acceptance (useful_signal lens): PASS "
          f"(recall {useful['recall']:.2f} >= 0.7 AND missed {useful['fn']} <= 5)")
else:
    reasons = []
    if not ok_recall:
        reasons.append(f"recall {useful['recall']:.2f} < 0.7")
    if not ok_missed:
        reasons.append(f"missed {useful['fn']} >= 5")
    print(f"Acceptance (useful_signal lens): FAIL ({'; '.join(reasons)}) - Strategy 4 is unlocked", file=sys.stderr)
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
