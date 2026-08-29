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
#   makes the test vacuous. It must NOT BLOCK a default compile — otherwise the
#   guideline is secretly still a gate — AND it must FAIL UNDER STRICT —
#   otherwise the rule was not relaxed, it was deleted, and the reference is a
#   comment nobody checks. assert_guideline asserts both from one fixture, so
#   neither half can be forgotten.
#
#   Note what a default compile does NOT mean here: a guideline still RECORDS
#   itself on every render, as queryable metadata the aggregate reads back and
#   prints. This suite compiles single fixtures with `typst` directly, so it
#   sees only the non-blocking half; that the guidance actually reaches a human
#   is asserted in typst-layer.test.sh, against the aggregate that reports it.
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

# Solved diagrams use the Graphviz carrier and do not accept authored
# coordinates as part of their required node shape. Assert their labels reach
# the page, not merely that the renderer exits successfully.
fixture render-solved '#show: design-doc.with(hero_title: [Doc])
#diagram-native(
  altitude: "L2", layout: "solved", flow: "left-to-right", title: "shape",
  nodes: ((id: "a", label: "Salpha"), (id: "b", label: "Sbeta")),
  edges: (("a", "b", "Sgamma"),),
)'
out="$(compile render-solved plain)"
if [ -f "$WORK/render-solved.pdf" ]; then
  text="$(pdftotext "$WORK/render-solved.pdf" - 2>/dev/null)"
  missing=""
  for mark in Salpha Sbeta Sgamma; do
    case "$text" in
    *"$mark"*) ;;
    *) missing="$missing $mark" ;;
    esac
  done
  if [ -z "$missing" ]; then
    pass_line "a solved diagram renders its node and edge labels"
  else
    fail_line "the solved diagram omitted these marks:$missing"
  fi
else
  fail_line "the solved diagram did not compile"
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

assert_invariant diagram-layout "diagram layout" \
  '#diagram-native(layout: "radial", altitude: "L1", nodes: ())'

assert_guideline diagram-empty "at least one node" \
  '#diagram-native(altitude: "L1", nodes: (), edges: ())'

# THE ALTITUDE LADDER IS OPEN, AND ITS TWO RULES NOW SPLIT ON SEVERITY. Each
# gets its own fixture, because they pull in opposite directions: an omitted
# level GUIDES, while a malformed one still fails.
#
# PRESENCE. A diagram with no altitude leaves the reader unable to tell which
# zoom level they are looking at, which is worse but not wrong — the drawing
# still renders, under a badge that says the altitude is unstated.
assert_guideline diagram-altitude-missing "altitude is unstated" \
  '#diagram-native(
     nodes: ((id: "a", pos: (0,0), label: [A]),), edges: ())'

