#let terms = (
  (
    slug: "term-design-unit",
    title: [Design unit],
    body: [One part of a design, stated in a fixed shape: an overview, an
      interface, invariants, side effects, a verification, and the code paths
      that realize it. Units nest, and the nesting is the design's hierarchy.],
  ),
  (
    slug: "term-folder-contract",
    title: [Folder contract],
    body: [The generated region of a directory's `AGENTS.md` that carries the
      contract of every #term("term-design-unit") listing that directory.],
  ),
  (
    slug: "term-guideline",
    title: [Guideline],
    body: [A structural or style expectation that is reported during ordinary
      rendering. Strict mode makes a guideline violation an error.],
  ),
  (
    slug: "term-invariant",
    title: [Invariant],
    body: [A rule whose violation makes the document model invalid. Its
      validation failure prevents a successful check.],
  ),
  (
    slug: "term-semantic-metadata",
    title: [Semantic metadata],
    body: [Structured content emitted by the authoring functions in projection
      mode. It carries document meaning independently of visual layout.],
  ),
)
