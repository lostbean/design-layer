# Entity descriptions and typed attributes

## Scope

- Entity cards now accept `description:` below the heading. Attribute clauses
  now accept `name:` and `type:` above the body. The attribute body describes
  the value's meaning.
- Both new attribute arguments and the entity description accept strings or
  Typst content. Types express readable domain meaning; the renderer does not
  parse a type algebra.
- Existing clauses still render with the updated bundle. Missing new arguments
  produce guidelines in the ordinary render report. Strict mode rejects those
  omissions.

## Update the bundle first

- Update the host's pinned renderer input before adding the arguments. Older
  renderer functions accept unknown named arguments silently, so they can
  compile a document while omitting its new descriptions, names, and types.
- Identify the renderer input in the host's `flake.nix` and `flake.lock`.
  Input names and host wrapper names are host-defined; do not assume an input
  named `design-layer` exists.
- Use the host's pinned projection and render wrappers when available. Otherwise
  use the exact renderer revision recorded in its updated lock file for every
  command below; replace the revision placeholder before running commands.

```sh
task_renderer_ref='github:lostbean/design-layer/<revision-in-host-lock>'
nix build "$task_renderer_ref#gate-bundle" --no-link --print-out-paths
```

- The resulting bundle contains `schema/design-schema.json` and `render/`.
  Rebuild each host `.render` library from that bundle's schema with the same
  revision's `project` app. Adapt the output path to the import in `design.typ`.

```sh
task_renderer_bundle=$(nix build "$task_renderer_ref#gate-bundle" --no-link --print-out-paths)
nix run "$task_renderer_ref#project" -- \
  "$task_renderer_bundle/schema/design-schema.json" docs/design/.render
```

- Rebuild any other library directories imported by the layer from the same
  bundle. Mixing a new schema with an old library does not install the new
  rendering behavior.

## Rewrite the census

- Add a sentence or short paragraph describing each entity. Keep the entity
  body ordered as attribute clauses followed by relationship clauses.
- Split independent values into separate attribute clauses. Preserve a meaningful
  composite value as one clause when its domain type and component fields are
  explicit.
- Use domain types such as `Time window`, `Elapsed time`, or `Booking reference`.
  Define unfamiliar domain types where the layer defines its terms. Never infer
  an exact unknown type merely to fill the field; leave it unstated until its
  meaning is established.
- Preserve each value's provenance and any distinction between derivation at
  read and derivation at write. Preserve relationship meaning and cardinality.
  Splitting prose does not authorize a model change.
- The following examples are illustrative scheduling data. Save either example
  beside the projected `.render` directory to compile it as a standalone Typst
  document.

### Before

```typst
#import ".render/designlib.typ": *
#entity(
  title: "Booking", kind: "aggregate", owner: "Scheduling",
  lifecycle: "stateful", domain: "Scheduling",
)[
  #attribute(provenance: "authored")[
    Requested start and end instants, stated by the customer.
  ]
  #attribute(provenance: "derived")[
    Duration computed at read from the requested window, and expiry instant
    computed at read from the requested window and policy.
  ]
  #relates(cardinality: "n : 1")[Belongs to one Customer.]
]
```

### After

```typst
#import ".render/designlib.typ": *
#entity(
  title: "Booking", kind: "aggregate", owner: "Scheduling",
  lifecycle: "stateful", domain: "Scheduling",
  description: [A reservation for a customer during a requested time window.],
)[
  #attribute(name: "Requested window", type: "Time window", provenance: "authored")[
    Start and end instants stated by the customer.
  ]
  #attribute(name: "Duration", type: "Elapsed time", provenance: "derived")[
    Computed at read from the requested window.
  ]
  #attribute(name: "Expiry", type: "Expiry instant", provenance: "derived")[
    Computed at read from the requested window and policy.
  ]
  #relates(cardinality: "n : 1")[Belongs to one Customer.]
]
```

## Rebuild and verify

- Regenerate the complete layer PDF after updating its sources and imported
  libraries. Use the same pinned renderer revision for the render and check.
  Adapt the layer root and repository root to the host.

```sh
nix run "$task_renderer_ref#render" -- docs/design docs/design/design-layer.pdf
nix run "$task_renderer_ref#check" -- docs/design .
nix run "$task_renderer_ref#lint" -- docs/design
```

- Review the ordinary render's guideline count and named fields. Resolve the
  migrated census omissions; retain unrelated existing guidance explicitly.
  The optional `lint` command promotes every guideline to an error, including
  unrelated existing guidance.
- Extract PDF text with a Nix-provided `pdftotext` and confirm every migrated
  name, type, and description appears. Compilation alone does not prove that an
  older renderer displayed the new arguments.

```sh
nix shell nixpkgs#poppler-utils --command \
  pdftotext -layout docs/design/design-layer.pdf /tmp/entity-migration.txt
```

- Inspect long cards in the rendered PDF. A card may span pages, but its heading
  must accompany its first attribute, group headings must accompany their first
  item, and attribute headings must accompany their descriptions.
- Keep reference validation enabled. A type expressed as Typst reference content
  must resolve; test an intentionally missing reference in a temporary fixture
  and confirm compilation fails before discarding that fixture.
- Stage the host's lock file, migrated sources, regenerated imported libraries
  where tracked, and complete PDF together. Run the host's existing gate before
  committing so its source and rendered document use one renderer revision.
