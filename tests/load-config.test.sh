#!/usr/bin/env bash
# Unit tests for skills/team-digest/lib/load-config.sh (read + validate config).
# Pure (no network). Uses TEAM_DIGEST_CONFIG to point at fixture configs.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib-assert.sh"
H="$(cd "$DIR/.." && pwd)/skills/team-digest/lib/load-config.sh"

TMP="$(mktemp -d /tmp/team-digest-test-cfg.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

VALID="$TMP/valid.json"
cat > "$VALID" <<'JSON'
{
  "team-digest": {
    "notion": { "config_page_id": "abc123def456abc123def456abc123de", "database_id": "111122223333444455556666777788ab" },
    "github": { "orgs": [ { "name": "acme", "priority_repos": [], "scan_all": true } ] },
    "defaults": { "keywords": ["x"], "partner_patterns": ["Meeting with"] }
  }
}
JSON

EMPTYIDS="$TMP/emptyids.json"
cat > "$EMPTYIDS" <<'JSON'
{ "team-digest": { "notion": { "config_page_id": "", "database_id": "" } } }
JSON

BADJSON="$TMP/bad.json"
printf '{ this is not valid json ' > "$BADJSON"

# --- Valid config: exit 0, emits the digest object ---
out=$(TEAM_DIGEST_CONFIG="$VALID" bash "$H" team-digest); code=$?
assert_eq "valid config exits 0" "0" "$code"
assert_contains "valid config emits config_page_id" "abc123def456abc123def456abc123de" "$out"
assert_contains "valid config emits database_id"    "111122223333444455556666777788ab" "$out"

# --- Missing config file -> exit 1 ---
TEAM_DIGEST_CONFIG="$TMP/does-not-exist.json" bash "$H" team-digest >/dev/null 2>&1
assert_eq "missing config file -> exit 1" "1" "$?"

# --- Malformed JSON -> exit 2 ---
TEAM_DIGEST_CONFIG="$BADJSON" bash "$H" team-digest >/dev/null 2>&1
assert_eq "malformed JSON -> exit 2" "2" "$?"

# --- Requested digest key absent -> exit 3 ---
TEAM_DIGEST_CONFIG="$VALID" bash "$H" no-such-digest >/dev/null 2>&1
assert_eq "missing digest key -> exit 3" "3" "$?"

# --- Empty Notion IDs -> exit 4 ---
TEAM_DIGEST_CONFIG="$EMPTYIDS" bash "$H" team-digest >/dev/null 2>&1
assert_eq "empty Notion IDs -> exit 4" "4" "$?"

# --- Missing digest-name arg -> non-zero (usage guard) ---
TEAM_DIGEST_CONFIG="$VALID" bash "$H" >/dev/null 2>&1
code=$?
if [ "$code" -ne 0 ]; then pass "missing digest-name arg errors"; else fail "missing digest-name arg errors" "expected non-zero"; fi

summary
