# Changelog

## Unreleased

- Added the `#unit` block: one required shape for every design unit — `id`,
  `title`, `overview`, `interface`, `invariants`, `side-effects`,
  `verification`, and `paths` — with an optional body that holds any other
  block and nested units. A missing field, a malformed or duplicate id, and an
  illegal path fail the render; an empty list renders as `None`.
- Added the `units` app. It writes each unit's contract into a generated region
  of `AGENTS.md` in every directory the unit lists, and links `CLAUDE.md` where
  none exists. `check` now also fails on a unit path that does not exist, a
  stale region, and a region no unit lists, and reports the tracked directories
  no unit path covers.
- `context` gains `--unit ID` and `--path REPO-PATH`, and the manifest lists
  units when a layer declares them.
- The foundation minimum now binds the root design document only. A context
  document may omit goals, invariants, and principles, and is not held to the
  spine order or to its `System at a glance` and `End-to-end walkthrough`
  sections.
- A foundation statement written inside a unit's body is not read as part of
  the document's foundation order or minimum.
- A link may target a unit as `design.typ#unit-<id>`; `layer-integrity`
  resolves it.
- Rendered output changes by a sub-point amount where text directly follows a
  `#section` or `#subsection` call on the same line of flow, so a host
  re-renders its PDF on upgrade.
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
