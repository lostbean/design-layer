<!-- design-units:begin -->
<!-- Generated from the design layer by design-units. Do not edit between these markers: change the unit in its Typst source and regenerate. -->
<!-- prettier-ignore-start -->

## Design unit: Documentation guidance

Overview: Two skills travel in the bundle. `document-design` selects what a newcomer needs and where explanation stops. `design-document-syntax` owns exact notation and mechanical contracts.

Interface:

- `skills/document-design/SKILL.md` states the baseline unit contract and when each optional block applies.
- `skills/design-document-syntax/SKILL.md` states file homes, calls, vocabularies, and commands.

Invariants:

- The syntax skill describes only what the library, the schema, or a gate script decides.
- Neither skill names a sibling framework or a host workflow.

Side effects: None

Verification: None mechanical. The gallery and the self-tests hold the contracts the skills describe.

Source: [docs/design/design.typ#unit-documentation-guidance](../docs/design/design.typ#unit-documentation-guidance)

Full unit: `nix run .#context -- docs/design --unit documentation-guidance`

<!-- prettier-ignore-end -->
<!-- design-units:end -->
