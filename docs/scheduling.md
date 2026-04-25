# Scheduling the Team Daily Digest

Three options for automated daily runs, from simplest to most persistent.

## Option 1: Claude Code Desktop/Web Routine (Recommended)

The easiest way to get a persistent, automated daily digest. Routines run on Anthropic's servers - they work when your laptop is closed.

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

## Verifying the Schedule

After setting up any scheduling option:

1. Wait for the next scheduled run (or trigger manually with `/team-digest`)
2. Check your digest database in Notion (the `database_id` from your `config.json`)
3. A new page should appear with today's date and "Auto" status
4. If nothing appears, check the Claude Code session logs or routine history for errors
