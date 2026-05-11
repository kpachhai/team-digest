#!/usr/bin/env bash
# team-weekly-run.sh - headless terminal entry point for the Team Weekly Digest.
#
# Invokes the /team-weekly skill via `claude -p` with the necessary Notion
# MCP tools allow-listed. Use this from cron, launchd, or directly in
# the terminal. From inside Claude Code, just type /team-weekly instead.
#
# Usage:
#   team-weekly-run.sh                          # last full ISO week (Mon-Sun)
#   team-weekly-run.sh 2026-05-07               # the ISO week containing this date
#   team-weekly-run.sh --from F --to T          # arbitrary date range, F to T inclusive
#   team-weekly-run.sh --dry-run                # write to /tmp/team-digest-dry-runs/, skip Notion
#   team-weekly-run.sh 2026-05-07 --dry-run     # ISO-week mode + dry run
#   team-weekly-run.sh --from F --to T --dry-run # custom range + dry run
#
# Logs:
#   $TEAM_DIGEST_LOG (default ~/.local/log/team-weekly.log)         - human-readable
#   $TEAM_DIGEST_RAW_LOG (default ~/.local/log/team-weekly-raw.jsonl) - raw stream-json events
#
# Override the model with TEAM_DIGEST_MODEL=claude-...

set -euo pipefail

# Ensure Homebrew and other tools are on PATH for cron / launchd contexts
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

LOG="${TEAM_DIGEST_LOG:-$HOME/.local/log/team-weekly.log}"
RAW_LOG="${TEAM_DIGEST_RAW_LOG:-$HOME/.local/log/team-weekly-raw.jsonl}"
MODEL="${TEAM_DIGEST_MODEL:-claude-sonnet-4-6}"

mkdir -p "$(dirname "$LOG")" "$(dirname "$RAW_LOG")"
echo "" >> "$LOG"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG"

# Allow-list the tools the skill needs. Notion MCP tools are required
# for Step 2 (query data source), Step 3 (fetch each daily), and Step 5
# (write the weekly page).
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
# Supported forms (order is flexible, except --from/--to must each have a value):
#   team-weekly-run.sh
#   team-weekly-run.sh YYYY-MM-DD
#   team-weekly-run.sh --from YYYY-MM-DD --to YYYY-MM-DD
#   team-weekly-run.sh --dry-run
#   team-weekly-run.sh YYYY-MM-DD --dry-run
#   team-weekly-run.sh --from F --to T --dry-run

DATE_ARG=""
DRY_RUN=""
FROM=""
TO=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN="--dry-run"
      shift
      ;;
    --from)
      FROM="${2:-}"
      if [ -z "$FROM" ] || ! echo "$FROM" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        echo "ERROR: --from requires a YYYY-MM-DD value (got '$FROM')." | tee -a "$LOG"
        exit 1
      fi
      shift 2
      ;;
    --to)
      TO="${2:-}"
      if [ -z "$TO" ] || ! echo "$TO" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        echo "ERROR: --to requires a YYYY-MM-DD value (got '$TO')." | tee -a "$LOG"
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      if echo "$1" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        DATE_ARG="$1"
      else
        echo "ERROR: unrecognized argument '$1'. Use YYYY-MM-DD, --from/--to, or --dry-run." | tee -a "$LOG"
        exit 1
      fi
      shift
      ;;
  esac
done

# Cross-flag validation
if [ -n "$FROM" ] && [ -z "$TO" ]; then
  echo "ERROR: --from requires --to." | tee -a "$LOG"; exit 1
fi
if [ -z "$FROM" ] && [ -n "$TO" ]; then
  echo "ERROR: --to requires --from." | tee -a "$LOG"; exit 1
fi
if { [ -n "$FROM" ] || [ -n "$TO" ]; } && [ -n "$DATE_ARG" ]; then
  echo "ERROR: cannot mix a positional date arg with --from/--to. Pick one mode." | tee -a "$LOG"
  exit 1
fi

# ---- Build the prompt ------------------------------------------------------
PROMPT="/team-weekly"
[ -n "$DATE_ARG" ] && PROMPT="$PROMPT $DATE_ARG"
[ -n "$FROM" ] && [ -n "$TO" ] && PROMPT="$PROMPT --from $FROM --to $TO"
[ -n "$DRY_RUN" ] && PROMPT="$PROMPT $DRY_RUN"

echo "Running: $PROMPT" | tee -a "$LOG"
run_claude "$PROMPT"
