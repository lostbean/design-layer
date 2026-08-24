// ---- the vendored packages, and the names they bind ----------------------
//
// A figure body names a vendored package; the library imports each one so the
// AUTHOR never writes an import statement in a design document. The renderer
// binary vendors exactly this set, and `schema.typ` reads the DECLARED set out
// of design_doc.vendored_packages — widget-coverage binds the schema's
// declaration to the flake's actual `withPackages` list.
//
// A Typst import binds its names into the importing module's own scope, so a
// consumer asking the compiled library what it provides sees these bindings
// mixed in with the library's own. BORROWED is what the coverage check
// subtracts to recover the surface this library actually offers an author.
// It is written HERE, next to the import lines it names, which is the only
// place that knowledge exists once.

// diagraph renders a dot graph — the carrier a converted mermaid fence reaches.
#import "@preview/diagraph:0.3.6": render as dot-render

// fletcher lays out a node-and-edge diagram from declared nodes and edges, so
// the native diagram block never asks an author for coordinates. Imported under
// private names because `node` and `edge` are common words a document may bind.
#import "@preview/fletcher:0.5.8" as _fletcher
#import "@preview/fletcher:0.5.8": node as _fl-node, edge as _fl-edge

// the inline layer's CommonMark parser
#import "@preview/cmarker:0.1.6"

// the drawing packages a figure block's `uses` names
#import "@preview/chronos:0.2.1"
#import "@preview/finite:0.5.0"
#import "@preview/cetz:0.4.2"
#import "@preview/cetz-plot:0.1.2"
#import "@preview/lilaq:0.5.0"

#let BORROWED = (
  "_fl-edge",
  "_fl-node",
  "_fletcher",
  "cetz",
  "cetz-plot",
  "chronos",
  "cmarker",
  "dot-render",
  "finite",
  "lilaq",
)
