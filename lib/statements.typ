// ---- the foundation statements, their trail, and the two document-level
// contracts that read it back ---------------------------------------------
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *
#import "furniture.typ": *

// ---- the foundation order, enforced ---------------------------------------
// FOUNDATION-ORDER states the order the four foundation kinds must appear in.
// That is a DOCUMENT-LEVEL rule: it compares one block against another, which
// no per-block function can do, since a function only runs when it is called
// and cannot see what was called before it.
//
// On the markdown side the aggregate's own fold reads the parsed block list and
// checks this. That fold parses markdown, so it sees nothing in a Typst layer,
// which left the order DECLARED AND UNENFORCED here: the vocabulary was
// projected, it read as enforcement to anyone who grepped for it, and nothing
// ran. A rule the schema declares and no home runs is worse than an undeclared
// one, so the gap is closed rather than documented.
//
// A state closes it, because in this mode the author calls the library directly
// and the call ORDER is the document's own. Each foundation statement appends
// its kind to the trail; the assertion reads the finished trail and panics on
// the first inversion. The scope is one CONTEXT, not the whole aggregate: a
// layer renders many chapters into one document, and a later chapter opening on
// a goal does not follow the previous chapter's principle.
#let _foundation-trail = state("foundation-trail", ())

#let _note-foundation(kind, title) = {
  if FOUNDATION-ORDER.contains(kind) {
    _foundation-trail.update(t => t + ((kind: kind, title: title),))
  }
}

// Open a fresh scope. The aggregate calls this before each context's body, so
// every context's foundation is judged on its own.
#let foundation-scope-reset = _foundation-trail.update(())

// Read the trail as it stands HERE and refuse an inversion. The read is
// `.get()`, not `.final()`, and the difference is the whole scoping story:
// `.final()` returns the state at the END of the document, which after the next
// context's reset is that context's trail, so a single final assertion would
// judge the last chapter four times and the others never. `.get()` inside a
// `context` block sees the trail accumulated up to this point, so an assertion
// placed after each chapter's body judges exactly that chapter.
#let assert-foundation-order = context {
  let rank = (:)
  for (i, k) in FOUNDATION-ORDER.enumerate() { rank.insert(k, i) }
  let prev = -1
  let prev-kind = none
  for e in _foundation-trail.get() {
    let r = rank.at(e.kind)
    if r < prev {
      _guide("foundation.order",
             "out of order: " + e.kind + " " + repr(e.title)
             + " follows " + prev-kind + " — the declared order is "
             + FOUNDATION-ORDER.join(", "))
    }
    prev = r
    prev-kind = e.kind
  }
}

// THE PER-KIND MINIMUM, read off the same trail. This is the one document-level
// contract that must notice a block NOBODY WROTE, and a function cannot report
// its own absence — but the trail can, because it is complete once the context's
// body has been laid out: a kind missing from the finished trail was never
// called.
//
// `index-only` waives the minimum for a multi-context ROOT that merely indexes
// its children. Such a root carries only genuinely cross-context foundation and
// points down to each context for the rest; holding it to the full minimum would
// force it to restate a goal a context already owns, which is the restatement
// the layer exists to prevent. The waiver is an ARGUMENT rather than a guess:
// nothing in the document's own text distinguishes an index root from a leaf
// that forgot its foundation, so the author declares which one it is.
#let assert-foundation-cardinality(index-only: false) = context {
  if not index-only {
    let present = _foundation-trail.get().map(e => e.kind).dedup()
    // A document carrying NO foundation at all is not a document that failed
    // the minimum — it is a document not carrying a foundation, a behavior-rule
    // sheet or a reference page. The minimum binds a document that declares a
    // foundation, and no other.
    if present.len() > 0 {
      for k in FOUNDATION-REQUIRED {
        if not present.contains(k) {
          _guide("foundation.cardinality",
                 "declares no " + k + " — the cardinality guideline expects at "
                 + "least one of each of: " + FOUNDATION-REQUIRED.join(", ")
                 + ". Declare one, or keep the layer as it is if this context "
                 + "has a reason not to carry one "
                 + "(design_doc.foundation_cardinality)")
        }
      }
    }
  }
}

// A clause's body is markdown already routed through cmarker.render, so its
// content tree is a call, not literal text — this walks it down to the
// characters the author actually wrote, the same structural walk _len (below)


