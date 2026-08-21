#!/usr/bin/env bash
#
# Self-test for scripts/design-render's SOURCE-SCAN phase (schema
# scripts_contract.self_test) — the two checks that run on the generated typst
# after the fence router and before the compile.
#
# WHY THESE TESTS EXIST. Both checks close a gap where a design document
# compiled cleanly, passed the gate, and was still wrong. Neither gap was
# hypothetical:
#
#   the import scan  — a figure body carrying `#import "@preview/nulite:0.1.0"`
#                      made the renderer DOWNLOAD 669.5 KiB mid-compile. Typst
#                      has no offline flag; only a read-only Nix store stopped
#                      it, as a filesystem permission rather than a contract.
#   the prose scan   — a link whose text was a code span, ``[`afk`](dest)``,
#                      never became a #lnk call, so three pages of this layer's
#                      own committed PDFs printed the literal markdown
#                      `[afk](CONTEXT.md#term-run-mode)` with no clickable link.
#
# Scenarios, each a throwaway fixture document under mktemp:
#   (a) a clean document                          -> exit 0
#   (b) an unvendored import in a figure body     -> exit 1, names the package
#   (c) a vendored import in a figure body        -> exit 0
#   (d) a transitive import (oxifmt version-suffixed attr) -> exit 0
#   (e) a code-span link renders as a real #lnk   -> exit 0, no literal markdown
#   (f) fail-closed: a violation writes no PDF    -> exit 1, no design.pdf
#   (g) the aggregate resolves internal links     -> 11 destination shapes
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DR="${1:-$HERE/design-render}"
FRAMEWORK="$(cd "$HERE/.." && pwd)"

if [ ! -f "$DR" ]; then
  echo "error: design-render not found: $DR" >&2
  exit 2
fi
if ! command -v "${TYPST:-typst}" >/dev/null 2>&1; then
  echo "design-render.test: error: no renderer on PATH (set TYPST or enter the dev shell)" >&2
  exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The library the fixtures compile against is PROJECTED FRESH from the one
# declared schema, not read from a committed copy. This repo ships the gate and
# holds no design layer of its own, so there is no committed projection to point
# at — and projecting is the stronger test anyway: it proves the fixtures render
# against the library this schema actually produces.
LIB_SRC="$TMP/.render"
if ! bash "$HERE/render-project" "$FRAMEWORK/schema/design-schema.json" "$LIB_SRC" >/dev/null; then
  echo "error: could not project $FRAMEWORK/schema/design-schema.json" >&2
  exit 2
fi
if [ ! -f "$LIB_SRC/designlib.typ" ]; then
  echo "error: projection produced no designlib.typ" >&2
  exit 2
fi

pass=0
fail=0
pass_line() {
  printf '  ok   %s\n' "$1"
  pass=$((pass + 1))
}
fail_line() {
  printf '  FAIL %s\n' "$1"
  fail=$((fail + 1))
}

# fixture <name> <body-of-section-01> -> echoes the design.md path
fixture() {
  local name="$1" body="$2"
  local d="$TMP/$name/docs/design"
  mkdir -p "$d"
  cp -r "$LIB_SRC" "$d/.render"
  {
    echo "---"
    echo "title: Fixture"
    echo "---"
    echo
    echo "# 00 Foundation"
    echo
    echo ':::goal {title="Fixture goal"}'
    echo "A goal."
    echo ":::"
    echo
    echo ':::invariant {title="Fixture invariant" enforcement=convention}'
    echo "An invariant."
    echo ":::"
    echo
    echo ':::principle {title="Fixture principle"}'
    echo "A principle."
    echo ":::"
    echo
    echo "# 01 Body"
    echo
    printf '%s\n' "$body"
  } >"$d/design.md"
  echo "$d/design.md"
}

# run <label> <expected-exit> <md-path> [<must-contain>]
run() {
  local label="$1" want="$2" md="$3" needle="${4:-}"
  local out code
  out="$(python3 "$DR" "$md" 2>&1)"
  code=$?
  if [ "$code" != "$want" ]; then
    fail_line "$label (exit $code, expected $want)"
    printf '       %s\n' "$out" | head -4
    return
  fi
  if [ -n "$needle" ] && ! printf '%s' "$out" | grep -qF "$needle"; then
    fail_line "$label (exit $want but report lacks '$needle')"
    printf '       %s\n' "$out" | head -4
    return
  fi
  pass_line "$label"
}

