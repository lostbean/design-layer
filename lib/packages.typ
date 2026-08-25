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

// the drawing packages a figure block's `uses` names. Three of them ALSO carry
// a first-class block: `chronos` draws the sequence, and `lilaq` and `cetz`
// the chart. `finite` stays a figure-only package: it draws the right marks
// for an automaton but has no layout solver, so the state machine goes to the
// graph renderer that does. Each is bound a second time under a private
// name that the block calls, so the block never depends on what the public
// name happens to be bound to in a document that also imports it. The public
// binding stays because a figure body still names the package.
#import "@preview/chronos:0.2.1"
#import "@preview/chronos:0.2.1" as _chronos
#import "@preview/finite:0.5.0"
#import "@preview/cetz:0.4.2"
#import "@preview/cetz:0.4.2" as _cetz
#import "@preview/cetz-plot:0.1.2"
#import "@preview/lilaq:0.5.0"
#import "@preview/lilaq:0.5.0" as _lilaq

#let BORROWED = (
  "_cetz",
  "_chronos",
  "_fl-edge",
  "_fl-node",
  "_fletcher",
  "_lilaq",
  "cetz",
  "cetz-plot",
  "chronos",
  "cmarker",
  "dot-render",
  "finite",
  "lilaq",
)
