# team-digest Roadmap

What landed in iteration 1, what's parked for later, and how each parked item maps to a likely future iteration.

This file is the canonical home for "what's next" decisions. Spec section 20 of `docs/superpowers/specs/2026-05-16-team-digest-iteration-1-design.md` is the short-form preview; this file is the long form with rationale and gotchas per item.

## Iteration 1 (shipped 2026-05)

Tracked in `docs/superpowers/specs/2026-05-16-team-digest-iteration-1-design.md` and the matching plan. Highlights:

- HIP Activity source for the daily digest (Step 2.3), including Tier 1/2/2b/3 entry shapes and status-change detection.
- HIP cross-reference annotation (Mechanism A) on every PR/issue that names a HIP, with regex extraction filtered against a weekly-refreshed known-HIPs index.
- Per-HIP implementation-PR/commit search (Mechanism B), bounded by `max_hips_with_implementation_expansion` (default 10).
- Pre-Write Link Audit check 9: bare `HIP-N` text in prose must be a markdown link.
- HIP Movement This Week theme in `/team-weekly`, with cross-day status arcs and cross-repo implementation tracking.
- Token-efficiency Phase 1 (body cap, skip-fetch, child cap, highlight length) and Phase 4 (split `notion-create-pages` + `notion-update-page` to keep within the Notion MCP timeout budget).

User-facing surface lives in [`docs/hip-tracking.md`](hip-tracking.md), [`docs/configuration.md`](configuration.md), and [`docs/troubleshooting.md`](troubleshooting.md).

## Iteration 3 (shipped 2026-05-18)

Calibration-quality follow-ups surfaced by iteration 2's retrospective:

