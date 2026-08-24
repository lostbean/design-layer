#!/usr/bin/env bash
#
# widget-coverage.test.sh — every declared block kind is projected, and the
# gallery exercises every function the projection offers an author.
#
# WHY THIS TEST EXISTS. The block vocabulary is declared in the schema,
# projected into a Typst library, and demonstrated in the gallery. Those three
# can drift independently, and each drift is SILENT: a block declared but not
# projected fails only when someone writes it; a function projected but not
# demonstrated is never exercised, so a regression in it ships. This test binds
# the three together.
#
# HOW THE LIBRARY IS INSPECTED, AND WHY IT CHANGED. This check used to read the
# library's SOURCE TEXT and call a `#let name(` line a function. That made the
# check an assertion about a spelling rather than about the library: a function
# bound any other way — by a closure factory, `#let goal = STATEMENTS.at("goal")`
# — has no `(` after its name, so the regex reported it ABSENT. This is a
# COVERAGE check, so that failure would not have been loud. It would have
# reported the kind missing while the library provided it perfectly, and the
# reverse error is worse still: a name the regex happens to match is called
# covered without anyone asking whether it is a callable function at all.
#
# So the library is now asked, at runtime, what it provides. `dictionary()` over
# an imported module enumerates that module's scope, and the value at each name
# carries its type. The check therefore asserts the thing it means — this name
# resolves, in the compiled library, to a callable function — and it asserts it
# without any knowledge of how the binding was written. A generated `#let f(..)`
# and a factory-built `#let f = D.at("f")` are indistinguishable to it, which is
# the property that lets the library change shape underneath it.
#
# It checks these things:
#   1. every block kind the SCHEMA declares resolves, in the compiled library,
#      to a callable function (or is deliberately exempt — a fenced diagram
#      language, which reaches a carrier rather than a directive function)
#   2. the GALLERY calls every function projected for authoring
#   3. the gallery RENDERS, and its marks reach the page — a function can be
#      declared, projected, present in the gallery, and still fail to compile,
#      and a page that draws nothing still exits 0
#   4. the schema's vendored package set matches the flake's
#
# Usage: widget-coverage.test.sh [repo-root]
# Exit: 0 all pass, 1 a check failed, 2 the check could not run.
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1

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

SCHEMA="schema/design-schema.json"

# The library is PROJECTED FRESH from the one declared schema. This repo ships
# the gate and holds no design layer of its own, so there is no committed
# projection to read; projecting here also makes check 1 below a statement
# about the schema as it stands, never about a stale committed copy.
WC_TMP="$(mktemp -d)"
trap 'rm -rf "$WC_TMP"' EXIT
LIB="$WC_TMP/.render/designlib.typ"
if ! bash ./scripts/render-project "$SCHEMA" "$WC_TMP/.render" >/dev/null; then
  echo "widget-coverage: could not project $SCHEMA" >&2
  exit 1
fi
if [ ! -f "$LIB" ]; then
  echo "widget-coverage: projection produced no designlib.typ" >&2
  exit 1
fi
export DESIGN_LIB_DIR="$WC_TMP/.render"

# The runtime query and the render both need the renderer. Say so plainly
# rather than reporting a confusing failure when the binary is simply absent.
if ! command -v "${TYPST:-typst}" >/dev/null 2>&1; then
  echo "widget-coverage: error: no renderer on PATH (set TYPST or enter the dev shell)" >&2
  exit 2
fi

echo "widget-coverage: schema -> projection -> gallery"

# --- 0. ask the compiled library what it provides -----------------------------
# The probe imports the projected library as a module and enumerates it. Every
# member is reported with its name and its TYPE, so a caller can tell a callable
# function from a data constant, from a document-level assertion whose value is
# content, from a vendored package the library imported.
#
# BORROWED is read from the library rather than listed here. A Typst import
# binds into the importing module's scope, so a vendored package's names appear
# in this enumeration exactly as the library's own do. The projector records
# each name as it writes the import line that binds it, which is the only place
# that knowledge exists once; a copy here would be a second declaration of one
# fact, and two declarations drift.
PROBE="$WC_TMP/probe"
mkdir -p "$PROBE"
cp -r "$WC_TMP/.render" "$PROBE/.render"
cat >"$PROBE/probe.typ" <<'TYP'
#import ".render/designlib.typ" as lib
#import ".render/designlib.typ": BORROWED

