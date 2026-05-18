# HIP Tracking in team-digest

This document explains the HIP Activity source and HIP cross-reference annotations. Iteration 1 introduced the source itself plus two matching strategies (Mechanism A = regex annotation, Mechanism B = per-HIP `gh search`). Iteration 2 added two more strategies, a unified confidence model (high / medium / low), a verbose-mode subsection for medium and low matches, a strategy-independent labeled set, and a calibration helper. Strategy 4 (LLM-driven similarity) is gated behind a Phase 2 trigger; see [Phase 2 gate](#phase-2-gate) below.

If you don't track Hedera/Hiero HIPs and want to disable this entirely, see [Opting out](#opting-out) below.

## What it does

The `/team-digest` daily skill scans the `hiero-ledger/hiero-improvement-proposals` repository for HIP files touched on the digest day, and:

1. Builds a `## HIP Activity` section under each `hiero-ledger` org header in the digest. Each HIP gets one of three entry shapes:
   - **Tier 1 (full):** HIP had a status change AND has implementation activity in `hiero-ledger/*` on the same day. Includes a `Status: <prev> -> <current>` callout, abstract excerpt, and a bulleted list of the implementation PRs/commits.
   - **Tier 2 (minimal):** HIP file was touched (e.g., abstract edit) but no status change and no implementation activity. One short paragraph noting the touch.
   - **Tier 2b (proposal):** HIP exists only as an open PR against the HIP repo, not yet merged. Renders with a gray "Proposed (PR open)" callout.
2. Annotates PRs and issues in any configured GitHub org with `Linked HIPs: HIP-N` when the PR title or body references a HIP number. This runs in the existing `fetch-github-prs.sh` and `fetch-github-issues.sh` helpers (Mechanism A) - no new API calls.
3. Cross-links: a PR in `hiero-consensus-node` that mentions `HIP-1137` gets a backlink `(implements [HIP-1137](url))` in the priority-repo narrative, and the corresponding HIP entry lists the PR under its "implementation activity" line.

If more than 10 HIPs were touched on the digest day, the top 10 (ranked status-changed-first) get full implementation-activity expansion; the rest appear in a single `### Other HIPs touched today` overflow list without implementation lookup. The cap is configurable via `hip_tracking.max_hips_with_implementation_expansion`.

The `/team-weekly` skill aggregates HIP entries from the past week's dailies into a `## HIP Movement This Week` theme. It does NOT re-scan the HIP repo - the weekly is a pure synthesis layer over the dailies.

## How it works

Six `lib/` helpers (four iteration-1, two iteration-2) plus inline Mechanism A annotation in `fetch-github-prs.sh` / `fetch-github-issues.sh` do the work:

- `lib/refresh-hip-index.sh` - keeps a local index of known HIP numbers at `~/.config/team-digest/hip-numbers.txt`. Refreshed at most weekly. Used to filter out false-positive HIP regex matches (e.g., `HIP-9999` mentioned in a PR body where no HIP-9999 exists).
- `lib/extract-hip-refs.sh` - pure-text utility that finds `HIP-N` patterns in arbitrary text. Iteration 2 bumped the regex from `\d{1,4}` to `\d{1,5}` (HIP-10000+ safe) and added a placeholder blocklist for `HIP-0000` and `HIP-9999`. Reads stdin, writes one HIP number per line to stdout. Filters against the known-HIPs index if present.
- `lib/fetch-hip-updates.sh` - fetches HIPs touched in a date window, with status-change detection and proposal-PR awareness. Returns one JSON record per touched HIP with frontmatter fields, abstract excerpt, and optional `prev_status`.
- `lib/fetch-hip-implementation-prs.sh` - Mechanism B: for one HIP, searches PRs (`gh search prs`) and commits (`gh search commits`) across configured `implementation_orgs` that reference it. Iteration 2 added `confidence: "high"`, `source: "mech_b"`, and `per_source` fields to every emitted PR and commit dict.
- `lib/fetch-hip-release-refs.sh` _(new in iteration 2)_ - Strategy 2: scans release notes from `implementation_orgs` repos for HIP references; emits one MatchRecord per (HIP, release) pair, attributed to PRs via `gh api compare/<prev>...<this>` and commit-message PR-number parsing. See [Strategy 2 - Release-Note Analysis](#strategy-2---release-note-analysis).
- `lib/fetch-hip-timeline-correlations.sh` _(new in iteration 2)_ - Strategy 3: batched per-org `gh search prs` for PRs created in the past 7d whose titles/labels match keywords from status-changed HIPs, with a HIP-category-to-repo tiebreaker map for 1-2-token overlap. See [Strategy 3 - Timeline Correlation](#strategy-3---timeline-correlation).
- `lib/calibrate-hip-matches.sh` _(new in iteration 2)_ - measures precision/recall/F1 of all strategies against the strategy-independent labeled set; emits baseline + per-run drift snapshots. See [Calibration](#calibration).

Mechanism A (regex annotation on existing PR/issue data) runs inside the existing `fetch-github-prs.sh` and `fetch-github-issues.sh` helpers - the same scan pass that already fetches PRs and issues now also pattern-matches HIP references in the body and title. Iteration 2 added a `(high)` confidence label inline: `Linked HIPs: HIP-1137 (high), HIP-1140 (high)`.

Mechanism B (per-HIP `gh search`) runs once per touched HIP in the daily pipeline's Step 2.3 (between `fetch-github-releases.sh` in Step 2 and `notion-search keywords` in Step 3). Bounded by `max_hips_with_implementation_expansion` (default 10) to keep the API budget predictable.

Strategies 2 and 3 run after Mechanism B as new Phase 2b and Phase 2c sub-steps inside Step 2.3. Strategy 4 (LLM identifier-generation + gitGrep) is a gated Phase 2 within iteration 2 and ships only if the Phase 1 calibration baseline fails the acceptance gate (recall < 0.7 OR ≥ 5 hand-known true matches missed).

## Confidence model

Every emitted MatchRecord carries a `confidence` of `high`, `medium`, or `low`, plus a `sources[]` list of which strategies contributed and a `per_source` map with each strategy's own confidence + reason. When two records share the dedup key `(hip_id, repo, pr_number)`, **MAX confidence wins** and the source list / per_source map are unioned. Default per-strategy emissions:

| Strategy | Reason | Emitted confidence |
|---|---|---|
| Mechanism A (regex annotation) | Explicit HIP-N in title/body, filtered through known-HIPs index | `high` |
| Mechanism B (per-HIP `gh search`) | Author of PR/commit named the HIP in searched text | `high` |
| Strategy 2 - HIP-N in release tag | Release tag/name contains the HIP token | `high` |
| Strategy 2 - HIP-N in release body | Release body mentions HIP but not the tag | `medium` |
| Strategy 3 - keyword overlap ≥ 3 | PR title/labels share 3+ tokens with HIP title | `medium` |
| Strategy 3 - keyword overlap 1-2 + category tiebreak | Weak overlap, but PR repo is in the HIP-category's expected-repo set | `low` |
| Strategy 4 - LLM identifier hit (gated) | Claude-generated identifiers matched in PR title/labels | `medium` |

The digest renders **only high-confidence matches** by default. Medium and low matches surface in a `### Lower-Confidence Matches` subsection when `TEAM_DIGEST_HIP_VERBOSE=1`. See [Verbose mode](#verbose-mode).

## Strategy 2 - Release-Note Analysis

`fetch-hip-release-refs.sh` scans releases from `implementation_orgs` repos in the digest window. For each release:

1. Extract HIP-N tokens from the release tag + name (`in_tag` reason, `high` confidence).
2. Extract HIP-N tokens from the release body (`in_body` reason, `medium` confidence; suppressed for HIPs already matched in the tag).
3. Find the previous release for the same repo via `gh api repos/<org>/<repo>/releases` sorted by `published_at`.
4. Compare the two tags via `gh api repos/<org>/<repo>/compare/<prev>...<this>` and parse `(#NNN)` tokens from each commit's message (GitHub default merge format).
5. Emit one MatchRecord per `(hip_id, repo, pr_number)` cross-product of (HIPs found, PRs attributed), capped at `strategy2.max_pr_attribution_lookups_per_release` (default 10).

Backfill mode (`--backfill N`) reaches back N days from the digest date; capped at `strategy2.max_backfill_days` (default 30); larger windows require `--force-backfill`.

If a release mentions more than `strategy2.max_refs_per_release` (default 50) HIPs, the helper logs a `[Notice]` on stderr and truncates.

## Strategy 3 - Timeline Correlation

`fetch-hip-timeline-correlations.sh` correlates today's status-changed HIPs against PRs created in the past 7 days across `implementation_orgs`:

1. Read HIPs from `fetch-hip-updates.sh`; filter to entries with `status_changed: true` AND `prev_status NOT IN (null, "Unknown")` (Tier 2 best-effort gate). Cap at `strategy3.max_correlation_hips` (default 10).
2. Extract up to 5 keywords per HIP title (English stopwords dropped, tokens of length ≥ 4 only).
3. Build one batched OR-query per org: `gh search prs "HIP-X OR HIP-Y OR kw1 OR kw2 ..." --owner <org> --created=<window>` with `--limit 100`.
4. Per-org budget cap: `strategy3.per_org_search_budget` (default 10) calls. Exponential 1s/2s/4s backoff on HTTP 422 / secondary-rate-limit; after 3 failed retries, the org emits a single `source: "s3_skipped"` record with `reason: "rate_limit_after_3_retries"` - the helper continues and does NOT crash the digest.
5. Score each candidate PR against each HIP. ≥ 3 keyword tokens overlapping = `medium`; 1-2 overlap + the PR's repo is in the HIP category's expected-repo set (`strategy3.category_to_repos`) = `low`; 0 overlap = drop.
6. Apply noise ceiling: for any repo with > `strategy3.noise_ceiling_commits_per_day` (default 20) commits on the digest day, downgrade its matches to `low` with reason `high-volume area (downgraded)`.

The category-to-repo map ships with reasonable defaults for HTS / HSS / HCS / Mirror Node / SDK in `config.template.json`; override per machine.

## Verbose mode

By default the digest renders only `confidence: high` matches in `## HIP Activity`. To see medium and low matches too, set `TEAM_DIGEST_HIP_VERBOSE=1` in the runtime environment. Persistent setting:

```bash
echo 'export TEAM_DIGEST_HIP_VERBOSE=1' >> ~/.config/team-digest/env
```

`bin/team-digest-run.sh` (and `bin/team-weekly-run.sh`) source this file automatically. The verbose subsection renders inside the existing `## HIP Activity` H2 boundary at H3 depth, so the chunked-write logic in Step 5.3 (sentinel-driven, H2-split) is unaffected.

The verbose subsection format includes the source label, confidence, matched keywords (Strategy 3), category tiebreak (Strategy 3), and per-source reason. `s3_skipped` rate-limit records render only in verbose mode with a special no-PR-link form.

## Calibration

The labeled set at `~/.config/team-digest/hip-code-mapper-labeled-set.json` is the source of truth for measuring matching quality. It is **strategy-independent**: built from HIP `Reference Implementation:` fields, maintainer manual recall, and hiero-agent index cross-check. Iteration-1 dry-run output is **explicitly excluded** as a seed (anti-circularity).

Run a one-shot baseline measurement after a clean dry-run:

```bash
/team-digest 2026-05-06 --dry-run
bash ~/.claude/skills/team-digest/lib/calibrate-hip-matches.sh --baseline \
  /tmp/team-digest-dry-runs/team-digest-2026-05-06-v1.md
```

This computes precision/recall/F1 per strategy and overall, writes `~/.config/team-digest/hip-calibration-baseline.json`, and reports Phase 1 acceptance:

- **PASS**: overall recall ≥ 0.7 AND missed ≤ 5
- **FAIL**: either condition broken → Phase 2 (Strategy 4) is unlocked

Every digest run also invokes `calibrate-hip-matches.sh --current-only` at finalize, emitting a per-run match-count distribution at `~/.config/team-digest/hip-calibration-current.json` and warning on stderr if the baseline is more than 180 days old.

### Calibration lenses + date-range window (iteration 3)

As of iteration 3, the baseline measures matching quality under **two lenses** so the HIP-doc-update class can be classified without inflating "implementation" false positives:

| Lens | What counts as a positive | What counts as a negative |
|---|---|---|
| `implementation` | PR is a code change in a production codebase (narrow) | PR is a HIP doc update OR test fixture |
| `useful_signal` | PR is worth surfacing in the digest (HIP doc updates + implementations) | PR is a test fixture or template placeholder |

The Phase 2 gate now uses the `useful_signal` lens because that's closer to the digest's actual purpose — every match should be useful signal regardless of whether it's production code.

The baseline run also accepts optional `--window-start YYYY-MM-DD --window-end YYYY-MM-DD` args to restrict the labeled positives to those whose `pr_merged_at` falls within the window. This addresses the date-scope mismatch surfaced in iteration 2 (a single-day dry-run was being measured against a labeled set spanning multiple years).

```bash
# Full labeled set (no date filter) - useful for "all-time recall"
bash skills/team-digest/lib/calibrate-hip-matches.sh --baseline /tmp/team-digest-dry-runs/team-digest-2026-05-06-v2.md

# Past-week window - aligns with the digest's PR-update window
bash skills/team-digest/lib/calibrate-hip-matches.sh --baseline /tmp/team-digest-dry-runs/team-digest-2026-05-06-v2.md \
  --window-start 2026-05-01 --window-end 2026-05-06
```

Labeled-set entries gained three optional fields in iteration 3: `is_hip_doc_update` (true for HIP-repo PRs that update the HIP document), `is_useful_signal` (true for both implementations and HIP-doc-updates; false for test-fixture FPs), and `pr_merged_at` (ISO date for the window filter). Existing entries without these fields are treated as `is_useful_signal: true` and in-scope by default for back-compat.

### Recalibration triggers

Re-run `--baseline` when any of:

1. Labeled set is more than 6 months old.
2. A new HIP-N has been published where N exceeds the labeled-set max by 100+.
3. Phase 2 (Strategy 4) has been triggered.
4. The per-run drift warning fires 3+ times in a 30-day window.

## Phase 2 gate

Strategy 4 (LLM identifier-generation + `gitGrep`) is intentionally NOT shipped by default; iteration 2 ships it only if Phase 1 (Strategies A + B + 2 + 3 + confidence + calibration) measurably under-performs. After the baseline runs, check `~/.config/team-digest/iteration-2-phase2-decision.json` (written by the gate script) for `decision: TRIGGER | DEFER`.

If `TRIGGER`: Strategy 4 ships next. Input is strictly `(HIP title, HIP abstract, PR title, PR labels)` - **never PR body content** (secret-leak mitigation). Cost-capped at `strategy4.cost_cap_usd` (default $2.00/run) with an 80% circuit-break and a "budget exhausted: N HIPs unscored" footnote.

If `DEFER`: Strategy 4 stays in the parking lot and the baseline metrics are recorded in `docs/roadmap.md` as the evidence for the deferral.

## Status-change detection

When `fetch-hip-updates.sh` finds a HIP file touched on the digest day, it compares the file's frontmatter `status:` value at the touching commit's parent against the value at the touching commit. If they differ AND both are parseable, the entry includes `prev_status` and renders a prominent `Status: Draft -> Last Call` callout. Tier 1 and Tier 2 entries use this same detection logic.

Failure modes:

- **Parent SHA cannot be resolved** (commit predates the day window edge) -> `prev_status` is omitted; only the current status renders.
- **Frontmatter is malformed** -> status field reads "Unknown" rather than aborting the entry.
- **Multiple commits in the same day** -> uses the latest commit's status as the "current" value and the earliest reachable parent as the "previous" value. Intermediate values are not surfaced.

## Opting out

Set `hip_tracking.enabled: false` in `~/.config/team-digest/config.json`:

```json
"hip_tracking": {
  "enabled": false
}
```

With this set:

- Step 2.3 in the daily pipeline is skipped entirely.
- The `Linked HIPs:` annotation in `fetch-github-prs.sh` / `fetch-github-issues.sh` is disabled.
- Audit check 9 in the Pre-Write Link Audit (Step 4.5) is a no-op.
- The weekly skill's `## HIP Movement This Week` theme is omitted.

The rest of the digest behaves identically to the pre-iteration-1 baseline. Forkers who don't track Hedera/Hiero HIPs should set this flag to `false` and ignore the rest of this doc.

An additional run-time gate exists via the `TEAM_DIGEST_HIP_ENABLED` environment variable. If exported as `0` in the shell that runs the digest, the HIP source and the weekly theme are skipped regardless of config. Useful for one-off backfills against historical dates where HIP scanning would be noise.

## Adding more `implementation_orgs`

By default, Mechanism B (per-HIP implementation search) only searches `hiero-ledger`. If your team has integration repos in another org that reference HIPs, add the org to `hip_tracking.implementation_orgs`:

```json
"hip_tracking": {
  "implementation_orgs": ["hiero-ledger", "your-integration-org"]
}
```

Each additional org adds one `gh search prs` call and one `gh search commits` call per active HIP per day. Budget accordingly if your team has many active HIPs: e.g., 10 active HIPs across 3 orgs = 60 additional `gh search` calls per daily run, well under the 30/hour rate limit per token but worth knowing if you also run other automation against the same `GH_TOKEN`.

## Pointing at a different HIP repo

If you maintain your own improvement-proposal repository in a different location, override the defaults:

```json
"hip_tracking": {
  "repo": "your-org/your-improvement-proposals",
  "path": "proposals"
}
```

The helpers assume `<repo>/<path>/<file>` where `<file>` matches `hip-*.md` or any `*.md` shape. The `path` field is the subdirectory the helpers scan; `repo` is the `owner/repo` slug.

## Troubleshooting

See [`docs/troubleshooting.md`](troubleshooting.md) for: empty HIP section when content was expected, stale known-HIPs index, Phase 4 update-step recovery via `--from-file`.

## What's parked for later

See [`docs/roadmap.md`](roadmap.md) for HIP-related items not yet shipped. P4a Phase 1 (Strategies 2 + 3 + confidence + calibration) shipped in iteration 2. Phase 2 (Strategy 4) is gated; ship-vs-defer outcome is recorded in `~/.config/team-digest/iteration-2-phase2-decision.json` and the roadmap doc. Still parked: GitHub Discussions integration (P5), monthly/quarterly synthesis (P6), and the option to consume an external `data/hips.json` cache directly instead of re-fetching (P4b).
