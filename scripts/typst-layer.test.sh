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
    #invariant(title: "Zrootinv", enforcement: "mechanism")[Root invariant.]
    #principle(title: "Zrootprin")[Root principle.]
    #subsection(title: "Zroot detail")[Root detail.]
  ])
  #section(title: "Zroot section 2", body: [Two.])
  #section(title: "Zroot section 3", body: [Three.])
  #section(title: "Zroot section 4", body: [Four.])
  #section(title: "Zroot section 5", body: [Five.])
  #section(title: "Zroot section 6", body: [Six.])
  #section(title: "Zroot section 7", body: [Seven.])
  #section(title: "Zroot section 8", body: [Eight.])
  #section(title: "Zroot section 9", body: [Nine.])
  #section(title: "Zroot section 10", body: [
    #subsection(title: "Zroot tenth detail")[Tenth detail.]
  ])
]
EOF
cat >"$LAYER/alpha/design.typ" <<'EOF'
#import "../.render/designlib.typ": *
#let title = [Zalpha context]
#let body = [
  #section(title: "00 Foundation", body: [
    #goal(title: "Zalphagoal")[Alpha goal.]
    #invariant(title: "Zalphainv", enforcement: "convention")[Alpha invariant.]
    #principle(title: "Zalphaprin")[Alpha principle.]
    #subsection(title: "Zalpha detail")[Alpha detail.]
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
    #invariant(title: "Zbetainv", enforcement: "partial")[Beta invariant.]
    #principle(title: "Zbetaprin")[Beta principle.]
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

  # --- chapters own the displayed section number --------------------------
  # Chapter headings are level one. Authored sections and subsections render
  # beneath them, so the same content-only source naturally reads 1.1,
  # 1.1.1, 1.10.1, then 2.1 and 2.1.1 in the next context.
  for numbered in \
    '1 Zroot document' \
    '1.1 00 Foundation' \
    '1.1.1 Zroot detail' \
    '1.10.1 Zroot tenth detail' \
    '2 Zalpha context' \
    '2.1 00 Foundation' \
    '2.1.1 Zalpha detail'; do
    if printf '%s\n' "$text" | grep -qE "${numbered//./\\.}"; then
      pass_line "chapter-local number reaches $numbered"
    else
      fail_line "chapter-local number is missing: $numbered"
    fi
  done
  if printf '%s\n' "$text" | grep -qE '^[0-9.]+ +Glossary *$'; then
    fail_line "the glossary is numbered as a design chapter"
  else
    pass_line "the glossary is an unnumbered reference chapter"
  fi

  # The TOC is page two in this fixture. Read that page alone so the assertion
  # proves navigation depth rather than matching the chapter body later on.
  toc_text="$(pdftotext -layout -f 2 -l 2 "$LAYER/design-layer.pdf" - 2>/dev/null)"
  if printf '%s\n' "$toc_text" | grep -q 'Zroot document' &&
    printf '%s\n' "$toc_text" | grep -q 'Zroot detail'; then
    pass_line "the table of contents includes chapters through subsections"
  else
    fail_line "the table of contents omits a chapter or subsection"
  fi
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
  if printf '%s' "$text" | grep -qE '^Zthing *$'; then
    pass_line "the unnumbered term heading renders as Zthing"
  else
    fail_line "no unnumbered heading reads exactly 'Zthing'"
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

# --- 3. A LEGACY MARKDOWN LAYER IS REFUSED, naming what to migrate ------------
# Markdown authoring was removed. A layer still carrying a design.md is refused
# by name rather than walked past: ignoring it would render a document silently
# missing that context, which reads as complete. The refusal must name the file
# and point at the migration, because "no design layer" against a directory
# full of design documents sends the reader after the wrong fault.
echo "# a stray markdown context" >"$LAYER/beta/design.md"
out="$(python3 ./scripts/design-aggregate "$LAYER" "$LAYER/mixed.pdf" 2>&1)"
rc=$?
if [ "$rc" -eq 2 ]; then
  pass_line "a layer holding design.md is an error (exit 2)"
else
  fail_line "a legacy markdown layer exited $rc, wanted 2 — it rendered anyway"
