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

"$APP" "$LAYER" --base HEAD --pdf -o "$WORK/review.html"
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
echo "design-review: Git, cross-section identity, PDF companions and duplicate detection passed"
