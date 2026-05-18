# Troubleshooting

## Setup Issues

### "gh: command not found"

Install the GitHub CLI:
```bash
# macOS
brew install gh

# Linux
sudo apt install gh   # or see https://cli.github.com
```

Then authenticate:
```bash
gh auth login
```

### "claude: command not found"

Install Claude Code:
```bash
# macOS/Linux
npm install -g @anthropic-ai/claude-code
```

Or see https://claude.ai/code for other installation methods.

### Notion MCP not connected

The Notion MCP server must be connected in Claude Code for keyword and partner scanning to work.

1. Open Claude Code
2. Go to Settings > MCP Servers
3. Add the Notion connector
4. Authenticate with your Notion account

If Notion MCP is unavailable, the digest will still produce the GitHub section and mark the Notion sections as failed.

## Runtime Issues

### "No results" for Notion keyword searches

- The `created_date_range` filter only matches pages **created** in the time window, not pages that were **edited**. If a page was created last week but edited today, it will not appear.
- Check that the Notion MCP has access to the workspace pages you expect. The search operates with your authenticated user's permissions.
- Try running a manual search in Notion's own UI to verify the pages exist.

### GitHub rate limiting

`gh` uses whichever token it resolves first: `$GH_TOKEN` env var → `$GITHUB_TOKEN` env var → the credential `gh auth login` stored. Authenticated users get 5,000 core API requests/hour and 30 search requests/hour, well within limits for a daily digest run. The `bin/team-digest-run.sh` headless wrapper uses the same resolution — for cron and launchd, set `GH_TOKEN` in the wrapper script's environment.

