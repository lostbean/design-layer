#!/usr/bin/env bash
#
# design-units.test.sh — the `unit` block, the selectors that read it, the
# folder contracts generated from it, and the gate checks that hold them.
#
# WHY THIS TEST EXISTS. A unit is one declaration with four readers: the PDF,
# the Markdown projection, a folder's AGENTS.md, and the gate. Each reader can
# drift from the declaration on its own, and each drift is quiet — a contract
# that renders with a field missing, a selector returning a neighbouring unit,
# a folder still carrying a contract its unit no longer lists. So every rule
# here is asserted in BOTH directions: the well-formed case passes, and a
# fixture that breaks the rule fails naming it.
#
# What it covers:
#   1. the block's INVARIANTS — a missing required field, a malformed or
#      duplicate id, an illegal path, an unknown attribute, content in a field
#      that is not prose — each fail the compile; its GUIDELINES report and
#      block only under strict
#   2. the rendered page carries the contract, an empty list reads `None`, and
#      nesting is the heading hierarchy down to the sixth heading level, in a
#      document body, a section, and a subsection; a section inside a unit is
#      refused by the page, the projection, and the gate alike; and a heading
#      written in markup keeps its level outside a unit and nests inside one
#   3. a context document is not held to the foundation minimum, and a
#      statement inside a unit is not read as the document's foundation
#   4. the projection, and selection by unit id and by code path
#   5. the generator: create, replace, several units in one folder, one unit in
#      several folders, an existing CLAUDE.md, and removal — and what it
#      refuses to touch: a symlinked or unusable target, a marker someone wrote
#      in their own text, two spellings of one directory, the line endings and
#      final newline of a file it shares, a file it has no reason to read, and
#      a nested project's contracts, declared or not; and what a failure while
#      writing leaves behind
#   6. the gate: a missing path, a stale contract, a contract no unit lists —
#      through the scripts and through the public check app — the links a
#      generated region carries into the layer, which the host-link check
#      resolves, and the uncovered-directory report, which never changes an
#      exit code
#   7. a layer that authors no unit is untouched, including under the schema
#      as it stood before the block existed
#
# Usage: design-units.test.sh [repo-root]
# Exit:  0 all assertions pass, 1 an assertion failed, 2 a tool is missing.
set -uo pipefail

# A pre-commit runner may export the parent repository's Git directory, index,
# and object paths. Fixture repositories must use their own metadata.
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS
unset GIT_CONFIG_COUNT GIT_OBJECT_DIRECTORY GIT_DIR GIT_WORK_TREE
unset GIT_IMPLICIT_WORK_TREE GIT_GRAFT_FILE GIT_INDEX_FILE
unset GIT_NO_REPLACE_OBJECTS GIT_REPLACE_REF_BASE GIT_PREFIX
unset GIT_SHALLOW_FILE GIT_COMMON_DIR

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1

TYPST="${TYPST:-typst}"
for tool in "$TYPST" pdftotext git python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "design-units: error: no $tool on PATH (enter the dev shell)" >&2
    exit 2
  fi
done
# The composite gate and the generator are also exercised through their PUBLIC
# apps. A run that cannot reach them must not report success for the scenarios
# it skipped, so their absence is an error rather than a note.
for app in DESIGN_CHECK_APP DESIGN_RENDER_APP DESIGN_UNITS_APP DESIGN_CONTEXT_APP; do
  if [ -z "${!app:-}" ]; then
    echo "design-units: error: $app is not set (run through the dev shell)" >&2
    exit 2
  fi
done

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

LIB="$WORK/lib"
if ! bash ./scripts/render-project schema/design-schema.json "$LIB" >/dev/null; then
  echo "design-units: could not project the schema" >&2
  exit 2
fi
export DESIGN_SCHEMA="$ROOT/schema/design-schema.json"

echo "design-units: block -> projection -> folder contracts -> gate"

# --- helpers -------------------------------------------------------------------
# run <expected-exit> <label> -- <command...>; the output lands in $OUT.
OUT=""
run() {
  local expected="$1" label="$2"
  shift 3
  local code
  OUT="$("$@" 2>&1)"
  code=$?
  if [ "$code" -eq "$expected" ]; then
    pass_line "$label (exit $code)"
  else
    fail_line "$label: expected exit $expected, got $code"
    printf '%s\n' "$OUT" | head -6 | sed 's/^/       /'
  fi
}
has() { # <needle> <label>
  case "$OUT" in
  *"$1"*) pass_line "$2" ;;
  *)
    fail_line "$2: output lacks '$1'"
    printf '%s\n' "$OUT" | head -6 | sed 's/^/       /'
    ;;
  esac
}
lacks() { # <needle> <label>
  case "$OUT" in
  *"$1"*) fail_line "$2: output unexpectedly holds '$1'" ;;
  *) pass_line "$2" ;;
  esac
}
same_file() { # <a> <b> <label>
  if cmp -s "$1" "$2"; then pass_line "$3"; else fail_line "$3"; fi
}
# The output line naming <where> must not also say <needle>: a violation the
# generator cannot repair must not tell the reader to run the generator.
line_lacks() { # <where> <needle> <label>
  local line
  line="$(printf '%s\n' "$OUT" | grep -F -- "$1")"
  if [ -z "$line" ]; then
    fail_line "$3: no output line names '$1'"
    return
  fi
  case "$line" in
  *"$2"*) fail_line "$3: the line naming '$1' holds '$2'" ;;
  *) pass_line "$3" ;;
  esac
}
absent() { # <path> <label>
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then pass_line "$2"; else fail_line "$2: $1 exists"; fi
}

