#!/usr/bin/env bash
set -euo pipefail

# Self-test for scripts/layer-integrity.
#
# Builds throwaway fixture repos under a single mktemp -d and asserts the
# checker's exit code plus a distinguishing report string per scenario:
#   (a) clean single-context layer                     -> exit 0
#   (b) clean multi-context layer                      -> exit 0
#   (c) dangling term link (anchor absent)             -> exit 1
#   (d) near-miss anchors (#trem- typo, bare #term-)   -> exit 1 (fail-closed)
#   (e) ADR filename/anchor NNNN mismatch              -> exit 1
#   (f) CONTEXT.md missing from CONTEXT-MAP.md         -> exit 1
#   (g) a per-context design.pdf (the layer renders as ONE) -> exit 1
#   (h) duplicate term id within one CONTEXT.md        -> exit 1
#   (i) empty repo / no design layer                   -> exit 2 ("no design layer")
#   (j) usage error: too many args                     -> exit 2
#   (k) unresolvable schema (DESIGN_SCHEMA points off) -> exit 2
#   (s) copy-installed script reads its script-sibling schema -> exit 0
#   (t) generation debris (</content> line) in an ADR / COVERAGE.md -> exit 1
#   (u) debris shape inside a fenced code block -> exit 0 (documentation)
#   (v) layer files colocated in a source directory -> exit 1 (mishomed)
#   (w) CONTEXT-MAP.md at repo root instead of docs/ -> exit 1 (mishomed)
#   (x) staleness advisory fires past the threshold -> exit 0 + advisory line
#   (y) staleness advisory silent under the threshold / without the schema key
#
# Depends on no repo files beyond the checker + schema and leaves no
# artifacts behind. Accepts an optional path to the checker as $1
# (default: resolved from this script's location).

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="${1:-$HERE/layer-integrity}"

if [ ! -x "$CHECK" ]; then
  echo "error: checker not found or not executable: $CHECK" >&2
  exit 2
fi

# The checker must resolve the schema from its own location; make sure a
# stray environment override does not leak into the scenarios.
unset DESIGN_SCHEMA || true

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

# assert_exit <expected-code> <label> -- <cmd...>
# Runs the command, captures exit code and combined output, checks the code,
# and stashes the output in LAST_OUT for follow-up content assertions.
LAST_OUT=""
assert_exit() {
  local expected="$1" label="$2"
  shift 3 # drop expected, label, and the literal "--"
  local out code
  set +e
  out="$("$@" 2>&1)"
  code=$?
  set -e
  LAST_OUT="$out"
  if [ "$code" -eq "$expected" ]; then
    echo "PASS: $label (exit $code)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label -- expected exit $expected, got $code"
    echo "      output: $out"
    fail=$((fail + 1))
  fi
}

# assert_contains <needle> <label> -- checks LAST_OUT contains needle.
assert_contains() {
  local needle="$1" label="$2"
  if printf '%s' "$LAST_OUT" | grep -qF -- "$needle"; then
    echo "PASS: $label"
    pass=$((pass + 1))
  else
    echo "FAIL: $label -- output did not contain '$needle'"
    echo "      output: $LAST_OUT"
    fail=$((fail + 1))
  fi
}

# assert_not_contains <needle> <label> -- checks LAST_OUT lacks needle.
assert_not_contains() {
  local needle="$1" label="$2"
  if printf '%s' "$LAST_OUT" | grep -qF -- "$needle"; then
    echo "FAIL: $label -- output unexpectedly contained '$needle'"
    echo "      output: $LAST_OUT"
    fail=$((fail + 1))
  else
    echo "PASS: $label"
    pass=$((pass + 1))
  fi
}

