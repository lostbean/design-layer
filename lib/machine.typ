// ---- the state machine, drawn by an automaton renderer -------------------
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
// `finite` solves the layout, draws the initial marker and the double ring on
// an accepting state, and curves an arc around a state rather than through it.
// The author writes what the machine IS; the carrier decides where it sits.
//
// NO ALTITUDE. An altitude labels the zoom level of a structural view. A
// machine has none — it is ordered by transition, not by containment — so the
// kind strip spends its space naming the machine instead.
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *
#import "packages.typ": *
#import "native.typ": _drawing-frame, _req-enum

// The layouts a machine may ask for, named by what they are good for rather
// than by the carrier's own vocabulary. A pipeline reads left to right; a
// machine whose states cycle reads better on a ring; a dense machine with many
// crossing transitions reads better wrapped.
#let MACHINE-LAYOUTS = ("linear", "circular", "snake", "grid")

#let _layout-of(name, spacing, columns) = {
  if name == "circular" { _finite.layout.circular.with(spacing: spacing) }
  else if name == "snake" {
    _finite.layout.snake.with(spacing: spacing, columns: columns)
  } else if name == "grid" {
    _finite.layout.grid.with(spacing: spacing, columns: columns)
  } else { _finite.layout.linear.with(spacing: spacing) }
}

// A state machine.
//
//   states       — the ordered state names. Order is the layout's reading
//                  order, so it is the author's one lever over placement.
//   transitions  — (from, to, event) triples. `from` and `to` name declared
//                  states; a typo is a hard failure rather than a missing arc,
//                  because an edge to nowhere renders as a drawing with a line
//                  quietly absent.
//   initial      — the state the machine starts in. Guidance when unstated: a
//                  machine whose entry point is unknown cannot be followed.
//   accepting    — the terminal states, drawn with the double ring.
#let state-machine(
  title: none, caption: none, accent: "teal", layout: auto,
  columns: auto, spacing: auto, states: (), transitions: (),
  initial: none, accepting: (),
) = {
  _req-enum("accent", accent, TINTS)

  // THE LAYOUT DEFAULTS TO THE MACHINE'S OWN SIZE. A short machine reads best
  // as a straight line, and a long one does not: seven states on one row runs
  // off the page, which is the failure a hand-placed grid was invented to
  // avoid. So a machine past a handful of states wraps unless the author says
  // otherwise. The author keeps the override; they no longer need it to get a
  // drawing that fits.
  let layout = if layout != auto { layout } else if states.len() > 5 {
    "snake"
  } else { "linear" }
  _req-enum("machine layout", layout, MACHINE-LAYOUTS)

  // AN EMPTY MACHINE NEVER REACHES THE CARRIER. The guidance is the whole
  // response: the carrier reads the first state to seed its automaton and
  // panics on an empty one, and a carrier panic would replace this block's
  // guidance — which names the rule and what to do — with a stack trace from
  // inside a package the author never called. So the block guides and stops,
  // exactly as it would for any other absence it can render around.
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

  // SIZE THE STATE TO ITS LABEL. The carrier's default radius is set for the
  // one-letter states of a textbook automaton; a design layer names its states
  // in words (`ready_for_agent`), and at the default the text runs outside the
  // circle it belongs to. Deriving the radius from the longest name keeps every
  // state legible without asking the author to tune a number.
  let widest = calc.max(1, ..states.map(s => str(s).len()))
  let radius = calc.max(0.62, 0.20 * calc.sqrt(widest * 1.0))
  let spacing = if spacing != auto { spacing } else { radius * 3.6 }
  // Wrap before a row grows wider than the page. The same width budget the
  // radius consumes decides how many states fit on one line. A NARROWER row
  // also shortens the transition arcs, and short arcs are what keeps two
  // labels from landing on the same point — so the wrap is a legibility lever,
  // not only a width one.
  let columns = if columns != auto { columns } else {
    calc.max(2, calc.min(3, int(7.5 / (radius * 2.6))))
  }

  // The carrier takes its machine as a dictionary of state -> (target: event).
  // Two transitions sharing a state pair are joined onto one arc, because two
  // arcs between the same pair would be drawn on top of each other.
  let tbl = (:)
  for s in states { tbl.insert(s, (:)) }
  for t in transitions {
    let (from, to, ..rest) = t
    let ev = if rest.len() > 0 { rest.at(0) } else { "" }
    let row = tbl.at(from)
    if to in row and row.at(to) != "" and ev != "" {
      row.insert(to, row.at(to) + ", " + ev)
    } else {
      row.insert(to, ev)
    }
    tbl.insert(from, row)
  }

  _drawing-frame(
    tint: c,
    kind: [STATE MACHINE],
    title: title, caption: caption,
    align(center, {
      set text(size: 7.6pt)
      _finite.automaton(
        tbl,
        initial: initial,
        final: accepting,
        layout: _layout-of(layout, spacing, columns),
        style: (
          state: (
            radius: radius,
            fill: c.lighten(88%),
            stroke: 0.7pt + c,
            label: (fill: luma(30)),
          ),
          transition: (
            stroke: 0.7pt + luma(85),
            label: (fill: luma(80), size: 7pt),
          ),
        ),
      )
    }),
  )
}
