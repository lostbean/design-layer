#!/usr/bin/env bash
set -euo pipefail

# This test enters through the public flake app. It intentionally leaves the
# schema and library variables unset so the wrapper's bundled defaults are the
# values under test.
APP="${DESIGN_CONTEXT_APP:-}"
if [ -z "$APP" ]; then
  echo "design-context-app: DESIGN_CONTEXT_APP is not set" >&2
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/design-context-app.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
LAYER="$WORK/docs/design"
mkdir -p "$LAYER/.render"
bash ./scripts/render-project schema/design-schema.json "$LAYER/.render" >/dev/null

cat >"$LAYER/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [App fixture]
#let body = [#section(title: "One", lead: [Lead.], body: [#goal(title: "Ship")[Goal.]])]
EOF

cat >"$WORK/docs/COVERAGE.md" <<'EOF'
# Coverage map
EOF

expected="$WORK/expected.md"
cat >"$expected" <<'EOF'
# App fixture

## One

Lead.

### goal: Ship

Goal.

<!-- source: docs/COVERAGE.md -->

# Coverage map
EOF

default="$WORK/default.md"
"$APP" "$LAYER" >"$default"
cmp -s "$expected" "$default"

output="$WORK/output.md"
"$APP" "$LAYER" --output "$output" >"$WORK/output-stdout"
[ ! -s "$WORK/output-stdout" ]
cmp -s "$default" "$output"

estimate="$WORK/estimate.json"
"$APP" "$LAYER" --estimate >"$estimate"
python3 - "$default" "$estimate" <<'PY'
import json
import math
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
raw = pathlib.Path(sys.argv[1]).read_bytes()
text = raw.decode("utf-8")
expected = {
    "utf8_bytes": len(raw),
    "characters": len(text),
    "words": len(text.split()),
    "lines": text.count("\n"),
    "likely_tokens": math.ceil(len(raw) / 4),
    "conservative_tokens": math.ceil(len(raw) / 3),
    "likely_tokens_method": "ceil(utf8_bytes/4)",
    "conservative_tokens_method": "ceil(utf8_bytes/3)",
}
assert data == expected, (data, expected)
PY

assert_exit() {
  expected_status="$1"
  label="$2"
  shift 2
  stdout="$WORK/$label.stdout"
  stderr="$WORK/$label.stderr"
  set +e
  "$APP" "$@" >"$stdout" 2>"$stderr"
  status=$?
  set -e
  if [ "$status" -ne "$expected_status" ] || [ -s "$stdout" ]; then
    echo "design-context-app: $label expected exit $expected_status and empty stdout" >&2
    cat "$stderr" >&2
    exit 1
  fi
}

assert_exit 2 help --help
assert_exit 2 missing-root "$WORK/missing"
assert_exit 2 unknown-option "$LAYER" --unknown
assert_exit 2 conflicting-modes "$LAYER" --estimate --output "$WORK/no.md"
assert_exit 2 missing-output "$LAYER" --output
assert_exit 2 output-write "$LAYER" --output "$WORK/no-such-directory/out.md"

# A semantic/source violation is distinct from a usage/runtime error and must
# leave no usable projection behind.
cp "$LAYER/design.typ" "$WORK/design.good.typ"
cat >"$LAYER/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Unrepresentable app fixture]
#let body = [#figure-block(caption: [Figure meaning], uses: ("cetz"))[Figure body.]]
EOF
semantic_output="$WORK/semantic-failure.md"
assert_exit 1 semantic-failure "$LAYER" --output "$semantic_output"
[ ! -e "$semantic_output" ]
cp "$WORK/design.good.typ" "$LAYER/design.typ"

# The app must reject a stale source-tree projection instead of silently using
# the bundled library with a source tree whose imports no longer agree.
printf 'divergence probe\n' >>"$LAYER/.render/native.typ"
divergent="$WORK/divergent.md"
assert_exit 2 divergent-library "$LAYER" --output "$divergent"
[ ! -e "$divergent" ]

echo "design-context-app: bundled app modes, estimates, failures, and divergence are green"
