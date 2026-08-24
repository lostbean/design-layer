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
#
# Zcites calls the LIBRARY — `term()` and `ctx()` — from inside a term body,
# which is how a real glossary cross-references its siblings. This is the case
# that shipped broken: `#emph` and `#strong` are Typst BUILTINS, in scope
# everywhere, so a fixture using only those proves nothing about scope. A
# CONTEXT.typ imports nothing and the aggregate supplies the scope, so placing
# a term by importing the file as a module left every library name unbound —
# and a Typst import is EAGER, so one such call failed the whole build. Every
# host layer whose terms cite each other broke while these assertions passed.
cat >"$LAYER/alpha/CONTEXT.typ" <<'EOF'
#let terms = (
  (slug: "term-zthing", title: [Zthing], body: [A Zthing is a thing.]),
  (slug: "term-zmarked", title: [Zmarked #emph[inner] tail],
   body: [Zbody with #strong[Zbold] inside.]),
  (slug: "term-zcites", title: [Zcites],
   body: [Zref to #term("term-zthing") owned by #ctx("alpha").]),
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
  *"3 term(s)"*) pass_line "the summary counts every glossary term" ;;
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

  # --- a term body may CALL THE LIBRARY, and the aggregate supplies the scope -
  # A CONTEXT.typ imports nothing. Its bodies must still resolve `term()` and
  # `ctx()`, because they are spliced where the library is already imported.
  if printf '%s' "$text" | grep -q 'Zref to'; then
    pass_line "a term body calling the library renders"
  else
    fail_line "the library-calling term body is absent — the splice lost its scope"
  fi

  # --- A CITATION RENDERS THE TERM'S TITLE, NEVER ITS SLUG ------------------
  # `term("term-zthing")` names a term titled `Zthing`, so the page must read
  # "Zref to Zthing". The slug is an identifier the author types; printing it
  # into running prose corrupts the sentence a reader reads, and NO freshness
  # check can see that, because a consistently wrong document byte-compares
  # equal to a fresh render of itself.
  #
  # The negative assertion is the load-bearing half. The assertion here used
  # to be that the slug appears — which passed green through exactly this
  # corruption across a whole corpus.
  if printf '%s' "$text" | grep -q 'Zref to Zthing'; then
    pass_line "term() renders the declared title"
  else
    fail_line "term() did not render its title"
    printf '%s' "$text" | grep -i "zref" | head -3 | sed 's/^/       got: /'
  fi
  if printf '%s' "$text" | grep -q 'term-zthing'; then
    fail_line "term() printed the raw slug into the prose"
  else
    pass_line "no raw term slug reached the page"
  fi
  if printf '%s' "$text" | grep -qE 'owned by alpha\.|by alpha'; then
    pass_line "ctx() inside a term body resolved and rendered its chip"
  else
    fail_line "ctx() did not render — the library was not in scope at the splice"
  fi
else
  fail_line "a Typst layer did not aggregate (exit $rc)"
  printf '%s\n' "$out" | head -6 | sed 's/^/       /'
  # Every assertion above sits inside the success branch, so a failed build
  # SKIPS them rather than failing them — one FAIL line would stand in for a
  # dozen unrun checks, and the count would read as though little was wrong.
  # Say plainly what did not run.
  fail_line "the glossary assertions did not run at all (the build failed first)"
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

# --- 3b. AN UNDECLARED REFERENCE STOPS THE BUILD, naming the slug -------------
# This is the referential integrity the call notation exists for, and it is
# asserted by MUTATION: break the reference, demand the failure, restore.
#
# Before the registry existed, `term()` printed whatever string it was handed.
# A citation of a term nobody declared rendered a dead identifier into the
# prose and exited 0, and renaming a term at its declaration left every use
# site stale with the whole gate green — the layer's rendered document was the
# only place the break appeared, as text no check reads.
cp "$LAYER/beta/design.typ" "$WORK/beta-design.typ.orig"
cp "$LAYER/alpha/CONTEXT.typ" "$WORK/alpha-CONTEXT.typ.orig"

ref_case() { # $1 = label, $2 = body line, $3 = expected substring
  cat >"$LAYER/beta/design.typ" <<EOF
#import "../.render/designlib.typ": *
#let title = [Zbeta context]
#let body = [
  #section(title: "00 Foundation", body: [
    #goal(title: "Zbetagoal")[Beta goal. $2]
  ])
]
EOF
  out="$(python3 ./scripts/design-aggregate "$LAYER" "$LAYER/ref.pdf" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    pass_line "$1 fails the build (exit $rc)"
  else
    fail_line "$1 built clean — a dead reference reached the rendered prose"
  fi
  case "$out" in
  *"$3"*) pass_line "$1 names the offending reference" ;;
  *)
    fail_line "$1 did not name '$3' in its message"
    printf '%s\n' "$out" | head -3 | sed 's/^/       /'
    ;;
  esac
  rm -f "$LAYER/ref.pdf"
}

