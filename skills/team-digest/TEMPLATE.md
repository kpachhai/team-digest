# Team Daily Digest - Output Template

This file is the canonical output format for `/team-digest`.
Edit this file to change how digests look. The skill reads it in Step 5 as the output contract.
`<PLACEHOLDER>` values are substituted at write time. Notion-flavored Markdown syntax throughout.

Inline annotations (lines starting with `NOTE:`) are instructions to the model - do not render them.

**Placeholder legend (window-aware):** `<DATE_LABEL>` = the window label — a single date (`2026-06-09`) for a single-day digest, or `<start>..<end>` (`2026-06-08..2026-06-14`) for a range digest. `<TITLE>` follows TITLE LOCK: `Team Daily Digest` for a single day, `Team Digest` for a range. `<DATA_WINDOW>` = `<DATE_LABEL> 00:00 - 23:59 UTC` for a single day, or `<start> 00:00 - <end> 23:59 UTC` for a range.

**Reading experience (apply throughout):** these pages are read top-to-bottom by someone catching up, not debugging. Lead every item with what it MEANS in plain words; keep jargon, internal IDs, and long PR lists out of the main flow (link out, or tuck them into a `<details>` toggle). A reader should understand each section without opening a single link. Use the emoji section anchors below so sections are easy to find when scrolling.

---

## SECTION ORDER

1. Header callout
2. 🔑 Executive Summary
3. ⚠️ Heads up (optional - only when one item is genuinely critical)
4. ⭐ Top Picks: Notion Pages Worth Reading (omit if zero qualify)
5. Per-org blocks (priority repos + other active repos, one block per org)
6. 🚀 Releases
7. 📰 Industry News (omit if no items from any feed)
8. 🔎 Notion Keyword Monitor
9. 📌 Favorites Activity (omit if not configured)
10. 🤝 Partner Conversations
11. Footer callout (ALWAYS last)

---

## TEMPLATE

