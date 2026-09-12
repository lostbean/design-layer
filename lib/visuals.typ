// ---- admonitions, cards, stat tiles, tables, embedded figures -----------
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *
#import "furniture.typ": *

#let _clue(kind, title, tint, body) = {
  _enum(kind, "tint", tint, TINTS)
  let c = if tint == none { KIND-COLOR.at(kind) } else { TINT-COLOR.at(tint) }
  block(width: 100%, inset: (x: 8pt, y: 7pt), fill: c.lighten(95%),
    stroke: 0.5pt + c.lighten(50%), radius: 2pt,
    [
      #set par(justify: false)
      #text(size: 6.5pt, fill: c, weight: "bold", tracking: 0.4pt,
            upper(if title != none { title } else { kind }))
      #linebreak() #body
    ])
  v(0.45em)
}
#let info(title: none, tint: none, ..a, body) = _clue("info", title, tint, body)
#let warning(title: none, tint: none, ..a, body) = _clue("warning", title, tint, body)

// ---- cards, stat tiles, tables, figures ---------------------------------
// COLUMN COUNT IS DERIVED FROM CONTENT only when the author leaves `cols`
// absent. An explicit count is part of the layout contract and must not be
// replaced by the automatic fallback because a body is long.
#let _len(c) = {
  if type(c) == str { c.len() }
  else if type(c) != content { 0 }
  else if c.has("text") { c.text.len() }
  else if c.has("children") { c.children.map(_len).sum(default: 0) }
  else if c.has("body") { _len(c.body) }
  else { 0 }
}
#let _cards-columns(cols, longest, count) = {
  if cols == none {
    if longest > 160 { 1 } else { calc.min(count, 2) }
  } else {
    int(cols)
  }
}
#let _card-item(item, body-size) = [
  #set par(justify: false)
  #text(weight: "bold", size: RENDERER-TITLE, item.title) #linebreak()
  #text(size: body-size)[#item.body]
]

