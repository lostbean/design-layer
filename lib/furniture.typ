// ---- inline furniture: lens pills, chips, links, the inline layer -------
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *

#let pill(..names) = {
  let ns = names.pos()
  for n in ns { _enum("lens pill", "lens", n, LENSES) }
  box(baseline: 2pt)[
    #for (i, n) in ns.enumerate() {
      let c = LENS-COLOR.at(n)
      box(inset: (x: 4pt, y: 1.35pt), radius: 6pt,
          fill: c.lighten(84%), stroke: 0.45pt + c.lighten(38%),
          text(size: 6.4pt, fill: c.darken(22%), weight: "bold", n))
      if i < ns.len() - 1 { h(2pt) }
    }
  ]
}

#let chip(body, tone: none) = {
  let c = if tone == none { SURFACE-STRONG } else { tone.lighten(85%) }
  let fg = if tone == none { MUTED } else { tone.darken(24%) }
  box(inset: (x: 4pt, y: 1.5pt), radius: 3pt, fill: c, baseline: 2pt,
      stroke: if tone == none { none } else { 0.5pt + tone.lighten(45%) },
      text(size: 6.5pt, fill: fg, weight: if tone == none { "regular" } else { "bold" },
           body))
}

#let lnk(dest, body) = link(dest, text(fill: TINT-COLOR.at("blue"), body))

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
      link(label(it.dest.slice(1)), text(fill: TINT-COLOR.at("blue"), it.body))
    } else {
      text(fill: TINT-COLOR.at("blue"), it)
    }
  }
  body
}
