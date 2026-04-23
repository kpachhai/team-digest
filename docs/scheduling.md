# Scheduling the DA Daily Digest

Three options for automated daily runs, from simplest to most persistent.

## Option 1: Claude Code Desktop/Web Routine (Recommended)

The easiest way to get a persistent, automated daily digest.

1. Open **Claude Code Desktop** or visit **claude.ai/code**
2. Create a new **Routine**
3. Paste the trigger prompt (the full content of `skills/da-digest/SKILL.md` from this repo)
4. Set schedule: **Weekdays at 7:00 AM ET** (or your preferred time)
5. Enable MCP connectors: **Notion**
6. Save

The routine runs on Anthropic's servers - it works when your laptop is closed. Each team member creates their own routine pointing at the same Notion database.

## Option 2: Session-Local Cron

Within any Claude Code session, the `/da-digest` skill can be scheduled locally:

```
/schedule da-digest every weekday at 7am
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
  "name": "DA Daily Digest",
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
              "content": "PASTE_THE_TRIGGER_PROMPT_HERE",
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

## Verifying the Schedule

After setting up any scheduling option:

1. Wait for the next scheduled run (or trigger manually with `/da-digest`)
2. Check your digest database in Notion (the `database_id` from your `config.json`)
3. A new page should appear with today's date and "Auto" status
4. If nothing appears, check the Claude Code session logs or routine history for errors
