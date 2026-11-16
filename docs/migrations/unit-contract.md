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
  The library now scopes a heading style over each section and subsection
  body, which is how a nested unit finds its level. Where prose directly
  follows a `#section` or `#subsection` call without a blank line, one line of
  text moves by a fraction of a point, so the committed PDF no longer matches a
  fresh render even when no source changed.
- Headings keep their levels. The library's own blocks and a heading written
  in markup — `=== Title` — render at the level, number, and contents entry
  they had. One form changes: a heading called with no level, `#heading[...]`,
  inside a section or subsection body takes the level below that body's
  heading instead of level one. It no longer opens a chapter, so the chapters
  and sections after it take back the numbers they have without it. In a
  section body it becomes a level-three heading, numbered under the section
  and listed in the contents, and each later subsection of that section is
  numbered one higher. In a subsection body it becomes a level-four heading,
  which the contents — three levels deep — no longer lists. Give such a call
  `level: 1` to keep the old reading.
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
  Write each path as the file system stores it: no symbolic link in it, and
  the letter case its parent directory lists.
- Write prose in a field: text, emphasis, inline code, a code block, a link,
  a reference, mathematics, and the library's inline citations. A code block
  is projected as a fenced block, so a verification command may be written as
  one; a title holds none. A list, a footnote, a box, a heading, or a
  `context` in a field fails the render. Write each point as
  its own item of `interface`, `invariants`, or `side-effects`, and put
  anything else in the unit's body.
- Keep `section` and `subsection` out of a unit's body. They are the
  document's spine; inside a unit, a nested unit carries the structure. A
  heading written in markup in a unit's body nests below the unit.
- Nest at most to the sixth heading level: five units directly in the root
  document's body, four inside a section, three inside a subsection, and one
  fewer in a context document.
- Export `#let context_command = "<the host's context app> --"` from the root
  `design.typ` so folder contracts print the host's own command. Without it
  they print `nix run github:lostbean/design-layer#context --`.
- Run the `units` app, then the render app, then the gate. A repository with
  nested projects passes `units` the same `--nested-project <path>` arguments
  it passes `check`; without them `units` reports a nested project's contracts
  and writes nothing.
- List a folder of a nested project in that project's own layer. A unit path
  inside a directory that holds its own `docs/design/design.typ` is refused,
  whether or not the project is declared.
- Keep git's spelling of a listed directory the same as the file system's. On
  a file system that folds letter case, a directory renamed in case only keeps
  its old spelling in git; the gate reports the folder contract naming both
  spellings, and `git mv` through a temporary name makes them agree.
- Replace an `AGENTS.md` that is a symbolic link with a regular file in each
  listed directory. `units` does not write through a link.
- Commit each generated `AGENTS.md` and each `CLAUDE.md` symlink with the
  design change that produced them.
- Keep a Markdown formatter away from the generated region. It is wrapped in
  `prettier-ignore` markers; a formatter that does not honor them needs the
  listed `AGENTS.md` files excluded. A region a formatter did touch is
  reported stale, and `units` writes it again.
- When `units` reports a malformed region, delete the region's lines, from the
  begin marker through the end marker, and run `units` again.

## Verify

- Run the host's complete design gate after regenerating the PDF and the
  folder contracts.
- Read the uncovered-directory report and decide whether each listed directory
  should be claimed by a unit.
