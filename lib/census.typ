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
#let _census-head(label) = block(sticky: true, inset: (top: 4pt, bottom: 3pt),
  text(size: 6pt, fill: luma(125), weight: "bold", tracking: 1pt, upper(label)))
#let _census-group = state("census-group", none)
#let _state-link-owner = state("state-link-owner", none)
#let _state-link-trail = state("state-link-trail", ())

#let _note-state-link(entry) = _state-link-trail.update(t => t + (entry,))

#let _note-state-type(id, title, variants) = {
  _note-state-link((kind: "type", id: id, title: title, variants: variants))
}

#let _note-state-machine(id, subject, state-field, state-type, states) = {
  _note-state-link((kind: "machine", id: id, subject: subject,
                    field: state-field, state-type: state-type, states: states))
}

#let _one-by-id(entries, id) = {
  let found = entries.filter(e => e.id == id)
  if found.len() == 0 { none } else { found.first() }
}

#let _reject-duplicate(entries, noun, scoped: false) = {
  let seen = ()
  for e in entries {
    let key = if scoped { e.owner + "\u{0}" + e.id } else { e.id }
    if seen.contains(key) {
      panic("state links: duplicate " + noun + " id " + repr(e.id)
            + if scoped { " within entity " + repr(e.owner) } else { "" })
    }
    seen.push(key)
  }
}