#let members = dictionary(lib)
#metadata(
  members
    .pairs()
    .filter(p => not BORROWED.contains(p.at(0)))
    .map(p => (name: p.at(0), kind: str(type(p.at(1))))),
)<surface>
TYP

SURFACE="$WC_TMP/surface.json"
if ! "${TYPST:-typst}" query --root "$PROBE" "$PROBE/probe.typ" '<surface>' \
  --field value >"$SURFACE" 2>"$WC_TMP/probe.err"; then
  # The library could not even be imported. That is not a coverage result and
  # must not be reported as one — every check below would find nothing and, on
  # a naive reading, find nothing wrong.
  echo "widget-coverage: error: could not query the projected library" >&2
  sed 's/^/  /' "$WC_TMP/probe.err" >&2 | head -8
  exit 2
fi

# WHAT EACH CHECK BELOW WILL ACTUALLY LOOK AT, counted once, up front. The
# counts are reported in the summary so a run says how much it verified rather
# than only that it found nothing wrong — a check that silently narrowed to
# nothing is the failure this suite has been bitten by, and a bare "OK" cannot
# tell that apart from a real pass.
read -r SURFACE_N KINDS_CHECKED GALLERY_CHECKED <<EOF
$(
  python3 - "$SURFACE" "$SCHEMA" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
if rows and isinstance(rows[0], list):
    rows = rows[0]
funcs = {r["name"] for r in rows if r["kind"] == "function"}
public = {n for n in funcs if not n.startswith("_")}
EXEMPT = {
    "aggregate-doc", "chapter-page", "context-owner", "declare-vocabulary",
    "assert-foundation-cardinality",
}
blocks = json.load(open(sys.argv[2]))["design_doc"]["blocks"]
kinds = [k for k in blocks if k not in {"mermaid", "vega-lite"}]
print(len(funcs), len(kinds), len(public - EXEMPT))
PY
)
EOF

# A query that returns an empty surface is a broken probe, not a clean library.
# THE ZERO CASE IS THE DANGEROUS ONE: every membership test below passes
# vacuously against an empty set, so the suite would go green having verified
# nothing at all. Refuse before the checks rather than after.
for _n in "${SURFACE_N:-}" "${KINDS_CHECKED:-}" "${GALLERY_CHECKED:-}"; do
  if [ -z "$_n" ] || [ "$_n" -lt 1 ] 2>/dev/null; then
    echo "widget-coverage: error: nothing to verify" >&2
    echo "  functions=${SURFACE_N:-?} kinds=${KINDS_CHECKED:-?}" \
      "gallery=${GALLERY_CHECKED:-?}" >&2
    echo "  a coverage check over an empty set passes vacuously; refusing" >&2
    exit 2
  fi
done
pass_line "the compiled library answers what it provides ($SURFACE_N function(s))"

# --- 1. every declared block kind is projected --------------------------------
# A fenced diagram language is routed to a carrier rather than projected as a
# directive function, so those kinds are exempt by name.
missing=$(
  python3 - "$SCHEMA" "$SURFACE" <<'PY'
import json, re, sys
schema, surface = sys.argv[1], sys.argv[2]
doc = json.load(open(schema))["design_doc"]
declared = list(doc["blocks"].keys())

rows = json.load(open(surface))
if rows and isinstance(rows[0], list):
    rows = rows[0]
# THE SURFACE IS A TYPED ANSWER, so "present" means present AS A FUNCTION. A
# name bound to a string or a dictionary is not something an author can call,
# and calling it covered would be exactly the silent pass this check exists to
# prevent.
callable_names = {r["name"] for r in rows if r["kind"] == "function"}

# fenced diagram languages reach a carrier, not a directive function
FENCE_KINDS = {"mermaid", "vega-lite"}
# A kind and the function rendering it carry ONE name
# (design_doc.function_naming), so there is nothing to translate. The single
# declared exception is `figure`, which would shadow a Typst builtin. It is
# READ from the schema rather than restated here, so this check cannot drift
# from the rule it checks.
_collisions = doc["function_naming"]["collisions"]
_pair = re.findall(r"`([a-z][a-z0-9-]*)`", _collisions)
ALIAS = {_pair[0]: _pair[1]} if len(_pair) >= 2 else {}
missing = []
checked = 0
for kind in declared:
    if kind in FENCE_KINDS:
        continue
    checked += 1
    fn = ALIAS.get(kind, kind)
    if fn not in callable_names:
        missing.append("%s (expected a callable #%s)" % (kind, fn))
# A run that checked no kind verified nothing. Report that as a failure rather
# than as an empty missing-list, which reads as a pass.
if checked == 0:
    missing.append("<no block kind was checked at all>")
print("\n".join(missing))
PY
)
if [ -z "$missing" ]; then
  pass_line "every declared block kind resolves to a callable function ($KINDS_CHECKED kind(s))"
