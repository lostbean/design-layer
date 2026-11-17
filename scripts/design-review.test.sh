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
assert "5 more sections are in the PDF." in render_summary(many)
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
# Each change names the part that draws it. The diagram moved between sections,
# so its change is drawn in one part before and in another after.
assert link["part"] == {"before": "section root/Introduction", "after": "section root/Introduction"}, link
assert edge["part"] == {"before": "section root/Introduction", "after": "section root/Delivery"}, edge
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

# One PDF holds the review: two renders, and per side one query for the records
# and one for the places.
trace_review "$LAYER" --base HEAD -o "$WORK/review.pdf"
printf 'compile\ncompile\nquery\nquery\nquery\nquery\n' | cmp - <(sort "$REVIEW_TEST_CALLS")
test ! -e "$WORK/review-before.pdf"
python3 - "$WORK/review.pdf" <<'PY'
import sys
import pymupdf

report = pymupdf.open(sys.argv[1])
index, sheets = report[0], {}
assert "2 confirmed · 0 need review" in index.get_text(), index.get_text()
for page in list(report)[1:]:
    title = page.get_text("text", clip=pymupdf.Rect(0, 0, page.rect.width, 28)).split()
    sheets[title[-1]] = page
assert set(sheets) == {"Introduction", "Delivery"}, sheets
middle = report[1].rect.width / 2
# The diagram is boxed where each revision draws it: in Introduction before,
# in Delivery after. Its change is counted once, in the new design's part.
(old_tag,) = sheets["Introduction"].search_for("diagram changed")
(new_tag,) = sheets["Delivery"].search_for("diagram changed")
assert old_tag.x1 < middle < new_tag.x0, (old_tag, new_tag)
assert "1 changed · holds the old place of 1" in sheets["Introduction"].get_text()
assert "\n1 changed\n" in sheets["Delivery"].get_text(), sheets["Delivery"].get_text()
for page in sheets.values():
    assert "Before · page" in page.get_text() and "After · page" in page.get_text()
PY
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
if "$APP" "$LAYER" --base HEAD -o "$WORK/review.pdf" >"$WORK/overwrite" 2>&1; then
  echo "review overwrote an existing PDF" >&2
  exit 1
fi
rg -q 'output already exists' "$WORK/overwrite"
if "$APP" "$LAYER" --base HEAD >"$WORK/nowhere" 2>&1; then
  echo "review accepted a PDF review without a path to write" >&2
  exit 1
fi
rg -q -- '-o names the PDF to write' "$WORK/nowhere"

# Two revisions without a change still produce a PDF, and it says so.
"$APP" "$LAYER" "$LAYER" -o "$WORK/same.pdf"
test "$(pdfinfo "$WORK/same.pdf" | sed -n 's/^Pages: *//p')" = 1
pdftotext "$WORK/same.pdf" - | rg -q 'No changes in the projected fields'

APP_FIXTURE="$WORK/duplicate.typ"
cat >"$APP_FIXTURE" <<'EOF'
#import ".render/designlib.typ": diagram-native
#let nodes = ((id: "one", pos: (0, 0), label: [One]),)
#diagram-native(altitude: "L3", review-id: "same", nodes: nodes)
#diagram-native(altitude: "L3", review-id: "same", nodes: nodes)
EOF
if "$APP" "$APP_FIXTURE" "$APP_FIXTURE" --format json >"$WORK/duplicate.out" 2>"$WORK/duplicate.err"; then
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

# An empty side is neither evaluated nor rendered. Every part of the other
# side is then shown as added, beside a panel that says the part is not there.
for review in adopt explicit; do
  outputs=(-o "$WORK/$review.pdf" --summary "$WORK/$review.md")
  if [ "$review" = adopt ]; then
    trace_review "$ADOPT_LAYER" --base HEAD "${outputs[@]}"
  else
    trace_review "$EMPTY" "$ADOPT_LAYER" "${outputs[@]}"
  fi
  rg -q '^`[^`]+` has no design layer, so it is compared as an empty one\.$' "$WORK/$review.md"
  printf 'compile\nquery\nquery\n' | cmp - <(sort "$REVIEW_TEST_CALLS")
  python3 - "$WORK/adopt.json" "$WORK/$review.pdf" <<'PY'
