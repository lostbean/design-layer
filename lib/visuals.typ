// ---- admonitions, cards, stat tiles, tables, embedded figures -----------
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *
#import "furniture.typ": *

#let _clue(kind, title, tint, body) = {
  _enum(kind, "tint", tint, TINTS)
  let c = if tint == none { KIND-COLOR.at(kind) } else { TINT-COLOR.at(tint) }
  block(width: 100%, inset: 7pt, fill: c.lighten(93%),
        stroke: (left: 2.5pt + c), radius: (right: 2pt),
    [
      #text(size: 6.5pt, fill: c, weight: "bold", tracking: 0.4pt,
            upper(if title != none { title } else { kind }))
      #linebreak() #body
    ])
  v(0.45em)
}
#let info(title: none, tint: none, ..a, body) = _clue("info", title, tint, body)
#let warning(title: none, tint: none, ..a, body) = _clue("warning", title, tint, body)

// ---- cards, stat tiles, tables, figures ---------------------------------
// COLUMN COUNT IS DERIVED FROM CONTENT: a card carrying a paragraph of prose
// reads badly in a narrow column, so a card set whose bodies are long stacks
// in one column and reads as a list.
#let _len(c) = {
  if type(c) == str { c.len() }
  else if type(c) != content { 0 }
  else if c.has("text") { c.text.len() }
  else if c.has("children") { c.children.map(_len).sum(default: 0) }
  else if c.has("body") { _len(c.body) }
  else { 0 }
}
#let cards(cols: "2", tint: none, size: none, items: (), ..a) = {
  _enum("cards", "tint", tint, TINTS)
  let c = if tint == none { luma(180) } else { TINT-COLOR.at(tint) }
  let longest = calc.max(..items.map(it => _len(it.body)), 0)
  let n = if longest > 160 { 1 } else { int(cols) }
  block(width: 100%, grid(columns: (1fr,) * n, gutter: 7pt, row-gutter: 6pt,
    ..items.map(it => block(width: 100%, inset: 8pt, radius: 3pt,
      fill: c.lighten(96%), stroke: 0.6pt + c.lighten(35%),
      [#text(weight: "bold", size: 9.5pt, it.title) #linebreak() #it.body]))))
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
    ..ts.map(t => block(width: 100%, inset: 7pt, radius: 3pt, fill: luma(246),
      [
        #text(size: 16pt, weight: "bold", t.at("value", default: ""))
        #linebreak()
        #text(size: 7pt, fill: luma(110), t.at("label", default: ""))
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
#let md-table(ncol, cells) = block(width: 100%, table(
  columns: ncol, stroke: 0.4pt + luma(215), inset: 5pt,
  fill: (_, y) => if y == 0 { luma(243) }, ..cells))
#let code-block(lang, src) = raw(src, block: true, lang: lang)
#let embedded-svg(caption: none, file: none, ..a, body) = block(
  width: 100%, inset: 6pt, stroke: 0.5pt + luma(200), radius: 3pt,
  text(size: 7.5pt, fill: luma(120), "figure: " + str(file)))
