# team-monthly helpers

Shell helpers invoked by the `team-monthly` skill. The skill body owns all
MCP-driven work (Notion query, fetch, write); this directory contains only
bash work with no MCP dependency.

## Helpers

| Helper | Purpose | Inputs | Output |
|---|---|---|---|
| `compute-month-window.sh` | Resolve a calendar month (or `--from/--to` range; default last full calendar month) into `MONTH_START`, `MONTH_END`, `MONTH_LABEL`, `MONTH_NAME`, `START`, `END`. | optional `YYYY-MM` / `YYYY-MM-DD`, or `--from F --to T` | `KEY=VALUE` lines for `eval` (`MONTH_NAME` is single-quoted because it contains a space). |

## Conventions

Same as `skills/team-digest/lib/` and `skills/team-weekly/lib/`: `set -euo pipefail`,
errors to stderr, primary output to stdout, no MCP calls (those only work inside
Claude), no disk writes (the `bin/` wrapper handles logging).

## Sharing with team-digest helpers

This skill ALSO calls `~/.claude/skills/team-digest/lib/load-config.sh` to read the
shared `team-digest` config. The three cadences (daily, weekly, monthly) share one
config block, Notion IDs, GitHub orgs, and the team profile.