echo "design-render: the source-scan phase"

# --- (a) a clean document renders ------------------------------------------
MD="$(fixture clean 'Plain prose with a [link](CONTEXT.md#term-x) and `code`.')"
run "(a) a clean document renders" 0 "$MD"

# --- (b) an unvendored import is rejected, and named -----------------------
MD="$(fixture unvendored ':::figure {caption="f" uses="cetz"}
#import "@preview/nulite:0.1.0"
#text("hi")
:::')"
run "(b) an unvendored import in a figure body is rejected" 1 "$MD" \
  "does not vendor"

# --- (c) a vendored import in a figure body passes -------------------------
MD="$(fixture vendored ':::figure {caption="f" uses="cetz"}
#import "@preview/cetz:0.4.2"
#text("hi")
:::')"
run "(c) a vendored import passes" 0 "$MD"

# --- (d) a transitive, version-suffixed attribute name passes --------------
# `oxifmt_0_2_1` is the NIX ATTRIBUTE for `@preview/oxifmt:0.2.1`. A scan
# comparing import names against the attribute list verbatim would reject this
# legitimate transitive import, so the suffix is normalized away.
MD="$(fixture transitive ':::figure {caption="f" uses="cetz"}
#import "@preview/oxifmt:0.2.1"
#text("hi")
:::')"
run "(d) a transitive version-suffixed import passes" 0 "$MD"

# --- (e) a code-span link becomes a real #lnk, not literal markdown --------
# The regression that shipped: CODE_RE ran before LINK_RE, so the link text was
# already an emitted span and LINK_RE could not match across it.
MD="$(fixture codespanlink 'Under [`afk`](CONTEXT.md#term-run-mode) the route holds.')"
run "(e) a code-span link renders" 0 "$MD"
GEN="$(dirname "$MD")/design.gen.typ"
python3 "$HERE/md-to-typst" "$MD" "$GEN" --lib ".render/designlib.typ" >/dev/null 2>&1
# A link in PROSE stays markdown all the way to cmarker — that is what lets any
# emphasis wrapping it pair correctly, which injecting a Typst call does not.
# The destination is resolved to an @label earlier, by the aggregate, on the
# markdown itself.
if grep -q 'cmarker.render(.*\[`afk`\](CONTEXT.md#term-run-mode)' "$GEN"; then
  pass_line "(e2) a code-span link reaches cmarker as markdown, intact"
else
  fail_line "(e2) the code-span link did not survive to cmarker"
  grep -n 'afk' "$GEN" | head -2
fi
if grep -q '\\#term-run-mode' "$GEN"; then
  fail_line '(e3) an escaped \#term- leaked into the generated typst'
else
  pass_line "(e3) no escaped framework call leaked into content position"
fi
rm -f "$GEN"

# --- (e4/e5) the entity scan reads content positions, not every string -----
# An HTML entity in PROSE is authored markdown: it travels to cmarker as a
# string argument, and cmarker — a CommonMark parser — decodes it, so `&amp;`
# is `&` on the page. Reporting that as a leak states the opposite of the
# truth, and it did, because the scan read the raw generated line.
MD="$(fixture entityprose 'An entity &amp; and a less-than &lt;tag&gt; here.')"
run "(e4) an HTML entity in prose is authored markdown, not a leak" 0 "$MD"

# The exemption is the cmarker ARGUMENT, not "any string literal". A diagram
# carries its DOT source as a string too, and nothing decodes that one: the
# entity prints verbatim, which is the bug the rule was written for. Widening
# the exemption to all strings makes this fixture render clean.
MD="$(fixture entitydiagram '```mermaid
flowchart LR
  a["lang/&lt;language&gt;/"] --> b