ref_case "a term citation with no declaration" \
  '#term("term-znever-declared")' "term-znever-declared"
ref_case "a context citation with no directory" \
  '#ctx("znever-a-context")' "znever-a-context"

# A RENAME AT THE DECLARATION is the case that motivated the registry: the
# term still exists under a new slug, and every stale use site must fail. The
# citation is placed in a DESIGN DOCUMENT, which is where a layer's citations
# actually live and which the rename does not touch — renaming the slug inside
# CONTEXT.typ alone would also rewrite the one citation in the term body there,
# and the mutation would prove nothing.
cat >"$LAYER/beta/design.typ" <<'EOF'
#import "../.render/designlib.typ": *
#let title = [Zbeta context]
#let body = [
  #section(title: "00 Foundation", body: [
    #goal(title: "Zbetagoal")[Beta goal cites #term("term-zthing").]
  ])
]
EOF
sed 's/slug: "term-zthing"/slug: "term-zrenamed"/' "$WORK/alpha-CONTEXT.typ.orig" \
  >"$LAYER/alpha/CONTEXT.typ"
out="$(python3 ./scripts/design-aggregate "$LAYER" "$LAYER/ref.pdf" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then
  pass_line "renaming a term at its declaration fails its stale use sites"
else
  fail_line "a renamed term left stale citations and the build exited 0"
fi
rm -f "$LAYER/ref.pdf"
cp "$WORK/alpha-CONTEXT.typ.orig" "$LAYER/alpha/CONTEXT.typ"
cp "$WORK/beta-design.typ.orig" "$LAYER/beta/design.typ"

# DELETING EVERY GLOSSARY must not silently restore the unchecked behavior.
# The registry lookup falls back to printing the slug when the layer declares
# no term, because a layer written before its glossary is legal; a layer that
# CITES a term while declaring none is not, and would print raw slugs and exit
# 0 through exactly that fallback.
cat >"$LAYER/beta/design.typ" <<'EOF'
#import "../.render/designlib.typ": *
#let title = [Zbeta context]
#let body = [
  #section(title: "00 Foundation", body: [
    #goal(title: "Zbetagoal")[Beta goal cites #term("term-zthing").]
  ])
]
EOF
mv "$LAYER/alpha/CONTEXT.typ" "$WORK/alpha-CONTEXT.typ.hidden"
out="$(python3 ./scripts/design-aggregate "$LAYER" "$LAYER/ref.pdf" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then
  pass_line "citing a term while the layer declares none fails the build"
else
  fail_line "an empty glossary silently disabled every citation check"
fi
rm -f "$LAYER/ref.pdf"
mv "$WORK/alpha-CONTEXT.typ.hidden" "$LAYER/alpha/CONTEXT.typ"
cp "$WORK/beta-design.typ.orig" "$LAYER/beta/design.typ"

# The restore is asserted, so a later scenario cannot inherit a broken fixture.
if python3 ./scripts/design-aggregate "$LAYER" "$LAYER/design-layer.pdf" \
  >/dev/null 2>&1; then
  pass_line "the layer builds again once the references are restored"
else
  fail_line "the fixture did not restore — later scenarios run against a broken layer"
fi

# --- 3d. A TERM THAT STOPS PARSING IS LOUD -----------------------------------
# The glossary scan had three consecutive silent-drop paths: a title it could
# not read, a missing `body:`, and a body it could not read each dropped the
# term and carried on. The document then rendered without it and the summary
# reported the smaller count as though it were the whole vocabulary. Measured:
# renaming a slug to a non-conforming form took the count 84 to 83 with the
# gate still green.
cat >"$LAYER/beta/CONTEXT.typ" <<'EOF'
#let terms = (
  (slug: "term-zbeta", title: [Zbeta], body: [A Zbeta.]),
  (slug: "Not_A_Valid_Slug", title: [Zdropped], body: [Silently lost.]),
)
EOF
out="$(python3 ./scripts/design-aggregate "$LAYER" "$LAYER/drop.pdf" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then
  pass_line "a term the scan cannot reach fails the build"
else
  fail_line "a term was dropped from the glossary and the build exited 0"
fi
case "$out" in
*"Not_A_Valid_Slug"*) pass_line "the error names the unreachable term" ;;
*)
  fail_line "the error does not name the unreachable term"
  printf '%s\n' "$out" | head -3 | sed 's/^/       /'
  ;;
esac
rm -f "$LAYER/drop.pdf" "$LAYER/beta/CONTEXT.typ"

# --- 3c. GUIDELINES are reachable, and reachable ONLY on request -------------
# The library's guidelines were silent by default and promoted to errors under
# `--input strict=1`, which no app, no check, and no hook ever passed. All
# twelve were unreachable code that read as enforcement to anyone who grepped
# for them. DESIGN_STRICT is the door; both halves are asserted, because a
# guideline that fires in the ordinary render would block a commit over advice.
cat >"$LAYER/beta/design.typ" <<'EOF'
#import "../.render/designlib.typ": *
#let title = [Zbeta context]
#let body = [
  #section(title: "00 Foundation", body: [
    #goal(title: "Zbetagoal")[Beta goal.]
    #stat-grid()
  ])
]
EOF
if python3 ./scripts/design-aggregate "$LAYER" "$LAYER/lint.pdf" >/dev/null 2>&1; then
  pass_line "a guideline stays silent in an ordinary render"
