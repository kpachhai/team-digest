# Team Monthly Digest - Output Template

This file is the canonical output format for `/team-monthly`.
Edit this file to change how monthly digests look. The skill reads it in Step 5 as the output contract.
`<PLACEHOLDER>` values are substituted at write time. Notion-flavored Markdown syntax throughout.

Inline annotations (lines starting with `NOTE:`) are instructions to the model - do not render them.

**Reading experience (apply throughout):** this page is read top-to-bottom by someone who may have read none of the dailies or weeklies. Lead with the story in plain words; keep jargon, IDs, and exhaustive lists out of the main flow (link out, or use a `<details>` toggle for reference lists). Use the emoji section anchors below so sections are easy to find when scrolling.

---

## SECTION ORDER

1. Header callout
2. 📖 The Month in Review (narrative)
3. 🧵 Top Storylines (the interconnection layer - 4-7 named threads)
4. 📊 By the Numbers (releases, repos-active trend, HIP arcs, keyword frequency)
5. 📚 Supporting Detail (aggregated weekly-style sections; omit any with no data)
6. 🗓️ Week-by-Week Index
7. Footer callout (ALWAYS last)

---

## TEMPLATE

```
<callout icon="🗓️" color="purple_bg">**Team Monthly Digest** | <MONTH_NAME> | <N_WEEKLIES> weeklies | <N_DAILIES> dailies | <N_REPOS> repos active | <N_RELEASES> releases | <N_PARTNERS> partner threads</callout>

---

## 📖 The Month in Review

NOTE: Keep the heading words "The Month in Review" - higher tiers extract this section's lead by name.
NOTE: 3-5 paragraphs. Write this LAST, from the storylines + weekly spine. This is the
NOTE: single most important section: someone who reads ONLY this should understand what the
NOTE: month was about. Lead with the arc, not a list. Outsider-readable (full Plain-English
NOTE: rules from /team-digest apply). No PR numbers here - this is the narrative; detail lives below.
NOTE:
NOTE: BAD:  "In May, hiero-consensus-node had 60 PRs, hiero-json-rpc-relay had 45 PRs..."
NOTE: GOOD: "May was the month the EVM relay got serious about the Pectra fork. What started as
NOTE:       scattered type-handling fixes in early weeks consolidated into a coordinated
NOTE:       readiness push, landing in the v0.x release at month-end - and three partners were
NOTE:       waiting on exactly that. In parallel, the tokenization reference stack closed its
NOTE:       external security audit..."

<Paragraph 1: the headline arc of the month>

<Paragraph 2-4: the other defining threads, how they connect, where the month landed>

---

## 🧵 Top Storylines

NOTE: 4-7 named threads. THIS IS THE POINT OF THE MONTHLY. A storyline is NOT "repo X was
NOTE: active" - it is "the effort to do Y, which pulled together repos A+B, HIP-N, a partner
NOTE: ask, and a Notion design doc." Each thread interconnects sources the dailies/weeklies
NOTE: kept in separate sections. Every entity is a markdown link.
NOTE:
NOTE: Each storyline uses the started -> middle -> where-it-landed -> what's-next shape:
NOTE: source the arc from the weekly bodies (esp. their "Threads to Watch" sections) + cross-week
NOTE: HIP status arcs + sustained GitHub themes + multi-week partner momentum.

### <Storyline title - plain English, e.g. "Pectra-fork readiness across the EVM stack">

<2-4 paragraph narrative. Where it started this month, how it progressed week over week, where
it landed by month-end, and what's still open. Weave in: the repos involved (linked), the
HIP(s) (linked, with status arc if any), the partner asks it answers (if any), the Notion
design docs that informed it (linked), and the release(s) it shipped in (linked).>

**Where it stands:** <one line - shipped / mid-flight / blocked, and the single most useful link>

NOTE: Repeat ### for each of the 4-7 storylines, most consequential first.

---

## 📊 By the Numbers

NOTE: Mostly skeleton-derived (cheap) - built from the page-properties query, not body fetches.

**Releases this month**

<table header-row="true">
<tr><td>Repo</td><td>Version</td><td>Date</td><td>What changed (plain English)</td></tr>
<tr><td>[<repo>](<repo-url>)</td><td>[<tag>](<release-url>)</td><td><YYYY-MM-DD></td><td><1-sentence: what changed for users></td></tr>
</table>

NOTE: Every release mentioned in any weekly's Releases section, deduped, grouped by repo. If none: "No releases this month."

**Activity trend**

- <N> digests present (<first date> to <last date>)<note any gaps: "missing 2026-05-12, 2026-05-19">
- Busiest stretch: <week label> (<N> repos active / <N> releases)
- Repos active across the month: <N unique>

**HIP movement this month**

NOTE: Omit if TEAM_DIGEST_HIP_ENABLED=0 or no HIP activity in any weekly. Cross-week status arcs are the high-value signal here.

- **[HIP-<N>](<url>) - <title>** - advanced <prev> -> <current> this month; implementation in [<repo>](url), [<repo>](url)
- Touched but no status change: [HIP-<X>](url), [HIP-<Y>](url)

**Keyword themes**

- Top keywords this month (by days appeared): **<kw>** (<N> days), **<kw>** (<N> days), ...

---

## 📚 Supporting Detail

NOTE: The exhaustive catalog so nothing is lost. Aggregate the weekly-style sections across the
NOTE: month. Omit any subsection with no data (no filler). Synthesize - do not paste weekly text.

### 📁 Top GitHub Themes

<2-4 paragraphs: repos with sustained month-long activity, linked. Lead with the user-visible theme in plain words.>

### 🤝 Partner Momentum

NOTE: Aggregate partner threads across the month. Companies appearing across multiple weeks get a
NOTE: "what moved this month" paragraph; single-touch companies get a one-line list. Omit if none.

#### <Company> (<N weeks>)

<1-2 sentences: what moved this month, what's open>

(Single touch: <Company A> (<week>), <Company B> (<week>).)

### 🔎 Notion Content Pulse

NOTE: The month's most consequential Notion pages (design docs, decisions), deduped, ranked by
NOTE: team-profile relevance + cross-week momentum. Each: linked title + what it is + why it matters this month.

- **[<Page Title>](<notion-url>)** - <what it is>; <why it mattered this month>

### 📰 Industry News Roundup

NOTE: Aggregate from the weeklies' Industry News, dedup by URL, group by category. Omit empty categories.

#### <category-label>

- [<title>](<link>) - <plain-English what happened>; relevant because <why it matters>

### 📌 Favorites Movement

NOTE: Pages from the weeklies' Favorites Movement that saw multi-week activity. Omit if none.

- **[<Page Title>](<notion-url>)** - active across <weeks>: <1-sentence what the sustained activity signals>

---

## 🗓️ Week-by-Week Index

NOTE: Navigation hub back into the weeklies (and via them, the dailies). Collapse it in a toggle so it stays out of the main flow. One line per weekly in the month, linked; note any missing weeks.

<details>
<summary>Open the week-by-week index (<N> weeklies)</summary>

- <WEEK_LABEL> (<start> to <end>): [<weekly title>](<weekly-page-url>)

</details>

---

<callout icon="ℹ️" color="gray_bg">**Auto-generated** by Team Monthly Digest | Synthesized from <N_WEEKLIES> weeklies + <N_DEEP> of <N_DAILIES> dailies read in full | Month: <MONTH_NAME> (<MONTH_START> to <MONTH_END>)</callout>
```

