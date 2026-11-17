// ---- the design unit: one required shape at every depth -----------------
//
// A layer is a tree of units, and a unit is the same thing at every depth: it
// says what it is, what it exposes, what always holds, what it changes outside
// itself, how that is verified, and which code paths realize it. Those are the
// sections `design_doc.unit_contract` declares, and this file is their one
// renderer.
//
// EVERY FIELD IS REQUIRED, AND A MISSING ONE FAILS. That is the opposite of
// the component card this block shares its anatomy with, and the difference is
// deliberate. A component card's answers are optional so that a unit with no
// failure mode says nothing about failure. Here the question is always asked,
// so the answer is always written: an EMPTY LIST is how a unit says "none",
// and it renders as the declared empty label. The rule is to say none and
// never to invent one — and a field the author did not write at all is a
// question nobody answered, which the reader cannot tell from "none".
//
// THE ANATOMY IS THE COMPONENT CARD'S. The frame, the role pill, and the
// labelled rows come from `native.typ` — `_card`, `_unit-furniture`,
// `_answer-rows`, `_answer-row` — so a reader who has learned one card reads
// this one. What this file adds is the required shape, the nesting, and the
// code paths.
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *
#import "furniture.typ": *
#import "semantic.typ": *
#import "statements.typ": _foundation-unit-close, _foundation-unit-open
#import "native.typ": (
  _answer-row, _answer-rows, _card, _card-anatomy, _host-level, _hosted-unit,
  _sentences, _unit-furniture,
)

// The neutral accent. A unit's card marks STRUCTURE, and the tint axis is
// reserved for ownership, so a unit does not spend a domain colour.
#let _UNIT-ACCENT = "slate"

// Every unit call appends its id here, and the next call reads the trail back,
// so a second use of an id fails AT THE SECOND CALL rather than at an assertion
// someone has to remember to place. The trail is never reset: an id is unique
// across the whole layer, not within one chapter.
#let _unit-trail = state("unit-trail", ())

// A heading has six levels, in the rendered document and in the Markdown
// projection alike. The chapter is level one, so a unit directly in a document
// body is level two and five units nest there; four nest inside a `section`,
// three inside a `subsection`.
//
// The projection writes the layer as ONE Markdown document: the root design is
// its level-one title and each context document is a level-two heading below
// it. A unit in a context document is therefore one level lower in the
// projection than on the page, and the limit is judged where it binds first,
// so the render never accepts a unit the projection cannot address.
#let _UNIT-LEVEL-MAX = 6

// Whether the unit is being laid out in a context document's chapter. The
// aggregate heads every document with a level-one heading labelled
// `ctx-<name>`, and the root's name is `root`. A unit compiled outside the
// aggregate has no chapter above it and is judged as the root is.
#let _in-context-document() = {
  let chapters = query(heading.where(level: 1).before(here()))
  if chapters.len() == 0 or not chapters.last().has("label") { return false }
  let name = str(chapters.last().label)
  name.starts-with("ctx-") and name != "ctx-root"
}

#let _unit-fail(id, msg) = _fail(
  "unit",
  (if type(id) == str and id != "" { repr(id) + " " } else { "" }) + msg,
)

#let _unit-blank(value) = (
  value == none or (type(value) == str and value.trim() == "") or value == []
)

// A UNIT FIELD IS PROSE, AND ONLY PROSE. The five sections are read by three
// carriers — the page, the Markdown projection, and a folder's `AGENTS.md` —
// and the last two write a text section as a paragraph and a list section as
// one entry per item. So a field holds what a sentence holds: text, emphasis,
// inline code, a link, a reference, mathematics, and the library's own inline
// citations — and one more thing a contract often needs, a CODE BLOCK, such as
// the command that verifies it. The projection writes a code block as a
// fenced block, with a fence longer than any run of backticks in its text, so
// the block ends where it does and never swallows what follows. The title is
// the exception: it is one heading line, and a code block there is refused.
// Anything else has no form in Markdown — a list, a footnote, a box, a
// heading, a `context` — and the page would draw it while the projection and
// the generator stopped on a layer the render had accepted. The render
// refuses it here, naming the content function.
//
// THE RENDER IS THE STRICTER OF THE TWO, and that is the guarantee: whatever
// passes here the projection can express. The reverse does not hold. The
// projection reads a field in its own mode, where a library citation is a
// semantic node rather than the chip the page draws, and it walks through
// layout wrappers this check refuses. The names below are the content
// functions `design-context` projects as prose; a function added there is
// added here, and `design-units.test.sh` renders and projects one field of
// each to hold the two together.
#let _UNIT-PROSE = (
  "sequence", "styled", "text", "space", "symbol", "smartquote", "linebreak",
  "parbreak", "strong", "emph", "raw", "link", "ref", "equation", "frac",
  "attach", "root", "vec",
)
// Where each of those keeps the content it wraps.
#let _UNIT-PROSE-CHILDREN = (
  "children", "child", "body", "num", "denom", "base", "t", "b", "tl", "tr",
  "bl", "br", "radicand", "index",
)
#let _UNIT-LISTS = ("item", "list", "enum", "terms")
// The semantic kinds of the library's inline citations.
#let _UNIT-INLINE-KINDS = (
  "term-reference", "context-reference", "adr", "lens-pill", "pill",
)