else
  fail_line "a guideline fired in the ordinary render — advice blocked the gate"
fi
rm -f "$LAYER/lint.pdf"
out="$(DESIGN_STRICT=1 python3 ./scripts/design-aggregate "$LAYER" "$LAYER/lint.pdf" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then
  pass_line "the same guideline fires under DESIGN_STRICT"
else
  fail_line "DESIGN_STRICT did not reach the guidelines — they remain dead code"
fi
case "$out" in
*"[guideline]"*) pass_line "the strict failure is labelled a guideline" ;;
*) fail_line "the strict failure does not name itself a guideline" ;;
esac
rm -f "$LAYER/lint.pdf"
cp "$WORK/beta-design.typ.orig" "$LAYER/beta/design.typ"

# --- 4. the foundation ORDER is enforced in Typst mode ------------------------
# FOUNDATION-ORDER was projected into the library and read by nothing: the
# document-level fold that checks the order parses markdown, so against Typst
# sources it found zero blocks and passed VACUOUSLY. The vocabulary read as
# enforcement to anyone who grepped for it while no check ran.
#
# The cases below resemble a REAL layer rather than a minimal one, because the
# minimal shape hid this once already. A host's foundation blocks live in a
# `design.typ` that the aggregate places BY MODULE REFERENCE (`#<mod>.body`),
# carry named arguments and multi-line bodies, and repeat a kind several times
# before the next kind starts. A fixture with one block per kind spliced inline
# exercises none of that.
FO="$WORK/fo/docs/design"
mkdir -p "$FO/alpha"
cp -R "$LAYER/.render" "$FO/.render"

fo_layer() { # $1 = alpha's foundation body
  cat >"$FO/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Zfoot root]
#let body = [
  #section(
    title: "00 Foundation",
    body: [
      #goal(title: "Zfg")[Root goal.]
      #principle(title: "Zfp")[Root principle.]
    ],
  )
]
EOF
  cat >"$FO/alpha/design.typ" <<EOF
#import "../.render/designlib.typ": *
#let title = [Zfoot alpha]
#let body = [
  #section(
    title: "00 Foundation",
    body: [
      $1
    ],
  )
]
EOF
}

# (a) an ordered foundation renders — the check must not fire on a good layer.
# Several blocks per kind, named arguments, multi-line bodies: a real
# foundation repeats a kind before moving to the next, and the rank comparison
# must treat equal ranks as ordered rather than as an inversion.
fo_layer '#goal(title: "Zag1")[First goal.]
      #goal(title: "Zag2")[Second goal.]
      #no-goal(title: "Zan")[A no-goal.]
      #invariant(
        title: "Zai",
        enforcement: "convention",
      )[An invariant with a named argument.]
      #principle(title: "Zap", lens: "depth")[A principle with a lens.]'
if python3 ./scripts/design-aggregate "$FO" "$FO/a.pdf" >/dev/null 2>&1; then
  pass_line "an ordered Typst foundation renders"
else
  fail_line "the order check fired on a correctly ordered foundation"
fi

# (a3) A DIVERGENT layer library is refused before anything renders. The layer's
# own .render is what each context imports, so when it disagrees with the
# library this run compiles against, every context is validated by a different
# library than the document — silently, at exit 0.
DIV="$WORK/div/docs/design"
mkdir -p "$DIV/alpha"
cp -R "$FO/.render" "$DIV/.render"
cat >"$DIV/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Zdiv root]
#let body = [#section(title: "00 Foundation", body: [#goal(title: "Zdg")[g]])]
EOF
cat >"$DIV/alpha/design.typ" <<'EOF'
#import "../.render/designlib.typ": *
#let title = [Zdiv alpha]
#let body = [#section(title: "00 Foundation", body: [#goal(title: "Zda")[g]])]
EOF
printf '\n// a divergence the layer copy carries and the one in use does not\n' \
  >>"$DIV/.render/designlib.typ"
div_out="$(DESIGN_LIB_DIR="$FO/.render" python3 ./scripts/design-aggregate \
  "$DIV" "$DIV/o.pdf" 2>&1)"
div_rc=$?
if [ "$div_rc" -eq 2 ]; then
  pass_line "a divergent layer library is an error (exit 2)"
else
  fail_line "a divergent layer library exited $div_rc — contracts silently differ"
fi
if [ -f "$DIV/o.pdf" ]; then
  fail_line "a divergent layer library still wrote a document"
else
  pass_line "a divergent layer library writes no document"
fi
case "$div_out" in
*"the layer's copy"*) pass_line "the refusal names both libraries" ;;
*) fail_line "the refusal does not name the two libraries" ;;
esac

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
