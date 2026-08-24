#!/usr/bin/env bash
set -euo pipefail

# Self-test for scripts/layer-integrity.
#
# THE AUTHORING SURFACE IS TYPST. A design document is a `design.typ` calling
# the library directly and its glossary a `CONTEXT.typ`; markdown authoring was
# removed, and a layer still holding a `design.md` or a `CONTEXT.md` is REFUSED
# rather than checked. So every fixture below authors Typst.
#
# THE REST OF THE LAYER STAYS MARKDOWN, and that boundary is the point of the
# migration: `docs/adr/NNNN-slug.md`, `docs/CONTEXT-MAP.md` and
# `docs/COVERAGE.md` are markdown artifacts, indexed by the markdown indexer,
# and every check that reads them must keep working exactly as it did. The
# markdown-only mechanisms — a fenced code block exempting its content, a
# mermaid `click` target resolving as a link — therefore keep their assertions,
# asked of a markdown artifact rather than of a design document.
#
# Builds throwaway fixture repos under a single mktemp -d and asserts the
# checker's exit code plus a distinguishing report string per scenario:
#   (a) clean single-context layer                     -> exit 0
#   (b) clean multi-context layer                      -> exit 0
#   (c) dangling term link (anchor absent)             -> exit 1
#   (d) near-miss anchors (#trem- typo, bare #term-)   -> exit 1 (fail-closed)
#   (e) ADR filename/anchor NNNN mismatch              -> exit 1
#   (f) CONTEXT.typ missing from CONTEXT-MAP.md        -> exit 1
#   (g) a per-context design.pdf (the layer renders as ONE) -> exit 1
#   (d4/d5) multi-line #section( indexes as an anchor  -> exit 0 / exit 1
#   (h) duplicate term id within one CONTEXT.typ       -> exit 1
#   (q2/q3) wrapped ADR citations vs real restatement  -> exit 0 / exit 1
#   (i) empty repo / no design layer                   -> exit 2 ("no design layer")
#   (j) usage error: too many args                     -> exit 2
#   (k) unresolvable schema (DESIGN_SCHEMA points off) -> exit 2
#   (s) copy-installed script reads its script-sibling schema -> exit 0
#   (t) generation debris (</content> line) in an ADR / COVERAGE.md -> exit 1
#   (u) debris shape inside a fenced code block (markdown) -> exit 0
#   (v) layer files colocated in a source directory -> exit 1 (mishomed)
#   (w) CONTEXT-MAP.md at repo root instead of docs/ -> exit 1 (mishomed)
#   (x) staleness advisory fires past the threshold -> exit 0 + advisory line
#   (y) staleness advisory silent under the threshold / without the schema key
#   (md) a layer still authored in markdown -> exit 2 (refused, names the file)
#
# Depends on no repo files beyond the checker + schema and leaves no
# artifacts behind. Accepts an optional path to the checker as $1
# (default: resolved from this script's location).

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="${1:-$HERE/layer-integrity}"

if [ ! -x "$CHECK" ]; then
  echo "error: checker not found or not executable: $CHECK" >&2
  exit 2
fi

# The checker must resolve the schema from its own location; make sure a
# stray environment override does not leak into the scenarios.
unset DESIGN_SCHEMA || true

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

# assert_exit <expected-code> <label> -- <cmd...>
# Runs the command, captures exit code and combined output, checks the code,
# and stashes the output in LAST_OUT for follow-up content assertions.
LAST_OUT=""
assert_exit() {
  local expected="$1" label="$2"
  shift 3 # drop expected, label, and the literal "--"
  local out code
  set +e
  out="$("$@" 2>&1)"
  code=$?
  set -e
  LAST_OUT="$out"
  if [ "$code" -eq "$expected" ]; then
    echo "PASS: $label (exit $code)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label -- expected exit $expected, got $code"
    echo "      output: $out"
    fail=$((fail + 1))
  fi
}

# assert_contains <needle> <label> -- checks LAST_OUT contains needle.
assert_contains() {
  local needle="$1" label="$2"
  if printf '%s' "$LAST_OUT" | grep -qF -- "$needle"; then
    echo "PASS: $label"
    pass=$((pass + 1))
  else
    echo "FAIL: $label -- output did not contain '$needle'"
    echo "      output: $LAST_OUT"
    fail=$((fail + 1))
  fi
}

# assert_not_contains <needle> <label> -- checks LAST_OUT lacks needle.
assert_not_contains() {
  local needle="$1" label="$2"
  if printf '%s' "$LAST_OUT" | grep -qF -- "$needle"; then
    echo "FAIL: $label -- output unexpectedly contained '$needle'"
    echo "      output: $LAST_OUT"
    fail=$((fail + 1))
  else
    echo "PASS: $label"
    pass=$((pass + 1))
  fi
}

# build_single <root> -- a healthy single-context Typst layer:
#   <root>/docs/design/CONTEXT.typ         two valid term declarations
#   <root>/docs/design/design.typ          cites a term + an ADR by CALL, links
#                                          a term by path, plus ignorable links
#                                          (external, non-design-ish relative)
#   <root>/docs/design/design-layer.pdf    the layer's ONE rendered document
#   <root>/docs/adr/0001-first-decision.md one anchor, in lockstep (MARKDOWN)
#
# The fixture is read by layer-integrity, a text scanner, and never compiled,
# so it is shaped like a real layer rather than made renderable.
build_single() {
  local root="$1"
  mkdir -p "$root/docs/design" "$root/docs/adr"

  cat >"$root/docs/design/CONTEXT.typ" <<'EOF'
#let terms = (
  (slug: "term-drift", title: [Drift],
   body: [The gap between the design layer and the implementation.]),
  (slug: "term-work-order", title: [Work Order],
   body: [A self-contained brief handed to a coding agent.]),
)
EOF

  cat >"$root/docs/adr/0001-first-decision.md" <<'EOF'
# 0001 — First decision

<a id="adr-0001"></a>

## Status

Accepted.

## Decision

Decisions are recorded as an append-only ADR ledger.
EOF

  cat >"$root/docs/design/design.typ" <<'EOF'
#let title = [Design]
#let body = [
  #section(title: "00 Foundation")[
    The system tracks #term("term-drift") between the layer and the system.
    The ledger holds the argument, #adr(1).
    A term also reachable by path: #link("CONTEXT.typ#term-work-order")[the brief].
  ]
  #section(title: "01 System at a glance")[
    An #link("https://example.com/spec")[external spec] and a non-design-ish
    relative link to a #link("../notes/plan.md")[missing note] are both
    ignored by the checker.
  ]
]
EOF

  # The layer's rendered document. Its CONTENT is irrelevant to every check
  # here — the artifact is binary and carries no anchors to index — so a stub
  # stands in for a real render. What matters is its NAME and its PLACE.
  printf '%%PDF-1.7 stub\n' >"$root/docs/design/design-layer.pdf"
}