// The first content function in `value` that is not prose, or none. What
// stands between the library's inline marks is one of its own citations and is
// not read.
#let _unit-not-prose(value) = {
  if type(value) == array {
    let inside = 0
    for part in value {
      if type(part) == content and part.func() == metadata {
        if part.value == _INLINE-OPEN { inside += 1; continue }
        if part.value == _INLINE-CLOSE { inside -= 1; continue }
      }
      if inside > 0 { continue }
      let found = _unit-not-prose(part)
      if found != none { return found }
    }
    return none
  }
  if type(value) != content { return none }
  let name = repr(value.func())
  if value.func() == metadata {
    let label = value.at("label", default: none)
    // A guideline note is a diagnostic the render records, never content.
    if label == <design-guideline> { return none }
    // In the projection a library citation is its semantic node.
    if (
      context-projection and label == <design-semantic>
        and type(value.value) == dictionary
        and value.value.at("kind", default: none) in _UNIT-INLINE-KINDS
    ) { return none }
    return name
  }
  // A term citation records itself in a state the page reads; in the
  // projection that update stands bare beside the citation's node.
  if context-projection and name == "state-update" { return none }
  if name not in _UNIT-PROSE { return name }
  let fields = value.fields()
  if name == "link" and type(fields.at("dest", default: none)) != str {
    return "link to a label or a location"
  }
  for key in _UNIT-PROSE-CHILDREN {
    let found = _unit-not-prose(fields.at(key, default: none))
    if found != none { return found }
  }
  none
}

// Whether `value` holds a code block: raw text set as a block.
#let _unit-code-block(value) = {
  if type(value) == array { return value.any(_unit-code-block) }
  if type(value) != content { return false }
  if value.func() == raw { return value.at("block", default: false) == true }
  let fields = value.fields()
  _UNIT-PROSE-CHILDREN.any(key => _unit-code-block(fields.at(key, default: none)))
}

#let _unit-check-prose(id, where, value) = {
  let found = _unit-not-prose(value)
  if found == none { return }
  if found in _UNIT-LISTS {
    _unit-fail(id, where + " holds a list — unsupported Typst content "
      + "function 'item' in a unit field. The Markdown projection and a "
      + "folder's AGENTS.md carry a text section as a paragraph and a list "
      + "section as one entry per item, so a list written inside a field has "
      + "no form there. State each point as its own item of interface, "
      + "invariants or side-effects, and write the other fields as sentences")
  }
  _unit-fail(id, where + " holds " + found + " — unsupported Typst content "
    + "function '" + found + "' in a unit field. A unit field is prose: "
    + "text, emphasis, inline code, a code block, a link to a URL or a "
    + "path, a reference, mathematics, and the library's inline citations "
    + "(term, ctx, adr, pill, lens-pill). The Markdown projection and a "
    + "folder's AGENTS.md carry a field as a paragraph or as one entry of a "
    + "list, and this content has no form there. Say it in words, or move "
    + "it into the unit's body")
}

// ONE PATH, by the spelling rule the schema declares. Whether the path EXISTS
// is not visible from inside a compile — that is the gate's half.
#let _unit-check-path(id, path, forbidden) = {
  if type(path) != str {
    _unit-fail(id, "path " + repr(path) + " is not a string — a path is "
      + "written as a repo-relative string such as \"src/billing\"")
  }
  if path == "" { _unit-fail(id, "lists an empty path") }
  if path.starts-with("/") {
    _unit-fail(id, "path " + repr(path) + " is absolute — a unit path is "
      + "relative to the repository root")
  }
  for ch in forbidden {
    if path.contains(ch) {
      _unit-fail(id, "path " + repr(path) + " contains " + repr(ch)
        + " — a unit path is one exact directory, never a pattern")
    }
  }
  if path == "." {
    _unit-fail(id, "path \".\" names the repository root, which no unit may "
      + "claim as its own folder")
  }
  for segment in path.split("/") {
    if segment == "" {
      _unit-fail(id, "path " + repr(path) + " has an empty segment — write "
        + "it without a leading, trailing, or doubled slash")
    }
    if segment == "." or segment == ".." {
      _unit-fail(id, "path " + repr(path) + " has a " + repr(segment)
        + " segment — a unit path is written from the repository root")
    }
  }
}