fi
if [ -f "$LAYER/mixed.pdf" ]; then
  fail_line "a legacy markdown layer wrote a PDF — it must emit nothing"
  rm -f "$LAYER/mixed.pdf"
else
  pass_line "a legacy markdown layer writes no document"
fi
case "$out" in
*"beta/design.md"*) pass_line "the error names the markdown file" ;;
*) fail_line "the error does not name the offending markdown file" ;;
esac
case "$out" in
*"migration 0008"*) pass_line "the refusal points at the migration" ;;
*) fail_line "the refusal does not say where to go next" ;;
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

# --- 3c. GUIDELINES ALWAYS PRINT, and never block ----------------------------
# The guidelines used to be SILENT unless DESIGN_STRICT was set, which made them
# invisible in practice: a rule nobody reads is the same defect as a check that
# passes over nothing. They now print on every render and change no exit code,
# with DESIGN_STRICT kept as the opt-in escalation to failure. All three halves
# are asserted — printed, non-blocking, and still escalatable.
cat >"$LAYER/beta/design.typ" <<'EOF'
#import "../.render/designlib.typ": *
#let title = [Zbeta context]
#let body = [
  #section(title: "00 Foundation", body: [
    #goal(title: "Zbetagoal")[Beta goal.]
    #invariant(title: "Zbetainv2", enforcement: "partial")[Beta invariant.]
    #principle(title: "Zbetaprin2")[Beta principle.]
    #stat-grid()
  ])
]
EOF
lint_out="$(python3 ./scripts/design-aggregate "$LAYER" "$LAYER/lint.pdf" 2>&1)"
lint_rc=$?
if [ "$lint_rc" -eq 0 ]; then
  pass_line "a guideline does not block an ordinary render"
else
  fail_line "a guideline fired as a failure in the ordinary render (exit $lint_rc)"
fi
# THE LOAD-BEARING HALF. Without this the change is merely a deleted check.
case "$lint_out" in
*"guideline: stat-grid.empty"*)
  pass_line "the guideline PRINTS in the ordinary render, naming its rule"
  ;;
*)
  fail_line "the guideline did not print — it is invisible, the old defect"
  ;;
esac
case "$lint_out" in
*"guideline(s):"*) pass_line "the render reports a guideline count summary" ;;
*) fail_line "no count summary — a reader cannot tell how many fired" ;;
esac
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
      #invariant(title: "Zfi", enforcement: "convention")[Root invariant.]
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

# (b) a misordered foundation is GUIDED, not refused. The order is a structural
# opinion: a design legitimately changes shape, and the library says what it
# expected rather than refusing to render. All four halves are asserted —
# the render succeeds, the guidance is PRINTED, it names the offending pair, and
# the strict ratchet still escalates it — because dropping any one of them would
# leave a deleted check looking like a converted one.
fo_layer '#principle(title: "Zap")[p] #goal(title: "Zag")[g]'
fo_out="$(python3 ./scripts/design-aggregate "$FO" "$FO/b.pdf" 2>&1)"
fo_rc=$?
if [ "$fo_rc" -eq 0 ]; then
  pass_line "a misordered Typst foundation renders (exit 0)"
else
  fail_line "a misordered foundation was refused (exit $fo_rc) — structure now guides"
fi
case "$fo_out" in
*"guideline: foundation.order"*)
  pass_line "the guidance names the foundation.order rule"
  ;;
*)
  fail_line "the guidance does not name the rule: $(printf '%s' "$fo_out" | head -1)"
  ;;
esac
case "$fo_out" in
*"out of order"*) pass_line "the guidance says the foundation is out of order" ;;
*) fail_line "the guidance does not say what is wrong" ;;
esac
if printf '%s' "$fo_out" | grep -q 'goal' && printf '%s' "$fo_out" | grep -q 'principle'; then
  pass_line "the guidance names the offending pair"
else
  fail_line "the guidance does not name which block followed which"
fi
case "$fo_out" in
*"the declared order is"*)
  pass_line "the guidance says what order was expected"
  ;;
*) fail_line "the guidance does not say what was expected — advice with no remedy" ;;
esac
# This fixture carries a principle before a goal AND no invariant, so it trips
# the order rule and the cardinality rule — the summary counts both under the
# `foundation` area.
case "$fo_out" in
*"2 guideline(s): 2 foundation"*)
  pass_line "the count summary counts both foundation guidelines"
  ;;
