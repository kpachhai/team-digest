---
name: team-digest
description: Team Daily Digest - scans GitHub activity, Notion keywords, and partner conversations, writes a combined digest to Notion. Usage - /team-digest [YYYY-MM-DD | setup | config]
user-invocable: true
---

# Team Daily Digest - Manual Trigger

## Purpose

Manually run the Team Daily Digest pipeline on demand. Scans a specific day's activity (00:00-23:59 UTC) across three data sources and writes a structured summary to the Team Daily Digest Notion database.

**Usage:**
- `/team-digest` - digest for the previous calendar day (default)
- `/team-digest 2026-04-20` - digest for a specific date
- `/team-digest setup` - first-time setup or update your Notion IDs
- `/team-digest config` - show current config (Notion IDs, orgs, keywords)

Use this when:
- Testing the digest before enabling automation
- Re-running after a failed automated run
- Running an ad-hoc digest outside the normal schedule
- Backfilling a missed day (e.g., `/team-digest 2026-04-18`)

## Important Runtime Notes

- **DO NOT use `readMcpResource` or `ReadMcpResourceTool`** to fetch Notion markdown specs. The output format is fully defined in this skill. The MCP server name format varies between sessions and will cause errors.
- **DO NOT read persisted tool result files** (the `/tool-results/` paths). Process `gh` CLI JSON output directly within the same Bash command using `python3 -c` inline scripts. Persisted files may have prefix lines that break JSON parsing.
- **DO NOT use `cat` to read files then parse them in a separate step.** Always pipe or process in a single command chain.

## Time Window

The digest covers a **single calendar day in UTC** (00:00:00 to 23:59:59 UTC).

**If a date argument is provided** (e.g., `/team-digest 2026-04-20`), use that date.
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

- **If `<!-- SA-DIGEST-CONFIG -->` is present:** extract the JSON between the open and close tags, parse it, and store it as `inline_config`. Extract the `team-digest` key from that JSON. If `<!-- SA-DIGEST-PROFILE -->` markers are also present, extract the text between them and store it as `inline_profile`. Set `config_source = "inline"`. Do NOT read from the filesystem.
- **If the markers are absent:** set `config_source = "filesystem"`. Continue to Step 0 below.

This pre-flight scan happens regardless of subcommand. Even `config` and `setup` subcommands need to know whether they're running inline or filesystem mode.

---

### Step 0: Handle Subcommands and Load Config

#### Subcommand: `setup`

If the argument is `setup`, run the interactive setup flow (see below) regardless of whether a config already exists. This lets users update their Notion IDs at any time. After writing the config, confirm success and stop (do not run the digest).

#### Subcommand: `config`

If the argument is `config` and `config_source == "inline"`, display the inline config values. If `config_source == "filesystem"`, read `~/.config/team-digest/config.json` and display the current `team-digest` configuration in a readable format: Notion IDs (masked to last 8 chars for brevity), GitHub orgs, priority repos, and default keywords. Then stop.

#### Load Config

If `config_source == "inline"`: config is already loaded from the pre-flight step. Skip filesystem reads.

If `config_source == "filesystem"`: read `~/.config/team-digest/config.json` using the Read tool.

**If the config file does not exist or is missing the `team-digest` key**, and `config_source == "filesystem"`:

- If this appears to be a routine/automated context (no interactive user, no terminal): **ABORT** with this message: "ERROR: No config found. This appears to be a routine run but no inline config block was found in the prompt and `~/.config/team-digest/config.json` does not exist on this server. Embed your config between `<!-- SA-DIGEST-CONFIG -->` markers at the end of the routine prompt. See the Appendix in the skill definition." Do not proceed further.
- If this is an interactive local run: run the first-time setup flow automatically:

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
          "name": "your-org",
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
          "name": "your-org",
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

7. If the config file already exists with other digest keys (e.g., `my-team-digest`), merge the new `team-digest` key into the existing file rather than overwriting it.
8. Confirm the config was created and tell the user they can now run `/team-digest` to produce their first digest.
9. **Stop here** (do not continue to the digest pipeline on first-time setup).

If the argument was `setup`, use the same flow above but pre-fill the prompts with existing values so the user can see what's currently set and only change what they need.

#### Normal Config Load (config exists)

Parse the `team-digest` key from the config to get:
- `notion.config_page_id` - the Notion configuration page ID
- `notion.database_id` - the Notion database ID for digest output
- `github.orgs` - array of GitHub organizations to scan, each with:
  - `name` - the org name (e.g., "your-org")
  - `priority_repos` - repos that get full narrative summaries (can be empty)
  - `scan_all` - whether to scan all repos in the org or only priority repos
- `defaults.*` - fallback values for keywords and partner patterns

