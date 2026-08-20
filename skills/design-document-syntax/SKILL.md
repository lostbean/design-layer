---
name: design-document-syntax
description: The format specification for a design layer — the authored markdown that `design.md`, `CONTEXT.md`, and `docs/adr/` are written in, and the contracts the renderer and the gate decide pass or fail on. Covers the artifact set and where each file lives, term and ADR anchors, block anatomy and the `title=` contract, the full block vocabulary, the required section spine, the pending ledger's entry fields, the `:::behavior` clause blocks and `level=`, the `::::entity` census with provenance and cardinality, and how renderer versioning is pinned. Use when writing or editing a `design.md`, `CONTEXT.md`, or an ADR; when a render or gate run reports a violation and the correct syntax is needed; when asking "what block do I use for this?", "how do I write an invariant / a behavior rule / an entity", "where does this file go", "what does `title=` require", "why did my foundation fail to render"; or when bootstrapping a design layer in a repo that has none.
domains: [engineering]
status: ship
---

# Design document syntax

A design layer is authored markdown. `design.md` is markdown extended with a
small set of container-directive blocks; `CONTEXT.md` and the files under
`docs/adr/` are plain markdown holding declared anchors. A renderer compiles
the layer into one PDF, and a gate decides whether the layer is well-formed.

This document is the format specification: what you may write, where it goes,
and which rules a machine actually decides. It does not say when a system is
worth designing, how deep to go, or whether a design is any good. Those are
judgment calls made with the rendered document in hand.

## How to read this document

The block vocabulary has one live demonstration: `fixtures/widget-gallery.md`
in the design-layer repository. Every declared block kind appears there once,
written in real syntax, and a self-test fails if a declared kind is missing
from it or stops rendering. **Read the gallery for syntax; read the tables
below as an index into it.** A table here tells you which block to reach for
and what its contract requires. The gallery shows you the block working.

Two words are used precisely throughout:

- **Machine-checked** — a script or the renderer decides pass or fail on this,
  fail-closed. Break it and you get a violation naming the file and the line.
- **Convention** — no check enforces it. It is stated because a layer that
  ignores it reads badly, but nothing will stop you.

Every command below is a `nix run` against the design-layer flake. A host repo
copies nothing in: the scripts, the schema, and the renderer travel together as
one pinned bundle, and the host stores only its own markdown.

---

## 1 · The artifact set and where it lives

The design layer is **three artifacts owning three concerns**, joined by
cross-links.

| Artifact                           | Owns                                                                 | Never contains                                                   |
| ---------------------------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `design.md` → a chapter of the PDF | the design itself — the current, actual snapshot, presented visually | a restated definition; a re-argued decision — link the other two |
| `CONTEXT.md`                       | semantics — the canonical definition, one term per anchor            | implementation detail                                            |
| `docs/adr/NNNN-slug.md`            | rationale — the canonical argument, one decision per anchor          | a duplicate of either of the above                               |

The design document is not a link farm. It presents structure, narrative, and
visuals in full, and links out only where a word needs knowing or a reader
would genuinely ask "why?". Definitions and rationale have canonical homes
elsewhere; the design document states what the design **is**.

### Links stay `.md`

Every link in every artifact points at the `.md` file. The context map links a
context's `design.md`, a root links a domain's `design.md`, a `#term-` or
`#adr-` fragment links its `.md`.

There is no rewrite to a second link form. The layer renders to one PDF, and
`CONTEXT.md` and the ADRs are never rendered at all, so there is no parallel
artifact set to keep consistent. A link written by the author is the link that
ships — which keeps the markdown internally coherent as text, the form a
reviewer reads in a diff and a forge renders in a browser.

A dangling design-ish link is **machine-checked**: the gate's integrity check
resolves every one and reports the ones that do not land.

### Single-context layout — the default

