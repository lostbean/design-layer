// ---- the native authoring surface: what a design.typ calls directly -----
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *
#import "furniture.typ": *
#import "packages.typ": *
#import "semantic.typ": *

// A design.typ calls these directly. The markdown router never emits them.

// Each altitude carries its own tint, so a diagram's altitude is legible
// before its caption is read. The ladder, its names, and its tints are all
// PROJECTED from the one schema.
//
// THE LADDER IS OPEN. ALTITUDES lists the NAMED rungs, not the legal ones —
// a design layer is a recursively self-similar tree that recurses until a
// unit passes the reproduction test, so its depth cannot be capped by a
// four-word vocabulary. Any `L<n>` for a positive integer n is legal.
// ALTITUDE-NAMES and ALT-TINT cover the named rungs; the two private
// resolvers below answer for every other rung, so no lookup can panic on a
// legal value.
//
// ALTITUDES, ALTITUDE-PATTERN, ALTITUDE-NAMES, ALT-TINT and ALT-TINT-CYCLE are
// all read from the one schema in `schema.typ` and reach this file through the
// wildcard import above, so the ladder is declared in exactly one place.

// The LEVEL NUMBER of an altitude, as an integer. `none` when the string is
// not a well-formed rung — which is how the validator tells a deeper level
// apart from a typo without a second parse.
#let _alt-level(value) = {
  if type(value) != str { return none }
  let m = value.matches(regex(ALTITUDE-PATTERN))
  if m.len() == 0 { return none }
  int(m.first().captures.first())
}

// A REQUIRED, OPEN altitude. Presence stays mandatory: a drawing whose
// altitude is unstated leaves a reader unable to tell which zoom level they
// are looking at, and that is the reason the label exists. Only the CLOSED
// SET relaxes — the shape is still checked, so `L0`, `L`, `X2`, `L2.5` and
// `"2"` are refused by name rather than drawn as an unreadable band.
// PRESENCE is guidance; a MALFORMED value stays fail-closed. An absent altitude
// leaves the badge unstated and the diagram still draws. A value like "L0" or
// "L2.5" is one the library cannot resolve to a level, a name, or a tint — it
// would have to invent the band, so it refuses instead.
#let _req-altitude(value) = {
  if value == none {
    _guide("diagram.altitude",
           "diagram altitude is unstated, so a reader cannot tell which zoom " +
           "level the drawing is at. Expected \"L<n>\" for a positive whole " +
           "number n — the named rungs are " + repr(ALTITUDES) + ", and a " +
           "deeper unit may declare a further one.")
  } else if _alt-level(value) == none {
    panic("diagram altitude=" + repr(value) + " is not a well-formed " +
          "altitude. An altitude is written \"L<n>\" for a positive whole " +
          "number n (for example " + repr(ALTITUDES) + "); the ladder is " +
          "open, so a level past the named rungs is legal, but L0, a bare " +
          "level number, and a fractional level are not.")
  }
}

// The NAME shown in the badge. A named rung reads as its name; a rung the
// schema does not name reads as its level number, because the badge already
// says ALTITUDE L5 and inventing a word for a level nobody named would put a
// term in the reader's head that appears nowhere else in the layer. The
// number is the honest answer: it says exactly what is known.
//
// PRIVATE, like the two resolvers below and above it. An author never calls
// this: `diagram-native` resolves the badge from the altitude the author
// already declared, so it carries the leading underscore that marks a helper
// exercised through its caller rather than demonstrated in the gallery.
// An UNSTATED altitude resolves to a neutral label rather than crashing: the
// presence rule is guidance now, so every resolver below has to be able to
// answer for an altitude the author did not write.
#let _alt-name(altitude) = {
  if altitude == none { return "unstated" }
  ALTITUDE-NAMES.at(altitude, default: "level " + str(_alt-level(altitude)))
}

// The TINT of the band. A named rung keeps the accent the schema declared for
// it. An unnamed rung indexes the declared accent list by its level number,
// which makes the colour a pure function of the level — the same altitude
// draws the same band on every render, and the band can only ever be an
// accent this layer already uses. Cycling is deliberate over running out:
// past the end of the accent list the ladder repeats colours rather than
// failing, because a level's colour is a reading aid, not an identifier.
#let _alt-tint(altitude) = {
  if altitude == none { return "slate" }
  ALT-TINT.at(altitude, default: ALT-TINT-CYCLE.at(
    calc.rem(_alt-level(altitude) - 1, ALT-TINT-CYCLE.len())))
}

// GUIDELINE helpers — sentence budgets. Only a plain string can be counted, so
// content carrying markup passes through; that is the honest limit of it.
#let _sentences(t) = t.matches(regex("[.!?](\\s|$)")).len()

#let _max-sentences(where, body, limit: 3) = {
  if type(body) == str and body != "" and _sentences(body) > limit {
    _guide("bullet.sentences",
           where + ": " + str(_sentences(body)) + " sentences exceeds the " +
           str(limit) + "-sentence bullet guideline. A new bullet begins at a " +
           "change of object, property, or processing step.")
  }
}

#let _max-lead(where, body, limit: 4) = {
  if type(body) == str and body != "" and _sentences(body) > limit {
    _guide("section.lead-sentences",
           where + ": a section lead holds about " + str(limit) +
           " sentences, found " + str(_sentences(body)) +
           ". Go deep in a section rather than in its intro.")
  }
}

// A required enum, split the same way every other field is: ABSENT is guidance,
// a value OUTSIDE the vocabulary is a hard failure. The library can render
// around a label nobody wrote; it cannot render a label it has no entry for.
#let _req-enum(field, value, allowed) = {
  if value == none {
    _guide("enum.missing",
           field + " is unstated — expected one of " + repr(allowed) + ".")
  } else if value not in allowed {
    panic(field + "=" + repr(value) + " must be one of " + repr(allowed))
  }
}

// THE SHARED DRAWING FRAME — the furniture every drawing block wears.
//
// A drawing is a tinted kind strip, an optional title, the drawing itself, and
// an optional caption. That is the same for a structure diagram, a state
// machine, a sequence, and a chart, so it is written once here and each block
// supplies only what differs: its tint, the word naming its kind, and the
// content it draws.
//
// The KIND STRIP is what makes a drawing legible before the caption is read.
// A structure diagram spends it on its altitude, because a reader of a
// structural view needs to know which zoom level they are at. The other kinds
// spend it on their own name, because they have no zoom level to state — a
// sequence is ordered by time and a machine by transition, so an altitude on
// either would be a label with nothing behind it.
// `kind` arrives as CONTENT, not as a string. The strip is set inside a
// content block, and a string interpolated there joins its surroundings
// differently from content written in place — enough to shift the drawing
// below it by a fraction of a point. Taking content keeps every caller's
// output identical to the markup it replaced.
#let _drawing-frame(tint: none, kind: none, title: none, caption: none, body) = {
  let c = if tint == none { luma(120) } else { tint }
  block(width: 100%, breakable: false)[
    #block(width: 100%, inset: (x: 8pt, y: 4.5pt), fill: c.lighten(94%),
           stroke: (top: 1.35pt + c, rest: 0.4pt + c.lighten(58%)),
           radius: 2pt)[
      #text(size: 6.2pt, weight: "bold", fill: c, tracking: 0.7pt)[
        #kind
      ]
      #if title != none [ #h(0.8em) #text(size: 8pt, fill: MUTED)[#title] ]
    ]
    #v(0.45em)
    #body
    #if caption != none [
      #v(0.35em)
      #block(width: 100%, inset: (x: 2pt))[
        #text(size: 7.5pt, fill: MUTED, style: "italic")[#caption]
      ]
    ]
  ]
  v(0.55em)
}