# build_multi <root> -- a healthy multi-context Typst layer:
#   <root>/docs/CONTEXT-MAP.md             exact links to both CONTEXT.typ (MARKDOWN)
#   <root>/docs/design/design.typ          names both contexts by ctx() call + ADR
#   <root>/docs/design/design-layer.pdf    the layer's ONE rendered document
#   <root>/docs/adr/0001-first-decision.md one anchor, in lockstep (MARKDOWN)
#   <root>/docs/design/alpha/{design.typ,CONTEXT.typ}
#   <root>/docs/design/beta/{design.typ,CONTEXT.typ}
#   (no per-context PDF: a context renders as a chapter, not its own document)
#
# THE ROOT NAMES ITS CONTEXTS BY CALL, not by path. `#ctx("alpha")` is the
# reference form, so check 4's root-linkage half is asked of the root's ctx()
# arguments rather than of its link destinations.
build_multi() {
  local root="$1"
  mkdir -p "$root/docs/design/alpha" "$root/docs/design/beta" "$root/docs/adr"

  cat >"$root/docs/CONTEXT-MAP.md" <<'EOF'
# Context Map

- [Alpha](./design/alpha/CONTEXT.typ) — the alpha vocabulary.
- [Beta](./design/beta/CONTEXT.typ) — the beta vocabulary.
EOF

  cat >"$root/docs/adr/0001-first-decision.md" <<'EOF'
# 0001 — First decision

<a id="adr-0001"></a>

Decisions are recorded as an append-only ADR ledger.
EOF

  cat >"$root/docs/design/design.typ" <<'EOF'
#let title = [Design]
#let body = [
  #section(title: "00 Foundation")[
    The ledger holds the argument, #adr(1).
  ]
  #section(title: "01 System at a glance")[
    The layer carves the system into #ctx("alpha") and #ctx("beta").
  ]
]
EOF

  # The layer's rendered document. Its CONTENT is irrelevant to every check
  # here — the artifact is binary and carries no anchors to index — so a stub
  # stands in for a real render. What matters is its NAME and its PLACE.
  printf '%%PDF-1.7 stub\n' >"$root/docs/design/design-layer.pdf"

  cat >"$root/docs/design/alpha/CONTEXT.typ" <<'EOF'
#let terms = (
  (slug: "term-alpha-thing", title: [Alpha Thing],
   body: [The one thing alpha owns.]),
)
EOF

  cat >"$root/docs/design/alpha/design.typ" <<'EOF'
#let title = [Alpha design]
#let body = [
  #section(title: "00 Foundation")[
    Alpha is built around the #term("term-alpha-thing") and nothing else.
  ]
]
EOF

  cat >"$root/docs/design/beta/CONTEXT.typ" <<'EOF'
#let terms = (
  (slug: "term-beta-thing", title: [Beta Thing],
   body: [The one thing beta owns.]),
)
EOF

  cat >"$root/docs/design/beta/design.typ" <<'EOF'
#let title = [Beta design]
#let body = [
  #section(title: "00 Foundation")[
    Beta is built around the #term("term-beta-thing") and nothing else.
  ]
]
EOF
}

# --- Scenario (a): clean single-context -> exit 0 ---------------------------
SA="$TMP/a"
build_single "$SA"
assert_exit 0 "clean single-context layer" -- "$CHECK" "$SA"
assert_contains "layer-integrity OK" "clean single-context prints the OK summary"

# Default repo-root is "." — running from inside the fixture, no args.
assert_exit 0 "default repo-root is the cwd" -- bash -c 'cd "$1" && "$0"' "$CHECK" "$SA"
assert_contains "layer-integrity OK" "default-root run prints the OK summary"

# --- Scenario (b): clean multi-context -> exit 0 -----------------------------
SB="$TMP/b"
build_multi "$SB"
assert_exit 0 "clean multi-context layer" -- "$CHECK" "$SB"
assert_contains "layer-integrity OK" "clean multi-context prints the OK summary"

# --- Scenario (c): dangling term link -> exit 1 ------------------------------
SC="$TMP/c"
build_single "$SC"
cat >"$SC/docs/design/design.typ" <<'EOF'
#let title = [Design]
#let body = [
  #section(title: "00 Foundation")[
    The system tracks #link("CONTEXT.typ#term-missing-term")[drift] here.
  ]
]
EOF
assert_exit 1 "dangling term link is a violation" -- "$CHECK" "$SC"
assert_contains "dangling term anchor" "report flags the dangling term anchor"
assert_contains "term-missing-term" "report names the missing term id"

# --- Scenario (d): near-miss anchors -> exit 1 (fail-closed) ------------------
# A #trem- typo and a bare #term- (no slug) both LOOK design-ish and must be
# violations, never silent skips.
SD="$TMP/d"
build_single "$SD"
cat >"$SD/docs/design/design.typ" <<'EOF'
#let title = [Design]
#let body = [
  #section(title: "00 Foundation")[
    The system tracks #link("CONTEXT.typ#trem-drift")[drift] between artifacts.
    A slugless anchor is just as broken: #link("CONTEXT.typ#term-")[bad].
  ]
]
EOF
assert_exit 1 "near-miss anchors are violations" -- "$CHECK" "$SD"
assert_contains "malformed anchor" "report flags the near-miss as malformed"
assert_contains "trem-drift" "report names the #trem- typo"
assert_contains "'#term-'" "report names the slugless #term-"

# --- Scenario (d2): section anchors -> accepted, and resolved ----------------
# design_doc.generation.link_rewrite documents `foo/design.typ#02-x`, so a link
# into a SECTION of a design document is legal alongside term and adr anchors.
# It must resolve like any other: a real section passes, an invented one fails.
# The section's rendered id comes from the `#section(title: "…")` argument, by
# the same slug rule the schema declares.
SD2="$TMP/d2"
build_single "$SD2"
cat >"$SD2/docs/design/design.typ" <<'EOF'
#let title = [Design]
#let body = [
  #section(title: "00 Foundation")[
    A pointer into a real section: #link("design.typ#02-the-artifact-trio")[the trio].
  ]
  #section(title: "02 The artifact trio")[
    The section the link above resolves to, named by its own heading text.
  ]
]
EOF
assert_exit 0 "a section anchor resolving to a real section passes" -- "$CHECK" "$SD2"

SD3="$TMP/d3"
build_single "$SD3"
cat >"$SD3/docs/design/design.typ" <<'EOF'
#let title = [Design]
#let body = [
  #section(title: "00 Foundation")[
    A pointer into a section that does not exist:
    #link("design.typ#99-not-a-section")[nowhere].
  ]
]
EOF
assert_exit 1 "a section anchor with no such section is a violation" -- "$CHECK" "$SD3"
assert_contains "dangling section anchor" "report names it as a dangling section anchor"

# --- Scenario (d4): a MULTI-LINE section call indexes as an anchor -----------
# THE REAL AUTHORING STYLE OPENS A SECTION ACROSS LINES. Every fixture above
# spells `#section(title: "…")` on one line, which is the convenient spelling
# and not the one consumer repos use:
#
#   #section(
#     title: "04 The catalog gate",
#     body: [ … ]
#   )
#
# The section scan ran per line, so `\s*` between `section(` and `title:` could
# never cross the newline and every multi-line section fell out of the anchor
# index. Measured on a real layer: 4 of 10 sections indexed, and all 16 distinct
# cross-document section anchors were reported dangling — a 100% rejection rate,
# which is the signature of a check matching nothing. A single-line section is
# asserted alongside so the fix is proved to have ADDED the multi-line form
# rather than swapped which spelling works.
SD4="$TMP/d4"
build_single "$SD4"
cat >"$SD4/docs/design/design.typ" <<'EOF'
#let title = [Design]
#let body = [
  #section(
    title: "00 Foundation",
    body: [
      A pointer into a multi-line section:
      #link("design.typ#04-the-catalog-gate")[the gate].
      And one into a single-line subsection:
      #link("design.typ#031-the-composition-mechanism")[the mechanism].
    ],
  )
  #section(
    title: "04 The catalog gate",
    lead: "The gate that keeps ship-status skills discoverable.",
    body: [
      The section the first link resolves to, opened across several lines
      exactly as a real design document opens one.
    ],
  )
  #subsection(title: "031 The composition mechanism")[
    The single-line spelling, which indexed correctly all along.
  ]
]
EOF
assert_exit 0 "a multi-line #section( anchor resolves" -- "$CHECK" "$SD4"
assert_contains "layer-integrity OK" "multi-line section run stays clean"
assert_not_contains "dangling section anchor" \
  "neither the multi-line nor the single-line section is reported dangling"

