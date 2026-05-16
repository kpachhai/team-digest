---
name: team-digest
description: Team Daily Digest - scans GitHub activity, Notion keywords, and partner conversations, writes a combined digest to Notion. Usage - /team-digest [YYYY-MM-DD | --dry-run | --from-file <path> | setup | config]
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

- **DO NOT construct Notion page URLs from page titles.** Every Notion link in the digest MUST come from the `url` field of a `notion-search` or `notion-fetch` MCP response. URLs like `https://www.notion.so/Some-Page-Title` or `https://www.notion.so/Jake-Kea` that you derive from a title are invalid - Notion does not serve pages at title-derived slugs. If you do not have the URL from an MCP response, write the title as plain text with `(link unavailable)` instead. This rule applies to every section: Keyword Monitor, Favorites, Partner Conversations, Executive Summary, Top Picks.
- **DO NOT use `readMcpResource` or `ReadMcpResourceTool`** to fetch Notion markdown specs. The output format is fully defined in this skill. The MCP server name format varies between sessions and will cause errors.
- **DO NOT read persisted tool result files** (the `/tool-results/` paths). Process command output directly within the same Bash command. Persisted files may have prefix lines that break JSON parsing.
- **DO NOT use `cat` to read files then parse them in a separate step.** Always pipe or process in a single command chain.
- **GitHub data fetching uses helpers in `lib/`.** Do not re-implement `gh search prs ... | python3 -c ...` inline. The helper scripts (`fetch-github-prs.sh`, `fetch-github-issues.sh`, `fetch-github-releases.sh`) are the single source of truth for GitHub data extraction. They live at `~/.claude/skills/team-digest/lib/<helper>.sh` after `setup.sh` / `update.sh` runs.
- **DO NOT dispatch Notion MCP calls (`notion-fetch`, `notion-search`, `notion-create-pages`, `notion-update-page`, `notion-query-data-sources`) to `Agent` subagents.** Claude.ai-hosted MCP tools (Notion, Gmail, Calendar) are only available in the main Claude Code session - subagents have a separate tool registry that does NOT include them. Every Notion MCP call MUST be made directly in the main session. If you need to parallelize Notion searches, use multiple parallel MCP tool calls in a single message, not subagents.
- **DO NOT silently fall back to a dry-run write when Notion MCP tools are unavailable.** The dry-run path is reserved for the explicit `--dry-run` flag. If `$DRY_RUN` is NOT set but Notion MCP schemas cannot be loaded (see Step 0.5), STOP the run with a clear error message - do not write a dry-run file as a workaround. Silent dry-run on failure breaks the cron / launchd contract: the user expects either a Notion page or a loud failure, never a silent file in `/tmp`.

## Time Window

The digest covers a **single calendar day in UTC** (00:00:00 to 23:59:59 UTC).

**If a date argument is provided** (e.g., `/team-digest 2026-04-20`), use that date.
**If no argument is provided**, default to the previous calendar day.

This ensures:
- Manual runs at any time of day produce the same result
- Automated morning runs and manual re-runs are consistent
- No activity is missed or double-counted between runs
- Missed days can be backfilled by specifying the date

Compute the window using the `compute-window.sh` helper. Pass the user-provided date arg (if any) as the first positional. The helper validates the format and emits `KEY=VALUE` lines that you can `eval` into your shell:

```bash
eval "$(bash ~/.claude/skills/team-digest/lib/compute-window.sh "$DATE_ARG")"
# Now $DATE_LABEL, $START, $END are set.
```

If the user did not pass a date arg, invoke the helper with no arg and it defaults to yesterday in UTC. If the helper exits non-zero (invalid date format), surface its stderr to the user and stop.

Pass both `$START` and `$END` to GitHub helpers (the `START..END` range pins the window to exactly that UTC day). Use `$DATE_LABEL` as both `start_date` and `end_date` in all Notion `created_date_range` filters.

### Backfill Limitations

When running for a past date, be aware of source-specific behavior:

| Source | Backfill Support | Notes |
|--------|-----------------|-------|
| GitHub PRs/Issues | Full | `gh search --updated` works for any past date |
| GitHub Releases | Full | Release `published_at` is compared against `$START` |
| Notion Keywords | Partial | `created_date_range` only matches pages **created** on that date; pages that existed before but were **edited** that day will be missed. This is a Notion MCP search limitation. |
| Notion Partners | Partial | Same limitation as keywords - only newly created meeting notes are found |

