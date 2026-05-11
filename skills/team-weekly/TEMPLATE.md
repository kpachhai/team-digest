# Team Weekly Digest - Output Template

This file defines the canonical output format for `/team-weekly`.
Edit this file to change how weekly digests look. The SKILL.md reads this file in Step 5
as the output contract. Keep `<PLACEHOLDER>` notation intact - these are substituted at
write time. Notion-flavored Markdown syntax is used throughout.

---

## SECTION ORDER

1. Header callout
2. Week at a Glance (stats bullets)
3. Executive Summary
4. Top Picks: Notion Pages Worth Reading This Week (omit if zero qualify)
5. Top GitHub Themes
6. Releases This Week
7. Partner Momentum (omit if no partner conversations across the week)
8. Notion Content Pulse
9. Industry News Roundup (omit if no items)
10. Favorites Movement (omit if no Favorites Activity in any daily)
11. Day-by-Day Index
12. Footer callout (ALWAYS the last block)

---

## TEMPLATE

```
<callout icon="📈" color="purple_bg">
**Team Weekly Digest** | <WEEK_LABEL> | <WEEK_START> to <WEEK_END>
<N_DIGESTS> daily digests processed | <N_REPOS> repos active | <N_RELEASES> releases | <N_PARTNERS> partner conversations
</callout>

---

# Week at a Glance

- <N> daily digests processed (<first weekday> to <last weekday>)
- <N> priority repos with sustained activity (3+ days of PRs)
- <N> releases shipped across the week
- <N> partners with conversations recorded
- <N> favorited pages with multi-day updates

---

## Executive Summary

- **<Bold project or theme>** - <one-line plain-English statement of what shifted across the week and why it matters; link to the relevant theme section below>
- **<Bold project or theme>** - <...>
(5-8 bullets total. Cover: top sustained GitHub themes, notable releases, partner momentum, consequential Notion pages, industry-news standouts. Write for an outsider - no insider jargon without translation.)

---

## Top Picks: Notion Pages Worth Reading This Week

- **[<Page Title>](<notion-url from MCP>)** - <2-3 sentence summary: what it contains, why it's relevant this week, one or two key facts>
- **[<Page Title>](<notion-url from MCP>)** - <...>
(3-5 picks from the union of each daily's Top Picks + Notion Content Pulse; ranked by profile relevance + cross-day momentum; omit the section when zero qualify)

---

# Top GitHub Themes

<Paragraph 1: the 2-3 repos with the most sustained cross-week activity. What were they collectively building? Link the most significant individual PRs.>

<Paragraph 2: architectural changes, if any. Reference specific merged ADRs or design docs. Do not re-render Mermaid diagrams from the dailies - reference them by name and date.>

<Quieter this week: **<repo>** - no activity recorded despite being a key repo per the team profile. (Only include when the team profile lists the repo as high-priority and no PRs appeared in the week.)>

---

# Releases This Week

<table header-row="true">
<tr><td>Repo</td><td>Version</td><td>Date</td><td>Notes</td></tr>
<tr><td>[<repo>](<repo-url>)</td><td>[<tag>](<release-url>)</td><td><YYYY-MM-DD></td><td><1-sentence summary></td></tr>
</table>

(If no releases across the week: "No releases this week.")

---

# Partner Momentum

## <Company Name> (N days)

<1-2 sentence "what's moving" summary for companies that appeared in 2+ daily digests>

(Single-touch companies: list names in a one-liner at the end: "Single touch: Company A (Tue), Company B (Thu).")

**Open threads:** <action items that appeared in multiple dailies - most likely escalation candidates>

(Omit this entire section if no partner conversations were found across the week.)

---

# Notion Content Pulse

(Top 3-5 keywords by frequency - how many days they appeared across the week.)

- **<keyword>** - appeared <N> days (<days list>); most relevant pages: [<page>](<url>) (<day>), [<page>](<url>) (<day>)
- **<keyword>** - <...>

(Omit keywords that appeared on only one day - covered by that day's daily. If all keywords appeared only once, write "No repeated keyword themes this week - see individual daily digests for details.")

---

# Industry News Roundup

## <category-label>

- [<title>](<link>) - <source> (<day>)

(Deduplicate by URL across all 7 dailies - the same post can appear in multiple dailies due to RSS feed lag. Group by category. Omit category subsection when it has zero items across the week. Omit the entire Industry News Roundup section when all categories had zero items.)

---

# Favorites Movement

(Pages from the Favorites list with multi-day updates get highlighted callouts; single-day updates get bullets.)

<callout icon="📌" color="yellow_bg">
**[<Page Title>](<notion-url>)** updated on <Day1> and <Day2> - <2-sentence summary of the cross-day activity>
</callout>

- **[<Page Title>](<notion-url>)** - updated <Day>, <date>: <1-sentence summary>

(Omit this section if no Favorites Activity appeared in any daily digest.)

---

# Day-by-Day Index

- Monday, <date>: [<daily digest title>](<daily-page-url>)
- Tuesday, <date>: [<daily digest title>](<daily-page-url>)
- Wednesday, <date>: [<daily digest title>](<daily-page-url>)
- Thursday, <date>: [<daily digest title>](<daily-page-url>)
- Friday, <date>: [<daily digest title>](<daily-page-url>)
- Saturday, <date>: [<daily digest title>](<daily-page-url>) (or: "no digest run")
- Sunday, <date>: [<daily digest title>](<daily-page-url>) (or: "no digest run")

(List all 7 days in the window. For missing days write: "<Weekday>, <date>: no daily digest run")

---

<callout icon="ℹ️" color="gray_bg">
**Auto-generated** by Team Weekly Digest | Synthesized from <N> daily digests | Week: <WEEK_LABEL> (<WEEK_START> to <WEEK_END>)
</callout>
```

---

## FORMAT RULES (reference only - do not render in output)

### Weekly vs. daily
- The weekly is a SYNTHESIS, not a copy. Cross-day signal (sustained activity, recurring themes,
  multi-touch partners) is the point. Single-day items are already in the daily.
- Do not re-summarize content already well-covered in a daily. Link to the daily for drill-down.
- Mermaid diagrams from the dailies are referenced by name ("architecture diagram in the
  2026-05-07 hiero-block-node section"), not re-rendered.

### Notion API constraints (same as daily)
- Callout emoji: standard Unicode only (📈 ℹ️ 📊 ⚠️ 📌). Never `:shortcode:` form.
- No bold+code collision.
- The footer callout is ALWAYS the last block.
- No meta-sections about run hygiene.

### Links (same as daily)
- All Notion links from MCP responses only. Never construct from page titles.
- All repo/PR/release links from gh CLI JSON output.
- Daily digest page links come from the `url` property of the `notion-query-data-sources` results.
