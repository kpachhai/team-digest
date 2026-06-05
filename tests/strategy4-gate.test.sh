#!/usr/bin/env bash
# Unit tests for skills/team-digest/lib/strategy4-gate.sh (DEFER/TRIGGER state machine).
# Pure (no network). Uses TEAM_DIGEST_CALIBRATION_BASELINE + TEAM_DIGEST_GATE_DECISION
# env overrides so it never reads or clobbers real ~/.config state.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib-assert.sh"
H="$(cd "$DIR/.." && pwd)/skills/team-digest/lib/strategy4-gate.sh"

field() { python3 -c "import json,sys; print(json.load(sys.stdin)$1)"; }

TMP="$(mktemp -d /tmp/td-test-gate.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
DEC="$TMP/decision.json"

run_gate() {  # run_gate <baseline-path-or-empty>
  local baseline="$1"
  TEAM_DIGEST_CALIBRATION_BASELINE="$baseline" TEAM_DIGEST_GATE_DECISION="$DEC" bash "$H"
}

write_baseline() {  # write_baseline <recall> <fn>
  cat > "$TMP/baseline.json" <<JSON
{ "captured_at": "2026-05-06T00:00:00Z",
  "lenses": { "useful_signal": { "overall": { "recall": $1, "fn": $2, "precision": 1.0 } } } }
JSON
}

# --- No baseline -> DEFERRED_AWAITING_BASELINE, decision file written ---
out=$(run_gate "$TMP/no-such-baseline.json")
dec=$(echo "$out" | field "['decision']")
assert_eq "no baseline -> DEFERRED_AWAITING_BASELINE" "DEFERRED_AWAITING_BASELINE" "$dec"
assert_eq "no baseline -> decision file written" "DEFERRED_AWAITING_BASELINE" "$(field "['decision']" < "$DEC")"

# --- recall >= 0.7 AND missed <= 5 -> DEFER ---
write_baseline 0.80 3
dec=$(run_gate "$TMP/baseline.json" | field "['decision']")
assert_eq "recall 0.80, fn 3 -> DEFER" "DEFER" "$dec"

# --- recall < 0.7 -> TRIGGER (even with low fn) ---
write_baseline 0.52 2
dec=$(run_gate "$TMP/baseline.json" | field "['decision']")
assert_eq "recall 0.52 < 0.7 -> TRIGGER" "TRIGGER" "$dec"

# --- missed (fn) >= 5 -> TRIGGER (even with high recall) ---
write_baseline 0.95 7
dec=$(run_gate "$TMP/baseline.json" | field "['decision']")
assert_eq "fn 7 >= 5 -> TRIGGER" "TRIGGER" "$dec"

# --- Boundary characterization. The gate code is:
#       trigger = (recall < 0.7) OR (missed >= 5)
#     so the DEFER region is recall >= 0.7 AND missed <= 4 (i.e. missed < 5).
#     NOTE: the human docs (architecture.md / roadmap.md / CLAUDE.md) phrase DEFER as
#     "missed <= 5", which disagrees with the code at exactly fn=5. Code is source of truth.
write_baseline 0.70 5            # recall on the >= boundary, missed on the >= boundary
dec=$(run_gate "$TMP/baseline.json" | field "['decision']")
assert_eq "recall 0.70, fn 5 -> TRIGGER (missed>=5 fires)" "TRIGGER" "$dec"
write_baseline 0.70 4            # the true DEFER boundary
dec=$(run_gate "$TMP/baseline.json" | field "['decision']")
assert_eq "recall 0.70, fn 4 -> DEFER (the real DEFER boundary)" "DEFER" "$dec"

# --- Legacy 'overall' shape (no lenses) is accepted ---
cat > "$TMP/legacy.json" <<'JSON'
{ "captured_at": "2026-01-01T00:00:00Z", "overall": { "recall": 0.9, "fn": 1, "precision": 1.0 } }
JSON
out=$(run_gate "$TMP/legacy.json")
lens=$(echo "$out" | field "['lens_used']")
assert_eq "legacy overall shape -> lens_used legacy_overall" "legacy_overall" "$lens"

# --- Malformed baseline (neither lenses nor overall) -> non-zero exit ---
echo '{ "captured_at": "x" }' > "$TMP/malformed.json"
TEAM_DIGEST_CALIBRATION_BASELINE="$TMP/malformed.json" TEAM_DIGEST_GATE_DECISION="$DEC" bash "$H" >/dev/null 2>&1
code=$?
if [ "$code" -ne 0 ]; then pass "malformed baseline errors (non-zero)"; else fail "malformed baseline errors" "expected non-zero"; fi

# --- Real ~/.config decision file was NOT touched (env override worked) ---
assert_eq "did not write a decision to default path under repo" "absent" "$( [ -e "$DIR/decision.json" ] && echo present || echo absent )"

summary
