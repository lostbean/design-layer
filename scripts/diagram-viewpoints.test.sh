#!/usr/bin/env bash
#
# diagram-viewpoints.test.sh — viewpoint-aware solved structure diagrams.
#
# This suite exercises only the public `diagram(...)` and `diagram-native(...)`
# authoring surfaces. It reads PDF text and SVG marks because a successful
# compile alone does not prove that boundaries, legends, shapes, or relation
# styles reached the rendered document.
#
# Usage: diagram-viewpoints.test.sh [repo-root]
# Exit: 0 all assertions pass, 1 an assertion failed, 2 a tool is missing.
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1

TYPST="${TYPST:-typst}"
for tool in "$TYPST" pdftotext python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "diagram-viewpoints: error: no $tool on PATH (enter the dev shell)" >&2
    exit 2
  fi
done

WORK="$(mktemp -d)"
if [ "${KEEP_DIAGRAM_VIEWPOINT_WORK:-0}" = "1" ]; then
  printf 'diagram-viewpoints: work directory %s\n' "$WORK"
else
  trap 'rm -rf "$WORK"' EXIT
fi

if ! bash ./scripts/render-project schema/design-schema.json "$WORK" >/dev/null; then
  echo "diagram-viewpoints: could not assemble the renderer" >&2
  exit 2
fi

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

fixture() {
  printf '#import "designlib.typ": *\n%s\n' "$2" >"$WORK/$1.typ"
}

compile_pdf() {
  local name="$1"
  env TYPST_PACKAGE_PATH="$WORK/nope" TYPST_PACKAGE_CACHE_PATH="$WORK/nope" \
    "$TYPST" compile --root "$WORK" "$WORK/$name.typ" "$WORK/$name.pdf" 2>&1
}

compile_svg() {
  local name="$1"
  env TYPST_PACKAGE_PATH="$WORK/nope" TYPST_PACKAGE_CACHE_PATH="$WORK/nope" \
    "$TYPST" compile --format svg --root "$WORK" "$WORK/$name.typ" \
    "$WORK/$name.svg" 2>&1
}

assert_renders() {
  local name="$1" body="$2"
  fixture "$name" "$body"
  local out
  out="$(compile_pdf "$name")"
  if [ -f "$WORK/$name.pdf" ]; then
    pass_line "$name renders"
  else
    fail_line "$name did not render"
    printf '%s\n' "$out" | head -5 | sed 's/^/       /'
  fi
}

assert_invariant() {
  local name="$1" needle="$2" body="$3"
  fixture "$name" "$body"
  local out
  out="$(compile_pdf "$name")"
  if [ -f "$WORK/$name.pdf" ]; then
    fail_line "$name compiled, but the invariant should have stopped it"
    return
  fi
  case "$out" in
  *"$needle"*) pass_line "invariant: $name names its rule" ;;
  *)
    fail_line "$name failed, but did not name '$needle'"
    printf '%s\n' "$out" | head -4 | sed 's/^/       /'
    ;;
  esac
}

echo "diagram-viewpoints: solved diagram viewpoints and boundaries"

