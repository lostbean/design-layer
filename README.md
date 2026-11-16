# Design Layer

A design layer is a small set of authored files — `design.typ`, `CONTEXT.typ`,
an append-only `docs/adr/` — that describe a system's structure, vocabulary,
and decisions, kept next to the code and reviewed like code. This repo owns documentation guidance and the **mechanical gate** for that
layer: the renderer, the schema that declares its block vocabulary, and the
scripts that decide pass or fail. Its own [architecture overview](docs/design/design-layer.pdf)
explains how these responsibilities cooperate; the [Typst source](docs/design/design.typ)
is the authored version.

## Guidance and mechanical checks

The `document-design` skill guides what to document and where to stop.
The tools answer: **Is this `design.typ` well-formed, and what does it render to?**
Their checks have two severities, split by what a violation breaks.

**Referential integrity is fail-closed.** A reference that resolves to nothing
is broken output, not a matter of taste: a `term()` no `CONTEXT.typ` declares
has no text to render, a diagram edge naming no node draws a line to nowhere,
and a value outside a declared vocabulary is one the renderer would have to
invent a meaning for. These fail the render, naming the violation and its
location, and no flag relaxes them.

**A design unit's contract is fail-closed too.** Every `unit` answers the same
five questions and lists its code paths. A unit missing one of those fields, a
duplicate unit id, and an illegal path fail the render; an empty list is how a
unit says "none".

**Structure is guided by warnings.** Which foundation kinds the root document
declares, what order they run in, whether an optional block's attributes were
filled — these are opinions about how a design is usually organized, and a
design legitimately changes shape. A context document is not held to the
foundation minimum at all. The renderer says what it expected, names the rule
and the offending item, and renders anyway. Every guideline prints on every
render and the run ends with a count summary, so guidance is never silent; none
of it changes the exit code. Set `DESIGN_STRICT=1` to escalate every guideline
to a hard failure, for a repo that wants the stricter ratchet in CI.

The reason for the split: a design document that will not render helps nobody,
and refusing to draw a layer because it carries two of the three foundation
kinds fails a document a reader may still need. A broken reference is different
in kind — it produces a document that looks finished and is quietly wrong.

This repo has **no opinion** about:

- when a system is worth designing or which architecture it should use
- what to build next, or how to prioritize it
- whether a design is _good_ — only whether it is well-formed

Those decisions belong to the host. Documentation guidance helps humans and
agents explain them; mechanical checks establish whether their representation
is well-formed.

## Use

Everything runs through Nix — nothing is copied into your repo.

Build the layer's rendered document, then gate it:

```sh
nix run github:lostbean/design-layer#render -- docs/design docs/design/design-layer.pdf
nix run github:lostbean/design-layer#check  -- docs/design .
```

`render` compiles every `design.typ` under the layer root into one navigable
PDF. The root design is chapter 1, and each context follows as its own chapter.
Sections and subsections use chapter-local numbers such as `1.10.1`; authors
still supply content-only titles. The grouped table of contents marks chapter
boundaries, nests sections and subsections, and aligns page numbers. The
alphabetized glossary closes the document as an unnumbered reference chapter.
`check` then runs four things in sequence and exits 0 clean, 1 on a
violation, 2 on an error:

1. **freshness** — regenerate the aggregate and byte-compare it against the
   committed PDF, so a stale render is caught, not trusted
2. **token coverage** — every semantic token a block renderer references
   (a lens color, a tint, an enforcement badge) is actually defined
3. **layer integrity** — every cross-link resolves (a term citation, an ADR
   reference, a section pointer), every ADR is in lockstep with its filename,
   every glossary term is unique, no layer file sits outside its declared
   home under `docs/`
4. **unit folder contracts** — every path a unit lists is one real directory
   of the repository, every generated `AGENTS.md` region matches a fresh
   generation, no folder carries a region no unit lists, and every unit is
   one the Markdown projection can address

The same step prints a **report** of the git-tracked directories no unit path
covers. It shows what the design does not claim and never changes the exit
code.

