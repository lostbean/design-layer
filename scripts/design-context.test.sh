#!/usr/bin/env bash
set -euo pipefail

WORK="$(mktemp -d "${TMPDIR:-/tmp}/design-context-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

LAYER="$WORK/docs/design"
mkdir -p "$LAYER/.render" "$LAYER/alpha" "$LAYER/zeta"
bash ./scripts/render-project schema/design-schema.json "$LAYER/.render" >/dev/null

cat >"$LAYER/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Minimal]
#let styled = [#text(weight: "bold")[Styled prose.]]
#let body = [#section(title: "Root overview", lead: [The root overview cites #term("term-zeta").], visual: [#how-to-read()], body: [Root prose. Root overview. #goal(title: "Build context", lens: "composition", since: "2026-01-01", adr: 80)[Goal prose.] #goal(title: "Multi-lens", lens: ("state", "composition"))[Multi-lens prose.] #goal(title: "No lens")[#styled] #no-goal(title: "Out of scope")[Excluded.] #invariant(title: "Data is valid", enforcement: "mechanism", lens: "invariants")[Valid data.] #principle(title: "Prefer clarity", lens: ("modeling", "composition"))[Clear design.] #behavior(title: "Projection order", area: "Context loading", level: "interface", lens: ("state", "composition"))[#given[Sources are complete.] #when[The command runs.] #then[The projection is emitted.] #then[The estimate is emitted.]] #points([First point.], [Second point.]) #subsection(title: "Subsection")[Subsection prose.] #notes(title: "Notes")[Notes prose.] Inline #ctx("alpha") #adr(42) #lens-pill("state") #pill("state", "composition") #link("https://example.test")[a link] #emph[emphasis] #strong[strong] #raw("inline") #raw(block: true, lang: "text", "raw block") #smartquote(double: true)quoted#smartquote(double: true) #sym.arrow.r #info(title: "Info", tint: "teal")[Info body.] #warning(title: "Warning", tint: "amber")[Warning body.] #answers(title: "Answers", accent: "violet", responsibility: [Own it.], interactions: [Call it.], failure: [Fails.]) #components(accent: "teal", cols: "2", component(name: "First", lens: "state", mission: [First mission.], tint: "rose", answers: answers-data(responsibility: [First resp.], failure: [First fail.]), body: [First body.]), component(name: "Second", mission: [Second mission.], answers: answers-data(interface: [Second interface.]), body: [Second body.])) #contract(name: "Agreement", lens: "composition", mission: [Contract mission.], accent: "amber", tint: "violet", answers: answers-data(invariants: [Contract inv.]), body: [Contract body.]) #entity(id: "booking", title: "Booking", description: [A booking entity.], kind: "aggregate", owner: "Scheduling", lifecycle: "stateful", domain: "Ordering", lens: "state", tint: "rose")[#attribute(id: "status", name: "Status", type: "Booking status", provenance: "derived", state-type: "status-type", state-machine: "booking-flow")[Current status.] #attribute(name: "Customer", type: [#term("term-zeta") from #ctx("alpha")], provenance: "authored")[Customer field.] #relates(cardinality: "1 : 0..n")[Booking relationship.]] #cards(tint: "teal", items: ((title: "First card", tint: "rose", body: [Card one.]), (title: "Second card", body: [Card two.]))) #md-table(3, ([Name], [Meaning | pipe], [Notes], [alpha], [line one #linebreak() line two], [tail])) #coverage(("part/a", "captured"), ("part/b", "out-of-scope", "Reason")) #stat-grid(tiles: (stat-tile(value: "12", label: "Rows", delta: "+2", dir: "up"), stat-tile(value: "9", label: "Errors"))) #code-block("python", "def f():\n  return 1  # x  !")])]
 #let body = body + [#section(title: "Math and procedure", body: [Inline $x_i^2 + sqrt(y)$. #formula(id: "budget", title: "Budget", numbered: true, notation: (([$A$], [availability]), ([$T$], [time])), caption: [Budget caption.])[$A = 1 - frac(D, T)$] See @formula-budget. #pseudocode(id: "decision", title: "Decision", inputs: ([request],), outputs: ([result],), steps: (pseudo-step([read request]), pseudo-if([valid], (pseudo-for([item], [items], (pseudo-step([check item]),)),), otherwise: (pseudo-return([error]),)), pseudo-repeat([complete], (pseudo-step([advance]),)), pseudo-return([result])), caption: [Procedure caption.]) See @pseudocode-decision. #code-block("text", "literal ``` marker") #code-block("rust", ```rust
