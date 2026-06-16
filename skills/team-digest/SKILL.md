---
name: team-digest
description: Team Daily Digest - scans GitHub activity, Notion keywords, and partner conversations over a single day or an explicit multi-day range, writes a combined digest to Notion. Usage - /team-digest [YYYY-MM-DD | START..END | --from F --to T | --days N | --dry-run | --from-file <path> | setup | config]
user-invocable: true
---

# Team Daily Digest - Manual Trigger

## Purpose

Manually run the Team Daily Digest pipeline on demand. Scans a specific day's activity (00:00-23:59 UTC) across three data sources and writes a structured summary to the Team Daily Digest Notion database.

**Usage:**
- `/team-digest` - digest for the previous calendar day (default)
- `/team-digest 2026-04-20` - digest for a specific date
- `/team-digest --dry-run` - run the full pipeline but write the markdown to a local file instead of creating the Notion page (safe for refactor validation - does not overwrite an existing daily digest)
- `/team-digest 2026-04-20 --dry-run` - both date and dry-run
- `/team-digest --from-file /tmp/team-digest-dry-runs/team-digest-2026-05-15-v1.md` - upload a previously saved safety file to Notion, skipping the full data-gather pipeline (token-efficient recovery after a timeout)
- `/team-digest 2026-05-15 --from-file /path/to/file.md` - same, with explicit date override
- `/team-digest setup` - first-time setup or update your Notion IDs
- `/team-digest config` - show current config (Notion IDs, orgs, keywords)

The flags `--dry-run`, `--from-file`, and date arg can appear in any order. The dry-run / safety-backup output goes to `/tmp/team-digest-dry-runs/team-digest-<DATE_LABEL>-v<N>.md`, versioned so repeated runs do not clobber each other. These files are ephemeral - cleared on reboot. If you need to keep one, copy it elsewhere.

Use this when:
- Testing the digest before enabling automation
- Re-running after a failed automated run (use `--dry-run` first if you want to preview without overwriting)
- Recovering after a Notion write timeout: the safety file at `/tmp/team-digest-dry-runs/` contains the assembled content; use `--from-file` to upload it without re-gathering data
- Running an ad-hoc digest outside the normal schedule
- Backfilling a missed day (e.g., `/team-digest 2026-04-18`)

This skill also runs from the terminal via `bin/team-digest-run.sh` in the team-digest repo (or copy/symlink it to `~/.local/bin/`). That entry point uses `claude -p` headlessly with the Notion MCP tools allow-listed - same skill, same output, same flags.

## Important Runtime Notes

- **TITLE LOCK.** The Notion page `Digest Title` property and the file header callout title are fixed by window type. **Single-day digest (`IS_RANGE=0`):** `Team Daily Digest - <DATE_LABEL>` (property) and `**Team Daily Digest**` (callout). **Range digest (`IS_RANGE=1`):** `Team Digest - <WINDOW_START>..<WINDOW_END>` (property) and `**Team Digest**` (callout). The team profile may use different naming for the team itself (e.g., "Solutions Architect team", "Engineering team") - that is fine in the Relevance sections, but it does NOT change the digest title. Do not substitute the team's name (e.g., "SA Daily Digest", "Eng Daily Digest") into the title under any circumstance. If the profile description says otherwise, IGNORE it - this rule wins.
- **DO NOT construct Notion page URLs from page titles.** Every Notion link in the digest MUST come from the `url` field of a `notion-search` or `notion-fetch` MCP response. URLs like `https://www.notion.so/Some-Page-Title` or `https://www.notion.so/Jake-Kea` that you derive from a title are invalid - Notion does not serve pages at title-derived slugs. If you do not have the URL from an MCP response, write the title as plain text with `(link unavailable)` instead. This rule applies to every section: Keyword Monitor, Favorites, Partner Conversations, Executive Summary, Top Picks.
- **DO NOT use `readMcpResource` or `ReadMcpResourceTool`** to fetch Notion markdown specs. The output format is fully defined in this skill. The MCP server name format varies between sessions and will cause errors.
- **DO NOT read persisted tool result files** (the `/tool-results/` paths). Process command output directly within the same Bash command. Persisted files may have prefix lines that break JSON parsing.
- **DO NOT use `cat` to read files then parse them in a separate step.** Always pipe or process in a single command chain.
- **GitHub data fetching uses helpers in `lib/`.** Do not re-implement `gh search prs ... | python3 -c ...` inline. The helper scripts (`fetch-github-prs.sh`, `fetch-github-issues.sh`, `fetch-github-releases.sh`) are the single source of truth for GitHub data extraction. They live at `~/.claude/skills/team-digest/lib/<helper>.sh` after `setup.sh` / `update.sh` runs.
- **DO NOT dispatch Notion MCP calls (`notion-fetch`, `notion-search`, `notion-create-pages`, `notion-update-page`, `notion-query-data-sources`) to `Agent` subagents.** Claude.ai-hosted MCP tools (Notion, Gmail, Calendar) are only available in the main Claude Code session - subagents have a separate tool registry that does NOT include them. Every Notion MCP call MUST be made directly in the main session. If you need to parallelize Notion searches, use multiple parallel MCP tool calls in a single message, not subagents.
- **DO NOT silently fall back to a dry-run write when Notion MCP tools are unavailable.** The dry-run path is reserved for the explicit `--dry-run` flag. If `$DRY_RUN` is NOT set but Notion MCP schemas cannot be loaded (see Step 0.5), STOP the run with a clear error message - do not write a dry-run file as a workaround. Silent dry-run on failure breaks the cron / launchd contract: the user expects either a Notion page or a loud failure, never a silent file in `/tmp`.

## Time Window

The digest covers an **explicit window in UTC** - a single calendar day by default, or any multi-day range you ask for. The window is always an explicit input; there is no hidden backfill.

**Forms:**
- `/team-digest` - the previous calendar day (single day)
- `/team-digest 2026-04-20` - that single day
- `/team-digest 2026-06-08..2026-06-14` - an inclusive range
- `/team-digest --from 2026-06-08 --to 2026-06-14` - an inclusive range (parity with /team-weekly)
- `/team-digest --days 3` - the last 3 days, ending yesterday

A single-day digest reports only that day. A range digest scans every source (GitHub, Notion, HIP, RSS) over the whole window and produces ONE page covering it - the token-efficient way to cover a week without running seven dailies.

This ensures:
- Manual runs at any time of day produce the same result for the same window
- Automated runs and manual re-runs are consistent
- No activity is missed or double-counted within a window
- Missed days are covered by specifying the date or range

Compute the window using the `compute-window.sh` helper. Pass through the window tokens only - a positional `YYYY-MM-DD`, an `A..B` range, `--from F --to T`, or `--days N` (skill-level flags `--dry-run`, `--from-file`, `setup`, `config` are stripped during argument parsing below). The helper validates input and emits `KEY=VALUE` lines you `eval` into your shell. Also export `TEAM_DIGEST_MATCHES_DIR` so helpers write structured match-record sidecars used by the consolidation step:

```bash
# WINDOW_ARGS = the window tokens only (unquoted so "--from X --to Y" word-splits).
eval "$(bash ~/.claude/skills/team-digest/lib/compute-window.sh $WINDOW_ARGS)"
# Now $WINDOW_START $WINDOW_END $WINDOW_LABEL $IS_RANGE $START $END $DATE_LABEL are set.
# $DATE_LABEL == $WINDOW_START (single-day back-compat alias).

# Matches sidecar dir - helpers write structured Mech A / Mech B / S2 / S3
# records here. When invoked via bin/team-digest-run.sh, the wrapper already
# exported TEAM_DIGEST_MATCHES_DIR; just use it. For interactive runs (no
# wrapper), create one ourselves so helpers still have a destination.
#
# **DO NOT re-export TEAM_DIGEST_MATCHES_DIR to a different value in
# subsequent Bash tool calls.** The wrapper may have set it to one path
# (e.g. `/tmp/team-digest-matches-<wrapper-PID>`); if you re-export to a
# different path in later Bash calls, sidecars end up split across two dirs
# and the wrapper's post-run consolidator can only see one. Just use the
# value the env var currently holds. Inheritance across Bash subshells works
# for vars exported by the parent process.
if [ -z "${TEAM_DIGEST_MATCHES_DIR:-}" ]; then
  export TEAM_DIGEST_MATCHES_DIR="/tmp/team-digest-matches-${DATE_LABEL}"
fi
mkdir -p "$TEAM_DIGEST_MATCHES_DIR"
```

If the user did not pass a window arg, the helper defaults to yesterday in UTC (single day). If the helper exits non-zero (invalid date format, end-before-start, bad `--days`, or mixed window modes), surface its stderr to the user and stop.

**Window contract for downstream callers:**

- **PRs + issues** scan: pass `$START $END` to `fetch-github-prs.sh` and `fetch-github-issues.sh`. The window is the whole digest window - one day, or the full range.
- **Releases** scan: pass `$START $END`. With an explicit window there is no stale-release resurfacing - releases inside the window are exactly what is wanted.
- **Notion keyword / partner / favorites search**: pass `$WINDOW_START` as `start_date` and `$WINDOW_END` as `end_date`. All sources share one window - this fixes the prior asymmetry where GitHub could span days while Notion stayed single-day.
- **HIP Activity (Step 2.3)**: Mechanism B's per-HIP search uses `--since-iso "$START"` (the window start).

The header callout's `Data window` field reflects `$WINDOW_START` for a single day, or `$WINDOW_START .. $WINDOW_END` for a range. There is no separate lookback notice.

### Backfill Limitations

When running for a past date, be aware of source-specific behavior:

| Source | Backfill Support | Notes |
|--------|-----------------|-------|
| GitHub PRs/Issues | Full | `gh search --updated` works for any past date |
| GitHub Releases | Full | Release `published_at` is compared against `$START` |
| Notion Keywords | Partial | `created_date_range` only matches pages **created** within the window; pages that existed before but were **edited** in the window will be missed. This is a Notion MCP search limitation. |
| Notion Partners | Partial | Same limitation as keywords - only newly created meeting notes are found |

For backfill or past-window runs, include a note in the digest footer indicating that Notion sections may be incomplete for past dates.

## Process

### Step 0: Argument parsing, subcommands, config load

#### Argument parsing

The skill argument is a single string after `/team-digest`. Parse it as zero or more of:

- **Window tokens** → collected into `$WINDOW_ARGS` and passed through to `compute-window.sh` (see Time Window): a `YYYY-MM-DD` date, an `A..B` range, `--from F --to T`, or `--days N`.
- The literal `--dry-run` → set `$DRY_RUN=1`
- `--from-file <path>` → set `$FROM_FILE` to the path token that follows the flag; this activates upload-only mode (see subcommand below)
- The literal `setup` or `config` → handle as a subcommand (below)

Order does not matter: `/team-digest 2026-05-04 --dry-run` and `/team-digest --dry-run 2026-05-04` are equivalent. The window forms are mutually exclusive with each other (the helper enforces this). Anything else is an error.

`--from-file` and `--dry-run` are mutually exclusive; if both are present, stop with an error.

#### Subcommand: `--from-file <path>` (upload-only mode)

When `$FROM_FILE` is set, skip the full data-gather pipeline (Steps 1-4) and jump directly to the Notion write. This is the token-efficient recovery path for when a previous run assembled the content but the Notion write timed out.

Flow:
1. Load config (Step 0 Load Config below) - still needed for `database_id` and `data_source_id`.
2. Load Notion MCP schemas (Step 0.5) - required to call `notion-create-pages` and `notion-update-page`.
3. Fetch `data_source_id` from the database (the deferred part of Step 0).
4. Read `$FROM_FILE` using the Read tool. The file contains Notion-flavored markdown assembled by a previous run.
5. Extract `$DATE_LABEL` from the filename if no `$DATE_ARG` was provided. Safety file names follow the pattern `team-digest-YYYY-MM-DD-vN.md`; extract the `YYYY-MM-DD` portion. If extraction fails and no `$DATE_ARG` was given, stop with an error asking the user to pass the date explicitly.
6. Check whether a digest page already exists for that window (search for the locked Digest Title — see TITLE LOCK: `Team Daily Digest - <DATE_LABEL>` for a single day, or `Team Digest - <WINDOW_START>..<WINDOW_END>` for a range). Three cases:
   - **No existing page found:** fall through to step 7 (create + chunked write).
   - **Existing page found AND its body matches the placeholder** (`Digest content loading...` callout) OR **body contains `DIGEST-SECTION-BREAK`** (a previous chunked write was interrupted mid-way): SKIP create, jump to step 8 with `$NEW_PAGE_ID` set to the existing page's id.
   - **Existing page found AND its body has real content (no placeholder, no sentinel):** STOP with a duplicate-protection warning. Do not overwrite. Tell the user the date already has a digest and the file is preserved at `$FROM_FILE`.
