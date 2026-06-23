---
name: team-monthly
description: Team Monthly Digest - synthesizes a calendar month of Team Daily + Weekly Digests into a storyline-first monthly rollup, written to the same Notion database. Usage - /team-monthly [YYYY-MM | --from F --to T | --dry-run | --allow-partial | --from-file <path> | config]
user-invocable: true
---

# Team Monthly Digest - Manual Trigger

## Purpose

Run a monthly synthesis of a calendar month's `Team Daily Digest` + `Team Weekly Digest` pages from your Notion database. Reads the weekly pages in full (the synthesized spine), reads cheap page-properties for every daily in the month (the free skeleton), and selectively deep-reads a capped handful of dailies. Produces a storyline-first monthly page that interconnects repos, HIPs, partners, Notion docs, and releases into named threads a single weekly could not surface.

This skill is the month-level "rollup" companion to `/team-digest` (daily) and `/team-weekly` (weekly). It is a CONSUMER, not a scanner: it does NOT re-scan GitHub, Notion keywords, partner conversations, HIPs, or RSS. The dailies and weeklies already did that work; this skill compounds them.

## Usage

- `/team-monthly` - synthesize the **last full calendar month** (the most recent month that has fully ended in UTC)
- `/team-monthly 2026-05` - synthesize that calendar month
- `/team-monthly 2026-05-14` - synthesize the calendar month containing this date
- `/team-monthly --from 2026-04-15 --to 2026-05-20` - synthesize an arbitrary date range (inclusive), parity with `/team-weekly`
- `/team-monthly --dry-run` - run the full pipeline but write the markdown to a local file instead of creating a Notion page
- `/team-monthly 2026-05 --dry-run` - month + dry run
- `/team-monthly 2026-05 --allow-partial` - synthesize from available weekly/daily pages even if some weeks are missing; notes gaps in the digest body rather than aborting. Useful for past months where some weeks were never digested.
- `/team-monthly --from-file /tmp/team-digest-dry-runs/team-monthly-2026-05-v1.md` - upload a previously saved safety file to Notion, skipping synthesis (token-efficient recovery after a timeout); a month arg or `--from`/`--to` must accompany this flag so the Notion properties can be computed
- `/team-monthly config` - show the current config (shared with team-digest)

Flags can appear in any order. Mixing a positional month with `--from`/`--to` is an error. `--from` and `--to` must appear together. `--from-file` and `--dry-run` are mutually exclusive. Safety / dry-run output goes to `/tmp/team-digest-dry-runs/team-monthly-<MONTH_LABEL>-v<N>.md`, ephemeral by design (cleared on reboot).

This skill also runs from the terminal via `bin/team-monthly-run.sh` in the team-digest repo. Same skill, same flags.

## Important Runtime Notes

- **TITLE LOCK.** The Notion page `Digest Title` property and the file header callout title are ALWAYS `Team Monthly Digest - <MONTH_NAME>` (e.g. `Team Monthly Digest - May 2026`) and `**Team Monthly Digest**` respectively. The team profile may name the team differently in the body; that is fine, but it does NOT change the digest title. Never substitute a team-specific name (e.g., "SA Monthly Digest") into the title under any circumstance.
- **DO NOT use `readMcpResource` or `ReadMcpResourceTool`** to fetch Notion markdown specs. The output format is fully defined here and in `TEMPLATE.md`.
- **Config is shared with team-digest.** This skill reads the `team-digest` key from `~/.config/team-digest/config.json` (Notion IDs, GitHub orgs, profile path). It does not require its own config block. The dailies and weeklies must have been generated against the same `database_id`.
- **No network scanning.** No `gh search`, no Notion keyword search, no RSS fetches, no HIP scans. The dailies and weeklies already did that. If you need fresh data, run `/team-digest <date>` then `/team-weekly <week>` for the missing windows first, then re-run `/team-monthly`.
- **DO NOT dispatch Notion MCP calls to `Agent` subagents.** Claude.ai-hosted MCP tools (Notion) are only available in the main Claude Code session - subagents have a separate tool registry that does NOT include them. Every Notion MCP call (`notion-fetch`, `notion-query-data-sources`, `notion-create-pages`, `notion-update-page`) MUST be made directly in the main session. To parallelize, emit multiple MCP tool calls in a single message, not subagents.
- **DO NOT silently fall back to a dry-run write when Notion MCP tools are unavailable.** The dry-run path is reserved for the explicit `--dry-run` flag. If `$DRY_RUN` is NOT set but Notion MCP schemas cannot be loaded (see Step 0.5), STOP the run with a clear error - do not write a dry-run file as a workaround.

