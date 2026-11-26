# Changelog

## Unreleased

- `design-check` and `design-aggregate --check` accept `--no-rendered-file`
  for a host that does not commit `docs/design/design-layer.pdf`. The layer is
  still compiled, so one that does not render fails and guidelines are still
  reported; only the missing-or-stale PDF comparison is skipped. The flag is
  explicit and never inferred from the file's absence, and `design-aggregate`
  refuses it without `--check`. Without the flag nothing changes.
- **Breaking:** `review` now writes one PDF. Each changed part of the design is
  shown with the old design on the left and the new design on the right,
  after an index of the changed parts. The comparison of records still decides
  what changed; a part without a listed change is left out. Parts are paired
  by identity, a unit by its id and a section by its title in its document,
  and never by page number. Removed and added words are highlighted, and a
  changed diagram, custom figure, or formula is boxed on each side.
  The HTML report, `--format html`, `--pdf`, and the two separate PDFs are
  gone. To migrate a workflow, drop `--pdf`, give `-o` a `.pdf` path, upload
  that file, and point readers at it. `--format json` and `--summary` are
  unchanged, and each JSON change now names the part that draws it.
- The library records where each part, diagram, custom figure, and formula is
  drawn when a document is compiled with the input `review-places=1`. The
  record is metadata that draws nothing and moves nothing, and an ordinary
  render holds no trace of it. The margin bar the review used to draw beside a
  changed diagram, and the input `design-review-diagrams`, are gone.
- The design layer's own design now has a unit for the design review.

- `review` accepts `--summary <path>` and writes a Markdown summary beside the
  report: the confirmed and need-review counts, the changes counted by section,
  and each change that needs review. Design text appears in it only inside code
  spans. The design review workflow now has a second job that posts that
  summary as one pull request comment and updates it on every push. The job
  that runs the pull request's code keeps read access alone.
- Added the `#unit` block: one required shape for every design unit — `id`,
  `title`, `overview`, `interface`, `invariants`, `side-effects`,
  `verification`, and `paths` — with an optional body that holds any other
  block and nested units. A missing field, a malformed or duplicate id, an
  illegal path, and content in a field that is not prose — a list, a
  footnote, a box, a heading, a `context` — fail the render; an empty list
  renders as `None`. A field may hold a code block, such as a verification
  command, and the projection and a folder contract write it as a fenced
  block with a fence longer than any backtick run in it; a title holds none. Units nest down to the sixth heading level — five
  directly in the root document's body, four inside a section, three inside a
  subsection, one fewer in a context document — and one deeper fails the
  render, the projection, and the gate's unit step alike.
- A unit's body holds no `section` or `subsection`. Both keep their fixed
  heading level, which would sit above the unit that holds them, so the
  render, the projection, and the gate's unit step each refuse one there. A
  heading called with its own level at or above the unit's — such as
  `#heading(level: 2)` in a unit at level two — is refused the same way; a
  heading in markup, or called with no level, nests below the unit.
- Added the `units` app. It writes each unit's contract into a generated region
  of `AGENTS.md` in every directory the unit lists, and links `CLAUDE.md` where
  none exists. `check` now also fails on a unit path that does not exist, a
  stale region, a region no unit lists, a unit the Markdown projection would
  write past its sixth heading level, and a folder contract git tracks under
  another spelling than the file system stores. It reports the tracked
  directories no unit path covers.
- `units` writes only what it owns. A region is recognized by its whole
  generated shape, so a marker shown in a code block or a raw HTML block —
  `<pre>`, `<details>`, a comment — is never read, as a region's opening or
  as its end, and any other stray marker, or a region whose closing lines are
  missing, is reported, with what to do about it, and the file left as it
  is. A region a formatter touched — a space after a marker, a blank
  line between two of its lines — is still found, reported stale, and written
  again. Text outside the region keeps its line endings and its final newline,
  and removing a region restores the file byte for byte: a file that was empty
  before its region is left empty, and only a file the generator created is
  deleted. A target that is a symbolic link, a directory, or not UTF-8 text,
  and a unit path that is not the path the file system stores, are violations;
  a file named `AGENTS.md` that holds no marker is never read. A run writes
  every folder contract or none: every new text is staged in a temporary file
  before any target is replaced, and an interrupt leaves no temporary file
  behind. The `CLAUDE.md` link `units` creates — a symbolic link to the bare
  name `AGENTS.md` — goes with the region when the `AGENTS.md` is left with
  nothing to read; beside a file with text of its own it stays.
- `units` takes `--nested-project`, the argument `check` takes, and never
  writes into a nested project: a unit path inside a directory that holds its
  own design layer is refused whether or not the project is declared, and a
  region found there is left in place.
