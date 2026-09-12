---
name: Design Layer Renderer
description: A quiet technical atlas whose visual grammar makes structure, ownership, state, and evidence easy to scan.
colors:
  paper: "#fbfbf8"
  ink: "#172126"
  muted: "#58656b"
  faint: "#7b868b"
  hairline: "#d7ddda"
  surface: "#f2f5f3"
  surface-strong: "#e8eeeb"
  teal: "#087f79"
  violet: "#6952a3"
  amber: "#a86408"
  blue: "#2870a6"
  rose: "#ad3451"
  slate: "#5f6b73"
  coverage-standard: "#6f7a80"
  scope-rust: "#a8492a"
  pending-build: "#2f5f8f"
  pending-foundation: "#5a4fa0"
  pending-ruling: "#8a6a1f"
  procedure-teal: "#187b78"
typography:
  display:
    fontFamily: "Libertinus Serif, Georgia, serif"
    fontSize: "31pt"
    fontWeight: 700
  chapter:
    fontFamily: "Libertinus Serif, Georgia, serif"
    fontSize: "26pt"
    fontWeight: 700
  hero:
    fontFamily: "Libertinus Serif, Georgia, serif"
    fontSize: "23pt"
    fontWeight: 700
  heading-1:
    fontFamily: "Libertinus Serif, Georgia, serif"
    fontSize: "16pt"
    fontWeight: 700
  heading-2:
    fontFamily: "Libertinus Serif, Georgia, serif"
    fontSize: "12.5pt"
    fontWeight: 700
  heading-3:
    fontFamily: "Libertinus Serif, Georgia, serif"
    fontSize: "10.2pt"
    fontWeight: 600
  body:
    fontFamily: "Libertinus Serif, Georgia, serif"
    fontSize: "9.4pt"
    fontWeight: 400
  renderer-title:
    fontFamily: "Libertinus Serif, Georgia, serif"
    fontSize: "10.2pt"
    fontWeight: 700
  renderer-body:
    fontFamily: "Libertinus Serif, Georgia, serif"
    fontSize: "8.4pt"
    fontWeight: 400
  compact:
    fontFamily: "Libertinus Serif, Georgia, serif"
    fontSize: "7.8pt"
    fontWeight: 400
  label:
    fontFamily: "Libertinus Serif, Georgia, serif"
    fontSize: "6.7pt"
    fontWeight: 700
    letterSpacing: "0.65pt"
  mono:
    fontFamily: "DejaVu Sans Mono, ui-monospace, monospace"
    fontSize: "7.8pt"
    fontWeight: 400
rounded:
  xs: "1.5pt"
  sm: "2pt"
  md: "3pt"
  pill: "6pt"
spacing:
  micro: "1.5pt"
  xs: "3pt"
  block-gap: "0.45em"
  sm: "6pt"
  md: "8pt"
  lg: "10pt"
  section: "13pt"
  indent: "14pt"
  page-x: "2.05cm"
  page-y: "1.9cm"
components:
  statement-card:
    textColor: "{colors.ink}"
    typography: "{typography.renderer-body}"
    rounded: "{rounded.sm}"
    padding: "7pt 9pt 8pt"
    width: "100%"
  semantic-chip:
    backgroundColor: "{colors.surface-strong}"
    textColor: "{colors.muted}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "1.5pt 4pt"
  drawing-frame:
    textColor: "{colors.ink}"
    typography: "{typography.renderer-body}"
    rounded: "{rounded.sm}"
    width: "100%"
  entity-census:
    textColor: "{colors.ink}"
    typography: "{typography.renderer-body}"
    rounded: "{rounded.md}"
    width: "100%"
  stat-tile:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    padding: "8pt"
  pending-entry:
    textColor: "{colors.ink}"
    typography: "{typography.renderer-body}"
    rounded: "{rounded.sm}"
    padding: "6pt 8pt"
  formula-block:
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    padding: "8pt 10pt"
    width: "100%"
  pseudocode-block:
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    padding: "8pt 10pt"
    width: "100%"
  data-table:
    textColor: "{colors.ink}"
    typography: "{typography.renderer-body}"
    width: "100%"