## Process

### Step 0: Argument parsing, subcommands, config load

Parse the skill argument as zero or more of:

- A `YYYY-MM` month or `YYYY-MM-DD` date → captured as `$DATE_ARG` (resolves to the calendar month containing it)
- `--from YYYY-MM-DD --to YYYY-MM-DD` → captured as `$FROM` and `$TO` (arbitrary date range, inclusive)
- The literal `--dry-run` → set `$DRY_RUN=1`
- The literal `--allow-partial` → set `$ALLOW_PARTIAL=1` (equivalent to `TEAM_DIGEST_ALLOW_PARTIAL=1` in env; bypasses the Step 2.5 coverage gate and proceeds with whatever weekly/daily pages exist)
- `--from-file <path>` → set `$FROM_FILE` to the path token that follows the flag; activates upload-only mode (see subcommand below)
- The literal `config` → handle as a subcommand (below)

Order does not matter. **Validation rules:**

- `--from` and `--to` must appear together. Specifying one without the other is an error.
- A positional month/date arg cannot coexist with `--from`/`--to`. Pick one mode and surface a clear error if both are given.
- `--from-file` and `--dry-run` are mutually exclusive.
- `--from-file` requires at least one month-context arg (`$DATE_ARG`, or `--from`/`--to`) so `MONTH_LABEL`, `MONTH_NAME`, `MONTH_START`, and `MONTH_END` can be computed for the Notion page properties.

The window-resolution helper (`compute-month-window.sh`) handles all three valid forms (no-arg, single month/date, --from/--to range) and validates each. Pass `$DATE_ARG`, `$FROM`, `$TO` through to it as-is.

#### Subcommand: `--from-file <path>` (upload-only mode)

When `$FROM_FILE` is set, skip the full synthesis pipeline (Steps 1-4) and jump directly to the Notion write. This is the token-efficient recovery path for when a previous run assembled the content but the Notion write timed out.

Flow:
1. Load config (Step 0 Load config below) - still needed for `database_id` and `data_source_id`.
2. Run `compute-month-window.sh` with the provided month/range args to set `$MONTH_LABEL`, `$MONTH_NAME`, `$MONTH_START`, `$MONTH_END`. This is needed for Notion page properties.
3. Load Notion MCP schemas (Step 0.5) - required to call `notion-create-pages` and `notion-update-page`.
4. Fetch `data_source_id` from the database (same `notion-fetch` call as Step 2).
5. Read `$FROM_FILE` using the Read tool. The file contains Notion-flavored markdown assembled by a previous run.
6. Check whether a monthly digest page already exists for `$MONTH_NAME` (search for "Team Monthly Digest - <MONTH_NAME>"). Three cases:
   - **No existing page found:** fall through to step 7 (create + chunked write).
   - **Existing page found AND its body matches the placeholder** (`Monthly digest content loading...` callout) OR **body contains `DIGEST-SECTION-BREAK`** (a previous chunked write was interrupted mid-way): SKIP create, jump to step 8 with `$NEW_PAGE_ID` set to the existing page's id.
   - **Existing page found AND its body has real content (no placeholder, no sentinel):** STOP with a duplicate-protection warning. Do not overwrite. Tell the user the month already has a digest and the file is preserved at `$FROM_FILE`.
7. Call `notion-create-pages` with the placeholder body (`<callout icon="⏳" color="gray">Monthly digest content loading...</callout>`) and standard properties (`Digest Title`, `date:Date:start: $MONTH_START`, `date:Date:end: $MONTH_END`, `date:Date:is_datetime: 0`, `Digest Type: Monthly`, `Status: Auto`). For `Repos Active` and `Keywords Matched` (and `Partners Mentioned`, if the database has that column), use zero / empty-array defaults (the file header callout contains the actual counts inline). Capture `$NEW_PAGE_ID` and `$NEW_PAGE_URL` from the response. If this call fails, tell the user the source file is still at `$FROM_FILE` and they can retry.
8. Upload the file content using the **CHUNKED-WRITE PROCEDURE** defined in Step 5.3 (using `$NEW_PAGE_ID`, `$NEW_PAGE_URL`, and `$FROM_FILE` as the source). The chunked write always starts with `replace_content` for chunk 1, so it safely overwrites any partial content or placeholder already on the page.
9. On success, print the Notion page URL. Do NOT write another safety file (the source file already exists).
10. On step 8 failure mid-chunk, tell the user the page exists at `$NEW_PAGE_URL` with partial content, the source file is still at `$FROM_FILE`, and they can re-run `--from-file` — the step 6 check will detect the `DIGEST-SECTION-BREAK` sentinel and route back to step 8 for a clean restart.