# --- 1. THE BLOCK'S OWN CONTRACT ----------------------------------------------
# Single fixtures compiled directly, so each rule is judged alone.
BLOCK="$WORK/block"
mkdir -p "$BLOCK"
cp "$LIB"/* "$BLOCK/"

UNIT_OK='id: "billing-ledger",
  title: "Billing ledger",
  overview: [Appends what was charged.],
  interface: ([`append(entry)`], "Emits a receipt."),
  invariants: ("An entry is never rewritten.",),
  side-effects: (),
  verification: [`make test-ledger`],
  paths: ("src/ledger",),'

block_compile() { # <name> <strict|plain> <body>
  printf '#import "designlib.typ": *\n%s\n' "$3" >"$BLOCK/$1.typ"
  local args=()
  [ "$2" = "strict" ] && args+=(--input strict=1)
  rm -f "$BLOCK/$1.pdf"
  "$TYPST" compile "${args[@]}" --root "$BLOCK" "$BLOCK/$1.typ" "$BLOCK/$1.pdf" 2>&1
}
unit_invariant() { # <name> <needle> <unit arguments>
  local out
  out="$(block_compile "$1" plain "#unit($3)")"
  if [ -f "$BLOCK/$1.pdf" ]; then
    fail_line "$1: compiled, but the invariant should have stopped it"
    return
  fi
  case "$out" in
  *"$2"*) pass_line "invariant: $1 fails naming its rule" ;;
  *)
    fail_line "$1: failed, but the message does not name the rule"
    printf '       wanted: %s\n' "$2"
    printf '%s\n' "$out" | head -3 | sed 's/^/       /'
    ;;
  esac
}
# Drop one named argument from the well-formed call.
without() { printf '%s\n' "$UNIT_OK" | grep -v "^ *$1:"; }
# Replace one named argument of the well-formed call.
with() { printf '%s\n  %s' "$(without "$1")" "$2"; }

out="$(block_compile ok plain "#unit($UNIT_OK)[The body is optional prose.]")"
if [ -f "$BLOCK/ok.pdf" ]; then
  pass_line "a well-formed unit compiles"
  text="$(pdftotext "$BLOCK/ok.pdf" - 2>/dev/null)"
  missing=""
  for mark in "Billing ledger" billing-ledger overview interface invariants \
    "side effects" verification paths "src/ledger" "make test-ledger" None \
    "The body is optional prose."; do
    case "$text" in *"$mark"*) ;; *) missing="$missing [$mark]" ;; esac
  done
  if [ -z "$missing" ]; then
    pass_line "the unit's five sections, its paths, and its empty list reach the page"
  else
    fail_line "the unit rendered but these marks are absent:$missing"
  fi
else
  fail_line "a well-formed unit does not compile: $(printf '%s' "$out" | head -2)"
fi
out="$(block_compile nobody plain "#unit($UNIT_OK)")"
if [ -f "$BLOCK/nobody.pdf" ]; then
  pass_line "a unit with no body compiles"
else
  fail_line "a unit with no body does not compile: $(printf '%s' "$out" | head -2)"
fi

# Every required field, removed in turn. One fixture per field: a loop that
# removed them all at once would pass on the first and never test the rest.
for f in id title overview interface invariants side-effects verification paths; do
  unit_invariant "missing-$f" "missing $f" "$(without "$f")"
done
# Present but empty where the section has no empty answer.
unit_invariant empty-overview "missing overview" "$(with overview 'overview: "  ",')"
unit_invariant empty-verification "missing verification" \
  "$(with verification 'verification: [],')"
unit_invariant empty-title "missing title" "$(with title 'title: "",')"
# A list field handed something that is not a list.
unit_invariant list-as-string "interface must be a list" \
  "$(with interface 'interface: ("one item"),')"
unit_invariant list-empty-item "holds an empty item" \
  "$(with invariants 'invariants: ("",),')"
unit_invariant paths-as-string "paths must be a list" \
  "$(with paths 'paths: ("src/ledger"),')"
# The id is a kebab-case slug.
for bad in 'Billing' 'billing_ledger' 'billing--ledger' '-billing' 'billing ledger'; do
  unit_invariant "id-$(printf '%s' "$bad" | tr -c 'A-Za-z0-9' '_')" \
    "is not a kebab-case slug" "$(with id "id: \"$bad\",")"
done
# Every path rule, one fixture each.
# The panic prints its message as a quoted string, so a quote inside it arrives
# escaped; the needles are written the way the compiler prints them.
unit_invariant path-glob 'contains \"*\"' "$(with paths 'paths: ("src/*",),')"
unit_invariant path-brace 'contains \"{\"' "$(with paths 'paths: ("src/{a,b}",),')"
unit_invariant path-backslash "never a pattern" \
  "$(with paths 'paths: ("src\\ledger",),')"
unit_invariant path-absolute "is absolute" "$(with paths 'paths: ("/src/ledger",),')"
unit_invariant path-dot "names the repository root" "$(with paths 'paths: (".",),')"
unit_invariant path-dotdot "segment" "$(with paths 'paths: ("src/../etc",),')"
unit_invariant path-dot-segment "segment" "$(with paths 'paths: ("./src",),')"
unit_invariant path-trailing-slash "empty segment" "$(with paths 'paths: ("src/",),')"
unit_invariant path-empty "lists an empty path" "$(with paths 'paths: ("",),')"
unit_invariant path-twice "twice" "$(with paths 'paths: ("src/a", "src/a"),')"
unit_invariant path-not-string "is not a string" "$(with paths 'paths: (3,),')"
# An unrecognized attribute is never dropped silently.
unit_invariant unknown-attribute "unknown attribute tint=" \
  "$UNIT_OK
  tint: \"teal\","
# A list written INSIDE a field renders on the page but has no form in the
# projection or in a folder contract, so the render refuses it in the
# projection's own words. One fixture per kind of list and per field shape.
unit_invariant list-in-text-field "overview holds a list" "$(with overview 'overview: [Two parts.

- the first
- the second],')"
unit_invariant list-in-text-field-names-it "unsupported Typst content function" \
  "$(with overview 'overview: [Two parts.

- the first
- the second],')"
unit_invariant numbered-list-in-field "verification holds a list" \
  "$(with verification 'verification: [Run in order.

+ build
+ test],')"
unit_invariant list-in-list-item "an item of interface holds a list" \
  "$(with interface 'interface: ([Two calls.

- `append`
- `read`],),')"
unit_invariant explicit-list-in-field "overview holds a list" \
  "$(with overview 'overview: [Parts: #list([one], [two])],')"
# A FIELD IS PROSE. Each of these rendered, and then stopped the projection and
# the generator: a footnote and a box as content functions with no Markdown
# form, a context and a heading as content the projection drops, leaving the
# section empty. The render refuses each, naming the function, so the three
# carriers never disagree about a unit the page accepted.
unit_invariant footnote-in-field "overview holds footnote" \
  "$(with overview 'overview: [Appends what was charged.#footnote[An aside.]],')"
unit_invariant box-in-field "overview holds rect" \
  "$(with overview 'overview: [#rect[Appends what was charged.]],')"
unit_invariant context-in-field "verification holds context" \
  "$(with verification 'verification: context [make test-ledger],')"
unit_invariant heading-in-field "overview holds heading" "$(with overview 'overview: [
= Appends what was charged
],')"
unit_invariant layout-in-list-item "an item of invariants holds box" \
  "$(with invariants 'invariants: ([An entry is #box[never] rewritten.],),')"
unit_invariant field-content-names-the-rule "A unit field is prose" \
  "$(with overview 'overview: [Appends.#footnote[An aside.]],')"
unit_invariant field-content-names-the-remedy "move it into the unit" \
  "$(with overview 'overview: [Appends.#footnote[An aside.]],')"
# A duplicate id fails at the second call.
out="$(block_compile duplicate plain "#unit($UNIT_OK)
#unit($UNIT_OK)")"
if [ ! -f "$BLOCK/duplicate.pdf" ] && printf '%s' "$out" | grep -q "is declared twice"; then
  pass_line "invariant: a duplicate unit id fails naming it"
else
  fail_line "a duplicate unit id compiled, or failed without naming the rule"
fi

# The style half. Each guideline must NOT block a default compile and MUST
# fail under strict; asserting one half alone would pass on a deleted rule.
unit_guideline() { # <name> <needle> <unit arguments>
  block_compile "$1" plain "#unit($3)" >/dev/null
  if [ ! -f "$BLOCK/$1.pdf" ]; then
    fail_line "guideline $1: blocked a default compile"
    return
  fi
  local out
  out="$(block_compile "$1" strict "#unit($3)")"
  if [ -f "$BLOCK/$1.pdf" ]; then
    fail_line "guideline $1: did not fail under strict"
    return
  fi
  case "$out" in
  *"$2"*) pass_line "guideline: $1 reports, and fails only under strict" ;;
  *) fail_line "guideline $1: strict failed without naming the rule ($2)" ;;
  esac
}
unit_guideline long-item "unit.item-sentences" \
  "$(with invariants 'invariants: ("One. Two. Three. Four.",),')"
unit_guideline long-section "unit.section-sentences" \
  "$(with overview 'overview: "A. B. C. D. E. F.",')"
unit_guideline long-title "title.length" \
  "$(with title 'title: "A unit title that runs on well past the sixty-four characters allowed",')"
# The well-formed unit fires no guideline at all: strict compiles it.
block_compile strict-ok strict "#unit($UNIT_OK)" >/dev/null
if [ -f "$BLOCK/strict-ok.pdf" ]; then
  pass_line "a well-formed unit fires no guideline under strict"
else
  fail_line "a well-formed unit failed under strict"
fi

# --- the fixture repository -----------------------------------------------------
# A layer at <repo>/docs/design with a root and one context, units nested in
# the root, and a real git history, because the stale-contract scan and the
# uncovered-directory report both read the work tree through git.
REPO="$WORK/repo"
LAYER="$REPO/docs/design"
mkdir -p "$LAYER/alpha" "$REPO/src/ledger" "$REPO/src/gateway" "$REPO/src/shared" \
  "$REPO/tools/release" "$REPO/docs/adr"
cp -R "$LIB" "$LAYER/.render"
export DESIGN_LIB_DIR="$LAYER/.render"

write_root() { # $1 = the ledger unit's paths, $2 = the ledger overview
  cat >"$LAYER/design.typ" <<EOF
#import ".render/designlib.typ": *
#let title = [Zroot]
#let context_command = "nix run .#design-context --"
#let body = [
  #section(title: "Foundation", body: [
    #goal(title: "Zgoal")[Root goal.]
    #invariant(title: "Zinv", enforcement: "convention")[Root invariant.]
    #principle(title: "Zprin")[Root principle.]
  ])
  #section(title: "Parts", body: [
    #unit(
      id: "billing",
      title: "Zbilling",
      overview: [Charges customers; its ledger is @unit-ledger.],
      interface: ([\`charge(order)\` returns a receipt.],),
      invariants: ("A receipt names one order.",),
      side-effects: (),
      verification: [\`make test-billing\`],
      paths: (),
    )[
      Zbilling groups two parts.

      #unit(
        id: "ledger",
        title: "Zledger",
        overview: "$2",
        interface: ("append(entry)",),
        invariants: ("An entry is never rewritten.",),
        side-effects: ("Writes the ledger table.",),
        verification: "cargo test -p ledger",
        paths: $1,
      )[
        #principle(title: "Zunitprin")[A principle the unit carries.]
        #goal(title: "Zunitgoal")[A goal after it, inside the same unit.]
      ]
      #unit(
        id: "gateway",
        title: "Zgateway",
        overview: "Talks to the card processor.",
        interface: (),
        invariants: (),
        side-effects: ("Calls the processor over the network.",),
        verification: "None. Exercised only in staging.",
        paths: ("src/gateway",),
      )

      Zafterchild is the group's own closing prose.
    ]

    Zafterparent is the section's closing prose.
  ])
]
EOF
}
cat >"$LAYER/alpha/design.typ" <<'EOF'
#import "../.render/designlib.typ": *
#let title = [Zalpha]
#let body = [
  #goal(title: "Zalphagoal")[The one aim that differs from the root.]
  #unit(
    id: "shared-kernel",
    title: "Zshared",
    overview: "Types both parts use.",
    interface: ("Money", "OrderId"),
    invariants: (),
    side-effects: (),
    verification: "cargo test -p shared",
    paths: ("src/shared",),
  )
]
EOF
write_root '("src/ledger", "src/shared")' "Appends immutable entries."
printf '# Context map\n' >"$REPO/docs/CONTEXT-MAP.md"
cat >"$REPO/docs/COVERAGE.md" <<'EOF'
# Coverage

| Part   | Status   | Where                                 |
| ------ | -------- | ------------------------------------- |
| Ledger | captured | [Zledger](design/design.typ#unit-ledger) |
EOF
printf 'fn main() {}\n' >"$REPO/src/ledger/lib.rs"
printf 'fn main() {}\n' >"$REPO/src/gateway/lib.rs"
printf 'fn main() {}\n' >"$REPO/src/shared/lib.rs"
printf 'fn main() {}\n' >"$REPO/src/main.rs"
printf '#!/bin/sh\n' >"$REPO/tools/release/cut.sh"
printf '.render/\n' >"$REPO/.gitignore"
(
  cd "$REPO" && git init -q . && git add -A &&
    git -c user.name=t -c user.email=t@localhost commit -qm init
) >/dev/null 2>&1

render() { python3 ./scripts/design-aggregate "$LAYER" "$LAYER/design-layer.pdf" "$@"; }
units() { python3 ./scripts/design-units "$LAYER" "$REPO" "$@"; }
context() { python3 ./scripts/design-context "$LAYER" "$@"; }

# --- 2 + 3. THE RENDERED LAYER, AND THE RELAXED STRUCTURE ---------------------
run 0 "a layer using units renders" -- render
has "0 guideline(s)" "the layer fires no guideline"
lacks "foundation.cardinality" "a context carrying one goal is not held to the minimum"
lacks "foundation.order" "a principle before a goal INSIDE a unit is not the document's order"
if [ -f "$LAYER/design-layer.pdf" ]; then
  text="$(pdftotext -layout "$LAYER/design-layer.pdf" - 2>/dev/null)"
  missing=""
  # 1.2 is the Parts section, so nesting gives 1.2.1 Zbilling and 1.2.1.1
  # Zledger; the context's top-level unit sits directly under its chapter.
  for mark in "1.2.1 Zbilling" "1.2.1.1 Zledger" "1.2.1.2 Zgateway" "2.1 Zshared" \
    "src/ledger" "Section 1.2.1.1"; do
    case "$text" in *"$mark"*) ;; *) missing="$missing [$mark]" ;; esac
  done
  if [ -z "$missing" ]; then
    pass_line "nesting is the heading hierarchy, and a unit reference resolves"
  else
    fail_line "the layer rendered but these marks are absent:$missing"
  fi
else
  fail_line "the layer wrote no PDF"
fi
run 0 "strict accepts the layer: a context may omit foundation kinds" -- \
  env DESIGN_STRICT=1 python3 ./scripts/design-aggregate "$LAYER" "$WORK/strict.pdf"

# The other direction of each relaxation, so neither is a deleted rule.
# The ROOT is still held to the minimum.
cp "$LAYER/design.typ" "$WORK/root.good"
python3 - "$LAYER/design.typ" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
line = '    #principle(title: "Zprin")[Root principle.]\n'
assert line in s
open(p, "w").write(s.replace(line, ""))
PY
run 0 "a root missing a foundation kind still renders" -- render
has "guideline: foundation.cardinality" "the ROOT is still held to the per-kind minimum"
has "declares no principle" "the guidance names the kind the root lacks"
run 1 "strict still fails a root missing a foundation kind" -- \
  env DESIGN_STRICT=1 python3 ./scripts/design-aggregate "$LAYER" "$WORK/strict.pdf"
cp "$WORK/root.good" "$LAYER/design.typ"
# The order rule still binds statements OUTSIDE a unit, in any document.
cp "$LAYER/alpha/design.typ" "$WORK/alpha.good"
python3 - "$LAYER/alpha/design.typ" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
line = '  #goal(title: "Zalphagoal")[The one aim that differs from the root.]\n'
assert line in s
open(p, "w").write(s.replace(
    line, '  #principle(title: "Zalphaprin")[p]\n' + line))
PY
run 0 "a context with a misordered foundation still renders" -- render
has "guideline: foundation.order" "the order rule still binds a context's own statements"
cp "$WORK/alpha.good" "$LAYER/alpha/design.typ"
# A duplicate id ACROSS documents fails the render.
python3 - "$LAYER/alpha/design.typ" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
assert 'id: "shared-kernel"' in s
open(p, "w").write(s.replace('id: "shared-kernel"', 'id: "ledger"'))
PY
run 1 "a unit id repeated in another document fails the render" -- render
has "is declared twice" "the render names the duplicate id rule"
run 1 "a unit id repeated in another document fails the projection" -- context
has "declared twice" "the projection names the duplicate id rule"
cp "$WORK/alpha.good" "$LAYER/alpha/design.typ"
run 0 "the fixture renders again" -- render

# NESTING DEPTH. A unit's heading level is its depth, and a document has six
# heading levels. The chapter is level one, so the deepest nesting is five
# units directly in a document body, four inside a section, and three inside a
# subsection. Each must render in ONE settled layout: a level derived through
# a state costs a layout pass per nested unit, and four of them once stopped
# the render with "layout did not converge". One unit deeper is past the sixth
# level, and the render and the projection both refuse it, naming the unit.
DEPTH="$WORK/depth"
mkdir -p "$DEPTH/docs/design"
cp -R "$LIB" "$DEPTH/docs/design/.render"
printf '# Map\n' >"$DEPTH/docs/CONTEXT-MAP.md"
printf '# Coverage\n' >"$DEPTH/docs/COVERAGE.md"
depth_unit() { # <n> [body]
  printf '#unit(id: "d%s", title: "Zdeep%s", overview: "O.", interface: (), invariants: (), side-effects: (), verification: "none", paths: ())%s' \
    "$1" "$1" "${2:-}"
}
depth_nest() { # <count> [from] — <count> units, each in the body of the one before
  local count="$1" at="${2:-1}"
  if [ "$at" -eq "$count" ]; then
    depth_unit "$at"
  else
    depth_unit "$at" "[ $(depth_nest "$count" $((at + 1))) ]"
  fi
}
depth_layer() { # <what follows the foundation>
  cat >"$DEPTH/docs/design/design.typ" <<EOF
#import ".render/designlib.typ": *
#let title = [Zdepth]
#let body = [
  #section(title: "Foundation", body: [
    #goal(title: "Zdg")[g]
    #invariant(title: "Zdi", enforcement: "convention")[i]
    #principle(title: "Zdp")[p]
  ])
  $1
]
EOF
}
depth_render() {
  DESIGN_LIB_DIR="$DEPTH/docs/design/.render" python3 ./scripts/design-aggregate \
    "$DEPTH/docs/design" "$DEPTH/out.pdf"
}
depth_context() {
  DESIGN_LIB_DIR="$DEPTH/docs/design/.render" python3 ./scripts/design-context \
    "$DEPTH/docs/design" "$@"
}
depth_units() {
  DESIGN_LIB_DIR="$DEPTH/docs/design/.render" python3 ./scripts/design-units \
    "$DEPTH/docs/design" "$DEPTH" --check
}
# <count> units, each in the body of the one before, the last holding <innermost>
depth_nest_around() {
  local count="$1" inner="$2" at="${3:-1}"
  if [ "$at" -eq "$count" ]; then
    depth_unit "$at" "[ $inner ]"
  else
    depth_unit "$at" "[ $(depth_nest_around "$count" "$inner" $((at + 1))) ]"
  fi
}
# <where> <deepest count> <host template>. The template holds NEST where the
# nested units go. In every host the deepest unit is the sixth heading level,
# so the aggregate numbers it with six parts under chapter 1, section 2.
depth_case() {
  local where="$1" count="$2" host="$3" text
  depth_layer "${host/NEST/$(depth_nest "$count")}"
  rm -f "$DEPTH/out.pdf"
  run 0 "$count nested units render $where" -- depth_render
  lacks "did not converge" "$count nested units $where settle in the layout passes Typst allows"
  has "0 guideline(s)" "$count nested units $where fire no guideline"
  text="$(pdftotext -layout "$DEPTH/out.pdf" - 2>/dev/null)"
  case "$text" in
  *"1.2.1.1.1.1 Zdeep$count"*) pass_line "the deepest unit $where is the sixth heading level" ;;
  *) fail_line "the deepest unit $where is not numbered 1.2.1.1.1.1" ;;
  esac
  run 0 "the projection accepts $count nested units $where" -- depth_context
  has "###### unit: Zdeep$count" "the projection heads the deepest unit $where at level six"
  # The manifest compares the level the projection wrote each unit at with the
  # level the gate's unit reader computed for it, so the two cannot drift.
  run 0 "the manifest addresses $count nested units $where" -- depth_context --manifest
  has "\"id\": \"d$count\"" "the manifest lists the deepest unit $where"
  run 0 "the unit checks accept $count nested units $where" -- depth_units

  depth_layer "${host/NEST/$(depth_nest $((count + 1)))}"
  run 1 "$((count + 1)) nested units $where fail the render" -- depth_render
  has "d$((count + 1))\\\" is nested at heading level 7" "the render names the unit past the sixth level"
  lacks "did not converge" "the render fails on the depth rule, not on convergence"
  run 1 "$((count + 1)) nested units $where fail the projection" -- depth_context
  has "nested past Markdown's 6 heading levels" "the projection names the same limit"
  run 1 "$((count + 1)) nested units $where fail the unit checks" -- depth_units
  has "nested past Markdown's 6 heading levels" "the gate's unit step names the same limit"
}
depth_case "directly in a document body" 5 'NEST'
depth_case "inside a section" 4 '#section(title: "Parts", body: [ NEST ])'
depth_case "inside a subsection" 3 \
  '#section(title: "Parts", body: [#subsection(title: "Sub")[ NEST ]])'
# A CONTEXT DOCUMENT sits one level lower in the projection, which writes the
# root as the Markdown title and each context as a heading below it. The limit
# is judged there, so the render refuses exactly the unit the projection cannot
# address, and names the level in both carriers.
depth_layer ''
mkdir -p "$DEPTH/docs/design/alpha"
depth_context_document() { # <count>
  cat >"$DEPTH/docs/design/alpha/design.typ" <<EOF
#import "../.render/designlib.typ": *
#let title = [Zdepth alpha]
#let body = [ $(depth_nest "$1") ]
EOF
}
depth_context_document 4
run 0 "4 nested units render in a context document's body" -- depth_render
lacks "did not converge" "4 nested units in a context document settle in the layout passes Typst allows"
run 0 "the projection accepts 4 nested units in a context document's body" -- depth_context
has "###### unit: Zdeep4" "the projection heads the deepest unit of a context document at level six"
depth_context_document 5
run 1 "5 nested units in a context document's body fail the render" -- depth_render
has 'd5\" is nested at heading level 6 of a context document, which the Markdown projection writes at level 7' \
  "the render names the page level and the projection level"
run 1 "5 nested units in a context document's body fail the projection" -- depth_context
has "nested past Markdown's 6 heading levels" "the projection names the same limit for a context document"
rm -rf "$DEPTH/docs/design/alpha"

# A SECTION BELONGS TO THE DOCUMENT, NEVER TO A UNIT. `section` and
# `subsection` draw the fixed levels two and three. Inside a unit they kept
# them: four nested units and then a subsection holding a fifth rendered with
# the page levels 2, 3, 4, 5, 3, 4 — an outline out of order — passed the unit
# checks, and stopped every projection, which nests each heading below its
# host. All three carriers now refuse the call, in the same words.
spine_in_unit() { # <kind> <the call> <units above it>
  depth_layer "$(depth_nest_around "$3" "$2")"
  rm -f "$DEPTH/out.pdf"
  run 1 "a $1 inside $3 nested unit(s) fails the render" -- depth_render
  has "$1 block: is written inside a unit" "the render names the $1 and the rule"
  absent "$DEPTH/out.pdf" "no page is written for a $1 inside $3 nested unit(s)"
  run 1 "a $1 inside $3 nested unit(s) fails the projection" -- depth_context
  has "is written inside the body of unit 'd$3'" "the projection names the $1's unit"
  run 1 "a $1 inside $3 nested unit(s) fails the unit checks" -- depth_units
  has "is written inside the body of unit 'd$3'" "the gate's unit step names it too"
}
spine_in_unit section '#section(title: "Zinner", body: [Text.])' 1
spine_in_unit subsection '#subsection(title: "Zinner")[Text.]' 1
spine_in_unit subsection "#subsection(title: \"Zinner\")[ $(depth_unit 5) ]" 4
# Outside a unit the page keeps a section at its fixed level while the
# projection nests it, so a layer can render that the projection cannot
# address. The gate's unit step runs the projection's depth rule, so the gate
# refuses it rather than passing a layer no selector can read.
depth_layer "#section(title: \"Zouter\", body: [#section(title: \"Zinner\", body: [ $(depth_nest 4) ])])"
run 0 "four units inside a section inside a section render" -- depth_render
run 1 "the projection cannot address the fourth of them" -- depth_context
has "nested past Markdown's 6 heading levels" "the projection names the limit"
run 1 "the unit checks refuse the layer the projection cannot address" -- depth_units
has "unit 'd4'" "the gate's unit step names the unit"
has "nested past Markdown's 6 heading levels" "the gate's unit step runs the projection's depth rule"
# A unit inside a notes block: the projection places it below the notes
# heading, and the manifest holds the unit reader to the same level.
depth_layer "#section(title: \"Zparts\", notes: notes(title: \"Znotes\")[ $(depth_unit 1) ], body: [Text.])"
run 0 "a unit inside a notes block renders" -- depth_render
run 0 "the manifest addresses a unit inside a notes block" -- depth_context --manifest
has '"id": "d1"' "the manifest lists the unit inside the notes block"

# A HEADING WRITTEN IN MARKUP. Outside a unit it is the level its `=` signs
# say, numbered and listed in the contents, as it was before the unit block
# existed: the level a nested unit reads is carried without moving it. It used
# to be shifted by its host's level — `===` in a section body became level
# five, numbered 1.2.0.0.1, and left the contents.
depth_layer '#section(title: "Zparts", body: [Intro.

=== Zrawthree

Text.

#subsection(title: "Zsub")[Sub text.

==== Zrawfour

More.]])'
run 0 "markup headings in a section and a subsection render" -- depth_render
text="$(pdftotext -layout "$DEPTH/out.pdf" - 2>/dev/null)"
if [ "$(printf '%s\n' "$text" | grep -c '1\.2\.1 Zrawthree')" = "2" ]; then
  pass_line "a === heading in a section body is level three: numbered 1.2.1 on its page and in the contents"
else
  fail_line "a === heading in a section body is not numbered 1.2.1 in the contents and on its page"
fi
case "$text" in
*"1.2.2.1 Zrawfour"*) pass_line "a ==== heading in a subsection body is level four" ;;
*) fail_line "a ==== heading in a subsection body is not numbered 1.2.2.1" ;;
esac
case "$text" in
*"1.2.0"*) fail_line "a markup heading was shifted below its host and numbered through a missing level" ;;
*) pass_line "no markup heading is numbered through a missing level" ;;
esac
# Inside a unit a markup heading nests below the unit, at any depth, and one
# pushed past the sixth level fails naming itself instead of rendering.
depth_layer "$(depth_unit 1 '[Body.

= Zrawinunit

Text.]')"
run 0 "a markup heading in a unit body renders" -- depth_render
text="$(pdftotext -layout "$DEPTH/out.pdf" - 2>/dev/null)"
case "$text" in
*"1.2.1 Zrawinunit"*) pass_line "a markup heading in a unit body nests below the unit" ;;
*) fail_line "a markup heading in a unit body is not numbered below its unit" ;;
esac
depth_layer "$(depth_nest_around 5 '

== Zrawdeep

Text.')"
run 1 "a markup heading pushed past the sixth level fails the render" -- depth_render
has "a heading inside a unit body is drawn at level 8" "the render names the heading's level"

# EVERY KIND OF PROSE A FIELD MAY HOLD passes all three carriers: the render
# accepts it, the projection writes it, and the unit checks read it. The
# render is the strictest of the three, so this is the list it must not
# shrink below what authors write.
cat >"$DEPTH/docs/design/CONTEXT.typ" <<'EOF'
#let terms = (
  (slug: "term-zthing", title: [Zthing], body: [A thing the fixture cites.]),
)
EOF
depth_layer '#unit(
  id: "prose",
  title: [Zprose *title*],
  overview: [Plain *strong* _emph_ `code` "quoted" it'"'"'s https://example.org
    #link("https://example.org/x")[a link] $x^2 + a/b$ #adr(3)
    #lens-pill("state") #pill("state") #term("term-zthing") and @unit-prose. \
    A second line.],
  interface: ([`call()` returns #sym.arrow.r a #term("term-zthing").],),
  invariants: ("A plain string.",),
  side-effects: (),
  verification: [```sh
make test
```],
  paths: (),
)'
run 0 "a unit whose fields hold every kind of prose renders" -- depth_render
has "0 guideline(s)" "prose in a field fires no guideline"
run 0 "the projection writes every kind of prose a field holds" -- depth_context
has 'Overview: Plain **strong** *emph* `code` "quoted"' "the projection carries emphasis, code, and quotes"
has "[a link](https://example.org/x)" "the projection carries a link"
has "Zthing" "the projection carries a term citation by its title"
has "ADR-0003" "the projection carries an ADR citation"
run 0 "the unit checks read every kind of prose a field holds" -- depth_units
rm -f "$DEPTH/docs/design/CONTEXT.typ"

# --- 4. THE PROJECTION AND ITS SELECTORS ----------------------------------------
context >"$WORK/full.md" 2>"$WORK/full.err"
OUT="$(cat "$WORK/full.md")"
has "### unit: Zbilling" "the projection heads a unit by its title"
has "ID: ledger" "the projection carries the unit id"
has 'Paths: `src/ledger`, `src/shared`' "the projection carries the unit paths"
has "Side effects: None" "an empty list projects as None"
has "#### unit: Zledger" "a nested unit projects one heading level down"
has "- An entry is never rewritten." "a list section projects as a Markdown list"

run 0 "--unit selects one unit" -- context --unit ledger
has "#### unit: Zledger" "--unit returns the named unit"
has "##### principle: Zunitprin" "--unit returns the unit's body"
lacks "Zgateway" "--unit does not return a sibling unit"
lacks "<!-- source:" "--unit stops at the end of the unit"
# ONE UNIT IS ITS CONTRACT, ITS BODY, AND ITS NESTED UNITS — and nothing that
# follows it. The selector used to return the unit's heading subtree, which
# runs to the next heading of the same level: prose after a nested unit in its
# parent's body, and prose after the parent in its section, were both printed
# as though they belonged to the last nested unit.
run 0 "--unit selects the last nested unit" -- context --unit gateway
has "#### unit: Zgateway" "--unit returns the last nested unit"
lacks "Zafterchild" "--unit does not return the parent's prose that follows a nested unit"
lacks "Zafterparent" "--unit does not return the section's prose that follows the parent"
context --unit billing >"$WORK/billing.md"
OUT="$(cat "$WORK/billing.md")"
has "#### unit: Zgateway" "--unit on a parent returns its nested units"
has "Zafterchild" "--unit on a parent returns the prose its own body closes with"
lacks "Zafterparent" "--unit on a parent does not return the prose that follows it"
if [ "$(tail -n 1 "$WORK/billing.md")" = "Zafterchild is the group's own closing prose." ]; then
  pass_line "--unit ends on the last line the unit itself wrote"
else
  fail_line "--unit does not end on the unit's own last line"
fi
run 0 "--path selects the last nested unit by its path" -- context --path src/gateway
lacks "Zafterchild" "--path does not return prose that follows the unit it selects"
run 2 "--unit on an unknown id is an error" -- context --unit nope
has "unit not found: nope" "the error names the unknown id"

run 0 "--path selects the unit listing that path" -- context --path src/gateway
has "unit: Zgateway" "--path returns the unit listing the path"
lacks "Zledger" "--path does not return a unit listing another path"
run 0 "--path selects by a PARENT of the queried path" -- \
  context --path ./src/ledger/deep/file.rs
has "unit: Zledger" "a path inside a listed directory selects that unit"
run 0 "--path returns every governing unit" -- context --path src/shared
has "unit: Zledger" "the first unit listing the path is returned"
has "unit: Zshared" "the second unit listing the path is returned"
run 2 "--path with no governing unit is an error" -- context --path tools/release
has "no unit lists tools/release" "the error names the path"
run 2 "--path refuses a path that climbs" -- context --path ../outside
run 2 "--path refuses an absolute path" -- context --path /src/ledger
run 2 "--path refuses a glob" -- context --path 'src/*'
run 2 "--unit and --section are mutually exclusive" -- context --unit ledger --section 1.1
run 2 "--unit requires an id" -- context --unit

context --manifest >"$WORK/manifest.json"
if python3 - "$WORK/manifest.json" "$WORK/full.md" <<'PY'; then
import hashlib, json, pathlib, sys
manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
units = {u["id"]: u for u in manifest["units"]}
assert list(units) == ["billing", "ledger", "gateway", "shared-kernel"], list(units)
assert units["ledger"]["parent"] == "billing" and units["billing"]["parent"] is None
assert units["ledger"]["paths"] == ["src/ledger", "src/shared"]
assert units["shared-kernel"]["document"] == "alpha"
titles = {s["address"]: s["title"] for s in manifest["sections"]}
for unit in units.values():
    assert titles[unit["address"]] == "unit: " + unit["title"], unit
raw = pathlib.Path(sys.argv[2]).read_bytes()
assert manifest["projection"]["sha256"] == "sha256:" + hashlib.sha256(raw).hexdigest()
PY
  pass_line "the manifest lists every unit with its address, parent, and paths"
else
  fail_line "the manifest's unit listing is wrong"
fi
# A unit selected by id is NOT the heading subtree at its address. The two
# begin at the same heading; the subtree runs on to the next heading of that
# level, through whatever the unit's parents wrote after it, and the unit
# stops where its own node does. The digest guard and --output behave as they
# do for --section.
address="$(python3 -c 'import json,sys; print([u["address"] for u in json.load(open(sys.argv[1]))["units"] if u["id"]=="gateway"][0])' "$WORK/manifest.json")"
digest="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["projection"]["sha256"])' "$WORK/manifest.json")"
context --unit gateway >"$WORK/by-unit.md"
context --section "$address" >"$WORK/by-section.md"
if head -c "$(wc -c <"$WORK/by-unit.md")" "$WORK/by-section.md" | cmp -s - "$WORK/by-unit.md"; then
  pass_line "--unit returns the bytes the unit's heading subtree begins with"
else
  fail_line "--unit does not begin as the heading subtree at the unit's address does"
fi
OUT="$(cat "$WORK/by-section.md")"
has "Zafterchild" "--section at a unit's address runs on into the prose that follows the unit"
if cmp -s "$WORK/by-unit.md" "$WORK/by-section.md"; then
  fail_line "--unit returned the whole heading subtree, with the prose that follows the unit"
else
  pass_line "--unit stops where the unit does, short of its heading subtree"
fi
run 0 "--unit accepts the projection digest" -- context --unit gateway --expect-digest "$digest"
run 2 "--unit refuses a digest from another snapshot" -- \
  context --unit gateway --expect-digest sha256:0000
run 0 "--path accepts the projection digest" -- context --path src/shared --expect-digest "$digest"
rm -f "$WORK/out.md"
run 0 "--unit writes --output" -- context --unit gateway --output "$WORK/out.md"
same_file "$WORK/out.md" "$WORK/by-unit.md" "--output holds the selected unit"
run 0 "the public context app selects a unit" -- "$DESIGN_CONTEXT_APP" "$LAYER" --unit gateway
has "unit: Zgateway" "the public app returns the named unit"

# --- 5. THE GENERATOR ------------------------------------------------------------
# Hand-written text and a hand-written CLAUDE.md are in place BEFORE the first
# generation, so creation and preservation are observed in the same run.
printf '# Shared notes\n\nHand-written above.\n' >"$REPO/src/shared/AGENTS.md"
printf 'my own instructions\n' >"$REPO/src/gateway/CLAUDE.md"

run 1 "before generation the gate reports every missing folder contract" -- units --check
has "src/ledger/AGENTS.md: missing folder contract" "the gate names a missing contract"
if [ ! -e "$REPO/src/ledger/AGENTS.md" ]; then
  pass_line "--check writes nothing"
else
  fail_line "--check created a file"
fi

run 0 "the generator writes the folder contracts" -- units
has "wrote 3 folder contract(s)" "the generator counts what it wrote"
for d in ledger gateway shared; do
  if [ -f "$REPO/src/$d/AGENTS.md" ]; then
    pass_line "src/$d/AGENTS.md exists"
  else
    fail_line "src/$d/AGENTS.md was not written"
  fi
done
OUT="$(cat "$REPO/src/ledger/AGENTS.md")"
has "<!-- design-units:begin -->" "a created file opens the machine-owned region"
has "<!-- design-units:end -->" "a created file closes the machine-owned region"
has "Do not edit between these markers" "the region carries its do-not-edit notice"
has "## Design unit: Zledger" "the region carries the unit's title"
has "Overview: Appends immutable entries." "the region carries the overview"
has "- append(entry)" "the region carries the interface"
has "- An entry is never rewritten." "the region carries the invariants"
has "- Writes the ledger table." "the region carries the side effects"
has "Verification: cargo test -p ledger" "the region carries the verification"
has "(../../docs/design/design.typ#unit-ledger)" "the region links the unit in its Typst source"
has '`nix run .#design-context -- docs/design --unit ledger`' \
  "the region prints the command for the full unit, with the layer's own prefix"
lacks "Zbilling" "a grouping unit with no paths reaches no folder"
# The printed command is real: it is the selector, and it returns this unit.
if [ -f "$REPO/src/ledger/../../docs/design/design.typ" ]; then
  pass_line "the region's relative link resolves to the source file"
else
  fail_line "the region's relative link does not resolve"
fi

# Several units in one folder; one unit in several folders.
OUT="$(cat "$REPO/src/shared/AGENTS.md")"
has "## Design unit: Zledger" "a folder two units list carries the first"
has "## Design unit: Zshared" "a folder two units list carries the second"
has "(../../docs/design/alpha/design.typ#unit-shared-kernel)" \
  "a context's unit links its own design.typ"
if [ "$(grep -c 'design-units:begin' "$REPO/src/shared/AGENTS.md")" = "1" ]; then
  pass_line "a folder with several governing units still has ONE region"
else
  fail_line "a folder with several governing units has more than one region"
fi
if head -3 "$REPO/src/shared/AGENTS.md" | cmp -s - <(printf '# Shared notes\n\nHand-written above.\n'); then
  pass_line "text already in AGENTS.md is kept above the region"
else
  fail_line "text already in AGENTS.md was changed"
fi

# CLAUDE.md: linked when absent, never replaced.
if [ -L "$REPO/src/ledger/CLAUDE.md" ] && [ "$(readlink "$REPO/src/ledger/CLAUDE.md")" = "AGENTS.md" ]; then
  pass_line "an absent CLAUDE.md is created as a symlink to AGENTS.md"
else
  fail_line "CLAUDE.md was not linked to AGENTS.md"
fi
if [ ! -L "$REPO/src/gateway/CLAUDE.md" ] && [ "$(cat "$REPO/src/gateway/CLAUDE.md")" = "my own instructions" ]; then
  pass_line "an existing CLAUDE.md is never replaced"
else
  fail_line "an existing CLAUDE.md was replaced"
fi

run 0 "after generation the gate is clean" -- units --check
has "every folder contract is fresh" "the gate says the contracts are fresh"
has "4 unit(s), 4 unit path(s), 3 folder contract(s)" "the gate counts what it examined"
cp "$REPO/src/shared/AGENTS.md" "$WORK/shared.before"
run 0 "generating twice is idempotent" -- units
has "wrote 0 folder contract(s)" "a second run rewrites nothing"
same_file "$REPO/src/shared/AGENTS.md" "$WORK/shared.before" "a second run leaves the file byte-identical"

# REPLACE. Text outside the region — above AND below — survives a regeneration
# byte for byte, and the region follows the Typst.
printf '\nHand-written below.\n' >>"$REPO/src/shared/AGENTS.md"
write_root '("src/ledger", "src/shared")' "Appends entries and never edits one."
run 1 "an edited unit makes its folder contract stale" -- units --check
has "src/ledger/AGENTS.md: stale folder contract" "the gate names the stale contract"
run 0 "the generator replaces the region" -- units
OUT="$(cat "$REPO/src/shared/AGENTS.md")"
has "Appends entries and never edits one." "the replaced region carries the new text"
lacks "Appends immutable entries." "the replaced region drops the old text"
if head -3 "$REPO/src/shared/AGENTS.md" | cmp -s - <(printf '# Shared notes\n\nHand-written above.\n') &&
  tail -2 "$REPO/src/shared/AGENTS.md" | cmp -s - <(printf '\nHand-written below.\n'); then
  pass_line "replacing the region leaves the text above and below it unchanged"
else
  fail_line "replacing the region changed text outside it"
fi
run 0 "the gate is clean after the replacement" -- units --check

# A hand edit INSIDE the region is staleness, not authorship.
python3 - "$REPO/src/gateway/AGENTS.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
assert "Talks to the card processor." in s
open(p, "w").write(s.replace("Talks to the card processor.", "Hand-edited."))
PY
run 1 "a hand edit inside the region is stale" -- units --check
has "src/gateway/AGENTS.md: stale folder contract" "the gate names the hand-edited contract"
run 0 "the generator restores the region" -- units
run 0 "the gate is clean after the restore" -- units --check

# REMOVAL. src/shared leaves the ledger unit: the folder keeps its other unit.
write_root '("src/ledger",)' "Appends entries and never edits one."
run 1 "a path removed from a unit makes the folder's contract stale" -- units --check
run 0 "the generator rewrites the folder without the removed unit" -- units
OUT="$(cat "$REPO/src/shared/AGENTS.md")"
lacks "Zledger" "the unit that dropped the path is gone from the folder"
has "## Design unit: Zshared" "the unit still listing the path stays"

# Now no unit lists src/shared or src/ledger. src/shared holds hand-written
# text, so only its region goes; src/ledger held nothing else, so the file
# goes, and the link the generator made goes with it.
cat >"$LAYER/alpha/design.typ" <<'EOF'
#import "../.render/designlib.typ": *
#let title = [Zalpha]
#let body = [
  #goal(title: "Zalphagoal")[The one aim that differs from the root.]
]
EOF
write_root '()' "Appends entries and never edits one."
run 1 "a region in a folder no unit lists is reported" -- units --check
has "src/shared/AGENTS.md: stale folder contract" "the gate names the unlisted folder"
has "no unit lists this directory" "the gate says why the region is stale"
has "src/ledger/AGENTS.md: stale folder contract" "the gate names the second unlisted folder"
run 0 "the generator removes the unlisted regions" -- units
has "removed 2 stale region(s)" "the generator counts what it removed"
if cmp -s "$REPO/src/shared/AGENTS.md" <(printf '# Shared notes\n\nHand-written above.\n\nHand-written below.\n'); then
  pass_line "an emptied region is removed and the hand-written text is exactly restored"
else
  fail_line "removing the region did not restore the hand-written file"
  sed 's/^/       /' "$REPO/src/shared/AGENTS.md" | head -8
fi
if [ -L "$REPO/src/shared/CLAUDE.md" ]; then
  pass_line "the CLAUDE.md link stays while AGENTS.md still has content"
else
  fail_line "the CLAUDE.md link was removed though AGENTS.md remains"
fi
if [ ! -e "$REPO/src/ledger/AGENTS.md" ] && [ ! -L "$REPO/src/ledger/CLAUDE.md" ]; then
  pass_line "a file holding only the region is deleted, with the link made for it"
else
  fail_line "an emptied AGENTS.md or its dangling CLAUDE.md link was left behind"
fi
if [ -f "$REPO/src/gateway/AGENTS.md" ] && [ "$(cat "$REPO/src/gateway/CLAUDE.md")" = "my own instructions" ]; then
  pass_line "a folder a unit still lists is untouched by the removal"
else
  fail_line "the removal touched a folder that is still listed"
fi
run 0 "the gate is clean after the removal" -- units --check

# A file whose markers do not delimit one region is refused, never rewritten.
printf '<!-- design-units:begin -->\nno end marker\n' >"$REPO/tools/release/AGENTS.md"
(cd "$REPO" && git add -A >/dev/null 2>&1)
cp "$REPO/tools/release/AGENTS.md" "$WORK/malformed.before"
run 1 "a malformed region is a violation in --check" -- units --check
has "tools/release/AGENTS.md: malformed folder contract region" "the gate names the malformed file"
run 1 "a malformed region is a violation when generating" -- units
same_file "$REPO/tools/release/AGENTS.md" "$WORK/malformed.before" "a malformed file is left as it was"
rm -f "$REPO/tools/release/AGENTS.md"
# A marker mentioned inside a sentence is prose, not a region.
printf 'The region opens with `<!-- design-units:begin -->` on its own line.\n' \
  >"$REPO/tools/release/AGENTS.md"
(cd "$REPO" && git add -A >/dev/null 2>&1)
run 0 "a marker named inside prose is not a region" -- units --check
rm -f "$REPO/tools/release/AGENTS.md"

# --- 5b. WHAT THE GENERATOR REFUSES TO TOUCH ---------------------------------------
# The generator shares each file with hand-written text and each tree with
# links, other layers, and other spellings of one directory. Every case below
# starts from its own small repository — two units, `ua` on src/a and `ub` on
# src/b — so a refusal is judged alone, and so "nothing was written" can be
# read off the folder the run did NOT fault.
SAFE=""
safe_root() { # <paths of unit ua> <paths of unit ub>
  cat >"$SAFE/docs/design/design.typ" <<EOF
#import ".render/designlib.typ": *
#let title = [Zsafe]
#let body = [
  #section(title: "Foundation", body: [
    #goal(title: "Zsg")[g]
    #invariant(title: "Zsi", enforcement: "convention")[i]
    #principle(title: "Zsp")[p]
  ])
  #unit(id: "ua", title: "Zunit A", overview: "Overview A.", interface: (),
    invariants: (), side-effects: (), verification: "none", paths: $1)
  #unit(id: "ub", title: "Zunit B", overview: "Overview B.", interface: (),
    invariants: (), side-effects: (), verification: "none", paths: $2)
]
EOF
}
safe_repo() { # <name>
  SAFE="$WORK/safe/$1/repo"
  mkdir -p "$SAFE/docs/design" "$SAFE/src/a" "$SAFE/src/b" "$SAFE/other"
  cp -R "$LIB" "$SAFE/docs/design/.render"
  printf 'x\n' >"$SAFE/src/a/x.rs"
  printf 'x\n' >"$SAFE/src/b/x.rs"
  printf 'x\n' >"$SAFE/other/x"
  printf '.render/\n' >"$SAFE/.gitignore"
  safe_root '("src/a",)' '("src/b",)'
  (
    cd "$SAFE" && git init -q . && git add -A &&
      git -c user.name=t -c user.email=t@localhost commit -qm init
  ) >/dev/null 2>&1
}
safe_units() {
  DESIGN_LIB_DIR="$SAFE/docs/design/.render" python3 ./scripts/design-units \
    "$SAFE/docs/design" "$SAFE" "$@"
}
# The folder the run did not fault stays as it was: no file, no link.
nothing_written() { # <label>
  if [ ! -e "$SAFE/src/b/AGENTS.md" ] && [ ! -L "$SAFE/src/b/CLAUDE.md" ]; then
    pass_line "$1"
  else
    fail_line "$1: src/b was written although the run reported a violation"
  fi
}

# A TARGET THAT IS A SYMBOLIC LINK. Only the directory used to be resolved
# against the repository root, so a link named AGENTS.md was written through:
# to a file outside the repository, or into a new file where the link dangled.
safe_repo link-outside
printf 'outside notes\n' >"$WORK/safe/link-outside/outside.md"
cp "$WORK/safe/link-outside/outside.md" "$WORK/outside.before"
ln -s ../../../outside.md "$SAFE/src/a/AGENTS.md"
run 1 "a target linking outside the repository is a violation" -- safe_units
has "src/a/AGENTS.md: unusable folder contract file" "the violation names the linked target"
has "it is a symbolic link to ../../../outside.md" "the violation says the target is a link, and to what"
same_file "$WORK/safe/link-outside/outside.md" "$WORK/outside.before" \
  "the file the link points at outside the repository is not written"
nothing_written "a refused target stops every write, not only its own"
has "nothing was written" "the generator says it wrote nothing"
run 1 "the gate reports the linked target too" -- safe_units --check
line_lacks "src/a/AGENTS.md:" "run the units app" \
  "the gate does not send the reader to the generator for a target it refuses"

safe_repo link-dangling
ln -s ../../../created-outside.md "$SAFE/src/a/AGENTS.md"
run 1 "a dangling target link is a violation" -- safe_units
absent "$WORK/safe/link-dangling/created-outside.md" \
  "no file is created outside the repository through a dangling link"
nothing_written "a dangling link stops every write"

safe_repo link-inside
printf 'shared notes\n' >"$SAFE/other/notes.md"
ln -s ../../other/notes.md "$SAFE/src/a/AGENTS.md"
run 1 "a target linking to a file inside the repository is refused as well" -- safe_units
if [ "$(cat "$SAFE/other/notes.md")" = "shared notes" ]; then
  pass_line "the linked file inside the repository is not written"
else
  fail_line "the generator wrote through a link inside the repository"
fi

# A TARGET THAT IS NOT A FILE, or not text. Each is a violation with its own
# words — never a raw errno — found before any other folder is written.
safe_repo target-directory
mkdir "$SAFE/src/a/AGENTS.md"
run 1 "a target that is a directory is a violation, not an error" -- safe_units
has "it is a directory" "the violation says the target is a directory"
lacks "Errno" "no raw system error reaches the reader"
nothing_written "a directory in a target's place stops every write"
run 1 "the gate reports the directory" -- safe_units --check
line_lacks "src/a/AGENTS.md:" "run the units app" \
  "the gate does not tell the reader to regenerate over a directory"

safe_repo target-binary
printf '\377\376 not text\n' >"$SAFE/src/a/AGENTS.md"
cp "$SAFE/src/a/AGENTS.md" "$WORK/binary.before"
run 1 "a target that is not UTF-8 text is a violation" -- safe_units
has "it is not UTF-8 text" "the violation says why the file cannot be shared"
same_file "$SAFE/src/a/AGENTS.md" "$WORK/binary.before" "the undecodable file is left as it was"
nothing_written "an undecodable target stops every write"

# The well-formed run leaves no temporary file behind and keeps a file's mode.
safe_repo atomic
printf '# Private notes\n' >"$SAFE/src/a/AGENTS.md"
chmod 600 "$SAFE/src/a/AGENTS.md"
run 0 "the generator writes through a temporary file and a rename" -- safe_units
if [ -z "$(find "$SAFE/src" -name '.AGENTS.md.*')" ]; then
  pass_line "no temporary file is left beside a folder contract"
else
  fail_line "a temporary file was left behind"
fi
if [ "$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$SAFE/src/a/AGENTS.md")" = "0o600" ]; then
  pass_line "a rewritten file keeps its permissions"
else
  fail_line "a rewritten file lost its permissions"
fi

# A MARKER SOMEONE WROTE IS NOT A REGION. A region is the generator's whole
# shape. A marker inside a fenced or indented code block is an example and is
# never read, and it used to be deleted: from a directory no unit lists, and
# with the fence's content replaced in a listed one.
write_marker_example() { # <file>
  cat >"$1" <<'EOF'
# How a generated region looks

```markdown
<!-- design-units:begin -->
my own example text
<!-- design-units:end -->
```

~~~
<!-- design-units:begin -->
~~~

    <!-- design-units:end -->

Trailing prose.
EOF
}
safe_repo example-unlisted
write_marker_example "$SAFE/other/AGENTS.md"
cp "$SAFE/other/AGENTS.md" "$WORK/example.before"
(cd "$SAFE" && git add -A >/dev/null 2>&1)
run 0 "the generator runs beside a file that shows the markers as an example" -- safe_units
has "removed 0 stale region(s)" "an example of the markers is not removed as a stale region"
same_file "$SAFE/other/AGENTS.md" "$WORK/example.before" \
  "a file showing the markers in a code block is byte-identical after generation"
run 0 "the gate does not read the example as a region" -- safe_units --check
lacks "other/AGENTS.md" "the gate reports nothing about the example file"

safe_repo example-listed
write_marker_example "$SAFE/src/a/AGENTS.md"
run 0 "the generator adds a region below a file that shows the markers" -- safe_units
if head -c "$(wc -c <"$WORK/example.before")" "$SAFE/src/a/AGENTS.md" | cmp -s - "$WORK/example.before"; then
  pass_line "the example text is kept byte for byte above the generated region"
else
  fail_line "the example text was changed in a listed directory"
fi
OUT="$(cat "$SAFE/src/a/AGENTS.md")"
has "my own example text" "the fenced example still holds its own text"
has "## Design unit: Zunit A" "the real region is written below it"
run 0 "the gate reads the real region and not the example" -- safe_units --check
safe_root '()' '("src/b",)'
run 0 "the generator removes the real region and keeps the example" -- safe_units
same_file "$SAFE/src/a/AGENTS.md" "$WORK/example.before" \
  "removing the region restores the file that showed the markers"

# Anything else that holds a marker is MALFORMED: reported, and never changed.
malformed_case() { # <name> <needle> — the file is already in $SAFE/src/a/AGENTS.md
  cp "$SAFE/src/a/AGENTS.md" "$WORK/malformed-$1.before"
  run 1 "$1: a malformed region is a violation when generating" -- safe_units
  has "src/a/AGENTS.md: malformed folder contract region" "$1: the generator names the file"
  has "$2" "$1: the violation says what is wrong"
  same_file "$SAFE/src/a/AGENTS.md" "$WORK/malformed-$1.before" "$1: the file is left as it was"
  nothing_written "$1: a malformed file stops every write"
  run 1 "$1: a malformed region is a violation in the gate" -- safe_units --check
  line_lacks "src/a/AGENTS.md:" "run the units app" \
    "$1: the gate does not send the reader to the generator"
}
safe_repo malformed-bare-markers
printf 'Notes.\n\n<!-- design-units:begin -->\nhand-written between bare markers\n<!-- design-units:end -->\n' \
  >"$SAFE/src/a/AGENTS.md"
malformed_case bare-markers "holds a region marker outside a generated region"

safe_repo malformed-end-first
printf '<!-- design-units:end -->\nx\n<!-- design-units:begin -->\n' >"$SAFE/src/a/AGENTS.md"
malformed_case end-first "line 1, 3 holds a region marker"

safe_repo malformed-unclosed
{
  printf '<!-- design-units:begin -->\n'
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["design_doc"]["unit_contract"]["folder_contract"]["notice"])' \
    schema/design-schema.json
  printf '<!-- prettier-ignore-start -->\n\ntext with no closing lines\n'
} >"$SAFE/src/a/AGENTS.md"
malformed_case unclosed "is never closed"

safe_repo malformed-open-fence
printf '# Notes\n\n```\nan example that never closes its fence\n' >"$SAFE/src/a/AGENTS.md"
malformed_case open-fence "ends inside a code fence that is never closed"

# Two regions: generate once, then double the file.
safe_repo malformed-two-regions
safe_units >/dev/null 2>&1
cat "$SAFE/src/b/AGENTS.md" "$SAFE/src/b/AGENTS.md" >"$SAFE/src/a/AGENTS.md"
cp "$SAFE/src/a/AGENTS.md" "$WORK/two.before"
run 1 "a file holding two regions is a violation" -- safe_units
has "found 2 generated regions" "the violation counts the regions"
same_file "$SAFE/src/a/AGENTS.md" "$WORK/two.before" "a file holding two regions is left as it was"

# TWO SPELLINGS OF ONE DIRECTORY. The expected output was keyed by the path as
# written, so two spellings of one directory overwrote each other's region and
# generate-then-check reported "stale" for ever.
safe_repo spelling-link
ln -s a "$SAFE/src/link"
safe_root '("src/a",)' '("src/link",)'
run 1 "a unit path through a symlinked directory is a violation" -- safe_units
has "unit ub: unit path is not the directory's own path" "the violation names the unit and the rule"
has "src/link is declared, and the file system stores that directory as src/a" \
  "the violation names the declared path and the stored one"
absent "$SAFE/src/a/AGENTS.md" "no contract is written for a directory reached by two spellings"
run 1 "the gate reports the same spelling violation" -- safe_units --check

# A case-insensitive file system opens src/a for `src/A`. Where the file
# system is case-sensitive the same path simply does not exist; the run is a
# violation either way, and which one is asserted by what the file system does.
safe_repo spelling-case
safe_root '("src/a",)' '("src/A",)'
run 1 "a unit path in another letter case is a violation" -- safe_units
if [ -d "$SAFE/src/A" ]; then
  has "src/A is declared, and the file system stores that directory as src/a" \
    "on a case-insensitive file system the violation names both spellings"
else
  has "missing unit path: src/A does not exist" \
    "on a case-sensitive file system the other case is a missing path"
fi
absent "$SAFE/src/a/AGENTS.md" "no contract is written while one directory has two spellings"

# LINE ENDINGS AND THE FINAL NEWLINE belong to the file. A file with CRLF
# endings used to be rewritten wholesale with LF, and a file with no final
# newline gained one after its region was added and removed.
crlf_only() { # <file> — every line ends CRLF, none with a bare LF
  python3 - "$1" <<'PY'
import sys
data = open(sys.argv[1], "rb").read()
sys.exit(0 if b"\r\n" in data and b"\n" not in data.replace(b"\r\n", b"") else 1)
PY
}
safe_repo crlf
printf '# Notes\r\n\r\nHand-written with CRLF.\r\n' >"$SAFE/src/a/AGENTS.md"
cp "$SAFE/src/a/AGENTS.md" "$WORK/crlf.before"
run 0 "the generator adds a region to a CRLF file" -- safe_units
if head -c "$(wc -c <"$WORK/crlf.before")" "$SAFE/src/a/AGENTS.md" | cmp -s - "$WORK/crlf.before"; then
  pass_line "the CRLF text above the region is kept byte for byte"
else
  fail_line "the CRLF text above the region was rewritten"
fi
if crlf_only "$SAFE/src/a/AGENTS.md"; then
  pass_line "the region takes the file's own CRLF line ending"
else
  fail_line "the file now mixes line endings"
fi
run 0 "a CRLF region is fresh in the gate" -- safe_units --check
cp "$SAFE/src/a/AGENTS.md" "$WORK/crlf.generated"
run 0 "regenerating a CRLF file is idempotent" -- safe_units
has "wrote 0 folder contract(s)" "a fresh CRLF region is not rewritten"
same_file "$SAFE/src/a/AGENTS.md" "$WORK/crlf.generated" "a second run leaves the CRLF file byte-identical"
safe_root '("src/a",)' '("src/a", "src/b")'
run 0 "the generator replaces the region of a CRLF file" -- safe_units
if crlf_only "$SAFE/src/a/AGENTS.md" && grep -q "Zunit B" "$SAFE/src/a/AGENTS.md"; then
  pass_line "a replaced region keeps the file's CRLF line ending"
else
  fail_line "replacing the region changed the file's line endings"
fi
safe_root '()' '("src/b",)'
run 0 "the generator removes the region of a CRLF file" -- safe_units
same_file "$SAFE/src/a/AGENTS.md" "$WORK/crlf.before" \
  "removing the region restores the CRLF file byte for byte"

safe_repo no-final-newline
printf 'line one\nline two' >"$SAFE/src/a/AGENTS.md"
cp "$SAFE/src/a/AGENTS.md" "$WORK/nofinal.before"
run 0 "the generator adds a region to a file with no final newline" -- safe_units
if head -c "$(wc -c <"$WORK/nofinal.before")" "$SAFE/src/a/AGENTS.md" | cmp -s - "$WORK/nofinal.before" &&
  [ "$(tail -c 1 "$SAFE/src/a/AGENTS.md" | od -An -c | tr -d ' ')" != '\n' ]; then
  pass_line "the file keeps its text and still ends without a newline"
else
  fail_line "the file gained a final newline, or its text changed"
fi
run 0 "a region at the end of a file with no final newline is fresh" -- safe_units --check
safe_root '()' '("src/b",)'
run 0 "the generator removes that region" -- safe_units
same_file "$SAFE/src/a/AGENTS.md" "$WORK/nofinal.before" \
  "add-then-remove restores a file with no final newline exactly"

# --- 6. THE GATE -----------------------------------------------------------------
# Restore the full fixture and generate, so each broken variant starts clean.
cp "$WORK/alpha.good" "$LAYER/alpha/design.typ"
write_root '("src/ledger", "src/shared")' "Appends immutable entries."
run 0 "the fixture regenerates" -- units
run 0 "the fixture re-renders" -- render
(cd "$REPO" && git add -A && git -c user.name=t -c user.email=t@localhost commit -qm units) >/dev/null 2>&1

run 0 "layer-integrity resolves a link to a unit anchor" -- python3 ./scripts/layer-integrity "$REPO"
# THE HOST-LINK CHECK READS THE GENERATED REGIONS. layer-integrity resolves
# every link an AGENTS.md outside docs/ carries into the layer, and a
# generated region carries one per unit, to `design.typ#unit-<id>`. The
# fixture's three folder contracts hold four such links, and all of them
# resolve beside units, fresh regions, and a clean gate.
has "resolved 3 instruction files" "the host-link check reads the three generated folder contracts"
has "4 instruction links resolved" "the host-link check resolves each generated link into the layer"
run 0 "the unit checks are clean beside the host-link check" -- units --check
# A generated link names a unit by id. One that names no declared unit is a
# dangling link, reported at the folder contract's own line.
cp "$REPO/src/gateway/AGENTS.md" "$WORK/gateway.linked"
sed 's/design\.typ#unit-gateway)/design.typ#unit-absent)/' "$WORK/gateway.linked" \
  >"$REPO/src/gateway/AGENTS.md"
if cmp -s "$REPO/src/gateway/AGENTS.md" "$WORK/gateway.linked"; then
  fail_line "the fixture did not change the generated link"
else
  pass_line "the fixture points a generated link at a unit nobody declares"
fi
run 1 "the host-link check refuses a generated link to a unit nobody declares" -- \
  python3 ./scripts/layer-integrity "$REPO"
has "src/gateway/AGENTS.md:" "the violation names the folder contract and its line"
has 'no heading renders id "unit-absent"' "the violation names the unit id that does not exist"
run 1 "the unit checks call the same region stale" -- units --check
has "src/gateway/AGENTS.md: stale folder contract" "the gate's unit step names the edited region"
cp "$WORK/gateway.linked" "$REPO/src/gateway/AGENTS.md"
run 0 "the host-link check passes once the generated link is restored" -- \
  python3 ./scripts/layer-integrity "$REPO"
cp "$REPO/docs/COVERAGE.md" "$WORK/coverage.good"
sed 's/#unit-ledger/#unit-absent/' "$WORK/coverage.good" >"$REPO/docs/COVERAGE.md"
run 1 "layer-integrity refuses a link to a unit nobody declares" -- \
  python3 ./scripts/layer-integrity "$REPO"
has 'no heading renders id "unit-absent"' "the violation names the missing unit anchor"
cp "$WORK/coverage.good" "$REPO/docs/COVERAGE.md"
# The id is a named argument and may stand anywhere in the call. A unit written
# title-first renders, so a link to it must resolve: the index used to read the
# id only as the FIRST argument and reported this anchor as dangling. The call
# also carries what a careless scan trips on — a quote and a parenthesis in
# prose, a URL, and an `id:` belonging to something else.
python3 - "$LAYER/alpha/design.typ" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
first = '    id: "shared-kernel",\n'
last = '    paths: ("src/shared",),\n'
assert first in s and last in s
s = s.replace(first, "").replace(last, last + first)
open(p, "w").write(s)
PY
printf '| Shared | captured | [Zshared](design/alpha/design.typ#unit-shared-kernel) |\n' \
  >>"$REPO/docs/COVERAGE.md"
run 0 "a unit whose id is not its first argument still renders" -- render
run 0 "layer-integrity resolves a link to a unit written title-first" -- \
  python3 ./scripts/layer-integrity "$REPO"
run 0 "the folder contracts do not depend on argument order" -- units --check
# A `//` inside a STRING is text. The scan cut every `//` to the end of its
# line before it read the call, so a field such as `overview: "a // b"` lost
# its closing quote and the `id:` after it was never found. A `//` outside a
# string still opens a comment, and a unit call inside one declares nothing.
python3 - "$LAYER/alpha/design.typ" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
overview = '    overview: "Types both parts use.",\n'
assert overview in s
s = s.replace(
    overview,
    '    overview: "Types both parts use. // not a comment",  // a real comment\n'
    "    /* a block comment, with id: \"wrong\" in it */\n",
)
s += '// #unit(id: "ghost", title: "Commented out", paths: ())\n'
open(p, "w").write(s)
PY
run 0 "a unit with // inside a string field still renders" -- render
run 0 "layer-integrity resolves a link to a unit whose earlier field holds //" -- \
  python3 ./scripts/layer-integrity "$REPO"
