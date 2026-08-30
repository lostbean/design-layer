// gallery.typ — the live demonstration of the authoring surface.
//
// This is a DRIFT TRIPWIRE rather than documentation: widget-coverage asserts
// that every function the library projects for authoring appears here, and
// that this file renders. A function with no gallery coverage is not covered
// by the drift check, so a regression in it ships unnoticed.
//
// It is rendered on its own rather than folded into an aggregate: it is a
// reference document an adopter browses, not a context of anyone's design
// layer.
//
// The library is imported from the projection made beside this file at check
// time, so the gallery always demonstrates the CURRENT projection rather than
// a copy that could drift.
#import ".render/designlib.typ": *

#show: design-doc.with(
  eyebrow: [Reference],
  hero_title: [The block gallery],
  lede: [Every function a design.typ calls, rendered once, so a change in any
    one of them is visible in a diff of this document.],
  footer: [Generated from the projected library — never hand-styled.],
)

#section(
  title: "How this file is read",
  lead: "A section is the unit: a muted lead, one visual, then the body.",
  visual: how-to-read(),
  body: [
    A design document calls these functions directly. The author writes words
    and structure; every visual decision lives in the library, so nothing here
    is styled at the call site.

    #points(
      [A bullet holds one property.],
      [Three sentences is the budget. A fourth is a new bullet.],
      [Plain prose beside bullets is legal, and better when the sense is a
        chain of causes.],
    )
  ],
)

#section(
  title: "The foundation statements",
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
  title: "The diagram",
  lead: "Nodes and edges are data; the solver lays out this graph.",
  visual: diagram(
    altitude: "L2",
    title: "the authoring surface over one library",
    caption: [A design document calls the library directly, so there is no
      conversion step between what was written and what is checked.],
    nodes: (
      (id: "typ", label: "design.typ", sub: "authored", tint: "teal"),
      (id: "schema", label: "design-schema", sub: "declared", tint: "violet"),
      (id: "lib", label: "designlib", sub: "projected", tint: "blue"),
      (id: "pdf", label: "one document", external: true),
    ),
    edges: (
      ("typ", "lib", "called directly"),
      ("schema", "lib", "projects"),
      ("lib", "pdf", "renders", "dashed"),
    ),
  ),
  body: [
    The altitude is a required argument, so a drawing always says which zoom
    level it is at. A node may declare a tint from the fixed accent vocabulary;
    a node without one uses the diagram accent.
  ],
)

#section(
  title: "The positioned diagram",
  lead: "Coordinates carry this drawing's reading order.",
  visual: diagram-native(
    altitude: "L3",
    title: "the explicit left-to-right path",
    nodes: (
      (id: "author", pos: (0, 0), label: [author]),
      (id: "review", pos: (1, 0), label: [review]),
      (id: "publish", pos: (2, 0), label: [publish]),
    ),
    edges: (
      ("author", "review", "submits"),
      ("review", "publish", "accepts"),
    ),
  ),
  body: [
    Use the positioned carrier only when an authored grid is part of the
    meaning or precise visual control is necessary.
  ],
)

#section(
  title: "Units and their answers",
  lead: "A component answers five questions; absent answers stay absent.",
  body: [
    #components(
      component(
        name: "projector",
        lens: "composition",
        mission: "Turns the declared schema into the library.",
        answers: answers-data(
          responsibility: [One schema in, one library out.],
          failure: [Refuses a schema missing a required vocabulary.],
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
      interface: [Three commands: project, aggregate, check.],
      interactions: [Reads the schema; runs the renderer.],
      invariants: [A stale rendered document fails the check.],
      failure: [Exit 1 on a violation, exit 2 on a missing tool.],
    )
  ],
)

