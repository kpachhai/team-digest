# Scheduling the Team Daily Digest

Four options for automated daily runs. **If you're on macOS and want reliability without cloud dependencies, use Option 4 (launchd).**

## Option 1: Claude Code Desktop/Web Routine

Routines run on Anthropic's servers - they work when your laptop is closed. **Known limitation:** long-running digests (many repos, many Notion searches) can hit server-side session timeouts and produce partial output. If you experience this, use Option 4 (launchd) instead.

**Important:** Routines have no access to your local filesystem, so you must embed your config (and optionally your team profile) directly in the trigger prompt.

1. Open **Claude Code Desktop** or visit **claude.ai/code**
2. Create a new **Routine**
3. Paste the trigger prompt: the full content of `skills/team-digest/SKILL.md`
4. **At the end of the prompt**, append your config using the inline markers:
   ```
   <!-- SA-DIGEST-CONFIG -->
   {
     "team-digest": {
       "notion": {
         "config_page_id": "<your-config-page-id>",
         "database_id": "<your-database-id>"
       },
       "github": {
         "github_token": "<your-github-pat>",
         "orgs": [
           { "name": "your-org", "priority_repos": ["hiero-json-rpc-relay", "hiero-mirror-node", "hiero-consensus-node", "hiero-block-node", "hiero-improvement-proposals", "hiero-contracts", "solo", "hiero-sdk-js", "hiero-mirror-node-explorer"], "scan_all": false },
           { "name": "your-org", "priority_repos": ["hedera-docs", "hedera-agent-kit-js", "hedera-wallet-connect", "hedera-evm-testing", "stablecoin-studio", "asset-tokenization-studio", "guardian"], "scan_all": false },
           { "name": "your-org", "priority_repos": [], "scan_all": true }
         ]
       },
       "defaults": {
         "keywords": ["EVM", "smart contracts", "relay", "JSON-RPC", "mirror node", "HIP", "Hiero", "consensus", "block node", "SDK"],
         "partner_patterns": ["Meeting with", "Call with", "Catch up with", "Deep dive", "Sync with", "Check-in with", "Follow up with", "Debrief"]
       }
     }
   }
   <!-- /SA-DIGEST-CONFIG -->
   ```
   The `github_token` is required for full GitHub coverage in routines (issues and releases will be silently skipped without it due to unauthenticated API rate limits). See `docs/configuration.md` for how to create a minimal read-only PAT.
5. Optionally append your team profile:
   ```
   <!-- SA-DIGEST-PROFILE -->
   (paste your team-digest.md profile content here)
   <!-- /SA-DIGEST-PROFILE -->
   ```
6. Set schedule: **Weekdays at 7:00 AM ET** (or your preferred time)
7. Enable MCP connectors: **Notion**
8. Save

Each team member creates their own routine pointing at the same Notion database. See the "Appendix: Inline Config" section in SKILL.md for the full format reference.

## Option 2: Session-Local Cron

Within any Claude Code session, the `/team-digest` skill can be scheduled locally:

```
/schedule team-digest every weekday at 7am
```

Or use the CronCreate approach directly in chat - ask Claude to set up a cron job.

**Limitations:**
- Dies when the Claude Code session ends
- Auto-expires after 7 days
- Requires your laptop to be on and the session running

**Good for:** Testing the schedule before committing to a persistent routine.

## Option 3: Remote Trigger API

For programmatic setup. Requires your `environment_id` from claude.ai cloud settings.

```json
{
  "name": "Team Daily Digest",
  "cron_expression": "3 12 * * 1-5",
  "job_config": {
    "ccr": {
      "environment_id": "YOUR_ENVIRONMENT_ID",
      "session_context": {
        "model": "claude-sonnet-4-6",
        "allowed_tools": ["Bash", "Read", "Write", "Edit", "Glob", "Grep"]
      },
      "events": [
        {
          "data": {
            "uuid": "GENERATE_A_UUID_V4",
            "session_id": "",
            "type": "user",
            "parent_tool_use_id": null,
            "message": {
              "content": "PASTE_SKILL_MD_CONTENT_WITH_INLINE_CONFIG_APPENDED",
              "role": "user"
            }
          }
        }
      ]
    }
  }
}
```

The `cron_expression` `3 12 * * 1-5` means weekdays at 12:03 PM UTC. Adjust for your timezone.

**Note:** The Remote Trigger API is in research preview. The format may change. The Claude Code Desktop routine (Option 1) is more stable and easier to manage.

## Option 4: Local macOS launchd (Most Reliable for Local Use)

Runs on your Mac via launchd - survives sleep/wake cycles and requires no cloud account. Uses your local `gh` auth and Notion MCP config directly, so no inline config embedding is needed. **Requires your Mac to be on (not off) at the scheduled time.**

### 1. Create the wrapper script

```bash
mkdir -p ~/.local/bin ~/.local/log
```

Create `~/.local/bin/team-digest-run.sh`:

```bash
#!/bin/bash

# Ensure Homebrew and other tools are on PATH
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

LOG="$HOME/.local/log/team-digest.log"
echo "" >> "$LOG"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG"

claude -p "/team-digest" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" 2>&1 | tee -a "$LOG"
```

Make it executable:

```bash
chmod +x ~/.local/bin/team-digest-run.sh
```

Test it runs correctly before scheduling:

```bash
~/.local/bin/team-digest-run.sh
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

**Note:** launchd will not fire a missed run if your Mac was asleep or off at the scheduled time. If you need catch-up on missed days, run `/team-digest YYYY-MM-DD` manually.

## Verifying the Schedule

After setting up any scheduling option:

1. Wait for the next scheduled run (or trigger manually with `/team-digest`)
2. Check your digest database in Notion (the `database_id` from your `config.json`)
3. A new page should appear with today's date and "Auto" status
4. If nothing appears, check the Claude Code session logs or routine history for errors