```
docs/design/design.md          # the design source (authored)
docs/design/CONTEXT.md         # the glossary — holds the #term- anchors
docs/design/design-layer.pdf   # generated — the ONE rendered document
docs/COVERAGE.md               # the coverage map (optional)
docs/adr/0001-slug.md          # append-only decision records
```

### Multi-context layout

```
docs/CONTEXT-MAP.md               # entry: links each context's design.md + CONTEXT.md
docs/design/design.md             # the root design source
docs/design/design-layer.pdf      # generated — ONE document, the whole layer
docs/design/<context>/design.md   # a context's design source
docs/design/<context>/CONTEXT.md  # that context's glossary
docs/COVERAGE.md
docs/adr/NNNN-slug.md             # central — rationale often spans contexts
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

| Basename           | Home                                                           |
| ------------------ | -------------------------------------------------------------- |
| `CONTEXT-MAP.md`   | `docs/CONTEXT-MAP.md`                                          |
| `COVERAGE.md`      | `docs/COVERAGE.md`                                             |
| `design.md`        | `docs/design/design.md` or `docs/design/<context>/design.md`   |
| `CONTEXT.md`       | `docs/design/CONTEXT.md` or `docs/design/<context>/CONTEXT.md` |
| `design-layer.pdf` | `docs/design/design-layer.pdf`                                 |

A file carrying one of those basenames found anywhere else is a mishomed stray
and fails the gate.

Two consequences follow, both machine-checked:

- **The layer renders as ONE document.** `docs/design/design-layer.pdf` is the
  whole layer; a context renders as a chapter of it and emits no sibling PDF.
  A per-context `design.pdf` is a stray left by an older render.
- **In multi-context mode there is no root glossary.** Every glossary lives in
  its context folder. A `docs/design/CONTEXT.md` alongside context folders is
  an orphan.

### `COVERAGE.md`

`docs/COVERAGE.md` is the coverage map: a table with one row per meaningful
system part, each row carrying a status that says whether the design covers it.
Its **name, its home, and the integrity of its links** are machine-checked like
any other layer artifact — a row linking a design section that does not exist
fails the gate.

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
context links to the owner's anchor and never redefines it. The map owns
context-level relationships only — fine-grained structural relations, module
seams, and flows live in the root design document's system-at-a-glance section.

---

## 2 · Anchors

Two anchor forms are declared, and the gate resolves every reference against
them.

### Term anchors — `CONTEXT.md`

```markdown
### Pending ledger {#term-pending-ledger}

The single section of a design document holding every intentionally-open state.

_Avoid_: backlog — implies work queued rather than design running ahead.
```

- **Form**: `### <Term> {#term-<slug>}` — heading level three, exactly.
- **Slug**: lowercase; runs of non-alphanumeric characters collapse to single
  hyphens; leading and trailing hyphens stripped. Machine-checked against
  `^term-[a-z0-9]+(-[a-z0-9]+)*$`.
- **One term per anchor**, and a slug is **never repurposed** for a different
  concept. Retire the term and mint a new slug; rebinding silently rewrites
  every link that trusted it. Duplicate term ids in one glossary are
  machine-checked.
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
  the anchor id, and in every reference to it.
- **Title shape** (convention): the title **is** the decision statement. No
  `ADR-NNNN:` prefix in the title text — the number lives in the filename and
  the anchor.
- **Append-only** (convention): a decision is superseded by a **new** ADR that
  links the old one, never rewritten in place. The design document and
  `CONTEXT.md` are present-tense snapshots; the ADR set is the history.

### Section anchors

A link into a section of a design document uses the rendered id the generator
derives from the numbered heading: lowercase the heading text, collapse runs of
non-alphanumerics to single hyphens, and drop the numbering's dot.

| Heading                       | Anchor                    |
| ----------------------------- | ------------------------- |
| `## 02 The artifact trio`     | `#02-the-artifact-trio`   |
| `### 02.1 The pending ledger` | `#021-the-pending-ledger` |