*)
  fail_line "the count summary does not report them: $(printf '%s' "$fo_out" | grep 'guideline(s)' | head -1)"
  ;;
esac
if [ -f "$FO/b.pdf" ]; then
  pass_line "a misordered foundation still renders its document"
  rm -f "$FO/b.pdf"
else
  fail_line "a misordered foundation wrote no PDF — the render was blocked"
fi
# the strict ratchet still turns it into a failure, for a CI that wants one
if DESIGN_STRICT=1 python3 ./scripts/design-aggregate "$FO" "$FO/bs.pdf" \
  >/dev/null 2>&1; then
  fail_line "DESIGN_STRICT did not escalate the foundation order guideline"
else
  pass_line "DESIGN_STRICT escalates the foundation order guideline to a failure"
fi
rm -f "$FO/bs.pdf"

# (c) the scope is ONE CONTEXT. The root ends on a principle and alpha opens on
# a goal, which is legal — every context carries its own foundation. A check
# folding over the whole aggregate would call this an inversion and fail every
# multi-context layer that exists.
fo_layer '#goal(title: "Zag")[g]
      #invariant(title: "Zai2", enforcement: "convention")[i]
      #principle(title: "Zap2")[p]'
if python3 ./scripts/design-aggregate "$FO" "$FO/c.pdf" >/dev/null 2>&1; then
  pass_line "the order is scoped per context, not across the aggregate"
else
  fail_line "a goal opening the next context read as following the previous principle"
fi

# --- 4b. THE FOUNDATION'S PER-KIND MINIMUM ------------------------------------
# The cardinality rule — at least one of each required kind — is the one
# document-level contract that must notice a block NOBODY WROTE. A function
# cannot report its own absence, so this reads the same trail the order check
# uses: a kind missing from the finished trail was never called.
#
# It is asserted here rather than in the gallery because the assertion is
# emitted by the AGGREGATE around each chapter, not written by an author. All
# four directions are covered, because a check that only ever passes and a
# check that only ever fails are equally useless.

# (d) a foundation missing a required kind is GUIDED, not refused. This is the
# case the flexibility ruling was decided on: a layer may legitimately not carry
# one of the levels, and failing the whole design over it is the behavior being
# reversed. The guidance still has to name the missing kind and what was
# expected, or it is noise.
fo_layer '#goal(title: "Zdg")[g]
      #invariant(title: "Zdi", enforcement: "convention")[i]'
fc_out="$(python3 ./scripts/design-aggregate "$FO" "$FO/d.pdf" 2>&1)"
fc_rc=$?
if [ "$fc_rc" -eq 0 ]; then
  pass_line "a foundation missing a required kind renders (exit 0)"
else
  fail_line "a short foundation was refused (exit $fc_rc) — the minimum should guide"
fi
case "$fc_out" in
*"guideline: foundation.cardinality"*)
  pass_line "the guidance names the foundation.cardinality rule"
  ;;
*) fail_line "the guidance does not name the cardinality rule" ;;
esac
case "$fc_out" in
*"declares no principle"*) pass_line "the guidance names the missing kind" ;;
*) fail_line "the guidance does not say which kind is missing" ;;
esac
case "$fc_out" in
*"expects at least one of each"*)
  pass_line "the guidance says what the cardinality rule expected"
  ;;
*) fail_line "the guidance does not say what was expected" ;;
esac
if [ -f "$FO/d.pdf" ]; then
  pass_line "a short foundation still renders its document"
  rm -f "$FO/d.pdf"
else
  fail_line "a short foundation wrote no PDF — the render was blocked"
fi
if DESIGN_STRICT=1 python3 ./scripts/design-aggregate "$FO" "$FO/ds.pdf" \
  >/dev/null 2>&1; then
  fail_line "DESIGN_STRICT did not escalate the cardinality guideline"
else
  pass_line "DESIGN_STRICT escalates the cardinality guideline to a failure"
fi
rm -f "$FO/ds.pdf"

