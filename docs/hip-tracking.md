# HIP Tracking in team-digest

This document explains the HIP Activity source and HIP cross-reference annotations that were added in iteration 1. If you don't track Hedera/Hiero HIPs and want to disable this entirely, see [Opting out](#opting-out) below.

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

Four `lib/` helpers do the work:

- `lib/refresh-hip-index.sh` - keeps a local index of known HIP numbers at `~/.config/team-digest/hip-numbers.txt`. Refreshed at most weekly. Used to filter out false-positive HIP regex matches (e.g., `HIP-9999` mentioned in a PR body where no HIP-9999 exists).
- `lib/extract-hip-refs.sh` - pure-text utility that finds `HIP-N` patterns in arbitrary text. Reads stdin, writes one HIP number per line to stdout. Filters against the known-HIPs index if present.
- `lib/fetch-hip-updates.sh` - fetches HIPs touched in a date window, with status-change detection and proposal-PR awareness. Returns one JSON record per touched HIP with frontmatter fields, abstract excerpt, and optional `prev_status`.
- `lib/fetch-hip-implementation-prs.sh` - for one HIP, searches PRs (via `gh search prs`) and commits (via `gh search commits`) across the configured `implementation_orgs` that reference it. Returns a JSON array of matches.

Mechanism A (regex annotation on existing PR/issue data) runs inside the existing `fetch-github-prs.sh` and `fetch-github-issues.sh` helpers - the same scan pass that already fetches PRs and issues now also pattern-matches HIP references in the body and title.

Mechanism B (per-HIP `gh search`) runs once per touched HIP in the daily pipeline's Step 2.3 (between `fetch-github-releases.sh` in Step 2 and `notion-search keywords` in Step 3). Bounded by `max_hips_with_implementation_expansion` (default 10) to keep the API budget predictable.

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

See [`docs/roadmap.md`](roadmap.md) for HIP-related items that didn't make iteration 1: GitHub Discussions integration (P5), advanced HIP-to-code mapping strategies with confidence scoring (P4a), and the option to consume an external `data/hips.json` cache directly instead of re-fetching (P4b).