# SHAPE, and this half STAYS FAIL-CLOSED. A value that is not `L<n>` for a
# positive whole n has no defensible reading: the library cannot resolve it to a
# level, a name, or a band colour, so it would have to invent one. Guessing is
# the one thing a design document must not do, which is why a MALFORMED value
# fails where a MISSING one guides. L0 and L2.5 are the interesting cases: both
# are "L-and-digits" and both are wrong, so a check that merely looked for a
# leading L would pass them.
for bad in '"L0"' '"L"' '"X2"' '"L2.5"' '"2"' '"L-1"'; do
  assert_invariant "diagram-altitude-malformed-$(printf '%s' "$bad" | tr -cd 'A-Za-z0-9.-')" \
    "is not a well-formed altitude" \
    "#diagram-native(
     altitude: $bad,
     nodes: ((id: \"a\", pos: (0,0), label: [A]),), edges: ())"
done

assert_guideline coverage-unreasoned "states no reason" \
  '#coverage(("part/x", "out-of-scope"))'

assert_invariant coverage-status "coverage status" \
  '#coverage(("part/x", "maybe", "why"))'

assert_invariant pending-date "must be a YYYY-MM-DD date" \
  '#pending-ledger(pending-entry(title: "T", kind: "verify", since: "soon")[b])'

assert_guideline pending-build-adr "cites no ADR" \
  '#pending-ledger(pending-entry(title: "T", kind: "build", since: "2026-01-02")[b])'

assert_guideline section-untitled "section is missing title" \
  '#section(lead: "x", body: [y])'

assert_guideline component-missionless "component is missing mission" \
  '#components(component(name: "C1"))'

# A stat tile hands a DICTIONARY to its grid, so it cannot emit its own
# guidance and defers it to the block that renders it. The fixture therefore
# goes through `stat-grid`: a bare `stat-tile` returns a value nothing places on
# the page, and the guidance would have no content position to be emitted from.
assert_guideline stat-tile-valueless "stat-tile is missing value" \
  '#stat-grid(stat-tile(label: "things"))'

# The census's relationship shape is a DECLARED field precisely so it can be
# checked. It now GUIDES: an unreadable cardinality still renders in its capsule
# exactly as the author typed it, so the reader sees what was written and the
# library says what it expected instead.
assert_guideline relates-bad-side "cardinality side" \
  '#relates(cardinality: "many : 1")[other]'

assert_guideline relates-bad-shape "expected to be written" \
  '#relates(cardinality: "1")[other]'

assert_guideline relates-no-cardinality "relates is missing cardinality" \
  '#relates[other]'

# --- guidelines: reported by default, escalated under strict ------------------
assert_guideline title-length "title exceeds 64 characters" \
  '#goal(title: "This title is deliberately far longer than the sixty-four character budget")[b]'

assert_guideline bullet-sentences "3-sentence bullet guideline" \
  '#points("One sentence. Two sentences. Three sentences. Four sentences.")'

# AREA IS REQUIRED because it carries the rule's confirmed ownership. The
# default render reports the omission and strict mode rejects the same case.
assert_guideline behavior-area-missing "behavior is missing area" \
  '#behavior(title: "Rule", level: "interface")[
     #when[the check runs]
     #then[the result is reported]
   ]'

# THE BEHAVIOR FENCE. A then clause naming the mechanism instead of the
# observable outcome is a WORDING call, so the clause renders exactly as
# written and the library reports what it found. Asserted here so the rule
# cannot be deleted silently while the schema still describes it.
assert_guideline behavior-fence "forbidden term" \
  '#behavior(title: "Rule", area: "Test area", level: "interface")[
     #when[the form is submitted]
     #then[the SignupController returns an http status code]
   ]'

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

# --- every machine fact is DECLARED in the schema, not restated in the code ---
# The schema states each of these facts twice: once as prose a person reads, and
# once as data the projector reads. Only the data half is load-bearing here.
#
# Asserting the REAL value proves nothing — it passes identically against a
# hardcoded literal in render-project. The only assertion that can tell a read
# from a hardcode EDITS THE SCHEMA TO A DELIBERATELY DIFFERENT VALUE and demands
# the projection follow. Every fact below therefore gets a pair: the real value
# (a sanity check) and a different one (the load-bearing half).
#
# The prose beside each key is deliberately NOT edited by these fixtures. A
# projection that still followed the edited data while the prose said something
# else is the correct outcome: the data is the contract, the prose documents it.