# One fixture uses every declared group kind, node kind, and relation. The
# labels are intentionally unique so PDF extraction proves the diagram and its
# generated legend reached the page rather than merely compiling.
fixture enriched '#set page(width: 900pt, height: 900pt, margin: 24pt)
#diagram(
  altitude: "L2",
  viewpoint: "context-ownership",
  title: "Zviewpoint map",
  groups: (
    (id: "enterprise", label: "Zenterprise", kind: "domain", tint: "teal"),
    (id: "sales", label: "Zsales", kind: "subdomain", parent: "enterprise"),
    (id: "booking", label: "Zbooking", kind: "bounded-context", parent: "sales"),
    (id: "platform", label: "Zplatform", kind: "runtime", tint: "blue"),
    (id: "workload", label: "Zworkload", kind: "subsystem", parent: "platform"),
    (id: "cluster", label: "Zcluster", kind: "deployment", tint: "violet"),
  ),
  nodes: (
    (id: "actor", label: "Zactor", kind: "actor", group: "enterprise", external: true),
    (id: "system", label: "Zsystem", kind: "system", group: "enterprise"),
    (id: "aggregate", label: "Zaggregate", kind: "aggregate", group: "booking"),
    (id: "entity", label: "Zentity", kind: "entity", group: "booking"),
    (id: "value", label: "Zvalue", kind: "value-object", group: "booking"),
    (id: "event", label: "Zevent", kind: "event", group: "booking"),
    (id: "frontend", label: "Zfrontend", kind: "frontend", group: "workload"),
    (id: "backend", label: "Zbackend", kind: "backend", group: "workload"),
    (id: "service", label: "Zservice", kind: "service", group: "workload"),
    (id: "component", label: "Zcomponent", kind: "component", group: "workload"),
    (id: "queue", label: "Zqueue", kind: "queue", group: "platform"),
    (id: "topic", label: "Ztopic", kind: "topic", group: "platform"),
    (id: "database", label: "Zdatabase", kind: "database", group: "cluster"),
    (id: "external", label: "Zexternal", kind: "external-system", group: "cluster"),
  ),
  edges: (
    (from: "actor", to: "frontend", relation: "call", label: "Zcalls"),
    (from: "backend", to: "service", relation: "dependency", label: "Zdepends"),
    (from: "service", to: "topic", relation: "pubsub", label: "Zpublishes"),
    (from: "queue", to: "database", relation: "dataflow", label: "Zflows"),
  ),
)'
out="$(compile_pdf enriched)"
if [ ! -f "$WORK/enriched.pdf" ]; then
  fail_line "the enriched viewpoint diagram did not render"
  printf '%s\n' "$out" | head -7 | sed 's/^/       /'
else
  text="$(pdftotext "$WORK/enriched.pdf" - 2>/dev/null | tr -s '[:space:]' ' ')"
  missing=""
  for mark in \
    Zviewpoint Zenterprise Zsales Zbooking Zplatform Zworkload Zcluster \
    Zactor Zsystem Zaggregate Zentity Zvalue Zevent Zfrontend Zbackend \
    Zservice Zcomponent Zqueue Ztopic Zdatabase Zexternal \
    Zcalls Zdepends Zpublishes Zflows; do
    case "$text" in
    *"$mark"*) ;;
    *) missing="$missing $mark" ;;
    esac
  done
  if [ -z "$missing" ]; then
    pass_line "nested groups, nodes, and explicit relation labels reach the PDF"
  else
    fail_line "the enriched PDF omits:$missing"
  fi

  squeezed="$(printf '%s' "$text" | tr -cd 'A-Za-z0-9')"
  badge="${squeezed%%Zviewpointmap*}"
  if [ "$badge" = "VIEWPOINTCONTEXTOWNERSHIPALTITUDEL2CONTEXTS" ]; then
    pass_line "viewpoint and altitude are both visible"
  else
    fail_line "viewpoint and altitude are not both visible"
    printf '       badge text: %s\n' "$badge"
  fi

  boundary_missing=""
  for label in DOMAIN SUBDOMAIN BOUNDEDCONTEXT RUNTIME DEPLOYMENT SUBSYSTEM; do
    case "$squeezed" in
    *"$label"*) ;;
    *) boundary_missing="$boundary_missing $label" ;;
    esac
  done
  if [ -z "$boundary_missing" ]; then
    pass_line "every used boundary kind is explicitly labelled"
  else
    fail_line "boundary-kind labels are absent:$boundary_missing"
  fi

  # Preserve layout while reading the legend. The legend spans two rows, and
  # the default extractor may interleave columns before a role phrase is
  # complete even though the phrase is visibly contiguous on the page.
  legend_text="$(pdftotext -layout "$WORK/enriched.pdf" - 2>/dev/null |
    tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]\n')"
  legend_missing=""
  for label in \
    "actor · person or role" "system · endpoint" aggregate entity "value object" \
    "event · domain fact" "frontend · user-facing component" \
    "backend · system endpoint" "service · internal service" \
    "component · owned runtime part" "queue · work channel" \
    "topic · event stream" "database · persistent store" \
    "external system · trust boundary" dependency call pubsub dataflow; do
    normalized="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
    case "$legend_text" in
    *"$normalized"*) ;;
    *) legend_missing="$legend_missing [$label]" ;;
    esac
  done
  if [ -z "$legend_missing" ]; then
    pass_line "the generated legend names every used node and relation kind"
  else
    fail_line "the generated legend omits:$legend_missing"
  fi

  case "$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')" in
  *durab* | *ordered* | *delivery*)
    fail_line "pubsub styling inferred durability, ordering, or delivery semantics"
    ;;
  *) pass_line "pubsub conveys only its explicit directional label" ;;
  esac

  svg_out="$(compile_svg enriched)"
  if [ ! -f "$WORK/enriched.svg" ]; then
    fail_line "the enriched viewpoint diagram did not render as SVG"
    printf '%s\n' "$svg_out" | head -5 | sed 's/^/       /'
  elif python3 - "$WORK/enriched.svg" <<'PYTEST'; then
