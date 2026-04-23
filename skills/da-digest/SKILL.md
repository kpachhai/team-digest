---
name: da-digest
description: Manually trigger the DA Daily Digest - scans your-org GitHub activity, Notion keywords, and partner conversations, writes a combined digest to Notion. Usage - /da-digest
user-invocable: true
---

# DA Daily Digest - Manual Trigger

## Purpose

Manually run the DA Daily Digest pipeline on demand. Scans the last 24 hours of activity across three data sources and writes a structured summary to the DA Daily Digest Notion database.

Use this when:
- Testing the digest before enabling automation
- Re-running after a failed automated run
- Running an ad-hoc digest outside the normal schedule

## Process

### Step 0: Load Local Config

Read the config file at `~/.config/team-digest/config.json`. Parse the `da-digest` key to get:
- `notion.config_page_id` - the Notion configuration page ID (browsable: `notion.so/<id>`)
- `notion.database_id` - the Notion database ID for digest output (browsable: `notion.so/<id>`)
- `github.org` - the GitHub organization to scan
- `defaults.*` - fallback values for priority repos, keywords, and partner patterns

Then fetch the database page using `notion-fetch` with the `database_id` to discover the internal `data_source_id` (the `collection://...` URL in the response). This is needed to create pages in the database but is derived at runtime - users never need to look it up.

If the config file does not exist or is missing the `da-digest` key, stop and tell the user to run `setup.sh` from the team-digest repo first.

### Step 1: Read Notion Configuration

Using the `config_page_id` from the local config, fetch the Notion configuration page using the `notion-fetch` tool.

Extract:
- GitHub organization name (under "Organization")
- Priority repos list (under "Priority Repos")
- Keywords list (under "Keywords")
- Partner conversation patterns (under "Title Patterns")

If the Notion config page is unreachable, fall back to the `defaults` section from the local config file.

### Step 2: Scan GitHub Activity (last 24 hours)

Using `gh` CLI, scan the GitHub organization for all activity in the last 24 hours.

Run in parallel:

1. **PRs:**
   ```
   SINCE=$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
   gh search prs --owner=<org> --updated=">=$SINCE" --json repository,title,state,author,number,body,url,labels --limit 100
   ```

2. **Issues:**
   ```
   gh search issues --owner=<org> --updated=">=$SINCE" --json repository,title,state,author,number,body,url,labels --limit 100
   ```

3. **Releases:** Check all org repos for releases published since `$SINCE`.

For **priority repos**: Write rich narrative summaries explaining what happened and why it matters. Include GitHub links on every PR and issue. Read PR descriptions to understand context - do not just list PR titles. Highlight breaking changes, new features, bug fixes, and anything relevant to Developer Advocacy.

For **other repos with activity**: Create a summary table with repo name and a brief prose description of notable activity.

If GitHub scanning fails, note the failure in the digest and continue with remaining sections.

### Step 3: Scan Notion Keywords (last 24 hours)

For each keyword from configuration, search the Notion workspace:
- Use `notion-search` with `query_type: "internal"`
- Filter to pages created in the last 24 hours using `created_date_range: { start_date: "<yesterday>" }`
- Set `page_size: 10` and `max_highlight_length: 300`

Run keyword searches in parallel batches (2-3 keywords per search query to reduce API calls).

**Deduplication:** Track page IDs across all keyword searches. Each page appears only once in the digest with all matching keywords listed.

**Exclusions:** Skip any page whose title starts with "DA Daily Digest" (our own output).

For each unique page found:
- Fetch full page content using `notion-fetch`
- Write a narrative summary explaining what the page contains
- List which keywords matched
- Add a "DA relevance" note explaining why this matters for the DA team

If Notion keyword scanning fails, note the failure and continue.

### Step 4: Scan Partner Conversations (last 24 hours)

For each partner pattern from configuration, search the Notion workspace using `notion-search` with `created_date_range` filter.

**Deduplication:** Skip pages already covered in the keyword monitor section. Track by page ID.

For each meeting/conversation page found:
- Fetch full page content
- Identify partner/company names discussed
- **Group results by company/partner** (not by page)
- Summarize key discussion points
- Extract and list action items with checkboxes
- Note any follow-ups or deadlines mentioned

If partner scanning fails, note the failure and continue.

### Step 5: Write the Combined Digest to Notion

Create a new page in the DA Daily Digest database using `notion-create-pages`:

**Parent:** `{ "type": "data_source_id", "data_source_id": "<data_source_id from local config>" }`

**Properties:**
- Digest Title: `DA Daily Digest - <YYYY-MM-DD>`
- date:Date:start: `<YYYY-MM-DD>`
- Digest Type: `Combined`
- Repos Active: `<count of repos with activity>`
- Keywords Matched: `["keyword1", "keyword2", ...]` (JSON array of keywords that had hits)
- Status: `Auto`

**Content structure** (using Notion-flavored Markdown):

```
<callout icon="icon" color="blue_bg">
**DA Daily Digest - your-org** | <date>
<N> repos active | <N> PRs updated | <N> issues updated | <N> releases
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

<callout icon="icon" color="gray_bg">
**Auto-generated** by DA Daily Digest | Scanned <N> repos in <org> | Data window: ...
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
