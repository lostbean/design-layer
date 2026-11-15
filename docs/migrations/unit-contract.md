# Unit contracts and folder contracts

## Scope

- The library gains `#unit`, the one block with a required shape at every
  depth: `id`, `title`, `overview`, `interface`, `invariants`, `side-effects`,
  `verification`, and `paths`. Its body is optional and holds any other block,
  including nested units.
- The `units` app writes each unit's contract into a generated region of
  `AGENTS.md` in every directory that unit lists.
- `check` gains a fourth step: unit paths exist, folder contracts are fresh,
  and no folder carries a contract no unit lists. It also reports the tracked
  directories no unit path covers; the report never changes the exit code.
- The foundation minimum binds the root design document only. A context
  document may omit `goal`, `invariant`, and `principle`, and is no longer
  expected to follow the spine or to carry `System at a glance` and
  `End-to-end walkthrough`.
- `context` gains `--unit ID` and `--path REPO-PATH`.
- Every existing block and every existing layer stays valid. A layer that
  authors no unit needs no source change.

## Apply the upgrade

- Update the host repository's pinned design-layer input.
- Regenerate `docs/design/design-layer.pdf` through the host's render wrapper.
  The library now marks the start and end of each section body. Where prose
  directly follows a `#section` or `#subsection` call without a blank line, one
  line of text moves by a fraction of a point, so the committed PDF no longer
  matches a fresh render even when no source changed.
- A host that gates with its own schema copy adds `design_doc.blocks.unit`,
  `design_doc.unit_contract`, `design_doc.spine_scope`, the `unit` entry under
  `design_doc.agent_context.projection.classification.projected`, and the
  reworded `design_doc.foundation_cardinality`. Until it does, a layer with no
  unit still renders and gates, the unit step prints that it did not run, and
  the first `#unit` call fails naming the missing declaration.
- A host that wraps `check` needs no change: the wrapper already receives the
  new step. A host that forwards apps may forward `units` beside `render`.
- A host running the gate with `DESIGN_STRICT=1` no longer fails on a context
  document that omits a foundation kind.

## Adopt units, when the host chooses to

- Write one `#unit` per part of the design, and nest units to express the
  hierarchy. State an empty list as `()`; never leave a required field out.
- List exact repo-relative directories in `paths`. A grouping unit lists none.
- Export `#let context_command = "<the host's context app> --"` from the root
  `design.typ` so folder contracts print the host's own command. Without it
  they print `nix run github:lostbean/design-layer#context --`.
- Run the `units` app, then the render app, then the gate.
- Commit each generated `AGENTS.md` and each `CLAUDE.md` symlink with the
  design change that produced them.
- Keep a Markdown formatter away from the generated region. It is wrapped in
  `prettier-ignore` markers; a formatter that does not honor them needs the
  listed `AGENTS.md` files excluded.

## Verify

- Run the host's complete design gate after regenerating the PDF and the
  folder contracts.
- Read the uncovered-directory report and decide whether each listed directory
  should be claimed by a unit.