import base64
import re
import sys

svg = open(sys.argv[1], encoding="utf-8").read()
payloads = re.findall(r'data:image/svg\+xml;base64,([^" ]+)', svg)
if not payloads:
    raise SystemExit("Typst SVG contains no embedded Graphviz SVG")
graph = base64.b64decode(max(payloads, key=len)).decode("utf-8")

def block(kind, title):
    match = re.search(
        r'<g id="[^"]+" class="%s">\s*<title>%s</title>(.*?)</g>'
        % (kind, re.escape(title)), graph, re.S)
    if not match:
        raise SystemExit("missing Graphviz %s %s" % (kind, title))
    return match.group(1)

# These are Graphviz cluster marks, not decorative Typst frames. The nested
# ownership chain and nested runtime chain each remain separate solver-owned
# boundaries in the output.
for name in (
    "cluster_enterprise", "cluster_sales", "cluster_booking",
    "cluster_platform", "cluster_workload", "cluster_cluster",
):
    block("cluster", name)

domain = block("cluster", "cluster_enterprise")
bounded_context = block("cluster", "cluster_booking")
runtime = block("cluster", "cluster_platform")
deployment = block("cluster", "cluster_cluster")
if "stroke-dasharray" in domain:
    raise SystemExit("ownership boundary unexpectedly uses a runtime/deployment line")
if 'stroke-width="1.8"' not in bounded_context:
    raise SystemExit("bounded-context boundary has no distinct ownership weight")
if 'stroke-dasharray="5,2"' not in runtime:
    raise SystemExit("runtime boundary has no distinct dashed treatment")
if 'stroke-dasharray="1,5"' not in deployment:
    raise SystemExit("deployment boundary has no distinct dotted treatment")

# Representative node kinds retain distinct Graphviz silhouettes.
if "<ellipse" not in block("node", "actor"):
    raise SystemExit("actor is not shaped as an actor")
if "<polygon" not in block("node", "value"):
    raise SystemExit("value object is not shaped as a value object")
if block("node", "database").count("<path") < 2:
    raise SystemExit("database has no database silhouette")
if block("node", "frontend").count("<polyline") < 2:
    raise SystemExit("frontend has no component silhouette")
if block("node", "system").count("<polyline") < 2:
    raise SystemExit("system endpoint has no box3d silhouette")
if block("node", "backend").count("<polyline") < 2:
    raise SystemExit("backend endpoint has no box3d silhouette")
if "<polyline" in block("node", "service"):
    raise SystemExit("internal service incorrectly uses an endpoint silhouette")
queue = block("node", "queue")
queue_path = re.search(r'<path[^>]* d="([^"]+)"', queue)
if not queue_path:
    raise SystemExit("queue has no visible Graphviz path")
points = [
    (float(x), float(y))
    for x, y in re.findall(r'(-?[0-9.]+),(-?[0-9.]+)', queue_path.group(1))
]
if not points:
    raise SystemExit("queue path has no measurable points")
top = min(y for _, y in points)
bottom = max(y for _, y in points)
top_x = [x for x, y in points if abs(y - top) < 0.01]
bottom_x = [x for x, y in points if abs(y - bottom) < 0.01]
if len(top_x) < 2 or len(bottom_x) < 2:
    raise SystemExit("queue path has no measurable top and bottom edges")
left_shift = min(top_x) - min(bottom_x)
right_shift = max(top_x) - max(bottom_x)
if left_shift < 1 or right_shift < 1:
    raise SystemExit("queue path does not retain offset parallelogram edges")
# Relation styling stays directional and distinct. The explicit labels are
# asserted in the PDF above; these checks assert only their line treatments.
call = block("edge", "actor&#45;&gt;frontend")
dependency = block("edge", "backend&#45;&gt;service")
pubsub = block("edge", "service&#45;&gt;topic")
dataflow = block("edge", "queue&#45;&gt;database")
if "stroke-dasharray" in call:
    raise SystemExit("call is not a solid directional relation")
if 'stroke-dasharray="5,2"' not in dependency:
    raise SystemExit("dependency is not dashed")
