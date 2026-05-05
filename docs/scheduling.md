# Scheduling the Team Daily Digest

The skill runs in two contexts and the same `bin/team-digest-run.sh` covers both:

1. **Interactive (Claude Code)** - type `/team-digest` in a Claude Code session.
2. **Headless (terminal / cron / launchd)** - run `bin/team-digest-run.sh` from a shell.

For automated daily runs on macOS, **launchd is the recommended option**. It survives sleep/wake cycles, requires no cloud account, and uses your local `gh` and Notion MCP setup directly.

## The wrapper script: `bin/team-digest-run.sh`

The team-digest repo ships `bin/team-digest-run.sh` as the headless entry point. It invokes the `/team-digest` skill via `claude -p` with the necessary Notion MCP tools allow-listed. From the repo root:

```bash
bin/team-digest-run.sh                        # digest for yesterday (UTC)
bin/team-digest-run.sh 2026-04-27             # digest for a specific date
bin/team-digest-run.sh --dry-run              # write markdown to /tmp/team-digest-dry-runs/, skip Notion
bin/team-digest-run.sh 2026-04-27 --dry-run   # both
bin/team-digest-run.sh --help                 # usage
```

For convenience, copy or symlink it to a directory on your `$PATH`:

```bash
# Symlink (preferred - tracks repo updates automatically):
mkdir -p ~/.local/bin
ln -sf "$(pwd)/bin/team-digest-run.sh" ~/.local/bin/team-digest-run.sh

# Or copy (snapshot - won't auto-update with git pull):
cp bin/team-digest-run.sh ~/.local/bin/team-digest-run.sh
```

After symlinking, you can invoke `team-digest-run.sh` from anywhere.

### Environment overrides

| Variable | Default | Purpose |
|---|---|---|
| `TEAM_DIGEST_LOG` | `~/.local/log/team-digest.log` | Human-readable streaming log |
| `TEAM_DIGEST_RAW_LOG` | `~/.local/log/team-digest-raw.jsonl` | Raw `claude -p --output-format stream-json` events |
| `TEAM_DIGEST_MODEL` | `claude-opus-4-7` | Override the model used by `claude -p` |

### What you'll see streaming in real time

- `[init] session=... model=...` - once when Claude starts
- `[claude] ...` - each chunk of assistant reasoning/text
- `[tool→] Bash {...}` - each tool call as it's invoked
- `[tool✓] ...` - the result of each tool call
- `[done] success duration=... cost=$...` - final summary

If `jq` isn't installed (`brew install jq`), the script falls back to printing raw JSON events.

### About the Notion MCP server name

The `mcp__claude_ai_Notion__*` prefix in the script's allow-list matches the Notion connector exposed by Claude Code Desktop. If your MCP server is registered under a different name, run `claude mcp list` to find the actual server identifier and adjust the prefix in `bin/team-digest-run.sh`. Alternatively, replace `--allowedTools "$ALLOWED_TOOLS"` with `--permission-mode bypassPermissions` for a script you fully control - simpler, broader.

## Local macOS launchd (recommended for daily automation)

### 1. Make sure the wrapper is reachable

Either symlink the repo's script (preferred) or copy it:

```bash
mkdir -p ~/.local/bin ~/.local/log
ln -sf "$(pwd)/bin/team-digest-run.sh" ~/.local/bin/team-digest-run.sh
```

Test it manually before scheduling:

```bash
~/.local/bin/team-digest-run.sh --dry-run    # safe smoke test - no Notion write
~/.local/bin/team-digest-run.sh              # real run for yesterday
~/.local/bin/team-digest-run.sh 2026-04-27   # specific date
```

### 2. Create the launchd plist

