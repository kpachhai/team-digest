#!/usr/bin/env bash
# lib-assert.sh - tiny shared assertion helpers for the *.test.sh files.
# Source it from a test:  . "$(dirname "$0")/lib-assert.sh"
# NOT named *.test.sh on purpose, so the run-all.sh glob never executes it directly.
#
# Provides: PASS/FAIL counters and:
#   pass <desc>                         - record a pass
#   fail <desc> [detail]                - record a fail
#   assert_eq <desc> <expected> <actual>
#   assert_contains <desc> <needle> <haystack>
#   summary                             - print "PASS=N FAIL=M"; returns non-zero if any FAIL
#
# Tests capture command output and exit codes themselves (so stdin pipes and
# env-var prefixes work uniformly), then call these helpers.

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "ok   - $1"; }
fail() {
  FAIL=$((FAIL + 1))
  echo "FAIL - $1"
  [ "$#" -gt 1 ] && echo "        $2"
  return 0
}

assert_eq() {
  # assert_eq <desc> <expected> <actual>
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$2] got [$3]"; fi
}

assert_contains() {
  # assert_contains <desc> <needle> <haystack>
  case "$3" in
    *"$2"*) pass "$1" ;;
    *) fail "$1" "output does not contain [$2]" ;;
  esac
}

summary() {
  echo "---"
  echo "PASS=$PASS FAIL=$FAIL"
  [ "$FAIL" -eq 0 ]
}
