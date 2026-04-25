# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

team-digest is a zero-infrastructure digest system built on Claude Code skills. It aggregates GitHub activity, Notion keyword matches, and partner meeting notes into structured daily summaries written to Notion. Each team gets its own skill and config; the first shipped skill is `/da-digest` for Developer Advocacy at Hiero.

## Key Commands

```bash
./setup.sh          # First-time: checks prereqs (claude, gh, Notion MCP), creates config.json
                    # from template, installs skills to ~/.claude/skills/, syncs profiles
./update.sh         # After git pull: syncs skills + config, flags new template keys
/da-digest          # Run in Claude Code - produces yesterday's digest
/da-digest 2026-04-20  # Backfill a specific date
```

There are no build steps, tests, or linters. The codebase is shell scripts and a Claude Code skill definition.

## Architecture

### Config Flow

```
config.template.json  --(setup.sh copies)--> config.json  --(setup.sh/update.sh syncs)--> ~/.config/team-digest/config.json
profiles/*.template.md --(setup.sh copies)--> profiles/*.md --(syncs)--> ~/.config/team-digest/profiles/*.md
skills/*/SKILL.md      --(setup.sh/update.sh copies)--> ~/.claude/skills/*/SKILL.md
```

Skills read config from `~/.config/team-digest/config.json` at runtime, not from the repo. The config key must match the skill directory name (e.g., `da-digest` skill reads `config["da-digest"]`).

### Two-Layer Config

1. **`config.json`** (gitignored) - structural config: Notion page/database IDs, GitHub orgs array, fallback defaults
2. **Notion config page** (fetched at runtime via `config_page_id`) - live settings: keywords, partner patterns. Editable by anyone on the team without touching files. Falls back to `config.json` defaults if unreachable.

### Digest Pipeline (SKILL.md)

The skill in `skills/da-digest/SKILL.md` is the core logic. It runs as a Claude Code skill, not a standalone script. The pipeline:

0. Read `~/.config/team-digest/config.json` + team profile from `~/.config/team-digest/profiles/da-digest.md`
1. Fetch Notion config page for live keywords/patterns
2. Scan GitHub orgs via `gh` CLI (PRs, issues, releases) - parallelized across orgs
3. Search Notion for keyword matches via `notion-search` MCP tool
4. Search Notion for partner conversations via `notion-search` MCP tool
5. Write combined digest page to Notion database via `notion-create-pages` MCP tool

Each source is independent; if one fails, the rest still run and the digest is produced with a failure indicator.

### Team Profile System

Profiles (`profiles/*.template.md`) describe a team's role, priorities, and what "relevant" means. Claude reads the profile to write contextual "DA Relevance" paragraphs in the digest. Templates are committed; personalized copies (without `.template` suffix) are gitignored.

## Conventions

- **Config key = skill directory name.** A skill named `eng-digest` lives in `skills/eng-digest/` and reads `config["eng-digest"]`.
- **No Notion IDs in committed files.** All IDs live in gitignored `config.json`; the `data_source_id` for writing pages is derived at runtime by fetching the database.
- **GitHub orgs is an array.** Each entry has `name`, `priority_repos` (get narrative summaries), and `scan_all` (whether to scan non-priority repos). Empty `priority_repos` means all repos get summary table treatment.
- **Notion MCP constraints in SKILL.md:** Do not use `readMcpResource`/`ReadMcpResourceTool`; do not save `gh` output to intermediate files - process JSON inline with `python3 -c`.

## Adding a New Team Digest

1. Add a new top-level key to both `config.json` and `config.template.json`
2. Copy `skills/da-digest/SKILL.md` to `skills/<team>-digest/SKILL.md`, change all `da-digest` references to `<team>-digest`
3. Create `profiles/<team>-digest.template.md` with the team's role and relevance criteria
4. Run `./update.sh` to install
