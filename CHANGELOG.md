# Changelog

## Unreleased

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