### References are relative paths

The design document links by relative path, and the gate resolves each one:

```markdown
the [pending ledger](CONTEXT.md#term-pending-ledger) is read first
recorded in [the homing decision](../adr/0004-layer-homing.md#adr-0004)
see [the artifact trio](design.md#02-the-artifact-trio)
```

---

## 3 · The authored format

### The source is markdown; the document is generated

`design.md` is the **authored source** — markdown extended with container
directives. The PDF is **generated** and never hand-edited.

Build it, then gate it:

```sh
nix run github:lostbean/design-layer#aggregate -- docs/design docs/design/design-layer.pdf
nix run github:lostbean/design-layer#check     -- docs/design .
```

The renderer reads the authored markdown through a **fence router**: every
fenced block reaches its own handler with the block's declared language intact.
That is what keeps the authored file plain markdown a human reviews in a diff,
while the contracts are enforced in the renderer's own language.

Generation is deliberately two things at once:

- **Validation** — it fails closed on an unknown block, a missing or
  mis-ordered foundation, a malformed pending entry, or a broken diagram. A
  design that does not render clean produces **no document at all**. There is
  no partial credit and no warning-only mode.
- **Normalization** — typesetting and styling come from the renderer's own
  visual system, applied uniformly. Authors write content; the renderer owns
  the look.

### Block anatomy — structured fields, not free blobs

Every statement block — `goal`, `no-goal`, `principle`, `invariant` — shares
one anatomy:

```markdown
:::invariant {title="Every booking names an existing resource" enforcement=mechanism script="check-booking-refs"}
No booking may reference a resource that has been withdrawn. An invariant
declaring `enforcement=mechanism` must name the script that enforces it.
:::
```

- **`title=` is required and machine-checked**: plain text, at most **64
  characters**, no links. A missing or over-length title fails the render.
  (The cap counts grapheme clusters, so an accented character costs one.)
- **The body** is the long description in markdown. For an `invariant` the body
  **is** the checkable statement. Only `no-goal` may omit a body.
- **Attributes are always brace-wrapped.** `:::invariant {title="…"}` is
  correct; a bare `key=value` after the kind is a violation.
- **The footer is a declared slot.** `id`, `lens`, `enforcement`, and `script`
  come from attributes and render as furniture in the block's footer. Never
  scatter them through the body, and never fake them as markup in the heading.

A block contract declares the information that must be captured at that point
of a design. When the design needs to capture a new kind of information
reliably, do not free-form it into prose — the contract is what makes the field
checkable.

### Titles are the scannable claim

**Convention, not machine-checked** beyond presence and length. The title is
what a reader sees before reading the body, so it should carry the whole
statement at a glance. State the assertion, not the topic. Roughly four to ten
words — long enough to mean something, under the 64-character cap.

- Weak: `title="Concern"` — a topic word; the reader learns nothing until they
  read the body.
- Strong: `title="One home per concern"` — the claim itself; the body only
  elaborates. Likewise `title="Make illegal states unrepresentable"` over
  `title="Invariants"`.

A `**Bold first line**` in the body is **not** a title. It renders as body
text. Titles live in `title=` only.

### The block vocabulary

Twenty block kinds are declared. Each row names its required attributes; the
gallery shows each one written out.

