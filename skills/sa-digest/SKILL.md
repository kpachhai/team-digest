---
name: sa-digest
description: SA Daily Digest - scans GitHub activity, Notion keywords, and partner conversations, writes a combined digest to Notion. Usage - /sa-digest [YYYY-MM-DD | setup | config]
user-invocable: true
---

# SA Daily Digest - Manual Trigger

## Purpose

Manually run the SA Daily Digest pipeline on demand. Scans a specific day's activity (00:00-23:59 UTC) across three data sources and writes a structured summary to the SA Daily Digest Notion database.

**Usage:**
- `/sa-digest` - digest for the previous calendar day (default)
- `/sa-digest 2026-04-20` - digest for a specific date
- `/sa-digest --dry-run` - run the full pipeline but write the markdown to a local file instead of creating the Notion page (safe for refactor validation - does not overwrite an existing daily digest)
- `/sa-digest 2026-04-20 --dry-run` - both date and dry-run
- `/sa-digest setup` - first-time setup or update your Notion IDs
- `/sa-digest config` - show current config (Notion IDs, orgs, keywords)

The flags `--dry-run` and date arg can appear in any order. The dry-run output goes to `/tmp/team-digest-dry-runs/sa-digest-<DATE_LABEL>-v<N>.md`, versioned so repeated runs do not clobber each other. The path is ephemeral on purpose - dry runs are throwaway validation artifacts, not history. If you need to keep one, copy it elsewhere.

Use this when:
- Testing the digest before enabling automation
- Re-running after a failed automated run (use `--dry-run` first if you want to preview without overwriting)
- Running an ad-hoc digest outside the normal schedule
- Backfilling a missed day (e.g., `/sa-digest 2026-04-18`)

This skill also runs from the terminal via `bin/sa-digest-run.sh` in the team-digest repo (or copy/symlink it to `~/.local/bin/`). That entry point uses `claude -p` headlessly with the Notion MCP tools allow-listed - same skill, same output, same `--dry-run` flag.

## Important Runtime Notes

- **DO NOT use `readMcpResource` or `ReadMcpResourceTool`** to fetch Notion markdown specs. The output format is fully defined in this skill. The MCP server name format varies between sessions and will cause errors.
- **DO NOT read persisted tool result files** (the `/tool-results/` paths). Process command output directly within the same Bash command. Persisted files may have prefix lines that break JSON parsing.
- **DO NOT use `cat` to read files then parse them in a separate step.** Always pipe or process in a single command chain.
- **GitHub data fetching uses helpers in `lib/`.** Do not re-implement `gh search prs ... | python3 -c ...` inline. The helper scripts (`fetch-github-prs.sh`, `fetch-github-issues.sh`, `fetch-github-releases.sh`) are the single source of truth for GitHub data extraction. They live at `~/.claude/skills/sa-digest/lib/<helper>.sh` after `setup.sh` / `update.sh` runs.

## Time Window

The digest covers a **single calendar day in UTC** (00:00:00 to 23:59:59 UTC).

**If a date argument is provided** (e.g., `/sa-digest 2026-04-20`), use that date.
**If no argument is provided**, default to the previous calendar day.

This ensures:
- Manual runs at any time of day produce the same result
- Automated morning runs and manual re-runs are consistent
- No activity is missed or double-counted between runs
- Missed days can be backfilled by specifying the date

Compute the window using the `compute-window.sh` helper. Pass the user-provided date arg (if any) as the first positional. The helper validates the format and emits `KEY=VALUE` lines that you can `eval` into your shell:

```bash
eval "$(bash ~/.claude/skills/sa-digest/lib/compute-window.sh "$DATE_ARG")"
# Now $DATE_LABEL, $START, $END are set.
```

If the user did not pass a date arg, invoke the helper with no arg and it defaults to yesterday in UTC. If the helper exits non-zero (invalid date format), surface its stderr to the user and stop.

Use `$START` as the `--updated` filter for GitHub and `$DATE_LABEL` as the `start_date` for Notion searches.

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

The skill argument is a single string after `/sa-digest`. Parse it as zero or more of:

- A `YYYY-MM-DD` date → captured as `$DATE_ARG`
- The literal `--dry-run` → set `$DRY_RUN=1`
- The literal `setup` or `config` → handle as a subcommand (below)