#### Subcommand: `config`

Read `~/.config/team-digest/config.json`, display the `team-digest` config (the same one this skill reads): Notion IDs (masked to last 8 chars), GitHub orgs, default keywords, and the `monthly` block (`max_daily_deep_fetch`, `boundary`). Then stop.

#### Load config

Run the helper:

```bash
bash ~/.claude/skills/team-digest/lib/load-config.sh team-digest
```

Yes - this skill reads the **team-digest** config, not a separate `team-monthly` config. The three cadences (daily, weekly, monthly) share Notion IDs, GitHub setup, and the team profile. This avoids config sprawl. The helper validates `notion.config_page_id` and `notion.database_id` are present and non-empty; on failure, surface the error and stop.

Read `monthly.max_daily_deep_fetch` (default 8) into `$MAX_DEEP` for Step 3b:

```bash
MAX_DEEP=$(bash ~/.claude/skills/team-digest/lib/load-config.sh team-digest | python3 -c "import json,sys; d=json.load(sys.stdin); print((d.get('monthly') or {}).get('max_daily_deep_fetch', 8))")
```

Export the HIP feature flag (consumed by the HIP Movement section in Step 4 to gate it):

```bash
HIP_ENABLED=$(bash ~/.claude/skills/team-digest/lib/load-config.sh team-digest | python3 -c "import json,sys; d=json.load(sys.stdin); print('1' if d.get('hip_tracking',{}).get('enabled',True) else '0')")
export TEAM_DIGEST_HIP_ENABLED="$HIP_ENABLED"
```

Defaults to true if `hip_tracking.enabled` is absent or true; false only if explicitly set to false in config.

Also read the team profile at `~/.config/team-digest/profiles/team-digest.md`. Used for the **Relevance** synthesis and storyline ranking. If absent, fall back to generic relevance heuristics. Its **Project Glossary** drives first-mention expansions.

**Cascade context (reserved):** the monthly reserves the same higher-tier context hook the daily and weekly use - it would load the most-recent `Quarterly` digest's Executive Summary for month-arc context. No quarterly cadence exists yet, so this is a documented no-op: skip it silently. When a quarterly is added, this hook activates with no other change.

**Also read `~/.claude/skills/team-monthly/TEMPLATE.md` NOW** using the Read tool. This is the canonical output contract - section order, header callout format, the storyline shape, By the Numbers, Supporting Detail, and Format Rules. Loading it at Step 0 (not Step 4) keeps the model assembling content into the right shape from the start. Reference it throughout the synthesis.

### Step 0.5: Load Notion MCP tool schemas (mandatory pre-flight)

The headless `claude -p` session registers `mcp__claude_ai_Notion__*` tools as **deferred tools** - their names are known but their JSON schemas are NOT loaded into the live tool registry by default. Calling them without first loading the schemas will fail with `InputValidationError`. You MUST explicitly load the schemas via `ToolSearch` BEFORE any Notion call (Steps 2, 3, 5).

Run this `ToolSearch` call now:

```
ToolSearch query="select:mcp__claude_ai_Notion__notion-fetch,mcp__claude_ai_Notion__notion-query-data-sources,mcp__claude_ai_Notion__notion-create-pages,mcp__claude_ai_Notion__notion-update-page" max_results=5
```

**Expected result:** an array of 4 `tool_reference` entries naming each tool. After this returns successfully, the four tools become callable for the remainder of the session.

**Retry-once-on-empty:** if the result is `No matching deferred tools found` or an array with fewer than 4 tool_reference entries, the Notion MCP failed to register its tools (likely a transient claude.ai MCP startup race or auth refresh). Do NOT proceed and do NOT use `Agent` to work around it (subagents cannot access claude.ai-hosted MCPs). Make exactly ONE more `ToolSearch` call with the same `select:` query. If the retry also returns empty or partial, STOP the run with this error to the user:

> Notion MCP tools failed to register in the deferred-tools registry after one retry. The headless `claude -p` session cannot read digests from Notion this run. Verify Notion connectivity with `claude mcp list` and check the user's claude.ai OAuth status. The cron run is aborting - no dry-run will be written.

Exit with a non-zero result. The cron / launchd job will see the failure. **Do NOT auto-fallback to writing a dry-run file** - that masks the real failure and breaks the cron contract.

If `$DRY_RUN` IS explicitly set by the user (via `--dry-run` flag) AND the Notion calls below are skippable for a dry-run scenario, you may continue without Notion tools - but only if `$DRY_RUN` was user-requested, never as a fallback.

