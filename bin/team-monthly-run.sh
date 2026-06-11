#!/usr/bin/env bash
# team-monthly-run.sh - headless terminal entry point for the Team Monthly Digest.
#
# Invokes the /team-monthly skill via `claude -p` with the necessary Notion
# MCP tools allow-listed. Use this from cron, launchd, or directly in
# the terminal. From inside Claude Code, just type /team-monthly instead.
#
# Usage:
#   team-monthly-run.sh                               # last full calendar month
#   team-monthly-run.sh 2026-05                        # a specific calendar month
#   team-monthly-run.sh 2026-05-14                     # the calendar month containing this date
#   team-monthly-run.sh --from F --to T               # arbitrary date range, F to T inclusive
#   team-monthly-run.sh --dry-run                     # write safety file, skip Notion
#   team-monthly-run.sh 2026-05 --dry-run             # month mode + dry run
#   team-monthly-run.sh --from F --to T --dry-run     # custom range + dry run
#   team-monthly-run.sh 2026-05 --from-file /tmp/team-digest-dry-runs/team-monthly-2026-05-v1.md
#                                                    # upload saved safety file, skip synthesis
#   team-monthly-run.sh --from F --to T --from-file /tmp/.../file.md
#                                                    # same with custom range
#   team-monthly-run.sh --help                        # this message
#
# --from-file is the token-efficient recovery path: when a previous run assembled
# the monthly digest but the Notion write timed out, use --from-file to upload the
# saved safety file without re-running the full synthesis pipeline. A month or
# --from/--to range is required alongside --from-file so month properties can be set.
#
# Logs:
#   $TEAM_DIGEST_LOG (default ~/.local/log/team-monthly.log)           - human-readable
#   $TEAM_DIGEST_RAW_LOG (default ~/.local/log/team-monthly-raw.jsonl) - raw stream-json events
#
# Override the model with TEAM_DIGEST_MODEL=... (defaults to Opus for monthly synthesis).

set -euo pipefail

# Ensure Homebrew and other tools are on PATH for cron / launchd contexts
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

LOG="${TEAM_DIGEST_LOG:-$HOME/.local/log/team-monthly.log}"
RAW_LOG="${TEAM_DIGEST_RAW_LOG:-$HOME/.local/log/team-monthly-raw.jsonl}"
# Monthly synthesis is reasoning-heavy and runs once a month, so default to Opus.
# Override with TEAM_DIGEST_MODEL=... (the CLI also accepts the `sonnet`/`haiku` aliases).
MODEL="${TEAM_DIGEST_MODEL:-opus}"

mkdir -p "$(dirname "$LOG")" "$(dirname "$RAW_LOG")"
echo "" >> "$LOG"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG"

# Allow-list the tools the skill needs. Notion MCP tools are required
# for Step 2 (query data source), Step 3 (fetch each daily), and Step 5
# (write the weekly page). Read is needed for --from-file mode.
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
  CLAUDE_EXIT=${PIPESTATUS[0]}
}

# ---- Argument parsing ------------------------------------------------------
# Supported forms (order is flexible, except --from/--to/--from-file must each have a value):
#   team-monthly-run.sh
#   team-monthly-run.sh YYYY-MM-DD
#   team-monthly-run.sh --from YYYY-MM-DD --to YYYY-MM-DD
#   team-monthly-run.sh --dry-run
#   team-monthly-run.sh YYYY-MM-DD --dry-run
#   team-monthly-run.sh --from F --to T --dry-run
#   team-monthly-run.sh 2026-05-07 --from-file /path/to/file.md
#   team-monthly-run.sh --from F --to T --from-file /path/to/file.md

DATE_ARG=""
DRY_RUN=""
FROM=""
TO=""
FROM_FILE=""

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
    --from-file)
      FROM_FILE="${2:-}"
      if [ -z "$FROM_FILE" ]; then
        echo "ERROR: --from-file requires a file path argument." | tee -a "$LOG"
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      if echo "$1" | grep -qE '^[0-9]{4}-[0-9]{2}(-[0-9]{2})?$'; then
        DATE_ARG="$1"
      else
        echo "ERROR: unrecognized argument '$1'. Use YYYY-MM or YYYY-MM-DD, --from/--to, --dry-run, or --from-file <path>." | tee -a "$LOG"
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
if [ -n "$FROM_FILE" ] && [ -n "$DRY_RUN" ]; then
  echo "ERROR: --from-file and --dry-run are mutually exclusive." | tee -a "$LOG"; exit 1