Order does not matter: `/sa-digest 2026-05-04 --dry-run` and `/sa-digest --dry-run 2026-05-04` are equivalent. Anything else is an error.

#### Subcommand: `setup`

If the argument is `setup`, run the interactive setup flow (see below) regardless of whether a config already exists. This lets users update their Notion IDs at any time. After writing the config, confirm success and stop (do not run the digest).

#### Subcommand: `config`

If the argument is `config`, read `~/.config/team-digest/config.json` and display the current `sa-digest` configuration in a readable format: Notion IDs (masked to last 8 chars for brevity), GitHub orgs, priority repos, and default keywords. Then stop.

#### Load Config

Run the helper:

```bash
bash ~/.claude/skills/sa-digest/lib/load-config.sh sa-digest
```

It reads `~/.config/team-digest/config.json`, validates that the `sa-digest` key and required Notion IDs exist, and prints the digest's config object as JSON on stdout. On failure (file missing, key missing, empty IDs) it exits non-zero with a clear message on stderr.

**If the helper exits with status 1 (config file missing) and this is an interactive local run:** trigger the first-time setup flow automatically:

1. Tell the user this is first-time setup for the SA Daily Digest
2. Explain they need two Notion IDs - both are the 32-char hex string from Notion page URLs (`notion.so/<this-id>`)
3. Ask for the **Notion config page ID** (the page with keywords and partner patterns)
4. Ask for the **Notion database ID** (the database where digest pages are written)
5. Create the directory `~/.config/team-digest/` if it doesn't exist
6. Write `~/.config/team-digest/config.json` with this structure:

```json
{
  "sa-digest": {
    "notion": {
      "config_page_id": "<user-provided>",
      "database_id": "<user-provided>"
    },
    "github": {
      "orgs": [
        {
          "name": "hiero-ledger",
          "priority_repos": [
            "hiero-json-rpc-relay",
            "hiero-mirror-node",
            "hiero-consensus-node",
            "hiero-block-node",
            "hiero-improvement-proposals",
            "hiero-contracts",
            "solo",
            "hiero-sdk-js",
            "hiero-mirror-node-explorer"
          ],
          "scan_all": false
        },
        {
          "name": "hashgraph",
          "priority_repos": [
            "hedera-docs",
            "hedera-agent-kit-js",
            "hedera-wallet-connect",
            "hedera-evm-testing",
            "stablecoin-studio",
            "asset-tokenization-studio",
            "guardian"
          ],
          "scan_all": false
        },
        {
          "name": "hedera-dev",
          "priority_repos": [],
          "scan_all": true
        }
      ]
    },
    "defaults": {
      "keywords": [
        "EVM", "smart contracts", "relay", "JSON-RPC",
        "mirror node", "HIP", "Hiero", "consensus", "block node", "SDK"
      ],
      "partner_patterns": [
        "Meeting with", "Call with", "Catch up with", "Deep dive",
        "Sync with", "Check-in with", "Follow up with", "Debrief"
      ]
    }
  }
}
```

7. If the config file already exists with other digest keys (e.g., `eng-digest`), merge the new `sa-digest` key into the existing file rather than overwriting it.
8. Confirm the config was created and tell the user they can now run `/sa-digest` to produce their first digest.
9. **Stop here** (do not continue to the digest pipeline on first-time setup).

If the argument was `setup`, use the same flow above but pre-fill the prompts with existing values so the user can see what's currently set and only change what they need.

#### Normal Config Load (config exists)

The JSON returned by `lib/load-config.sh sa-digest` contains:
- `notion.config_page_id` - the Notion configuration page ID
- `notion.database_id` - the Notion database ID for digest output
- `github.orgs` - array of GitHub organizations to scan, each with:
  - `name` - the org name (e.g., "hiero-ledger")
  - `priority_repos` - repos that get full narrative summaries (can be empty)
  - `scan_all` - whether to scan all repos in the org or only priority repos
- `defaults.*` - fallback values for keywords and partner patterns