import json
import re
import sys
from pathlib import Path
import pymupdf

changes = json.loads(Path(sys.argv[1]).read_text())["changes"]
report = pymupdf.open(sys.argv[2])
index = report[0].get_text()
assert "has no design layer, so it is compared as an empty one" in index, index
assert f"{len(changes)} confirmed · 0 need review" in index, index
statuses = [line for line in index.splitlines() if line in ("changed", "added", "removed")]
assert statuses and set(statuses) == {"added"}, statuses
assert sum(map(int, re.findall(r"(\d+) added", index))) == len(changes), index
for page in list(report)[1:]:
    assert "Before · not in this revision" in page.get_text(), page.get_text()
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
# The review's rules, each on one small layer. A long section inserted in the
# new design moves everything after it to later pages.
PAIRED="$WORK/paired"
write_paired() {
  local side="$1" word="$2" unit_title="$3" divisor="$4"
  mkdir -p "$PAIRED/$side"
  cat >"$PAIRED/$side/design.typ" <<EOF
#import ".render/designlib.typ": *
#let title = [Paired fixture]
#let body = [
  #section(title: [Alpha], body: [The first section says $word here.])
  #if "$side" == "after" { section(title: [Inserted], body: [INSERTEDTEXT #lorem(1400)]) }
  #section(title: [Beta], body: [UNCHANGEDBETA stays as it is.])
  #section(title: [Units], body: [
    #unit(
      id: "ledger",
      title: "$unit_title",
      overview: [Keeps the entries.],
      interface: ([\`post\`],),
      invariants: ([Every entry balances.],),
      side-effects: (),
      verification: [The self-tests.],
      paths: ("scripts",),
    )
  ])
  #section(title: [Rates], body: [
    #formula(title: [Rate])[\$ r = a / $divisor \$]
  ])
]
EOF
}
write_paired before OLDWORD "Ledger" b
write_paired after NEWWORD "General ledger" c
"$APP" "$PAIRED/before" "$PAIRED/after" -o "$WORK/paired.pdf" --summary "$WORK/paired.md"
"$APP" "$PAIRED/before" "$PAIRED/after" --format json -o "$WORK/paired.json"
python3 - "$WORK/paired.pdf" "$WORK/paired.json" "$WORK/paired.md" <<'PY'
import json
import re
import sys
from pathlib import Path
import pymupdf

report = pymupdf.open(sys.argv[1])
changes = json.loads(Path(sys.argv[2]).read_text())["changes"]
summary = Path(sys.argv[3]).read_text()
index = report[0].get_text()
sheets = list(report)[1:]
everything = "\n".join(page.get_text() for page in report)
middle = sheets[0].rect.width / 2

def sheet(name):
    found = [p for p in sheets if name in p.get_text("text", clip=pymupdf.Rect(0, 0, p.rect.width, 28))]
    assert found, (name, index)
    return found

# The record comparison alone decides what is shown: the part without a
# listed change is left out, although the insertion moved it to another page.
assert {row["part"]["after"] for row in changes} == {
    "section root/Alpha", "section root/Inserted", "unit ledger", "section root/Rates",
}, changes
assert "UNCHANGEDBETA" not in everything and "Beta" not in index, index

# The three outputs agree on the counts.
uncertain = sum(row["kind"] == "needs-review" for row in changes)
assert uncertain == 1 and f"{len(changes) - 1} confirmed · 1 need review" in index, index
assert summary.startswith(f"<!-- design-review changes={len(changes)} -->\n"), summary
rows = index.split("left out.", 1)[1].split("Need review", 1)[0]
counted = sum(map(int, re.findall(r"(\d+) (?:changed|added|removed|need review)", rows)))
assert counted == len(changes), (counted, len(changes), index)

# Old on the left, new on the right, with the changed words marked on each.
(alpha,) = sheet("Alpha")
(old_word,), (new_word,) = alpha.search_for("OLDWORD"), alpha.search_for("NEWWORD")
assert old_word.x1 < middle < new_word.x0, (old_word, new_word)
marks = [d for d in alpha.get_drawings() if d.get("fill") and d.get("fill_opacity", 1) < 1]
assert any(d["rect"].intersects(old_word) for d in marks), marks
assert any(d["rect"].intersects(new_word) for d in marks), marks

# A part in one revision alone is added, and shown in full beside an empty side.
inserted = sheet("Inserted")
assert len(inserted) >= 2 and "ADDED" in inserted[0].get_text(), inserted[0].get_text()
assert all("Before · not in this revision" in page.get_text() for page in inserted)

# A unit is paired by its id: a new title is a change, not a removal and an addition.
(unit,) = sheet("General ledger")
assert "CHANGED" in unit.get_text() and "Before · page" in unit.get_text(), unit.get_text()
assert unit.search_for("General")[-1].x0 > middle

# A changed formula is boxed on both sides and left to a person.
(rates,) = sheet("Rates")
tags = rates.search_for("formula needs review")
assert len(tags) == 2 and tags[0].x1 < middle < tags[1].x0, tags
assert "Need review" in index and "Formula notation changed" in index, index
change = next(row for row in changes if row["kind"] == "needs-review")
assert change["block"] == {"before": ["formula", 1], "after": ["formula", 1]}, change

PY

# Harder layouts, one section each: a title that holds a library call, a
# landscape page, and a figure that breaks across two pages.
EDGE="$WORK/edge"
for side in before after; do
  mkdir -p "$EDGE/$side"
  cat >"$EDGE/$side/design.typ" <<'EOF'
#import ".render/designlib.typ": *
#let title = [Edge fixture]
#let body = [
  #section(title: [Decision #adr(12)], body: [The decided word is @WORD@.])
  #section(title: [Wide], body: [
    Before the wide page.
    #page(flipped: true)[#align(right)[FARRIGHT @WORD@ end]]
  ])
  #section(title: [Drawing], body: [
    #v(300pt)
    #figure-block(caption: [A tall drawing.], uses: ("cetz",))[```typst
    #rect(width: 100pt, height: @HEIGHT@)
    ```]
  ])
]
EOF
done
sed -i.bak -e 's/@WORD@/OLDWORD/g' -e 's/@HEIGHT@/600pt/' "$EDGE/before/design.typ"
sed -i.bak -e 's/@WORD@/NEWWORD/g' -e 's/@HEIGHT@/610pt/' "$EDGE/after/design.typ"
rm "$EDGE"/*/design.typ.bak
"$APP" "$EDGE/before" "$EDGE/after" -o "$WORK/edge.pdf"
python3 - "$WORK/edge.pdf" <<'PY'
import sys
import pymupdf

report = pymupdf.open(sys.argv[1])
sheets = list(report)[1:]

def sheet(name):
    found = [p for p in sheets if name in p.get_text("text", clip=pymupdf.Rect(0, 0, p.rect.width, 28))]
    assert found, (name, report[0].get_text())
    return found

def marked(page, word):
    marks = [d for d in page.get_drawings() if d.get("fill") and d.get("fill_opacity", 1) < 1]
    return all(any(d["rect"].intersects(hit) for d in marks) for hit in page.search_for(word))

# A library call in a title renders differently where the records are read
# and where the page is drawn. The part is still found, by its place in order.
(decision,) = sheet("Decision")
assert decision.search_for("OLDWORD") and decision.search_for("NEWWORD"), decision.get_text()
assert "no visible mark" not in decision.get_text()

# A landscape page is shown whole, on a wider sheet, with its marks on its words.
wide = next(p for p in sheet("Wide") if p.search_for("FARRIGHT"))
assert wide.rect.width > decision.rect.width, (wide.rect, decision.rect)
assert len(wide.search_for("FARRIGHT")) == 2, wide.get_text()
assert marked(wide, "OLDWORD") and marked(wide, "NEWWORD")

# A figure that breaks across pages is boxed on both pages, on each side.
tags = sum(len(p.search_for("figure needs review")) for p in sheet("Drawing"))
assert tags == 4, tags
PY

# An index longer than one page: every line still leads to the sheet of its part.
MANY="$WORK/many"
for side in before after; do
  mkdir -p "$MANY/$side"
  {
    printf '#import ".render/designlib.typ": *\n#let title = [Many]\n#let body = [\n'
    for n in $(seq 101 150); do
      printf '  #section(title: [Part %s], body: [Text of the %s design.])\n' "$n" "$side"
    done
    printf ']\n'
  } >"$MANY/$side/design.typ"
done
"$APP" "$MANY/before" "$MANY/after" -o "$WORK/many.pdf"
python3 - "$WORK/many.pdf" <<'PY'
import re
import sys
import pymupdf

report = pymupdf.open(sys.argv[1])
index = [page for page in report if "Design review" in page.get_text("text", clip=pymupdf.Rect(0, 0, 400, 50))]
assert len(index) == 2, len(index)
followed = 0
for page in index:
    for link in page.get_links():
        row = page.get_text("text", clip=link["from"])
        (name,) = re.findall(r"Part \d+", row)
        target = report[link["page"]]
        title = target.get_text("text", clip=pymupdf.Rect(0, 0, target.rect.width, 28))
        assert name in title and f"page {link['page'] + 1}" in row, (row, title)
        followed += 1
assert followed == 50, followed
PY

# A review place draws nothing and moves nothing: the gallery is laid out the
# same with the places switched on.
typst compile "$WORK/baseline.typ" "$WORK/plain.pdf"
typst compile --input review-places=1 "$WORK/baseline.typ" "$WORK/placed.pdf"
pdftotext -bbox "$WORK/plain.pdf" "$WORK/plain.bbox"
pdftotext -bbox "$WORK/placed.pdf" "$WORK/placed.bbox"
cmp "$WORK/plain.bbox" "$WORK/placed.bbox"
test "$(typst query --input review-places=1 "$WORK/baseline.typ" '<design-review-place>' --field value | python3 -c 'import json,sys; print(len({p["kind"] for p in json.load(sys.stdin)} & {"section","unit","diagram","figure-block","formula","page"}))')" = 6
test "$(typst query "$WORK/baseline.typ" '<design-review-place>')" = "[]"
# The same holds for a whole layer, where the chapters and the glossary are
# marked as well.
python3 - "$ROOT" "$PAIRED/after" "$WORK" <<'PY'
from pathlib import Path
import subprocess
import sys

root, layer, work = (Path(path).resolve() for path in sys.argv[1:])
sys.path.insert(0, str(root / "scripts"))
from design_pdf import render_layer
from design_source import projection_layer

# The review left the layer its own copy of the library; compile against it.
source, library = projection_layer(layer), (layer / ".render" / "designlib.typ").resolve()
places = []
assert render_layer(source, work / "layer-plain.pdf", False, library) == 0
assert render_layer(source, work / "layer-placed.pdf", False, library, places=places) == 0
assert {"document", "section", "unit", "formula", "page"} <= {p["kind"] for p in places}, places
boxes = [
    subprocess.run(["pdftotext", "-bbox", work / name, "-"], capture_output=True, check=True).stdout
    for name in ("layer-plain.pdf", "layer-placed.pdf")
]
assert boxes[0] == boxes[1]
PY

echo "design-review: Git, cross-section identity, the side-by-side PDF, the summary, duplicate detection and missing layers passed"
