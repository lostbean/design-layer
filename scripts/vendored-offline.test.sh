#!/usr/bin/env bash
#
# vendored-offline.test.sh — the vendored package set resolves NOTHING at run
# time, and every package it declares actually draws.
#
# WHY THIS TEST EXISTS. The offline guarantee is the property the vendoring
# buys, and it fails silently in both directions.
#
#   A MISSING TRANSITIVE PIN reopens the network. `withPackages` resolves a
#   transitive closure, which makes listing a top-level package look
#   sufficient. Measured directly, it is not: with `fletcher` alone the
#   closure carries cetz 0.3.4 but NOT the oxifmt 0.2.1 that cetz 0.3.4
#   imports, so the compile reaches for the network. On a developer's warm
#   package cache that fetch SUCCEEDS, the render is correct, and the broken
#   guarantee is invisible until CI or a sandbox runs with no network.
#
#   AN EXIT CODE IS NOT A DRAWING. A diagram library called wrongly can
#   compile clean and emit a blank frame. Asserting `typst compile` exited 0
#   would pass on a page with nothing on it, which is the failure this suite
#   exists to catch.
#
# So both halves are asserted POSITIVELY. Package resolution is pointed at a
# path that does not exist, so any network reach surfaces here as a failure
# instead of a cache hit; and the rendered PDF is converted back to text and
# the drawing's own labels are asserted present.
#
# Usage:  vendored-offline.test.sh [<typst-binary>]
# Exit:   0 all assertions pass, 1 an assertion failed, 2 a tool is missing.
set -uo pipefail

TYPST="${1:-${TYPST:-typst}}"

if ! command -v "$TYPST" >/dev/null 2>&1; then
  echo "vendored-offline: error: no renderer on PATH (set TYPST or enter the dev shell)" >&2
  exit 2
fi

# The mark assertion reads the rendered PDF back as text. Without the extractor
# the assertion cannot run, and a test that cannot run must not report success:
# this suite exists because a SKIP once let the exact case it covers go
# unchecked while the hook stayed green.
if ! command -v pdftotext >/dev/null 2>&1; then
  echo "vendored-offline: error: no pdftotext (enter the dev shell)" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
pass_line() {
  printf '  ok   %s\n' "$1"
  PASS=$((PASS + 1))
}
fail_line() {
  printf '  FAIL %s\n' "$1"
  FAIL=$((FAIL + 1))
}

echo "vendored-offline: the package set resolves offline, and draws"

# Every package resolution is sent to a path that does not exist. A package the
# vendored set did not carry would be fetched from the network here, and this
# is what turns that fetch into a visible failure.
export TYPST_PACKAGE_PATH="$WORK/no-such-package-tree"
export TYPST_PACKAGE_CACHE_PATH="$WORK/no-such-package-cache"
export HOME="$WORK/no-such-home"

# --- fletcher: the node-and-edge diagram carrier ------------------------------
# The labels below are the ASSERTED MARKS. They are chosen to be strings no
# part of the renderer's own furniture emits, so finding them in the extracted
# text proves this drawing produced them.
cat >"$WORK/fletcher.typ" <<'EOF'
#import "@preview/fletcher:0.5.8" as fletcher: node, edge
#fletcher.diagram(
  spacing: (16mm, 11mm),
  node((0, 0), [Zalpha], name: label("a")),
  node((1, 0), [Zbeta], name: label("b")),
  edge(label("a"), label("b"), "->", label: [Zgamma]),
)
EOF

if out="$("$TYPST" compile --root "$WORK" "$WORK/fletcher.typ" "$WORK/fletcher.pdf" 2>&1)"; then
  pass_line "fletcher compiles with package resolution pointed at nothing"

  text="$(pdftotext "$WORK/fletcher.pdf" - 2>/dev/null)"
  missing=""
  for mark in Zalpha Zbeta Zgamma; do
    case "$text" in
    *"$mark"*) ;;
    *) missing="$missing $mark" ;;
    esac
  done
  if [ -z "$missing" ]; then
    pass_line "the fletcher diagram renders its nodes and its edge label"
  else
    fail_line "the fletcher diagram compiled but these marks are absent:$missing"
    fail_line "  (a blank drawing that exits 0 is the failure this asserts against)"
  fi
else
  fail_line "fletcher does not resolve offline — a transitive pin is missing"
  printf '%s\n' "$out" | sed 's/^/       /'
fi

# --- the schema's declared list and the flake's set agree ---------------------
# The schema declares the vendored list and states that it must equal the
# flake's withPackages set. Two declarations of one set drift silently, so the
# agreement is asserted rather than trusted.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
drift="$(
  python3 - "$ROOT/schema/design-schema.json" "$ROOT/flake.nix" <<'PY'
import json, re, sys

schema_path, flake_path = sys.argv[1], sys.argv[2]
declared = json.load(open(schema_path))["design_doc"]["vendored_packages"]["packages"]

src = open(flake_path).read()
m = re.search(r"withPackages \(\s*ps: with ps; \[(.*?)\]\s*\)", src, re.S)
if not m:
    print("cannot locate the withPackages set in flake.nix")
    raise SystemExit(0)

flake = []
for line in m.group(1).split("\n"):
    line = line.split("#", 1)[0].strip()
    if line:
        flake.append(line)

only_schema = [p for p in declared if p not in flake]
only_flake = [p for p in flake if p not in declared]
if only_schema:
    print("declared in the schema, absent from the flake: " + ", ".join(only_schema))
if only_flake:
    print("present in the flake, undeclared in the schema: " + ", ".join(only_flake))
PY
)"
if [ -z "$drift" ]; then
  pass_line "the schema's vendored list equals the flake's package set"
else
  fail_line "the vendored list and the flake's package set disagree:"
  printf '%s\n' "$drift" | sed 's/^/       /'
fi

echo
echo "vendored-offline: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
