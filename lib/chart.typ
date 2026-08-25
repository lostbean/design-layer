// ---- the chart, drawn by a plotting carrier ------------------------------
//
// WHY A CHART IS ITS OWN BLOCK. A design layer states magnitudes — how many
// rows a coverage table carries, how long each stage of a pipeline takes, how
// a budget divides. A number in prose is precise and gives no sense of
// proportion; a table of numbers gives proportion only to a reader willing to
// do arithmetic. A plot gives it directly, which is the whole reason to draw
// one.
//
// This block used to render the AUTHORED TABLE inside a grey box and call it a
// chart. That was honest about having no carrier, and useless as a drawing: the
// reader saw the same numbers they would have read in prose, framed. A carrier
// is vendored, so the block now plots.
//
// NO ALTITUDE. A chart has no zoom level; it has axes.
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *
#import "packages.typ": *
#import "native.typ": _drawing-frame, _req-enum

#let CHART-TYPES = ("bar", "column", "line", "pie")

// A chart.
//
//   kind   — bar (horizontal), column (vertical), line, or pie.
//   points — ordered (label, value) pairs. The order is the reading order;
//            a chart never sorts on the author's behalf, because the order
//            a design states its categories in is itself information.
#let chart(
  kind: none, title: none, caption: none, accent: "blue",
  points: (), unit: none,
) = {
  _req-enum("chart type", kind, CHART-TYPES)
  _req-enum("accent", accent, TINTS)

  if points.len() == 0 {
    _guide("chart.points",
           "a chart is expected to plot at least one point. An empty chart " +
           "renders blank axes, which reads as a drawing that failed rather " +
           "than as the absence of one.")
  }

  // A value the carrier cannot plot is a hard failure rather than a guideline:
  // a non-number has no position on an axis, so the alternative to failing is
  // inventing one.
  for p in points {
    let v = p.at(1)
    if type(v) != int and type(v) != float {
      panic("chart point " + repr(p.at(0)) + " carries " + repr(v) +
            ", which is not a number. Every plotted value must be a number.")
    }
  }

  let c = TINT-COLOR.at(accent)

  if points.len() == 0 {
    return _drawing-frame(
      tint: c, kind: [CHART], title: title, caption: caption, [],
    )
  }

  let labels = points.map(p => p.at(0))
  let values = points.map(p => float(p.at(1)))
  let idx = range(points.len())

  _drawing-frame(
    tint: c,
    kind: [CHART · #upper(kind)],
    title: title, caption: caption,
    align(center, {
      set text(size: 7.4pt)
      if kind == "pie" {
        // The carrier plots on axes; a pie is drawn from the values directly.
        // Each slice takes a tint from the shared vocabulary so a pie is
        // coloured by the same table every other block reads.
        let total = values.sum()
        let hues = TINTS.map(t => TINT-COLOR.at(t))
        _cetz.canvas({
          import _cetz.draw: *
          let start = 0deg
          for (i, v) in values.enumerate() {
            let sweep = 360deg * (v / total)
            let col = hues.at(calc.rem(i, hues.len()))
            arc((0, 0), start: start, stop: start + sweep, radius: 1.6,
                anchor: "origin", mode: "PIE",
                fill: col.lighten(55%), stroke: 0.6pt + col)
            let mid = start + sweep / 2
            content(
              (1.05 * calc.cos(mid), 1.05 * calc.sin(mid)),
              text(size: 6.6pt, fill: luma(30))[#labels.at(i)],
            )
            start = start + sweep
          }
        })
      } else if kind == "line" {
        _lilaq.diagram(
          width: 7cm, height: 3.6cm,
          xaxis: (ticks: idx.map(i => (i, text(size: 6.6pt)[#labels.at(i)]))),
          ylabel: if unit != none { text(size: 6.6pt)[#unit] } else { none },
          _lilaq.plot(idx, values, color: c, mark: "o", stroke: 1pt + c),
        )
      } else {
        // bar draws its categories down the side, column across the bottom.
        // They are the same data read along different axes, which is why they
        // are one carrier call with the arguments swapped.
        let horizontal = kind == "bar"
        _lilaq.diagram(
          width: 7cm, height: 3.6cm,
          xaxis: if horizontal {
            (ticks: auto)
          } else {
            (ticks: idx.map(i => (i, text(size: 6.6pt)[#labels.at(i)])))
          },
          yaxis: if horizontal {
            (ticks: idx.map(i => (i, text(size: 6.6pt)[#labels.at(i)])))
          } else { (ticks: auto) },
          // The carrier has a dedicated call per orientation: `hbar` reads
          // its categories down the side, `bar` across the bottom.
          if horizontal {
            // hbar reads (lengths, positions) — the REVERSE of bar's
            // (positions, heights). Passing them in bar's order plots the
            // index as the magnitude, which draws a chart of the row numbers.
            _lilaq.hbar(values, idx, fill: c.lighten(40%), stroke: 0.6pt + c)
          } else {
            _lilaq.bar(idx, values, fill: c.lighten(40%), stroke: 0.6pt + c)
          },
        )
      }
    }),
  )
}
