# team-digest helpers

Shell helpers invoked by the `team-digest` skill. Each helper does one thing,
exits non-zero on failure with errors on stderr, and writes its primary
output to stdout. The skill body (`SKILL.md`) treats each helper's stdout
as plain text input for the narrative writing step.

These helpers also run from `bin/team-digest-run.sh` (the headless terminal
entry point) by way of the same skill — there is no parallel
implementation. The skill is the orchestrator; helpers are the data layer.

## Helpers

| Helper | Purpose | Inputs | Output |
|---|---|---|---|
| `compute-window.sh` | Resolve a date arg (or default to yesterday-UTC) into `DATE_LABEL`, `START`, `END` ISO timestamps. | optional `YYYY-MM-DD` arg | `KEY=VALUE` lines suitable for `eval`. |
| `load-config.sh` | Read and validate the team-digest config for one digest (e.g. `team-digest`). Confirms required Notion IDs are present. | `<digest-name>` | The digest's config object as JSON. |
| `fetch-github-prs.sh` | Fetch PRs updated in the window for one org. | `<org> <start-iso>` | Plain-text summary grouped by repo, with PR numbers, authors, URLs, descriptions. |
| `fetch-github-issues.sh` | Fetch issues updated in the window for one org. | `<org> <start-iso>` | Plain-text summary, same shape as PRs. |
| `fetch-github-releases.sh` | Fetch releases published in the window for one org. Iterates every repo via `gh api`. | `<org> <start-iso>` | One line per release: `<repo>: <tag> - <name> (<date>) <url>`. |
| `fetch-rss.sh` | Fetch RSS or Atom feed entries published on a target date. Curl + Python stdlib XML parsing; no `feedparser` dependency. | `<feed-url> <YYYY-MM-DD>` | JSON array `[{title, link, published, summary}]`; empty array if no matches or parse error. |
| `fetch-gh-commits.sh` | Fetch GitHub commits to a repo on a target date, optionally restricted to a path prefix. Used for spec sets that don't publish RSS (notably EIPs). | `<owner/repo> <YYYY-MM-DD> [path]` | JSON array `[{sha, message, author, date, url}]`; empty array if no matches. |
| `refresh-hip-index.sh` | Maintain the known-HIPs index at `~/.config/team-digest/hip-numbers.txt`, used by `extract-hip-refs.sh` to filter false-positive HIP regex matches. Idempotent: re-runs within 7 days exit silently. On API failure with an existing index, uses the stale file and warns to stderr. | _(none)_ | Writes to `~/.config/team-digest/hip-numbers.txt` (one HIP number per line). Stdout is empty. |
| `extract-hip-refs.sh` | Find `HIP-N` references in arbitrary text on stdin. Matches `HIP-1137`, `HIP 1137`, `HIP_1137`, `hip1137` (case-insensitive) plus blob-URL forms (`hiero-improvement-proposals/blob/main/HIP/hip-1137.md`). Filters against the known-HIPs index when present; degrades to "emit all matches" if the index is missing. **Iteration 2:** regex widened to `\d{1,5}` (HIP-10000+ safe); placeholder blocklist rejects HIP-0000 and HIP-9999 template values. | text on stdin | JSON array of HIP numbers, deduplicated and sorted ascending; `[]` if no matches. |
| `fetch-hip-updates.sh` | Fetch HIPs touched in `hiero-ledger/hiero-improvement-proposals` on a target date, including frontmatter parsing, status-change detection (compares frontmatter `status:` at the touching commit vs its parent), and proposal-PR awareness (HIPs that exist only as open PRs against the HIP repo). | `<YYYY-MM-DD>` | JSON array of records `{hip, title, status, prev_status?, status_changed, type, category, primary_author, abstract_excerpt, raw_url, discussions_url, source, last_touched_commit?, proposal_pr_number?}`; empty array if no activity. |
| `fetch-hip-implementation-prs.sh` | For one HIP on one date, search PRs and commits across configured orgs for HIP references (Mechanism B). Bounded by the caller; the helper runs one search per org per call. **Iteration 2:** each emitted PR/commit dict includes `confidence: "high"`, `source: "mech_b"`, and `per_source` for the unified Match schema. | `<hip-number> <YYYY-MM-DD> [comma-separated-orgs]` (orgs defaults to `hiero-ledger`) | JSON object `{hip, prs: [...], commits: [...]}` where each entry has repo/title/url/author/date/confidence/source/per_source fields. |
| `fetch-hip-release-refs.sh` _(iteration 2 - Strategy 2)_ | Scan release notes from `implementation_orgs` repos for HIP references in the digest window. HIP-N in release tag/name emits `high` confidence with `reason: "in_tag"`; HIP-N only in the body emits `medium` confidence with `reason: "in_body"`. PRs attributed via `gh api compare/<prev-tag>...<this-tag>` parsing of `(#NNN)` tokens in commit messages. Backfill mode capped at `strategy2.max_backfill_days` (30 default); `--force-backfill` overrides. | `<YYYY-MM-DD> [--backfill N] [--force-backfill]` | JSON array of MatchRecords with `release_tag` and `release_url` for verbose-mode rendering. |
| `fetch-hip-timeline-correlations.sh` _(iteration 2 - Strategy 3)_ | For HIPs that changed status today (and have a valid `prev_status`), run one batched `gh search prs` per org with the HIP-N OR keyword-from-HIP-title disjunction. Per-org budget cap (`strategy3.per_org_search_budget`, default 10) + exponential 1s/2s/4s backoff on 429; after 3 retries, emits a `source: "s3_skipped"` record and continues without crashing. Score: ≥3 keyword overlap → `medium`; 1-2 + category-tiebreaker repo match → `low`; 0 overlap → drop. Repos with > `noise_ceiling_commits_per_day` (20 default) commits on the digest day get matches downgraded to `low`. | `<YYYY-MM-DD>` | JSON array of MatchRecords with `matched_keywords` and optional `category_tiebreak` for verbose-mode rendering. |
| `calibrate-hip-matches.sh` _(iteration 2 - calibration)_ | Measure precision/recall/F1 of HIP-to-code matching strategies against the strategy-independent labeled set at `~/.config/team-digest/hip-code-mapper-labeled-set.json`. `--baseline <dry-run-output>` reads the run's peer matches.json and computes per-strategy + overall metrics, writing to `~/.config/team-digest/hip-calibration-baseline.json` with a Phase 1 acceptance verdict. `--current-only [dry-run-output]` emits the run's match-count distribution to `hip-calibration-current.json` and warns if the baseline is >180 days old. | `--baseline <dry-run>` \| `--current-only [dry-run]` | Stdout summary; writes the calibration JSON files. |
| `phase2-gate.sh` _(iteration 2 - Phase 2 gate)_ | Apply the iteration-2 OR rule (`recall < 0.7 OR missed >= 5`) to the calibration baseline. Writes `~/.config/team-digest/iteration-2-phase2-decision.json` with one of three states: `DEFERRED_AWAITING_BASELINE` (no baseline exists yet), `DEFER` (Phase 1 met acceptance criteria), `TRIGGER` (Phase 2 = Strategy 4 unlocked). Re-run any time the baseline refreshes. | _(none; reads baseline JSON)_ | Decision JSON to stdout; writes decision file. |

