# team-digest

A modular, extensible digest system that aggregates activity from multiple sources (GitHub, Notion, meetings) into structured summaries delivered to Notion. Built on Claude Code with zero infrastructure.

Each team gets its own skill and configuration. New sources and cadences can be added without changing existing ones.

## Architecture

```
team-digest/
├── config.template.json   # Committed template with empty Notion IDs
├── config.json            # Your Notion IDs (gitignored, created by setup.sh)
├── .gitignore
├── setup.sh               # First-time setup: creates config, checks prereqs, installs skills
├── update.sh              # After git pull: syncs skills and config, flags new template keys
├── skills/                # One skill per team/digest type
│   ├── team-digest/         # team daily digest (ships today)
│   └── <team>-digest/     # Future: engineering, product, etc.
├── profiles/              # Team profiles describing role, priorities, and relevance criteria
│   ├── team-digest.template.md   # team template (committed)
│   ├── my-team-digest.template.md  # Eng team template (committed)
│   └── team-digest.md            # Your personalized copy (gitignored)
├── docs/                  # Setup, configuration, scheduling, troubleshooting
└── README.md
```

**Core concept:** A digest is a combination of **sources** (where data comes from) and a **cadence** (how often it runs). Each team configures which sources they care about and how they want the output structured.

```
Sources (pluggable)          Cadence (configurable)        Output
─────────────────           ──────────────────────        ──────
GitHub org activity    ─┐
Notion keywords        ─┤── daily / weekly / monthly ──> Notion database
Notion meetings        ─┘
RSS feeds (future)     ─┐
Slack channels (future)─┤── (same cadence options)  ──> (same output)
Blog feeds (future)    ─┘
```

## Current: Team Daily Digest

The first skill ships with this repo - a daily digest for the team.

### What It Scans

1. **GitHub Activity** - PRs, issues, and releases across all 40+ your-org repos. Priority repos get rich narrative summaries; others get a highlights table.
2. **Notion Keyword Monitor** - Searches the entire Notion workspace for pages matching configurable keywords (EVM, smart contracts, HIP, etc.).
3. **Partner Conversations** - Finds meeting notes and partner discussions, groups by company, extracts action items.

### Quick Start (under 10 minutes)

**Prerequisites:**