# The discriminating half: with multi-line sections indexed, an anchor naming a
# section that genuinely does not exist must STILL fail. Without this, a fix
# that indexed every string in the file would pass the assertion above.
SD5="$TMP/d5"
build_single "$SD5"
cat >"$SD5/docs/design/design.typ" <<'EOF'
#let title = [Design]
#let body = [
  #section(
    title: "00 Foundation",
    body: [
      A pointer into a section nobody wrote:
      #link("design.typ#07-not-a-real-section")[nowhere].
    ],
  )
  #section(
    title: "04 The catalog gate",
    body: [
      A real multi-line section, which is not the one linked above.
    ],
  )
]
EOF
assert_exit 1 "an invented section anchor still fails once multi-line sections index" \
  -- "$CHECK" "$SD5"
assert_contains "dangling section anchor" "the invented section is reported dangling"
assert_contains "07-not-a-real-section" "report names the invented section id"

# --- Scenario (d6): the NUMBERING'S DOT is removed, not collapsed ------------
# The schema (anchors.section.slug_rule) is explicit: "the numbering's dot
# REMOVED", '### 02.1 The pending ledger' -> '021-the-pending-ledger'. Both
# indexers instead collapsed that dot to a hyphen and produced
# '02-1-the-pending-ledger', so a cross-document link written to the schema was
# reported dangling. Measured on a real layer: 8 violations, every one a dotted
# subsection anchor, against a COVERAGE.md that was correct all along.
#
# A dotted subsection and an undotted section are asserted together, so the rule
# is proved to handle the numbering without breaking the plain case.
SD6="$TMP/d6"
build_single "$SD6"
cat >"$SD6/docs/design/design.typ" <<'EOF'
#let title = [Design]
#let body = [
  #section(
    title: "03 The primitive",
    body: [
      A pointer at a dotted subsection:
      #link("design.typ#031-the-composition-mechanism")[the mechanism].
      And one at an undotted section:
      #link("design.typ#03-the-primitive")[the primitive].
    ],
  )
  #subsection(
    title: "03.1 The composition mechanism",
    body: [
      The dotted subsection, whose id drops the numbering's dot entirely.
    ],
  )
]
EOF
assert_exit 0 "a dotted subsection anchor resolves with the dot removed" -- "$CHECK" "$SD6"
assert_contains "layer-integrity OK" "dotted-subsection run stays clean"
assert_not_contains "dangling section anchor" \
  "neither the dotted nor the undotted section is reported dangling"

# The discriminating half: the OLD, wrong spelling must now FAIL. Without this,
# a rule that emitted both spellings would pass the assertion above while still
# leaving which id a section actually has ambiguous.
SD7="$TMP/d7"
build_single "$SD7"
cat >"$SD7/docs/design/design.typ" <<'EOF'
#let title = [Design]
#let body = [
  #section(
    title: "03 The primitive",
    body: [
      The dot-collapsed spelling the schema does not bless:
      #link("design.typ#03-1-the-composition-mechanism")[the mechanism].
    ],
  )
  #subsection(
    title: "03.1 The composition mechanism",
    body: [
      The section's real id drops the dot entirely.
    ],
  )
]
EOF
assert_exit 1 "the dot-collapsed spelling is not a valid section id" -- "$CHECK" "$SD7"
assert_contains "dangling section anchor" "the wrong spelling is reported dangling"

# --- Scenario (d8): a NON-NUMBERING dot survives as a hyphen -----------------
# The schema says "the numbering's dot", so the removal is SCOPED to the leading
# number rather than applied to every dot in the heading. The numbering is the
# only place a dot joins two halves of one identifier; anywhere else a dot is
# ordinary punctuation and collapses to a hyphen like any other non-alphanumeric
# run. Blanket-deleting every dot would weld a title naming 'design.typ' into
# 'designtyp', mangling a word the reader is meant to recognise. Both scopes
# appear in ONE heading, so they are proved distinct rather than merely stated.
SD8="$TMP/d8"
build_single "$SD8"
cat >"$SD8/docs/design/design.typ" <<'EOF'
#let title = [Design]
#let body = [
  #section(
    title: "02 Foundation",
    body: [
      A dot inside the TITLE is punctuation, not numbering:
      #link("design.typ#021-the-renderer-reads-design-typ")[the renderer].
    ],
  )
  #subsection(
    title: "02.1 The renderer reads design.typ",
    body: [
      The numbering's dot is removed and the title's dot becomes a hyphen.
    ],
  )
]
EOF
assert_exit 0 "a non-numbering dot collapses to a hyphen" -- "$CHECK" "$SD8"
assert_contains "layer-integrity OK" "non-numbering-dot run stays clean"
assert_not_contains "dangling section anchor" "the mixed-dot heading resolves"

# --- Scenario (d10): THE ANTI-DRIFT PROPERTY, asserted directly --------------
# The slug rule belongs to the ANCHOR, not to the notation the target was
# written in, so the SAME heading text must yield the SAME id on both sides.
# Both indexers now call one section_slug, and this asserts they AGREE on the
# id for one heading text.
#
# THE ASSERTION IS MADE AT THE UNIT LEVEL, DELIBERATELY, because no end-to-end
# fixture can currently observe the markdown side of this property.
# `section_ids` is consulted only on a link's TARGET, and the schema's
# design_ish_markers make the only markdown targets the ADR files — whose
# fragments classify as `adr`, never as `section`. COVERAGE.md and
# CONTEXT-MAP.md are not design-ish targets at all. So the markdown heading slug
# is unreachable through a link today: a black-box fixture that breaks it still
# passes, which was measured rather than assumed. Asserting through the gate
# here would produce a test that reports agreement while examining one side.
#
# The two readers are therefore called directly on the same heading text and
# their ids compared, which is the property itself rather than a proxy for it.
# The Typst side keeps its end-to-end coverage in d6/d7/d8 above.
SD10="$TMP/d10"
python3 - "$CHECK" <<'PY'
import importlib.util, json, os, sys, tempfile

spec = importlib.util.spec_from_loader("layer_integrity", None)
mod = importlib.util.module_from_spec(spec)
mod.__dict__["__name__"] = "layer_integrity_under_test"
exec(compile(open(sys.argv[1]).read(), sys.argv[1], "exec"), mod.__dict__)

index_markdown = mod.__dict__["index_markdown"]
index_typst = mod.__dict__["index_typst"]
load_schema = mod.__dict__["load_schema"]
locate_schema = mod.__dict__["locate_schema"]

schema = load_schema(locate_schema(sys.argv[1]))
tmp = tempfile.mkdtemp()

