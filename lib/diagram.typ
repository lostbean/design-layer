// ---- diagrams, charts, and the one block carrying renderer markup -------
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *
#import "furniture.typ": *
#import "packages.typ": *

// A mermaid fence is CONVERTED to its carrier by the router and arrives here
// already in the carrier's own language. Colour comes from the projected token
// table, never from styling inside the diagram.
#let diagram(src, accent: none, caption: none) = {
  _enum("diagram", "accent", accent, TINTS)
  let c = if accent == none { TINT-COLOR.at("teal") } else { TINT-COLOR.at(accent) }
  let q = str.from-unicode(34)
  let f = "fontname=" + q + "Libertinus Serif" + q
  let hx(x) = q + x.to-hex() + q
  let preamble = (
    "  graph [" + f + ", fontsize=10];" + "
"
      + "  node [shape=box, style=" + q + "rounded,filled" + q + ", " + f
      + ", fontsize=9, color=" + hx(c) + ", fillcolor=" + hx(c.lighten(90%))
      + ", penwidth=1.0];" + "
"
      + "  edge [" + f + ", fontsize=7.5, color=" + q + "#555555" + q + "];" + "
"
  )
  // inject the projected look right after the graph header
  let body = if src.contains("{") {
    let i = src.position("{")
    src.slice(0, i + 1) + "
" + preamble + src.slice(i + 1)
  } else { src }
  // SIZE THE DIAGRAM BY ITS OWN SHAPE, capped — never stretched to fill.
  // Forcing every graph to a fixed fraction of the column made size meaningless:
  // a two-node graph whose natural width is 152pt was blown up to ~440pt, while
  // a twelve-node graph was pushed to a full page. The reader then reads size as
  // importance, which it is not.
  //
  // So the diagram draws at its NATURAL size and is scaled down only when it
  // would overflow. The ceiling is the column; the floor keeps a very small
  // graph from looking like a typo. Between them the drawing keeps its own
  // proportions, so two diagrams of similar complexity come out similar.
  layout(size => {
    let nat = measure(dot-render(body))
    // the ceiling keeps a big graph inside the column; the floor stops a
    // two-node graph from rendering so small it reads as an error.
    let hi = size.width * 0.92
    let lo = size.width * 0.34
    let w = if nat.width <= 0pt { hi } else {
      calc.min(calc.max(nat.width, lo), hi)
    }
    // HEIGHT IS THE SECOND CEILING, and the one width alone misses. A tall
    // rankdir=TD graph can be narrow and still overflow the page: a twelve-node
    // chain measures 134pt wide by 764pt tall against a 723pt page body. Scale
    // the width down by the same ratio so the drawing keeps its proportions
    // rather than being squashed.
    let hcap = size.height * 0.82
    let scaled = if nat.height > 0pt and nat.width > 0pt {
      let drawn_h = nat.height * (w / nat.width)
      if drawn_h > hcap { w * (hcap / drawn_h) } else { w }
    } else { w }
    align(center, dot-render(body, width: scaled))
  })
  if caption != none {
    v(3pt); align(center, text(size: 7.5pt, fill: luma(110), caption))
  }
  v(0.45em)
}

// ---- figure: the ONE block that carries renderer markup -------------------
// Named at both ends: a distinct block kind in the source, and a visibly
// distinct frame in the rendered document, so nobody mistakes a figure for a
// validated diagram. Its `uses` list is restricted to the VENDORED packages,
// which is what keeps a design layer offline-reproducible.
#let figure-block(caption: none, uses: (), ..a, body) = {
  _need("figure", "caption", caption)
  // An empty `uses` is guidance — the figure still draws, and the list is
  // documentation of what it draws with. A package OUTSIDE the vendored set
  // stays fail-closed: it is the rule that keeps a layer reproducible offline,
  // and rendering past it would produce a document that builds here and
  // nowhere else.
  if uses.len() == 0 {
    _guide("figure.uses",
           "figure names no packages in a uses= list — the list is expected to "
           + "name what the figure draws with (allowed: " + VENDORED.join(", ")
           + ")")
  }
  for u in uses {
    if not VENDORED.contains(u) {
      _fail("figure", "uses " + repr(u) + ", which the framework does not "
            + "vendor (allowed: " + VENDORED.join(", ") + ")")
    }
  }
  block(width: 100%, inset: 8pt, radius: 3pt,
        stroke: (paint: luma(150), thickness: 0.6pt, dash: "dashed"),
    [
      #text(size: 6.5pt, fill: luma(110), weight: "bold", tracking: 0.4pt,
            "NATIVE FIGURE · " + uses.join(", "))
      #v(4pt)
      #align(center, body)
      #v(4pt)
      #text(size: 7.5pt, fill: luma(110), caption)
    ])
  v(0.45em)
}
