# Token Efficiency Implementation Plan

## Problem Statement

The team-digest skill accumulates ~960K cached tokens over a typical 29-minute, 71-turn run. This causes the `notion-create-pages` tool call to fail with a "Stream idle timeout - partial response received" error when Claude's output stream times out generating the large page content. The assembled digest content is lost unless a safety file was written first.

**Observed from a real run (2026-05-15):**
- Duration: 1,727,259ms (~29 minutes)
- Cache creation: 415,686 tokens
- Cache reads: 545,563 tokens
- Output tokens: 35,602 (near the 32K output limit)
- Cost: $2.53
- Result: timeout at `notion-create-pages` step

**Root causes ranked by impact:**

1. Full Notion page bodies fetched for every keyword-matched page (`notion-fetch` returns entire page content - often 5-10K tokens per page)
2. Full PR description bodies in GitHub helper output (bodies can be 1-5K tokens each; many repos with many PRs)
3. Phase B child descent (up to 15 child pages fetched per qualifying favorite - each a full `notion-fetch`)
4. Quality scaffold re-reads (checks A/B/C cause Claude to re-read and regenerate large blocks of already-assembled content)
5. Large `notion-create-pages` payload generated in a single output block (the entire page as one tool call input)

---

## Phase 1: Quick Wins (Low effort, high impact)

These are targeted cuts to data volume with no architectural change.

### 1.1 - Cap GitHub PR/issue body excerpts to 150 chars

**Files:** `skills/team-digest/lib/fetch-github-prs.sh`, `fetch-github-issues.sh`

Current behavior: the Python parser trims to 200 chars but the raw `gh search` JSON includes much larger bodies that stay in context.

Change: in the Python `-c` pipeline, set `excerpt = (body or '')[:150].replace('\n', ' ')` and add a `# body truncated for token efficiency` note when truncated. Also strip markdown formatting (links, images, HTML comments) before truncating.

Estimated savings: 50-200K tokens depending on PR activity volume.

### 1.2 - Skip `notion-fetch` for keyword-matched pages when summary is sufficient

**File:** `skills/team-digest/SKILL.md` Step 3

Current behavior: after every `notion-search`, fetch each matched page in full with `notion-fetch`.

Change: only call `notion-fetch` on a page if the `highlight` from `notion-search` is under 100 chars (too short to write a useful summary from). If the highlight is 100+ chars, write the summary from the search result directly without fetching the full page. Add one sentence noting the summary is from search highlight, not full page.

Note: still always `notion-fetch` for Favorites (Step 3.5) since those are explicitly curated.

Estimated savings: 30-100K tokens depending on keyword hit count.

### 1.3 - Reduce Phase B child descent cap from 15 to 5

**File:** `skills/team-digest/SKILL.md` Step 3.5

Current cap: 15 children per qualifying parent favorite.

Change: reduce to 5. The typical case is an index page with a handful of active sub-pages; 15 is defense against a worst-case that rarely occurs and is very expensive when it does.

Estimated savings: up to 50K tokens on days with active favorites.

### 1.4 - Reduce `max_highlight_length` from 300 to 150

**File:** `skills/team-digest/SKILL.md` Steps 3 and 4

All `notion-search` calls currently use `max_highlight_length: 300`. This controls how much text is returned per result in the search response. Halving it reduces search response size.

Change: set `max_highlight_length: 150` on all `notion-search` calls.

Estimated savings: 10-30K tokens.

---

## Phase 2: Structural - Two-Phase Run (Medium effort, high impact)

Split the single long run into two short runs. Each phase has a fresh context window, dramatically reducing per-session token accumulation.

### 2.1 - Gather phase: save structured data to disk

Add a new flag `--gather-only` to the skill and script.

When `--gather-only` is set:
1. Run Steps 0-4 (GitHub scan, Notion keyword/favorites/partners) as normal
2. At the end of Step 4, instead of proceeding to write, serialize all gathered data to a JSON file at `/tmp/team-digest-dry-runs/team-digest-<DATE_LABEL>-data.json`
3. Print the file path and exit

The JSON structure:
```json
{
  "date_label": "2026-05-15",
  "start": "...",
  "end": "...",
  "github": {
    "<org>": {
      "priority_repos": { "<repo>": { "prs": [...], "issues": [...] } },
      "other_repos": { "<repo>": { "pr_count": N, "issue_count": N, "notable": "..." } }
    }
  },
  "rss_feeds": [...],
  "notion_keywords": [...],
  "notion_favorites": [...],
  "notion_partners": [...]
}
```

### 2.2 - Write phase: read data file, generate and upload