```')"
run "(e5) an HTML entity in a diagram label is still a violation" 1 "$MD"

# --- (f) fail-closed: a violation leaves no rendered PDF -------------------
MD="$(fixture failclosed ':::figure {caption="f" uses="cetz"}
#import "@preview/nulite:0.1.0"
#text("hi")
:::')"
python3 "$DR" "$MD" >/dev/null 2>&1
if [ -e "$(dirname "$MD")/design.pdf" ]; then
  fail_line "(f) fail-closed: a violating document left a rendered PDF behind"
else
  pass_line "(f) fail-closed: a violation writes no PDF"
fi
if [ -e "$(dirname "$MD")/design.gen.typ" ]; then
  fail_line "(f2) the generated typst was left behind after a violation"
else
  pass_line "(f2) the generated typst is removed on the violation path"
fi

# --- (l) a retired attribute fails loudly, not silently --------------------
# script= and id= were removed. Every block signature ends `..rest`, so an
# unnamed argument is silently ignored — a host carrying the old markup would
# render clean forever and never learn the contract dropped it. Retired names
# are named and refused.
RET="$TMP/retired"
# A PRINCIPLE, not an invariant: the foundation-order fold ranks kinds across
# the whole document, so a body invariant reports "out of order" before the
# render is reached and masks the case under test.
MD_RET="$(fixture retired ':::principle {title="Old markup" id=P9}
The value.
:::')"
ret_out="$(DESIGN_LIB_DIR="$LIB_SRC" python3 "$DR" "$MD_RET" 2>&1)" && ret_rc=0 || ret_rc=$?
if [ "$ret_rc" -eq 0 ]; then
  fail_line "(l) a retired id= attribute rendered clean"
elif printf '%s' "$ret_out" | grep -q "id= was retired"; then
  pass_line "(l) a retired id= attribute is refused by name"
else
  fail_line "(l) the run failed, but not on the retired attribute"
fi

# --- (l2) an unknown attribute fails, not just the retired ones ------------
# `lens` is OPTIONAL, so `lense=` was dropped into ..a and the block rendered
# without it — correct-looking and missing what the author wrote. The named
# parameters are the allowed set; anything else is outside the contract.
MD_UNK="$(fixture unknownattr ':::principle {title="Typo" lense=depth}
The value.
:::')"
unk_out="$(DESIGN_LIB_DIR="$LIB_SRC" python3 "$DR" "$MD_UNK" 2>&1)" && unk_rc=0 || unk_rc=$?
if [ "$unk_rc" -eq 0 ]; then
  fail_line "(l2) an unknown attribute rendered clean"
elif printf '%s' "$unk_out" | grep -q "unknown attribute lense="; then
  pass_line "(l2) an unknown attribute is refused by name"
else
  fail_line "(l2) the run failed, but not on the unknown attribute"
fi

# --- (k) a context contributes ONE chapter, not two ------------------------
# The aggregate emitted a synthetic `= title <ctx-stem>` heading to carry the
# cross-document link label. A context whose design.md has its own `# Title`
# then had TWO level-1 headings, so the outline listed every context twice — an
# empty divider chapter and the real one, on the same page. The label now rides
# a zero-width metadata anchor beside the authored H1.
CHD="$TMP/chapters"
mkdir -p "$CHD/docs/design/alpha"
cat >"$CHD/docs/design/CONTEXT.md" <<'EOF'
# CONTEXT

### Root term {#term-root}

Shared.
EOF
cat >"$CHD/docs/design/design.md" <<'EOF'
---
index_only: true
---

# Root

## 00 Foundation

:::goal {title="Index"}
Points at [alpha](alpha/design.md).
:::
EOF
cat >"$CHD/docs/design/alpha/CONTEXT.md" <<'EOF'
# CONTEXT

### Alpha thing {#term-alpha-thing}

A thing.
EOF
cat >"$CHD/docs/design/alpha/design.md" <<'EOF'
# alpha — the alpha library

## 00 Foundation