fn main() {}
```)])]
 #let body = body + [#section(title: "Semantic families", visual: [#how-to-read()], notes: [#notes(title: "Section note")[Section note body.]], body: [#diagram(altitude: "L3", title: "System map", caption: [Map caption.], accent: "violet", viewpoint: "runtime", groups: ((id: "core", label: "Core", kind: "bounded-context", tint: "violet"),), nodes: ((id: "source", label: "Source", sub: "authored", kind: "entity", group: "core", tint: "blue"), (id: "consumer", label: "Consumer", kind: "external-system", group: "core", external: true)), edges: ((from: "source", to: "consumer", relation: "dependency", label: "loads", style: "dashed"),)) #diagram-native(altitude: "L3", title: "Positioned path", spacing: (12mm, 8mm), nodes: ((id: "a", pos: (0, 0), label: "A"), (id: "b", pos: (1, 0), label: "B")), edges: (("a", "b", "step", "dashed"),)) #chart(kind: "line", title: "Trend", caption: [Chart caption.], unit: "rows", points: (("alpha", 1), ("beta", 2))) #state-type(id: "status-type", title: "Status", variants: ((id: "draft", description: [Not submitted.]), (id: "done", description: [Accepted.]))) #state-machine(id: "booking-flow", subject: "booking", state-field: "status", state-type: "status-type", title: "Booking flow", caption: [Flow caption.], states: ("draft", "done"), transitions: (("draft", "done", "approve"),), initial: "draft", accepting: ("done",)) #sequence(title: "Exchange", caption: [Exchange caption.], participants: ((id: "client", label: "Client", shape: "actor"), (id: "api", label: "API", shape: "boundary")), steps: (seq-msg("client", "api", "request", dashed: true, activate: true), seq-note("api", [Received.], side: "left"), seq-alt("valid", (seq-msg("api", "client", "ok"),), otherwise: (seq-msg("api", "client", "error", dashed: true),)), seq-loop("retry", (seq-msg("client", "api", "again"),)), seq-opt("cached", (seq-msg("api", "client", "hit", deactivate: true),)))) #pending-ledger(pending-entry(title: "Need", kind: "verify", since: "2026-01-01", adr: 80)[Verify body.], pending-entry(title: "Question", kind: "ruling", since: "2026-02-01")[Question body.])])]
 #let body = body + [#sequence(title: "Empty exchange", caption: [No steps.], participants: (), steps: ())]
 #let body = body + [#section(title: "Visual order", visual: [#block[#how-to-read() #chart(kind: "bar", title: "Visual chart", points: (("one", 1),))]], notes: [#notes(title: "Visual note")[Visual note body.]], body: [Visual body.] )]
 #let body = body + [#pending-ledger(pending-entry(title: "Reference", kind: "verify", since: "2026-03-01", adr: [#adr(80)])[Reference body.])]
EOF

cat >"$LAYER/alpha/design.typ" <<'EOF'
#import "../.render/designlib.typ": *
#let title = [Alpha context]
#let body = [#section(title: "Alpha section", lead: [Alpha lead.], body: [Alpha body. #goal(title: "Alpha goal")[Alpha goal body.]])]
EOF

cat >"$LAYER/zeta/design.typ" <<'EOF'
#import "../.render/designlib.typ": *
#let title = [Zeta context]
#let body = [#section(title: "Zeta section", lead: [Zeta lead.], body: [Zeta body.])]
EOF

cat >"$LAYER/alpha/CONTEXT.typ" <<'EOF'
#let terms = (
  (slug: "term-alpha", title: [Alpha term], body: [The #term("term-zeta") definition. #{ import "../refs.typ": cite; cite(7) }]),
)
EOF

cat >"$LAYER/refs.typ" <<'EOF'
#let cite(number) = [ADR-#number]
EOF

cat >"$LAYER/zeta/CONTEXT.typ" <<'EOF'
#let terms = (
  (slug: "term-zeta", title: [Zeta term], body: [The zeta definition for #ctx("alpha"). #raw(block: true, lang: "text", "  term code  !")]),
)
EOF

cat >"$WORK/docs/CONTEXT-MAP.md" <<'EOF'
# Context map

| Context | Owner |
| --- | --- |
| alpha | Alpha team |
EOF

cat >"$WORK/docs/COVERAGE.md" <<'EOF'
# Coverage map

| Part | Status |
| --- | --- |
| root | captured |
EOF

expected="$WORK/expected.md"
cat >"$expected" <<'EOF'
# Minimal

## Root overview

The root overview cites Zeta term.

Root prose. Root overview.

### goal: Build context

Lens: composition

Since: 2026-01-01

ADR: 80

Goal prose.

### goal: Multi-lens

Lens: state, composition

Multi-lens prose.

### goal: No lens

Styled prose.

### no-goal: Out of scope

Excluded.

### invariant: Data is valid

Lens: invariants

Enforcement: mechanism

Valid data.

### principle: Prefer clarity

Lens: modeling, composition

Clear design.

### behavior: Projection order

Area: Context loading

Level: interface

Lens: state, composition

- Given: Sources are complete.
- When: The command runs.
- Then: The projection is emitted.
- Then: The estimate is emitted.

- First point.
- Second point.

### Subsection

Subsection prose.

### Notes: Notes

Notes prose.

Inline alpha ADR-0042 state state, composition [a link](https://example.test) *emphasis* **strong** `inline`

```text
raw block
```
"quoted" →

### info: Info

Info body.

### warning: Warning

Warning body.

### answers: Answers

Responsibility: Own it.

Interactions: Call it.

Failure: Fails.

### components

#### component: First

Mission: First mission.

Lens: state

Responsibility: First resp.

Failure: First fail.

First body.

#### component: Second

Mission: Second mission.

Interface: Second interface.

Second body.

### contract: Agreement

Mission: Contract mission.

Lens: composition

Invariants: Contract inv.

Contract body.

### entity: Booking

ID: booking

Kind: aggregate

Owner: Scheduling

Lifecycle: stateful

Domain: Ordering

Lens: state

Description: A booking entity.

#### attribute: Status

ID: status

Type: Booking status

Provenance: derived

State type: status-type

State machine: booking-flow

Current status.

#### attribute: Customer

Type: Zeta term from alpha

Provenance: authored

Customer field.

#### relates: 1: 0..n

Booking relationship.

### cards

#### card: First card

Card one.

#### card: Second card

Card two.

### md-table

| Name | Meaning \| pipe | Notes |
| --- | --- | --- |
| alpha | line one <br> line two | tail |

### coverage

| Part | Status | Reason |
| --- | --- | --- |
| part/a | captured | |
| part/b | out-of-scope | Reason |

### stat-grid

| Value | Label | Delta | Direction |
| --- | --- | --- | --- |
| 12 | Rows | +2 | up |
| 9 | Errors | | |

```python
def f():
  return 1  # x  !