#section(
  title: "Magnitudes and breadth",
  lead: "A tile states a fact; a coverage row states a decision.",
  body: [
    #stat-grid(
      stat-tile(value: "2.4M", label: "words rendered", delta: "+12%", dir: "up"),
      stat-tile(value: "93", label: "gate assertions"),
      stat-tile(value: "3", label: "silent failures caught", delta: "-2", dir: "down"),
    )

    #subsection(title: "Coverage")[
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
  title: "Cross references",
  lead: "A reference is a call, so a rename is a compile error.",
  body: [
    A context is named with #ctx("design-layer"), a term with
    #term("term-pending-ledger"), and a judgement axis with
    #lens-pill("robustness"). A decision is cited by number — #adr(65) — and
    the number is the whole citation: the gate resolves it against the files on
    disk, so a citation of a decision that does not exist is caught at the
    citing line, where a hand-typed path would rot silently on a rename.

    Each of those is a #chip[chip] — the one inline primitive they share,
    tinted by what it names. Written bare it carries no tint, which is the
    honest rendering of a token that names no declared vocabulary.

    A judgement axis also renders as a standalone #pill("robustness") pill, and
    a combination of two sorts itself into the declared enum order:
    #pill("modeling", "composition"). An external destination is written as a
    #lnk("https://typst.app", "link") that carries its own tone.
  ],
)

#section(
  title: "The entity census",
  lead: "An entity states what it is made of and how it sits against others.",
  body: [
    #entity(
      title: "Design layer",
      kind: "aggregate",
      owner: "the author",
      lifecycle: "stateful",
      domain: "documentation",
    )[
      #attribute(provenance: "authored")[
        The notation the layer is written in.
      ]
      #attribute(provenance: "derived")[
        The rendered document, produced by the renderer and never hand-edited.
      ]
      #relates(cardinality: "1 : 0..n")[
        A layer holds many contexts, and a context belongs to exactly one layer.
      ]
    ]

    The two groups label themselves from the run of clauses, so the authored
    source names neither heading.
  ],
)

#section(
  title: "Behavior rules",
  lead: "A rule is a context, one event, and the outcomes a reader can observe.",
  body: [
    #behavior(
      title: "A stale rendered document fails the check",
      area: "Mechanical repository commands",
      level: "interface",
    )[
      #given[The layer's sources have changed since the document was rendered.]
      #when[The gate runs its freshness check.]
      #then[The check reports the document as stale and exits non-zero.]
      #then[No rendered artifact is written, so nothing reads as having passed.]
    ]
  ],
)

#section(
  title: "Admonitions, cards, and tables",
  lead: "Each shape carries one job, and the tint says which.",
  body: [
    #info(title: "What a gate proves")[
      A freshness check proves render-matches-render. It never proves
      render-matches-source, and stating the limit is what keeps the claim
      honest.
    ]

    #warning(title: "A degrading check", tint: "amber")[
      A check whose helper is missing can report SKIP and still exit 0. That is
      worse than no check, because it reports success.
    ]

    #cards(
      cols: "2",
      tint: "blue",
      items: (
        (title: "Invariant", body: [A rule whose violation makes the model
          wrong. It panics.]),
        (title: "Guideline", body: [A rule of style. It is silent unless the
          author asks for it.]),
      ),
    )

    #md-table(
      3,
      (
        [*Phase*], [*Reads*], [*Decides*],
        [assert], [the authored source], [document-level contracts],
        [compile], [the generated typst], [per-block contracts],
        [freshness], [the committed document], [whether it is current],
      ),
    )

    #code-block("bash", "nix run .#check -- docs/design .")
  ],
)

#section(
  title: "Plots and figures",
  lead: "A chart states a magnitude; a figure carries renderer markup.",
  body: [
    #chart(
      kind: "column",
      title: "rules by kind",
      accent: "blue",
      points: (("invariant", 31), ("guideline", 12), ("fence", 7)),
      caption: [A column chart reads its categories across the bottom.],
    )

    #chart(
      kind: "bar",
      title: "coverage rows by status",
      accent: "teal",
      points: (("captured", 24), ("standard", 5), ("out-of-scope", 2)),
    )

    #chart(
      kind: "line",
      title: "decisions recorded, by version",
      accent: "violet",
      unit: "ADRs",
      points: (("v1", 12), ("v2", 34), ("v3", 71)),
    )

    #chart(
      kind: "pie",
      title: "where the lines live",
      accent: "amber",
      points: (("library", 2240), ("scripts", 2621), ("schema", 900)),
    )

    #figure-block(
      caption: [A figure names the vendored packages it uses, so a render stays
        offline-reproducible.],
      uses: ("cetz",),
    )[
      #text(size: 8pt, fill: luma(110))[a drawing would sit here]
    ]

    #embedded-svg(caption: [An external drawing], file: "diagram.svg")[]
  ],
)

