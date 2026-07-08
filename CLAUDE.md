# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

team-digest is a zero-infrastructure digest system built on Claude Code skills. It aggregates GitHub activity, Notion keyword matches, and partner meeting notes into structured daily summaries written to Notion. The repo ships three cadences: `/team-digest` (the only scanner - a single day by default, or any explicit multi-day range), `/team-weekly` (weekly rollup), and `/team-monthly` (storyline-first monthly rollup). The weekly and monthly are consumers - they read existing Notion pages by date-range overlap, not external sources. The scan window is always an explicit argument (single date, `A..B`, `--from/--to`, or `--days N`); there is no hidden backfill. A downward **context cascade** feeds each tier a slice of the tier above (daily reads the latest weekly, weekly reads the latest monthly) so output is storyline-aware instead of cold. Additional team-specific digests live in your local checkout only - they are not committed to this public repo.

## Key Commands

```bash
./setup.sh                            # First-time: checks prereqs (claude, gh, Notion MCP),
                                      #   creates config.json from template, installs skills
                                      #   + lib/ helpers to ~/.claude/skills/, syncs profiles
./update.sh                           # After git pull: re-syncs SKILL.md, lib/, config, profiles
/team-digest                            # Daily: yesterday's digest, written to Notion
/team-digest 2026-04-20                 # Daily: specific date
/team-digest 2026-06-08..2026-06-14     # Range: scan a multi-day window (all sources), one page
/team-digest --from 2026-06-08 --to 2026-06-14   # Range: same, weekly-style flags
/team-digest --days 3                   # Range: last 3 days, ending yesterday
/team-digest --dry-run                  # Daily: write markdown locally, skip Notion
/team-weekly                            # Weekly: synthesize last full week of dailies into
                                      #   a weekly summary, written to the same Notion DB
/team-weekly 2026-05-07 --dry-run       # Weekly: specific week, preview locally
/team-monthly                           # Monthly: synthesize last full calendar month of
                                      #   weeklies + daily metadata into a storyline-first page
/team-monthly 2026-05 --dry-run         # Monthly: specific month, preview locally
bin/team-digest-run.sh                  # Headless terminal entry point for /team-digest
bin/team-weekly-run.sh                  # Headless terminal entry point for /team-weekly
bin/team-monthly-run.sh                 # Headless terminal entry point for /team-monthly (Opus default)

# Offline tests (no live Notion / gh / Claude needed):
bash tests/run-all.sh                                         # run the whole suite (10 files, 148 assertions)
bash tests/lint-digest-markdown.sh <file.md>                  # lint a dry-run digest page
bash tests/lint-digest-markdown.sh --template <TEMPLATE.md>   # lint a skill TEMPLATE.md
```

There is no build step. `tests/run-all.sh` runs the offline suite: unit tests for all 9 pure helpers (the 3 date-window resolvers, `extract-hip-refs`, `load-config`, `consolidate-matches`, `strategy4-gate`, `calibrate-hip-matches`, `coverage-gap`) plus the Notion-markdown linter. The 11 network fetch helpers and the three `SKILL.md` pipelines are NOT unit-tested (they need `gh`/network or run inside Claude against Notion MCP); validate those operationally with `--dry-run`. See [`tests/README.md`](tests/README.md) for coverage details, the testability env overrides, and the known gap the tests surfaced.

## Deploying updates to another machine

Every machine that runs team-digest is macOS. To pick up any change made in this repo (skills, wrappers, the headless security sandbox), a Claude session or a human on another machine runs exactly one idempotent command from the repo root - no manual steps:

```bash
git pull && ./update.sh
```

`update.sh` syncs skills/lib/config/profiles **and symlinks the headless wrappers** (`bin/*-run.sh`) into `~/.local/bin`. Because they are symlinks (not copies), each wrapper resolves its sibling `bin/sandbox-settings.json` from the repo, so the scoped `--allowedTools` and the OS-level sandbox go live for the existing launchd/cron job automatically - the plist already points at `~/.local/bin/<wrapper>` and needs no change. A prior copy-install is auto-converted to a symlink.

Then validate once on that machine:

```bash
bin/team-digest-run.sh $(date -v-1d +%F) --dry-run   # gather + sandbox, skips the Notion write
```

Confirm the log shows `[sandbox] on: .../bin/sandbox-settings.json` (not an `UNSANDBOXED` warning), then let the next scheduled run exercise the Notion write under the sandbox. Security model, requirements, and the network-egress caveat live in `docs/scheduling.md` -> "Sandboxing (security)".