# Rewrite one schema key to a new JSON value, assemble the library against it,
# and assert the named vocabulary carries the wanted value.
#
# THE LIBRARY IS ASKED, NOT GREPPED. This used to read the token out of the
# generated designlib.typ, which made the assertion a claim about a spelling in
# emitted text. The library is hand-written now and READS the schema at compile
# time, so there is no emitted text to read — and grepping the source would be
# the weaker question anyway. `typst query` compiles the library and reports the
# value the renderer would actually use, which is the fact these cases mean.
#   $1 name  $2 dotted path under design_doc  $3 JSON value  $4 token  $5 want
assert_declared_fact() {
  local name="$1" path="$2" value="$3" token="$4" want="$5"
  local sdir="$WORK/schema-$name" out
  mkdir -p "$sdir/.render"
  if ! python3 - "$path" "$value" "$sdir/design-schema.json" <<'PY'; then
import json, sys
path, value, dest = sys.argv[1], sys.argv[2], sys.argv[3]
s = json.load(open("schema/design-schema.json"))
node = s["design_doc"]
keys = path.split(".")
for k in keys[:-1]:
    node = node[k]
node[keys[-1]] = json.loads(value)
json.dump(s, open(dest, "w"))
PY
    fail_line "$name: could not write the edited schema"
    return
  fi

  if ! bash ./scripts/render-project "$sdir/design-schema.json" "$sdir/.render" \
    >"$sdir/out" 2>&1; then
    fail_line "$name: the edited schema did not assemble"
    head -3 "$sdir/out" | sed 's/^/       /'
    return
  fi

  printf '#import ".render/designlib.typ": %s\n#metadata(repr(%s))<v>\n' \
    "$token" "$token" >"$sdir/probe.typ"
  # `typst query` prints JSON, so the repr's own quotes arrive backslash-escaped.
  # Unescape them before comparing, so each case states the Typst value a reader
  # would write rather than its JSON encoding.
  if ! out="$("${TYPST:-typst}" query --root "$sdir" "$sdir/probe.typ" '<v>' \
    --field value 2>"$sdir/qerr")"; then
    fail_line "$name: the assembled library could not be queried for $token"
    head -3 "$sdir/qerr" | sed 's/^/       /'
    return
  fi
  out="$(printf '%s' "$out" | sed 's/\\"/"/g')"
  case "$out" in
  *"$want"*) pass_line "$token follows the schema: $name" ;;
  *)
    fail_line "$name: the compiled library ignored the schema's declared $token"
    printf '       wanted: %s\n' "$want"
    printf '       got:    %s\n' "$out"
    ;;
  esac
}

# 1. behavior clause ORDER — behavior_contract.clause_sequence
assert_declared_fact clause-order-real \
  behavior_contract.clause_sequence '["given","when","then"]' \
  CLAUSE-ORDER '"given", "when", "then"'
assert_declared_fact clause-order-edited \
  behavior_contract.clause_sequence '["when","given","then"]' \
  CLAUSE-ORDER '"when", "given", "then"'

# 2. behavior clause CARDINALITY — behavior_contract.clause_bounds. The edited
# case moves 'exactly 1' off `when` and onto `given`, and makes `when` the 1..n
# clause, so a hardcode of either list is caught.
assert_declared_fact clause-bounds-real \
  behavior_contract.clause_bounds \
  '{"given":"0..n","when":"exactly 1","then":"1..n"}' \
  CLAUSE-EXACTLY-ONE '"when",'
assert_declared_fact clause-bounds-edited \
  behavior_contract.clause_bounds \
  '{"given":"exactly 1","when":"1..n","then":"0..n"}' \
  CLAUSE-EXACTLY-ONE '"given",'
assert_declared_fact clause-atleast-edited \
  behavior_contract.clause_bounds \
  '{"given":"exactly 1","when":"1..n","then":"0..n"}' \
  CLAUSE-AT-LEAST-ONE '"when",'

# 3. foundation ORDER — design_doc.foundation_order
assert_declared_fact foundation-order-real \
  foundation_order '["goal","no-goal","invariant","principle"]' \
  FOUNDATION-ORDER '"goal", "no-goal", "invariant", "principle"'
assert_declared_fact foundation-order-edited \
  foundation_order '["principle","invariant","no-goal","goal"]' \
  FOUNDATION-ORDER '"principle", "invariant", "no-goal", "goal"'

# 4. foundation REQUIRED kinds — design_doc.foundation_required. The edited case
# inverts which kind is optional: no-goal becomes required and goal does not.
assert_declared_fact foundation-required-real \
  foundation_required '["goal","invariant","principle"]' \
  FOUNDATION-REQUIRED '"goal", "invariant", "principle"'
assert_declared_fact foundation-required-edited \
  foundation_required '["no-goal","invariant"]' \
  FOUNDATION-REQUIRED '"no-goal", "invariant"'

# 5. entity KINDS — design_doc.entity_contract.kinds
assert_declared_fact entity-kinds-real \
  entity_contract.kinds '["entity","value-object","aggregate","event"]' \
  ENTITY-KINDS '"entity", "value-object", "aggregate", "event"'
