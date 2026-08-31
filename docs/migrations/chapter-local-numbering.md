# Chapter-local numbering and grouped contents

## Scope

- Every root or context `design.typ` now renders as a numbered chapter.
- Sections and subsections derive chapter-local numbers such as `1.1`,
  `1.1.1`, and `1.10.1`. The next context restarts its section path under the
  next chapter, such as `2.1`.
- The table of contents marks each chapter boundary and nests sections and
  subsections beneath it. The glossary is a separate unnumbered reference
  chapter.
- Authored titles and their derived anchors do not change. This migration adds
  no author function and requires no `design.typ` or `CONTEXT.typ` rewrite.

## Apply the renderer-only migration

- Update the host repository's pinned design-layer input to a revision carrying
  this migration.
- Use that exact revision to rebuild the projected `.render` library when the
  host commits one. Do not combine a new schema with an older renderer library.
- Regenerate the layer's one `docs/design/design-layer.pdf` through the host's
  pinned render wrapper.

## Review the rendered document

- Confirm the root is chapter 1 and contexts follow in aggregate order.
- Confirm sections and subsections carry their owning chapter number.
- Confirm chapter rows form clear groups in the table of contents, nested rows
  remain readable, and page numbers align at the right edge.
- Confirm the glossary heading carries no chapter number.
- Follow existing section and context links to confirm their destinations did
  not change.

## Verify

- Run the host repository's complete design gate after regenerating the PDF.
- Commit the renderer pin, projected library if the host carries one, and the
  regenerated PDF together. Commit no source rewrite for this migration.
