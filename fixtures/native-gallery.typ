// native-gallery.typ — the live demonstration of the NATIVE authoring surface.
//
// This is the Typst-authoring counterpart of widget-gallery.md, and it is a
// DRIFT TRIPWIRE rather than documentation: widget-coverage asserts that every
// function the library projects for native authoring appears here, and that
// this file renders. A function with no gallery coverage is not covered by the
// drift check, so a regression in it ships unnoticed.
//
// It is rendered on its own rather than folded into an aggregate, exactly as
// the markdown gallery is: it is a reference document an adopter browses, not
// a context of anyone's design layer.
//
// The library is imported from the projection made beside this file at check
// time, so the gallery always demonstrates the CURRENT projection rather than
// a copy that could drift.
#import ".render/designlib.typ": *

#show: design-doc.with(
  eyebrow: [Reference],
  hero_title: [The native block gallery],
  lede: [Every function a design.typ calls, rendered once, so a change in any
    one of them is visible in a diff of this document.],
  footer: [Generated from the projected library — never hand-styled.],
)

#section(
  title: "01 How this file is read",
  lead: "A section is the unit: a muted lead, one visual, then the body.",
  visual: how-to-read(),
  body: [
    A design document authored in Typst calls these functions directly. The
    author writes words and structure; every visual decision lives in the
    library, so nothing here is styled at the call site.

    #points(
      [A bullet holds one property.],
      [Three sentences is the budget. A fourth is a new bullet.],
      [Plain prose beside bullets is legal, and better when the sense is a
        chain of causes.],
    )
  ],
)

#section(
  title: "02 The foundation statements",
  lead: "Four kinds share one anatomy, so a reader learns the shape once.",
  body: [
    #goal(title: "Author content, never styling", lens: "composition")[
      The authored file carries words and structure. A reviewer reading a diff
      reads the claim, not the presentation.
    ]

    #no-goal(title: "A general document system")[
      This renders design layers. A different kind of document is a different
      tool's problem.
    ]

    #principle(title: "One name per concept", lens: ("modeling", "composition"))[
      A block kind and the function rendering it carry the same name, so there
      is nothing to translate and nothing to look up.
    ]

    #invariant(
      title: "Every diagram edge names a declared node",
      enforcement: "mechanism",
    )[
      The library checks each endpoint against the declared node ids, so an
      edge to nowhere stops the compile instead of rendering a missing line.
    ]

    #notes(title: "On enforcement labels")[
      The `enforcement` argument is required. A convention labelled honestly
      beats a mechanism claimed falsely, and an omitted label claims nothing
      while looking like a claim.
    ]
  ],
)

#section(
  title: "03 The diagram",
  lead: "Nodes and edges are data; the library lays them out.",
  visual: diagram-native(
    altitude: "L2",
    title: "the two authoring surfaces over one library",
    caption: [Both notations reach the same projected library, so a rule
      stated once binds either way.],
    nodes: (
      (id: "md", pos: (0, 0), label: [design.md], sub: [markdown]),
      (id: "typ", pos: (0, 1), label: [design.typ], sub: [native]),
      (id: "lib", pos: (1, 0.5), label: [designlib], sub: [projected]),
      (id: "pdf", pos: (2, 0.5), label: [one document], external: true),
    ),
    edges: (
      ("md", "lib", "converted"),
      ("typ", "lib", "called directly"),
      ("lib", "pdf", "renders", "dashed"),
    ),
  ),
  body: [
    The altitude is a required argument, so a drawing always says which zoom
    level it is at, and its band is tinted to match.
  ],
)

#section(
  title: "04 Units and their answers",
  lead: "A component answers five questions; absent answers stay absent.",
  body: [
    #components(
      component(
        name: "router",
        lens: "composition",
        mission: "Turns authored markdown into library calls.",
        answers: answers-data(
          responsibility: [One notation in, one call tree out.],
          failure: [Refuses an unknown block kind by name.],
        ),
      ),
      component(
        name: "library",
        lens: "invariants",
        mission: "Holds every block contract as a signature.",
        answers: answers-data(
          responsibility: [Validate one block, then render it.],
          invariants: [An enum value outside its declared set panics.],
        ),
      ),
      component(
        name: "aggregate",
        lens: "state",
        mission: "Assembles the contexts into one document.",
      ),
    )

    #answers(
      title: "The gate",
      responsibility: [Decide pass or fail on a whole layer.],
      interface: [Three commands: render, aggregate, check.],
      interactions: [Reads the schema; runs the renderer.],
      invariants: [A stale rendered document fails the check.],
      failure: [Exit 1 on a violation, exit 2 on a missing tool.],
    )
  ],
)

#section(
  title: "05 Magnitudes and breadth",
  lead: "A tile states a fact; a coverage row states a decision.",
  body: [
    #stat-grid(
      stat-tile(value: "2.4M", label: "words rendered", delta: "+12%", dir: "up"),
      stat-tile(value: "93", label: "gate assertions"),
      stat-tile(value: "3", label: "silent failures caught", delta: "-2", dir: "down"),
    )

    #subsection(title: "05.1 Coverage")[
      Every row carries a status, and a row that is not `captured` states why,
      so an absence is a recorded decision rather than an oversight.

      #coverage(
        ("scripts/design-aggregate", "captured", "Rendered by this document."),
        ("flake.nix", "standard", "Conventional Nix packaging."),
        ("LICENSE", "out-of-scope", "Not a designed subsystem."),
      )
    ]
  ],
)

#section(
  title: "06 Cross references",
  lead: "A reference is a call, so a rename is a compile error.",
  body: [
    A context is named with #ctx("design-layer"), a term with
    #term("term-pending-ledger"), and a judgement axis with
    #lens-pill("robustness"). A decision is cited by number: the ADR call
    resolves against the files on disk, so a citation of a decision that does
    not exist is caught at this line.

    Each of those is a #chip[chip] — the one inline primitive they share,
    tinted by what it names. Written bare it carries no tint, which is the
    honest rendering of a token that names no declared vocabulary.
  ],
)

#section(
  title: "07 End-to-end walkthrough",
  lead: "A prose-only section is legal, and this one demonstrates it.",
  body: [
    An author writes a `design.typ` beside its `CONTEXT.typ`. Each file is a
    module exporting a title and a body, so nothing in it decides page size,
    numbering, or colour.

    The aggregate discovers the layer's mode from the files present, imports
    each context as a module, and places its body under a chapter heading. The
    result is one document with one table of contents, and the gate proves it
    is current by rendering it again and comparing the bytes.

    A section that reaches for narrative rather than a diagram is not a
    failure of the document. The spine mandates a walkthrough, and a
    walkthrough is a sequence carried in sentences, so the `visual` argument
    is optional and this section supplies none.
  ],
)

#pending-ledger(
  pending-entry(
    title: "Foundation order is unenforced in native mode",
    kind: "verify",
    since: "2026-08-23",
  )[
    The markdown path re-parses the authored file to assert the foundation's
    order. That parser reads markdown, so the native path does not run it; the
    cross-block ordering rule is not yet checked here.
  ],
  pending-entry(
    title: "A native context map",
    kind: "build",
    since: "2026-08-23",
    adr: [ADR-0065],
  )[
    The context map and coverage map are still authored as markdown beside a
    Typst layer. Generating them from the Typst sources would stop the two
    indexes disagreeing with what they index.
  ],
)
