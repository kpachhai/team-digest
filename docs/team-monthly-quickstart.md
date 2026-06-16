# Team Monthly Digest - Quickstart

The monthly digest synthesizes a calendar month of `Team Daily Digest` + `Team Weekly Digest` pages from your Notion database into a single storyline-first monthly summary, written back to the same database.

## What It Does

`/team-monthly` reads the weeklies and dailies that already exist in Notion and produces a page that reads coherently top-to-bottom - something no single weekly can give you:

- **The Month in Review** - a 3-5 paragraph narrative of the month's arc
- **Top Storylines** - 4-7 named threads, each interconnecting repos + HIPs + partner asks + Notion docs + releases into one `started -> landed -> what's next` story. This is the monthly's reason to exist.
- **By the Numbers** - releases table, repos-active trend, HIP status arcs across the month, keyword frequency (most of this is built from cheap page-properties, not body fetches)
- **Supporting Detail** - the exhaustive weekly-style catalog so nothing is lost
- **Week-by-Week Index** - quick-jump links back into each weekly (and through them, the dailies)

It does NOT re-scan GitHub, Notion, RSS, or HIPs. The dailies and weeklies already did that. The monthly compounds them.

### How it reads the month (hybrid spine)

To stay token-efficient, the monthly reads cheapest-first:

1. **One properties query** returns the metadata (repo counts, keywords, dates) for *every* daily and weekly in the month - nearly free.
2. **It fetches the 4-5 weekly bodies in full** - the synthesized spine.
3. **It selectively deep-reads only a capped handful of daily bodies** (default 8, via `monthly.max_daily_deep_fetch`) - the high-signal days a storyline needs. The footer states `N of M dailies read in full` so the tradeoff is visible.

## Prerequisites

1. `/team-digest` (daily) and `/team-weekly` (weekly) are set up and have been writing pages to your Notion database for at least one full calendar month.
2. The same `~/.config/team-digest/config.json` and `~/.config/team-digest/profiles/team-digest.md` that the daily/weekly use - this skill reads them directly. No separate config block.

## Run it

```
/team-monthly                                      # last full calendar month
/team-monthly 2026-05                              # a specific calendar month
/team-monthly 2026-05-14                           # the calendar month containing this date
/team-monthly --from 2026-04-15 --to 2026-05-20    # arbitrary date range, inclusive
/team-monthly --dry-run                            # preview - markdown to /tmp/team-digest-dry-runs/, no Notion write
/team-monthly 2026-05 --dry-run                    # month mode + dry run
/team-monthly config                               # show current config
```

The first time you run it, do a `--dry-run` against a complete past month to see the synthesis quality - especially the Top Storylines section - before letting it write to Notion.

**Month boundary:** weeklies are included by their stored Sunday date; days at the very end of a month that belong to a week ending in the next month are still covered from their dailies. So `/team-monthly 2026-05` covers all of May at the daily level plus every weekly whose Sunday fell in May.

## Run it from a terminal

```bash
bin/team-monthly-run.sh                          # last full calendar month
bin/team-monthly-run.sh 2026-05                   # a specific calendar month
bin/team-monthly-run.sh 2026-05 --dry-run         # preview
```

The monthly runner defaults to the **Opus** model (synthesis is reasoning-heavy and runs only once a month, so the cost is negligible). Override with `TEAM_DIGEST_MODEL=...`. Symlink to `~/.local/bin/` for cron/launchd convenience:

```bash
ln -sf "$(pwd)/bin/team-monthly-run.sh" ~/.local/bin/team-monthly-run.sh
```

## Schedule it

Run on the 1st of each month (for the prior full month), after that day's daily and the prior week's weekly have had a chance to land. See [`docs/scheduling.md`](scheduling.md) for the full launchd plist; the key difference from the weekly is `StartCalendarInterval` with `Day = 1` instead of `Weekday`.

## The cascade makes everything else better

Once monthlies start landing, the **context cascade** kicks in automatically: each weekly loads the most-recent monthly's lead before it runs, and each daily loads the most-recent weekly's Executive Summary. That background lets a daily add one clause of storyline context ("part of the ongoing migration") instead of presenting each change cold - while keeping the daily's content scoped to its own window. No configuration needed (toggle with `cascade.enabled` in config). The weekly-from-monthly link is a no-op until your first monthly exists, then it switches on by itself.

## Output

The monthly page lands in the SAME Notion database as the daily and weekly pages, distinguished by `Digest Type = Monthly`. The title is `Team Monthly Digest - <Month YYYY>` (e.g. `Team Monthly Digest - May 2026`).

Filter the database view by `Digest Type` to separate monthly rollups from weekly and daily entries.

## Failure modes

- **No dailies/weeklies in window** - skill aborts with a clear message. Generate them first via `/team-digest` and `/team-weekly`.
- **Some weeklies missing** - skill produces a partial monthly with gap notes in the Week-by-Week Index. Synthesis proceeds from the weeklies that ARE present, supplemented by daily metadata.
- **A weekly-fetch fails (page deleted or moved)** - skill notes the gap and synthesizes from the rest.

## See also

- [`docs/architecture.md`](architecture.md) - the three-tier cadence and the context cascade, including why the monthly is a synthesis layer over the weeklies, not a parallel scanner
- [`docs/configuration.md`](configuration.md) - the shared config plus the `monthly` and `cascade` blocks
- [`docs/team-weekly-quickstart.md`](team-weekly-quickstart.md) - set up the weekly first; monthly depends on weeklies already being in Notion
- [`docs/scheduling.md`](scheduling.md) - launchd plist and cron syntax for production scheduling
- [`docs/troubleshooting.md`](troubleshooting.md) - common failure modes and recovery paths