When a layer declares units, write their folder contracts before gating:

```sh
nix run github:lostbean/design-layer#units -- docs/design .
```

`units` writes one generated region into the `AGENTS.md` of every directory a
unit lists, and links `CLAUDE.md` to it where none exists. `check` only
compares; it never rewrites a stale region.

The `CLAUDE.md` link is the generator's only in the form it creates — a
symbolic link whose target is the bare name `AGENTS.md`. When a region leaves
a folder and its `AGENTS.md` is left with nothing to read, deleted or holding
only whitespace, `units` removes that link with it. When `AGENTS.md` keeps
text of its own, the link stays: it still links something worth reading. A
`CLAUDE.md` in any other form is never touched.

`units` shares each file with hand-written text, so it is strict about what it
touches:

- Text outside the region keeps every byte, including its line endings and
  whether the file ends with a newline. Removing a region restores the file it
  was added to: a file that was empty is left empty, and only a file `units`
  created is deleted.
- A region is recognized by its whole generated shape. A marker shown inside a
  code block or a raw HTML block — `<pre>`, `<details>`, a comment — is an
  example and is never read, as the opening of a region or as its end; a
  marker line anywhere else outside that shape, or a region whose closing
  lines are missing, is reported and the file is left as it is. To recover,
  delete the region's lines and run `units` again.
- A region a formatter touched — a space after a marker, a blank line between
  two of its lines — is still found. `check` reports it stale and `units`
  writes it again.
- The target is a regular file in the listed directory. An `AGENTS.md` that is
  a symbolic link, a directory, or not UTF-8 text is a violation. An
  `AGENTS.md` anywhere else that holds no marker is never read.
- A unit path is the path the file system stores. A path through a symbolic
  link, or in another letter case on a case-insensitive file system, fails
  naming both spellings. `.git` and the layer directory are not unit paths. A
  folder contract git tracks under another spelling than the file system
  stores is reported naming both, and is never removed.
- A run writes every folder contract or none: one violation leaves every file
  untouched, and every new text is staged in a temporary file before any
  target is replaced.

A directory holding its own `docs/design/design.typ` is a **nested project**,
and its folder contracts belong to its own layer. `units` never touches one by
default: it refuses a unit path inside one, declared or not, and it reports a
region found there and leaves it in place. Declare the project with the
argument `check` takes:

```sh
nix run github:lostbean/design-layer#units -- docs/design . --nested-project packages/api
nix run github:lostbean/design-layer#check -- docs/design . --nested-project packages/api
```

`--nested-project <path>` is repeatable. It leaves the project out of the
outer run, then writes — or with `--check` compares — the project's own layer
at `<path>/docs/design` against the project's root. `--exclude-project <path>`
only leaves the project out, for a caller that processes it separately.

One further entry point is advisory rather than a gate:

```sh
nix run github:lostbean/design-layer#lint -- docs/design
```

`lint` renders the layer with every GUIDELINE promoted to an error and reports
the first that fires — the same escalation `DESIGN_STRICT=1` performs, as a
named entry point. It is deliberately not part of `check`.

Note what `lint` is not needed for: a guideline is **already reported** by an
ordinary `render` or `check` run, naming its rule, the offending item, and
what was expected, with a count summary at the end. `lint` changes the
SEVERITY, not the visibility — it is for a repo that wants a guideline to stop
a commit, not for finding out which ones fired.

One lower-level entry point backs the composite ones above:

```sh
nix run github:lostbean/design-layer#project -- <schema.json> <out-dir> # schema -> renderer library
```

`project` is the seam between the schema and the renderer: it reads
`schema/design-schema.json` and emits the Typst library every compile imports.
You will not normally call it directly — `render` and `check` both project
fresh on demand — but it is exposed for an installer or a CI job that wants
the library as a build artifact.

A standalone document that is not part of a layer — a reference page an
adopter browses on its own — is compiled by the renderer directly, the way
`fixtures/gallery.typ` is.

