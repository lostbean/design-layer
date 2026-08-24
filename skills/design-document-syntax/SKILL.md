---
name: design-document-syntax
description: The format specification for a design layer — the Typst that `design.typ` and `CONTEXT.typ` are authored in, the markdown that `docs/adr/` and `COVERAGE.md` stay in, and the contracts the renderer and the gate decide pass or fail on. Covers the artifact set and where each file lives, the bindings a design document exports, the `terms` array a glossary exports, ADR anchors, the block functions and their required arguments, the section spine, the pending ledger, the behavior clause calls and `level`, the entity census, and how the renderer is pinned. Use when writing or editing a `design.typ`, a `CONTEXT.typ`, or an ADR; when a compile or gate run reports a violation and the correct call is needed; when asking "what function do I call for this?", "how do I write an invariant / a behavior rule / an entity", "where does this file go", "why did my foundation fail to compile"; or when bootstrapping a design layer in a repo that has none.
domains: [engineering]
status: ship
---

# Design document syntax

A design layer is authored Typst. `design.typ` and `CONTEXT.typ` are Typst
modules that call a projected library; the files under `docs/adr/`, plus
`CONTEXT-MAP.md` and `COVERAGE.md`, are plain markdown holding declared
anchors. A renderer compiles the layer into one PDF, and a gate decides whether
the layer is well-formed.

This document is the format specification: what you may write, where it goes,
and which rules a machine actually decides. It does not say when a system is
worth designing, how deep to go, or whether a design is any good. Those are
judgment calls made with the rendered document in hand.

## How to read this document

The block vocabulary has one live demonstration: `fixtures/gallery.typ`
in the design-layer repository. Every function the library projects for an
author appears there once, written in real syntax, and a self-test fails if a
projected function is missing from it or stops rendering. **Read the gallery
for syntax; read the tables below as an index into it.** A table here tells you
which function to reach for and what its contract requires. The gallery shows
you the function working.

Three words are used precisely throughout:

- **Machine-checked** — the renderer or a gate script decides pass or fail on
  this, fail-closed. Break it and you get a violation naming the file and the
  line. This severity is reserved for what makes the OUTPUT wrong: a value
  outside a declared vocabulary, a citation or diagram edge that resolves to
  nothing, a malformed date or altitude. The renderer would have to invent a
  meaning to continue, and a design document must never guess.
- **Guideline** — the renderer holds the rule, REPORTS it on every render, and
  renders anyway. The report names the rule, the offending item, and what was
  expected; the run ends with a count summary; the exit code does not change.
  This is the severity of every STRUCTURAL opinion — which foundation kinds a
  context declares and in what order, whether a required argument was filled,
  the shape of a clause or a cardinality — because a design legitimately
  changes shape and a layer missing one level may be missing it for a good
  reason. `DESIGN_STRICT=1`, or the `lint` sweep (§6), promotes every guideline
  to a hard error for a repo that wants the stricter ratchet.
- **Convention** — no check enforces it at all. It is stated because a layer
  that ignores it reads badly, but nothing will stop you.

The split matters when reading the rest of this document: "required" almost
always means **guideline-required** — the renderer expects it and says so, and
your document still renders without it.

Every command below is a `nix run` against the design-layer flake. A host repo
copies nothing in: the scripts, the schema, and the renderer travel together as
one pinned bundle, and the host stores only its own sources.

---

## 1 · The artifact set and where it lives

The design layer is **three artifacts owning three concerns**, joined by
cross-references.

| Artifact                            | Owns                                                                 | Never contains                                                   |
| ----------------------------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `design.typ` → a chapter of the PDF | the design itself — the current, actual snapshot, presented visually | a restated definition; a re-argued decision — cite the other two |
| `CONTEXT.typ`                       | semantics — the canonical definition, one term per slug              | implementation detail                                            |
| `docs/adr/NNNN-slug.md`             | rationale — the canonical argument, one decision per anchor          | a duplicate of either of the above                               |

The design document is not a link farm. It presents structure, narrative, and
visuals in full, and points out only where a word needs knowing or a reader
would genuinely ask "why?". Definitions and rationale have canonical homes
elsewhere; the design document states what the design **is**.

### The ADRs stay markdown

Authoring in `design.md` + `CONTEXT.md` was removed; the Typst modules are the
only authoring surface for the design and its glossary. The ADRs did not move
with them, and neither did `CONTEXT-MAP.md` or `COVERAGE.md`. They were never
the authoring surface — they are indexes and records a reader browses in a
forge — so they stay plain markdown with the anchor contract of §2.

A layer still carrying a `design.md` is **refused by name**: the aggregate and
the integrity check both name every leftover markdown source and point at the
migration, rather than walking past it. Walking past it would report "no design
layer" against a directory visibly full of design documents, and send the
reader after the wrong fault.

A dangling design-ish reference is **machine-checked**: the gate's integrity
check resolves every one and reports the ones that do not land.

### Single-context layout — the default

```
docs/design/design.typ         # the design source (authored)
docs/design/CONTEXT.typ        # the glossary — declares the term slugs
docs/design/design-layer.pdf   # generated — the ONE rendered document
docs/COVERAGE.md               # the coverage map (optional)
docs/adr/0001-slug.md          # append-only decision records
```

### Multi-context layout