### Step 1: Compute the month (or custom range) window

Run the helper, passing whichever args you parsed in Step 0:

```bash
# No arg - last full calendar month:
eval "$(bash ~/.claude/skills/team-monthly/lib/compute-month-window.sh)"

# Positional YYYY-MM or YYYY-MM-DD - the calendar month containing it:
eval "$(bash ~/.claude/skills/team-monthly/lib/compute-month-window.sh "$DATE_ARG")"

# --from/--to - arbitrary range, inclusive:
eval "$(bash ~/.claude/skills/team-monthly/lib/compute-month-window.sh --from "$FROM" --to "$TO")"
```

After `eval`, `$MONTH_START`, `$MONTH_END`, `$MONTH_LABEL`, `$MONTH_NAME`, `$START`, `$END` are set. For calendar-month mode, `$MONTH_LABEL` is e.g. `2026-05` and `$MONTH_NAME` is e.g. `May 2026`; for custom-range mode, `$MONTH_LABEL` is `<from>_to_<to>`. `$MONTH_NAME` is single-quoted in the helper output (it contains a space), so `eval` handles it correctly.

If the helper exits non-zero (invalid month/date format, --from after --to, mixing positional with --from/--to), surface its stderr to the user and stop.

### Step 2: Query the database for the whole month (the free skeleton)

Fetch `data_source_id` from the database with `notion-fetch` on `database_id` (extract the `data-source-url` / `collection://...` from the response - same pattern as the weekly). Then make ONE `notion-query-data-sources` call against that data source:

- **Filter (overlap, not exact date):** `date:Date:start <= $MONTH_END`. **Do NOT filter by `Digest Type`** - we want every daily/range scan AND every weekly that overlaps the month in one query.
- **Sort:** `date:Date:start` ascending.
- **Paginate.** A 31-day month can exceed one page. If the response has `has_more: true`, repeat the query with the returned `start_cursor` until `has_more` is false. Accumulate all results.
- **Then keep only pages overlapping the month, IN CONTEXT:** a page overlaps when `coalesce(date:Date:end, date:Date:start) >= $MONTH_START`. Weeklies (and range Combined pages) now carry `start..end`, so a week straddling the month boundary is still caught; single-day dailies have a null end and use their start.

Partition the surviving results by the `Digest Type` property:

- `Weekly` rows → the **spine** (fetch bodies in Step 3a).
- `Combined` rows → the **daily skeleton**. Keep their properties (`date`, `Repos Active`, `Keywords Matched`, `url`) - they feed "By the Numbers" and the deep-fetch ranking. Do NOT fetch their bodies yet.
- Exclude any row whose title starts with `Team Monthly Digest` (our own prior output).

Record `$N_WEEKLIES` (weekly rows) and `$N_DAILIES` (daily rows) for the header and footer.

If zero results: abort with `No daily/weekly digests found for ${MONTH_NAME} (${MONTH_START} to ${MONTH_END}). Generate them first via /team-digest and /team-weekly.`

The skeleton alone gives you: dailies present + gaps, the repos-active trend, the keyword union + frequency, and which weeks have weeklies. This is nearly free (no body fetches) and is the backbone of the "By the Numbers" section.

### Step 2.5: Coverage-completeness gate (mandatory)

The monthly must not be built on a month whose weeklies are incomplete. Run two authoritative coverage checks against the kept pages from Step 2 (range-aware: a single multi-week Weekly page covers all its weeks; a range Combined page covers all its days). Both use the shared helper:

**Check A - weekly spine covers every full in-month week.** Only when `HAS_FULL_WEEK=1` (from Step 1). Feed one `start [end]` line per **Weekly** row (weeklies always carry `date:Date:start` + `date:Date:end`), windowed to the weekly span:

```bash
printf '%s\n' "2026-06-01 2026-06-07" "2026-06-08 2026-06-14" "2026-06-15 2026-06-21" "2026-06-22 2026-06-28" \
  | bash ~/.claude/skills/team-digest/lib/coverage-gap.sh \
      --window-start "$WEEKLY_SPAN_START" --window-end "$WEEKLY_SPAN_END"
```

**Check B - month is fully covered by weeklies or dailies.** Feed one `start [end]` line per kept page of **either** type (Weekly AND Combined), windowed to the full month. This catches boundary days (before the first Monday / after the last Sunday) that weeklies do not cover but dailies should:

```bash
printf '%s\n' "2026-06-01 2026-06-28" "2026-06-29" "2026-06-30" \
  | bash ~/.claude/skills/team-digest/lib/coverage-gap.sh \
      --window-start "$MONTH_START" --window-end "$MONTH_END"
```

