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

# Source optional env file for GH_TOKEN and other overrides.
# Create ~/.config/team-digest/env with: export GH_TOKEN=<your_PAT>
# This is the recommended way to pass a token to launchd runs without
# putting secrets in the plist or config.json.
ENV_FILE="$HOME/.config/team-digest/env"
# shellcheck source=/dev/null
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

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

# ---- Deterministic matches.json consolidation ------------------------------
# Set up the matches sidecar dir BEFORE invoking claude so helpers (which see
# this env var when claude -p propagates env to its Bash tool subshells) can
# write structured Mech A / Mech B / Strategy 2 / Strategy 3 records during
# the run. After claude exits, we deterministically consolidate everything
# into matches.json regardless of what Claude remembered to do at Step 5.0.
#
# Env-var propagation across `claude -p` subprocesses is unreliable in
# practice - some harness versions strip env. We still export the var for
# the benefit of any path where it does work, but the SKILL.md code falls
# back to its own dir name pattern
# (`/tmp/team-digest-matches-<DATE_LABEL>-<skill-PID>`) when the env var
# doesn't propagate. The wrapper then discovers whichever dir actually got
# written by listing /tmp/team-digest-matches-* by mtime.
TEAM_DIGEST_MATCHES_DIR="/tmp/team-digest-matches-$$"
export TEAM_DIGEST_MATCHES_DIR
mkdir -p "$TEAM_DIGEST_MATCHES_DIR"

# Capture a pre-run reference file so we can find files written by THIS run
# (vs left over from prior dry-runs). Using a reference file with `find -newer`
# is portable across BSD find (macOS) and GNU find (Linux); `find -newermt
# @<epoch>` only works on GNU find.
PRE_RUN_REF=$(mktemp /tmp/team-digest-prerunref.XXXXXX)
# mktemp already touches the file with mtime = now, which is what -newer wants.

run_claude "$PROMPT"

# ---- Post-run consolidation ------------------------------------------------
# Find the safety file (md) written by this run.
DRY_DIR="/tmp/team-digest-dry-runs"
LATEST_SAFETY=""
if [ -d "$DRY_DIR" ]; then
  LATEST_SAFETY=$(find "$DRY_DIR" -maxdepth 1 -name "team-digest-*.md" -newer "$PRE_RUN_REF" -print 2>/dev/null | head -1)
  if [ -z "$LATEST_SAFETY" ]; then
    LATEST_SAFETY=$(ls -t "$DRY_DIR"/team-digest-*.md 2>/dev/null | head -1 || true)
  fi
fi

# Find the matches dir Claude's helpers actually wrote to. The wrapper
# can't assume Claude used the env-var path: a Write-tool error mid-run
# can prompt the skill body to re-export TEAM_DIGEST_MATCHES_DIR to a
# different path before recovering. Result: wrapper's dir has 1 sidecar,
# SKILL's recovery dir has the full set. Winner-by-volume discovery:
# iterate all candidate dirs, pick the one with the MOST JSON files newer
# than the pre-run reference. Whichever dir got the real workload wins,
# regardless of which name pattern was used.
discover_matches_dir() {
  local best_dir=""
  local best_count=0
  local d
  for d in "$TEAM_DIGEST_MATCHES_DIR" /tmp/team-digest-matches-*; do
    [ -d "$d" ] || continue
    local count
    count=$(find "$d" -maxdepth 1 -name '*.json' -newer "$PRE_RUN_REF" -print 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -gt "$best_count" ]; then
      best_count="$count"
      best_dir="$d"
    fi
  done
  echo "$best_dir"
}

# set +e around discover to avoid pipefail/set-e surprises in the helper.
set +e
ACTIVE_MATCHES_DIR=$(discover_matches_dir)
set -e

SIDECAR_COUNT=0
if [ -n "$ACTIVE_MATCHES_DIR" ]; then
  SIDECAR_COUNT=$(find "$ACTIVE_MATCHES_DIR" -maxdepth 1 -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
fi

# Clean up the reference file - we don't need it past this point.
rm -f "$PRE_RUN_REF"

if [ -n "$LATEST_SAFETY" ] && [ "$SIDECAR_COUNT" -gt 0 ]; then
  MATCHES_OUT="${LATEST_SAFETY%.md}-matches.json"
  echo "[post-run] Consolidating $SIDECAR_COUNT match sidecar(s) from $ACTIVE_MATCHES_DIR -> $MATCHES_OUT" | tee -a "$LOG"
  CONSOLIDATOR="$HOME/.claude/skills/team-digest/lib/consolidate-matches.sh"
  if [ -x "$CONSOLIDATOR" ]; then
    bash "$CONSOLIDATOR" "$ACTIVE_MATCHES_DIR" "$MATCHES_OUT" 2>&1 | tee -a "$LOG" || true
  else
    echo "[post-run] WARN: consolidator not at $CONSOLIDATOR; skipping" | tee -a "$LOG"
  fi

  # Calibration drift snapshot. Non-fatal.
  CALIBRATOR="$HOME/.claude/skills/team-digest/lib/calibrate-hip-matches.sh"
  if [ -x "$CALIBRATOR" ] && [ -f "$MATCHES_OUT" ]; then
    bash "$CALIBRATOR" --current-only "$LATEST_SAFETY" 2>&1 | tee -a "$LOG" || true
  fi
else
  echo "[post-run] No matches consolidation: safety=${LATEST_SAFETY:-<none>}, dir=${ACTIVE_MATCHES_DIR:-<none>}, sidecars=$SIDECAR_COUNT" | tee -a "$LOG"
fi

# Clean up both the wrapper's dir and any skill-body fallback dir we found.
rm -rf "$TEAM_DIGEST_MATCHES_DIR"
if [ -n "$ACTIVE_MATCHES_DIR" ] && [ "$ACTIVE_MATCHES_DIR" != "$TEAM_DIGEST_MATCHES_DIR" ]; then
  rm -rf "$ACTIVE_MATCHES_DIR"
fi
