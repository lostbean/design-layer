// ---- the native authoring surface: what a design.typ calls directly -----
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *
#import "furniture.typ": *
#import "packages.typ": *

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
  block(width: 100%, inset: (x: 7pt, y: 3.5pt), fill: c.lighten(92%),
        stroke: (left: 2.4pt + c))[
    #text(size: 6.2pt, weight: "bold", fill: c, tracking: 0.7pt)[
      #kind
    ]
    #if title != none [ #h(0.6em) #text(size: 8pt, fill: luma(70))[#title] ]
  ]
  v(0.45em)
  body
  if caption != none {
    v(0.35em)
    block(width: 100%, inset: (x: 2pt))[
      #text(size: 7.4pt, fill: luma(115))[#caption]
    ]
  }
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
  list(..xs)
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
  heading(level: 1)[#title]
  if lead != none {
    block(text(size: 9.4pt, fill: luma(70))[#lead]); v(0.3em)
  }
  if visual != none { visual }
  if notes != none { notes }
  if body != none { body }
}

#let subsection(title: none, body) = {
  _need("subsection", "title", title)
  heading(level: 2)[#title]
  body
}

#let notes(title: none, body) = {
  _need("notes", "title", title)
  block(width: 100%, inset: (x: 7pt, y: 6pt), fill: luma(248),
        stroke: (left: 2.4pt + luma(175)), radius: (right: 2pt))[
    #text(size: 6.2pt, weight: "bold", tracking: 0.6pt, fill: luma(95),
          upper(title))
    #linebreak() #body
  ]
  v(0.45em)
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

#let ctx(name, accent: "teal") = {
  _req-enum("accent", accent, TINTS)
  context {
    let declared = CONTEXT-NAMES.final()
    if declared.len() > 0 and name not in declared {
      panic("ctx(" + repr(name) + ") names no context this layer declares. " +
            "Declared: " + declared.join(", ") + ". A context reference " +
            "resolves against the directories the layer holds, so a renamed " +
            "or misspelled context fails here rather than rendering a dead " +
            "identifier into the prose.")
    }
    chip(name, tone: TINT-COLOR.at(accent))
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
  chip("ADR-" + padded, tone: TINT-COLOR.at("slate"))
}

#let term(slug) = {
  CITED-TERMS.update(xs => xs + (slug,))
  context {
    let titles = TERM-TITLES.final()
    if titles.len() == 0 {
      chip(slug, tone: luma(110))
    } else if slug in titles {
      chip(titles.at(slug), tone: luma(110))
    } else {
      panic("term(" + repr(slug) + ") cites a term no CONTEXT.typ declares. " +
            "A term citation renders the declared TITLE, so an undeclared " +
            "slug has no text to render and would print the raw identifier " +
            "into the prose. Declare the term in a CONTEXT.typ, or correct " +
            "the slug.")
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
#let declare-vocabulary(terms: (:), contexts: ()) = {
  TERM-TITLES.update(terms)
  CONTEXT-NAMES.update(contexts)
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
  chip(name, tone: LENS-COLOR.at(name))
}

// THE DIAGRAMS — nodes and edges are DATA. `diagram` gives the graph to the
// Graphviz carrier that state machines use. `diagram-native` preserves an
// authored grid when that fine control is necessary. The author never writes a
// diagram language, so no dialect or label escaping leaks into a design
// document.
#let DIAGRAM-LAYOUTS = ("manual", "solved")
#let DIAGRAM-FLOWS = ("left-to-right", "top-to-bottom")
#let _diagram-layout-box = layout

#let _diagram-dot-quote(value) = {
  let quote = str.from-unicode(34)
  quote + str(value).replace("\\", "\\\\").replace(quote, "\\" + quote) + quote
}

#let _diagram-dot-label(node) = {
  if "sub" in node { node.label + " · " + node.sub } else { node.label }
}

#let _diagram-rankdir(flow) = if flow == "top-to-bottom" { "TB" } else { "LR" }

