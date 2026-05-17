# Team Daily Digest - Output Template

This file is the canonical output format for `/team-digest`.
Edit this file to change how digests look. The skill reads it in Step 5 as the output contract.
`<PLACEHOLDER>` values are substituted at write time. Notion-flavored Markdown syntax throughout.

Inline annotations (lines starting with `NOTE:`) are instructions to the model - do not render them.

---

## SECTION ORDER

1. Header callout
2. Executive Summary
3. Top Picks: Notion Pages Worth Reading (omit if zero qualify)
4. Per-org blocks (priority repos + other active repos, one block per org)
5. Releases
6. Industry News (omit if no items from any feed)
7. Notion Keyword Monitor
8. Favorites Activity (omit if not configured)
9. Partner Conversations
10. Footer callout (ALWAYS last)

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

NOTE: 5-8 bullets. Each bullet must pass two tests before you write it:
NOTE: Q1 - Is it SPECIFIC? No "various improvements", "continued work on", "lots of activity", "dependency updates".
NOTE: Q2 - Does it state the CONSEQUENCE? Not just what happened, but what effect it has or why a reader should care.
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

- **<plain bold or [linked name](url)>** - <specific change in plain English>; <consequence or why it matters to a partner/reader>
- **<plain bold or [linked name](url)>** - <...>
(5-8 bullets; cover priority-repo highlights, releases, Notion design docs, partner conversations, industry news standouts)

---

## Top Picks: Notion Pages Worth Reading

NOTE: 3-5 pages from Notion Keyword Monitor + Favorites Activity. Omit section if zero qualify.
NOTE: Each entry: page title as a link, 2-3 sentences covering WHAT the page is + WHY it's worth reading NOW + one key fact.
NOTE: Omit pages whose title starts with "Team Daily Digest", "Team Weekly Digest", "SA Daily Digest".

- **[<Page Title>](<notion-url from MCP>)** - <what the page is about>. <why it's relevant right now - which team priority it touches, what decision it represents>. <one concrete fact that helps the reader decide whether to open it>
- **[<Page Title>](<notion-url from MCP>)** - <...>

---

# <org-name>

<!-- For orgs in hip_tracking.implementation_orgs (default: hiero-ledger): -->
## HIP Activity

<!-- Tier 1 entry (status changed AND implementation activity today) -->
### [HIP-<N>](<raw_url>) — <title>