```
docs/CONTEXT-MAP.md                # entry: links each context's CONTEXT.typ
docs/design/design.typ             # the root design source
docs/design/design-layer.pdf       # generated — ONE document, the whole layer
docs/design/<context>/design.typ   # a context's design source
docs/design/<context>/CONTEXT.typ  # that context's glossary
docs/COVERAGE.md
docs/adr/NNNN-slug.md              # central — rationale often spans contexts
```

`<context>` is exactly **one** path segment in kebab-case, matching
`^[a-z0-9][a-z0-9-]*$`. A context folder holds only that context's layer files.

Split into contexts when a **second real vocabulary** appears — not on module
count. Four design documents for a five-module project is the smell. The one
declared exception: a core model context and its first peer are exempt, because
the core model's vocabulary counts as a second vocabulary by construction.
Every context beyond those two earns its place by carrying real vocabulary of
its own.

### The layer is homed, never colocated

Every layer artifact lives under `docs/` at its declared home. The design
references the system by path; the system's source directories never host layer
files. A context is a unit of the design, not of the source tree, so its folder
is `docs/design/<context>/` even when the context happens to match one source
directory exactly.

**Machine-checked.** The declared homes are:

| Basename           | Home                                                             |
| ------------------ | ---------------------------------------------------------------- |
| `CONTEXT-MAP.md`   | `docs/CONTEXT-MAP.md`                                            |
| `COVERAGE.md`      | `docs/COVERAGE.md`                                               |
| `design.typ`       | `docs/design/design.typ` or `docs/design/<context>/design.typ`   |
| `CONTEXT.typ`      | `docs/design/CONTEXT.typ` or `docs/design/<context>/CONTEXT.typ` |
| `design-layer.pdf` | `docs/design/design-layer.pdf`                                   |

A file carrying one of those basenames found anywhere else is a mishomed stray
and fails the gate.

Two consequences follow, both machine-checked:

- **The layer renders as ONE document.** `docs/design/design-layer.pdf` is the
  whole layer; a context renders as a chapter of it and emits no sibling PDF.
  A per-context `design.pdf` is a stray left by an older render.
- **In multi-context mode there is no root glossary.** Every glossary lives in
  its context folder. A `docs/design/CONTEXT.typ` alongside context folders is
  an orphan.

### `COVERAGE.md`

`docs/COVERAGE.md` is the coverage map: a table with one row per meaningful
system part, each row carrying a status that says whether the design covers it.
Its **name, its home, and the integrity of its links** are machine-checked like
any other layer artifact — a row pointing at a design section that does not
exist fails the gate.

The same breadth axis can also be carried **inside** a design document, as a
`#coverage(…)` call (§3). There the statuses are machine-checked by the
renderer: a row must be `captured`, `standard`, or `out-of-scope`, and a row
that is not `captured` must state a reason, so an absence is a recorded
decision rather than an oversight.

What earns a part one status rather than another is a judgment call this
specification does not make. The file is optional; a layer without one is
well-formed.

### The context map declares relationships

`docs/CONTEXT-MAP.md` is more than a link index. Each context entry carries a
one-line description of what that context owns, and a relationships section
declares every cross-context relationship in the DDD vocabulary, with its
direction:

`customer/supplier` · `conformist` · `anti-corruption layer` · `shared kernel` ·
`separate ways`

A term shared across contexts names exactly one **owning** context. Every other
context cites the owner's slug and never redefines it. The map owns
context-level relationships only — fine-grained structural relations, module
seams, and flows live in the root design document's system-at-a-glance section.

---

## 2 · Declarations and references

### A design document is a module

`design.typ` is a Typst module. It imports the projected library and exports
its content as bindings the aggregate reads:

```typst
#import "../.render/designlib.typ": *

#let title = [Scheduling]

#let body = [
  #section(title: "00 Foundation", lead: "What this context is for.", body: [
    #goal(title: "Onboard any repository")[…]
  ])
]
```

| Binding      | Contract                                                                                                       |
| ------------ | -------------------------------------------------------------------------------------------------------------- |
| `title`      | the chapter's display title; a content block. Optional — the directory name stands in when it is absent        |
| `body`       | the document's whole content, placed under the chapter heading. This is what the aggregate renders             |
| `index_only` | optional boolean; legal on a multi-context **root** and changes what the foundation contract requires — see §4 |

**The page shell is not the document's to apply.** The aggregate supplies one
shell for the whole layer — the title page, the table of contents, the running
footer, the per-chapter front pages. A `design.typ` exports `body` and calls no
`design-doc`, so a context cannot decide page size, numbering, or colour.

A **standalone reference page** that is not part of any layer is the one
exception: it is compiled on its own, so it applies its own shell with
`#show: design-doc.with(eyebrow: …, hero_title: …, lede: …, footer: …)`. That
is how `fixtures/gallery.typ` is written.

### A glossary declares a `terms` array

`CONTEXT.typ` exports one binding, `terms`: an array of entries, each carrying
a slug, a title, and a body, **in that order**.

```typst
#let terms = (
  (
    slug: "term-pending-ledger",
    title: [Pending ledger],
    body: [
      The single section of a design document holding every intentionally-open
      state.

      _Avoid_: backlog — implies work queued rather than design running ahead.
    ],
  ),
  (
    slug: "term-behavior-rule",
    title: [Behavior rule],
    body: [A conditional rule stating what a surface does, cited from
      #term("term-pending-ledger") where it runs ahead.],
  ),
)
```

