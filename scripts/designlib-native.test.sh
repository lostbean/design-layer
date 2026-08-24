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

# --- the altitude ladder renders, named rungs and open rungs alike -----------
#
# Asserted by reading the BADGE TEXT back out of the PDF, not by exit code. The
# badge is the whole point of the label — it is what tells a reader which zoom
# level the drawing sits at — so "it compiled" proves nothing about it. The
# fixture is written the way a real design.typ writes it: multi-line, with the
# altitude on its own line.
#
# The four NAMED rungs are the REGRESSION GUARD. Opening the ladder must not
# move them, so each is asserted against the exact badge it rendered before the
# ladder opened: L1 · BOUNDARY, L2 · CONTEXTS, L3 · COMPONENTS, L4 · INTERNALS.
# The unnamed rungs are asserted to read as their level number.
altitude_badge() {
  local name="$1" alt="$2"
  fixture "$name" "#diagram-native(
  altitude: \"$alt\",
  title: \"the shape\",
  nodes: ((id: \"a\", pos: (0,0), label: [Zalpha]),
          (id: \"b\", pos: (1,0), label: [Zbeta])),
  edges: ((\"a\",\"b\",\"Zgamma\"),),
)"
  local out
  out="$(compile "$name" plain)"
  if [ ! -f "$WORK/$name.pdf" ]; then
    printf '%s\n' "$out" | head -3 | sed 's/^/       /' >&2
    return 1
  fi
  # The extractor breaks the letter-spaced badge across spaces and lines, so
  # the comparison is made on the text with all whitespace squeezed out.
  pdftotext "$WORK/$name.pdf" - 2>/dev/null | tr -d ' \n\r'
}

assert_badge() {
  local name="$1" alt="$2" want="$3"
  local squeezed
  if ! squeezed="$(altitude_badge "$name" "$alt")"; then
    fail_line "altitude $alt: did not compile"
    return
  fi
  local wantsq
  wantsq="$(printf '%s' "$want" | tr -d ' ')"
  case "$squeezed" in
  *"$wantsq"*) pass_line "altitude $alt renders its badge as '$want'" ;;
  *)
    fail_line "altitude $alt: badge is not '$want'"
    printf '       page text: %s\n' "$(printf '%s' "$squeezed" | head -c 90)"
    ;;
  esac
}

# the named ladder — these four must not move
assert_badge alt-named-l1 L1 "ALTITUDEL1·BOUNDARY"
assert_badge alt-named-l2 L2 "ALTITUDEL2·CONTEXTS"
assert_badge alt-named-l3 L3 "ALTITUDEL3·COMPONENTS"
assert_badge alt-named-l4 L4 "ALTITUDEL4·INTERNALS"

# the open ladder — a rung past the named ones is legal and reads as its level
assert_badge alt-open-l5 L5 "ALTITUDEL5·LEVEL5"
assert_badge alt-open-l7 L7 "ALTITUDEL7·LEVEL7"
assert_badge alt-open-l12 L12 "ALTITUDEL12·LEVEL12"

# --- the altitude tint is a function of the level, never of render order -----
#
# A band whose colour depended on when it was drawn would make two printings of
# one document disagree, so the tint must be DETERMINISTIC — and it must come
# from the schema's declared accent vocabulary rather than a raw hue, or the
# open ladder would smuggle in colours the layer never declared.
#
# `_alt-tint` is private (an author never calls it; diagram-native resolves the
# band itself), and a test reaching a private helper directly is the right call
# here: the colour is what must be pinned, and it is not recoverable from the
# rendered page.
#
# The tint is not recoverable from extracted PDF text, so the fixture PRINTS
# what the resolver returned and the assertion reads that back.
#
# DETERMINISM IS ASSERTED ACROSS SEPARATE COMPILES, never within one. Calling
# the resolver twice inside a single render and comparing is the vacuous
# version of this test: anything that varies per-render — a clock, a document
# hash, a counter seeded at startup — is constant within one compile, so the
# two calls agree and the check passes on exactly the input it exists to
# catch. That was this test's first shape, and a fixture that keyed the tint to
# a per-render input sailed through it. Two independent compiles are what
# actually pins the colour to the level.
alt_tint_table() {
  local name="$1"
  fixture "$name" '#let rungs = ALTITUDES + ("L5","L6","L7","L8","L9","L13")
#for t in rungs.map(a => _alt-tint(a)) {
  if t not in TINTS {
    panic("_alt-tint produced " + repr(t) + ", which is not a declared tint")
  }
}
#for a in rungs [ #a=#_alt-tint(a) ]'
  local out
  out="$(compile "$name" plain)"
  if [ ! -f "$WORK/$name.pdf" ]; then
    printf '%s\n' "$out" | head -5 | sed 's/^/       /' >&2
    return 1
  fi
  pdftotext "$WORK/$name.pdf" - 2>/dev/null | tr -s ' \n' ' '
}

if tints_a="$(alt_tint_table alt-tint-a)" &&
  tints_b="$(alt_tint_table alt-tint-b)"; then
  # every tint the resolver returned is a declared one — asserted inside the
  # fixture, so reaching this point at all is the proof.
  pass_line "_alt-tint stays inside the declared tint vocabulary"

  if [ "$tints_a" = "$tints_b" ]; then
    pass_line "_alt-tint is deterministic across separate renders ($tints_a)"
  else
    fail_line "_alt-tint is NOT deterministic across renders"
    printf '       render 1: %s\n' "$tints_a"
    printf '       render 2: %s\n' "$tints_b"
  fi

  # the four named rungs keep the exact accents the schema declares for them
  named_ok=1
  for want in "L1=slate" "L2=teal" "L3=amber" "L4=violet"; do
    case "$tints_a" in
    *"$want"*) ;;
    *)
      named_ok=0
      fail_line "altitude tint regression: expected $want, page says: $tints_a"
      ;;
    esac
  done
  [ "$named_ok" -eq 1 ] &&
    pass_line "the named rungs keep their declared tints"
