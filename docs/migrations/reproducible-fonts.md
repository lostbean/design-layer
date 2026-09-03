# Reproducible font resolution

- The renderer sets `TYPST_IGNORE_SYSTEM_FONTS=true` for every aggregate compile and query.
- The renderer removes `TYPST_FONT_PATHS`, so an inherited host directory cannot change font selection.
- The renderer removes `TYPST_IGNORE_EMBEDDED_FONTS`, so the embedded families remain available.
- The supplied Typst command selects the pinned binary for the public Nix applications and rejects `--font-path` and `--ignore-embedded-fonts`.

## Migrate a host

- Remove `TYPST_FONT_PATHS` and `TYPST_IGNORE_EMBEDDED_FONTS` from render and check environments.
- Rebuild the committed PDF with the pinned renderer:

  ```sh
  nix run github:lostbean/design-layer#render -- docs/design docs/design/design-layer.pdf
  nix run github:lostbean/design-layer#check -- docs/design .
  ```

- Use the renderer's embedded families (including Libertinus Serif and DejaVu Sans Mono) for byte-stable output.
- A custom font requires an explicit, pinned renderer contract before it can be part of a reproducible layer.
