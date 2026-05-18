# Configuration

team-digest uses a two-layer configuration system:

1. **Local config file** (`config.json`, gitignored) - Notion IDs and defaults per digest. Each user has their own.
2. **Notion config page** (per digest) - Live settings (keywords, repos, patterns) that anyone on the team can edit.

## Local Config File

The config file lives at the repo root as `config.json` (gitignored). It is also synced to `~/.config/team-digest/config.json` by `setup.sh` so skills can find it from any directory.

`config.template.json` is the committed template with empty Notion IDs. Run `setup.sh` to create `config.json` from the template, then fill in your IDs.

### Structure

```json
{
  "team-digest": {
    "notion": {
      "config_page_id": "<32-char hex from config page URL>",
      "database_id": "<32-char hex from database URL>"
    },
    "github": {
      "orgs": [
        {
          "name": "your-org",
          "priority_repos": ["repo-1", "repo-2"],
          "scan_all": false
        }
      ]
    },
    "rss_feeds": [
      {"name": "Example Blog",        "url": "https://example.com/feed",                "category": "blogs"},
      {"name": "Spec Set (commits)",  "url": "github://<owner>/<repo>/<path>",          "category": "specs"}
    ],
    "defaults": {
      "keywords": ["keyword-1", "keyword-2"],
      "partner_patterns": ["Meeting with", "Call with"]
    }
  }
}
```

Each digest type is a top-level key. Add a new key for each new team digest.

### RSS feeds (Industry News section)

The `rss_feeds` array drives the digest's **Industry News** section: public/external content your team should be aware of (blog posts, ecosystem announcements, spec changes). Two URL forms are supported:

- **Standard RSS / Atom feed:** `"url": "https://example.com/feed"` - fetched via `lib/fetch-rss.sh` (curl + Python stdlib XML parsing). Bring any feed URL.
- **GitHub commit watching:** `"url": "github://<owner>/<repo>"` or `"url": "github://<owner>/<repo>/<path>"` - fetched via `lib/fetch-gh-commits.sh`. Use this for content that lives in a public git repo but doesn't publish RSS (e.g., a spec set tracked via commits to a directory).

Each entry needs a `name` (display label), `url`, and `category` (grouping label that becomes a subheading in the Industry News output). Multiple feeds can share a category to group related sources together.

If `rss_feeds` is missing or empty, the Industry News section is silently omitted from the digest. If any feed returns no items for the digest day, that source is silently skipped. If every feed returns nothing, the whole section is omitted (no "no news today" filler).

### HIP tracking (`hip_tracking` block)

The `hip_tracking` config block controls the HIP Activity source (Step 2.3 of the daily pipeline) and the HIP cross-reference annotations (Mechanism A) in `fetch-github-prs.sh` / `fetch-github-issues.sh`. The full feature surface is documented in [docs/hip-tracking.md](hip-tracking.md); this section is the reference for the config fields.

Example block (the defaults from `config.template.json`):

```json
"hip_tracking": {
  "enabled": true,
  "repo": "hiero-ledger/hiero-improvement-proposals",
  "path": "HIP",
  "implementation_orgs": ["hiero-ledger"],
  "max_hips_with_implementation_expansion": 10
}
```

| Field | Default | When to override |
|---|---|---|
| `enabled` | `true` | Set to `false` to disable the HIP Activity source, the `Linked HIPs:` annotation in PR/issue helpers, the Pre-Write Link Audit check 9, and the weekly `HIP Movement This Week` theme. Forkers who don't track Hedera/Hiero HIPs should set this to `false`. |
| `repo` | `hiero-ledger/hiero-improvement-proposals` | Override if you maintain your own improvement-proposal repository. Format is `<owner>/<repo>`. |
| `path` | `HIP` | Subdirectory inside the HIP repo where `hip-N.md` files live. Note the singular `HIP`, not `HIPS` or `proposals` - confirmed by the canonical repo's tree. Override only if your repo uses a different subdirectory. |
| `implementation_orgs` | `["hiero-ledger"]` | Orgs that Mechanism B searches for HIP-referencing PRs and commits. Add additional orgs if your team has integration repos in another GitHub org that reference HIPs. Each additional org adds one `gh search prs` + one `gh search commits` call per active HIP per day. |
| `max_hips_with_implementation_expansion` | `10` | Cap on how many of the day's touched HIPs get full implementation-PR lookup (Mechanism B). HIPs above this cap appear in an `Other HIPs touched today` overflow list without expansion. Raise if your team routinely sees many active HIPs per day; lower to tighten the API budget. |

