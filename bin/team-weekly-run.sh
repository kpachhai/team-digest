#!/usr/bin/env bash
# team-weekly-run.sh - headless terminal entry point for the Team Weekly Digest.
#
# Invokes the /team-weekly skill via `claude -p` with the necessary Notion
# MCP tools allow-listed. Use this from cron, launchd, or directly in
# the terminal. From inside Claude Code, just type /team-weekly instead.
#
# Usage:
#   team-weekly-run.sh                               # last full ISO week (Mon-Sun)
#   team-weekly-run.sh 2026-05-07                    # the ISO week containing this date
#   team-weekly-run.sh --from F --to T               # arbitrary date range, F to T inclusive
#   team-weekly-run.sh --dry-run                     # write safety file, skip Notion
#   team-weekly-run.sh 2026-05-07 --dry-run          # ISO-week mode + dry run
#   team-weekly-run.sh --from F --to T --dry-run     # custom range + dry run
#   team-weekly-run.sh 2026-05-07 --allow-partial    # synthesize from available days even if
#                                                    # some days are missing (notes gaps in body)
#   team-weekly-run.sh 2026-05-07 --from-file /tmp/team-digest-dry-runs/team-weekly-2026-W19-v1.md
#                                                    # upload saved safety file, skip synthesis
#   team-weekly-run.sh --from F --to T --from-file /tmp/.../file.md
#                                                    # same with custom range
#   team-weekly-run.sh --help                        # this message
#
# --from-file is the token-efficient recovery path: when a previous run assembled
# the weekly digest but the Notion write timed out, use --from-file to upload the
# saved safety file without re-running the full synthesis pipeline. A date or
# --from/--to range is required alongside --from-file so week properties can be set.
#
# Logs:
#   $TEAM_DIGEST_LOG (default ~/.local/log/team-weekly.log)           - human-readable
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

# Allow-list the tools the skill needs for this HEADLESS run. Bare
# `Bash`/`Write`/`Edit` is unsafe (it auto-approves any shell command a
# prompt-injection payload emits), so Bash is scoped to the command families
# the skill runs - its own lib plus the shared team-digest lib (load-config,
# coverage-gap) - Write is scoped to the safety/dry-run dir, and Edit is
# dropped. Notion MCP tools cover Steps 2/3/5; Read covers --from-file.
# NOTE: python3/eval stay allowed (inline in the skill) - defense-in-depth,
# not a full sandbox. Validate changes with `--dry-run` before cron.
ALLOWED_TOOLS="Read,Glob,Grep"
ALLOWED_TOOLS+=",Write(/tmp/team-digest-dry-runs/**)"
ALLOWED_TOOLS+=",Bash(bash ~/.claude/skills/team-weekly/lib/*)"
ALLOWED_TOOLS+=",Bash(bash ~/.claude/skills/team-digest/lib/*)"
ALLOWED_TOOLS+=",Bash(gh *),Bash(python3 *),Bash(eval *),Bash(mkdir *),Bash(sleep *),Bash(export *)"
ALLOWED_TOOLS+=",mcp__claude_ai_Notion__notion-fetch"
ALLOWED_TOOLS+=",mcp__claude_ai_Notion__notion-search"
ALLOWED_TOOLS+=",mcp__claude_ai_Notion__notion-create-pages"
ALLOWED_TOOLS+=",mcp__claude_ai_Notion__notion-update-page"
ALLOWED_TOOLS+=",mcp__claude_ai_Notion__notion-query-data-sources"

# OS-level sandbox (kernel-enforced: macOS Seatbelt / Linux bubblewrap) - the
# REAL boundary the --allowedTools scoping above cannot be (Claude Code Bash
# allow rules are not path-canonicalized, so a directory-prefix rule is a speed
# bump, not a boundary). It confines this run's filesystem writes to the
# pipeline's own scratch dirs, so an injected payload in scanned third-party
# content can't tamper with ~/.ssh, ~/.claude, or arbitrary files. The config
# lives next to this script (committed, portable, ~ paths - reproducible on any
# machine) and is applied per-invocation via --settings, so interactive Claude
# Code sessions are unaffected. Set TEAM_DIGEST_NO_SANDBOX=1 to disable (debug).
# Resolve this script's real dir following the ~/.local/bin symlink portably -
# macOS /bin/bash is 3.2 and BSD readlink lacks -f, so walk the links by hand.
sb_src="${BASH_SOURCE[0]}"
while [ -L "$sb_src" ]; do
  sb_dir="$(cd -P "$(dirname "$sb_src")" >/dev/null 2>&1 && pwd)"
  sb_src="$(readlink "$sb_src")"
  [ "${sb_src#/}" = "$sb_src" ] && sb_src="$sb_dir/$sb_src"
done
SANDBOX_SETTINGS="$(cd -P "$(dirname "$sb_src")" >/dev/null 2>&1 && pwd)/sandbox-settings.json"
SANDBOX_ARGS=()
if [ "${TEAM_DIGEST_NO_SANDBOX:-0}" = "1" ]; then
  echo "WARNING: TEAM_DIGEST_NO_SANDBOX=1 - running UNSANDBOXED (filesystem not confined)." | tee -a "$LOG"