printf '| Ghost | captured | [Zghost](design/alpha/design.typ#unit-ghost) |\n' \
  >>"$REPO/docs/COVERAGE.md"
run 1 "a unit call inside a comment declares no anchor" -- python3 ./scripts/layer-integrity "$REPO"
has 'no heading renders id "unit-ghost"' "the violation names the commented-out unit's anchor"
cp "$WORK/alpha.good" "$LAYER/alpha/design.typ"
cp "$WORK/coverage.good" "$REPO/docs/COVERAGE.md"
# The overview's text changed and is restored, so the page is rendered again.
run 0 "the fixture re-renders after the comment variants" -- render

# The composite, through the public app: clean first, then one broken variant
# per new check, each restored before the next.
run 0 "the public gate passes the fixture" -- "$DESIGN_CHECK_APP" "$LAYER" "$REPO"
has "every folder contract is fresh" "the public gate runs the unit checks"
has "design-units: report:" "the public gate prints the uncovered-directory report"

# (a) a unit path that does not exist
write_root '("src/ledger", "src/shared", "src/absent")' "Appends immutable entries."
"$DESIGN_RENDER_APP" "$LAYER" "$LAYER/design-layer.pdf" >/dev/null 2>&1
run 1 "the public gate fails a unit path that does not exist" -- "$DESIGN_CHECK_APP" "$LAYER" "$REPO"
has "missing unit path: src/absent does not exist" "the gate names the missing path"
run 1 "the generator fails a unit path that does not exist" -- units
if [ ! -e "$REPO/src/absent" ]; then
  pass_line "the generator does not create a missing unit path"
