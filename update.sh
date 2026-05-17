#!/usr/bin/env bash
set -euo pipefail

# team-digest update script
# Run after git pull to sync skills and config to local machine.
# Unlike setup.sh, this skips prerequisite checks and config creation.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"
GLOBAL_CONFIG_DIR="$HOME/.config/team-digest"
GLOBAL_CONFIG_FILE="$GLOBAL_CONFIG_DIR/config.json"
PROFILES_DIR="$SCRIPT_DIR/profiles"
GLOBAL_PROFILES_DIR="$GLOBAL_CONFIG_DIR/profiles"

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
# 2. Sync config to global location with deep-merge
#
# The repo's config.json is gitignored (per-user state) and bootstrap writes
# values like Notion IDs only to the GLOBAL config. A raw cp from repo to
# global would clobber bootstrap-written values. Instead, deep-merge the
# repo template into the global config with this rule: an empty value never
# overwrites a non-empty value. This preserves bootstrap-written IDs while
# still propagating user edits and template additions.
#
# Also surfaces new fields at any nesting depth (not just top-level) so the
# user knows about new template fields after a git pull.
# -------------------------------------------------------------------
TEMPLATE_FILE="$SCRIPT_DIR/config.template.json"
mkdir -p "$GLOBAL_CONFIG_DIR"

python3 - "$CONFIG_FILE" "$GLOBAL_CONFIG_FILE" "$TEMPLATE_FILE" <<'PY'
import json, os, sys

repo_path, global_path, template_path = sys.argv[1], sys.argv[2], sys.argv[3]

with open(repo_path) as f:
    repo = json.load(f)

if os.path.exists(global_path):
    with open(global_path) as f:
        existing = json.load(f)
else:
    existing = {}

template = None
if os.path.exists(template_path):
    with open(template_path) as f:
        template = json.load(f)


def is_empty(v):
    return v is None or v == "" or v == [] or v == {}


def deep_merge(repo, existing):
    """Merge repo into existing. Rule: an empty value never overwrites a
    non-empty value. For dicts, recurse. For non-dict leaves, repo wins
    unless repo's value is empty and existing's is not."""
    if isinstance(repo, dict) and isinstance(existing, dict):
        merged = {}
        for k in dict.fromkeys(list(repo) + list(existing)):
            if k in repo and k in existing:
                merged[k] = deep_merge(repo[k], existing[k])
            elif k in repo:
                merged[k] = repo[k]
            else:
                merged[k] = existing[k]
        return merged
    if is_empty(repo) and not is_empty(existing):
        return existing
    return repo


def find_new_paths(tmpl, cfg, prefix=""):
    """Return dotted paths in tmpl that are missing from cfg. Skips keys
    starting with underscore (treated as comments) and *_help sibling keys."""
    paths = []
    if isinstance(tmpl, dict):
        for k, v in tmpl.items():
            if k.startswith("_") or k.endswith("_help"):
                continue
            sub = f"{prefix}.{k}" if prefix else k
            if not isinstance(cfg, dict) or k not in cfg:
                paths.append(sub)
            elif isinstance(v, dict) and isinstance(cfg.get(k), dict):
                paths.extend(find_new_paths(v, cfg[k], sub))
    return paths


merged = deep_merge(repo, existing)

if template is not None:
    new_paths = find_new_paths(template, merged)
    if new_paths:
        sys.stderr.write(
            "[NEW] Template has fields missing from your config:\n"
        )
        for p in new_paths:
            sys.stderr.write(f"      - {p}\n")
        sys.stderr.write(
            "      See config.template.json for default values.\n\n"
        )

with open(global_path, "w") as f:
    json.dump(merged, f, indent=2)
    f.write("\n")
PY

echo "[OK] Config merged into $GLOBAL_CONFIG_FILE"

# -------------------------------------------------------------------
# 3b. Sync profiles (new templates -> local copies if missing; sync all to global)
# -------------------------------------------------------------------
if [ -d "$PROFILES_DIR" ]; then
  mkdir -p "$GLOBAL_PROFILES_DIR"
  for template_file in "$PROFILES_DIR"/*.template.md; do
    [ -f "$template_file" ] || continue
    template_name=$(basename "$template_file" .template.md)
    local_profile="$PROFILES_DIR/$template_name.md"
    global_profile="$GLOBAL_PROFILES_DIR/$template_name.md"

    if [ ! -f "$local_profile" ]; then
      cp "$template_file" "$local_profile"
      echo "[NEW] Profile added: profiles/$template_name.md - personalize it for your role"
    fi

    cp "$local_profile" "$global_profile"
    echo "[OK] Profile synced: $template_name"
  done
fi

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
    # Copy TEMPLATE.md if present (output format contract, read by the skill at Step 5)
    [ -f "$skill_dir/TEMPLATE.md" ] && cp "$skill_dir/TEMPLATE.md" "$target_dir/TEMPLATE.md"
    # Marker file - lets the stale-skill check below distinguish team-digest's
    # own skills from any other skill that happens to mention "team-digest"
    # in its body (which would false-positive on a string-match heuristic).
    touch "$target_dir/.team-digest-managed"

    # Sync lib/ helpers if the skill has them. Mirror the lib/ contents
    # so removed helpers in the repo get cleaned up at the install path.
    if [ -d "$skill_dir/lib" ]; then
      mkdir -p "$target_dir/lib"
      # Remove any installed helpers no longer present in the repo
      for installed in "$target_dir/lib/"*.sh; do
        [ -f "$installed" ] || continue
        helper_name=$(basename "$installed")
        [ -f "$skill_dir/lib/$helper_name" ] || rm -f "$installed"
      done
      cp "$skill_dir/lib/"*.sh "$target_dir/lib/" 2>/dev/null || true
      cp "$skill_dir/lib/README.md" "$target_dir/lib/README.md" 2>/dev/null || true
      chmod +x "$target_dir/lib/"*.sh 2>/dev/null || true
      lib_count=$(find "$skill_dir/lib" -name '*.sh' -type f | wc -l | tr -d ' ')
      echo "[OK] Updated /$skill_name (with $lib_count helper script(s))"
    else
      echo "[OK] Updated /$skill_name"
    fi
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
  # Only flag skills this repo actually installed (marker file present).
  # Skills installed from elsewhere - dotfiles, other plugins, third-party
  # marketplaces - are left alone even if they happen to reference team-digest.
  if [ -f "$HOME/.claude/skills/$skill_name/.team-digest-managed" ]; then
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
