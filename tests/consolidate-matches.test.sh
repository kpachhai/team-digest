#!/usr/bin/env bash
# Unit tests for skills/team-digest/lib/consolidate-matches.sh.
# This is the helper that replaced a lossy in-Claude merge; the dedup +
# MAX-confidence behavior is the thing we most want to lock down.
# Pure (no network).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib-assert.sh"
H="$(cd "$DIR/.." && pwd)/skills/team-digest/lib/consolidate-matches.sh"

# field <python-expr-over-d> : read JSON array from stdin, print expr
field() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

# --- Non-existent dir -> [] ---
out=$(bash "$H" /tmp/team-digest-test-nodir-$$)
assert_eq "non-existent dir -> []" "[]" "$out"

# --- Empty dir (no JSON) -> [] ---
EMPTY="$(mktemp -d /tmp/td-test-empty.XXXXXX)"
out=$(bash "$H" "$EMPTY")
assert_eq "empty dir -> []" "[]" "$out"
rmdir "$EMPTY"

# --- Build a fixture matches dir ---
MD="$(mktemp -d /tmp/td-test-matches.XXXXXX)"
trap 'rm -rf "$MD"' EXIT

# mech_a sidecar: HIP-1137 / foo / PR 100 at MEDIUM, plus HIP-1140 / bar / PR 200 at low.
cat > "$MD/mech_a-prs-acme.json" <<'JSON'
[
  {"hip_id":"HIP-1137","repo":"hiero-ledger/foo","pr_number":100,"confidence":"medium","sources":["mech_a"],"per_source":{"mech_a":{"confidence":"medium"}},"pr_title":"foo work"},
  {"hip_id":"HIP-1140","repo":"hiero-ledger/bar","pr_number":200,"confidence":"low","sources":["mech_a"],"per_source":{"mech_a":{"confidence":"low"}}}
]
JSON

# strategy2 sidecar: SAME (HIP-1137, foo, 100) but HIGH from a different source -> must merge.
cat > "$MD/strategy2.json" <<'JSON'
[
  {"hip_id":"HIP-1137","repo":"hiero-ledger/foo","pr_number":100,"confidence":"high","sources":["s2"],"per_source":{"s2":{"confidence":"high","reason":"in_tag"}}}
]
JSON

# Mech B dict shape: {hip, prs:[...]} -> lifted to MatchRecords.
cat > "$MD/mech_b.json" <<'JSON'
{"hip":1200,"prs":[{"repo":"hiero-ledger/baz","number":300,"confidence":"high","source":"mech_b","pr_title":"baz"}],"commits":[]}
JSON

# A record missing hip_id -> must be dropped by normalize_record.
cat > "$MD/junk.json" <<'JSON'
[ {"repo":"hiero-ledger/qux","pr_number":999,"confidence":"high"} ]
JSON

# A record with null pr_number -> normalized to 0.
cat > "$MD/nullpr.json" <<'JSON'
[ {"hip_id":"HIP-1300","repo":"hiero-ledger/zed","pr_number":null,"confidence":"low"} ]
JSON

out=$(bash "$H" "$MD")

# 4 distinct keys survive: (1137,foo,100 merged), (1140,bar,200), (1200,baz,300), (1300,zed,0).
n=$(echo "$out" | field "len(d)")
assert_eq "dedup -> 4 distinct records (junk dropped, 1137 merged)" "4" "$n"

# The merged 1137/foo/100 record: MAX confidence high, sources unioned + sorted.
conf=$(echo "$out" | field "[r for r in d if r['hip_id']=='HIP-1137'][0]['confidence']")
assert_eq "collision -> MAX confidence (high)" "high" "$conf"
srcs=$(echo "$out" | field "','.join([r for r in d if r['hip_id']=='HIP-1137'][0]['sources'])")
assert_eq "collision -> sources unioned + sorted" "mech_a,s2" "$srcs"
psrc=$(echo "$out" | field "sorted([r for r in d if r['hip_id']=='HIP-1137'][0]['per_source'].keys())")
assert_contains "collision -> per_source has both strategies" "'mech_a', 's2'" "$psrc"

# Mech B dict was lifted correctly.
mb=$(echo "$out" | field "[r for r in d if r['hip_id']=='HIP-1200'][0]['pr_number']")
assert_eq "mech_b dict lifted: number -> pr_number" "300" "$mb"

# null pr_number normalized to 0.
np=$(echo "$out" | field "[r for r in d if r['hip_id']=='HIP-1300'][0]['pr_number']")
assert_eq "null pr_number -> 0" "0" "$np"

# Output is sorted by (hip_id, repo, pr_number).
order=$(echo "$out" | field "[r['hip_id'] for r in d]")
assert_eq "records sorted by hip_id" "['HIP-1137', 'HIP-1140', 'HIP-1200', 'HIP-1300']" "$order"

# --- Output to a file path also works ---
OUTF="$MD/out.json"
bash "$H" "$MD" "$OUTF" 2>/dev/null
fn=$(python3 -c "import json;print(len(json.load(open('$OUTF'))))")
assert_eq "writes to output file" "4" "$fn"

summary
