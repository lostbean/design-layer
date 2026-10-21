# Design Layer

A design layer is a small set of authored files — `design.typ`, `CONTEXT.typ`,
an append-only `docs/adr/` — that describe a system's structure, vocabulary,
and decisions, kept next to the code and reviewed like code. This repo is the
**mechanical gate** for that layer: the renderer, the schema that declares its
block vocabulary, and the scripts that decide pass or fail. It holds no design
layer of its own.

## The one question this repo answers

**Is this `design.typ` well-formed, and what does it render to?**

That is the whole scope, and the answer comes in two severities, split by what
a violation breaks.

**Referential integrity is fail-closed.** A reference that resolves to nothing
is broken output, not a matter of taste: a `term()` no `CONTEXT.typ` declares
has no text to render, a diagram edge naming no node draws a line to nowhere,
and a value outside a declared vocabulary is one the renderer would have to
invent a meaning for. These fail the render, naming the violation and its
location, and no flag relaxes them.

**Structure is guided by warnings.** Which foundation kinds a context declares,
what order its sections run in, whether every required attribute was filled —
these are opinions about how a design is usually organized, and a design
legitimately changes shape. The renderer says what it expected, names the rule
and the offending item, and renders anyway. Every guideline prints on every
render and the run ends with a count summary, so guidance is never silent; none
of it changes the exit code. Set `DESIGN_STRICT=1` to escalate every guideline
to a hard failure, for a repo that wants the stricter ratchet in CI.

The reason for the split: a design document that will not render helps nobody,
and refusing to draw a layer because it carries two of the three foundation
kinds fails a document a reader may still need. A broken reference is different
in kind — it produces a document that looks finished and is quietly wrong.

This repo has **no opinion** about:

- when a system is worth designing, or how deep to go
- what to build next, or how to prioritize it
- whether a design is _good_ — only whether it is well-formed

Those are judgment calls a human or an agent makes with the rendered document
in front of them. This repo's job ends at "it renders" or "here is exactly
what's wrong."

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
`check` then runs three things in sequence and exits 0 clean, 1 on a
violation, 2 on an error:

1. **freshness** — regenerate the aggregate and byte-compare it against the
   committed PDF, so a stale render is caught, not trusted
2. **token coverage** — every semantic token a block renderer references
   (a lens color, a tint, an enforcement badge) is actually defined
3. **layer integrity** — every cross-link resolves (a term citation, an ADR
   reference, a section pointer), every ADR is in lockstep with its filename,
   every glossary term is unique, no layer file sits outside its declared
   home under `docs/`

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
layer; nothing about it lives beside the source it describes.

## What this repo deliberately does not do

- **It does not decide when to design, or how much.** That is a judgment
  call made with a rendered document in hand, not a mechanical property.
- **It does not hold a design layer of its own.** It is a tool. Its
  correctness is proven by the self-tests under `scripts/*.test.sh` and by
  `fixtures/gallery.typ`, the fixture that exercises every function the
  library projects for authoring — never by dogfooding a layer it would then
  have an incentive to keep looking good.
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
scripts/     the gate: design-aggregate, layer-integrity, token-coverage, render-project
schema/      the ONE declared schema — block vocabulary, anchors, layout, enums
fixtures/    the gallery: every projected function, and the renderer-drift tripwire
skills/      the authoring guidance an agent loads to write a well-formed layer
```

## Writing a design document

The gate tells you a document is malformed; it does not tell you how to write
one. That is `skills/design-document-syntax/SKILL.md` — the format
specification: the artifact set and where each file lives, the term and ADR
anchors, block anatomy and the `title` contract, the whole block vocabulary,
the section spine, the pending ledger's fields, the behavior and entity census
blocks, and which rules are machine-checked rather than convention. It is a
plain markdown file; read it in the browser, in a clone, or point an agent
at it.

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
and references. It omits presentation-only furniture and fails when a public
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

The estimate reports UTF-8 bytes, characters, words, lines, and the named
planning estimates `ceil(utf8_bytes/4)` and `ceil(utf8_bytes/3)`. These values
are model-independent estimates rather than tokenizer counts. The manifest
adds SHA-256 digests without changing the legacy estimate shape.

The Markdown is a temporary reading projection. Typst remains authoritative,
the PDF remains the published rendered artifact, and the Markdown output is not
committed. A semantic violation exits 1 without usable output; an invocation,
runtime, digest, section-selection, or output-write error exits 2.

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