- [Claude Code](https://claude.ai/code) installed and authenticated
- [GitHub CLI](https://cli.github.com) installed and authenticated (`gh auth login`)
- Notion MCP server connected in Claude Code (Settings > MCP Servers > Notion)

**Install:**

```bash
git clone <this-repo>
cd team-digest
./setup.sh
```

The setup script verifies prerequisites, installs the `/team-digest` skill to `~/.claude/skills/`, and checks access to the your-org GitHub org.

**Run your first digest:**

```
/team-digest
```

Open Claude Code in any directory and type the command above. The output lands in your Notion digest database (configured in `config.json`).

**Run for a specific date (backfill):**

```
/team-digest 2026-04-20
```

Useful for catching up on missed days. GitHub data is fully accurate for any past date. Notion sections (keywords, partner conversations) are limited to pages **created** on that date - pages that existed before but were edited that day will not appear (Notion MCP search limitation).

**Automate it:** See [docs/scheduling.md](docs/scheduling.md) for daily automation options.

### Updating After Git Pull

When the repo is updated with new skills or changes:

```bash
git pull
./update.sh
```

`update.sh` syncs all skills to `~/.claude/skills/`, updates your global config, and flags any new digest keys in the template that you need to add to your `config.json`. Restart Claude Code if a session is already open.

| Script      | When to Use                                                         |
| ----------- | ------------------------------------------------------------------- |
| `setup.sh`  | First time setup (creates config, checks prereqs, installs skills)  |
| `update.sh` | After `git pull` (syncs skills and config, flags new template keys) |

### Customization

Three layers of configuration - no hardcoded Notion links anywhere:

1. **`config.json`** (gitignored) - Your Notion page/database IDs and GitHub org structure. Created from `config.template.json` by `setup.sh`.
2. **Notion config page** - Live, team-editable settings (keywords, partner patterns). Anyone on the team can update it without touching files.
3. **`profiles/team-digest.md`** (gitignored) - Your team profile. Describes your role, what you care about, and what "relevant" means for your work. Claude reads this to write the **Relevance** section in each digest. Edit it to match your actual priorities.

`setup.sh` copies `profiles/team-digest.template.md` to `profiles/team-digest.md` on first run. Edit the `.md` file directly - it's yours and won't be overwritten by `update.sh`.

See [docs/configuration.md](docs/configuration.md).

## How It Works

```
/team-digest (or scheduled trigger)
    |
    v
[0] Read config.json (Notion IDs, GitHub orgs) + team profile (role, priorities)
    |
    v
[1] Fetch Notion config page (live keywords/patterns) or fall back to defaults
    |
    +---> [2] gh CLI: scan GitHub orgs PRs, issues, releases
    |            Priority repos: synthesized narrative + Relevance (from profile)
    |            Other repos: summary table
    |
    +---> [3] Notion MCP: search workspace for keyword matches
    |
    +---> [4] Notion MCP: find meeting notes / partner conversations
    |
    v
[5] Notion MCP: write combined digest page to database
```

Each source runs independently. If one fails, the others still run and the digest is produced with a failure indicator for the broken section.

## Adding a New Team

To create a digest for another team (e.g., engineering):

1. Create a new Notion config page and database for the team
2. Add a new top-level key to `config.json` and `config.template.json`:
   ```json
   {
     "team-digest": { ... },
     "my-team-digest": {
       "notion": { "config_page_id": "...", "database_id": "..." },
       "github": { "orgs": [ ... ] },
       "defaults": { "keywords": [ ... ], "partner_patterns": [ ... ] }
     }
   }
   ```
3. Copy `skills/team-digest/SKILL.md` to `skills/my-team-digest/SKILL.md`
4. In the copied skill, change all occurrences of `team-digest` to `my-team-digest` (the config key, the skill name, the callout title). Convention: the config key always matches the skill directory name.
5. Adjust the GitHub orgs, priority repos, keywords, and partner patterns to match the new team's focus
6. Copy `profiles/team-digest.template.md` to `profiles/my-team-digest.template.md` and rewrite it to describe the engineering team's role, priorities, and what "relevant" means for them
7. Run `./update.sh` to install the new skill and sync the new profile
8. The team can now use `/my-team-digest` in Claude Code

Each team's skill is independent - different config keys, different sources, different output databases. No Notion IDs are hardcoded in any committed file.

## Future Extensions

### New Sources

The digest architecture is designed to add new data sources without changing existing skills. Each source is a self-contained scan step that produces structured output.

| Source                 | Status  | How It Would Work                                                                     |
| ---------------------- | ------- | ------------------------------------------------------------------------------------- |
| GitHub org activity    | Shipped | `gh` CLI scans PRs, issues, releases                                                  |
| Notion keyword monitor | Shipped | Notion MCP semantic search                                                            |
| Notion meeting notes   | Shipped | Notion MCP pattern-based search                                                       |
| RSS / Atom feeds       | Planned | `curl` + XML parsing; scan blog feeds, release notes, ecosystem news                  |
| Slack channels         | Planned | Slack MCP (when available) or Slack API; scan channels for keyword-relevant messages  |
| Blog feeds             | Planned | Web fetch + summarization; monitor Hedera blog, partner blogs, ecosystem publications |
| Twitter/X lists        | Planned | X API; monitor ecosystem accounts for announcements                                   |
| Linear/Jira issues     | Planned | Project management MCP; track sprint progress, blockers                               |
| Google Docs/Drive      | Planned | Google Drive MCP (already available in Claude Code); scan shared docs for updates     |
| Calendar events        | Planned | Calendar integration; surface upcoming meetings, deadlines, events                    |

Adding a source means adding a new step to the skill's process section and a new configuration block to the Notion config page.

### Cadence Rollups

Daily digests are the atomic unit. Higher-cadence digests are rollups that summarize lower-cadence ones.

| Cadence   | Status  | Input                                  | Output                                                                                               |
| --------- | ------- | -------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Daily     | Shipped | Raw sources (GitHub, Notion, meetings) | One Notion page per day                                                                              |
| Weekly    | Planned | Monday-Friday daily digests            | One summary page highlighting the week's most significant items, trends, and unresolved action items |
| Monthly   | Planned | Weekly digests for the month           | One page with themes, metrics (PRs merged, partners engaged), and strategic observations             |
| Quarterly | Planned | Monthly digests                        | Executive-level summary with trends, comparisons to prior quarter, team highlights                   |

**How rollups work:** A weekly digest skill reads the last 5 daily digest pages from the Notion database, synthesizes them into themes and highlights, and writes a weekly summary page. The daily pages become the "source of truth" that higher cadences reference - no re-scanning of raw sources needed.

### Organizational Memory

As digests accumulate over weeks and months, the Notion database becomes a searchable organizational memory:

- **"What happened with Company X?"** - Search the database for partner mentions across all digests
- **"When did we start seeing HIP-1195 activity?"** - Filter digests by keyword to find the first mention
- **"What were the biggest changes last quarter?"** - Quarterly rollup provides the answer
- **"Who was working on the Pectra upgrade?"** - GitHub activity sections track contributors by name

Future skills could query this database directly to answer questions, generate reports, or surface trends over time.

### Multi-Team Support

Each team creates their own skill, config page, and database. A future "org digest" skill could aggregate across team databases to produce a cross-functional summary for leadership.

```
team ──> /team-digest ──> Team Daily Digest database
Eng team ─> /my-team-digest ─> Eng Daily Digest database
Product ──> /pm-digest ──> PM Daily Digest database
                |
                v
         /org-digest (future)
                |
                v
         Org Weekly Summary database
```

## Configuration Files

| File                                       | Committed       | Purpose                                                               |
| ------------------------------------------ | --------------- | --------------------------------------------------------------------- |
| `config.template.json`                     | Yes             | Template with empty Notion IDs; starting point for new users          |
| `config.json`                              | No (gitignored) | Your actual Notion IDs; created by `setup.sh` from template           |
| `~/.config/team-digest/config.json`        | N/A (local)     | Global copy synced by `setup.sh`; skills read from here               |
| `profiles/<team>.template.md`              | Yes             | Team profile template; describes role, priorities, relevance criteria |
| `profiles/<team>.md`                       | No (gitignored) | Your personalized profile; created from template by `setup.sh`        |
| `~/.config/team-digest/profiles/<team>.md` | N/A (local)     | Global copy synced by `setup.sh`; skills read from here               |

## Requirements

| Tool            | Version  | Purpose                                   |
| --------------- | -------- | ----------------------------------------- |
| Claude Code     | 2.1+     | Runs digest skills and scheduled triggers |
| GitHub CLI (gh) | 2.0+     | Scans GitHub orgs for activity            |
| Notion MCP      | Built-in | Searches Notion and writes digest pages   |

Zero additional SaaS costs. Everything runs on existing Claude Code and GitHub subscriptions.

## Docs

- [docs/configuration.md](docs/configuration.md) - Customize keywords, repos, partner patterns
- [docs/scheduling.md](docs/scheduling.md) - Set up automated daily runs
- [docs/troubleshooting.md](docs/troubleshooting.md) - Common issues and fixes
