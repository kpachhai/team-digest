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
# Symlink (preferred - tracks repo updates, and the headless sandbox config
# next to the wrapper is always found):
mkdir -p ~/.local/bin
ln -sf "$(pwd)/bin/team-digest-run.sh" ~/.local/bin/team-digest-run.sh

# Or copy (snapshot - won't auto-update with git pull). Copy the sandbox
# config alongside it, or the run falls back to UNSANDBOXED (see Sandboxing):
cp bin/team-digest-run.sh bin/sandbox-settings.json ~/.local/bin/
```

After symlinking, you can invoke `team-digest-run.sh` from anywhere.

### Environment overrides

| Variable | Default | Purpose |
|---|---|---|
| `TEAM_DIGEST_LOG` | `~/.local/log/team-digest.log` | Human-readable streaming log |
| `TEAM_DIGEST_RAW_LOG` | `~/.local/log/team-digest-raw.jsonl` | Raw `claude -p --output-format stream-json` events |
| `TEAM_DIGEST_MODEL` | `claude-sonnet-4-6` | Override the model used by `claude -p` |

### What you'll see streaming in real time

- `[init] session=... model=...` - once when Claude starts
- `[claude] ...` - each chunk of assistant reasoning/text
- `[tool→] Bash {...}` - each tool call as it's invoked
- `[tool✓] ...` - the result of each tool call
- `[done] success duration=... cost=$...` - final summary

If `jq` isn't installed (`brew install jq`), the script falls back to printing raw JSON events.

### About the Notion MCP server name

The `mcp__claude_ai_Notion__*` prefix in the script's allow-list matches the Notion connector exposed by Claude Code Desktop. If your MCP server is registered under a different name, run `claude mcp list` to find the actual server identifier and adjust the prefix in `bin/team-digest-run.sh`. Alternatively, replace `--allowedTools "$ALLOWED_TOOLS"` with `--permission-mode bypassPermissions` for a script you fully control - simpler, broader.

### Sandboxing (security)

The headless run ingests untrusted third-party text (public GitHub PR/issue/release bodies, RSS, team-editable Notion pages). A prompt-injection payload in that content could try to make the model run arbitrary shell commands, so two layers guard the run:

1. **`--allowedTools` scoping** (in the wrapper) - the model may only invoke the pipeline's own `lib/` helpers plus `gh`/`mkdir`/`python3`/`eval`/`sleep` and write to the dry-run dir; bare `Bash`/`Write`/`Edit` are not granted. This is a *speed bump*, not a hard boundary: Claude Code's Bash allow-rules are not path-canonicalized.
2. **OS-level sandbox** (`bin/sandbox-settings.json`, applied per-invocation via `claude -p --settings`) - the real boundary. Kernel-enforced (macOS Seatbelt / Linux bubblewrap) filesystem confinement: the run may only write to `/tmp/team-digest-*` scratch dirs, so an injection cannot tamper with `~/.ssh`, `~/.claude`, or arbitrary files. Interactive Claude Code sessions are unaffected.

Requirements and caveats:

- **The config must sit next to the wrapper.** The symlink install finds it automatically; a copy install must copy `sandbox-settings.json` too (see above). If it is missing, the wrapper prints a loud `UNSANDBOXED` warning and continues.
- **Needs a sandbox backend.** Always present on macOS; on Linux install `bubblewrap`. `failIfUnavailable` makes the run fail rather than silently run unsandboxed.
- **Network stays ON** (the pipeline needs github.com, the Notion connector, and the Anthropic API), so the sandbox alone does not stop a determined injection from exfiltrating over the network. To close that, run the job inside a container/VM whose egress is limited to those hosts.
- `TEAM_DIGEST_NO_SANDBOX=1` disables the sandbox for debugging only.
- After changing the allow-list or sandbox config, validate with `bin/team-digest-run.sh <date> --dry-run` (skips the Notion write) before trusting the next scheduled run.

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
    <string>/Users/YOUR_USERNAME/.local/bin/team-digest-run.sh</string> <!-- pii-allow:launchd-placeholder -->
  </array>

  <!-- Every day at 01:00 UTC. TimeZone key (macOS 12+) pins the schedule to UTC
       so the trigger time does not drift with DST or timezone changes.
       Omitting the Weekday key means launchd fires every day (Sun-Sat). -->
  <key>TimeZone</key>
  <string>UTC</string>

  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>1</integer>
    <key>Minute</key><integer>0</integer>
  </dict>

  <key>StandardOutPath</key>
  <string>/Users/YOUR_USERNAME/.local/log/team-digest-launchd.log</string> <!-- pii-allow:launchd-placeholder -->

  <key>StandardErrorPath</key>
  <string>/Users/YOUR_USERNAME/.local/log/team-digest-launchd.log</string> <!-- pii-allow:launchd-placeholder -->

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
0 1 * * * "$HOME/.local/bin/team-digest-run.sh" > /dev/null 2>&1
```

