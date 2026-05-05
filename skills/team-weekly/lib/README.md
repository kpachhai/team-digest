# team-weekly helpers

Shell helpers invoked by the `team-weekly` skill. The skill body owns
all MCP-driven work (Notion query, fetch, write); this directory
contains only the bash work that has no MCP dependency.

## Helpers

| Helper | Purpose | Inputs | Output |
|---|---|---|---|
| `compute-week-window.sh` | Resolve a date arg (or default to last full ISO week) into `WEEK_START`, `WEEK_END`, `WEEK_LABEL`, `START`, `END`. | optional `YYYY-MM-DD` arg | `KEY=VALUE` lines suitable for `eval`. |

## Conventions

Same as `skills/team-digest/lib/`: `set -euo pipefail`, positional args
validated with `${ARG:?usage}`, errors to stderr, primary output to
stdout, no MCP calls (those only work inside Claude), no disk writes
(the bin/ wrapper handles logging).

## Sharing with team-digest helpers

This skill ALSO calls `~/.claude/skills/team-digest/lib/load-config.sh`
to read the shared `team-digest` config. We deliberately read the same
config file rather than maintaining a separate `team-weekly` config -
the two skills share Notion IDs, GitHub orgs, and the team profile.