Add a new flag `--from-data-file <path>` (distinct from `--from-file` which uploads a pre-assembled markdown file).

When `--from-data-file` is set:
1. Read the JSON data file (small, fast)
2. Run Steps 4.5 and 5 only: quality scaffold, link audit, and Notion write
3. The context starts fresh and stays small because the data was serialized - no long tool call history

### 2.3 - Update `bin/team-digest-run.sh` for two-phase invocation

The script would chain the two phases automatically:
```bash
DATA_FILE="$DRY_DIR/team-digest-${DATE_LABEL}-data.json"
run_claude "/team-digest $DATE_ARG --gather-only"   # Phase 1: gather
run_claude "/team-digest $DATE_ARG --from-data-file $DATA_FILE"  # Phase 2: write
```

Each phase is a separate `claude -p` call with a fresh context window. Cost stays roughly the same (same tokens gathered), but no timeout risk because the write phase starts clean.

---

## Phase 3: Content Reduction (Medium effort, medium impact)

Reduce the volume of content generated in the digest itself.

### 3.1 - Cap priority repo narrative length

**File:** `skills/team-digest/SKILL.md` Step 2

Add an explicit rule: each priority repo narrative section (text + diagram) must not exceed 400 words. If there is more activity than can fit, summarize the remainder in a "Additional activity" bullet list (3-5 bullets, no full paragraph treatment).

### 3.2 - Skip `notion-fetch` for partner conversation pages when search highlight is sufficient

**File:** `skills/team-digest/SKILL.md` Step 4

Same principle as Phase 1.2: if the `notion-search` highlight is 100+ chars for a partner page, write the summary from the highlight without fetching the full page body. Only fetch full body when the highlight is too short for a useful action-item extraction.

### 3.3 - Remove quality scaffold re-reads

**File:** `skills/team-digest/SKILL.md` Step 4.5 (Part B)

The quality checks A/B/C currently ask Claude to "re-read" assembled content. In practice this means the model re-processes content already in context - it doesn't save tokens but signals the model to be more thorough. Replace with inline guidance: instead of "re-read and audit", audit paragraph-by-paragraph as you write (inline check), so no re-reading pass is needed.

---

## Phase 4: Write Optimization (Higher effort, eliminates timeout risk)

Make the Notion write itself timeout-proof by splitting it into two API calls.

### 4.1 - Create page with properties only, then update with content

**File:** `skills/team-digest/SKILL.md` Step 5

Change the write sequence:
1. Call `notion-create-pages` with title, properties (date, type, status, counts), and a placeholder body: `> Digest content loading...`
2. Extract the new page ID from the response
3. Call `notion-update-page` with the full page content, targeting the new page ID

The first call is fast (small payload, guaranteed to succeed). The second call carries the heavy content but can retry independently without re-running the entire pipeline.

If step 3 fails, the page exists with a placeholder body. The user can re-run `--from-file` to populate it, or delete the placeholder page and re-run from scratch.

Note: verify that `notion-update-page` supports replacing the full page body (not just updating properties). If the MCP tool only supports property updates, this approach may need a different strategy. Check the `notion-update-page` schema at implementation time.

---

## Implementation Order

| Phase | Effort | Estimated token reduction | Timeout risk after |
|-------|--------|--------------------------|-------------------|
| 1.1 (PR body cap) | 1-2 hours | 50-200K | Moderate |
| 1.2 (skip fetch on keywords) | 2-3 hours | 30-100K | Moderate |
| 1.3 (Phase B cap) | 30 min | up to 50K | Moderate |
| 1.4 (highlight length) | 30 min | 10-30K | Moderate |
| Phase 1 total | ~6 hours | 140-380K | Moderate |
| Phase 2 (two-phase run) | 1-2 days | near-zero (fresh context) | Very low |
| Phase 3 (content reduction) | 1 day | 50-150K | Low |
| Phase 4 (split write) | 2-4 hours | 0 (prevents timeout at write) | Eliminated |

**Recommended sequence:**
1. Do Phase 1 first - quick wins with immediate impact, no architecture change
2. Do Phase 4 next - eliminates the timeout at the write step specifically
3. Do Phase 2 if timeouts persist despite Phase 1+4 - structural fix for very large orgs
4. Do Phase 3 as ongoing polish

---

## Acceptance Criteria

A successful implementation should achieve:
- Total session token accumulation under 200K (within one context window)
- `notion-create-pages` call succeeds consistently without timeout
- Run duration under 10 minutes for typical day
- Cost under $0.80 per daily run
- Safety file still written before Notion write (current behavior preserved)
- `--from-file` recovery path still works as fallback