`nix build github:lostbean/design-layer#gate-bundle` gives the store path
holding the scripts, the schema, and a fresh projection of that schema
together, for a host that wants to reference all three as one unit.

## What a host repo stores

Nothing from this repo is ever copied in. A host that adopts a design layer
keeps only its own content, laid out under `docs/`:

```
docs/
  design/
    design.typ             # or design/<context>/design.typ, one per context
    CONTEXT.typ             # the glossary — terms this system's design leans on
    design-layer.pdf        # the ONE rendered document (never hand-edited)
  CONTEXT-MAP.md            # multi-context layers only: links every CONTEXT.typ
  COVERAGE.md                # optional: what the layer covers, what it doesn't
  adr/
    0001-first-decision.md  # append-only; a decision is superseded, never rewritten
```

A single-context layer is just `docs/design/{design.typ,CONTEXT.typ}` plus
`docs/adr/` — no `CONTEXT-MAP.md` required. Everything under `docs/` is the
layer. One thing is generated beside the source it describes: a directory a
`unit` lists carries that unit's contract in a marked region of its
`AGENTS.md`. The region is written by `units` and never authored by hand.

## What this repo deliberately does not do

- **It does not choose or improve a system architecture.** It teaches how to
  document an existing system and established intent. Documentation depth is
  authoring guidance, not a mechanical correctness property.
- **Its own design layer is not its proof of correctness.** The repository
  carries a concise layer under `docs/design/` that describes its parts as
  units, and `lib/`, `schema/`, `fixtures/`, `scripts/`, and `skills/` each
  carry the generated folder contract. `nix flake check` gates that layer —
  its PDF, its links, and its folder contracts — which exercises integration.
  Correctness is proven by the self-tests under
  `scripts/*.test.sh` and by `fixtures/gallery.typ`, the fixture that
  exercises every function the library projects for authoring — never by a
  layer the repository would have an incentive to keep looking good.
- **It does not render to anything but PDF.** One document, one artifact;
  no HTML output, no stylesheet theming layer to keep in sync.
- **It is not a proof of good design.** The behavior-rule fence (see
  `design_doc.behavior_contract.fence` in the schema) is declared
  `enforcement=partial`: it catches a denylist of implementation-shaped
  words and a few id/selector patterns, and it openly cannot catch a
  mechanism described in ordinary words. Passing the gate means the layer
  is well-formed, not that its content is right.

## Layout

```
scripts/     the gate: design-aggregate, design-context, design-units, layer-integrity,
             token-coverage, render-project
lib/         the hand-written Typst library the layer calls
schema/      the ONE declared schema — block vocabulary, anchors, layout, enums
fixtures/    the gallery: every projected function, and the renderer-drift tripwire;
             and the schema as it stood before the unit block, for the old-schema test
skills/      the authoring guidance an agent loads to write a well-formed layer
docs/design/ this repository's own layer: its parts as units, and the rendered PDF
```

## Writing a design document

Two skills travel with the gate bundle:

- [document-design](skills/document-design/SKILL.md) guides what to document,
  where to stop, and how to represent the system for humans and code agents.
  It starts from the use case and explains the principal abstractions and how
  they cooperate. Code remains authoritative for implementation detail.
- [design-document-syntax](skills/design-document-syntax/SKILL.md) specifies
  file homes, Typst calls, block contracts, anchors, and mechanical checks.

Read `document-design` to create or revise the architectural explanation.
Read `design-document-syntax` for the exact notation. Both are available under
`skills/` in the `gate-bundle` store path; a host can expose those directories
through its agent's skill discovery mechanism. No separate design workflow is
required to use them. Architecture selection and improvement remain outside
this repository's responsibility.

### Design units

A `unit` is the one block every part of a design uses. It has the same required
shape at every depth: an overview, an interface, invariants, side effects, a
verification, and the code paths that realize it. Every other block is optional
and goes in the unit's body, where a nested `unit` is the next level down.

