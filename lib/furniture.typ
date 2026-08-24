// ---- inline furniture: lens pills, chips, links, the inline layer -------
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *

#let pill(..names) = {
  let ns = names.pos()
  for n in ns { _enum("lens pill", "lens", n, LENSES) }
  let cs = ns.map(n => LENS-COLOR.at(n))
  box(inset: (x: 4pt, y: 1.5pt), radius: 6pt, baseline: 2pt,
      fill: if cs.len() == 1 { cs.first() }
            else { gradient.linear(..cs).sharp(cs.len()) },
      text(size: 6.5pt, fill: white, weight: "bold", ns.join("+")))
}

#let chip(body, tone: none) = {
  let c = if tone == none { luma(233) } else { tone.lighten(82%) }
  let fg = if tone == none { luma(70) } else { tone.darken(25%) }
  box(inset: (x: 4pt, y: 1.5pt), radius: 3pt, fill: c, baseline: 2pt,
      stroke: if tone == none { none } else { 0.5pt + tone.lighten(45%) },
      text(size: 6.5pt, fill: fg, weight: if tone == none { "regular" } else { "bold" },
           body))
}

#let lnk(dest, body) = link(dest, text(fill: rgb("#0369a1"), body))

// ---- the inline layer ----------------------------------------------------
// Prose runs are parsed by cmarker rather than by regex in the router. SCOPE
// carries the framework's own calls into the evaluated paragraph — only the lens
// pill and an ADR anchor need it, because everything else stays markdown.
#let SCOPE = (pill: pill, lnk: lnk)

// The `@label` link rule. A #show at module scope does not reach the importing
// document, so each document shell applies it — that is what turns a resolved
// `@name` destination into a real internal jump rather than an external URI.
#let _link-rule(body) = {
  show link: it => {
    if type(it.dest) == str and it.dest.starts-with("@") {
      link(label(it.dest.slice(1)), text(fill: rgb("#0369a1"), it.body))
    } else {
      text(fill: rgb("#0369a1"), it)
    }
  }
  body
}