# THE REAL INDEXERS ARE CALLED, never a local re-implementation of their logic.
# A test that mirrors the rule instead of invoking it passes while the shipped
# function is broken — measured: a hand-rolled copy of index_markdown's slug
# path reported agreement with the markdown reader gutted underneath it.
def markdown_id(heading: str) -> str:
    p = os.path.join(tmp, "COVERAGE.md")
    with open(p, "w") as fh:
        fh.write(heading + "\n\nBody text under the heading.\n")
    ids = index_markdown(p, "COVERAGE.md", schema).section_ids
    return sorted(ids)[0] if ids else ""

def typst_id(title: str) -> str:
    p = os.path.join(tmp, "design.typ")
    # Real Typst: a DOUBLE-quoted title, in the multi-line authoring style.
    # json.dumps gives double quotes and escapes correctly; repr() would emit
    # Python's single quotes, which TYPST_SECTION_RE does not match — and a
    # helper that silently indexes nothing is the failure this suite exists to
    # catch, so the fixture must be genuine Typst.
    with open(p, "w") as fh:
        fh.write(
            "#let body = [\n  #section(\n    title: %s,\n"
            "    body: [ Body text under the section. ],\n  )\n]\n"
            % json.dumps(title, ensure_ascii=False)
        )
    ids = index_typst(p, "design.typ", schema).section_ids
    return sorted(ids)[0] if ids else ""

cases = [
    ("02 The artifact trio", "02-the-artifact-trio"),
    ("02.1 The pending ledger", "021-the-pending-ledger"),
    ("04.2 Token coverage — the semantic look is total",
     "042-token-coverage-the-semantic-look-is-total"),
    ("02.1 The renderer reads design.typ", "021-the-renderer-reads-design-typ"),
]

failed = 0
for title, expected in cases:
    md = markdown_id("### " + title)
    tp = typst_id(title)
    if md != tp:
        print(f"FAIL: markdown/Typst slug drift for {title!r}: {md!r} != {tp!r}")
        failed += 1
    elif tp != expected:
        print(f"FAIL: slug for {title!r} is {tp!r}, schema requires {expected!r}")
        failed += 1
    else:
        print(f"PASS: both notations derive {tp!r}")

sys.exit(1 if failed else 0)
PY
if [ $? -eq 0 ]; then
  echo "PASS: markdown and Typst derive the same schema-correct id for one heading"
  pass=$((pass + 1))
else
  echo "FAIL: markdown and Typst disagree on a section id"
  fail=$((fail + 1))
fi

# --- Scenario (e): ADR filename/anchor mismatch -> exit 1 --------------------
# THE ADRs STAY MARKDOWN. Check 2 reads them with the markdown indexer and
# asserts the same lockstep it always did.
SE="$TMP/e"
build_single "$SE"
cat >"$SE/docs/adr/0002-second-decision.md" <<'EOF'
# 0002 — Second decision

<a id="adr-0003"></a>

The anchor disagrees with the filename.
EOF
assert_exit 1 "adr filename/anchor mismatch is a violation" -- "$CHECK" "$SE"
assert_contains "adr lockstep mismatch" "report flags the lockstep break"
assert_contains "0002-second-decision.md" "report names the offending ADR"

# --- Scenario (f): CONTEXT.typ missing from the map -> exit 1 -----------------
SF="$TMP/f"
build_multi "$SF"
cat >"$SF/docs/CONTEXT-MAP.md" <<'EOF'
# Context Map

- [Alpha](./design/alpha/CONTEXT.typ) — the alpha vocabulary.
EOF
assert_exit 1 "unmapped glossary is a violation" -- "$CHECK" "$SF"
assert_contains "unmapped glossary" "report flags the map gap"
assert_contains "docs/design/beta/CONTEXT.typ" "report names the unmapped context"

# --- Scenario (f2): a context the root does not name -> exit 1 ---------------
# CHECK 4's ROOT-LINKAGE HALF, in the vocabulary the notation actually uses.
# The reference is a CALL carrying a bare name, so the question "is any domain
# design document orphaned from the root" is asked against the root's ctx()
# arguments. This half had no coverage: asked of a markdown root it returned
# early on anything else, so once markdown authoring was removed the early
# return was unconditional and the check examined nothing while still reading
# as enforcement.
SF2="$TMP/f2"
build_multi "$SF2"
cat >"$SF2/docs/design/design.typ" <<'EOF'
#let title = [Design]
#let body = [
  #section(title: "00 Foundation")[
    The ledger holds the argument, #adr(1).
  ]
  #section(title: "01 System at a glance")[
    The layer names #ctx("alpha") and forgets the other context entirely.
  ]
]
EOF
assert_exit 1 "a context the root never names is a violation" -- "$CHECK" "$SF2"
assert_contains "unindexed domain design doc" "report flags the unindexed context"
assert_contains "docs/design/beta/design.typ" "report names the orphaned design doc"
assert_contains 'ctx("…") call' "report names the reference form it looked for"
# The context the root DOES name is not reported, so the check discriminates
# rather than rejecting every context it sees.
assert_not_contains "docs/design/alpha/design.typ: unindexed" \
  "the named context is not reported as unindexed"

# --- Scenario (g): orphan design.pdf -> exit 1 -------------------------------
SG="$TMP/g"
build_single "$SG"
mkdir -p "$SG/docs/design/tool"
printf '%%PDF-1.7 stub\n' >"$SG/docs/design/tool/design.pdf"
assert_exit 1 "a per-context design.pdf is a violation" -- "$CHECK" "$SG"
assert_contains "mishomed layer artifact" "report flags it as mishomed"
assert_contains "docs/design/tool/design.pdf" "report names the stray file"

# --- Scenario (h): duplicate term id -> exit 1 --------------------------------
# A glossary declaring one slug twice: the second declaration silently shadows
# the first, and every citation of it resolves to whichever the renderer kept.
SH="$TMP/h"
build_single "$SH"
cat >"$SH/docs/design/CONTEXT.typ" <<'EOF'
#let terms = (
  (slug: "term-drift", title: [Drift],
   body: [The gap between the design layer and the implementation.]),
  (slug: "term-drift", title: [Drift Again],
   body: [The same id declared twice over.]),
)
EOF
assert_exit 1 "duplicate term id is a violation" -- "$CHECK" "$SH"
assert_contains "duplicate term id" "report flags the duplicate"
assert_contains "term-drift" "report names the duplicated id"

# --- Scenario (i): empty repo / no layer -> exit 2, distinct message ----------
SI="$TMP/i"
mkdir -p "$SI/src"
echo "just code" >"$SI/src/main.txt"
assert_exit 2 "repo without a design layer is an IO-level error" -- "$CHECK" "$SI"
assert_contains "no design layer" "report says 'no design layer' distinctly"
assert_contains "no design.typ, CONTEXT.typ" "the message names the Typst entry points"

# --- Scenario (j): usage error (too many args) -> exit 2 ----------------------
assert_exit 2 "too many args is a usage error" -- "$CHECK" "$SA" extra-arg

# --- Scenario (k): unresolvable schema -> exit 2 ------------------------------
assert_exit 2 "missing schema is an error" -- \
  env DESIGN_SCHEMA=/nonexistent/design-schema.json "$CHECK" "$SA"
assert_contains "design schema not found" "report names the schema gap"