# (e) the minimum is still scoped PER CONTEXT. The scoping is what makes the
# guidance accurate rather than merely absent: without the per-context reset a
# context carrying no foundation of its own would inherit the previous chapter's
# statements and the guidance would never fire. Alpha carries only a goal here,
# so a correctly scoped check reports the two kinds it lacks.
fo_layer '#goal(title: "Zeg")[g]'
fe_out="$(python3 ./scripts/design-aggregate "$FO" "$FO/e.pdf" 2>&1)"
if printf '%s' "$fe_out" | grep -q 'declares no invariant' &&
  printf '%s' "$fe_out" | grep -q 'declares no principle'; then
  pass_line "the minimum is scoped per context, not across the aggregate"
else
  fail_line "a partial foundation inherited the root's statements — no guidance fired"
fi
rm -f "$FO/e.pdf"

# (f) a document carrying NO foundation at all is not a document that failed
# the minimum — it is a document not carrying one. A reference page or a
# behavior-rule sheet is legal, and reporting it would fail correct documents.
fo_layer '#notes(title: "Zfn")[Prose only, no foundation statements here.]'
if python3 ./scripts/design-aggregate "$FO" "$FO/f.pdf" >/dev/null 2>&1; then
  pass_line "a document declaring no foundation is not held to the minimum"
else
  fail_line "a document with no foundation was reported as missing kinds"
fi
rm -f "$FO/f.pdf"

# (g) index_only WAIVES the minimum for a root that merely indexes its
# contexts. Such a root points down to each context rather than restating a
# goal a context already owns, so holding it to the full minimum would force
# the restatement the layer exists to prevent.
cat >"$FO/design.typ" <<'XEOF'
#import ".render/designlib.typ": *
#let title = [Zfoot root]
#let index_only = true
#let body = [
  #section(title: "00 Foundation", body: [
    #goal(title: "Zig")[The only cross-context goal.]
  ])
]
XEOF
if python3 ./scripts/design-aggregate "$FO" "$FO/g.pdf" >/dev/null 2>&1; then
  pass_line "index_only waives the per-kind minimum"
else
  fail_line "index_only did not waive the minimum — an index root cannot render"
fi
rm -f "$FO/g.pdf"

# --- 4c. THE BEHAVIOR CLAUSE CONTRACT -----------------------------------------
# given/when/then render as INDEPENDENT calls, so a clause never meets its
# siblings and cannot know it is the second `when`. The cardinality and order
# were declared in the schema and enforced by nothing; a clause trail closes it
# the same way the foundation trail does. Scope is ONE block — two sibling
# rules are two rules — so the accepting cases below matter as much as the
# refusing ones.
bc_layer() { # $1 = the behavior block's body
  cat >"$FO/design.typ" <<'XEOF'
#import ".render/designlib.typ": *
#let title = [Zbc root]
#let body = [
  #section(title: "00 Foundation", body: [
    #goal(title: "Zbcg")[g]
    #invariant(title: "Zbci", enforcement: "convention")[i]
    #principle(title: "Zbcp")[p]
  ])
]
XEOF
  cat >"$FO/alpha/design.typ" <<EOF
#import "../.render/designlib.typ": *
#let title = [Zbc alpha]
#let body = [
  #section(title: "01 Rules", body: [
    $1
  ])
]
EOF
}
# A clause-shape violation GUIDES rather than refuses. Both halves are asserted
# on every case: the document still renders, AND the guidance prints naming the
# rule and what was expected. Asserting only the first half would let a deleted
# check pass as a converted one.
bc_guides() { # $1 = label, $2 = body, $3 = expected message fragment
  bc_layer "$2"
  bc_out="$(python3 ./scripts/design-aggregate "$FO" "$FO/bc.pdf" 2>&1)"
  bc_rc=$?
  if [ "$bc_rc" -ne 0 ]; then
    fail_line "$1 — the render was refused (exit $bc_rc) instead of guided"
  elif [ ! -f "$FO/bc.pdf" ]; then
    fail_line "$1 — no document was written"
  elif ! printf '%s' "$bc_out" | grep -q 'guideline: behavior\.'; then
    fail_line "$1 — no behavior guidance printed; the check was deleted, not converted"
  elif printf '%s' "$bc_out" | grep -q "$3"; then
    pass_line "$1"
  else
    fail_line "$1 — the guidance does not say what was expected"
  fi
  rm -f "$FO/bc.pdf"
  # the strict ratchet still escalates the same case to a failure
  if DESIGN_STRICT=1 python3 ./scripts/design-aggregate "$FO" "$FO/bcs.pdf" \
    >/dev/null 2>&1; then
    fail_line "$1 — DESIGN_STRICT did not escalate it"
  else
    pass_line "$1 — DESIGN_STRICT escalates it"
  fi
  rm -f "$FO/bcs.pdf"
}
bc_accepts() { # $1 = label, $2 = body
  bc_layer "$2"
  if python3 ./scripts/design-aggregate "$FO" "$FO/bc.pdf" >/dev/null 2>&1; then
    pass_line "$1"
  else
    fail_line "$1 — a legal behavior rule was refused"
  fi
  rm -f "$FO/bc.pdf"
}

