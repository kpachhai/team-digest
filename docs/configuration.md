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

The skill uses your local `gh` CLI authentication. Run `gh auth login` once (any scope is fine for public repos; for private repos you need at least `repo` read access). The `bin/team-digest-run.sh` headless entry point also inherits your local `gh` auth - cron and launchd both work without any token configuration.

If `gh auth status` fails when the digest runs, the skill aborts with an actionable error rather than producing a partial digest. There is no token-in-config fallback.

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

**Track Pages Created By** - A list of Notion user emails. The digest scans the workspace for pages created on the digest day where `created_by.person.email` matches one of these emails, and surfaces them in a dedicated "Pages I Created" section. Useful for catching new strategy docs, one-off notes, or fresh meeting pages that don't match keywords or partner patterns.

- Add a heading **Track Pages Created By** on the config page
- Under a sub-heading **Email** (or directly under the main heading), paste a bullet list of Notion user emails - one per line
- Empty or missing section means this scan is skipped (the section is silently omitted from the digest)
- Multi-team digest: list multiple emails to surface pages created by any teammate

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