#section(
  title: "The state machine",
  lead: "A machine declares states and transitions, never positions.",
  body: [
    #state-machine(
      title: "an issue, from intake to its two terminals",
      accent: "amber",
      initial: "needs_triage",
      accepting: ("done", "wontfix"),
      states: (
        "needs_triage", "needs_info", "ready_for_agent",
        "in_progress", "done", "wontfix",
      ),
      transitions: (
        ("needs_triage", "needs_info", "request-info"),
        ("needs_info", "needs_triage", "info-received"),
        ("needs_triage", "ready_for_agent", "brief"),
        ("ready_for_agent", "in_progress", "start"),
        ("in_progress", "done", "deliver"),
        ("in_progress", "wontfix", "abandon"),
        ("needs_triage", "wontfix", "reject"),
      ),
      caption: [The carrier solves the layout, draws the initial marker, and
        rings each accepting state.],
    )
  ],
)

#section(
  title: "The sequence",
  lead: "A sequence is ordered by time, and says when a party is active.",
  body: [
    #sequence(
      title: "a work order, from dispatch to accepted change",
      accent: "violet",
      participants: (
        (id: "coder", label: "coder", shape: "control"),
        (id: "wo", label: "work-order", shape: "participant"),
        (id: "gate", label: "the gate", shape: "boundary"),
        (id: "repo", label: "repository", shape: "database"),
      ),
      steps: (
        seq-msg("coder", "wo", "dispatch one chunk", activate: true),
        seq-note("wo", [the brief is durable], side: "right"),
        seq-loop("until the gate is green", (
          seq-msg("wo", "repo", "write the change"),
          seq-msg("wo", "gate", "run the gate"),
          seq-alt(
            "the gate passes",
            (seq-msg("gate", "wo", "green", dashed: true),),
            otherwise: (
              seq-msg("gate", "wo", "violation", dashed: true),
              seq-msg("wo", "repo", "repair"),
            ),
          ),
        )),
        seq-msg("wo", "coder", "deliver", dashed: true, deactivate: true),
        seq-opt("the delivery is bounced", (
          seq-msg("coder", "wo", "re-dispatch with findings"),
        )),
      ),
      caption: [Activation, branch, repetition, and an optional block —
        the constructs a node-and-edge drawing cannot state.],
    )
  ],
)

#section(
  title: "End-to-end walkthrough",
  lead: "A prose-only section is legal, and this one demonstrates it.",
  body: [
    An author writes a `design.typ` beside its `CONTEXT.typ`. Each file is a
    module exporting a title and a body, so nothing in it decides page size,
    numbering, or colour.

    The aggregate discovers each context, imports it as a module, and places
    its body under a chapter heading. The result is one document with one table
    of contents, and the gate proves it is current by rendering it again and
    comparing the bytes.

    A section that reaches for narrative rather than a diagram is not a
    failure of the document. The spine mandates a walkthrough, and a
    walkthrough is a sequence carried in sentences, so the `visual` argument
    is optional and this section supplies none.
  ],
)

#pending-ledger(
  pending-entry(
    title: "The context map is still authored by hand",
    kind: "build",
    since: "2026-08-23",
    adr: [#adr(65)],
  )[
    The context map and the coverage map are markdown files kept beside the
    layer they index, so each can disagree with what it indexes. Generating
    them from the Typst sources would remove the disagreement rather than
    check for it.
  ],
  pending-entry(
    title: "The mechanism fence catches only a denylist",
    kind: "verify",
    since: "2026-08-23",
  )[
    A behavior clause must state an observable outcome rather than the
    mechanism producing it. The check matches a list of implementation-shaped
    words and a few id patterns, so it is labelled partial: a mechanism
    described in ordinary words passes it.
  ],
)
