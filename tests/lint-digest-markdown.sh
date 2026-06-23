#!/usr/bin/env bash
# lint-digest-markdown.sh [--template] <file.md> - structural lint for Notion-flavored
# digest output. Catches the Notion API hard constraints the skills must satisfy.
# Offline; no network. Usable on any tier's dry-run safety file (daily / weekly / monthly).
#
# --template mode skips the three checks that legitimately fire on TEMPLATE.md files:
#   #3 shortcode-emoji (templates DOCUMENT ":shortcode:" in their FORMAT RULES),
#   #4 bold+code collision (templates document the **`code`** anti-pattern), and
#   #5 footer-last (templates end with FORMAT RULES, not a footer callout).
#   #6 section headings (templates document the wrong form as an anti-example),
#   #7 Keyword Monitor table (templates reference table format in FORMAT RULES).
# In --template mode only the structural checks #1, #2, #8, #9 run.
set -uo pipefail
TEMPLATE=0
if [ "${1:-}" = "--template" ]; then TEMPLATE=1; shift; fi
F="${1:?usage: lint-digest-markdown.sh [--template] <file.md>}"
[ -f "$F" ] || { echo "ERROR: no such file: $F" >&2; exit 2; }
ERR=0

# 1. Callouts must be single-line: an opening <callout ...> must have its closing
#    </callout> on the SAME line.
while IFS= read -r line; do
  case "$line" in
    *"<callout"*)
      case "$line" in *"</callout>"*) : ;; *) echo "FAIL: multi-line callout: $line"; ERR=1 ;; esac ;;
  esac
done < "$F"
# A bare </callout> on its own line is the tell-tale of a split callout.
if grep -qE '^[[:space:]]*</callout>[[:space:]]*$' "$F"; then echo "FAIL: stray </callout> on its own line"; ERR=1; fi

# 2. No literal backslash-n inside mermaid labels (checked across mermaid fences).
awk '
  /```mermaid/ {inm=1; next}
  /```/ {inm=0}
  inm && /\\n/ {print "FAIL: literal \\n inside mermaid label: " $0; e=1}
  END {exit e?1:0}
' "$F" || ERR=1

# 3. No :shortcode: emoji (Notion rejects them). Skipped for templates.
if [ "$TEMPLATE" -eq 0 ] && grep -nE ':[a-z_]+:' "$F" | grep -vE 'https?:' >/dev/null; then
  echo "FAIL: :shortcode: emoji present (use Unicode):"; grep -nE ':[a-z_]+:' "$F" | grep -vE 'https?:' | head; ERR=1
fi

# 4. Bold-immediately-followed-by-backtick collision (**`). Skipped for templates.
if [ "$TEMPLATE" -eq 0 ] && grep -nF '**`' "$F" >/dev/null; then echo "FAIL: bold+code collision (**\`):"; grep -nF '**`' "$F" | head; ERR=1; fi

# 5. Footer callout must be the LAST non-empty block. Skipped for templates.
if [ "$TEMPLATE" -eq 0 ]; then
  LASTBLOCK="$(grep -vE '^[[:space:]]*$' "$F" | tail -1)"
  case "$LASTBLOCK" in
    *"Auto-generated"*"</callout>"*) : ;;
    *) echo "FAIL: last block is not the auto-generated footer callout: $LASTBLOCK"; ERR=1 ;;
  esac
fi

# 6. Section headings must use the correct H-level. Skipped for templates.
# "Notion Keyword Monitor" must be H1 (# ), never H2 or H3.
if [ "$TEMPLATE" -eq 0 ]; then
  if grep -qE '^#{2,}[[:space:]]+.*Keyword Monitor' "$F"; then
    echo "FAIL: 'Notion Keyword Monitor' heading must be H1 (# 🔎 Notion Keyword Monitor) — found:"
    grep -nE '^#{2,}[[:space:]]+.*Keyword Monitor' "$F"
    ERR=1
  fi
fi

# 7. Keyword Monitor section must not contain a <table> tag (narrative format required).
# Skipped for templates (FORMAT RULES section documents the table anti-example).
if [ "$TEMPLATE" -eq 0 ]; then
  awk '
    /^# .* Notion Keyword Monitor/ { in_km=1; next }
    /^#[^#]/ { in_km=0 }
    in_km && /<table/ { print "FAIL: <table> found inside Keyword Monitor section — use narrative paragraphs, not a table (line " NR "): " $0; e=1 }
    END { exit e?1:0 }
  ' "$F" || ERR=1
fi

# 8. Unbalanced </table> tags mean stray closers from old Keyword Monitor table format or a split table.
_table_opens=$(grep -o '<table' "$F" | wc -l | tr -d ' ')
_table_closes=$(grep -o '</table>' "$F" | wc -l | tr -d ' ')
if [ "$_table_closes" -gt "$_table_opens" ]; then
  echo "FAIL: unbalanced table tags: $_table_opens <table openers vs $_table_closes </table> closers (stray </table> — check Keyword Monitor uses narrative format, not a table)"
  ERR=1
fi

# 9. <details><summary> must be on SEPARATE lines. The Notion MCP backslash-escapes
#    the < when both are on the same line, rendering the toggle as literal text.
if grep -qE '<details><summary>' "$F"; then
  echo "FAIL: <details><summary> on the same line — put <details> and <summary> on separate lines:"
  grep -nE '<details><summary>' "$F" | head
  ERR=1
fi

[ "$ERR" -eq 0 ] && echo "OK: $F passes digest-markdown lint"
exit "$ERR"