## Architecture

### File Layout

```
team-digest/
├── bin/team-digest-run.sh              # Headless terminal entry point (claude -p wrapper)
├── bin/team-weekly-run.sh             # Weekly headless entry point
├── bin/team-monthly-run.sh           # Monthly headless entry point (Opus default)
├── config.template.json              # Committed config template
├── config.json                       # Gitignored - your Notion IDs + structural settings
├── profiles/
│   ├── team-digest.template.md         # Committed minimal placeholder (copied by setup.sh)
│   ├── team-digest.example.md          # Committed Solutions Architect worked example
│   └── team-digest.md                  # Gitignored - your personalized profile
├── skills/
│   ├── team-digest/                    # Daily digest
│   │   ├── SKILL.md                  # Skill body: orchestration + MCP calls + writing rules
│   │   └── lib/                      # 16 shell helpers (no MCP - those only work inside Claude)
│   │       ├── compute-window.sh     # Resolve day or range → WINDOW_START/END/LABEL, IS_RANGE, START/END
│   │       ├── coverage-gap.sh       # Window + covered ranges → uncovered days (weekly/monthly coverage gate)
│   │       ├── load-config.sh        # Read + validate config.json (shared by team-weekly + team-monthly)
│   │       ├── fetch-github-prs.sh   # gh search prs + python parsing
│   │       ├── fetch-github-issues.sh
│   │       ├── fetch-github-releases.sh
│   │       ├── fetch-rss.sh          # RSS/Atom feed → JSON of items dated to target
│   │       ├── fetch-gh-commits.sh   # GitHub commits on a date (for spec sets w/o RSS)
│   │       ├── fetch-hip-updates.sh  # HIPs touched on a date in the HIP repo (+ status detection)
│   │       ├── fetch-hip-implementation-prs.sh  # Per-HIP cross-repo PR/commit search (Mechanism B)
│   │       ├── fetch-hip-release-refs.sh        # Strategy 2 - release-note analysis
│   │       ├── fetch-hip-timeline-correlations.sh  # Strategy 3 - timeline correlation
│   │       ├── extract-hip-refs.sh   # Extract HIP-N patterns from arbitrary text on stdin
│   │       ├── refresh-hip-index.sh  # Maintain known-HIPs index for false-positive filtering
│   │       ├── calibrate-hip-matches.sh  # Precision/recall/F1 vs labeled set
│   │       ├── strategy4-gate.sh        # Strategy 4 gate decision (calibration-driven)
│   │       └── README.md             # Helper inventory and conventions
│   ├── team-weekly/                    # Weekly rollup of dailies
│   │   ├── SKILL.md                  # Reads dailies from Notion DB, synthesizes cross-day themes
│   │   └── lib/
│   │       ├── compute-week-window.sh  # Resolve date arg → ISO week Mon-Sun timestamps
│   │       └── README.md
│   └── team-monthly/                   # Monthly rollup of weeklies + daily metadata (storyline-first)
│       ├── SKILL.md                  # Hybrid-spine consumer: skeleton query + weekly bodies + capped daily deep-fetch
│       └── lib/
│           ├── compute-month-window.sh  # Resolve calendar month → MONTH_START/END/LABEL/NAME
│           └── README.md
├── tests/                            # Offline test suite (no live Notion / gh / Claude)
│   ├── run-all.sh                    # Runs every *.test.sh; exits non-zero on any failure
│   ├── lib-assert.sh                 # Shared assertion helpers (sourced by tests)
│   ├── *.test.sh                     # Unit tests for the 9 pure helpers + the linter self-test
│   ├── lint-digest-markdown.sh       # Notion-flavored-markdown linter (use --template for TEMPLATE.md)
│   ├── fixtures/                     # Sample monthly output + synthetic fixture month
│   └── README.md                     # Coverage map, testability env overrides, known gaps
└── docs/                             # User-facing documentation
```

### Sync Flow