- **Slug**: lowercase; runs of non-alphanumeric characters collapse to single
  hyphens; leading and trailing hyphens stripped. Machine-checked against
  `^term-[a-z0-9]+(-[a-z0-9]+)*$`.
- **One term per slug**, and a slug is **never repurposed** for a different
  concept. Retire the term and mint a new slug; rebinding silently rewrites
  every citation that trusted it. Duplicate slugs across the layer are
  machine-checked.
- **Order is fixed and machine-checked**: `slug`, then `title`, then `body`. An
  entry whose `body` does not follow its `title` is reported by name.
- **`title` and `body` are content blocks**, so they may carry markup — and
  they may cite other terms and contexts, because the aggregate splices them
  into a document where the library is already in scope. **`CONTEXT.typ`
  imports nothing**; adding an import there is not how the scope arrives.
- **Definition shape** (convention): one or two sentences stating what the
  concept **is** — never what the system does with it.
- **`_Avoid_:` line** (optional, convention): names the rejected synonyms with
  a reason, so a later writer sees why a candidate lost instead of
  re-litigating it.

### ADR anchors — `docs/adr/`

```markdown
# The design layer lives entirely under docs/

<a id="adr-0004"></a>

Colocating layer files beside source made them invisible to the gate's homing
check and let two copies of one context drift. Every layer artifact now has one
declared home under `docs/`.
```

- **Filename**: `NNNN-slug.md` — four digits, then kebab-case.
  Machine-checked against `^[0-9]{4}-[a-z0-9-]+\.md$`.
- **Anchor**: `<a id="adr-NNNN"></a>` on its own line, under the file's first
  `# ` title. Exactly one per file — zero, two, or a malformed one each fail.
- **Lockstep, machine-checked**: the `NNNN` is identical in the filename, in
  the anchor id, and in every citation of it.
- **Title shape** (convention): the title **is** the decision statement. No
  `ADR-NNNN:` prefix in the title text — the number lives in the filename and
  the anchor.
- **Append-only** (convention): a decision is superseded by a **new** ADR that
  links the old one, never rewritten in place. The design document and
  `CONTEXT.typ` are present-tense snapshots; the ADR set is the history.

### Section anchors

A pointer into a section of a design document uses the id derived from the
numbered section title: lowercase the title text, collapse runs of
non-alphanumerics to single hyphens, and drop the numbering's dot.

| `section(title: …)`     | Anchor                 |
| ----------------------- | ---------------------- |
| `"02 The artifact set"` | `#02-the-artifact-set` |
| `"02.1 Pending ledger"` | `#021-pending-ledger`  |

### A reference is a call

Cross-references are function calls rather than paths, and that is what makes a
rename a compile error at the citing line instead of a dangling pointer someone
finds later.

```typst
The #term("term-pending-ledger") is read first, and it is owned by
#ctx("scheduling"). A judgement axis renders as #lens-pill("depth").

The decision that homed the layer is #adr(4).
```

| Call                  | Names                          | Resolves against                                                         |
| --------------------- | ------------------------------ | ------------------------------------------------------------------------ |
| `#term("term-slug")`  | a glossary term                | every `CONTEXT.typ` in the layer; renders the term's declared **title**  |
| `#ctx("name")`        | a bounded context              | the context directories the layer holds                                  |
| `#adr(64)`            | a recorded decision, by number | the ADR directory on disk, checked by the gate                           |
| `#lens-pill("depth")` | one of the six judgement axes  | the declared lens enum                                                   |
| `#lnk("dest")[text]`  | an external or markdown target | nothing at compile time; the gate's integrity check resolves it          |
| `#pill("a", "b")`     | a lens combo as one gradient   | the lens enum, auto-sorted into the fixed order                          |
| `#chip[text]`         | a bare inline token            | nothing — the honest rendering of a name that is not declared vocabulary |

**A citation panics at the citing line.** `#term("term-typo")` names a slug no
`CONTEXT.typ` declares, so the compile stops there rather than printing a raw
identifier into running prose that no comparison of the output would catch.
The same holds for `#ctx` against the layer's context directories.

**An ADR is cited by NUMBER, never by path.** Write `#adr(64)`; it renders as
`ADR-0064`, and the gate refuses a number the ADR directory holds no file for.
The number is the whole citation because the ADRs are markdown files outside
the rendered document — there is nothing to jump to inside it, and a hand-typed
path would rot silently the moment a file is renamed while a wrong number is
caught at the citing line.

---

## 3 · The authored format

### The author calls the library — there is no translation step

`design.typ` is the **authored source**, and it calls the projected library
directly. The PDF is **generated** and never hand-edited.

Build it, then gate it:

```sh
nix run github:lostbean/design-layer#aggregate -- docs/design docs/design/design-layer.pdf
nix run github:lostbean/design-layer#check     -- docs/design .
```

Nothing stands between what the author wrote and what is checked. There is no
converter reading the source and deciding what call it meant, so a construct
outside the grammar cannot half-convert into something that renders differently
from what it says — an unknown name is an unknown variable, reported at its own
line. A rule that would otherwise have been a second parse over the source is
instead a function signature the compiler enforces where the author writes it.

Generation is deliberately two things at once:

- **Validation**, at two severities. It **fails closed** on an illegal enum
  value, a malformed pending date, a malformed altitude, and any reference that
  resolves to nothing — a document that breaks one of these produces **no
  document at all**, because the renderer cannot draw what it cannot read. It
  **reports a guideline** and renders anyway for a missing required argument, a
  mis-ordered foundation, a foundation missing one of its kinds, mis-ordered
  clauses, or a clause naming a mechanism. The guidance names the rule and what
  was expected on every render; `DESIGN_STRICT=1` turns each into a failure.
- **Normalization** — typesetting and styling come from the library's own
  visual system, applied uniformly. Authors write content; the library owns the
  look.

### Block anatomy — named arguments, not free blobs

Every statement block — `goal`, `no-goal`, `principle`, `invariant` — shares
one anatomy: named arguments carrying the declared fields, then a content block
carrying the body.

```typst
#invariant(
  title: "Every booking names an existing resource",
  enforcement: "mechanism",
)[
  No booking may reference a resource that has been withdrawn.
]
```

- **`title:` is required**: plain text, no links. Both halves of the contract
  are **guidelines** — a missing title is reported by name and the block still
  renders, and the **64 character cap** is reported the same way. (The cap
  counts grapheme clusters, so an accented character costs one.)
- **The body** is the trailing content block, the long description. For an
  `invariant` the body **is** the checkable statement.
- **An unknown argument is a compile failure.** The named parameters _are_ the
  allowed set, so `lense:` for `lens:` stops the render naming the argument,
  rather than being dropped silently into a block that looks right and is
  missing what you wrote.
- **The footer is a declared slot.** `lens` and `enforcement` come from
  arguments and render as furniture in the block's footer. Never scatter them
  through the body, and never fake them as markup in the head row.

A block contract declares the information that must be captured at that point
of a design. When the design needs to capture a new kind of information
reliably, do not free-form it into prose — the contract is what makes the field
checkable.

### Titles are the scannable claim

**Convention**, beyond the machine-checked presence and the length guideline.
The title is what a reader sees before reading the body, so it should carry the
whole statement at a glance. State the assertion, not the topic. Roughly four
to ten words — long enough to mean something, under the 64-character cap.

- Weak: `title: "Concern"` — a topic word; the reader learns nothing until they
  read the body.
- Strong: `title: "One home per concern"` — the claim itself; the body only
  elaborates. Likewise `title: "Make illegal states unrepresentable"` over
  `title: "Invariants"`.

A `*Bold first line*` in the body is **not** a title. It renders as body text.
Titles live in `title:` only.

### A block kind is a function name

The kind and the function that renders it carry **the same name**, spelled
kebab-case: `no-goal` is `#no-goal`, `stat-grid` is `#stat-grid`. There is no
translation table between them, and nothing to look up.

The **one exception** is `figure`, whose function is `#figure-block`, because
`figure` is a Typst builtin and shadowing it would break every document that
uses the builtin.

### The block vocabulary

Each row names its required arguments; the gallery shows each one written out.

| Function                               | Required arguments                                   | Use it for                                                                                                                                                              |
| -------------------------------------- | ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `#goal`                                | `title:`                                             | a pragmatic, practical objective. `lens:` optional                                                                                                                      |
| `#no-goal`                             | `title:`                                             | an explicit exclusion. The one block whose body may be empty — write `[]`                                                                                               |
| `#principle`                           | `title:`                                             | an aspirational value guiding judgment; `lens:` optional                                                                                                                |
| `#invariant`                           | `title:`, `enforcement:`                             | a property that holds at all times. `enforcement:` is the honest label for HOW it is held, never which check holds it                                                   |
| `#behavior` + `#given` `#when` `#then` | `title:`, `level:`                                   | one conditional rule — a context, one event, observable outcomes. The body is clause calls, never prose (§5)                                                            |
| `#entity` + `#attribute` `#relates`    | `title:`, `kind:`, `owner:`, `lifecycle:`, `domain:` | one entry of a core model's entity census (§5)                                                                                                                          |
| `#pending-ledger` + `#pending-entry`   | `title:`, `kind:`, `since:` on each entry            | the pending ledger (§4)                                                                                                                                                 |
| `#cards`                               | `items:`                                             | **the workhorse grid**: `items:` is an array of `(title: …, body: …)`. `cols:`, `tint:`, `size:` optional                                                               |
| `#stat-grid` wrapping `#stat-tile`     | `value:`, `label:` on each tile                      | a row of KPI numbers read at a glance. Tiles are passed positionally                                                                                                    |
| `#info` · `#warning`                   | —                                                    | a titled notes panel. `title:` and `tint:` optional; with no tint it falls back to the kind's own colour                                                                |
| `#notes`                               | `title:`                                             | a muted aside beside a section's argument, for a caveat that would break the run of prose                                                                               |
| `#points`                              | —                                                    | bullets, one property each, passed positionally. Three sentences per bullet is a guideline                                                                              |
| `#diagram-native`                      | `altitude:`, `nodes:`                                | flowcharts and structure diagrams. Declare nodes and edges as data, never coordinates. Every edge endpoint must name a declared node                                    |
| `#diagram-source`                      | positional kind and source                           | a diagram shape with no carrier — the source stays visible rather than vanishing                                                                                        |
| `#chart`                               | `type:` (`bar`\|`line`\|`pie`)                       | a chart drawn from a small table in the body. First column category, second value                                                                                       |
| `#md-table`                            | positional column count and cells                    | a plain table; the first row is the header                                                                                                                              |
| `#code-block`                          | positional language and source                       | a literal snippet, syntax-highlighted by its language                                                                                                                   |
| `#embedded-svg`                        | `caption:`                                           | a placeholder frame naming a sibling SVG in `file:`. **The file is not read or embedded** — the renderer draws a labelled box, so a missing file does not fail the gate |
| `#figure-block`                        | `caption:`, `uses:`                                  | a self-contained drawing carrying renderer markup, for a shape no diagram carrier covers                                                                                |
| `#coverage`                            | positional rows                                      | the breadth axis in the document: `(part, status, why)` per row                                                                                                         |
| `#components` + `#component`           | `name:`, `mission:` on each                          | a unit map: one card per component, each optionally answering the five questions                                                                                        |
| `#answers`                             | —                                                    | the five questions for one unit, written out: responsibility, interface, interactions, invariants, failure                                                              |
| `#section` · `#subsection`             | `title:`                                             | the spine's structure. A section takes an optional `lead:`, `visual:`, `notes:`, and `body:`                                                                            |
| `#how-to-read`                         | —                                                    | the generated legend panel — it shows each mark rather than naming it                                                                                                   |