else
  fail_line "the generator created the missing directory"
fi
# a unit path naming a FILE
write_root '("src/ledger", "src/shared", "src/main.rs")' "Appends immutable entries."
run 1 "a unit path naming a file is a violation" -- units --check
has "unit path is not a directory" "the gate says a unit path names a folder"
# a unit path that leaves the repository through a symlink
ln -s "$WORK" "$REPO/src/escape"
write_root '("src/ledger", "src/shared", "src/escape")' "Appends immutable entries."
run 1 "a unit path resolving outside the repository is a violation" -- units --check
has "unit path escapes the repository" "the gate names the escaping path"
rm -f "$REPO/src/escape"
# git's own directory and the layer directory are not a unit's folders.
write_root '("src/ledger", "src/shared", ".git")' "Appends immutable entries."
run 1 "a unit path naming .git is a violation" -- units
has "unit path is inside git's own directory" "the violation names the .git rule"
absent "$REPO/.git/AGENTS.md" "no contract is written into .git"
write_root '("src/ledger", "src/shared", "docs/design")' "Appends immutable entries."
run 1 "a unit path naming the layer directory is a violation" -- units
has "unit path names the design layer" "the violation names the layer rule"
absent "$LAYER/AGENTS.md" "no contract is written into the layer directory"
write_root '("src/ledger", "src/shared", "docs/design/alpha")' "Appends immutable entries."
run 1 "a unit path inside the layer directory is a violation" -- units --check
has "unit path names the design layer" "a context directory is the layer too"
write_root '("src/ledger", "src/shared")' "Appends immutable entries."
"$DESIGN_RENDER_APP" "$LAYER" "$LAYER/design-layer.pdf" >/dev/null 2>&1
run 0 "the public gate passes again" -- "$DESIGN_CHECK_APP" "$LAYER" "$REPO"