`eval` each helper's output. The month passes only if **both** checks report `MISSING_COUNT=0` (Check A is vacuously satisfied when `HAS_FULL_WEEK=0`). If either reports gaps:

- **If `$DRY_RUN` is set, OR `$ALLOW_PARTIAL` is set (from `--allow-partial` flag), OR `TEAM_DIGEST_ALLOW_PARTIAL=1` in the run env:** proceed with a partial monthly. Note the missing weeks/days in the Week-by-Week Index so the gap is visible.
- **Otherwise (a normal scheduled/real run): ABORT before fetching any bodies or writing.** Print exactly this sentinel line so the headless wrapper logs a clean skip rather than a failure (use Check A's missing dates for a week gap, Check B's for a day gap; combine if both):

  ```
  [coverage] INCOMPLETE - month ${MONTH_NAME} missing coverage: <missing dates>. Skipping monthly synthesis - no page written.
  ```

  Then add one guidance line: `Generate the missing weekly/daily windows via /team-weekly and /team-digest and re-run, or pass --allow-partial to synthesize from available pages.` STOP the run here - do NOT run Step 3 fetches, synthesize, write a safety file, or call Notion. Exit cleanly (this is an intentional skip, not an error).

### Step 3: Fetch the spine, then selectively deep-read dailies

**Step 3a - Weekly bodies (the spine).** For each `Weekly` row from Step 2, call `notion-fetch` on its `url`. **Parallelize** - emit all calls in one message. These bodies (their Executive Summaries, Top GitHub Themes, HIP Movement, Partner Momentum, and **Threads to Watch / Carried Over** sections) are the raw material for the storylines.

If a weekly fetch fails, log `(<WEEK_LABEL>: not accessible - <reason>)` and continue. Synthesis proceeds from the available weeklies.

**Step 3b - Selective daily deep-fetch (capped at `$MAX_DEEP`, default 8).** After reading the weeklies, choose up to `$MAX_DEEP` dailies to `notion-fetch` in full, by this rule:

1. **Pointer-driven first:** any daily a weekly storyline explicitly leans on for a fact the weekly compressed away (e.g. a weekly says "see the Tuesday design doc" - fetch that daily).
2. **Then signal-driven:** among days NOT already well-covered by a weekly body, take the highest `Repos Active` days from the skeleton until the cap is reached.
3. **Never exceed `$MAX_DEEP`.** Track `$N_DEEP` = number actually deep-fetched.

Parallelize the deep-fetches (one message). The remaining dailies stay skeleton-only; that is fine - the footer states `<N_DEEP> of <N_DAILIES> dailies read in full` so the synthesis-of-synthesis tradeoff is visible, not hidden.

### Step 4: Synthesize the monthly (storyline-first)

This is the core work. Using the weekly spine + daily skeleton + deep-fetched dailies, assemble the monthly per `TEMPLATE.md` (loaded in Step 0). **Author order** (the reader-facing order differs - The Month in Review goes first on the page but is written last):

1. **Top Storylines first** - identify 4-7 named threads. A storyline interconnects sources the lower tiers kept in separate sections: a repo cluster + a HIP arc + a partner ask + a Notion doc + a release, told as one `started → middle → landed → what's next` narrative. Draw the arcs from the weekly **Threads to Watch / Carried Over** sections, cross-week HIP status arcs, sustained GitHub themes, and multi-week partner momentum. This is the monthly's reason to exist - do not reduce it to a list of "repo X was active."
2. **By the Numbers** - mostly from the skeleton (cheap): releases table (dedup across weeklies, grouped by repo), activity trend, HIP movement summary (skip if `TEAM_DIGEST_HIP_ENABLED=0`), keyword frequency.
3. **Supporting Detail** - aggregate the weekly-style sections (Top GitHub Themes, Partner Momentum, Notion Content Pulse, Industry News Roundup, Favorites Movement). Omit any with no data. Synthesize across weeks - do not paste weekly text.
4. **Week-by-Week Index** - one linked line per weekly.
5. **The Month in Review** - write this LAST, distilled from the storylines: 3-5 paragraphs someone could read alone and understand the month.

Apply the full Plain-English / Outsider rules and Linking Rules inherited from `/team-digest` (write for someone who has never worked in this codebase; lead with the user-visible change; translate every internal name / acronym on first mention; no creative metaphors). Every entity reference (repo, PR, release, Notion page, HIP) is a markdown link. The footer MUST include `<N_DEEP> of <N_DAILIES> dailies read in full`.

### Step 4.5: Pre-Write Link Audit (mandatory)

