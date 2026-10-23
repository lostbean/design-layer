---
name: document-design
description: Creates or updates a high-level design layer from an existing repository so humans and code agents share the system's purpose, boundaries, abstractions, and important flows. Use when asked to document an architecture, explain a repository through a design layer, choose what belongs in design documentation, or reduce implementation detail in an existing layer. It documents the system and established intent; it does not redesign the system. Use design-document-syntax for exact Typst calls and mechanical contracts.
domains: [engineering]
status: ship
---

# Document design

## Purpose and authority

- Produce a shared mental model for a reader unfamiliar with the repository. Explain the use case, the abstractions that address it, and how those abstractions cooperate. The PDF and agent Markdown must communicate the same claims.
- Code is the source of truth for implemented behavior and structure. Established owner intent supplies goals, non-goals, principles, and reasons that code cannot establish. Never infer an intentional guarantee merely from one implementation path or passing test.
- This skill owns documentation selection, explanation, and representation. It does not choose a new architecture, improve the implementation, or judge whether the system follows a preferred design philosophy. Describe an unconventional design faithfully; report a consequential uncertainty separately.
- Consult the bundled [design-document-syntax](../design-document-syntax/SKILL.md) when authoring or checking the layer. It owns file homes, Typst bindings, block signatures, declared vocabularies, and mechanical contracts. Use the host's pinned version; do not copy or reinvent those contracts here.

## Gather evidence

- Read repository instructions, the existing layer, public entry points, and relevant tests and configuration. Trace a representative use case through the code to identify actual boundaries, responsibility, state ownership, and external interactions. Expand investigation only where a missing fact changes the architectural explanation.
- Distinguish implemented facts, established intent, and unresolved inference. Use code and configuration for implementation claims, tests as supporting evidence, and supplied requirements or decision records for rationale. A package dependency alone does not establish its architectural role.
- Ask the owner only for missing intent that materially changes the explanation. Continue documenting supported facts while an answer is pending. Do not invent business goals, non-goals, historical rationale, domains, or guarantees to complete a template.
- When an existing document contradicts the code, describe the implemented state and preserve the discrepancy explicitly. Do not silently discard accepted intent or present an unbuilt proposal as current behavior. Use the existing pending mechanism for material uncertainty or planned changes; preserve decision history.
- Respect the requested scope. A documentation request does not authorize implementation changes, new design decisions, repository-wide document deletion, or workflow installation.

## Select the content

- Standardize the questions below across projects. Group answers into concise sections using the pinned syntax's section guidance. The document's opening summary should establish purpose before asking the reader to interpret detailed constraints.

| Question                                        | Include                                                                                                  | Stop before                                            |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| What is this system for?                        | Users or callers, problem, principal use cases, intended outcome, deliberate exclusions                  | Feature backlog or exhaustive requirements             |
| Where does it begin and end?                    | System boundary, external actors and systems, meaningful inputs and outputs, trust boundaries            | Endpoint and payload catalogues                        |
| What shapes the solution?                       | Established goals, constraints, invariants, principles, and their reasons                                | Generic quality slogans or a new design philosophy     |
| How is it organized?                            | Major responsibilities, ownership, dependencies, and why the decomposition matters                       | File trees, classes, functions, or every module        |
| What concepts must a reader understand?         | Principal abstractions, domain concepts, meaningful relationships, state ownership, important lifecycles | Every entity, field, status, or database table         |
| How do the parts deliver the use case?          | One representative path; additional failure or recovery paths when architecturally significant           | Exhaustive behavior rules or handler-by-handler traces |
| What should a newcomer preserve or investigate? | Consequential trade-offs, limitations, unresolved claims, and selected code or reference entry points    | Runbooks, API references, or copied decision history   |

