#!/usr/bin/env bash
# team-digest-run.sh - headless terminal entry point for the Team Daily Digest.
#
# Invokes the /team-digest skill via `claude -p` with the necessary
# Notion MCP tools allow-listed. Use this from cron, launchd, or
# directly in the terminal. From inside Claude Code, just type
# /team-digest instead.
#
# Usage:
#   team-digest-run.sh                                     # digest for yesterday (UTC)
#   team-digest-run.sh 2026-05-04                          # digest for a specific date
#   team-digest-run.sh --dry-run                           # write safety file, skip Notion
#   team-digest-run.sh 2026-05-04 --dry-run                # both
#   team-digest-run.sh --from-file /tmp/.../file.md        # upload saved safety file to Notion
#   team-digest-run.sh 2026-05-15 --from-file /tmp/...     # same, with explicit date
#   team-digest-run.sh --help                              # this message
#
# The --from-file flag is the token-efficient recovery path: when a previous run
# assembled the digest but the Notion write timed out, use --from-file to upload
# the saved safety file without re-running the full data-gather pipeline.
#
# Logs:
#   $TEAM_DIGEST_LOG (default ~/.local/log/team-digest.log)           - human-readable
#   $TEAM_DIGEST_RAW_LOG (default ~/.local/log/team-digest-raw.jsonl) - raw stream-json events
#
# Override the model with TEAM_DIGEST_MODEL=claude-...

set -euo pipefail

# Ensure Homebrew and other tools are on PATH for cron / launchd contexts
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

LOG="${TEAM_DIGEST_LOG:-$HOME/.local/log/team-digest.log}"
RAW_LOG="${TEAM_DIGEST_RAW_LOG:-$HOME/.local/log/team-digest-raw.jsonl}"
MODEL="${TEAM_DIGEST_MODEL:-claude-sonnet-4-6}"

mkdir -p "$(dirname "$LOG")" "$(dirname "$RAW_LOG")"
echo "" >> "$LOG"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG"

# Allow-list the tools the skill needs. Without these, `claude -p`
# blocks on permission prompts and the run aborts. Notion MCP tools
# are required for Step 1 (config fetch), Step 3 (keyword search),
# Step 4 (partner search), and Step 5 (digest write). Read is needed
# for --from-file mode to read the safety file.
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
#   team-digest-run.sh
#   team-digest-run.sh YYYY-MM-DD
#   team-digest-run.sh --dry-run
#   team-digest-run.sh YYYY-MM-DD --dry-run
#   team-digest-run.sh --dry-run YYYY-MM-DD
#   team-digest-run.sh --from-file /path/to/file.md
#   team-digest-run.sh 2026-05-15 --from-file /path/to/file.md

DATE_ARG=""
DRY_RUN=""
FROM_FILE=""
SKIP_NEXT=""

for arg in "$@"; do
  if [ -n "$SKIP_NEXT" ]; then
    SKIP_NEXT=""
    continue
  fi
  case "$arg" in
    --dry-run)
      DRY_RUN="--dry-run"
      ;;
    --from-file)
      # Next positional is the file path - handled via shift trick below
      # We use a flag so the next iteration captures it
      FROM_FILE="__PENDING__"
      ;;
    -h|--help)
      sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      if [ "$FROM_FILE" = "__PENDING__" ]; then
        FROM_FILE="$arg"
      elif echo "$arg" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        DATE_ARG="$arg"
      else
        echo "ERROR: unrecognized argument '$arg'. Use YYYY-MM-DD, --dry-run, or --from-file <path>." | tee -a "$LOG"
        exit 1
      fi
      ;;
  esac
done

# Validate --from-file
if [ "$FROM_FILE" = "__PENDING__" ]; then
  echo "ERROR: --from-file requires a file path argument." | tee -a "$LOG"
  exit 1
fi
if [ -n "$FROM_FILE" ] && [ ! -f "$FROM_FILE" ]; then
  echo "ERROR: --from-file path does not exist: $FROM_FILE" | tee -a "$LOG"
  exit 1
fi
if [ -n "$FROM_FILE" ] && [ -n "$DRY_RUN" ]; then
  echo "ERROR: --from-file and --dry-run are mutually exclusive." | tee -a "$LOG"
  exit 1
fi

# ---- Build the prompt ------------------------------------------------------
PROMPT="/team-digest"
[ -n "$DATE_ARG" ] && PROMPT="$PROMPT $DATE_ARG"
[ -n "$DRY_RUN" ] && PROMPT="$PROMPT $DRY_RUN"
[ -n "$FROM_FILE" ] && PROMPT="$PROMPT --from-file $FROM_FILE"

echo "Running: $PROMPT" | tee -a "$LOG"
run_claude "$PROMPT"