bc_guides "two when clauses are two rules" \
  '#behavior(title: "Zb1", area: "Test area", level: "interface")[#when[a] #when[b] #then[c]]' \
  'expected exactly 1'
bc_guides "a rule with no when clause is guided" \
  '#behavior(title: "Zb2", area: "Test area", level: "interface")[#then[c]]' \
  'expected exactly 1'
bc_guides "a rule with no then clause states no outcome" \
  '#behavior(title: "Zb3", area: "Test area", level: "interface")[#when[a]]' \
  'no then clause'
bc_guides "a then before a when is out of order" \
  '#behavior(title: "Zb4", area: "Test area", level: "interface")[#then[c] #when[a]]' \
  'out of order'

bc_accepts "when + then is the minimal legal rule" \
  '#behavior(title: "Zb5", area: "Test area", level: "interface")[#when[a] #then[c]]'
bc_accepts "repeated given and then clauses stay legal" \
  '#behavior(title: "Zb6", area: "Test area", level: "interface")[#given[g1] #given[g2] #when[a] #then[c1] #then[c2]]'
# THE SCOPING CASE. Without the per-block reset the second rule's `when` would
# read as a second `when` in the first rule, and every layer carrying two
# behavior rules would fail.
bc_accepts "two sibling rules each carry their own when" \
  '#behavior(title: "Zb7", area: "Test area", level: "interface")[#when[a] #then[c]]
    #behavior(title: "Zb8", area: "Test area", level: "interface")[#when[b] #then[d]]'

# --- 4d. RENDERER-OWNED SECTION NUMBERING ------------------------------------
# The author supplies content-only titles. Typst's heading counter derives
# displayed sequence from document order, so no source title carries a number.
sp_layer() { # $1 = alpha's section sequence
  cat >"$FO/design.typ" <<'XEOF'
#import ".render/designlib.typ": *
#let title = [Zsp root]
#let body = [
  #section(title: "00 Foundation", body: [
    #goal(title: "Zspg")[g]
    #invariant(title: "Zspi", enforcement: "convention")[i]
    #principle(title: "Zspp")[p]
  ])
]
XEOF
  cat >"$FO/alpha/design.typ" <<EOF
#import "../.render/designlib.typ": *
#let title = [Zsp alpha]
#let body = [
$1
]
EOF
}

sp_layer '#section(title: "Foundation", body: [
    #goal(title: "Zsag")[g]
    #invariant(title: "Zsai", enforcement: "convention")[i]
    #principle(title: "Zsap")[p]
  ])
  #section(title: "At a glance", body: [x])
  #section(title: "The parts", body: [y])'
if python3 ./scripts/design-aggregate "$FO" "$FO/sp.pdf" >/dev/null 2>&1; then
  pass_line "content-only section titles render"
else
  fail_line "content-only section titles did not render"
fi
rm -f "$FO/sp.pdf"

# --- 4e. THE ADR CITATION ------------------------------------------------------
# `#adr(N)` is the one citation whose target lives OUTSIDE the rendered
# document: the ADRs are markdown files, so there is nothing to jump to inside
# the render and nothing for the compiler to resolve. The number is therefore
# the whole citation, and the gate is what checks it — layer-integrity reads
# every call and refuses a number the ADR directory has no file for.
#
# This is asserted because the call was DOCUMENTED and NOT PROJECTED: the
# integrity check read `#adr(N)`, the gallery's prose described it, and the
# library defined no such function, so the one citation form the gate checked
# was a form nobody could write.
bc_layer '#behavior(title: "Zadr", area: "Test area", level: "interface")[#when[a] #then[b]]
    The decision is #adr(7).'
