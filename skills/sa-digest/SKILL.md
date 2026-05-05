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
- `/sa-digest setup` - first-time setup or update your Notion IDs
- `/sa-digest config` - show current config (Notion IDs, orgs, keywords)

Use this when:
- Testing the digest before enabling automation
- Re-running after a failed automated run
- Running an ad-hoc digest outside the normal schedule
- Backfilling a missed day (e.g., `/sa-digest 2026-04-18`)

## Important Runtime Notes

- **DO NOT use `readMcpResource` or `ReadMcpResourceTool`** to fetch Notion markdown specs. The output format is fully defined in this skill. The MCP server name format varies between sessions and will cause errors.
- **DO NOT read persisted tool result files** (the `/tool-results/` paths). Process `gh` CLI JSON output directly within the same Bash command using `python3 -c` inline scripts. Persisted files may have prefix lines that break JSON parsing.
- **DO NOT use `cat` to read files then parse them in a separate step.** Always pipe or process in a single command chain.

## Time Window

The digest covers a **single calendar day in UTC** (00:00:00 to 23:59:59 UTC).

**If a date argument is provided** (e.g., `/sa-digest 2026-04-20`), use that date.
**If no argument is provided**, default to the previous calendar day.

This ensures:
- Manual runs at any time of day produce the same result
- Automated morning runs and manual re-runs are consistent
- No activity is missed or double-counted between runs
- Missed days can be backfilled by specifying the date

Compute the window at the start:
```bash
# If user provided a date argument, use it; otherwise use yesterday
TARGET_DATE="${1:-}"  # The argument passed to the skill, if any

if [ -n "$TARGET_DATE" ]; then
  # Validate format: YYYY-MM-DD
  if echo "$TARGET_DATE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    DATE_LABEL="$TARGET_DATE"
  else
    echo "ERROR: Invalid date format '$TARGET_DATE'. Use YYYY-MM-DD (e.g., 2026-04-20)"
    exit 1
  fi
else
  # Default to previous calendar day
  DATE_LABEL=$(date -u -v-1d +%Y-%m-%d 2>/dev/null || date -u -d 'yesterday' +%Y-%m-%d)
fi

START="${DATE_LABEL}T00:00:00Z"
END="${DATE_LABEL}T23:59:59Z"
```

Use `$START` as the `--updated` filter for GitHub and `$DATE_LABEL` as the `start_date` for Notion searches.

**Important:** When a date argument is provided, check the skill argument/input for a YYYY-MM-DD string and use it as `DATE_LABEL`. The bash snippet above is illustrative; adapt the logic to however the date reaches you (skill argument, user message, etc.).

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

### PRE-FLIGHT: Scan for Inline Config (DO THIS FIRST, BEFORE ANYTHING ELSE)

**This step MUST run before subcommand handling and before any filesystem access.**

Routines and remote triggers run on Anthropic's servers with no access to local files. When running in that context, config is embedded directly in this prompt between these markers:

```
<!-- SA-DIGEST-CONFIG -->
{ ... JSON ... }
<!-- /SA-DIGEST-CONFIG -->

<!-- SA-DIGEST-PROFILE -->
... markdown ...
<!-- /SA-DIGEST-PROFILE -->
```

**Action:** Scan the full text of this prompt right now for those exact marker strings.

- **If `<!-- SA-DIGEST-CONFIG -->` is present:** extract the JSON between the open and close tags, parse it, and store it as `inline_config`. Extract the `sa-digest` key from that JSON. If `<!-- SA-DIGEST-PROFILE -->` markers are also present, extract the text between them and store it as `inline_profile`. Set `config_source = "inline"`. Do NOT read from the filesystem.
- **If the markers are absent:** set `config_source = "filesystem"`. Continue to Step 0 below.

This pre-flight scan happens regardless of subcommand. Even `config` and `setup` subcommands need to know whether they're running inline or filesystem mode.

---

### Step 0: Handle Subcommands and Load Config

#### Subcommand: `setup`