```

## Math and procedure

Inline $x^{2}_{i} + sqrt(y)$.

### formula: Budget

ID: budget

Numbered: true

Expression:
$A = 1 − (D) / (T)$

Notation:
| Symbol | Meaning |
| --- | --- |
| $A$ | availability |
| $T$ | time |

Caption: Budget caption.
See [formula-budget](#formula-budget).

### pseudocode: Decision

ID: decision

Inputs:
- request

Outputs:
- result

Procedure:
- DO read request
- IF valid
  - FOR EACH item IN items
    - DO check item
  - END FOR
- OTHERWISE
  - RETURN error
- END IF
- REPEAT
  - DO advance
- UNTIL complete
- RETURN result

Caption: Procedure caption.
See [pseudocode-decision](#pseudocode-decision).

````text
literal ``` marker
````

```rust
fn main() {}
```

## Semantic families

### Notes: Section note

Section note body.

### diagram: System map

Altitude: L3

Viewpoint: runtime

Caption: Map caption.

#### group: Core

ID: core

Kind: bounded-context

#### node: Source

ID: source

Sub: authored

Kind: entity

Group: core

#### node: Consumer

ID: consumer

Kind: external-system

Group: core

External: true

#### edges

- source -> consumer
  Relation: dependency
  Label: loads

