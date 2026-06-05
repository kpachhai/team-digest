#!/usr/bin/env bash
# lint-digest-markdown.sh [--template] <file.md> - structural lint for Notion-flavored
# digest output. Catches the Notion API hard constraints the skills must satisfy.
# Offline; no network. Usable on any tier's dry-run safety file (daily / weekly / monthly).
#
# --template mode skips the three checks that legitimately fire on TEMPLATE.md files:
#   #3 shortcode-emoji (templates DOCUMENT ":shortcode:" in their FORMAT RULES),
#   #4 bold+code collision (templates document the **`code`** anti-pattern), and
#   #5 footer-last (templates end with FORMAT RULES, not a footer callout).
# In --template mode only the structural example checks (#1 callout single-line,
# #2 mermaid \n) run.
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

[ "$ERR" -eq 0 ] && echo "OK: $F passes digest-markdown lint"
exit "$ERR"