#let _diagram(
  altitude: none, title: none, caption: none, accent: "teal",
  layout: "manual", flow: "left-to-right", spacing: (16mm, 11mm), nodes: (),
  edges: (),
) = {
  _req-altitude(altitude)
  _req-enum("accent", accent, TINTS)
  _req-enum("diagram layout", layout, DIAGRAM-LAYOUTS)
  _req-enum("diagram flow", flow, DIAGRAM-FLOWS)
  if nodes.len() == 0 {
    _guide("diagram.nodes",
           "a diagram is expected to declare at least one node. An empty " +
           "diagram renders a blank frame, which reads as a drawing that " +
           "failed rather than as the absence of one — declare a node, or " +
           "drop the diagram block.")
  }
  let c = TINT-COLOR.at(accent)
  let ac = TINT-COLOR.at(_alt-tint(altitude))
  // Every endpoint must name a declared node; a typo would otherwise draw an
  // edge to nowhere, which renders as a drawing missing a line.
  let ids = nodes.map(n => n.id)
  for e in edges {
    for endpoint in (e.at(0), e.at(1)) {
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
    for e in edges {
      if e.len() > 2 and type(e.at(2)) != str {
        panic("solved diagram edge " + repr(e.at(0)) + " -> " + repr(e.at(1)) +
          " requires a string label; use diagram-native(...) for positioned Typst content")
      }
    }
  }
  let manual = if layout == "manual" {
    let ns = nodes.map(n => {
      let ext = n.at("external", default: false)
      let lbl = if "sub" in n {
        align(center)[
          #text(size: 8.6pt)[#n.label] \
          #text(size: 7.6pt, fill: luma(95))[#n.sub]
        ]
      } else { text(size: 8.6pt)[#n.label] }
      _fl-node(n.pos, lbl, name: label(n.id),
        fill: if ext { white } else { c.lighten(88%) },
        stroke: if ext {
          (dash: "dashed", paint: luma(150), thickness: 0.7pt)
        } else { 0.8pt + c },
        corner-radius: 2pt, inset: 6pt)
    })
    let es = edges.map(e => {
      let dashed = e.len() > 3 and e.at(3) == "dashed"
      _fl-edge(label(e.at(0)), label(e.at(1)),
        if dashed { "-->" } else { "->" },
        label: text(size: 7pt, fill: luma(80))[#e.at(2)],
        label-side: if e.len() > 4 { e.at(4) } else { auto },
        label-sep: 3pt, label-size: 7pt,
        stroke: if dashed {
          (dash: "dashed", thickness: 0.6pt, paint: luma(110))
        } else { 0.7pt + luma(85) })
    })
    align(center, _fletcher.diagram(spacing: spacing, ..ns, ..es))
  } else { none }
  let solved = if layout == "solved" {
    let fill = (c.lighten(88%)).to-hex()
    let stroke = c.to-hex()
    let node-declarations = nodes.map(n => {
      let external = n.at("external", default: false)
      let style = if external { "rounded,dashed" } else { "rounded,filled" }
      let node-fill = if external { "#ffffff" } else { fill }
      let node-stroke = if external { "#969696" } else { stroke }
      (
        "  " + _diagram-dot-quote(n.id) + " [label="
        + _diagram-dot-quote(_diagram-dot-label(n)) + ", style="
        + _diagram-dot-quote(style) + ", color=" + _diagram-dot-quote(node-stroke)
        + ", fillcolor=" + _diagram-dot-quote(node-fill) + "];\n"
      )
    }).sum(default: "")
    let edge-declarations = edges.map(e => {
      let dashed = e.len() > 3 and e.at(3) == "dashed"
      let edge-style = if dashed { "dashed" } else { "solid" }
      let edge-label = if e.len() > 2 { str(e.at(2)) } else { "" }
      (
        "  " + _diagram-dot-quote(e.at(0)) + " -> "
        + _diagram-dot-quote(e.at(1)) + " [label="
        + _diagram-dot-quote(edge-label) + ", style="
        + _diagram-dot-quote(edge-style) + "];\n"
      )
    }).sum(default: "")
    let source = (
      "digraph {\n  rankdir=" + _diagram-rankdir(flow) + ";\n"
      + "  graph [fontname=\"Libertinus Serif\", fontsize=10, nodesep=0.35, ranksep=0.55];\n"
      + "  node [shape=box, fontname=\"Libertinus Serif\", fontsize=9, penwidth=1.0];\n"
      + "  edge [fontname=\"Libertinus Serif\", fontsize=7, color=\"#555555\"];\n"
      + node-declarations + edge-declarations + "}"
    )
    _diagram-layout-box(size => {
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
  } else { none }
  _drawing-frame(
    tint: ac,
    kind: if altitude == none [
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
  flow: "left-to-right", nodes: (), edges: (),
) = _diagram(
  altitude: altitude, title: title, caption: caption, accent: accent,
  layout: "solved", flow: flow, nodes: nodes, edges: edges,
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

#let _answers-compact(data, size: 7.6pt) = {
  let rows = _answer-rows(data)
  for (i, r) in rows.enumerate() {
    if i > 0 { v(2pt) }
    grid(columns: (4.6em, 1fr), gutter: 4pt,
      text(size: size - 0.8pt, weight: "bold", fill: luma(115))[#lower(r.at(0))],
      text(size: size)[#r.at(1)])
  }
}

#let answers(
  title: none, accent: "teal", responsibility: none, interface: none,
  interactions: none, invariants: none, failure: none,
) = {
  _req-enum("accent", accent, TINTS)
  if title != none { _title("answers", title) }
  let data = answers-data(
    responsibility: responsibility, interface: interface,
    interactions: interactions, invariants: invariants, failure: failure)
  let rows = _answer-rows(data)
  if rows.len() == 0 {
    _guide("answers.empty",
           "answers() carries no answer. A unit block with all five fields " +
           "absent says nothing the surrounding prose did not.")
    return
  }
  let c = TINT-COLOR.at(accent)
  block(width: 100%, inset: (x: 7pt, y: 6pt), fill: c.lighten(97%),
        stroke: (left: 2.4pt + c), radius: (right: 2pt))[
    #if title != none [ #text(size: 9.4pt, weight: "bold")[#title] #v(2.5pt) ]
    #for (i, r) in rows.enumerate() [
      #if i > 0 [ #v(2.5pt) ]
      #grid(columns: (5.6em, 1fr), gutter: 5pt,
        text(size: 7pt, weight: "bold", fill: c)[#lower(r.at(0))],
        text(size: 8.4pt)[#r.at(1)])
    ]
  ]
  v(0.45em)
}

// COMPONENT CARDS — the fixed shape, so an author cannot invent a variant.
// A card returns DATA to `components`, so its guidance is deferred into the
// dictionary and replayed there — see `_guides`.
#let component(name: none, lens: none, mission: none, answers: none, body: none) = {
  let gs = ()
  for (f, v) in (("name", name), ("mission", mission)) {
    if v == none or v == "" {
      gs.push((rule: "component.missing-field",
               message: "component is missing " + f + " — a card without it "
                        + "renders as a card that does not name that fact."))
    }
  }
  if lens != none { _req-enum("lens", lens, LENSES) }
  (name: name, lens: lens, mission: mission, answers: answers, body: body,
   _guides: gs)
}

#let components(..cs, accent: "teal") = {
  _req-enum("accent", accent, TINTS)
  let items = cs.pos()
  if items.len() == 0 {
    _guide("components.empty",
           "components() holds at least one card; an empty grid renders nothing")
    return
  }
  // Replay each card's deferred guidance from here, a content position.
  for x in items { _guides(x.at("_guides", default: ())) }
  let c = TINT-COLOR.at(accent)
  grid(columns: (1fr,) * calc.min(items.len(), 3), gutter: 6pt,
    ..items.map(x => block(width: 100%, inset: 6pt, fill: luma(250),
                           stroke: 0.5pt + luma(210), radius: 2pt)[
      #grid(columns: (1fr, auto),
        text(size: 8.6pt, weight: "bold", fill: c)[#x.name],
        if x.lens != none {
          box(fill: c.lighten(85%), inset: (x: 3pt, y: 1pt), radius: 1.5pt,
              text(size: 5.8pt, weight: "bold", fill: c.darken(20%))[#x.lens])
        })
      #v(2pt)
      #text(size: 8.2pt, weight: "bold")[#x.mission]
      #if x.body != none [ #v(1.5pt) #text(size: 8pt)[#x.body] ]
      #if x.answers != none [
        #v(3pt) #line(length: 100%, stroke: 0.4pt + luma(220)) #v(3pt)
        #_answers-compact(x.answers)
      ]
    ]))
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
  block(width: 100%)[
    #table(columns: (auto, auto, 1fr), stroke: none,
      inset: (x: 5pt, y: 3.5pt), align: (left, left, left),
      table.header(..("Part", "Status", "Why").map(h => text(size: 6.3pt,
        weight: "bold", tracking: 0.5pt, fill: luma(110), upper(h)))),
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
  // Replay each entry's deferred guidance from here, a content position.
  for e in es { _guides(e.at("_guides", default: ())) }
  heading(level: 1)[Pending updates]
  v(0.3em)
  // An entry with no date sorts to the front rather than crashing the sort:
  // `since` is a guideline now, so the ledger has to be able to draw a row that
  // does not carry one. The empty key keeps the comparison total.
  for e in es.sorted(key: e => if e.since == none { "" } else { e.since }) {
    // A missing kind takes a neutral row rather than indexing the colour table
    // with `none`, which would be a crash where the library promised guidance.
    let col = if e.kind == none { luma(150) } else { PENDING-COLOR.at(e.kind) }
    block(width: 100%, inset: (x: 7pt, y: 5pt), stroke: (left: 2.4pt + col),
          fill: col.lighten(96%), radius: (right: 2pt))[
      #grid(columns: (auto, 1fr, auto), gutter: 6pt,
        box(fill: col.lighten(85%), inset: (x: 3pt, y: 1pt), radius: 1.5pt,
            text(size: 6pt, weight: "bold", fill: col.darken(15%))[
              #if e.kind == none { "—" } else { e.kind }]),
        text(size: 9.2pt, weight: "bold")[#e.title],
        text(size: 7pt, fill: luma(120), font: "DejaVu Sans Mono")[
          #if e.since == none { "—" } else { e.since }])
      #if e.body != none [ #v(2pt) #text(size: 8.2pt)[#e.body] ]
      #if e.adr != none [ #v(1.5pt) #text(size: 7.2pt, fill: luma(110))[#e.adr] ]
    ]
    v(0.35em)
  }
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
  let c = TINT-COLOR.at(accent)
  block(width: 100%, inset: (x: 7pt, y: 6pt), fill: luma(250),
        stroke: 0.5pt + luma(215), radius: 2pt)[
    #text(size: 6.3pt, weight: "bold", tracking: 0.6pt, fill: luma(95))[
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
      align(horizon, line(length: 26pt, stroke: 0.7pt + luma(85))),
      text(size: 7.6pt)[a relationship inside this unit],
      align(horizon, line(length: 26pt,
        stroke: (dash: "dashed", thickness: 0.6pt, paint: luma(110)))),
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
