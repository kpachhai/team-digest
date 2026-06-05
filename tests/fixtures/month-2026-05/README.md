# Fixture month: May 2026 (synthetic)

Synthetic Team Daily + Weekly Digest inputs for hand-validating a `/team-monthly`
synthesis offline. These are NOT real digests - they are trimmed, fabricated pages
that exercise the monthly's storyline-stitching.

## The deliberate multi-week thread

All files carry one intentional thread so a reviewer can confirm the monthly connects it:

- **HIP-1137 status arc:** Draft (W19) -> Last Call (W20). A real monthly run reading more
  weeks would show this advancing to Accepted.
- **Sustained repo:** `hiero-json-rpc-relay` has Pectra-fork work in every file.
- **Recurring partner:** Acme Corp appears in both weeklies, gated on the relay work.

## How to use

There is no `--from-fixtures` mode (the skill reads from Notion). To validate offline,
hand-feed these files to a `/team-monthly --dry-run`-style synthesis (paste the weekly
bodies as if they were `notion-fetch` responses) and confirm the output's Top Storylines
section stitches the HIP arc + relay activity + Acme ask into one thread.

The weekly fixtures pass `tests/lint-digest-markdown.sh` (full mode); the dailies are
trimmed references.