else
  fail_line "the altitude-tint fixture did not compile"
fi

# --- invariants: a wrong value has no defensible reading ---------------------
assert_invariant diagram-ghost-edge "not a declared node" \
  '#diagram-native(altitude: "L1",
     nodes: ((id: "a", pos: (0,0), label: [A]),),
     edges: (("a","ghost","x"),))'

assert_invariant diagram-empty "at least one node" \
  '#diagram-native(altitude: "L1", nodes: (), edges: ())'

# THE ALTITUDE LADDER IS OPEN, AND STILL REQUIRED. Two rules that pull in
# opposite directions, so each gets its own fixture: the set of legal levels is
# unbounded, and an omitted level is still a hard failure.
#
# PRESENCE. A diagram with no altitude leaves the reader unable to tell which
# zoom level they are looking at, so absence stays an invariant. This is the
# half that opening the enum could have quietly deleted.
assert_invariant diagram-altitude-missing "altitude is required" \
  '#diagram-native(
     nodes: ((id: "a", pos: (0,0), label: [A]),), edges: ())'

# SHAPE. Only the CLOSED SET relaxed; a value that is not `L<n>` for a positive
# whole n has no defensible reading and must still stop the build, naming what
# it was given. L0 and L2.5 are the interesting cases: both are "L-and-digits"
# and both are wrong, so a check that merely looked for a leading L would pass
# them.
for bad in '"L0"' '"L"' '"X2"' '"L2.5"' '"2"' '"L-1"'; do
  assert_invariant "diagram-altitude-malformed-$(printf '%s' "$bad" | tr -cd 'A-Za-z0-9.-')" \
    "is not a well-formed altitude" \
    "#diagram-native(
     altitude: $bad,
     nodes: ((id: \"a\", pos: (0,0), label: [A]),), edges: ())"
done

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

# The census's relationship shape is a DECLARED field precisely so it can be
# checked; a shape nothing validates is a claim the reader takes on trust.
assert_invariant relates-bad-side "cardinality side" \
  '#relates(cardinality: "many : 1")[other]'

assert_invariant relates-bad-shape "must be written" \
  '#relates(cardinality: "1")[other]'

assert_invariant relates-no-cardinality "is missing required field: cardinality" \
  '#relates[other]'

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
