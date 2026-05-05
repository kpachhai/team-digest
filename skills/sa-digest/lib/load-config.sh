#!/usr/bin/env bash
# load-config.sh - read and validate the team-digest config for a given digest.
#
# Usage: load-config.sh <digest-name>
#   e.g. load-config.sh sa-digest
#
# Output: the digest's config object as JSON on stdout.
# Exits non-zero on missing/invalid config; errors go to stderr.
#
# Override the config path with TEAM_DIGEST_CONFIG=/path/to/config.json
# (defaults to ~/.config/team-digest/config.json).

set -euo pipefail

DIGEST_NAME="${1:?usage: load-config.sh <digest-name>}"
CONFIG_FILE="${TEAM_DIGEST_CONFIG:-$HOME/.config/team-digest/config.json}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: no config found at $CONFIG_FILE." >&2
  echo "       Run ./setup.sh from the team-digest repo, or '/sa-digest setup' in Claude Code." >&2
  exit 1
fi

python3 - "$DIGEST_NAME" "$CONFIG_FILE" <<'PY'
import json, sys

digest_name, config_file = sys.argv[1], sys.argv[2]

try:
    with open(config_file) as f:
        cfg = json.load(f)
except Exception as e:
    print(f'ERROR: failed to parse {config_file}: {e}', file=sys.stderr)
    sys.exit(2)

digest = cfg.get(digest_name)
if digest is None:
    print(f'ERROR: "{digest_name}" key missing from config at {config_file}', file=sys.stderr)
    sys.exit(3)

notion = digest.get('notion', {})
missing = [k for k in ('config_page_id', 'database_id') if not notion.get(k)]
if missing:
    print(f'ERROR: empty Notion IDs in {digest_name} config: {", ".join(missing)}', file=sys.stderr)
    print(f'       Edit {config_file} or run "/sa-digest setup".', file=sys.stderr)
    sys.exit(4)

json.dump(digest, sys.stdout, indent=2)
PY
