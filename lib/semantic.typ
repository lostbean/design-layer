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