else
  fail_line "declared but NOT callable in the projected library:"
  # ONE FINDING PER LINE. An unquoted expansion splits on every space, so a
  # finding that names what it expected arrives shredded across six lines.
  printf '%s\n' "$missing" | sed 's/^/       /'
fi

# --- 2. the gallery exercises every projected function -----------------------
# THE GALLERY IS THE RENDERER-DRIFT TRIPWIRE. A function projected for authoring
# and absent from the gallery is never exercised, so a regression in it ships
# unnoticed. The exemptions below are the functions no author ever writes.
#
# THE GALLERY HALF STAYS TEXTUAL, DELIBERATELY. The two halves of this check ask
# different questions and the right instrument differs. Check 1 asks what the
# library PROVIDES, which is a property of the compiled library and nothing else
# can answer it. This check asks whether the gallery CALLS a name, and the
# gallery is authored Typst whose call sites are visible in its text. A runtime
# instrument would answer a weaker question, not a stronger one: compiling the
# gallery proves that whatever it called worked, but a function it never called
# leaves no trace at runtime, which is precisely the absence being hunted. So
# the grep is the correct instrument here rather than an unexamined leftover.
GALLERY="fixtures/gallery.typ"
if [ -f "$GALLERY" ]; then
  uncovered=$(
    python3 - "$SURFACE" "$GALLERY" <<'PY'
import json, re, sys
surface, gallery = sys.argv[1], sys.argv[2]
rows = json.load(open(surface))
if rows and isinstance(rows[0], list):
    rows = rows[0]
used = open(gallery).read()

# THE AUTHORING SURFACE, as the compiled library reports it. A private helper
# (_x) is exercised through its callers; a vocabulary constant is data, not a
# call, and the typed answer tells the two apart without a naming convention
# having to stand in for a type.
public = {
    r["name"] for r in rows
    if r["kind"] == "function" and not r["name"].startswith("_")
}

# AGGREGATE INFRASTRUCTURE, not authoring widgets. The aggregate emits each of
# these itself, from data it read out of the layer — the document shell, a
# chapter's front page, a glossary entry's owner chip, and the vocabulary
# registry. An author never writes one, so a gallery page demonstrating them
# would demonstrate nothing a reader could copy. Their behavior is covered
# where it is real: the aggregate assertions in typst-layer.test.sh.
#
# THE LIST IS SHORT ON PURPOSE. Every name here is a function this check stops
# looking at, so an exemption granted loosely is coverage silently withdrawn.
AGGREGATE_EMITTED = {
    "aggregate-doc", "chapter-page", "context-owner", "declare-vocabulary",
    # The document-level assertions. The aggregate places each one around a
    # chapter's body — an author never writes one, and a gallery page calling
    # one would assert against the gallery rather than demonstrate anything.
    # They are covered where they are real: the foundation-contract assertions
    # in typst-layer.test.sh, which drive them through the aggregate and check
    # that each one FAILS on a layer that violates it.
    "assert-foundation-cardinality",
}

missing = []
for fn in sorted(public - AGGREGATE_EMITTED):
    # \b does not end a hyphenated name the way it ends a word: in `#stat-tile`
    # the boundary after `stat` matches, so `#stat` would look present. The
    # trailing guard is therefore "not another name character", hyphen included.
    if not re.search(r"[#(\s]" + re.escape(fn) + r"(?![a-z0-9-])", used):
        missing.append(fn)

if len(public - AGGREGATE_EMITTED) == 0:
    missing.append("<no projected function was checked at all>")
print("\n".join(missing))
PY
  )
  if [ -z "$uncovered" ]; then
    pass_line "the gallery exercises every projected function ($GALLERY_CHECKED function(s))"
  else
    fail_line "projected for authoring but NOT in the gallery:"
    printf '%s\n' "$uncovered" | sed 's/^/       /'
  fi

  # And it must RENDER. A function can be projected, present in the gallery,
  # and still fail to compile; only a render says it works. The rendered text
  # is then read back, because a page that draws nothing still exits 0.
  NG_TMP="$WC_TMP/gallery"
  mkdir -p "$NG_TMP"
  cp "$GALLERY" "$NG_TMP/gallery.typ"
  cp -r "$WC_TMP/.render" "$NG_TMP/.render"
  if "${TYPST:-typst}" compile --root "$NG_TMP" \
    "$NG_TMP/gallery.typ" "$NG_TMP/out.pdf" 2>"$WC_TMP/ng.err"; then
    pass_line "the gallery renders clean"
    if command -v pdftotext >/dev/null 2>&1; then
      ngtext="$(pdftotext "$NG_TMP/out.pdf" - 2>/dev/null)"
      ngmissing=""
      # one mark per structure that could silently render empty: the diagram's
      # own labels, a coverage reason, a stat value, a pending entry.
      for mark in designlib "called directly" LICENSE "2.4M" "Pending updates" \
        "ADR-0065"; do
        case "$ngtext" in
        *"$mark"*) ;;
        *) ngmissing="$ngmissing [$mark]" ;;
        esac
      done
      if [ -z "$ngmissing" ]; then
        pass_line "the gallery's diagram, table, and ledger reach the page"
      else
        fail_line "the gallery rendered but these marks are absent:$ngmissing"
      fi
    else
      fail_line "no pdftotext: the gallery's marks could not be asserted"
    fi
  else
    fail_line "the gallery does NOT render:"
    sed 's/^/       /' "$WC_TMP/ng.err" | head -6
  fi