// THE BULLET BLOCK. Content is often written as bullets, one property each.
// This is the convenient way to write that, never the only legal way: a
// passage whose sense is a chain of causes reads worse chopped into bullets.
#let points(..items) = {
  let xs = items.pos()
  if xs.len() == 0 {
    _guide("points.empty",
           "points() holds at least one bullet; an empty list renders nothing")
  }
  for x in xs { _max-sentences("points bullet", x) }
  let visual = list(..xs)
  semantic-result("points", visual, fields: (items: xs))
}

// SECTION — the rhythm offered, not imposed: a muted lead, one visual, then
// notes. `visual` is OPTIONAL, and that is a contract rather than a taste
// call: the spine mandates an end-to-end walkthrough, and a walkthrough is a
// narrative. A required visual would make a mandated section illegal to write.
// ---- the spine ------------------------------------------------------------
// The renderer owns section numbering. Authors supply only content titles, so
// inserting or moving a section updates the displayed sequence without a
// source rewrite.

#let section(title: none, lead: none, visual: none, notes: none, body: none) = {
  _need("section", "title", title)
  _max-lead("section lead", lead)
  let visual-content = {
    if visual != none {
      block(width: 100%, breakable: false)[
        #heading(level: 2)[#title]
        #if lead != none [
          #block(width: 92%, text(size: 9.4pt, fill: MUTED)[#lead])
          #v(0.45em)
        ]
        #visual
      ]
    } else {
      heading(level: 2)[#title]
      if lead != none {
        block(width: 92%, text(size: 9.4pt, fill: MUTED)[#lead]); v(0.45em)
      }
    }
    if notes != none { notes }
    if body != none { body }
  }
  semantic-result("section", visual-content,
    fields: (title: title, lead: lead, visual: visual, notes: notes, body: body))
}

#let subsection(title: none, body) = {
  _need("subsection", "title", title)
  let visual = {
    heading(level: 3)[#title]
    body
  }
  semantic-result("subsection", visual, fields: (title: title, body: body))
}

#let notes(title: none, body) = {
  _need("notes", "title", title)
  let visual = {
    block(width: 100%, inset: (x: 8pt, y: 7pt), fill: SURFACE,
          stroke: 0.5pt + HAIRLINE, radius: 2pt)[
      #text(size: 6.2pt, weight: "bold", tracking: 0.6pt, fill: MUTED,
            upper(title))
      #linebreak() #body
    ]
    v(0.45em)
  }
  semantic-result("notes", visual, fields: (title: title, body: body))
}

// CROSS REFERENCES — a reference RESOLVES against declared data, so a rename
// is a compile error rather than a dangling path a link checker finds later.
//
// THE REGISTRY IS WHAT MAKES THAT CLAIM TRUE. Both registries are supplied by
// the aggregate, which reads every CONTEXT.typ and every context directory
// before it compiles: TERM-TITLES maps each declared slug to the title its
// glossary entry carries, and CONTEXT-NAMES lists every context the layer
// holds. A citation looks its subject up and renders the TITLE, so the reader
// sees the phrase the term names rather than the identifier the author typed.
// A slug with no declaration panics AT THE CITING CALL, which is the
// referential integrity this notation exists for: renaming a term at its
// declaration fails every stale use site during the compile, instead of
// printing a dead identifier into running prose that no byte-compare of the
// output can detect.
//
// AN EMPTY REGISTRY DISABLES THE LOOKUP, and only that case. A context
// compiled ALONE — an author previewing one document — has no aggregate to
// supply a registry, and panicking there would make a single file
// unrenderable. That fallback prints the slug, as this function always did.
// The aggregate additionally asserts its registry is non-empty, so the empty
// case can never arise in the render that gates and silently restore the old
// unchecked behavior.
#let TERM-TITLES = state("design-term-titles", (:))
#let CONTEXT-NAMES = state("design-context-names", ())
#let CITED-TERMS = state("design-cited-terms", ())

#let ctx(name, accent: none) = {
  _enum("ctx", "accent", accent, TINTS)
  if context-projection {
    semantic("context-reference", fields: (name: name, accent: accent))
  } else {
    context {
      let declared = CONTEXT-NAMES.final()
      if declared.len() > 0 and name not in declared {
        panic("ctx(" + repr(name) + ") names no context this layer declares. " +
              "Declared: " + declared.join(", ") + ". A context reference " +
              "resolves against the directories the layer holds, so a renamed " +
              "or misspelled context fails here rather than rendering a dead " +
              "identifier into the prose.")
      }
      let tone = if accent == none { _context-tint(name) } else {
        TINT-COLOR.at(accent)
      }
      chip(name, tone: tone)
    }
  }
}

// AN ADR CITATION, by number. The number IS the whole citation: the ADRs are
// markdown files outside this document, so there is nothing here to resolve
// against and nothing to jump to inside the render. What the call buys is that
// the NUMBER is checkable at the citing line — layer-integrity reads every
// adr(N) and refuses one the ADR directory has no file for, where a hand-typed
// path would silently rot the moment a file is renamed.
//
// The rendered form is a chip carrying the padded id, so a citation reads the
// same way a term or a context reference does.
#let adr(n) = {
  if type(n) != int {
    _fail("adr citation", "takes the ADR NUMBER as an integer, got " + repr(n)
          + " — the number is the citation, and a path would rot on a rename")
  }
  if n < 0 {
    _fail("adr citation", "takes a positive ADR number, got " + repr(n))
  }
  let padded = str(n)
  while padded.len() < 4 { padded = "0" + padded }
  if context-projection {
    semantic("adr", fields: (number: n))
  } else {
    chip("ADR-" + padded, tone: TINT-COLOR.at("slate"))
  }
}

#let term(slug) = {
  CITED-TERMS.update(xs => xs + (slug,))
  if context-projection {
    semantic("term-reference", fields: (slug: slug))
  } else {
    context {
      let titles = TERM-TITLES.final()
      if titles.len() == 0 {
        chip(slug, tone: luma(110))
      } else if slug in titles {
        let owner = TERM-OWNERS.final().at(slug, default: none)
        chip(titles.at(slug), tone: if owner == none {
          luma(110)
        } else {
          let tint = _context-tint(owner)
          if tint == none { luma(110) } else { tint }
        })
      } else {
        panic("term(" + repr(slug) + ") cites a term no CONTEXT.typ declares. " +
              "A term citation renders the declared TITLE, so an undeclared " +
              "slug has no text to render and would print the raw identifier " +
              "into the prose. Declare the term in a CONTEXT.typ, or correct " +
              "the slug.")
      }
    }
  }
}

// The aggregate declares the layer's vocabulary before any body renders.
//
// A layer that declares NO term is legal — a layer may be written before its
// glossary is. That case leaves the term registry empty and the lookup falls
// back to printing the slug, so the aggregate refuses a citation it cannot
// resolve rather than resolving it wrongly: `assert-references-resolvable`
// below runs at the end of the document and fails if any citation was made
// against an empty registry.
#let declare-vocabulary(
  terms: (:), contexts: (), term-owners: (:), context-accents: (:),
) = {
  TERM-TITLES.update(terms)
  TERM-OWNERS.update(term-owners)
  let names = ()
  let accents = (:)
  for ctx_entry in contexts {
    if type(ctx_entry) == str {
      names.push(ctx_entry)
    } else {
      names.push(ctx_entry.name)
      let accent = ctx_entry.at("accent", default: none)
      _enum("context", "accent", accent, TINTS)
      if accent != none { accents.insert(ctx_entry.name, accent) }
    }
  }
  for pair in context-accents.pairs() {
    let name = pair.at(0)
    let accent = pair.at(1)
    if accent != none {
      _req-enum("context " + repr(name) + " accent", accent, TINTS)
      accents.insert(name, accent)
    }
  }
  CONTEXT-NAMES.update(names)
  CONTEXT-ACCENTS.update(accents)
}