#let _cards-item-color(item, fallback) = {
  let item-tint = item.at("tint", default: none)
  if item-tint == none {
    fallback
  } else { TINT-COLOR.at(item-tint) }
}
#let cards(cols: none, tint: none, size: none, items: (), ..a) = {
  _enum("cards", "tint", tint, TINTS)
  _enum("cards", "cols", cols, ("2", "3", "4"))
  _enum("cards", "size", size, ("md", "sm"))
  for it in items {
    _enum("cards item", "tint", it.at("tint", default: none), TINTS)
  }
  let c = if tint == none { luma(180) } else { TINT-COLOR.at(tint) }
  let longest = calc.max(..items.map(it => _len(it.body)), 0)
  let n = _cards-columns(cols, longest, items.len())
  let body-size = if size == "sm" { RENDERER-COMPACT } else { RENDERER-BODY }
  // A table, rather than a grid, gives every cell in one row the height of
  // the tallest cell. The frame therefore closes on one baseline even when a
  // neighbouring card has much less content. The table also retains the grid's
  // two-dimensional placement and can break between rows when a long card
  // reaches a page boundary.
  block(width: 100%)[
    #table(
      columns: (1fr,) * n,
      gutter: 7pt,
      inset: (x: 8pt, y: 8pt),
      fill: (x, y) => if x + y * n >= items.len() {
        none
      } else {
        let color = _cards-item-color(items.at(x + y * n), c)
        color.lighten(96%)
      },
      stroke: (x, y) => if x + y * n >= items.len() {
        none
      } else {
        let color = _cards-item-color(items.at(x + y * n), c)
        (top: 1.2pt + color, rest: 0.4pt + color.lighten(55%))
      },
      align: left + top,
      ..items.map(it => _card-item(it, body-size)),
    )
  ]
  v(0.45em)
}
#let stat-grid(cols: "3", tiles: (), ..a) = {
  // The two surfaces hand the tiles over differently and both are legal: the
  // markdown router collects the nested :::stat-tile blocks into `tiles:`,
  // while a native document passes them positionally. Accepting both matters
  // more than it looks — passing tiles positionally to a tiles:-only signature
  // renders an EMPTY GRID and exits 0, which is a blank page that reports
  // success.
  let ts = if tiles.len() > 0 { tiles } else { a.pos() }
  if ts.len() == 0 {
    _guide("stat-grid.empty",
           "stat-grid() holds at least one tile; an empty grid renders nothing")
    return
  }
  // Replay each tile's deferred guidance from here, a content position.
  for t in ts { _guides(t.at("_guides", default: ())) }
  block(width: 100%, grid(columns: (1fr,) * calc.min(ts.len(), int(cols)),
    gutter: 6pt,
    ..ts.map(t => block(width: 100%, inset: (x: 8pt, y: 8pt), radius: 2pt,
      fill: SURFACE, stroke: 0.45pt + HAIRLINE,
      [
        #text(size: 16pt, weight: "bold", t.at("value", default: ""))
        #linebreak()
        #text(size: 7pt, fill: MUTED, t.at("label", default: ""))
        #if t.at("delta", default: none) != none [
          #linebreak()
          #text(size: 6.8pt, weight: "bold",
                fill: if t.at("dir", default: none) == "up" {
                  TINT-COLOR.at("teal")
                } else { TINT-COLOR.at("rose") },
                t.delta)
        ]
      ]))))
  v(0.45em)
}
#let md-table(ncol, cells) = {
  if type(ncol) != int or ncol < 1 {
    panic("md-table: column count must be a positive integer")
  }
  if type(cells) != array {
    panic("md-table: cells must be an array")
  }
  if cells.len() < ncol {
    panic("md-table: cells must include a header row")
  }
  if calc.rem(cells.len(), ncol) != 0 {
    panic("md-table: cells must form whole rows")
  }
  let last-row = calc.ceil(cells.len() / ncol) - 1
  let header = cells.slice(0, ncol).map(cell => [
    #set text(weight: "semibold")
    #show strong: it => it.body
    #cell
  ])
  let body = cells.slice(ncol)
  let columns = range(ncol).map(column => {
    let lengths = range(column, cells.len(), step: ncol).map(index => repr(cells.at(index)).len())
    let longest = lengths.fold(0, (current, length) => calc.max(current, length))
    calc.min(48, calc.max(8, longest)) * 1fr
  })
  block(width: 100%)[
    #set par(justify: false)
    #table(
      columns: columns,
      fill: (_, y) => if y == 0 { SURFACE-STRONG } else if calc.rem(y, 2) == 0 { SURFACE } else { none },
      stroke: (_, y) => (
        top: none,
        right: none,
        bottom: if y == last-row { none } else if y == 0 {
          0.7pt + MUTED
        } else {
          0.35pt + HAIRLINE
        },
        left: none,
      ),
      inset: (x: 5pt, y: 4pt),
      table.header(..header),
      ..body,
    )
  ]
}
#let code-block(lang, src) = {
  if type(lang) != str or lang.trim() == "" {
    panic("code-block language must be a non-empty string")
  }
  let c = TINT-COLOR.at("slate")
  block(
    width: 100%, breakable: false,
    inset: (x: 8pt, y: 6pt),
    fill: SURFACE,
    stroke: (top: 1.2pt + c, rest: 0.4pt + HAIRLINE),
    radius: 2pt,
  )[
    #grid(
      columns: (1fr, auto),
      text(size: RENDERER-META, fill: c, weight: "bold", tracking: 0.5pt)[CODE],
      text(size: RENDERER-COMPACT, fill: MUTED, font: "DejaVu Sans Mono")[#upper(lang)],
    )
    #v(4pt)
    #raw(src, block: true, lang: lang)
  ]
  v(0.45em)
}
#let embedded-svg(caption: none, file: none, ..a, body) = {
  let c = TINT-COLOR.at("slate")
  block(
    width: 100%, breakable: false,
    inset: (x: 8pt, y: 6pt),
    stroke: (top: 1.2pt + c, rest: 0.4pt + HAIRLINE),
    radius: 2pt, fill: SURFACE,
  )[
    #grid(
      columns: (1fr, auto),
      text(size: RENDERER-META, fill: c, weight: "bold", tracking: 0.5pt)[EXTERNAL SVG],
      text(size: RENDERER-COMPACT, fill: MUTED, font: "DejaVu Sans Mono")[#file],
    )
    #if caption != none [
      #v(4pt)
      #text(size: 7.5pt, fill: MUTED, style: "italic")[#caption]
    ]
  ]
  v(0.45em)
}