# --- Scenario (l): dangling sibling adr-ish link -> exit 1 --------------------
# The observed e2e hole: an adr-ish filename linked as a sibling path with no
# fragment matches no filename/substring/dir marker, but the schema's re:
# markers classify it design-ish — and the file does not exist.
SL="$TMP/l"
build_single "$SL"
cat >>"$SL/docs/design/design.typ" <<'EOF'
#section(title: "03 Storage")[
  Storage: #link("adr-0001-storage-envelope.md")[ADR-0001].
]
EOF
assert_exit 1 "dangling sibling adr-ish link is a violation" -- "$CHECK" "$SL"
assert_contains "dangling link" "report flags the unresolvable adr-ish link"
assert_contains "adr-0001-storage-envelope.md" "report names the missing adr-ish target"

# --- Scenario (m): adr-ish file existing outside the ADR dir -> exit 1 --------
# Same link, but the stray file exists next to design.typ: still a violation —
# an adr-ish target must live in the canonical ADR dir.
SM="$TMP/m"
build_single "$SM"
cat >>"$SM/docs/design/design.typ" <<'EOF'
#section(title: "03 Storage")[
  Storage: #link("adr-0001-storage-envelope.md")[ADR-0001].
]
EOF
cat >"$SM/docs/design/adr-0001-storage-envelope.md" <<'EOF'
# A stray ADR-looking file living outside docs/adr
EOF
assert_exit 1 "adr-ish file outside the ADR dir is a violation" -- "$CHECK" "$SM"
assert_contains "stray adr-ish file" "report flags the stray adr-ish target"

# --- Scenario (n): legal fragment-less link to a canonical ADR -> exit 0 ------
# A fragment-less link to an existing, lockstep-valid docs/adr/NNNN-slug.md is
# legal: the file resolves and check 2 owns its lockstep.
SN="$TMP/n"
build_single "$SN"
cat >>"$SN/docs/design/design.typ" <<'EOF'
#section(title: "03 The decision")[
  The full decision: #link("../adr/0001-first-decision.md")[ADR 1].
]
EOF
assert_exit 0 "fragment-less link to a canonical lockstep-valid ADR is legal" -- "$CHECK" "$SN"
assert_contains "layer-integrity OK" "legal adr link run stays clean"

# --- Scenario (o): verbatim-duplicated prose -> exit 1 -----------------------
# Restatement instead of a cross-link: the same prose sentence appears twice
# within one design.typ.
SO="$TMP/o"
build_single "$SO"
cat >>"$SO/docs/design/design.typ" <<'EOF'
#section(title: "02 Restatement")[
  The system tracks drift between the design layer and the implementation.
  Some interleaving prose that keeps the two copies apart in the file.
  The system tracks drift between the design layer and the implementation.
]
EOF
assert_exit 1 "verbatim-duplicated prose is a violation" -- "$CHECK" "$SO"
assert_contains "duplicate prose" "report flags the duplicated prose"
assert_contains "The system tracks drift between the design layer" \
  "report quotes the duplicated sentence"
assert_contains "appears 2x" "report counts the occurrences"

# --- Scenario (o2): a REPEATED CALL LINE is not duplicate prose -> exit 0 ----
# THE UNIT IS PROSE, NOT THE SOURCE LINE, and this is the direction that makes
# the check usable. Under a call notation a repeated line is usually the syntax
# working: an entity census writes `#attribute(provenance: "authored")[` once
# per attribute, and every section opens with the same `#section(` head.
# Counting lines would fail every well-formed layer, which trains a reader to
# ignore the check and hides the restatement it exists to catch.
SO2="$TMP/o2"
build_single "$SO2"
cat >>"$SO2/docs/design/design.typ" <<'EOF'
#section(title: "02 The entity census")[
  #attribute(provenance: "authored")[one]
  #attribute(provenance: "authored")[two]
  #attribute(provenance: "authored")[three]
]
#section(title: "03 The second census")[
  #attribute(provenance: "authored")[four]
  #attribute(provenance: "authored")[five]
]
EOF
assert_exit 0 "a repeated call line is not duplicate prose" -- "$CHECK" "$SO2"
assert_contains "layer-integrity OK" "repeated-call run stays clean"
assert_not_contains "duplicate prose" "no duplicate reported for a repeated call line"

# --- Scenario (p): repeated TRIVIAL fragments -> exit 0 (no false positive) ---
# Closing brackets, bare call heads, and short lone markers all legitimately
# repeat; none may trip the duplicate check.
SP="$TMP/p"
build_single "$SP"
cat >>"$SP/docs/design/design.typ" <<'EOF'
#section(title: "02 Invariants")[
  #invariant(
    title: "First",
    enforcement: "convention",
  )[
    An invariant statement long enough to count as prose, stated once.
  ]
  #invariant(
    title: "Second",
    enforcement: "convention",
  )[
    A different invariant statement, also long enough to count as prose.
  ]
  TODO
  A closing sentence with enough length to count as real prose here.
  TODO
]
EOF
assert_exit 0 "repeated trivial fragments do not false-positive" -- "$CHECK" "$SP"
assert_contains "layer-integrity OK" "trivial-repeat run stays clean"
assert_not_contains "duplicate prose" "no duplicate reported for trivial repeats"

# --- Scenario (q): repeated citation-only fragment -> exit 0 ------------------
# "Cited, never restated" makes citations the legal form of repetition: a
# fragment consisting entirely of citation calls (plus punctuation) may repeat.
SQ="$TMP/q"
build_single "$SQ"
cat >>"$SQ/docs/design/design.typ" <<'EOF'
#section(title: "02 Citations")[
  #adr(1) and #term("term-drift") and #ctx("design").
  Prose in between the two citations of the very same decision record.
  #adr(1) and #term("term-drift") and #ctx("design").
]
EOF
assert_exit 0 "repeated citation-only fragment is legal" -- "$CHECK" "$SQ"
assert_not_contains "duplicate prose" "no duplicate reported for repeated citations"