#let _unit-validate(id, title, data, paths, extra) = {
  if UNIT-CONTRACT == none {
    _fail("unit", "the schema in use declares no design_doc.unit_contract, so "
      + "the unit block has no sections to render. The schema this library "
      + "was projected with predates the unit block; project the library "
      + "with a schema that declares it")
  }
  for (name, _) in extra.named() {
    _fail("unit", "unknown attribute " + name + "= — the unit contract "
      + "declares id, title, " + UNIT-SECTION-FIELDS.join(", ")
      + " and paths, and an unrecognized name would otherwise be dropped "
      + "silently (schema design_doc.blocks.unit)")
  }
  if extra.pos().len() > 1 {
    _fail("unit", "takes one optional body, got " + str(extra.pos().len())
      + " positional arguments")
  }
  if id == none or id == "" {
    _fail("unit", "is missing id — every unit carries a kebab-case id, "
      + "unique across the layer, that its anchor, its folder contract, and "
      + "the context projection resolve against")
  }
  if type(id) != str or id.matches(regex(UNIT-CONTRACT.id_pattern)).len() == 0 {
    _fail("unit", "id " + repr(id) + " is not a kebab-case slug — expected "
      + "lowercase words joined by single hyphens, such as "
      + "\"billing-ledger\" (schema design_doc.unit_contract.id_pattern)")
  }
  if _unit-blank(title) {
    _unit-fail(id, "is missing title — the unit's name heads its contract")
  }
  if type(title) != str and type(title) != content {
    _unit-fail(id, "title must be a string or content, got " + repr(title))
  }
  _unit-check-prose(id, "title", title)
  if _unit-code-block(title) {
    _unit-fail(id, "title holds a code block — a title is the one line that "
      + "heads the unit's contract, in the page, the Markdown projection, and "
      + "a folder's AGENTS.md alike. Write the code inline, with single "
      + "backticks, or move the block into a field or the unit's body")
  }
  for s in UNIT-SECTIONS {
    let value = data.at(s.field)
    if s.shape == "list" {
      if value == none {
        _unit-fail(id, "is missing " + s.field + " — every unit answers it. "
          + "Write the list, or write an empty list `()` when the honest "
          + "answer is none: it renders as " + repr(UNIT-CONTRACT.empty_label)
          + ", and a field left out is a question nobody answered")
      }
      if type(value) != array {
        _unit-fail(id, s.field + " must be a list, got " + repr(value)
          + ". A one-item list needs its trailing comma: `(\"one item\",)`")
      }
      for item in value {
        if _unit-blank(item) {
          _unit-fail(id, s.field + " holds an empty item — remove it, or "
            + "write an empty list when there is nothing to state")
        }
        if type(item) != str and type(item) != content {
          _unit-fail(id, s.field + " item " + repr(item) + " is not a string "
            + "or content")
        }
        _unit-check-prose(id, "an item of " + s.field, item)
      }
    } else {
      if _unit-blank(value) {
        _unit-fail(id, "is missing " + s.field + " — every unit states it. "
          + "When there is none, say so in words")
      }
      if type(value) != str and type(value) != content {
        _unit-fail(id, s.field + " must be a string or content, got "
          + repr(value))
      }
      _unit-check-prose(id, s.field, value)
    }
  }
  if paths == none {
    _unit-fail(id, "is missing paths — every unit lists the directories that "
      + "realize it. A unit that only groups other units has no code of its "
      + "own and writes an empty list `()`")
  }
  if type(paths) != array {
    _unit-fail(id, "paths must be a list, got " + repr(paths)
      + ". A one-item list needs its trailing comma: `(\"src/billing\",)`")
  }
  let seen = ()
  for path in paths {
    _unit-check-path(id, path, UNIT-CONTRACT.path_forbidden_characters)
    if seen.contains(path) {
      _unit-fail(id, "lists path " + repr(path) + " twice")
    }
    seen.push(path)
  }
}

// THE STYLE HALF — guidelines, never failures. A unit that says too much in
// one place still states a true contract.
#let _unit-guides(id, title, data) = {
  if type(title) == str and title.clusters().len() > TITLE-MAX {
    _guide("title.length", "unit title exceeds " + str(TITLE-MAX)
      + " characters: " + title)
  }
  for s in UNIT-SECTIONS {
    let value = data.at(s.field)
    if s.shape == "list" {
      for item in value {
        if type(item) == str and _sentences(item) > 3 {
          _guide("unit.item-sentences", "unit " + repr(id) + " " + s.field
            + " holds an item of " + str(_sentences(item)) + " sentences. An "
            + "item states one fact; expected at most 3 sentences, with a new "
            + "item at each change of subject.")
        }
      }
    } else if type(value) == str and _sentences(value) > 5 {
      _guide("unit.section-sentences", "unit " + repr(id) + " " + s.field
        + " runs to " + str(_sentences(value)) + " sentences. Expected at "
        + "most 5: the contract is the summary, and the unit's body is where "
        + "depth goes.")
    }
  }
}