If the argument is `setup`, run the interactive setup flow (see below) regardless of whether a config already exists. This lets users update their Notion IDs at any time. After writing the config, confirm success and stop (do not run the digest).

#### Subcommand: `config`

If the argument is `config` and `config_source == "inline"`, display the inline config values. If `config_source == "filesystem"`, read `~/.config/team-digest/config.json` and display the current `sa-digest` configuration in a readable format: Notion IDs (masked to last 8 chars for brevity), GitHub orgs, priority repos, and default keywords. Then stop.

#### Load Config

If `config_source == "inline"`: config is already loaded from the pre-flight step. Skip filesystem reads.

If `config_source == "filesystem"`: read `~/.config/team-digest/config.json` using the Read tool.

**If the config file does not exist or is missing the `sa-digest` key**, and `config_source == "filesystem"`:

- If this appears to be a routine/automated context (no interactive user, no terminal): **ABORT** with this message: "ERROR: No config found. This appears to be a routine run but no inline config block was found in the prompt and `~/.config/team-digest/config.json` does not exist on this server. Embed your config between `<!-- SA-DIGEST-CONFIG -->` markers at the end of the routine prompt. See the Appendix in the skill definition." Do not proceed further.
- If this is an interactive local run: run the first-time setup flow automatically:

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

Parse the `sa-digest` key from the config to get:
- `notion.config_page_id` - the Notion configuration page ID
- `notion.database_id` - the Notion database ID for digest output
- `github.orgs` - array of GitHub organizations to scan, each with:
  - `name` - the org name (e.g., "hiero-ledger")
  - `priority_repos` - repos that get full narrative summaries (can be empty)
  - `scan_all` - whether to scan all repos in the org or only priority repos
- `defaults.*` - fallback values for keywords and partner patterns

Also read the team profile at `~/.config/team-digest/profiles/sa-digest.md` using the Read tool (skip if inline profile was already loaded above). If the file does not exist and no inline profile was provided, continue without it. The profile describes the team's role, priorities, and what makes activity relevant to them - used to write the **Relevance** sections throughout the digest. If no profile is loaded, fall back to generic relevance heuristics (developer-facing APIs, breaking changes, architecture impacts, partner integration concerns).

Then fetch the database page using `notion-fetch` with the `database_id` to discover the internal `data_source_id` (the `collection://...` URL in the response). Extract the data source URL from the `data-source-url` attribute in the response.

### Step 1: Read Notion Configuration

Using the `config_page_id` from the local config, fetch the Notion configuration page using the `notion-fetch` tool.

Extract:
- Keywords list (under "Keywords")
- Partner conversation patterns (under "Title Patterns")

GitHub org and repo configuration comes from `config.json` (the `github.orgs` array), not from the Notion config page. This keeps structural config (which orgs/repos to scan) separate from frequently-changing settings (keywords, patterns).

If the Notion config page is unreachable, fall back to the `defaults` section from the local config file.

### Step 2: Scan GitHub Activity

**GitHub authentication:** Before running any `gh` command, check authentication status:

```bash
gh auth status 2>/dev/null
```

- If that succeeds, `gh` is already authenticated - proceed normally.
- If it fails (typical in routine/remote-trigger context), check whether `github_token` is set in the loaded config. If it is, export it before all subsequent `gh` commands:

```bash
export GITHUB_TOKEN="<config.github_token value>"
```

- If neither is available, note in the digest footer: "GitHub scanned with no auth token - core API rate limit is 60 req/hour and may have been exhausted; issues and releases may be incomplete." Then proceed anyway - PR searches (search API) will still work even when the core API is rate-limited.

Scan **each org** from `config.github.orgs` for activity during the target date.

**Critical: Process JSON output directly in each Bash command. Do not save to intermediate files.**

**For each org**, run these commands (parallelize across orgs when possible):

