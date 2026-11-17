<!-- design-units:begin -->
<!-- Generated from the design layer by design-units. Do not edit between these markers: change the unit in its Typst source and regenerate. -->
<!-- prettier-ignore-start -->

## Design unit: Checked library

Overview: Hand-written Typst that reads the schema at compile time. One function per block kind validates its own call, then draws it for the PDF or emits Semantic metadata for the projection.

Interface:

- `designlib.typ` is the one import a `design.typ` makes.
- `schema/design-schema.json` declares every vocabulary, the unit contract, and the anchor patterns.
- The compile input `strict=1` promotes every guideline to an error; `context=1` switches every call to semantic metadata.
- The compile input `review-places=1` makes every document, section, subsection, unit, pending ledger, glossary, diagram, custom figure, and formula record the page and position where it is drawn, as metadata that draws nothing and moves nothing.

Invariants:

- A value outside a declared vocabulary, an unresolved reference, and a unit missing a required field fail the compile.
- A unit's heading level is its depth. A unit past the sixth level fails the compile, as it fails the projection.
- A unit field holds prose only, a code block included, and a unit's body holds no section or heading above the unit. Content the projection cannot express fails the compile.
- A guideline never reaches the page and never blocks an ordinary render.
- Every declared block kind resolves to a callable function of the same name, and the gallery calls it.

Side effects: None

Verification: `nix develop --command bash scripts/designlib-native.test.sh` and `scripts/widget-coverage.test.sh`.

Source: [docs/design/design.typ#unit-checked-library](../docs/design/design.typ#unit-checked-library)

Full unit: `nix run .#context -- docs/design --unit checked-library`

<!-- prettier-ignore-end -->
<!-- design-units:end -->