<callout icon="📈" color="blue">
**Status: <prev_status> → <current_status>** · Type: <type> · Category: <category> · Author: [@<handle>](https://github.com/<handle>)
</callout>

<2-3 sentence narrative drawing on the abstract_excerpt and explaining the change>

**Implementation activity today:**

- [<repo> #<num>](<url>) — <plain-English what the PR does>, by [@<author>](https://github.com/<author>) (<state>)
- <N> commits in [<repo>](repo-url) referencing HIP-<N>: [<sha>](<commit-url>) "<subject>" by [@<author>](https://github.com/<author>)

<!-- Tier 2 entry (HIP touched but no status change, no implementation activity) -->
### [HIP-<N>](<raw_url>) — <title>

Status: <status> · Type: <type> · Category: <category> · Author: [@<handle>](https://github.com/<handle>)

Minor edits to the abstract today; no implementation activity in the configured `implementation_orgs`.

<!-- Tier 2b entry (proposal PR open against HIP repo, not yet on main) -->
### [HIP-<N>](<pr_url>) — <title> (Proposed)

<callout icon="📌" color="gray">
**Status: Proposed (PR open)** · Type: <type> · Category: <category> · Author: [@<handle>](https://github.com/<handle>)
</callout>

Proposed in [#<pr_num>](<pr_url>) against the HIP repository; not yet merged to main. <abstract_excerpt>

<!-- Tier 3 overflow (>10 HIPs touched) -->
### Other HIPs touched today

- [HIP-<N>](<url>) — <title> (<status>, no status change)
- ...

_(10-HIP implementation-expansion cap reached; HIPs above this line did not get implementation-activity lookup.)_

---

## Priority Repos

NOTE: If any priority repos had ZERO activity in the date window, collapse them into a single line at the top of this section:
NOTE: "Priority repos with no activity today: `<repo-a>`, `<repo-b>`."
NOTE: Do NOT emit an H3 heading + "No activity on <DATE_LABEL>." paragraph for each silent priority repo. Then only emit H3 entries for priority repos WITH activity.

### [<repo-name>](https://github.com/<org>/<repo>)

NOTE: Paragraph 1 - what MERGED. Lead with the user-visible change, not the PR number.
NOTE: BAD:  "[#1096](url) merged: ensures DEFAULT_ADMIN_ROLE is granted to token owner during deployment."
NOTE: GOOD: "A critical deployment bug was fixed: previously, if the token owner address was omitted during contract setup,
NOTE:       admin functions were permanently locked with no recovery path. Fixed in [#1096](url)."
NOTE:
NOTE: Paragraph 2 (optional) - what is OPEN and worth watching. Only include open PRs with real advisory relevance.
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

<Paragraph 1: what merged - plain English lead sentence, then cite PR numbers as links>

<Paragraph 2: open PRs worth watching - only include those with real advisory relevance>

<Mermaid diagram if a diagram trigger fired - see Quality check A>

**Relevance:** <why this matters to the team; use the team profile as the lens - integration impact, SDK changes, partner-facing APIs, breaking changes, content opportunities>

---

(Repeat ### for each priority repo with activity)

## Other Active Repos

NOTE: Every repo with at least one PR/issue/release in the window. No silent drops.
NOTE: One H3 entry per repo. Counts go in the heading; each item is a sub-bullet.
NOTE: Sub-bullet format: bold the user-visible change, then link the PR/issue, then "—" + one-clause why-it-matters when non-obvious.
NOTE: Order items within a repo: merged/released first, then open PRs by signal strength, then issues.
NOTE: Cap each repo at the top 3-5 items; trailing routine work goes in a final "+ N more" line linking the repo's PR list.

### [<repo-name>](https://github.com/<org>/<repo>) — <count summary>

- **<bold lead: the user-visible change>** ([#<num>](<url>)) — <one-clause why-it-matters when non-obvious>
- <next item, same shape>

NOTE: "<count summary>" examples: "1 merged, 3 open", "5 open PRs, 2 open issues", "[v0.155.0-rc1](url) released, 1 open PR".
NOTE: If a repo's only activity is one routine item (typo fix, CODEOWNERS, dep bump), the H3 heading + single bullet is fine.
NOTE: For Mechanism A HIP annotations, sub-bullets that touch a HIP should include the linked `[HIP-N](url)` in the bold lead or follow with "(implements [HIP-N](url))".

---

(Repeat ### for each repo with activity in this org)

(Repeat # org block for each org in config.github.orgs)

# Releases

<table header-row="true">
<tr><td>Repo</td><td>Tag</td><td>Date</td><td>Notes</td></tr>
<tr><td>[<repo>](<repo-url>)</td><td>[<tag>](<release-url>)</td><td><YYYY-MM-DD></td><td><1-sentence plain-English: what changed for users of this release></td></tr>
</table>

NOTE: If no releases: "No new releases on <DATE_LABEL>." (do not write the table)

---

# Industry News

NOTE: Required format per item: [title](link) - <plain-English what happened>; relevant because <why it matters for our Hedera/EVM work>
NOTE: DO NOT copy the raw RSS description or commit message verbatim as the summary.
NOTE: If you cannot write a genuine "relevant because" clause for an item, drop it.
NOTE:
NOTE: BAD:  - [EIP-7981 update](url) - Update EIP-7981 reference implementation by Toni Wahrstatter
NOTE: GOOD: - [EIP-7981 reference implementation updated](url) - the reference code for validator credential rotation was revised;
NOTE:         relevant because Hedera's Pectra compatibility work will need to handle this credential mechanism
NOTE:
NOTE: BAD:  - [Hedera Blog: Token Studio v3](url) - Token Studio version 3 is now available with new features.
NOTE: GOOD: - [Hedera Token Studio v3 released](url) - adds batch token operations and a drag-and-drop policy builder;
NOTE:         relevant because partners building tokenization tools can upgrade workflows without custom contract code

## <category-label>

- [<title>](<link>) - <plain-English what happened>; relevant because <why it matters for our Hedera/EVM work>

NOTE: For github:// commit-watch entries:
NOTE: - [<short-sha>](<commit-url>): <plain-English what changed in the spec>; relevant because <why it matters>
NOTE:
NOTE: Group by category from config. Omit a category subsection with zero items.
NOTE: Omit the entire Industry News section when ALL categories returned zero items.

---

# Notion Keyword Monitor

NOTE: Pages created on DATE_LABEL matching configured keywords. Each page ID appears at most once.
NOTE: Write a 2-4 sentence narrative per page: what it is, which keywords matched, why it matters for the team.
NOTE: Every page title is a link using the URL from the MCP response - never construct URLs from titles.

**[<Page Title>](<notion-url from MCP>)**
<2-4 sentence narrative: what this page is about and what it contains>
*Keywords matched: <keyword1>, <keyword2>*
*Relevance: <team-profile-driven note - what action or awareness this warrants>*

NOTE: If zero keyword hits: "No keyword matches for <DATE_LABEL>."

---

# Favorites Activity

NOTE: Pages from the Favorites list (and their direct child pages) edited on DATE_LABEL.
NOTE: Phase B only ran if at least one favorite was a qualifying parent (edited on DATE_LABEL).
NOTE: For child pages, note the parent: "(under [Parent Title](parent-url))"

**[<Page Title>](<notion-url from MCP>)** - last edited <last_edited_time>
<2-4 sentence summary of what changed or what the page contains>
**Relevance:** <why this update matters to the team>

NOTE: If Favorites configured but nothing updated: "No favorited pages or their child pages had updates on <DATE_LABEL>."
NOTE: Omit this entire section when the Favorites list is empty or unreachable.

---

# Partner Conversations

## <Company Name>

**[<Meeting Note Title>](<notion-url from MCP>)** - <date/time>
<2-4 sentence summary of the key discussion points - what was discussed, what decisions were made, what friction surfaced>

Action items:
- [ ] <action item with owner if named>
- [ ] <action item>

NOTE: Group by company. If zero partner conversations found: "No partner conversations found on <DATE_LABEL>."

---

<callout icon="ℹ️" color="gray_bg">
**Auto-generated** by Team Daily Digest | Scanned <N> repos across <orgs> | Data window: <DATE_LABEL> 00:00 - 23:59 UTC
</callout>
```

NOTE: For backfill runs, add inside the footer callout:
NOTE: "This is a backfill run; Notion keyword results reflect pages created on <DATE_LABEL> only (pages edited but not created on that date are not captured by Notion MCP search)."

---

## FORMAT RULES (human reference - do not render in output)

### Notion API hard constraints
- Callout emoji: standard Unicode only (📊 ℹ️ 📈 ⚠️ 📌 🤝). Never `:shortcode:` - Notion rejects them with a validation error.
- Bold+code collision: `` **`name`** `` renders as `**** ` artifacts. Use `**[name](url)**` or `**name**` instead. Never combine bold and backtick.
- No `\n` inside Mermaid node labels - Notion silently truncates after the newline.
- The footer callout is ALWAYS the last block. No meta-sections after it.
- No "Known limitations", "Caveats", or run-hygiene sections.

### Links
- All Notion page links use the exact URL from a `notion-search` or `notion-fetch` MCP response. Never construct from title.
- All repo/PR/issue/release/user links use the exact URL from gh CLI JSON output.

### Quality gates (enforced in Step 4.5 Part B before writing)
- Diagrams: required for every priority repo where a structural trigger fired (8 triggers listed in Quality check A)
- Executive Summary bullets: must pass Q1 (specific) and Q2 (consequence) before writing
- Industry News items: must have plain-English "what happened" + "why it matters" before writing