assert_declared_fact entity-kinds-edited \
  entity_contract.kinds '["event","aggregate","entity"]' \
  ENTITY-KINDS '"event", "aggregate", "entity"'

# 6. entity LIFECYCLES — design_doc.entity_contract.lifecycles
assert_declared_fact entity-lifecycles-real \
  entity_contract.lifecycles '["immutable","append-only","stateful"]' \
  ENTITY-LIFECYCLES '"immutable", "append-only", "stateful"'
assert_declared_fact entity-lifecycles-edited \
  entity_contract.lifecycles '["stateful","immutable"]' \
  ENTITY-LIFECYCLES '"stateful", "immutable"'

# 7. the behavior FENCE's patterns — behavior_contract.fence.*_forbids.patterns.
# The schema declares these in the renderer's own regex dialect and the library
# reads them unchanged, so this is a declared fact like the six above.
assert_declared_fact fence-patterns-real \
  behavior_contract.fence.interface_forbids.patterns \
  '["#[A-Za-z0-9_-]+","\\\\.[A-Za-z][A-Za-z0-9_-]*-[A-Za-z0-9_-]+","\\\\bid=","data-testid"]' \
  BEHAVIOR-FENCE 'data-testid'
assert_declared_fact fence-patterns-edited \
  behavior_contract.fence.interface_forbids.patterns \
  '["zzz-not-a-real-shape"]' \
  BEHAVIOR-FENCE 'zzz-not-a-real-shape'

# --- THE FENCE'S PATTERN HALF, asserted on what it CATCHES -------------------
# The declared fact above proves the library HOLDS the schema's patterns. It
# does not prove the fence APPLIES them: a fence that read the list and then
# matched against nothing would satisfy it. These cases render a clause and ask
# what the fence said, which is the property a reader of the schema is promised.
#
# Each pattern gets a positive case, and the phrasing the schema's own prose
# ADMITS gets a negative one. The negative case is the load-bearing half: a
# fence that flagged every clause would pass all four positive cases.
assert_guideline fence-pattern-id "matches the forbidden shape" \
  '#behavior(title: "R", area: "Test area", level: "interface")[
     #when[the form is submitted]
     #then[the field #raw("#email-input") gains focus]
   ]'

assert_guideline fence-pattern-class "matches the forbidden shape" \
  '#behavior(title: "R", area: "Test area", level: "interface")[
     #when[the form is submitted]
     #then[#raw(".is-invalid") appears on the field]
   ]'

# Written as PLAIN TEXT, not as inline `raw`, and deliberately so. The clause
# body is flattened by concatenating its children with no separator, so an
# inline element fuses with the word before it — `with #raw("id=")` flattens to
# "withid=", where this pattern's leading word boundary correctly finds no
# boundary to match. The pattern is right; the flattening loses the gap. The
# case is written the way an author writes the clause.
assert_guideline fence-pattern-idattr "matches the forbidden shape" \
  '#behavior(title: "R", area: "Test area", level: "interface")[
     #when[the form is submitted]
     #then[an element with id=signup is marked]
   ]'

assert_guideline fence-pattern-testid "matches the forbidden shape" \
  '#behavior(title: "R", area: "Test area", level: "interface")[
     #when[the form is submitted]
     #then[the #raw("data-testid") hook is set]
   ]'

# THE ADMITTED PHRASING. The schema's interface_forbids prose names this exact
# wording as allowed, so a fence that flags it contradicts the declaration it
# claims to enforce. Asserted under STRICT, where a guideline panics: a clean
# strict compile is the only evidence that nothing fired.
fixture fence-admitted '#behavior(title: "R", area: "Test area", level: "interface")[
  #when[the form is submitted]
  #then[the offending field is named]
]'
fence_admitted_out="$(compile fence-admitted strict)"
if [ -f "$WORK/fence-admitted.pdf" ]; then
  pass_line "fence: the admitted phrasing is not caught, even under strict"
  rm -f "$WORK/fence-admitted.pdf"