```
<callout icon="📊" color="blue_bg">**<TITLE>** | <DATE_LABEL> | <N_REPOS> repos active | <N_PRS> PRs updated | <N_ISSUES> issues updated | <N_RELEASES> releases | Data window: <DATA_WINDOW></callout>

---

## 🔑 Executive Summary

NOTE: This is the "what's worth knowing" section - a reader who only skims this should leave understanding the day. Keep the heading text "Executive Summary" (the cascade extracts this section by that name).
NOTE: 5-8 bullets. Each bullet must pass two tests before you write it:
NOTE: Q1 - Is it SPECIFIC? No "various improvements", "continued work on", "lots of activity", "dependency updates".
NOTE: Q2 - Does it state the CONSEQUENCE in plain words? Not just what happened, but what it means for a partner/reader.
NOTE: Lead with a plain-English bold phrase - NOT **`repo-name`** (produces artifacts). Use **[repo-name](url)** or **plain bold**.
NOTE:
NOTE: BAD:  - **`hiero-consensus-node`** architecture documentation - Three docs opened as PRs.
NOTE:       (fails Q1: what docs? fails Q2: so what? also has bold+code collision)
NOTE: GOOD: - **[hiero-consensus-node](url) publishes three architecture docs** - Restart, Event Creator, and Signed State Management
NOTE:       ADRs are now in review; these become the canonical reference for partners asking about consensus reliability guarantees.
NOTE:
NOTE: BAD:  - **`solo`** gains new features - MDC logging and silent mode added.
NOTE:       (fails Q2: what does that enable?)
NOTE: GOOD: - **[solo](url) becomes CI-scriptable** - a new `SOLO_SILENT_MODE` env flag disables interactive output, enabling
NOTE:       headless use in partner CI pipelines. Partners who currently can't automate solo can do so once this merges.
NOTE:
NOTE: Match framing to the window. Single-day digest: keep each bullet day-scoped (no "this week"). Range digest: period
NOTE: framing ("over this period", "this week") is fine. If cascade context surfaced an ongoing storyline, add at most ONE
NOTE: background clause - name the thread, do not claim a timespan the window does not cover.

- **<plain bold or [linked name](url)>** - <specific change in plain English>; <consequence or why it matters to a partner/reader>
- **<plain bold or [linked name](url)>** - <...>
(5-8 bullets; cover priority-repo highlights, releases, Notion design docs, partner conversations, industry news standouts)

---

NOTE: HEADS UP (optional) - include this ONE callout only when a single item is genuinely critical (a breaking change,
NOTE: a security fix, a partner-blocking regression). At most one per page; omit entirely on a normal day. Keep it
NOTE: single-line. The point is a can't-miss flag, so reserve it for things that truly cannot be missed.
<callout icon="⚠️" color="red_bg">**Heads up:** <the single most important thing today, in plain words> - <what to do / where to look> ([link](url))</callout>

---

## ⭐ Top Picks: Notion Pages Worth Reading

NOTE: 3-5 pages from Notion Keyword Monitor + Favorites Activity. Omit section if zero qualify.
NOTE: Each entry: page title as a link, 2-3 sentences covering WHAT the page is + WHY it's worth reading NOW + one key fact.
NOTE: Omit pages whose title starts with "Team Daily Digest", "Team Weekly Digest", "Team Monthly Digest", or "Team Digest - " (range-scan form), OR matches the regex `^[A-Z]{2,4} (Daily|Weekly|Monthly) Digest` (legacy short-prefix names).

- **[<Page Title>](<notion-url from MCP>)** - <what the page is about>. <why it's relevant right now - which team priority it touches, what decision it represents>. <one concrete fact that helps the reader decide whether to open it>
- **[<Page Title>](<notion-url from MCP>)** - <...>

---

# <org-name>

<!-- For orgs in hip_tracking.implementation_orgs (default: hiero-ledger): -->
## 🧩 HIP Activity

<!-- Tier 1 entry (status changed AND implementation activity today) -->
### [HIP-<N>](<raw_url>) — <title>

<callout icon="📈" color="blue">**Status: <prev_status> → <current_status>** · Type: <type> · Category: <category> · Author: [@<handle>](https://github.com/<handle>)</callout>

<2-3 sentence plain-English narrative: what this HIP changes and why it matters - no internal jargon>

<details><summary>Implementation activity (<N>)</summary>

- [<repo> #<num>](<url>) — <plain-English what the PR does>, by [@<author>](https://github.com/<author>) (<state>) `(<source-label> · <confidence>)`
- <N> commits in [<repo>](repo-url) referencing HIP-<N>: [<sha>](<commit-url>) "<subject>" by [@<author>](https://github.com/<author>) `(<source-label> · <confidence>)`

</details>

NOTE: `<source-label>` and `<confidence>` come from the MatchRecord (`per_source[<primary>]`). High-confidence matches render in this section by default; medium and low matches surface in the `### Lower-Confidence Matches` subsection at the end of HIP Activity when `TEAM_DIGEST_HIP_VERBOSE=1` is set. `<source-label>` maps: `mech_a` → regex, `mech_b` → per-HIP search, `s2_in_tag`/`s2_in_body` → release note, `s3` → timeline, `s4` → semantic. Use the source label of the primary (highest-confidence) match from `sources[]`.
NOTE: The `<details>` toggle keeps the per-PR detail collapsed so the narrative reads cleanly. If there is only ONE implementation item, you may keep it inline instead of in a toggle.

<!-- Tier 2 entry (HIP touched but no status change, no implementation activity) -->
### [HIP-<N>](<raw_url>) — <title>