# (b) a stale folder contract
cp "$REPO/src/gateway/AGENTS.md" "$WORK/gateway.good"
sed 's/Talks to the card processor./Stale text./' "$WORK/gateway.good" >"$REPO/src/gateway/AGENTS.md"
run 1 "the public gate fails a stale folder contract" -- "$DESIGN_CHECK_APP" "$LAYER" "$REPO"
has "src/gateway/AGENTS.md: stale folder contract" "the gate names the stale file"
cp "$WORK/gateway.good" "$REPO/src/gateway/AGENTS.md"

# (c) a contract in a folder no unit lists
cp "$WORK/gateway.good" "$REPO/tools/release/AGENTS.md"
(cd "$REPO" && git add -A >/dev/null 2>&1)
run 1 "the public gate fails a contract no unit lists" -- "$DESIGN_CHECK_APP" "$LAYER" "$REPO"
has "tools/release/AGENTS.md: stale folder contract" "the gate names the unlisted folder"
rm -f "$REPO/tools/release/AGENTS.md"
(cd "$REPO" && git add -A >/dev/null 2>&1)
run 0 "the public gate passes once the variants are restored" -- "$DESIGN_CHECK_APP" "$LAYER" "$REPO"

# The public generator app, on a removed contract.
rm -f "$REPO/src/gateway/AGENTS.md"
run 0 "the public units app regenerates a deleted contract" -- "$DESIGN_UNITS_APP" "$LAYER" "$REPO"
same_file "$REPO/src/gateway/AGENTS.md" "$WORK/gateway.good" "the public app writes the same contract"

