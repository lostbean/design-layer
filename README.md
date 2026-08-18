# Design Layer

Mechanical infrastructure and syntax for the design layer: the renderer, the
projector, the block contracts, and the gate.

Called through Nix, never copied into a host. A host stores only its own
`design.md`, `CONTEXT.md`, `docs/adr/`, and the rendered document.

Status: empty shell. Nothing has moved here yet — the Nix bundle must first be
proven against a bare host in the framework repo.