Also read the team profile at `~/.config/team-digest/profiles/team-digest.md` using the Read tool (skip if inline profile was already loaded above). If the file does not exist and no inline profile was provided, continue without it. The profile describes the team's role, priorities, and what makes activity relevant to them - used to write the **Relevance** sections throughout the digest. If no profile is loaded, fall back to generic relevance heuristics (developer-facing APIs, breaking changes, architecture impacts, partner integration concerns).

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
- **Priority repos** (listed in `priority_repos`): Write synthesized narrative summaries - NOT bulleted PR lists. Group related PRs by theme and describe the collective work in 2-4 paragraphs. Only reference a specific PR by number/link when it is individually significant (breaking change, major feature, hotfix). After the narrative, add a **Relevance:** paragraph using the loaded team profile as your guide - the profile describes the team's role, what they care about, and what "relevant" means for them specifically. If no profile was loaded, fall back to: does this affect developer-facing APIs or SDKs? Does it impact partner integrations or architecture decisions? Does it affect EVM compatibility? Is there a breaking change developers should know about? Could it inform a technical design recommendation? If the activity represents an architectural change (component split/merge, service restructuring, data flow change, before/after pattern), add a Mermaid diagram after the narrative - use `graph TD` with `direction LR` subgraphs for a square layout; keep all node labels on a single line (no `\n` in labels). One diagram per repo maximum; skip if nothing structural happened.
- **Other repos** (if `scan_all` is true): Create a summary table with repo name and a brief one-line description of notable activity.
- **Orgs with no priority repos** (e.g., `your-org`): Show all repos in a summary table; no narrative section.

The digest should group output under org-level headers:

```
# your-org

## Priority Repos
(narrative summaries for each priority repo with activity)

## Other Activity
(summary table for non-priority repos)

# your-org

## Priority Repos
(narrative summaries)

## Other Activity
(summary table)

# your-org

## Activity
(summary table for all repos - no priority repos defined)
```

If scanning an org fails, note the failure and continue with the next org.

### Step 3: Scan Notion Keywords

For each keyword group from configuration, search the Notion workspace:
- Use the `notion-search` MCP tool with `query_type: "internal"`
- Filter to pages created on the previous calendar day using `created_date_range: { start_date: "<DATE_LABEL>" }`
- Set `page_size: 10` and `max_highlight_length: 300`

Run keyword searches in parallel batches (2-3 keywords per search query to reduce API calls).

**Deduplication:** Track page IDs across all keyword searches. Each page appears only once in the digest with all matching keywords listed.

**Exclusions:** Skip any page whose title starts with "Team Daily Digest" (our own output).

For each unique page found:
- Fetch full page content using the `notion-fetch` MCP tool
- Write a narrative summary explaining what the page contains
- List which keywords matched
- Add a "relevance" note explaining why this matters for the team

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

### Step 5: Write the Combined Digest to Notion

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

**Content structure:**

```
<callout icon="📊" color="blue_bg">
**Team Daily Digest** | <DATE_LABEL>
<N> repos active | <N> PRs updated | <N> issues updated | <N> releases
Data window: <DATE_LABEL> 00:00 - 23:59 UTC
</callout>

---

# <org-name> (e.g. your-org)

## Priority Repos

### <repo-name>
<2-4 paragraph synthesized narrative - describes themes and collective work, not a PR list>
<Mermaid diagram if architectural change occurred>

**Relevance:** <why this matters to the team - integration impact, architecture decisions, SDK changes, partner-facing APIs, breaking changes>

---

(repeat for each priority repo with activity)

## Other Active Repos

<summary table>

---

(repeat org section for each org)


# Other Active Repos

<table with repo name and notable activity>

# Releases

<releases or "No new releases">

---

# Notion Keyword Monitor

<narrative summaries of keyword-matched pages>

---

# Partner Conversations

<grouped by company with discussion summaries and action items>

---

<callout icon="ℹ️" color="gray_bg">
**Auto-generated** by Team Daily Digest | Scanned <N> repos in <org> | Data window: <DATE_LABEL> 00:00 - 23:59 UTC
</callout>
```

## Style Rules

- **Synthesize, don't list** - describe what the team is collectively accomplishing, not individual PR titles. "The team is decomposing the monolithic operations facet into single-responsibility components" beats listing 14 PRs.
- Only link a specific PR when it is individually significant (breaking change, major feature, hotfix). For a batch of related PRs, link to the repo instead.
- After each priority repo narrative, add a **Relevance:** paragraph. Use the team profile loaded in Step 0 to drive this - the profile specifies what the team cares about, their priorities, and content opportunity triggers. If no profile exists, use generic heuristics.
- Add a Mermaid diagram for architectural changes - component splits, service restructuring, data flow changes. Keep labels on single lines. Use `graph TD` with `direction LR` subgraphs for square layout. One diagram per repo max.
- Surface cross-repo connections when relevant (e.g., a Solo bug that also affects relay)
- Keep the digest scannable in under 3 minutes
- Use hyphens (-) or semicolons (;) instead of em-dashes
- If any section fails, produce a partial digest with a clear failure indicator rather than failing entirely

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
          "name": "your-org",
          "priority_repos": ["hiero-json-rpc-relay", "hiero-mirror-node", "..."],
          "scan_all": true
        },
        {
          "name": "your-org",
          "priority_repos": ["hedera-docs", "hedera-agent-kit-js", "..."],
          "scan_all": true
        },
        {
          "name": "your-org",
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

The config is created automatically on first run (`/team-digest`) or manually via `/team-digest setup`. To update Notion IDs later, run `/team-digest setup` again. To view current config, run `/team-digest config`.

## Appendix: Inline Config for Routines and Remote Triggers

When running as a **Claude Code Routine** or **Remote Trigger**, the skill has no access to local files. Append your config and (optionally) your team profile directly after the skill content using these markers:

```
<!-- SA-DIGEST-CONFIG -->
{
  "team-digest": {
    "notion": {
      "config_page_id": "<your-config-page-id>",
      "database_id": "<your-database-id>"
    },
    "github": {
      "github_token": "<optional - GitHub PAT with public_repo read scope; required for full coverage when running as a routine>",
      "orgs": [
        {
          "name": "your-org",
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
