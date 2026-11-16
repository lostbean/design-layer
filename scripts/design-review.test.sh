#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
WORK="$(mktemp -d)"
trap 'chmod u+w "$WORK/.render" 2>/dev/null || true; rm -rf "$WORK"' EXIT

cd "$ROOT"
bash scripts/render-project schema/design-schema.json "$WORK/.render" >/dev/null
export DESIGN_LIB_DIR="$WORK/.render"
APP="${DESIGN_REVIEW_APP:-$ROOT/scripts/design-review}"

python3 - "$ROOT" "$WORK" <<'PY'
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json
import subprocess
import sys

root, work = map(Path, sys.argv[1:])
sys.path.insert(0, str(root / "scripts"))
from review_model import compare

source = (root / "fixtures/gallery.typ").read_text()
cases = json.loads((root / "fixtures/review-edits.json").read_text())
baseline = work / "baseline.typ"
baseline.write_text(source)

def snapshot(path):
    return json.loads(subprocess.run(
        ["typst", "query", path, "<design-semantic>", "--field", "value",
         "--input", "context=1", "--input", "review-projection=1"],
        capture_output=True, check=True,
    ).stdout)

old = snapshot(baseline)
def audit(case):
    before, after = cases[case]
    assert source.count(before) == 1, case
    variant = work / f"{case}.typ"
    variant.write_text(source.replace(before, after, 1))
    changes = compare(old, snapshot(variant))
    uncertain = [row for row in changes if row["kind"] == "needs-review"]
    precise = [row for row in changes if row["kind"] != "needs-review"]
    if case in {"diagram-native", "components", "warning", "cards"}:
        assert not changes, (case, changes)
    elif case in {"figure", "landscape-figure", "formula"}:
        assert uncertain and not precise, (case, changes)
    else:
        assert precise and not uncertain, (case, changes)

with ThreadPoolExecutor(max_workers=4) as pool:
    list(pool.map(audit, cases))
print(f"design-review: {len(cases)} isolated gallery edits passed")

unchanged = {"kind": "diagram-native", "review-id": "stable", "nodes": [], "groups": [], "edges": []}
added, = compare([], [unchanged])
removed, = compare([unchanged], [])
assert added["kind"] == "added" and added["anchor"] == "diagram/stable", added
assert removed["kind"] == "removed" and removed["anchor"] == "diagram/stable", removed

# The summary is posted where anyone can read it, so design text stays inert:
# one table row per section and one line per uncertain change, whatever the
# text holds.
from review_model import render_summary

def change(kind, *path):
    row = {"kind": kind, "path": list(path), "before": None, "after": None, "anchor": None}
    return {**row, "reason": "Formula notation changed."} if kind == "needs-review" else row

hostile = "a | b `c` ``d`` @someone <img src=x>\n| forged | row |"
report = {
    "sources": {"before": "abc123", "after": "docs/design"},
    "changes": [
        change("changed", "section " + hostile, "body"),
        change("added", "section " + hostile, "item"),
        change("needs-review", "section Rates", "formula " + hostile),
        change("removed", "term Ledger"),
    ],
    "coverage": {"before": {}, "after": {"formula": 1}},
}
summary = render_summary(report).splitlines()
assert summary[0] == "<!-- design-review changes=4 -->", summary[0]
assert "**3 confirmed · 1 need review**" in summary, summary
rows = [line for line in summary if line.startswith("| `")]
inert = "```a \\| b `c` ``d`` @someone <img src=x> \\| forged \\| row \\|```"
assert rows == [
    f"| {inert} | 1 | 1 | 0 | 0 |",
    "| `Rates` | 0 | 0 | 0 | 1 |",
    "| `Document and shared records` | 0 | 0 | 1 | 0 |",
], rows
uncertain = [line for line in summary if line.startswith("- ")]
assert len(uncertain) == 1 and uncertain[0].endswith("```: Formula notation changed."), uncertain
assert "\\|" not in uncertain[0] and "| forged | row |" in uncertain[0], uncertain
assert summary[-1].startswith("Native figures"), summary[-1]
many = {**report, "changes": [change("added", f"section {n}", "item") for n in range(45)]}
assert "5 more sections are in the full report." in render_summary(many)
empty = render_summary({**report, "changes": [], "coverage": {"before": {}, "after": {}}})
assert empty.startswith("<!-- design-review changes=0 -->\n") and "No changes" in empty
long = render_summary({**report, "changes": [change("changed", "section " + "x" * 500)]})
assert max(map(len, long.splitlines())) < 260, long
PY