Before writing to Notion, scan the assembled monthly content one final time. Verify:

1. **Every repo, PR, issue, release, and HIP reference is a markdown link.** Bare entity references are unacceptable - same rules as `/team-digest`.
2. **Every Notion page reference is a markdown link** using a URL from an MCP response (the weekly-page `url` from the Step 2 query results, or a page URL that appeared inside a fetched weekly/daily body). Never construct a Notion URL from a page title.
3. **No `\n` inside Mermaid labels.** The monthly rarely renders its own diagrams (it references the dailies'/weeklies'), but if it does, keep all node labels on a single line.
4. **First-mention expansions are present.** When the synthesis names a project, component, or acronym for the first time, follow it with a 3-7 word plain-English expansion, sourced from the team profile's Project Glossary if present.
5. **Storyline coherence.** Each Top Storyline actually interconnects more than one source type (not just one repo). If a "storyline" is really single-source, demote it to Supporting Detail.
6. **Callout single-line + no bold+code collision + standard Unicode emoji** (no `:shortcode:`), per the Notion API constraints in `TEMPLATE.md`.

If any check fails, fix the draft before proceeding.

### Step 5: Write the monthly digest

**FIRST: Always write a safety backup file** before doing anything else in this step - even before the dry-run check. This ensures the assembled content is never lost to a Notion API timeout or stream error.

```bash
DRY_DIR="/tmp/team-digest-dry-runs"
mkdir -p "$DRY_DIR"
N=1
while [ -f "$DRY_DIR/team-monthly-${MONTH_LABEL}-v${N}.md" ]; do
  N=$((N + 1))
done
SAFETY_PATH="$DRY_DIR/team-monthly-${MONTH_LABEL}-v${N}.md"
# Use the Write tool to write the assembled content to $SAFETY_PATH.
```

Use the `Write` tool to write the content **in Notion-flavored Markdown** (keep all `<callout>`, `<details>`, `<table header-row>` tags exactly as they would appear in the Notion page). This is intentional: the safety file doubles as the source for `--from-file` recovery, so it must be in the same format as what `notion-create-pages` receives. It is ephemeral - cleared on reboot.

After writing, print a single line: `Safety backup: <SAFETY_PATH>` so the user knows where to find it if the Notion write fails.

**If `$DRY_RUN` is set:** also print `Dry-run output: <SAFETY_PATH>` and stop. Skip the rest of Step 5. (The safety file IS the dry-run output - same content, same path.)

**If `$DRY_RUN` is NOT set:** proceed with the SPLIT-WRITE procedure to avoid the stream-timeout failure mode that hits single-call `notion-create-pages` writes when the body grows large. A monthly synthesizes 4-5 weeklies and is materially larger than a single weekly, so the timeout risk is higher here. The split moves the heavy payload into a sentinel-driven sequence of `notion-update-page` calls so the small `notion-create-pages` call almost never fails, and a failure mid-chunk can be retried independently without losing the page.

**Step 5.1: Create the page with a PLACEHOLDER body.**

Call `notion-create-pages` with:

- **Parent:** `{ "type": "data_source_id", "data_source_id": "<data_source_id discovered in Step 2>" }`
- **Properties:**
  - `Digest Title`: `Team Monthly Digest - <MONTH_NAME>`
  - `date:Date:start`: `<MONTH_START>`
  - `date:Date:end`: `<MONTH_END>`
  - `date:Date:is_datetime`: `0`
  - `Digest Type`: `Monthly` (the page carries the full month as a `start..end` range so a future Quarterly cadence finds it by overlap)
  - `Repos Active`: total unique repos active across the month (sum-of-uniques, not sum-of-weeklies)
  - `Keywords Matched`: union of `Keywords Matched` across the month as a JSON array
  - `Partners Mentioned`: JSON array of distinct partner/company names from the month's Partner Momentum (multi-week + single-touch); empty array if none. **Include ONLY if the database schema (from the Step 2 database fetch) has a `Partners Mentioned` property; OMIT it entirely otherwise** (older installs without the column reject unknown properties).
  - `Status`: `Auto`
- **Content:** the literal one-line placeholder `<callout icon="⏳" color="gray">Monthly digest content loading...</callout>` — nothing else. This call carries the metadata payload only; the body comes later.

If THIS call fails (rare given the small payload), tell the user:
> Notion page creation failed at the metadata step. Assembled content is saved at `<SAFETY_PATH>`. Re-run with:
> `bin/team-monthly-run.sh <MONTH_OR_RANGE_ARGS> --from-file <SAFETY_PATH>`
Then STOP - do NOT silently retry or write another safety file.