Three things a writer might reach for **do not exist and will not render**: raw
HTML of any kind; stylesheet theming (there are no CSS custom properties
anywhere in the pipeline); and any rendered artifact other than the PDF.

### `#figure-block` is a figure, not an escape hatch

`#figure-block` is the one declared way to carry renderer markup directly, for
a drawing no diagram carrier covers — interface mass, band thickness, a marked
grid of illegal states.

**Machine-checked**: it requires a `caption:` and a non-empty `uses:` list, and
every package named in `uses:` must be one the framework **vendors**. An import
outside that set fails the render, which is what keeps a design layer
reproducible offline. It renders inside a visibly distinct frame naming those
packages, so the exception is legible in the rendered document and not only in
the source.

It is not a way to restyle a statement block, and never a second path for a
node-and-edge graph — that belongs in `#diagram-native`, where the library
validates every endpoint and the projected tokens colour it.

### Inline pills, accents, and lenses

`#lens-pill("depth")` renders that lens's pill mid-sentence. `#pill("state",
"composition")` renders one gradient pill, with the contributing lenses
**auto-sorted into the schema's fixed order** — never the order you wrote them.
The same `lens:` argument is accepted on statement blocks, where it takes
either one name or an array of them.

The six lenses, in their fixed order: `modeling` · `depth` · `composition` ·
`state` · `invariants` · `robustness`. An unknown lens name is
**machine-checked** and fails the render, as does a combo repeating a member.

The six accent tints: `teal` · `violet` · `amber` · `blue` · `rose` · `slate`.

**Two axes, never conflated**: a **tint** marks ownership — a bounded context
binds one tint and keeps it stable across every document that mentions it. A
**lens pill** marks judgment.

### The document shell — page identity

A standalone document that is compiled on its own applies the shell itself.
Four arguments carry its identity:

```typst
#show: design-doc.with(
  eyebrow: [Domain overview · Scheduling],
  hero_title: [Scheduling],
  lede: [How a booking is placed, confirmed, and released.],
  footer: [Scheduling · design owned here, vocabulary in CONTEXT.typ, rationale in docs/adr/.],
)
```

- **`eyebrow`** — a micro-caps identity line: the document's position in the
  layer hierarchy.
- **`hero_title`** — the display title, rendered as the hero heading inside the
  masthead. It is an argument rather than a body heading so the whole hero
  composes as one unit.
- **`lede`** — a muted one-to-three-line summary.
- **`footer`** — a colophon line restating the ownership split.

**A `design.typ` inside a layer calls none of this.** It exports `title` and
`body`; the aggregate supplies the shell for the whole layer (§2).

### Numbers and data read at a glance

**Guideline and convention.** A stat value and a chart are glances, not
ledgers.

- **Abbreviate large numbers** in a stat tile: `2.4M`, `1.2B`, `3.5×10⁹` —
  never `2,400,000`. The value is a magnitude the eye takes in, not an
  accountant's figure. An accountant's figure is caught by a guideline.
- **Chart data stays small** — a handful of rows. A chart illustrates one
  point. Many series in one chart reads as noise; a paragraph plus one focused
  chart beats one dense chart.

---

## 4 · Document-level contracts

The per-block contracts above are checked as each block is called. These are
checked across calls, by state the library carries from one call to the next —
they are properties no single block can see. Each is scoped to **one context**,
so a chapter is judged on its own and never on the strength of the previous
chapter's statements.

### The spine

**Guideline.** A design document's sections are expected to run in a fixed
order. Every rule in this section is reported and none of them blocks the
render — this is the shape a design usually takes, not a shape it must take.

```
00 Foundation          goals · no-goals · invariants · principles, in that order
Pending updates        unnumbered, immediately after the foundation; omitted when empty
01 System at a glance  one diagram of the whole
02…0N-1                progressive breakdown, gross to fine, recursing via NN.M
0N                     end-to-end walkthrough — one real usage path
```

Three parts of this are checked, each as a guideline that reports and lets the
render finish:

1. **Foundation cardinality** — at least one `goal`, at least one `invariant`,
   at least one `principle`. Zero or more `no-goal`s. A kind missing from the
   context's finished run of foundation calls is a kind nobody wrote, and the
   render names it. If your context has a reason not to carry one of these,
   that is a legitimate design and the guidance is the whole consequence.
2. **Foundation order** — the four kinds are expected in the declared order. A
   `#principle` called before an `#invariant` is reported, naming the offending
   statement's title.