// The empty-registry fallback is a real hole, so it is closed by an assertion
// rather than by trust: a layer declaring no term at all renders, and a layer
// that CITES a term while declaring none stops here. Without this, deleting
// every CONTEXT.typ would silently restore the old unchecked behavior for the
// whole document.
#let assert-references-resolvable = context {
  let cited = CITED-TERMS.final()
  if cited.len() > 0 and TERM-TITLES.final().len() == 0 {
    panic("the document cites " + str(cited.len()) + " term(s) — including " +
          repr(cited.first()) + " — while the layer declares no term at all, " +
          "so no citation could be resolved and each one printed its raw " +
          "slug. Declare the terms in a CONTEXT.typ.")
  }
}
#let lens-pill(name) = {
  _req-enum("lens", name, LENSES)
  if context-projection {
    semantic("lens-pill", fields: (name: name))
  } else {
    chip(name, tone: LENS-COLOR.at(name))
  }
}

// THE DIAGRAMS — nodes and edges are DATA. `diagram` gives the graph to the
// Graphviz carrier that state machines use. `diagram-native` preserves an
// authored grid when that fine control is necessary. The author never writes a
// diagram language, so no dialect or label escaping leaks into a design
// document.
#let DIAGRAM-LAYOUTS = ("manual", "solved")
#let DIAGRAM-FLOWS = ("left-to-right", "top-to-bottom")
#let _diagram-layout-box = layout

#let _DIAGRAM-NODE-SHAPES = (
  actor: "ellipse",
  bounded-context: "box",
  system: "box",
  aggregate: "doubleoctagon",
  entity: "box",
  value-object: "note",
  event: "hexagon",
  frontend: "component",
  backend: "box",
  service: "box",
  component: "component",
  queue: "parallelogram",
  topic: "hexagon",
  database: "folder",
  external-system: "box",
)

// Graphviz owns geometry, not architecture meaning. These labels state the
// authoring role attached to each shape, so the generated legend explains the
// project convention instead of presenting a silhouette as a universal rule.
#let _DIAGRAM-NODE-ROLES = (
  actor: (name: "actor", description: "person or role"),
  bounded-context: (name: "bounded context", description: "domain owner"),
  system: (name: "system", description: "endpoint"),
  aggregate: (name: "aggregate", description: "invariant-owning cluster"),
  entity: (name: "entity", description: "identity-bearing record"),
  value-object: (name: "value object", description: "attribute-defined value"),
  event: (name: "event", description: "domain fact"),
  frontend: (name: "frontend", description: "user-facing component"),
  backend: (name: "backend", description: "system endpoint"),
  service: (name: "service", description: "internal service"),
  component: (name: "component", description: "owned runtime part"),
  queue: (name: "queue", description: "work channel"),
  topic: (name: "topic", description: "event stream"),
  database: (name: "database", description: "persistent store"),
  external-system: (name: "external system", description: "trust boundary"),
)

#let _DIAGRAM-GROUP-PRESENTATION = (
  domain: (name: "domain", description: "ownership boundary",
    style: "rounded,solid", penwidth: "2.2"),
  subdomain: (name: "subdomain", description: "ownership boundary",
    style: "rounded,solid", penwidth: "1.1"),
  bounded-context: (name: "bounded context", description: "ownership boundary",
    style: "rounded,bold", penwidth: "1.8"),
  runtime: (name: "runtime", description: "execution boundary",
    style: "rounded,dashed", penwidth: "1.1"),
  deployment: (name: "deployment", description: "placement boundary",
    style: "rounded,dotted", penwidth: "1.1"),
  subsystem: (name: "subsystem", description: "structural boundary",
    style: "rounded,solid", penwidth: "1.1"),
)

#let _DIAGRAM-RELATION-PRESENTATION = (
  dependency: (name: "dependency", description: "dashed directed link",
    style: "dashed", arrowhead: "vee", penwidth: "1.0"),
  call: (name: "call", description: "solid directed link",
    style: "solid", arrowhead: "normal", penwidth: "1.0"),
  pubsub: (name: "pubsub", description: "dotted publish or consume link",
    style: "dotted", arrowhead: "vee", penwidth: "1.4"),
  dataflow: (name: "dataflow", description: "weighted directed link",
    style: "bold", arrowhead: "vee", penwidth: "1.8"),
)

#let _diagram-check-implementation() = {
  for pair in (
    ("node role", DIAGRAM-NODE-KINDS, _DIAGRAM-NODE-ROLES),
    ("node kind", DIAGRAM-NODE-KINDS, _DIAGRAM-NODE-SHAPES),
    ("group kind", DIAGRAM-GROUP-KINDS, _DIAGRAM-GROUP-PRESENTATION),
    ("relation", DIAGRAM-RELATIONS, _DIAGRAM-RELATION-PRESENTATION),
  ) {
    let label = pair.at(0)
    let declared = pair.at(1)
    let implemented = pair.at(2)
    for value in declared {
      if value not in implemented {
        panic("diagram schema " + label + " " + repr(value)
          + " has no renderer implementation")
      }
    }
    for value in implemented.keys() {
      if value not in declared {
        panic("diagram renderer " + label + " " + repr(value)
          + " is not declared by the schema")
      }
    }
  }
}

#let _diagram-dot-quote(value, linebreaks: false) = {
  let quote = str.from-unicode(34)
  let newline = str.from-unicode(10)
  let escaped = str(value).replace("\\", "\\\\").replace(quote, "\\" + quote)
  if linebreaks { escaped = escaped.replace(newline, "\\n") }
  quote + escaped + quote
}

#let _diagram-dot-label(node) = {
  if "sub" in node {
    node.label + str.from-unicode(10) + node.sub
  } else { node.label }
}

#let _diagram-rankdir(flow) = if flow == "top-to-bottom" { "TB" } else { "LR" }

#let _diagram-unique(items) = items.fold((), (found, item) => {
  if item in found { found } else { found + (item,) }
})

#let _diagram-edge-data(edge) = {
  if type(edge) == dictionary {
    for field in ("from", "to", "relation", "label") {
      if field not in edge {
        panic("diagram dictionary edge is missing " + field
          + "; expected (from:, to:, relation:, label:)")
      }
    }
    _req-enum("diagram edge relation", edge.at("relation"), DIAGRAM-RELATIONS)
    if type(edge.at("label")) != str or edge.at("label").trim() == "" {
      panic("solved diagram dictionary edge " + repr(edge.at("from")) + " -> "
        + repr(edge.at("to")) + " requires a non-empty string label")
    }
    (
      from: edge.at("from"),
      to: edge.at("to"),
      label: edge.at("label"),
      relation: edge.at("relation"),
      legacy-style: none,
    )
  } else {
    if edge.len() < 2 {
      panic("diagram tuple edge requires from and to endpoints")
    }
    if edge.len() > 2 and type(edge.at(2)) != str {
      panic("solved diagram edge " + repr(edge.at(0)) + " -> "
        + repr(edge.at(1)) + " requires a string label; use "
        + "diagram-native(...) for positioned Typst content")
    }
    (
      from: edge.at(0),
      to: edge.at(1),
      label: if edge.len() > 2 { edge.at(2) } else { "" },
      relation: none,
      legacy-style: if edge.len() > 3 { edge.at(3) } else { none },
    )
  }
}

#let _diagram-node-shape(kind) = if kind == none { "box" } else {
  _DIAGRAM-NODE-SHAPES.at(kind)
}

#let _diagram-relation-attrs(relation, legacy-style) = {
  if relation == "pubsub" {
    // This is a directional line style only. Its label says publish or consume;
    // the renderer never invents durability, order, or delivery semantics.
    _DIAGRAM-RELATION-PRESENTATION.at(relation)
  } else if relation != none {
    _DIAGRAM-RELATION-PRESENTATION.at(relation)
  } else {
    (
      style: if legacy-style == "dashed" { "dashed" } else { "solid" },
      arrowhead: "normal",
      penwidth: "1.0",
    )
  }
}