**Step 5.2: Extract `page_id` from the response.**

The `notion-create-pages` response includes a `pages` array. Take the first entry's `id` field as `$NEW_PAGE_ID`. Also extract the `url` field as `$NEW_PAGE_URL` for the success message at the end.

**Step 5.3: Upload the full monthly content using CHUNKED-WRITE.**

The full monthly content (typically 30-60 KB - larger than the weekly because it synthesizes a month) exceeds what a single `notion-update-page` call can deliver within the stream idle timeout. Write it in sections so each call stays under ~4 KB and the stream stays alive between calls via progress log lines.

**Sentinel:** the string `DIGEST-SECTION-BREAK` — appended as a standalone paragraph after each chunk, replaced by the next chunk in the next call, and removed in the final call. This sentinel matches the value the daily and weekly use; a single page is only ever bound to one digest at a time, so reusing the sentinel name is safe and keeps recovery logic identical.

**How to split:**
- Identify all `## ` heading boundaries in the assembled content (e.g. `## 📖 The Month in Review`, `## 🧵 Top Storylines`, `## 📊 By the Numbers`, `## 📚 Supporting Detail`, `## 🗓️ Week-by-Week Index`). The splitter keys on the `## ` prefix; the emoji anchor after it is part of the heading text.
- Section 0 = everything before the first `## ` (header callout + `---` separator).
- Each `## Heading\n...content...` up to the next `## ` boundary is one section.
- Merge two consecutive sections into one chunk if their combined length is under 3,000 characters.
- A single large section (e.g. `## Top Storylines` with 7 threads) may exceed 4 KB - if so, split it at `### ` storyline boundaries into multiple chunks, keeping each under ~4 KB.
- Keep the footer callout (`<callout ...>` at the very end) as its own final section.

**Write loop (N = total chunks after merging):**

1. Print `[write 1/N]`. Call `notion-update-page`:
   - `page_id`: `$NEW_PAGE_ID`
   - `command`: `"replace_content"`
   - `new_str`: `[chunk 1 content]\n\nDIGEST-SECTION-BREAK`
   - `properties`: `{}`, `content_updates`: `[]`

2. For chunks 2 through N-1: print `[write i/N]`. Call `notion-update-page`:
   - `page_id`: `$NEW_PAGE_ID`
   - `command`: `"update_content"`
   - `properties`: `{}`
   - `content_updates`: `[{ "old_str": "DIGEST-SECTION-BREAK", "new_str": "[chunk i content]\n\nDIGEST-SECTION-BREAK" }]`

3. Final chunk N: print `[write N/N]`. Call `notion-update-page`:
   - `page_id`: `$NEW_PAGE_ID`
   - `command`: `"update_content"`
   - `properties`: `{}`
   - `content_updates`: `[{ "old_str": "\n\nDIGEST-SECTION-BREAK", "new_str": "\n\n[chunk N content]" }]`

**Step 5.4: If any chunk call fails** (timeout, API error, anything non-2xx): the page exists at `$NEW_PAGE_URL` with partial content (all chunks up to the last successful one, plus the sentinel if the write was interrupted mid-loop). Tell the user:

> Page created but content upload was interrupted. The page exists at `$NEW_PAGE_URL`. Re-run with:
> `bin/team-monthly-run.sh <MONTH_OR_RANGE_ARGS> --from-file <SAFETY_PATH>`
> The `--from-file` path detects the `DIGEST-SECTION-BREAK` sentinel and restarts the chunked write from the beginning.

Then STOP. Do NOT silently retry; do NOT write another safety file.

**Step 5.5: On full success, print the Notion page URL.**

Print `Notion page: $NEW_PAGE_URL` so the user (or the cron log) has the link to the new monthly digest.

**Content** uses Notion-flavored Markdown. The same Notion API rules apply as in `/team-digest` and `/team-weekly` Step 5:

- Emoji must be standard Unicode characters (🗓️, 📈, ℹ️, 📊) - NEVER `:shortcode:` form. Notion's API rejects shortcodes with `validation_error: Custom emoji ":xxx:" not found in this workspace`.
- Do NOT bold inline code (the bold and code spans collide and render as `****` artifacts). Use `**[name](url)**` or `**name**`.
- The auto-generated footer is the LAST block. Do NOT replace it with a "Known limitations" / "Caveats" meta-section; section-level inline notes belong inside their section.
- Do NOT invent closing meta-sections about run hygiene. If a weekly fetch failed, note it inline in the Week-by-Week Index, not as a closing callout.

