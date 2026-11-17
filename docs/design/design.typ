#import ".render/designlib.typ": *

#let title = [Design Layer]
#let accent = "blue"
#let context_command = "nix run .#context --"

#let body = [
  Design Layer helps a project explain its architecture to people and code
  agents from one authored source. It combines documentation guidance with a
  checked Typst library, a PDF renderer, a Markdown projector, a folder-contract
  generator, a design review, and a document gate. The project being described
  remains responsible for its architecture.

  #section(title: "Foundation", lead: "Shared understanding with explicit limits.", body: [
    #goal(title: "Orient a newcomer")[
      Explain purpose, boundaries, principal abstractions, and their cooperation
      in a form that people can read as PDF and agents can read as Markdown.
    ]
    #no-goal(title: "Choose the host architecture")[
      This repository guides documentation. It does not choose the host's
      architecture, prescribe its implementation, or prove that its code
      satisfies the documented intent.
    ]
    #invariant(title: "Reject undefined meaning", enforcement: "mechanism")[
      An illegal declared value or unresolved semantic reference fails
      validation. The Markdown projector rejects unsupported content instead
      of silently dropping it.
    ]
    #principle(title: "Keep implementation authority in code")[
      The layer explains the system at architectural depth. Code remains
      authoritative for implemented detail; established owner intent supplies
      goals and rationale. A passing document gate establishes well-formedness.
    ]
  ])

  #section(title: "System at a glance", lead: "One source serves two reading modes.", visual: diagram(
    altitude: "L3",
    title: "The document pipeline",
    caption: [The host supplies authored content. The library checks it and
      exposes visual output or semantic metadata. The PDF renderer consumes the
      visual view; the Markdown projector and the folder-contract generator
      consume the semantic one. The design review reads both views of two
      revisions. The separate gate also checks references and folder contracts
      across the host's artifacts.],
    flow: "top-to-bottom",
    nodes: (
      (id: "source", label: "Host sources", sub: "Typst + vocabulary", kind: "external-system"),
      (id: "library", label: "Checked library", sub: "schema-backed contracts", kind: "component"),
      (id: "pdf", label: "PDF renderer", sub: "human reading", kind: "component"),
      (id: "markdown", label: "Markdown projector", sub: "agent reading", kind: "component"),
      (id: "contracts", label: "Folder contracts", sub: "AGENTS.md per code folder", kind: "component"),
      (id: "review", label: "Design review", sub: "what a change did", kind: "component"),
    ),
    edges: (
      (from: "source", to: "library", relation: "call", label: "calls authoring functions"),
      (from: "library", to: "pdf", relation: "dataflow", label: "visual content"),
      (from: "library", to: "markdown", relation: "dataflow", label: "semantic metadata"),
      (from: "library", to: "contracts", relation: "dataflow", label: "unit contracts"),
      (from: "library", to: "review", relation: "dataflow", label: "metadata and places"),
      (from: "pdf", to: "review", relation: "dataflow", label: "rendered pages"),
    ),
  ), body: [
    *Host boundary.* A host owns its `design.typ`, glossary `CONTEXT.typ`, and
    supporting Markdown records under `docs/`. Its code is not an input to the
    renderer. A human or agent uses the documentation skills to select supported
    architectural claims before authoring them.

    *Tool boundary.* Nix packages the scripts, schema, library, Typst compiler,
    fonts policy, and vendored drawing dependencies. A host pins that bundle.
    The public apps prepare a disposable `.render` library beside the layer;
    source files call its functions directly. There is no Markdown authoring
    conversion between those calls and their contracts.

    *State boundary.* Authored sources, the host's committed PDF, and the
    generated region of each listed folder's `AGENTS.md` persist. Library
    copies, compile workspaces, and agent Markdown are derived outputs. The
    system owns no application database or long-running service.
  ])

  #section(title: "Progressive breakdown", lead: "Responsibilities follow the evidence each part can see.", body: [
    Each part below is a #term("term-design-unit"). It answers the same five
    questions at every depth and lists the directories that realize it. A
    listed directory carries the unit as a #term("term-folder-contract").

    *Validation has three scopes.* Individual calls check their own values.
    Compile-local trails collect facts across calls, then document assertions
    check the completed scope; this can detect an omitted statement as well as
    a malformed one. Artifact integrity resolves links, glossary ownership,
    declared file homes, unit paths, and folder contracts across the repository.

    An #term("term-invariant") rejects invalid meaning. A #term("term-guideline")
    reports a structural or style expectation without blocking an ordinary
    render. Strict mode promotes guidelines to errors. Reports stay outside
    the PDF so readers see the authored design rather than authoring diagnostics.

    #unit(
      id: "documentation-guidance",
      title: "Documentation guidance",
      overview: [Two skills travel in the bundle. `document-design` selects
        what a newcomer needs and where explanation stops.
        `design-document-syntax` owns exact notation and mechanical contracts.],
      interface: (
        [`skills/document-design/SKILL.md` states the baseline unit contract
          and when each optional block applies.],
        [`skills/design-document-syntax/SKILL.md` states file homes, calls,
          vocabularies, and commands.],
      ),
      invariants: (
        [The syntax skill describes only what the library, the schema, or a
          gate script decides.],
        [Neither skill names a sibling framework or a host workflow.],
      ),
      side-effects: (),
      verification: [None mechanical. The gallery and the self-tests hold the
        contracts the skills describe.],
      paths: ("skills",),
    )

    #unit(
      id: "checked-library",
      title: "Checked library",
      overview: [Hand-written Typst that reads the schema at compile time. One
        function per block kind validates its own call, then draws it for the
        PDF or emits #term("term-semantic-metadata") for the projection.],
      interface: (
        [`designlib.typ` is the one import a `design.typ` makes.],
        [`schema/design-schema.json` declares every vocabulary, the unit
          contract, and the anchor patterns.],
        [The compile input `strict=1` promotes every guideline to an error;
          `context=1` switches every call to semantic metadata.],
        [The compile input `review-places=1` makes every document, section,
          subsection, unit, pending ledger, glossary, diagram, custom figure,
          and formula record the page and position where it is drawn, as
          metadata that draws nothing and moves nothing.],
      ),
      invariants: (
        [A value outside a declared vocabulary, an unresolved reference, and a
          unit missing a required field fail the compile.],
        [A unit's heading level is its depth. A unit past the sixth level
          fails the compile, as it fails the projection.],
        [A unit field holds prose only, a code block included, and a unit's
          body holds no section or heading above the unit. Content the
          projection cannot express fails the compile.],
        [A guideline never reaches the page and never blocks an ordinary
          render.],
        [Every declared block kind resolves to a callable function of the same
          name, and the gallery calls it.],
      ),
      side-effects: (),
      verification: [`nix develop --command bash scripts/designlib-native.test.sh`
        and `scripts/widget-coverage.test.sh`.],
      paths: ("lib", "schema", "fixtures"),
    )

    #unit(
      id: "pdf-renderer",
      title: "PDF renderer",
      overview: [`design-aggregate` discovers the root and context documents,
        declares the layer's vocabulary, and compiles one PDF under a shared
        shell. `render-project` assembles the library directory it compiles
        against.],
      interface: (
        [`render <layer-root> <out.pdf>` writes the document.],
        [`render <layer-root> <out.pdf> --check` regenerates and compares, and
          writes nothing.],
        [`project <schema> <out-dir>` assembles a library directory.],
      ),
      invariants: (
        [Two renders of one source are byte-identical.],
        [A layer-local library that differs from the one in use is refused
          before anything renders.],
        [A compiler warning fails the render.],
      ),
      side-effects: (
        [Writes the PDF and a compile workspace under `.render`, which it
          removes.],
        [The public app refreshes the layer's `.render` library copy.],
      ),
      verification: [`nix develop --command bash scripts/typst-layer.test.sh`],
      paths: ("scripts",),
    )

    #unit(
      id: "markdown-projector",
      title: "Markdown projector",
      overview: [`design-context` queries the semantic metadata the authoring
        calls emit and writes Markdown for an agent. It preserves
        decision-bearing fields and relationships and omits presentation.],
      interface: (
        [`context <layer-root>` prints the complete projection.],
        [`--manifest` and `--preview` list section addresses, unit ids, sizes,
          and a digest.],
        [`--section <address>`, `--unit <id>`, and `--path <repo-path>` print
          one part; `--expect-digest` refuses a part from another snapshot.],
        [`--unit` prints a unit's contract, body, and nested units, and stops
          where the unit does.],
      ),
      invariants: (
        [A construct with no Markdown form fails the projection instead of
          disappearing.],
        [Complete output and selected output come from one projection.],
      ),
      side-effects: (
        [Writes a file only under `--output`, and never over an existing one.],
      ),
      verification: [`nix develop --command bash scripts/design-context.test.sh`],
      paths: ("scripts",),
    )

    #unit(
      id: "folder-contracts",
      title: "Folder contracts",
      overview: [`design-units` writes each unit's contract into the
        `AGENTS.md` of every directory that unit lists. An agent working in a
        folder then reads its governing contract without loading the layer.],
      interface: (
        [`units <layer-root> [repo-root]` writes the contracts.],
        [`units <layer-root> [repo-root] --check` regenerates and compares.],
        [`--nested-project <path>` leaves a nested project out, then handles
          its own layer against its own root.],
      ),
      invariants: (
        [Text outside the generated region keeps every byte, its line endings
          and final newline included.],
        [A region is recognized by its whole generated shape. A marker in a
          code block or a raw HTML block is never read, and any other stray
          marker, or a region missing its closing lines, leaves the file
          untouched.],
        [A target is a regular file in a directory stored under the listed
          path. A symbolic link is never written through.],
        [A run writes every folder contract or none. Every new text is
          staged before any file is replaced.],
        [An existing `CLAUDE.md` is never replaced. The link the generator
          makes goes when its region leaves a file left with nothing to
          read.],
        [A region no unit lists is removed, and its file only when the file
          is the region alone, as the generator created it.],
        [Nothing is written into a nested project. A unit path inside one is
          refused, and a region found there is reported and left in place.],
      ),
      side-effects: (
        [Creates, replaces, or deletes `AGENTS.md` in listed directories,
          each staged in a temporary file and renamed into place.],
        [Creates a `CLAUDE.md` symlink where none exists.],
        [The public app refreshes the `.render` library copy of the layer and
          of each nested project's layer.],
      ),
      verification: [`nix develop --command bash scripts/design-units.test.sh`],
      paths: ("scripts",),
    )

    #unit(
      id: "design-review",
      title: "Design review",
      overview: [`design-review` shows what a change did to a layer. It
        compares the semantic metadata of two revisions, ties each difference
        to the part that draws it, and composes one PDF with the old part on
        the left and the new part on the right. A part is a document, a
        section, a subsection, a unit, a pending ledger, or the glossary.],
      interface: (
        [`review <layer-root> --base <revision> -o <changes.pdf>` compares the
          working tree with a Git revision. `review <before> <after> -o
          <changes.pdf>` compares two layer roots or two Typst entry points.],
        [`--summary <path>` also writes Markdown sized for one pull request
          comment: the counts by section and each change that needs review.],
        [`--format json` writes the comparison as a `design-review/v1` report
          for an agent, with the part of each change, and writes no PDF.],
        [The PDF opens with an index of the changed parts, each linked to its
          sheet. Each sheet names its part, the counts of its changes, and
          the page each side comes from. Both sides start level at the top of
          the sheet.],
        [Exit 0 when the comparison ran, with or without a change, and 2 when
          it could not run or the PDF could not be rendered.],
      ),
      invariants: (
        [The comparison of semantic metadata alone decides what changed. The
          PDF shows every part that holds a listed change, and no part that
          holds none.],
        [Parts are paired by identity, never by page number: a unit by its id,
          a section by its title within its document, a document by its name.
          A part in one revision alone is shown as added or removed.],
        [A record belongs to the part whose heading is the last one drawn
          before it. A part the rendered document does not show by itself
          counts in the part that encloses it.],
        [An added or removed record is one change. It is shown with every
          part it holds, such as the sections and units of an added
          document.],
        [Every listed change is counted on the sheet of one shown part. The
          counts of the PDF, the summary, and the JSON report agree.],
        [Each side shows its revision as rendered. A mark is drawn over the
          page and moves nothing.],
        [A highlight on changed words helps a reader find a listed change. It
          appears only inside a shown part and adds nothing to the counts.],
        [A changed diagram, custom figure, or formula is boxed on each side
          on every page where it is drawn. Changed native drawing code and a changed formula
          body are listed as needing review, and the tool does not judge
          them.],
        [A difference in presentation alone, such as a tint, a layout, or a
          column count, is not a change.],
        [Two revisions without a change produce a one-page PDF that says so.],
      ),
      side-effects: (
        [Writes the PDF, and the summary or report when asked, and never over
          an existing file.],
        [Extracts the base revision into a temporary directory, which it
          removes.],
        [Creates the `.render` library copy of a compared layer that has
          none.],
      ),
      verification: [`nix flake check`, which runs
        `scripts/design-review.test.sh`.],
      paths: ("scripts",),
    )

    #unit(
      id: "document-gate",
      title: "Document gate",
      overview: [The `check` app decides whether a layer is well-formed. It
        proves the PDF fresh, checks semantic token coverage, resolves
        cross-artifact references, and checks every unit path and folder
        contract.],
      interface: (
        [`check <layer-root> [repo-root]` exits 0 when clean, 1 on a violation,
          and 2 on an error. `--nested-project <path>` adds an independently
          checked project.],
        [`lint <layer-root>` reports the first guideline as an error. It is
          never part of `check`.],
      ),
      invariants: (
        [A stale generated artifact is reported and never rewritten.],
        [A check that examined nothing does not report a pass.],
        [A unit the projection cannot address fails the gate, although the
          gate never runs the projection.],
        [The report of directories no unit covers never changes the exit
          code.],
      ),
      side-effects: (
        [Refreshes the `.render` library copy of the checked layer and of each
          nested project's layer.],
      ),
      verification: [`nix flake check`],
      paths: ("scripts",),
    )

    The gallery and self-tests separately exercise the tools, including
    rejected inputs. This layer exercises integration; the self-tests prove
    individual contracts.
  ])

  #section(title: "End-to-end walkthrough", lead: "An architecture change becomes a shared reading surface.", body: [
    *Author.* An author inspects the host's code and established intent, then updates
      only the architectural claims affected by the change. Vocabulary has one
      owning glossary. Detailed implementation remains in the host's code.

    *Render.* The render app prepares the selected library and compiles the layer.
      Invalid values or references stop validation. Guidelines are reported;
      they block only when strict mode is requested. A successful render writes
      the aggregate PDF.

    *Project.* The context app queries the same authored layer and emits Markdown.
      For a large layer, an agent first reads the manifest and then requests
      the relevant section subtree with its expected digest.

    *Link.* The units app writes each unit's contract into the folders that
      unit lists. A folder's `AGENTS.md` then names the unit, links its Typst
      source, and prints the command that loads the full unit.

    *Check.* The author inspects both reading forms and runs the gate. A stale PDF
      fails freshness; a broken cross-artifact link fails integrity; a missing
      unit path or a stale folder contract fails the unit checks. Passing
      these checks does not establish that the host implements its claims.

    *Review.* On a pull request, the review app compares the layer with its
      merge base and writes one PDF. A reader opens it, finds each changed
      part with the old design on the left and the new one on the right, and
      judges the change. The review shows a change and accepts nothing.

    *Representation limits.* Semantic diagrams preserve nodes and relationships
    in Markdown. A custom figure with a raw `typst` body becomes a drawing in
    PDF and a code fence in Markdown. Its caption or adjacent prose must state
    its meaning. Evaluated custom figure bodies and embedded
    SVGs cannot currently be projected to Markdown and fail that projection.

    *Reproducibility boundary.* The bundle fixes renderer dependencies and
    excludes system fonts. Compilation uses vendored packages without fetching
    them at render time. Obtaining the Nix inputs and building the bundle is a
    separate provisioning step. A bundle update can change output, so hosts
    must re-render before freshness can pass.

    *Where to investigate.* `lib/designlib.typ` maps the library responsibilities;
    `schema/design-schema.json` declares the vocabulary. `scripts/design-aggregate`
    and `scripts/design-context` own the two reading outputs.
    `scripts/design-units` owns the folder contracts.
    `scripts/design-review` owns the comparison of two revisions.
    `scripts/layer-integrity` owns cross-artifact checks. `flake.nix` assembles
    the bundle and public apps. The gallery and self-tests provide executable
    examples and failure cases.
  ])
]