3. **Spine order** — the numbered sections are expected to ascend. A `#section`
   whose leading number falls below the one before it is reported, naming both
   titles. Only a **numbered** title takes part; an unnumbered section is simply
   not on the axis this orders.

`DESIGN_STRICT=1` turns all three into hard failures, which is how a repo that
does want the fixed shape enforces it.

The foundation contract binds a document that **declares a foundation at all**.
A document carrying no foundation — a behavior-rule sheet, a reference page —
is not held to the per-kind minimum, because it is not a document that failed
the minimum; it is a document not carrying a foundation.

**The pending section is unnumbered on purpose**: its appearance and
disappearance never renumber the rest of the spine, and it stays off the
ascending-order axis.

**The `index_only` exemption.** A multi-context **root** that only indexes its
child contexts exports `#let index_only = true` and is waived from the per-kind
minimum. It then carries only genuinely cross-context foundation and points
down to each context for the rest, never restating a context-owned goal or
invariant. The waiver is a declaration rather than a guess, because nothing in
a document's own text distinguishes an index root from a leaf that forgot its
foundation. The **order** rule still binds whatever foundation the root does
carry.

### Principles and goals are never conflated

**Convention.** A principle is an aspirational, abstract value — "low-entropy
evolution". A goal is a pragmatic, practical objective — "onboard any repo".
The renderer draws them as distinct kinds, so a value written as a goal reads
as a category error to anyone scanning the foundation.

### The pending ledger

A design document may run explicitly ahead of the system. All intentionally-open
state lives in **one place** — the **Pending updates** section, immediately
after the foundation — never as badges scattered through the page. The section
is omitted entirely when empty; an absent ledger states "this page is the
present".

The ledger is one `#pending-ledger` call taking `#pending-entry` values
positionally:

```typst
#pending-ledger(
  pending-entry(
    title: "Release withdraws a confirmed booking",
    kind: "build",
    since: "2026-08-16",
    adr: [#adr(12)],
  )[
    The release transition is designed but not built.
  ],
  pending-entry(
    title: "Who owns a cancelled booking's audit trail",
    kind: "ruling",
    since: "2026-08-20",
  )[],
)
```

Note that the entries are written **without** a leading `#` — inside the
call's argument list they are ordinary expressions, not markup.

Entry fields, all **machine-checked** except the summary:

| Field    | Contract                                                                        |
| -------- | ------------------------------------------------------------------------------- |
| `title:` | required, plain text; the ≤64-character cap is a guideline                      |
| `kind:`  | required; one of `build` · `verify` · `foundation` · `ruling`                   |
| `since:` | required; exactly `YYYY-MM-DD`                                                  |
| `adr:`   | **required on a `build` entry** — the citation of the decision that designed it |
| body     | otherwise optional — a `ruling` entry may be title-only, written `[]`           |

The four kinds:

| Kind         | Means                                                                      |
| ------------ | -------------------------------------------------------------------------- |
| `build`      | designed, not yet built                                                    |
| `verify`     | derived from the system; faithfulness not yet verified                     |
| `foundation` | content the system cannot yield — goals, no-goals, principles need a human |
| `ruling`     | an open owner decision the layer cannot settle                             |

Only `build` must cite an ADR. The other three may predate any decision record,
so their citation is optional.

**`since` is load-bearing, not decorative.** The ledger renders on a **time
axis**: entries place by their date, so aging design debt is visible at a glance
rather than buried in a list. An entry whose date is wrong or guessed misplaces
itself on that axis and misreports how long the layer has run ahead. Date an
entry the day it opens, and never refresh the date to make a ledger look young.

An entry lives in the design document that owns the affected structure — a
domain document for a domain-scoped delta, the root for a cross-cutting one.

### Structural recursion

A design is a recursively self-similar tree of units, and a unit is the same
shape at every altitude: an overview, its child units, and a pointer to its
parent. `context`, `component`, and an `NN.M` subsection are **depth labels on
one node type**, not different things. The root indexes contexts, a context
indexes its components, a component indexes its `NN.M` sub-parts. The same
ladder names a diagram's altitude — `L1` boundary, `L2` contexts, `L3`
components, `L4` internals — which `#diagram-native` requires on every drawing,
so a reader can tell which zoom level they are looking at before reading the
caption.

Two rules follow, both **convention**:

- **A unit's overview indexes only its own children.** Any reference to a
  non-child unit is an explicit pointer — down, up, or lateral — never a silent
  inclusion and never a silent omission. A spanning "at a glance" that lists
  some off-node units and drops others is an authoring bug: either index every
  off-node unit with a pointer, or scope the section to this unit's children,
  and say which.
- **Recursion is not the file split.** A unit recurses deeply inside one file
  via `NN.M.K` without any split. Where the recursion breaks into separate
  `design.typ` files is the second-real-vocabulary judgment of §1 — a semantic
  call, not a depth counter.

Overlaid on the tree is a **lateral reference graph**: terms owned by one unit
and cited by others, seams between siblings, and the relationships declared in
the context map. Those edges are cross-references, not the recursion.

---

## 5 · Block reference

