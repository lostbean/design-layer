#!/usr/bin/env bash
#
# typst-layer.test.sh — a TYPST-authored layer renders as one document, and a
# MIXED layer is refused.
#
# WHY THIS TEST EXISTS. A layer may be authored as markdown (design.md) or as
# Typst (design.typ), and the mode is derived from the files present rather
# than declared by a flag, so the declaration cannot disagree with the tree.
# Two failures are possible and both are silent:
#
#   A MIXED LAYER rendered by preference. If the aggregate picked a winner —
#   the larger set, or one extension — it would emit a document missing every
#   context the losing mode held, and that document READS AS COMPLETE: the
#   table of contents is coherent, each chapter present is correct, and
#   nothing marks the absence. A half-migrated layer is exactly when this
#   arises, so the refusal is asserted, and asserted to name BOTH sides.
#
#   A DOCUMENT THAT COMPILES TO NOTHING. Asserting exit 0 would pass on a
#   blank page, so the rendered PDF is read back as text and each context's
#   own marks are asserted present.
#
# Usage: typst-layer.test.sh [repo-root]
# Exit:  0 all assertions pass, 1 an assertion failed, 2 a tool is missing.
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1

TYPST="${TYPST:-typst}"
if ! command -v "$TYPST" >/dev/null 2>&1; then
  echo "typst-layer: error: no renderer on PATH (set TYPST or enter the dev shell)" >&2
  exit 2
fi
# The mark assertion reads the PDF back. A check that cannot run must not
# report success, so a missing extractor is an error rather than a SKIP.
if ! command -v pdftotext >/dev/null 2>&1; then
  echo "typst-layer: error: no pdftotext (enter the dev shell)" >&2
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

# A layer conventionally sits at <repo>/docs/design, and the aggregate resolves
# its renderer root from that shape, so the fixture reproduces it.
LAYER="$WORK/repo/docs/design"
mkdir -p "$LAYER/alpha" "$LAYER/beta"

if ! bash ./scripts/render-project schema/design-schema.json "$LAYER/.render" >/dev/null; then
  echo "typst-layer: could not project the schema" >&2
  exit 2
fi

# Each context exports `title` and `body`. The aggregate supplies ONE page
# shell for the whole layer, so a context never calls design-doc itself.
cat >"$LAYER/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Zroot document]
#let body = [
  #section(title: "00 Foundation", lead: "The root.", body: [
    #goal(title: "Zrootgoal")[Root goal body.]
  ])
]
EOF
cat >"$LAYER/alpha/design.typ" <<'EOF'
#import "../.render/designlib.typ": *
#let title = [Zalpha context]
#let body = [
  #section(title: "00 Foundation", body: [
    #goal(title: "Zalphagoal")[Alpha goal.]
  ])
]
EOF
# A term's title is a CONTENT BLOCK here, which is how a real layer writes it.
# The fixture used a quoted string once, and that is precisely why the glossary
# shipped broken for as long as it did: a quoted title has no brackets for the
# aggregate to double-wrap, so the one term under test rendered correctly while
# every content-block title in every real layer rendered as `[Zthing]`.
#
# Zmarked carries markup INSIDE its title and body. It covers the second
# failure: a scrape bounded by the first `]` cannot see past `#emph[`, so the
# term was dropped from the glossary entirely and the count reported one fewer
# without complaint.
cat >"$LAYER/alpha/CONTEXT.typ" <<'EOF'
#let terms = (
  (slug: "term-zthing", title: [Zthing], body: [A Zthing is a thing.]),
  (slug: "term-zmarked", title: [Zmarked #emph[inner] tail],
   body: [Zbody with #strong[Zbold] inside.]),
)
EOF
cat >"$LAYER/beta/design.typ" <<'EOF'
#import "../.render/designlib.typ": *
#let title = [Zbeta context]
#let body = [
  #section(title: "00 Foundation", body: [
    #goal(title: "Zbetagoal")[Beta goal.]
  ])
]
EOF

echo "typst-layer: a Typst-authored layer renders as one document"