## Conventions

- Every helper accepts positional args, validates them with `${ARG:?usage}`,
  and exits 1 with a usage hint if a required arg is missing.
- All helpers use `set -euo pipefail`. Failures abort the helper; the
  skill catches the failure (non-zero exit) and continues to the next
  source per the skill's "if any section fails, produce a partial
  digest" rule.
- Helpers do not write to disk. They do not log to a fixed location.
  The terminal entry point (`bin/team-digest-run.sh`) handles logging.
- Helpers do not call MCP tools. MCP (notably the Notion tools) is
  only callable from inside Claude. Anything that needs an MCP call
  stays in `SKILL.md`.
- Python is invoked inline via `python3 - <<'PY' ... PY` for parsing
  JSON output from `gh`. We use stdlib only — no `pip install` needed.

## Local invocation contract

The skill installs to `~/.claude/skills/team-digest/`, with this `lib/`
directory copied alongside `SKILL.md` by `setup.sh` and `update.sh`.
Helpers are invoked by absolute path:

```bash
bash ~/.claude/skills/team-digest/lib/<helper>.sh <args>
```

`bin/team-digest-run.sh` invokes the same skill via `claude -p
"/team-digest ..."`, which means helpers run inside Claude's Bash tool
either way.

## Adding a new helper

1. Drop the file in this directory with a `.sh` extension and an
   executable bit (`chmod +x lib/<name>.sh`).
2. Document its purpose, inputs, and output shape in the header
   comment of the script itself, then add a row to the table above.
3. Add the call site in `SKILL.md`. Helpers without a call site do
   nothing.
4. Run `./update.sh` from the repo root to sync to
   `~/.claude/skills/team-digest/lib/`.
