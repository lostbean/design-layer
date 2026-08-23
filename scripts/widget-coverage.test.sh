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
# It checks three things:
#   1. every block kind the SCHEMA declares has a function in the PROJECTION
#      (or is deliberately exempt — a fenced diagram language, not a call)
#   2. the GALLERY calls every function projected for authoring
#   3. the gallery RENDERS, and its marks reach the page — a function can be
#      declared, projected, present in the gallery, and still fail to compile,
#      and a page that draws nothing still exits 0
#
# Usage: widget-coverage.test.sh [repo-root]
# Exit: 0 all pass, 1 a check failed.
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

# The render check needs the renderer. Say so plainly rather than reporting a
# confusing render failure when the binary is simply absent.
if ! command -v "${TYPST:-typst}" >/dev/null 2>&1; then
  echo "widget-coverage: error: no renderer on PATH (set TYPST or enter the dev shell)" >&2
  exit 2
fi

echo "widget-coverage: schema -> projection -> gallery"

# --- 1. every declared block kind is projected --------------------------------
# A fenced diagram language is routed to a carrier rather than projected as a
# directive function, so those kinds are exempt by name.
missing=$(
  python3 - "$SCHEMA" "$LIB" <<'PY'
import json, re, sys
schema, lib = sys.argv[1], sys.argv[2]
doc = json.load(open(schema))["design_doc"]
declared = list(doc["blocks"].keys())
src = open(lib).read()
have = set(re.findall(r"^#let ([a-z][a-z0-9-]*)\(", src, re.M))
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
for kind in declared:
    if kind in FENCE_KINDS:
        continue
    fn = ALIAS.get(kind, kind)
    if fn not in have:
        missing.append("%s (expected #%s)" % (kind, fn))
print("\n".join(missing))
PY
)
if [ -z "$missing" ]; then
  pass_line "every declared block kind has a projected function"
else
  fail_line "declared but NOT projected:"
  printf '       %s\n' $missing
fi

# --- 2. the gallery exercises every projected function -----------------------
# THE GALLERY IS THE RENDERER-DRIFT TRIPWIRE. A function projected for authoring
# and absent from the gallery is never exercised, so a regression in it ships
# unnoticed. The exemptions below are the functions no author ever writes.
GALLERY="fixtures/gallery.typ"
if [ -f "$GALLERY" ]; then
  uncovered=$(
    python3 - "$LIB" "$GALLERY" <<'PY'
import re, sys
lib, gallery = sys.argv[1], sys.argv[2]
src = open(lib).read()
used = open(gallery).read()

# The functions that make up the authoring surface. A private helper (_x) is
# exercised through its callers; a vocabulary constant is data, not a call.
public = set(re.findall(r"^#let ([a-z][a-z0-9-]*)\(", src, re.M))
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
print("\n".join(missing))
PY
  )
  if [ -z "$uncovered" ]; then
    pass_line "the gallery exercises every projected function"
  else
    fail_line "projected for authoring but NOT in the gallery:"
    printf '       %s\n' $uncovered
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
  echo "widget-coverage: OK ($PASS check(s) passed)"
  exit 0
fi
echo "widget-coverage: $FAIL check(s) failed, $PASS passed"
exit 1
