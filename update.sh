#!/usr/bin/env bash
set -euo pipefail

# team-digest update script
# Run after git pull to sync skills and config to local machine.
# Unlike setup.sh, this skips prerequisite checks and config creation.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"
GLOBAL_CONFIG_DIR="$HOME/.config/team-digest"
GLOBAL_CONFIG_FILE="$GLOBAL_CONFIG_DIR/config.json"

echo "=== team-digest Update ==="
echo ""

# -------------------------------------------------------------------
# 1. Check that config.json exists (setup.sh must have been run first)
# -------------------------------------------------------------------
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config.json not found. Run ./setup.sh first."
  exit 1
fi

# -------------------------------------------------------------------
# 2. Check for new digest keys in template that are missing from config
# -------------------------------------------------------------------
TEMPLATE_FILE="$SCRIPT_DIR/config.template.json"
if command -v python3 &>/dev/null && [ -f "$TEMPLATE_FILE" ]; then
  NEW_KEYS=$(python3 -c "
import json
with open('$TEMPLATE_FILE') as f:
    template = json.load(f)
with open('$CONFIG_FILE') as f:
    config = json.load(f)
new_keys = [k for k in template if k not in config and not k.startswith('_')]
if new_keys:
    print(', '.join(new_keys))
" 2>/dev/null || echo "")

  if [ -n "$NEW_KEYS" ]; then
    echo "[NEW] Template has new digest keys not in your config: $NEW_KEYS"
    echo "      Add them to config.json with your Notion IDs."
    echo "      See config.template.json for the structure."
    echo ""
  fi
fi

# -------------------------------------------------------------------
# 3. Sync config to global location
# -------------------------------------------------------------------
mkdir -p "$GLOBAL_CONFIG_DIR"
cp "$CONFIG_FILE" "$GLOBAL_CONFIG_FILE"
echo "[OK] Config synced to $GLOBAL_CONFIG_FILE"

# -------------------------------------------------------------------
# 4. Install/update all skills
# -------------------------------------------------------------------
INSTALLED=0
for skill_dir in "$SCRIPT_DIR"/skills/*/; do
  if [ -f "$skill_dir/SKILL.md" ]; then
    skill_name=$(basename "$skill_dir")
    target_dir="$HOME/.claude/skills/$skill_name"
    mkdir -p "$target_dir"
    cp "$skill_dir/SKILL.md" "$target_dir/SKILL.md"
    echo "[OK] Updated /$skill_name"
    INSTALLED=$((INSTALLED + 1))
  fi
done

echo ""
echo "Updated $INSTALLED skill(s)."

# -------------------------------------------------------------------
# 5. Check for removed skills (in ~/.claude/skills but no longer in repo)
# -------------------------------------------------------------------
for installed_skill in "$HOME"/.claude/skills/*/SKILL.md; do
  [ -f "$installed_skill" ] || continue
  skill_name=$(basename "$(dirname "$installed_skill")")
  if [ -d "$SCRIPT_DIR/skills/$skill_name" ]; then
    continue
  fi
  # Only flag skills that look like they came from team-digest
  if grep -q "team-digest" "$installed_skill" 2>/dev/null; then
    echo "[WARN] /$skill_name is installed but no longer in the repo. Remove manually if no longer needed:"
    echo "       rm -rf $HOME/.claude/skills/$skill_name"
  fi
done

# -------------------------------------------------------------------
# 6. Done
# -------------------------------------------------------------------
echo ""
echo "=== Update Complete ==="
echo ""
echo "Skills are current. Restart Claude Code if a session is already open."
