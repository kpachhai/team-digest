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
| `extract-hip-refs.sh` | Find `HIP-N` references in arbitrary text on stdin. Matches `HIP-1137`, `HIP 1137`, `HIP_1137`, `hip1137` (case-insensitive) plus blob-URL forms (`hiero-improvement-proposals/blob/main/HIP/hip-1137.md`). Filters against the known-HIPs index when present; degrades to "emit all matches" if the index is missing. | text on stdin | JSON array of HIP numbers, deduplicated and sorted ascending; `[]` if no matches. |
| `fetch-hip-updates.sh` | Fetch HIPs touched in `hiero-ledger/hiero-improvement-proposals` on a target date, including frontmatter parsing, status-change detection (compares frontmatter `status:` at the touching commit vs its parent), and proposal-PR awareness (HIPs that exist only as open PRs against the HIP repo). | `<YYYY-MM-DD>` | JSON array of records `{hip, title, status, prev_status?, status_changed, type, category, primary_author, abstract_excerpt, raw_url, discussions_url, source, last_touched_commit?, proposal_pr_number?}`; empty array if no activity. |
| `fetch-hip-implementation-prs.sh` | For one HIP on one date, search PRs and commits across configured orgs for HIP references (Mechanism B). Bounded by the caller; the helper runs one search per org per call. | `<hip-number> <YYYY-MM-DD> [comma-separated-orgs]` (orgs defaults to `hiero-ledger`) | JSON object `{hip, prs: [...], commits: [...]}` where each entry has repo/title/url/author/date fields. |

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
