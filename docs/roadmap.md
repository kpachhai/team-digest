# team-digest Roadmap

What's shipped today, what's parked for later, and the rationale for each parked item. This is the canonical home for "what's next" decisions.

For a date-anchored history of when each capability landed, see the git log (`git log --oneline docs/roadmap.md`) or `CHANGELOG.md` if present.

## Shipped capabilities

### Daily digest (`/team-digest`)

- HIP Activity source for the daily digest (Step 2.3), including Tier 1 / Tier 2 / Tier 2b / Tier 3 (overflow) entry shapes and status-change detection.
- HIP cross-reference annotation (Mechanism A) on every PR/issue that names a HIP, with regex extraction filtered against a weekly-refreshed known-HIPs index.
- Per-HIP implementation-PR/commit search (Mechanism B), bounded by `max_hips_with_implementation_expansion` (default 10).
- Pre-Write Link Audit check 9: bare `HIP-N` text in prose must be a markdown link.
- Strategy 2 - Release-Note Analysis (`fetch-hip-release-refs.sh`): scans implementation_orgs repos' release notes for HIP-N tokens in tag/name (high confidence) and body (medium confidence), attributes to PRs via compare-against-prev-tag commit-message parsing.
- Strategy 3 - Timeline Correlation (`fetch-hip-timeline-correlations.sh`): batched per-org `gh search prs` for past-7d PRs whose titles/labels share keywords with today's status-changed HIPs. HIP-category-to-repo tiebreaker map for 1-2-token overlap. Per-org budget, 429 backoff, noise-ceiling downgrade.
- Unified confidence model (high / medium / low) threaded through Mechanism A, B, Strategy 2, Strategy 3. MAX-confidence dedup on `(hip_id, repo, pr_number)` key.
- Verbose-mode `### Lower-Confidence Matches` subsection, gated on `TEAM_DIGEST_HIP_VERBOSE=1` (persistent setting via `~/.config/team-digest/env`).
- Strategy-independent labeled set at `~/.config/team-digest/hip-code-mapper-labeled-set.json` (≥30 entries / ≥10 negatives). Calibration helper (`calibrate-hip-matches.sh`) with baseline + per-run drift modes.
- Two-lens calibration: `calibrate-hip-matches.sh` reports metrics under two lenses against the labeled set: `implementation` (narrow, production-codebase code change) and `useful_signal` (broader, includes HIP-doc-update PRs which are valuable signal but not implementations). `strategy4-gate.sh` uses the `useful_signal` lens for the gate decision (better aligned with the digest's purpose).
- Date-range window filtering: `calibrate-hip-matches.sh --baseline` accepts optional `--window-start YYYY-MM-DD --window-end YYYY-MM-DD` args. When set, labeled positives are filtered to those whose `pr_merged_at` (or `attributed_to_releases` date) falls in the window — necessary when a single-day dry-run is measured against a labeled set spanning multiple years.
- Release-attribution credit: labeled-set entries can carry an `attributed_to_releases: [<date>, ...]` field. The calibration helper's `in_window()` returns true if `pr_merged_at` OR any `attributed_to_releases` date falls in the window. Required for Strategy 2 fidelity — S2 attributes HIPs to PRs included in releases published in the window, even if the PR itself merged earlier.
- Labeled-set schema: entries carry `is_hip_doc_update`, `is_useful_signal`, `pr_merged_at`, and optional `attributed_to_releases`. Entries without these fields are treated as `is_useful_signal: true` and in-scope by default (back-compat).
- PR-update window lookback: `compute-window.sh` accepts optional `--lookback-days N` and emits `LOOKBACK_START` + `LOOKBACK_DAYS`. SKILL.md reads the `github.pr_lookback_days` config key (default `0` — preserves daily-cron behavior) and passes `$LOOKBACK_START` to `fetch-github-prs.sh`, `fetch-github-issues.sh`, and Mechanism B's `fetch-hip-implementation-prs.sh` (via `--since-iso ISO`). Releases stay on the narrow window. When the lookback is > 0, the digest header gets a `[Notice]` and each PR gets a `(merged YYYY-MM-DD)` suffix.
- Deterministic matches.json consolidation: every match-producing helper writes structured JSON sidecars to `$TEAM_DIGEST_MATCHES_DIR`. After Claude exits, `bin/team-digest-run.sh` runs `consolidate-matches.sh` to merge them with MAX-confidence dedup on `(hip_id, repo, pr_number)`. Moves the canonical merge out of Claude's in-context state into deterministic shell — Claude proved lossy under high PR volume. The wrapper uses winner-by-volume directory discovery to handle env-var-propagation failure and mid-run Write-tool recoveries.
- Token-efficiency safeguards (body cap, skip-fetch, child cap, highlight length) and chunked Notion write (split `notion-create-pages` + `notion-update-page`) to stay within the Notion MCP timeout budget. Same chunked-write pattern applies to `/team-weekly`.

User-facing surface lives in [`docs/hip-tracking.md`](hip-tracking.md), [`docs/configuration.md`](configuration.md), and [`docs/troubleshooting.md`](troubleshooting.md).

### Strategy 4 (gated)

Strategy 4 (LLM identifier-generation + `gitGrep`) is gated by `lib/strategy4-gate.sh` against the calibration baseline. State machine: `DEFERRED_AWAITING_BASELINE` → `DEFER` (calibration met `recall >= 0.7 AND missed <= 5` on the `useful_signal` lens) or `TRIGGER` (otherwise). Strategy 4 ships only on `TRIGGER`. Decision recorded in `~/.config/team-digest/strategy4-gate-decision.json`. PR body content is explicitly excluded from Strategy 4 inputs as the strongest secret-leak mitigation.

## Calibration snapshot

Real metrics against a 2026-05-06 dry-run with a 7-day lookback window:

| Lens | Window | Precision | Recall | F1 | TP/FP/FN |
|---|---|---|---|---|---|
| useful_signal | [2026-04-29, 2026-05-06] | **1.00** | **0.52** | 0.69 | 11 / 0 / 10 |
| implementation | [2026-04-29, 2026-05-06] | 0.64 | 0.50 | 0.56 | 7 / 4 / 7 |

Per-strategy under useful_signal (windowed):

| Strategy | Records | TP | Precision | Recall |
|---|---|---|---|---|
| `mech_a` | 8 | 5 | 1.00 | 0.24 |
| `mech_b` | 9 | 4 | 1.00 | 0.19 |
| `s2` | 30 | 3 | 1.00 | 0.14 |
| `s3` | 0 | 0 | n/a | n/a |
| **Overall** | **46** | **11** | **1.00** | **0.52** |

Total matches.json: 46 records covering 12 distinct HIPs across the active strategies. **Zero false positives across all strategies.** S2 (release-note analysis) is the dominant volume contributor; Mech A + Mech B + S2 each have perfect precision.

Gate stays in TRIGGER (recall 0.52 < 0.7 threshold). But the diagnostic is honest: the 10 still-missed labeled positives are PRs in repos the digest already scans, just with different PR numbers than the helpers happened to surface. Strategy 4 (LLM identifier-generation) would not address that gap; the calibration is already against the system's real coverage.

**Recommendation:** keep Strategy 4 deferred. The mechanical gate-TRIGGER is conservative; the actual digest output is rich and high-precision. Future improvements come from extending the labeled set (which converges the recall metric to the real coverage).

## Parked items

Items below are scoped enough to fit one or two focused work sessions. Order is rough priority; reorder per upcoming need.

### Cross-day dedup for lookback-window PRs

**What:** when `pr_lookback_days > 0`, a PR that merged earlier in the week appears in each successive daily digest until it falls out of the window. Add a cross-day "previously surfaced" tracker so the same PR is rendered fully on day 1 and noted as `(previously surfaced YYYY-MM-DD)` on subsequent days.

**Why:** main UX issue with the lookback feature. Without dedup, the same PR clutters multiple consecutive daily pages.

**Approach sketch:**

1. Persist a `~/.config/team-digest/seen-prs.json` cache mapping `(repo, pr_number)` → first-surfaced-date.
2. At cross-link time, mark any PR whose `(repo, pr_number)` is in the cache and whose first-surfaced-date < today. Render with the `(previously surfaced YYYY-MM-DD)` annotation.
3. After successful Notion write, update the cache with today's date for any new PRs.
4. Cache prune: drop entries older than `max_backfill_days × 2`.

**Gotchas:**

- Multiple machines syncing the cache: probably out-of-scope; each machine has its own cache.
- The cache is part of the runtime state, not the labeled set or config. Document it.

### YouTube channel watching

**What:** Surface new uploads from configured YouTube channels in the digest, with optional transcript-derived topic summaries.

**Why:** A meaningful slice of ecosystem signal (conference talks, walkthroughs, partner channel content) lands as video, not text. Today the digest is blind to it.

**Approach sketch:** Each YouTube channel exposes an RSS feed at `https://www.youtube.com/feeds/videos.xml?channel_id=<ID>`. The existing `lib/fetch-rss.sh` already parses RSS - extending it would mostly mean recognizing YouTube-shape entries and rendering a thumbnail + duration. The bigger lift is transcript-derived topic extraction: fetch the timed-text transcript via `youtube-transcript-api` (Python) or the `yt-dlp` subtitle path, then summarize with an LLM call. Without summaries, you still get a list of "new videos from your watched channels today" which is useful on its own.

**Gotchas:**

- Transcript fetch is rate-limited and intermittently blocked by YouTube. Cache aggressively.
- LLM summarization adds tokens. Budget realistically: ~1.5K tokens per 30-minute talk transcript at Sonnet pricing.
- Auto-generated transcripts have transcription errors; partner names get mangled. Use them for "what's this about" classification, not for verbatim quotes.

### X profile watching

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

### Slack channel watching

**What:** Scan configured Slack channels for keyword-relevant messages on the digest day.

**Why:** Several teams keep significant ecosystem and customer signal in Slack threads that never make it to Notion or GitHub. The digest is currently blind to that surface.

**Approach sketch:** Slack provides a Web API with `conversations.history` for channel reads. Auth requires either an OAuth bot token (needs workspace admin install) or a user token (user-scoped, simpler for a one-person setup). The helper would be `lib/fetch-slack-messages.sh` taking `<channel-id> <YYYY-MM-DD>` and returning a JSON array of messages with author handle, timestamp, text, and permalink.

**Gotchas:**

- PII-sensitive on a committed repo. The channel list, bot token, and any default scan queries belong in `~/.config/team-digest/config.local.json` (gitignored) per the dotfiles discipline; they must not land in `config.template.json` even as placeholder values.
- Slack rate limits are tier-1 (~50 calls/minute) - fine for daily scans, would need attention for backfills.
- Thread reply context matters: a top-level message reading "yep, that works" is meaningless without the parent. Either fetch threads when a parent has replies, or skip messages with no significant content of their own.

### Cross-tool consumption from a `hiero-agent` cache

**What:** Read a companion `hiero-agent` repo's `data/hips.json` cache at runtime instead of re-fetching the HIP repo ourselves.

**Why:** `hiero-agent` already maintains a richer HIP cache (full bodies, parsed frontmatter, cross-reference indexes) refreshed on its own cadence. Reading the cache directly would zero out our HIP-fetch API budget and give us richer fields (the `hiero-agent` parser handles edge cases ours doesn't).

**Approach sketch:** Add a `hip_tracking.source` config field with two values: `"github"` (today's behavior) and `"hiero-agent-cache"`. The cache-backed path reads `data/hips.json` from a configured local `hiero-agent` checkout path and trusts whatever the cache says. The github path stays as today's fallback if the cache isn't installed.

**Gotchas:**

- Cross-tool dependency. If `hiero-agent` changes its cache schema, our reader breaks silently. Pin to a specific schema version field and surface a clear error on mismatch.
- The cache's freshness is `hiero-agent`'s call, not ours. Don't promise "today's HIP activity" when the cache is days old; surface the cache age in the digest section header.
- Some forkers won't have `hiero-agent` installed. The `"github"` default must stay the canonical path; cache-backed is opt-in.

### GitHub Discussions integration

**What:** Scan configured GitHub Discussions categories for new posts and replies on the digest day, the same way the digest scans PRs and issues today.

**Why:** A meaningful share of ecosystem design conversation lives in Discussions, not PR comments - especially in the HIP repo, where pre-PR design proposals get aired. Discussions are invisible to the digest today.

**Approach sketch:** Discussions live in the GitHub GraphQL API (not REST). The existing `gh api` calls use REST; this needs `gh api graphql -f query='...'`. A new `lib/fetch-github-discussions.sh` would take `<org> <repo> <YYYY-MM-DD>` and return a JSON array of discussion threads with new top-level posts or replies that day. The token needs the `read:discussion` scope.

**Gotchas:**

- GraphQL queries are versioned differently from REST and easier to break. Pin the query shape and snapshot-test it.
- Discussions are per-repo, not per-org. The helper has to enumerate repos (or take a hardcoded list) - same shape as how `fetch-github-releases.sh` enumerates.
- Long discussion threads need a "today's new content" filter, not a full-thread dump. Filter by `createdAt > digest_window_start`.

### Monthly / quarterly / yearly synthesis

**What:** Extend the `team-weekly` synthesis-from-existing-pages pattern to longer windows: a `team-monthly` that reads the past 4-5 weeklies and synthesizes month-spanning themes, and analogous `team-quarterly` and `team-yearly`.

**Why:** Weekly captures the cadence well; monthly captures the trajectory. A monthly is where you see "HIP-X moved from Draft to Accepted over the past month with implementation work in 4 repos" - a daily reader could not piece that together, and a weekly reader sees only one slice.

**Approach sketch:** The weekly is the proof-of-concept. The same shape extends: change the Notion property filter from `date in [Mon, Sun]` to `date in [Month-start, Month-end]` etc., read all weeklies in the window, synthesize cross-week themes. The theme set may differ - status-arc and cross-repo HIP work matter even more in a monthly view than in a weekly.

**Gotchas:**

- Synthesizing from synthesis. A monthly reads weeklies; each weekly is already a compression of dailies. Some signal is lost at each layer. Decide explicitly what monthly themes ask of the source data: if a monthly theme needs a fact that wasn't preserved in weeklies, the daily layer has to surface it.
- Render performance at the monthly/quarterly cadence: a quarterly reading 13 weeklies, each with 5-7 themes, easily produces a long Notion page. Audit the page-length budget.
- Cadence boundaries don't always align. ISO weeks cross month boundaries; ISO quarters drift from calendar quarters by a few days. Pick one convention per cadence and stick to it.

### Token-efficiency follow-ups (contingency)

**What:** Two further token-efficiency mechanisms beyond the existing safeguards: a "gather + write" two-pass mode (`--gather-only` plus `--from-data-file`) with a serialized intermediate file, and per-section content reduction (per-repo narrative caps, skip `notion-fetch` in partner conversations).

**Why:** Today's safeguards hit the acceptance criteria (under 200K tokens per daily, under $0.80 per run, no timeouts). These follow-ups are contingency for "today's safeguards prove insufficient" - won't know that until the system runs for several weeks of HIP-active dailies.

**Approach sketch:** The two-pass mode is the bigger architectural lift: a clean serialization boundary between the data-gathering pipeline and the narrative-writing pipeline. Likely a JSON file at `/tmp/team-digest-data/<DATE>.json` that the gather pass writes and the write pass consumes. Content-reduction is per-section heuristics: cap each priority-repo narrative at N PR-narrative bullets, skip `notion-fetch` on partner-conversation pages where the title already encodes the action.

**Gotchas:**

- Defer until acceptance criteria measurably break. Premature optimization adds complexity for no benefit.
- The two-pass mode is a behavior change - the gather pass and write pass run in different processes (probably different `claude -p` invocations). Lock down the JSON schema before splitting; otherwise the two passes drift.
- Content-reduction heuristics are easy to over-tune. Each cut needs to be justified by a specific measured cost, not "this looks redundant."

---

## Deferred / not yet scoped

Items collected for future consideration but without a sized approach yet. Add to this section when an idea surfaces that doesn't have a concrete plan.

- **Per-section confidence tags in the daily digest header.** "GitHub: 100% / HIP: partial (rate-limited) / Notion keywords: skipped (MCP down)" so a reader instantly sees what to trust today.
- **Notion-side filter UI for the digest database.** A Notion view that hides "Auto" status pages by default, surfaces "Edited after auto-generation" pages explicitly. Quality-of-life, not functional.
- **Cross-team digest aggregation.** A separate `team-org-digest` skill that reads the daily digests of multiple teams and produces a cross-team rollup. Mentioned in the README; not yet specced.