fi
if [ -n "$FROM_FILE" ] && [ -z "$DATE_ARG" ] && [ -z "$FROM" ]; then
  echo "ERROR: --from-file requires a date or --from/--to range so week properties can be set." | tee -a "$LOG"
  echo "  Examples:" | tee -a "$LOG"
  echo "    team-monthly-run.sh 2026-05-07 --from-file /path/to/file.md" | tee -a "$LOG"
  echo "    team-monthly-run.sh --from 2026-04-28 --to 2026-05-04 --from-file /path/to/file.md" | tee -a "$LOG"
  exit 1
fi
if [ -n "$FROM_FILE" ] && [ ! -f "$FROM_FILE" ]; then
  echo "ERROR: --from-file path does not exist: $FROM_FILE" | tee -a "$LOG"
  exit 1
fi

# ---- Build the prompt ------------------------------------------------------
PROMPT="/team-monthly"
[ -n "$DATE_ARG" ] && PROMPT="$PROMPT $DATE_ARG"
[ -n "$FROM" ] && [ -n "$TO" ] && PROMPT="$PROMPT --from $FROM --to $TO"
[ -n "$DRY_RUN" ] && PROMPT="$PROMPT $DRY_RUN"
[ -n "$FROM_FILE" ] && PROMPT="$PROMPT --from-file $FROM_FILE"

echo "Running: $PROMPT" | tee -a "$LOG"
# Byte offsets so the post-run gate inspects only THIS run's log output.
LOG_OFFSET=$(wc -c < "$LOG" 2>/dev/null || echo 0)
RAW_OFFSET=$(wc -c < "$RAW_LOG" 2>/dev/null || echo 0)

run_claude "$PROMPT"

# ---- Post-run verification gate ---------------------------------------------
# Deterministic pass/fail for schedulers (launchd/cron). The tee pipeline in
# run_claude swallows claude's exit code, so without this block the wrapper
# exits 0 even when the run failed. Checks, cheapest first: claude exit code,
# the harness's own result event, error-shaped strings, output artifact.
NEW_LOG="$(tail -c "+$((LOG_OFFSET + 1))" "$LOG" 2>/dev/null || true)"

if [ "${CLAUDE_EXIT:-1}" -ne 0 ]; then
  echo "[gate] FAIL: claude exited with code ${CLAUDE_EXIT:-unknown}" | tee -a "$LOG"
  exit 1
fi
# The [done] line only exists when jq rendered the result event.
if command -v jq >/dev/null 2>&1; then
  if ! printf '%s' "$NEW_LOG" | grep -q "\[done\] success"; then
    echo "[gate] FAIL: no successful result event in run output" | tee -a "$LOG"
    exit 1
  fi
fi
GATE_ERRORS="$(printf '%s' "$NEW_LOG" | grep -iE 'API Error|rate_limit_error|overloaded_error|MCP server [^ ]+ (failed|disconnected)|No such tool available|invalid_api_key|credit balance is too low' | head -3 || true)"
if [ -n "$GATE_ERRORS" ]; then
  echo "[gate] FAIL: error signal in run output:" | tee -a "$LOG"
  printf '%s\n' "$GATE_ERRORS" | tee -a "$LOG"
  exit 1
fi
if [ -z "$DRY_RUN" ]; then
  if ! tail -c "+$((RAW_OFFSET + 1))" "$RAW_LOG" 2>/dev/null | grep -q 'notion\.so/'; then
    echo "[gate] FAIL: no Notion page URL in run output - the write may not have happened" | tee -a "$LOG"
    exit 1
  fi
fi
echo "[gate] PASS" | tee -a "$LOG"
exit 0