- `context` gains `--unit ID` and `--path REPO-PATH`, and the manifest lists
  units when a layer declares them. `--unit` prints the unit's own contract,
  body, and nested units, and stops where the unit does.
- The foundation minimum now binds the root design document only. A context
  document may omit goals, invariants, and principles, and is not held to the
  spine order or to its `System at a glance` and `End-to-end walkthrough`
  sections.
- A foundation statement written inside a unit's body is not read as part of
  the document's foundation order or minimum.
- A link may target a unit as `design.typ#unit-<id>`; `layer-integrity`
  resolves it wherever `id:` stands among the unit's arguments, and resolves
  the link each generated folder contract carries to its unit.
- Rendered output changes by a sub-point amount where text directly follows a
  `#section` or `#subsection` call on the same line of flow, so a host
  re-renders its PDF on upgrade. A heading written in markup keeps its level,
  its number, and its contents entry. One heading form does change: a heading
  called with no level, `#heading[...]`, inside a section or subsection body
  now takes the level below that body's heading instead of level one. It no
  longer opens a chapter, so the chapters and sections after it, which it
  used to renumber, take back the numbers they have without it. Inside a
  section body it is a level-three heading, numbered under the section and
  listed in the contents, and each later subsection of that section is
  numbered one higher. Inside a subsection body it is a level-four heading,
  which the contents — three levels deep — no longer lists. Give the call
  `level: 1` to keep the old reading.
- `nix flake check` now gates this repository's own design layer: its rendered
  PDF, its links, and its generated folder contracts.
- The migration is documented in [Unit contracts and folder contracts](docs/migrations/unit-contract.md).
- The layer-integrity gate now checks every host `README.md` and `AGENTS.md`
  outside `docs/`: links into `docs/design/` and `docs/adr/` must resolve
  (section anchors included), each bold title under `## Designed, not built`
  must name a pending entry, and a link to a superseded ADR is an advisory.
  Violations name the file and line.

- The agent-context projector now exposes a deterministic manifest, depth-limited
  preview, exact heading-subtree selection, token metrics, SHA-256 digests, and
  digest guards while preserving the complete projection as the default.
- The document renderer now uses one restrained visual grammar across pages,
  statements, cards, tables, drawings, legends, and inline semantic furniture.
- Added the native `#formula` block for displayed equations with optional
  numbering, stable targets, notation keys, captions, and shared accents.
- Added structured `#pseudocode` for implementation-neutral procedures, with
  explicit inputs, outputs, branches, iteration, repetition, and returns.
- Prose tables now consume the full text measure and allocate bounded column proportions from their content lengths, so compact columns remain compact without starving adjacent prose columns.
- Prose tables now use semantic headers, repeated headers across pages, and open horizontal rules instead of a spreadsheet grid.
- Invalid column counts, missing headers, non-array cells, and incomplete rows now fail with specific messages.
- The renderer ignores ambient system font paths and keeps its embedded font families for byte-stable PDF output across Ubuntu and macOS.
- The migration is documented in [Reproducible font resolution](docs/migrations/reproducible-fonts.md).
- `review --base <rev>` treats a base revision with nothing at the layer path
  as an empty layer, so the pull request that adopts a layer gets a report
  instead of exit 2. Every record in the working tree is reported as added.
  A layer path missing from the working tree is still an error.
- `review` compares a layer with no design documents as an empty layer under
  `--pdf` too. It writes no PDF for that side, where it used to fail to render
  one and exit 2. The HTML report and the `--summary` comment name the side
  that has no layer.
- The shared render function refuses a layer with no `design.typ` by name, as
  the `render` app already did, and writes nothing. A caller other than the
  app used to get a Typst type error instead.
- The design review workflow no longer loses or reverts its pull request
  comment. Re-running only a failed comment job used to look for the review
  under the new attempt's name, miss it, and post that the review could not
  be produced; the review job now passes the name it uploaded under. Runs for
  one pull request now take turns, so two runs no longer both create a
  comment: a new push cancels the review still running for an older head, and
  a re-run of an older run waits instead of cancelling the current one. The
  comment job posts nothing when the pull request has moved past the head its
  run reviewed, so neither an older run finishing late nor a re-run of one
  replaces a newer summary. A repository that copied the workflow should carry
  these changes.
- `context` projects a list in prose — a bullet item, an enum item, a term
  item in markup, and a `list`, `enum`, or `terms` call — as a Markdown list,
  where it used to stop on the whole layer with "unsupported Typst content
  function 'item'". A nested list, a second paragraph, or a code block stays
  inside its item. An item that states its number, or an item of an `enum`
  call, keeps its number; Typst records an automatically numbered `+` item
  the same way as a `-` item, so the projection writes it as a bullet. A
  list in a unit field is still refused by the render.
