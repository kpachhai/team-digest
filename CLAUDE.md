# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

team-digest is a zero-infrastructure digest system built on Claude Code skills. It aggregates GitHub activity, Notion keyword matches, and partner meeting notes into structured daily summaries written to Notion. Each team gets its own skill and config; the first shipped skill is `/sa-digest` for the Solutions Architect team.

## Key Commands

```bash
./setup.sh                            # First-time: checks prereqs (claude, gh, Notion MCP),
                                      #   creates config.json from template, installs skills
                                      #   + lib/ helpers to ~/.claude/skills/, syncs profiles
./update.sh                           # After git pull: re-syncs SKILL.md, lib/, config, profiles
/sa-digest                            # In Claude Code: yesterday's digest, written to Notion
/sa-digest 2026-04-20                 # Specific date
/sa-digest --dry-run                  # Same pipeline, but write markdown locally - skip Notion
bin/sa-digest-run.sh                  # Headless terminal entry point - uses `claude -p`,
                                      #   inherits local gh auth, supports same flags
bin/sa-digest-run.sh 2026-04-20 --dry-run
```

There are no build steps, tests, or linters. The codebase is shell scripts, Bash helper scripts, and Claude Code skill definitions.

## Architecture

### File Layout

```
team-digest/
├── bin/sa-digest-run.sh              # Headless terminal entry point (claude -p wrapper)
├── config.template.json              # Committed config template
├── config.json                       # Gitignored - your Notion IDs + structural settings
├── profiles/
│   ├── sa-digest.template.md         # Committed team profile template
│   └── sa-digest.md                  # Gitignored - your personalized profile
├── skills/sa-digest/
│   ├── SKILL.md                      # Skill body: orchestration + MCP calls + writing rules
│   └── lib/                          # Shell helpers (no MCP - those only work inside Claude)
│       ├── compute-window.sh         # Resolve date arg → DATE_LABEL/START/END
│       ├── load-config.sh            # Read + validate config.json
│       ├── fetch-github-prs.sh       # gh search prs + python parsing
│       ├── fetch-github-issues.sh
│       ├── fetch-github-releases.sh
│       └── README.md                 # Helper inventory and conventions
└── docs/                             # User-facing documentation
```

### Sync Flow

```
config.template.json   --(setup.sh)-->  config.json   --(setup/update.sh)-->  ~/.config/team-digest/config.json
profiles/*.template.md --(setup.sh)-->  profiles/*.md --(setup/update.sh)-->  ~/.config/team-digest/profiles/*.md
skills/*/SKILL.md      --(setup/update.sh)-->                                  ~/.claude/skills/*/SKILL.md
skills/*/lib/*.sh      --(setup/update.sh)-->                                  ~/.claude/skills/*/lib/*.sh
```

Skills read config from `~/.config/team-digest/config.json` at runtime. The config key must match the skill directory name (`sa-digest` skill reads `config["sa-digest"]`). The skill body invokes `lib/*.sh` helpers by absolute path at `~/.claude/skills/<name>/lib/<helper>.sh`.

### Two-Layer Config

1. **`config.json`** (gitignored) - structural config: Notion page/database IDs, GitHub orgs array, fallback defaults
2. **Notion config page** (fetched at runtime via `config_page_id`) - live settings: keywords, partner patterns. Editable by anyone on the team without touching files. Falls back to `config.json` defaults if unreachable.

### Digest Pipeline (SKILL.md)

The skill in `skills/sa-digest/SKILL.md` is the core logic. It runs as a Claude Code skill, not a standalone script. The pipeline:

0. Read `~/.config/team-digest/config.json` + team profile from `~/.config/team-digest/profiles/sa-digest.md`
1. Fetch Notion config page for live keywords/patterns
2. Scan GitHub orgs via `gh` CLI (PRs, issues, releases) - parallelized across orgs
3. Search Notion for keyword matches via `notion-search` MCP tool
4. Search Notion for partner conversations via `notion-search` MCP tool
5. Write combined digest page to Notion database via `notion-create-pages` MCP tool

Each source is independent; if one fails, the rest still run and the digest is produced with a failure indicator.

### Team Profile System

Profiles (`profiles/*.template.md`) describe a team's role, priorities, and what "relevant" means. Claude reads the profile to write contextual "SA Relevance" paragraphs in the digest. Templates are committed; personalized copies (without `.template` suffix) are gitignored.

## Conventions

- **Config key = skill directory name.** A skill named `eng-digest` lives in `skills/eng-digest/` and reads `config["eng-digest"]`.
- **No Notion IDs in committed files.** All IDs live in gitignored `config.json`; the `data_source_id` for writing pages is derived at runtime by fetching the database.
- **GitHub orgs is an array.** Each entry has `name`, `priority_repos` (get narrative summaries), and `scan_all` (whether to scan non-priority repos). Empty `priority_repos` means all repos get summary table treatment.
- **Notion MCP constraints in SKILL.md:** Do not use `readMcpResource`/`ReadMcpResourceTool`; do not save `gh` output to intermediate files. GitHub data fetching lives in `skills/sa-digest/lib/*.sh` helpers - do not re-implement `gh search ... | python3 -c "..."` inline.
- **Helper scripts in `skills/<name>/lib/`:** Skill bodies orchestrate; helpers do CLI/data work. Helpers must not call MCP tools (those only work inside Claude). `setup.sh` and `update.sh` copy `lib/` alongside `SKILL.md` to `~/.claude/skills/<name>/lib/`.
- **Headless runs via `bin/<digest>-run.sh`:** Each digest skill ships a `bin/<digest>-run.sh` wrapper (in the repo) that invokes `claude -p "/<digest> [args]"` with the necessary Notion MCP tools allow-listed. This is the same skill - just a different invocation path. There is no separate routine/inline-config code path.
- **`--dry-run` flag:** Every digest skill supports `--dry-run` which runs the full pipeline but writes the markdown to `~/.config/team-digest/dry-runs/<digest>-<date>-v<N>.md` instead of calling Notion. Use this to validate refactors without overwriting an existing live digest page.

## Adding a New Team Digest

1. Add a new top-level key to both `config.json` and `config.template.json`
2. Copy `skills/sa-digest/` to `skills/<team>-digest/` (including the `lib/` subdirectory). Change all `sa-digest` references in `SKILL.md` to `<team>-digest`. Most `lib/` helpers are reusable as-is - the exception is `load-config.sh`, which takes the digest-name as its first arg, so just call it with the new name.
3. Create `profiles/<team>-digest.template.md` with the team's role, relevance criteria, and a Project Glossary section.
4. Copy `bin/sa-digest-run.sh` to `bin/<team>-digest-run.sh`; in the new script, change every `sa-digest` reference (the prompt, log paths, the model env var name) to `<team>-digest`.
5. Run `./update.sh` to install. Verify with `<team>-digest --dry-run`.
