#!/usr/bin/env bash
# phase2-gate.sh - Iteration 2 Phase 2 (Strategy 4) gate decision.
#
# Reads ~/.config/team-digest/hip-calibration-baseline.json (produced by
# calibrate-hip-matches.sh --baseline) and applies the OR rule:
#
#   TRIGGER Phase 2 if  recall < 0.7  OR  missed >= 5
#
# Writes the decision to ~/.config/team-digest/iteration-2-phase2-decision.json
# with timestamp + the metrics used. Prints the decision to stdout.
#
# If no baseline exists yet, writes a DEFERRED_AWAITING_BASELINE decision
# so the file is always present (downstream tooling can read it without
# null-checks). Re-run after each baseline refresh.

set -euo pipefail

BASELINE_FILE="$HOME/.config/team-digest/hip-calibration-baseline.json"
DECISION_FILE="$HOME/.config/team-digest/iteration-2-phase2-decision.json"

mkdir -p "$(dirname "$DECISION_FILE")"

if [ ! -f "$BASELINE_FILE" ]; then
  BASELINE_FILE="$BASELINE_FILE" DECISION_FILE="$DECISION_FILE" python3 - <<'PY'
import datetime, json, os
out = {
    "decided_at": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None).isoformat() + "Z",
    "decision": "DEFERRED_AWAITING_BASELINE",
    "rule": "OR(recall < 0.7, missed >= 5)",
    "reason": ("No baseline exists at " + os.environ["BASELINE_FILE"] + " yet. "
               "Run `/team-digest <date> --dry-run` then "
               "`bash skills/team-digest/lib/calibrate-hip-matches.sh --baseline <dry-run-output>` "
               "to produce the baseline, then re-run this gate."),
}
with open(os.environ["DECISION_FILE"], "w") as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
PY
  exit 0
fi

BASELINE_FILE="$BASELINE_FILE" DECISION_FILE="$DECISION_FILE" python3 - <<'PY'
import datetime, json, os, sys

with open(os.environ["BASELINE_FILE"]) as f:
    baseline = json.load(f)

# Iteration 3: baseline schema gained a "lenses" object. Gate decision uses
# the useful_signal lens (broader than implementation; better aligned with
# what the digest actually surfaces). Back-compat: fall through to the
# pre-iter3 "overall" shape if "lenses" is absent.
if "lenses" in baseline and "useful_signal" in baseline["lenses"]:
    lens_used = "useful_signal"
    overall = baseline["lenses"]["useful_signal"]["overall"]
elif "overall" in baseline:
    lens_used = "legacy_overall"
    overall = baseline["overall"]
else:
    print("ERROR: baseline JSON has neither 'lenses.useful_signal' nor 'overall'", file=sys.stderr)
    sys.exit(1)

recall = overall["recall"]
missed = overall["fn"]
trigger = (recall < 0.7) or (missed >= 5)

out = {
    "decided_at": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None).isoformat() + "Z",
    "decision": "TRIGGER" if trigger else "DEFER",
    "rule": "OR(recall < 0.7, missed >= 5)",
    "lens_used": lens_used,
    "recall_at_decision": recall,
    "missed_at_decision": missed,
    "window_start": baseline.get("window_start"),
    "window_end": baseline.get("window_end"),
    "window_active": baseline.get("window_active", False),
    "baseline_captured_at": baseline.get("captured_at"),
    "baseline_team_digest_sha": baseline.get("baseline_team_digest_sha"),
    "reason": (
        f"Phase 1 met acceptance criteria on the {lens_used} lens "
        f"(recall {recall:.2f} >= 0.7 AND missed {missed} <= 5). "
        f"Strategy 4 deferred-with-evidence."
        if not trigger else
        f"Phase 1 missed acceptance on the {lens_used} lens ("
        + (f"recall {recall:.2f} < 0.7" if recall < 0.7 else "")
        + (" AND " if (recall < 0.7 and missed >= 5) else "")
        + (f"missed {missed} >= 5" if missed >= 5 else "")
        + "). Strategy 4 (Phase 2) is unlocked."
    ),
}
with open(os.environ["DECISION_FILE"], "w") as f:
    json.dump(out, f, indent=2)
print(json.dumps(out, indent=2))
PY