# Use the same directory mode as the packaged renderer.
chmod a-w "$WORK/.render"

REPO="$WORK/repo"
LAYER="$REPO/docs/design"
mkdir -p "$LAYER"
git -C "$REPO" init -q
write_layer() {
  local side="$1"
  cat >"$LAYER/design.typ" <<EOF
#import ".render/designlib.typ": *
#let title = [Review fixture]
#let graph = diagram-native(
  review-id: "publish-path", altitude: "L3",
  nodes: ((id: "review", label: [Review], pos: (0, 0)),
          (id: "publish", label: [Publish], pos: (1, 1))),
  edges: (($2, $3, "accepts"),),
)
#let body = [
  #section(title: [Introduction], visual: if "$side" == "before" { graph }, body: [
    Read the #link("https://example.org/$side")[guide].
  ])
  #section(title: [Delivery], visual: if "$side" == "after" { graph }, body: [Publish.])
]
EOF
}
write_layer before '"review"' '"publish"'
git -C "$REPO" add docs/design/design.typ
git -C "$REPO" -c user.name=Test -c user.email=test@example.invalid commit -qm Before
write_layer after '"publish"' '"review"'
"$APP" "$LAYER" --base HEAD --format json >"$WORK/report.json"
python3 - "$WORK/report.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text())
assert report["format"] == "design-review/v1"
assert len(report["changes"]) == 2, report
link = next(row for row in report["changes"] if row["path"][-1] == "dest")
assert link["before"].endswith("/before") and link["after"].endswith("/after")
edge = next(row for row in report["changes"] if row["anchor"] == "diagram/publish-path")
assert edge["before"]["from"] == "review" and edge["after"]["from"] == "publish"
PY

# Observe only the external Typst boundary while exercising the public review CLI.
export REVIEW_TEST_TYPST="$(type -P typst)"
export REVIEW_TEST_CALLS="$WORK/typst-calls"
mkdir "$WORK/bin"
{
  printf '#!%s\n' "$BASH"
  cat <<'SH'
printf '%s\n' "$1" >>"$REVIEW_TEST_CALLS"
exec "$REVIEW_TEST_TYPST" "$@"
SH
} >"$WORK/bin/typst"
chmod +x "$WORK/bin/typst"

trace_review() {
  : >"$REVIEW_TEST_CALLS"
  PATH="$WORK/bin:$PATH" python3 "$ROOT/scripts/design-review" "$@"
}

trace_review "$LAYER" "$LAYER" --format json >"$WORK/same.json"
printf 'query\n' | cmp - "$REVIEW_TEST_CALLS"

trace_review "$LAYER" --base HEAD --pdf -o "$WORK/review.html"
printf 'compile\ncompile\nquery\nquery\n' | sort | cmp - <(sort "$REVIEW_TEST_CALLS")
rg -q 'Before PDF' "$WORK/review.html"
rg -q 'Diagram marked where it appears' "$WORK/review.html"
for pdf in "$WORK/review-before.pdf" "$WORK/review-after.pdf"; do
  pdftotext "$pdf" - | rg 'Publish' >/dev/null
  pdftoppm -r 72 "$pdf" "${pdf%.pdf}"