```typst
#unit(
  id: "billing-ledger",
  title: "Billing ledger",
  overview: [Records what each customer was charged.],
  interface: ([`append(entry)` adds one entry.],),
  invariants: ([An entry is never rewritten.],),
  side-effects: (),
  verification: [`cargo test -p ledger`],
  paths: ("src/ledger",),
)[
  Optional body: prose, any other block, and nested units.
]
```

Every field is required. An empty list is a legal answer and renders as `None`;
a field left out fails the render. A field holds prose: text, emphasis, inline
code, a code block, a link, a reference, mathematics, and the library's inline
citations. A code block — fenced in markup, or `#raw(..., block: true)` — is
written to the projection and to a folder contract as a fenced block, below
the field's label or indented under a list item, with a fence longer than any
backtick run it holds; a title, which is one heading line, holds none. A list,
a footnote, a box, or a heading written inside a field fails too: state each
point as its own item of a list field, and put anything else in the body.
`paths` holds exact repo-relative directories, and a unit that only groups
other units lists none. A unit's heading level is its depth, down to the sixth
level: five units nest directly in the root document's body, four inside a
section, three inside a subsection, and one fewer in a context document. The
body holds no `section` or `subsection`: inside a unit, a nested unit carries
the structure. The `id` is
unique across the layer and is the unit's stable address: the reference
`@unit-billing-ledger`, the link fragment `design.typ#unit-billing-ledger`, and
the selector `--unit billing-ledger`.

`units` then writes the contract into `src/ledger/AGENTS.md`, between
`<!-- design-units:begin -->` and `<!-- design-units:end -->`. Export
`#let context_command = "nix run .#design-gate-context --"` from the root
`design.typ` to print your own forwarding app in that region.

### Diagram node tints

`#diagram` and `#diagram-native` accept an optional `tint:` on each node. The
tint must be one of the document's declared accents. A node without `tint:`
uses the diagram-level `accent:`, so existing diagrams render unchanged.

Use a node tint to state stable ownership in a cross-context diagram. Keep the
diagram accent neutral when no one context owns the whole diagram. External
nodes stay white with the existing dashed neutral treatment.

```typst
#diagram(
  altitude: "L2",
  accent: "slate",
  nodes: (
    (id: "orders", label: "Order management", tint: "teal"),
    (id: "billing", label: "Billing", tint: "violet"),
    (id: "payment", label: "Payment provider", external: true),
  ),
  edges: (("orders", "billing", "invoice"), ("billing", "payment", "charge")),
)
```

The tint marks ownership. It does not transfer authority, persistence access,
or lifecycle ownership across an edge. State those limits in the caption or
adjacent clauses.

### Equations and formulas

Inline mathematics uses Typst's native math syntax directly. Use `#formula`
when an expression is a named design unit that benefits from a title, equation
number, notation key, caption, or stable internal target:

```typst
#formula(
  id: "availability-budget",
  title: "Availability budget",
  numbered: true,
  notation: (
    ([$A$], [availability over the observation window]),
    ([$D$], [accumulated downtime]),
    ([$T$], [total observation time]),
  ),
  caption: [Subsystem targets may refine this shared budget but cannot silently
    redefine it.],
)[
  $ A = 1 - frac(D, T) $
]
```

A formula states a mathematical relation rather than structural containment,
so it carries no diagram altitude. An `id:` creates a target named
`formula-<id>`; the example above is referenced as
`@formula-availability-budget`.

### Pseudocode

Use structured pseudocode when a procedure matters but its implementation
language does not. The renderer owns the keywords and indentation; the author
supplies the inputs, outputs, conditions, and domain actions:

```typst
#pseudocode(
  id: "accept-one-change",
  title: "Accept one change",
  inputs: ([a work order], [repository state]),
  outputs: ([an accepted change], [actionable findings]),
  steps: (
    pseudo-for([criterion], [acceptance criteria], (
      pseudo-if(
        [the criterion can be observed],
        (pseudo-step([bind it to one check]),),
        otherwise: (pseudo-return([a clarification request]),),
      ),
    )),
    pseudo-repeat([the gate is green], (
      pseudo-step([implement one coherent change]),
      pseudo-step([run the complete gate]),
    )),
    pseudo-return([the accepted change]),
  ),
)
```

