#!/usr/bin/env bash
# Unit tests for skills/team-digest/lib/calibrate-hip-matches.sh.
# Pure (no network). Uses TEAM_DIGEST_LABELED_SET / TEAM_DIGEST_CALIBRATION_BASELINE /
# TEAM_DIGEST_CALIBRATION_CURRENT env overrides so it reads fixtures and writes to a
# temp dir - never touching real ~/.config calibration state.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib-assert.sh"
H="$(cd "$DIR/.." && pwd)/skills/team-digest/lib/calibrate-hip-matches.sh"

TMP="$(mktemp -d /tmp/td-test-cal.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

LABELED="$TMP/labeled.json"
BASE="$TMP/baseline.json"
CUR="$TMP/current.json"

# Labeled set:
#   HIP-1/r1/1: impl=true,  useful=true   (TP if matched)
#   HIP-2/r2/2: impl=false, useful=true   (impl NEGATIVE; useful POSITIVE) - the HIP-doc-update case
#   HIP-3/r3/3: impl=true,  useful=true   (a positive we do NOT match -> FN)
cat > "$LABELED" <<'JSON'
[
  {"hip_id":"HIP-1","repo":"r1","pr_number":1,"is_implementation":true,"is_useful_signal":true,"pr_merged_at":"2026-05-05"},
  {"hip_id":"HIP-2","repo":"r2","pr_number":2,"is_implementation":false,"is_useful_signal":true,"pr_merged_at":"2026-05-05"},
  {"hip_id":"HIP-3","repo":"r3","pr_number":3,"is_implementation":true,"is_useful_signal":true,"pr_merged_at":"2026-05-05"}
]
JSON

# Matches found by the strategies (the dry-run's companion -matches.json):
#   HIP-1/r1/1 via mech_a ; HIP-2/r2/2 via s2_in_tag (aliases to s2).
DRY="$TMP/run.md"; : > "$DRY"
cat > "$TMP/run-matches.json" <<'JSON'
[
  {"hip_id":"HIP-1","repo":"r1","pr_number":1,"confidence":"high","sources":["mech_a"],"per_source":{"mech_a":{"confidence":"high"}}},
  {"hip_id":"HIP-2","repo":"r2","pr_number":2,"confidence":"high","sources":["s2_in_tag"],"per_source":{"s2_in_tag":{"confidence":"high"}}}
]
JSON

field() { python3 -c "import json,sys; print(json.load(sys.stdin)$1)"; }
fieldf() { python3 -c "import json; print(json.load(open('$1'))$2)"; }

run_baseline() { TEAM_DIGEST_LABELED_SET="$LABELED" TEAM_DIGEST_CALIBRATION_BASELINE="$BASE" bash "$H" --baseline "$DRY" "$@" >/dev/null 2>&1; }

# --- Baseline over the full set (no window) ---
run_baseline
assert_eq "baseline file is written" "yes" "$( [ -f "$BASE" ] && echo yes || echo no )"

# useful_signal lens: positives={1,2,3}, matched={1,2} -> tp=2, fn=1, fp=0
assert_eq "useful_signal tp" "2" "$(fieldf "$BASE" "['lenses']['useful_signal']['overall']['tp']")"
assert_eq "useful_signal fn" "1" "$(fieldf "$BASE" "['lenses']['useful_signal']['overall']['fn']")"
assert_eq "useful_signal fp" "0" "$(fieldf "$BASE" "['lenses']['useful_signal']['overall']['fp']")"
assert_eq "useful_signal precision 1.0" "1.0" "$(fieldf "$BASE" "['lenses']['useful_signal']['overall']['precision']")"

# implementation lens: positives={1,3}, negatives={2}, matched={1,2} -> tp=1, fn=1, fp=1
assert_eq "implementation tp" "1" "$(fieldf "$BASE" "['lenses']['implementation']['overall']['tp']")"
assert_eq "implementation fn" "1" "$(fieldf "$BASE" "['lenses']['implementation']['overall']['fn']")"
assert_eq "implementation fp (HIP-doc-update matched)" "1" "$(fieldf "$BASE" "['lenses']['implementation']['overall']['fp']")"

# s2_in_tag must alias to the s2 strategy bucket.
assert_eq "s2 strategy sees the s2_in_tag match (tp=1)" "1" "$(fieldf "$BASE" "['lenses']['useful_signal']['per_strategy']['s2']['tp']")"
assert_eq "mech_a strategy tp=1" "1" "$(fieldf "$BASE" "['lenses']['useful_signal']['per_strategy']['mech_a']['tp']")"

# --- Window filter: restrict to a window that EXCLUDES the May-05 merges ---
run_baseline --window-start 2026-06-01 --window-end 2026-06-30
# All labeled positives fall outside -> 0 positives -> tp=0, fn=0
assert_eq "window excludes all -> useful_signal tp=0" "0" "$(fieldf "$BASE" "['lenses']['useful_signal']['overall']['tp']")"
assert_eq "window active flag recorded" "True" "$(fieldf "$BASE" "['window_active']")"

# --- --current-only writes the distribution snapshot ---
TEAM_DIGEST_CALIBRATION_CURRENT="$CUR" TEAM_DIGEST_CALIBRATION_BASELINE="$TMP/none.json" bash "$H" --current-only "$DRY" >/dev/null 2>&1
assert_eq "current snapshot written" "yes" "$( [ -f "$CUR" ] && echo yes || echo no )"
assert_eq "current: mech_a high count = 1" "1" "$(fieldf "$CUR" "['per_strategy_match_counts']['mech_a']['high']")"
assert_eq "current: s2 high count = 1 (s2_in_tag aliased)" "1" "$(fieldf "$CUR" "['per_strategy_match_counts']['s2']['high']")"

# --- Error cases ---
TEAM_DIGEST_LABELED_SET="$TMP/no-labeled.json" TEAM_DIGEST_CALIBRATION_BASELINE="$BASE" bash "$H" --baseline "$DRY" >/dev/null 2>&1
assert_eq "missing labeled set -> exit 1" "1" "$?"
TEAM_DIGEST_LABELED_SET="$LABELED" TEAM_DIGEST_CALIBRATION_BASELINE="$BASE" bash "$H" --baseline "$TMP/no-such-run.md" >/dev/null 2>&1
assert_eq "missing matches json -> exit 1" "1" "$?"
bash "$H" --bogus-mode >/dev/null 2>&1
assert_eq "unknown mode -> exit 1" "1" "$?"

summary