done
python3 - "$WORK" <<'PYTEST'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
for side in ("before", "after"):
    matches = 0
    for image in root.glob(f"review-{side}-*.ppm"):
        data = image.read_bytes()
        header = re.match(rb"P6\n(\d+) (\d+)\n255\n", data)
        width, height = map(int, header.groups())
        pixels = data[header.end():]
        for y in range(height):
            for x in range(40, 54):
                offset = 3 * (y*width+x)
                matches += pixels[offset:offset+3] == bytes((40,112,166))
    assert matches >= 12, (side, matches)
PYTEST
"$APP" "$LAYER" --base HEAD --format json -o "$WORK/summary.json" --summary "$WORK/summary.md"
head -n 1 "$WORK/summary.md" | rg -qx -- '<!-- design-review changes=2 -->'
rg -qx -- '\*\*2 confirmed · 0 need review\*\*' "$WORK/summary.md"
rg -qx -- '\| `Introduction` \| 1 \| 0 \| 0 \| 0 \|' "$WORK/summary.md"
rg -qx -- '\| `Document and shared records` \| 1 \| 0 \| 0 \| 0 \|' "$WORK/summary.md"
if "$APP" "$LAYER" --base HEAD --format json --summary "$WORK/summary.md" >"$WORK/summary.out" 2>&1; then
  echo "review overwrote an existing summary" >&2
  exit 1
fi
rg -q 'output already exists' "$WORK/summary.out"
if "$APP" "$LAYER" --base HEAD -o "$WORK/review.html" >"$WORK/overwrite" 2>&1; then
  echo "review overwrote an existing report" >&2
  exit 1
fi
rg -q 'output already exists' "$WORK/overwrite"

APP_FIXTURE="$WORK/duplicate.typ"
cat >"$APP_FIXTURE" <<'EOF'
#import ".render/designlib.typ": diagram-native
#let nodes = ((id: "one", pos: (0, 0), label: [One]),)
#diagram-native(altitude: "L3", review-id: "same", nodes: nodes)
#diagram-native(altitude: "L3", review-id: "same", nodes: nodes)
EOF
if "$APP" "$APP_FIXTURE" "$APP_FIXTURE" >"$WORK/duplicate.out" 2>"$WORK/duplicate.err"; then
  echo "review accepted duplicate diagram identity" >&2
  exit 1
fi
rg -q 'duplicate diagram review-id' "$WORK/duplicate.err"

# The change that adopts a layer compares against a base with no layer.
ADOPT="$WORK/adopt"
ADOPT_LAYER="$ADOPT/docs/design"
mkdir -p "$ADOPT/docs"
git -C "$ADOPT" init -q
echo "Before the design layer." >"$ADOPT/README.md"
git -C "$ADOPT" add README.md
git -C "$ADOPT" -c user.name=Test -c user.email=test@example.invalid commit -qm Before
mkdir "$ADOPT_LAYER"
cat >"$ADOPT_LAYER/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Adoption fixture]
#let body = [
  #section(title: [Adoption plan], body: [
    #unit(
      id: "review-app",
      title: "Review app",
      overview: [Compares two revisions of a layer.],
      interface: ([`review <layer> --base <rev>`],),
      invariants: ([Every record of the working tree is reported.],),
      side-effects: (),
      verification: [The self-tests.],
      paths: ("scripts",),
    )
  ])
  #section(title: [Delivery], visual: diagram-native(
    review-id: "adoption-flow", altitude: "L3",
    nodes: ((id: "draft", label: [Draft], pos: (0, 0)),
            (id: "adopt", label: [Adopt], pos: (1, 0))),
    edges: (("draft", "adopt", "merges"),),
  ), body: [Publish.])
]
EOF
cat >"$ADOPT_LAYER/CONTEXT.typ" <<'EOF'
#let terms = (
  (slug: "term-adoption", title: [Adoption], body: [The change that adds a layer.]),
)
EOF
"$APP" "$ADOPT_LAYER" --base HEAD --format json >"$WORK/adopt.json"
EMPTY="$WORK/empty/docs/design"
mkdir -p "$EMPTY"
"$APP" "$EMPTY" "$ADOPT_LAYER" --format json >"$WORK/explicit.json"
"$APP" "$ADOPT_LAYER" "$EMPTY" --format json >"$WORK/emptied.json"
python3 - "$WORK/adopt.json" "$WORK/explicit.json" "$WORK/emptied.json" <<'PY'
import json
import sys
from pathlib import Path