A run-time override exists via the `TEAM_DIGEST_HIP_ENABLED` environment variable. If exported as `0` in the shell that runs the digest, the HIP source is skipped regardless of config. Useful for historical backfills where HIP scanning would be noise.

If `hip_tracking` is missing from `config.json` entirely, the helpers fall back to the defaults above (enabled by default, on the canonical repo). Existing users who upgrade across iteration 1 do not need to edit their config unless they want to opt out or point at a different repo.

#### Iteration 2 additions (Strategies 2, 3, 4 + verbose mode)

Iteration 2 adds `strategy2.*`, `strategy3.*`, and (if Phase 2 triggers) `strategy4.*` sub-blocks. Defaults are encoded in `config.template.json` and the helpers fall back to them if the keys are missing; you only need to add the sub-blocks to your `config.json` if you want to override a default.

| Field | Default | What it controls |
|---|---|---|
| `strategy2.max_refs_per_release` | `50` | Cap on HIP references extracted per release. Overflow logs a `[Notice]` and is truncated. |
| `strategy2.max_backfill_days` | `30` | Default cap on `--backfill N` for `fetch-hip-release-refs.sh`. Larger windows require `--force-backfill`. |
| `strategy2.max_pr_attribution_lookups_per_release` | `10` | Cap on the PR-attribution lookups per release (compare-against-prev-tag → `(#NNN)` token parse). |
| `strategy3.max_correlation_hips` | `10` | Cap on how many status-changed HIPs Strategy 3 correlates per run. |
| `strategy3.per_org_search_budget` | `10` | Cap on `gh search` calls per org per run. Exponential 1s/2s/4s backoff on 429. |
| `strategy3.noise_ceiling_commits_per_day` | `20` | Repos with more than N commits on the digest day get their Strategy 3 matches downgraded to `low`. |
| `strategy3.category_to_repos` | (HTS/HSS/HCS/Mirror/SDK defaults; see `config.template.json`) | Tiebreaker map used when Strategy 3 keyword overlap is 1-2. Override if your team uses different repo names or categories. |
| `strategy4.cost_cap_usd` | `2.00` | Hard cap on Strategy 4 LLM cost per run (Phase 2 only). 80% warn, then exhaustion footnote. |
| `strategy4.min_abstract_chars` | `200` | Strategy 4 skips HIPs with abstracts shorter than this (Draft-HIP boilerplate gate). |

#### Verbose-mode env var

Set `TEAM_DIGEST_HIP_VERBOSE=1` to render the `### Lower-Confidence Matches` subsection with medium- and low-confidence HIP-to-code matches. Persistent setting (cron/launchd safe):

```bash
echo 'export TEAM_DIGEST_HIP_VERBOSE=1' >> ~/.config/team-digest/env
```