else
  fail_line "no gallery at $GALLERY"
fi

# --- 4. the schema's vendored set equals the flake's --------------------------
# The projector reads the vendored package list from the SCHEMA, so a host that
# only ever receives the schema still projects the right set. That makes the
# schema the declaration and the flake the thing that actually vendors, and two
# declarations of one fact drift. This binds them, in the same spirit as checks
# 1-3 above.
#
# It replaced a worse arrangement: the projector scraped the list out of
# flake.nix, located relative to the schema. On a host the schema is
# copy-installed beside the scripts, so the lookup missed, the error was
# swallowed, and the set silently fell back to one package.
if [ -f "$ROOT/flake.nix" ]; then
  if python3 - "$ROOT" <<'PYEOF'; then
import json, re, sys
root = sys.argv[1]
schema = json.load(open(root + "/schema/design-schema.json", encoding="utf-8"))
declared = list(schema["design_doc"]["vendored_packages"]["packages"])
txt = open(root + "/flake.nix", encoding="utf-8").read()
m = re.search(r"withPackages\s*\(\s*\n?\s*ps:\s*with ps;\s*\[(.*?)\]", txt, re.S)
if not m:
    sys.stderr.write("cannot find the typst withPackages set in flake.nix\n")
    sys.exit(1)
actual = [l.split("#")[0].strip() for l in m.group(1).split("\n") if l.split("#")[0].strip()]
if declared != actual:
    sys.stderr.write("schema declares %r\nflake vendors  %r\n" % (declared, actual))
    sys.exit(1)
PYEOF
    pass_line "the schema's vendored set matches the flake's"
  else
    fail_line "the schema's vendored package set has drifted from the flake:"
    sed 's/^/       /' /tmp/wc-vendor.err 2>/dev/null | head -4
  fi
else
  # The flake is what actually vendors the package set, so its absence does not
  # make this check inapplicable — it makes the check IMPOSSIBLE, which is a
  # different thing and must not read as a pass. Without this branch the
  # assertion count fell 7 to 6 and the suite still exited 0.
  fail_line "no $ROOT/flake.nix: the vendored set could not be compared"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "widget-coverage: OK ($PASS check(s) passed;" \
    "$KINDS_CHECKED declared kind(s) resolved," \
    "$GALLERY_CHECKED projected function(s) found in the gallery)"
  exit 0
fi
echo "widget-coverage: $FAIL check(s) failed, $PASS passed"
exit 1