# The unit checks read the units, not the Markdown projection. A layer is
# well-formed without the corpus maps the projection requires, so the gate
# must hold one that has neither.
mv "$REPO/docs/COVERAGE.md" "$WORK/coverage.away"
mv "$REPO/docs/CONTEXT-MAP.md" "$WORK/map.away"
run 0 "the unit checks do not require the projection's corpus maps" -- units --check
run 1 "the projection itself still requires them" -- context
mv "$WORK/coverage.away" "$REPO/docs/COVERAGE.md"
mv "$WORK/map.away" "$REPO/docs/CONTEXT-MAP.md"

# THE REPORT. It lists what no unit path covers and never changes the exit.
run 0 "the report leaves a clean gate at exit 0" -- units --check
has "covered by no unit path (a report, not a check)" "the report says it is not a check"
has "  tools/ (1 file(s))" "the report lists an unclaimed subtree once, at its top"
has "  src/ (1 file(s) directly in it; a subdirectory is claimed)" \
  "the report lists files beside a claimed subdirectory"
lacks "  src/ledger" "the report does not list a claimed directory"
lacks "  docs/design" "the report does not list the layer's own home"
# docs/ holds the layer's maps beside the layer directory. They are the layer,
# not source, and listing docs/ for them told every host that the design does
# not claim its own documents.
lacks "  docs/" "the report does not list docs/ for the layer's own maps"
# The exclusion is the maps alone: any other tracked file there is still listed.
mkdir -p "$REPO/docs/runbook"
printf 'notes\n' >"$REPO/docs/runbook/restart.md"
(cd "$REPO" && git add -A >/dev/null 2>&1)
run 0 "the report still runs with an unclaimed document beside the layer" -- units --check
has "  docs/ (1 file(s))" "a tracked file under docs/ that is not the layer's is listed"
rm -rf "$REPO/docs/runbook"
(cd "$REPO" && git add -A >/dev/null 2>&1)
# Outside git the report says it did not run, rather than listing nothing.
NOGIT="$WORK/nogit"
mkdir -p "$NOGIT"
cp -R "$REPO/docs" "$REPO/src" "$REPO/tools" "$NOGIT/"
OUT="$(DESIGN_LIB_DIR="$NOGIT/docs/design/.render" python3 ./scripts/design-units \
  "$NOGIT/docs/design" "$NOGIT" --check 2>&1)"
