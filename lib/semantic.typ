// The semantic query seam used by the ephemeral agent-context projection.
// Metadata is invisible in the rendered document and is read by `typst query`.
// Values may contain Typst content, so the query returns the renderer's own
// structured content tree instead of asking a second parser to read source.
#let context-projection = sys.inputs.at("context", default: "0") in ("1", "true", "yes")

#let semantic(kind, fields: (:)) = if context-projection {
  [#metadata((kind: kind, ..fields)) <design-semantic>]
} else {
  none
}

#let semantic-result(kind, visual, fields: (:)) = if context-projection {
  semantic(kind, fields: fields)
} else {
  visual
}

// THE REVIEW PLACES. With the compile input `review-places=1`, each part of
// the document and each diagram, custom figure, and formula records the page
// and position where it is drawn. The design review reads the records with
// `typst query` and ties each change to its place. A mark is metadata inside
// `context`: it has no size, draws nothing, and moves nothing. Without the
// input a mark is `none`, so an ordinary render holds no trace of it.
#let review-places = sys.inputs.at("review-places", default: "0") == "1"

// The start of a part: a document, a section, a subsection, a unit, a pending
// ledger, or the glossary. It stands directly before the part's heading. A
// mark names a unit or a document by its id and carries no title: the review
// matches marks to records by their order, so a title's markup cannot make
// the two disagree.
#let _review-place(kind, id: none, edge: "start", ..fields) = if review-places {
  context {
    let at = here().position()
    [#metadata((kind: kind, id: id, edge: edge,
      page: at.page, x: at.x.pt(), y: at.y.pt(), ..fields.named()))<design-review-place>]
  }
}

// The two corners of a block, marked from inside it: the first as the block's
// first child and the second as its last. A block that breaks across pages
// then reports its end on the page where it ends. `inset` is the block's own
// inset, so the corners are the corners of what the reader sees.
#let _review-corner(kind, id: none, edge: "start", inset: (x: 0pt, y: 0pt)) = if review-places {
  if edge == "start" {
    place(top + left, dx: -inset.x, dy: -inset.y, _review-place(kind, id: id))
  } else {
    place(bottom + right, dx: inset.x, dy: inset.y, _review-place(kind, id: id, edge: "end"))
  }
}

// A semantic projection still participates in Typst's label registry so a
// source reference is validated before it becomes a Markdown link. The empty
// block is query-visible but has no authored content to project.
#let _semantic-target(name) = [#block(width: 0pt)[]#label(name)]

// A LIBRARY INLINE VISUAL, MARKED AS ONE. A term citation, a context
// reference, an ADR citation and a lens pill are each one inline call, and
// outside the projection each draws a chip — a `box`, or a `context` that
// resolves the chip's text. A `unit` field is prose, and the unit refuses any
// content the Markdown projection cannot express; a box or a context an author
// wrote is such content, and a citation is not, because the projection reads a
// citation from its semantic node. The two are the same element on the page,
// so the library brackets its own inline visuals between these two marks and
// the unit reads past whatever stands between them. A mark is `metadata`: it
// has no size, draws nothing, and carries no label a query selects.
#let _INLINE-OPEN = (design-inline: "open")
#let _INLINE-CLOSE = (design-inline: "close")
#let _inline-visual(visual) = [#metadata(_INLINE-OPEN)#visual#metadata(_INLINE-CLOSE)]