---

## FORMAT RULES (human reference - do not render in output)

### Monthly vs. weekly
- The storyline layer is the monthly's reason to exist - interconnect sources the lower tiers kept separate.
- Synthesize from the weekly spine; deep-fetch dailies only for facts the weeklies compressed away (capped).
- The footer's "N_DEEP of N_DAILIES read in full" line is mandatory honesty about the synthesis-of-synthesis tradeoff.

### Plain language (this is the top-of-stack overview)
- Lead with what the month MEANT, not the mechanism. Translate internal names, acronyms, and IDs, or leave them out and let links carry the detail. A reader should understand the page without opening a single link.

### Notion API hard constraints (same as daily/weekly)
- Callout emoji: standard Unicode only (🗓️ 📖 🧵 📊 📚 📁 🤝 🔎 📰 📌 ℹ️). Never `:shortcode:`.
- Callout blocks single-line: `<callout ...>content</callout>` on one line. Each newline is a block boundary.
- Toggles: `<details>` then `<summary>label</summary>` on separate lines, closed with `</details>`. Use for reference lists; never put a `## ` heading inside a toggle (the chunked write splits on `## `). Putting `<details>` and `<summary>` on the same line causes Notion to backslash-escape the `<` and render the toggle as literal text.
- Bold+code collision: bolded inline-code renders as `****` artifacts. Use `**[name](url)**` or `**name**`.
- No `\n` inside Mermaid node labels. Footer callout is ALWAYS last. No run-hygiene meta-sections.

### Links (same as daily/weekly)
- All Notion links from MCP responses only. Never construct from page titles.
- Weekly/daily page links from the `url` property of the `notion-query-data-sources` results.

### Quality (same gates as daily/weekly)
- Storyline titles + Month in Review: outsider-readable, lead with the user-visible arc.
- Every entity reference is a markdown link.
