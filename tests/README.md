# team-digest offline tests

Deterministic, offline tests for the parts of team-digest that are pure logic -
no network, no Notion MCP, no `claude` invocation. Run the whole suite with:

```bash
bash tests/run-all.sh
```

It runs every `tests/*.test.sh`, prints a per-file pass/fail line, and exits
non-zero if anything fails. No dependencies beyond `bash` + `python3` (already
required by the helpers).

## What is covered

The **9 pure helpers** (deterministic, file/stdin/arg in -> stdout/file out) plus
the Notion-markdown linter:

| Test file | Helper under test | What it checks |
|---|---|---|
| `compute-window.test.sh` | `team-digest/lib/compute-window.sh` | single-day + range (`A..B`, `--from/--to`, `--days N`) resolution, `IS_RANGE` flag, default-yesterday, calendar + format validation, error exits |
| `compute-week-window.test.sh` | `team-weekly/lib/compute-week-window.sh` | ISO week (Mon..Sun) resolution, custom range, Monday/7-day invariants, errors |
| `compute-month-window.test.sh` | `team-monthly/lib/compute-month-window.sh` | calendar month, leap Feb, date-in-month, custom range, weekly-span (first Mon..last Sun) + `HAS_FULL_WEEK`, errors |
| `coverage-gap.test.sh` | `team-digest/lib/coverage-gap.sh` | window vs covered ranges: range pages covering multi-day spans, single-day dailies, gaps, overlap/out-of-window clamping, bad-input exit 2 |
| `extract-hip-refs.test.sh` | `team-digest/lib/extract-hip-refs.sh` | HIP regex forms, dedup, placeholder blocklist, known-HIPs index filter |
| `load-config.test.sh` | `team-digest/lib/load-config.sh` | valid config, missing file/key/IDs, malformed JSON (exit codes 1-4) |
| `consolidate-matches.test.sh` | `team-digest/lib/consolidate-matches.sh` | `(hip_id,repo,pr_number)` dedup, MAX-confidence merge, Mech B dict lift, sorting |
| `strategy4-gate.test.sh` | `team-digest/lib/strategy4-gate.sh` | DEFER/TRIGGER/DEFERRED state machine, lens selection, boundaries |
| `calibrate-hip-matches.test.sh` | `team-digest/lib/calibrate-hip-matches.sh` | precision/recall/fp per lens, window filter, `s2_in_tag` aliasing, `--current-only`, errors |
| `lint-digest-markdown.test.sh` | `tests/lint-digest-markdown.sh` | the linter itself: valid pages pass, malformed fail, `--template` mode |

`lib-assert.sh` holds the shared assertion helpers (sourced by each test; not a
test itself). `lint-digest-markdown.sh` is both a test target and a reusable tool
- it lints any tier's dry-run safety file (`--template` for `TEMPLATE.md` files).

## What is NOT covered here (by design)

- **The 11 network fetch helpers** (`fetch-github-*.sh`, `fetch-hip-*.sh`,
  `fetch-rss.sh`, `fetch-gh-commits.sh`, `refresh-hip-index.sh`) call `gh`/`curl`
  and need live network + auth. Mocking them is brittle and low-value; verify them
  by running an actual `/team-digest --dry-run`.
- **The three `SKILL.md` pipelines** (daily/weekly/monthly) are prompts that run
  inside Claude against Notion MCP - not unit-testable. The offline proxy for their
  output shape is `lint-digest-markdown.sh` against a `--dry-run` safety file;
  end-to-end correctness is validated operationally with `--dry-run` on the work machine.

## Testability env overrides

To run in isolation without reading or clobbering real `~/.config/team-digest/`
state, these helpers honor env overrides (unset -> production default, so runtime
behavior is unchanged):

| Env var | Helper(s) | Overrides |
|---|---|---|
| `TEAM_DIGEST_CONFIG` | `load-config.sh` | config.json path (pre-existing) |
| `TEAM_DIGEST_HIP_INDEX` | `extract-hip-refs.sh` | known-HIPs index path |
| `TEAM_DIGEST_CALIBRATION_BASELINE` | `strategy4-gate.sh`, `calibrate-hip-matches.sh` | baseline JSON path |
| `TEAM_DIGEST_GATE_DECISION` | `strategy4-gate.sh` | decision-output path |
| `TEAM_DIGEST_LABELED_SET` | `calibrate-hip-matches.sh` | labeled-set path |
| `TEAM_DIGEST_CALIBRATION_CURRENT` | `calibrate-hip-matches.sh` | current-snapshot path |

## Known gaps the tests surfaced (not yet fixed - intentional)

1. **`strategy4-gate.sh` boundary at `missed == 5`.** The code is
   `trigger = (recall < 0.7) OR (missed >= 5)`, so `missed == 5` -> TRIGGER. Some
   human docs phrase the DEFER region as "missed <= 5", which disagrees at exactly
   5. The gate's own docstring and the test follow the code (the source of truth);
   the doc phrasing could be tightened to "missed < 5" / "missed >= 5 triggers".
