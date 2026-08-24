// The ONE declared schema, read at COMPILE TIME.
//
// This library is not generated. It reads schema/design-schema.json directly
// through Typst's own `json()`, so a schema edit reaches the library with no
// regeneration step: the compile IS the projection.
//
// HOW THE SCHEMA IS FOUND. Typst resolves a path in `json()` relative to the
// file containing the call and refuses any path that escapes `--root`. A
// library living in a read-only bundle therefore cannot reach a consumer's
// schema by a relative path — the consumer's repo is not under the bundle.
//
// The answer is that the schema TRAVELS WITH THE LIBRARY. `render-project`
// assembles a library directory holding these .typ files, the fence table it
// generates, and a copy of the schema, so the path below is relative and
// always resolves. A caller that copies the directory somewhere else copies
// the schema with it, which is what keeps every existing consumer working:
// they all `cp -r <lib-dir> <target>/.render` and compile with a --root that
// spans the copy, and the schema is inside the copy.
//
// `--input schema=` still overrides, for a caller that wants to compile
// against a schema elsewhere under its --root. A path beginning with `/` is
// resolved against --root rather than against the filesystem.
#let SCHEMA-PATH = sys.inputs.at("schema", default: "design-schema.json")

#let schema = json(SCHEMA-PATH)

// ---- the projector's own fail-closed checks, now compile-time checks -------
// The generator refused to project a schema whose declarations were incoherent.
// Those checks do not disappear when the generator does — they move here, and
// they now run on every compile rather than once per projection.
#let _schema-fail(msg) = panic("design-schema: " + msg)

// ---- the declared vocabularies, read from the one schema ------------------
#let LENSES = schema.enums.lens.values
#let ENFORCEMENTS = schema.enums.enforcement.values
#let TINTS = schema.design_doc.accents.values
#let PENDING-KINDS = schema.pending_ledger.kinds.keys()
#let PROVENANCES = schema.enums.provenance.values
#let ENTITY-KINDS = schema.design_doc.entity_contract.kinds
#let ENTITY-LIFECYCLES = schema.design_doc.entity_contract.lifecycles
#let COVERAGE-STATUSES = schema.layer_layout.coverage_map.statuses.keys()
#let FOUNDATION-ORDER = schema.design_doc.foundation_order
#let FOUNDATION-REQUIRED = schema.design_doc.foundation_required
#let TITLE-MAX = 64

// `levels` carries a prose no_pairing entry alongside the real levels; a level
// is a key that also has a fence entry, exactly as the generator read it.
#let BEHAVIOR-LEVELS = schema.design_doc.behavior_contract.levels.keys().filter(
  lv => lv + "_forbids" in schema.design_doc.behavior_contract.fence,
)

// THE CLAUSE ORDER AND CARDINALITY, read as DECLARED DATA. A clause renders as
// an independent call, so no clause ever meets its siblings; the order and the
// per-clause bound are document-level rules the library asserts from a trail.
#let CLAUSE-ORDER = schema.design_doc.behavior_contract.clause_sequence
#let _CLAUSE-BOUNDS = schema.design_doc.behavior_contract.clause_bounds
#let _LEGAL-BOUNDS = ("0..n", "exactly 1", "1..n")
#let CLAUSE-EXACTLY-ONE = CLAUSE-ORDER.filter(c => _CLAUSE-BOUNDS.at(
  c,
  default: none,
) == "exactly 1")
#let CLAUSE-AT-LEAST-ONE = CLAUSE-ORDER.filter(c => _CLAUSE-BOUNDS.at(
  c,
  default: none,
) == "1..n")

// The vendored package set a figure block's `uses` is restricted to. READ FROM
// THE SCHEMA, because a host receives the schema and nothing else.
#let VENDORED = schema.design_doc.vendored_packages.packages

// THE ALTITUDE LADDER. `altitudes` is not the set of legal values: it is the
// list of NAMED rungs. The legal set is whatever altitude_pattern admits,
// because the layer recurses until a unit passes the reproduction test — a
// depth no fixed vocabulary can bound.
#let _UNIT-MODEL = schema.layer_layout.unit_model
#let ALTITUDES = _UNIT-MODEL.altitudes
#let ALTITUDE-PATTERN = _UNIT-MODEL.altitude_pattern
#let ALTITUDE-NAMES = _UNIT-MODEL.altitude_names
#let ALT-TINT = _UNIT-MODEL.altitude_tints
// The FALLBACK LADDER for a rung the schema does not name: indexing the
// declared accent list by level number makes the colour a pure function of the
// level, so the same altitude draws the same band on every render.
#let ALT-TINT-CYCLE = TINTS

// The page-identity frontmatter keys the document shell renders.
#let FRONTMATTER-KEYS = schema.design_doc.frontmatter_keys.keys()

