<!-- design-units:begin -->
<!-- Generated from the design layer by design-units. Do not edit between these markers: change the unit in its Typst source and regenerate. -->
<!-- prettier-ignore-start -->

## Design unit: PDF renderer

Overview: `design-aggregate` discovers the root and context documents, declares the layer's vocabulary, and compiles one PDF under a shared shell. `render-project` assembles the library directory it compiles against.

Interface:

- `render <layer-root> <out.pdf>` writes the document.
- `render <layer-root> <out.pdf> --check` regenerates and compares, and writes nothing.
- `project <schema> <out-dir>` assembles a library directory.

Invariants:

- Two renders of one source are byte-identical.
- A layer-local library that differs from the one in use is refused before anything renders.
- A compiler warning fails the render.

Side effects:

- Writes the PDF and a compile workspace under `.render`, which it removes.
- The public app refreshes the layer's `.render` library copy.

Verification: `nix develop --command bash scripts/typst-layer.test.sh`

Source: [docs/design/design.typ#unit-pdf-renderer](../docs/design/design.typ#unit-pdf-renderer)

Full unit: `nix run .#context -- docs/design --unit pdf-renderer`

## Design unit: Markdown projector

Overview: `design-context` queries the semantic metadata the authoring calls emit and writes Markdown for an agent. It preserves decision-bearing fields and relationships and omits presentation.

Interface:

- `context <layer-root>` prints the complete projection.
- `--manifest` and `--preview` list section addresses, unit ids, sizes, and a digest.
- `--section <address>`, `--unit <id>`, and `--path <repo-path>` print one part; `--expect-digest` refuses a part from another snapshot.
- `--unit` prints a unit's contract, body, and nested units, and stops where the unit does.

Invariants:

- A construct with no Markdown form fails the projection instead of disappearing.
- Complete output and selected output come from one projection.

Side effects:

- Writes a file only under `--output`, and never over an existing one.

Verification: `nix develop --command bash scripts/design-context.test.sh`

Source: [docs/design/design.typ#unit-markdown-projector](../docs/design/design.typ#unit-markdown-projector)

Full unit: `nix run .#context -- docs/design --unit markdown-projector`

## Design unit: Folder contracts

Overview: `design-units` writes each unit's contract into the `AGENTS.md` of every directory that unit lists. An agent working in a folder then reads its governing contract without loading the layer.

Interface:

- `units <layer-root> [repo-root]` writes the contracts.
- `units <layer-root> [repo-root] --check` regenerates and compares.
- `--nested-project <path>` leaves a nested project out, then handles its own layer against its own root.

Invariants:

- Text outside the generated region keeps every byte, its line endings and final newline included.
- A region is recognized by its whole generated shape. A marker in a code block or a raw HTML block is never read, and any other stray marker, or a region missing its closing lines, leaves the file untouched.
- A target is a regular file in a directory stored under the listed path. A symbolic link is never written through.
- A run writes every folder contract or none. Every new text is staged before any file is replaced.
- An existing `CLAUDE.md` is never replaced. The link the generator makes goes when its region leaves a file left with nothing to read.
- A region no unit lists is removed, and its file only when the file is the region alone, as the generator created it.
- Nothing is written into a nested project. A unit path inside one is refused, and a region found there is reported and left in place.

Side effects:

- Creates, replaces, or deletes `AGENTS.md` in listed directories, each staged in a temporary file and renamed into place.
- Creates a `CLAUDE.md` symlink where none exists.
- The public app refreshes the `.render` library copy of the layer and of each nested project's layer.

Verification: `nix develop --command bash scripts/design-units.test.sh`

Source: [docs/design/design.typ#unit-folder-contracts](../docs/design/design.typ#unit-folder-contracts)

Full unit: `nix run .#context -- docs/design --unit folder-contracts`

## Design unit: Design review

Overview: `design-review` shows what a change did to a layer. It compares the semantic metadata of two revisions, ties each difference to the part that draws it, and composes one PDF with the old part on the left and the new part on the right. A part is a document, a section, a subsection, a unit, a pending ledger, or the glossary.

Interface:

- `review <layer-root> --base <revision> -o <changes.pdf>` compares the working tree with a Git revision. `review <before> <after> -o <changes.pdf>` compares two layer roots or two Typst entry points.
- `--summary <path>` also writes Markdown sized for one pull request comment: the counts by section and each change that needs review.
- `--format json` writes the comparison as a `design-review/v1` report for an agent, with the part of each change, and writes no PDF.
- The PDF opens with an index of the changed parts, each linked to its sheet. Each sheet names its part, the counts of its changes, and the page each side comes from. Both sides start level at the top of the sheet.
- Exit 0 when the comparison ran, with or without a change, and 2 when it could not run or the PDF could not be rendered.

Invariants:

- The comparison of semantic metadata alone decides what changed. The PDF shows every part that holds a listed change, and no part that holds none.
- Parts are paired by identity, never by page number: a unit by its id, a section by its title within its document, a document by its name. A part in one revision alone is shown as added or removed.
- A record belongs to the part whose heading is the last one drawn before it. A part the rendered document does not show by itself counts in the part that encloses it.
- An added or removed record is one change. It is shown with every part it holds, such as the sections and units of an added document.
- Every listed change is counted on the sheet of one shown part. The counts of the PDF, the summary, and the JSON report agree.
- Each side shows its revision as rendered. A mark is drawn over the page and moves nothing.
- A highlight on changed words helps a reader find a listed change. It appears only inside a shown part and adds nothing to the counts.
- A changed diagram, custom figure, or formula is boxed on each side on every page where it is drawn. Changed native drawing code and a changed formula body are listed as needing review, and the tool does not judge them.
- A difference in presentation alone, such as a tint, a layout, or a column count, is not a change.
- Two revisions without a change produce a one-page PDF that says so.

Side effects:

- Writes the PDF, and the summary or report when asked, and never over an existing file.
- Extracts the base revision into a temporary directory, which it removes.
- Creates the `.render` library copy of a compared layer that has none.

Verification: `nix flake check`, which runs `scripts/design-review.test.sh`.

Source: [docs/design/design.typ#unit-design-review](../docs/design/design.typ#unit-design-review)

Full unit: `nix run .#context -- docs/design --unit design-review`

## Design unit: Document gate

Overview: The `check` app decides whether a layer is well-formed. It proves the PDF fresh, checks semantic token coverage, resolves cross-artifact references, and checks every unit path and folder contract.

Interface:

- `check <layer-root> [repo-root]` exits 0 when clean, 1 on a violation, and 2 on an error. `--nested-project <path>` adds an independently checked project.
- `lint <layer-root>` reports the first guideline as an error. It is never part of `check`.

Invariants:

- A stale generated artifact is reported and never rewritten.
- A check that examined nothing does not report a pass.
- A unit the projection cannot address fails the gate, although the gate never runs the projection.
- The report of directories no unit covers never changes the exit code.

Side effects:

- Refreshes the `.render` library copy of the checked layer and of each nested project's layer.

Verification: `nix flake check`

Source: [docs/design/design.typ#unit-document-gate](../docs/design/design.typ#unit-document-gate)

Full unit: `nix run .#context -- docs/design --unit document-gate`

<!-- prettier-ignore-end -->
<!-- design-units:end -->