if python3 ./scripts/design-aggregate "$FO" "$FO/adr.pdf" >/dev/null 2>&1; then
  pass_line "an adr() citation compiles"
  if pdftotext "$FO/adr.pdf" - 2>/dev/null | grep -q "ADR-0007"; then
    pass_line "an adr() citation renders its padded id"
  else
    fail_line "adr() compiled but printed nothing a reader can see"
  fi
else
  fail_line "adr() does not compile — the gate checks a form nobody can write"
fi
rm -f "$FO/adr.pdf"

# --- 4e. REFERENTIAL INTEGRITY IS STILL FAIL-CLOSED ---------------------------
# The severity policy relaxed every STRUCTURAL rule to guidance. It relaxed
# nothing about REFERENCES, and that boundary is the thing most at risk of being
# eroded by a later pass that reads "warnings not gates" as a blanket rule.
#
# A broken reference is not a design opinion: a citation resolving to nothing has
# no text to render, and an edge naming no node draws a line to nowhere. Each
# would produce a corrupt document that still exits 0. So each is asserted to
# STILL exit non-zero, one case per reference kind.
ri_refuses() { # $1 = label, $2 = alpha body, $3 = expected message fragment
  # The layer declares a real term and a real context, so a dangling citation
  # is judged by the RESOLVER rather than by the empty-registry guard — which
  # is a different rule and would mask the one under test.
  cat >"$FO/alpha/CONTEXT.typ" <<'XEOF'
#let terms = (
  (slug: "term-zri", title: [Zri], body: [A declared term.]),
)
XEOF
  cat >"$FO/design.typ" <<'XEOF'
#import ".render/designlib.typ": *
#let title = [Zri root]
#let body = [
  #section(title: "00 Foundation", body: [
    #goal(title: "Zrig")[g]
    #invariant(title: "Zrii", enforcement: "convention")[i]
    #principle(title: "Zrip")[p]
  ])
]
XEOF
  cat >"$FO/alpha/design.typ" <<EOF
#import "../.render/designlib.typ": *
#let title = [Zri alpha]
#let body = [
  #section(title: "01 Refs", body: [
    $2
  ])
]
EOF
  ri_out="$(python3 ./scripts/design-aggregate "$FO" "$FO/ri.pdf" 2>&1)"
  ri_rc=$?
  if [ "$ri_rc" -eq 0 ]; then
    fail_line "$1 — a broken reference rendered, integrity was weakened"
  elif [ -f "$FO/ri.pdf" ]; then
    fail_line "$1 — refused but still wrote a document"
  elif ! printf '%s' "$ri_out" | grep -q "$3"; then
    # A non-zero exit is NOT enough. Relaxing the integrity check let this case
    # crash further downstream instead — the run still failed, and the test
    # still passed, while the check it names was gone. The REASON is asserted so
    # the assertion tracks the check rather than the exit code.
    fail_line "$1 — refused for the wrong reason: $(printf '%s' "$ri_out" | head -1)"
  else
    pass_line "$1"
  fi
  rm -f "$FO/ri.pdf"
}

# a term nothing declares: the citation renders the declared TITLE, so an
# undeclared slug has no text at all.
ri_refuses "a dangling term() still hard-fails" \
  'The #term("no-such-term-anywhere") is cited.' \
  'cites a term no CONTEXT.typ declares'
# a context no directory declares
ri_refuses "a dangling ctx() still hard-fails" \
  'The #ctx("no-such-context") is cited.' \
  'names no context this layer declares'
# an edge naming a node the diagram does not declare
ri_refuses "a diagram edge to an undeclared node still hard-fails" \
  '#diagram-native(altitude: "L2", nodes: ((id: "a", label: "A", pos: (0, 0)),),
     edges: (("a", "ghost"),))' \
  'is not a declared node'
# an adr() citation that is not a usable number — the citation IS the number
ri_refuses "a malformed adr() citation still hard-fails" \
  'The decision is #adr("7").' \
  'takes the ADR NUMBER as an integer'