#let _diagram-node-style(kind, external, color) = {
  let trust-boundary = kind == "external-system"
  (
    style: if trust-boundary {
      "dashed,bold"
    } else if external {
      "rounded,dashed"
    } else { "rounded,filled" },
    fill: if trust-boundary or external { "#ffffff" }
           else { color.lighten(88%).to-hex() },
    stroke: if trust-boundary or external { "#969696" }
            else { color.to-hex() },
    penwidth: if trust-boundary { "2.0" } else { "1.0" },
  )
}

#let _diagram-node-declaration(
  node, label: none, accent: "teal", extra: none,
) = {
  let external = node.at("external", default: false)
  let kind = node.at("kind", default: none)
  let node-color = TINT-COLOR.at(node.at("tint", default: accent))
  let style = _diagram-node-style(kind, external, node-color)
  let node-label = if label == none { _diagram-dot-label(node) } else { label }
  (
    "  " + _diagram-dot-quote(node.id) + " [label="
    + _diagram-dot-quote(
      node-label,
      linebreaks: label != none or (label == none and (
        "sub" in node or str.from-unicode(10) in node-label
      )),
    )
    + ", style=" + _diagram-dot-quote(style.style)
    + ", color=" + _diagram-dot-quote(style.stroke)
    + ", fillcolor=" + _diagram-dot-quote(style.fill)
    + ", shape=" + _diagram-dot-quote(_diagram-node-shape(kind))
    + ", penwidth=" + style.penwidth
    + if extra == none { "" } else { ", " + extra }
    + "];\n"
  )
}

#let DIAGRAM-LEGEND-PER-ROW = 5
#let DIAGRAM-LEGEND-SYMBOL-WIDTH = 38pt
#let DIAGRAM-LEGEND-SYMBOL-HEIGHT = 22pt

// Each symbol remains a real Graphviz carrier. The empty label and fixed
// dimensions keep the mark small and stable while Typst owns its arrangement.
#let _diagram-legend-node-source(node, accent) = {
  let id = "legend_node_mark_" + node.kind
  (
    "digraph {\n"
    + "  graph [margin=0, bgcolor=\"transparent\"];\n"
    + "  node [fontname=\"Libertinus Serif\", fontsize=9];\n"
    + _diagram-node-declaration(
      (id: id, kind: node.kind,
       tint: node.at("tint", default: accent),
       external: node.at("external", default: false)),
      label: "",
      accent: accent,
      extra: "width=0.62, height=0.34, fixedsize=true, margin=\"0,0\"",
    )
    + "}\n"
  )
}

// A group symbol is the carrier's cluster outline around an invisible sizing
// anchor. The sizing anchor has no visible mark, so no second inner box
// competes with the actual ownership or deployment boundary.
#let _diagram-legend-group-source(group, accent) = {
  let kind = group.kind
  let id = "legend_group_anchor_" + kind
  let color = TINT-COLOR.at(group.at("tint", default: accent))
  let presentation = _DIAGRAM-GROUP-PRESENTATION.at(kind)
  (
    "digraph {\n"
    + "  graph [margin=0, bgcolor=\"transparent\"];\n"
    + "  subgraph " + _diagram-dot-quote("cluster_legend_group_" + kind)
    + " {\n"
    + "    style=" + _diagram-dot-quote(presentation.style) + "; color="
    + _diagram-dot-quote(color.to-hex()) + "; penwidth="
    + presentation.penwidth + "; margin=0; bgcolor=\"transparent\";\n"
    + "    " + _diagram-dot-quote(id)
    + " [label=\"\", shape=box, style=invis, width=0.70, height=0.34, fixedsize=true];\n"
    + "  }\n}\n"
  )
}

#let _diagram-legend-relation-source(relation) = {
  let attrs = _diagram-relation-attrs(relation, none)
  let from = "legend_relation_from_" + relation
  let to = "legend_relation_to_" + relation
  (
    "digraph {\n"
    + "  graph [rankdir=LR, margin=0, nodesep=0.2, bgcolor=\"transparent\"];\n"
    + "  node [shape=point, style=invis, label=\"\", width=0.01, height=0.01];\n"
    + "  " + _diagram-dot-quote(from) + "; "
    + _diagram-dot-quote(to) + ";\n"
    + "  " + _diagram-dot-quote(from) + " -> "
    + _diagram-dot-quote(to) + " [label=\"\", style="
    + _diagram-dot-quote(attrs.style) + ", arrowhead="
    + _diagram-dot-quote(attrs.arrowhead) + ", penwidth="
    + attrs.penwidth + "];\n}\n"
  )
}

#let _diagram-legend-symbol(source) = box(
  width: 100%, height: DIAGRAM-LEGEND-SYMBOL-HEIGHT,
  align(center + horizon, layout(size => {
    let natural = measure(dot-render(source, math-mode: "text"))
    let max-width = DIAGRAM-LEGEND-SYMBOL-WIDTH
    let max-height = DIAGRAM-LEGEND-SYMBOL-HEIGHT
    let width = if natural.width <= 0pt or natural.height <= 0pt {
      max-width
    } else {
      calc.min(max-width, (natural.width / natural.height) * max-height)
    }
    dot-render(source, width: width, math-mode: "text")
  })),
)

#let _diagram-legend-cell(source, name, description) = block(width: 100%)[
  #set par(leading: 0pt, justify: false)
  #grid(
    columns: 1,
    row-gutter: 2pt,
    align: center,
    _diagram-legend-symbol(source),
    text(size: 7.2pt, weight: "bold", fill: INK)[#name],
    text(size: 6.5pt, fill: MUTED)[#description],
  )
]

#let _diagram-legend-table(cells, columns: none) = {
  let count = cells.len()
  if count == 0 { none } else {
    let column-count = if columns == none {
      calc.min(count, DIAGRAM-LEGEND-PER-ROW)
    } else {
      columns
    }
    table(
      columns: (1fr,) * column-count,
      gutter: 4pt,
      row-gutter: 4pt,
      inset: 0pt,
      stroke: none,
      align: center + top,
      ..cells,
    )
  }
}

#let _diagram-legend(groups, nodes, relations, accent) = {
  let group-kinds = _diagram-unique(groups.map(group => group.kind))
  let node-kinds = _diagram-unique(nodes.filter(
    node => node.at("kind", default: none) != none,
  ).map(node => node.kind))
  if group-kinds.len() == 0 and node-kinds.len() == 0 and relations.len() == 0 {
    none
  } else {
    let group-cells = group-kinds.map(kind => {
      let group = groups.filter(group => group.kind == kind).first()
      let presentation = _DIAGRAM-GROUP-PRESENTATION.at(kind)
      (
        source: _diagram-legend-group-source(group, accent),
        name: presentation.name,
        description: presentation.description,
      )
    })
    let node-cells = node-kinds.map(kind => {
      let matching = nodes.filter(
        node => node.at("kind", default: none) == kind,
      )
      let sample = matching.first()
      let styled = (
        id: sample.id,
        kind: sample.kind,
        tint: sample.at("tint", default: accent),
        external: sample.at("external", default: false),
      )
      let role = _DIAGRAM-NODE-ROLES.at(kind)
      (
        source: _diagram-legend-node-source(styled, accent),
        name: role.name,
        description: role.description,
      )
    })
    let relation-cells = relations.map(relation => {
      let presentation = _DIAGRAM-RELATION-PRESENTATION.at(relation)
      (
        source: _diagram-legend-relation-source(relation),
        name: presentation.name,
        description: presentation.description,
      )
    })
    let legend-cells = (group-cells + node-cells + relation-cells).map(cell => _diagram-legend-cell(
        cell.source, cell.name, cell.description,
      ))
    let legend-table = _diagram-legend-table(legend-cells)
    v(0.35em)
    block(width: 100%, inset: (x: 2pt, y: 2pt), fill: none, stroke: none)[
      #text(size: 6.6pt, weight: "bold", tracking: 0.55pt, fill: FAINT)[LEGEND]
      #v(1pt)
      #legend-table
    ]
  }
}