Two block families carry nested clause calls rather than prose. Their bodies
are **not** free content, and the library validates the presence, count, and
order of their children.

### `#behavior` — the conditional rule

`#behavior` captures what an `#invariant` cannot. An invariant holds at all
times, with no trigger and no actor — "cross-references resolve". A behavior
rule has a context, an event, and an outcome. That distinction is the whole
test for which block to reach for.

```typst
#behavior(
  title: "A duplicate address is refused without disclosure",
  level: "interface",
)[
  #given[a visitor is not signed in]
  #when[they submit a sign-up whose address is already registered]
  #then[the sign-up is refused and the offending field is named]
  #then[the response never reveals that the address is already registered]
]
```

**`level:` is required.** The fence that discourages naming a mechanism is
defined per level, so a rule carrying no level is a rule no fence applies to.
Omitting it is reported as a guideline naming the field; the rule still renders.

**Clause cardinality and order, reported as guidelines:**

| Clause   | Count     | Holds                                                             |
| -------- | --------- | ----------------------------------------------------------------- |
| `#given` | 0..n      | one context each. A rule needing no setup carries none            |
| `#when`  | exactly 1 | the actor's action. Two events are **two rules**, not two clauses |
| `#then`  | 1..n      | one observable outcome each, so each is separately checkable      |

They render and validate in the fixed order `given`, `when`, `then`. A `#then`
before a `#when` is a violation naming both. Each rule's clauses are counted
against that rule and no other, so two sibling behavior blocks never confuse
each other's clauses.

**A rule states the rule, never an example of it.** No concrete values: write
"a baby animal younger than its selling age", not "a rabbit called Fluffy who is
1½ months old". The layer holds the durable rule; concrete values belong in
whatever executable scenarios are derived from it.

#### `level:` — two levels, and a rule belongs to exactly one

| `level:`    | States                                                               | Only this level can express                                                                                                  |
| ----------- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `interface` | what a person perceives, chooses, and is told — including on failure | interaction over time: progress is visible, an action stays cancellable, the user is never left unable to tell what happened |
| `boundary`  | behavior at the application boundary, in the domain's own language   | integrity: an operation is atomic, idempotent, ordered                                                                       |

A slow upload's "progress is visible and it stays cancellable" is `interface`
and has no boundary form. A transfer's "either both balances move or neither
does" is `boundary` and has no meaningful interface form.

The levels are **not two descriptions of one rule** — they capture different
rules. **Never mirror a rule across both levels**: a mirrored pair invites
filler, and a feature's rules are uneven across levels by design.

#### The fence — name the outcome, never the mechanism

The test is one question: **will this wording need to change if the
implementation does?** If yes, the clause names a mechanism and must be restated
as the observable outcome.

This is **checked per clause and reported as a guideline** — the clause renders
exactly as written and the render names what it found. Wording is the author's
call to make, and the check is honestly declared `enforcement=partial`, because
it is a denylist plus a small set of patterns rather than a proof. A denylist
that blocked the build would refuse correct rules over a word it does not
understand, which is exactly why it reports instead.

- At `level: "interface"` it rejects widget and element ids, CSS selectors and
  class names, component / controller / presenter / view-model / repository /
  DTO names, HTTP status codes, and exact UI copy quoted as the outcome. "the
  offending field is named" is admitted; "the SignupController returns 409" and
  "`#email-input` gains `.is-invalid`" are violations.
- At `level: "boundary"` it rejects the transport and the storage — HTTP verbs
  and status codes, SQL, table and column names, queue and topic names, wire
  formats. The domain's **own** operation and entity names are the correct
  vocabulary here and are admitted: "the registration operation rejects the
  request" is fine; "INSERT into users fails the unique index" is a violation.

**What it cannot catch**: any mechanism named in ordinary words. "the blue
button in the top right" passes the check and is still a fence violation. The
mechanical check raises the floor; a reviewer catches the rest.

### `#entity` — the census of a core model

A **core model context** is the bounded context owning the application's core
entities, their relationships, and the state and logic flowing over them. It is
homed at the declared path `docs/design/core-model/`, with its own `design.typ`
and `CONTEXT.typ`. The path is fixed rather than author-named so the core is
findable in any repo without reading the map first.

Its census is written one `#entity` call per entity. The body is the attribute
clauses, then the relates clauses — nothing else.

```typst
#entity(
  title: "Booking",
  kind: "aggregate",
  owner: "scheduling",
  lifecycle: "stateful",
  domain: "scheduling",
  tint: "violet",
)[
  #attribute(provenance: "authored")[
    the requested time window, stated by the person booking
  ]
  #attribute(provenance: "derived")[
    the duration, computed from the requested window
  ]
  #relates(cardinality: "n : 1")[belongs to one *Customer*]
]
```

**Entity arguments, all required except `tint` and `lens`:**

| Argument     | Values                                      | Means                                         |
| ------------ | ------------------------------------------- | --------------------------------------------- |
| `title:`     | the entity's name                           | required                                      |
| `kind:`      | `entity` `value-object` `aggregate` `event` | required; see below                           |
| `owner:`     | free text                                   | required; the unit responsible for it         |
| `lifecycle:` | `immutable` `append-only` `stateful`        | required; how it changes over time            |
| `domain:`    | free text                                   | required; the discovered domain it belongs to |
| `tint:`      | one of the six accents                      | optional; the domain's colour                 |

