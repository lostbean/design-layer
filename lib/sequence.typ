// ---- the sequence, drawn by a message-sequence carrier -------------------
//
// WHY A SEQUENCE IS NOT A DIAGRAM. A structural diagram answers "what is made
// of what"; a sequence answers "what happened, in what order". The second
// question has a dimension the first does not — time, running down the page —
// and it has constructs a node-and-edge drawing cannot express at all: a
// participant that is active only for part of the exchange, a branch taken
// under one condition, a block that repeats, a participant created partway
// through and destroyed before the end.
//
// Forcing that into boxes and arrows loses exactly the part a protocol reader
// needs. An arrow between two boxes cannot say WHEN, cannot say "only if the
// token was valid", and cannot say "three times". So the sequence is its own
// block, over a carrier built for it.
//
// NO ALTITUDE, for the same reason the state machine has none: a sequence is
// ordered by time, not by containment, so a zoom level would be a label with
// nothing behind it.
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *
#import "packages.typ": *
#import "native.typ": _drawing-frame, _req-enum

// The participant shapes, from the carrier's own vocabulary. They are the
// roles a design layer actually draws — a person, a boundary the system meets,
// a store, a queue — and naming the role rather than drawing every party as an
// identical box is what makes a sequence readable at a glance.
#let PARTICIPANT-SHAPES = (
  "participant", "actor", "boundary", "control", "entity",
  "database", "collections", "queue",
)

// One step of an exchange. Each is a plain dictionary so a sequence body is
// DATA the block validates before the carrier ever sees it — the same choice
// the state machine makes, and for the same reason: a message naming an
// undeclared participant must fail naming the typo, not draw a line to nowhere.
#let seq-msg(from, to, label, dashed: false, activate: false, deactivate: false) = (
  kind: "msg", from: from, to: to, label: label,
  dashed: dashed, activate: activate, deactivate: deactivate,
)
#let seq-note(on, body, side: "right") = (
  kind: "note", on: on, body: body, side: side,
)
// A branch, a repetition, an optional block. `steps` nests, so a group holds
// messages and further groups.
#let seq-alt(condition, steps, otherwise: none) = (
  kind: "alt", condition: condition, steps: steps, otherwise: otherwise,
)
#let seq-loop(condition, steps) = (kind: "loop", condition: condition, steps: steps)
#let seq-opt(condition, steps) = (kind: "opt", condition: condition, steps: steps)

#let _known(steps, ids, where) = {
  for s in steps {
    let k = s.at("kind")
    if k == "msg" {
      for endpoint in (s.from, s.to) {
        if endpoint not in ids {
          panic("sequence " + where + " names participant " + repr(endpoint) +
                ", which is not declared. Declared participants: " + repr(ids))
        }
      }
    } else if k == "note" {
      if s.on not in ids {
        panic("sequence note is attached to " + repr(s.on) + ", which is not " +
              "a declared participant. Declared participants: " + repr(ids))
      }
    } else {
      _known(s.steps, ids, where)
      if k == "alt" and s.otherwise != none { _known(s.otherwise, ids, where) }
    }
  }
}

// `_opt` and `_break` are UNUSABLE in the vendored carrier version: both call
// an unbound `grp` where every sibling calls `_grp`, so either one fails the
// compile with "unknown variable: grp" from inside the package. The primitive
// they are shorthand for works, so an optional block is built from it directly
// and renders exactly as the shorthand would have. Drop this indirection when
// the vendored version carries the fix.
#let _emit(steps, c) = {
  import _chronos: _seq, _note, _alt, _loop, _grp
  for s in steps {
    let k = s.at("kind")
    if k == "msg" {
      _seq(s.from, s.to, comment: s.label, dashed: s.dashed,
           enable-dst: s.activate, disable-src: s.deactivate)
    } else if k == "note" {
      _note(s.side, s.body, pos: s.on)
    } else if k == "alt" {
      if s.otherwise == none {
        _alt(s.condition, { _emit(s.steps, c) })
      } else {
        _alt(s.condition, { _emit(s.steps, c) },
             "else", { _emit(s.otherwise, c) })
      }
    } else if k == "loop" {
      _loop(s.condition, { _emit(s.steps, c) })
    } else if k == "opt" {
      _grp("opt", desc: s.condition, type: "opt", { _emit(s.steps, c) })
    }
  }
}

// A message sequence.
//
//   participants — ordered (id, label, shape) entries. Order is left-to-right
//                  placement, which is the author's one lever over layout.
//   steps        — the exchange, in time order, built from `seq-msg`,
//                  `seq-note`, `seq-alt`, `seq-loop`, and `seq-opt`.
#let sequence(
  title: none, caption: none, accent: "teal",
  participants: (), steps: (),
) = {
  _req-enum("accent", accent, TINTS)

  if participants.len() == 0 {
    _guide("sequence.participants",
           "a sequence is expected to declare at least one participant. An " +
           "exchange with no parties renders a blank frame, which reads as a " +
           "drawing that failed rather than as the absence of one.")
  }
  if steps.len() == 0 {
    _guide("sequence.steps",
           "a sequence declares no steps, so it draws parties with nothing " +
           "happening between them. Add the messages, or drop the block.")
  }

  for p in participants {
    if "shape" in p { _req-enum("participant shape", p.shape, PARTICIPANT-SHAPES) }
  }
  let ids = participants.map(p => p.id)
  _known(steps, ids, "message")

  let c = TINT-COLOR.at(accent)

  // An empty sequence never reaches the carrier: it reads the participant list
  // to place its lifelines, and the guidance above is the whole response.
  if participants.len() == 0 or steps.len() == 0 {
    return _drawing-frame(
      tint: c, kind: [SEQUENCE], title: title, caption: caption, [],
    )
  }

  _drawing-frame(
    tint: c,
    kind: [SEQUENCE],
    title: title, caption: caption,
    align(center, {
      set text(size: 7.6pt)
      _chronos.diagram({
        import _chronos: _par
        for p in participants {
          _par(
            p.id,
            display-name: p.at("label", default: p.id),
            shape: p.at("shape", default: "participant"),
            color: c.lighten(88%),
          )
        }
        _emit(steps, c)
      })
    }),
  )
}