# build_single <root> -- a healthy single-context layer:
#   <root>/docs/design/CONTEXT.md          two valid term anchors
#   <root>/docs/design/design.md           links a term + an ADR anchor, plus
#                                          ignorable links (external, pure
#                                          fragment, non-design-ish relative)
#   <root>/docs/design/design-layer.pdf    the layer's ONE rendered document
#   <root>/docs/adr/0001-first-decision.md one anchor, in lockstep
build_single() {
  local root="$1"
  mkdir -p "$root/docs/design" "$root/docs/adr"

  cat >"$root/docs/design/CONTEXT.md" <<'EOF'
# Glossary

### Drift {#term-drift}

The gap between the design layer and the implementation.

### Work Order {#term-work-order}

A self-contained brief handed to a coding agent.
EOF

  cat >"$root/docs/adr/0001-first-decision.md" <<'EOF'
# 0001 — First decision

<a id="adr-0001"></a>

## Status

Accepted.

## Decision

Decisions are recorded as an append-only ADR ledger.
EOF

  cat >"$root/docs/design/design.md" <<'EOF'
# Design

## 00 Foundation

The system tracks [drift](CONTEXT.md#term-drift) between artifacts.
The ledger holds the argument: [ADR-0001](../adr/0001-first-decision.md#adr-0001).

## 01 System at a glance

An [external spec](https://example.com/spec), a pure fragment
[back to top](#00-foundation), and a non-design-ish relative link to a
[missing note](../notes/plan.md) are all ignored by the checker.
EOF

  # The layer's rendered document. Its CONTENT is irrelevant to every check
  # here — the artifact is binary and carries no anchors to index — so a stub
  # stands in for a real render. What matters is its NAME and its PLACE.
  printf '%%PDF-1.7 stub\n' >"$root/docs/design/design-layer.pdf"
}

# build_multi <root> -- a healthy multi-context layer:
#   <root>/docs/CONTEXT-MAP.md             exact links to both CONTEXT.md
#   <root>/docs/design/design.md           links both context design docs + ADR
#   <root>/docs/design/design-layer.pdf    the layer's ONE rendered document
#   <root>/docs/adr/0001-first-decision.md one anchor, in lockstep
#   <root>/docs/design/alpha/{design.md,CONTEXT.md}
#   <root>/docs/design/beta/{design.md,CONTEXT.md}
#   (no per-context PDF: a context renders as a chapter, not its own document)
build_multi() {
  local root="$1"
  mkdir -p "$root/docs/design/alpha" "$root/docs/design/beta" "$root/docs/adr"

  cat >"$root/docs/CONTEXT-MAP.md" <<'EOF'
# Context Map

- [Alpha](./design/alpha/CONTEXT.md) — the alpha vocabulary.
- [Beta](./design/beta/CONTEXT.md) — the beta vocabulary.
EOF

  cat >"$root/docs/adr/0001-first-decision.md" <<'EOF'
# 0001 — First decision

<a id="adr-0001"></a>

Decisions are recorded as an append-only ADR ledger.
EOF

  cat >"$root/docs/design/design.md" <<'EOF'
# Design

## 00 Foundation

The ledger holds the argument: [ADR-0001](../adr/0001-first-decision.md#adr-0001).

## 01 System at a glance

- [Alpha context design](./alpha/design.md)
- [Beta context design](./beta/design.md)
EOF

  # The layer's rendered document. Its CONTENT is irrelevant to every check
  # here — the artifact is binary and carries no anchors to index — so a stub
  # stands in for a real render. What matters is its NAME and its PLACE.
  printf '%%PDF-1.7 stub\n' >"$root/docs/design/design-layer.pdf"

  cat >"$root/docs/design/alpha/CONTEXT.md" <<'EOF'
# Alpha

### Alpha Thing {#term-alpha-thing}

The one thing alpha owns.
EOF

  cat >"$root/docs/design/alpha/design.md" <<'EOF'
# Alpha design

Built around the [alpha thing](CONTEXT.md#term-alpha-thing).
EOF

  cat >"$root/docs/design/beta/CONTEXT.md" <<'EOF'
# Beta

### Beta Thing {#term-beta-thing}

The one thing beta owns.
EOF

  cat >"$root/docs/design/beta/design.md" <<'EOF'
# Beta design

Built around the [beta thing](./CONTEXT.md#term-beta-thing).
EOF
}

# --- Scenario (a): clean single-context -> exit 0 ---------------------------
SA="$TMP/a"
build_single "$SA"
assert_exit 0 "clean single-context layer" -- "$CHECK" "$SA"
assert_contains "layer-integrity OK" "clean single-context prints the OK summary"

# Default repo-root is "." — running from inside the fixture, no args.
assert_exit 0 "default repo-root is the cwd" -- bash -c 'cd "$1" && "$0"' "$CHECK" "$SA"
assert_contains "layer-integrity OK" "default-root run prints the OK summary"

# --- Scenario (b): clean multi-context -> exit 0 -----------------------------
SB="$TMP/b"
build_multi "$SB"
assert_exit 0 "clean multi-context layer" -- "$CHECK" "$SB"
assert_contains "layer-integrity OK" "clean multi-context prints the OK summary"

# --- Scenario (c): dangling term link -> exit 1 ------------------------------
SC="$TMP/c"
build_single "$SC"
cat >"$SC/docs/design/design.md" <<'EOF'
# Design

## 00 Foundation

The system tracks [drift](CONTEXT.md#term-missing-term) between artifacts.
EOF
assert_exit 1 "dangling term link is a violation" -- "$CHECK" "$SC"
assert_contains "dangling term anchor" "report flags the dangling term anchor"
assert_contains "term-missing-term" "report names the missing term id"

# --- Scenario (d): near-miss anchors -> exit 1 (fail-closed) ------------------
# A #trem- typo and a bare #term- (no slug) both LOOK design-ish and must be
# violations, never silent skips.
SD="$TMP/d"
build_single "$SD"
cat >"$SD/docs/design/design.md" <<'EOF'
# Design

## 00 Foundation

The system tracks [drift](CONTEXT.md#trem-drift) between artifacts.
A slugless anchor is just as broken: [bad](CONTEXT.md#term-).
EOF
assert_exit 1 "near-miss anchors are violations" -- "$CHECK" "$SD"
assert_contains "malformed anchor" "report flags the near-miss as malformed"
assert_contains "trem-drift" "report names the #trem- typo"
assert_contains "'#term-'" "report names the slugless #term-"

# --- Scenario (d2): section anchors -> accepted, and resolved ----------------
# design_doc.generation.link_rewrite documents `foo/design.md#02-x`, so a link
# into a SECTION of a design document is legal alongside term and adr anchors.
# It must resolve like any other: a real heading passes, an invented one fails.
SD2="$TMP/d2"
build_single "$SD2"
cat >"$SD2/docs/design/design.md" <<'EOF'
# Design

## 00 Foundation

A pointer into a real section: [the trio](design.md#02-the-artifact-trio).

## 02 The artifact trio

The section the link above resolves to.
EOF
assert_exit 0 "a section anchor resolving to a real heading passes" -- "$CHECK" "$SD2"

SD3="$TMP/d3"
build_single "$SD3"
cat >"$SD3/docs/design/design.md" <<'EOF'
# Design

## 00 Foundation

A pointer into a section that does not exist:
[nowhere](design.md#99-not-a-section).
EOF
assert_exit 1 "a section anchor with no such heading is a violation" -- "$CHECK" "$SD3"
assert_contains "dangling section anchor" "report names it as a dangling section anchor"

# --- Scenario (e): ADR filename/anchor mismatch -> exit 1 --------------------
SE="$TMP/e"
build_single "$SE"
cat >"$SE/docs/adr/0002-second-decision.md" <<'EOF'
# 0002 — Second decision

<a id="adr-0003"></a>

The anchor disagrees with the filename.
EOF
assert_exit 1 "adr filename/anchor mismatch is a violation" -- "$CHECK" "$SE"
assert_contains "adr lockstep mismatch" "report flags the lockstep break"
assert_contains "0002-second-decision.md" "report names the offending ADR"

# --- Scenario (f): CONTEXT.md missing from the map -> exit 1 ------------------
SF="$TMP/f"
build_multi "$SF"
cat >"$SF/docs/CONTEXT-MAP.md" <<'EOF'
# Context Map

- [Alpha](./design/alpha/CONTEXT.md) — the alpha vocabulary.
EOF
assert_exit 1 "unmapped CONTEXT.md is a violation" -- "$CHECK" "$SF"
assert_contains "unmapped CONTEXT.md" "report flags the map gap"
assert_contains "docs/design/beta/CONTEXT.md" "report names the unmapped context"

# --- Scenario (g): orphan design.pdf -> exit 1 -------------------------------
SG="$TMP/g"
build_single "$SG"
mkdir -p "$SG/docs/design/tool"
printf '%%PDF-1.7 stub\n' >"$SG/docs/design/tool/design.pdf"
assert_exit 1 "a per-context design.pdf is a violation" -- "$CHECK" "$SG"
assert_contains "mishomed layer artifact" "report flags it as mishomed"
assert_contains "docs/design/tool/design.pdf" "report names the stray file"

# --- Scenario (h): duplicate term id -> exit 1 --------------------------------
SH="$TMP/h"
build_single "$SH"
cat >"$SH/docs/design/CONTEXT.md" <<'EOF'
# Glossary

### Drift {#term-drift}

The gap between the design layer and the implementation.

### Drift Again {#term-drift}

The same id declared twice.
EOF
assert_exit 1 "duplicate term id is a violation" -- "$CHECK" "$SH"
assert_contains "duplicate term id" "report flags the duplicate"
assert_contains "term-drift" "report names the duplicated id"

# --- Scenario (i): empty repo / no layer -> exit 2, distinct message ----------
SI="$TMP/i"
mkdir -p "$SI/src"
echo "just code" >"$SI/src/main.txt"
assert_exit 2 "repo without a design layer is an IO-level error" -- "$CHECK" "$SI"
assert_contains "no design layer" "report says 'no design layer' distinctly"

# --- Scenario (j): usage error (too many args) -> exit 2 ----------------------
assert_exit 2 "too many args is a usage error" -- "$CHECK" "$SA" extra-arg

# --- Scenario (k): unresolvable schema -> exit 2 ------------------------------
assert_exit 2 "missing schema is an error" -- \
  env DESIGN_SCHEMA=/nonexistent/design-schema.json "$CHECK" "$SA"
assert_contains "design schema not found" "report names the schema gap"

# --- Scenario (l): dangling sibling adr-ish link -> exit 1 --------------------
# The observed e2e hole: an adr-ish filename linked as a sibling path with no
# fragment matches no filename/substring/dir marker, but the schema's re:
# markers classify it design-ish — and the file does not exist.
SL="$TMP/l"
build_single "$SL"
cat >>"$SL/docs/design/design.md" <<'EOF'

Storage: [ADR-0001](adr-0001-storage-envelope.md).
EOF
assert_exit 1 "dangling sibling adr-ish link is a violation" -- "$CHECK" "$SL"
assert_contains "dangling link" "report flags the unresolvable adr-ish link"
assert_contains "adr-0001-storage-envelope.md" "report names the missing adr-ish target"

# --- Scenario (m): adr-ish file existing outside the ADR dir -> exit 1 --------
# Same link, but the stray file exists next to design.md: still a violation —
# an adr-ish target must live in the canonical ADR dir.
SM="$TMP/m"
build_single "$SM"
cat >>"$SM/docs/design/design.md" <<'EOF'

Storage: [ADR-0001](adr-0001-storage-envelope.md).
EOF
cat >"$SM/docs/design/adr-0001-storage-envelope.md" <<'EOF'
# A stray ADR-looking file living outside docs/adr
EOF
assert_exit 1 "adr-ish file outside the ADR dir is a violation" -- "$CHECK" "$SM"
assert_contains "stray adr-ish file" "report flags the stray adr-ish target"

# --- Scenario (n): legal fragment-less link to a canonical ADR -> exit 0 ------
# A fragment-less link to an existing, lockstep-valid docs/adr/NNNN-slug.md is
# legal: the file resolves and check 2 owns its lockstep.
SN="$TMP/n"
build_single "$SN"
cat >>"$SN/docs/design/design.md" <<'EOF'

The full decision: [ADR 1](../adr/0001-first-decision.md).
EOF
assert_exit 0 "fragment-less link to a canonical lockstep-valid ADR is legal" -- "$CHECK" "$SN"
assert_contains "layer-integrity OK" "legal adr link run stays clean"

# --- Scenario (o): verbatim-duplicated non-trivial line -> exit 1 -------------
# Restatement instead of a cross-link: the same prose sentence appears twice
# within one design.md.
SO="$TMP/o"
build_single "$SO"
cat >>"$SO/docs/design/design.md" <<'EOF'

## 02 Restatement

The system tracks drift between the design layer and the implementation.
Some interleaving prose that keeps the two copies apart in the file.
The system tracks drift between the design layer and the implementation.
EOF
assert_exit 1 "verbatim-duplicated non-trivial line is a violation" -- "$CHECK" "$SO"
assert_contains "duplicate line" "report flags the duplicated line"
assert_contains "The system tracks drift between the design layer" \
  "report quotes the duplicated sentence"
assert_contains "appears 2x" "report counts the occurrences"

# --- Scenario (p): repeated TRIVIAL lines -> exit 0 (no false positive) -------
# Blank lines, rules, table separators, short lone markers and ::: block
# directive markers all legitimately repeat; none may trip the duplicate check.
SP="$TMP/p"
build_single "$SP"
cat >>"$SP/docs/design/design.md" <<'EOF'

## 02 Tables

| Col A | Col B |
| --- | --- |
| one | two |

---

| Col C | Col D |
| --- | --- |
| three | four |

---

:::invariant {enforcement=convention}
An invariant statement long enough to count as prose, stated once.
:::

:::invariant {enforcement=convention}
A different invariant statement, also long enough to count as prose.
:::

TODO
A closing sentence with enough length to count as real prose here.
TODO
EOF
assert_exit 0 "repeated trivial lines do not false-positive" -- "$CHECK" "$SP"
assert_contains "layer-integrity OK" "trivial-repeat run stays clean"
assert_not_contains "duplicate line" "no duplicate reported for trivial repeats"

# --- Scenario (q): repeated citation-only line -> exit 0 ----------------------
# "Cited, never restated" makes citations the legal form of repetition: a
# line consisting entirely of a markdown link (plus punctuation) may repeat.
SQ="$TMP/q"
build_single "$SQ"
cat >>"$SQ/docs/design/design.md" <<'EOF'

## 02 Citations

[ADR-0001](../adr/0001-first-decision.md#adr-0001).

Prose in between the two citations of the very same decision record.

[ADR-0001](../adr/0001-first-decision.md#adr-0001).
EOF
assert_exit 0 "repeated citation-only line is legal" -- "$CHECK" "$SQ"
assert_contains "layer-integrity OK" "citation-repeat run stays clean"
assert_not_contains "duplicate line" "no duplicate reported for repeated citations"

# --- Scenario (r): gitignored broken layer is pruned -> exit 0 ----------------
# When the target root is a git repo, gitignored trees are not part of the
# system: a broken design layer inside one must not surface. (Every other
# fixture is a plain directory, proving the non-git full-scan fallback.)
SR="$TMP/r"
build_single "$SR"
git -C "$SR" init -q
printf 'scratch/\n' >"$SR/.gitignore"
mkdir -p "$SR/scratch/sub"
cat >"$SR/scratch/design.md" <<'EOF'
# Scratch design

A dangling design-ish link: [nope](CONTEXT.md#term-nope).
EOF
cat >"$SR/scratch/CONTEXT.md" <<'EOF'
# Scratch glossary

### Dup {#term-dup}

First declaration.

### Dup Again {#term-dup}

Second declaration of the same id.
EOF
cat >"$SR/scratch/sub/design.pdf" <<'EOF'
<!doctype html>
<html>
  <body>
    <h1>An orphan page in a gitignored tree</h1>
  </body>
</html>
EOF
assert_exit 0 "gitignored broken layer is pruned from discovery" -- "$CHECK" "$SR"
assert_contains "layer-integrity OK" "gitignored-scratch run stays clean"
assert_not_contains "scratch/" "no violation mentions the gitignored tree"

# --- Scenario (s): copy-installed sibling schema lookup -> exit 0 -------------
# The distribution contract (scripts_contract.distribution) copy-installs the
# checker and design-schema.json side by side in a target repo's scripts/.
# Prove the checker resolves that script-sibling copy: install both into a
# bare bin dir whose parent has NO schema/ directory, so only the sibling
# lookup can succeed.
SS="$TMP/s"
build_single "$SS"
INSTALL="$TMP/s-install/scripts"
mkdir -p "$INSTALL"
cp "$CHECK" "$INSTALL/layer-integrity"
cp "$HERE/../schema/design-schema.json" "$INSTALL/design-schema.json"
chmod +x "$INSTALL/layer-integrity"
assert_exit 0 "copy-installed checker resolves its script-sibling schema" -- \
  "$INSTALL/layer-integrity" "$SS"
assert_contains "layer-integrity OK" "sibling-schema run prints the OK summary"

# --- Scenario (t): generation debris in layer artifacts -> exit 1 -------------
# A generation-wrapper artifact line (a literal </content>, surrounding
# whitespace allowed) inside a layer artifact is writer leakage, never
# content. The patterns come from the schema
# (layer_layout.generation_debris_patterns), never from the script.
ST="$TMP/t"
build_single "$ST"
printf '</content>\n' >>"$ST/docs/adr/0001-first-decision.md"
cat >"$ST/docs/COVERAGE.md" <<'EOF'
# Coverage

| Part | Status   |
| ---- | -------- |
| core | captured |

  </content>
EOF
assert_exit 1 "generation debris in layer artifacts is a violation" -- "$CHECK" "$ST"
assert_contains "generation debris" "report flags the debris line"
assert_contains "0001-first-decision.md" "report names the ADR carrying debris"
assert_contains "COVERAGE.md" "report catches whitespace-surrounded debris in COVERAGE.md"

# --- Scenario (u): debris shape inside a fenced code block -> exit 0 ----------
# An example of the wrapper line inside a fence is documentation, not leakage.
SU="$TMP/u"
build_single "$SU"
cat >>"$SU/docs/design/design.md" <<'EOF'

## 02 Example

```text
</content>
```
EOF
assert_exit 0 "a fenced </content> example is not debris" -- "$CHECK" "$SU"
assert_not_contains "generation debris" "no debris reported for the fenced example"

# --- Scenario (v): layer files colocated in a source dir -> exit 1 ------------
# The layer lives entirely under docs/ (schema layer_layout.homing): a
# context's design.md/CONTEXT.md sitting inside a source directory is a
# mishomed stray, however internally well-formed.
SV="$TMP/v"
build_single "$SV"
mkdir -p "$SV/src/alpha"
cat >"$SV/src/alpha/CONTEXT.md" <<'EOF'
# Alpha

### Alpha Thing {#term-alpha-thing}

The one thing alpha owns.
EOF
cat >"$SV/src/alpha/design.md" <<'EOF'
# Alpha design

Built around the [alpha thing](CONTEXT.md#term-alpha-thing).
EOF
assert_exit 1 "colocated layer files are mishomed" -- "$CHECK" "$SV"
assert_contains "mishomed layer artifact" "report flags the mishomed files"
assert_contains "src/alpha/CONTEXT.md" "report names the colocated glossary"
assert_contains "src/alpha/design.md" "report names the colocated design doc"

# --- Scenario (w): CONTEXT-MAP.md at repo root -> exit 1 ----------------------
# The map's declared home is docs/CONTEXT-MAP.md; a root-level map (the
# pre-v3 layout) is both mishomed and, with 2+ contexts, missing from its
# home — the loud migration signal.
SW="$TMP/w"
build_multi "$SW"
mv "$SW/docs/CONTEXT-MAP.md" "$SW/CONTEXT-MAP.md"
assert_exit 1 "root-level context map is mishomed" -- "$CHECK" "$SW"
assert_contains "mishomed layer artifact" "report flags the mishomed map"
assert_contains "missing context map" "report also flags the absent homed map"

# --- Scenario (x): staleness advisory fires past the threshold -> exit 0 ------
# Advisory, never a check: a repo that moved threshold+ commits since the
# layer last changed gets one advisory line and a clean exit. The threshold
# comes from the schema; a lowered-threshold schema copy keeps the fixture
# small.
SX="$TMP/x"
build_single "$SX"
git -C "$SX" init -q
git -C "$SX" -c user.email=t@t -c user.name=t add -A
git -C "$SX" -c user.email=t@t -c user.name=t commit -qm "layer"
for i in 1 2 3; do
  git -C "$SX" -c user.email=t@t -c user.name=t commit -qm "system move $i" --allow-empty
done
LOWERED="$TMP/schema-threshold-3.json"
python3 -c '
import json, sys
s = json.load(open(sys.argv[1]))
s["layer_layout"]["staleness_advisory"]["threshold_commits"] = 3
json.dump(s, open(sys.argv[2], "w"))' "$HERE/../schema/design-schema.json" "$LOWERED"
assert_exit 0 "staleness advisory keeps the exit clean" -- \
  env DESIGN_SCHEMA="$LOWERED" "$CHECK" "$SX"
assert_contains "advisory: 3 commit(s) since the design layer last changed" \
  "advisory names the commit count"

# --- Scenario (y): advisory silent under threshold / without the key ----------
SY="$TMP/y"
build_single "$SY"
git -C "$SY" init -q
git -C "$SY" -c user.email=t@t -c user.name=t add -A
git -C "$SY" -c user.email=t@t -c user.name=t commit -qm "layer"
git -C "$SY" -c user.email=t@t -c user.name=t commit -qm "one move" --allow-empty
assert_exit 0 "under-threshold repo stays clean" -- \
  env DESIGN_SCHEMA="$LOWERED" "$CHECK" "$SY"
assert_not_contains "advisory:" "no advisory under the threshold"
NOKEY="$TMP/schema-no-advisory.json"
python3 -c '
import json, sys
s = json.load(open(sys.argv[1]))
del s["layer_layout"]["staleness_advisory"]
json.dump(s, open(sys.argv[2], "w"))' "$HERE/../schema/design-schema.json" "$NOKEY"
assert_exit 0 "pre-advisory schema copy is tolerated" -- \
  env DESIGN_SCHEMA="$NOKEY" "$CHECK" "$SX"
assert_not_contains "advisory:" "no advisory without the schema key"

# --- Scenario (z): mermaid click targets are design-ish links ----------------
# A `click NODE "dest"` inside a ```mermaid fence navigates like any link; a
# dangling one must fail even though it lives in a code fence (which the plain
# link extractor drops). A resolving click stays clean.
SZ="$TMP/z"
build_single "$SZ"
cat >>"$SZ/docs/design/design.md" <<'EOF'

## 02 Diagram

```mermaid
graph TD
    A["drift"]
    click A "CONTEXT.md#term-drift"
```
EOF
assert_exit 0 "resolving mermaid click target stays clean" -- "$CHECK" "$SZ"

SZ2="$TMP/z2"
build_single "$SZ2"
cat >>"$SZ2/docs/design/design.md" <<'EOF'

## 02 Diagram

```mermaid
graph TD
    A["gone"]
    click A "../gone/design.md"
```
EOF
assert_exit 1 "dangling mermaid click target is a violation" -- "$CHECK" "$SZ2"
assert_contains "../gone/design.md" "click-target violation names the destination"

# --- Scenario (aa): an invariant carries no pointer to its enforcer ---------
# `script=` is gone. It named the mechanism holding a property, but resolution
# only ever proved a name existed — never that the named thing checked
# anything — and it had to be kept current by hand. Which check holds a
# property is the gate's own job to find, so the attribute was removed rather
# than made resolvable. `enforcement` stays as the honest label for the KIND of
# enforcement, and an invariant declaring it is legal with nothing else.
SAA="$TMP/aa"
build_single "$SAA"
cat >>"$SAA/docs/design/design.md" <<'EOF'

:::invariant {title="Held by a mechanism" enforcement=mechanism}
The property is checked; which check holds it is not declared here.
:::
EOF
assert_exit 0 "an enforcement=mechanism invariant needs no enforcer pointer" \
  -- "$CHECK" "$SAA"

# --- Scenario (cov): COVERAGE.md's own citations resolve ----------------------
# The coverage map cites terms and design sections like any other entry point.
# It was once indexed but never link-checked, so an invented term anchor passed
# clean here while the identical break inside a design document failed — the
# silent hole the map exists to close.
SCOV="$TMP/cov"
build_single "$SCOV"
cat >"$SCOV/docs/COVERAGE.md" <<'EOF'
# Coverage

| Part | Status | Note |
| ---- | ------ | ---- |
| the engine | captured | Described as [drift](design/CONTEXT.md#term-no-such-term). |
EOF
assert_exit 1 "a dangling term anchor in COVERAGE.md is a violation" -- "$CHECK" "$SCOV"
assert_contains "term-no-such-term" "the violation names the missing term"

# The same map citing a term that DOES exist resolves clean.
SCOVB="$TMP/covb"
build_single "$SCOVB"
cat >"$SCOVB/docs/COVERAGE.md" <<'EOF'
# Coverage

| Part | Status | Note |
| ---- | ------ | ---- |
| the engine | captured | Described as [drift](design/CONTEXT.md#term-drift). |
EOF
assert_exit 0 "a resolving term anchor in COVERAGE.md is clean" -- "$CHECK" "$SCOVB"

# --- Scenario (perf): a run finishes well under a wall-clock ceiling ----------
# The parse-once invariant: the checker reads each layer file ONCE into an
# index and answers every check as a lookup against it. The shape it replaced
# spawned a fresh python interpreter per regex match and re-read each target
# file per reference into it, which cost tens of seconds on a real layer. The
# ceiling is deliberately generous — far above real cost on slow CI hardware,
# far below the cost of a return to per-match spawning.
CEILING=10
SPERF="$TMP/perf"
build_multi "$SPERF"
perf_start=$(date +%s)
assert_exit 0 "parse-once run stays clean" -- "$CHECK" "$SPERF"
perf_elapsed=$(($(date +%s) - perf_start))
if [ "$perf_elapsed" -lt "$CEILING" ]; then
  echo "PASS: run completes under the ${CEILING}s ceiling (${perf_elapsed}s)"
  pass=$((pass + 1))
else
  echo "FAIL: run took ${perf_elapsed}s, over the ${CEILING}s parse-once ceiling"
  fail=$((fail + 1))
fi

# --- Summary ------------------------------------------------------------------
echo
echo "----------------------------------------"
echo "PASS: $pass  FAIL: $fail"
if [ "$fail" -ne 0 ]; then
  echo "SELF-TEST FAILED"
  exit 1
fi
echo "SELF-TEST PASSED"
