// ---- the state machine, drawn by a layout-solving graph renderer ---------
//
// WHY THIS IS ITS OWN BLOCK RATHER THAN A DIAGRAM. A state machine is not a
// structure drawn at a zoom level: it is a set of states and the transitions
// between them, and what a reader needs from it is which state is initial,
// which are terminal, and what event moves the machine along each edge. A
// node-and-edge diagram can be MADE to show that, but only by hand-placing
// every state on a grid — and a hand-placed layout stops being right the
// moment a transition is added, which is how a machine drawing decays.
//
// So the machine declares STATES and TRANSITIONS and nothing about position.
// The author writes what the machine IS; the carrier decides where it sits.
//
// WHY THE GRAPH RENDERER AND NOT THE AUTOMATON PACKAGE. The automaton package
// draws the right marks — a start arrow, a double ring on an accepting state —
// but it has NO LAYOUT SOLVER. Its five modes place states on fixed geometric
// patterns (a line, a ring, a grid, a wrapped line) and route no edges around
// each other. On a machine of any density the transition labels land on top of
// one another, and the only remedy the package offers is tuning the pattern by
// hand — which is the hand-placed layout this block exists to remove, wearing a
// different name.
//
// The graph renderer SOLVES the layout: it ranks the states, routes each edge
// around the others, and places every label clear of the rest. Measured on one
// twelve-transition machine, the pattern-placed drawing overlapped four label
// pairs and the solved drawing overlapped none. The marks the automaton package
// gave for free are cheap to state here — a point node for the start, a double
// circle for an accepting state — so the solver is the half worth keeping.
//
// NO ALTITUDE. An altitude labels the zoom level of a structural view. A
// machine has none — it is ordered by transition, not by containment — so the
// kind strip spends its space naming the machine instead.
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *
#import "packages.typ": *
#import "native.typ": _drawing-frame, _req-enum

// The reading direction. A machine that runs from an entry to a terminal reads
// left to right like a sentence; one whose states cycle is often clearer top to
// bottom. Both are directions for the SOLVER, never positions for a state.
#let MACHINE-FLOWS = ("left-to-right", "top-to-bottom")

#let _rankdir(flow) = if flow == "top-to-bottom" { "TB" } else { "LR" }

// TWO LAYERS READ A STATE NAME, and each needs its own care. The carrier parses
// one string, so a name carrying a quote would end the token early and produce
// a graph that fails to parse or — worse — parses into a different graph than
// the author wrote; this quotes and escapes for that parser. The carrier then
// EVALUATES each label as math unless told otherwise, so the same name would
// reach Typst's math parser and fail inside the package, naming a line the
// author never wrote. State names are identifiers rather than formulas, so
// every render below asks for text mode and this escaping is the only layer
// left that has to be right.
#let _q(s) = {
  let dq = str.from-unicode(34)
  dq + str(s).replace(dq, "\\" + dq) + dq
}