For backfill runs, include a note in the digest footer indicating that Notion sections may be incomplete for past dates.

## Process

### Step 0: Argument parsing, subcommands, config load

#### Argument parsing

The skill argument is a single string after `/team-digest`. Parse it as zero or more of:

- A `YYYY-MM-DD` date → captured as `$DATE_ARG`
- The literal `--dry-run` → set `$DRY_RUN=1`
- `--from-file <path>` → set `$FROM_FILE` to the path token that follows the flag; this activates upload-only mode (see subcommand below)
- The literal `setup` or `config` → handle as a subcommand (below)

Order does not matter: `/team-digest 2026-05-04 --dry-run` and `/team-digest --dry-run 2026-05-04` are equivalent. Anything else is an error.

`--from-file` and `--dry-run` are mutually exclusive; if both are present, stop with an error.

#### Subcommand: `--from-file <path>` (upload-only mode)

When `$FROM_FILE` is set, skip the full data-gather pipeline (Steps 1-4) and jump directly to the Notion write. This is the token-efficient recovery path for when a previous run assembled the content but the Notion write timed out.

Flow:
1. Load config (Step 0 Load Config below) - still needed for `database_id` and `data_source_id`.
2. Load Notion MCP schemas (Step 0.5) - required to call `notion-create-pages`.
3. Fetch `data_source_id` from the database (the deferred part of Step 0).
4. Read `$FROM_FILE` using the Read tool. The file contains Notion-flavored markdown assembled by a previous run.
5. Extract `$DATE_LABEL` from the filename if no `$DATE_ARG` was provided. Safety file names follow the pattern `team-digest-YYYY-MM-DD-vN.md`; extract the `YYYY-MM-DD` portion. If extraction fails and no `$DATE_ARG` was given, stop with an error asking the user to pass the date explicitly.
6. Check whether a digest page already exists for that date (same existence check as the full pipeline - search for "Team Daily Digest <DATE_LABEL>"). If one exists, stop with a warning rather than creating a duplicate.
7. Call `notion-create-pages` with the file content as the page body and standard properties (`Digest Title`, `date:Date:start`, `Digest Type: Combined`, `Status: Auto`). For `Repos Active` and `Keywords Matched`, use zero / empty-array defaults (the file header callout contains the actual counts inline).
8. On success, print the Notion page URL. Do NOT write another safety file (the source file already exists).
9. On failure, tell the user the source file is still at `$FROM_FILE` and they can try again.

#### Subcommand: `setup`

If the argument is `setup`, run the interactive setup flow (see below) regardless of whether a config already exists. This lets users update their Notion IDs at any time. After writing the config, confirm success and stop (do not run the digest).

#### Subcommand: `config`

If the argument is `config`, read `~/.config/team-digest/config.json` and display the current `team-digest` configuration in a readable format: Notion IDs (masked to last 8 chars for brevity), GitHub orgs, priority repos, and default keywords. Then stop.

#### Load Config

Run the helper:

```bash
bash ~/.claude/skills/team-digest/lib/load-config.sh team-digest

# Resolve GitHub token if config has one (env vars still win).
eval "$(bash ~/.claude/skills/team-digest/lib/load-config.sh team-digest | bash ~/.claude/skills/team-digest/lib/resolve-gh-token.sh)"
```

It reads `~/.config/team-digest/config.json`, validates that the `team-digest` key and required Notion IDs exist, and prints the digest's config object as JSON on stdout. On failure (file missing, key missing, empty IDs) it exits non-zero with a clear message on stderr.

**If the helper exits with status 1 (config file missing) and this is an interactive local run:** trigger the first-time setup flow automatically:

1. Tell the user this is first-time setup for the Team Daily Digest
2. Explain they need two Notion IDs - both are the 32-char hex string from Notion page URLs (`notion.so/<this-id>`)
3. Ask for the **Notion config page ID** (the page with keywords and partner patterns)
4. Ask for the **Notion database ID** (the database where digest pages are written)
5. Create the directory `~/.config/team-digest/` if it doesn't exist
6. Write `~/.config/team-digest/config.json` with this structure:

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

7. If the config file already exists with other digest keys, merge the new `team-digest` key into the existing file rather than overwriting it.
8. Confirm the config was created and tell the user they can now run `/team-digest` to produce their first digest.
9. **Stop here** (do not continue to the digest pipeline on first-time setup).

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