# --- 1. it renders, and every chapter is really on the page -------------------
out="$(python3 ./scripts/design-aggregate "$LAYER" "$LAYER/design-layer.pdf" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$LAYER/design-layer.pdf" ]; then
  pass_line "a Typst layer aggregates (exit 0)"
  text="$(pdftotext "$LAYER/design-layer.pdf" - 2>/dev/null)"
  missing=""
  # one mark per chapter, one per goal, and the glossary term: a chapter that
  # silently failed to place its body would drop its goal but keep its title.
  for mark in Zroot Zalpha Zbeta Zrootgoal Zalphagoal Zbetagoal Zthing; do
    case "$text" in
    *"$mark"*) ;;
    *) missing="$missing $mark" ;;
    esac
  done
  if [ -z "$missing" ]; then
    pass_line "every chapter, goal, and glossary term reaches the page"
  else
    fail_line "the document rendered but these marks are absent:$missing"
  fi
  case "$out" in
  *"3 context(s)"*) pass_line "the summary counts all three contexts" ;;
  *) fail_line "the summary miscounts the contexts: $out" ;;
  esac
  case "$out" in
  *"2 term(s)"*) pass_line "the summary counts both glossary terms" ;;
  *) fail_line "the summary miscounts the terms: $out" ;;
  esac

  # --- the glossary renders its terms, not their SOURCE TEXT ----------------
  # Asserting the mark is present is not enough, and that is the whole lesson
  # of this bug: `[Zthing]` contains `Zthing`, so the mark loop above passed
  # green through every broken render. These assertions read the exact
  # characters on the page and REFUSE the bracketed form.
  if printf '%s' "$text" | grep -q '\[Zthing\]'; then
    fail_line "the term heading renders as [Zthing] — its source brackets reached the page"
  else
    pass_line "the term heading carries no literal source brackets"
  fi
  if printf '%s' "$text" | grep -qE '^[0-9.]+ +Zthing *$'; then
    pass_line "the term heading renders as Zthing"
  else
    fail_line "no numbered heading reads exactly 'Zthing'"
    printf '%s' "$text" | grep -i "zthing" | head -3 | sed 's/^/       got: /'
  fi
  if printf '%s' "$text" | grep -q '\[A Zthing is a thing\.\]'; then
    fail_line "the term body renders wrapped in literal brackets"
  else
    pass_line "the term body carries no literal source brackets"
  fi

  # --- a title holding markup survives, in the heading AND in the count -----
  if printf '%s' "$text" | grep -q 'Zmarked inner tail'; then
    pass_line "a term title holding markup renders its text"
  else
    fail_line "the markup-bearing term title is absent or mangled"
    printf '%s' "$text" | grep -i "zmarked" | head -3 | sed 's/^/       got: /'
  fi
  if printf '%s' "$text" | grep -q 'Zbody with Zbold inside'; then
    pass_line "a term body holding markup renders its text"
  else
    fail_line "the markup-bearing term body is absent or mangled"
  fi
  if printf '%s' "$text" | grep -qE '#emph|#strong'; then
    fail_line "a Typst call reached the page as literal text"
  else
    pass_line "no Typst call leaked onto the page"
  fi
else
  fail_line "a Typst layer did not aggregate (exit $rc)"
  printf '%s\n' "$out" | head -6 | sed 's/^/       /'
fi

# --- 2. the freshness check verifies rather than repairs ----------------------
if python3 ./scripts/design-aggregate "$LAYER" "$LAYER/design-layer.pdf" --check >/dev/null 2>&1; then
  pass_line "a freshly built Typst layer is reported fresh"
else
  fail_line "a freshly built Typst layer was reported stale"
fi

# --- 3. a MIXED layer is refused, naming both sides ---------------------------
echo "# a stray markdown context" >"$LAYER/beta/design.md"
out="$(python3 ./scripts/design-aggregate "$LAYER" "$LAYER/mixed.pdf" 2>&1)"
rc=$?
if [ "$rc" -eq 2 ]; then
  pass_line "a mixed layer is an error (exit 2)"
else
  fail_line "a mixed layer exited $rc, wanted 2 — a half-migrated layer rendered"
fi
if [ -f "$LAYER/mixed.pdf" ]; then
  fail_line "a mixed layer wrote a PDF — it must emit nothing"
  rm -f "$LAYER/mixed.pdf"