# --- 4f. HOST FONTS CANNOT CHANGE RENDERED BYTES ------------------------------
# Typst searches supplied font paths before its embedded fonts. A host can
# therefore render the same source with a different font file while every
# visible mark remains present. The gate must remove ambient font paths and
# keep the embedded families (Libertinus Serif and DejaVu Sans Mono) selected.
FONT_LAYER="$WORK/font-layer/docs/design"
mkdir -p "$FONT_LAYER"
# Typst resolves --root against canonical paths. macOS exposes /tmp as a
# symlink to /private/tmp, so retain the physical path or an external bundled
# library can be addressed as /private/nix/... and fail to resolve.
FONT_LAYER="$(cd "$FONT_LAYER" && pwd -P)"
bash ./scripts/render-project schema/design-schema.json "$FONT_LAYER/.render" >/dev/null
cat >"$FONT_LAYER/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Zfont document]
#let body = [
  #set text(font: "Libertinus Serif")
  #section(title: "Zfont section", body: [
    #text(font: "DejaVu Sans Mono")[Zfont embedded family 1234567890.]
  ])
]
EOF

FONT_DIR="${DESIGN_TEST_FONT_DIR:-}"
RAW_TYPST="${DESIGN_RAW_TYPST:-}"
if [ -z "$FONT_DIR" ] || [ ! -d "$FONT_DIR" ] ||
  [ -z "$RAW_TYPST" ] || [ ! -x "$RAW_TYPST" ]; then
  fail_line "the font regression has no real DejaVu font directory"
else
  cat >"$FONT_LAYER/font-probe.typ" <<'EOF'