Also read the team profile at `~/.config/team-digest/profiles/sa-digest.md` using the Read tool. If the file does not exist, continue without it. The profile describes the team's role, priorities, and what makes activity relevant to them - used to write the **SA Relevance** sections throughout the digest, and its **Project Glossary** drives the first-mention expansion rule (see Plain-English Description Rules in the Style Rules section). If no profile is loaded, fall back to generic relevance heuristics (developer-facing APIs, breaking changes, architecture impacts, partner integration concerns) and explain jargon from your own knowledge.

Then fetch the database page using `notion-fetch` with the `database_id` to discover the internal `data_source_id` (the `collection://...` URL in the response). Extract the data source URL from the `data-source-url` attribute in the response.

### Step 1: Read Notion Configuration

Using the `config_page_id` from the local config, fetch the Notion configuration page using the `notion-fetch` tool.

Extract:
- Keywords list (under the heading "Keywords")
- Partner conversation patterns (under the heading "Title Patterns")
- **Favorites list** (under the heading "Favorites" or "Favorite Pages") - a bullet list of Notion page URLs the user wants to monitor. The Notion API does not expose a user's sidebar Favorites, so this list is the user-curated equivalent: pages they care about regardless of keyword match. Each bullet is a URL like `https://www.notion.so/Page-Title-32hex` or just the 32-char hex page ID. Empty/missing section means no favorites are configured - skip Step 3.5.
- **Track Pages Created By email** (under the heading "Track Pages Created By" or "Email") - a single email address (or list, one per bullet) of the Notion users whose newly-created pages should be surfaced in the digest. This drives Step 3.6: pages created on the digest day where `created_by.person.email` matches one of these emails. Empty/missing section means skip Step 3.6.

GitHub org and repo configuration comes from `config.json` (the `github.orgs` array), not from the Notion config page. This keeps structural config (which orgs/repos to scan) separate from frequently-changing settings (keywords, patterns, favorites, created-by emails).

If the Notion config page is unreachable, fall back to the `defaults` section from the local config file. Favorites and Track-Pages-Created-By have no `defaults` fallback - if the config page is unreachable, skip Step 3.5 and Step 3.6 entirely with a one-line note.

### Step 2: Scan GitHub Activity

**GitHub authentication:** Before running any `gh` command, check authentication once:

```bash
gh auth status 2>/dev/null && echo "authed" || echo "not authed"
```

- If authed: proceed normally. The terminal entry point (`bin/sa-digest-run.sh`), cron, and launchd all inherit the user's local `gh` auth, so this is the expected path.
- If not authed: surface an actionable error to the user (`Run 'gh auth login' before running the digest.`) and stop. Without auth, `gh search` either refuses or hits a 60 req/hour rate limit that produces partial digests; failing fast is better than producing a half-empty digest.

Scan **each org** from `config.github.orgs` for activity during the target date by calling the helper scripts. Parallelize across orgs by emitting multiple Bash tool calls in a single message.

**For each org, invoke these three helpers in parallel:**

```bash
bash ~/.claude/skills/sa-digest/lib/fetch-github-prs.sh      <org> "$START"
bash ~/.claude/skills/sa-digest/lib/fetch-github-issues.sh   <org> "$START"
bash ~/.claude/skills/sa-digest/lib/fetch-github-releases.sh <org> "$START"
```

Each helper writes a plain-text summary to stdout. PR and issue helpers group by repo with `## <repo> (<N>)` headers, then per-item lines with `[STATE] #<number> <title>`, author handle, URL, and a 200-char description excerpt. The releases helper emits one line per release: `<repo>: <tag> - <name> (<YYYY-MM-DD>) <html_url>`.

If a helper exits non-zero (e.g., the org is unreachable or `gh` rate-limit hit), log the failure inline in the digest as `(<org>: PR scan failed - <message>)` and continue with the next source. Do not abort the entire digest on one source failure - per the partial-digest rule.

**Critical: do not save helper output to intermediate files. Capture stdout into the conversation context directly so the narrative-writing step can reference it.**

**Output structure - organize by org, then by priority:**