Pseudocode complements behavior rules rather than replacing them: behavior
states what an observer can see, while pseudocode may explain the internal
logical procedure. It is ordered by control flow and therefore has no altitude.
An `id:` creates a `pseudocode-<id>` target; the example above is referenced as
`@pseudocode-accept-one-change`.

### Code snippets

Use `#code-block` when the programming language is itself part of the design
evidence—for example, an existing interface, configuration fragment, or API
usage whose exact syntax matters. The first argument is the language used for
syntax highlighting and the second is the literal source:

````typst
#code-block("rust", ```rust
pub trait Clock {
    fn now(&self) -> Instant;
}
```)
````

Use `#pseudocode` instead when the procedure should survive a change of
implementation language. A code block preserves syntax; pseudocode preserves
intent and control flow.

### Agent context Markdown

Agents read an ephemeral semantic Markdown projection instead of loading the
rendered PDF or parsing Typst source. The projection preserves authored order,
design fields, relationships, transitions, formulas, pseudocode control flow,
and references. Custom figures authored with raw `typst` bodies retain their
source in fenced code blocks, with captions and package names; the PDF evaluates
the same source as a drawing. Explain the drawing's meaning in its caption or
adjacent prose. Evaluated figure bodies and embedded SVGs remain unsupported.
The projection omits presentation-only furniture and fails when a public
construct has no complete Markdown representation.

Estimate the projection before loading it:

```sh
nix run .#context -- docs/design --estimate
```

Emit the same complete Markdown bytes to standard output, or write them to a
new temporary path:

```sh
nix run .#context -- docs/design
nix run .#context -- docs/design --output /tmp/design-context.md
```

When the complete projection is too large for the agent's context, inspect its
manifest or a compact preview before selecting a section:

```sh
nix run .#context -- docs/design --manifest > /tmp/design-context-manifest.json
nix run .#context -- docs/design --preview
nix run .#context -- docs/design --preview --depth 3
```

The manifest assigns deterministic, manifest-scoped addresses such as `1`,
`1.1`, and `1.1.2` to headings outside fenced code. Each address records its
parent, children, direct-content metrics, subtree metrics, and SHA-256 digest.
The projection record carries the digest that pairs the manifest with the
source snapshot. The preview shows the same addresses, token ranges, and
subtree digests as a human-readable table; it shows depth two by default.

Render one exact subtree to standard output or a new file:

```sh
nix run .#context -- docs/design --section 1.1
nix run .#context -- docs/design --section 1.1 \
  --expect-digest sha256:<projection-or-section-digest> \
  --output /tmp/design-context-1.1.md
```

`--expect-digest` accepts the manifest projection digest or the selected
subtree digest. Pass the projection digest when the manifest and section must
come from one source snapshot. Section output is an exact byte slice of the
complete projection, so the default and incremental modes cannot drift in
their Markdown mapping.

Select by design unit instead of by address when the layer declares units:

```sh
nix run .#context -- docs/design --unit billing-ledger
nix run .#context -- docs/design --path src/ledger/entry.rs
```

`--unit` prints one unit: its contract, its body, and its nested units. It
stops where the unit does, so it is shorter than `--section` at the same
address whenever text follows the unit under the same heading. `--path` takes a
repo-relative path and prints every unit whose `paths` contain it or a parent
directory of it. Both accept `--output` and `--expect-digest`. When a layer
declares units, the manifest gains a `units` list giving each unit's id,
address, parent, document, and paths.

The estimate reports UTF-8 bytes, characters, words, lines, and the named
planning estimates `ceil(utf8_bytes/4)` and `ceil(utf8_bytes/3)`. These values
are model-independent estimates rather than tokenizer counts. The manifest
adds SHA-256 digests without changing the legacy estimate shape.

The Markdown is a temporary reading projection. Typst remains authoritative,
the PDF remains the published rendered artifact, and the Markdown output is not
committed. A semantic violation exits 1 without usable output; an invocation,
runtime, digest, selection, or output-write error exits 2.