#let _unit-value(section, value) = {
  if section.shape != "list" { return value }
  if value.len() == 0 {
    return text(fill: MUTED, style: "italic", UNIT-CONTRACT.empty_label)
  }
  list(tight: true, ..value)
}

#let unit(
  id: none, title: none, overview: none, interface: none, invariants: none,
  side-effects: none, verification: none, paths: none, ..rest,
) = {
  let data = (
    "overview": overview, "interface": interface, "invariants": invariants,
    "side-effects": side-effects, "verification": verification,
  )
  _unit-validate(id, title, data, paths, rest)
  let body = if rest.pos().len() == 0 { none } else { rest.pos().first() }
  let anchor = UNIT-CONTRACT.anchor_prefix + id
  _unit-guides(id, title, data)
  if context-projection {
    // The node carries the section table and the empty label it was rendered
    // with. The projection reads them from here, so the schema keeps exactly
    // one reader and the Markdown cannot label a section differently from the
    // page.
    return [#_semantic-target(anchor)#semantic("unit", fields: (
      id: id, title: title, sections: UNIT-SECTIONS,
      "empty-label": UNIT-CONTRACT.empty_label,
      overview: overview, interface: interface,
      invariants: invariants, "side-effects": side-effects,
      verification: verification, paths: paths, body: body,
    ))]
  }
  context {
    let earlier = _unit-trail.get()
    if earlier.contains(id) {
      _unit-fail(id, "is declared twice — a unit id is unique across the "
        + "whole layer, because its anchor, its folder contract, and the "
        + "context projection all select one unit by it")
    }
  }
  _unit-trail.update(ids => ids + (id,))
  let anatomy = _card-anatomy(_UNIT-ACCENT)
  let fields = UNIT-SECTIONS.map(s => (s.field, s.label))
  let shown = (:)
  for s in UNIT-SECTIONS { shown.insert(s.field, _unit-value(s, data.at(s.field))) }
  let rows = _answer-rows(shown, fields: fields)
  context {
    let level = _host-level() + 1
    let projected = level + if _in-context-document() { 1 } else { 0 }
    if projected > _UNIT-LEVEL-MAX {
      let lower = if projected > level {
        (" of a context document, which the Markdown projection writes at "
          + "level " + str(projected))
      } else { "" }
      _unit-fail(id, "is nested at heading level " + str(level) + lower
        + " — a design document has " + str(_UNIT-LEVEL-MAX) + " heading "
        + "levels, and the Markdown projection cannot address a unit below "
        + "the last one. Flatten the nesting, or split the unit's subtree "
        + "into sibling units")
    }
    [#_review-place("unit", id: id)#heading(level: level)[#title]#label(anchor)]
    _card(
      accent: _UNIT-ACCENT,
      title: text(font: "DejaVu Sans Mono", size: RENDERER-COMPACT, id),
      furniture: _unit-furniture(role: "unit", color: anatomy.color),
    )[
      #set par(justify: false)
      // A row stays whole across a page break, so a label is never stranded
      // at the foot of a page above the answer it names. The card itself may
      // break BETWEEN rows: a long contract is still one card.
      #for (i, r) in rows.enumerate() [
        #if i > 0 [ #v(2.5pt) ]
        #block(width: 100%, breakable: false, _answer-row(
          r, size: RENDERER-BODY, label-size: RENDERER-META,
          color: anatomy.color,
        ))
      ]
      // The rule and the paths row travel together, so a page never ends on
      // a rule that separates the contract from nothing.
      #block(width: 100%, breakable: false)[
        #v(3pt) #line(length: 100%, stroke: 0.4pt + HAIRLINE) #v(3pt)
        #_answer-row(
          ("paths", if paths.len() == 0 {
            text(fill: MUTED, style: "italic", UNIT-CONTRACT.empty_label)
          } else {
            paths.map(p => text(
              font: "DejaVu Sans Mono", size: RENDERER-COMPACT, p,
            )).join(h(0.9em))
          }),
          size: RENDERER-BODY, label-size: RENDERER-META, color: anatomy.color,
        )
      ]
    ]
    v(0.45em)
    // The body is the unit's own scope for foundation statements: the marks
    // bracket it in the foundation trail, so the document-level order and
    // minimum never read a statement a unit carries.
    if body != none {
      _foundation-unit-open
      _hosted-unit(level, _UNIT-LEVEL-MAX, body)
      _foundation-unit-close
    }
  }
}
