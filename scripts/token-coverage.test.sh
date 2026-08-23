#!/usr/bin/env bash
#
# token-coverage.test.sh — the token check actually FINDS the tables it checks.
#
# WHY THIS TEST EXISTS. token-coverage locates token tables by matching an
# identifier pattern against the projected library. When the library's
# identifiers were respelled kebab-case, that pattern admitted only underscores,
# so it matched NO table at all — and the check then reported every declared
# pair as an undefined token table. The failure is loud in one direction and
# silent in the other: a pattern that matches nothing reports "no table" for a
# library that defines eleven, and a pattern that matches nothing would equally
# report OK for a library whose every token really was undefined, since a check
# with no tables has no lookups to fail.
#
# So the assertion is not merely "exit 0". It asserts a NON-ZERO table count
# against the real projection, which is the property a pattern regression
# breaks and an exit code alone cannot see.
#
# Usage: token-coverage.test.sh [repo-root]
# Exit:  0 all assertions pass, 1 an assertion failed, 2 a tool is missing.
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
  echo "token-coverage.test: error: python3 is required" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
pass_line() {
  printf '  ok   %s\n' "$1"
  PASS=$((PASS + 1))
}
fail_line() {
  printf '  FAIL %s\n' "$1"
  FAIL=$((FAIL + 1))
}

echo "token-coverage.test: the check finds the tables it checks"

# The library under test is the CURRENT projection of the committed schema, so
# a rename in the projector is caught here rather than in a host's layer.
if ! bash ./scripts/render-project schema/design-schema.json "$WORK/.render" >/dev/null; then
  echo "token-coverage.test: could not project the schema" >&2
  exit 2
fi

OUT="$(DESIGN_LIB_DIR="$WORK/.render" python3 ./scripts/token-coverage "$WORK" 2>&1)"
RC=$?

if [ "$RC" -eq 0 ]; then
  pass_line "a clean projection passes the token check"
else
  fail_line "a clean projection passes the token check (exit $RC: $OUT)"
fi

# The load-bearing assertion: tables were actually located. A pattern that
# matches nothing produces a report naming zero tables, which is the exact
# regression this file exists for.
COUNT="$(printf '%s' "$OUT" | sed -n 's/.*across \([0-9][0-9]*\) table(s).*/\1/p')"
if [ -n "$COUNT" ] && [ "$COUNT" -gt 0 ]; then
  pass_line "the check located $COUNT token table(s), not zero"
else
  fail_line "the check located no token table (report: $OUT)"
fi

# Every declared pair resolves. A pair naming a table the projector no longer
# emits under that spelling is the same regression seen from the other side.
MISSING="$(printf '%s' "$OUT" | grep -c 'defines no' || true)"
if [ "$MISSING" -eq 0 ]; then
  pass_line "every declared table pair resolves against the projection"
else
  fail_line "$MISSING declared pair(s) name a table the projection does not define"
fi

printf '\ntoken-coverage.test: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
