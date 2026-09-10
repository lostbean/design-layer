# Changelog

## Unreleased

- Prose tables now consume the full text measure and allocate bounded column proportions from their content lengths, so compact columns remain compact without starving adjacent prose columns.
- Prose tables now use semantic headers, repeated headers across pages, and open horizontal rules instead of a spreadsheet grid.
- Invalid column counts, missing headers, non-array cells, and incomplete rows now fail with specific messages.
- The renderer ignores ambient system font paths and keeps its embedded font families for byte-stable PDF output across Ubuntu and macOS.
- The migration is documented in [Reproducible font resolution](docs/migrations/reproducible-fonts.md).