// ---- the coherence checks the generator used to run at projection time ----
// Each one refused to emit a library whose declarations contradicted each
// other. They run on every compile now, which is strictly more often.
#let _check-schema = {
  if FOUNDATION-ORDER.len() == 0 {
    _schema-fail(
      "design_doc.foundation_order is empty — the foundation order rule would "
        + "run over an empty sequence",
    )
  }
  let declared = schema.design_doc.blocks.keys()
  for k in FOUNDATION-ORDER {
    if not declared.contains(k) {
      _schema-fail(
        "design_doc.foundation_order names kind " + k + ", which "
          + "design_doc.blocks does not declare",
      )
    }
  }
  if FOUNDATION-REQUIRED.len() == 0 {
    _schema-fail(
      "design_doc.foundation_required is empty — the cardinality rule would be "
        + "an assertion over an empty set",
    )
  }
  for k in FOUNDATION-REQUIRED {
    if not FOUNDATION-ORDER.contains(k) {
      _schema-fail(
        "design_doc.foundation_required names kind " + k + ", which is absent "
          + "from design_doc.foundation_order",
      )
    }
  }
  if CLAUSE-ORDER.len() == 0 {
    _schema-fail(
      "design_doc.behavior_contract.clause_sequence is empty — the clause "
        + "order rule would run over an empty sequence",
    )
  }
  for c in CLAUSE-ORDER {
    if c not in _CLAUSE-BOUNDS {
      _schema-fail(
        "design_doc.behavior_contract.clause_bounds declares no bound for "
          + "clause " + repr(c) + ", which clause_sequence names",
      )
    }
    if _CLAUSE-BOUNDS.at(c) not in _LEGAL-BOUNDS {
      _schema-fail(
        "design_doc.behavior_contract.clause_bounds gives clause "
          + repr(c) + " the bound " + repr(_CLAUSE-BOUNDS.at(c))
          + ", which is not one of " + repr(_LEGAL-BOUNDS),
      )
    }
  }
  if CLAUSE-EXACTLY-ONE.len() == 0 and CLAUSE-AT-LEAST-ONE.len() == 0 {
    _schema-fail(
      "design_doc.behavior_contract.clause_bounds declares neither an "
        + "'exactly 1' nor a '1..n' clause — the clause cardinality rule "
        + "would be an assertion over an empty set",
    )
  }
  for ek in ("kinds", "lifecycles") {
    if schema.design_doc.entity_contract.at(ek, default: ()).len() == 0 {
      _schema-fail(
        "design_doc.entity_contract declares no " + ek + " — the entity block "
          + "would validate against an empty vocabulary",
      )
    }
  }
  // fail-closed on shell drift: the shell renders a masthead (eyebrow, lede)
  // and a colophon (footer), so the schema must still declare those three
  // page-identity keys. A schema that drops or renames one is a visible break.
  for k in ("eyebrow", "lede", "footer") {
    if not FRONTMATTER-KEYS.contains(k) {
      _schema-fail(
        "design_doc.frontmatter_keys no longer declares the page-identity key "
          + repr(k) + ", which the document shell renders",
      )
    }
  }
  if VENDORED.len() == 0 {
    _schema-fail(
      "design_doc.vendored_packages.packages is empty, so a figure block's "
        + "uses= list could name nothing legal",
    )
  }
  // A NAMED rung must carry both its name and its tint. The check is not
  // vacuous under an open ladder: it quantifies over the rungs the schema
  // chose to name, and naming a rung is what obliges the schema to say what it
  // is called and what colour it draws in.
  for a in ALTITUDES {
    if a.matches(regex(ALTITUDE-PATTERN)).len() == 0 {
      _schema-fail(
        "layer_layout.unit_model.altitudes lists " + repr(a) + ", which the "
          + "declared altitude_pattern " + repr(ALTITUDE-PATTERN)
          + " does not admit",
      )
    }
    if a not in ALTITUDE-NAMES {
      _schema-fail(
        "layer_layout.unit_model.altitude_names has no entry for " + repr(a),
      )
    }
    if a not in ALT-TINT {
      _schema-fail(
        "layer_layout.unit_model.altitude_tints has no entry for " + repr(a),
      )
    }
    // An altitude names a tint as a STRING, so renaming a tint in
    // design_doc.accents would otherwise leave an altitude pointing at a
    // colour that does not exist.
    if ALT-TINT.at(a) not in TINTS {
      _schema-fail(
        "altitude " + repr(a) + " names tint " + repr(ALT-TINT.at(a))
          + ", which design_doc.accents does not declare",
      )
    }
  }
  if ALT-TINT-CYCLE.len() == 0 {
    _schema-fail(
      "design_doc.accents declares no tint, so an unnamed altitude has no "
        + "colour to fall back to",
    )
  }
}
