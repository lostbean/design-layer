# Working in this repo

The mechanical half of the design layer: the renderer, the projector, the block
contracts, and the gate. It answers one question — is this design layer
well-formed, and what does it render to.

## Two authoring surfaces, one library

A layer is authored in exactly ONE of two notations, and the mode is derived
from the files present rather than declared by a flag, so the declaration
cannot disagree with the tree:

- **markdown** — `design.md` + `CONTEXT.md`, converted by `md-to-typst`;
- **typst** — `design.typ` + `CONTEXT.typ`, calling the library directly.

A layer holding both is a hard error (exit 2) naming every file on each side,
in the aggregate and in `layer-integrity` alike. Preferring one side would
render a document silently missing the other, and that document reads as
complete — a coherent table of contents, every chapter present correct, and
nothing marking the absence.

Both notations reach ONE projected library, so a rule stated once binds either
way. A block kind and the function rendering it carry the same name, spelled
kebab (`design_doc.function_naming`); the one exception is `figure`, whose
function is `figure-block` because `figure` is a Typst builtin.

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

nix run .#render    -- <design.md> [--check]
nix run .#aggregate -- <layer-root> <out.pdf> [--check]
nix run .#check     -- <layer-root> <repo-root>
nix run .#project   -- schema/design-schema.json <out-dir>
```

The self-tests are the correctness proof — this repo has no design layer of its
own by decision, so nothing here is verified by dogfooding:

```sh
nix develop --command bash scripts/design-render.test.sh
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

There are TWO gallery fixtures, because there are two authoring surfaces and
each drifts on its own. `fixtures/widget-gallery.md` demonstrates every declared
block kind; `fixtures/native-gallery.typ` demonstrates every function projected
for native authoring, which no markdown document can reach.
`widget-coverage.test.sh` fails when a declared kind has no projected function,
when either gallery stops exercising one, or when a gallery renders without its
marks reaching the page.

## Where a check belongs

Three homes, and picking the wrong one is how a contract ends up declared and
unenforced:

- **The projected library** validates ONE block against its own contract —
  a required field, an enum value, a title length. It cannot see anything
  outside the block it is rendering.
- **`design-render`'s `assert_document`** folds over the WHOLE document —
  foundation cardinality and order, spine order, clause cardinality, pending
  entries. Anything needing two blocks compared belongs here. `given`/`when`/
  `then` render as independent calls, so clause order was impossible to check
  in the library and sat unenforced until the fold existed.
- **`layer-integrity`** crosses ARTIFACTS — links, anchors, homing, the
  coverage map's own citations.

A rule the schema declares and no home runs is worse than an undeclared one: the
manual promises it, an author trusts it, and nothing objects.

## Don't

- Do not hand-edit `designlib.typ` or any rendered PDF.
- Do not add ADR citations, references to a sibling framework repo, or its
  skill and primitive names. This repo ships to hosts that have none of them.
- Do not weaken a check to make something pass.
