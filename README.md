# Design Layer

A design layer is a small set of markdown files — `design.md`, `CONTEXT.md`,
an append-only `docs/adr/` — that describe a system's structure, vocabulary,
and decisions, kept next to the code and reviewed like code. This repo is the
**mechanical gate** for that layer: the renderer, the schema that declares its
block vocabulary, and the scripts that decide pass or fail. It holds no design
layer of its own.

## The one question this repo answers

**Is this `design.md` well-formed, and what does it render to?**

That is the whole scope. A block either satisfies its declared contract or the
render fails, fail-closed, naming the violation and its location. There is no
partial credit and no warning-only mode: a design document either compiles to
a PDF or it does not.

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
nix run github:lostbean/design-layer#aggregate -- docs/design docs/design/design-layer.pdf
nix run github:lostbean/design-layer#check     -- docs/design .
```

`aggregate` compiles every `design.md` under the layer root into one navigable
PDF — a context per chapter, one alphabetized glossary, a table of contents.
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

Two lower-level entry points back the composite ones above:

```sh
nix run github:lostbean/design-layer#render  -- <design.md> [--check]   # one document
nix run github:lostbean/design-layer#project -- <schema.json> <out-dir> # schema -> renderer library
```

`render` compiles a single `design.md` to its own PDF — useful for one
document in isolation, before it joins the aggregate. `project` is the seam
between the schema and the renderer: it reads `schema/design-schema.json` and
emits the Typst library every compile imports. You will not normally call it
directly — `aggregate`, `render`, and `check` all project fresh on demand —
but it is exposed for an installer or a CI job that wants the library as a
build artifact.

`nix build github:lostbean/design-layer#gate-bundle` gives the store path
holding the scripts, the schema, and a fresh projection of that schema
together, for a host that wants to reference all three as one unit.

## What a host repo stores

Nothing from this repo is ever copied in. A host that adopts a design layer
keeps only its own content, laid out under `docs/`:

```
docs/
  design/
    design.md              # or design/<context>/design.md, one per context
    CONTEXT.md              # the glossary — terms this system's design leans on
    design-layer.pdf        # the ONE rendered document (never hand-edited)
  CONTEXT-MAP.md            # multi-context layers only: links every CONTEXT.md
  COVERAGE.md                # optional: what the layer covers, what it doesn't
  adr/
    0001-first-decision.md  # append-only; a decision is superseded, never rewritten
```

A single-context layer is just `docs/design/{design.md,CONTEXT.md}` plus
`docs/adr/` — no `CONTEXT-MAP.md` required. Everything under `docs/` is the
layer; nothing about it lives beside the source it describes.

## What this repo deliberately does not do

- **It does not decide when to design, or how much.** That is a judgment
  call made with a rendered document in hand, not a mechanical property.
- **It does not hold a design layer of its own.** It is a tool. Its
  correctness is proven by the self-tests under `scripts/*.test.sh` and by
  `fixtures/widget-gallery.md`, the fixture that exercises every declared
  block kind — never by dogfooding a layer it would then have an incentive
  to keep looking good.
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
scripts/     the gate: aggregate, render, layer-integrity, token-coverage, render-project
schema/      the ONE declared schema — block vocabulary, anchors, layout, enums
fixtures/    the widget gallery: every block kind, and the renderer-drift tripwire
```

## Development

`nix develop` provides the vendored Typst renderer (a version-exact package
set, pinned so a render resolves nothing at run time), Python, and the
formatter.

`nix fmt` formats the tree. `nix flake check` runs the formatter check, the
gate's self-tests (`scripts/*.test.sh`), and the projector's determinism
check (projecting the schema twice must yield identical bytes).
