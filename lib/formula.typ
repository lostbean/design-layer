// ---- equations and formulas ---------------------------------------------
//
// A formula is mathematical content with the reading aids an architecture
// document needs around it: a name, optional stable target, optional equation
// number, a compact notation key, and a caption explaining why the expression
// matters. Inline mathematics remains ordinary Typst math in prose; this block
// is for an expression the reader should be able to find and cite as a unit.
#import "schema.typ": *
#import "semantic.typ": *
#import "tokens.typ": *
#import "rules.typ": *

#let formula(
  id: none,
  title: none,
  caption: none,
  accent: "violet",
  numbered: false,
  notation: (),
  body,
) = {
  _enum("formula", "accent", accent, TINTS)
  if type(numbered) != bool {
    panic("formula numbered= must be true or false, got " + repr(numbered))
  }
  if id != none and (type(id) != str or id.trim() == "") {
    panic("formula id= must be a non-empty string when supplied")
  }
  if type(notation) != array {
    panic("formula notation= must be an array of (symbol, meaning) pairs")
  }
  for item in notation {
    if type(item) != array or item.len() != 2 {
      panic("formula notation entry " + repr(item)
        + " must be a (symbol, meaning) pair")
    }
  }
  if context-projection {
    let projected = semantic("formula", fields: (
      id: id, title: title, caption: caption, numbered: numbered,
      notation: notation, body: body,
    ))
    return if id == none {
      projected
    } else {
      [#_semantic-target("formula-" + id)#projected]
    }
  }

  let c = TINT-COLOR.at(accent)
  let rendered = block(
    width: 100%,
    breakable: false,
    fill: c.lighten(96%),
    stroke: (top: 1.4pt + c, rest: 0.45pt + c.lighten(55%)),
    radius: 2pt,
    inset: (x: 10pt, y: 8pt),
  )[
    #grid(
      columns: (1fr, auto),
      align: (left, right),
      text(size: RENDERER-META, weight: "bold", tracking: 0.65pt,
           fill: c)[FORMULA],
      if title != none {
        text(size: RENDERER-COMPACT, weight: "semibold", fill: MUTED)[#title]
      },
    )
    #v(8pt)
    #align(center)[
      #set text(size: 10.5pt, fill: INK)
      #math.equation(
        block: true,
        numbering: if numbered { "(1)" } else { none },
        body,
      )
    ]
    #if notation.len() > 0 [
      #v(7pt)
      #line(length: 100%, stroke: 0.4pt + c.lighten(55%))
      #v(5pt)
      #text(size: 6.1pt, weight: "bold", tracking: 0.55pt, fill: FAINT)[NOTATION]
      #v(3pt)
      #table(
        columns: (auto, 1fr),
        column-gutter: 8pt,
        row-gutter: 3pt,
        inset: 0pt,
        stroke: none,
        ..notation.map(item => (
          text(size: RENDERER-COMPACT, weight: "semibold", fill: c)[#item.at(0)],
          text(size: RENDERER-COMPACT, fill: MUTED)[#item.at(1)],
        )).flatten(),
      )
    ]
    #if caption != none [
      #v(7pt)
      #text(size: 7.5pt, fill: MUTED, style: "italic")[#caption]
    ]
  ]

  if id == none {
    rendered
  } else {
    [#metadata(id)#rendered#label("formula-" + id)]
  }
  v(0.55em)
}
