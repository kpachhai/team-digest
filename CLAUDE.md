# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

team-digest is a zero-infrastructure digest system built on Claude Code skills. It aggregates GitHub activity, Notion keyword matches, and partner meeting notes into structured daily summaries written to Notion. The repo ships a generic `/team-digest` (daily) and `/team-weekly` (weekly rollup) pair. Additional team-specific digests live in your local checkout only - they are not committed to this public repo.

## Key Commands

```bash
./setup.sh                            # First-time: checks prereqs (claude, gh, Notion MCP),
                                      #   creates config.json from template, installs skills
                                      #   + lib/ helpers to ~/.claude/skills/, syncs profiles
./update.sh                           # After git pull: re-syncs SKILL.md, lib/, config, profiles
/team-digest                            # Daily: yesterday's digest, written to Notion
/team-digest 2026-04-20                 # Daily: specific date
/team-digest --dry-run                  # Daily: write markdown locally, skip Notion
/team-weekly                            # Weekly: synthesize last full week of dailies into
                                      #   a weekly summary, written to the same Notion DB
/team-weekly 2026-05-07 --dry-run       # Weekly: specific week, preview locally
bin/team-digest-run.sh                  # Headless terminal entry point for /team-digest
bin/team-weekly-run.sh                  # Headless terminal entry point for /team-weekly
```

There are no build steps, tests, or linters. The codebase is shell scripts, Bash helper scripts, and Claude Code skill definitions.

## Architecture

### File Layout

```
team-digest/
├── bin/team-digest-run.sh              # Headless terminal entry point (claude -p wrapper)
├── config.template.json              # Committed config template
├── config.json                       # Gitignored - your Notion IDs + structural settings
├── profiles/
│   ├── team-digest.template.md         # Committed team profile template
│   └── team-digest.md                  # Gitignored - your personalized profile
├── skills/
│   ├── team-digest/                    # Daily digest
│   │   ├── SKILL.md                  # Skill body: orchestration + MCP calls + writing rules
│   │   └── lib/                      # Shell helpers (no MCP - those only work inside Claude)
│   │       ├── compute-window.sh     # Resolve date arg → DATE_LABEL/START/END
│   │       ├── load-config.sh        # Read + validate config.json (used by team-weekly too)
│   │       ├── fetch-github-prs.sh   # gh search prs + python parsing
│   │       ├── fetch-github-issues.sh
│   │       ├── fetch-github-releases.sh
│   │       ├── fetch-rss.sh          # RSS/Atom feed → JSON of items dated to target
│   │       ├── fetch-gh-commits.sh   # GitHub commits on a date (for spec sets w/o RSS)
│   │       └── README.md             # Helper inventory and conventions
│   └── team-weekly/                    # Weekly rollup of dailies
│       ├── SKILL.md                  # Reads dailies from Notion DB, synthesizes cross-day themes
│       └── lib/
│           ├── compute-week-window.sh  # Resolve date arg → ISO week Mon-Sun timestamps
│           └── README.md
└── docs/                             # User-facing documentation
```

### Sync Flow

```
config.template.json   --(setup.sh)-->  config.json   --(setup/update.sh)-->  ~/.config/team-digest/config.json
profiles/*.template.md --(setup.sh)-->  profiles/*.md --(setup/update.sh)-->  ~/.config/team-digest/profiles/*.md
skills/*/SKILL.md      --(setup/update.sh)-->                                  ~/.claude/skills/*/SKILL.md
skills/*/lib/*.sh      --(setup/update.sh)-->                                  ~/.claude/skills/*/lib/*.sh
```

Skills read config from `~/.config/team-digest/config.json` at runtime. The config key must match the skill directory name (`team-digest` skill reads `config["team-digest"]`). The skill body invokes `lib/*.sh` helpers by absolute path at `~/.claude/skills/<name>/lib/<helper>.sh`.

### Two-Layer Config

1. **`config.json`** (gitignored) - structural config: Notion page/database IDs, GitHub orgs array, fallback defaults
2. **Notion config page** (fetched at runtime via `config_page_id`) - live settings: keywords, partner patterns. Editable by anyone on the team without touching files. Falls back to `config.json` defaults if unreachable.