# --- Scenario (q2): two DISTINCT wrapped ADR citations are not duplicates -----
# The citation helper is imported at the citing site, which is how a real
# glossary cites a decision:
#
#   (#{ import "../refs.typ": adr; adr(63) }).],
#
# Only the inner `adr(63)` was recognised as a citation and removed, leaving the
# import preamble behind as the entire surviving "prose". Two citations of
# DIFFERENT decisions then normalised to the identical string
# `#{ import "../refs.typ": adr; } .`, and the duplicate check reported
# restatement across two lines that restate nothing. Two different ADR citations
# are not duplicated prose.
SQ2="$TMP/q2"
build_single "$SQ2"
cat >"$SQ2/docs/design/CONTEXT.typ" <<'EOF'
#let terms = (
  (slug: "term-drift", title: [Drift],
   body: [The gap between the design layer and the implementation.
      Every part binds at every write, ask, and report moment
      (#{ import "../refs.typ": adr; adr(1) }).],
  ),
  (slug: "term-work-order", title: [Work Order],
   body: [A self-contained brief handed to a coding agent.
      A word can name its concept and still strand a reader, and both bind
      (#{ import "../refs.typ": adr; adr(1) }).],
  ),
)
EOF
assert_exit 0 "two distinct wrapped ADR citations are not duplicate prose" -- "$CHECK" "$SQ2"
assert_contains "layer-integrity OK" "wrapped-citation run stays clean"
assert_not_contains "duplicate prose" "no duplicate reported for the import preamble"

# --- Scenario (q3): REAL duplicated prose is STILL caught --------------------
# The guard on the exemption above. A fix that excused too much would silence
# the check entirely, so the restated sentence sits ON THE SAME LINE as the
# wrapped citation. That placement is what makes this test load-bearing: an
# over-broad fix — exempting any LINE that carries an import preamble, rather
# than removing just the citation it wraps — still passes a fixture whose
# duplicated prose sits on a separate line, and would ship a check that silently
# stopped detecting restatement. Here the exemption and the restatement occupy
# one line, so excusing too much is caught.
SQ3="$TMP/q3"
build_single "$SQ3"
cat >"$SQ3/docs/design/CONTEXT.typ" <<'EOF'
#let terms = (
  (slug: "term-drift", title: [Drift],
   body: [A gap opens up between the two sides of the repository.
      The layer and the system disagree about what was actually built (#{ import "../refs.typ": adr; adr(1) }).],
  ),
  (slug: "term-work-order", title: [Work Order],
   body: [A brief handed to a coding agent, carrying its own context.
      The layer and the system disagree about what was actually built (#{ import "../refs.typ": adr; adr(1) }).],
  ),
)
EOF
assert_exit 1 "genuinely restated prose is still a violation" -- "$CHECK" "$SQ3"
assert_contains "duplicate prose" "report still flags real restatement"
assert_contains "The layer and the system disagree about what was actually built" \
  "report quotes the genuinely duplicated sentence"

# --- Scenario (r): gitignored broken layer is pruned -> exit 0 ----------------
# When the target root is a git repo, gitignored trees are not part of the
# system: a broken design layer inside one must not surface. (Every other
# fixture is a plain directory, proving the non-git full-scan fallback.)
SR="$TMP/r"
build_single "$SR"
git -C "$SR" init -q
printf 'scratch/\n' >"$SR/.gitignore"
mkdir -p "$SR/scratch/sub"
cat >"$SR/scratch/design.typ" <<'EOF'
#let title = [Scratch design]
#let body = [
  #section(title: "00 Foundation")[
    A dangling design-ish link: #link("CONTEXT.typ#term-nope")[nope].
  ]
]
EOF
cat >"$SR/scratch/CONTEXT.typ" <<'EOF'
#let terms = (
  (slug: "term-dup", title: [Dup], body: [First declaration.]),
  (slug: "term-dup", title: [Dup Again], body: [Second declaration of the id.]),
)
EOF
printf '%%PDF-1.7 stub\n' >"$SR/scratch/sub/design.pdf"
assert_exit 0 "gitignored broken layer is pruned from discovery" -- "$CHECK" "$SR"
assert_contains "layer-integrity OK" "gitignored-scratch run stays clean"
assert_not_contains "scratch/" "no violation mentions the gitignored tree"

# A gitignored MARKDOWN design doc is likewise pruned, so the migration
# refusal cannot be tripped by a tree that is not part of the system.
SR2="$TMP/r2"
build_single "$SR2"
git -C "$SR2" init -q
printf 'scratch/\n' >"$SR2/.gitignore"
mkdir -p "$SR2/scratch"
echo "# a legacy markdown design doc, gitignored" >"$SR2/scratch/design.md"
assert_exit 0 "a gitignored markdown design doc does not trip the refusal" -- "$CHECK" "$SR2"
assert_not_contains "authored in Markdown" "the pruned markdown file is never seen"

# --- Scenario (s): copy-installed sibling schema lookup -> exit 0 -------------
# The distribution contract (scripts_contract.distribution) copy-installs the
# checker and design-schema.json side by side in a target repo's scripts/.
# Prove the checker resolves that script-sibling copy: install both into a
# bare bin dir whose parent has NO schema/ directory, so only the sibling
# lookup can succeed.
SS="$TMP/s"
build_single "$SS"
INSTALL="$TMP/s-install/scripts"
mkdir -p "$INSTALL"
cp "$CHECK" "$INSTALL/layer-integrity"
cp "$HERE/../schema/design-schema.json" "$INSTALL/design-schema.json"
chmod +x "$INSTALL/layer-integrity"
assert_exit 0 "copy-installed checker resolves its script-sibling schema" -- \
  "$INSTALL/layer-integrity" "$SS"
assert_contains "layer-integrity OK" "sibling-schema run prints the OK summary"

# --- Scenario (t): generation debris in layer artifacts -> exit 1 -------------
# A generation-wrapper artifact line (a literal </content>, surrounding
# whitespace allowed) inside a layer artifact is writer leakage, never
# content. The patterns come from the schema
# (layer_layout.generation_debris_patterns), never from the script. The
# artifact set spans BOTH notations: a markdown ADR, a markdown COVERAGE.md,
# and a Typst design document.
ST="$TMP/t"
build_single "$ST"
printf '</content>\n' >>"$ST/docs/adr/0001-first-decision.md"
cat >"$ST/docs/COVERAGE.md" <<'EOF'
# Coverage

| Part | Status   |
| ---- | -------- |
| core | captured |

  </content>
EOF
assert_exit 1 "generation debris in layer artifacts is a violation" -- "$CHECK" "$ST"
assert_contains "generation debris" "report flags the debris line"
assert_contains "0001-first-decision.md" "report names the ADR carrying debris"
assert_contains "COVERAGE.md" "report catches whitespace-surrounded debris in COVERAGE.md"

ST2="$TMP/t2"
build_single "$ST2"
printf '</content>\n' >>"$ST2/docs/design/design.typ"
assert_exit 1 "generation debris in a design.typ is a violation" -- "$CHECK" "$ST2"
assert_contains "generation debris" "report flags debris in the Typst design doc"
assert_contains "docs/design/design.typ" "report names the design doc carrying debris"

# --- Scenario (u): debris shape inside a fenced code block -> exit 0 ----------
# An example of the wrapper line inside a fence is documentation, not leakage.
# The exemption is a MARKDOWN mechanism — fence tracking belongs to the
# markdown indexer — so it is asserted of a markdown layer artifact, which is
# where a fenced example now lives.
SU="$TMP/u"
build_single "$SU"
cat >"$SU/docs/COVERAGE.md" <<'EOF'
# Coverage

| Part | Status   |
| ---- | -------- |
| core | captured |

The wrapper line, shown as an example rather than leaked:

```text
</content>
```
EOF
assert_exit 0 "a fenced </content> example is not debris" -- "$CHECK" "$SU"
assert_not_contains "generation debris" "no debris reported for the fenced example"

# --- Scenario (v): layer files colocated in a source dir -> exit 1 ------------
# The layer lives entirely under docs/ (schema layer_layout.homing): a
# context's design.typ/CONTEXT.typ sitting inside a source directory is a
# mishomed stray, however internally well-formed.
SV="$TMP/v"
build_single "$SV"
mkdir -p "$SV/src/alpha"
cat >"$SV/src/alpha/CONTEXT.typ" <<'EOF'
#let terms = (
  (slug: "term-alpha-thing", title: [Alpha Thing],
   body: [The one thing alpha owns.]),
)
EOF
cat >"$SV/src/alpha/design.typ" <<'EOF'
#let title = [Alpha design]
#let body = [
  #section(title: "00 Foundation")[
    Alpha is built around the #term("term-alpha-thing") and nothing else.
  ]
]
EOF
assert_exit 1 "colocated layer files are mishomed" -- "$CHECK" "$SV"
assert_contains "mishomed layer artifact" "report flags the mishomed files"
assert_contains "src/alpha/CONTEXT.typ" "report names the colocated glossary"
assert_contains "src/alpha/design.typ" "report names the colocated design doc"

