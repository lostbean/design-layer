// ---- the behavior block, its clauses, and the mechanism fence -------------
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *
#import "furniture.typ": *
#import "statements.typ": *

// THE FENCE IS READ FROM THE SCHEMA, like every other vocabulary — its terms
// and its patterns alike, through `BEHAVIOR-FENCE` in schema.typ. The schema
// declares each pattern in the dialect `regex()` reads, so a pattern travels
// from the declaration to the check unchanged, and there is no translation step
// where the declared shape and the enforced shape could come to differ.
//
// Enforcement is declared PARTIAL: the fence catches the shapes it names — an
// id or a selector by pattern, a bare term such as "controller" by term — and
// misses a mechanism named in ordinary words ("the blue button"), exactly as
// the schema's own honest_limit states.

#let _fence-violation(text, level) = {
  if level == none { return none }
  let f = BEHAVIOR-FENCE.at(level, default: none)
  if f == none { return none }
  let lower_text = lower(text)
  for term in f.terms {
    if lower_text.contains(term) {
      return "names the forbidden term " + repr(term)
    }
  }
  for pat in f.patterns {
    if text.contains(regex(pat)) {
      return "matches the forbidden shape " + repr(pat)
    }
  }
  none
}

// ---- the clause trail -----------------------------------------------------
// CLAUSE CARDINALITY AND ORDER are document-level rules inside one block:
// given/when/then each render as an INDEPENDENT call, so a clause never meets
// its siblings and cannot know it is the second `when` or that it preceded
// one. The rules were declared in behavior_contract and enforced by nothing.
//
// The same state pattern the foundation uses closes it: each clause appends
// its kind as it is called, and the behavior block reads the trail back once
// its body has been laid out. The scope is ONE behavior block — the trail is
// cleared as the block opens — because two sibling rules are two rules, and a
// `when` in the next block does not follow this one's `then`.
#let _clause-trail = state("clause-trail", ())

#let _clause(word, body) = context {
  let level = _behavior-level.get()
  let flat = _flatten-text(body)
  let hit = _fence-violation(flat, level)
  if hit != none {
    // The fence is about WORDING, which is the author's call to make: the
    // clause renders exactly as written and the library says what it found.
    _guide("behavior.fence",
           lower(word) + " clause at level=" + level + " " + hit + " — " +
           "the behavior fence discourages naming the mechanism " +
           "(design_doc.behavior_contract.fence): restate the OBSERVABLE " +
           "outcome instead")
  }
  block(inset: (left: 10pt), [*#word* #body])
}
// The trail update sits OUTSIDE the `context` block above, because a context
// block is laid out lazily and an update inside it would not be visible to a
// read that happens later in the same body.
#let _note-clause(kind) = _clause-trail.update(t => t + (kind,))
#let given(..a, body) = { _note-clause("given"); _clause("Given", body) }
#let when(..a, body) = { _note-clause("when"); _clause("When", body) }
#let then(..a, body) = { _note-clause("then"); _clause("Then", body) }

#let _assert-clauses = context {
  let seq = _clause-trail.get()
  // A behavior block whose body carries no clause at all is left to the
  // cardinality rule below; an empty sequence means the author wrote prose
  // where clauses belong, which `then: 1..n` already reports.
  for c in CLAUSE-EXACTLY-ONE {
    let n = seq.filter(x => x == c).len()
    if n != 1 {
      _guide("behavior.clause-cardinality",
             "a behavior rule has " + str(n) + " " + c + " clause(s), expected "
             + "exactly 1 (design_doc.behavior_contract.clause_cardinality)")
    }
  }
  for c in CLAUSE-AT-LEAST-ONE {
    if seq.filter(x => x == c).len() == 0 {
      _guide("behavior.clause-cardinality",
             "a behavior rule has no " + c + " clause, expected at least 1 "
             + "(design_doc.behavior_contract.clause_cardinality)")
    }
  }
  let rank = (:)
  for (i, c) in CLAUSE-ORDER.enumerate() { rank.insert(c, i) }
  let prev = -1
  let prev-c = none
  for c in seq {
    let r = rank.at(c)
    if r < prev {
      _guide("behavior.clause-order",
             "a behavior rule's clauses are out of order: " + c + " follows "
             + prev-c + " — the expected order is " + CLAUSE-ORDER.join(", ")
             + " (design_doc.behavior_contract.clause_order)")
    }
    prev = r
    prev-c = c
  }
}

// A behavior block's `level` is REQUIRED — the fence that forbids naming a
// mechanism is defined per level, so a rule carrying no level is a rule no
// fence applies to. The check is here rather than in `_statement`, which is
// shared with kinds that carry no level at all.
//
// The clause trail is cleared as the block opens and judged after its body, so
// each rule's clauses are counted against that rule and no other.
#let behavior(..a, body) = {
  _need("behavior", "level", a.named().at("level", default: none))
  _clause-trail.update(())
  _statement("behavior", ..a, body)
  _assert-clauses
}