### Digest Pipeline (SKILL.md)

The skill in `skills/team-digest/SKILL.md` is the core logic. It runs as a Claude Code skill, not a standalone script. The pipeline:

0. Read `~/.config/team-digest/config.json` + team profile from `~/.config/team-digest/profiles/team-digest.md`
1. Fetch Notion config page for live keywords/patterns
2. Scan GitHub orgs via `gh` CLI (PRs, issues, releases) - parallelized across orgs
3. Search Notion for keyword matches via `notion-search` MCP tool
4. Search Notion for partner conversations via `notion-search` MCP tool
5. Write combined digest page to Notion database via `notion-create-pages` MCP tool

Each source is independent; if one fails, the rest still run and the digest is produced with a failure indicator.

### Team Profile System

Profiles (`profiles/*.template.md`) describe a team's role, priorities, and what "relevant" means. Claude reads the profile to write contextual "Relevance" paragraphs in the digest. Only the generic `team-digest.template.md` is committed; personalized copies (without `.template` suffix) and any team-specific templates are gitignored.

## Conventions

- **Config key = skill directory name.** A skill named `<my-team>-digest` lives in `skills/<my-team>-digest/` and reads `config["<my-team>-digest"]`.
- **No Notion IDs in committed files.** All IDs live in gitignored `config.json`; the `data_source_id` for writing pages is derived at runtime by fetching the database.
- **GitHub orgs is an array.** Each entry has `name`, `priority_repos` (get narrative summaries), and `scan_all` (whether to scan non-priority repos). Empty `priority_repos` means all repos get summary table treatment.
- **Notion MCP constraints in SKILL.md:** Do not use `readMcpResource`/`ReadMcpResourceTool`; do not save `gh` output to intermediate files. GitHub data fetching lives in `skills/team-digest/lib/*.sh` helpers - do not re-implement `gh search ... | python3 -c "..."` inline.
- **Helper scripts in `skills/<name>/lib/`:** Skill bodies orchestrate; helpers do CLI/data work. Helpers must not call MCP tools (those only work inside Claude). `setup.sh` and `update.sh` copy `lib/` alongside `SKILL.md` to `~/.claude/skills/<name>/lib/`.
- **Headless runs via `bin/<digest>-run.sh`:** Each digest skill ships a `bin/<digest>-run.sh` wrapper (in the repo) that invokes `claude -p "/<digest> [args]"` with the necessary Notion MCP tools allow-listed. This is the same skill - just a different invocation path. There is no separate routine/inline-config code path.
- **`--dry-run` flag:** Every digest skill supports `--dry-run` which runs the full pipeline but writes the markdown to `/tmp/team-digest-dry-runs/<digest>-<date>-v<N>.md` instead of calling Notion. The path is ephemeral on purpose - dry runs are throwaway validation artifacts (compare once, discard). Use this flag to validate refactors without overwriting an existing live digest page.

## Adding a New Team Digest (LOCAL ONLY)

The repo ships only the generic `team-digest` skill in committed form. Any additional team-specific digest you create stays in your local checkout - do NOT commit it to this public repo. The `.gitignore` already covers `profiles/*.md` (your personalized profiles) and `config.json` (your Notion IDs); add `skills/<my-team>-digest/` to your local `.git/info/exclude` if you want defense-in-depth against accidental commits.

1. Add a new top-level key to your local `config.json` (NOT `config.template.json`).
2. Copy `skills/team-digest/` to `skills/<my-team>-digest/` (including the `lib/` subdirectory). Change all `team-digest` references in `SKILL.md` to `<my-team>-digest`. Most `lib/` helpers are reusable as-is - the exception is `load-config.sh`, which takes the digest-name as its first arg, so just call it with the new name.
3. Create `profiles/<my-team>-digest.md` (no `.template.md` needed - go straight to the personalized copy) with the team's role, relevance criteria, and a Project Glossary section.
4. Copy `bin/team-digest-run.sh` to `bin/<my-team>-digest-run.sh`; in the new script, change every `team-digest` reference (the prompt, log paths) to `<my-team>-digest`.
5. Run `./update.sh` to install. Verify with `<my-team>-digest --dry-run`.