else
  fail_line "fence-admitted: the fence flagged wording the schema admits"
  printf '%s\n' "$fence_admitted_out" | head -3 | sed 's/^/       /'
fi

# INLINE MARKUP MUST NOT HIDE A FENCED TERM. The text walk reads a clause by
# recursing its content tree, and Typst holds the gap between two words as its
# own `space` element. A walk that dropped it welded the words together — `an
# element with #raw("id=") set` flattened to "an element withid=set" — and a
# pattern anchored on a word boundary then could not match. The fence went
# blind to exactly the phrasing it exists to catch, silently, on any clause
# carrying markup. Asserted under strict, where the guideline panics.
fixture fence-markup '#behavior(title: "R", area: "Test area", level: "interface")[
  #when[an element with #raw("id=") set is clicked]
  #then[the form is submitted]
]'
fence_markup_out="$(compile fence-markup strict || true)"
if [ -f "$WORK/fence-markup.pdf" ]; then
  fail_line "fence-markup: markup hid a fenced term from the fence"
  rm -f "$WORK/fence-markup.pdf"
elif printf '%s\n' "$fence_markup_out" | grep -q 'behavior.fence'; then
  pass_line "fence: inline markup does not hide a fenced term"
else
  fail_line "fence-markup: strict failed, but not on the fence rule"
  printf '%s\n' "$fence_markup_out" | head -3 | sed 's/^/       /'
fi

# A PATTERN EDITED IN THE SCHEMA CHANGES WHAT THE FENCE CATCHES. This is the
# assertion that separates a read from a hardcode at the level that matters —
# not what the library holds, but what it flags. The schema's real patterns are
# replaced by one deliberately different shape, and BOTH directions are checked
# from the same edited schema: the new shape is caught, and a clause that the
# REAL patterns would have caught now renders clean. Only the second half fails
# against a library that kept a private copy of the shipped list.
assert_fence_follows_schema() {
  local name="$1" patterns="$2" body="$3" want="$4"
  local sdir="$WORK/fence-$name" out
  mkdir -p "$sdir/.render"
  if ! python3 - "$patterns" "$sdir/design-schema.json" <<'PY'; then
import json, sys
patterns, dest = sys.argv[1], sys.argv[2]
s = json.load(open("schema/design-schema.json"))
fence = s["design_doc"]["behavior_contract"]["fence"]
fence["interface_forbids"]["patterns"] = json.loads(patterns)
# The TERM half is emptied too. Leaving it in place would let a term hit stand
# in for a pattern hit and report a pass this case did not earn.
fence["interface_forbids"]["terms"] = []
json.dump(s, open(dest, "w"))
PY
    fail_line "$name: could not write the edited schema"
    return
  fi
  if ! bash ./scripts/render-project "$sdir/design-schema.json" "$sdir/.render" \
    >"$sdir/out" 2>&1; then
    fail_line "$name: the edited schema did not assemble"
    head -3 "$sdir/out" | sed 's/^/       /'
    return
  fi
  printf '#import ".render/designlib.typ": *\n%s\n' "$body" >"$sdir/probe.typ"
  out="$("${TYPST:-typst}" compile --root "$sdir" --input strict=1 \
    "$sdir/probe.typ" "$sdir/probe.pdf" 2>&1)" || true

  if [ "$want" = "caught" ]; then
    if [ -f "$sdir/probe.pdf" ]; then
      fail_line "$name: the schema's edited pattern was declared but never applied"
      return
    fi
    case "$out" in
    *"matches the forbidden shape"*)
      pass_line "fence follows the schema: $name is caught"
      ;;
    *)
      fail_line "$name: the compile failed, but not on the fence's pattern half"
      printf '%s\n' "$out" | head -3 | sed 's/^/       /'
      ;;
    esac
  else
    if [ -f "$sdir/probe.pdf" ]; then
      pass_line "fence follows the schema: $name is clean once the pattern is gone"
    else
      fail_line "$name: still caught after the schema dropped the pattern — the fence carries its own copy"
      printf '%s\n' "$out" | head -3 | sed 's/^/       /'
    fi
  fi
}

