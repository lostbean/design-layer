#!/usr/bin/env bash
#
# designlib-native.test.sh — the NATIVE authoring surface of the projected
# library: the functions a `design.typ` calls directly.
#
# THE CONTRACT THIS ASSERTS, in two halves, because the library holds two
# classes of rule.
#
#   An INVARIANT must fail the build. Every invariant gets a fixture that
#   BREAKS it, and the test asserts the compile fails AND that the message
#   names the rule. An invariant with no failing fixture is advice wearing a
#   function signature.
#
#   A GUIDELINE must do BOTH things, and asserting only one of them is what
#   makes the test vacuous. It must COMPILE CLEAN by default — otherwise the
#   guideline is secretly still a gate — AND it must FAIL UNDER STRICT —
#   otherwise the rule was not relaxed, it was deleted, and the reference is a
#   comment nobody checks. assert_guideline asserts both from one fixture, so
#   neither half can be forgotten.
#
# The positive case is asserted too, and not merely that it exits 0: a document
# that compiles to a blank page is the failure mode a bare exit code misses, so
# the rendered PDF is read back as text and the drawing's own labels are
# asserted present. A drawing that silently renders nothing still compiles.
#
# The library is PROJECTED FRESH from the one declared schema. This repo ships
# no committed projection, and projecting here makes every assertion a
# statement about the schema as it stands rather than about a stale copy.
#
# Usage: designlib-native.test.sh [repo-root]
# Exit:  0 all assertions pass, 1 an assertion failed, 2 a tool is missing.
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1

TYPST="${TYPST:-typst}"
if ! command -v "$TYPST" >/dev/null 2>&1; then
  echo "designlib-native: error: no renderer on PATH (set TYPST or enter the dev shell)" >&2
  exit 2
fi
# The mark assertion reads the rendered PDF back as text. A test that cannot
# run must not report success, so a missing extractor is an error, never a SKIP.
if ! command -v pdftotext >/dev/null 2>&1; then
  echo "designlib-native: error: no pdftotext (enter the dev shell)" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if ! bash ./scripts/render-project schema/design-schema.json "$WORK" >/dev/null; then
  echo "designlib-native: could not project the schema" >&2
  exit 2
fi

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

# Compile a fixture body and capture combined output. Package resolution is
# pointed at a path that does not exist, so any attempt to reach the network
# surfaces as a failure here rather than succeeding on a warm cache.
compile() {
  local name="$1" strict="$2"
  local src="$WORK/$name.typ"
  local args=()
  [ "$strict" = "strict" ] && args+=(--input strict=1)
  env TYPST_PACKAGE_PATH="$WORK/nope" TYPST_PACKAGE_CACHE_PATH="$WORK/nope" \
    "$TYPST" compile "${args[@]}" --root "$WORK" "$src" "$WORK/$name.pdf" 2>&1
}

fixture() {
  printf '#import "designlib.typ": *\n%s\n' "$2" >"$WORK/$1.typ"
}

# An INVARIANT: the compile must fail, and the message must name the rule.
assert_invariant() {
  local name="$1" needle="$2" body="$3"
  fixture "$name" "$body"
  local out
  out="$(compile "$name" plain)"
  if [ -f "$WORK/$name.pdf" ]; then
    fail_line "$name: compiled, but the invariant should have stopped it"
    rm -f "$WORK/$name.pdf"
    return
  fi
  case "$out" in
  *"$needle"*) pass_line "invariant: $name names its rule" ;;
  *)
    fail_line "$name: failed, but the message does not name the rule"
    printf '       wanted: %s\n' "$needle"
    printf '%s\n' "$out" | head -3 | sed 's/^/       /'
    ;;
  esac
}

# A GUIDELINE: clean by DEFAULT, and a panic naming the rule under STRICT.
# Both halves from one fixture, so neither can be forgotten.
assert_guideline() {
  local name="$1" needle="$2" body="$3"
  fixture "$name" "$body"

  local out
  out="$(compile "$name" plain)"
  if [ -f "$WORK/$name.pdf" ]; then
    pass_line "guideline: $name compiles clean by default"
    rm -f "$WORK/$name.pdf"
  else
    fail_line "$name: a guideline blocked a default compile — it is still a gate"
    printf '%s\n' "$out" | head -3 | sed 's/^/       /'
  fi

  out="$(compile "$name" strict)"
  if [ -f "$WORK/$name.pdf" ]; then
    fail_line "$name: strict mode did not fire — the rule was deleted, not relaxed"
    rm -f "$WORK/$name.pdf"
    return
  fi
  case "$out" in
  *"[guideline]"*"$needle"*) pass_line "guideline: $name fails under strict, naming its rule" ;;
  *)
    fail_line "$name: strict failed, but not as a named guideline"
    printf '       wanted: %s\n' "$needle"
    printf '%s\n' "$out" | head -3 | sed 's/^/       /'
    ;;
  esac
}