### diagram-native: Positioned path

Altitude: L3

#### node: A

ID: a

#### node: B

ID: b

#### edges

- a -> b
  Label: step

### chart: Trend

Kind: line

Caption: Chart caption.

Unit: rows

| Label | Value |
| --- | --- |
| alpha | 1 |
| beta | 2 |

### state-type: Status

ID: status-type

Variants:
- draft: Not submitted.
- done: Accepted.

### state-machine: Booking flow

ID: booking-flow

Subject: booking

State field: status

State type: status-type

Caption: Flow caption.

Initial: draft

Accepting: done

States:
- draft
- done

Transitions:
- draft -> done: approve

### sequence: Exchange

Caption: Exchange caption.

Participants:
- client: Client
- api: API

Steps:
- message: client -> api: request [activate]
- note on api: Received.
- alt: valid
  - message: api -> client: ok
  - otherwise:
    - message: api -> client: error
- loop: retry
  - message: client -> api: again
- opt: cached
  - message: api -> client: hit [deactivate]

### pending-ledger

#### pending: Need

Kind: verify

Since: 2026-01-01

ADR: 80

Verify body.

#### pending: Question

Kind: ruling

Since: 2026-02-01

Question body.

## sequence: Empty exchange

Caption: No steps.

Participants:

Steps:

## Visual order

### chart: Visual chart

Kind: bar

| Label | Value |
| --- | --- |
| one | 1 |

### Notes: Visual note

Visual note body.

Visual body.

## pending-ledger

### pending: Reference

Kind: verify

Since: 2026-03-01

ADR: ADR-0080

Reference body.

## Alpha context

### Alpha section

Alpha lead.

Alpha body.

#### goal: Alpha goal

Alpha goal body.

## Zeta context

### Zeta section

Zeta lead.

Zeta body.

## Vocabulary: alpha

### term-alpha — Alpha term

Owner: alpha

The Zeta term definition. ADR-7

## Vocabulary: zeta

### term-zeta — Zeta term

Owner: zeta

The zeta definition for alpha.

```text
  term code  !
```

<!-- source: docs/CONTEXT-MAP.md -->

# Context map

| Context | Owner |
| --- | --- |
| alpha | Alpha team |

<!-- source: docs/COVERAGE.md -->

# Coverage map

| Part | Status |
| --- | --- |
| root | captured |
EOF