if 'stroke-dasharray="1,5"' not in pubsub:
    raise SystemExit("pubsub has no distinct directional style")
if 'stroke-width="1.8"' not in dataflow:
    raise SystemExit("dataflow has no distinct weighted style")

# External trust is dashed and bold, while deployment is dotted. A deployment
# boundary therefore cannot be mistaken for an external trust boundary.
external = block("node", "external")
if 'stroke-dasharray="5,2"' not in external:
    raise SystemExit("external system has no trust-boundary treatment")
if not re.search(r'stroke-width="2(?:\.0)?"', external):
    raise SystemExit("external trust boundary is not visually explicit")
PYTEST
    pass_line "SVG retains distinct cluster, shape, relation, and trust treatments"
  else
    fail_line "SVG does not retain distinct cluster, shape, relation, and trust treatments"
  fi
fi

# Existing solved tuple edges remain valid, including their legacy dashed
# fourth field. This is the compatibility seam for existing design layers.
assert_renders legacy-solved '#diagram(
  altitude: "L2",
  nodes: ((id: "a", label: "Zlegacy-a", external: true), (id: "b", label: "Zlegacy-b")),
  edges: (("a", "b", "Zlegacy-edge", "dashed"),),
)'
legacy_svg_out="$(compile_svg legacy-solved)"
if [ ! -f "$WORK/legacy-solved.svg" ]; then
  fail_line "legacy solved diagram did not render as SVG"
  printf '%s\n' "$legacy_svg_out" | head -5 | sed 's/^/       /'
elif python3 - "$WORK/legacy-solved.svg" <<'PYTEST'; then
import base64, re, sys
svg = open(sys.argv[1], encoding="utf-8").read()
payload = max(re.findall(r'data:image/svg\+xml;base64,([^" ]+)', svg), key=len)
graph = base64.b64decode(payload).decode("utf-8")
node = re.search(r'<g id="[^"]+" class="node">\s*<title>a</title>(.*?)</g>', graph, re.S)
if not node or "<path" not in node.group(1) or 'stroke-dasharray="5,2"' not in node.group(1):
    raise SystemExit("legacy external node lost its rounded dashed treatment")
if 'stroke-width="2"' in node.group(1):
    raise SystemExit("legacy external node acquired the new trust-boundary weight")
PYTEST
  pass_line "legacy external nodes retain their rounded dashed treatment"
else
  fail_line "legacy external node treatment changed"
fi

# Validation is local to one diagram. Reusing group and node ids in another
# viewpoint does not imply or require a cross-view registry.
assert_renders per-diagram-scope '#diagram(
  altitude: "L1", viewpoint: "business-domain",
  groups: ((id: "same", label: "First", kind: "domain"),),
  nodes: ((id: "same-node", label: "First node", kind: "system", group: "same"),),
)
#diagram(
  altitude: "L4", viewpoint: "runtime",
  groups: ((id: "same", label: "Second", kind: "runtime"),),
  nodes: ((id: "same-node", label: "Second node", kind: "service", group: "same"),),
)'

# `diagram-native` retains its positioned Typst-content contract and does not
# acquire solved-diagram viewpoint or grouping arguments.
assert_renders legacy-native '#diagram-native(
  altitude: "L3",
  nodes: ((id: "a", pos: (0, 0), label: [Znative-a]),
          (id: "b", pos: (1, 0), label: [Znative-b])),
  edges: (("a", "b", [Znative-edge]),),
)'
assert_invariant native-unchanged "unexpected argument" \
  '#diagram-native(altitude: "L3", viewpoint: "runtime", nodes: ())'

# Closed vocabularies fail by field name so an author can correct the value at
# the call site without knowing the renderer implementation.
assert_invariant viewpoint-enum "diagram viewpoint" \
  '#diagram(altitude: "L2", viewpoint: "transition", nodes: ())'
assert_invariant group-kind-enum "diagram group kind" \
  '#diagram(altitude: "L2", groups: ((id: "g", label: "G", kind: "team"),), nodes: ())'
assert_invariant node-kind-enum "diagram node kind" \
  '#diagram(altitude: "L2", nodes: ((id: "a", label: "A", kind: "process"),))'
assert_invariant relation-enum "diagram edge relation" \
  '#diagram(altitude: "L2", nodes: ((id: "a", label: "A"), (id: "b", label: "B")), edges: ((from: "a", to: "b", relation: "transition", label: "go"),))'