// ---- the statement block: accent rule, title, body, FOOTER furniture ----
// The footer carries lens / enforcement as DECLARED furniture rather than
// markup convention. It carries no pointer to an enforcer: `enforcement` names
// the KIND of enforcement, and finding which check holds a property is the
// gate's own job, not a claim the document makes and a human keeps current.
#let _statement(kind, title: none, lens: none, enforcement: none,
                since: none, level: none, adr: none,
                ..rest, body) = {
  _title(kind, title)
  // Record the call for the document-level order check. A foundation kind is
  // the only kind that lands in the trail; every other statement passes through.
  _note-foundation(kind, title)
  // EVERY unrecognized attribute fails, not just the retired two. A block
  // signature ends `..rest`, so an unknown name is silently dropped: `lense=`
  // for `lens=`, a plain typo — the block renders without it and looks
  // correct, which is the worst shape a mistake can take. The named parameters
  // ARE the allowed set, so anything reaching `rest` is outside the contract.
  // The retired names keep their own message, because "unknown" would send an
  // author hunting a typo that is not there.
  for (k, _) in rest.named() {
    if k == "script" {
      _fail(kind, "attribute script= was retired. enforcement names the KIND of "
            + "enforcement; which check holds a property is the gate's job to "
            + "find, not a pointer the document carries and a human keeps "
            + "current. Remove it")
    }
    if k == "id" {
      _fail(kind, "attribute id= was retired. It existed to be cited from "
            + "prose and nothing cited it; a block is referenced by its section "
            + "anchor. Remove it")
    }
    _fail(kind, "unknown attribute " + k + "= — the block contract declares no "
          + "such attr, and an unrecognized name would otherwise be dropped "
          + "silently, rendering a block that looks right and is missing what "
          + "you wrote (schema design_doc.blocks)")
  }
  _enum(kind, "enforcement", enforcement, ENFORCEMENTS)
  _enum(kind, "level", level, BEHAVIOR-LEVELS)
  let ls = _lenses(kind, lens)
  if since != none and since.match(regex("^\d{4}-\d{2}-\d{2}$")) == none {
    _fail(kind, "since must be YYYY-MM-DD, got " + repr(since))
  }
  let c = KIND-COLOR.at(kind, default: luma(120))
  let furniture = ()
  if ls.len() > 0 { furniture.push(pill(..ls)) }
  if enforcement != none {
    furniture.push(chip(enforcement, tone: ENFORCEMENT-COLOR.at(enforcement)))
  }
  if since != none { furniture.push(chip("since " + since)) }
  if level != none { furniture.push(chip("level: " + level)) }
  // A behavior block's clauses (given/when/then) are nested INSIDE `body` and
  // read their enclosing level back out of this state — set before `body` is
  // shown, cleared after, the same lazy-content pattern _census-group already
  // uses for the entity census's two groups. Typst evaluates a content
  // argument's function calls at SHOW time, not at call time, so a clause
  // nested in `body` sees the level this update makes visible, never a stale
  // one from a previous behavior block.
  if kind == "behavior" { _behavior-level.update(level) }
  block(width: 100%, inset: (left: 9pt, rest: 7pt), fill: c.lighten(94%),
        stroke: (left: 2.5pt + c), radius: (right: 2pt), breakable: false,
    [
      #text(size: 6.5pt, fill: c, weight: "bold", tracking: 0.4pt, upper(kind))
      #linebreak() #text(weight: "bold", size: 10pt, title)
      #linebreak() #body
      #if furniture.len() > 0 [ #v(4pt) #furniture.join(h(3pt)) ]
    ])
  if kind == "behavior" { _behavior-level.update(none) }
  v(0.45em)
}

// ---- the per-kind wrappers, built by a closure factory --------------------
// THE WRAPPER IS WHERE A PER-KIND REQUIREMENT CAN LIVE. `_statement` is one
// shared body serving every statement kind, so it cannot demand `enforcement`
// without demanding it of goal, no-goal and principle too. Here the kind is
// known, so each wrapper asserts exactly what its own declaration marks
// (required).
//
// The generator emitted one `#let <kind>(..a, body) = ...` per foundation kind
// with those assertions inlined. No codegen is needed for that: a closure
// factory produces the same functions from the same data.
//
// WHICH ATTRIBUTES ARE REQUIRED is read from the block DECLARATIONS — the same
// regex over the same prose the generator ran, so the requirement is derived
// from one place rather than restated.
//
// Two shapes appear in the declarations and both mean required:
//   level=interface|boundary (required)      a field with its vocabulary
//   owner (required, the unit responsible)   a bare field
#let _ATTR-REQ = regex("\b([a-z_]+)\s*(?:=[^;(]*?)?\((?:required)\b")

#let _required-attrs(kind) = {
  let decl = schema.design_doc.blocks.at(kind, default: none)
  if type(decl) != str { return () }
  let found = ()
  for m in decl.matches(_ATTR-REQ) {
    let f = m.captures.at(0)
    // `title` is already required by _statement for every kind, so asserting it
    // in the wrapper too would report one omission as two violations.
    if f != "title" and not found.contains(f) { found.push(f) }
  }
  found
}

#let _mk(kind) = {
  let req = _required-attrs(kind)
  (..a, body) => {
    let named = a.named()
    for f in req { _need(kind, f, named.at(f, default: none)) }
    _statement(kind, ..a, body)
  }
}

// The whole foundation vocabulary, as functions, keyed by the schema's own kind
// names. `#let (goal, no-goal, ...) = ...` is not destructurable by a computed
// key, so each kind is bound explicitly below — the FUNCTIONS are data-driven,
// only the four bindings are written out. A kind the schema declares and this
// file does not bind is caught by the widget-coverage check, which asks the
// compiled library whether every declared kind resolves to a callable.
#let STATEMENTS = FOUNDATION-ORDER.fold((:), (acc, k) => acc + ((k): _mk(k)))

#let goal = STATEMENTS.at("goal")
#let no-goal = STATEMENTS.at("no-goal")
#let invariant = STATEMENTS.at("invariant")
#let principle = STATEMENTS.at("principle")