The database `notion-fetch` call to discover the internal `data_source_id` is deferred to AFTER Step 0.5 below, because that call requires the Notion MCP schemas to be loaded first.

**GitHub token resolution:** the `lib/resolve-gh-token.sh` helper resolves which GitHub token to use, in this priority order: (1) `$GH_TOKEN` or `$GITHUB_TOKEN` env vars, (2) the `github.token` field in `config.json`, (3) the token stored by `gh auth login`. If (2) wins, the helper exports `GH_TOKEN` for the run; all existing `gh search` / `gh api` calls in the lib helpers transparently pick it up. Scopes needed for iteration 1: `public_repo` + `read:discussion` (use `repo` instead of `public_repo` for private orgs).

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
- Filter to pages created on the previous calendar day using `created_date_range: { start_date: "<DATE_LABEL>", end_date: "<DATE_LABEL>" }`
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

**Phase A - Fetch each favorite (parallel):**

1. Call `notion-fetch` with the URL or ID. The MCP tool accepts both forms; no need to parse the 32-char hex from the URL manually.
2. From the response, read `last_edited_time` (an ISO-8601 UTC timestamp on the page object) AND the page's canonical `url` field. Add the `{page_id, title, url}` tuple to the Notion Link Registry immediately.
3. Compare the date portion of `last_edited_time` (in UTC) against `$DATE_LABEL`. If they match, the favorite itself was edited during the digest window - mark it as a "qualifying parent."
4. If the page was archived (response includes `archived: true`), skip it silently along with any descent.
5. If `notion-fetch` returns an error (page not found, page deleted, user lacks permission), log a one-line failure note like `(Favorite <ID>: not accessible - check the URL or your access)` and continue.
6. **Collect child page references** from the response content. The Notion MCP enhanced-Markdown response renders child pages as `<page url="..." title="..."/>` tags or as Notion `@mention`-style page links inside the page body. Extract every Notion page URL or ID found inside the favorite's content. These are the candidates for descent.

Emit all favorite `notion-fetch` calls in one message so they run concurrently.

**Phase B - Descend one level (conditional, parallel, capped):**

**This phase only runs when at least one favorite was marked as a qualifying parent in Phase A** (i.e., its `last_edited_time` date matched `$DATE_LABEL`). If Phase A found zero qualifying parents, skip Phase B entirely and proceed to Phase C with an empty child list. This prevents fetching dozens of child pages from large index favorites on days when nothing is actively being edited.

For each **qualifying parent favorite** (and only those), take its collected child page references and call `notion-fetch` on each in parallel. Apply these limits:

- **Cap at 5 children per favorite.** If a qualifying parent has more than 5 unique child page references, fetch the first 5 and add a one-line note `(<favorite title>: 5-child cap reached, N pages skipped)` to the Favorites section.
- **Single hop only.** Do NOT recurse into the children's children. Loops or deep trees would explode the cost.
- **Deduplicate across favorites.** If two different favorites both link to the same child page, fetch it once.
- **Apply the same `last_edited_time == $DATE_LABEL` filter** to each child. Children not edited that day are silently dropped.
- **Skip archived children silently.** Skip permission-error children with a one-line note in the digest.

**Phase C - Cross-section dedup:**

Track page IDs across all Notion sections. If a page already appeared in the Keyword Monitor (Step 3), still mention it briefly in the Favorites section with a link-back rather than re-summarizing - the user explicitly cares about favorites, so silent dedup hides signal. If a page is BOTH a favorite (or its child) AND a keyword match, prefer the Favorites section and add a `(also matched keywords: ...)` note.

**For each qualifying page (favorite or child, edited on `$DATE_LABEL`):**

- Use the page's canonical URL from the MCP response as the link target.
- Write a 2-4 sentence narrative summary of what changed or what the page contains.
- Add an **Relevance:** sentence explaining why this update matters for the team, using the team profile as the lens.
- Note `last_edited_time`.
- For child pages, note the parent favorite title in the entry: e.g., `[Sub-page Title](url) (under [Parent Favorite](parent-url))`.

**Section-empty fallback:**

If every favorite (and every descended child) was either inaccessible, archived, or not edited on `$DATE_LABEL`, include the Favorites section with a single line: `No favorited pages or their child pages had updates on <DATE_LABEL>.` This distinguishes a successful no-hit scan from a configuration mistake.

