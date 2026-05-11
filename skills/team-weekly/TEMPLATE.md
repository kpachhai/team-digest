# Team Weekly Digest - Output Template

This file is the canonical output format for `/team-weekly`.
Edit this file to change how weekly digests look. The skill reads it in Step 5 as the output contract.
`<PLACEHOLDER>` values are substituted at write time. Notion-flavored Markdown syntax throughout.

Inline annotations (lines starting with `NOTE:`) are instructions to the model - do not render them.

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
12. Footer callout (ALWAYS last)

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
- <N> priority repos with sustained activity (3+ days of PRs or issues)
- <N> releases shipped across the week
- <N> partners with conversations recorded
- <N> favorited pages with multi-day updates

---

## Executive Summary

NOTE: 5-8 bullets covering the WEEK's signal - not a repeat of individual daily headlines.
NOTE: Each bullet must name a cross-week THEME or SHIFT, not a single day's event.
NOTE: Same two-question gate as the daily: Q1 - specific? Q2 - consequence/why it matters?
NOTE: Same bold+code rule: use **[repo-name](url)** or **plain bold**, never **`code`**.
NOTE:
NOTE: BAD:  - **`asset-tokenization-studio`** security audit - Audit fixes continued throughout the week.
NOTE:       (fails Q1: which findings? fails Q2: so what for partners?)
NOTE: GOOD: - **[asset-tokenization-studio](url) closed its external security audit sprint** - 12 findings merged this week,
NOTE:       including a critical admin-role lockout bug (FIND-111) and a nonce-sequencing vulnerability (FIND-073).
NOTE:       Partners using ATS as a tokenization baseline should hold mainnet deployments until the audit is complete.
NOTE:
NOTE: BAD:  - **Guardian** had lots of activity - AI Toolkit scaffold merged, various PRs merged.
NOTE:       (fails Q1 and Q2)
NOTE: GOOD: - **[Guardian](url) adds an AI automation layer** - the Guardian AI Toolkit scaffold merged, introducing
NOTE:       Docker Compose infrastructure and repo structure for AI-driven policy creation. First step toward
NOTE:       reducing the manual policy authoring burden for sustainability use cases.

- **<plain bold or [linked name](url)>** - <specific cross-week theme>; <consequence for partners or the team>
- **<plain bold or [linked name](url)>** - <...>
(5-8 bullets; cover top sustained GitHub themes, releases, partner momentum shifts, consequential Notion pages, industry news standouts)

---

## Top Picks: Notion Pages Worth Reading This Week

NOTE: 3-5 pages. Aggregate Top Picks from all dailies + Notion Content Pulse. Dedupe by page ID.
NOTE: Rank by team-profile relevance + cross-day momentum (page appearing on multiple days ranks higher).
NOTE: Omit section if zero pages qualify.
NOTE: Each entry: 2-3 sentences - WHAT + WHY WORTH READING THIS WEEK + one concrete fact.

- **[<Page Title>](<notion-url from MCP>)** - <what the page is about>. <why it's relevant this week - cross-day context, what decision it supports>. <one concrete fact>
- **[<Page Title>](<notion-url from MCP>)** - <...>

---

# Top GitHub Themes

NOTE: 2-3 paragraphs synthesizing the repos with SUSTAINED activity (3+ days of PRs or issues).
NOTE: A repo with 1 PR on Monday is noise; a repo with PRs every day is signal.
NOTE: Lead each paragraph with the user-visible theme, not the repo name or PR numbers.
NOTE: Reference the most significant individual PRs; link every one.
NOTE:
NOTE: BAD:  "hiero-consensus-node had 15 PRs this week including #25382, #25381, #25380..."
NOTE: GOOD: "The Hedera consensus layer (hiero-consensus-node) published five architecture reference documents this week -
NOTE:        covering restart procedures, event routing, and cryptographic state management. These are the first formal
NOTE:        ADRs for the consensus subsystem and will directly support SA deep-dives with enterprise partners on
NOTE:        network reliability guarantees."
NOTE:
NOTE: End the section with a one-line "Quieter this week" callout for expected repos that were absent.
NOTE: Only include repos the team profile lists as high-priority AND that had no PRs this week.

<Paragraph 1: top sustained theme with user-visible framing and linked PRs>

<Paragraph 2: second sustained theme, if any>

<Paragraph 3: architectural changes, if any. Reference diagrams from the daily digests by name - do NOT re-render them.>

*Quieter this week: **[<repo>](<url>)** - no activity recorded despite being a key integration repo.*

---

# Releases This Week