If no token is available (no env var set and `gh auth status` fails), the skill aborts with a clear error rather than producing a partial digest. To fix: either run `gh auth login`, or export `GH_TOKEN=<your_PAT>` in the shell where you invoke the digest. The skill does NOT read tokens from `config.json` — env-var-only by design (avoids storing secrets on disk). See [docs/configuration.md](configuration.md#github-authentication) for required scopes and when to override the `gh auth login` default.

To check your current rate limit status:
```bash
gh api rate_limit --jq '.rate'
```

### Digest page is missing sections

The digest is designed to produce partial output on failure. If a section shows a failure indicator:
- **GitHub section failed:** Check `gh auth status` and network connectivity
- **Notion keywords failed:** Check that Notion MCP is connected and authenticated
- **Partner conversations failed:** Same as keywords - check Notion MCP

### Bootstrap failed partway through

`/team-digest setup` (when you choose `new`) creates four artifacts in order: Notion parent page, Notion config page, Notion database, local config.json. The local profile file is written only if it doesn't already exist. There is no atomic rollback — if a later step fails, earlier artifacts stay. Recovery depends on where it failed:

- **Parent page created, config page failed:** delete the orphan parent page in Notion UI, then re-run `/team-digest setup`.
- **Parent + config page created, database failed:** delete both pages in Notion UI, then re-run.
- **All Notion pages created, profile file write failed:** the confirmation message will show the Notion URLs. Create `~/.config/team-digest/profiles/team-digest.md` manually (copy from `profiles/team-digest.template.md` in the repo). No need to re-run `setup`.
- **All Notion pages and profile created, config.json write failed:** the error message will print the two IDs. Paste them manually into `~/.config/team-digest/config.json` under the `team-digest.notion` block. No need to re-run.

If you've already started `setup` once and want to abandon and try fresh: delete the parent page in Notion (which cascades to its children), `rm ~/.config/team-digest/config.json`, and re-run `setup`.

### HIP section is empty when I expect content

If the `## HIP Activity` section is missing from the digest on a day you know had HIP commits, run through these checks in order:

1. Confirm the date actually had HIP commits:
   ```bash
   gh api -X GET repos/hiero-ledger/hiero-improvement-proposals/commits \
     --field since=<DATE>T00:00:00Z \
     --field until=<DATE>T23:59:59Z \
     --field path=HIP \
     --paginate \
     --jq 'length'
   ```
   A `0` result means there was no HIP activity that day - the section is correctly omitted. Anything > 0 means continue to the next check.

2. Check that `hip_tracking.enabled` is `true` in your config:
   ```bash
   bash skills/team-digest/lib/load-config.sh team-digest | jq '.hip_tracking.enabled'
   ```
   If this prints `false`, the section is correctly omitted. Edit `~/.config/team-digest/config.json` to set it to `true`.

3. Check that the env-var override isn't disabling it:
   ```bash
   echo "TEAM_DIGEST_HIP_ENABLED=${TEAM_DIGEST_HIP_ENABLED:-unset}"
   ```
   If this prints `0`, unset it (`unset TEAM_DIGEST_HIP_ENABLED`) and re-run.

4. Check that the known-HIPs index file exists and is non-empty:
   ```bash
   wc -l ~/.config/team-digest/hip-numbers.txt
   ```
   Empty or missing means Mechanism A annotations will be skipped (regex matches without an index can't be filtered for false positives). Force a refresh: `bash skills/team-digest/lib/refresh-hip-index.sh`.

### Notion update step failed - recover with --from-file

The daily and weekly skills split the Notion write into two MCP calls: `notion-create-pages` (creates the page with a placeholder body) followed by `notion-update-page` (writes the full content). This keeps each call within the Notion MCP timeout budget. If the second call fails after the first succeeds, the page exists in Notion with a placeholder body and the full content lives in the safety file at `/tmp/team-digest-dry-runs/team-digest-<DATE>-v<N>.md`. Recover by re-running from the safety file:

```bash
bin/team-digest-run.sh <DATE_LABEL> --from-file /tmp/team-digest-dry-runs/team-digest-<DATE>-v<N>.md
```

If you want a clean retry instead, delete the placeholder page in Notion first; the re-run will create a fresh page.

### Known-HIPs index file is stale or missing

The HIP cross-reference annotation (Mechanism A) filters regex matches against a local index of known HIP numbers at `~/.config/team-digest/hip-numbers.txt`. The index is refreshed at most weekly. If it's older than a week (or you suspect missing HIPs), force a refresh:

```bash
rm ~/.config/team-digest/hip-numbers.txt
bash skills/team-digest/lib/refresh-hip-index.sh
wc -l ~/.config/team-digest/hip-numbers.txt   # should be 100+ HIPs on the canonical Hiero repo
```

A non-empty index gates the `Linked HIPs:` annotation - without it, the helpers fall back to "no annotations" rather than risk surfacing false-positive HIP references. If the refresh helper itself fails, check `gh auth status` and that the configured `hip_tracking.repo` is reachable.

### HIP-to-code confidence calibration drift

The daily run emits a per-run match-count distribution to `~/.config/team-digest/hip-calibration-current.json` and warns on stderr if the baseline (in `hip-calibration-baseline.json`) is more than 180 days old. To re-baseline:

```bash
/team-digest 2026-05-06 --dry-run                                       # produces a v1 dry-run + matches.json
bash skills/team-digest/lib/calibrate-hip-matches.sh --baseline \
    /tmp/team-digest-dry-runs/team-digest-2026-05-06-v1.md
```

Re-run the baseline when any of the recalibration triggers fire: labeled set > 6 months old; new HIP-N where N exceeds labeled-set max by 100+; Phase 2 (Strategy 4) has been triggered; the per-run drift warning fires 3+ times in a 30-day window. Edit `~/.config/team-digest/hip-code-mapper-labeled-set.json` to add new positive / negative examples as the codebase + HIP space evolves.

### Strategy 3 timeline correlation hit rate-limit

When `fetch-hip-timeline-correlations.sh` exhausts its per-org budget (`strategy3.per_org_search_budget`, default 10) or sees three back-to-back 429 / secondary-rate-limit responses, it emits a single `source: "s3_skipped"` MatchRecord and continues - it does NOT crash the digest. The skipped record renders in the verbose-mode subsection only (`TEAM_DIGEST_HIP_VERBOSE=1`) with a no-PR-link form.

If skips are recurring:

- Lower `strategy3.max_correlation_hips` to cap the OR-query size.
- Raise `strategy3.per_org_search_budget` if you have headroom on your `gh` token's rate limit.
- Check that the digest is running under a token, not gh CLI guest mode (`gh auth status`).

### Strategy 4 budget exhausted (Phase 2 only)

If iteration 2's gate triggered Phase 2 and Strategy 4 is running, every digest run logs cumulative LLM spend. At 80% of `strategy4.cost_cap_usd` (default $2.00), a `[WARN]` fires on stderr; at 100%, the strategy circuit-breaks and the digest emits a `Strategy 4 budget exhausted at $X.XX — N HIPs unscored` footnote in the HIP Activity section header.

Options:

- Wait for the next digest run; cache hits (keyed on `(hip_id, hip_content_sha)` + `(repo, pr_number, pr_title_sha, pr_labels_sha)`) typically push the second run's spend below the cap.
- Raise `strategy4.cost_cap_usd` in `~/.config/team-digest/config.json` if your team's HIP volume genuinely needs more budget.
- Lower `strategy3.max_correlation_hips` to feed Strategy 4 fewer candidate HIPs.

### Duplicate digest pages

If the automation ran and you also ran `/team-digest` manually, you will get two digest pages for the same day. The database has a "Status" property - automated runs are "Auto", which you can use to filter.

To avoid duplicates, check the database before running manually:
1. Open your digest database in Notion (the `database_id` from your `config.json`)
2. Look for today's date
3. If a page exists, you can update it instead of creating a new one

## Common Questions

### Can I change the scan window?

The default is 24 hours. The scan window is set in the `gh search` commands (the `--updated` flag) and the Notion `created_date_range` filter. To change it, edit the configuration page's "Scan Window" section.

### Can multiple team members run the digest?

Yes. Each person creates their own digest page in the shared Notion database. The "Auto-generated by" footer shows which instance created it. For automated runs, each person sets up their own launchd / cron schedule using `bin/team-digest-run.sh` on their own machine.

### What if I want different keywords than the team?

The Notion configuration page is shared. If you need personal keywords, you can:
1. Create a copy of the configuration page in your own Notion space
2. Update the `config_page_id` in your local `config.json` to point to your personal copy
3. Re-run `setup.sh` to sync the change

### How do I stop the automated runs?

- **macOS launchd:** `launchctl unload ~/Library/LaunchAgents/com.team-digest.team-digest.plist` (and optionally delete the plist)
- **Linux cron:** `crontab -e` and remove or comment the `team-digest-run.sh` line
- **GitHub Actions:** disable or delete the workflow in `.github/workflows/`