elif [ -f "$SANDBOX_SETTINGS" ]; then
  SANDBOX_ARGS=(--settings "$SANDBOX_SETTINGS")
  echo "[sandbox] on: $SANDBOX_SETTINGS" >> "$LOG"
else
  echo "WARNING: sandbox settings not found at $SANDBOX_SETTINGS - running UNSANDBOXED. Redeploy the repo to restore the sandbox." | tee -a "$LOG"
fi

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
        "[done] " + (if .is_error then "error" else (.subtype // "?") end) + " duration=" + ((.duration_ms // 0) | tostring) + "ms cost=$" + ((.total_cost_usd // 0) | tostring)
      else empty end
    '
  else
    cat
  fi
}

run_claude() {
  local prompt="$1"
  # set +e so a jq parse failure (e.g. a non-JSON hook lifecycle message on
  # stderr) does not exit the script before the post-run gate can run.
  # stderr is routed directly to the log to keep the JSON stream clean; API
  # errors appear in the stream as synthetic assistant messages anyway.
  set +e
  claude -p "$prompt" \
    --model "$MODEL" \
    --allowedTools "$ALLOWED_TOOLS" \
    ${SANDBOX_ARGS[@]+"${SANDBOX_ARGS[@]}"} \
    --output-format stream-json \
    --verbose \
    2>> "$LOG" | tee -a "$RAW_LOG" | format_stream | tee -a "$LOG"
  CLAUDE_EXIT=${PIPESTATUS[0]}
  set -e
}

# ---- Argument parsing ------------------------------------------------------
# Supported forms (order is flexible, except --from/--to/--from-file must each have a value):
#   team-weekly-run.sh
#   team-weekly-run.sh YYYY-MM-DD
#   team-weekly-run.sh --from YYYY-MM-DD --to YYYY-MM-DD
#   team-weekly-run.sh --dry-run
#   team-weekly-run.sh YYYY-MM-DD --dry-run
#   team-weekly-run.sh --from F --to T --dry-run
#   team-weekly-run.sh 2026-05-07 --from-file /path/to/file.md
#   team-weekly-run.sh --from F --to T --from-file /path/to/file.md

DATE_ARG=""
DRY_RUN=""
ALLOW_PARTIAL=""
FROM=""
TO=""
FROM_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN="--dry-run"
      shift
      ;;
    --allow-partial)
      ALLOW_PARTIAL="--allow-partial"
      export TEAM_DIGEST_ALLOW_PARTIAL=1
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
      if echo "$1" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        DATE_ARG="$1"
      else
        echo "ERROR: unrecognized argument '$1'. Use YYYY-MM-DD, --from/--to, --dry-run, or --from-file <path>." | tee -a "$LOG"
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
  echo "    team-weekly-run.sh 2026-05-07 --from-file /path/to/file.md" | tee -a "$LOG"
  echo "    team-weekly-run.sh --from 2026-04-28 --to 2026-05-04 --from-file /path/to/file.md" | tee -a "$LOG"
  exit 1
fi
if [ -n "$FROM_FILE" ] && [ ! -f "$FROM_FILE" ]; then
  echo "ERROR: --from-file path does not exist: $FROM_FILE" | tee -a "$LOG"
  exit 1
fi

# ---- Build the prompt ------------------------------------------------------
PROMPT="/team-weekly"
[ -n "$DATE_ARG" ] && PROMPT="$PROMPT $DATE_ARG"
[ -n "$FROM" ] && [ -n "$TO" ] && PROMPT="$PROMPT --from $FROM --to $TO"
[ -n "$DRY_RUN" ] && PROMPT="$PROMPT $DRY_RUN"
[ -n "$ALLOW_PARTIAL" ] && PROMPT="$PROMPT $ALLOW_PARTIAL"
[ -n "$FROM_FILE" ] && PROMPT="$PROMPT --from-file $FROM_FILE"

echo "Running: $PROMPT" | tee -a "$LOG"
# Byte offset so the post-run gate inspects only THIS run's log output.
LOG_OFFSET=$(wc -c < "$LOG" 2>/dev/null || echo 0)

run_claude "$PROMPT"

# ---- Post-run verification gate ---------------------------------------------
# Deterministic pass/fail for schedulers (launchd/cron). The tee pipeline in
# run_claude swallows claude's exit code, so without this block the wrapper
# exits 0 even when the run failed. Checks, cheapest first: claude exit code,
# the harness's own result event, error-shaped strings, output artifact.
NEW_LOG="$(tail -c "+$((LOG_OFFSET + 1))" "$LOG" 2>/dev/null || true)"

# Intentional coverage skip: the skill's Step 2.5 gate aborted before writing
# because the week was not fully covered. This is a clean no-op, not a failure.
if printf '%s' "$NEW_LOG" | grep -q '\[coverage\] INCOMPLETE'; then
  echo "[gate] SKIP: coverage incomplete - no digest written this run" | tee -a "$LOG"
  exit 0
fi

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
  if ! printf '%s' "$NEW_LOG" | grep -qE 'notion\.so/|app\.notion\.com/'; then
    echo "[gate] FAIL: no Notion page URL in run output - the write may not have happened" | tee -a "$LOG"
    exit 1
  fi
fi
echo "[gate] PASS" | tee -a "$LOG"
exit 0
