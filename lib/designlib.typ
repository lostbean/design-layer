// designlib.typ — the renderer's block-contract library.
//
// THIS FILE IS HAND-WRITTEN, and so is everything it imports. The library used
// to be emitted from heredocs inside a Python generator; it is now plain Typst
// files that READ the ONE declared schema at compile time through `json()`.
// A schema edit therefore reaches the library with no regeneration step: the
// compile itself is the projection.
//
// NOTHING HERE IS GENERATED. The last generated file was the behavior fence's
// pattern table, which existed only because the schema declared those patterns
// in a dialect the renderer's regex engine could not read. The schema declares
// them in the engine's own dialect now, so the fence is read straight from
// design-schema.json like every other vocabulary and no file is left to write.
//
// HOW A CONSUMER USES IT. `render-project <schema> <dir>` assembles a library
// directory holding these files and a copy of the schema; a consumer imports
// `<dir>/designlib.typ`. The schema travels INSIDE the directory, so a caller
// that copies the directory elsewhere copies the schema with it and every
// relative path still resolves.
//
// SCOPE, declared honestly. The library carries every PER-BLOCK contract: field
// presence, title length, enum legality, and the cross-field rules that live
// inside one block.
//
// It ALSO carries the DOCUMENT-level contracts, which is not obvious, because a
// function only runs when it is CALLED and therefore cannot see a block that was
// never written. A STATE closes that gap: each call appends to a trail, and an
// assertion the aggregate places at the end of the scope reads the finished
// trail back. A kind missing from a finished trail was never called, which is
// how a contract notices an absence. Three trails do this — the foundation
// (order and per-kind minimum), a behavior block's clauses (cardinality and
// order), and the numbered spine (ascending order).
//
// What the library cannot see is anything ACROSS ARTIFACTS — a link into
// another file, an ADR that exists on disk, a term another context declares.
// That is layer-integrity's half, and the split is by what is visible from
// inside one compile.
//
// ---- where each concern lives --------------------------------------------
//   schema.typ     reads the ONE declared schema; every vocabulary; the
//                  coherence checks the generator used to run at projection
//   tokens.typ     the semantic colour tables and their totality guarantee
//   rules.typ      guidelines vs fail-closed failures; the contract helpers
//   furniture.typ  lens pills, chips, links, the inline layer
//   packages.typ   the vendored package imports and the names they bind
//   statements.typ the foundation statements and their document-level trail
//   behavior.typ   the behavior block, its clauses, the mechanism fence
//   census.typ     the entity census card, its attributes and relationships
//   visuals.typ    admonitions, cards, stat tiles, tables, embedded figures
//   diagram.typ    diagrams, charts, and the figure block
//   shell.typ      the document shell and the aggregate shell
//   native.typ     the native authoring surface a design.typ calls directly
#import "schema.typ": *
#import "tokens.typ": *
#import "rules.typ": *
#import "furniture.typ": *
#import "packages.typ": *
#import "statements.typ": *
#import "behavior.typ": *
#import "census.typ": *
#import "visuals.typ": *
#import "diagram.typ": *
#import "shell.typ": *
#import "native.typ": *
