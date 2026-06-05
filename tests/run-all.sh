#!/usr/bin/env bash
# run-all.sh - run every tests/*.test.sh and print a summary.
# Offline only (no network, no Notion MCP, no Claude). Exits non-zero if any
# test file fails. Run from anywhere:  bash tests/run-all.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

total_pass=0
total_fail=0
files_run=0
files_failed=0

echo "team-digest offline test suite"
echo "=============================="

for t in "$DIR"/*.test.sh; do
  [ -e "$t" ] || continue
  files_run=$((files_run + 1))
  name="$(basename "$t")"
  out="$(bash "$t" 2>&1)"
  code=$?
  line="$(echo "$out" | grep -E '^PASS=[0-9]+ FAIL=[0-9]+$' | tail -1)"
  p="$(echo "$line" | sed -n 's/^PASS=\([0-9]*\).*/\1/p')"; p="${p:-0}"
  f="$(echo "$line" | sed -n 's/.*FAIL=\([0-9]*\)$/\1/p')"; f="${f:-0}"
  total_pass=$((total_pass + p))
  total_fail=$((total_fail + f))
  if [ "$code" -eq 0 ] && [ "$f" -eq 0 ]; then
    printf "  PASS  %-34s %s assertions\n" "$name" "$p"
  else
    files_failed=$((files_failed + 1))
    printf "  FAIL  %-34s %s of %s failed\n" "$name" "$f" "$((p + f))"
    echo "$out" | grep '^FAIL' | sed 's/^/        /'
  fi
done

echo "------------------------------"
echo "Files: $files_run run, $files_failed failed | Assertions: $total_pass passed, $total_fail failed"
[ "$files_failed" -eq 0 ] && [ "$total_fail" -eq 0 ]
