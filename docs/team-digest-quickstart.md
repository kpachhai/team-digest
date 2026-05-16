# Team Daily Digest - Quick Start Guide

A daily digest that scans GitHub activity, Notion keywords, and partner conversations across the systems your team cares about, then writes a structured summary to a shared Notion database.

## Prerequisites

- [Claude Code](https://claude.ai/code) installed and authenticated
- [GitHub CLI](https://cli.github.com) installed and authenticated (`gh auth login`)
- Notion MCP server connected in Claude Code (Settings > MCP Servers > Notion)

## Install

Copy the `SKILL.md` file to your Claude Code skills directory:

```bash
mkdir -p ~/.claude/skills/team-digest
cp SKILL.md ~/.claude/skills/team-digest/SKILL.md
```

Restart Claude Code if a session is already open.

## First Run

```
/team-digest
```

On first run, the skill asks: "Do you already have Notion pages set up, or should I create them? [existing/new]"

- **If you have Notion pages already** (a teammate shared them, or you set them up yourself), choose `existing`. The skill prompts for two IDs:
  1. **Config page ID** - the Notion page with keywords and partner patterns
  2. **Database ID** - the Notion database where digest pages are written

  Both are the 32-char hex string from the Notion page URL: `notion.so/<this-id>`.

- **If your Notion workspace is fresh**, choose `new`. The skill auto-creates a "Team Digest Workspace" parent page with a config page (prefilled with starter defaults) and the entries database. See [docs/configuration.md](configuration.md#bootstrap-your-notion-workspace) for what gets created and where to find it in your Notion sidebar.

Either path saves your config to `~/.config/team-digest/config.json` and pre-fills GitHub orgs and default keywords. Run `/team-digest` again to produce your first digest.

## Commands

| Command | What it does |
|---------|-------------|
| `/team-digest` | Digest for the previous calendar day |
| `/team-digest 2026-04-20` | Digest for a specific date (backfill) |
| `/team-digest setup` | Create or update your Notion IDs |
| `/team-digest config` | Show your current configuration |

## Personalize with a Team Profile (Optional)

Create a profile file to customize the "Relevance" sections in each digest:

```bash
mkdir -p ~/.config/team-digest/profiles
```

Create `~/.config/team-digest/profiles/team-digest.md` with your team's role and priorities. Use `profiles/team-digest.template.md` in the repo as a starting point - copy it and replace the `<placeholder>` fields with your team's actual context (role, responsibilities, key repos, glossary, audience).

The more specific you are, the more useful the Relevance sections become. Without a profile, the skill falls back to generic heuristics.

## Validate Without Spamming Notion

Before turning on automation, run a dry run to preview the digest output as a local file (no Notion write):

```bash
/team-digest --dry-run               # yesterday's digest, written locally
/team-digest 2026-04-27 --dry-run    # specific date, written locally
```

The output lands in `/tmp/team-digest-dry-runs/team-digest-<DATE>-v<N>.md`. Open the file, sanity-check the format, then do a real run when you're satisfied. Multiple `--dry-run` invocations on the same day produce versioned files (`-v1.md`, `-v2.md`, ...) so you can compare iterations. The `/tmp` path is ephemeral on purpose - if you want to keep a dry run, copy it out before reboot.

## Automate It

The recommended option for daily runs is **macOS launchd** (or **Linux cron**) using the repo's `bin/team-digest-run.sh`. This survives sleep/wake cycles, requires no cloud account, and uses your local `gh` and Notion MCP setup directly.

```bash
# Symlink the wrapper script onto your $PATH
mkdir -p ~/.local/bin ~/.local/log
ln -sf "$(pwd)/bin/team-digest-run.sh" ~/.local/bin/team-digest-run.sh

# Smoke test before scheduling
~/.local/bin/team-digest-run.sh --dry-run    # safe - skips Notion write
~/.local/bin/team-digest-run.sh              # real run for yesterday

# Schedule via launchd or cron
# See docs/scheduling.md for the launchd plist and cron line
```

The full launchd plist, cron syntax, and a GitHub Actions workflow example are in [`docs/scheduling.md`](scheduling.md).

## Add a New Team Digest (LOCAL ONLY)

Additional team-specific digests live in your local checkout - do NOT commit them to the public repo. To create a digest for another team (e.g., engineering):

1. Copy `SKILL.md` to a new skill directory:
   ```bash
   mkdir -p ~/.claude/skills/<my-team>-digest
   cp ~/.claude/skills/team-digest/SKILL.md ~/.claude/skills/<my-team>-digest/SKILL.md
   ```

2. In the copied skill, replace all `team-digest` references with `<my-team>-digest` (skill name, config key, callout titles, helper invocations).

3. Create a separate Notion config page and database for the new team.

4. Run `/<my-team>-digest` - the first-run setup will ask for the new team's Notion IDs.

5. Optionally create a profile at `~/.config/team-digest/profiles/<my-team>-digest.md` describing the team's priorities.

Each team's config key matches its skill directory name. Multiple digests coexist in the same config file without conflict.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "config not found" on first run | The skill should prompt you automatically. If not, run `/team-digest setup` |
| Notion sections empty | Check Notion MCP is connected (Settings > MCP Servers). Keyword search only finds pages **created** on the target date, not edited. |
| GitHub rate limiting | Run `gh api rate_limit --jq '.rate'` to check. Normal digest uses ~45 API calls; limit is 5,000/hour. |
| Want to change Notion IDs | Run `/team-digest setup` to update |
| Duplicate digest pages | Check database before running manually. Automated runs have Status: "Auto". |