else
  pass_line "a mixed layer writes no document"
fi
case "$out" in
*"beta/design.md"*) pass_line "the error names the markdown file" ;;
*) fail_line "the error does not name the offending markdown file" ;;
esac
case "$out" in
*"alpha/design.typ"*) pass_line "the error names the Typst files" ;;
*) fail_line "the error does not name the Typst files" ;;
esac
rm -f "$LAYER/beta/design.md"

# --- 4. the foundation ORDER is enforced in Typst mode ------------------------
# FOUNDATION-ORDER was projected into the library and read by nothing: the
# document-level fold that checks the order parses markdown, so against Typst
# sources it found zero blocks and passed VACUOUSLY. The vocabulary read as
# enforcement to anyone who grepped for it while no check ran.
#
# Three cases, because one alone would not distinguish a working check from a
# check that fires on everything or on nothing.
FO="$WORK/fo/docs/design"
mkdir -p "$FO/alpha"
cp -R "$LAYER/.render" "$FO/.render"

fo_layer() { # $1 = alpha's foundation body
  cat >"$FO/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Zfoot root]
#let body = [
  #section(title: "00 Foundation", body: [
    #goal(title: "Zfg")[Root goal.]
    #principle(title: "Zfp")[Root principle.]
  ])
]
EOF
  cat >"$FO/alpha/design.typ" <<EOF
#import "../.render/designlib.typ": *
#let title = [Zfoot alpha]
#let body = [
  #section(title: "00 Foundation", body: [
    $1
  ])
]
EOF
}

# (a) an ordered foundation renders — the check must not fire on a good layer.
fo_layer '#goal(title: "Zag")[g] #invariant(title: "Zai")[i]'
if python3 ./scripts/design-aggregate "$FO" "$FO/a.pdf" >/dev/null 2>&1; then
  pass_line "an ordered Typst foundation renders"
else
  fail_line "the order check fired on a correctly ordered foundation"
fi

# (b) a misordered foundation is REFUSED, and the message names both kinds.
fo_layer '#principle(title: "Zap")[p] #goal(title: "Zag")[g]'
fo_out="$(python3 ./scripts/design-aggregate "$FO" "$FO/b.pdf" 2>&1)"
fo_rc=$?
if [ "$fo_rc" -ne 0 ]; then
  pass_line "a misordered Typst foundation is refused (exit $fo_rc)"
else
  fail_line "a misordered Typst foundation rendered — the order is unenforced"
fi
case "$fo_out" in
*"out of order"*) pass_line "the refusal says the foundation is out of order" ;;
*) fail_line "the refusal does not name the rule: $(printf '%s' "$fo_out" | head -1)" ;;
esac
if printf '%s' "$fo_out" | grep -q 'goal' && printf '%s' "$fo_out" | grep -q 'principle'; then
  pass_line "the refusal names the offending pair"
else
  fail_line "the refusal does not name which block followed which"
fi
if [ -f "$FO/b.pdf" ]; then
  fail_line "a misordered foundation still wrote a PDF"
  rm -f "$FO/b.pdf"
else
  pass_line "a misordered foundation writes no document"
fi

# (c) the scope is ONE CONTEXT. The root ends on a principle and alpha opens on
# a goal, which is legal — every context carries its own foundation. A check
# folding over the whole aggregate would call this an inversion and fail every
# multi-context layer that exists.
fo_layer '#goal(title: "Zag")[g]'
if python3 ./scripts/design-aggregate "$FO" "$FO/c.pdf" >/dev/null 2>&1; then
  pass_line "the order is scoped per context, not across the aggregate"
else
  fail_line "a goal opening the next context read as following the previous principle"
fi

# --- 5. an empty layer is an error, not an empty document ---------------------
EMPTY="$WORK/empty/docs/design"
mkdir -p "$EMPTY"
if python3 ./scripts/design-aggregate "$EMPTY" "$EMPTY/out.pdf" >/dev/null 2>&1; then
  fail_line "a layer with no documents rendered instead of failing"
else
  pass_line "a layer with no design document is an error"
fi

echo
echo "typst-layer: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