:::goal {title="G"}
An [alpha thing](CONTEXT.md#term-alpha-thing).
:::

:::invariant {title="I" enforcement=convention}
Held.
:::

:::principle {title="P" lens=depth}
Simple.
:::
EOF
ch_out="$(DESIGN_LIB_DIR="$LIB_SRC" "$HERE/design-aggregate" \
  "$CHD/docs/design" "$CHD/docs/design/design-layer.pdf" 2>&1)" && ch_rc=0 || ch_rc=$?
if [ "$ch_rc" -ne 0 ]; then
  fail_line "(k) a multi-context layer with authored H1s failed to render: $ch_out"
else
  # The bug produced NO error — it rendered a wrong document quietly — so the
  # only honest assertion reads the outline the reader sees. pdftotext comes
  # from the devShell; when it is missing the case reports skipped rather than
  # passing, because a silent pass here is exactly the failure mode under test.
  if command -v pdftotext >/dev/null 2>&1; then
    toc="$(pdftotext -f 1 -l 3 "$CHD/docs/design/design-layer.pdf" - 2>/dev/null |
      grep -cE '^[0-9]+ alpha' || true)"
    if [ "${toc:-0}" -eq 1 ]; then
      pass_line "(k) a context with its own H1 contributes exactly one chapter"
    else
      fail_line "(k) the outline lists the alpha context ${toc:-0} time(s), want 1"
    fi
  else
    printf '  SKIP (k) outline check needs pdftotext (nix develop provides it)\n'
  fi
  case "$ch_out" in
  *"labelled multiple times"*)
    fail_line "(k2) the context label collided with the heading's own label"
    ;;
  *) pass_line "(k2) the context label does not collide with the section label" ;;
  esac
fi

# --- (j) emphasis wrapping a link survives the span split ------------------
# `**[Term](dest)**` in a table cell used to strand both `**` markers in
# separate literal spans — LINK_RE had emitted the middle as opaque — so
# BOLD_RE could never pair them and Typst warned "no text within stars" twice.
# The link must still split FIRST, so the fix matches emphasis across spans
# while preserving each span's kind: rebuilding the match as one literal would
# send the converted #lnk back through the escaper.
MDT="$HERE/md-to-typst"
emphasis_case() { # <markdown> <expected-substring> <label>
  got="$(python3 -c "
import importlib.util, importlib.machinery, sys
spec = importlib.util.spec_from_loader('m',
    importlib.machinery.SourceFileLoader('m', sys.argv[1]))
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
print(mod.inline(sys.argv[2]))" "$MDT" "$1")"
  # EXACT, not a substring: `*#lnk("d")[A]*` is a substring of the buggy
  # `**#lnk("d")[A]**`, so a substring test passes against the very output it
  # exists to reject.
  if [ "$got" = "$2" ]; then
    pass_line "(j) $3"
  else
    fail_line "(j) $3 — want: $2 | got: $got"
  fi
}
emphasis_case '**[A](d)**' '*#lnk("d")[A]*' 'bold wrapping a link converts both'
emphasis_case '[**b**](d)' '#lnk("d")[*b*]' 'link wrapping bold still converts'
emphasis_case '[`afk`](d)' '#lnk("d")[`afk`]' 'link wrapping code still converts'
emphasis_case '**bold** and [link](d)' '*bold* and #lnk("d")[link]' \
  'a converted link is not re-escaped'

# --- (i) clause cardinality and order, and required block attributes -------
# The projected library structurally cannot check these: given/when/then render
# as independent _clause calls, so a clause never meets its siblings. The rules
# were declared in behavior_contract for a long time with nothing reading them.
CLD="$TMP/clauses"
mkdir -p "$CLD/docs/design"
cat >"$CLD/docs/design/CONTEXT.md" <<'EOF'
# CONTEXT

### Lift {#term-lift}

Force.
EOF
cat >"$CLD/docs/design/design.md" <<'EOF'
# X

## 00 Foundation

