// THE SEMANTIC TOKEN TABLE — the framework owns the semantic look.
//
// WHY THE HUES LIVE HERE AND NOT IN THE SCHEMA. A hue is an APPEARANCE, not a
// decision: thirteen fixed constants, mostly one repeated six-colour palette.
// The schema declares the VOCABULARY each table is keyed by — the lens members,
// the tints, the enforcement values, the entity kinds and lifecycles, the
// provenances, the coverage statuses, the pending kinds. What colour a member
// draws in is this library's own presentation choice.
//
// THE TOTALITY GUARANTEE SURVIVES THAT SPLIT, and it is the reason the two
// halves cannot quietly disagree. Every table below is paired against the
// schema-derived key list it must cover, and `_assert-total` panics NAMING the
// member with no colour. A vocabulary member added to the schema and forgotten
// here fails the compile rather than rendering an untinted card, which is what
// `.at(k)` on a missing key would otherwise do far away from the cause.
#import "schema.typ": *

// The renderer's text surfaces share four sizes. Primary prose uses BODY;
// headings use TITLE; dense supporting copy uses COMPACT; labels and furniture
// use META. Keeping these values here prevents one block family from quietly
// becoming denser or louder than another.
#let RENDERER-TITLE = 10.2pt
#let RENDERER-BODY = 8.4pt
#let RENDERER-COMPACT = 7.8pt
#let RENDERER-META = 6.7pt

// The neutral foundation is shared as deliberately as the semantic hues. It
// gives every block family one paper, ink, secondary voice, keyline, and quiet
// surface. Semantic colour then answers "what kind?" or "who owns this?"
// instead of also having to invent depth, borders, and typography each time.
#let PAPER = rgb("#fbfbf8")
#let INK = rgb("#172126")
#let MUTED = rgb("#58656b")
#let FAINT = rgb("#7b868b")
#let HAIRLINE = rgb("#d7ddda")
#let SURFACE = rgb("#f2f5f3")
#let SURFACE-STRONG = rgb("#e8eeeb")

// A vocabulary member with no declared colour is an error, raised at the point
// where the table is built rather than at the first card that reads it.
#let _assert-total(name, table, keys) = {
  keys.fold(
    (:),
    (acc, k) => {
      if k not in table {
        _schema-fail(
          "no colour token declared for " + name + " member " + repr(k)
            + " — every member of the declared vocabulary carries a colour, "
            + "so add it to " + name + " in lib/tokens.typ",
        )
      }
      acc + ((k): rgb(table.at(k)))
    },
  )
}

#let _LENS-HUES = (
  "modeling": "#6952a3",
  "depth": "#2870a6",
  "composition": "#087f79",
  "state": "#a86408",
  "invariants": "#ad3451",
  "robustness": "#5f6b73",
)

#let _TINT-HUES = (
  "teal": "#087f79",
  "violet": "#6952a3",
  "amber": "#a86408",
  "blue": "#2870a6",
  "rose": "#ad3451",
  "slate": "#5f6b73",
)

// enforcement reads as a STRENGTH scale: how much of the claim is actually
// checked. mechanism (a check decides the whole property) -> partial (it checks
// a mechanical shadow) -> convention (held by review).
#let _ENFORCEMENT-HUES = (
  "mechanism": "#087f79",
  "partial": "#a86408",
  "convention": "#5f6b73",
)

// ---- the entity census's three colour axes --------------------------------
// A census card carries three independent facts, and a reader must separate
// them BEFORE reading the words. Each maps onto the SHARED tint vocabulary
// rather than minting a new palette: these are reading aids on the tints, not
// new ownership axes.
//
// KIND is what the thing IS. Four kinds, four distinct tints — deliberately NOT
// reusing the foundation's goal/no-goal/invariant assignments as a set, because
// this is a different axis; it shares the tint VOCABULARY, not its meanings.
#let _ENTITY-KIND-HUES = (
  "aggregate": "#6952a3",
  "entity": "#2870a6",
  "value-object": "#087f79",
  "event": "#a86408",
)