1. **PRs** - run this as a single Bash command that outputs a human-readable summary:
   ```bash
   gh search prs --owner=<org-name> --updated=">=$START" --json repository,title,state,author,number,body,url,labels --limit 100 | python3 -c "
   import json, sys
   data = json.load(sys.stdin)
   repos = {}
   for pr in data:
       repo = pr['repository']['name']
       if repo not in repos: repos[repo] = []
       repos[repo].append(pr)
   for repo in sorted(repos.keys()):
       print(f'## {repo} ({len(repos[repo])} PRs)')
       for pr in repos[repo]:
           body = (pr.get('body') or '')[:200].replace(chr(10), ' ').strip()
           print(f'  [{pr[\"state\"].upper()}] #{pr[\"number\"]} {pr[\"title\"]}')
           print(f'    Author: @{pr[\"author\"][\"login\"]}')
           print(f'    URL: {pr[\"url\"]}')
           if body: print(f'    Description: {body}')
           print()
   "
   ```

2. **Issues** - same pattern as PRs but with `gh search issues`.

3. **Releases** - check all org repos:
   ```bash
   gh api orgs/<org-name>/repos --paginate --jq '.[].name' | while read repo; do
     gh api "repos/<org-name>/$repo/releases" --jq "[.[] | select(.published_at >= \"$START\")] | .[] | \"$repo: \(.tag_name) - \(.name // \"no title\") (\(.published_at[:10]))\"" 2>/dev/null
   done
   ```

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
4. **Every Notion page title is a link.** In the Keyword Monitor and Partner Conversations sections, every page title must be `[<title>](<notion-url>)` using the URL from the MCP response.
5. **Every GitHub user mention is a link.** Search for bare `@<handle>` patterns - each must link to `https://github.com/<handle>`.
6. **First-mention expansions are present.** Spot-check that any project name, component, or acronym mentioned for the first time in a section is followed by a 3-7 word expansion (per the Plain-English Description Rules).

If any of these checks fail, fix the draft before proceeding to Step 5. Bare entity references and unexplained jargon are the two most common readability bugs - this audit is the gate that prevents both from reaching Notion.

### Step 5: Write the Combined Digest to Notion

Create a new page in the SA Daily Digest database using the `notion-create-pages` MCP tool.

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

---

# Notion Keyword Monitor

<narrative summaries of keyword-matched pages>

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
- Add a Mermaid diagram for architectural changes - component splits, service restructuring, data flow changes. Keep labels on single lines. Use `graph TD` with `direction LR` subgraphs for square layout. One diagram per repo max.
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

## Appendix: Inline Config for Routines and Remote Triggers

When running as a **Claude Code Routine** or **Remote Trigger**, the skill has no access to local files. Append your config and (optionally) your team profile directly after the skill content using these markers:

```
<!-- SA-DIGEST-CONFIG -->
{
  "sa-digest": {
    "notion": {
      "config_page_id": "<your-config-page-id>",
      "database_id": "<your-database-id>"
    },
    "github": {
      "github_token": "<optional - GitHub PAT with public_repo read scope; required for full coverage when running as a routine>",
      "orgs": [
        {
          "name": "hiero-ledger",
          "priority_repos": ["hiero-json-rpc-relay", "hiero-mirror-node", "..."],
          "scan_all": false
        }
      ]
    },
    "defaults": {
      "keywords": ["EVM", "smart contracts", "relay", "JSON-RPC", "mirror node", "HIP", "Hiero", "consensus", "block node", "SDK"],
      "partner_patterns": ["Meeting with", "Call with", "Catch up with", "Deep dive", "Sync with", "Check-in with", "Follow up with", "Debrief"]
    }
  }
}
<!-- /SA-DIGEST-CONFIG -->

<!-- SA-DIGEST-PROFILE -->
(paste your team profile markdown here - optional)
<!-- /SA-DIGEST-PROFILE -->
```

**How to set this up:**

1. Copy the full content of this SKILL.md file
2. At the very end, paste the config block above with your actual Notion IDs
3. Optionally paste your team profile between the profile markers
4. Use the combined text as your Routine trigger prompt or Remote Trigger message

The skill checks for these markers before attempting to read from the filesystem. If found, it uses the inline values and skips file reads entirely.