#let _diagram(
  altitude: none, title: none, caption: none, accent: "teal",
  layout: "manual", flow: "left-to-right", spacing: (16mm, 11mm), nodes: (),
  edges: (), viewpoint: none, groups: (),
) = {
  _diagram-check-implementation()
  _req-altitude(altitude)
  _req-enum("accent", accent, TINTS)
  _req-enum("diagram layout", layout, DIAGRAM-LAYOUTS)
  _req-enum("diagram flow", flow, DIAGRAM-FLOWS)
  if layout == "solved" and viewpoint != none {
    _req-enum("diagram viewpoint", viewpoint, DIAGRAM-VIEWPOINTS)
  }
  if nodes.len() == 0 {
    _guide("diagram.nodes",
           "a diagram is expected to declare at least one node. An empty " +
           "diagram renders a blank frame, which reads as a drawing that " +
           "failed rather than as the absence of one — declare a node, or " +
           "drop the diagram block.")
  }
  let ac = TINT-COLOR.at(_alt-tint(altitude))
  // Every endpoint must name a declared node; a typo would otherwise draw an
  // edge to nowhere, which renders as a drawing missing a line.
  let ids = nodes.map(n => n.id)
  if layout == "solved" {
    let seen = ()
    for id in ids {
      if id in seen {
        panic("duplicate diagram node id " + repr(id)
          + "; node ids are unique within one diagram")
      }
      seen.push(id)
    }
  }
  for n in nodes {
    if "tint" in n {
      _req-enum("diagram node " + repr(n.id) + " tint", n.tint, TINTS)
    }
    if layout == "solved" and "kind" in n {
      _req-enum("diagram node kind", n.kind, DIAGRAM-NODE-KINDS)
    }
  }
  let solved-edges = if layout == "solved" {
    edges.map(_diagram-edge-data)
  } else { () }
  let checked-edges = if layout == "solved" { solved-edges } else {
    edges.map(e => (from: e.at(0), to: e.at(1)))
  }
  for e in checked-edges {
    for endpoint in (e.at("from"), e.at("to")) {
      if endpoint not in ids {
        panic("diagram edge names " + repr(endpoint) + ", which is not a " +
              "declared node. Declared nodes: " + repr(ids))
      }
    }
  }
  if layout == "manual" {
    for n in nodes {
      if "pos" not in n {
        panic("manual diagram node " + repr(n.id) + " is missing pos; either " +
          "declare pos or use diagram(...) for automatic layout")
      }
    }
  }
  if layout == "solved" {
    for n in nodes {
      if type(n.label) != str or ("sub" in n and type(n.sub) != str) {
        panic("solved diagram node " + repr(n.id) + " requires string label " +
          "and sub values; use diagram-native(...) for positioned Typst content")
      }
    }
    let group-by-id = (:)
    for group in groups {
      for field in ("id", "label", "kind") {
        if field not in group {
          panic("diagram group is missing " + field
            + "; expected (id:, label:, kind:, parent?:, tint?:)")
        }
      }
      if group.id in group-by-id {
        panic("duplicate diagram group id " + repr(group.id)
          + "; group ids are unique within one diagram")
      }
      _req-enum("diagram group kind", group.kind, DIAGRAM-GROUP-KINDS)
      if type(group.label) != str {
        panic("diagram group " + repr(group.id) + " requires a string label")
      }
      if "tint" in group {
        _req-enum("diagram group " + repr(group.id) + " tint", group.tint, TINTS)
      }
      group-by-id.insert(group.id, group)
    }
    for group in groups {
      if "parent" in group {
        if group.parent == group.id {
          panic("diagram group " + repr(group.id) + " cannot parent itself")
        }
        if group.parent not in group-by-id {
          panic("diagram group " + repr(group.id) + " parent "
            + repr(group.parent) + " is not a declared diagram group")
        }
      }
    }
    for group in groups {
      let seen = ()
      let cursor = group.id
      while cursor != none {
        if cursor in seen {
          panic("diagram group parent cycle reaches " + repr(cursor))
        }
        seen.push(cursor)
        cursor = group-by-id.at(cursor).at("parent", default: none)
      }
    }
    for node in nodes {
      if "group" in node and node.group not in group-by-id {
        panic("diagram node " + repr(node.id) + " group " + repr(node.group)
          + " is not a declared diagram group")
      }
      if groups.len() > 0 {
        if "group" not in node {
          panic("diagram node is missing group while the diagram declares groups")
        }
      }
    }
  }
  if context-projection {
    return semantic(
      if layout == "manual" { "diagram-native" } else { "diagram" },
      fields: (
      altitude: altitude, title: title, caption: caption, accent: accent,
      layout: layout, flow: flow, spacing: spacing, viewpoint: viewpoint,
      groups: groups, nodes: nodes, edges: edges,
    ))
  }
  let manual = if layout == "manual" {
    let ns = nodes.map(n => {
      let ext = n.at("external", default: false)
      let node-color = TINT-COLOR.at(n.at("tint", default: accent))
      let lbl = if "sub" in n {
        align(center)[
          #text(size: 8.6pt)[#n.label] \
          #text(size: 7.6pt, fill: MUTED)[#n.sub]
        ]
      } else { text(size: 8.6pt)[#n.label] }
      _fl-node(n.pos, lbl, name: label(n.id),
        fill: if ext { white } else { node-color.lighten(88%) },
        stroke: if ext {
          (dash: "dashed", paint: luma(150), thickness: 0.7pt)
        } else { 0.8pt + node-color },
        corner-radius: 2pt, inset: 6pt)
    })
    let es = edges.map(e => {
      let dashed = e.len() > 3 and e.at(3) == "dashed"
      _fl-edge(label(e.at(0)), label(e.at(1)),
        if dashed { "-->" } else { "->" },
        label: text(size: 7pt, fill: MUTED)[#e.at(2)],
        label-side: if e.len() > 4 { e.at(4) } else { auto },
        label-sep: 3pt, label-size: 7pt,
        stroke: if dashed {
          (dash: "dashed", thickness: 0.6pt, paint: luma(110))
        } else { 0.7pt + MUTED })
    })
    align(center, _fletcher.diagram(spacing: spacing, ..ns, ..es))
  } else { none }
  let solved = if layout == "solved" {
    let node-declaration(n) = {
      _diagram-node-declaration(n, accent: accent)
    }
    let group-by-id = (:)
    for group in groups { group-by-id.insert(group.id, group) }
    let grouped-node-ids = nodes.filter(n => "group" in n).map(n => n.id)
    let root-node-declarations = nodes.filter(
      n => n.id not in grouped-node-ids,
    ).map(node-declaration).sum(default: "")
    let group-declaration(group-id) = {
      let group = group-by-id.at(group-id)
      let color = TINT-COLOR.at(group.at("tint", default: accent))
      let presentation = _DIAGRAM-GROUP-PRESENTATION.at(group.kind)
      let style = presentation.style
      let penwidth = presentation.penwidth
      let own-nodes = nodes.filter(
        n => n.at("group", default: none) == group-id,
      ).map(node-declaration).sum(default: "")
      let children = groups.filter(
        child => child.at("parent", default: none) == group-id,
      ).map(child => group-declaration(child.id)).sum(default: "")
      (
        "  subgraph " + _diagram-dot-quote("cluster_" + group.id) + " {\n"
        + "    label=" + _diagram-dot-quote(upper(group.kind) + " · " + group.label) + ";\n"
        + "    style=" + _diagram-dot-quote(style) + "; color="
        + _diagram-dot-quote(color.to-hex()) + "; penwidth=" + penwidth
        + "; bgcolor=" + _diagram-dot-quote(color.lighten(96%).to-hex()) + ";\n"
        + own-nodes + children + "  }\n"
      )
    }
    let group-declarations = groups.filter(
      group => group.at("parent", default: none) == none,
    ).map(group => group-declaration(group.id)).sum(default: "")
    let edge-declarations = solved-edges.map(e => {
      let attrs = _diagram-relation-attrs(e.relation, e.at("legacy-style"))
      (
        "  " + _diagram-dot-quote(e.from) + " -> "
        + _diagram-dot-quote(e.to) + " [label="
        + _diagram-dot-quote(e.label) + ", style="
        + _diagram-dot-quote(attrs.style) + ", arrowhead="
        + _diagram-dot-quote(attrs.arrowhead) + ", penwidth="
        + attrs.penwidth + "];\n"
      )
    }).sum(default: "")
    let source = (
      "digraph {\n  rankdir=" + _diagram-rankdir(flow) + ";\n"
      + "  graph [fontname=\"Libertinus Serif\", fontsize=10, nodesep=0.35, ranksep=0.55];\n"
      + "  node [shape=box, fontname=\"Libertinus Serif\", fontsize=10, penwidth=1.0];\n"
      + "  edge [fontname=\"Libertinus Serif\", fontsize=8.3, color=\"#555555\"];\n"
      + root-node-declarations + group-declarations + edge-declarations + "}"
    )
    let graph = _diagram-layout-box(size => {
      let natural = measure(dot-render(source, math-mode: "text"))
      let ceiling = size.width * 0.94
      let width = if natural.width <= 0pt { ceiling } else {
        calc.min(natural.width, ceiling)
      }
      let height-ceiling = size.height * 0.78
      let scaled = if natural.height > 0pt and natural.width > 0pt {
        let drawn-height = natural.height * (width / natural.width)
        if drawn-height > height-ceiling {
          width * (height-ceiling / drawn-height)
        } else { width }
      } else { width }
      align(center, dot-render(source, width: scaled, math-mode: "text"))
    })
    let used-relations = _diagram-unique(solved-edges.filter(
      edge => edge.relation != none,
    ).map(edge => edge.relation))
    [#graph #_diagram-legend(groups, nodes, used-relations, accent)]
  } else { none }
  _drawing-frame(
    tint: ac,
    kind: if viewpoint != none and altitude == none [
      VIEWPOINT #upper(viewpoint) · ALTITUDE #upper(_alt-name(altitude))
    ] else if viewpoint != none [
      VIEWPOINT #upper(viewpoint) · ALTITUDE #altitude · #upper(_alt-name(altitude))
    ] else if altitude == none [
      ALTITUDE #upper(_alt-name(altitude))
    ] else [
      ALTITUDE #altitude · #upper(_alt-name(altitude))
    ],
    title: title, caption: caption,
    if layout == "solved" { solved } else { manual },
  )
}

// THE DEFAULT STRUCTURE DIAGRAM — Graphviz solves placement and routing from
// declared nodes and edges. Use this unless a reader needs an authored grid.
#let diagram(
  altitude: none, title: none, caption: none, accent: "teal",
  flow: "left-to-right", viewpoint: none, groups: (), nodes: (), edges: (),
) = _diagram(
  altitude: altitude, title: title, caption: caption, accent: accent,
  layout: "solved", flow: flow, viewpoint: viewpoint, groups: groups,
  nodes: nodes, edges: edges,
)

// THE POSITIONED STRUCTURE DIAGRAM — use only where the authored coordinates
// carry meaning or a human requires precise visual control.
#let diagram-native(
  altitude: none, title: none, caption: none, accent: "teal",
  spacing: (16mm, 11mm), nodes: (), edges: (),
) = _diagram(
  altitude: altitude, title: title, caption: caption, accent: accent,
  layout: "manual", spacing: spacing, nodes: nodes, edges: edges,
)

// THE FIVE ANSWERS — the repeated component unit, made composable. EVERY FIELD
// IS OPTIONAL, and that is load-bearing rather than convenient: a unit with no
// failure mode should say nothing about failure. Requiring all five is how a
// genuine "none" becomes a fabricated sentence.
#let ANSWER-FIELDS = (
  ("responsibility", "Responsibility"), ("interface", "Interface"),
  ("interactions", "Interactions"), ("invariants", "Invariants"),
  ("failure", "Failure"),
)

#let answers-data(
  responsibility: none, interface: none, interactions: none,
  invariants: none, failure: none,
) = (
  responsibility: responsibility, interface: interface,
  interactions: interactions, invariants: invariants, failure: failure,
)