assert_invariant relation-label-empty "requires a non-empty string label" \
  '#diagram(altitude: "L2", nodes: ((id: "a", label: "A"), (id: "b", label: "B")), edges: ((from: "a", to: "b", relation: "call", label: "  "),))'
assert_invariant relation-label-missing "dictionary edge is missing label" \
  '#diagram(altitude: "L2", nodes: ((id: "a", label: "A"), (id: "b", label: "B")), edges: ((from: "a", to: "b", relation: "call"),))'

# Identity and ownership invariants are checked before Graphviz sees the data.
assert_invariant duplicate-node-id "duplicate diagram node id" \
  '#diagram(altitude: "L2", nodes: ((id: "same", label: "A"), (id: "same", label: "B")))'
assert_invariant duplicate-group-id "duplicate diagram group id" \
  '#diagram(altitude: "L2", groups: ((id: "same", label: "A", kind: "domain"), (id: "same", label: "B", kind: "subdomain")), nodes: ())'
assert_invariant group-missing-id "diagram group is missing id" \
  '#diagram(altitude: "L2", groups: ((label: "A", kind: "domain"),), nodes: ())'
assert_invariant group-missing-label "diagram group is missing label" \
  '#diagram(altitude: "L2", groups: ((id: "g", kind: "domain"),), nodes: ())'
assert_invariant group-missing-kind "diagram group is missing kind" \
  '#diagram(altitude: "L2", groups: ((id: "g", label: "G"),), nodes: ())'
assert_invariant parent-unknown "not a declared diagram group" \
  '#diagram(altitude: "L2", groups: ((id: "g", label: "G", kind: "domain", parent: "ghost"),), nodes: ())'
assert_invariant parent-self "cannot parent itself" \
  '#diagram(altitude: "L2", groups: ((id: "g", label: "G", kind: "domain", parent: "g"),), nodes: ())'
assert_invariant parent-cycle "diagram group parent cycle" \
  '#diagram(altitude: "L2", groups: ((id: "a", label: "A", kind: "domain", parent: "b"), (id: "b", label: "B", kind: "subdomain", parent: "a")), nodes: ())'
assert_invariant node-membership-missing "diagram node is missing group" \
  '#diagram(altitude: "L2", groups: ((id: "g", label: "G", kind: "domain"),), nodes: ((id: "a", label: "A", kind: "system"),))'
assert_invariant node-membership-unknown "not a declared diagram group" \
  '#diagram(altitude: "L2", groups: ((id: "g", label: "G", kind: "domain"),), nodes: ((id: "a", label: "A", kind: "system", group: "ghost"),))'
assert_invariant node-membership-without-groups "not a declared diagram group" \
  '#diagram(altitude: "L2", nodes: ((id: "a", label: "A", kind: "system", group: "ghost"),))'

# Both dictionary and legacy edges resolve endpoints inside their own diagram.
assert_invariant dictionary-edge-endpoint "not a declared node" \
  '#diagram(altitude: "L2", nodes: ((id: "a", label: "A"),), edges: ((from: "a", to: "ghost", relation: "call", label: "calls"),))'
assert_invariant legacy-edge-endpoint "not a declared node" \
  '#diagram(altitude: "L2", nodes: ((id: "a", label: "A"),), edges: (("a", "ghost", "calls"),))'

# Schema mutations prove the declared vocabularies remain non-vacuous and that
# every declared structural kind has an explicit renderer implementation.
cp "$WORK/design-schema.json" "$WORK/design-schema.original.json"
python3 - "$WORK/design-schema.json" <<'PYTEST'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
data["design_doc"]["diagram_contract"]["relations"].append("stream")
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle)
PYTEST
assert_invariant schema-relation-totality "has no renderer implementation" \
  '#diagram(altitude: "L2", nodes: ((id: "a", label: "A"),))'
cp "$WORK/design-schema.original.json" "$WORK/design-schema.json"
python3 - "$WORK/design-schema.json" <<'PYTEST'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
data["design_doc"]["diagram_contract"]["viewpoints"] = []
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle)
PYTEST
assert_invariant schema-viewpoint-nonempty "diagram_contract.viewpoints is empty" \
  '#diagram(altitude: "L2", nodes: ((id: "a", label: "A"),))'
cp "$WORK/design-schema.original.json" "$WORK/design-schema.json"

printf 'diagram-viewpoints: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