assert_fence_follows_schema edited-shape-caught '["zzz-[0-9]+"]' \
  '#behavior(title: "R", area: "Test area", level: "interface")[
     #when[the form is submitted]
     #then[the marker zzz-42 is shown]
   ]' caught

assert_fence_follows_schema real-shape-released '["zzz-[0-9]+"]' \
  '#behavior(title: "R", area: "Test area", level: "interface")[
     #when[the form is submitted]
     #then[the field #raw("#email-input") gains focus]
   ]' clean

# AN UNPARSEABLE PATTERN MUST FAIL LOUDLY, NAMING THE PATTERN. The renderer's
# regex engine rejects a malformed pattern, but it rejects LAZILY — a pattern
# belonging to a level no document happens to author is never compiled, so a
# broken declaration would sit behind a green build while the fence quietly
# enforced one shape fewer than the schema declares. The library compiles every
# declared pattern up front for exactly this reason. Asserted on a document that
# authors NO behavior block at all, because that is the case a lazy compile
# would let through.
assert_bad_pattern() {
  local name="$1" patterns="$2" wantkey="$3"
  local sdir="$WORK/badpat-$name" out
  mkdir -p "$sdir/.render"
  if ! python3 - "$patterns" "$sdir/design-schema.json" <<'PY'; then
import json, sys
patterns, dest = sys.argv[1], sys.argv[2]
s = json.load(open("schema/design-schema.json"))
s["design_doc"]["behavior_contract"]["fence"]["interface_forbids"]["patterns"] \
    = json.loads(patterns)
json.dump(s, open(dest, "w"))
PY
    fail_line "$name: could not write the edited schema"
    return
  fi
  if ! bash ./scripts/render-project "$sdir/design-schema.json" "$sdir/.render" \
    >"$sdir/out" 2>&1; then
    fail_line "$name: the edited schema did not assemble"
    head -3 "$sdir/out" | sed 's/^/       /'
    return
  fi
  # No behavior block, no clause — nothing that would touch the fence on its own.
  printf '#import ".render/designlib.typ": *\n#points("A bullet.")\n' \
    >"$sdir/probe.typ"
  if out="$("${TYPST:-typst}" compile --root "$sdir" "$sdir/probe.typ" \
    "$sdir/probe.pdf" 2>&1)"; then
    fail_line "$name: compiled clean — a pattern the engine cannot read went unnoticed"
    return
  fi
  case "$out" in
  *"$wantkey"*) pass_line "bad pattern: $name fails the compile, naming $wantkey" ;;
  *)
    fail_line "$name: the compile failed, but the message does not name $wantkey"
    printf '       wanted: %s\n' "$wantkey"
    printf '%s\n' "$out" | head -5 | sed 's/^/       /'
    ;;
  esac
}

assert_bad_pattern unclosed-class '["#[A-Za-z"]' 'unclosed character class'
assert_bad_pattern dangling-repeat '["*bogus"]' 'repetition'
# A non-string entry never reaches the engine, so the library names it itself.
assert_bad_pattern non-string '[42]' 'not a string'

# WHY THE SCHEMA DECLARES ITS PATTERN DIALECT, asserted rather than asserted in
# prose. The engine rejects a pattern it cannot PARSE, which the three cases
# above cover. It cannot reject a pattern that parses and means something else,
# and that is the whole hazard of a wrong dialect: the schema this fence reads
# once declared these patterns in Lua's syntax, and every one of them is ALSO a
# legal expression in the renderer's engine — one that matches none of the text
# it was written to catch. A fence loaded with them enforces nothing and reports
# success, so the failure is silent and no parse check can see it.
#
# The guard is that the declared dialect is the read dialect, with no
# translation between them. This case pins the hazard down so a future edit that
# reintroduces the retired syntax is caught by a failing test rather than by a
# fence that quietly stopped working.
assert_fence_follows_schema retired-dialect-is-dead \
  '["#[%w_-]+","%.[%a][%w_-]*%-[%w_-]+","%f[%w]id=","data%-testid"]' \
  '#behavior(title: "R", area: "Test area", level: "interface")[
     #when[the form is submitted]
     #then[the field #raw("#email-input") gains focus]
   ]' clean