The script handles its own logging via `TEAM_DIGEST_LOG` and `TEAM_DIGEST_RAW_LOG`. Cron will not fire missed runs on a sleeping machine - same caveat as launchd.

## GitHub Actions (self-hosted runner)

If you have a self-hosted runner with `claude` and `gh` configured, add a workflow:

```yaml
name: Team Daily Digest
on:
  schedule:
    - cron: '0 1 * * *'  # every day at 01:00 UTC
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

## Scheduling the weekly and monthly rollups

The same wrapper pattern covers `bin/team-weekly-run.sh` and `bin/team-monthly-run.sh`. Both are consumers - they read existing Notion pages rather than scanning sources - so schedule them AFTER the dailies (and, for the monthly, the weeklies) they depend on have landed.

- **Weekly** - run Monday morning, after the prior week's dailies are in. launchd uses `StartCalendarInterval` with `Weekday = 1`. The full plist is in [`docs/team-weekly-quickstart.md`](team-weekly-quickstart.md).
- **Monthly** - run on the 1st of each month (for the prior full calendar month), after that day's daily and the prior week's weekly have landed. The monthly runner defaults to the **Opus** model (synthesis is reasoning-heavy and runs once a month); override with `TEAM_DIGEST_MODEL`.

Monthly launchd plist - save as `~/Library/LaunchAgents/com.team-digest.team-monthly.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.team-digest.team-monthly</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/YOUR_USERNAME/.local/bin/team-monthly-run.sh</string> <!-- pii-allow:launchd-placeholder -->
  </array>

  <!-- 1st of every month at 10:00 local time. Day=1 (vs the weekly's Weekday=1). -->
  <key>StartCalendarInterval</key>
  <dict>
    <key>Day</key><integer>1</integer>
    <key>Hour</key><integer>10</integer>
    <key>Minute</key><integer>0</integer>
  </dict>

  <key>StandardOutPath</key>
  <string>/Users/YOUR_USERNAME/.local/log/team-monthly-launchd.log</string> <!-- pii-allow:launchd-placeholder -->

  <key>StandardErrorPath</key>
  <string>/Users/YOUR_USERNAME/.local/log/team-monthly-launchd.log</string> <!-- pii-allow:launchd-placeholder -->

  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
```

Replace `YOUR_USERNAME` with your macOS username (`whoami`), then `launchctl load ~/Library/LaunchAgents/com.team-digest.team-monthly.plist`.

Linux cron for the monthly (10:00 on the 1st):

```
0 10 1 * * "$HOME/.local/bin/team-monthly-run.sh" > /dev/null 2>&1
```

## Verifying the schedule

After setting up any scheduling option:

1. Wait for the next scheduled run (or trigger manually)
2. Check your digest database in Notion (the `database_id` from your `config.json`)
3. A new page should appear with that date and "Auto" status
4. If nothing appears, check `~/.local/log/team-digest.log` for errors

For repeated debugging without spamming Notion, use `--dry-run` - the markdown lands in `/tmp/team-digest-dry-runs/team-digest-<date>-v<N>.md` and you can `cat` or `diff` it before doing a real run. Files are ephemeral (cleared on reboot).