| Block                                           | Required attrs                                       | Use it for                                                                                                                                                              |
| ----------------------------------------------- | ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `:::goal`                                       | `title=`                                             | a pragmatic, practical objective. `lens=` optional                                                                                                                      |
| `:::no-goal`                                    | `title=`                                             | an explicit exclusion. Body optional — the only block where it is                                                                                                       |
| `:::principle`                                  | `title=`                                             | an aspirational value guiding judgment. `id=P1` makes it citable from prose; `lens=` optional                                                                           |
| `:::invariant`                                  | `title=`, `enforcement=`                             | a property that holds at all times. `mechanism` and `partial` must each name a `script=`                                                                                |
| `::::behavior` + `:::given` `:::when` `:::then` | `title=`, `level=`                                   | one conditional rule — a context, one event, observable outcomes. Body is clauses, never prose (§5)                                                                     |
| `::::entity` + `:::attribute` `:::relates`      | `title=`, `kind=`, `owner=`, `lifecycle=`, `domain=` | one entry of a core model's entity census (§5)                                                                                                                          |
| `:::pending`                                    | `title=`, `kind=`, `since=`                          | one pending-ledger entry (§4)                                                                                                                                           |
| `:::cards`                                      | —                                                    | **the workhorse grid**: items are `###` headings inside the block. `cols=2\|3\|4`, `tint=`, `size=md\|sm`                                                               |
| `:::stat-grid` wrapping `:::stat-tile`          | `value=`, `label=` on each tile                      | a row of KPI numbers read at a glance                                                                                                                                   |
| `:::info` · `:::warning`                        | —                                                    | a titled notes panel. `title=` and `tint=` optional; with no tint it falls back to the kind's own colour                                                                |
| ` ```mermaid `                                  | —                                                    | flowcharts, sequence diagrams, state machines. Declare nodes and edges only, never coordinates                                                                          |
| `:::chart`                                      | `type=bar\|line\|pie`                                | a chart drawn from a small markdown table immediately inside the block. First column category, second value                                                             |
| `:::embedded-svg`                               | `caption=`                                           | a placeholder frame naming a sibling SVG in `file=`. **The file is not read or embedded** — the renderer draws a labelled box, so a missing file does not fail the gate |
| `:::figure`                                     | `caption=`, `uses=`                                  | a self-contained drawing carrying renderer markup, for a shape no diagram carrier covers                                                                                |

Note the fence depth. A block that **nests** other blocks opens with four
colons (`::::behavior`, `::::entity`, `::::stat-grid`) so its children can use
three. Mismatched depth is the most common authoring error.

Three things a writer might reach for **do not exist and will not render**:
raw HTML of any kind beyond the id-carrying `<a id="…"></a>` anchor (no
`<details>`, no inline `<svg>`); stylesheet theming (there are no CSS custom
properties anywhere in the pipeline); and any rendered artifact other than the
PDF.

### `:::figure` is a figure, not an escape hatch

`:::figure` is the one declared way to carry renderer markup directly, for a
drawing no diagram carrier covers — interface mass, band thickness, a marked
grid of illegal states.

**Machine-checked**: it requires a `caption=` and a `uses=` list, and every
package named in `uses=` must be one the framework **vendors**. An import
outside that set fails the render, which is what keeps a design layer
reproducible offline. It renders inside a visibly distinct frame naming those
packages, so the exception is legible in the rendered document and not only in
the source.

It is not a way to restyle a statement block, and never a second path for a
node-and-edge graph — that belongs in a ` ```mermaid ` fence, where the gate
validates it and the projected tokens colour it.

### Inline pills, accents, and lenses

A code span `` `lens:depth` `` renders as that lens's pill mid-sentence. A
combo `` `lens:state+composition` `` renders one gradient pill, with the
contributing lenses **auto-sorted into the schema's fixed order** — never the
order you wrote them. The same `lens=` attribute is accepted on statement
blocks.

The six lenses, in their fixed order: `modeling` · `depth` · `composition` ·
`state` · `invariants` · `robustness`. An unknown lens name is
**machine-checked** and fails the render.

The six accent tints: `teal` · `violet` · `amber` · `blue` · `rose` · `slate`.

**Two axes, never conflated**: a **tint** marks ownership — a bounded context
binds one tint and keeps it stable across every document that mentions it. A
**lens pill** marks judgment.

### Frontmatter — page identity

Four keys the generator renders, at the top of every `design.md`:

```yaml
---
eyebrow: Domain overview · Scheduling · [root](../design.md)
hero_title: Scheduling
lede: How a booking is placed, confirmed, and released.
footer: Scheduling · design owned here, vocabulary in CONTEXT.md, rationale in docs/adr/.
---
```

- **`eyebrow`** — a micro-caps identity line: the document's position in the
  layer hierarchy, with links up.
- **`hero_title`** — the display title, rendered as the hero heading inside the
  masthead. It is carried in frontmatter rather than as a body `# ` heading so
  the whole hero composes as one unit.
- **`lede`** — a muted one-to-three-line summary.
- **`footer`** — a colophon line restating the ownership split, linking back up.

A fifth key, `index_only: true`, is legal on a multi-context **root** document
and changes what the foundation contract requires — see §4.

### Numbers and data read at a glance

**Convention.** A stat value and a chart are glances, not ledgers.

- **Abbreviate large numbers** in a stat tile: `2.4M`, `1.2B`, `3.5×10⁹` —
  never `2,400,000`. The value is a magnitude the eye takes in, not an
  accountant's figure.
- **Chart data stays small** — a handful of rows. A chart illustrates one
  point. Many series in one chart reads as noise; a paragraph plus one focused
  chart beats one dense chart.

---

## 4 · Document-level contracts

The per-block contracts above are checked by the renderer as each block draws.
These are checked by a separate fold over the whole document, before it
compiles — they are properties no single block can see.

### The spine

**Machine-checked.** A design document's sections run in a fixed order.

```
00 Foundation          goals · no-goals · invariants · principles, in that order
Pending updates        unnumbered, immediately after the foundation; omitted when empty
01 System at a glance  one diagram of the whole
02…0N-1                progressive breakdown, gross to fine, recursing via NN.M
0N                     end-to-end walkthrough — one real usage path
```

Three parts of this are enforced:

1. **Foundation cardinality** — at least one `goal`, at least one `invariant`,
   at least one `principle`. Zero or more `no-goal`s.
2. **Foundation order** — the four kinds appear in the declared order. A
   `principle` before an `invariant` is a violation naming the line.
3. **Spine order** — the numbered sections ascend, and the spine opens with
   section `00`.

The foundation contract binds the section actually numbered `00` **and titled
Foundation**. A document with no foundation at all — a behavior-rule document,
say — is not held to the per-kind minimum.

**The pending section is unnumbered on purpose**: its appearance and
disappearance never renumber the rest of the spine.

**The `index_only` exemption.** A multi-context **root** that only indexes its
child contexts may declare `index_only: true` in frontmatter and is waived from
the per-kind minimum. It then carries only genuinely cross-context foundation
and points down to each context for the rest, never restating a context-owned
goal or invariant. The flag is legal **only** on a document that links at least
one child `<context>/design.md`; on a single-context document it is itself a
violation, so a leaf can never skip its own foundation. The **order** rule still
binds whatever foundation the root does carry.

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

Each entry is a `:::pending` block:

```markdown
:::pending {title="Release withdraws a confirmed booking" kind=build since=2026-08-16}
The release transition is designed but not built. See
[the release decision](../adr/0012-release-transition.md#adr-0012).
:::
```

Entry fields, all **machine-checked** except the summary:

| Field         | Contract                                                                           |
| ------------- | ---------------------------------------------------------------------------------- |
| `title=`      | required; ≤64 characters, plain text                                               |
| `kind=`       | required; one of `build` · `verify` · `foundation` · `ruling`                      |
| `since=`      | required; exactly `YYYY-MM-DD`                                                     |
| ADR link      | **required in the body of a `build` entry** — a link whose fragment is `#adr-NNNN` |
| tracker issue | optional                                                                           |
| body          | otherwise optional — a `ruling` entry may be title-only                            |

The four kinds:

| Kind         | Means                                                                      |
| ------------ | -------------------------------------------------------------------------- |
| `build`      | designed, not yet built                                                    |
| `verify`     | derived from the system; faithfulness not yet verified                     |
| `foundation` | content the system cannot yield — goals, no-goals, principles need a human |
| `ruling`     | an open owner decision the layer cannot settle                             |

Only `build` must cite an ADR. The other three may predate any decision record,
so their link is optional.

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
indexes its components, a component indexes its `NN.M` sub-parts.

Two rules follow, both **convention**:

- **A unit's overview indexes only its own children.** Any reference to a
  non-child unit is an explicit pointer — down, up, or lateral — never a silent
  inclusion and never a silent omission. A spanning "at a glance" that lists
  some off-node units and drops others is an authoring bug: either index every
  off-node unit with a pointer, or scope the section to this unit's children,
  and say which.
- **Recursion is not the file split.** A unit recurses deeply inside one file
  via `NN.M.K` without any split. Where the recursion breaks into separate
  `design.md` files is the second-real-vocabulary judgment of §1 — a semantic
  call, not a depth counter.

Overlaid on the tree is a **lateral reference graph**: terms owned by one unit
and cited by others, seams between siblings, and the relationships declared in
the context map. Those edges are cross-references, not the recursion.

---

## 5 · Block reference

Two block families carry nested clauses rather than prose. Their bodies are
**not** free markdown, and the renderer validates the presence, count, and order
of their children.

### `:::behavior` — the conditional rule

`:::behavior` captures what an `invariant` cannot. An invariant holds at all
times, with no trigger and no actor — "cross-links resolve". A behavior rule has
a context, an event, and an outcome. That distinction is the whole test for
which block to reach for.

```markdown
::::behavior {title="A duplicate address is refused without disclosure" level=interface}

:::given
a visitor is not signed in
:::

:::when
they submit a sign-up whose address is already registered
:::

:::then
the sign-up is refused and the offending field is named
:::

:::then
the response never reveals that the address is already registered
:::

::::
```

**Clause cardinality and order, machine-checked:**

| Clause     | Count     | Holds                                                             |
| ---------- | --------- | ----------------------------------------------------------------- |
| `:::given` | 0..n      | one context each. A rule needing no setup carries none            |
| `:::when`  | exactly 1 | the actor's action. Two events are **two rules**, not two clauses |
| `:::then`  | 1..n      | one observable outcome each, so each is separately checkable      |

They render and validate in the fixed order `given`, `when`, `then`. A `then`
before a `when` is a violation.

**A rule states the rule, never an example of it.** No concrete values: write
"a baby animal younger than its selling age", not "a rabbit called Fluffy who is
1½ months old". The layer holds the durable rule; concrete values belong in
whatever executable scenarios are derived from it.

#### `level=` — two levels, and a rule belongs to exactly one

| `level=`    | States                                                               | Only this level can express                                                                                                  |
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

This is **enforced, fail-closed, per clause** — and it is honestly declared
`enforcement=partial`, because it is a denylist plus a small set of patterns
rather than a proof.

- At `level=interface` it rejects widget and element ids, CSS selectors and
  class names, component / controller / presenter / view-model / repository /
  DTO names, HTTP status codes, and exact UI copy quoted as the outcome. "the
  offending field is named" is admitted; "the SignupController returns 409" and
  "`#email-input` gains `.is-invalid`" are violations.
- At `level=boundary` it rejects the transport and the storage — HTTP verbs and
  status codes, SQL, table and column names, queue and topic names, wire
  formats. The domain's **own** operation and entity names are the correct
  vocabulary here and are admitted: "the registration operation rejects the
  request" is fine; "INSERT into users fails the unique index" is a violation.

**What it cannot catch**: any mechanism named in ordinary words. "the blue
button in the top right" passes the check and is still a fence violation. The
mechanical check raises the floor; a reviewer catches the rest.

### `::::entity` — the census of a core model