# --- a MISSING or EMPTY declaration must stop the projection, never default ---
# Removing the fragile prose parse must not remove the validation with it: a
# schema that declares no order has no contract to project, and projecting an
# empty rule would enforce nothing while reporting success.
# WHERE THE REFUSAL NOW HAPPENS. These checks used to run inside the generator,
# once per projection. The library is hand-written now and reads the schema at
# COMPILE time, so the same checks run on every compile — strictly more often —
# and the refusal is a compile error rather than an assembly error. This asserts
# the property that matters either way: an incoherent schema must stop the
# build naming the declaration to fix, never fall back to a silent default.
assert_schema_rejected() {
  local name="$1" mutation="$2" wantkey="$3"
  local sdir="$WORK/reject-$name" out
  mkdir -p "$sdir/.render"
  if ! python3 - "$mutation" "$sdir/design-schema.json" <<'PY'; then
import json, sys
mutation, dest = sys.argv[1], sys.argv[2]
s = json.load(open("schema/design-schema.json"))
d = s["design_doc"]
exec(mutation, {"d": d})
json.dump(s, open(dest, "w"))
PY
    fail_line "$name: could not write the edited schema"
    return
  fi
  if ! bash ./scripts/render-project "$sdir/design-schema.json" "$sdir/.render" \
    >"$sdir/out" 2>&1; then
    # The fence half still refuses at assembly time, so an assembly failure is
    # a legitimate refusal — check its message and stop here.
    out="$(cat "$sdir/out")"
  else
    printf '#import ".render/designlib.typ": *\n#LENSES.len()\n' >"$sdir/probe.typ"
    if out="$("${TYPST:-typst}" compile --root "$sdir" "$sdir/probe.typ" \
      "$sdir/probe.pdf" 2>&1)"; then
      fail_line "$name: compiled anyway — it fell back to a silent default"
      return
    fi
  fi
  case "$out" in
  *"$wantkey"*) pass_line "$name errors, naming $wantkey" ;;
  *)
    fail_line "$name failed, but the message does not name $wantkey"
    printf '%s\n' "$out" | head -3 | sed 's/^/       /'
    ;;
  esac
}

assert_schema_rejected missing-clause-sequence \
  'del d["behavior_contract"]["clause_sequence"]' clause_sequence
assert_schema_rejected empty-clause-sequence \
  'd["behavior_contract"]["clause_sequence"] = []' clause_sequence
assert_schema_rejected missing-clause-bounds \
  'del d["behavior_contract"]["clause_bounds"]' clause_bounds
assert_schema_rejected unbounded-clause \
  'del d["behavior_contract"]["clause_bounds"]["when"]' clause_bounds
assert_schema_rejected unknown-bound \
  'd["behavior_contract"]["clause_bounds"]["when"] = "some"' clause_bounds
assert_schema_rejected no-cardinality-constraint \
  'd["behavior_contract"]["clause_bounds"] = {"given":"0..n","when":"0..n","then":"0..n"}' \
  clause_bounds
assert_schema_rejected missing-foundation-order \
  'del d["foundation_order"]' foundation_order
assert_schema_rejected empty-foundation-order \
  'd["foundation_order"] = []' foundation_order
assert_schema_rejected undeclared-foundation-kind \
  'd["foundation_order"] = ["goal","axiom"]' foundation_order
assert_schema_rejected missing-foundation-required \
  'del d["foundation_required"]' foundation_required
assert_schema_rejected empty-foundation-required \
  'd["foundation_required"] = []' foundation_required
assert_schema_rejected stray-foundation-required \
  'd["foundation_required"] = ["goal","axiom"]' foundation_required
assert_schema_rejected missing-entity-kinds \
  'del d["entity_contract"]["kinds"]' entity_contract
assert_schema_rejected missing-entity-lifecycles \
  'del d["entity_contract"]["lifecycles"]' entity_contract

echo
echo "designlib-native: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