:::goal {title="G"}
A [lift](CONTEXT.md#term-lift).
:::

:::invariant {title="I" enforcement=convention}
Held.
:::

:::principle {title="P" lens=depth}
Simple.
:::

## 01 Behavior

::::behavior {title="Malformed"}
:::then
outcome first
:::
:::when
one
:::
:::when
two
:::
::::
EOF
cl_out="$(DESIGN_LIB_DIR="$LIB_SRC" "$HERE/design-aggregate" \
  "$CLD/docs/design" "$CLD/docs/design/design-layer.pdf" 2>&1)" && cl_rc=0 || cl_rc=$?
if [ "$cl_rc" -eq 0 ]; then
  fail_line "(i) a malformed behavior block was accepted"
else
  printf '%s' "$cl_out" | grep -q "2 when clause" &&
    pass_line "(i) two when clauses is a violation" ||
    fail_line "(i) the duplicate when clause was not reported"
  printf '%s' "$cl_out" | grep -q "clauses out of order" &&
    pass_line "(i2) a then before a when is a violation" ||
    fail_line "(i2) the clause order was not reported"
  printf '%s' "$cl_out" | grep -q "missing required attribute level=" &&
    pass_line "(i3) a behavior block with no level= is a violation" ||
    fail_line "(i3) the missing level= was not reported"
fi

# --- (h) the AGGREGATE path asserts the document-level contracts -----------
# design-render carries the document-level fold, but a host gates through the
# aggregate, which once imported this module only for `warns`. An out-of-order
# foundation then rendered clean: the contract existed and nothing ran it on
# the path that actually matters.
AGGD="$TMP/aggfold"
mkdir -p "$AGGD/docs/design"
cat >"$AGGD/docs/design/CONTEXT.md" <<'EOF'
# CONTEXT

### Lift {#term-lift}

Upward force from airflow.
EOF
cat >"$AGGD/docs/design/design.md" <<'EOF'
# Kite

## 00 Foundation

:::goal {title="It flies"}
The kite makes [lift](CONTEXT.md#term-lift).
:::

:::principle {title="Simple beats clever" lens=depth}
Fewer parts, fewer failures.
:::

:::invariant {title="The line stays taut" enforcement=convention}
Tension is maintained.
:::
EOF
agg_out="$(DESIGN_LIB_DIR="$LIB_SRC" "$HERE/design-aggregate" \
  "$AGGD/docs/design" "$AGGD/docs/design/design-layer.pdf" 2>&1)" &&
  agg_rc=0 || agg_rc=$?
if [ "$agg_rc" -eq 0 ]; then
  fail_line "(h) the aggregate accepted an out-of-order foundation"
elif printf '%s' "$agg_out" | grep -q "foundation out of order"; then
  pass_line "(h) the aggregate rejects an out-of-order foundation"
else
  fail_line "(h) the aggregate failed, but not on the order rule"
fi

# --- (g) the aggregate resolves internal links ----------------------------
# A relative markdown path is a FILE reference. Inside one rendered document it
# has no meaning, so a viewer offers to open another application and every term
# citation dead-ends. The aggregate rewrites a destination that has an internal
# target into a label reference; an ADR link stays external because the ADRs are
# not part of the document.
RESOLVE_OUT="$(
  python3 - "$HERE" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("agg", sys.argv[1] + "/design-aggregate")
spec = importlib.util.spec_from_loader("agg", loader)
agg = importlib.util.module_from_spec(spec)
loader.exec_module(agg)
known = {"term-x", "ctx-root", "ctx-lifecycle", "ctx-skill-system",
         "sec-root-00-foundation"}
cases = [
    ("CONTEXT.md#term-x", "design-layer", "term-x"),                  # own glossary
    ("../design-layer/CONTEXT.md#term-x", "lifecycle", "term-x"),     # another's
    ("../design.md", "lifecycle", "ctx-root"),                        # up to root
    ("../lifecycle/design.md", "design-layer", "ctx-lifecycle"),      # sideways
    ("#00-foundation", "root", "sec-root-00-foundation"),             # in-page
    ("../../adr/0052-x.md#adr-0052", "design-layer", None),           # stays external
    ("CONTEXT.md#term-absent", "design-layer", None),                 # no target
    # a GLOSSARY body's own shapes. A CONTEXT.md cites a sibling term with a
    # BARE anchor (the file is implied) and its own document as a bare
    # `design.md` — both were dead in the first pass, because the glossary text
    # was assembled without the rewrite the design documents got.
    ("#term-x", "skill-system", "term-x"),                            # bare anchor
    ("design.md", "skill-system", "ctx-skill-system"),                # own chapter
    ("design.md", "root", "ctx-root"),                                # root's own
    ("../../CONTEXT-MAP.md", "skill-system", None),                   # not in the doc
]
bad = 0
for dest, stem, want in cases:
    got = agg.resolve_dest(dest, stem, known)
    if got != want:
        print("  %s from %s -> %r, expected %r" % (dest, stem, got, want))
        bad += 1
print("OK" if bad == 0 else "FAIL")
PY
)"
if [ "${RESOLVE_OUT##*$'\n'}" = "OK" ] || [ "$RESOLVE_OUT" = "OK" ]; then
  pass_line "(g) the aggregate resolves internal link destinations"
else
  fail_line "(g) internal link resolution is wrong:"
  printf '%s\n' "$RESOLVE_OUT" | head -6
fi

echo
printf 'design-render: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