report, explicit, emptied = (json.loads(Path(path).read_text()) for path in sys.argv[1:])
changes = report["changes"]
assert changes == explicit["changes"], (changes, explicit["changes"])
removed = emptied["changes"]
assert [row["path"] for row in removed] == [row["path"] for row in changes], removed
assert all(row["kind"] == "removed" and row["after"] is None for row in removed), removed
assert changes and all(row["kind"] == "added" and row["before"] is None for row in changes), changes
assert report["coverage"]["before"] == {}, report
added = {row["path"][0]: row for row in changes}
assert set(added) == {"document Adoption fixture", "term Adoption", "diagram adoption-flow"}, added
document = json.dumps(added["document Adoption fixture"]["after"])
for name in ("Adoption plan", "Delivery", "review-app"):
    assert name in document, name
assert added["term Adoption"]["after"]["slug"] == "term-adoption", added
assert added["diagram adoption-flow"]["anchor"] == "diagram/adoption-flow", added
PY

# An empty side is neither evaluated nor rendered, so it has no PDF. That holds
# for a base without the path and for an existing layer without documents.
for review in adopt explicit; do
  outputs=(--pdf -o "$WORK/$review.html" --summary "$WORK/$review.md")
  if [ "$review" = adopt ]; then
    trace_review "$ADOPT_LAYER" --base HEAD "${outputs[@]}"
  else
    trace_review "$EMPTY" "$ADOPT_LAYER" "${outputs[@]}"
  fi
  rg -q '^`[^`]+` has no design layer, so it is compared as an empty one\.$' "$WORK/$review.md"
  printf 'compile\nquery\n' | cmp - <(sort "$REVIEW_TEST_CALLS")
  test -s "$WORK/$review-after.pdf"
  test ! -e "$WORK/$review-before.pdf"
  rg -q 'After PDF' "$WORK/$review.html"
  if rg -q 'Before PDF' "$WORK/$review.html"; then
    echo "review linked a before PDF for an empty layer" >&2
    exit 1
  fi
  rg -q 'has no design layer, so it is compared as an empty one' "$WORK/$review.html"
  python3 - "$WORK/adopt.json" "$WORK/$review.html" <<'PY'
import json
import re
import sys
from pathlib import Path

changes = json.loads(Path(sys.argv[1]).read_text())["changes"]
classes = re.findall(r'<article class="([^"]+)">', Path(sys.argv[2]).read_text())
assert classes == ["added"] * len(changes), classes
PY
done

# A missing working-tree layer is an error, whether or not the base has one.
if "$APP" "$ADOPT/docs/missing" --base HEAD --format json >"$WORK/missing.out" 2>"$WORK/missing.err"; then
  echo "review accepted a working tree without a layer" >&2
  exit 1
fi
rg -q 'design source does not exist: .*/adopt/docs/missing$' "$WORK/missing.err"
mv "$LAYER" "$WORK/held-layer"
if "$APP" "$LAYER" --base HEAD --format json >"$WORK/removed.out" 2>"$WORK/removed.err"; then
  echo "review accepted a working tree whose layer was removed" >&2
  exit 1
fi
mv "$WORK/held-layer" "$LAYER"
rg -q 'design source does not exist: .*/repo/docs/design$' "$WORK/removed.err"
echo "design-review: Git, cross-section identity, PDF companions, the summary, duplicate detection and missing layers passed"
