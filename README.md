# team-digest

A modular, extensible digest system that aggregates activity from multiple sources (GitHub, Notion pages and meetings, your Notion Favorites, pages you authored, RSS/Atom blog feeds, and GitHub spec-set commits like EIPs) into structured summaries delivered to Notion. Daily digests synthesize one day; weekly digests roll up a full week. Built on Claude Code with zero infrastructure.

Each team gets its own skill and configuration. New sources and cadences can be added without changing existing ones.

## Architecture

```
team-digest/
├── bin/                   # Headless terminal entry points (claude -p wrappers)
│   ├── team-digest-run.sh   # Daily - symlink onto $PATH for cron/launchd
│   └── team-weekly-run.sh   # Weekly rollup
├── config.template.json   # Committed template with empty Notion IDs
├── config.json            # Your Notion IDs (gitignored, created by setup.sh)
├── .gitignore
├── setup.sh               # First-time setup: creates config, checks prereqs, installs skills + lib/
├── update.sh              # After git pull: syncs skills, lib/, config, profiles
├── skills/                # One skill per team/digest type and cadence
│   ├── team-digest/         # Daily
│   │   ├── SKILL.md       # Skill body: orchestration + MCP calls + writing rules
│   │   └── lib/           # compute-window, load-config, fetch-github-*, fetch-rss, fetch-gh-commits,
│   │                       # fetch-hip-* (4 helpers: updates, implementation-prs, release-refs,
│   │                       # timeline-correlations), extract-hip-refs, refresh-hip-index,
│   │                       # calibrate-hip-matches, phase2-gate (15 helpers total)
│   └── team-weekly/         # Weekly rollup of daily digests
│       ├── SKILL.md       # Reads dailies from Notion, synthesizes cross-day themes
│       └── lib/           # compute-week-window
├── profiles/              # Team profiles describing role, priorities, glossary
│   ├── team-digest.template.md   # Committed minimal placeholder (setup.sh copies to team-digest.md)
│   ├── team-digest.example.md    # Committed worked example (Solutions Architect profile)
│   └── team-digest.md            # Your personalized copy (gitignored)
├── docs/                  # Setup, configuration, scheduling, troubleshooting
└── README.md
```

**Core concept:** A digest is a combination of **sources** (where data comes from) and a **cadence** (how often it runs). Each team configures which sources they care about and how they want the output structured.

```
Sources (pluggable)                  Cadence              Output
─────────────────                    ───────              ──────
GitHub org PRs/issues/releases  ─┐
Notion keywords                  │
Notion Favorites + 1-hop descent ├── daily   ───────> Notion database
HIP repo activity                │   (team-digest)         (one page per day,
Partner conversation patterns    │                        Digest Type=Combined)
RSS/Atom blog feeds              │
GitHub commits to spec sets     ─┘

Last 5-7 daily digests         ─┐
                                ├── weekly  ───────> Same Notion database
                                │   (team-weekly)        (one page per week,
                                                        Digest Type=Weekly)
```

## Skills shipped today

This repo ships two skills out of the box - one for each cadence:

- **`/team-digest`** - the daily digest (the workhorse)
- **`/team-weekly`** - the weekly rollup (synthesizes the past week's daily digests)

Both write to the SAME Notion database, distinguished by the `Digest Type` property (`Combined` vs. `Weekly`).

### What `/team-digest` scans (six sources)

1. **GitHub Activity** - PRs, issues, and releases across configured GitHub orgs. Priority repos get rich narrative summaries with synthesized themes, **Relevance** notes, and Mermaid diagrams for architectural changes; every other repo with activity in the date window gets a row in the **Other Active Repos** table.
2. **Industry News** - public RSS/Atom feeds plus GitHub commit-watching for spec sets that don't publish RSS. Configured via `rss_feeds` in `config.json`. Items dated to the digest day are grouped by category in an **Industry News** section.
3. **HIP Activity** - HIPs touched in `hiero-ledger/hiero-improvement-proposals` on the digest day, with status-change detection (e.g., `Status: Draft -> Last Call`) and cross-references to implementation PRs/commits across `hiero-ledger/*`. Four matching strategies fire per HIP (Mechanism A regex annotation, Mechanism B per-HIP `gh search`, Strategy 2 release-note analysis, Strategy 3 timeline correlation), each emitting matches with a unified `confidence: high|medium|low` field. High matches render in the main HIP Activity section; medium and low surface in a `### Lower-Confidence Matches` subsection when `TEAM_DIGEST_HIP_VERBOSE=1`. A calibration helper measures precision/recall against a strategy-independent labeled set. Configurable via `hip_tracking` in `config.json`; opt out with `hip_tracking.enabled: false`. See [docs/hip-tracking.md](docs/hip-tracking.md).
4. **Notion Keyword Monitor** - searches the Notion workspace for pages **created** on the digest day matching configured keywords. One narrative summary per matched page with linked title, matched keywords, and relevance.
5. **Notion Favorites** - reads a user-curated list of Notion page URLs from a **Favorites** heading on the Notion config page (since Notion's API does not expose sidebar Favorites). For each favorite, fetches `last_edited_time`; if the page was edited on the digest day it gets a summary. Single-level child descent: if a favorite is an *index* page, the digest also fetches each linked page (one hop, capped at 50 children) and includes those edited that day.
6. **Partner Conversations** - searches Notion for pages with titles matching configured patterns (`Meeting with`, `Call with`, `Catch up with`, `Deep dive`, etc.). Grouped by company, with extracted action items.

Pages found through multiple sources are deduplicated by page ID across sections; the user explicitly cares about Favorites, so a favorite that ALSO matched a keyword stays in the Favorites section with a back-link rather than being silently dropped.

### What `/team-weekly` does (cross-day synthesis, no re-scan)

`/team-weekly` reads the past week's daily digests already in Notion (filtered by `Digest Type = Combined` and date in [Mon, Sun]) and synthesizes seven cross-day themes:

- **Top GitHub Themes** - repos with sustained activity across 3+ days, with linked PRs/issues
- **Releases This Week** - every release from any daily, in a single linked GFM table
- **HIP Movement This Week** - HIPs touched 2+ days, status arcs across the week, cross-repo implementation activity per HIP. Synthesized from the dailies' `HIP Activity` sections - no re-scan.
- **Partner Momentum** - companies that came up multiple days, with multi-day "Open threads"
- **Notion Content Pulse** - keywords that spanned multiple days, with example linked pages
- **Industry News Roundup** - deduplicated RSS items across the week, grouped by category
- **Favorites Movement** - favorited pages that updated on 2+ days (active work) vs. single-day touches
- **Day-by-Day Index** - one linked entry per daily for fast navigation

Critically, `/team-weekly` does NOT re-scan GitHub, Notion, or RSS - the dailies have already done that work. The weekly is a pure synthesis layer over the daily output, which keeps token cost bounded and avoids drift between what each cadence "saw."

### Quick Start (under 10 minutes)

**Prerequisites:**

- [Claude Code](https://claude.ai/code) installed and authenticated
- [GitHub CLI](https://cli.github.com) installed and authenticated (`gh auth login`). For higher API rate limits or private-org access, export `GH_TOKEN=<your_PAT>` in the shell that runs the digest — see [docs/configuration.md](docs/configuration.md#github-authentication) for details.
- Notion MCP server connected in Claude Code (Settings > MCP Servers > Notion). If you don't already have Notion pages set up for the digest, `/team-digest setup` can create them for you — see [docs/configuration.md](docs/configuration.md#bootstrap-your-notion-workspace) for the full flow.

**Install:**

```bash
git clone <this-repo>
cd team-digest
./setup.sh
```

The setup script verifies prerequisites, installs the `/team-digest` and `/team-weekly` skills to `~/.claude/skills/`, and checks access to the first GitHub org configured in `config.json`.

**Run your first daily digest:**

```
/team-digest
```

Open Claude Code in any directory and type the command above. The output lands in your Notion digest database (configured in `config.json`).

**Run for a specific date (backfill):**

```
/team-digest 2026-04-20
```

Useful for catching up on missed days. GitHub data is fully accurate for any past date. Notion sections (keywords, partner conversations, pages-I-created) are limited to pages **created** on that date - pages that existed before but were edited that day will not appear in those sections (Notion MCP search limitation). The Favorites section uses `last_edited_time` instead of `created_time`, so it correctly catches edits to existing pages.

**Preview a digest without writing to Notion (`--dry-run`):**

```
/team-digest --dry-run                # yesterday's digest, written to a local file
/team-digest 2026-04-20 --dry-run     # specific date, local file
```

The output goes to `/tmp/team-digest-dry-runs/team-digest-<DATE>-v<N>.md`. Use this to validate refactors or preview a digest before doing a real run that overwrites a Notion page. Files are ephemeral (cleared on reboot) - copy them out if you want to keep one.

**Run the weekly rollup:**

```
/team-weekly                                                # last full ISO week (Mon-Sun)
/team-weekly 2026-05-07                                     # the week containing this date
/team-weekly --from 2026-04-25 --to 2026-05-03              # arbitrary range (post-conf recap, missed-week catch-up, sprint window)
/team-weekly --dry-run                                      # preview, no Notion write
/team-weekly --from 2026-04-25 --to 2026-05-03 --dry-run    # custom range + dry run
```

Reads the past week's daily digests already in Notion (no re-scanning) and writes a synthesized weekly summary to the same database. Prerequisite: at least 5-7 dailies for the target week must already exist in Notion. See [docs/team-weekly-quickstart.md](docs/team-weekly-quickstart.md) for the full walkthrough.

**Run from the terminal (cron / launchd / scripts):**

```bash
bin/team-digest-run.sh                       # yesterday's daily (writes to Notion)
bin/team-digest-run.sh 2026-04-20 --dry-run  # specific daily, local file
bin/team-weekly-run.sh                       # last full week's rollup
bin/team-weekly-run.sh --dry-run             # preview the rollup, no Notion write
```

Both wrappers invoke `claude -p` headlessly with the Notion MCP tools allow-listed. Same skill, same flags, same output - just non-interactive entry points. Symlink to `~/.local/bin/` for convenience.

**Automate it:** See [docs/scheduling.md](docs/scheduling.md) for the launchd plist, cron syntax, and a GitHub Actions example. Recommended cadence: `bin/team-digest-run.sh` every weekday morning, `bin/team-weekly-run.sh` Monday morning after Friday's daily lands.

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

### Running on a second machine

If you already have `team-digest` set up on one machine and want to mirror it onto another (different work / personal split, new laptop, etc.), the deep-merge in `update.sh` makes this clean:

1. **Clone + setup on the second machine.** `git clone` the repo, run `./setup.sh`. This creates a placeholder `~/.config/team-digest/config.json` and copies the minimal profile template.
2. **Sync the machine-local files yourself.** `config.json` and `profiles/team-digest.md` are gitignored (one per machine). Two paths:
   - **From scratch**: edit `~/.config/team-digest/config.json` to fill Notion IDs, edit `~/.config/team-digest/profiles/team-digest.md` for your team.
   - **Mirror from your other machine**: copy those two files across via a transfer method you trust (chezmoi, rsync, manual paste). Both files contain machine-local content - Notion IDs, employer-specific orgs, your live SA profile.
3. **Re-run `./update.sh`** so the helpers, skills, and matches-sidecar wiring all land in `~/.claude/skills/team-digest/`.
4. **First dry-run validation.** `bin/team-digest-run.sh <yesterday> --dry-run` should produce a richer digest (more orgs scanned, more RSS feeds, full Notion keyword surface, partner conversations) than the test machine could because the Notion workspace is real.
5. **Production cron.** Install the launchd plist (macOS) or cron entry (Linux) per `docs/scheduling.md`. The plist defaults to `bin/team-digest-run.sh` (no flags) which runs yesterday's daily.

The labeled set and calibration baseline (`~/.config/team-digest/hip-code-mapper-labeled-set.json`, `hip-calibration-baseline.json`) are machine-local by design - each machine can have its own. If you want the same labeled set on the second machine, copy that file across too.

### Customization

Three layers of configuration - no hardcoded Notion links anywhere:

1. **`config.json`** (gitignored) - Your Notion page/database IDs and GitHub org structure. Created from `config.template.json` by `setup.sh`.
2. **Notion config page** - Live, team-editable settings (keywords, partner patterns). Anyone on the team can update it without touching files.
3. **`profiles/team-digest.md`** (gitignored) - Your team profile. Describes your role, what you care about, and what "relevant" means for your work. Claude reads this to write the **Relevance** section in each digest. Edit it to match your actual priorities.

`setup.sh` copies `profiles/team-digest.template.md` (a minimal placeholder) to `profiles/team-digest.md` on first run. If you'd rather start from a worked example, copy `profiles/team-digest.example.md` (a fully-populated Solutions Architect profile, ~200 lines) over your personalized file: `cp profiles/team-digest.example.md profiles/team-digest.md`. Edit the `.md` file directly - it's yours and won't be overwritten by `update.sh`.

See [docs/configuration.md](docs/configuration.md).

## How It Works

### `/team-digest` pipeline

```
/team-digest [YYYY-MM-DD] [--dry-run]
    |
    v
[0] Argument parsing (date arg, --dry-run, setup, config) + load config
    |    via lib/load-config.sh - validates Notion IDs are present
    |    + load team profile + Project Glossary (jargon expansion source)
    |    via lib/compute-window.sh - resolves DATE_LABEL / START / END (UTC)
    v
[1] notion-fetch the Notion config page (Keywords, Title Patterns,
    Favorites list, Track-Pages-Created-By email, data_source_id)
    |
    +---> [2]  lib/fetch-github-prs.sh / fetch-github-issues.sh /
    |          fetch-github-releases.sh - parallel across all orgs
    |          (Priority repos: narratives with Mermaid diagrams + Relevance.
    |           Other Active Repos: every repo with activity gets a row.)
    |
    +---> [2.5] lib/fetch-rss.sh / fetch-gh-commits.sh - parallel across
    |           all rss_feeds entries (RSS for blogs, github:// for spec sets)
    |
    +---> [3]  notion-search keywords, scoped to created_date_range = DATE_LABEL
    |
    +---> [3.5] For each Favorite URL: notion-fetch + check last_edited_time.
    |           For favorited *index* pages: also fetch one-level-deep children
    |           (capped at 50 per parent).
    |
    +---> [4]  notion-search partner-conversation title patterns
    |
    v
[4.5] Pre-Write Link Audit (mandatory): every repo/PR/issue/release/
      Notion-page is a markdown link; no \n in Mermaid labels;
      first-mention expansions present; HTML stripped from RSS summaries
    |
    v
[5] notion-create-pages → Team Daily Digest database
    OR (if --dry-run) Write tool → /tmp/team-digest-dry-runs/team-digest-<DATE>-v<N>.md
```

Each source runs independently. If one fails (org unreachable, malformed feed, deleted page), the others still run and the digest is produced with a failure indicator for the broken section instead of aborting.

### `/team-weekly` pipeline

```
/team-weekly [YYYY-MM-DD] [--dry-run]
    |
    v
[0] Argument parsing + load shared team-digest config (no separate team-weekly config)
    |
    v
[1] lib/compute-week-window.sh resolves to ISO week (Mon-Sun) timestamps,
    WEEK_LABEL (e.g. 2026-W19), START / END
    |
    v
[2] notion-query-data-sources on the Team Daily Digest database, filtered
    by Digest Type = Combined and date in [WEEK_START, WEEK_END]
    Returns up to 7 daily page IDs/URLs (one per weekday)
    |
    v
[3] notion-fetch each daily page in parallel - capture full content
    Missing days are noted in the Day-by-Day Index, not aborted on
    |
    v
[4] Synthesize 7 cross-day themes (no re-scanning of raw sources):
      - Top GitHub Themes      - Notion Content Pulse
      - Releases This Week     - Industry News Roundup (deduplicated)
      - Partner Momentum       - Favorites Movement
                               - Day-by-Day Index
    |
    v
[4.5] Same Pre-Write Link Audit as /team-digest
    |
    v
[5] notion-create-pages → same Team Daily Digest database with
    Digest Type = Weekly, date = WEEK_END (Sunday)
    OR (if --dry-run) Write → /tmp/team-digest-dry-runs/team-weekly-<WEEK_LABEL>-v<N>.md
```

The weekly's value is the synthesis - patterns that span days that no single daily can show. Token cost is bounded because the weekly reads pre-summarized markdown, not raw GitHub/Notion/RSS data.

## Adding a New Team Digest

The default `team-digest` skill is the public, generic shell. Any additional team-specific skill you create lives entirely in your local checkout - don't commit it to this repo. The `.gitignore` already covers `profiles/*.md` and `config.json`; any new team's skill folder under `skills/` is also ignored unless you explicitly add it.

To create a digest for another team locally (e.g., engineering, product, growth):

1. Create a new Notion config page and database for the team.
2. Add a new top-level key to your local `config.json` (NOT `config.template.json`):
   ```json
   {
     "team-digest": { ... },
     "<my-team>-digest": {
       "notion": { "config_page_id": "...", "database_id": "..." },
       "github": { "orgs": [ ... ] },
       "defaults": { "keywords": [ ... ], "partner_patterns": [ ... ] }
     }
   }
   ```
3. Copy the entire `skills/team-digest/` directory to `skills/<my-team>-digest/`. The `lib/*.sh` helpers are reusable as-is.
4. In `skills/<my-team>-digest/SKILL.md`, change all occurrences of `team-digest` to `<my-team>-digest` (config key, skill name, callout title, helper invocations). Convention: the config key always matches the skill directory name.
5. Adjust the GitHub orgs, priority repos, keywords, and partner patterns to match the new team's focus.
6. Copy `profiles/team-digest.template.md` to `profiles/<my-team>-digest.md` and personalize it. (No `.template.md` needed for local-only skills - go straight to the personalized copy.)
7. Copy `bin/team-digest-run.sh` to `bin/<my-team>-digest-run.sh` and search-replace `team-digest` → `<my-team>-digest`.
8. Run `./update.sh` to install. Verify with `<my-team>-digest --dry-run`.

Each team's skill is independent - different config keys, different sources, different output databases. No Notion IDs are hardcoded in any committed file.

## Future Extensions

### New Sources

The digest architecture is designed to add new data sources without changing existing skills. Each source is a self-contained scan step that produces structured output.

| Source                       | Status  | How It Works                                                                                                  |
| ---------------------------- | ------- | ------------------------------------------------------------------------------------------------------------- |
| GitHub org activity          | Shipped | `lib/fetch-github-prs.sh` / `fetch-github-issues.sh` / `fetch-github-releases.sh` - `gh` CLI + Python parsing |
| Notion keyword monitor       | Shipped | `notion-search` MCP scoped to `created_date_range`                                                            |
| Notion Favorites + 1-hop     | Shipped | Favorites list on the Notion config page; per-favorite `notion-fetch` + child-page descent (cap 50)           |
| Notion meeting notes         | Shipped | `notion-search` MCP filtered by configurable title patterns                                                   |
| RSS / Atom feeds             | Shipped | `lib/fetch-rss.sh` - curl + Python stdlib XML; handles RSS 2.0 and Atom in one pass                           |
| GitHub spec-set commits      | Shipped | `lib/fetch-gh-commits.sh` - `gh api commits` with optional path filter (e.g., a public spec repo)             |
| Slack channels               | Planned | Slack MCP (when available) or Slack API; scan channels for keyword-relevant messages                          |
| Twitter/X lists              | Planned | X API; monitor ecosystem accounts for announcements                                                           |
| Linear/Jira issues           | Planned | Project management MCP; track sprint progress, blockers                                                       |
| Google Docs/Drive             | Planned | Google Drive MCP (available in Claude Code); scan shared docs for updates                                     |
| Calendar events              | Planned | Calendar integration; surface upcoming meetings, deadlines, events                                            |

Adding a source means adding a new step to the skill's process section and a new configuration block to the Notion config page.

### Cadence Rollups

Daily digests are the atomic unit. Higher-cadence digests are rollups that summarize lower-cadence ones.

| Cadence   | Status  | Input                                  | Output                                                                                               |
| --------- | ------- | -------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Daily     | Shipped | Raw sources (GitHub, Notion, RSS)      | One Notion page per day                                                                              |
| Weekly    | Shipped | The week's daily digests in Notion     | One Notion page synthesizing cross-day themes (top GitHub work, releases, partner momentum, content pulse, industry news roundup, favorites movement) |
| Monthly   | Planned | Weekly digests for the month           | One page with themes, metrics (PRs merged, partners engaged), and strategic observations             |
| Quarterly | Planned | Monthly digests                        | Executive-level summary with trends, comparisons to prior quarter, team highlights                   |

**How rollups work:** A weekly digest skill reads the last 5 daily digest pages from the Notion database, synthesizes them into themes and highlights, and writes a weekly summary page. The daily pages become the "source of truth" that higher cadences reference - no re-scanning of raw sources needed.

### Organizational Memory

As digests accumulate over weeks and months, the Notion database becomes a searchable organizational memory:

- **"What happened with Company X?"** - Search the database for partner mentions across all digests
- **"When did we start seeing <topic> activity?"** - Filter digests by keyword to find the first mention
- **"What were the biggest changes last quarter?"** - Quarterly rollup provides the answer
- **"Who was working on <feature>?"** - GitHub activity sections track contributors by name

Future skills could query this database directly to answer questions, generate reports, or surface trends over time.

### Multi-Team Support

Each team creates their own skill, config page, and database. A future "org digest" skill could aggregate across team databases to produce a cross-functional summary for leadership.

```
Team A ──> /team-digest ──> Team A Daily Digest database
Team B ──> /<team-b>-digest ──> Team B Daily Digest database
Team C ──> /<team-c>-digest ──> Team C Daily Digest database
                |
                v
         /org-digest (future)
                |
                v
         Org Weekly Summary database
```

## Configuration Files

| File                                            | Committed       | Purpose                                                                       |
| ----------------------------------------------- | --------------- | ----------------------------------------------------------------------------- |
| `config.template.json`                          | Yes             | Template with empty Notion IDs; starting point for new users                  |
| `config.json`                                   | No (gitignored) | Your actual Notion IDs; created by `setup.sh` from template                   |
| `~/.config/team-digest/config.json`             | N/A (local)     | Global copy synced by `setup.sh`; skills read from here                       |
| `profiles/<team>.template.md`                   | Yes             | Minimal placeholder profile template; describes the shape of role + relevance + glossary sections |
| `profiles/<team>.example.md`                    | Yes             | Worked example profile (Solutions Architect), ~200 lines, ready to copy as a starting point |
| `profiles/<team>.md`                            | No (gitignored) | Your personalized profile; created from template by `setup.sh`                |
| `~/.config/team-digest/profiles/<team>.md`      | N/A (local)     | Global copy synced by `setup.sh`; skills read from here                       |
| `/tmp/team-digest-dry-runs/`                    | N/A (local)     | `--dry-run` markdown output; ephemeral, cleared on reboot                     |
| `bin/<team>-run.sh`                             | Yes             | Headless terminal entry point; symlink to `~/.local/bin/` for cron/launchd     |
| `skills/<team>-digest/lib/*.sh`                 | Yes             | Helper scripts the skill body invokes for GitHub fetching and config loading   |
| `~/.claude/skills/<team>-digest/lib/*.sh`       | N/A (local)     | Installed copy synced by `setup.sh`/`update.sh`; the skill invokes from here   |

## Requirements

| Tool            | Version  | Purpose                                   |
| --------------- | -------- | ----------------------------------------- |
| Claude Code     | 2.1+     | Runs digest skills and scheduled triggers |
| GitHub CLI (gh) | 2.0+     | Scans GitHub orgs for activity            |
| Notion MCP      | Built-in | Searches Notion and writes digest pages   |

Zero additional SaaS costs. Everything runs on existing Claude Code and GitHub subscriptions.

## Docs

- [docs/team-digest-quickstart.md](docs/team-digest-quickstart.md) - 10-minute setup walkthrough for the daily digest
- [docs/team-weekly-quickstart.md](docs/team-weekly-quickstart.md) - The weekly rollup skill: prerequisites, usage, scheduling, failure modes
- [docs/configuration.md](docs/configuration.md) - Customize keywords, partner patterns, Favorites, Pages-I-Created email, RSS feeds, HIP tracking
- [docs/hip-tracking.md](docs/hip-tracking.md) - HIP Activity source, cross-reference annotations, status-change detection, opting out
- [docs/scheduling.md](docs/scheduling.md) - macOS launchd, Linux cron, GitHub Actions self-hosted runners
- [docs/troubleshooting.md](docs/troubleshooting.md) - Common issues and fixes
- [docs/roadmap.md](docs/roadmap.md) - What's parked for later (YouTube/X/Slack watching, monthly/quarterly digests, advanced HIP-to-code mapping)
