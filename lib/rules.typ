// ---- the two classes of rule, and the contract helpers every block uses --
//
// This file is HAND-WRITTEN and static. It was static text inside the
// generator too — nothing in it was ever derived from the schema.
#import "schema.typ": *
#import "tokens.typ": *

// STRICT MODE turns every guideline into a hard error, for the ratchet a CI or
// an author asks for:  typst compile --input strict=1 <doc>.typ <doc>.pdf
// The default is off: a guideline reports, it does not block. The value is read
// at CALL TIME by a plain binding rather than by document `state`, because
// Typst resolves state during layout and a check running after its own panic
// site never fires.
#let STRICT = "strict" in sys.inputs and sys.inputs.at("strict") not in ("", "0", "false")

// A guideline: recorded on every render, a panic under strict.
//
// The metadata is tagged <design-guideline> so `typst query` can read the whole
// trail back in one pass. It is emitted as CONTENT, which means a guideline can
// only be recorded from a position where content is accepted — every call site
// below is inside a block body, which is why this works.
//
// `rule` NAMES the guideline so a reader can act on it; `message` says what was
// found AND what was expected. A warning that does not say what to do instead
// is noise, so no call site passes a bare complaint.
#let _guide(rule, message) = {
  if STRICT { panic("[guideline] " + rule + ": " + message) }
  [#metadata((rule: rule, message: message))<design-guideline>]
}

// DEFERRED guidance, for the blocks that return DATA rather than content.
// `stat-tile` and `pending-entry` hand a dictionary to their parent block, and
// a function whose value is a dictionary cannot also emit content — Typst
// refuses to join the two. So such a block collects its guidance INTO the
// dictionary it already returns, and the parent, which does render content,
// replays it through `_guides`. The rule reaches the same trail either way;
// only the position it is emitted from differs.
#let _guides(gs) = {
  for g in gs { _guide(g.rule, g.message) }
}


// ---- contract helpers — every block's checks route through these --------
#let _fail(kind, msg) = panic(kind + " block: " + msg)

// A MISSING required field is a guideline. The author did not say something the
// block would have carried, and the block renders without it — the reader sees
// a card that does not answer that question. That is worse, not wrong, and the
// author may have a reason: a field may be genuinely unknown while the design
// is still moving. So the library says what it expected and renders anyway.
//
// Compare `_enum` below, which stays FAIL-CLOSED. The two look similar and are
// not: a field the author never wrote is an ABSENCE the library can render
// around, while a field carrying a value outside the declared vocabulary is a
// statement the library CANNOT INTERPRET. `enforcement: "banana"` has no colour,
// no ordering and no meaning in the model — rendering it would either invent a
// meaning or silently drop what the author wrote. Guessing is the one thing a
// design document must not do, so a value the vocabulary does not contain
// remains a hard failure.
#let _need(kind, field, value) = {
  if value == none or value == "" {
    _guide(kind + ".missing-field",
           kind + " is missing " + field + " — the block contract declares "
           + field + " because a " + kind + " without it does not answer that "
           + "question, and the card renders as though it were not applicable. "
           + "Add " + field + "=, or leave it if this block has a reason not "
           + "to carry one.")
  }
}

// The title contract splits across BOTH classes of rule. PRESENCE is now a
// guideline like every other required field. LENGTH stays a guideline too.
#let _title(kind, title) = {
  _need(kind, "title", title)
  // str.len() counts UTF-8 BYTES; a title carrying a multi-byte character
  // would be measured longer than a reader sees it. The contract is about
  // characters, so count clusters. A title that is ABSENT has no length to
  // measure, and the guard is what lets presence be a guideline: without it the
  // missing-title case would reach `.clusters()` on `none` and crash with a
  // Typst type error instead of the guidance `_need` just recorded.
  if title != none and type(title) == str and title.clusters().len() > TITLE-MAX {
    _guide("title.length", kind + " title exceeds " + str(TITLE-MAX)
           + " characters: " + title)
  }
}

// AN ILLEGAL ENUM VALUE STAYS FAIL-CLOSED. See `_need` above for why this one
// does not relax: the author stated something the declared vocabulary does not
// contain, so there is no correct way to render it.
#let _enum(kind, field, value, allowed) = {
  if value != none and not allowed.contains(value) {
    _fail(kind, "invalid " + field + " " + repr(value) + " (expected one of "
          + allowed.join(", ") + ")")
  }
}

// a `lens=` attr may carry a `+` combo; each part is checked, duplicates are a
// violation, and the rendered order follows the schema's fixed lens order.
#let _lenses(kind, lens) = {
  if lens == none { return () }
  // The two authoring surfaces spell a combo differently and both are legal:
  // the markdown router passes the authored attr through as a "a+b" STRING,
  // while a native document writes the array it means. Accepting both here is
  // what lets one validation rule serve both, rather than a second copy that
  // could drift.
  let parts = if type(lens) == array {
    lens
  } else {
    lens.split("+").map(p => p.trim())
  }
  for p in parts { _enum(kind, "lens", p, LENSES) }
  if parts.dedup().len() != parts.len() {
    _fail(kind, "lens combo repeats a member: " + repr(lens))
  }
  LENSES.filter(l => parts.contains(l))
}

// ---- the behavior fence — design_doc.behavior_contract.fence ------------
// Declared enforcement=partial: it catches the shapes BEHAVIOR-FENCE names
// (an id or selector, a bare term like "controller") and misses a mechanism
// named in ordinary words ("the blue button"), exactly as the schema's own
// honest_limit states. Both halves of the fence — its terms and its patterns —
// are read from the schema, so the check applies what the schema declares and
// never a copy of it.
//
// A behavior block's clauses (given/when/then) are nested INSIDE its body and
// read the enclosing level back out of this state — _statement sets it before
// showing that body, clears it after. Typst evaluates a content argument's
// function calls at SHOW time, not at the point the argument is written, so a
// clause nested in the body sees the level this state makes visible, never a
// stale one from a previous behavior block. Same lazy-content pattern
// _census-group already uses for the entity census's two groups.
#let _behavior-level = state("behavior-level", none)

// A clause's body is markdown already routed through cmarker.render, so its
// content tree is a call, not literal text — this walks it down to the
// characters the author actually wrote, the same structural walk _len (below)
// uses to measure a card body, but returning text instead of a length.
// THE WORD BREAKS ARE IN THE TREE, and dropping them welds words together.
// Typst represents the gap between two words as its own `space` element, which
// carries no text, no children, and no body — so a walk that returns "" for
// anything it does not recognise silently deletes every space that had markup
// on either side of it. `[the #emph[form] is submitted]` came out as
// "theformis submitted".
//
// That defeats both halves of the behavior fence: a pattern anchored on a word
// boundary cannot match `withid=`, and a forbidden term sitting next to another
// word is never seen. It also reaches the section titles this walk feeds, so a
// title holding any inline markup derived a slug with the words run together.
//
// A `space` and a `linebreak` therefore render as the single space they are.
// The gaps are recovered from the tree rather than inserted between children,
// which is the difference between reconstructing what the author wrote and
// guessing at it: joining children with a separator would just as wrongly push
// a space into `#emph[design]-layer`, where the tree holds none.
#let _flatten-text(c) = {
  if type(c) == str { c }
  else if type(c) != content { "" }
  else if c.func() == [ ].func() { " " }
  else if c.func() == linebreak { " " }
  else if c.has("text") { c.text }
  else if c.has("children") { c.children.map(_flatten-text).sum(default: "") }
  else if c.has("body") { _flatten-text(c.body) }
  else { "" }
}
