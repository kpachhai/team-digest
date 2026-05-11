# Team Daily Digest - Output Template

This file defines the canonical output format for `/team-digest`.
Edit this file to change how digests look. The SKILL.md reads this file in Step 5 as
the output contract. Keep `<PLACEHOLDER>` notation intact - these are substituted at
write time. Notion-flavored Markdown syntax is used throughout.

---

## SECTION ORDER

1. Header callout
2. Executive Summary
3. Top Picks: Notion Pages Worth Reading (omit if zero qualify)
4. Per-org blocks (one per org in config; priority repos + other active repos)
5. Releases
6. Industry News (omit if no items from any feed)
7. Notion Keyword Monitor
8. Favorites Activity (omit if Favorites not configured)
9. Partner Conversations
10. Footer callout (ALWAYS the last block)

---

## TEMPLATE

```
<callout icon="📊" color="blue_bg">
**Team Daily Digest** | <DATE_LABEL>
<N_REPOS> repos active | <N_PRS> PRs updated | <N_ISSUES> issues updated | <N_RELEASES> releases
Data window: <DATE_LABEL> 00:00 - 23:59 UTC
</callout>

---

## Executive Summary

- **<Bold project or topic>** - <one-line plain-English change with stakes; include a markdown link to the drill-down section or PR below>
- **<Bold project or topic>** - <...>
(5-8 bullets total. Cover a mix: priority-repo highlights, releases, consequential Notion pages, partner conversations of substance, notable industry news. Skip routine dep bumps and maintenance.)

---

## Top Picks: Notion Pages Worth Reading

- **[<Page Title>](<notion-url from MCP>)** - <2-3 sentence summary: what it contains, why it's worth reading right now, one or two key facts>
- **[<Page Title>](<notion-url from MCP>)** - <...>
(3-5 picks; omit this entire section when zero Notion pages qualify)

---

# <org-name-1>

## Priority Repos

### [<repo-name>](https://github.com/<org>/<repo>)

<Paragraph 1: what merged - lead with user-visible change, then cite PR numbers as links.>

<Paragraph 2: what is open / still in review - open PRs and issues worth watching.>

**Relevance:** <why this matters to the team; use the team profile as the lens>

---

(Repeat ### block for each priority repo with activity)

## Other Active Repos

<table header-row="true">
<tr><td>Repo</td><td>PRs</td><td>Issues</td><td>Releases</td><td>Notable Activity</td></tr>
<tr><td>[<repo>](https://github.com/<org>/<repo>)</td><td><N merged / N open, or -></td><td><N open, or -></td><td>[<tag>](<release-url>) or -</td><td><1-2 sentence plain-English summary with linked PR/issue numbers></td></tr>
</table>

(Every repo with at least one PR, issue, or release in the date window must appear here. No silent drops.)

---

(Repeat # org block for each org in config.github.orgs)

# Releases

<table header-row="true">
<tr><td>Repo</td><td>Tag</td><td>Date</td><td>Notes</td></tr>
<tr><td>[<repo>](<repo-url>)</td><td>[<tag>](<release-url>)</td><td><YYYY-MM-DD></td><td><1-sentence plain-English summary of what changed></td></tr>
</table>

(If no releases on DATE_LABEL: omit the table and write "No new releases on <DATE_LABEL>.")

---

# Industry News

## <category-label>

- [<title>](<link>) - <1-2 sentence summary, HTML stripped>

(For github:// commit-watch entries: - [<short-sha>](<commit-url>): <commit subject> by <author>)

(Group items by category from config. Omit a category subsection when it has zero items. Omit the entire Industry News section when ALL categories returned zero items for DATE_LABEL.)

---

# Notion Keyword Monitor

(Pages created on DATE_LABEL that match configured keywords. Each page ID appears at most once.)

**[<Page Title>](<notion-url from MCP>)**
<2-4 sentence narrative: what the page contains, which keywords matched>
*Keywords matched: <keyword1>, <keyword2>*
*Relevance: <team-profile-driven advisory note>*

(Repeat for each unique page. If zero keyword hits: "No keyword matches for <DATE_LABEL>.")

---

# Favorites Activity

(Favorited pages and their direct child pages that were edited on DATE_LABEL.)

**[<Page Title>](<notion-url from MCP>)** - last edited <last_edited_time>
<2-4 sentence summary of what changed or what the page contains>
**Relevance:** <why this update matters to the team>

(For child pages, note the parent: "(under [<Parent Favorite Title>](<parent-url>))")

(If Favorites is configured but nothing updated: "No favorited pages or their child pages had updates on <DATE_LABEL>.")
(Omit this entire section when the Favorites list is empty or unreachable.)

---

# Partner Conversations

## <Company Name>

**[<Meeting Note Title>](<notion-url from MCP>)** - <date/time>
<2-4 sentence summary of key discussion points>

Action items:
- <action item>
- <action item>

(Group by company. If zero partner conversations found: "No partner conversations found on <DATE_LABEL>.")

---

<callout icon="ℹ️" color="gray_bg">
**Auto-generated** by Team Daily Digest | Scanned <N> repos across <orgs> | Data window: <DATE_LABEL> 00:00 - 23:59 UTC
</callout>
```

---

## FORMAT RULES (reference only - do not render in output)

### Notion API constraints
- Callout emoji: standard Unicode only (📊 ℹ️ 📈 ⚠️ 📌 🤝). Never `:shortcode:` form - Notion rejects them.
- No bold+code collision: pick **bold** OR `code`, never `` **`both`** ``.
- No `\n` inside Mermaid node labels - Notion silently truncates after the newline.
- The footer callout is ALWAYS the last block. Never append meta-sections after it.

### Links
- All Notion page links use the exact URL from a `notion-search` or `notion-fetch` MCP response.
  Never construct a Notion URL from a page title (e.g. `notion.so/Some-Page-Title` is wrong).
  If no URL is available from an MCP response, write the title as plain text + "(link unavailable)".
- All repo/PR/issue/release/user links use the exact URL from the `gh` CLI JSON output.

### Sections
- Do not add meta-sections about run hygiene ("Known limitations", "Caveats", etc.).
- Section-level inline notes (e.g., "(gh cap hit - some PRs not shown)") belong inside the section, not at the end.
- If a section has no data (e.g., no industry news), omit it entirely rather than writing "None today."
  Exception: Notion Keyword Monitor and Favorites Activity each have explicit fallback lines defined above.

### Backfill note
When running for a past date, add this line inside the footer callout:
"This is a backfill run; Notion keyword results reflect pages created on <DATE_LABEL> only (pages edited but not created on that date are not captured by Notion MCP search)."