7. Call `notion-create-pages` with the placeholder body (`<callout icon="⏳" color="gray">Digest content loading...</callout>`) and standard properties (`Digest Title`, `date:Date:start`, `Digest Type: Combined`, `Status: Auto`). For `Repos Active` and `Keywords Matched` (and `Partners Mentioned`, if the database has that column), use zero / empty-array defaults (the file header callout contains the actual counts inline). Capture `$NEW_PAGE_ID` and `$NEW_PAGE_URL` from the response. If this call fails, tell the user the source file is still at `$FROM_FILE` and they can retry.
8. Upload the file content using the **CHUNKED-WRITE PROCEDURE** defined in Step 5.3 (using `$NEW_PAGE_ID`, `$NEW_PAGE_URL`, and `$FROM_FILE` as the source). The chunked write always starts with `replace_content` for chunk 1, so it safely overwrites any partial content or placeholder already on the page.
9. On success, print the Notion page URL. Do NOT write another safety file (the source file already exists).
10. On step 8 failure mid-chunk, tell the user the page exists at `$NEW_PAGE_URL` with partial content, the source file is still at `$FROM_FILE`, and they can re-run `--from-file` — the step 6 check will detect the `DIGEST-SECTION-BREAK` sentinel and route back to step 8 for a clean restart.

#### Subcommand: `setup`

If the argument is `setup`, run the interactive setup flow (see below) regardless of whether a config already exists. This lets users update their Notion IDs at any time. After writing the config, confirm success and stop (do not run the digest).

#### Subcommand: `config`

If the argument is `config`, read `~/.config/team-digest/config.json` and display the current `team-digest` configuration in a readable format: Notion IDs (masked to last 8 chars for brevity), GitHub orgs, priority repos, and default keywords. Then stop.

#### Load Config

Run the helper:

```bash
bash ~/.claude/skills/team-digest/lib/load-config.sh team-digest
```

It reads `~/.config/team-digest/config.json`, validates that the `team-digest` key and required Notion IDs exist, and prints the digest's config object as JSON on stdout. On failure (file missing, key missing, empty IDs) it exits non-zero with a clear message on stderr.

Also refresh the known-HIPs index (at most once per week per machine; used by `lib/extract-hip-refs.sh` to filter false-positive HIP regex matches):

```bash
bash ~/.claude/skills/team-digest/lib/refresh-hip-index.sh || true
```

The `|| true` ensures a hard failure (no existing index AND API call fails) does not abort the digest — Mechanism A degrades gracefully to "no filter" when the index is missing.

Export the HIP feature flag (consumed by `fetch-github-prs.sh` / `fetch-github-issues.sh` / future HIP helpers). Reads `hip_tracking.enabled` from config; defaults to enabled if the block is absent:

```bash
HIP_ENABLED=$(bash ~/.claude/skills/team-digest/lib/load-config.sh team-digest | python3 -c "import json,sys; d=json.load(sys.stdin); print('1' if d.get('hip_tracking',{}).get('enabled',True) else '0')")
export TEAM_DIGEST_HIP_ENABLED="$HIP_ENABLED"
```

The env var controls whether HIP-related machinery runs. Defaults to true if `hip_tracking.enabled` is absent or true; false only if explicitly set to false in config.

Also export the context-cascade flag (consumed by Step 1.5 below). Defaults to enabled if the `cascade` block is absent:

```bash
CASCADE_ENABLED=$(bash ~/.claude/skills/team-digest/lib/load-config.sh team-digest | python3 -c "import json,sys; d=json.load(sys.stdin); print('1' if d.get('cascade',{}).get('enabled',True) else '0')")
export TEAM_DIGEST_CASCADE_ENABLED="$CASCADE_ENABLED"
```

**If the helper succeeds (config file exists with non-empty Notion IDs) AND the argument is `setup`:** this is a re-run on an already-configured machine. Detect-and-verify the existing Notion pages before assuming the config is healthy:

1. Load the Notion MCP tool schemas via Step 0.5 (the existing ToolSearch call). This is required to call `notion-fetch`.
2. Call `notion-fetch` on the `config_page_id` AND `database_id` from config, in parallel (one message with two tool calls).
3. Branch on the results:

   **Both fetches succeed:** the existing setup is healthy. Print:
   > Already configured.
   > - Config page: `<title from fetch response>` (<URL>)
   > - Database:    `<title from fetch response>` (<URL>)
   >
   > To re-bootstrap (creates new Notion pages, overwrites config.json), delete `~/.config/team-digest/config.json` first.
   > To view the current config without changes, run `/team-digest config`.

   Then STOP. Do not re-prompt; do not modify any files.

   **Either fetch fails** (404, permission denied, deleted page, transient network error): the config points to inaccessible pages. Print a 3-way prompt:
   > Existing config points to inaccessible Notion pages.
   > - config_page_id: `<last 8 chars>` → `<success or error summary>`
   > - database_id:    `<last 8 chars>` → `<success or error summary>`
   >
   > What would you like to do?
   > [1] re-bootstrap — create new Notion pages and overwrite the config file
   > [2] provide replacement IDs manually
   > [3] cancel
   >
   > Enter 1, 2, or 3:

   - On `1`: fall through to the Bootstrap Flow subsection below. Before creating new pages, print: "About to overwrite `~/.config/team-digest/config.json` and orphan the old Notion pages (if they still exist). Type 'yes' to confirm:" and require the literal string `yes`. Any other input → STOP.
   - On `2`: jump to the existing prompt-for-IDs flow further below ("ask for the Notion config page ID", "ask for the Notion database ID"). Replace the old IDs in `config.json` with the new values.
   - On `3` or any other input: STOP.