Status: <status> · Type: <type> · Category: <category> · Author: [@<handle>](https://github.com/<handle>)

Minor edits to the abstract today; no implementation activity in the configured `implementation_orgs`.

<!-- Tier 2b entry (proposal PR open against HIP repo, not yet on main) -->
### [HIP-<N>](<pr_url>) — <title> (Proposed)

<callout icon="📌" color="gray">**Status: Proposed (PR open)** · Type: <type> · Category: <category> · Author: [@<handle>](https://github.com/<handle>)</callout>

Proposed in [#<pr_num>](<pr_url>) against the HIP repository; not yet merged to main. <abstract_excerpt>

<!-- Tier 3 overflow (>10 HIPs touched) -->
<details><summary>Other HIPs touched (<N>)</summary>

- [HIP-<N>](<url>) — <title> (<status>, no status change)
- ...

</details>

_(10-HIP implementation-expansion cap reached; HIPs above this line did not get implementation-activity lookup.)_

<!-- Verbose-only subsection (rendered when TEAM_DIGEST_HIP_VERBOSE=1). -->
<!-- Contains medium- and low-confidence matches from Strategies 2, 3, and 4. -->
<!-- Verbose-mode contract; see docs/hip-tracking.md "Verbose mode". -->
<details><summary>Lower-Confidence Matches (verbose)</summary>

_Surfaced because `TEAM_DIGEST_HIP_VERBOSE=1`. Signal-quality varies; cross-check before citing._

- **[HIP-<N>](<hip_url>)**: [PR #<num>](<pr_url>) by [@<author>](https://github.com/<author>) `(<source-label> · <confidence>)`
  - Source: <source-label>
  - Keywords: <comma-separated matched_keywords, if Strategy 3>
  - Category tiebreak: <category, if Strategy 3 used the category map>
  - Reason: <per_source[primary_source].reason>

</details>

NOTE: Render rows sorted by `hip_id` ascending then `confidence` descending (medium before low). If the verbose mode is off (env var unset / `0`), omit the entire `Lower-Confidence Matches` toggle and any medium/low matches that would have rendered there.

---

## 📁 Priority Repos

NOTE: If any priority repos had ZERO activity in the window, collapse them into a single line at the top of this section:
NOTE: "Priority repos with no activity in this window: `<repo-a>`, `<repo-b>`."
NOTE: Do NOT emit an H3 heading + "No activity." paragraph for each silent priority repo. Then only emit H3 entries for priority repos WITH activity.

### [<repo-name>](https://github.com/<org>/<repo>)

NOTE: Paragraph 1 - what MERGED, in plain English. Lead with the user-visible change, not the PR number.
NOTE: BAD:  "[#1096](url) merged: ensures DEFAULT_ADMIN_ROLE is granted to token owner during deployment."
NOTE: GOOD: "A critical deployment bug was fixed: previously, if the token owner address was omitted during contract setup,
NOTE:       admin functions were permanently locked with no recovery path. Fixed in [#1096](url)."
NOTE:
NOTE: Paragraph 2 (optional) - what is OPEN and worth watching. Only include open PRs with real advisory relevance.
NOTE:
NOTE: The narrative IS the summary - synthesize, do not enumerate. Put the full PR/issue list in the <details> toggle below
NOTE: so the main read stays clean. Skip the toggle if the repo had only one or two items (just cite them inline).
NOTE:
NOTE: DIAGRAM: Check the Quality Scaffold (Step 4.5 Part B, Quality check A) for whether this repo triggered a diagram.
NOTE: If a trigger fired, include a Mermaid diagram here showing the architectural change.
NOTE: Use graph TD with direction LR subgraphs for square layout. Single-line node labels only - no \n.
NOTE:
NOTE: DIAGRAM EXAMPLE (new FactoryFacet introduced in asset-tokenization-studio):
NOTE:
NOTE: ```mermaid
NOTE: graph TD
NOTE:   subgraph Before
NOTE:     direction LR
NOTE:     Owner --> TokenFacet
NOTE:     TokenFacet --> HTS
NOTE:   end
NOTE:   subgraph After
NOTE:     direction LR
NOTE:     Owner --> FactoryFacet
NOTE:     FactoryFacet --> TokenFacet
NOTE:     TokenFacet --> HTS
NOTE:   end
NOTE: ```

<Paragraph 1: what merged - plain English lead sentence, then cite the most significant PRs as links>

<Paragraph 2: open PRs worth watching - only include those with real advisory relevance>

<Mermaid diagram if a diagram trigger fired - see Quality check A>

**Relevance:** <why this matters to the team; use the team profile as the lens - integration impact, SDK changes, partner-facing APIs, breaking changes, content opportunities>

<details><summary>Notable PRs &amp; issues in this repo (top <N>)</summary>

NOTE: The narrative above is the summary. This toggle is the at-a-glance list of the SAME repo's top items - keep it capped at 3-5 (merged/released first, then high-signal open PRs), with a trailing "+ N more" link to the repo's PR list. Do NOT dump every PR; that bloats the page and the chunked write.

- **<bold lead: the user-visible change>** ([#<num>](<url>)) — <one-clause detail when non-obvious>
- <next item, same shape>
- [+ <N> more in this repo](https://github.com/<org>/<repo>/pulls)

</details>

NOTE: Include the toggle only when the repo had MORE items than the narrative names; skip it for a repo with one or two changes (just cite them inline).

---

(Repeat ### for each priority repo with activity)

## 📂 Other Active Repos

NOTE: Keep this as a `## ` H2 (the chunked write gives each H2 its own chunk; do not merge it into Priority Repos). The long tail of repos lives inside the toggle so it stays out of the main flow.
<details><summary>Other active repos in <org-name> (<N>) — tap to expand</summary>

NOTE: Every repo with at least one PR/issue/release in the window. No silent drops. One sub-list per repo.
NOTE: Sub-bullet format: bold the user-visible change, then link the PR/issue, then "—" + one-clause why-it-matters when non-obvious.
NOTE: Order items within a repo: merged/released first, then open PRs by signal strength, then issues.
NOTE: Cap each repo at the top 3-5 items; trailing routine work goes in a final "+ N more" line linking the repo's PR list.

**[<repo-name>](https://github.com/<org>/<repo>)** — <count summary>

- **<bold lead: the user-visible change>** ([#<num>](<url>)) — <one-clause why-it-matters when non-obvious>
- <next item, same shape>

NOTE: "<count summary>" examples: "1 merged, 3 open", "5 open PRs, 2 open issues", "[v0.155.0-rc1](url) released, 1 open PR".
NOTE: For Mechanism A HIP annotations, sub-bullets that touch a HIP should include the linked `[HIP-N](url)` in the bold lead or follow with "(implements [HIP-N](url))". The `Linked HIPs:` annotation line that the underlying helpers emit includes the confidence label inline (e.g. `HIP-1137 (high)`); preserve that label: `(implements [HIP-1137](url), high)`.

</details>

---

(Repeat # org block for each org in config.github.orgs)

# 🚀 Releases

<table header-row="true">
<tr><td>Repo</td><td>Tag</td><td>Date</td><td>What changed (plain English)</td></tr>
<tr><td>[<repo>](<repo-url>)</td><td>[<tag>](<release-url>)</td><td><YYYY-MM-DD></td><td><1-sentence plain-English: what changed for users of this release></td></tr>
</table>

NOTE: If no releases: "No new releases in this window." (do not write the table)

---

# 📰 Industry News

NOTE: Required format per item: [title](link) - <plain-English what happened>; relevant because <why it matters for our Hedera/EVM work>
NOTE: DO NOT copy the raw RSS description or commit message verbatim as the summary.
NOTE: If you cannot write a genuine "relevant because" clause for an item, drop it.
NOTE:
NOTE: BAD:  - [EIP-7981 update](url) - Update EIP-7981 reference implementation by Toni Wahrstatter
NOTE: GOOD: - [EIP-7981 reference implementation updated](url) - the reference code for validator credential rotation was revised;
NOTE:         relevant because Hedera's Pectra compatibility work will need to handle this credential mechanism

## <category-label>

- [<title>](<link>) - <plain-English what happened>; relevant because <why it matters for our Hedera/EVM work>

NOTE: For github:// commit-watch entries:
NOTE: - [<short-sha>](<commit-url>): <plain-English what changed in the spec>; relevant because <why it matters>
NOTE:
NOTE: Group by category from config. Omit a category subsection with zero items.
NOTE: Omit the entire Industry News section when ALL categories returned zero items.

---

# 🔎 Notion Keyword Monitor

NOTE: Pages created within the window matching configured keywords. Each page ID appears at most once.
NOTE: Write a 2-4 sentence plain-English narrative per page: what it is, which keywords matched, why it matters for the team.
NOTE: Every page title is a link using the URL from the MCP response - never construct URLs from titles.

**[<Page Title>](<notion-url from MCP>)**
<2-4 sentence narrative: what this page is about and what it contains>
*Keywords matched: <keyword1>, <keyword2>*
*Relevance: <team-profile-driven note - what action or awareness this warrants>*

NOTE: If zero keyword hits: "No keyword matches in this window."

---

# 📌 Favorites Activity

NOTE: Pages from the Favorites list (and their direct child pages) edited within the window.
NOTE: Phase B only ran if at least one favorite was a qualifying parent (edited in the window).
NOTE: For child pages, note the parent: "(under [Parent Title](parent-url))"

**[<Page Title>](<notion-url from MCP>)** - last edited <last_edited_time>
<2-4 sentence summary of what changed or what the page contains>
**Relevance:** <why this update matters to the team>

NOTE: If Favorites configured but nothing updated: "No favorited pages or their child pages had updates in this window."
NOTE: Omit this entire section when the Favorites list is empty or unreachable.

---

# 🤝 Partner Conversations

## <Company Name>

**[<Meeting Note Title>](<notion-url from MCP>)** - <date/time>
<2-4 sentence plain-English summary of the key points - what was discussed, what was decided, what friction surfaced>

Action items:
- [ ] <action item with owner if named>
- [ ] <action item>

NOTE: Group by company. If zero partner conversations found: "No partner conversations found in this window."

---

<callout icon="ℹ️" color="gray_bg">**Auto-generated** by <TITLE> | Scanned <N> repos across <orgs> | Data window: <DATA_WINDOW></callout>
```

NOTE: For past-window runs, append to the footer callout line (before the closing </callout>):
NOTE: " | Past-window run: keyword results reflect pages created in the window only."

---

## FORMAT RULES (human reference - do not render in output)

### Notion API hard constraints
- Callout emoji: standard Unicode only (📊 ℹ️ 📈 ⚠️ 📌 🤝 🔑 ⭐ 🧩 📁 📂 🚀 📰 🔎). Never `:shortcode:` - Notion rejects them with a validation error.
- Callout blocks must be single-line: `<callout icon="..." color="...">content</callout>` all on one line. Never put content on a new line after the opening tag; never put `</callout>` on its own line. The Notion MCP renderer treats each `\n` as a block boundary - multi-line callouts produce stray `</callout>` text blocks in the output.
- Toggles: `<details><summary>label</summary>` ... `</details>`. The `<summary>` line and the `</details>` close each go on their own line; block content (bullets, paragraphs) sits between them. Use toggles for depth (full PR lists, the long tail of repos), never for the headline narrative a reader needs to see.
- Bold+code collision: `` **`name`** `` renders as `**** ` artifacts. Use `**[name](url)**` or `**name**` instead. Never combine bold and backtick.
- No `\n` inside Mermaid node labels - Notion silently truncates after the newline.
- The footer callout is ALWAYS the last block. No meta-sections after it.
- No "Known limitations", "Caveats", or run-hygiene sections.

### Section anchors (emoji)
- Use the fixed anchors so sections are scannable: 🔑 Executive Summary · ⚠️ Heads up · ⭐ Top Picks · 🧩 HIP Activity · 📁 Priority Repos · 📂 Other active repos · 🚀 Releases · 📰 Industry News · 🔎 Notion Keyword Monitor · 📌 Favorites Activity · 🤝 Partner Conversations. Org `# <org-name>` headers stay plain (the name is the anchor).
- Keep the word "Executive Summary" in that heading - the cascade extracts the section by name.

### Plain language (these are overview pages)
- Lead every item with what it MEANS, not the mechanism. Translate internal class/method names, acronyms, and ticket IDs on first mention, or leave them out and let the link carry the detail.
- A reader should understand each section without opening a link. Links and toggles are for people who want to go deeper.
- Match framing to the scan window: no "this week" on a single-day digest.

### Links
- All Notion page links use the exact URL from a `notion-search` or `notion-fetch` MCP response. Never construct from title.
- All repo/PR/issue/release/user links use the exact URL from gh CLI JSON output.

### Quality gates (enforced in Step 4.5 Part B before writing)
- Diagrams: required for every priority repo where a structural trigger fired (8 triggers listed in Quality check A)
- Executive Summary bullets: must pass Q1 (specific) and Q2 (consequence) before writing
- Industry News items: must have plain-English "what happened" + "why it matters" before writing
- Heads up callout: at most one per page, omitted unless genuinely critical
