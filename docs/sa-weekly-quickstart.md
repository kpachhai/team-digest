# SA Weekly Digest - Quickstart

The weekly digest synthesizes the past week's `SA Daily Digest - <date>` pages from your Notion database into a single weekly summary, written back to the same database.

## What It Does

`/sa-weekly` reads the dailies that already exist in Notion and surfaces themes that span multiple days - things you cannot see from any single daily:

- **Top GitHub themes** - repos with sustained activity across the week (3+ days), with linked PRs/issues
- **Releases this week** - all releases from any daily, in a single linked table
- **Partner momentum** - companies that came up multiple times, with multi-day "open threads"
- **Notion content pulse** - keywords that spanned multiple days, with example pages
- **Industry news roundup** - deduplicated RSS items across the week, grouped by category
- **Favorites movement** - favorited pages that updated on 2+ days (active work) vs. single-day touches
- **Day-by-Day Index** - quick-jump links back into each daily

It does NOT re-scan GitHub, Notion, or RSS. The dailies have already done that work; the weekly compounds them.

## Prerequisites

1. The `/sa-digest` skill is set up and has been writing daily pages to your Notion database for at least one full ISO week (Mon-Sun in UTC).
2. The same `~/.config/team-digest/config.json` and `~/.config/team-digest/profiles/sa-digest.md` that `/sa-digest` uses - this skill reads them directly. No separate config block.

## Run it

```
/sa-weekly                           # last full week (Mon-Sun)
/sa-weekly 2026-05-07                # ISO week containing this date
/sa-weekly --dry-run                 # preview - markdown to /tmp/team-digest-dry-runs/, no Notion write
/sa-weekly 2026-05-07 --dry-run      # both
/sa-weekly config                    # show current config
```

The first time you run it, do a `--dry-run` against a complete past week to see the synthesis quality before letting it write to Notion.

## Run it from a terminal

```bash
bin/sa-weekly-run.sh                          # last full week
bin/sa-weekly-run.sh 2026-05-07               # specific week
bin/sa-weekly-run.sh 2026-05-07 --dry-run     # preview
```

Symlink to `~/.local/bin/` for cron/launchd convenience:

```bash
ln -sf "$(pwd)/bin/sa-weekly-run.sh" ~/.local/bin/sa-weekly-run.sh
```

## Schedule it

Run on Monday morning, after Friday's daily had a chance to land. macOS launchd plist (mirrors `docs/scheduling.md`'s sa-digest pattern):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.team-digest.sa-weekly</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/YOUR_USERNAME/.local/bin/sa-weekly-run.sh</string>
  </array>

  <!-- Mondays at 9:00 AM local time -->
  <key>StartCalendarInterval</key>
  <array>
    <dict>
      <key>Weekday</key><integer>1</integer>
      <key>Hour</key><integer>9</integer>
      <key>Minute</key><integer>0</integer>
    </dict>
  </array>

  <key>StandardOutPath</key>
  <string>/Users/YOUR_USERNAME/.local/log/sa-weekly-launchd.log</string>

  <key>StandardErrorPath</key>
  <string>/Users/YOUR_USERNAME/.local/log/sa-weekly-launchd.log</string>

  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
```

Save as `~/Library/LaunchAgents/com.team-digest.sa-weekly.plist`, replace `YOUR_USERNAME` with `whoami` output, then:

```bash
launchctl load ~/Library/LaunchAgents/com.team-digest.sa-weekly.plist
```

## Output

The weekly page lands in the SAME Notion database as the daily pages, distinguished by the `Digest Type = Weekly` property. The title is `SA Weekly Digest - <YYYY-Wxx> (<Mon-date> to <Sun-date>)`.

Filter the database view by `Digest Type` to separate weekly rollups from daily entries.

## Failure modes

- **No dailies in window** - skill aborts with a clear message. Generate the dailies first via `/sa-digest <date>` for each missing day.
- **Some dailies missing (e.g., Wednesday's run was skipped)** - skill produces a partial weekly with a "no daily digest run" note in the Day-by-Day Index. Synthesis proceeds with the days that ARE present.
- **A daily-fetch fails (page deleted or moved)** - skill notes the gap and synthesizes from the rest.