// The chain is written on ONE expression deliberately. A `.map` starting a
// fresh line in code mode does not attach to the value above it: the
// expression ends at the newline, the chain is dropped, and the unfiltered
// list flows on. That failure is SILENT — it renders every field including the
// absent ones — so the shape is kept where it cannot recur.
#let _answer-rows(data) = {
  let pairs = ANSWER-FIELDS.map(f => (f.at(1), data.at(f.at(0), default: none)))
  pairs.filter(r => r.at(1) != none)
}

#let _answer-row(r, size: 7.6pt, label-size: none, color: FAINT) = {
  let label-size = if label-size == none { size - 0.8pt } else { label-size }
  block(width: 100%)[
    #set par(justify: false)
    #text(size: label-size, weight: "bold", fill: color)[
      #lower(r.at(0))
    ]
    #v(0.5pt)
    #text(size: size)[#r.at(1)]
  ]
}

#let _answers-compact(data, size: 7.6pt, color: FAINT) = {
  let rows = _answer-rows(data)
  for (i, r) in rows.enumerate() {
    if i > 0 { v(2pt) }
    _answer-row(r, size: size, color: color)
  }
}

// ANSWERS PANELS, COMPONENT CARDS, and CONTRACT CARDS carry different facts,
// but a reader should learn their visual grammar once. These constructors own
// that grammar: callers supply semantic content, while heading/body typography
// and every frame token stay here. The component table owns equal row heights;
// standalone panels keep their natural height.
#let _card-anatomy(accent) = {
  let c = TINT-COLOR.at(accent)
  (
    color: c,
    inset: (x: 7pt, y: 6pt),
    fill: c.lighten(97%),
    stroke: 0.5pt + c.lighten(55%),
    radius: 2pt,
  )
}

#let _card-content(body, title: none, furniture: none, color: black) = [
  #set par(justify: false)
  #if title != none [
    #grid(
      columns: (1fr, auto),
      text(size: RENDERER-TITLE, weight: "bold", fill: color)[#title],
      if furniture != none { furniture },
    )
    #v(0.75pt)
    #text(size: RENDERER-BODY)[#body]
  ] else [
    #text(size: RENDERER-BODY)[#body]
  ]
]

#let _card(accent: "teal", title: none, furniture: none, body) = {
  let anatomy = _card-anatomy(accent)
  block(
    width: 100%,
    inset: anatomy.inset,
    fill: anatomy.fill,
    stroke: anatomy.stroke,
    radius: anatomy.radius,
    _card-content(
      body,
      title: title,
      furniture: furniture,
      color: anatomy.color,
    ),
  )
}

#let _unit-data(kind, name: none, lens: none, mission: none, answers: none,
               body: none, tint: none) = {
  let gs = ()
  for (f, v) in (("name", name), ("mission", mission)) {
    if v == none or v == "" {
      gs.push((rule: kind + ".missing-field",
               message: kind + " is missing " + f + " — a card without it "
                        + "renders as a card that does not name that fact."))
    }
  }
  if lens != none { _req-enum("lens", lens, LENSES) }
  _enum(kind, "tint", tint, TINTS)
  (name: name, lens: lens, mission: mission, answers: answers, body: body,
   tint: tint,
   _guides: gs)
}

#let _pill(label, color, fill: none) = {
  let fill = if fill == none { color.lighten(85%) } else { fill }
  box(
    fill: fill,
    inset: (x: 3pt, y: 1pt),
    radius: 1.5pt,
    text(size: RENDERER-META, weight: "bold", fill: color.darken(20%))[#label],
  )
}