#set text(font: "DejaVu Sans Mono")
Zfont raw probe 1234567890.
EOF
  clean_raw_env=(env TYPST_IGNORE_SYSTEM_FONTS=true)
  ambient_raw_env=(env TYPST_FONT_PATHS="$FONT_DIR" TYPST_IGNORE_SYSTEM_FONTS=false)
  clean_env=(env TYPST_IGNORE_SYSTEM_FONTS=true)
  ambient_env=(env TYPST_FONT_PATHS="$FONT_DIR" TYPST_IGNORE_SYSTEM_FONTS=false)
  embedded_env=(env TYPST_IGNORE_EMBEDDED_FONTS=true)

  if "${clean_raw_env[@]}" "$RAW_TYPST" compile --root "$FONT_LAYER" \
    "$FONT_LAYER/font-probe.typ" "$FONT_LAYER/raw-clean.pdf" >/dev/null 2>&1 &&
    "${ambient_raw_env[@]}" "$RAW_TYPST" compile --root "$FONT_LAYER" \
      "$FONT_LAYER/font-probe.typ" "$FONT_LAYER/raw-ambient.pdf" >/dev/null 2>&1 &&
    ! cmp -s "$FONT_LAYER/raw-clean.pdf" "$FONT_LAYER/raw-ambient.pdf"; then
    pass_line "the raw Typst renderer exposes the real font conflict"
  else
    fail_line "the real font fixture does not expose a raw renderer conflict"
  fi

  if "${clean_env[@]}" python3 ./scripts/design-aggregate \
    "$FONT_LAYER" "$FONT_LAYER/design-layer.pdf" >/dev/null 2>&1; then
    pass_line "the embedded-font fixture renders"
  else
    fail_line "the embedded-font fixture did not render"
  fi

  if "${clean_env[@]}" python3 ./scripts/design-aggregate \
    "$FONT_LAYER" "$FONT_LAYER/design-layer.pdf" --check >/dev/null 2>&1; then
    pass_line "the embedded-font fixture is fresh"
  else
    fail_line "the embedded-font fixture was reported stale"
  fi

  if "${ambient_env[@]}" python3 ./scripts/design-aggregate \
    "$FONT_LAYER" "$FONT_LAYER/ambient.pdf" >/dev/null 2>&1 &&
    cmp -s "$FONT_LAYER/design-layer.pdf" "$FONT_LAYER/ambient.pdf"; then
    pass_line "ambient font paths cannot change rendered bytes"
  else
    fail_line "ambient font paths changed the rendered bytes"
  fi

  if "${ambient_env[@]}" python3 ./scripts/design-aggregate \
    "$FONT_LAYER" "$FONT_LAYER/design-layer.pdf" --check >/dev/null 2>&1; then
    pass_line "freshness ignores ambient font path configuration"
  else
    fail_line "ambient font path configuration made a fresh PDF stale"
  fi

  if "${embedded_env[@]}" python3 ./scripts/design-aggregate \
    "$FONT_LAYER" "$FONT_LAYER/design-layer.pdf" --check >/dev/null 2>&1; then
    pass_line "an embedded-font opt-out cannot change freshness"
  else
    fail_line "an embedded-font opt-out changed the render policy"
  fi

  PUBLIC_RENDER="${DESIGN_RENDER_APP:-}"
  PUBLIC_CHECK="${DESIGN_CHECK_APP:-}"
  FONT_REPO="${FONT_LAYER%/docs/design}"
  git init -q "$FONT_REPO"
  if [ -z "$PUBLIC_RENDER" ] || [ ! -x "$PUBLIC_RENDER" ] ||
    [ -z "$PUBLIC_CHECK" ] || [ ! -x "$PUBLIC_CHECK" ]; then
    fail_line "the public render/check apps are missing from the gate test"
  else
    public_env=(env TYPST=/bin/false TYPST_FONT_PATHS="$FONT_DIR"
      TYPST_IGNORE_SYSTEM_FONTS=false TYPST_IGNORE_EMBEDDED_FONTS=true)
    cp "$FONT_LAYER/design-layer.pdf" "$FONT_LAYER/public-clean.pdf"
    if "${public_env[@]}" "$PUBLIC_RENDER" "$FONT_LAYER" \
      "$FONT_LAYER/design-layer.pdf" >/dev/null 2>&1 &&
      cmp -s "$FONT_LAYER/design-layer.pdf" "$FONT_LAYER/public-clean.pdf"; then
      cp "$FONT_LAYER/design-layer.pdf" "$FONT_LAYER/public-good.pdf"
      pass_line "the public render app ignores ambient font and binary settings"
    else
      fail_line "the public render app did not render the font fixture"
    fi

    if "${public_env[@]}" "$PUBLIC_CHECK" "$FONT_LAYER" "$FONT_REPO" \
      >/dev/null 2>&1; then
      pass_line "the public check app accepts the fresh ambient-font render"
    else
      fail_line "the public check app rejected its fresh render"
    fi

    cp "$FONT_LAYER/public-good.pdf" "$FONT_LAYER/design-layer.pdf"
    printf '\n%% public-stale-marker\n' >>"$FONT_LAYER/design-layer.pdf"
    cp "$FONT_LAYER/design-layer.pdf" "$FONT_LAYER/public-stale.pdf"
    public_stale_out="$FONT_LAYER/public-stale.out"
    if "${public_env[@]}" "$PUBLIC_CHECK" "$FONT_LAYER" "$FONT_REPO" \
      >"$public_stale_out" 2>&1; then
      fail_line "the public check app accepted a stale PDF"
    elif grep -q "is stale" "$public_stale_out" &&
      cmp -s "$FONT_LAYER/design-layer.pdf" "$FONT_LAYER/public-stale.pdf"; then
      pass_line "the public check app detects stale bytes without rewriting"
    else
      fail_line "the public check app did not report the stale PDF correctly"
    fi
    cp "$FONT_LAYER/public-good.pdf" "$FONT_LAYER/design-layer.pdf"
  fi

  if typst compile --root "$FONT_LAYER" --font-path "$FONT_DIR" \
    "$FONT_LAYER/design.typ" "$FONT_LAYER/cli.pdf" >/dev/null 2>&1; then
    fail_line "an explicit Typst font path bypassed the renderer policy"
    rm -f "$FONT_LAYER/cli.pdf"
  else
    pass_line "an explicit Typst font path is rejected by the renderer policy"
  fi

  if typst compile --root "$FONT_LAYER" --ignore-embedded-fonts \
    "$FONT_LAYER/design.typ" "$FONT_LAYER/cli-embedded.pdf" >/dev/null 2>&1; then
    fail_line "the embedded-font opt-out bypassed the renderer policy"
    rm -f "$FONT_LAYER/cli-embedded.pdf"
  else
    pass_line "the embedded-font opt-out is rejected by the renderer policy"
  fi
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