### Review design changes

Generate a standalone HTML report against a Git revision:

```sh
review_dir=$(mktemp -d)
nix run .#review -- docs/design --base origin/main -o "$review_dir/design-review.html"
```

The base comes from Git, and the second revision is the current working tree.
To compare two already available revisions, pass their layer directories
instead of `--base`. Two standalone Typst entry points also work when they
emit design-layer semantic records. Use `--format json` for the versioned
`design-review/v1` result. A successful comparison exits zero even when it
finds changes. Supply fresh output paths.

Typst emits structured records for the review, including diagram IDs. Python
compares those records directly. The Markdown projection uses the same layer
loader and Typst query code to produce reading material.
Diagram coordinates and decorative tints in the tested widgets are
presentation. It compares directed edges, labels, data values, and sequence
order. Changed native drawing code and formula bodies need manual review.
The report includes those limits even when no projected fields changed.

Add `--pdf` to write a before and an after PDF beside the HTML report. A stable,
unique `review-id:` on `diagram` or `diagram-native` allows comparison across
sections and adds a margin mark where a changed diagram appears. Use letters,
digits, underscores, or hyphens in the ID. Every change still appears in the
report if it has no PDF mark. The report evaluates each input once, sharing the
result when both paths resolve to the same source. With `--pdf`, it compiles
each distinct source once for the companions and reports compilation errors.
Use the regular render command for guideline advisories.

Add `--summary <path>` to also write a Markdown summary: the number of
confirmed changes and of changes that need review, the changes counted by
section, and each change that needs review. It is sized for one pull request
comment, and design text appears in it only inside code spans. Its first line
is `<!-- design-review changes=N -->`.

#### Review design changes in pull requests

A pull request that changes the design gets one comment from the **Design
review** workflow, and each push updates that comment. It holds the summary
and a link to the full report. A pull request that changes no design gets no
comment. Download the artifact from that link or from the job summary, extract
it, and open `design-review.html`. Keep the two PDF companions beside the HTML
so the report links work. The artifact stays with the workflow run and expires
according to the repository's retention policy.

For a consumer repository, copy the
[design review workflow](.github/workflows/design-review.yml) and use the
pinned review app forwarded by your flake, such as `.#design-gate-review`.
Set the layer path to the location used in both revisions. Check out the exact
PR head with full Git history and use `git merge-base` with the PR base SHA.
With Nix installed on the runner, the review step is:

```sh
base=$(git merge-base "$BASE_SHA" HEAD)
mkdir -p "$RUNNER_TEMP/design-review"
nix run .#design-gate-review -- docs/design --base "$base" --pdf \
  -o "$RUNNER_TEMP/design-review/design-review.html" \
  --summary "$RUNNER_TEMP/design-review/summary.md"
```

Set `BASE_SHA` from `github.event.pull_request.base.sha` on GitHub Actions. Omit
`--pdf` for HTML alone, or use `--format json` for a structured report. Upload
the output directory as one artifact and put the download link in the check
summary.

The workflow has two jobs, and their checks are named **Design review** and
**Design review comment**. The `review` job runs the pull request's code with
read access alone. The `comment` job holds `pull-requests: write`, runs none of
that code, and posts the summary from the artifact. Keep the two apart. A pull
request from a fork gets no comment, because its token cannot write; its report
is still in the check summary.

## Development

`nix develop` provides the vendored Typst renderer (a version-exact package
set, pinned so a render resolves nothing at run time). The renderer ignores
ambient system font paths and uses its embedded fonts, so the same source
produces the same PDF bytes on each supported host. Python and the formatter
are provided as well.

`nix fmt` formats the tree. `nix flake check` runs the formatter check, the
gate's self-tests (`scripts/*.test.sh`), and the projector's determinism
check (projecting the schema twice must yield identical bytes).

## Migrations