For each org in `config.github.orgs`:
- **Priority repos** (listed in `priority_repos`): Write synthesized narrative summaries - NOT bulleted PR lists. Group related PRs by theme and describe the collective work in 2-4 paragraphs. **Whenever you mention any PR, issue, release, or repo, it MUST be a markdown link** (see Linking Rules below). When summarizing a batch of related PRs, link the repo as the primary anchor AND link any individually-significant PRs you call out (breaking change, major feature, hotfix). After the narrative, add a **SA Relevance:** paragraph using the loaded team profile as your guide - the profile describes the team's role, what they care about, and what "relevant" means for them specifically. If no profile was loaded, fall back to: does this affect developer-facing APIs or SDKs? Does it impact partner integrations or architecture decisions? Does it affect EVM compatibility? Is there a breaking change developers should know about? Could it inform a technical design recommendation? If the activity represents an architectural change (component split/merge, service restructuring, data flow change, before/after pattern), add a Mermaid diagram after the narrative - use `graph TD` with `direction LR` subgraphs for a square layout; keep all node labels on a single line (no `\n` in labels). One diagram per repo maximum; skip if nothing structural happened.
- **Other repos** (if `scan_all` is true, or for orgs with no priority repos): Build a summary table that includes **every repo with at least one PR, issue, or release in the date window**. No silent drops, no aggregation across repos. One row per repo. The "notable activity" column is plain-English: see the Plain-English Description Rules below.
- **Orgs with no priority repos** (e.g., `hedera-dev`): Show all repos in the summary table per the rule above; no narrative section.

The digest should group output under org-level headers:

```
# hiero-ledger

## Priority Repos
(narrative summaries for each priority repo with activity)

## Other Active Repos
(summary table - every repo with activity in the date window appears here)

# hashgraph

## Priority Repos
(narrative summaries)

## Other Active Repos
(summary table)

# hedera-dev

## Other Active Repos
(summary table - all repos with activity; no priority repos defined for this org)
```

If scanning an org fails, note the failure and continue with the next org.

### Step 2.5: Scan Industry News (RSS feeds + commit-watching for spec sets)

This step covers public/external content the SA team should be aware of - blog posts, ecosystem announcements, EIP changes. Configured via the `rss_feeds` array in `config.json` (already loaded by `lib/load-config.sh` in Step 0).

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
bash ~/.claude/skills/sa-digest/lib/fetch-rss.sh "<url>" "$DATE_LABEL"