A **core model context** is the bounded context owning the application's core
entities, their relationships, and the state and logic flowing over them. It is
homed at the declared path `docs/design/core-model/`, with its own `design.md`
and `CONTEXT.md`. The path is fixed rather than author-named so the core is
findable in any repo without reading the map first.

Its census is written one `::::entity` block per entity. The body is the
attribute clauses, then the relates clauses — nothing else.

```markdown
::::entity {title="Booking" kind=aggregate owner="scheduling" lifecycle=stateful domain="scheduling" tint=violet}

:::attribute {provenance=authored}
the requested time window, stated by the person booking
:::

:::attribute {provenance=derived}
the duration, computed from the requested window
:::

:::relates {cardinality="n : 1"}
belongs to one **Customer**
:::

::::
```

**Entity attributes, all required except `tint` and `lens`:**

| Attr         | Values                                      | Means                               |
| ------------ | ------------------------------------------- | ----------------------------------- |
| `title=`     | the entity's name                           | required                            |
| `kind=`      | `entity` `value-object` `aggregate` `event` | see below                           |
| `owner=`     | free text                                   | the unit responsible for it         |
| `lifecycle=` | `immutable` `append-only` `stateful`        | how it changes over time            |
| `domain=`    | free text                                   | the discovered domain it belongs to |
| `tint=`      | one of the six accents                      | optional; the domain's colour       |

The four kinds: an **entity** has identity persisting as its attributes change;
a **value object** is defined only by its attributes; an **aggregate** is a
cluster with one root owning its invariants; an **event** is a thing that
happened. The card is filled by its kind, so a reader identifies an entity's
type before reading a word. None of that colouring is authored — it follows
from `kind=` and `lifecycle=`.

**Every relationship declares its cardinality** in the `1 : 0..n` vocabulary —
`1`, `0..1`, `n`, `0..n` on either side, written `<this> : <other>` — rather
than describing it in a sentence. The shape of the model then scans down one
column.

**Conventions for the census as a whole:**

- **Group by domain, and name the domain even when there is one.** Every entity
  carries `domain=`, and the census's subsections follow those groups. A
  single-domain census still says "this is one domain, and here is what holds it
  together" — otherwise a reader cannot tell whether the question was asked or
  skipped.
- **Give each domain an accent and use it everywhere.** Every entity of one
  domain declares the same `tint=`. Which domain takes which accent is your
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

Every `:::attribute` declares **how its fact arises**. It is a validated
attribute rather than a table cell precisely so the contract can check it.

| `provenance=` | Means                                                                             |
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
- **The widget gallery is the drift tripwire.** `fixtures/widget-gallery.md`
  exercises every declared block kind, and a self-test renders it on every
  change, so an upstream change that alters the look fails there rather than
  silently in a host's document. It is the reference to diff against.
- **A block kind absent from the gallery is not covered by that tripwire** —
  which is why the gallery is kept complete: every kind, and every important
  variant.

The gate proves the rendered PDF is fresh by regenerating it and comparing,
so a stale artifact is reported rather than trusted:

```sh
nix run github:lostbean/design-layer#check -- docs/design .
```

That composite runs three things in sequence and exits 0 clean, 1 on a
violation, 2 on an error: render freshness, token coverage, and layer
integrity. Two lower-level entry points back it — one document at a time, and
the schema-to-library projection:

```sh
nix run github:lostbean/design-layer#render  -- docs/design/design.md [--check]
nix run github:lostbean/design-layer#project -- <schema.json> <out-dir>
```

The declared vocabulary — every block contract, every enum, the anchor patterns
— lives in one schema, which travels inside the same bundle. Nothing is copied
into a host repo, so there is no local copy to drift. To read the schema this
skill describes:

```sh
cat "$(nix build --no-link --print-out-paths github:lostbean/design-layer#gate-bundle)/schema/design-schema.json"
```

Passing the gate means the layer is **well-formed**. It does not mean the
design is right.