```
config.template.json   --(setup.sh)-->  config.json   --(setup/update.sh)-->  ~/.config/team-digest/config.json
profiles/*.template.md --(setup.sh)-->  profiles/*.md --(setup/update.sh)-->  ~/.config/team-digest/profiles/*.md
skills/*/SKILL.md      --(setup/update.sh)-->                                  ~/.claude/skills/*/SKILL.md
skills/*/lib/*.sh      --(setup/update.sh)-->                                  ~/.claude/skills/*/lib/*.sh
bin/*-run.sh           --(update.sh symlink)-->                                ~/.local/bin/*-run.sh
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
2.3. Scan HIPs touched in `hiero-ledger/hiero-improvement-proposals` and search implementation orgs for HIP-referencing PRs/commits (gated on `hip_tracking.enabled`; see HIP Pipeline below)
3. Search Notion for keyword matches via `notion-search` MCP tool
4. Search Notion for partner conversations via `notion-search` MCP tool
5. Write combined digest page to Notion database via `notion-create-pages` MCP tool

Each source is independent; if one fails, the rest still run and the digest is produced with a failure indicator.

### HIP Pipeline (Step 2.3)

The HIP pipeline emits matches into a unified `MatchRecord` schema with `(hip_id, repo, pr_number)` dedup key and `confidence: high|medium|low`. Five match-producing stages run, then a deterministic consolidation step merges their output:

- **HIP detection** - `lib/fetch-hip-updates.sh` finds HIPs touched on the digest day in `hiero-ledger/hiero-improvement-proposals`, with status-change detection.
- **Mechanism A (regex annotation)** - inline in `fetch-github-prs.sh` / `fetch-github-issues.sh`. Emits `(high)` inline confidence labels parsed into MatchRecord shape.
- **Mechanism B (per-HIP search)** - top-N HIPs (ranked status-changed-first, capped by `max_hips_with_implementation_expansion`) get a per-HIP `gh search` across `hip_tracking.implementation_orgs`. Emits `confidence: high` for every hit because the search query was HIP-N itself.
- **Strategy 2 (release-note analysis)** - `lib/fetch-hip-release-refs.sh` scans release notes from implementation_orgs repos for HIP references. `high` if HIP-N is in the release tag, `medium` if only in the body. PRs attributed via compare-against-prev-tag commit-message parsing.
- **Strategy 3 (timeline correlation)** - `lib/fetch-hip-timeline-correlations.sh` runs one batched `gh search prs` per org with the HIP-N OR keyword-from-HIP-title disjunction. Per-org budget + 429 backoff; rate-limit-after-retries emits a graceful `source: "s3_skipped"` record without crashing. Scores ≥ 3 keyword overlap → `medium`; 1-2 + category-tiebreaker repo match → `low`.
- **Sidecar consolidation** - each match-producer writes structured JSON sidecars into `$TEAM_DIGEST_MATCHES_DIR`. After Claude exits, `bin/team-digest-run.sh` invokes `lib/consolidate-matches.sh` to dedup by `(hip_id, repo, pr_number)` with MAX-confidence rule, union `sources[]` + `per_source` maps. Moving the merge out of Claude's in-context state into deterministic shell prevents data loss under high PR volume.
- **Verbose filter** - read `TEAM_DIGEST_HIP_VERBOSE` (default `0`); render only `confidence: high` in the main HIP Activity section. With `=1`, append a `### Lower-Confidence Matches` H3 subsection with medium and low matches plus `s3_skipped` records.
- **Calibration** - `lib/calibrate-hip-matches.sh --current-only` runs after consolidation and warns on stderr if the calibration baseline is >180 days old.

The whole pipeline gates on `hip_tracking.enabled: true` in config (default), with an additional opt-out via the `TEAM_DIGEST_HIP_ENABLED=0` env var. The `lib/refresh-hip-index.sh` helper maintains the weekly-refreshed known-HIPs index at `~/.config/team-digest/hip-numbers.txt`; the HIP-N regex matches `\d{1,5}` with a placeholder blocklist (HIP-0000, HIP-9999) to avoid false positives.

**Strategy 4 gate:** the LLM-driven Strategy 4 is gated by `lib/strategy4-gate.sh` against a strategy-independent labeled set at `~/.config/team-digest/hip-code-mapper-labeled-set.json`. State machine: `DEFERRED_AWAITING_BASELINE` → `DEFER` (calibration met `recall >= 0.7 AND missed <= 5` on the `useful_signal` lens) or `TRIGGER` (otherwise). Strategy 4 ships only on `TRIGGER`.

### Team Profile System

