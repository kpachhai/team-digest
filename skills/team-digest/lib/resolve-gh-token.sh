#!/usr/bin/env bash
# resolve-gh-token.sh - resolve which GitHub token the digest run should use.
#
# Usage: cat <config-json> | resolve-gh-token.sh
#   (typically: pipe the output of load-config.sh through this helper)
#
# Resolution order (highest priority first):
#   1. $GH_TOKEN or $GITHUB_TOKEN env var → emit nothing (env already takes precedence)
#   2. github.token field in the piped config JSON → emit `export GH_TOKEN=<value>`
#   3. neither → emit nothing (gh CLI falls back to its stored auth)
#
# Output: one line on stdout, suitable for `eval`. Empty output is valid and
# means "do not override the existing token resolution."

set -euo pipefail

# Bail out early if either env var is already set — env wins.
if [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
  exit 0
fi

# Capture piped stdin into a variable; the python3 heredoc below uses its own
# stdin for the script body, so we cannot also read the config from stdin
# inside Python. Pass it through the environment instead.
CONFIG_JSON="$(cat)"

CONFIG_JSON="$CONFIG_JSON" python3 - <<'PY'
import json, os, sys

raw = os.environ.get('CONFIG_JSON', '')
if not raw.strip():
    sys.exit(0)

try:
    cfg = json.loads(raw)
except Exception:
    # Malformed input - silently do nothing, gh CLI fallback handles it.
    sys.exit(0)

token = (cfg.get('github') or {}).get('token', '').strip()
if not token:
    sys.exit(0)

# Use single quotes around the token value so embedded special chars don't break
# the eval. Tokens are ASCII alphanumerics + a few separators, no single quotes
# in practice, but defensive escaping is cheap.
escaped = token.replace("'", "'\\''")
print(f"export GH_TOKEN='{escaped}'")
PY