code=$?
if [ "$code" -eq 0 ]; then
  pass_line "the checks run outside a git work tree (exit 0)"
else
  fail_line "the checks failed outside a git work tree (exit $code)"
fi
has "is not a git work tree" "the report says it was skipped outside git"

# A nested project's contracts belong to its own layer.
mkdir -p "$REPO/projects/one/docs/design" "$REPO/projects/one/lib"
cat >"$REPO/projects/one/docs/design/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Znested]
#let index_only = true
#let body = [
  #unit(
    id: "ledger",
    title: "Znested ledger",
    overview: "The nested project's own unit, reusing an id of the outer layer.",
    interface: (),
    invariants: (),
    side-effects: (),
    verification: "None.",
    paths: ("lib",),
  )
]
EOF
printf '# Coverage\n' >"$REPO/projects/one/docs/COVERAGE.md"
printf 'x\n' >"$REPO/projects/one/lib/x.rs"
(cd "$REPO" && git add -A >/dev/null 2>&1)
run 0 "the public units app writes a nested project's contracts" -- \
  "$DESIGN_UNITS_APP" "$REPO/projects/one/docs/design" "$REPO/projects/one"
"$DESIGN_RENDER_APP" "$REPO/projects/one/docs/design" \
  "$REPO/projects/one/docs/design/design-layer.pdf" >/dev/null 2>&1
(cd "$REPO" && git add -A >/dev/null 2>&1)
run 1 "without the exclusion the outer scan reports the nested contract" -- units --check
has "projects/one/lib/AGENTS.md: stale folder contract" "the outer scan names the nested folder"
has "pass --nested-project projects/one" "the gate names the argument that declares the project"
line_lacks "projects/one/lib/AGENTS.md:" "run the units app to remove it" \
  "the gate does not tell the reader to remove another layer's contract"
# THE GENERATOR NEVER TOUCHES A NESTED PROJECT BY DEFAULT. Run without the
# argument it used to remove the nested region, delete the emptied file, and
# delete the CLAUDE.md link made for it.
cp "$REPO/projects/one/lib/AGENTS.md" "$WORK/nested.good"
run 1 "the generator reports an undeclared nested project instead of removing its contract" -- units
has "pass --nested-project projects/one" "the generator names the argument too"
same_file "$REPO/projects/one/lib/AGENTS.md" "$WORK/nested.good" \
  "the nested project's contract is left as it was"
if [ -L "$REPO/projects/one/lib/CLAUDE.md" ]; then
  pass_line "the nested project's CLAUDE.md link is left in place"
else
  fail_line "the nested project's CLAUDE.md link was removed"
fi
run 0 "--exclude-project leaves the nested project out of the outer run" -- \
  units --exclude-project projects/one
