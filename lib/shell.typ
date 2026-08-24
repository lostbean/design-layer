// ---- the document shell and the aggregate shell -------------------------
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *
#import "furniture.typ": *

#let design-doc(eyebrow: none, hero_title: none, lede: none, footer: none, body) = {
  show: _link-rule
  set page(paper: "a4", margin: (x: 2.1cm, y: 2cm),
    footer: context {
      set text(size: 7pt, fill: luma(130))
      grid(columns: (1fr, auto), align: (left, right),
        [#hero_title], [#counter(page).display()])
    })
  set text(size: 9.5pt, font: "Libertinus Serif")
  set par(justify: true, leading: 0.62em)
  show heading: set block(above: 1.3em, below: 0.7em)
  show heading.where(level: 1): set text(size: 15pt)
  show heading.where(level: 2): set text(size: 12pt)
  show heading.where(level: 3): set text(size: 10pt)
  if eyebrow != none {
    text(size: 7.5pt, fill: luma(120), tracking: 0.3pt, upper(eyebrow))
    linebreak()
  }
  if hero_title != none { v(2pt); text(size: 21pt, weight: "bold", hero_title); linebreak() }
  if lede != none { v(3pt); block(width: 100%, text(size: 9pt, fill: luma(95), lede)) }
  v(4pt); line(length: 100%, stroke: 0.6pt + luma(200)); v(10pt)
  body
  if footer != none {
    v(12pt); line(length: 100%, stroke: 0.6pt + luma(200)); v(4pt)
    text(size: 7.5pt, fill: luma(120), footer)
  }
}

// ---- the aggregate shell ------------------------------------------------
// One document over the whole layer: an outline, the contexts as chapters, and
// every glossary gathered into one section. Inside one document a term
// citation is an INTRA-document reference, so the compiler resolves it.
#let aggregate-doc(title: none, subtitle: none, body) = {
  show: _link-rule
  set page(paper: "a4", margin: (x: 2.1cm, y: 2cm),
    footer: context {
      set text(size: 7pt, fill: luma(130))
      grid(columns: (1fr, auto), align: (left, right),
        [#title], [#counter(page).display()])
    })
  set text(size: 9.5pt, font: "Libertinus Serif")
  set par(justify: true, leading: 0.62em)
  set heading(numbering: "1.1")
  show heading: set block(above: 1.3em, below: 0.7em)
  show heading.where(level: 1): set text(size: 16pt)
  show heading.where(level: 2): set text(size: 12pt)
  show heading.where(level: 3): set text(size: 10pt)

  // title page
  v(1fr)
  align(center)[
    #text(size: 28pt, weight: "bold", title)
    #if subtitle != none [ #v(6pt) #text(size: 11pt, fill: luma(110), subtitle) ]
  ]
  v(1fr)
  pagebreak()

  // the table of contents — the navigation the aggregate exists for
  outline(depth: 2, indent: auto)
  pagebreak()

  body
}

// ---- the chapter front page ---------------------------------------------
// Each domain opens on its own page, so moving from one context to the next is
// a visible break rather than a heading in a column of text. The page carries
// the context's accent, which is the same tint that context uses everywhere
// else in the layer — a reader recognises the domain before reading the title.
//
// The heading itself is emitted after this block by the aggregate, so the
// outline and the numbering stay the renderer's, not a second hand-built one.
#let chapter-page(title, lede: none, accent: none, index: (), kind: "context") = {
  pagebreak(weak: true)
  let hue = if accent != none and accent in TINTS { TINT-COLOR.at(accent) } else { luma(90) }
  v(3.2cm)
  block(width: 100%, stroke: (left: 3pt + hue), inset: (left: 14pt, y: 2pt))[
    #text(size: 8pt, fill: hue, weight: "bold", tracking: 1.2pt,
          upper(kind))
    #v(5pt)
    #text(size: 24pt, weight: "bold", title)
    #if lede != none [
      #v(7pt)
      #text(size: 10pt, fill: luma(105), style: "italic", lede)
    ]
  ]
  // what this chapter contains — the reader sees the shape before the prose.
  if index.len() > 0 {
    v(14pt)
    block(inset: (left: 17pt))[
      #text(size: 7.5pt, fill: luma(130), weight: "bold", tracking: 0.8pt,
            upper("in this chapter"))
      #v(5pt)
      #for s in index [
        #text(size: 9pt, fill: luma(70))[#s] #linebreak()
      ]
    ]
  }
  v(1fr)
}

// the context that OWNS a glossary term, shown beside the definition so a
// reader sees ownership without leaving the page.
#let context-owner(name) = {
  block(inset: (bottom: 3pt), chip("owned by " + name))
}
