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

### GitHub authentication

The skill resolves which GitHub token to use in this order, highest priority first:

1. **`$GH_TOKEN` or `$GITHUB_TOKEN` env var** — if either is set, it wins. Useful for one-off runs or CI where you want to override config without editing files.
2. **`github.token` field in `config.json`** — an optional PAT stored alongside your other team-digest settings. Empty string means "skip and fall through to (3)." This is the recommended option for cron and launchd, since the env-var approach requires you to wrap the cron entry with the token export.
3. **`gh auth login` fallback** — your local `gh` CLI session. The `bin/team-digest-run.sh` headless entry point inherits this auth, so simple setups work with no token configuration at all.

The helper at `skills/team-digest/lib/resolve-gh-token.sh` performs this resolution; both `/team-digest` and `/team-weekly` invoke it in Step 0 (right after `load-config.sh`).

**Required scopes:** `public_repo` (or `repo` for private orgs) plus `read:discussion`. Any token that works for `gh search prs` and `gh search issues` is sufficient.

**Setting `github.token` in `config.json`:**

```json
"github": {
  "token": "ghp_yourtokenhere",
  "orgs": [...]
}
```

Leave the field empty (`"token": ""`) to use the env-var or `gh auth` fallback. The template at `config.template.json` ships with an empty value so new installs default to the `gh` CLI flow.

If none of the three sources yields a usable token and `gh auth status` also fails, the skill aborts with an actionable error rather than producing a partial digest.

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
