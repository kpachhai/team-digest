# Configuration

team-digest uses a two-layer configuration system:

1. **Local config file** (`config.json`, gitignored) - Notion IDs and defaults per digest. Each user has their own.
2. **Notion config page** (per digest) - Live settings (keywords, repos, patterns) that anyone on the team can edit.

## Local Config File

The config file lives at the repo root as `config.json` (gitignored). It is also synced to `~/.config/team-digest/config.json` by `setup.sh` so skills can find it from any directory.

`config.template.json` is the committed template with empty Notion IDs. Run `setup.sh` to create `config.json` from the template, then fill in your IDs.

### Structure

```json
{
  "team-digest": {
    "notion": {
      "config_page_id": "<32-char hex from config page URL>",
      "database_id": "<32-char hex from database URL>"
    },
    "github": {
      "orgs": [
        {
          "name": "your-org",
          "priority_repos": ["repo-1", "repo-2"],
          "scan_all": false
        }
      ]
    },
    "defaults": {
      "keywords": ["keyword-1", "keyword-2"],
      "partner_patterns": ["Meeting with", "Call with"]
    }
  }
}
```

Each digest type is a top-level key. Add a new key for each new team digest.

### GitHub authentication

The skill uses your local `gh` CLI authentication. Run `gh auth login` once (any scope is fine for public repos; for private repos you need at least `repo` read access). The `bin/team-digest-run.sh` headless entry point also inherits your local `gh` auth - cron and launchd both work without any token configuration.

If `gh auth status` fails when the digest runs, the skill aborts with an actionable error rather than producing a partial digest. There is no token-in-config fallback.

### Finding Notion IDs

You only need two IDs, and both are found the same way:

1. Open the Notion page or database in your browser
2. Look at the URL: `notion.so/<32-char-hex-id>`
3. That hex string is the ID

| Config Field | What to Open |
|---|---|
| `config_page_id` | The Notion configuration page |
| `database_id` | The Notion digest database |

The internal `data_source_id` (needed by the Notion MCP API to write pages) is derived automatically at runtime - you never need to look it up.

### Joining an Existing Team

If the Notion database and config page already exist (a teammate set them up), ask them for the three IDs and paste them into your `config.json`. You do not need to create new Notion resources.

## Notion Config Page

The Notion config page holds the live, team-editable settings. The page ID is stored in your local `config.json`; the skill fetches the page at runtime.

### Editable Settings

**Priority Repos** - Repos that get full narrative summaries. All other repos in the org get a summary table entry.
- To add: add a bullet point with the repo name
- To remove: delete the bullet point

**Keywords** - Notion workspace search terms. Results are deduplicated across overlapping keywords.
- To add: add a bullet point
- To remove: delete the bullet point
- Tips: use specific terms ("JSON-RPC" not "API"); multi-word works ("smart contracts"); search is semantic

**Partner Conversation Patterns** - Phrases that identify meeting notes and partner discussions.
- To add: add a bullet point with the phrase
- To remove: delete the bullet point
- Tips: match your team's actual naming conventions for meeting notes

**Organization** - The GitHub org to scan.

**Scan Window** - How far back to scan (default: 24 hours).

### Fallback Behavior

If the Notion config page is unreachable (MCP not connected, permissions issue), the digest falls back to the `defaults` section in your local `config.json`. This ensures the GitHub section still works even without Notion access.

## Adding a New Team Digest

1. Create a new Notion config page for the team (duplicate an existing one and update the settings)
2. Create a new Notion database for the team's digest output
3. Add a new key to `config.json` and `config.template.json`:
   ```json
   {
     "team-digest": { ... },
     "my-team-digest": {
       "notion": {
         "config_page_id": "<new config page ID>",
         "database_id": "<new database ID>"
       },
       "github": {
         "org": "your-org"
       },
       "defaults": { ... }
     }
   }
   ```
4. Copy `skills/team-digest/SKILL.md` to `skills/my-team-digest/SKILL.md`
5. Update the skill name and description; change it to read the `my-team-digest` key from config
6. Run `./setup.sh` to install all skills