#let _unit-furniture(lens: none, role: none, color: black) = {
  let pills = ()
  if role != none {
    pills.push(_pill(role, color, fill: color.lighten(90%)))
  }
  if lens != none {
    let lens-color = LENS-COLOR.at(lens)
    pills.push(_pill(lens, lens-color))
  }
  if pills.len() == 0 {
    none
  } else if pills.len() == 1 {
    pills.at(0)
  } else {
    grid(columns: (auto,) * pills.len(), gutter: 3pt, ..pills)
  }
}

#let _unit-body(item, color) = [
  #set par(justify: false)
  #text(weight: "bold")[#item.mission]
  #if item.body != none [ #v(1.5pt) #item.body ]
  #if item.answers != none [
    #v(3pt) #line(length: 100%, stroke: 0.4pt + HAIRLINE) #v(3pt)
    #_answers-compact(item.answers, color: color)
  ]
]

#let answers(
  title: none, accent: "teal", responsibility: none, interface: none,
  interactions: none, invariants: none, failure: none,
) = {
  _req-enum("accent", accent, TINTS)
  if title != none { _title("answers", title) }
  let data = answers-data(
    responsibility: responsibility, interface: interface,
    interactions: interactions, invariants: invariants, failure: failure)
  if context-projection {
    return semantic("answers", fields: (
      title: title, accent: accent, answers: data,
    ))
  }
  let rows = _answer-rows(data)
  if rows.len() == 0 {
    _guide("answers.empty",
           "answers() carries no answer. A unit block with all five fields " +
           "absent says nothing the surrounding prose did not.")
    return
  }
  let c = TINT-COLOR.at(accent)
  _card(accent: accent, title: title)[
    #set par(justify: false)
    #for (i, r) in rows.enumerate() [
      #if i > 0 [ #v(2.5pt) ]
      #_answer-row(r, size: RENDERER-BODY, label-size: RENDERER-META, color: c)
    ]
  ]
  v(0.45em)
}

// COMPONENT CARDS — the fixed shape, so an author cannot invent a variant.
// A card returns DATA to `components`, so its guidance is deferred into the
// dictionary and replayed there — see `_guides`.
#let component(name: none, lens: none, mission: none, answers: none, body: none,
              tint: none) = {
  _unit-data("component", name: name, lens: lens, mission: mission,
             answers: answers, body: body, tint: tint)
}

// CONTRACT CARDS — the named agreement between independently owned units.
// This constructor shares the component data and card anatomy, but renders a
// single full-width card and makes the contract role explicit in the header.
#let contract(
  name: none, lens: none, mission: none, answers: none, body: none,
  accent: "teal", tint: none,
) = {
  _req-enum("accent", accent, TINTS)
  let item = _unit-data(
    "contract", name: name, lens: lens, mission: mission,
    answers: answers, body: body, tint: tint,
  )
  if context-projection {
    return semantic("contract", fields: (
      name: item.name, lens: item.lens, mission: item.mission,
      answers: item.answers, body: item.body, accent: accent, tint: item.tint,
    ))
  }
  _guides(item.at("_guides", default: ()))
  let item-tint = item.at("tint", default: none)
  let resolved-tint = if item-tint == none { accent } else { item-tint }
  let color = TINT-COLOR.at(resolved-tint)
  _card(
    accent: resolved-tint,
    title: item.name,
    furniture: _unit-furniture(
      lens: item.lens, role: "contract", color: color,
    ),
  )[
    #_unit-body(item, color)
  ]
  v(0.45em)
}

#let components(..cs, accent: "teal", cols: "2") = {
  _req-enum("accent", accent, TINTS)
  _req-enum("cols", cols, ("2", "3"))
  let items = cs.pos()
  if items.len() == 0 {
    _guide("components.empty",
           "components() holds at least one card; an empty grid renders nothing")
    return
  }
  // Replay each card's deferred guidance from here, a content position.
  if context-projection {
    return semantic("components", fields: (accent: accent, items: items))
  }
  for x in items { _guides(x.at("_guides", default: ())) }
  let n = calc.min(items.len(), int(cols))
  let anatomy = _card-anatomy(accent)
  block(width: 100%, radius: anatomy.radius, clip: true)[
    #table(
      columns: (1fr,) * n,
      gutter: 6pt,
      inset: _card-anatomy(accent).inset,
      fill: (x, y) => if x + y * n >= items.len() {
        none
      } else {
        let tint = items.at(x + y * n).at("tint", default: none)
        let color = if tint == none { TINT-COLOR.at(accent) } else {
          TINT-COLOR.at(tint)
        }
        color.lighten(97%)
      },
      stroke: (x, y) => if x + y * n >= items.len() {
        none
      } else {
        let tint = items.at(x + y * n).at("tint", default: none)
        let color = if tint == none { TINT-COLOR.at(accent) } else {
          TINT-COLOR.at(tint)
        }
        0.5pt + color.lighten(55%)
      },
      align: left + top,
      ..items.map(x => {
        let item-tint = x.at("tint", default: none)
        let item-color = if item-tint == none {
          anatomy.color
        } else { TINT-COLOR.at(item-tint) }
        _card-content(
          title: x.name,
          furniture: _unit-furniture(
            lens: x.lens, color: item-color,
          ),
          color: item-color,
        )[
          #_unit-body(x, item-color)
        ]
      }),
    )
  ]
  v(0.55em)
}