echo "designlib-native: the native authoring surface"

# --- the positive case: it renders, and the marks are really on the page -----
# Asserted by reading the PDF back, because a drawing that renders nothing
# still exits 0 — the failure an exit code alone cannot see.
fixture render-positive '#show: design-doc.with(hero_title: [Doc])
#section(title: "One", lead: "A lead.", visual: diagram-native(
  altitude: "L2", title: "shape",
  nodes: ((id: "a", pos: (0,0), label: [Zalpha]),
          (id: "b", pos: (1,0), label: [Zbeta])),
  edges: (("a","b","Zgamma"),),
), body: [
  #points([A bullet.])
  #coverage(("part/x", "captured"), ("vendor/y", "out-of-scope", "Zreason"))
  #answers(title: "Unit", responsibility: [Zduty.])
])'
out="$(compile render-positive plain)"
if [ -f "$WORK/render-positive.pdf" ]; then
  text="$(pdftotext "$WORK/render-positive.pdf" - 2>/dev/null)"
  missing=""
  for mark in Zalpha Zbeta Zgamma Zreason Zduty; do
    case "$text" in
    *"$mark"*) ;;
    *) missing="$missing $mark" ;;
    esac
  done
  if [ -z "$missing" ]; then
    pass_line "a native document renders its diagram, table, and panel marks"
  else
    fail_line "the document compiled but these marks are absent:$missing"
    fail_line "  (a page that renders nothing still exits 0)"
  fi
else
  fail_line "the positive fixture did not compile"
  printf '%s\n' "$out" | head -5 | sed 's/^/       /'
fi

# --- invariants: a wrong value has no defensible reading ---------------------
assert_invariant diagram-ghost-edge "not a declared node" \
  '#diagram-native(altitude: "L1",
     nodes: ((id: "a", pos: (0,0), label: [A]),),
     edges: (("a","ghost","x"),))'

assert_invariant diagram-empty "at least one node" \
  '#diagram-native(altitude: "L1", nodes: (), edges: ())'

assert_invariant diagram-altitude "diagram altitude" \
  '#diagram-native(altitude: "L9",
     nodes: ((id: "a", pos: (0,0), label: [A]),), edges: ())'

assert_invariant coverage-unreasoned "states no reason" \
  '#coverage(("part/x", "out-of-scope"))'

assert_invariant coverage-status "coverage status" \
  '#coverage(("part/x", "maybe", "why"))'

assert_invariant pending-date "must be a YYYY-MM-DD date" \
  '#pending-ledger(pending-entry(title: "T", kind: "verify", since: "soon")[b])'

assert_invariant pending-build-adr "cites no ADR" \
  '#pending-ledger(pending-entry(title: "T", kind: "build", since: "2026-01-02")[b])'

assert_invariant section-untitled "is missing required field: title" \
  '#section(lead: "x", body: [y])'

assert_invariant component-missionless "is missing required field: mission" \
  '#components(component(name: "C1"))'

assert_invariant stat-tile-valueless "is missing required field: value" \
  '#stat-tile(label: "things")'

# --- guidelines: silent by default, named under strict ------------------------
assert_guideline title-length "title exceeds 64 characters" \
  '#goal(title: "This title is deliberately far longer than the sixty-four character budget")[b]'

assert_guideline bullet-sentences "3-sentence bullet guideline" \
  '#points("One sentence. Two sentences. Three sentences. Four sentences.")'

assert_guideline lead-sentences "section lead holds about" \
  '#section(title: "T", lead: "One. Two. Three. Four. Five.", body: [x])'

assert_guideline empty-coverage "at least one row" '#coverage()'

assert_guideline empty-points "at least one bullet" '#points()'

assert_guideline empty-ledger "omitted entirely" '#pending-ledger()'

assert_guideline answers-empty "carries no answer" '#answers(title: "U")'

assert_guideline stat-tile-figure "accountant" \
  '#stat-grid(tiles: (stat-tile(value: "1,234,567", label: "rows"),))'

assert_guideline stat-tile-dir "carries a delta with no dir" \
  '#stat-grid(tiles: (stat-tile(value: "2.4M", label: "rows", delta: "+3%"),))'

echo
echo "designlib-native: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
