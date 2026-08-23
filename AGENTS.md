# Working in this repo

The mechanical half of the design layer: the renderer, the projector, the block
contracts, and the gate. It answers one question — is this design layer
well-formed, and what does it render to.

## One authoring surface

A layer is authored in Typst: `design.typ` + `CONTEXT.typ`, calling the
projected library directly. There is no conversion step, so a construct
outside the grammar cannot half-convert into something that renders
differently from what it says, and a rule that would have been a second parse
over the source is instead a function signature the compiler enforces at the
line the author writes.

Markdown authoring was REMOVED. A layer still carrying a `design.md` is
refused by name — the aggregate and `layer-integrity` both name every markdown
file and point at the migration — rather than walked past: ignoring it would
report "no design layer" against a directory visibly full of design documents,
and send the reader after the wrong fault.

ADRs, `CONTEXT-MAP.md` and `COVERAGE.md` are unaffected. They were never the
authoring surface and stay markdown, with the anchor contract intact; the ADR
markers in `layer_layout.design_ish_markers` are what keep an ADR citation
resolving.

A block kind and the function rendering it carry the same name, spelled kebab
(`design_doc.function_naming`); the one exception is `figure`, whose function
is `figure-block` because `figure` is a Typst builtin.

The library holds **two classes of rule**, and the class is visible at every
check site. An **invariant** is a rule whose violation makes the model wrong —
a value outside a declared enum, an edge naming no node, a block missing the
field that gives it meaning — and it panics. A **guideline** is a rule of style;
it is silent by default and panics only under `--input strict=1`. Nothing is
ever emitted onto the page: a design document is read by someone who did not
write it, who cannot act on a lint note.

## Run every tool through Nix, never bare

`nix develop --command <tool>`, or `nix run .#<app>`, or
`nix shell nixpkgs#<pkg> --command <tool>` for something the dev shell does not
carry. Nothing is guaranteed on a bare `PATH` — not `typst`, not `pdftotext`,
not the scripts themselves.

The reason is that the failure is silent rather than loud. A script that cannot
find its tool does not always stop: a check whose helper is missing can report
SKIP, or skip a branch, and the run still exits 0. That happened here. The
commit hook ran the self-tests bare while its own comment claimed the dev shell
provided them; without `pdftotext` the chapter-doubling assertion reported SKIP,
and the hook passed green while the case it existed for never ran. A degrading
check is worse than a missing one, because it reports success.

So a command that needs a tool is the command that supplies it. `lefthook.yml`
wraps the self-tests in `nix develop --command`, and
`checks.gate-self-tests` lists every tool in `nativeBuildInputs` rather than
assuming the sandbox has it.

## The commands

```sh
nix develop                       # the dev shell: lefthook, typst, pdftotext, python3
nix flake check                   # formatting, the self-tests, projection determinism
nix fmt                           # treefmt: nixfmt, prettier, shfmt, ruff-format

nix run .#aggregate -- <layer-root> <out.pdf> [--check]
nix run .#check     -- <layer-root> <repo-root>
nix run .#lint      -- <layer-root>          # the guideline sweep, never a gate
nix run .#project   -- schema/design-schema.json <out-dir>
```

`check` runs the invariants and decides pass or fail. `lint` promotes every
GUIDELINE to an error and is invoked by an author, never by the gate or the
commit hook: a guideline names a document that could read better, never one
that is wrong, so blocking a commit on one would impose a house style through
a mechanism meant for correctness.

The self-tests are the correctness proof — this repo has no design layer of its
own by decision, so nothing here is verified by dogfooding:

```sh
nix develop --command bash scripts/layer-integrity.test.sh
nix develop --command bash scripts/widget-coverage.test.sh
nix develop --command bash scripts/designlib-native.test.sh
nix develop --command bash scripts/typst-layer.test.sh
nix develop --command bash scripts/vendored-offline.test.sh
```

## What is generated, and what is authored

`designlib.typ` is **projected from the schema** by `scripts/render-project` and
is never hand-edited. A contract changes in `schema/design-schema.json`, and the
projection follows.

`fixtures/gallery.typ` is the ONE gallery: it calls every function the
library projects for authoring, and it is a DRIFT TRIPWIRE rather than
documentation. `widget-coverage.test.sh` fails when a declared kind has no
projected function, when the gallery stops exercising one, or when the gallery
renders without its marks reaching the page.

The gallery's exemption list is short on purpose. Every name on it is a
function the check stops looking at, so an exemption granted loosely is
coverage silently withdrawn. Only the four calls the AGGREGATE emits — the
document shell, a chapter page, a glossary entry's owner chip, the vocabulary
registry — plus the document-level assertions are exempt, and those are
covered where they are real, in `typst-layer.test.sh`.

## Where a check belongs

Three homes, and picking the wrong one is how a contract ends up declared and
unenforced:

- **The projected library** validates ONE block against its own contract —
  a required field, an enum value, a title length.
- **The projected library's TRAILS** carry a fact across calls, which is how a
  DOCUMENT-level rule is enforced without a second parse. `_foundation-trail`
  records each foundation statement, and `assert-foundation-order` and
  `assert-foundation-cardinality` read it back — the cardinality rule is the
  one that must notice a block NOBODY WROTE, and a kind missing from the
  finished trail was never called. `_clause-trail` does the same for a
  behavior block's given/when/then, and `_spine-trail` for the numbered
  sections. Each trail is reset at the boundary of the scope it judges: a
  context for the foundation and the spine, one block for the clauses.
- **`layer-integrity`** crosses ARTIFACTS — links, anchors, homing, the
  coverage map's own citations.

A rule the schema declares and no home runs is worse than an undeclared one: the
manual promises it, an author trusts it, and nothing objects.

**A check that stops looking at anything still reports OK.** That is this
repo's recurring failure, and it has two shapes. A rule can be DECLARED in the
schema and enforced nowhere — the foundation order was projected as
`FOUNDATION-ORDER` and read as enforcement to anyone who grepped for it, while
nothing ran it. Or a check can be guarded off for a notation and left that
way, so the guard becomes unconditional and the body never executes again.

So a rule needs a home that actually runs it, and a test proving it FAILS on a
document that violates it. An assertion that only ever passes proves nothing;
every contract added here is asserted in both directions.

## Don't

- Do not hand-edit `designlib.typ` or any rendered PDF.
- Do not add ADR citations, references to a sibling framework repo, or its
  skill and primitive names. This repo ships to hosts that have none of them.
- Do not weaken a check to make something pass.
