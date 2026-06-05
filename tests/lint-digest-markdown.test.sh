#!/usr/bin/env bash
# Self-test for tests/lint-digest-markdown.sh - confirms the linter passes valid
# digest pages, fails malformed ones, and handles --template. Pure (no network).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib-assert.sh"
LINT="$DIR/lint-digest-markdown.sh"
ROOT="$(cd "$DIR/.." && pwd)"

# --- Valid full pages pass full lint (exit 0) ---
bash "$LINT" "$DIR/fixtures/sample-monthly-output.md" >/dev/null 2>&1
assert_eq "sample monthly passes full lint" "0" "$?"
bash "$LINT" "$DIR/fixtures/month-2026-05/weekly-2026-W19.md" >/dev/null 2>&1
assert_eq "weekly fixture passes full lint" "0" "$?"

# --- Templates pass only in --template mode ---
for t in team-digest team-weekly team-monthly; do
  bash "$LINT" --template "$ROOT/skills/$t/TEMPLATE.md" >/dev/null 2>&1
  assert_eq "$t TEMPLATE passes --template lint" "0" "$?"
done

# --- Malformed pages fail (exit 1) ---
BAD="$(mktemp /tmp/td-test-badlint.XXXXXX.md)"
# multi-line callout + missing proper footer
printf '<callout icon="x">broken\n</callout>\nAuto-generated </callout>\n' > "$BAD"
bash "$LINT" "$BAD" >/dev/null 2>&1
assert_eq "multi-line callout fails" "1" "$?"

# :shortcode: emoji must fail full lint
printf '<callout icon="rocket">hi :rocket: there</callout>\n<callout>**Auto-generated** x</callout>\n' > "$BAD"
bash "$LINT" "$BAD" >/dev/null 2>&1
assert_eq ":shortcode: emoji fails" "1" "$?"

# missing footer callout as last block must fail
printf '<callout icon="x">ok line</callout>\n\nsome trailing prose not a footer\n' > "$BAD"
bash "$LINT" "$BAD" >/dev/null 2>&1
assert_eq "missing footer-last fails" "1" "$?"
rm -f "$BAD"

# --- Missing file -> exit 2 (usage error, distinct from lint failure) ---
bash "$LINT" /tmp/td-test-no-such-file-$$.md >/dev/null 2>&1
assert_eq "missing file -> exit 2" "2" "$?"

summary
