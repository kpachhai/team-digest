# SA Daily Digest - Quick Start Guide

A daily digest that scans GitHub activity, Notion keywords, and partner conversations across the Hedera/Hiero ecosystem, then writes a structured summary to a shared Notion database.

## Prerequisites

- [Claude Code](https://claude.ai/code) installed and authenticated
- [GitHub CLI](https://cli.github.com) installed and authenticated (`gh auth login`)
- Notion MCP server connected in Claude Code (Settings > MCP Servers > Notion)

## Install

Copy the `SKILL.md` file to your Claude Code skills directory:

```bash
mkdir -p ~/.claude/skills/sa-digest
cp SKILL.md ~/.claude/skills/sa-digest/SKILL.md
```

Restart Claude Code if a session is already open.

## First Run

```
/sa-digest
```

On first run, the skill will ask you for two Notion IDs:

1. **Config page ID** - the Notion page with keywords and partner patterns
2. **Database ID** - the Notion database where digest pages are written

Both are the 32-char hex string from the Notion page URL: `notion.so/<this-id>`. Ask your team lead for these if you don't have them.

The skill saves your config to `~/.config/team-digest/config.json` and pre-fills GitHub orgs and default keywords. Run `/sa-digest` again to produce your first digest.

## Commands

| Command | What it does |
|---------|-------------|
| `/sa-digest` | Digest for the previous calendar day |
| `/sa-digest 2026-04-20` | Digest for a specific date (backfill) |
| `/sa-digest setup` | Create or update your Notion IDs |
| `/sa-digest config` | Show your current configuration |

## Personalize with a Team Profile (Optional)

Create a profile file to customize the "SA Relevance" sections in each digest:

```bash
mkdir -p ~/.config/team-digest/profiles
```

Create `~/.config/team-digest/profiles/sa-digest.md` with your team's role and priorities. Example structure:

```markdown
# Team Profile: Solutions Architect (SA)

## Role and Responsibilities
We are the Solutions Architect team. Our job is to...

## What "Relevant" Means for Us

### High Priority - Always Surface
- SDK breaking changes - we support partners using these SDKs...
- New APIs or features - these open new integration patterns...

### Medium Priority - Worth Noting
- Performance improvements...
- Partner conversations about friction...

## Our Key Repos and Why They Matter
| Repo | Why We Care |
|------|-------------|
| hiero-sdk-js | JS/TS SDK used in partner integrations |
```

The more specific you are, the more useful the Relevance sections become. Without a profile, the skill falls back to generic heuristics.

## Validate Without Spamming Notion

Before turning on automation, run a dry run to preview the digest output as a local file (no Notion write):

```bash
/sa-digest --dry-run               # yesterday's digest, written locally
/sa-digest 2026-04-27 --dry-run    # specific date, written locally
```

The output lands in `/tmp/team-digest-dry-runs/sa-digest-<DATE>-v<N>.md`. Open the file, sanity-check the format, then do a real run when you're satisfied. Multiple `--dry-run` invocations on the same day produce versioned files (`-v1.md`, `-v2.md`, ...) so you can compare iterations. The `/tmp` path is ephemeral on purpose - if you want to keep a dry run, copy it out before reboot.

## Automate It

The recommended option for daily runs is **macOS launchd** (or **Linux cron**) using the repo's `bin/sa-digest-run.sh`. This survives sleep/wake cycles, requires no cloud account, and uses your local `gh` and Notion MCP setup directly.

```bash
# Symlink the wrapper script onto your $PATH
mkdir -p ~/.local/bin ~/.local/log
ln -sf "$(pwd)/bin/sa-digest-run.sh" ~/.local/bin/sa-digest-run.sh

# Smoke test before scheduling
~/.local/bin/sa-digest-run.sh --dry-run    # safe - skips Notion write
~/.local/bin/sa-digest-run.sh              # real run for yesterday

# Schedule via launchd or cron
# See docs/scheduling.md for the launchd plist and cron line
```

The full launchd plist, cron syntax, and a GitHub Actions workflow example are in [`docs/scheduling.md`](scheduling.md).

## Add a New Team Digest

To create a digest for another team (e.g., engineering):

1. Copy `SKILL.md` to a new skill directory:
   ```bash
   mkdir -p ~/.claude/skills/eng-digest
   cp ~/.claude/skills/sa-digest/SKILL.md ~/.claude/skills/eng-digest/SKILL.md
   ```

2. In the copied skill, replace all `sa-digest` with `eng-digest` and all `SA` references with `Eng` (skill name, config key, callout titles, relevance section names).

3. Create a separate Notion config page and database for the new team.

4. Run `/eng-digest` - the first-run setup will ask for the new team's Notion IDs.

5. Optionally create a profile at `~/.config/team-digest/profiles/eng-digest.md` describing the engineering team's priorities.

Each team's config key matches its skill directory name. Multiple digests coexist in the same config file without conflict.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "config not found" on first run | The skill should prompt you automatically. If not, run `/sa-digest setup` |
| Notion sections empty | Check Notion MCP is connected (Settings > MCP Servers). Keyword search only finds pages **created** on the target date, not edited. |
| GitHub rate limiting | Run `gh api rate_limit --jq '.rate'` to check. Normal digest uses ~45 API calls; limit is 5,000/hour. |
| Want to change Notion IDs | Run `/sa-digest setup` to update |
| Duplicate digest pages | Check database before running manually. Automated runs have Status: "Auto". |
