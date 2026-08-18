# Design Layer

Mechanical infrastructure and syntax for the design layer: the renderer, the
projector, the block contracts, and the gate.

Called through Nix, never copied into a host. A host stores only its own
`design.md`, `CONTEXT.md`, `docs/adr/`, and the rendered document.

## The boundary

A concept lives here when a script or the renderer decides pass/fail on it. It
lives in the framework repo when a human or an agent applies judgement. This
repo answers exactly one question — is this `design.md` well-formed, and what
does it render to — and holds no opinion about when to design, how deep to go,
or what to build next.

This repo has no design layer of its own, deliberately. It is a tool, and its
correctness is established by tests: the self-tests under `scripts/*.test.sh`
and the widget gallery fixture that exercises every declared block kind.

## Use

Build the rendered document from a layer, then gate it:

```sh
nix run github:lostbean/design-layer#aggregate -- docs/design docs/design/design-layer.pdf
nix run github:lostbean/design-layer#check     -- docs/design .
```

`check` runs three things in sequence — the aggregate freshness check
(regenerate and compare), token coverage, and layer integrity — and exits 0
clean, 1 on a violation, 2 on an error.

The other two entry points are lower level:

```sh
nix run <flake>#render  -- <design.md> [--check]   # one document
nix run <flake>#project -- <schema.json> <out-dir> # schema -> renderer library
```

`nix build .#gate-bundle` gives the store path holding the scripts, the schema,
and a fresh projection of that schema, for an installer or a CI job to
reference directly.

## Layout

```
scripts/     the gate: aggregate, render, integrity, coverage, projector
schema/      the ONE declared schema — enums, anchors, layout, contracts
fixtures/    the widget gallery: every block kind, and the renderer-drift tripwire
```

## Development

`nix develop` provides the vendored renderer, python, and the formatter.
`nix fmt` formats; `nix flake check` runs the formatter check, the gate
self-tests, and the projector's determinism check.