**Access model:** the Notion-hosted MCP (the OAuth-based connector Anthropic ships) inherits workspace-wide access from the user's OAuth grant - no per-page sharing required. If a `notion-fetch` returns a "not accessible" error, the cause is almost always one of: (a) the page was deleted or moved out of the user's workspace, (b) the user themselves lacks permission to that page (e.g., a private page in another team's space), or (c) the URL is malformed. Treat permission errors as a real signal worth surfacing in the digest, not as expected setup friction.

### Step 4: Scan Partner Conversations

For each partner pattern from configuration, search the Notion workspace using the `notion-search` MCP tool with `created_date_range: { start_date: "<DATE_LABEL>", end_date: "<DATE_LABEL>" }` to strictly bound results to that UTC day.

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

If any of checks 1-8 fail, fix the draft before proceeding.

### Part B: Quality Scaffold (mandatory - complete after the link checks above)

These three audits are the difference between a digest that reads like a log dump and one a non-technical person can actually use. Complete each one explicitly - state your findings in plain text before moving to Step 5.

#### Quality check A: Diagram audit

For EACH priority repo section, scan the PRs and issues that appeared on `$DATE_LABEL` and check whether any of these triggers fired:

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

**If `$DRY_RUN` is set:** also print `Dry-run output: <SAFETY_PATH>` and stop. Skip the rest of Step 5. (The safety file IS the dry-run output - same content, same path.)

**If `$DRY_RUN` is NOT set:** proceed to create the Notion page. If the `notion-create-pages` call fails (stream timeout, API error, or any other error), tell the user:
> Notion write failed. Assembled content is saved at `<SAFETY_PATH>`. Re-run with:
> `bin/team-digest-run.sh <DATE_LABEL> --from-file <SAFETY_PATH>`
Then stop - do NOT silently retry or write another file.

Create a new page in the Team Daily Digest database using the `notion-create-pages` MCP tool.

**Parent:** `{ "type": "data_source_id", "data_source_id": "<data_source_id discovered in Step 0>" }`

**Properties:**
- Digest Title: `Team Daily Digest - <DATE_LABEL>`
- date:Date:start: `<DATE_LABEL>`
- Digest Type: `Combined`
- Repos Active: `<count of repos with activity>`
- Keywords Matched: `["keyword1", "keyword2", ...]` (JSON array of keywords that had hits)
- Status: `Auto`

**Content** must use Notion-flavored Markdown. Key rules:
- Use `<callout icon="..." color="...">` for callout blocks
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

Read `~/.claude/skills/team-digest/TEMPLATE.md` with the Read tool. It contains the canonical section order, all Notion-flavored syntax blocks, and the Format Rules (Notion API constraints, linking rules, backfill notes). Substitute all `<PLACEHOLDER>` values with the actual data. The "FORMAT RULES" section at the bottom of TEMPLATE.md is a human reference only - do not render it in the Notion page.

#### Executive Summary (mandatory first content block)

Every digest opens with an **Executive Summary** under an `## Executive Summary` heading, immediately after the header callout. Purpose: a reader who only skims this section should leave with the day's headlines.

**Format:**

- 5 to 8 bullet points
- Each bullet is one specific change with stakes - not "lots of activity in X"
- Lead each bullet with a bold callout (the project, repo, or topic) followed by a one-line plain-English statement of what changed and why it matters
- Every bullet links to the relevant section below for drill-down (e.g., the priority-repo section, the release, the Notion page, the partner conversation)
- Cover a mix: priority-repo headlines, releases, major Notion design docs created today, partner conversations of substance, notable Industry News items
- Skip routine maintenance (dep bumps, README touch-ups, test refactors) - the per-section narratives already cover those
- Apply the same Plain-English Description Rules: write for an outsider, lead with the user-visible change, no insider jargon without translation
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

After the Executive Summary, include a `## Top Picks: Notion Pages Worth Reading` section IF AND ONLY IF the day produced at least one Notion page worth highlighting.

**Selection logic:**

1. Take the union of pages found via Notion Keyword Monitor (Step 3) and Favorites Activity (Step 3.5). De-duplicate by page ID.
2. Exclude pages whose title starts with "Team Daily Digest", "Team Weekly Digest", "SA Daily Digest" - the digest's own output should never be in Top Picks.
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
