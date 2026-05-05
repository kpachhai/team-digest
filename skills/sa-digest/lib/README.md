# sa-digest helpers

Shell helpers invoked by the `sa-digest` skill. Each helper does one thing,
exits non-zero on failure with errors on stderr, and writes its primary
output to stdout. The skill body (`SKILL.md`) treats each helper's stdout
as plain text input for the narrative writing step.

These helpers also run from `bin/sa-digest-run.sh` (the headless terminal
entry point) by way of the same skill — there is no parallel
implementation. The skill is the orchestrator; helpers are the data layer.

## Helpers

| Helper | Purpose | Inputs | Output |
|---|---|---|---|
| `compute-window.sh` | Resolve a date arg (or default to yesterday-UTC) into `DATE_LABEL`, `START`, `END` ISO timestamps. | optional `YYYY-MM-DD` arg | `KEY=VALUE` lines suitable for `eval`. |
| `load-config.sh` | Read and validate the team-digest config for one digest (e.g. `sa-digest`). Confirms required Notion IDs are present. | `<digest-name>` | The digest's config object as JSON. |
| `fetch-github-prs.sh` | Fetch PRs updated in the window for one org. | `<org> <start-iso>` | Plain-text summary grouped by repo, with PR numbers, authors, URLs, descriptions. |
| `fetch-github-issues.sh` | Fetch issues updated in the window for one org. | `<org> <start-iso>` | Plain-text summary, same shape as PRs. |
| `fetch-github-releases.sh` | Fetch releases published in the window for one org. Iterates every repo via `gh api`. | `<org> <start-iso>` | One line per release: `<repo>: <tag> - <name> (<date>) <url>`. |

## Conventions

- Every helper accepts positional args, validates them with `${ARG:?usage}`,
  and exits 1 with a usage hint if a required arg is missing.
- All helpers use `set -euo pipefail`. Failures abort the helper; the
  skill catches the failure (non-zero exit) and continues to the next
  source per the skill's "if any section fails, produce a partial
  digest" rule.
- Helpers do not write to disk. They do not log to a fixed location.
  The terminal entry point (`bin/sa-digest-run.sh`) handles logging.
- Helpers do not call MCP tools. MCP (notably the Notion tools) is
  only callable from inside Claude. Anything that needs an MCP call
  stays in `SKILL.md`.
- Python is invoked inline via `python3 - <<'PY' ... PY` for parsing
  JSON output from `gh`. We use stdlib only — no `pip install` needed.

## Local invocation contract

The skill installs to `~/.claude/skills/sa-digest/`, with this `lib/`
directory copied alongside `SKILL.md` by `setup.sh` and `update.sh`.
Helpers are invoked by absolute path:

```bash
bash ~/.claude/skills/sa-digest/lib/<helper>.sh <args>
```

`bin/sa-digest-run.sh` invokes the same skill via `claude -p
"/sa-digest ..."`, which means helpers run inside Claude's Bash tool
either way.

## Adding a new helper

1. Drop the file in this directory with a `.sh` extension and an
   executable bit (`chmod +x lib/<name>.sh`).
2. Document its purpose, inputs, and output shape in the header
   comment of the script itself, then add a row to the table above.
3. Add the call site in `SKILL.md`. Helpers without a call site do
   nothing.
4. Run `./update.sh` from the repo root to sync to
   `~/.claude/skills/sa-digest/lib/`.