This detect-and-verify branch is only reached when the argument is `setup`. A normal digest run (`/team-digest` without `setup`) hitting unreachable pages surfaces the error in the relevant step (e.g., Step 1's config-page fetch) and aborts; it does not trigger this recovery prompt — recovery is opt-in via `setup`.

**If the helper exits with status 1 (config file missing) and this is an interactive local run:** trigger the first-time setup flow automatically:

1. Tell the user this is first-time setup for the Team Daily Digest
2. **Existing-vs-new prompt.** Ask: "Do you already have Notion pages set up for team-digest, or should I create them for you? Enter `existing` or `new`:"
   - On `existing`: continue with the prompt-for-IDs flow below (steps 3-10 of this list).
   - On `new`: jump to the **Bootstrap Flow** subsection below.
   - On any other input: re-prompt once. Two invalid inputs → STOP.
3. Explain they need two Notion IDs - both are the 32-char hex string from Notion page URLs (`notion.so/<this-id>`)
4. Ask for the **Notion config page ID** (the page with keywords and partner patterns)
5. Ask for the **Notion database ID** (the database where digest pages are written)
6. Create the directory `~/.config/team-digest/` if it doesn't exist
7. Write `~/.config/team-digest/config.json` with this structure:

```json
{
  "team-digest": {
    "notion": {
      "config_page_id": "<user-provided>",
      "database_id": "<user-provided>"
    },
    "github": {
      "orgs": [
        {
          "name": "your-org",
          "priority_repos": [],
          "scan_all": true
        }
      ]
    },
    "defaults": {
      "keywords": [
        "your-keyword-1", "your-keyword-2"
      ],
      "partner_patterns": [
        "Meeting with", "Call with", "Catch up with", "Deep dive",
        "Sync with", "Check-in with", "Follow up with", "Debrief"
      ]
    }
  }
}
```

8. If the config file already exists with other digest keys, merge the new `team-digest` key into the existing file rather than overwriting it.
9. Confirm the config was created and tell the user they can now run `/team-digest` to produce their first digest.
10. **Stop here** (do not continue to the digest pipeline on first-time setup).

#### Bootstrap Flow (reached from existing-vs-new `new` choice, or from Branch A `[1] re-bootstrap` choice above)

This flow creates the Notion artifacts the team-digest pipeline requires: a parent page, a config page (with starter defaults), a database (with the 6-property schema), a local profile file, and writes `config.json`. All Notion MCP calls happen in the main Claude Code session — they cannot be dispatched to subagents.

Pre-flight: ensure Notion MCP schemas are loaded (Step 0.5's ToolSearch — if not already done, run it now).

**Step C.1: Create the workspace-level parent page.**

Call `notion-create-pages` with:
- `parent`: OMIT (workspace-level — pages land in user's Private section)
- `pages`: array with one entry:
  - `properties`: `{ "title": "Team Digest Workspace" }`
  - `icon`: `"📊"`
  - `content`: `"<callout icon=\"📊\" color=\"blue\">This is the Team Digest workspace. The Config page below holds your keywords, partner patterns, and favorites. The Entries database collects daily and weekly digest pages produced by /team-digest and /team-weekly.</callout>"`

Capture the returned `page_id` as `parent_page_id`.

**If the call fails** (MCP rejects the omit-parent case or returns any error): print the error, then prompt:
> Workspace-level page creation failed. Please paste a Notion parent page ID (32-char hex from any page URL you have access to — the new artifacts will be created as children of that page):

Validate the input is 32 hex characters (with or without dashes). Use as `parent_page_id`. Retry once on invalid input; second invalid → STOP.

**Step C.2: Create the config page as a child of the parent.**

Call `notion-create-pages` with:
- `parent`: `{ "type": "page_id", "page_id": "<parent_page_id>" }`
- `pages`: array with one entry:
  - `properties`: `{ "title": "Team Digest Config" }`
  - `icon`: `"⚙️"`
  - `content`: the markdown body below (copy verbatim):

```
<callout icon="✏️" color="yellow">These are starter defaults. Edit before your first real digest run — keywords and partner patterns drive what the daily digest surfaces.</callout>

## Keywords

- AI
- agent
- MCP
- API

## Partner Patterns

- Meeting with
- Sync with
- Call with
- Catch up with
- Discussion
- Deep dive
- Check-in with
- Follow up with
- Debrief

## Favorites

<callout icon="ℹ️" color="gray">Add Notion page URLs to monitor here, one per line. The digest scans for edits to these pages plus one level of child-page descent.</callout>
```

Capture the returned `page_id` as `config_page_id`. **If this call fails:** STOP. Print the MCP error and tell the user: "Parent page exists at <parent URL>; delete it manually before retrying."

**Step C.3: Create the database as a child of the parent.**

Call `notion-create-database` with:
- `parent`: `{ "page_id": "<parent_page_id>" }`
- `title`: `"Team Digest Entries"`
- `description`: `"Daily and weekly digest pages produced by /team-digest and /team-weekly. Schema must not be modified — the skills write specific property names."`
- `schema`: exactly this DDL string (including the double-quotes around column names):

```
CREATE TABLE ("Digest Title" TITLE, "date" DATE, "Digest Type" SELECT('Combined':blue, 'Weekly':purple, 'Monthly':orange), "Repos Active" NUMBER, "Keywords Matched" MULTI_SELECT(), "Partners Mentioned" MULTI_SELECT(), "Status" SELECT('Auto':green, 'Manual':yellow))
```

**Existing databases (no re-bootstrap):** writing a page with `Digest Type = Monthly` auto-creates the select option on first write, so no manual migration is needed when `/team-monthly` first runs against an older database. If a specific Notion workspace rejects an unknown select option, add a `Monthly` option to the database's `Digest Type` property once, by hand, then re-run `/team-monthly`. (`Combined` and `Weekly` are written by `/team-digest` and `/team-weekly`; a future `Quarterly` option is added when that cadence ships.)

The `Partners Mentioned` MULTI_SELECT column is new. Existing databases created before it was added will not have the column; the skills detect this (the Step 0 database fetch returns the schema) and simply omit the property — the page still writes, and partner detail still appears in the body. To populate the column on an older database, add a `Partners Mentioned` multi-select property to it by hand once; the next digest run fills it.

Capture the returned database `id` as `database_id`. The response also includes a `data_source_id` in a `<data-source>` tag — ignore it for config purposes (the existing skill discovers `data_source_id` at runtime by calling `notion-fetch` on `database_id` in Step 0, so storing it in config would be redundant).

**If this call fails:** STOP. Print the MCP error and tell the user: "Config page created at <config URL>; database creation failed. Delete the orphan config page and the parent page manually, then retry."

**Step C.4: Write the starter profile file (skip if exists).**

The profile may already exist (`setup.sh` copies `profiles/team-digest.template.md` to `~/.config/team-digest/profiles/team-digest.md` during repo install). Bootstrap MUST NOT overwrite an existing profile — any customizations the user made would be lost.

Check existence first; only write if missing:

```bash
PROFILE=~/.config/team-digest/profiles/team-digest.md
if [ -f "$PROFILE" ]; then
  echo "Profile already exists at $PROFILE — leaving it as-is."
else
  mkdir -p ~/.config/team-digest/profiles
  cat > "$PROFILE" <<'MARKDOWN'
# Team Profile

> Edit before your first real digest run. The profile drives "Relevance" sections throughout the daily and weekly digests.

## Role

Describe what your team does in 1-3 sentences. Example: "Solutions architects working with enterprise customers on integration design and architecture review for distributed systems."

## Priorities

What matters most to your team right now. Used to rank Top Picks and weight Executive Summary content.

- Priority 1
- Priority 2
- Priority 3

## Project Glossary

Acronyms, codenames, and jargon that need first-mention expansion in the digest. Format: `term — expansion`.

- HIP — Hedera Improvement Proposal
- MCP — Model Context Protocol

## Relevance heuristics

Custom rules for what makes activity "relevant" to your team specifically. Used to write the per-section Relevance paragraphs.

- Activity is relevant if: [your criteria]
- Activity is NOT relevant if: [your exclusions]
MARKDOWN
fi
```

**If this write fails** (permission denied, disk full): DO NOT STOP. Print:
> Notion pages created (URLs above); profile file write failed: `<error>`. Create `~/.config/team-digest/profiles/team-digest.md` manually using the template shown above.

Then continue to Step C.5.

**Step C.5: Write `config.json` preserving existing keys.**

The user's config file may already exist with other digest profile keys (e.g., a separate `<other-team>-digest` block). Merge rather than overwrite. Use Python via the Bash tool for safe JSON merge. Substitute `<CONFIG_PAGE_ID>` and `<DATABASE_ID>` with the actual values captured in Steps C.2 and C.3 before running:

```bash
mkdir -p ~/.config/team-digest
CONFIG=~/.config/team-digest/config.json
NEW_TEAM_DIGEST='{
  "notion": {
    "config_page_id": "<CONFIG_PAGE_ID>",
    "database_id": "<DATABASE_ID>"
  },
  "github": {
    "token": "",
    "orgs": [
      {
        "name": "your-org",
        "priority_repos": [],
        "scan_all": true
      }
    ]
  },
  "rss_feeds": [],
  "defaults": {
    "keywords": ["AI", "agent", "MCP", "API"],
    "partner_patterns": [
      "Meeting with", "Sync with", "Call with", "Catch up with",
      "Discussion", "Deep dive", "Check-in with", "Follow up with", "Debrief"
    ]
  }
}'

python3 - "$CONFIG" "$NEW_TEAM_DIGEST" <<'PY'
import json, os, sys
config_path, new_block_json = sys.argv[1], sys.argv[2]
new_block = json.loads(new_block_json)
if os.path.exists(config_path):
    with open(config_path) as f:
        cfg = json.load(f)
else:
    cfg = {}
cfg['team-digest'] = new_block
with open(config_path, 'w') as f:
    json.dump(cfg, f, indent=2)
PY
```

**If this write fails:** DO NOT STOP. Print:
> Notion pages created (URLs above); profile file created. `config.json` write failed: `<error>`. Paste these IDs manually into `~/.config/team-digest/config.json` under the `team-digest.notion` block:
> - config_page_id: `<id>`
> - database_id: `<id>`

Then continue to Step C.6.

**Step C.6: Print confirmation.**

Tell the user:
> Bootstrap complete.
> - Notion parent: `<parent URL>` (workspace-level pages land in your Private section — look there if you don't see it in the sidebar)
> - Config page:   `<config URL>` ← edit before first run
> - Database:      `<database URL>`
> - Profile file:  `~/.config/team-digest/profiles/team-digest.md` ← edit before first run
> - Config file:   `~/.config/team-digest/config.json`
>
> Next: run `/team-digest` (defaults to yesterday's UTC date) to produce your first digest.

**Stop here** (do not continue to the digest pipeline on first-time setup).

If the argument was `setup`, use the same flow above but pre-fill the prompts with existing values so the user can see what's currently set and only change what they need.

#### Normal Config Load (config exists)

The JSON returned by `lib/load-config.sh team-digest` contains:
- `notion.config_page_id` - the Notion configuration page ID
- `notion.database_id` - the Notion database ID for digest output
- `github.orgs` - array of GitHub organizations to scan, each with:
  - `name` - the org name (e.g., "your-org")
  - `priority_repos` - repos that get full narrative summaries (can be empty)
  - `scan_all` - whether to scan all repos in the org or only priority repos
- `defaults.*` - fallback values for keywords and partner patterns

Also read the team profile at `~/.config/team-digest/profiles/team-digest.md` using the Read tool. If the file does not exist, continue without it. The profile describes the team's role, priorities, and what makes activity relevant to them - used to write the **Relevance** sections throughout the digest, and its **Project Glossary** drives the first-mention expansion rule (see Plain-English Description Rules in the Style Rules section). If no profile is loaded, fall back to generic relevance heuristics (developer-facing APIs, breaking changes, architecture impacts, partner integration concerns) and explain jargon from your own knowledge.

**Also read `~/.claude/skills/team-digest/TEMPLATE.md` NOW** using the Read tool. This is the canonical output contract - section order, emoji section anchors, header callout format, per-org structure (`# <org>` H1 → `## 🧩 HIP Activity` → `## 📁 Priority Repos` H2 → `### [<repo>](url)` H3 with narrative summary + Relevance paragraph + optional depth toggle → `## 📂 Other Active Repos` H2 with the long-tail toggle), HIP Activity entry shapes, the optional `⚠️ Heads up` callout, plain-language rules, and Format Rules. Loading it at Step 0 (not Step 5) is intentional: the model assembles content into the right structural shape from the start, instead of writing flat output and trying to reshape it after the fact. Reference the template throughout data-gather and assembly.

The database `notion-fetch` call to discover the internal `data_source_id` is deferred to AFTER Step 0.5 below, because that call requires the Notion MCP schemas to be loaded first.

**GitHub authentication:** the skill calls `gh search` / `gh api` via the helpers in `lib/`. These commands honor whatever token `gh` has — in this order: `$GH_TOKEN` env var → `$GITHUB_TOKEN` env var → the credential `gh auth login` stored. To raise rate limits or access private repos beyond what your `gh auth login` token allows, export `GH_TOKEN=<your_PAT>` in the shell that runs the digest (or in the cron / launchd entry). Required PAT scopes: `public_repo` (or `repo` for private orgs) + `read:discussion`. The skill never reads tokens from `config.json` — env-var-only by design, to avoid storing secrets on disk.

**Known-HIPs index:** `lib/refresh-hip-index.sh` maintains a local file at `~/.config/team-digest/hip-numbers.txt` listing every HIP number that exists in `hiero-ledger/hiero-improvement-proposals/HIP/`. Refreshed at most weekly. Used by `lib/extract-hip-refs.sh` to filter out false-positive HIP regex matches like typos or version strings. If the index file is missing AND the API call fails, the false-positive filter is disabled for this run (the digest still works, just with possible noise in `Linked HIPs:` annotations).

### Step 0.5: Load Notion MCP tool schemas (mandatory pre-flight)

The headless `claude -p` session registers `mcp__claude_ai_Notion__*` tools as **deferred tools** - their names are known but their JSON schemas are NOT loaded into the live tool registry by default. Calling them without first loading the schemas will fail with `InputValidationError`. You MUST explicitly load the schemas via `ToolSearch` BEFORE any Notion call (Steps 1, 3, 3.5, 4, 5).

Run this `ToolSearch` call now:

```
ToolSearch query="select:mcp__claude_ai_Notion__notion-fetch,mcp__claude_ai_Notion__notion-search,mcp__claude_ai_Notion__notion-create-pages,mcp__claude_ai_Notion__notion-update-page,mcp__claude_ai_Notion__notion-query-data-sources" max_results=5
```

**Expected result:** an array of 5 `tool_reference` entries naming each tool. After this returns successfully, the five tools become callable for the remainder of the session.

**Retry-once-on-empty:** if the result is `No matching deferred tools found` or an array with fewer than 5 tool_reference entries, the Notion MCP failed to register its tools (likely a transient claude.ai MCP startup race or auth refresh). Do NOT proceed and do NOT use `Agent` to work around it (subagents cannot access claude.ai-hosted MCPs). Make exactly ONE more `ToolSearch` call with the same `select:` query. If the retry also returns empty or partial, STOP the run with this error to the user:

> Notion MCP tools failed to register in the deferred-tools registry after one retry. The headless `claude -p` session cannot write to Notion this run. Verify Notion connectivity with `claude mcp list` and check the user's claude.ai OAuth status. The cron run is aborting - no dry-run will be written.

Exit with a non-zero result. The cron / launchd job will see the failure and the user can investigate. **Do NOT auto-fallback to writing a dry-run file** - that masks the real failure and breaks the cron contract.

If `$DRY_RUN` IS explicitly set by the user (via `--dry-run` flag) AND every Notion call in Steps 1-4 is skippable for a dry-run scenario, you may continue without Notion tools - but only if `$DRY_RUN` was user-requested, never as a fallback.

**After Step 0.5 succeeds**, fetch the database page using `notion-fetch` with the `database_id` to discover the internal `data_source_id` (the `collection://...` URL in the response). Extract the data source URL from the `data-source-url` attribute in the response. This was the final piece of Step 0 work, deferred until after the schemas were loaded.

### Step 1: Read Notion Configuration

Using the `config_page_id` from the local config, fetch the Notion configuration page using the `notion-fetch` tool.

Extract:
- Keywords list (under the heading "Keywords")
- Partner conversation patterns (under the heading "Title Patterns")
- **Favorites list** (under the heading "Favorites" or "Favorite Pages") - a bullet list of Notion page URLs the user wants to monitor. The Notion API does not expose a user's sidebar Favorites, so this list is the user-curated equivalent: pages they care about regardless of keyword match. Each bullet is a URL like `https://www.notion.so/Page-Title-32hex` or just the 32-char hex page ID. Empty/missing section means no favorites are configured - skip Step 3.5.

GitHub org and repo configuration comes from `config.json` (the `github.orgs` array), not from the Notion config page. This keeps structural config (which orgs/repos to scan) separate from frequently-changing settings (keywords, patterns, favorites).

If the Notion config page is unreachable, fall back to the `defaults` section from the local config file. The Favorites list has no `defaults` fallback - if the config page is unreachable, skip Step 3.5 with a one-line note.

### Step 1.5: Load storyline context (cascade)

**Skip this entire step if `TEAM_DIGEST_CASCADE_ENABLED=0`.** This step gives the daily memory of the ongoing storylines so it can add background instead of presenting every change cold. It is the primary fix for "the daily reads raw."

1. Fetch `data_source_id` from the database (the same `notion-fetch` on `database_id` you already do for the write in Step 5 - if you have not done it yet, do it now). Query the data source (`notion-query-data-sources`) for the **single most-recent `Weekly` page with `date:Date:start` < `$DATE_LABEL`**: filter `Digest Type = Weekly` AND `date < $DATE_LABEL`, sort `date` descending, page_size 1.
2. Do the same for the most-recent `Monthly` page (`Digest Type = Monthly`, `date < $DATE_LABEL`, descending, page_size 1). This is a no-op until monthlies exist.
3. For each page found, `notion-fetch` it and extract **ONLY** the Executive Summary section (heading `## 🔑 Executive Summary`). For a monthly, also extract its `The Month in Review` lead (heading `## 📖 The Month in Review`). Match on the heading WORDS, ignoring any leading emoji anchor. If a page has neither, skip it.
4. Hold this as **"Ongoing Storylines"** context. **Cost control:** at most two `notion-fetch` calls; extract only those sections; never fetch other weeklies/monthlies; this context is INPUT only - it is NEVER rendered as a section in the daily.

**How the daily uses it (input-only):**
- Add a one-clause background when an item belongs to a known storyline ("part of the ongoing X migration") - see the Background-first rule in the Plain-English Description Rules. The background NAMES the thread; it does not assert a timespan the scan window does not cover (no "this week" on a single-day digest).
- Mark continuations instead of re-introducing a thread cold.
- Do NOT re-explain what the weekly/monthly already established; assume the reader can follow the arc.

If no weekly (and no monthly) exists yet, skip silently - no note, no output.

### Step 2: Scan GitHub Activity

**GitHub authentication:** Before running any `gh` command, check authentication once:

```bash
gh auth status 2>/dev/null && echo "authed" || echo "not authed"
```

- If authed: proceed normally. The terminal entry point (`bin/team-digest-run.sh`), cron, and launchd all inherit the user's local `gh` auth, so this is the expected path.
- If not authed: surface an actionable error to the user (`Run 'gh auth login' before running the digest.`) and stop. Without auth, `gh search` either refuses or hits a 60 req/hour rate limit that produces partial digests; failing fast is better than producing a half-empty digest.

Scan **each org** from `config.github.orgs` for activity during the target date by calling the helper scripts. Parallelize across orgs by emitting multiple Bash tool calls in a single message.

**For each org, invoke these three helpers in parallel:**

```bash
bash ~/.claude/skills/team-digest/lib/fetch-github-prs.sh      <org> "$START" "$END"
bash ~/.claude/skills/team-digest/lib/fetch-github-issues.sh   <org> "$START" "$END"
bash ~/.claude/skills/team-digest/lib/fetch-github-releases.sh <org> "$START" "$END"
```

All three helpers scan the same `$START..$END` window — one day for a single-day digest, the full span for a range digest. There is no separate lookback window.

For a **range** digest (`IS_RANGE=1`), add an inline `(YYYY-MM-DD)` date to an item only when the date materially aids the reader (e.g., to order a multi-day arc); default to no per-item date to keep output lean. For a **single-day** digest, never add per-item dates — everything happened that day.

Each helper writes a plain-text summary to stdout. PR and issue helpers group by repo with `## <repo> (<N>)` headers, then per-item lines with `[STATE] #<number> <title>`, author handle, URL, and a 200-char description excerpt. The releases helper emits one line per release: `<repo>: <tag> - <name> (<YYYY-MM-DD>) <html_url>`.

If a helper exits non-zero (e.g., the org is unreachable or `gh` rate-limit hit), log the failure inline in the digest as `(<org>: PR scan failed - <message>)` and continue with the next source. Do not abort the entire digest on one source failure - per the partial-digest rule.

**100-result cap:** When a helper emits a WARNING line about hitting the `--limit` cap (100 results), accept the partial data as-is and add a one-line inline note in that section: `(gh cap hit - some activity may not be shown)`. Do NOT re-invoke the helper with different filters. The cost of a retry exceeds the value of the missing tail-end items.

**Critical: do not save helper output to intermediate files. Capture stdout into the conversation context directly so the narrative-writing step can reference it.**

**Output structure - organize by org, then by priority:**

For each org in `config.github.orgs`:
- **Priority repos** (listed in `priority_repos`): Write synthesized narrative summaries - NOT bulleted PR lists. Group related PRs by theme and describe the collective work in 2-4 paragraphs. **Whenever you mention any PR, issue, release, or repo, it MUST be a markdown link** (see Linking Rules below). When summarizing a batch of related PRs, link the repo as the primary anchor AND link any individually-significant PRs you call out (breaking change, major feature, hotfix). After the narrative, add a **Relevance:** paragraph using the loaded team profile as your guide - the profile describes the team's role, what they care about, and what "relevant" means for them specifically. If no profile was loaded, fall back to: does this affect developer-facing APIs or SDKs? Does it impact partner integrations or architecture decisions? Does it affect EVM compatibility? Is there a breaking change developers should know about? Could it inform a technical design recommendation? If the activity represents an architectural change (component split/merge, service restructuring, data flow change, before/after pattern), add a Mermaid diagram after the narrative - use `graph TD` with `direction LR` subgraphs for a square layout; keep all node labels on a single line (no `\n` in labels). One diagram per repo maximum; skip if nothing structural happened.
- **Other repos** (if `scan_all` is true, or for orgs with no priority repos): Build a summary table that includes **every repo with at least one PR, issue, or release in the date window**. No silent drops, no aggregation across repos. One row per repo. The "notable activity" column is plain-English: see the Plain-English Description Rules below.
- **Orgs with no priority repos**: Show all repos in the summary table per the rule above; no narrative section.

The digest should group output under org-level headers:

```
# <org-name-1>

## Priority Repos
(narrative summaries for each priority repo with activity)

## Other Active Repos
(summary table - every repo with activity in the date window appears here)

# <org-name-2>

## Other Active Repos
(summary table - all repos with activity; no priority repos defined for this org)
```

If scanning an org fails, note the failure and continue with the next org.

### Step 2.3: Scan HIP Activity (Hedera/Hiero Improvement Proposals)

**Gated on `TEAM_DIGEST_HIP_ENABLED=1`** (set automatically by Step 0 based on `hip_tracking.enabled` in config). If set to 0, skip this entire step.

This step produces the HIP Activity section that appears under each org header in `hip_tracking.implementation_orgs` (default: `hiero-ledger`). It runs after the main GitHub scan so the cross-link stage below can cross-link with PR data already in context.

**Range mode (`IS_RANGE=1`):** the day-pinned helpers below — Stage 1 (`fetch-hip-updates.sh`), Stage 3 (`fetch-hip-release-refs.sh`), Stage 4 (`fetch-hip-timeline-correlations.sh`) — each scan a single UTC day. For a range digest, invoke each once per day across `$WINDOW_START..$WINDOW_END` (emit the per-day calls in parallel batches). Every day's sidecars accumulate in `$TEAM_DIGEST_MATCHES_DIR`; the consolidation step dedups by `(hip_id, repo, pr_number)`, so cross-day duplicates collapse automatically. Stage 2 (`fetch-hip-implementation-prs.sh`) is already windowed via `--since-iso "$START"` — call it once, not per day. For a single-day digest (`IS_RANGE=0`), call every stage once with `$DATE_LABEL` exactly as written below.

**Stage 1 — fetch HIP updates:**

```bash
bash ~/.claude/skills/team-digest/lib/fetch-hip-updates.sh "$DATE_LABEL"
```

Capture stdout as JSON. Empty array `[]` → skip the rest of Step 2.3 (no HIP Activity section in output). Non-zero exit → log inline `(HIP source: <error>)` at the HIP Activity section position and continue with the rest of the digest.

**Stage 2 — Mechanism B per-HIP implementation search (parallel, top 10 HIPs):**

Rank the HIP entries: status-changed first, then by HIP number ascending. Take the top `max_hips_with_implementation_expansion` (default 10).

For each, dispatch in parallel (emit all Bash tool calls in one message):

```bash
bash ~/.claude/skills/team-digest/lib/fetch-hip-implementation-prs.sh <hip> "$WINDOW_END" "<comma-joined implementation_orgs>" --since-iso "$START"
```

The positional `$WINDOW_END` sets the search's upper bound and `--since-iso "$START"` sets the lower bound, so the per-HIP `gh search` covers the whole digest window in one call — `[$WINDOW_START, $WINDOW_END]` (a single day when `IS_RANGE=0`).

Capture each as JSON.

**Stage 3 — Strategy 2 (release-note analysis):**

```bash
bash ~/.claude/skills/team-digest/lib/fetch-hip-release-refs.sh "$DATE_LABEL"
```

Capture stdout as a JSON array of MatchRecord entries (`{hip_id, repo, pr_number, confidence, sources: ["s2"], per_source.s2.reason: "in_tag"|"in_body", release_tag, release_url}`). Empty array `[]` → no release-note HIP signal today; continue. Non-zero exit → log inline `(Strategy 2: <error>)` and continue with the rest of HIP Activity (do NOT abort the digest on a single-strategy failure).

**Stage 4 — Strategy 3 (timeline correlation):**

```bash
bash ~/.claude/skills/team-digest/lib/fetch-hip-timeline-correlations.sh "$DATE_LABEL"
```

Capture stdout as a JSON array of MatchRecord entries (`{hip_id, repo, pr_number, confidence, sources: ["s3"], per_source.s3.reason: <keyword_overlap_3plus | keyword_overlap_1or2_plus_category_tiebreak | high-volume area (downgraded)>, matched_keywords, category_tiebreak?}`). The helper batches one `gh search prs` call per org (HIP-N OR <keywords>), respects `strategy3.per_org_search_budget` with exponential 1s/2s/4s backoff on 429 responses, applies the `noise_ceiling_commits_per_day` downgrade for high-volume repos, and emits a single `source: "s3_skipped"` record on rate-limit-after-3-retries instead of crashing. Same non-fatal contract as Strategy 2.

**Stage 5 — cross-link with Step 2 data:**

For each PR returned by Stages 2, 3, or 4: if the same PR (by `url` or `(repo, pr_number)` tuple) appeared in Step 2's `fetch-github-prs.sh` output (it would have a `Linked HIPs:` annotation), mark it as "already shown in priority-repo narrative below." When writing the priority-repo narrative, add a backlink for that PR: `(implements [HIP-N](raw_url-from-stage-1))`.

**Stage 6 — MAX-confidence dedup merge:**

Combine the MatchRecord arrays from Mechanism A (extracted from Step 2's `Linked HIPs:` annotations), Mechanism B (Stage 2 output), Strategy 2 (Stage 3 output), Strategy 3 (Stage 4 output) using dedup key `(hip_id, repo, pr_number)`. When two records share the dedup key, MAX their confidence (high > medium > low) and union their `sources[]` and `per_source` maps. The merged-and-deduped list is what gets rendered in the HIP Activity section.

**Stage 7 — verbose-mode filter:**

Read the env var `TEAM_DIGEST_HIP_VERBOSE` (default `0` if unset). Persistent setting lives in `~/.config/team-digest/env` (sourced by `bin/team-digest-run.sh` as of commit `251830a`). Two behaviors:

- `TEAM_DIGEST_HIP_VERBOSE=0` (default): filter the merged list to entries with `confidence == "high"`. Medium and low matches are dropped from the rendered output entirely. Render the standard HIP Activity Tier 1 / Tier 2 / Tier 2b / overflow shapes.
- `TEAM_DIGEST_HIP_VERBOSE=1`: render high-confidence matches as above. After the standard HIP Activity content (including any Tier 3 overflow), emit a `### Lower-Confidence Matches` H3 subsection containing every medium- and low-confidence match. Each row uses the verbose template from `TEMPLATE.md` (source label, confidence, matched_keywords if Strategy 3, category_tiebreak if Strategy 3, per_source primary reason). Sort rows by `hip_id` ascending then `confidence` descending (medium before low). If verbose=1 but no medium/low matches exist for the day, omit the subsection entirely (no empty-state filler).

The H3 subsection is contained within the H2 `## HIP Activity` boundary, so the chunked-write logic in Step 5.3 (sentinel-driven, H2-split, ~4KB chunks) is unaffected — the verbose subsection rides inside the HIP Activity chunk.

Pass-through for `s3_skipped` records: these were emitted by Strategy 3 when an org hit rate-limit retries. Render them in the verbose subsection only, with a special row form `_Strategy 3 skipped for <org>/_meta — <reason>_` (no PR link, no HIP-N link). In default (non-verbose) mode, omit `s3_skipped` records entirely.

**Stage 8 — match-record sidecars (FULLY AUTOMATIC, no skill-body action required):**

Every match-producing helper writes structured JSON sidecars to `$TEAM_DIGEST_MATCHES_DIR` directly. By the time the helpers in Stages 2 / 3 / 4 return, the dir contains:

- `mech_a-prs-<org>.json` (one per github org) — from `fetch-github-prs.sh`
- `mech_a-issues-<org>.json` (one per github org) — from `fetch-github-issues.sh`
- `mech_b-hip-<N>.json` (one per touched HIP) — from `fetch-hip-implementation-prs.sh`
- `strategy2.json` (one file total) — from `fetch-hip-release-refs.sh`
- `strategy3.json` (one file total) — from `fetch-hip-timeline-correlations.sh`

**You do NOT need to write anything to `$TEAM_DIGEST_MATCHES_DIR` from the skill body.** The helpers handled it.

After this stage, the dir is the canonical source of truth for matches. The wrapper (`bin/team-digest-run.sh`) calls `consolidate-matches.sh` on this dir after the skill returns; see Step 5.0 below.

To re-baseline (one-shot, run by the maintainer outside the daily cron):

```bash
/team-digest <date> --dry-run
bash ~/.claude/skills/team-digest/lib/calibrate-hip-matches.sh --baseline /tmp/team-digest-dry-runs/team-digest-<date>-vN.md
```

**Render the HIP Activity section** under each org header in `hip_tracking.implementation_orgs`, BEFORE the Priority Repos subsection. See the entry shapes in `TEMPLATE.md` for the exact format (Tier 1 / Tier 2 / Tier 2b / overflow).

**Section-empty fallback:** if Stage 1 returned `[]` and no proposal PRs were found, omit the entire HIP Activity section (no "no HIPs today" filler).

### Step 2.5: Scan Industry News (RSS feeds + commit-watching for spec sets)

This step covers public/external content the team should be aware of - blog posts, ecosystem announcements, EIP changes. Configured via the `rss_feeds` array in `config.json` (already loaded by `lib/load-config.sh` in Step 0).

**If `rss_feeds` is missing or empty:** skip this step entirely. Do not include an Industry News section in the output.

Each `rss_feeds` entry has the shape:

```json
{ "name": "<display name>", "url": "<URL or github:// pseudo-URL>", "category": "<grouping label>" }
```

**Two URL forms are recognized:**

- `https://...` (or `http://...`) - a regular RSS or Atom feed → call `lib/fetch-rss.sh`.
- `github://<owner>/<repo>` or `github://<owner>/<repo>/<path>` - a public GitHub repo (optionally restricted to a path) → call `lib/fetch-gh-commits.sh`. This is for spec sets like EIPs that don't publish RSS but live as a public git repo.

**Dispatch one helper per entry, in parallel** (one Bash tool message with N parallel calls):

```bash
# RSS/Atom feed:
bash ~/.claude/skills/team-digest/lib/fetch-rss.sh "<url>" "$DATE_LABEL"

# GitHub commit-watching - parse <owner>/<repo>[/<path>] from the github:// URL:
bash ~/.claude/skills/team-digest/lib/fetch-gh-commits.sh "<owner>/<repo>" "$DATE_LABEL" "<path-or-empty>"
```

Each helper returns a JSON array of items dated to `$DATE_LABEL`. Empty arrays (`[]`) are valid - that source had no items that day. Helper failures (network issue, malformed XML, gh rate limit) result in `[]` plus a stderr WARN line; do not abort the digest.

**Range mode (`IS_RANGE=1`):** `fetch-rss.sh` and `fetch-gh-commits.sh` are day-pinned. For a range digest, invoke each feed once per day across `$WINDOW_START..$WINDOW_END` (parallel batches) and merge the results, de-duplicating items by `link`/`sha`. For a single-day digest, call each once with `$DATE_LABEL` as written.

**For each non-empty result, write narrative output:**

- Group by the entry's `category` (e.g., all items sharing the same category label appear together).
- Within a category, list items as bullet points, one item per line.
- For RSS items: `- [<title>](<link>) - <1-2 sentence summary>` (source: helper's `summary` field).
- For github:// commit items: `- [<short SHA>](<commit url>): <commit subject> by <author>` (source: helper's `message` field).
- **Strip HTML tags from RSS summaries.** Many feeds return summaries containing `<p>`, `<img>`, `<a>` tags. Render them as plain text before writing - readers should not see raw HTML in the digest.
- **Do NOT fetch full article HTML.** The 400-char summary the helper returns is enough for a 1-2 sentence digest entry. Token cost is bounded.

**Section-empty fallback:** if every helper returned `[]`, omit the Industry News section entirely. Do NOT write "No industry news today" filler.

**Critical: do not save helper output to intermediate files. Capture stdout into the conversation context.**

### Step 3: Scan Notion Keywords

For each keyword group from configuration, search the Notion workspace:
- Use the `notion-search` MCP tool with `query_type: "internal"`
- Filter to pages created within the window using `created_date_range: { start_date: "<WINDOW_START>", end_date: "<WINDOW_END>" }` (a single day when `IS_RANGE=0`, the full span otherwise)
- Set `page_size: 10` and `max_highlight_length: 150`

Run keyword searches in parallel batches (2-3 keywords per search query to reduce API calls).

**Deduplication:** Track page IDs across all keyword searches. Each page appears only once in the digest with all matching keywords listed.

**Exclusions:** Skip any page whose title starts with "Team Daily Digest" (our own output).

**Notion Link Registry (mandatory - do this immediately after each search call):**

After EVERY `notion-search` response, before moving on, extract and record the URL for every page returned. The `notion-search` MCP tool includes a `url` (or `public_url`) field for each result - that exact value is what you must use when linking the page anywhere in the digest. Build and maintain a running registry in your context:

```
Page ID | Title | URL (from MCP response)
<id>    | <title> | <exact URL from notion-search or notion-fetch response>
```

**You MUST fetch each matched page with `notion-fetch` to get its canonical URL if `notion-search` does not return one.** Do NOT proceed to writing until you have a URL for every page in the registry.

For each unique page found:
- **If the `notion-search` highlight is ≥ 100 chars, skip `notion-fetch` and use the highlight directly as the summary source.** Add the `url` from the search result to the Notion Link Registry. Note in the page entry: `(summary from search highlight; full page not fetched for token efficiency)`. **If the highlight is < 100 chars**, call `notion-fetch` to get the full page; record the `url` from the fetch response in the registry; write a narrative summary from the full content. The Favorites section (Step 3.5) ALWAYS calls `notion-fetch` because favorites are explicitly curated — this skip rule applies only to keyword-matched pages.
- Write a narrative summary explaining what the page contains
- List which keywords matched
- Add a "relevance" note explaining why this matters for the team

If Notion keyword scanning fails, note the failure and continue.

### Step 3.5: Scan Notion Favorites (with one-level child descent)

This step covers the user's curated list of "Favorites" pages - documents they care about regardless of keyword match - PLUS one level of descent into pages those favorites link to. The Notion REST API does not expose a user's sidebar Favorites, so the list comes from the **Favorites** section of the Notion config page (loaded in Step 1).

**If no Favorites list was extracted from the config page:** skip this step entirely. Do not include a Favorites section in the output.

**"Edited in the window" predicate:** throughout this step, a page qualifies when the date portion of its `last_edited_time` (UTC) falls within `[$WINDOW_START, $WINDOW_END]` inclusive — a single day when `IS_RANGE=0`, the full span for a range digest.

**Phase A - Fetch each favorite (parallel):**

1. Call `notion-fetch` with the URL or ID. The MCP tool accepts both forms; no need to parse the 32-char hex from the URL manually.
2. From the response, read `last_edited_time` (an ISO-8601 UTC timestamp on the page object) AND the page's canonical `url` field. Add the `{page_id, title, url}` tuple to the Notion Link Registry immediately.
3. Apply the "edited in the window" predicate to `last_edited_time`. If it qualifies, the favorite itself was edited during the digest window - mark it as a "qualifying parent."
4. If the page was archived (response includes `archived: true`), skip it silently along with any descent.
5. If `notion-fetch` returns an error (page not found, page deleted, user lacks permission), log a one-line failure note like `(Favorite <ID>: not accessible - check the URL or your access)` and continue.
6. **Collect child page references** from the response content. The Notion MCP enhanced-Markdown response renders child pages as `<page url="..." title="..."/>` tags or as Notion `@mention`-style page links inside the page body. Extract every Notion page URL or ID found inside the favorite's content. These are the candidates for descent.

Emit all favorite `notion-fetch` calls in one message so they run concurrently.

**Phase B - Descend one level (conditional, parallel, capped):**

**This phase only runs when at least one favorite was marked as a qualifying parent in Phase A** (i.e., its `last_edited_time` fell within the window). If Phase A found zero qualifying parents, skip Phase B entirely and proceed to Phase C with an empty child list. This prevents fetching dozens of child pages from large index favorites on days when nothing is actively being edited.

For each **qualifying parent favorite** (and only those), take its collected child page references and call `notion-fetch` on each in parallel. Apply these limits:

- **Cap at 5 children per favorite.** If a qualifying parent has more than 5 unique child page references, fetch the first 5 and add a one-line note `(<favorite title>: 5-child cap reached, N pages skipped)` to the Favorites section.
- **Single hop only.** Do NOT recurse into the children's children. Loops or deep trees would explode the cost.
- **Deduplicate across favorites.** If two different favorites both link to the same child page, fetch it once.
- **Apply the same "edited in the window" predicate** to each child. Children not edited in the window are silently dropped.
- **Skip archived children silently.** Skip permission-error children with a one-line note in the digest.

**Phase C - Cross-section dedup:**

Track page IDs across all Notion sections. If a page already appeared in the Keyword Monitor (Step 3), still mention it briefly in the Favorites section with a link-back rather than re-summarizing - the user explicitly cares about favorites, so silent dedup hides signal. If a page is BOTH a favorite (or its child) AND a keyword match, prefer the Favorites section and add a `(also matched keywords: ...)` note.

**For each qualifying page (favorite or child, edited in the window):**

- Use the page's canonical URL from the MCP response as the link target.
- Write a 2-4 sentence narrative summary of what changed or what the page contains.
- Add an **Relevance:** sentence explaining why this update matters for the team, using the team profile as the lens.
- Note `last_edited_time`.
- For child pages, note the parent favorite title in the entry: e.g., `[Sub-page Title](url) (under [Parent Favorite](parent-url))`.

**Section-empty fallback:**

If every favorite (and every descended child) was either inaccessible, archived, or not edited in the window, include the Favorites section with a single line: `No favorited pages or their child pages had updates in <WINDOW_LABEL>.` This distinguishes a successful no-hit scan from a configuration mistake.

**Access model:** the Notion-hosted MCP (the OAuth-based connector Anthropic ships) inherits workspace-wide access from the user's OAuth grant - no per-page sharing required. If a `notion-fetch` returns a "not accessible" error, the cause is almost always one of: (a) the page was deleted or moved out of the user's workspace, (b) the user themselves lacks permission to that page (e.g., a private page in another team's space), or (c) the URL is malformed. Treat permission errors as a real signal worth surfacing in the digest, not as expected setup friction.

### Step 4: Scan Partner Conversations

For each partner pattern from configuration, search the Notion workspace using the `notion-search` MCP tool with `created_date_range: { start_date: "<WINDOW_START>", end_date: "<WINDOW_END>" }` to strictly bound results to the digest window. Set `max_highlight_length: 150` for token-efficiency parity with Step 3 — the highlight is only used to decide whether the meeting page is worth synthesizing in full via `notion-fetch`; long highlights waste tokens without changing the routing decision.

**Deduplication:** Skip pages already covered in the keyword monitor section. Track by page ID.

**URL capture (mandatory - same rule as Step 3):** After every `notion-search` response, immediately extract the `url` field for each result and add it to the Notion Link Registry. After every `notion-fetch` response, extract and record the canonical `url` field. Use ONLY these registry values when linking meeting pages in the Partner Conversations section. Never construct a Notion URL from a meeting note title (e.g., `https://www.notion.so/Jake-Kea` constructed from the title "Jake <> Kea" is WRONG).

For each meeting/conversation page found:
- Fetch full page content using the `notion-fetch` MCP tool; extract the `url` from the response and record it in the registry
- Identify partner/company names discussed
- **Group results by company/partner** (not by page)
- Summarize key discussion points
- Extract and list action items with checkboxes
- Note any follow-ups or deadlines mentioned
- Link the meeting page title using the URL from the registry: `[<title>](<registry-url>)`

If partner scanning fails, note the failure and continue.

### Step 4.5: Pre-Write Link Audit (mandatory)

Before writing to Notion, scan the assembled digest content one final time. Verify:

1. **Every repo name is a markdown link.** Search the draft for bare repo names. If a repo is mentioned without `[name](https://github.com/<org>/<name>)`, fix it.
2. **Every PR/issue number is a link.** Search for bare `#<number>` patterns. Every match must be `[#<number>](<url>)` with the actual URL.
3. **Every release tag is a link.** Search for bare version strings like `v1.2.3` in release contexts. Each must link to the GitHub release page.
4. **Every Notion page title is a link using a URL from the Notion Link Registry.** In the Keyword Monitor, Favorites Activity, and Partner Conversations sections, every page title must be `[<title>](<notion-url>)`. The URL MUST be the exact value extracted from a `notion-search` or `notion-fetch` MCP response and stored in the registry - never constructed from the page title. Scan the draft for any Notion URL that matches the pattern `notion.so/<title-slug>` (a slug derived from the page title) - these are fabricated and MUST be replaced with the registry value, or removed if no registry entry exists. If a page has no URL in the registry, write the title as plain text followed by `(link unavailable)` rather than inventing a URL. In Favorites Activity specifically, every child-page entry must also link its parent favorite (e.g., `(under [Parent Title](parent-url))`).
5. **Every GitHub user mention is a link.** Search for bare `@<handle>` patterns - each must link to `https://github.com/<handle>`.
6. **First-mention expansions are present.** Spot-check that any project name, component, or acronym mentioned for the first time in a section is followed by a 3-7 word expansion (per the Plain-English Description Rules).
7. **No `\n` inside Mermaid labels.** Search every Mermaid block (delimited by ` ```mermaid ` and ` ``` `) for the literal two-character sequence `\n` inside any node label. Mermaid line breaks do NOT render reliably in Notion - text after the `\n` is silently cut off, leaving readers with truncated diagrams. If a label is too long for one line, shorten it (drop the parenthetical, abbreviate, use a single key word) instead of splitting it. This rule is non-negotiable: a truncated diagram is worse than a verbose one because the reader does not know they are missing context.
8. **Every Industry News title or commit SHA is a link.** Items in the Industry News section must each be `[<title>](<link>)` (RSS) or `[<short-sha>](<commit-url>)` (commit). No bare titles or SHAs. Summaries must have HTML tags stripped - search the section for `<p>`, `<img>`, `<a `, and similar; if any are present, render the prose as plain text instead.
9. **Every `HIP-N` reference in prose is a markdown link.** Scan the draft for `\bHIP[-_ ]?\d+\b` and `\bhip[-_ ]?\d+\b` patterns NOT already wrapped in `[...](...)`. Every match must be `[HIP-N](https://github.com/hiero-ledger/hiero-improvement-proposals/blob/main/HIP/hip-N.md)`. The HIP Activity section's own subheadings (`### [HIP-1137](url) — ...`) are exempt; this check covers Executive Summary, priority-repo narratives, "Other Active Repos" notes, Industry News, and Partner Conversations action items. If `TEAM_DIGEST_HIP_ENABLED=0`, this check is a no-op.

If any of checks 1-9 fail, fix the draft before proceeding.

### Part B: Quality Scaffold (mandatory - complete after the link checks above)

These three audits are the difference between a digest that reads like a log dump and one a non-technical person can actually use. Complete each one explicitly - state your findings in plain text before moving to Step 5.

#### Quality check A: Diagram audit

For EACH priority repo section, scan the PRs and issues that appeared in the window (`$WINDOW_START..$WINDOW_END`; a single day when `IS_RANGE=0`) and check whether any of these triggers fired:

| Trigger | Example PR/issue descriptions that match |
|---|---|
| New component, service, module, or smart contract introduced | "add X service", "introduce XFacet", "scaffold X module", "FactoryFacet added", "new XHelper class" |
| Existing component split or extracted | "extract X from Y", "split X into A and B", "move X out of Y into its own module" |
| Components merged or consolidated | "merge X and Y", "consolidate X into Y", "fold X into Z" |
| Data flow or dependency changed between services | "X now calls Y", "remove dependency on Z", "route X through Y instead of Z" |
| Component restructured or migrated to a new pattern | "restructure X", "refactor X into layers", "migrate X to new pattern", "move X into the store layer" |
| Architecture documented in a PR | "add ADR for X", "document X architecture", "architecture diagram for X" |
| New integration point between two previously unconnected systems | "X now integrates with Y", "X emits events consumed by Y", "wire X to Y" |
| Bug fix that reveals an unexpected interaction between components | "fix X where Y incorrectly assumed Z after A was changed" |

**For every repo where at least one trigger fired, a diagram is required.** Add it now if missing. Use `graph TD` with `direction LR` subgraphs for square layout; single-line node labels only (no `\n`).

State your findings explicitly before writing Step 5 - one line per priority repo:
```
hiero-consensus-node: trigger "move X into store layer" fired → diagram REQUIRED → added
asset-tokenization-studio: trigger "new FactoryFacet introduced" fired → diagram REQUIRED → added
hiero-json-rpc-relay: no trigger matched → no diagram needed
solo: trigger "new silent mode changes how solo interacts with CI" fired → diagram REQUIRED → added
```

If you added a diagram, re-run check 7 above on it (no `\n` in labels).

#### Quality check B: Executive Summary specificity gate

Re-read each Executive Summary bullet. For each one, verify it passes both questions:
- **Q1 - Specific:** Does it name a concrete change - not "various improvements", "continued work on", "lots of activity in X", "dependency updates across the org"?
- **Q2 - Consequence:** Does it state the effect or why it matters to a reader - not just what happened, but what it means?

If a bullet fails either question, rewrite it before proceeding.

Then scan the entire Executive Summary for the pattern `` **` `` (bold immediately followed by a backtick). These produce `**** ` rendering artifacts in Notion. Replace every match:
- ❌ `` **`hiero-consensus-node`** architecture docs`` → artifacts on render
- ✅ `**[hiero-consensus-node](https://github.com/hiero-ledger/hiero-consensus-node) architecture docs**`

Use the linked form `[repo-name](url)` whenever possible - it provides navigation and avoids the collision entirely.

#### Quality check C: Industry News clarity

For each item in the Industry News section, verify it has two parts:
1. **What happened** - plain English, not a raw RSS title or feed description verbatim
2. **Why it matters** - one phrase explaining relevance to Hedera/EVM ecosystem work

Required format: `[title](link) - <plain-English what happened>; relevant because <why it matters for our work>`

- ❌ `[EIP-7981 reference implementation](url) - Update EIP-7981 reference implementation by Toni Wahrstatter` - raw commit message
- ✅ `[EIP-7981 reference implementation](url) - the reference code for validator credential rotation was updated; relevant because Hedera's Pectra compatibility work will need to handle this credential mechanism`

If you cannot construct a genuine "why it matters" for an item, drop it rather than padding with noise. Two relevant items beats five padded ones.

---

Only proceed to Step 5 after: all triggered diagrams are present and checked for `\n` labels, every Executive Summary bullet passes Q1 and Q2, and every Industry News item has both parts.

### Step 5: Write the Combined Digest

**FIRST: Always write a safety backup file** before doing anything else in this step - even before the dry-run check. This ensures the assembled content is never lost to a Notion API timeout or stream error.

```bash
DRY_DIR="/tmp/team-digest-dry-runs"
mkdir -p "$DRY_DIR"
# Find the next free version number for this date
N=1
while [ -f "$DRY_DIR/team-digest-${DATE_LABEL}-v${N}.md" ]; do
  N=$((N + 1))
done
SAFETY_PATH="$DRY_DIR/team-digest-${DATE_LABEL}-v${N}.md"
# Use the Write tool (not echo) to write the assembled content to $SAFETY_PATH.
```

Use the `Write` tool to write the content **in Notion-flavored Markdown** (keep all `<callout>`, `<details>`, `<table header-row>` tags exactly as they would appear in the Notion page). This is intentional: the safety file doubles as the source for `--from-file` recovery, so it must be in the same format as what `notion-create-pages` receives. It is ephemeral - cleared on reboot.

After writing, print a single line: `Safety backup: <SAFETY_PATH>` so the user knows where to find it if the Notion write fails.

**Step 5.0: matches.json consolidation is handled by the wrapper. Do NOT write matches.json yourself.**

The sidecar files written by the match helpers (`fetch-github-prs.sh`, `fetch-github-issues.sh`, `fetch-hip-implementation-prs.sh`, `fetch-hip-release-refs.sh`, `fetch-hip-timeline-correlations.sh`) all live at `$TEAM_DIGEST_MATCHES_DIR`. After this skill body returns, `bin/team-digest-run.sh` deterministically:

1. Finds the newest safety file written by this run.
2. Discovers the matches sidecar dir (the wrapper's own dir if env-var propagation worked, else the skill-body fallback dir `/tmp/team-digest-matches-<DATE_LABEL>-<pid>`).
3. Runs `consolidate-matches.sh <dir> <safety>-matches.json` to produce the canonical matches.json with MAX-confidence dedup.
4. Runs `calibrate-hip-matches.sh --current-only <safety>` for drift detection.
5. Cleans up the matches dir.

**STRICT RULES for this skill:**

- **DO NOT use the Write tool to create a `*-matches.json` file.** The wrapper will produce it from the sidecars. If you write one yourself, the wrapper's consolidator will overwrite it — but only if env-var propagation works AND your write happens before the wrapper's post-run step. The race is fragile; don't run it. Just write the sidecars and stop.
- **DO NOT call `consolidate-matches.sh` or `calibrate-hip-matches.sh --current-only` from inside this skill body.** The wrapper calls them after you return.
- Your end-of-run handoff to the user: print `Safety backup: <SAFETY_PATH>` (and, if dry-run, `Dry-run output: <SAFETY_PATH>`). Do NOT also print a `Matches sidecar: <path>` line; the wrapper logs that itself when consolidation succeeds.

If you're running interactively inside Claude Code (not via `bin/team-digest-run.sh`), the wrapper isn't there. The sidecars still get written but matches.json won't auto-consolidate. To produce it manually after the skill finishes, invoke:

```bash
bash ~/.claude/skills/team-digest/lib/consolidate-matches.sh "$TEAM_DIGEST_MATCHES_DIR" "${SAFETY_PATH%.md}-matches.json"
```

That's an explicit user action, not part of the skill body.

**If `$DRY_RUN` is set:** also print `Dry-run output: <SAFETY_PATH>` and stop. Skip the rest of Step 5. (The safety file IS the dry-run output - same content, same path. The matches.json peer file at `${SAFETY_PATH%.md}-matches.json` is the canonical calibration input.)

**If `$DRY_RUN` is NOT set:** proceed with the SPLIT-WRITE procedure to avoid the stream-timeout failure mode that hit single-call `notion-create-pages` writes when the body grew large. The split moves the heavy payload into a separate `notion-update-page` call so the small `notion-create-pages` call almost never fails, and a failure on the update step can be retried independently without losing the page.

**Step 5.1: Create the page with a PLACEHOLDER body.**

Call `notion-create-pages` with:

- **Parent:** `{ "type": "data_source_id", "data_source_id": "<data_source_id discovered in Step 0>" }`
- **Properties:**
  - Digest Title: `Team Daily Digest - <DATE_LABEL>` when `IS_RANGE=0`; `Team Digest - <WINDOW_START>..<WINDOW_END>` when `IS_RANGE=1` (see TITLE LOCK).
  - date:Date:start: `<WINDOW_START>`
  - date:Date:end: **OMIT entirely when `IS_RANGE=0`** (Notion requires a NULL end for a single date - never set it equal to the start); set to `<WINDOW_END>` when `IS_RANGE=1`. This is what lets `/team-weekly` find a range scan by overlap.
  - Digest Type: `Combined`
  - Repos Active: `<count of repos with activity>`
  - Keywords Matched: `["keyword1", "keyword2", ...]` (JSON array of keywords that had hits)
  - Partners Mentioned: `["<Company A>", "<Company B>", ...]` (JSON array of distinct partner/company names surfaced in Partner Conversations; empty array if none). **Include this property ONLY if the database schema (from the Step 0 `notion-fetch` on the database) has a `Partners Mentioned` property; OMIT it entirely otherwise** — older installs without the column would reject an unknown property and fail the page create.
  - Status: `Auto`
- **Content:** the literal one-line placeholder `<callout icon="⏳" color="gray">Digest content loading...</callout>` — nothing else. This call carries the metadata payload only; the body comes later.

If THIS call fails (rare given the small payload), tell the user:
> Notion page creation failed at the metadata step. Assembled content is saved at `<SAFETY_PATH>`. Re-run with:
> `bin/team-digest-run.sh <DATE_LABEL> --from-file <SAFETY_PATH>`
Then STOP - do NOT silently retry or write another safety file.

**Step 5.2: Extract `page_id` from the response.**

The `notion-create-pages` response includes a `pages` array. Take the first entry's `id` field as `$NEW_PAGE_ID`. Also extract the `url` field as `$NEW_PAGE_URL` for the success message at the end.

**Step 5.3: Upload the full digest content using CHUNKED-WRITE.**

The full content (~15-25 KB) exceeds what a single `notion-update-page` call can deliver within the stream idle timeout. Write it in sections so each call stays under ~4 KB and the stream stays alive between calls via progress log lines.

**Sentinel:** the string `DIGEST-SECTION-BREAK` — appended as a standalone paragraph after each chunk, replaced by the next chunk in the next call, and removed in the final call.

**How to split:**
- Identify all `## ` heading boundaries in the assembled content.
- Section 0 = everything before the first `## ` (header callout + `---` separator).
- Each `## Heading\n...content...` up to the next `## ` boundary is one section.
- Merge two consecutive sections into one chunk if their combined length is under 3,000 characters.
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
> `bin/team-digest-run.sh <DATE_LABEL> --from-file <SAFETY_PATH>`
> The `--from-file` path detects the `DIGEST-SECTION-BREAK` sentinel and restarts the chunked write from the beginning.

Then STOP. Do NOT silently retry; do NOT write another safety file.

**Step 5.5: On full success, print the Notion page URL.**

Print `Notion page: $NEW_PAGE_URL` so the user (or the cron log) has the link to the new digest.

**Content** must use Notion-flavored Markdown. Key rules:
- Use `<callout icon="..." color="...">content</callout>` for callout blocks — all content on a **single line**. Never put a newline after the opening tag; never put `</callout>` on its own line. The Notion MCP treats each `\n` as a block boundary and renders multi-line callouts as stray `</callout>` text blocks.
- Use `<details><summary>...</summary>...</details>` for toggles
- Use `<table header-row="true"><tr><td>...</td></tr></table>` for tables
- Use `[link text](URL)` for links
- Use `**bold**` for bold, `- item` for bullet lists
- Do NOT use `\n` inside content - use separate blocks
- Do NOT try to fetch the Notion markdown spec at runtime
- **Emoji must be standard Unicode characters (📊, ℹ️, 📈, ⚠️, 📌, 🤝)**, NEVER `:shortcode:` form (`:memo:`, `:rocket:`, `:warning:`). Notion's API rejects shortcodes with `validation_error: Custom emoji ":xxx:" not found in this workspace`, forcing a retry. The same applies to the page-level icon - either omit it or use a Unicode character; never pass a `:shortcode:` value.
- **Do NOT wrap inline code in bold.** Patterns like `**``repo-name``**` produce `**** ` artifacts in the rendered output because the bold and code spans collide. Pick one: either bold (`**repo-name**`) or code (`` `repo-name` ``). For repo names that are also markdown links, prefer the linked form `[repo-name](url)` and skip bold/code entirely.
- **The auto-generated footer is the LAST block of the page.** It is the closing callout that documents what was scanned and the data window. Never replace it with a "Known limitations" / "Caveats" / "Notes about this run" callout, never omit it. Section-level inline notes (e.g., `(Phase B descent skipped)` or `(gh search hit the 100-result cap)`) belong inside their respective sections, not as a closing callout.
- **Do NOT add meta-sections about run hygiene.** The output structure below is the contract. Do not invent extra closing sections like "Known limitations for this run", "Caveats", "What this digest does not cover", or any other meta-narrative about the digest's own production. If a source returned no data, that's already handled by the section-empty fallbacks per source. If a source partially failed, note it inline at the section, not at the end.

#### Output format contract

`TEMPLATE.md` was already loaded at Step 0 - it is the canonical output contract that has been in context throughout data gathering. Now apply it: substitute all `<PLACEHOLDER>` values with the actual data, in the order the template specifies. The "FORMAT RULES" section at the bottom of TEMPLATE.md is a human reference only - do not render it in the Notion page. If for any reason you do not have TEMPLATE.md in context (e.g., context was compacted), re-read it now before assembling.

**Structure enforcement check.** Before writing the safety file at Step 5.1, scan the assembled draft for these structural requirements:
- The header callout is `<callout icon="📊" color="blue_bg">**Team Daily Digest** | ...</callout>` for a single-day digest, or `<callout icon="📊" color="blue_bg">**Team Digest** | ...</callout>` for a range digest (`IS_RANGE=1`) — NOT "SA Daily Digest", NOT a team-specific name, NOT a callout missing the locked prefix. The `Data window` field shows `<WINDOW_START>` (single day) or `<WINDOW_START> .. <WINDOW_END>` (range).
- Each org with priority-repo activity has a top-level `# <org-name>` H1 (not H3), then `## 📁 Priority Repos` H2, then one `### [<repo>](url)` H3 per priority repo, each followed by a 2-4 paragraph narrative AND a `**Relevance:**` paragraph (and an optional `<details>` depth toggle).
- Orgs with non-priority repos have a `## 📂 Other Active Repos` H2 whose long-tail repo list sits inside a `<details>` toggle — never a flat dump of every PR in the main flow. Keep this as a `## ` H2 so the chunked write gives it its own chunk.
- Section anchors carry their fixed emoji (🔑 ⭐ 🧩 📁 📂 🚀 📰 🔎 📌 🤝); the `## 🔑 Executive Summary` heading keeps the words "Executive Summary" (the cascade matches on them).
- If any of these is missing, fix the draft before writing.

#### Executive Summary (mandatory first content block)

Every digest opens with an **Executive Summary** under an `## 🔑 Executive Summary` heading (keep the words "Executive Summary" - the cascade extracts the section by them), immediately after the header callout. Purpose: a reader who only skims this section should leave knowing what's worth knowing - the day's headlines in plain words.

**Format:**

- 5 to 8 bullet points
- **Length cap: 50-90 words per bullet.** Each bullet is the headline plus one consequence clause. If you need three independent facts, write three bullets. The per-section narratives below carry the depth; the Executive Summary is for scan-speed signal.
- Each bullet is one specific change with stakes - not "lots of activity in X"
- Lead each bullet with a bold callout (the project, repo, or topic) followed by a one-line plain-English statement of what changed and why it matters
- Every bullet links to the relevant section below for drill-down (e.g., the priority-repo section, the release, the Notion page, the partner conversation)
- Cover a mix: priority-repo headlines, releases, major Notion design docs created today, partner conversations of substance, notable Industry News items
- Skip routine maintenance (dep bumps, README touch-ups, test refactors) - the per-section narratives already cover those
- Apply the same Plain-English Description Rules: write for an outsider, lead with the user-visible change, no insider jargon without translation
- Match framing to the scan window. For a **single-day** digest (`IS_RANGE=0`), keep every bullet day-scoped — describe what changed that day. The cascade may add at most ONE short background clause for continuity ("part of the ongoing X work"), but never reframe a single day's change as a multi-week arc and never write "this week". For a **range** digest (`IS_RANGE=1`), period-scoped framing ("over this period", "this week") is correct because the window actually spans it. Do not invent an arc the cascade context does not support.
- The audience is your future self skimming the page in 30 seconds - what would you most want to surface?

**Anti-examples:**

- ❌ "Lots of activity in `hiero-json-rpc-relay`" - too vague; what specifically?
- ❌ "5 PRs merged across the org" - count without content
- ❌ "Quiet day on consensus-node" - belongs in the per-repo narrative, not the headlines

**Good examples:**

- ✅ "**`hiero-json-rpc-relay` Pectra-readiness work continued** - the relay now keeps concurrent transactions in submission order ([#5371](url) merged), and a separate type-handling fix for the new fork landed ([#5370](url))."
- ✅ "**Major design doc landed in Notion** - the [JSON-RPC Relay → Block Node Port](url) plan was authored, mapping the path to deprecate the Node.js relay in favor of an in-process Java plugin. Canonical reference for partners asking 'when can I run an in-process EVM endpoint?'"
- ✅ "**`solo` v0.72.0 released** - the local Hiero/Hedera dev network deployment tool cut a new release; partners using HIP-1137 or HIP-1261 features locally still hit a regression ([#4228](url))."

**Section-empty fallback:** the Executive Summary is mandatory - if the day was genuinely quiet (e.g., a holiday with zero activity), write a single bullet acknowledging it: "- Quiet day across all sources: no priority-repo activity, no releases, no Notion pages created, no partner conversations."

#### Top Picks: Notion Pages Worth Reading

After the Executive Summary (and the optional `⚠️ Heads up` callout, if the day warrants one), include a `## ⭐ Top Picks: Notion Pages Worth Reading` section IF AND ONLY IF the day produced at least one Notion page worth highlighting.

**Selection logic:**

1. Take the union of pages found via Notion Keyword Monitor (Step 3) and Favorites Activity (Step 3.5). De-duplicate by page ID.
2. Exclude pages whose title starts with "Team Daily Digest", "Team Weekly Digest", "Team Monthly Digest", or "Team Digest - " (the range-scan form) - the digest's own output should never be in Top Picks. Also exclude any title matching the regex `^[A-Z]{2,4} (Daily|Weekly|Monthly) Digest` (catches legacy outputs from earlier digest names like "SA Daily Digest", "Eng Weekly Digest" that may still live in the database).
3. Rank remaining pages by relevance to the team profile's "What's Relevant" / "High Priority" criteria. A page that touches multiple high-priority themes from the profile ranks higher than a page that touches one. A page with a clear stake (architecture decision, partner impact, breaking change) ranks higher than a page with a routine status update.
4. Pick the top 3-5. If fewer than 3 pages survive selection, pick all of them. If zero, omit the section entirely.

**Format per pick:**

```markdown
- **[<Page Title>](<notion-url>)** - 2-3 sentence summary of what the page contains AND why it's worth reading right now (which profile theme it touches, what decision/change it represents). Include one or two key facts from the page that would help the reader decide whether to drill in.
```

**Anti-examples:**

- ❌ Listing every keyword-matched page (that's what the Notion Keyword Monitor section is for)
- ❌ Including the digest's own output pages
- ❌ One-sentence summaries that just restate the title
- ❌ More than 5 picks - if everything is a top pick, nothing is

**Why this section exists:** the Notion Keyword Monitor below catches every keyword hit; that's a complete list. Top Picks is the curated subset for someone who only has 5 minutes - the 3-5 pages that, if you read nothing else in Notion today, you should still see.

**Content structure:** See `~/.claude/skills/team-digest/TEMPLATE.md` (loaded via the Read tool at the start of Step 5 above). The template defines every section, its order, Notion-flavored syntax, and the Format Rules (Notion API constraints, linking rules, backfill notes).

## Style Rules

### Synthesis

- **Synthesize, don't list** - describe what the team is collectively accomplishing, not individual PR titles. "The team is breaking one large contract into several smaller single-purpose contracts" beats listing 14 PRs.
- **Short paragraphs, scannable structure.** Two to three sentences per paragraph maximum. If a priority repo has more than one theme, break into two paragraphs (e.g., a "what merged" paragraph and a "what's still open" paragraph). When listing 5+ related PRs, prefer a short bullet list with one bullet per PR over a comma-separated run-on sentence - the eye can land on individual changes.
- **Lead with the user-visible change, not the PR number.** Each paragraph's opening sentence describes what changed for users; the PR/issue reference comes as a citation, not the subject. (See Plain-English Description Rules below for the translation-first rule and concrete bad/good shapes.)
- After each priority repo narrative, add a **Relevance:** paragraph. Use the team profile loaded in Step 0 to drive this - the profile specifies what the team cares about, their priorities, and content opportunity triggers. If no profile exists, use generic heuristics.
- Add a Mermaid diagram for architectural changes - component splits, service restructuring, data flow changes. **Keep every node label on a single line - never use `\n` inside labels.** Notion silently truncates Mermaid text after a `\n`, leaving readers with broken diagrams. If a label is too long, shorten it (drop parentheticals, abbreviate, use a single key word). Use `graph TD` with `direction LR` subgraphs for square layout. One diagram per repo max.
- Surface cross-repo connections when relevant (e.g., a bug in one repo that also affects a downstream consumer)
- Keep the digest scannable in under 3 minutes
- Use hyphens (-) or semicolons (;) instead of em-dashes
- If any section fails, produce a partial digest with a clear failure indicator rather than failing entirely

### Linking Rules (mandatory)

**Every entity reference is a markdown link.** Bare entity names are the #1 cause of digest unusability - a reader who wants to dig deeper has to manually search GitHub or Notion. Every time you write the name of an entity, link it.

| Entity | Link target | Format |
|--------|-------------|--------|
| Repo | `https://github.com/<org>/<repo>` | `[<repo>](https://github.com/<org>/<repo>)` |
| Pull request | The PR's `html_url` from the `gh` JSON output | `[#<number>](<url>)` |
| Issue | The issue's `html_url` from the `gh` JSON output | `[#<number>](<url>)` |
| Release | The release's GitHub URL | `[<tag-name>](<url>)` |
| GitHub user | `https://github.com/<handle>` | `[@<handle>](https://github.com/<handle>)` |
| Notion page | The page's URL from the MCP response | `[<page title>](<notion-url>)` |
| Industry News post | The `link` field from the RSS helper output | `[<title>](<link>)` |
| Industry News commit | The `url` field from the gh-commits helper output | `[<short-sha>](<commit-url>)` |

**Notes:**
- Person names that are NOT GitHub handles (e.g., partner names mentioned in meeting notes) do NOT get links.
- The first time you mention any specific entity in a section, it must be linked. Subsequent mentions in the same section may be plain text if context makes the reference unambiguous, but linking again is preferred.
- When the `gh` helper output contains a `url` field for a PR/issue/release, USE IT. Do not reconstruct URLs manually.
- For Notion pages found via `notion-search` or `notion-fetch`, the response includes a `url` (or `public_url`) field. Store it in the Notion Link Registry (Step 3) and use ONLY that exact value - never derive a URL from the page title. A URL like `https://www.notion.so/Some-Page-Title` that you constructed from a title is WRONG and will point to a nonexistent page. If you do not have the URL from the MCP response, write the title as plain text with `(link unavailable)` rather than fabricating a link.

### Plain-English Description Rules

#### Audience

**Write for an outsider** - a developer or partner who has NEVER worked in this codebase. Assume they know general industry concepts (HTTP, REST APIs, blockchain, smart contracts, RPC calls, OAuth, git, CI) but NOT:

- Your internal class names, method names, or file names
- Your internal acronyms (MAF, NPE, JPA, FIFO-in-this-context, TCK, BN, MN, CN, PE, etc.)
- Your team's sprint vocabulary or release shorthand
- Project-specific jargon even when it sounds like industry standard (e.g., "facet" means something specific in your codebase that an outsider does not know)

The team profile's **Project Glossary** is your starting point, NOT your ceiling. If a term is in the glossary, use the glossary entry. If a term is NOT in the glossary but YOU still recognize it as insider-only (an internal class name, an internal abstraction, a code-review shorthand), you must STILL translate it - either inline in plain English, or by skipping the term entirely.

#### Translation-first rule (mandatory)

**Every paragraph leads with one plain-English sentence describing the user-visible change.** PR/issue references come after the plain-English lead, not as the subject of the sentence.

Bad shape (PR-as-subject): `[#5371](url) merged: the async lock-service rework adjusts how eth_sendRawTransaction preserves FIFO nonce ordering for concurrent transactions.`

Good shape (change-as-subject): `When users send multiple Ethereum transactions at the same time, the JSON-RPC relay now keeps them in the order they were submitted, preventing out-of-order execution. Merged in [#5371](url).`

The change is the subject; the PR is the citation. Reverse the polarity of every paragraph and the digest reads to an outsider.

#### Background-first rule (mandatory)

A change is only "raw" when the reader does not know the storyline it belongs to. Before the user-visible change, add a one-clause **background** when EITHER is true:

1. The item belongs to an **Ongoing Storyline** loaded in Step 1.5 (cascade). Add ONE background clause naming the thread, scoped to the actual window. Single-day digest: "part of the ongoing fee-SPI cleanup; today this piece keeps concurrent transactions in submission order. Merged in [#5371](url)." Range digest, where the window genuinely spans the time: "the relay hardened Pectra-fork handling over this week; this piece keeps concurrent transactions in submission order. Merged in [#5371](url)." Never assert a timespan ("all month", "for three weeks") the scan window does not cover.
2. The item names a **project or component an outsider would not recognize** and the Project Glossary has (or implies) a one-line description. Lead with what it is before what changed.

Keep the background to ONE clause - it sets context, it does not retell the storyline. If Step 1.5 found no storylines (no weekly yet), fall back to glossary-driven background only. The goal: a reader who did not see yesterday's digest still understands why today's change matters.

#### Forbidden patterns (with concrete fixes)

**1. Creative metaphors and sprint slang.** Banned phrases - if you find yourself writing one, rewrite the sentence with plain action verbs (released, fixed, added, merged, opened, closed):

| ❌ Avoid | ✅ Use |
|---|---|
| "had a particularly load-bearing day" | "shipped 14 PRs and 1 release" |
| "defensive plumbing also tightened" | "added safety checks against bad input" |
| "a flurry of related items" | "five PRs, all related to X" |
| "in flight" | "open" or "still under review" |
| "cherry-picked into" | "also merged into the X release branch" |
| "the bulk of the work is" | "most of the activity is" |
| "lands" / "landed" | "merged" |

**2. Internal class/method/file names without translation.** If you have to cite an internal name (because it is the most precise reference), wrap it in plain English on first mention:

| ❌ Bad | ✅ Better |
|---|---|
| "fixes a NoSuchElementException in `RegisteredNodeCreateTransformer`" | "fixes a crash that occurred when a network state change was missing the expected node-registration record" |
| "extracts maturity from `BondFacet` into `MaturityFacet`" | "split bond-maturity logic out of the main bond contract into its own dedicated module" |
| "guards `getHistoricalBlockResponse` against empty mirror-node responses" | "added a safety check so the relay no longer crashes when the mirror node briefly returns no data" |

**3. RPC / API method names without context.** Ethereum RPC methods (`eth_call`, `eth_sendRawTransaction`, `eth_getBlockByNumber`, etc.), internal API endpoints, and protocol method names need a one-phrase translation on first mention:

| ❌ Bad | ✅ Better |
|---|---|
| "extends `eth_call` to accept blockhash" | "the read-only contract-call API can now accept a block hash directly, instead of only block numbers" |
| "fixes nonce typing issues and chain_id mapping bugs" | "fixes two type-handling bugs that affected transaction signing on the new fork" |
| "improves `debug_traceBlockByNumber` failures" | "fixes a developer-tooling endpoint that traces transaction execution for a given block" |

**4. Acronyms not in the Project Glossary.** Expand on first mention - first time only, then the bare acronym is fine in the rest of that section. If you cannot expand it confidently, drop it:

| ❌ Bad | ✅ Better |
|---|---|
| "the ongoing MAF migration" | "the ongoing 'Modular Architecture Facet' (MAF) migration - splitting one large contract into many smaller, single-purpose contracts" |
| "EIP-155 NPE fix on null chainId" | "fixes a crash (null pointer error) when processing pre-EIP-155 legacy Ethereum transactions, which do not carry a chain ID" |

**5. Multi-jargon sentences.** A sentence with three or more unexplained insider terms is unreadable. Split into two sentences, or translate at least one:

| ❌ Bad | ✅ Better |
|---|---|
| "fixes nonce typing and chain_id mapping for Pectra-era transactions surfaced from the new authorization-list parser" | "fixes type-handling bugs in two places that the new transaction-authorization parser found while processing Ethereum-Pectra-fork transactions" |

#### The Outsider Test (mandatory before completion)

After writing each priority-repo paragraph, read it imagining you joined the team last week and have only general blockchain knowledge. Ask:

- Did I introduce any term I don't recognize?
- Did I have to mentally translate any phrase?
- Is the user-visible change clear in the first sentence?
- Are there more than 3 unexplained internal terms in any single sentence?
- Did I give enough background for someone who did NOT read yesterday's digest - is the storyline this change belongs to clear in one clause, AND is the framing scoped to the actual window (no "this week" on a single-day digest)?

If the answer is "yes" to any of those, rewrite. The Pre-Write Link Audit (Step 4.5) checks links and Mermaid syntax mechanically; this Outsider Test checks readability semantically and is your job to apply paragraph-by-paragraph as you write.

#### Glossary-driven expansions (when the term IS in the profile)

When the **Project Glossary** in the team profile has an entry for a project/component/acronym, use it verbatim on first mention in the section. Examples (these come from glossary entries, not made up):

- `[<repo-name>](<repo-url>)`, the [glossary description verbatim]
- `<ComponentName>`, the [glossary description verbatim]
- `<ACRONYM>`, [glossary expansion + glossary description]

If the glossary entry is more than one line, condense to the most useful 7-12 words for the inline expansion.

## Configuration

All settings are read from `~/.config/team-digest/config.json` under the `team-digest` key:

```json
{
  "team-digest": {
    "notion": {
      "config_page_id": "<32-char hex from Notion config page URL>",
      "database_id": "<32-char hex from Notion database URL>"
    },
    "github": {
      "orgs": [
        {
          "name": "<your-org>",
          "priority_repos": ["<repo-1>", "<repo-2>", "..."],
          "scan_all": true
        }
      ]
    },
    "defaults": { ... }
  }
}
```

- **Notion IDs** are 32-char hex strings from page URLs. The internal `data_source_id` is derived at runtime.
- **GitHub orgs** is an array; each entry has a name, priority repos, and a `scan_all` flag.
- **`priority_repos`** get full narrative summaries; others get a summary table. Empty list means all repos are non-priority.
- **`scan_all: true`** scans every repo in the org. Set to `false` to only scan priority repos (useful for very large orgs).

The config is created automatically on first run (`/team-digest`) or manually via `/team-digest setup`. To update Notion IDs later, run `/team-digest setup` again. To view current config, run `/team-digest config`.

## Running headlessly (terminal / cron / launchd)

The `bin/team-digest-run.sh` script in the team-digest repo is the headless entry point. It invokes `claude -p "/team-digest [args]"` with the necessary Notion MCP tools allow-listed. Use it for:

- **Local terminal runs:** `~/repos/.../team-digest/bin/team-digest-run.sh 2026-05-04`
- **launchd / cron:** schedule `bin/team-digest-run.sh` (or a copy at `~/.local/bin/`) - see `docs/scheduling.md` for the launchd plist
- **CI / GitHub Actions self-hosted runners:** invoke `bin/team-digest-run.sh` from a workflow

The same skill, the same config file (`~/.config/team-digest/config.json`), and the same `--dry-run` flag work in every context. There is no separate "routine" code path to maintain.