Create `~/Library/LaunchAgents/com.team-digest.team-digest.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.team-digest.team-digest</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/YOUR_USERNAME/.local/bin/team-digest-run.sh</string>
  </array>

  <!-- Weekdays at 8:00 AM local time -->
  <key>StartCalendarInterval</key>
  <array>
    <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>8</integer><key>Minute</key><integer>0</integer></dict>
    <dict><key>Weekday</key><integer>2</integer><key>Hour</key><integer>8</integer><key>Minute</key><integer>0</integer></dict>
    <dict><key>Weekday</key><integer>3</integer><key>Hour</key><integer>8</integer><key>Minute</key><integer>0</integer></dict>
    <dict><key>Weekday</key><integer>4</integer><key>Hour</key><integer>8</integer><key>Minute</key><integer>0</integer></dict>
    <dict><key>Weekday</key><integer>5</integer><key>Hour</key><integer>8</integer><key>Minute</key><integer>0</integer></dict>
  </array>

  <key>StandardOutPath</key>
  <string>/Users/YOUR_USERNAME/.local/log/team-digest-launchd.log</string>

  <key>StandardErrorPath</key>
  <string>/Users/YOUR_USERNAME/.local/log/team-digest-launchd.log</string>

  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
```

Replace `YOUR_USERNAME` with your actual macOS username (`whoami` to check).

### 3. Load the job

```bash
launchctl load ~/Library/LaunchAgents/com.team-digest.team-digest.plist
```

Verify it loaded:

```bash
launchctl list | grep team-digest
```

### Managing the job

```bash
# Unload (disable without deleting)
launchctl unload ~/Library/LaunchAgents/com.team-digest.team-digest.plist

# Reload after editing the plist
launchctl unload ~/Library/LaunchAgents/com.team-digest.team-digest.plist
launchctl load ~/Library/LaunchAgents/com.team-digest.team-digest.plist

# Trigger a manual run immediately
launchctl start com.team-digest.team-digest

# View logs
tail -f ~/.local/log/team-digest.log
```

**Note:** launchd will not fire a missed run if your Mac was asleep or off at the scheduled time. If you need catch-up on missed days, run `bin/team-digest-run.sh YYYY-MM-DD` (or `/team-digest YYYY-MM-DD` interactively) manually.

## Linux cron

Same script works under cron. Add to `crontab -e`:

```
0 8 * * 1-5 /home/YOUR_USERNAME/.local/bin/team-digest-run.sh > /dev/null 2>&1
```

The script handles its own logging via `TEAM_DIGEST_LOG` and `TEAM_DIGEST_RAW_LOG`. Cron will not fire missed runs on a sleeping machine - same caveat as launchd.

## GitHub Actions (self-hosted runner)

If you have a self-hosted runner with `claude` and `gh` configured, add a workflow:

```yaml
name: Team Daily Digest
on:
  schedule:
    - cron: '0 13 * * 1-5'  # weekdays at 13:00 UTC
  workflow_dispatch:
    inputs:
      date:
        description: 'YYYY-MM-DD (blank = yesterday)'
        required: false
      dry_run:
        description: 'Dry run (writes locally, skips Notion)'
        type: boolean
        default: false

jobs:
  digest:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - run: |
          ARGS=""
          [ -n "${{ inputs.date }}" ] && ARGS="$ARGS ${{ inputs.date }}"
          [ "${{ inputs.dry_run }}" = "true" ] && ARGS="$ARGS --dry-run"
          ./bin/team-digest-run.sh $ARGS
```

GitHub-hosted runners do not have `claude` installed, so this requires a self-hosted setup. The Claude Code CLI must be authenticated on the runner.

## Verifying the schedule

After setting up any scheduling option:

1. Wait for the next scheduled run (or trigger manually)
2. Check your digest database in Notion (the `database_id` from your `config.json`)
3. A new page should appear with that date and "Auto" status
4. If nothing appears, check `~/.local/log/team-digest.log` for errors

For repeated debugging without spamming Notion, use `--dry-run` - the markdown lands in `/tmp/team-digest-dry-runs/team-digest-<date>-v<N>.md` and you can `cat` or `diff` it before doing a real run. Files are ephemeral (cleared on reboot).