- Include a detail when omitting it would cause a reader to misunderstand a responsibility, boundary, guarantee, or major decision. Technical specificity is justified when it explains the architecture; abstraction does not require concealing a consequential technology choice.
- Stop decomposition when a reader can explain the part's role, important interactions and constraints, and where to investigate further. Do not require that a reader could rebuild the part from documentation alone. A child with an interface or state does not automatically deserve its own section.
- Aim for an overview readable in a few pages. Treat length as editorial guidance, never as a gate or a reason to hide essential complexity. Add a focused deeper view only for a named architectural question; keep the overview understandable without it.
- Name major system responsibilities at a consistent level. A domain boundary, deployment unit, source module, and storage boundary are different relationships; do not force them into one hierarchy or assume each system has multiple domains.
- Preserve one canonical home for each explanation and project term. Link to implementation detail instead of transcribing it. Use a few stable paths to orient investigation; avoid a symbol-by-symbol mapping that requires updates after ordinary refactoring.

## Required use cases, scope, and domain model

- Always include a clearly labeled **Use cases and scope** section for the documented library or application. Introduce it before the internal architecture; it may be a subsection within the pinned syntax's section structure.
- Describe the system from the user or consumer's perspective. Identify who uses it, the problem they bring, the principal interactions, and the outcomes they expect. For a library, include the integrating developer or calling system; for an application, include the relevant human users or external callers.
- State what the system provides, what the user or host must supply, and what remains outside its scope. Describe representative use cases through the consumer's goal, meaningful input or action, and observable outcome. Keep API signatures, exhaustive scenarios, and feature backlogs in their authoritative references.
- Always include a clearly labeled **Domain model** section. Describe the main concepts in the problem being solved, their meaning, and their relationships. Include identity, ownership, state, or lifecycle only where it explains an important property.
- Keep the domain model high-level or focus it on the main elements needed to understand the principal use cases. A library's domain may consist of inputs, transformations, results, and errors; do not invent business entities, persistence, or multiple domains. A component inventory or glossary alone does not explain the relationships between domain concepts.
- Express the model with concise prose, a compact table, or a semantic diagram. Connect its concepts to the use cases and explain how the principal abstractions cooperate to produce the consumer's outcome. Leave fields, classes, database schemas, and exhaustive state definitions in code unless a detail changes the architectural explanation.

## Adapt to the system

- Select these additional prompts by actual characteristics. They supplement the required Use cases and scope and Domain model sections; they are composable views, not mutually exclusive templates or further mandatory sections. Record an important absence when it prevents misunderstanding, such as a library that owns no durable state.

| Characteristic   | Architectural questions                                                                                                                                             |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Library          | What does the host supply? What are the conceptual operations, extension points, resource lifetimes, side effects, and compatibility commitments?                   |
| Frontend         | Which journeys organize the interface? Who owns local and server state? Which rendering, accessibility, offline, or synchronization constraints shape the solution? |
| Backend          | Who calls it? Which responsibilities and authorization decisions does it own? Where are transaction and failure boundaries? Which work is asynchronous?             |
| Persistent state | Who owns durable facts? What is derived? Which consistency, lifecycle, deletion, and recovery rules affect the system model?                                        |
| Distributed work | What delivery, ordering, duplicate-handling, coordination, and reconciliation assumptions are essential to understanding outcomes?                                  |
| CLI or pipeline  | What enters and leaves? Which processing stages matter? Which side effects, reproducibility constraints, and restart behavior shape use?                            |

- Include an entity or lifecycle only when its identity, ownership, or transitions explain an important property. Explain principal concepts in domain language without manufacturing aggregates or state machines to match available widgets.

## Choose a representation

- Begin with the reader's question and select the carrier that answers it. Use existing semantic widgets before custom drawings. The renderer's vocabulary is a set of available representations, not a checklist of required document content.