// LIFECYCLE is the second axis on the same card, so it must stay legible
// against every kind fill rather than against one.
#let _ENTITY-LIFECYCLE-HUES = (
  "stateful": "#ad3451",
  "append-only": "#087f79",
  "immutable": "#5f6b73",
)

// PROVENANCE is how an attribute's fact arises, and the three values carry
// different weight for a reader auditing a census. `authored` is the one that
// DRIFTS, so it takes amber, the warning-ward tone. `derived` takes teal — the
// value that cannot desynchronize. `observed` takes slate, the quiet ground,
// because it describes reality without authorizing anything.
#let _PROVENANCE-HUES = (
  "authored": "#a86408",
  "derived": "#087f79",
  "observed": "#5f6b73",
)

// COVERAGE is the breadth axis: `captured` is the state the layer is working
// toward, so it takes teal, the settled tone. `standard` is grey because it is
// a part deliberately left to a convention and needs no attention. Anything
// else — `out-of-scope` — takes the warning tone, since a reader auditing
// breadth is looking for exactly the rows the layer decided not to cover.
#let _COVERAGE-HUES = (
  "captured": "#087f79",
  "standard": "#6f7a80",
  "out-of-scope": "#a8492a",
)

// PENDING kind colours the ledger's time axis, so the four kinds are told apart
// at a glance rather than by reading each entry's badge.
#let _PENDING-HUES = (
  "build": "#2f5f8f",
  "verify": "#087f79",
  "foundation": "#5a4fa0",
  "ruling": "#8a6a1f",
)

#let LENS-COLOR = _assert-total("LENS-COLOR", _LENS-HUES, LENSES)
#let TINT-COLOR = _assert-total("TINT-COLOR", _TINT-HUES, TINTS)

// Context ownership is one shared palette registry. The aggregate populates
// it from each context module's optional `accent` binding before any chapter
// body or glossary entry renders. Unknown and unassigned owners stay neutral.
#let CONTEXT-ACCENTS = state("design-context-accents", (:))
#let TERM-OWNERS = state("design-term-owners", (:))

#let _context-tint(name) = {
  let accent = CONTEXT-ACCENTS.final().at(name, default: none)
  if accent == none { none } else { TINT-COLOR.at(accent) }
}
#let ENFORCEMENT-COLOR = _assert-total(
  "ENFORCEMENT-COLOR",
  _ENFORCEMENT-HUES,
  ENFORCEMENTS,
)
#let ENTITY-KIND-COLOR = _assert-total(
  "ENTITY-KIND-COLOR",
  _ENTITY-KIND-HUES,
  ENTITY-KINDS,
)
#let ENTITY-LIFECYCLE-COLOR = _assert-total(
  "ENTITY-LIFECYCLE-COLOR",
  _ENTITY-LIFECYCLE-HUES,
  ENTITY-LIFECYCLES,
)
#let PROVENANCE-COLOR = _assert-total(
  "PROVENANCE-COLOR",
  _PROVENANCE-HUES,
  PROVENANCES,
)
#let COVERAGE-COLOR = _assert-total(
  "COVERAGE-COLOR",
  _COVERAGE-HUES,
  COVERAGE-STATUSES,
)
#let PENDING-COLOR = _assert-total("PENDING-COLOR", _PENDING-HUES, PENDING-KINDS)

// KIND-COLOR is keyed by BLOCK KIND, which is an open set rather than a closed
// enum — every reader of it uses `.at(kind, default: ...)`, so a kind with no
// entry falls back to a neutral tone instead of failing. There is no key list
// to be total against, so this one table is not asserted.
#let _KIND-HUES = (
  "behavior": "#a86408",
  "entity": "#6952a3",
  "goal": "#2870a6",
  "info": "#2870a6",
  "invariant": "#6952a3",
  "no-goal": "#ad3451",
  "pending": "#a86408",
  "principle": "#087f79",
  "warning": "#a86408",
  "formula": "#6952a3",
  "pseudocode": "#187b78",
)
#let KIND-COLOR = _KIND-HUES.pairs().fold(
  (:),
  (acc, p) => acc + ((p.at(0)): rgb(p.at(1))),
)