**Structure enforcement check.** Before writing the safety file, scan the assembled draft: the header callout MUST be `<callout icon="🗓️" color="purple_bg">**Team Monthly Digest** | ...</callout>` (not "SA Monthly Digest", not a team-specific name, not a callout missing the `**Team Monthly Digest**` prefix). The five top-level sections (`## 📖 The Month in Review`, `## 🧵 Top Storylines`, `## 📊 By the Numbers`, `## 📚 Supporting Detail`, `## 🗓️ Week-by-Week Index` — each carries its emoji anchor) must all be present, in that order, with the footer callout last. If wrong, fix the draft before writing.

**Output format contract:** `TEMPLATE.md` was already loaded at Step 0 - it is the canonical output contract. Substitute all `<PLACEHOLDER>` values with actual data, in the order the template specifies. The "FORMAT RULES" section at the bottom is a human reference only - do not render it in the Notion page. If TEMPLATE.md is not in context (e.g., context was compacted), re-read it now before assembling.

## Style Rules

The same Style Rules from `/team-digest` and `/team-weekly` apply here. Specifically:

- **Synthesize, don't copy.** Re-summarizing weekly content is a waste; the point of the monthly is the month-spanning storylines you cannot get from any one weekly.
- **Storyline-first.** The Top Storylines section is the monthly's reason to exist - interconnect sources (repos + HIPs + partners + Notion docs + releases) the lower tiers kept separate. A "storyline" that names only one repo is not a storyline; demote it.
- **Linking is mandatory.** Every entity reference (repo, PR, release, Notion page, HIP) is a markdown link. See `/team-digest`'s Linking Rules for the full table.
- **Write for an outsider.** A reader of the monthly may never have read a daily or weekly. Apply `/team-digest`'s full Plain-English Description Rules: write for someone who has never worked in this codebase, lead with the user-visible change, translate every internal name / acronym on first mention, avoid creative metaphors and sprint slang. Apply the Outsider Test paragraph-by-paragraph.
- **Short paragraphs, scannable structure.** Two to three sentences per paragraph maximum in the catalog sections. The Month in Review and Top Storylines are allowed longer narrative paragraphs because coherence is their job - but keep sentences plain.
- **Callout blocks must be single-line.** Write `<callout icon="..." color="...">content</callout>` all on one line. Never put a newline after the opening tag; never put `</callout>` on its own line.
- **Failure mode: partial digest, not no digest.** If one weekly fetch fails, synthesize from the rest and note the gap in the Week-by-Week Index. If one section has no data, omit it.

## Configuration

This skill reads from `~/.config/team-digest/config.json` under the `team-digest` key (NOT a separate `team-monthly` key). The shared config plus the monthly-specific block:

- `notion.database_id` - the same database the dailies and weeklies were written to
- `monthly.max_daily_deep_fetch` - cap on full daily-body fetches in Step 3b (default 8)
- `monthly.boundary` - month boundary convention (`calendar`); weeklies are included by stored Sunday date, month-edge days covered via dailies
- `defaults.keywords` / `github.orgs` - surfaced via the `Keywords Matched` / `Repos Active` properties on the daily/weekly pages

The team profile at `~/.config/team-digest/profiles/team-digest.md` is shared too, including its **Project Glossary** for jargon expansion.

## Running headlessly (terminal / cron / launchd)

`bin/team-monthly-run.sh` in the team-digest repo is the headless entry point. Same allow-listed Notion MCP tools as `bin/team-weekly-run.sh`, same env-var overrides for log paths and model. It defaults to **Opus** (monthly synthesis is reasoning-heavy and runs once a month, so the cost is negligible); override with `TEAM_DIGEST_MODEL`.

```bash
bin/team-monthly-run.sh                          # last full calendar month
bin/team-monthly-run.sh 2026-05                  # a specific calendar month
bin/team-monthly-run.sh --dry-run                # write to /tmp/team-digest-dry-runs/, skip Notion
bin/team-monthly-run.sh 2026-05 --dry-run        # both
```

For automation: schedule `bin/team-monthly-run.sh` on the 1st of each month, AFTER that day's `/team-digest` and the prior week's `/team-weekly` have had a chance to run. The Step 2.5 coverage gate is authoritative: it requires a Weekly digest for every full in-month week (boundary days at the month edges are covered by dailies), and aborts cleanly (logged as `[gate] SKIP`) without writing a partial monthly if anything is missing. Coverage is measured from page date-ranges, so a single multi-week page satisfies its span. To synthesize from whatever pages exist (e.g. for past months where some weeks were never digested), pass `--allow-partial` to the bin script or the skill, or set `TEAM_DIGEST_ALLOW_PARTIAL=1` in the run env.