// The aggregate places this once after every context body. The trail contains
// rendered calls rather than parsed source, so aliases and helper functions
// cannot hide a state link from validation.
#let assert-state-links = context {
  let trail = _state-link-trail.get()
  let entities = trail.filter(e => e.kind == "entity")
  let types = trail.filter(e => e.kind == "type")
  let machines = trail.filter(e => e.kind == "machine")
  let fields = trail.filter(e => e.kind == "field")

  _reject-duplicate(entities, "entity")
  _reject-duplicate(types, "state type")
  _reject-duplicate(machines, "state machine")
  _reject-duplicate(fields, "attribute", scoped: true)

  for field in fields.filter(f => f.linked) {
    let typ = _one-by-id(types, field.state-type)
    let machine = _one-by-id(machines, field.state-machine)
    if typ == none {
      panic("state links: attribute " + repr(field.id) + " on entity "
            + repr(field.owner) + " names unknown state type "
            + repr(field.state-type))
    }
    if machine == none {
      panic("state links: attribute " + repr(field.id) + " on entity "
            + repr(field.owner) + " names unknown state machine "
            + repr(field.state-machine))
    }
    if machine.subject != field.owner {
      panic("state links: state machine " + repr(machine.id) + " subject "
            + repr(machine.subject) + " does not own attribute "
            + repr(field.id) + " on entity " + repr(field.owner))
    }
    if machine.field != field.id {
      panic("state links: state machine " + repr(machine.id) + " state-field "
            + repr(machine.field) + " does not match attribute "
            + repr(field.id))
    }
    if machine.state-type != field.state-type {
      panic("state links: attribute " + repr(field.id) + " state-type "
            + repr(field.state-type) + " does not match state machine "
            + repr(machine.id) + " state-type " + repr(machine.state-type))
    }
  }

  for machine in machines {
    let entity = _one-by-id(entities, machine.subject)
    let typ = _one-by-id(types, machine.state-type)
    let matching-fields = fields.filter(f => f.owner == machine.subject
                                         and f.id == machine.field)
    let field = if matching-fields.len() == 0 { none }
                else { matching-fields.first() }
    if entity == none {
      panic("state links: state machine " + repr(machine.id)
            + " names unknown subject entity " + repr(machine.subject))
    }
    if field == none {
      panic("state links: state machine " + repr(machine.id) + " state-field "
            + repr(machine.field) + " does not exist on subject "
            + repr(machine.subject))
    }
    if field.state-machine != machine.id {
      panic("state links: subject " + repr(machine.subject) + " state-field "
            + repr(machine.field) + " links state machine "
            + repr(field.state-machine) + ", not " + repr(machine.id))
    }
    if typ == none {
      panic("state links: state machine " + repr(machine.id)
            + " names unknown state type " + repr(machine.state-type))
    }
    let variants = typ.variants.dedup()
    let states = machine.states.dedup()
    if (variants.len() != states.len()
        or variants.any(v => not states.contains(v))) {
      panic("state links: state type " + repr(typ.id) + " variants "
            + repr(typ.variants) + " do not equal state machine "
            + repr(machine.id) + " states " + repr(machine.states))
    }
  }
}
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
#let entity(id: none, title: none, kind: none, owner: none, lifecycle: none,
            domain: none, tint: none, description: none, ..a, body) = {
  // The census's four classifying facts are REQUIRED by the block's own
  // declaration: what the thing is, who owns it, how it changes, and which
  // domain it belongs to. A card missing one renders as a card that simply
  // does not answer that question, which reads as "not applicable" rather
  // than "never stated". `tint` stays optional — it is presentation.
  _need("entity", "title", title)
  _need("entity", "description", description)
  _need("entity", "kind", kind)
  _need("entity", "owner", owner)
  _need("entity", "lifecycle", lifecycle)
  _need("entity", "domain", domain)
  _enum("entity", "kind", kind, ENTITY-KINDS)
  _enum("entity", "lifecycle", lifecycle, ENTITY-LIFECYCLES)
  _enum("entity", "tint", tint, TINTS)
  let kc = if kind != none { ENTITY-KIND-COLOR.at(kind) } else { luma(120) }
  let lc = if lifecycle != none { ENTITY-LIFECYCLE-COLOR.at(lifecycle) } else { none }
  let tc = if tint == none { none } else { TINT-COLOR.at(tint) }
  let frame = if tc == none { luma(190) } else { tc }
  if id != none { _note-state-link((kind: "entity", id: id)) }
  block(width: 100%, breakable: true, radius: 3pt, inset: 0pt,
        stroke: 0.6pt + frame.lighten(55%),
    [
      // the head: the name, then the typed tags that classify it
      #block(width: 100%, sticky: true, fill: kc.lighten(92%), inset: (x: 9pt, y: 7pt),
        [
          #text(size: 10pt, weight: "bold", fill: kc.darken(28%), title)
          #h(6pt)
          #chip(kind, tone: kc)
          #if lc != none { [#h(3pt) #chip(lifecycle, tone: lc)] }
          #if domain != none { [#h(3pt) #chip(domain, tone: tc)] }
          #if owner != none { [#h(3pt) #chip("owned by " + owner, tone: tc)] }
        ])
      // The two groups label themselves — see _census-enter below. The state is
      // cleared as the card opens so every card starts a fresh run.
      #_census-group.update(none)
      #_state-link-owner.update(id)
      #block(width: 100%, breakable: true, inset: (x: 9pt, y: 6pt), [
        #set par(justify: false)
        #if description != none { block(below: 6pt, sticky: true, description) }
        #body
      ])
      #_state-link-owner.update(none)
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
#let attribute(id: none, provenance: none, name: none, type: none,
               state-type: none, state-machine: none, ..a, body) = {
  // Provenance is the load-bearing field of the census: it says whether the
  // value was authored, derived, or observed, and an attribute with no
  // provenance makes no claim about how it arises. Required, not defaulted.
  _need("attribute", "name", name)
  _need("attribute", "type", type)
  _need("attribute", "provenance", provenance)
  _enum("attribute", "provenance", provenance, PROVENANCES)
  let link-values = (id, state-type, state-machine)
  let linked = link-values.any(v => v != none)
  if linked and link-values.any(v => v == none) {
    _fail("attribute", "state link requires id, state-type, and state-machine together")
  }
  _census-enter("attributes")
  let c = if provenance != none { PROVENANCE-COLOR.at(provenance) } else { none }
  context {
    let entity-id = _state-link-owner.get()
    if linked and entity-id == none {
      _fail("attribute", "linked attribute " + repr(id)
            + " is outside an identified entity")
    }
    if id != none and entity-id != none {
      _note-state-link((kind: "field", id: id, owner: entity-id,
                        linked: linked, state-type: state-type,
                        state-machine: state-machine))
    }
    block(width: 100%, inset: (left: 2pt, y: 2.5pt),
      grid(columns: (58pt, 1fr), column-gutter: 7pt, align: (right + top, left),
        chip(provenance, tone: c), [
          #set par(justify: false)
          #if name != none or type != none {
            block(below: 2pt, sticky: true, [
              #if name != none { text(weight: "bold", name) }
              #if name != none and type != none { [#h(5pt)·#h(5pt)] }
              #if type != none { text(fill: luma(90), type) }
              #if linked {
                [#h(6pt)#lnk(label("state-type-" + state-type), state-type)
                 #h(4pt)·#h(4pt)
                 #lnk(label("state-machine-" + state-machine), state-machine)]
              }
            ])
          }
          #body
        ]))
  }
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
      [
        #set par(justify: false)
        #body
      ]))
}