default="$WORK/default.md"
before_files="$(find "$LAYER" -type f ! -path "$LAYER/.render/*" | sort)"
./scripts/design-context "$LAYER" >"$default"
if ! cmp -s "$expected" "$default"; then
  echo "design-context: corpus projection is not complete" >&2
  diff -u --text "$expected" "$default" >&2 || true
  exit 1
fi

output="$WORK/output.md"
./scripts/design-context "$LAYER" --output "$output"
if ! cmp -s "$default" "$output"; then
  echo "design-context: --output bytes differ from default stdout" >&2
  exit 1
fi

second="$WORK/default-second.md"
./scripts/design-context "$LAYER" >"$second"
if ! cmp -s "$default" "$second"; then
  echo "design-context: repeated default runs differ" >&2
  exit 1
fi
after_files="$(find "$LAYER" -type f ! -path "$LAYER/.render/*" | sort)"
if [[ $before_files != "$after_files" ]]; then
  echo "design-context: default mode created a layer file" >&2
  diff -u <(printf '%s\n' "$before_files") <(printf '%s\n' "$after_files") >&2 || true
  exit 1
fi

estimate="$WORK/estimate.json"
./scripts/design-context "$LAYER" --estimate >"$estimate"
python3 - "$estimate" "$default" <<'PY'
import json
import pathlib
import sys

estimate = json.loads(pathlib.Path(sys.argv[1]).read_text())
data = pathlib.Path(sys.argv[2]).read_bytes()
text = data.decode()
expected = {
    "utf8_bytes": len(data),
    "characters": len(text),
    "words": len(text.split()),
    "lines": text.count("\n"),
    "likely_tokens": (len(data) + 3) // 4,
    "conservative_tokens": (len(data) + 2) // 3,
    "likely_tokens_method": "ceil(utf8_bytes/4)",
    "conservative_tokens_method": "ceil(utf8_bytes/3)",
}
if estimate != expected:
    raise SystemExit(f"estimate mismatch: {estimate!r} != {expected!r}")
PY

assert_failure() {
  expected_status="$1"
  label="$2"
  shift 2
  stdout_file="$WORK/$label.stdout"
  stderr_file="$WORK/$label.stderr"
  set +e
  "$@" >"$stdout_file" 2>"$stderr_file"
  actual_status=$?
  set -e
  if [[ $actual_status -ne $expected_status ]]; then
    echo "design-context: $label returned $actual_status, expected $expected_status" >&2
    cat "$stderr_file" >&2
    exit 1
  fi
  if [[ -s $stdout_file ]]; then
    echo "design-context: $label emitted stdout on failure" >&2
    cat "$stdout_file" >&2
    exit 1
  fi
}

saved_context_map="$WORK/docs/CONTEXT-MAP.md.saved"
mv "$WORK/docs/CONTEXT-MAP.md" "$saved_context_map"
missing_map_output="$WORK/missing-context-map.md"
assert_failure 1 missing-context-map ./scripts/design-context "$LAYER" --output "$missing_map_output"
if [[ -e $missing_map_output ]]; then
  echo "design-context: missing context map created a usable output file" >&2
  exit 1
fi
mv "$saved_context_map" "$WORK/docs/CONTEXT-MAP.md"

saved_coverage="$WORK/docs/COVERAGE.md.saved"
mv "$WORK/docs/COVERAGE.md" "$saved_coverage"
missing_coverage_output="$WORK/missing-coverage.md"
assert_failure 1 missing-coverage ./scripts/design-context "$LAYER" --output "$missing_coverage_output"
if [[ -e $missing_coverage_output ]]; then
  echo "design-context: missing coverage map created a usable output file" >&2
  exit 1
fi
mv "$saved_coverage" "$WORK/docs/COVERAGE.md"

assert_failure 2 help ./scripts/design-context --help
assert_failure 2 missing-root ./scripts/design-context
assert_failure 2 unknown-option ./scripts/design-context "$LAYER" --unknown
assert_failure 2 missing-output-path ./scripts/design-context "$LAYER" --output
assert_failure 2 conflicting-modes ./scripts/design-context "$LAYER" --estimate --output "$WORK/never.md"
assert_failure 2 extra-positional ./scripts/design-context "$LAYER" extra

bad_layer="$WORK/bad-layer"
mkdir -p "$bad_layer/.render"
cp -R "$LAYER/.render/." "$bad_layer/.render/"
cat >"$bad_layer/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Bad]
#let body = [#unknown-function()]
EOF
bad_output="$WORK/bad-output.md"
assert_failure 1 semantic-violation ./scripts/design-context "$bad_layer" --output "$bad_output"
if [[ -e $bad_output ]]; then
  echo "design-context: semantic failure created a usable output file" >&2
  exit 1
fi

unknown_term_layer="$WORK/unknown-term"
mkdir -p "$unknown_term_layer/.render"
cp -R "$LAYER/.render/." "$unknown_term_layer/.render/"
cat >"$unknown_term_layer/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Unknown term]
#let body = [A #term("term-missing") reference.]
EOF
unknown_term_output="$WORK/unknown-term.md"
assert_failure 1 unknown-term-reference ./scripts/design-context "$unknown_term_layer" --output "$unknown_term_output"
if [[ -e $unknown_term_output ]]; then
  echo "design-context: unknown term created a usable output file" >&2
  exit 1
fi

unknown_context_layer="$WORK/unknown-context"
mkdir -p "$unknown_context_layer/.render"
cp -R "$LAYER/.render/." "$unknown_context_layer/.render/"
cat >"$unknown_context_layer/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Unknown context]
#let body = [An #ctx("context-missing") reference.]
EOF
unknown_context_output="$WORK/unknown-context.md"
assert_failure 1 unknown-context-reference ./scripts/design-context "$unknown_context_layer" --output "$unknown_context_output"
if [[ -e $unknown_context_output ]]; then
  echo "design-context: unknown context created a usable output file" >&2
  exit 1
fi

stray_clause_layer="$WORK/stray-clause"
mkdir -p "$stray_clause_layer/.render"
cp -R "$LAYER/.render/." "$stray_clause_layer/.render/"
cat >"$stray_clause_layer/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Stray clause]
#let body = [#given[This clause is not inside a behavior.]]
EOF
stray_clause_output="$WORK/stray-clause.md"
assert_failure 1 stray-clause ./scripts/design-context "$stray_clause_layer" --output "$stray_clause_output"
if [[ -e $stray_clause_output ]]; then
  echo "design-context: stray clause created a usable output file" >&2
  exit 1
fi

unsupported_layer="$WORK/unsupported-section"
mkdir -p "$unsupported_layer/.render"
cp -R "$LAYER/.render/." "$unsupported_layer/.render/"
cat >"$unsupported_layer/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Unsupported section fields]
#let body = [#section(
  title: "Carries unsupported fields",
  visual: [#diagram(src: "digraph { alpha -> beta }")],
  notes: [#notes(title: "Callout")[Note meaning.]],
  body: [Body meaning.],
)]
EOF
unsupported_output="$WORK/unsupported-section.md"
assert_failure 1 unsupported-section-fields ./scripts/design-context "$unsupported_layer" --output "$unsupported_output"
if [[ -e $unsupported_output ]]; then
  echo "design-context: unsupported section fields created a usable output file" >&2
  exit 1
fi

unsupported_math_layer="$WORK/unsupported-math"
mkdir -p "$unsupported_math_layer/.render"
cp -R "$LAYER/.render/." "$unsupported_math_layer/.render/"
cat >"$unsupported_math_layer/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Unsupported math]
#let body = [The matrix is $mat(1, 2; 3, 4)$.]
EOF
unsupported_math_output="$WORK/unsupported-math.md"
assert_failure 1 unsupported-math ./scripts/design-context "$unsupported_math_layer" --output "$unsupported_math_output"
if [[ -e $unsupported_math_output ]]; then
  echo "design-context: unsupported math created a usable output file" >&2
  exit 1
fi

unresolved_target_layer="$WORK/unresolved-target"
mkdir -p "$unresolved_target_layer/.render"
cp -R "$LAYER/.render/." "$unresolved_target_layer/.render/"
cat >"$unresolved_target_layer/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Unresolved target]
#let body = [See @formula-missing.]
EOF
unresolved_target_output="$WORK/unresolved-target.md"
assert_failure 1 unresolved-target ./scripts/design-context "$unresolved_target_layer" --output "$unresolved_target_output"
if [[ -e $unresolved_target_output ]]; then
  echo "design-context: unresolved target created a usable output file" >&2
  exit 1
fi

duplicate_target_layer="$WORK/duplicate-target"
mkdir -p "$duplicate_target_layer/.render"
cp -R "$LAYER/.render/." "$duplicate_target_layer/.render/"
cat >"$duplicate_target_layer/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Duplicate target]
#let body = [#formula(id: "same")[$A = 1$] #formula(id: "same")[$B = 2$]]
EOF
duplicate_target_output="$WORK/duplicate-target.md"
assert_failure 1 duplicate-target ./scripts/design-context "$duplicate_target_layer" --output "$duplicate_target_output"
if [[ -e $duplicate_target_output ]]; then
  echo "design-context: duplicate target created a usable output file" >&2
  exit 1
fi

figure_layer="$WORK/figure-layer"
mkdir -p "$figure_layer/.render"
cp -R "$LAYER/.render/." "$figure_layer/.render/"
cat >"$figure_layer/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Unrepresentable figure]
#let body = [#figure-block(caption: [Figure meaning], uses: ("cetz"))[Figure body.]]
EOF
figure_output="$WORK/figure.md"
assert_failure 1 figure-block ./scripts/design-context "$figure_layer" --output "$figure_output"
if [[ -e $figure_output ]]; then
  echo "design-context: figure block created a usable output file" >&2
  exit 1
fi

svg_layer="$WORK/svg-layer"
mkdir -p "$svg_layer/.render"
cp -R "$LAYER/.render/." "$svg_layer/.render/"
cat >"$svg_layer/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Unrepresentable SVG]
#let body = [#embedded-svg(file: "drawing.svg")[SVG meaning.]]
EOF
svg_output="$WORK/svg.md"
assert_failure 1 embedded-svg ./scripts/design-context "$svg_layer" --output "$svg_output"
if [[ -e $svg_output ]]; then
  echo "design-context: embedded SVG created a usable output file" >&2
  exit 1
fi

surplus_layer="$WORK/surplus-field"
mkdir -p "$surplus_layer/.render"
cp -R "$LAYER/.render/." "$surplus_layer/.render/"
cat >"$surplus_layer/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Surplus field]
#let body = [#semantic("goal", fields: (title: [Goal], body: [Body.], surprise: [Lost.]))]
EOF
assert_failure 1 surplus-semantic-field ./scripts/design-context "$surplus_layer"

invalid_state_layer="$WORK/invalid-state-link"
mkdir -p "$invalid_state_layer/.render"
cp -R "$LAYER/.render/." "$invalid_state_layer/.render/"
cat >"$invalid_state_layer/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Invalid state link]
#let body = [#entity(id: "booking", title: "Booking", description: [A booking.], kind: "aggregate", owner: "Team", lifecycle: "stateful", domain: "Sales")[#attribute(id: "status", name: "Status", type: "Status", provenance: "derived", state-type: "missing-type", state-machine: "missing-machine")[State.]]]
EOF
assert_failure 1 invalid-state-link ./scripts/design-context "$invalid_state_layer"

single_docs="$WORK/single-docs"
single_layer="$single_docs/design"
mkdir -p "$single_layer/.render"
cp -R "$LAYER/.render/." "$single_layer/.render/"
cat >"$single_layer/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Single context]
#let body = [#goal(title: "Stay whole")[Single context body.]]
EOF
cat >"$single_layer/CONTEXT.typ" <<'EOF'
#let terms = ((slug: "term-whole", title: [Whole], body: [One vocabulary.]),)
EOF
cat >"$single_docs/COVERAGE.md" <<'EOF'
# Coverage

| Part | Status |
| --- | --- |
| root | captured |
EOF
single_output="$WORK/single.md"
./scripts/design-context "$single_layer" --output "$single_output"
if grep -q 'source: docs/CONTEXT-MAP.md' "$single_output" || ! grep -q 'source: docs/COVERAGE.md' "$single_output"; then
  echo "design-context: single-context map selection is wrong" >&2
  exit 1
fi

existing_output="$WORK/existing.md"
printf 'keep me\n' >"$existing_output"
assert_failure 2 existing-output ./scripts/design-context "$LAYER" --output "$existing_output"
if [[ $(cat "$existing_output") != "keep me" ]]; then
  echo "design-context: existing output was overwritten" >&2
  exit 1
fi

assert_failure 2 output-write-failure ./scripts/design-context "$LAYER" --output "$WORK/no-parent/output.md"

echo "design-context: corpus order, maps, output, and estimate are deterministic"
