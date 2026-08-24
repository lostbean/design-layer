// ---- the entity census card, its attributes and its relationships -------
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *
#import "furniture.typ": *

// The two groups inside a card label THEMSELVES, from the run of clauses rather
// than from a wrapper block the author would have to write. The schema fixes the
// body order — attribute clauses, then relates clauses — so the first clause of
// each run emits its heading and the rest emit nothing. The authored source is
// unchanged by this.
#let _census-head(label) = block(inset: (top: 4pt, bottom: 3pt),
  text(size: 6pt, fill: luma(125), weight: "bold", tracking: 1pt, upper(label)))
#let _census-group = state("census-group", none)
#let _census-enter(label) = {
  context {
    if _census-group.get() != label { _census-head(label) }
  }
  _census-group.update(label)
}

// A census card carries THREE independent facts, and the reader separates them
// before reading a word: what the thing IS (kind), how it changes over time
// (lifecycle), and which domain owns it. Each is a typed tag with its own tone,
// so the card is scannable down a column rather than a paragraph to parse.
//
// The card also keeps its two GROUPS visibly apart. Attributes are what the
// entity is made of; relationships are how it sits against other entities.
// Rendering both as identical indented rows — which is what a generic statement
// body does — loses the distinction that makes a census a model.
#let entity(title: none, kind: none, owner: none, lifecycle: none,
            domain: none, tint: none, ..a, body) = {
  // The census's four classifying facts are REQUIRED by the block's own
  // declaration: what the thing is, who owns it, how it changes, and which
  // domain it belongs to. A card missing one renders as a card that simply
  // does not answer that question, which reads as "not applicable" rather
  // than "never stated". `tint` stays optional — it is presentation.
  _need("entity", "title", title)
  _need("entity", "kind", kind)
  _need("entity", "owner", owner)
  _need("entity", "lifecycle", lifecycle)
  _need("entity", "domain", domain)
  _enum("entity", "kind", kind, ENTITY-KINDS)
  _enum("entity", "lifecycle", lifecycle, ENTITY-LIFECYCLES)
  _enum("entity", "tint", tint, TINTS)
  let kc = if kind != none { ENTITY-KIND-COLOR.at(kind) } else { luma(120) }
  let lc = if lifecycle != none { ENTITY-LIFECYCLE-COLOR.at(lifecycle) } else { none }
  block(width: 100%, breakable: false, radius: 3pt, inset: 0pt, clip: true,
        stroke: 0.6pt + kc.lighten(55%),
    [
      // the head: the name, then the typed tags that classify it
      #block(width: 100%, fill: kc.lighten(92%), inset: (x: 9pt, y: 7pt),
        [
          #text(size: 10pt, weight: "bold", fill: kc.darken(28%), title)
          #h(6pt)
          #chip(kind, tone: kc)
          #if lc != none { [#h(3pt) #chip(lifecycle, tone: lc)] }
          #if domain != none { [#h(3pt) #chip(domain)] }
          #if owner != none { [#h(3pt) #chip("owned by " + owner)] }
        ])
      // The two groups label themselves — see _census-enter below. The state is
      // cleared as the card opens so every card starts a fresh run.
      #_census-group.update(none)
      #block(width: 100%, inset: (x: 9pt, y: 6pt), body)
    ])
  v(0.5em)
}

// The two groups label THEMSELVES, from the clause metadata rather than from a
// wrapper block the author would have to write. The schema fixes the body order
// — attribute clauses, then relates clauses — and each clause emits a hidden
// marker; the card's show rule turns the FIRST marker of each run into a
// heading. So the two lists read as two lists, and the authored source is
// unchanged.
// An attribute's keyword IS its provenance, so the keyword carries the tone.
#let attribute(provenance: none, ..a, body) = {
  // Provenance is the load-bearing field of the census: it says whether the
  // value was authored, derived, or observed, and an attribute with no
  // provenance makes no claim about how it arises. Required, not defaulted.
  _need("attribute", "provenance", provenance)
  _enum("attribute", "provenance", provenance, PROVENANCES)
  _census-enter("attributes")
  let c = if provenance != none { PROVENANCE-COLOR.at(provenance) } else { none }
  block(width: 100%, inset: (left: 2pt, y: 2.5pt),
    grid(columns: (58pt, 1fr), column-gutter: 7pt, align: (right + top, left),
      chip(provenance, tone: c), body))
}

// A relationship's cardinality is the shape of the edge, so it is set in a
// monospaced capsule: `1 : 0..n` scans down the column as a column of shapes.
#let CARDINALITY = ("1", "0..1", "n", "0..n")

#let relates(cardinality: none, ..a, body) = {
  _census-enter("relationships")
  // The cardinality is DECLARED rather than written into the body precisely so
  // it can be checked: the census states the shape of every relation uniformly
  // instead of burying it in a sentence, and a shape nothing validates is a
  // claim the reader has to take on trust.
  _need("relates", "cardinality", cardinality)
  // The SHAPE of a stated cardinality is guidance: an unreadable shape still
  // renders in its capsule as the author typed it, so the reader sees exactly
  // what was written and the library says what it expected instead.
  let sides = if cardinality == none { () } else {
    cardinality.split(":").map(p => p.trim())
  }
  if cardinality != none and sides.len() != 2 {
    _guide("relates.cardinality-shape",
           "relates cardinality " + repr(cardinality) +
           " is expected to be written `<this> : <other>`, for example " +
           repr("1 : 0..n"))
  } else {
    for side in sides {
      if side not in CARDINALITY {
        _guide("relates.cardinality-side",
               "relates cardinality side " + repr(side) +
               " is expected to be one of " + repr(CARDINALITY))
      }
    }
  }
  block(width: 100%, inset: (left: 2pt, y: 2.5pt),
    grid(columns: (58pt, 1fr), column-gutter: 7pt, align: (right + top, left),
      box(inset: (x: 4pt, y: 1.5pt), radius: 3pt, baseline: 2pt,
          fill: TINT-COLOR.at("blue").lighten(90%),
          stroke: 0.5pt + TINT-COLOR.at("blue").lighten(55%),
          text(size: 6.5pt, weight: "bold", font: "DejaVu Sans Mono",
               fill: TINT-COLOR.at("blue").darken(25%),
               if cardinality != none { cardinality } else { "—" })),
      body))
}