Omitting any of the five required arguments is reported as a guideline naming
the field, and the card still renders. The reason to fill them all in anyway: a
card missing one renders as a card that simply does not answer that question,
which reads as "not applicable" rather than "never stated".

The four kinds: an **entity** has identity persisting as its attributes change;
a **value object** is defined only by its attributes; an **aggregate** is a
cluster with one root owning its invariants; an **event** is a thing that
happened. The card is filled by its kind, so a reader identifies an entity's
type before reading a word. None of that colouring is authored — it follows
from `kind:` and `lifecycle:`. The two groups inside a card label themselves
from the run of clauses, so the authored source names neither heading.

**Every relationship declares its cardinality**: `cardinality:` is written
`<this> : <other>` and each side is expected to be one of `1`, `0..1`, `n`,
`0..n`. A missing `cardinality:`, a value with no colon, or a side outside that
vocabulary is reported as a guideline naming the offending value; the capsule
renders exactly what you typed, so the reader sees what was written. The shape
of the model then scans down one column.

**Conventions for the census as a whole:**

- **Group by domain, and name the domain even when there is one.** Every entity
  carries `domain:`, and the census's subsections follow those groups. A
  single-domain census still says "this is one domain, and here is what holds it
  together" — otherwise a reader cannot tell whether the question was asked or
  skipped.
- **Give each domain an accent and use it everywhere.** Every entity of one
  domain declares the same `tint:`. Which domain takes which accent is your
  call — domains are discovered per repo, so nothing predefines them — but once
  chosen it is that domain's colour in the census, in the whole-model graph, and
  in any later diagram drawing those entities.
- **The state machine lives OUTSIDE the entity block**, in the census's own
  lifecycle subsection, one per stateful entity. Six machines drawn inside six
  cards compete with each other and bury the two states that matter; read
  together in one subsection they are comparable.
- **The census is a model, not an inventory.** It names the entities whose
  identity and lifecycle the design must respect, not every field an
  implementation will store. Derivable internals stay out.

#### Provenance — the field that earns the block

Every `#attribute` declares **how its fact arises**. `provenance:` is required,
and the two halves split by severity: a value **outside** the three is
machine-checked and fails the render, because the library has no badge for it,
while **omitting** it is reported as a guideline. An attribute with no
provenance makes no claim about how its fact arises, so the absence is named
rather than defaulted.

| `provenance:` | Means                                                                             |
| ------------- | --------------------------------------------------------------------------------- |
| `authored`    | a human stated it, so it can be wrong and it drifts                               |
| `derived`     | computed from other facts, so it cannot desynchronize                             |
| `observed`    | recorded from outside the system, so it describes reality but never authorizes it |

**Prefer `derived` over `authored`** wherever a human would otherwise author a
claim about something observable — an authored claim about an observable fact is
the attribute most likely to go stale. When deriving, say whether it is
derive-at-read (repairable) or derive-at-write (reproducible). And never let an
`observed` value auto-publish into authoritative state: description is not
authority.

---

## 6 · The renderer, its version, and the gallery

The renderer travels with the gate as one pinned Nix flake input. A render
resolves nothing at run time and gives the same result in CI, in a sandbox, and
on a laptop. That input is bumped deliberately, and the look and the block
contracts move with it.

- **When the pinned input is bumped, re-render every design document.** A bump
  can change how a block draws even when no contract moved, so the re-render is
  part of the bump, not a follow-up to it. Review the rendered diff before
  accepting it.
- **The gallery is the drift tripwire.** `fixtures/gallery.typ` calls
  every function the library projects for authoring, and a self-test renders it
  on every change and reads the marks back off the page, so an upstream change
  that alters the look fails there rather than silently in a host's document.
  It is the reference to diff against.
- **A function absent from the gallery is not covered by that tripwire** —
  which is why the gallery is kept complete: every function, and every
  important variant.

The gate proves the rendered PDF is fresh by regenerating it and comparing,
so a stale artifact is reported rather than trusted:

```sh
nix run github:lostbean/design-layer#check -- docs/design .
```

That composite runs three things in sequence and exits 0 clean, 1 on a
violation, 2 on an error: render freshness, token coverage, and layer
integrity. Two further entry points sit beside it — the author-requested
guideline sweep, and the schema-to-library projection:

```sh
nix run github:lostbean/design-layer#lint    -- docs/design
nix run github:lostbean/design-layer#project -- <schema.json> <out-dir>
```

`lint` compiles the layer with every guideline promoted to an error and reports
the first that fires — the same escalation `DESIGN_STRICT=1` performs. It is
deliberately not part of `check`: a guideline names a document that could be
organized more conventionally, and blocking a commit on one would collapse the
distinction between the two classes of rule.

`lint` is not how you find out which guidelines fired. `check` and `aggregate`
already report every one of them, naming the rule, the offending item, and what
was expected, and end with a count summary. `lint` changes the severity, not
the visibility.

The declared vocabulary — every block contract, every enum, the anchor patterns
— lives in one schema, which travels inside the same bundle and is **projected**
into the library each compile imports. Nothing is copied into a host repo, so
there is no local copy to drift. To read the schema this skill describes:

```sh
cat "$(nix build --no-link --print-out-paths github:lostbean/design-layer#gate-bundle)/schema/design-schema.json"
```

Passing the gate means the layer is **well-formed**. It does not mean the
design is right.