# --- Scenario (w): CONTEXT-MAP.md at repo root -> exit 1 ----------------------
# The map's declared home is docs/CONTEXT-MAP.md; a root-level map (the
# pre-v3 layout) is both mishomed and, with 2+ contexts, missing from its
# home — the loud migration signal.
SW="$TMP/w"
build_multi "$SW"
mv "$SW/docs/CONTEXT-MAP.md" "$SW/CONTEXT-MAP.md"
assert_exit 1 "root-level context map is mishomed" -- "$CHECK" "$SW"
assert_contains "mishomed layer artifact" "report flags the mishomed map"
assert_contains "missing context map" "report also flags the absent homed map"

# --- Scenario (x): staleness advisory fires past the threshold -> exit 0 ------
# Advisory, never a check: a repo that moved threshold+ commits since the
# layer last changed gets one advisory line and a clean exit. The threshold
# comes from the schema; a lowered-threshold schema copy keeps the fixture
# small.
SX="$TMP/x"
build_single "$SX"
git -C "$SX" init -q
git -C "$SX" -c user.email=t@t -c user.name=t add -A
git -C "$SX" -c user.email=t@t -c user.name=t commit -qm "layer"
for i in 1 2 3; do
  git -C "$SX" -c user.email=t@t -c user.name=t commit -qm "system move $i" --allow-empty
done
LOWERED="$TMP/schema-threshold-3.json"
python3 -c '
import json, sys
s = json.load(open(sys.argv[1]))
s["layer_layout"]["staleness_advisory"]["threshold_commits"] = 3
json.dump(s, open(sys.argv[2], "w"))' "$HERE/../schema/design-schema.json" "$LOWERED"
assert_exit 0 "staleness advisory keeps the exit clean" -- \
  env DESIGN_SCHEMA="$LOWERED" "$CHECK" "$SX"
assert_contains "advisory: 3 commit(s) since the design layer last changed" \
  "advisory names the commit count"

# --- Scenario (y): advisory silent under threshold / without the key ----------
SY="$TMP/y"
build_single "$SY"
git -C "$SY" init -q
git -C "$SY" -c user.email=t@t -c user.name=t add -A
git -C "$SY" -c user.email=t@t -c user.name=t commit -qm "layer"
git -C "$SY" -c user.email=t@t -c user.name=t commit -qm "one move" --allow-empty
assert_exit 0 "under-threshold repo stays clean" -- \
  env DESIGN_SCHEMA="$LOWERED" "$CHECK" "$SY"
assert_not_contains "advisory:" "no advisory under the threshold"
NOKEY="$TMP/schema-no-advisory.json"
python3 -c '
import json, sys
s = json.load(open(sys.argv[1]))
del s["layer_layout"]["staleness_advisory"]
json.dump(s, open(sys.argv[2], "w"))' "$HERE/../schema/design-schema.json" "$NOKEY"
assert_exit 0 "pre-advisory schema copy is tolerated" -- \
  env DESIGN_SCHEMA="$NOKEY" "$CHECK" "$SX"
assert_not_contains "advisory:" "no advisory without the schema key"

# --- Scenario (z): mermaid click targets are design-ish links ----------------
# A `click NODE "dest"` inside a ```mermaid fence navigates like any link; a
# dangling one must fail even though it lives in a code fence (which the plain
# link extractor drops). A resolving click stays clean. Click extraction is a
# MARKDOWN mechanism, so it is asserted of the markdown layer artifact that
# carries diagrams — a design document authors its diagrams in Typst instead.
SZ="$TMP/z"
build_single "$SZ"
cat >"$SZ/docs/COVERAGE.md" <<'EOF'
# Coverage

```mermaid
graph TD
    A["drift"]
    click A "design/CONTEXT.typ#term-drift"
```
EOF
assert_exit 0 "resolving mermaid click target stays clean" -- "$CHECK" "$SZ"
assert_contains "layer-integrity OK" "resolving-click run stays clean"

SZ2="$TMP/z2"
build_single "$SZ2"
cat >"$SZ2/docs/COVERAGE.md" <<'EOF'
# Coverage

```mermaid
graph TD
    A["gone"]
    click A "../gone/design.typ"
```
EOF
assert_exit 1 "dangling mermaid click target is a violation" -- "$CHECK" "$SZ2"
assert_contains "../gone/design.typ" "click-target violation names the destination"

# --- Scenario (aa): an invariant carries no pointer to its enforcer ---------
# `script=` is gone. It named the mechanism holding a property, but resolution
# only ever proved a name existed — never that the named thing checked
# anything — and it had to be kept current by hand. Which check holds a
# property is the gate's own job to find, so the attribute was removed rather
# than made resolvable. `enforcement` stays as the honest label for the KIND of
# enforcement, and an invariant declaring it is legal with nothing else.
SAA="$TMP/aa"
build_single "$SAA"
cat >>"$SAA/docs/design/design.typ" <<'EOF'
#section(title: "02 Invariants")[
  #invariant(title: "Held by a mechanism", enforcement: "mechanism")[
    The property is checked; which check holds it is not declared here.
  ]
]
EOF
assert_exit 0 "an enforcement=mechanism invariant needs no enforcer pointer" \
  -- "$CHECK" "$SAA"

# --- Scenario (cov): COVERAGE.md's own citations resolve ----------------------
# The coverage map cites terms and design sections like any other entry point.
# It was once indexed but never link-checked, so an invented term anchor passed
# clean here while the identical break inside a design document failed — the
# silent hole the map exists to close. COVERAGE.md stays MARKDOWN, and its
# links now point at the Typst glossary.
SCOV="$TMP/cov"
build_single "$SCOV"
cat >"$SCOV/docs/COVERAGE.md" <<'EOF'
# Coverage

| Part | Status | Note |
| ---- | ------ | ---- |
| the engine | captured | Described as [drift](design/CONTEXT.typ#term-no-such-term). |
EOF
assert_exit 1 "a dangling term anchor in COVERAGE.md is a violation" -- "$CHECK" "$SCOV"
assert_contains "term-no-such-term" "the violation names the missing term"

# The same map citing a term that DOES exist resolves clean.
SCOVB="$TMP/covb"
build_single "$SCOVB"
cat >"$SCOVB/docs/COVERAGE.md" <<'EOF'
# Coverage

| Part | Status | Note |
| ---- | ------ | ---- |
| the engine | captured | Described as [drift](design/CONTEXT.typ#term-drift). |
EOF
assert_exit 0 "a resolving term anchor in COVERAGE.md is clean" -- "$CHECK" "$SCOVB"

# --- Scenario (adr-call): an ADR citation is a NUMBER -------------------------
# The Typst notation cites a decision as `#adr(N)`, resolved against the ADR
# filenames on disk, so a number naming no decision is caught at the citing
# line rather than surfacing as a dead link inside a rendered document nobody
# re-reads.
SADR="$TMP/adr-call"
build_single "$SADR"
cat >"$SADR/docs/design/design.typ" <<'EOF'
#let title = [Design]
#let body = [
  #section(title: "00 Foundation")[
    The ledger holds an argument that was never written, #adr(999).
  ]
]
EOF
assert_exit 1 "adr(N) naming no ADR is a violation" -- "$CHECK" "$SADR"
assert_contains "dangling ADR citation" "report flags the dangling ADR call"
assert_contains "adr(999)" "report names the offending ADR number"