---

# Design System: Design Layer Renderer

## Overview

**Creative North Star: "The Quiet Systems Atlas"**

The renderer treats an architecture document as a calm technical atlas: warm paper, dark editorial type, exact rules, and restrained semantic color make a dense model feel deliberate rather than busy. The page establishes orientation first, then lets headings, labels, frames, and diagrams disclose deeper structure without changing visual language.

The system is editorial in voice and mechanical in discipline. Large ideas receive generous white space; dense evidence is compressed into small, repeated anatomies. Color never decorates a page or simulates depth. It names a concept, owner, status, or evidence class, while wording, shape, line style, and order repeat the same meaning for print and color-independent reading.

**Key Characteristics:**

- Warm near-white pages with dark blue-black text.
- A serif-first hierarchy with compact tracked labels and sparing monospaced identifiers.
- Thin frames, quiet tonal fills, and colored top rules instead of shadows.
- One six-accent vocabulary reused across blocks, diagrams, charts, and inline furniture.
- Repeated component anatomies that stay legible at high information density.

## Colors

The palette is a neutral editorial foundation with muted, medium-dark accents chosen to survive long reading sessions, print, and common color-vision differences.

### Primary

- **Atlas Teal** (`#087f79`): The settled system voice for principles, composition, verified states, primary rules, and the document's opening rule.

### Secondary

- **Model Violet** (`#6952a3`): Modeling, aggregates, invariants, formulas, and analytical structures.
- **Structural Blue** (`#2870a6`): Depth, entities, goals, links, and structural information.

### Tertiary

- **Caution Amber** (`#a86408`): State, authored provenance, behavior, warnings, and transition-oriented material.
- **Invariant Rose** (`#ad3451`): No-goals, lifecycle state, and facts that need a distinct constraint signal.
- **Procedure Teal** (`#187b78`): The dedicated procedure tone used by pseudocode.
- **Scope Rust** (`#a8492a`): Coverage explicitly declared out of scope.
- **Build Blue, Foundation Violet, and Ruling Ochre** (`#2f5f8f`, `#5a4fa0`, `#8a6a1f`): The pending ledger's build, foundation, and ruling categories.

### Neutral

- **Near-Paper** (`#fbfbf8`): The A4 page ground and default light surface.
- **Blueprint Ink** (`#172126`): Primary prose, headings, values, and diagram labels.
- **Muted Blueprint** (`#58656b`): Ledes, captions, secondary titles, axes, and explanatory text.
- **Faint Blueprint** (`#7b868b`): Folios, dates, group labels, and low-priority metadata.
- **Hairline Sage** (`#d7ddda`): Quiet boundaries, dividers, and chart grids.
- **Quiet Surface** (`#f2f5f3`): Notes, stat tiles, code blocks, and nested information panels.
- **Strong Surface** (`#e8eeeb`): Table headers and untinted chips.
- **Quiet Slate** (`#5f6b73`): Robustness, conventional enforcement, code and external-figure furniture.
- **Standard Gray** (`#6f7a80`): Coverage delegated to a standard convention.

### Named Rules

**The Semantic Accent Rule.** Color answers what kind, who owns it, what state it is in, or how evidence arose; it does not invent depth or decoration.

**The Reinforced Meaning Rule.** Every semantic color is repeated by a label, shape, line style, position, or explicit word, so color never carries meaning alone.

## Typography

**Display Font:** Libertinus Serif (with Georgia and generic serif fallbacks)

**Body Font:** Libertinus Serif (with Georgia and generic serif fallbacks)

**Label/Mono Font:** DejaVu Sans Mono (with system monospace fallbacks) for identifiers, dates, cardinalities, code, and procedural text

**Character:** The single serif family makes the PDF read like a durable technical monograph rather than an application screen. Monospaced type appears only where fixed-width structure materially helps comparison or signals authored syntax.

