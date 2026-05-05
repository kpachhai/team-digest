#!/usr/bin/env bash
# sa-digest-run.sh - headless terminal entry point for the SA Daily Digest.
#
# Invokes the /sa-digest skill via `claude -p` with the necessary
# Notion MCP tools allow-listed. Use this from cron, launchd, or
# directly in the terminal. From inside Claude Code, just type
# /sa-digest instead.
#
# Usage:
#   sa-digest-run.sh                          # digest for yesterday (UTC)
#   sa-digest-run.sh 2026-05-04               # digest for a specific date
#   sa-digest-run.sh --dry-run                # write markdown to /tmp/team-digest-dry-runs/, skip Notion
#   sa-digest-run.sh 2026-05-04 --dry-run     # both
#
# Logs:
#   $TEAM_DIGEST_LOG (default ~/.local/log/sa-digest.log)         - human-readable
#   $TEAM_DIGEST_RAW_LOG (default ~/.local/log/sa-digest-raw.jsonl) - raw stream-json events
#
# Override the model with TEAM_DIGEST_MODEL=claude-...

set -euo pipefail

# Ensure Homebrew and other tools are on PATH for cron / launchd contexts
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

LOG="${TEAM_DIGEST_LOG:-$HOME/.local/log/sa-digest.log}"
RAW_LOG="${TEAM_DIGEST_RAW_LOG:-$HOME/.local/log/sa-digest-raw.jsonl}"
MODEL="${TEAM_DIGEST_MODEL:-claude-opus-4-7}"

mkdir -p "$(dirname "$LOG")" "$(dirname "$RAW_LOG")"
echo "" >> "$LOG"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG"

# Allow-list the tools the skill needs. Without these, `claude -p`
# blocks on permission prompts and the run aborts. Notion MCP tools
# are required for Step 1 (config fetch), Step 3 (keyword search),
# Step 4 (partner search), and Step 5 (digest write).
ALLOWED_TOOLS="Bash,Read,Write,Edit,Glob,Grep"
ALLOWED_TOOLS+=",mcp__claude_ai_Notion__notion-fetch"
ALLOWED_TOOLS+=",mcp__claude_ai_Notion__notion-search"
ALLOWED_TOOLS+=",mcp__claude_ai_Notion__notion-create-pages"
ALLOWED_TOOLS+=",mcp__claude_ai_Notion__notion-update-page"
ALLOWED_TOOLS+=",mcp__claude_ai_Notion__notion-query-data-sources"

format_stream() {
  if command -v jq >/dev/null 2>&1; then
    jq -r --unbuffered '
      if .type == "system" and .subtype == "init" then
        "[init] session=" + (.session_id // "?") + " model=" + (.model // "?")
      elif .type == "assistant" then
        (.message.content // []) | map(
          if .type == "text" then "[claude] " + (.text | gsub("\n"; " ⏎ ") | .[0:500])
          elif .type == "tool_use" then "[tool→] " + .name + " " + (.input | tostring | .[0:200])
          else empty end
        ) | .[]
      elif .type == "user" then
        (.message.content // []) | map(
          if .type == "tool_result" then
            "[tool✓] " + ((.content // "") | tostring | gsub("\n"; " ⏎ ") | .[0:300])
          else empty end
        ) | .[]
      elif .type == "result" then
        "[done] " + (.subtype // "?") + " duration=" + ((.duration_ms // 0) | tostring) + "ms cost=$" + ((.total_cost_usd // 0) | tostring)
      else empty end
    '
  else
    cat
  fi
}

run_claude() {
  local prompt="$1"
  claude -p "$prompt" \
    --model "$MODEL" \
    --allowedTools "$ALLOWED_TOOLS" \
    --output-format stream-json \
    --verbose \
    2>&1 | tee -a "$RAW_LOG" | format_stream | tee -a "$LOG"
}

# ---- Argument parsing ------------------------------------------------------
# Supported forms (order is flexible):
#   sa-digest-run.sh
#   sa-digest-run.sh YYYY-MM-DD
#   sa-digest-run.sh --dry-run
#   sa-digest-run.sh YYYY-MM-DD --dry-run
#   sa-digest-run.sh --dry-run YYYY-MM-DD

DATE_ARG=""
DRY_RUN=""

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN="--dry-run"
      ;;
    -h|--help)
      sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      if echo "$arg" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        DATE_ARG="$arg"
      else
        echo "ERROR: unrecognized argument '$arg'. Use YYYY-MM-DD or --dry-run." | tee -a "$LOG"
        exit 1
      fi
      ;;
  esac
done

# ---- Build the prompt ------------------------------------------------------
PROMPT="/sa-digest"
[ -n "$DATE_ARG" ] && PROMPT="$PROMPT $DATE_ARG"
[ -n "$DRY_RUN" ] && PROMPT="$PROMPT $DRY_RUN"

echo "Running: $PROMPT" | tee -a "$LOG"
run_claude "$PROMPT"