`bin/team-digest-run.sh` and `bin/team-weekly-run.sh` source this file. Default (env var unset) renders only high-confidence matches. See [`docs/hip-tracking.md` → Verbose mode](hip-tracking.md#verbose-mode).

#### GitHub scope minimization

Iteration 2 does NOT widen `GH_TOKEN` scope beyond iteration 1's requirements. All four strategies (A, B, 2, 3) work with `public_repo` (or no scope for tokens against fully-public org content). Strategy 4, when triggered, also does not require a new GitHub scope - it sends only HIP abstracts + HIP/PR titles + PR labels to the LLM provider, never PR bodies, so no scope escalation is needed.

#### `implementation_orgs` repo list maintenance

The `implementation_orgs` array (and `priority_repos` within `github.orgs`) is config-managed, not auto-discovered. When the hiero-ledger org renames, archives, or adds a repo, update your `~/.config/team-digest/config.json` to reflect the change. Strategies 2 and 3 enumerate repos via `gh api orgs/<org>/repos` at runtime (so additions are picked up automatically inside a known org), but the org list itself is fixed by config.

### GitHub authentication

The skill calls `gh search` / `gh api` via the helpers in `skills/team-digest/lib/`. These commands use whatever token `gh` itself resolves — in this order, highest priority first:

1. **`$GH_TOKEN` env var** — if set in the shell that runs the digest, `gh` uses it for every call.
2. **`$GITHUB_TOKEN` env var** — same behavior as `GH_TOKEN`, picked up if `GH_TOKEN` is unset.
3. **`gh auth login` credential** — the token `gh` stored in your OS keyring during the initial `gh auth login` flow.

The skill **never reads tokens from `config.json`** — env-var-only by design, so secrets never live on disk in a repo-adjacent config file. This is an intentional design choice: storing PATs in JSON config files creates leak surfaces (accidental commits, shell-output exposure, log capture by subprocesses) that env vars do not.

**When to set `GH_TOKEN` explicitly:**

- Your default `gh auth login` token hit rate limits (5,000 core API calls/hour, 30 search calls/hour for authenticated users) and you want a fresh PAT with the same scopes.
- You want richer per-PR / per-issue content via a PAT with `read:discussion` scope (gives access to GitHub Discussions, which the default `gh auth login` token often lacks).
- You're targeting private organizations and need `repo` scope rather than `public_repo`.
- You're running the digest from cron / launchd where the `gh` CLI keyring may not be accessible.

**Setting `GH_TOKEN`:**

```bash
# Interactive shell or one-off run:
export GH_TOKEN=<your_PAT>
bin/team-digest-run.sh

# Or inline for a single invocation:
GH_TOKEN=<your_PAT> bin/team-digest-run.sh

# In cron / launchd: set the env var in the wrapper script (NOT in your shell profile if the cron context doesn't source it).
```

**Required PAT scopes:** `public_repo` (or `repo` for private orgs) plus `read:discussion`. Any token that works for `gh search prs`, `gh search issues`, and `gh api repos/...` is sufficient.

**Creating a PAT:** https://github.com/settings/tokens → "Generate new token" (classic or fine-grained, both work). Save the value somewhere safe (1Password, Bitwarden, macOS Keychain) — GitHub only shows it once.

If neither env var is set and `gh auth status` fails, the skill aborts with an actionable error rather than producing a partial digest.

### Finding Notion IDs

You only need two IDs, and both are found the same way:

1. Open the Notion page or database in your browser
2. Look at the URL: `notion.so/<32-char-hex-id>`
3. That hex string is the ID

| Config Field | What to Open |
|---|---|
| `config_page_id` | The Notion configuration page |
| `database_id` | The Notion digest database |

The internal `data_source_id` (needed by the Notion MCP API to write pages) is derived automatically at runtime - you never need to look it up.

### Bootstrap your Notion workspace

If you don't already have Notion pages for the digest, the `setup` flow can create them for you:

```bash
/team-digest setup
```

When prompted "Do you already have Notion pages set up, or should I create them? [existing/new]", choose `new`. The skill will:

1. Create a parent page titled "Team Digest Workspace" at the workspace level (it lands in your Notion sidebar's Private section by default).
2. Create a "Team Digest Config" child page under the parent, prefilled with starter defaults — keywords (`AI`, `agent`, `MCP`, `API`), a comprehensive partner-pattern list, and a placeholder Favorites section. A yellow callout at the top reminds you to customize before your first real run.
3. Create a "Team Digest Entries" database under the parent, with the exact 6-property schema the skill writes to (`Digest Title`, `date`, `Digest Type`, `Repos Active`, `Keywords Matched`, `Status`). Do not modify the property names — the skills write specific values.
4. Write a starter team profile to `~/.config/team-digest/profiles/team-digest.md` (only if the file doesn't already exist — `setup.sh` may have installed one earlier; bootstrap respects it).
5. Write `~/.config/team-digest/config.json` with the two new Notion IDs (preserving any other digest-profile keys you already had).

**Workspace-level fallback:** if Notion rejects creating a workspace-level page (some MCP versions require an explicit parent), the skill will prompt you to paste a Notion parent page ID. Pick any page you have edit access to; the new artifacts will be created as children.

**Re-running `setup` is safe.** If your `config.json` already points to working Notion pages, `setup` detects that and stops with an "Already configured" message. If the stored IDs point to deleted or inaccessible pages, `setup` offers three options: re-bootstrap (create fresh pages and overwrite config), provide replacement IDs manually, or cancel.

**Edit before your first real run.** The defaults are useful for proving the pipeline works but won't surface team-specific content. Edit the Notion config page (keywords for what your team monitors, partner patterns for how you label meetings, favorites for documents you watch) and the local profile file (your team's role, priorities, glossary, and relevance heuristics) before running `/team-digest` for real.

### Joining an Existing Team

If the Notion database and config page already exist (a teammate set them up), ask them for the three IDs and paste them into your `config.json`. You do not need to create new Notion resources.

## Notion Config Page

The Notion config page holds the live, team-editable settings. The page ID is stored in your local `config.json`; the skill fetches the page at runtime.

### Editable Settings

**Priority Repos** - Repos that get full narrative summaries. All other repos in the org get a summary table entry.
- To add: add a bullet point with the repo name
- To remove: delete the bullet point

**Keywords** - Notion workspace search terms. Results are deduplicated across overlapping keywords.
- To add: add a bullet point
- To remove: delete the bullet point
- Tips: use specific terms; multi-word works; search is semantic

**Partner Conversation Patterns** - Phrases that identify meeting notes and partner discussions.
- To add: add a bullet point with the phrase
- To remove: delete the bullet point
- Tips: match your team's actual naming conventions for meeting notes

**Favorites** - A user-curated list of Notion pages the digest should check for updates each day. The Notion REST API does not expose a user's sidebar Favorites, so this list IS the digest's favorites: pages you care about regardless of keyword match. Each daily run fetches every page on the list and includes any that were edited (`last_edited_time`) during the digest's UTC date window.

- Add a heading **Favorites** (or **Favorite Pages**) on the config page
- Under it, paste a bullet list of Notion page URLs - one per line
- The skill accepts both full URLs (`https://www.notion.so/Page-Title-32hex`) and raw 32-char hex IDs
- To remove a favorite: delete the bullet point
- Empty or missing section means no favorites are scanned (the section is silently omitted from the digest)

**Single-level child descent.** If a favorited page is an *index* page (contains links to other Notion pages), the digest also fetches each linked page one level deep and includes those that were edited on the digest day. Caps at 50 child pages per favorite to bound cost. Child page entries in the digest always reference their parent favorite (e.g., `[Child Title](url) (under [Parent Favorite](parent-url))`). Loops are not a concern because there is no recursion past the first hop.

> **Access model.** The Notion-hosted MCP (the OAuth-based connector Anthropic ships) inherits workspace-wide access from your OAuth grant. You do NOT need to share each favorited page (or its children) with an integration manually - access is whatever your authenticated Notion session can see. If the digest logs `(not accessible)` on a favorite, the cause is almost always a deleted page, a moved page, a malformed URL, or a page in a workspace you yourself cannot read - treat it as a real signal, not expected setup friction.

**Organization** - The GitHub org to scan.

**Scan Window** - How far back to scan (default: 24 hours).

### Fallback Behavior

If the Notion config page is unreachable (MCP not connected, permissions issue), the digest falls back to the `defaults` section in your local `config.json`. This ensures the GitHub section still works even without Notion access.

## Adding a New Team Digest (LOCAL ONLY)

Additional team-specific digests live in your local checkout - do NOT commit them to this public repo.

1. Create a new Notion config page for the team (duplicate an existing one and update the settings)
2. Create a new Notion database for the team's digest output
3. Add a new key to your local `config.json` (NOT `config.template.json`):
   ```json
   {
     "team-digest": { ... },
     "<my-team>-digest": {
       "notion": {
         "config_page_id": "<new config page ID>",
         "database_id": "<new database ID>"
       },
       "github": {
         "orgs": [{"name": "<your-org>", "priority_repos": [], "scan_all": true}]
       },
       "defaults": { ... }
     }
   }
   ```
4. Copy `skills/team-digest/` to `skills/<my-team>-digest/` (including the `lib/` subdirectory)
5. Update the skill name, description, and all `team-digest` references in `SKILL.md` to match `<my-team>-digest`
6. Run `./update.sh` to install