### Hierarchy

- **Display** (bold, `31pt`): Aggregate title pages only.
- **Chapter** (bold, `26pt`): Context and chapter opening pages.
- **Hero** (bold, `23pt`): The title of a standalone design document.
- **Heading 1** (bold, `16–17pt`): Highest in-document section level, with the aggregate variant one point larger.
- **Heading 2** (bold, `12.5pt`): The recurring authored section title.
- **Heading 3** (semibold, `10.2pt`): Subsections and local divisions.
- **Body** (regular, `9.4pt`, `0.68em` paragraph leading): Justified long-form prose.
- **Renderer Title** (bold, `10.2pt`): Titles inside statement, component, entity, and data blocks.
- **Renderer Body** (regular, `8.4pt`): Primary copy inside compact components.
- **Compact** (regular, `7.8pt`): Dense answers, notation keys, and supporting detail.
- **Label** (bold, `6.2–7.5pt`, `0.4–1.2pt` tracking, uppercase): Kinds, groups, headers, and metadata.

### Named Rules

**The Serif-First Rule.** Use the serif family for reading and explanation; reserve monospace for identifiers, dates, cardinality shapes, source, and procedure lines.

**The Quiet Label Rule.** Labels are small, tracked, and explicit; hierarchy comes from placement and repetition rather than oversized chrome.

## Layout

The output is a fixed A4 reading surface with `2.05cm` horizontal and `1.9cm` vertical margins. Standalone pages use a `23pt` hero and an `88%`-measure lede above a teal rule; aggregate title pages center a `31pt` title between large areas of white space. Chapter openings begin lower on the page and use a top accent, a compact kind label, a `26pt` title, and a short index so a reader sees the chapter's shape before entering it.

A section follows one stable sequence: heading, muted lead, one visual when needed, then notes or body. Leads occupy at most `92%` of the text measure. Recurring vertical gaps cluster around `0.45em`, `6pt`, and `8pt`; larger section and shell transitions use `10–13pt`. Nested procedural levels advance by `14pt`.

Cards use one column when their prose is long and up to two columns when their content remains comparable; explicitly authored grids may use two to four columns. Tables consume the full measure but size columns from content. Structural drawings retain natural proportions, center in the measure, and scale down only when they would exceed roughly `92–94%` of available width or `78–82%` of available height.

**The Orientation-Before-Depth Rule.** Page, chapter, section, and drawing frames state their level or kind before the reader meets detail.

**The Natural-Drawing Rule.** Do not stretch a small drawing to fill the column; drawing size communicates complexity only when natural proportions are preserved.

## Elevation & Depth

The renderer uses no shadows. Depth comes from page-level white space, pale tonal fills, thin hairlines, and a slightly stronger colored top rule. Nested surfaces stay close in value so the document remains flat enough for print while still exposing containment.

**The Flat-By-Contract Rule.** Every surface rests on the page; hierarchy is expressed through tone, frame weight, and spacing rather than simulated elevation.

## Shapes

Large blocks are almost square: statement, drawing, formula, pseudocode, note, and ledger frames use gently eased `2pt` corners, while census and figure containers use `3pt`. Small role and status furniture uses `1.5–3pt` corners; lens pills alone use a compact `6pt` capsule because they behave as inline semantic tokens.

Most frames combine a fine perimeter with a stronger colored top edge. Dashed outlines are reserved for external ownership, cross-seam relationships, or authored figures that must remain visibly distinct from checked structural diagrams. Diagrams may use role-specific silhouettes, but their generated legends always explain those shapes.

**The Shallow-Corner Rule.** Keep document surfaces nearly square; rounded capsules belong to compact semantic furniture, not to panels.

**The Boundary-Style Rule.** Solid rules describe owned or internal structure; dashed rules describe external ownership, cross-seam relations, or a different rendering contract.

## Components

### Document Shell

