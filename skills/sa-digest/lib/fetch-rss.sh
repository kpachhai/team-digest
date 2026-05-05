#!/usr/bin/env bash
# fetch-rss.sh - fetch RSS/Atom feed entries published on a target date.
#
# Usage: fetch-rss.sh <feed-url> <YYYY-MM-DD>
#   e.g. fetch-rss.sh https://hedera.com/blog/rss.xml 2026-05-04
#
# Output: JSON array on stdout of `[{title, link, published, summary}]`,
# one entry per feed item whose pubDate (RSS) or updated/published (Atom)
# matches the target date in UTC. Empty array `[]` if no items match.
# Errors (non-XML response, network failure) go to stderr; exits 0 with
# `[]` on parse failures so the skill keeps going on a single bad feed.
#
# Token efficiency: returns titles + links + 400-char summaries only.
# The skill summarizes each item in 1-2 sentences with the link, so the
# helper deliberately does NOT fetch full article HTML.

set -euo pipefail

FEED_URL="${1:?usage: fetch-rss.sh <feed-url> <YYYY-MM-DD>}"
TARGET_DATE="${2:?usage: fetch-rss.sh <feed-url> <YYYY-MM-DD>}"

_py=$(mktemp /tmp/fetch-rss-XXXXXX.py)
trap 'rm -f "$_py"' EXIT
cat > "$_py" <<'PY'
import json, sys, xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
from datetime import datetime, timezone

target = sys.argv[1]
data = sys.stdin.read()

try:
    root = ET.fromstring(data)
except ET.ParseError as e:
    print(f"WARN: feed body is not valid XML: {e}", file=sys.stderr)
    print("[]")
    sys.exit(0)

ns = {"atom": "http://www.w3.org/2005/Atom"}
items = []

def to_utc_date(d):
    if not d:
        return None
    d = d.strip()
    try:
        if "," in d:  # RSS 2.0 RFC 822 format
            dt = parsedate_to_datetime(d)
        else:         # Atom ISO 8601 format
            dt = datetime.fromisoformat(d.replace("Z", "+00:00"))
        return dt.astimezone(timezone.utc).date().isoformat()
    except Exception:
        return None

# RSS 2.0 path: <rss><channel><item>...</item></channel></rss>
for item in root.iter("item"):
    pub = to_utc_date(item.findtext("pubDate"))
    if pub == target:
        items.append({
            "title": (item.findtext("title") or "").strip(),
            "link":  (item.findtext("link") or "").strip(),
            "published": pub,
            "summary": (item.findtext("description") or "").strip()[:400],
        })

# Atom path: <feed><entry>...</entry></feed>
for entry in root.findall("atom:entry", ns):
    pub_text = entry.findtext("atom:updated", "", ns) or entry.findtext("atom:published", "", ns)
    pub = to_utc_date(pub_text)
    if pub == target:
        link_el = entry.find("atom:link", ns)
        items.append({
            "title": (entry.findtext("atom:title", "", ns) or "").strip(),
            "link":  (link_el.get("href") if link_el is not None else ""),
            "published": pub,
            "summary": (entry.findtext("atom:summary", "", ns) or entry.findtext("atom:content", "", ns) or "").strip()[:400],
        })

print(json.dumps(items, ensure_ascii=False, indent=2))
PY

curl -fsSL --max-time 20 -A "team-digest/1.0" "$FEED_URL" | python3 "$_py" "$TARGET_DATE"