# GitHub commit-watching - parse <owner>/<repo>[/<path>] from the github:// URL:
bash ~/.claude/skills/sa-digest/lib/fetch-gh-commits.sh "<owner>/<repo>" "$DATE_LABEL" "<path-or-empty>"
```

Each helper returns a JSON array of items dated to `$DATE_LABEL`. Empty arrays (`[]`) are valid - that source had no items that day. Helper failures (network issue, malformed XML, gh rate limit) result in `[]` plus a stderr WARN line; do not abort the digest.

**For each non-empty result, write narrative output:**

- Group by the entry's `category` (e.g., all `hedera` items together, all `ethereum` items together, all `eips` items together).
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
- Filter to pages created on the previous calendar day using `created_date_range: { start_date: "<DATE_LABEL>" }`
- Set `page_size: 10` and `max_highlight_length: 300`

Run keyword searches in parallel batches (2-3 keywords per search query to reduce API calls).

**Deduplication:** Track page IDs across all keyword searches. Each page appears only once in the digest with all matching keywords listed.

**Exclusions:** Skip any page whose title starts with "SA Daily Digest" (our own output).

For each unique page found:
- Fetch full page content using the `notion-fetch` MCP tool
- Write a narrative summary explaining what the page contains
- List which keywords matched
- Add a "SA relevance" note explaining why this matters for the SA team

If Notion keyword scanning fails, note the failure and continue.

### Step 3.5: Scan Notion Favorites (with one-level child descent)

This step covers the user's curated list of "Favorites" pages - documents they care about regardless of keyword match - PLUS one level of descent into pages those favorites link to. The Notion REST API does not expose a user's sidebar Favorites, so the list comes from the **Favorites** section of the Notion config page (loaded in Step 1).

**If no Favorites list was extracted from the config page:** skip this step entirely. Do not include a Favorites section in the output.

**Phase A - Fetch each favorite (parallel):**

1. Call `notion-fetch` with the URL or ID. The MCP tool accepts both forms; no need to parse the 32-char hex from the URL manually.
2. From the response, read `last_edited_time` (an ISO-8601 UTC timestamp on the page object).
3. Compare the date portion of `last_edited_time` (in UTC) against `$DATE_LABEL`. If they match, the favorite itself was edited during the digest window - mark it as a "qualifying parent."
4. If the page was archived (response includes `archived: true`), skip it silently along with any descent.
5. If `notion-fetch` returns an error (page not found, page deleted, user lacks permission), log a one-line failure note like `(Favorite <ID>: not accessible - check the URL or your access)` and continue.
6. **Collect child page references** from the response content. The Notion MCP enhanced-Markdown response renders child pages as `<page url="..." title="..."/>` tags or as Notion `@mention`-style page links inside the page body. Extract every Notion page URL or ID found inside the favorite's content. These are the candidates for descent.

Emit all favorite `notion-fetch` calls in one message so they run concurrently.

**Phase B - Descend one level (parallel, capped):**

For each favorite, take its collected child page references and call `notion-fetch` on each in parallel. Apply these limits:

- **Cap at 50 children per favorite.** If a favorite has more than 50 unique child page references (e.g., a giant index page), fetch the first 50 and add a one-line note `(<favorite title>: 50-child cap reached, N pages skipped)` to the Favorites section.
- **Single hop only.** Do NOT recurse into the children's children. Loops or deep trees would explode the cost.
- **Deduplicate across favorites.** If two different favorites both link to the same child page, fetch it once.
- **Apply the same `last_edited_time == $DATE_LABEL` filter** to each child. Children not edited that day are silently dropped.
- **Skip archived children silently.** Skip permission-error children with a one-line note in the digest.

**Phase C - Cross-section dedup:**

Track page IDs across all Notion sections. If a page already appeared in the Keyword Monitor (Step 3), still mention it briefly in the Favorites section with a link-back rather than re-summarizing - the user explicitly cares about favorites, so silent dedup hides signal. If a page is BOTH a favorite (or its child) AND a keyword match, prefer the Favorites section and add a `(also matched keywords: ...)` note.

**For each qualifying page (favorite or child, edited on `$DATE_LABEL`):**

- Use the page's canonical URL from the MCP response as the link target.
- Write a 2-4 sentence narrative summary of what changed or what the page contains.
- Add an **SA Relevance:** sentence explaining why this update matters for the SA team, using the team profile as the lens.
- Note `last_edited_time`.
- For child pages, note the parent favorite title in the entry: e.g., `[Sub-page Title](url) (under [Parent Favorite](parent-url))`.

**Section-empty fallback:**

If every favorite (and every descended child) was either inaccessible, archived, or not edited on `$DATE_LABEL`, include the Favorites section with a single line: `No favorited pages or their child pages had updates on <DATE_LABEL>.` This distinguishes a successful no-hit scan from a configuration mistake.

**Access model:** the Notion-hosted MCP (the OAuth-based connector Anthropic ships) inherits workspace-wide access from the user's OAuth grant - no per-page sharing required. If a `notion-fetch` returns a "not accessible" error, the cause is almost always one of: (a) the page was deleted or moved out of the user's workspace, (b) the user themselves lacks permission to that page (e.g., a private page in another team's space), or (c) the URL is malformed. Treat permission errors as a real signal worth surfacing in the digest, not as expected setup friction.

### Step 3.6: Scan Pages You Created

This step surfaces Notion pages **you** personally created on the digest day - useful for catching new strategy docs, one-off notes, or fresh meeting pages that don't match the configured keywords or partner patterns.

**If no email was extracted from the "Track Pages Created By" config heading:** skip this step entirely. Do not include a Pages I Created section in the output.

**Process:**

1. Use `notion-search` with `query_type: "internal"`, `created_date_range: { start_date: "<DATE_LABEL>" }`, and an empty query string (or a generic term like the workspace name). Set `page_size: 50`.
2. From results, filter to those where `created_by.person.email` (or equivalent field on the response) matches any email in the configured list.
3. For each match, call `notion-fetch` to get the page content (parallelize).
4. Apply cross-section dedup against Keyword, Partner, and Favorites sections - if a page already appeared elsewhere, mention it briefly in this section with a link-back rather than re-summarizing.

**Output for each match:**

- Page title as a markdown link (canonical URL from the MCP response)
- 1-3 sentence summary of what the page is for
- A **SA Relevance:** sentence using the team profile as the lens (or "Personal note - no team context inferred." if the page looks personal)
- The `created_at` timestamp

**Section-empty fallback:**

If the email is configured but no matching pages were created on `$DATE_LABEL`, include the section with a single line: `No new pages created by <email> on <DATE_LABEL>.` This signals that the scan ran.

If `notion-search` fails entirely, note the failure inline and continue to Step 4.

### Step 4: Scan Partner Conversations

For each partner pattern from configuration, search the Notion workspace using the `notion-search` MCP tool with `created_date_range` filter for the previous calendar day.

**Deduplication:** Skip pages already covered in the keyword monitor section. Track by page ID.

For each meeting/conversation page found:
- Fetch full page content using the `notion-fetch` MCP tool
- Identify partner/company names discussed
- **Group results by company/partner** (not by page)
- Summarize key discussion points
- Extract and list action items with checkboxes
- Note any follow-ups or deadlines mentioned

If partner scanning fails, note the failure and continue.

### Step 4.5: Pre-Write Link Audit (mandatory)

Before writing to Notion, scan the assembled digest content one final time. Verify:

1. **Every repo name is a markdown link.** Search the draft for bare repo names (e.g., `hedera-docs`, `solo`, `hiero-mirror-node`). If a repo is mentioned without `[name](https://github.com/<org>/<name>)`, fix it.
2. **Every PR/issue number is a link.** Search for bare `#<number>` patterns. Every match must be `[#<number>](<url>)` with the actual URL.
3. **Every release tag is a link.** Search for bare version strings like `v1.2.3` in release contexts. Each must link to the GitHub release page.
4. **Every Notion page title is a link.** In the Keyword Monitor, Favorites Activity, Pages I Created, and Partner Conversations sections, every page title must be `[<title>](<notion-url>)` using the URL from the MCP response. In Favorites Activity specifically, every child-page entry must also link its parent favorite (e.g., `(under [Parent Title](parent-url))`).
5. **Every GitHub user mention is a link.** Search for bare `@<handle>` patterns - each must link to `https://github.com/<handle>`.
6. **First-mention expansions are present.** Spot-check that any project name, component, or acronym mentioned for the first time in a section is followed by a 3-7 word expansion (per the Plain-English Description Rules).
7. **No `\n` inside Mermaid labels.** Search every Mermaid block (delimited by ` ```mermaid ` and ` ``` `) for the literal two-character sequence `\n` inside any node label. Mermaid line breaks do NOT render reliably in Notion - text after the `\n` is silently cut off, leaving readers with truncated diagrams. If a label is too long for one line, shorten it (drop the parenthetical, abbreviate, use a single key word) instead of splitting it. This rule is non-negotiable: a truncated diagram is worse than a verbose one because the reader does not know they are missing context.
8. **Every Industry News title or commit SHA is a link.** Items in the Industry News section must each be `[<title>](<link>)` (RSS) or `[<short-sha>](<commit-url>)` (commit). No bare titles or SHAs. Summaries must have HTML tags stripped - search the section for `<p>`, `<img>`, `<a `, and similar; if any are present, render the prose as plain text instead.

If any of these checks fail, fix the draft before proceeding to Step 5. Bare entity references, unexplained jargon, and broken Mermaid diagrams are the three most common readability bugs - this audit is the gate that prevents all three from reaching Notion.

### Step 5: Write the Combined Digest

**If `$DRY_RUN` is set:** do NOT call `notion-create-pages`. Instead, write the assembled markdown content (everything inside the **Content structure** block below, with `<DATE_LABEL>` and counts substituted) to a versioned local file:

```bash
DRY_DIR="/tmp/team-digest-dry-runs"
mkdir -p "$DRY_DIR"
# Find the next free version number for this date
N=1
while [ -f "$DRY_DIR/sa-digest-${DATE_LABEL}-v${N}.md" ]; do
  N=$((N + 1))
done
DRY_PATH="$DRY_DIR/sa-digest-${DATE_LABEL}-v${N}.md"
# Use the Write tool (not echo) to write the assembled content to $DRY_PATH.
```

Use the `Write` tool to write the content (no Notion-flavored `<callout>` / `<details>` / `<table header-row>` tags - convert them to plain Markdown for the file: blockquote for callouts, headings for sections, GFM tables for tables). The dry-run output is meant for human review and diffing, not Notion. Then echo the path to the user (`Dry-run output: <path>`) and stop. Skip the rest of Step 5.

**If `$DRY_RUN` is NOT set:** create a new page in the SA Daily Digest database using the `notion-create-pages` MCP tool.

**Parent:** `{ "type": "data_source_id", "data_source_id": "<data_source_id discovered in Step 0>" }`

**Properties:**
- Digest Title: `SA Daily Digest - <DATE_LABEL>`
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

**Content structure:**

```
<callout icon="📊" color="blue_bg">
**SA Daily Digest** | <DATE_LABEL>
<N> repos active | <N> PRs updated | <N> issues updated | <N> releases
Data window: <DATE_LABEL> 00:00 - 23:59 UTC
</callout>

---

# <org-name> (e.g. hiero-ledger)

## Priority Repos

### [<repo-name>](https://github.com/<org>/<repo>)
<2-4 paragraph synthesized narrative. Every PR, issue, release, repo, or @handle reference inside the narrative is a markdown link. First mention of any project/component/acronym gets a 3-7 word plain-English expansion. See Linking Rules and Plain-English Description Rules in the Style Rules section.>
<Mermaid diagram if architectural change occurred>

**SA Relevance:** <why this matters to the Solutions Architect team - integration impact, architecture decisions, SDK changes, partner-facing APIs, breaking changes>

---

(repeat for each priority repo with activity)

## Other Active Repos

<table header-row="true">
<tr><td>Repo</td><td>Notable Activity</td></tr>
<tr><td>[<repo-name>](https://github.com/<org>/<repo>)</td><td><plain-English summary - what changed, what it affects, why it matters - with PR/issue numbers as links></td></tr>
</table>

(every repo with at least one PR/issue/release in the date window MUST appear; no aggregation, no silent drops)

---

(repeat org section for each org)

# Releases

<releases listed with linked tag names: [v1.2.3](release-url) - <repo> - <plain-English release summary>, or "No new releases">

---

# Industry News

<grouped by category. Each category has a `## <category>` subheading and a bullet list of items - RSS posts as `- [title](link) - 1-2 sentence summary`, GitHub commits as `- [short-sha](commit-url): subject by author`. Strip HTML tags from RSS summaries. Omit the entire section if every feed returned 0 items for DATE_LABEL.>

---

# Notion Keyword Monitor

<narrative summaries of keyword-matched pages>

---

# Favorites Activity

<for each favorited page (and any child page found one level deep, capped at 50 per favorite) edited on DATE_LABEL: 2-4 sentence narrative summary, page title as a markdown link, what changed, when (last_edited_time), and an SA Relevance line. Note child pages with their parent favorite, e.g. `[Child Title](url) (under [Parent](parent-url))`. Omit non-updated pages. If the favorites list is empty or unreachable, omit this section. If favorites are configured but had no updates, write: "No favorited pages or their child pages had updates on <DATE_LABEL>.">

---

# Pages I Created

<for each page created on DATE_LABEL by an email matching the "Track Pages Created By" config: page title as a markdown link, 1-3 sentence summary, SA Relevance, created_at timestamp. Omit if no email is configured. If email is configured but no matching pages: "No new pages created by <email> on <DATE_LABEL>.">

---

# Partner Conversations

<grouped by company with discussion summaries and action items>

---

<callout icon="ℹ️" color="gray_bg">
**Auto-generated** by SA Daily Digest | Scanned <N> repos in <org> | Data window: <DATE_LABEL> 00:00 - 23:59 UTC
</callout>
```

## Style Rules

### Synthesis

- **Synthesize, don't list** - describe what the team is collectively accomplishing, not individual PR titles. "The team is decomposing the monolithic operations facet into single-responsibility components" beats listing 14 PRs.
- After each priority repo narrative, add a **SA Relevance:** paragraph. Use the team profile loaded in Step 0 to drive this - the profile specifies what the team cares about, their priorities, and content opportunity triggers. If no profile exists, use generic heuristics.
- Add a Mermaid diagram for architectural changes - component splits, service restructuring, data flow changes. **Keep every node label on a single line - never use `\n` inside labels.** Notion silently truncates Mermaid text after a `\n`, leaving readers with broken diagrams. If a label is too long, shorten it (drop parentheticals, abbreviate, use a single key word). Use `graph TD` with `direction LR` subgraphs for square layout. One diagram per repo max.
- Surface cross-repo connections when relevant (e.g., a `solo` bug that also affects `hiero-json-rpc-relay`)
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
- For Notion pages found via `notion-search` or `notion-fetch`, the response includes a `url` (or `public_url`) field. Use that exact value.

### Plain-English Description Rules

Every PR/repo/release summary must answer three questions in language a developer who doesn't work on that specific project can understand:

1. **What changed?** (the action - "deprecated", "added", "split", "renamed")
2. **What does it affect?** (the surface area - an API, an SDK, a deployment tool)
3. **Why does it matter?** (the consequence for SA work - migration, partner advisory, integration impact)

**First-mention expansion rule:** the first time you name any project, internal component, or acronym in a section, immediately follow it with a 3-7 word plain-English expansion. Examples:
- `[solo](https://github.com/hiero-ledger/solo)`, the local Hiero/Hedera dev network deployment tool
- `HieroClient`, the V3 SDK top-level connection object replacing legacy `Client`
- `MethodDescriptor`, the gRPC method metadata wrapper used for SDK portability
- `HTS`, Hedera Token Service, the native token API on the consensus network

The expansions come from two sources, in priority order:
1. The **Project Glossary** section of the team profile (loaded in Step 0). If a glossary entry exists, use it verbatim.
2. Your own knowledge of the project, written in plain English at the level of detail above.

If you cannot confidently expand a term, that's a signal to skip the term entirely or hedge ("an internal SDK abstraction") rather than parrot the jargon.

**Anti-examples (do NOT write summaries like these):**
- ❌ "Deprecation notice PR #1328 opened - local-node being formally deprecated in favor of solo" (no link, "solo" not expanded)
- ❌ "V3 SDK spec sprint: client namespace with HieroClient and Operator (#230)" (no link, every term unexplained)

**Good examples:**
- ✅ "[#1328](url): [hiero-local-node](url) is being formally deprecated in favor of [solo](url), the local Hiero/Hedera dev network deployment tool. Partners using local-node for testing should plan a migration."
- ✅ "Active spec work in [#230](url) defines a new `client` namespace with `HieroClient` (the V3 top-level connection object replacing legacy `Client`) and `Operator` (the transaction signing and billing context). Partners writing V3-targeted SDK code will see breaking changes here."

## Configuration

All settings are read from `~/.config/team-digest/config.json` under the `sa-digest` key:

```json
{
  "sa-digest": {
    "notion": {
      "config_page_id": "<32-char hex from Notion config page URL>",
      "database_id": "<32-char hex from Notion database URL>"
    },
    "github": {
      "orgs": [
        {
          "name": "hiero-ledger",
          "priority_repos": ["hiero-json-rpc-relay", "hiero-mirror-node", "..."],
          "scan_all": true
        },
        {
          "name": "hashgraph",
          "priority_repos": ["hedera-docs", "hedera-agent-kit-js", "..."],
          "scan_all": true
        },
        {
          "name": "hedera-dev",
          "priority_repos": [],
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

The config is created automatically on first run (`/sa-digest`) or manually via `/sa-digest setup`. To update Notion IDs later, run `/sa-digest setup` again. To view current config, run `/sa-digest config`.

## Running headlessly (terminal / cron / launchd)

The `bin/sa-digest-run.sh` script in the team-digest repo is the headless entry point. It invokes `claude -p "/sa-digest [args]"` with the necessary Notion MCP tools allow-listed. Use it for:

- **Local terminal runs:** `~/repos/.../team-digest/bin/sa-digest-run.sh 2026-05-04`
- **launchd / cron:** schedule `bin/sa-digest-run.sh` (or a copy at `~/.local/bin/`) - see `docs/scheduling.md` for the launchd plist
- **CI / GitHub Actions self-hosted runners:** invoke `bin/sa-digest-run.sh` from a workflow

The same skill, the same config file (`~/.config/team-digest/config.json`), and the same `--dry-run` flag work in every context. There is no separate "routine" code path to maintain.
