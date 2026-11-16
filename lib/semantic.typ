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