The shell fixes the page ground, serif body, margins, justified paragraph rhythm, heading scale, and quiet footer. A standalone document opens with hero, lede, and teal rule; an aggregate adds title page, contents hierarchy, and context chapter pages. The shell is calm and spacious so dense block families can remain compact.

### Statement Cards

Goals, no-goals, principles, invariants, and behavior rules share one anatomy: tracked uppercase kind, bold local title, concise body, then optional semantic furniture. The card uses a very pale tint, a `1.4pt` semantic top rule, fine side rules, `2pt` corners, and `7–9pt` internal spacing. The family changes color by kind without changing structure.

### Semantic Chips and Pills

Chips name status, context, ownership, provenance, lifecycle, and citations. Neutral chips use Strong Surface and muted text; semantic chips use a pale tint, a fine matching border, and darker text. Lens pills use the same pattern with a `6pt` capsule and remain separate when more than one lens applies.

### Cards, Notes, and Stat Tiles

General cards use equal-height table cells, pale semantic fills, a stronger top edge, and `8pt` padding. Notes and stat tiles use Quiet Surface with a Hairline Sage border. Stat values rise to `16pt`, while their label and directional delta remain compact and semantically colored.

### Drawing Frames

Diagrams, charts, sequences, and state machines begin with a slim tinted strip naming the drawing kind, altitude, or viewpoint and may add a muted title. The drawing is centered beneath the strip at its natural proportion; captions are muted italic text below. Structural diagrams, charts, sequences, and machines share this frame even though each carrier draws different marks.

### Entity Census

An entity is a `3pt` framed container with a pale kind-tinted header that keeps the title, kind, lifecycle, domain, and owner together. The body announces Attributes and Relationships with small tracked labels. Provenance and cardinality occupy a fixed comparison column, making repeated records easy to scan vertically.

### Tables and Coverage

Prose tables use a stronger tonal header, alternating quiet rows, and open horizontal rules instead of a spreadsheet grid. Coverage is even lighter: three aligned columns, no enclosing box, compact status chips, and an explicit reason column. Code, file names, and cardinalities use monospace where column shape matters.

### Formula Blocks

Formula blocks use the shared top-rule frame with a kind label, optional title, centered equation, optional notation table, and muted italic caption. Violet is the default. Notation is separated by a fine rule and uses compact semibold symbols against muted definitions.

### Pseudocode Blocks

Pseudocode pairs a semantic frame with a nested Quiet Surface input/output panel. Keywords occupy a fixed right-aligned label column, while monospaced procedure text advances in `14pt` levels. Branches, loops, closing markers, and returns are visually explicit without imitating a specific programming language.

### Pending Ledger

Each pending item is a pale, kind-tinted row with a stronger top edge, compact category chip, bold title, right-aligned monospaced date, body, and optional record chip. The fixed anatomy makes age and category scannable without turning the page into a task board.

## Do's and Don'ts

### Do:

- **Do** begin with orientation: name the page, chapter, section, and drawing kind before showing detail.
- **Do** reuse the declared semantic accent for the same concept across cards, charts, diagrams, and inline furniture.
- **Do** pair color with words, shapes, line styles, or position so the document remains legible in grayscale and without reliable color discrimination.
- **Do** preserve the serif reading voice and use monospace only where fixed-width comparison or authored syntax matters.
- **Do** keep component spacing compact and repeat the same anatomy before adding a new visual form.
- **Do** preserve natural diagram proportions and let white space carry the page-level hierarchy.

### Don't:

- **Don't** use shadows, strong gradients, or ornamental color to create hierarchy.
- **Don't** round large panels into capsules; reserve pronounced rounding for inline semantic furniture.
- **Don't** merge distinct semantic labels into a blended pill or rely on hue alone to distinguish them.
- **Don't** stretch sparse drawings to the full text measure or assign importance through arbitrary scale.
- **Don't** style individual authoring calls; visual decisions belong to the renderer's shared component and token grammar.
- **Don't** turn open tables into boxed spreadsheet grids when alignment and horizontal rules already reveal structure.