// COVERAGE — the breadth axis, carried in the document. A row that is not
// `captured` states its reason, so absence is a recorded decision rather than
// an accident.
#let coverage(..rows) = {
  let rs = rows.pos()
  if rs.len() == 0 {
    _guide("coverage.empty",
           "coverage() holds at least one row; an empty table renders a bare header")
    return
  }
  for r in rs {
    _req-enum("coverage status", r.at(1), COVERAGE-STATUSES)
    if r.at(1) != "captured" and (r.len() < 3 or r.at(2) == "" or r.at(2) == none) {
      _guide("coverage.reason",
             "coverage row " + repr(r.at(0)) + " is " + repr(r.at(1)) +
             " and states no reason. A part is marked " + repr(r.at(1)) +
             " by an explicit decision, and the row is expected to carry why — "
      + "add a third column with the reason.")
    }
  }
  if context-projection {
    return semantic("coverage", fields: (rows: rs))
  }
  block(width: 100%)[
    #table(columns: (auto, auto, 1fr), stroke: none,
      inset: (x: 5pt, y: 3.5pt), align: (left, left, left),
      table.header(..("Part", "Status", "Why").map(h => text(size: 6.3pt,
        weight: "bold", tracking: 0.5pt, fill: FAINT, upper(h)))),
      ..rs.map(r => (
        text(size: 8.3pt, font: "DejaVu Sans Mono")[#r.at(0)],
        {
          let col = COVERAGE-COLOR.at(r.at(1))
          box(fill: col.lighten(88%), inset: (x: 3pt, y: 1pt), radius: 1.5pt,
              text(size: 6.5pt, weight: "bold", fill: col.darken(15%))[#r.at(1)])
        },
        text(size: 8.3pt)[#if r.len() > 2 { r.at(2) } else { "" }],
      )).flatten())
  ]
  v(0.5em)
}

// THE PENDING LEDGER — placed on a time axis, so aging design debt is visible
// at a glance. That makes `since` load-bearing rather than decorative, so it
// is required and its shape is checked.
// An entry returns DATA to the ledger, so its guidance is deferred into the
// dictionary and replayed by `pending-ledger` — see `_guides`.
#let pending-entry(title: none, kind: none, since: none, adr: none, body) = {
  let gs = ()
  if title == none or title == "" {
    gs.push((rule: "pending.missing-field",
             message: "a pending entry is missing title — the ledger row "
                      + "renders with no label to read it by."))
  }
  // The KIND's vocabulary stays fail-closed; its ABSENCE is guidance. A kind
  // outside the vocabulary has no colour and no row treatment, so it cannot be
  // drawn, while a missing kind falls back to a neutral row.
  if kind != none { _req-enum("pending kind", kind, PENDING-KINDS) }
  if kind == none {
    gs.push((rule: "pending.missing-field",
             message: "a pending entry is missing kind — expected one of "
                      + repr(PENDING-KINDS) + "."))
  }
  if since == none {
    gs.push((rule: "pending.missing-field",
             message: "pending entry " + repr(title) + " is missing since — "
                      + "the ledger places entries on a time axis, so an entry "
                      + "with no date cannot show how long the layer has run "
                      + "ahead. Expected a YYYY-MM-DD date."))
  } else if type(since) != str or since.matches(regex("^\\d{4}-\\d{2}-\\d{2}$")).len() == 0 {
    // A date that is PRESENT but not a date is fail-closed: it is a value the
    // ledger cannot place on its axis, and sorting by it would order the
    // ledger by nonsense rather than by time.
    panic("pending since=" + repr(since) + " must be a YYYY-MM-DD date. The " +
          "ledger places entries on a time axis, so a wrong or guessed date " +
          "misreports how long the layer has run ahead.")
  }
  if kind == "build" and adr == none {
    gs.push((rule: "pending.build-adr",
             message: "pending entry " + repr(title) + " is kind=build and "
                      + "cites no ADR. A designed-not-yet-built entry is "
                      + "expected to carry the decision that designed it — "
                      + "add adr: <number>."))
  }
  (title: title, kind: kind, since: since, adr: adr, body: body, _guides: gs)
}

#let pending-ledger(..entries) = {
  let es = entries.pos()
  // An empty ledger is OMITTED rather than rendered empty: an empty ledger
  // states that this page is the present, and a heading over nothing states
  // that the author forgot.
  if es.len() == 0 {
    _guide("pending-ledger.empty",
           "pending-ledger() holds at least one entry; an empty ledger is " +
           "omitted entirely rather than rendered empty.")
    return
  }
  if context-projection {
    return semantic("pending-ledger", fields: (entries: es))
  }
  // Replay each entry's deferred guidance from here, a content position.
  for e in es { _guides(e.at("_guides", default: ())) }
  // A short ledger is one reading unit, so keep its heading and rows together.
  // A longer ledger remains breakable; otherwise a real backlog could overflow
  // the page merely to avoid one page turn.
  block(width: 100%, breakable: es.len() > 3)[
    #heading(level: 2)[Pending updates]
    #v(0.3em)
    // An entry with no date sorts to the front rather than crashing the sort:
    // `since` is a guideline now, so the ledger has to be able to draw a row that
    // does not carry one. The empty key keeps the comparison total.
    #for e in es.sorted(key: e => if e.since == none { "" } else { e.since }) {
      // A missing kind takes a neutral row rather than indexing the colour table
      // with `none`, which would be a crash where the library promised guidance.
      let col = if e.kind == none { FAINT } else { PENDING-COLOR.at(e.kind) }
      block(width: 100%, inset: (x: 8pt, y: 6pt),
            stroke: (top: 1.2pt + col, rest: 0.4pt + col.lighten(58%)),
            fill: col.lighten(96%), radius: 2pt)[
        #grid(columns: (auto, 1fr, auto), gutter: 6pt,
          box(fill: col.lighten(85%), inset: (x: 3pt, y: 1pt), radius: 1.5pt,
              text(size: 6pt, weight: "bold", fill: col.darken(15%))[
                #if e.kind == none { "—" } else { e.kind }]),
          text(size: 9.2pt, weight: "bold")[#e.title],
          text(size: 7pt, fill: FAINT, font: "DejaVu Sans Mono")[
            #if e.since == none { "—" } else { e.since }])
        #if e.body != none [ #v(2pt) #text(size: 8.2pt)[#e.body] ]
        #if e.adr != none [ #v(1.5pt) #text(size: 7.2pt, fill: MUTED)[#e.adr] ]
      ]
      v(0.35em)
    }
  ]
  v(0.3em)
}

// STAT TILES — the identity fields are invariants (a tile with no value shows
// a number nobody can read); the presentation rules are guidelines.
#let stat-tile(value: none, label: none, delta: none, dir: none) = {
  if dir != none and dir not in ("up", "down") {
    panic("stat-tile dir=" + repr(dir) + " must be one of " + repr(("up", "down")))
  }
  // A stat tile returns DATA to its grid, so it cannot emit its own guidance —
  // `_need` emits content, which Typst refuses to join with the dictionary this
  // returns. Every rule here collects into `gs` instead, and `stat-grid`
  // replays the whole list from a content position.
  let gs = ()
  for (f, x) in (("value", value), ("label", label)) {
    if x == none or x == "" {
      gs.push((rule: "stat-tile.missing-field",
               message: "stat-tile is missing " + f + " — the tile renders "
                        + "with nothing to read in that position."))
    }
  }
  if delta != none and dir == none {
    gs.push((rule: "stat-tile.dir",
             message: "stat-tile " + repr(label) + " carries a delta with no "
                      + "dir=. A trend reads better coloured by its direction, "
                      + "so dir is up or down."))
  }
  // A tile with no value draws an em dash rather than crashing on `str(none)`:
  // presence is guidance now, so the tile has to be renderable without it.
  let v = if value == none { "—" } else if type(value) == str { value } else { str(value) }
  if v.matches(regex("^[0-9]{1,3}(,[0-9]{3})+$")).len() > 0 {
    gs.push((rule: "stat-tile.magnitude",
             message: "stat-tile value=" + repr(v) + " is an accountant's "
                      + "figure. A stat value is a magnitude the eye takes in "
                      + "— abbreviate it (2.4M, 1.2B)."))
  }
  (value: v, label: label, delta: delta, dir: dir, _guides: gs)
}

// THE LEGEND — show the mark, never name it. The panel is generated from the
// library's own visual decisions, so it cannot describe a mark the document
// does not use.
#let how-to-read(accent: "teal") = {
  _req-enum("accent", accent, TINTS)
  if context-projection {
    return semantic("how-to-read", fields: (accent: accent))
  }
  let c = TINT-COLOR.at(accent)
  block(width: 100%, inset: (x: 8pt, y: 7pt), fill: SURFACE,
        stroke: 0.5pt + HAIRLINE, radius: 2pt)[
    #text(size: 6.3pt, weight: "bold", tracking: 0.6pt, fill: MUTED)[
      HOW TO READ THIS
    ]
    #v(3pt)
    #grid(columns: (auto, 1fr), gutter: 6pt, row-gutter: 4pt,
      box(width: 26pt, height: 11pt, fill: c.lighten(88%),
          stroke: 0.8pt + c, radius: 2pt),
      text(size: 7.6pt)[a part this document owns],
      box(width: 26pt, height: 11pt, fill: white,
          stroke: (dash: "dashed", paint: luma(150), thickness: 0.7pt),
          radius: 2pt),
      text(size: 7.6pt)[a part owned elsewhere, drawn as a pointer],
      align(horizon, line(length: 26pt, stroke: 0.7pt + MUTED)),
      text(size: 7.6pt)[a relationship inside this unit],
      align(horizon, line(length: 26pt,
        stroke: (dash: "dashed", thickness: 0.6pt, paint: FAINT))),
      text(size: 7.6pt)[a relationship crossing the seam],
      ..COVERAGE-STATUSES.map(s => {
        let col = COVERAGE-COLOR.at(s)
        (box(fill: col.lighten(88%), inset: (x: 3pt, y: 1pt), radius: 1.5pt,
             text(size: 6.5pt, weight: "bold", fill: col.darken(15%))[#s]),
         text(size: 7.6pt)[a coverage row marked #s])
      }).flatten())
  ]
  v(0.5em)
}