| Information                                 | Representation                                                                             |
| ------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Purpose, rationale, limits                  | Short prose and applicable goal, no-goal, principle, or invariant blocks                   |
| Responsibilities and dependencies           | `diagram`; label relationships and identify external participants                          |
| A short inventory of major responsibilities | `components`, or a compact table                                                           |
| Important concepts and relationships        | Prose or a small model diagram; `entity` only when its structured fields add understanding |
| An important lifecycle                      | `state-machine`, with its meaning and abstraction limits explained                         |
| Cooperation over time                       | `sequence`, or a short numbered walkthrough                                                |
| A comparison                                | A table; a chart only for meaningful quantitative evidence                                 |
| A drawing no semantic carrier expresses     | `figure-block` with a raw `typst` body; Markdown retains the source                        |

- Use solved diagram layout by default. Use `diagram-native` when deliberate positioning conveys meaning. Keep ownership, deployment, and temporal views separate when combining them would obscure the relationships.
- Give each drawing one question, a readable scope, and meaningful labels. Explain consequential delivery or failure assumptions in adjacent text; an arrow alone does not establish them. Use color only with labels or other marks that survive grayscale.
- Custom figures with raw `typst` bodies render as drawings in PDF and fenced source in Markdown. Explain the drawing's architectural meaning in its caption or adjacent prose; the source preserves the drawing but does not replace that explanation. Ordinary evaluated figure bodies and embedded SVGs remain unsupported by the Markdown projector.
- Ensure Markdown carries every claim communicated visually. Inspect its actual projection, including direction, boundaries, transition meaning, and any fenced figure source. Use supported semantic carriers when they express the information directly.
- Add a new widget only for a recurring information need that existing carriers cannot represent faithfully. A new widget needs a defined meaning, a Markdown representation, validation contracts, and gallery coverage. Do not expand the renderer as part of a documentation task without that scope being requested.

## Keep the layer useful as code changes

- Update the layer when purpose, responsibility, ownership, major interaction, architectural constraint, or consequential trade-off changes. Ordinary renames, internal helper extraction, and nonarchitectural field additions should normally leave the explanation unchanged.
- Keep current architecture distinct from proposed changes and historical decisions. Reuse the layer's declared pending and decision artifacts instead of introducing a second plan or implementation ledger. Do not fabricate an ADR for rationale discovered only by inference.
- When scope reduction removes detail, preserve unique rationale, important guarantees, and incoming references. Do not discard architectural meaning merely because it is technical. Follow the owner of a generated artifact rather than editing its output.

## Validate the result

- Confirm that the Use cases and scope and Domain model sections are present in both PDF and Markdown. Check that they identify users or consumers, their goals and observable outcomes, scope boundaries, and the main domain concepts and relationships.
- Review the document as a newcomer: can the reader connect a consumer use case to the domain model and the cooperating abstractions, explain important constraints, and find where to investigate a change? A passing format gate cannot answer these questions.
- Check selected implementation claims against their evidence. Label unresolved claims honestly. A well-formed invariant block does not prove that the implementation enforces the invariant.
- Render through the host's pinned renderer and run its declared gate. Inspect affected PDF pages at normal reading scale for legibility, clipping, broken relationships, and missing context. Report an unavailable check or inspection rather than claiming it passed.
- Produce and inspect the semantic Markdown through the pinned `context` app. Use the manifest and exact section extraction for large layers. Check that PDF and Markdown preserve the same architectural claims and canonical terminology.
- Report the authored sources, rendered outputs, checks actually performed, and remaining uncertainties. Do not treat successful documentation as acceptance of the architecture or verification of every implementation behavior.

## Depth example

- For a payment application, document that Orders owns the purchase lifecycle, Payments owns settlement, confirmation advances an order, and repeated requests must not create repeated charges when those claims are supported. Show the collaboration and identify where to inspect each responsibility.
- Leave table columns, handler names, retry constants, and the full provider API in their authoritative implementation or reference. Include a specific retry or storage constraint only if it changes the architectural guarantee or explains a consequential trade-off.
- For a parser library, explain the input-to-result model, the host's responsibilities, error semantics, and whether parsing owns state or performs I/O. A service diagram, database model, or business-domain partition is unnecessary unless the library actually has those characteristics.