// A state machine.
//
//   states       — the state names. Order is the order they are declared to the
//                  solver, which nudges the ranking; it is not a placement.
//   transitions  — (from, to, event) triples. `from` and `to` name declared
//                  states; a typo is a hard failure rather than a missing arc,
//                  because an edge to nowhere renders as a drawing with a line
//                  quietly absent.
//   initial      — the state the machine starts in, drawn with an entry arrow.
//                  Guidance when unstated: a machine whose entry point is
//                  unknown cannot be followed.
//   accepting    — the terminal states, drawn with the double ring.
#let state-machine(
  title: none, caption: none, accent: "teal", flow: "left-to-right",
  states: (), transitions: (), initial: none, accepting: (),
) = {
  _req-enum("accent", accent, TINTS)
  _req-enum("machine flow", flow, MACHINE-FLOWS)

  // AN EMPTY MACHINE NEVER REACHES THE CARRIER. The guidance is the whole
  // response: a graph with no nodes renders an empty frame, and the block says
  // what it expected rather than drawing nothing and looking broken.
  if states.len() == 0 {
    _guide("machine.states",
           "a state machine is expected to declare at least one state. An " +
           "empty machine renders a blank frame, which reads as a drawing " +
           "that failed rather than as the absence of one.")
    return _drawing-frame(
      tint: TINT-COLOR.at(accent), kind: [STATE MACHINE],
      title: title, caption: caption, [],
    )
  }
  if initial == none {
    _guide("machine.initial",
           "the machine does not say which state it starts in, so a reader " +
           "cannot tell where to begin following it. Name one of " +
           repr(states) + " as `initial`.")
  }

  // Every endpoint must name a declared state. This is the same fail-closed
  // rule the structural diagram holds its edges to, and for the same reason:
  // the alternative is a transition the author wrote and the reader never sees.
  for s in (initial,) + accepting {
    if s != none and s not in states {
      panic("state machine names " + repr(s) + ", which is not a declared " +
            "state. Declared states: " + repr(states))
    }
  }
  for t in transitions {
    for endpoint in (t.at(0), t.at(1)) {
      if endpoint not in states {
        panic("state machine transition names " + repr(endpoint) + ", which " +
              "is not a declared state. Declared states: " + repr(states))
      }
    }
  }

  let c = TINT-COLOR.at(accent)
  let nl = "\n"
  let hx(x) = _q(x.to-hex())
  let f = "fontname=" + _q("Libertinus Serif")

  // THE START MARKER IS AN EDGE FROM A POINT, which is how a solved graph
  // states an entry: the point carries no label and no ring, so it reads as an
  // arrow arriving from outside rather than as a state of the machine.
  let src = (
    "digraph {" + nl
    + "  rankdir=" + _rankdir(flow) + ";" + nl
    + "  graph [" + f + ", fontsize=10, nodesep=0.35, ranksep=0.55];" + nl
    + "  node [shape=circle, style=" + _q("filled") + ", " + f
    + ", fontsize=8, color=" + hx(c) + ", fillcolor=" + hx(c.lighten(88%))
    + ", penwidth=1.0];" + nl
    + "  edge [" + f + ", fontsize=7, color=" + _q("#555555") + "];" + nl
  )

  // An accepting state is declared before its edges so the shape applies
  // wherever the state appears.
  let marks = accepting.map(s =>
    "  " + _q(s) + " [shape=doublecircle];" + nl).sum(default: "")

  let entry = if initial != none {
    ("  __entry [shape=point, width=0.07, color=" + hx(c) + "];" + nl
      + "  __entry -> " + _q(initial) + ";" + nl)
  } else { "" }

  let edges = transitions.map(t => {
    let (from, to, ..rest) = t
    let ev = if rest.len() > 0 { str(rest.at(0)) } else { "" }
    let lbl = if ev == "" { "" } else { " [label=" + _q(ev) + "]" }
    "  " + _q(from) + " -> " + _q(to) + lbl + ";" + nl
  }).sum(default: "")

  // A state naming no transition would otherwise never be drawn, because the
  // carrier only sees a name that appears in an edge. Declaring every state up
  // front keeps an isolated state visible rather than silently dropped.
  let decls = states.map(s => "  " + _q(s) + ";" + nl).sum(default: "")

  _drawing-frame(
    tint: c,
    kind: [STATE MACHINE],
    title: title, caption: caption,
    // SIZE THE DRAWING BY ITS OWN SHAPE, capped to the column — the same rule
    // the structural diagram follows, so two drawings of similar complexity
    // come out similar and size never reads as importance.
    layout(size => {
      // ORDER MATTERS TO THE SOLVER. It ranks from the first node it sees, so
      // the entry is declared before anything else: seeded with a terminal
      // instead, the solver ranks backwards and the machine reads from its end
      // to its beginning. The bare state declarations come last, where they
      // still rescue an isolated state without steering the ranking.
      let body = src + entry + marks + edges + decls + "}"
      let nat = measure(dot-render(body, math-mode: "text"))
      let hi = size.width * 0.94
      let w = if nat.width <= 0pt { hi } else { calc.min(nat.width, hi) }
      let hcap = size.height * 0.78
      let scaled = if nat.height > 0pt and nat.width > 0pt {
        let drawn = nat.height * (w / nat.width)
        if drawn > hcap { w * (hcap / drawn) } else { w }
      } else { w }
      align(center, dot-render(body, width: scaled, math-mode: "text"))
    }),
  )
}
