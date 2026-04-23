---
name: da-digest
description: Manually trigger the DA Daily Digest - scans your-org GitHub activity, Notion keywords, and partner conversations, writes a combined digest to Notion. Usage - /da-digest
user-invocable: true
---

# DA Daily Digest - Manual Trigger

## Purpose

Manually run the DA Daily Digest pipeline on demand. Scans the previous calendar day's activity (00:00-23:59 UTC) across three data sources and writes a structured summary to the DA Daily Digest Notion database.

Use this when:
- Testing the digest before enabling automation
- Re-running after a failed automated run
- Running an ad-hoc digest outside the normal schedule

## Important Runtime Notes

- **DO NOT use `readMcpResource` or `ReadMcpResourceTool`** to fetch Notion markdown specs. The output format is fully defined in this skill. The MCP server name format varies between sessions and will cause errors.
- **DO NOT read persisted tool result files** (the `/tool-results/` paths). Process `gh` CLI JSON output directly within the same Bash command using `python3 -c` inline scripts. Persisted files may have prefix lines that break JSON parsing.
- **DO NOT use `cat` to read files then parse them in a separate step.** Always pipe or process in a single command chain.

## Time Window

The digest always covers the **previous calendar day in UTC** (00:00:00 to 23:59:59 UTC), regardless of when you run it. This ensures:
- Manual runs at any time of day produce the same result
- Automated morning runs and manual re-runs are consistent
- No activity is missed or double-counted between runs

Compute the window at the start:
```bash
# Previous calendar day boundaries (UTC)
START=$(date -u -v-1d +%Y-%m-%dT00:00:00Z 2>/dev/null || date -u -d 'yesterday' +%Y-%m-%dT00:00:00Z)
END=$(date -u -v-1d +%Y-%m-%dT23:59:59Z 2>/dev/null || date -u -d 'yesterday' +%Y-%m-%dT23:59:59Z)
DATE_LABEL=$(date -u -v-1d +%Y-%m-%d 2>/dev/null || date -u -d 'yesterday' +%Y-%m-%d)
```

Use `$START` as the `--updated` filter for GitHub and the `start_date` for Notion searches.

## Process

### Step 0: Load Local Config

Read the config file at `~/.config/team-digest/config.json` using the Read tool. Parse the `da-digest` key to get:
- `notion.config_page_id` - the Notion configuration page ID
- `notion.database_id` - the Notion database ID for digest output
- `github.org` - the GitHub organization to scan
- `defaults.*` - fallback values for priority repos, keywords, and partner patterns

If the config file does not exist or is missing the `da-digest` key, stop and tell the user to run `setup.sh` from the team-digest repo first.

Then fetch the database page using `notion-fetch` with the `database_id` to discover the internal `data_source_id` (the `collection://...` URL in the response). Extract the data source URL from the `data-source-url` attribute in the response.

### Step 1: Read Notion Configuration

Using the `config_page_id` from the local config, fetch the Notion configuration page using the `notion-fetch` tool.

Extract:
- GitHub organization name (under "Organization")
- Priority repos list (under "Priority Repos")
- Keywords list (under "Keywords")
- Partner conversation patterns (under "Title Patterns")

If the Notion config page is unreachable, fall back to the `defaults` section from the local config file.

### Step 2: Scan GitHub Activity

Using `gh` CLI, scan the GitHub organization for activity during the previous calendar day.

**Critical: Process JSON output directly in each Bash command. Do not save to intermediate files.**

Run these commands in parallel:

1. **PRs** - run this as a single Bash command that outputs a human-readable summary:
   ```bash
   gh search prs --owner=<org> --updated=">=$START" --json repository,title,state,author,number,body,url,labels --limit 100 | python3 -c "
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

2. **Issues** - same pattern as PRs:
   ```bash
   gh search issues --owner=<org> --updated=">=$START" --json repository,title,state,author,number,body,url,labels --limit 100 | python3 -c "
   import json, sys
   data = json.load(sys.stdin)
   repos = {}
   for issue in data:
       repo = issue['repository']['name']
       if repo not in repos: repos[repo] = []
       repos[repo].append(issue)
   for repo in sorted(repos.keys()):
       print(f'## {repo} ({len(repos[repo])} issues)')
       for i in repos[repo]:
           body = (i.get('body') or '')[:200].replace(chr(10), ' ').strip()
           print(f'  [{i[\"state\"].upper()}] #{i[\"number\"]} {i[\"title\"]}')
           print(f'    Author: @{i[\"author\"][\"login\"]}')
           print(f'    URL: {i[\"url\"]}')
           if body: print(f'    Description: {body}')
           print()
   "
   ```

3. **Releases** - check all org repos:
   ```bash
   gh api orgs/<org>/repos --paginate --jq '.[].name' | while read repo; do
     gh api "repos/<org>/$repo/releases" --jq "[.[] | select(.published_at >= \"$START\")] | .[] | \"$repo: \(.tag_name) - \(.name // \"no title\") (\(.published_at[:10]))\"" 2>/dev/null
   done
   ```

For **priority repos**: Write rich narrative summaries explaining what happened and why it matters. Include GitHub links on every PR and issue. Read PR descriptions to understand context - do not just list PR titles. Highlight breaking changes, new features, bug fixes, and anything relevant to Developer Advocacy.

For **other repos with activity**: Create a summary table with repo name and a brief prose description of notable activity.

If GitHub scanning fails, note the failure in the digest and continue with remaining sections.

### Step 3: Scan Notion Keywords

For each keyword group from configuration, search the Notion workspace:
- Use the `notion-search` MCP tool with `query_type: "internal"`
- Filter to pages created on the previous calendar day using `created_date_range: { start_date: "<DATE_LABEL>" }`
- Set `page_size: 10` and `max_highlight_length: 300`

Run keyword searches in parallel batches (2-3 keywords per search query to reduce API calls).

**Deduplication:** Track page IDs across all keyword searches. Each page appears only once in the digest with all matching keywords listed.

**Exclusions:** Skip any page whose title starts with "DA Daily Digest" (our own output).

For each unique page found:
- Fetch full page content using the `notion-fetch` MCP tool
- Write a narrative summary explaining what the page contains
- List which keywords matched
- Add a "DA relevance" note explaining why this matters for the DA team

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

Create a new page in the DA Daily Digest database using the `notion-create-pages` MCP tool.

**Parent:** `{ "type": "data_source_id", "data_source_id": "<data_source_id discovered in Step 0>" }`

**Properties:**
- Digest Title: `DA Daily Digest - <DATE_LABEL>`
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
**DA Daily Digest - your-org** | <DATE_LABEL>
<N> repos active | <N> PRs updated | <N> issues updated | <N> releases
Data window: <DATE_LABEL> 00:00 - 23:59 UTC
</callout>

---

# Priority Repos

## <repo-name>
<narrative summary with GitHub links>

---

(repeat for each priority repo)

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
**Auto-generated** by DA Daily Digest | Scanned <N> repos in <org> | Data window: <DATE_LABEL> 00:00 - 23:59 UTC
</callout>
```

## Style Rules

- Write rich, human-readable narrative summaries - not raw PR/issue lists
- Include GitHub links on every PR, issue, and repo reference
- Surface cross-repo connections when relevant (e.g., a Solo bug that also affects relay)
- Highlight items that matter to Developer Advocacy specifically
- Keep the digest scannable in under 3 minutes
- Use hyphens (-) or semicolons (;) instead of em-dashes
- If any section fails, produce a partial digest with a clear failure indicator rather than failing entirely

## Configuration

All Notion resource IDs are read from `~/.config/team-digest/config.json` under the `da-digest` key:

```json
{
  "da-digest": {
    "notion": {
      "config_page_id": "<32-char hex from Notion config page URL>",
      "database_id": "<32-char hex from Notion database URL>"
    },
    "github": {
      "org": "your-org"
    },
    "defaults": { ... }
  }
}
```

Both IDs are the 32-character hex strings from the Notion page URLs (`notion.so/<id>`). The internal `data_source_id` needed to write pages is derived automatically at runtime by fetching the database.

Run `setup.sh` from the team-digest repo to create this file from the template.