# --- A TERM AND A CONTEXT CITATION RESOLVE, exactly as an ADR citation does ---
# The ADR call was enforced and the other two notations were not, because a
# markdown citation is a LINK that the schema's marker list recognises while a
# Typst citation is a CALL carrying a bare name that matches no marker. Every
# term() and ctx() therefore fell out of the link check through the branch
# that drops a non-design-ish destination: measured on a real layer, 91 ADR
# citations enforced against 433 term and 46 context citations checked by
# nothing, with an invented slug passing the full gate green.
STYPTERM="$TMP/typst-dangling-term"
build_single "$STYPTERM"
cat >"$STYPTERM/docs/design/design.typ" <<'EOF'
#let title = [Design]
#let body = [
  #section(title: "00 Foundation")[
    The system tracks #term("term-never-declared") between the artifacts.
  ]
]
EOF
assert_exit 1 "term() naming no declared term is a violation" -- "$CHECK" "$STYPTERM"
assert_contains "dangling term citation" "report flags the dangling term call"
assert_contains "term-never-declared" "report names the offending slug"

STYPCTX="$TMP/typst-dangling-ctx"
build_multi "$STYPCTX"
cat >"$STYPCTX/docs/design/alpha/design.typ" <<'EOF'
#let title = [Alpha design]
#let body = [
  #section(title: "00 Foundation")[
    Alpha leans on #ctx("no-such-context") for the rest of its behavior.
  ]
]
EOF
assert_exit 1 "ctx() naming no context is a violation" -- "$CHECK" "$STYPCTX"
assert_contains "dangling context citation" "report flags the dangling context call"
assert_contains "no-such-context" "report names the offending context"

# A RESOLVING citation of each kind stays clean, so the check is proved to
# discriminate rather than to reject every citation it sees.
STYPOK="$TMP/typst-resolving-cites"
build_multi "$STYPOK"
assert_exit 0 "resolving term() and ctx() citations are clean" -- "$CHECK" "$STYPOK"
# THE COUNT IS REPORTED, which is what makes a vacuous pass visible. The same
# clean line was printed whether the check resolved every reference or none.
assert_contains "resolved" "the summary reports what the check actually matched"
assert_contains "term citations" "the summary counts the term citations resolved"
assert_contains "context citations" "the summary counts the context citations resolved"
assert_contains "root context index" "the summary counts the contexts the root indexes"

# --- Scenario (multi): the three markdown-shaped checks stay quiet ------------
# Three checks were written when markdown was the only notation, and each
# asserted a MARKDOWN BASENAME or a MARKDOWN REFERENCE FORM. Against a
# well-formed Typst layer all three fired, and every one named a file the
# author never had or a link the notation does not use — the shape that trains
# a reader to ignore the checker. The multi fixture is well-formed and must be
# clean; the assertions below name each of the three by its message.
STYPM="$TMP/typst-multi"
build_multi "$STYPM"
assert_exit 0 "clean multi-context Typst layer" -- "$CHECK" "$STYPM"
# The root is design.typ; looking only for design.md reports it absent.
assert_not_contains "missing root design doc" "a Typst root is found at its own basename"
# The map indexes both glossaries, at the basename the notation uses.
assert_not_contains "unmapped glossary" "a map linking CONTEXT.typ maps its contexts"
# A repeated call line is syntax, not a restated fact.
assert_not_contains "duplicate prose" "a repeated call line is not a duplicate"
# The root names its contexts by call, and both are named.
assert_not_contains "unindexed domain design doc" "a root naming every context is clean"

# --- Scenario (md): a layer still authored in markdown is REFUSED -> exit 2 ---
# Markdown authoring was removed, so every check reads a notation these files
# are not in: the indexer would find zero terms, zero citations and zero
# sections, and each check would report clean over an empty set. That is the
# vacuity the gate's own anti-vacuity guard exists to prevent, so the condition
# is caught by name rather than downstream where it reads as a passing layer.
SMD="$TMP/md-only"
mkdir -p "$SMD/docs/design" "$SMD/docs/adr"
cat >"$SMD/docs/design/CONTEXT.md" <<'EOF'
# Glossary

### Drift {#term-drift}

The gap between the design layer and the implementation.
EOF
cat >"$SMD/docs/design/design.md" <<'EOF'
# Design

## 00 Foundation

The system tracks [drift](CONTEXT.md#term-drift) between artifacts.
EOF
assert_exit 2 "a markdown-authored layer is refused" -- "$CHECK" "$SMD"
assert_contains "authored in Markdown" "report says the layer is markdown-authored"
assert_contains "framework now authors Typst" "report names the notation that replaced it"
assert_contains "markdown: docs/design/design.md" "report names the markdown design doc"
assert_contains "markdown: docs/design/CONTEXT.md" "report names the markdown glossary"
assert_contains "migration 0008" "report points at the migration"
# A refusal is an ERROR, never a violation report: no check ran, so nothing may
# read as having been checked.
assert_not_contains "layer-integrity OK" "a refused layer prints no OK summary"

# A HALF-MIGRATED layer hits the same refusal. Every check would otherwise run
# against whichever half it discovered, report clean, and say nothing about the
# other — and a half-migrated layer is exactly when that arises.
SMIX="$TMP/md-mixed"
build_single "$SMIX"
mkdir -p "$SMIX/docs/design/alpha"
echo "# a stray markdown context" >"$SMIX/docs/design/alpha/design.md"
assert_exit 2 "a half-migrated markdown/Typst layer is refused" -- "$CHECK" "$SMIX"
assert_contains "authored in Markdown" "the half-migrated layer hits the same refusal"
assert_contains "docs/design/alpha/design.md" "report names the markdown leftover"

# A markdown CONTEXT.md alone — the glossary half of the migration — is refused
# on its own, so neither half can be left behind unnoticed.
SMIX2="$TMP/md-mixed-glossary"
build_single "$SMIX2"
mkdir -p "$SMIX2/docs/design/beta"
cat >"$SMIX2/docs/design/beta/CONTEXT.md" <<'EOF'
# Beta

### Beta Thing {#term-beta-thing}

The one thing beta owns.
EOF
assert_exit 2 "a leftover markdown glossary is refused" -- "$CHECK" "$SMIX2"
assert_contains "docs/design/beta/CONTEXT.md" "report names the markdown glossary leftover"

# --- Scenario (perf): a run finishes well under a wall-clock ceiling ----------
# The parse-once invariant: the checker reads each layer file ONCE into an
# index and answers every check as a lookup against it. The shape it replaced
# spawned a fresh python interpreter per regex match and re-read each target
# file per reference into it, which cost tens of seconds on a real layer. The
# ceiling is deliberately generous — far above real cost on slow CI hardware,
# far below the cost of a return to per-match spawning.
CEILING=10
SPERF="$TMP/perf"
build_multi "$SPERF"
perf_start=$(date +%s)
assert_exit 0 "parse-once run stays clean" -- "$CHECK" "$SPERF"
perf_elapsed=$(($(date +%s) - perf_start))
if [ "$perf_elapsed" -lt "$CEILING" ]; then
  echo "PASS: run completes under the ${CEILING}s ceiling (${perf_elapsed}s)"
  pass=$((pass + 1))
else
  echo "FAIL: run took ${perf_elapsed}s, over the ${CEILING}s parse-once ceiling"
  fail=$((fail + 1))
fi

# --- Summary ------------------------------------------------------------------
echo
echo "----------------------------------------"
echo "PASS: $pass  FAIL: $fail"
if [ "$fail" -ne 0 ]; then
  echo "SELF-TEST FAILED"
  exit 1
fi
echo "SELF-TEST PASSED"