- **F1 - three-lens calibration:** `calibrate-hip-matches.sh` now reports metrics under two lenses against the labeled set: `implementation` (narrow, production-codebase code change) and `useful_signal` (broader, includes HIP-doc-update PRs which are valuable signal but not implementations). `phase2-gate.sh` uses the `useful_signal` lens for the Phase 2 gate decision (better aligned with the digest's purpose). The iter-2 "Mech B precision = 0" finding was a classification artifact, not a strategy failure - under the `useful_signal` lens, Mech B precision is **1.00**.
- **F2 - date-range window filtering:** `calibrate-hip-matches.sh --baseline` gains optional `--window-start YYYY-MM-DD --window-end YYYY-MM-DD` args. When set, labeled positives are filtered to those whose `pr_merged_at` falls in the window. Addresses the iter-2 date-scope mismatch where a single-day dry-run was being measured against a multi-year labeled set.
- **Labeled-set schema upgrade:** entries gained `is_hip_doc_update`, `is_useful_signal`, and `pr_merged_at` fields. 60 existing entries were backfilled via `gh pr view` for `pr_merged_at`; 16 HIP-repo entries got `is_hip_doc_update: true`. Existing entries without these fields are treated as `is_useful_signal: true` and in-scope by default (back-compat).

Real metrics against the 2026-05-06 dry-run + past-week window:

| Lens | Precision | Recall | F1 | TP / FP / FN |
|---|---|---|---|---|
| useful_signal | **1.00** | 0.59 | 0.74 | 10 / 0 / 7 |
| implementation | 0.50 | 0.45 | 0.48 | 5 / 5 / 6 |

Gate remains TRIGGER (recall 0.59 < 0.7) but the diagnostic shifted: the 7 missed are mostly PRs that merged earlier in the past week and weren't caught by the digest's `--updated=DATE_LABEL` filter. Strategy 4 (LLM identifier-generation) would not address this; iteration 4 candidate F4 (widen the digest's PR-update window, or multi-day backfill mode) is the real fix.

## Iteration 2 (Phase 1 shipped 2026-05; Phase 2 gated)

Tracked in `docs/superpowers/specs/2026-05-17-team-digest-iteration-2-design.md` and the matching plan. Phase 1 (always-ship) highlights:

- Strategy 2 - Release-Note Analysis (`fetch-hip-release-refs.sh`): scans implementation_orgs repos' release notes for HIP-N tokens in tag/name (high confidence) and body (medium confidence), attributes to PRs via compare-against-prev-tag commit-message parsing.
- Strategy 3 - Timeline Correlation (`fetch-hip-timeline-correlations.sh`): batched per-org `gh search prs` for past-7d PRs whose titles/labels share keywords with today's status-changed HIPs. HIP-category-to-repo tiebreaker map for 1-2-token overlap. Per-org budget, 429 backoff, noise-ceiling downgrade.
- Unified confidence model (high / medium / low) threaded through Mechanism A, B, Strategy 2, Strategy 3. MAX-confidence dedup on `(hip_id, repo, pr_number)` key.
- Verbose-mode `### Lower-Confidence Matches` subsection, gated on `TEAM_DIGEST_HIP_VERBOSE=1` (persistent setting via `~/.config/team-digest/env`).
- Strategy-independent labeled set at `~/.config/team-digest/hip-code-mapper-labeled-set.json` (≥30 entries / ≥10 negatives). Calibration helper (`calibrate-hip-matches.sh`) with baseline + per-run drift modes.
- T-pre: ported the chunked Notion write (commit 251830a from iteration 1) to `/team-weekly` for consistency, since the weekly synthesizes 5-7 dailies and hits the same stream-idle timeout.

Phase 2 (Strategy 4 - LLM identifier-generation + gitGrep) status: gated. Decision recorded in `~/.config/team-digest/iteration-2-phase2-decision.json` based on Phase 1 calibration baseline (`OR(recall < 0.7, missed >= 5)`). PR body content is explicitly excluded from Strategy 4 inputs as the strongest secret-leak mitigation.

## Iteration 4 (shipped 2026-05-18)

### F4 - PR-update window lookback (SHIPPED)

`compute-window.sh` gained an optional `--lookback-days N` flag and now also emits `LOOKBACK_START` + `LOOKBACK_DAYS` variables. SKILL.md reads the new `github.pr_lookback_days` config key (default `0` — preserves today's daily-cron behavior) and passes `$LOOKBACK_START` (instead of `$START`) to `fetch-github-prs.sh`, `fetch-github-issues.sh`, and Mechanism B's `fetch-hip-implementation-prs.sh` (via a new `--since-iso ISO` flag). Releases stay on the narrow window (a wider lookback would re-surface old releases).

When `pr_lookback_days > 0`:

- The digest header gets a `[Notice]` announcing the wider window.
- Each PR in the priority-repo narrative gets a `(merged YYYY-MM-DD)` suffix so readers can distinguish today's signal from the backfill.
- The iteration-3 calibration helper's `--window-start/--window-end` args should match the lookback window for meaningful precision/recall.

Trade-offs (documented in `docs/configuration.md`): a PR can re-appear in successive daily digests (no cross-day dedup in iteration 4); larger lookback = more `gh search` results (capped at 100 per call). Mech B remains bounded by `max_hips_with_implementation_expansion`.

The fix targets iteration 3's specific finding (7 in-scope labeled positives missed because they merged earlier in the week). Validation requires a maintainer-run dry-run with `pr_lookback_days: 7` and a re-baseline against `--window-start <DATE-7d> --window-end <DATE>`. Expected outcome: useful_signal recall lifts above 0.7; Phase 2 gate flips from TRIGGER to DEFER.

## Iteration 5 candidates

Items below are scoped enough to fit one or two iterations. Order is rough priority; reorder per upcoming need.

### F5 - Cross-day dedup for lookback-window PRs

**What:** when `pr_lookback_days > 0`, a PR that merged earlier in the week appears in each successive daily digest until it falls out of the window. Add a cross-day "previously surfaced" tracker so the same PR is rendered fully on day 1 and noted as `(previously surfaced YYYY-MM-DD)` on subsequent days.

**Why:** F4's main UX issue. Without dedup, the same PR clutters multiple consecutive daily pages.

**Approach sketch:**

1. Persist a `~/.config/team-digest/seen-prs.json` cache mapping `(repo, pr_number)` → first-surfaced-date.
2. At Phase 3 cross-link time, mark any PR whose `(repo, pr_number)` is in the cache and whose first-surfaced-date < today. Render with the `(previously surfaced YYYY-MM-DD)` annotation.
3. After successful Notion write, update the cache with today's date for any new PRs.
4. Cache prune: drop entries older than `max_backfill_days × 2`.

**Gotchas:**

- Multiple machines syncing the cache: probably out-of-scope; each machine has its own cache.
- The cache is part of the runtime state, not the labeled set or config. Document it.

### P1 - YouTube channel watching

**What:** Surface new uploads from configured YouTube channels in the digest, with optional transcript-derived topic summaries.

**Why:** A meaningful slice of ecosystem signal (conference talks, walkthroughs, partner channel content) lands as video, not text. Today the digest is blind to it.

**Approach sketch:** Each YouTube channel exposes an RSS feed at `https://www.youtube.com/feeds/videos.xml?channel_id=<ID>`. The existing `lib/fetch-rss.sh` already parses RSS - extending it would mostly mean recognizing YouTube-shape entries and rendering a thumbnail + duration. The bigger lift is transcript-derived topic extraction: fetch the timed-text transcript via `youtube-transcript-api` (Python) or the `yt-dlp` subtitle path, then summarize with an LLM call. Without summaries, you still get a list of "new videos from your watched channels today" which is useful on its own.

**Gotchas:**

- Transcript fetch is rate-limited and intermittently blocked by YouTube. Cache aggressively.
- LLM summarization adds tokens. Budget realistically: ~1.5K tokens per 30-minute talk transcript at Sonnet pricing.
- Auto-generated transcripts have transcription errors; partner names get mangled. Use them for "what's this about" classification, not for verbatim quotes.

### P2 - X profile watching

**What:** Track new posts from configured X (Twitter) accounts of partners, ecosystem contributors, and key competitors.

**Why:** X is where a meaningful chunk of ecosystem announcements land first - sometimes hours or days before a blog post or release note. Today the digest waits for the eventual blog/release; we want the early signal.

**Approach sketch:** Three paths, in increasing cost and decreasing fragility:

1. **Slack-link-to-X heuristic:** if your team already shares interesting X links in Slack, scan a designated channel and surface today's links as the "X signal." Free, no auth, but only catches what someone posted to Slack.
2. **Chrome MCP scraping fallback:** open profile pages in an authenticated Chrome session via the existing Chrome MCP fallback chain (see global CLAUDE.md). Fragile against UI changes, but cost is zero per call.
3. **X API key:** the only durable solution. Costs $200/month for the Basic tier as of late 2025; "Free" tier is read-only and rate-limited too low for daily polling of 10+ accounts.

**Gotchas:**

- X actively breaks scraping. The Chrome MCP path will need maintenance every few months when their DOM shifts.
- Authenticated rate limits on the Free API tier are too tight even for one daily run across 10 accounts. Pricing realistically gates this on the Basic tier.
- Quoted posts, replies, and threads all have different surface shapes - the parser needs to handle each.

### P3 - Slack channel watching

**What:** Scan configured Slack channels for keyword-relevant messages on the digest day.

**Why:** Several teams keep significant ecosystem and customer signal in Slack threads that never make it to Notion or GitHub. The digest is currently blind to that surface.

**Approach sketch:** Slack provides a Web API with `conversations.history` for channel reads. Auth requires either an OAuth bot token (needs workspace admin install) or a user token (user-scoped, simpler for a one-person setup). The helper would be `lib/fetch-slack-messages.sh` taking `<channel-id> <YYYY-MM-DD>` and returning a JSON array of messages with author handle, timestamp, text, and permalink.

**Gotchas:**

- PII-sensitive on a committed repo. The channel list, bot token, and any default scan queries belong in `~/.config/team-digest/config.local.json` (gitignored) per the dotfiles discipline; they must not land in `config.template.json` even as placeholder values.
- Slack rate limits are tier-1 (~50 calls/minute) - fine for daily scans, would need attention for backfills.
- Thread reply context matters: a top-level message reading "yep, that works" is meaningless without the parent. Either fetch threads when a parent has replies, or skip messages with no significant content of their own.

### P4a - Advanced HIP-to-code mapping strategies (SHIPPED iteration 2 Phase 1; Phase 2 gated)

**Status:** Phase 1 shipped 2026-05 - Strategies 2 (release-note analysis) + 3 (timeline correlation) + confidence model + verbose mode + calibration. Strategy 4 (LLM semantic) is gated by Phase 1 calibration outcome; see `~/.config/team-digest/iteration-2-phase2-decision.json` for the actual decision and `docs/hip-tracking.md` for the operational surface. Below is the original parking-lot text preserved for context.

**What:** Beyond the iteration-1 Mechanism A (regex annotation) and Mechanism B (per-HIP `gh search`), implement the richer matching strategies from a companion `hiero-agent` repo's `tools/hip-code-mapper` module: release-note analysis, timeline correlation, and LLM semantic similarity scoring.

**Why:** Mechanism A + B catch the obvious "PR title mentions HIP-N" case. They miss PRs that implement a HIP without naming it (the developer forgot, or the implementation predates the HIP merge), and they miss the "this commit on this date suspiciously aligns with HIP-X moving to Last Call" temporal pattern.

**Approach sketch:** Three additive strategies on top of A and B:

- **Strategy 2 - Release-note analysis:** when a release lands, scan its release notes for HIP references and back-attribute the change set to those HIPs.
- **Strategy 3 - Timeline correlation:** for HIPs that moved status in the past week, look at the day's commits in `implementation_orgs` repos for clusters in the same area of the codebase as the HIP's expected surface.
- **Strategy 4 - LLM semantic similarity:** embed HIP abstracts and PR descriptions, surface pairs with high cosine similarity. The `hiero-agent` reference budget-caps this at $2/run.

Each strategy adds a `confidence` field to the match record (high / medium / low). The digest renders only high-confidence matches by default; medium and low go to a verbose mode.

**Gotchas:**

- Strategy 4 is the only one with hard cost. Budget it explicitly (per-run cap), or pre-compute embeddings nightly and only score similarities at digest time.
- Confidence scoring is the load-bearing piece. Without it, false positives drown the digest signal. Calibrate against a labeled set of known-true matches before shipping.
- Test data from an existing `hiero-agent` mapper run is the natural starting point - copy its labeled set, don't re-build one.

### P4b - Cross-tool consumption from a `hiero-agent` cache

**What:** Read a companion `hiero-agent` repo's `data/hips.json` cache at runtime instead of re-fetching the HIP repo ourselves.

**Why:** `hiero-agent` already maintains a richer HIP cache (full bodies, parsed frontmatter, cross-reference indexes) refreshed on its own cadence. Reading the cache directly would zero out our HIP-fetch API budget and give us richer fields (the `hiero-agent` parser handles edge cases ours doesn't).

**Approach sketch:** Add a `hip_tracking.source` config field with two values: `"github"` (today's behavior) and `"hiero-agent-cache"`. The cache-backed path reads `data/hips.json` from a configured local `hiero-agent` checkout path and trusts whatever the cache says. The github path stays as today's fallback if the cache isn't installed.

**Gotchas:**

- Cross-tool dependency. If `hiero-agent` changes its cache schema, our reader breaks silently. Pin to a specific schema version field and surface a clear error on mismatch.
- The cache's freshness is `hiero-agent`'s call, not ours. Don't promise "today's HIP activity" when the cache is days old; surface the cache age in the digest section header.
- Some forkers won't have `hiero-agent` installed. The `"github"` default must stay the canonical path; cache-backed is opt-in.

### P5 - GitHub Discussions integration

**What:** Scan configured GitHub Discussions categories for new posts and replies on the digest day, the same way the digest scans PRs and issues today.

**Why:** A meaningful share of ecosystem design conversation lives in Discussions, not PR comments - especially in the HIP repo, where pre-PR design proposals get aired. Discussions are invisible to the digest today.

**Approach sketch:** Discussions live in the GitHub GraphQL API (not REST). The existing `gh api` calls use REST; this needs `gh api graphql -f query='...'`. A new `lib/fetch-github-discussions.sh` would take `<org> <repo> <YYYY-MM-DD>` and return a JSON array of discussion threads with new top-level posts or replies that day. The token needs the `read:discussion` scope, which iteration 1's `GH_TOKEN` documentation already nudges users toward.

**Gotchas:**

- GraphQL queries are versioned differently from REST and easier to break. Pin the query shape and snapshot-test it.
- Discussions are per-repo, not per-org. The helper has to enumerate repos (or take a hardcoded list) - same shape as how `fetch-github-releases.sh` enumerates.
- Long discussion threads need a "today's new content" filter, not a full-thread dump. Filter by `createdAt > digest_window_start`.

### P6 - Monthly / quarterly / yearly synthesis

**What:** Extend the `team-weekly` synthesis-from-existing-pages pattern to longer windows: a `team-monthly` that reads the past 4-5 weeklies and synthesizes month-spanning themes, and analogous `team-quarterly` and `team-yearly`.

**Why:** Weekly captures the cadence well; monthly captures the trajectory. A monthly is where you see "HIP-X moved from Draft to Accepted over the past month with implementation work in 4 repos" - a daily reader could not piece that together, and a weekly reader sees only one slice.

**Approach sketch:** The weekly is the proof-of-concept. The same shape extends: change the Notion property filter from `date in [Mon, Sun]` to `date in [Month-start, Month-end]` etc., read all weeklies in the window, synthesize cross-week themes. The theme set may differ - status-arc and cross-repo HIP work matter even more in a monthly view than in a weekly.

**Gotchas:**

- Synthesizing from synthesis. A monthly reads weeklies; each weekly is already a compression of dailies. Some signal is lost at each layer. Decide explicitly what monthly themes ask of the source data: if a monthly theme needs a fact that wasn't preserved in weeklies, the daily layer has to surface it.
- Render performance at the monthly/quarterly cadence: a quarterly reading 13 weeklies, each with 5-7 themes, easily produces a long Notion page. Audit the page-length budget.
- Cadence boundaries don't always align. ISO weeks cross month boundaries; iso quarters drift from calendar quarters by a few days. Pick one convention per cadence and stick to it.

### P7 - Token-efficiency Phases 2 + 3 (contingency)

**What:** Two further token-efficiency mechanisms beyond iteration 1's Phase 1 + Phase 4: Phase 2 splits the digest run into "gather" and "write" passes with a serialized intermediate file (`--gather-only` plus `--from-data-file`); Phase 3 applies deeper content reduction (per-repo narrative caps, skip `notion-fetch` in partner conversations).

**Why:** Iteration 1's Phase 1 + 4 hit the acceptance criteria (under 200K tokens per daily, under $0.80 per run, no timeouts). Phase 2 + 3 are the contingency for "Phase 1 + 4 prove insufficient" - we won't know that until we run for several weeks of HIP-active dailies.

**Approach sketch:** Phase 2 is the bigger architectural lift: the skill needs a clean serialization boundary between the data-gathering pipeline and the narrative-writing pipeline. Likely a JSON file at `/tmp/team-digest-data/<DATE>.json` that the gather pass writes and the write pass consumes. Phase 3 is per-section heuristics: cap each priority-repo narrative at N PR-narrative bullets, skip `notion-fetch` on partner-conversation pages where the title already encodes the action.

**Gotchas:**

- Defer until acceptance criteria measurably break. Premature optimization adds complexity for no benefit.
- Phase 2's serialization boundary is a behavior change - the gather pass and write pass run in different processes (probably different `claude -p` invocations). Lock down the JSON schema before splitting; otherwise the two passes drift.
- Phase 3's content-reduction heuristics are easy to over-tune. Each cut needs to be justified by a specific measured cost, not "this looks redundant."

---

## Deferred / not yet scoped

Items collected for future consideration but not yet planned. Add to this section when an idea surfaces that doesn't yet have an iteration target.

- **Per-section confidence tags in the daily digest header.** "GitHub: 100% / HIP: partial (rate-limited) / Notion keywords: skipped (MCP down)" so a reader instantly sees what to trust today.
- **Notion-side filter UI for the digest database.** A Notion view that hides "Auto" status pages by default, surfaces "Edited after auto-generation" pages explicitly. Quality-of-life, not functional.
- **Cross-team digest aggregation.** A separate `team-org-digest` skill that reads the daily digests of multiple teams and produces a cross-team rollup. Mentioned in the README; not yet specced.