- [Unit contracts and folder contracts](docs/migrations/unit-contract.md) covers the `unit` block, the relaxed context structure, the new gate step, and what a host changes on upgrade.
- [Entity descriptions and typed attributes](docs/migrations/entity-descriptions-and-types.md) covers bundle updates, census rewrites, and PDF verification.
- [Reproducible font resolution](docs/migrations/reproducible-fonts.md) covers the embedded-font policy and host migration.

The [changelog](CHANGELOG.md) records unreleased renderer changes.

## Tested README snippets

The `snips` app packages upstream [Snips](https://github.com/cortesi/snips), pinned
by revision in `nix/snips.nix`. No snippet parser or checker is maintained here.

Keep example code in compiled, tested projects. Mark source regions with
`// snips-start: example` and `// snips-end: example`, then place
`<!-- snips: examples/example.gleam#example -->` above the README code fence.
Snips synchronizes the excerpt; the example project's tests establish behavior.
When using Prettier, place generated marker/fence pairs in its standard
`prettier-ignore-start` / `prettier-ignore-end` ranges: Snips requires adjacent
markers and fences, while Prettier normally inserts a blank line between them.
Format the source file with its language formatter before synchronizing snippets.

```sh
nix run .#snips -- --commands deny README.md
nix run .#snips -- --check --commands deny README.md
```

Consumers can expose `design-layer.apps.${system}.snips` as `apps.snips` and call
it directly from CI alongside their normal example tests. The package is also
available as `design-layer.packages.${system}.snips`. Snippet checking is separate
from the Typst design check and runs only on explicitly named Markdown files.

In an existing flake, add the input and forward the app inside its per-system
outputs (reuse an existing design-layer input):

```nix
inputs.design-layer.url = "github:lostbean/design-layer/main";
# Inside the outputs for each system, with design-layer in scope:
apps.snips = design-layer.apps.${system}.snips;
```

Commit `flake.lock` to keep CI and development on the same revision. Use
`nix flake update design-layer` to adopt a newer main revision deliberately.

For example, a README excerpt from `examples/basic/src/main.gleam` uses:

````markdown
<!-- prettier-ignore-start -->

<!-- snips: examples/basic/src/main.gleam#example -->
```gleam
pub fn greeting() {
  "Hello"
}
```

<!-- prettier-ignore-end -->
````

The source region encloses the complete `greeting` function. Use the source
language's comment syntax for region markers. Paths are relative to the Markdown
file; omit `#example` to include the whole file. Edit and format the source, then
run Snips in update mode and commit both files. Do not edit generated excerpts.

Add the check directly to an existing CI job, naming every managed README:

```yaml
- name: Check README snippets
  run: nix run --no-update-lock-file .#snips -- --check --commands deny README.md packages/example/README.md
```

Replace the example paths with the repository's actual files. Keep compilation
and behavioral tests for the source example projects in that job or the existing
application gate. Snips only detects stale excerpts; it does not compile or test
them. `--commands deny` disables command-backed snippets. No wrapper script,
README structure test, or duplicate example test suite is needed.

## Consumer app integration

Forward the pinned shared apps directly from a consumer flake:

```nix
apps.design-gate-render = design-layer.apps.${system}.render;
apps.design-gate-check = design-layer.apps.${system}.check;
apps.design-gate-context = design-layer.apps.${system}.context;
apps.design-gate-units = design-layer.apps.${system}.units;
apps.design-gate-review = design-layer.apps.${system}.review;
```

The render, check, and context apps prepare or refresh the generated `.render` library beside the root
`design.typ` before using it. The selected bundle owns this operation; consumers
need no projection wrapper or copied bootstrap script. `check` and `units` also
prepare each validated `--nested-project` layer. `check` still reports a stale
PDF without rewriting that PDF. All preparation uses local bundled files,
without network access.

`DESIGN_LIB_DIR` remains an explicit library override: preparation uses that
library when supplied. Direct script invocation retains its existing contract
and does not refresh a divergent layer library automatically.

The review app prepares a missing projection in either revision and validates
an existing projection against the selected renderer. A stale projection must
be refreshed before review. When comparing with `--base`, the archived base
uses the same selected renderer as the working tree.