same_file "$REPO/projects/one/lib/AGENTS.md" "$WORK/nested.good" \
  "an excluded project's contract is not rewritten"
# --nested-project is the argument `check` takes: the project is left out of
# the outer run and then handled against its own root, in the same invocation.
run 0 "--layers names the outer layer and each nested layer" -- \
  units --layers --nested-project projects/one
has "$REPO/projects/one/docs/design" "the nested layer is named for the app to prepare"
sed 's/The nested project/A stale nested project/' "$WORK/nested.good" \
  >"$REPO/projects/one/lib/AGENTS.md"
run 1 "the gate with --nested-project fails a stale nested contract" -- \
  units --check --nested-project projects/one
has "nested project projects/one" "the nested run is labelled with its project"
has "lib/AGENTS.md: stale folder contract" "the nested run names the stale contract by its own root"
# The public app prepares the nested layer's library copy itself.
rm -rf "$REPO/projects/one/docs/design/.render"
run 0 "the public units app writes the outer layer and a nested project in one run" -- \
  "$DESIGN_UNITS_APP" "$LAYER" "$REPO" --nested-project projects/one
same_file "$REPO/projects/one/lib/AGENTS.md" "$WORK/nested.good" \
  "the nested project's stale contract is regenerated against its own root"
run 0 "the gate with --nested-project is clean afterwards" -- \
  units --check --nested-project projects/one
# A declared nested project's folders are not the outer layer's to claim.
write_root '("src/ledger", "src/shared", "projects/one/lib")' "Appends immutable entries."
run 1 "an outer unit path inside a nested project is a violation" -- \
  units --check --nested-project projects/one
has "unit path is inside a nested project" "the violation names the nested-project rule"
write_root '("src/ledger", "src/shared")' "Appends immutable entries."
run 2 "--nested-project requires a project that holds a layer" -- \
  units --nested-project src/ledger
has "nested project has no layer" "the error says what a nested project is"
run 0 "the public gate checks a nested project against its own root" -- \
  "$DESIGN_CHECK_APP" "$LAYER" "$REPO" --nested-project projects/one
printf 'stale\n' >>"$REPO/projects/one/lib/AGENTS.md"
sed -i.bak 's/The nested project/A stale nested project/' "$REPO/projects/one/lib/AGENTS.md"
run 1 "the public gate fails a stale contract inside a nested project" -- \
  "$DESIGN_CHECK_APP" "$LAYER" "$REPO" --nested-project projects/one
has "lib/AGENTS.md: stale folder contract" "the nested run names the stale contract"
rm -rf "$REPO/projects"
(cd "$REPO" && git add -A >/dev/null 2>&1)

# THE FORBIDDEN PATH CHARACTERS ARE THE SCHEMA'S. A schema that forbids one
# more character must be obeyed by the selector and by the generator's project
# arguments; a list repeated in either script would keep accepting it.
python3 - schema/design-schema.json "$WORK/plus-schema.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
doc["design_doc"]["unit_contract"]["path_forbidden_characters"].append("+")
json.dump(doc, open(sys.argv[2], "w", encoding="utf-8"))
PY
mkdir -p "$REPO/vendor/a+b"
run 2 "--path accepts a character the schema does not forbid" -- context --path 'src/a+b'
has "no unit lists src/a+b" "the query was compared with the unit paths"
run 2 "--path refuses a character the schema forbids" -- \
  env DESIGN_SCHEMA="$WORK/plus-schema.json" python3 ./scripts/design-context "$LAYER" --path 'src/a+b'
has "--path requires one repo-relative path" "the refusal is the path rule, read from the schema"
run 2 "--path refuses a glob character the schema declares" -- context --path 'src/[ab]'
has "--path requires one repo-relative path" "a declared glob character is refused"
run 0 "a project argument may carry a character the schema does not forbid" -- \
  units --check --exclude-project 'vendor/a+b'
run 2 "a project argument is held to the schema's forbidden characters" -- \
  env DESIGN_SCHEMA="$WORK/plus-schema.json" python3 ./scripts/design-units \
  "$LAYER" "$REPO" --check --exclude-project 'vendor/a+b'
has "invalid --exclude-project value" "the refusal names the argument"
rmdir "$REPO/vendor/a+b" "$REPO/vendor"

# context_command: the default, and a value the generator cannot print.
python3 - "$LAYER/design.typ" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
line = '#let context_command = "nix run .#design-context --"\n'
assert line in s
open(p, "w").write(s.replace(line, ""))
PY
run 0 "the generator runs without a context_command" -- units
OUT="$(cat "$REPO/src/ledger/AGENTS.md")"
has '`nix run github:lostbean/design-layer#context -- docs/design --unit ledger`' \
  "the schema's default command is printed when the layer names none"
python3 - "$LAYER/design.typ" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
head = '#let title = [Zroot]\n'
assert head in s
open(p, "w").write(s.replace(head, head + '#let context_command = 42\n'))
PY
run 1 "a context_command that is not a one-line string is a violation" -- units --check
has "unusable context_command" "the violation names the binding"

# A unit whose text holds a marker line is refused before it is written: the
# region would close early and read as malformed on every later run.
cp "$LAYER/design.typ" "$WORK/root.before-marker"
write_root '("src/ledger", "src/shared")' 'First line.\n<!-- design-units:end -->\nLast line.'
run 1 "a unit whose text holds a region marker is a violation" -- units --check
has "unit text holds a folder contract marker" "the violation names the marker rule"
cp "$WORK/root.before-marker" "$LAYER/design.typ"

# --- 7. A LAYER THAT AUTHORS NO UNIT ---------------------------------------------
PLAIN="$WORK/plain"
mkdir -p "$PLAIN/docs/design/alpha" "$PLAIN/src"
cp -R "$LIB" "$PLAIN/docs/design/.render"
cat >"$PLAIN/docs/design/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Zplain]
#let body = [
  #section(title: "Foundation", body: [
    #goal(title: "Zpg")[g]
    #invariant(title: "Zpi", enforcement: "convention")[i]
    #principle(title: "Zpp")[p]
  ])
  #section(title: "System at a glance", body: [Prose only.])
]
EOF
cat >"$PLAIN/docs/design/alpha/design.typ" <<'EOF'
#import "../.render/designlib.typ": *
#let title = [Zplain alpha]
#let body = [#section(title: "Notes", body: [A context of free prose.])]
EOF
printf '# Map\n' >"$PLAIN/docs/CONTEXT-MAP.md"
printf '# Coverage\n' >"$PLAIN/docs/COVERAGE.md"
printf '# Hand-written\n' >"$PLAIN/src/AGENTS.md"
plain() { DESIGN_LIB_DIR="$PLAIN/docs/design/.render" "$@"; }
run 0 "a layer with no unit renders" -- plain python3 ./scripts/design-aggregate \
  "$PLAIN/docs/design" "$PLAIN/docs/design/design-layer.pdf"
run 0 "a layer with no unit passes the unit checks" -- plain python3 ./scripts/design-units \
  "$PLAIN/docs/design" "$PLAIN" --check
has "0 unit(s), 0 unit path(s), 0 folder contract(s), 1 AGENTS.md file(s) scanned" \
  "the summary says nothing was claimed and what was scanned"
run 0 "the generator on a layer with no unit writes nothing" -- plain python3 \
  ./scripts/design-units "$PLAIN/docs/design" "$PLAIN"
if [ "$(cat "$PLAIN/src/AGENTS.md")" = "# Hand-written" ] && [ ! -e "$PLAIN/src/CLAUDE.md" ]; then
  pass_line "a hand-written AGENTS.md with no region is never touched"
else
  fail_line "a hand-written AGENTS.md was changed"
fi
plain python3 ./scripts/design-context "$PLAIN/docs/design" --manifest >"$WORK/plain-manifest.json"
if python3 -c 'import json,sys; sys.exit("units" in json.load(open(sys.argv[1])))' "$WORK/plain-manifest.json"; then
  pass_line "a layer with no unit keeps a manifest with no units key"
else
  fail_line "the manifest gained a units key for a layer with no unit"
fi
run 2 "--unit on a layer with no unit is an error" -- plain python3 \
  ./scripts/design-context "$PLAIN/docs/design" --unit anything
run 0 "the public gate passes a layer with no unit" -- \
  "$DESIGN_CHECK_APP" "$PLAIN/docs/design" "$PLAIN"

# A host may gate with its OWN schema copy. One that predates the unit block
# must keep rendering a layer that authors no unit, must say that the unit
# checks did not run, and must refuse the first unit by name.
#
# The copy is the schema AS IT STOOD before the unit block: every declaration
# the block added is absent from it, not only the two the library reads. A
# copy made by deleting keys from today's schema would keep whatever else the
# block changed, and would then prove nothing about a host that has not
# upgraded its schema at all. The fixture is checked for that first, so it
# cannot drift into a schema that knows the block.
OLD="$WORK/old"
mkdir -p "$OLD/docs/design"
cp fixtures/design-schema.before-units.json "$OLD/schema.json"
if python3 - "$OLD/schema.json" schema/design-schema.json <<'PY'; then
import json, sys
old = json.load(open(sys.argv[1], encoding="utf-8"))["design_doc"]
new = json.load(open(sys.argv[2], encoding="utf-8"))["design_doc"]
projected = lambda doc: doc["agent_context"]["projection"]["classification"]["projected"]
for doc, present in ((old, False), (new, True)):
    assert ("unit_contract" in doc) is present
    assert ("unit" in doc["blocks"]) is present
    assert ("spine_scope" in doc) is present
    assert ("unit" in projected(doc)) is present
assert old["foundation_cardinality"] != new["foundation_cardinality"]
PY
  pass_line "the old-schema fixture declares nothing the unit block added"
else
  fail_line "the old-schema fixture is not the schema from before the unit block"
fi
bash ./scripts/render-project "$OLD/schema.json" "$OLD/docs/design/.render" >/dev/null
cp "$PLAIN/docs/design/design.typ" "$OLD/docs/design/design.typ"
printf '# Coverage\n' >"$OLD/docs/COVERAGE.md"
old() { DESIGN_SCHEMA="$OLD/schema.json" DESIGN_LIB_DIR="$OLD/docs/design/.render" "$@"; }
run 0 "a schema without the unit contract still renders a layer with no unit" -- \
  old python3 ./scripts/design-aggregate "$OLD/docs/design" "$OLD/out.pdf"
run 0 "the unit checks say they did not run under that schema" -- \
  old python3 ./scripts/design-units "$OLD/docs/design" "$OLD" --check
has "declares no design_doc.unit_contract" "the skip is said aloud, never silent"
run 0 "layer-integrity runs under that schema" -- old python3 ./scripts/layer-integrity "$OLD"
cat >>"$OLD/docs/design/design.typ" <<EOF
#let body = [#unit($UNIT_OK)]
EOF
run 1 "a unit authored under that schema fails the render" -- \
  old python3 ./scripts/design-aggregate "$OLD/docs/design" "$OLD/out.pdf"
has "declares no design_doc.unit_contract" "the failure names the missing schema declaration"

# Usage errors.
run 2 "the generator refuses a missing layer root" -- python3 ./scripts/design-units "$WORK/absent"
run 2 "the generator refuses an unknown option" -- units --frobnicate
run 2 "the generator refuses a layer outside the repo root" -- \
  python3 ./scripts/design-units "$LAYER" "$REPO/src"
run 2 "the generator refuses an exclusion that climbs" -- units --exclude-project ../x

echo
if [ "$FAIL" -eq 0 ]; then
  echo "design-units: OK ($PASS assertion(s) passed)"
  exit 0
fi
echo "design-units: $FAIL assertion(s) failed, $PASS passed"
exit 1
