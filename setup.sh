#!/usr/bin/env bash
set -euo pipefail

# team-digest setup script
# Installs all digest skills, creates config, and verifies prerequisites.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"
TEMPLATE_FILE="$SCRIPT_DIR/config.template.json"
GLOBAL_CONFIG_DIR="$HOME/.config/team-digest"
GLOBAL_CONFIG_FILE="$GLOBAL_CONFIG_DIR/config.json"

echo "=== team-digest Setup ==="
echo ""

# -------------------------------------------------------------------
# 1. Check prerequisites
# -------------------------------------------------------------------
MISSING=()

if ! command -v claude &>/dev/null; then
  MISSING+=("claude (Claude Code CLI - https://claude.ai/code)")
fi

if ! command -v gh &>/dev/null; then
  MISSING+=("gh (GitHub CLI - https://cli.github.com)")
else
  if ! gh auth status &>/dev/null 2>&1; then
    MISSING+=("gh auth (run: gh auth login)")
  fi
fi

if [ ${#MISSING[@]} -ne 0 ]; then
  echo "ERROR: Missing prerequisites:"
  for item in "${MISSING[@]}"; do
    echo "  - $item"
  done
  echo ""
  echo "Install the missing tools and re-run this script."
  exit 1
fi

echo "[OK] Claude Code CLI found ($(claude --version 2>/dev/null || echo 'unknown version'))"
echo "[OK] GitHub CLI found and authenticated"

# -------------------------------------------------------------------
# 2. Check Notion MCP connection
# -------------------------------------------------------------------
echo ""
echo "NOTE: The Notion MCP server must be connected in Claude Code."
echo "If not already connected, open Claude Code and connect it via:"
echo "  Settings > MCP Servers > Add > Notion"
echo ""

# -------------------------------------------------------------------
# 3. Handle config file
# -------------------------------------------------------------------
if [ -f "$CONFIG_FILE" ]; then
  echo "[OK] Local config exists at config.json"
else
  echo "[CREATED] Copying config.template.json -> config.json"
  cp "$TEMPLATE_FILE" "$CONFIG_FILE"
  echo ""
  echo "  *** ACTION REQUIRED ***"
  echo ""
  echo "  Edit config.json and fill in your Notion IDs for each digest."
  echo ""
  echo "  For each digest (e.g., da-digest), you need two Notion IDs:"
  echo "    - config_page_id : Notion config page ID"
  echo "    - database_id    : Notion database ID"
  echo ""
  echo "  Both are the 32-char hex string from the Notion page URL:"
  echo "    notion.so/<this-is-the-id>"
  echo ""
  echo "  If joining an existing team, ask a teammate for the IDs."
  echo ""
fi

# -------------------------------------------------------------------
# 4. Copy config to global location (skills read from here)
# -------------------------------------------------------------------
mkdir -p "$GLOBAL_CONFIG_DIR"
cp "$CONFIG_FILE" "$GLOBAL_CONFIG_FILE"
echo "[OK] Config synced to $GLOBAL_CONFIG_FILE"

# -------------------------------------------------------------------
# 5. Validate config has Notion IDs filled in
# -------------------------------------------------------------------
if command -v python3 &>/dev/null; then
  EMPTY_IDS=$(python3 -c "
import json, sys
with open('$CONFIG_FILE') as f:
    config = json.load(f)
empty = []
for digest_name, digest_config in config.items():
    notion = digest_config.get('notion', {})
    for key in ['config_page_id', 'database_id']:
        if not notion.get(key):
            empty.append(f'{digest_name}.notion.{key}')
if empty:
    print(', '.join(empty))
" 2>/dev/null || echo "")

  if [ -n "$EMPTY_IDS" ]; then
    echo "[WARN] Config has empty Notion IDs: $EMPTY_IDS"
    echo "       Edit config.json and re-run setup.sh"
  else
    echo "[OK] All Notion IDs are filled in"
  fi
fi

# -------------------------------------------------------------------
# 6. Install all skills from skills/ directory
# -------------------------------------------------------------------
echo ""
INSTALLED=0
for skill_dir in "$SCRIPT_DIR"/skills/*/; do
  if [ -f "$skill_dir/SKILL.md" ]; then
    skill_name=$(basename "$skill_dir")
    target_dir="$HOME/.claude/skills/$skill_name"
    mkdir -p "$target_dir"
    cp "$skill_dir/SKILL.md" "$target_dir/SKILL.md"
    echo "[OK] Installed /$skill_name -> $target_dir/SKILL.md"
    INSTALLED=$((INSTALLED + 1))
  fi
done

if [ "$INSTALLED" -eq 0 ]; then
  echo "[WARN] No skills found in $SCRIPT_DIR/skills/"
else
  echo ""
  echo "Installed $INSTALLED skill(s)."
fi

# -------------------------------------------------------------------
# 7. Verify GitHub org access
# -------------------------------------------------------------------
echo ""
ORG=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
first_digest = next(iter(config.values()))
print(first_digest.get('github', {}).get('org', 'hiero-ledger'))
" 2>/dev/null || echo "hiero-ledger")

echo "Verifying access to $ORG org..."
REPO_COUNT=$(gh api "orgs/$ORG/repos" --jq 'length' 2>/dev/null || echo "0")
if [ "$REPO_COUNT" -gt 0 ]; then
  echo "[OK] Can access $ORG org ($REPO_COUNT repos visible)"
else
  echo "[WARN] Cannot access $ORG org. Check your gh auth permissions."
fi

# -------------------------------------------------------------------
# 8. Done
# -------------------------------------------------------------------
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Config:  config.json (local, gitignored)"
echo "         $GLOBAL_CONFIG_FILE (global, read by skills)"
echo ""
echo "Skills:"
for skill_dir in "$SCRIPT_DIR"/skills/*/; do
  if [ -f "$skill_dir/SKILL.md" ]; then
    skill_name=$(basename "$skill_dir")
    echo "  /$skill_name"
  fi
done
echo ""
echo "Next steps:"
echo "  1. Ensure config.json has all Notion IDs filled in"
echo "  2. Open Claude Code and type /da-digest to run your first digest"
echo "  3. Check your Notion database for the output"
echo ""
echo "To customize: Edit your Notion config page (see docs/configuration.md)"
echo "To automate:  See docs/scheduling.md"