Profiles describe a team's role, priorities, and what "relevant" means. Claude reads the profile to write contextual "Relevance" paragraphs in the digest. Two committed files: `team-digest.template.md` is a minimal placeholder (setup.sh copies it to `team-digest.md` on first run); `team-digest.example.md` is a worked Solutions Architect example users can copy over if their team shape matches. Personalized copies (without `.template`/`.example` suffix) and any team-specific files are gitignored.

## Conventions

- **Config key = skill directory name.** A skill named `<my-team>-digest` lives in `skills/<my-team>-digest/` and reads `config["<my-team>-digest"]`.
- **No Notion IDs in committed files.** All IDs live in gitignored `config.json`; the `data_source_id` for writing pages is derived at runtime by fetching the database.
- **GitHub orgs is an array.** Each entry has `name`, `priority_repos` (get narrative summaries), and `scan_all` (whether to scan non-priority repos). Empty `priority_repos` means all repos get summary table treatment.
- **Notion MCP constraints in SKILL.md:** Do not use `readMcpResource`/`ReadMcpResourceTool`; do not save `gh` output to intermediate files. GitHub data fetching lives in `skills/team-digest/lib/*.sh` helpers - do not re-implement `gh search ... | python3 -c "..."` inline.
- **Helper scripts in `skills/<name>/lib/`:** Skill bodies orchestrate; helpers do CLI/data work. Helpers must not call MCP tools (those only work inside Claude). `setup.sh` and `update.sh` copy `lib/` alongside `SKILL.md` to `~/.claude/skills/<name>/lib/`.
- **Headless runs via `bin/<digest>-run.sh`:** Each digest skill ships a `bin/<digest>-run.sh` wrapper (in the repo) that invokes `claude -p "/<digest> [args]"` with the necessary Notion MCP tools allow-listed. This is the same skill - just a different invocation path. There is no separate routine/inline-config code path.
- **`--dry-run` flag:** Every digest skill supports `--dry-run` which runs the full pipeline but writes the markdown to `/tmp/team-digest-dry-runs/<digest>-<date>-v<N>.md` instead of calling Notion. The path is ephemeral on purpose - dry runs are throwaway validation artifacts (compare once, discard). Use this flag to validate refactors without overwriting an existing live digest page.
- **GitHub token resolution:** env-var only. `gh` resolves the token in this order: `$GH_TOKEN` -> `$GITHUB_TOKEN` -> the keyring credential from `gh auth login`. The skill does NOT read tokens from `config.json` - storing PATs in JSON config files creates leak surfaces (accidental commits, subprocess log capture). See `docs/configuration.md#github-authentication`.
- **HIP cross-reference:** Mechanism A = regex annotation on existing PR/issue data (free, runs inside `fetch-github-prs.sh` / `fetch-github-issues.sh`); Mechanism B = per-HIP `gh search` against `implementation_orgs` (bounded by `hip_tracking.max_hips_with_implementation_expansion`, default 10). False positives filtered against `~/.config/team-digest/hip-numbers.txt`.
- **HIP path convention:** files live at `HIP/hip-N.md` (singular `HIP`, not `HIPs`), confirmed by the canonical Hiero HIP repo's tree. Override via `hip_tracking.path` if pointing at a different improvement-proposal repo.

## Adding a New Team Digest (LOCAL ONLY)

The repo ships only the generic `team-digest` skill in committed form. Any additional team-specific digest you create stays in your local checkout - do NOT commit it to this public repo. The `.gitignore` already covers `profiles/*.md` (your personalized profiles) and `config.json` (your Notion IDs); add `skills/<my-team>-digest/` to your local `.git/info/exclude` if you want defense-in-depth against accidental commits.

1. Add a new top-level key to your local `config.json` (NOT `config.template.json`).
2. Copy `skills/team-digest/` to `skills/<my-team>-digest/` (including the `lib/` subdirectory). Change all `team-digest` references in `SKILL.md` to `<my-team>-digest`. Most `lib/` helpers are reusable as-is - the exception is `load-config.sh`, which takes the digest-name as its first arg, so just call it with the new name.
3. Create `profiles/<my-team>-digest.md` (no `.template.md` needed - go straight to the personalized copy) with the team's role, relevance criteria, and a Project Glossary section.
4. Copy `bin/team-digest-run.sh` to `bin/<my-team>-digest-run.sh`; in the new script, change every `team-digest` reference (the prompt, log paths) to `<my-team>-digest`.
5. Run `./update.sh` to install. Verify with `<my-team>-digest --dry-run`.