<table header-row="true">
<tr><td>Repo</td><td>Version</td><td>Date</td><td>Notes</td></tr>
<tr><td>[<repo>](<repo-url>)</td><td>[<tag>](<release-url>)</td><td><YYYY-MM-DD></td><td><1-sentence: what changed for users of this release></td></tr>
</table>

NOTE: If no releases across the week: "No releases this week." (omit the table)

---

# Partner Momentum

NOTE: Companies appearing in 2+ daily digests get a 1-2 sentence "what's moving" summary.
NOTE: Companies appearing once get a single-line entry in the "Single touch" list.
NOTE: "Open threads" = action items that surfaced in multiple dailies (escalation candidates).

## <Company Name> (<N> days)

<1-2 sentences: what is moving with this partner this week, what is the main topic or decision>

(Single touch: Company A (Day), Company B (Day).)

**Open threads:** <action items that appeared on multiple days - most likely to need follow-up>

NOTE: Omit this section if no partner conversations appeared across the week.

---

# Notion Content Pulse

NOTE: Top 3-5 keywords by frequency (number of days they appeared).
NOTE: Omit keywords that appeared only once - already covered in that daily.
NOTE: Each entry explains WHAT documents used the keyword and WHY that keyword theme is significant this week.

- **<keyword>** - appeared <N> days (<day list>); most relevant pages: [<page>](<url>) (<day>), [<page>](<url>) (<day>)
  *What this means: <1-sentence interpretation - why is this keyword appearing repeatedly this week?>*

NOTE: If all keywords appeared only once: "No repeated keyword themes this week - see individual daily digests."

---

# Industry News Roundup

NOTE: Aggregate from all daily digests. Deduplicate by URL (same post can appear in multiple dailies due to feed lag).
NOTE: Same two-part format as the daily: [title](link) - <plain-English what happened>; relevant because <why it matters>
NOTE: Do NOT copy raw RSS descriptions or commit messages verbatim.
NOTE: Group by category. Omit category subsections with zero items. Omit entire section if all categories had zero items.

## <category-label>

- [<title>](<link>) - <plain-English what happened>; relevant because <why it matters for our Hedera/EVM work> (<day>)

---

# Favorites Movement

NOTE: Pages with multi-day updates get highlighted callouts. Single-day updates get bullets.
NOTE: Only include pages that appeared in Favorites Activity in at least one daily digest this week.
NOTE: Omit this section if no Favorites Activity appeared in any daily.

<callout icon="📌" color="yellow_bg">
**[<Page Title>](<notion-url>)** updated on <Day1> and <Day2>
<2-sentence summary of what the cross-day activity means - what is actively changing about this page/topic>
</callout>

- **[<Page Title>](<notion-url>)** - updated <Day>, <date>: <1-sentence summary>

---

# Day-by-Day Index

NOTE: One line per day in the window. Note gaps explicitly.

- Monday, <date>: [<daily digest title>](<daily-page-url>)
- Tuesday, <date>: [<daily digest title>](<daily-page-url>)
- Wednesday, <date>: [<daily digest title>](<daily-page-url>)
- Thursday, <date>: [<daily digest title>](<daily-page-url>)
- Friday, <date>: [<daily digest title>](<daily-page-url>)
- Saturday, <date>: [<daily digest title>](<daily-page-url>) *(or: "no digest run")*
- Sunday, <date>: [<daily digest title>](<daily-page-url>) *(or: "no digest run")*

---

<callout icon="ℹ️" color="gray_bg">
**Auto-generated** by Team Weekly Digest | Synthesized from <N> daily digests | Week: <WEEK_LABEL> (<WEEK_START> to <WEEK_END>)
</callout>
```

---

## FORMAT RULES (human reference - do not render in output)

### Weekly vs. daily
- Synthesize, don't copy. Cross-day signal is the point - sustained activity, recurring themes, multi-touch partners.
- Don't re-summarize content already in a daily. Link to the daily for drill-down.
- Mermaid diagrams from the dailies are referenced by name, not re-rendered.

### Notion API hard constraints (same as daily)
- Callout emoji: standard Unicode only. Never `:shortcode:`.
- Bold+code collision: `` **`name`** `` = `` **** `` artifact. Use `**[name](url)**` or `**name**`.
- No `\n` inside Mermaid node labels.
- Footer callout is ALWAYS the last block.
- No meta-sections about run hygiene.

### Links (same as daily)
- All Notion links from MCP responses only. Never construct from page titles.
- Daily digest page links from `url` property of `notion-query-data-sources` results.

### Quality (same gates as daily, applied at Step 4.5 Part B)
- Executive Summary bullets: must pass Q1 (specific cross-week theme) and Q2 (consequence)
- Industry News items: must have plain-English "what happened" + "why it matters"
