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
fixture enriched '#set page(width: 900pt, height: 1200pt, margin: 24pt)
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
    (id: "system", label: "Zsystem", sub: "secondary", kind: "system", group: "enterprise"),
    (id: "aggregate", label: "Zaggregate", kind: "aggregate", group: "booking"),
    (id: "context", label: "Zcontext", sub: "domain owner", kind: "bounded-context", group: "booking"),
    (id: "entity", label: "Zentity", kind: "entity", group: "booking"),
    (id: "value", label: "Zvalue", kind: "value-object", group: "booking"),
    (id: "event", label: "Zevent", kind: "event", group: "booking"),
    (id: "frontend", label: "Zfrontend", kind: "frontend", group: "workload"),
    (id: "backend", label: "Zbackend", sub: "secondary", kind: "backend", group: "workload"),
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
    Zactor Zsystem secondary Zaggregate Zcontext "domain owner" Zentity Zvalue Zevent Zfrontend Zbackend \
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
  case "$squeezed" in
  *VIEWPOINTCONTEXTOWNERSHIPALTITUDEL2CONTEXTS*)
    pass_line "viewpoint and altitude are both visible"
    ;;
  *)
    fail_line "viewpoint and altitude are not both visible"
    ;;
  esac

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

  # Read only the legend chapter of the rendered output. The graph deliberately
  # puts role labels on separate lines beside marks, so assert each role word
  # and its distinguishing phrase independently instead of relying on column
  # order from a PDF text extractor.
  legend_text="$(pdftotext "$WORK/enriched.pdf" - 2>/dev/null |
    sed -n '/LEGEND/,$p' | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
  legend_missing=""
  for label in \
    actor "person or role" "bounded context" system endpoint aggregate entity \
    "value object" event "domain fact" frontend "user-facing component" \
    backend "system endpoint" service "internal service" component \
    "owned runtime part" queue "work channel" topic "event stream" database \
    "persistent store" "external system" "trust boundary" dependency call pubsub dataflow; do
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
graphs = [base64.b64decode(payload).decode("utf-8") for payload in payloads]
graph = next((item for item in graphs if "<title>cluster_enterprise</title>" in item), None)
if graph is None:
    raise SystemExit("main Graphviz graph is not present")

def block(kind, title):
    match = re.search(
        r'<g id="[^"]+" class="%s">\s*<title>%s</title>(.*?)</g>'
        % (kind, re.escape(title)), graph, re.S)
    if not match:
        raise SystemExit("missing Graphviz %s %s" % (kind, title))
    return match.group(1)

legend_payloads = [item for item in graphs if "legend_" in item]
if len(legend_payloads) != 25:
    raise SystemExit("legend payload count does not match 6 groups + 15 nodes + 4 relations: %d" % len(legend_payloads))
for payload in legend_payloads:
    if "<text" in payload:
        raise SystemExit("legend carrier payload contains text inside a symbol")
images = list(re.finditer(
    r'<image[^>]*xlink:href="data:image/svg\+xml;base64,([^" ]+)" '
    r'width="([0-9.eE+-]+)" height="([0-9.eE+-]+)"', svg,
))
if len(images) != 26:
    raise SystemExit("expected one main graph plus 25 bounded legend symbols")
for image in images[1:]:
    scales = re.findall(
        r'transform="matrix\(([0-9.eE+-]+) 0 0 ([0-9.eE+-]+) [^"]+\)"',
        svg[:image.start()],
    )
    if not scales:
        raise SystemExit("legend symbol has no scale transform")
    scale_x, scale_y = map(float, scales[-1])
    width, height = map(float, image.groups()[1:])
    if width * scale_x > 38.1 or height * scale_y > 22.1:
        raise SystemExit(
            "legend symbol exceeds its fixed area: %.2fpt x %.2fpt"
            % (width * scale_x, height * scale_y)
        )

def legend_mark(title):
    encoded = title.replace("-", "&#45;").replace(">", "&gt;")
    needle = "<title>" + encoded + "</title>"
    match = next((item for item in legend_payloads if needle in item), None)
    if match is None:
        raise SystemExit("missing legend Graphviz mark %s" % title)
    return match

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
if "<polygon" not in block("node", "database"):
    raise SystemExit("database has no flat datastore silhouette")
if block("node", "frontend").count("<polyline") < 2:
    raise SystemExit("frontend has no component silhouette")
for kind, title in (("system", "system"), ("backend", "backend"),
                    ("service", "service"), ("bounded-context", "context")):
    if "<polyline" in block("node", title):
        raise SystemExit("%s uses a depth-cue silhouette" % kind)
if "<polygon" not in block("node", "context") and \
   "<path" not in block("node", "context"):
    raise SystemExit("bounded-context has no direct context mark")
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

# The legend uses the same emitted marks as the main graph. It carries only
# kinds and relations present in this diagram, with direct shape evidence.
for kind, expected in (
    ("actor", "<ellipse"),
    ("system", "<path"),
    ("bounded-context", "<path"),
    ("database", "<polygon"),
    ("frontend", "<polygon"),
    ("external-system", "<polygon"),
):
    if expected not in legend_mark("legend_node_mark_" + kind):
        raise SystemExit("legend mark for %s is not the graph shape" % kind)
for kind in ("domain", "subdomain", "bounded-context", "runtime", "subsystem", "deployment"):
    boundary = legend_mark("cluster_legend_group_" + kind)
    if "<path" not in boundary:
        raise SystemExit("legend boundary %s has no carrier stroke" % kind)
    if '<g id="' in boundary and 'class="node"' in boundary:
        raise SystemExit("legend boundary %s contains a fake inner node" % kind)
for kind in (
    "actor", "bounded-context", "system", "aggregate", "entity", "value-object",
    "event", "frontend", "backend", "service", "component", "queue", "topic",
    "database", "external-system",
):
    legend_mark("legend_node_mark_" + kind)
for relation in ("call", "dependency", "pubsub", "dataflow"):
    relation_mark = legend_mark(
        "legend_relation_from_" + relation + "->legend_relation_to_" + relation,
    )
    if '<g id="' not in relation_mark or 'class="edge"' not in relation_mark:
        raise SystemExit("legend relation mark %s is missing its carrier edge" % relation)
if 'stroke-dasharray="5,2"' not in legend_mark("legend_relation_from_dependency->legend_relation_to_dependency"):
    raise SystemExit("legend dependency lost its dashed treatment")
if 'stroke-dasharray="1,5"' not in legend_mark("legend_relation_from_pubsub->legend_relation_to_pubsub"):
    raise SystemExit("legend pubsub lost its dotted treatment")
if 'stroke-width="1.8"' not in legend_mark("legend_relation_from_dataflow->legend_relation_to_dataflow"):
    raise SystemExit("legend dataflow lost its weighted treatment")
PYTEST
    pass_line "SVG retains distinct cluster, shape, relation, and trust treatments"
  else
    fail_line "SVG does not retain distinct cluster, shape, relation, and trust treatments"
  fi
fi

# The five-column grid keeps column centers stable across wrapped rows. The symbol area is
# bounded independently of the carrier's natural aspect ratio, so a tall
# boundary or wide queue cannot change its cell geometry. Names are followed
# by their descriptions in the extracted text, proving labels sit outside the
# text-free Graphviz payloads.
pdftotext -bbox "$WORK/enriched.pdf" "$WORK/enriched-bbox.xml" 2>/dev/null
if python3 - "$WORK/enriched-bbox.xml" <<'PYTEST'; then
import re, sys

xml = open(sys.argv[1], encoding="utf-8").read()
legend_end = xml.find(">LEGEND</word>")
legend_start = xml.rfind("<word", 0, legend_end)
if legend_start < 0:
    raise SystemExit("missing legend heading")
legend_xml = xml[legend_start:]
def boxes(word):
    return [
        tuple(map(float, match.groups()))
        for match in re.finditer(
            r'<word xMin="([0-9.]+)" yMin="([0-9.]+)" '
            r'xMax="([0-9.]+)" yMax="([0-9.]+)">%s</word>' % re.escape(word),
            legend_xml,
        )
    ]

def legend_box(word):
    values = boxes(word)
    if not values:
        raise SystemExit("missing legend word %s" % word)
    return min(values, key=lambda value: value[1])

def center(word):
    box = legend_box(word)
    return (box[0] + box[2]) / 2

for words in (
    ("domain", "deployment", "entity", "service"),
    ("subdomain", "actor", "call"),
    ("system", "event", "queue", "dependency"),
    ("runtime", "aggregate", "frontend", "topic", "pubsub"),
    ("subsystem", "backend", "database", "dataflow"),
):
    columns = [center(word) for word in words]
    if max(columns) - min(columns) > 5:
        raise SystemExit("equal-width grid column drift: %r" % columns)

name = legend_box("actor")
description = min(boxes("person"), key=lambda value: value[1])
if description[1] <= name[1]:
    raise SystemExit("legend description does not follow its symbol name")
PYTEST
  pass_line "legend uses five aligned columns with labels below symbols"
else
  fail_line "legend columns or external label order is not stable"
fi

# Relation cells flow through the same five-column grid as mark cells. Six
# marks and three relations therefore occupy two compact rows.
fixture aligned-relations '#set page(width: 500pt, height: 800pt, margin: 24pt)
#diagram(
  altitude: "L2",
  title: "Zaligned",
  nodes: (
    (id: "actor", label: "Zactor", kind: "actor"),
    (id: "system", label: "Zsystem", kind: "system"),
    (id: "queue", label: "Zqueue", kind: "queue"),
    (id: "topic", label: "Ztopic", kind: "topic"),
    (id: "database", label: "Zdatabase", kind: "database"),
    (id: "event", label: "Zevent", kind: "event"),
  ),
  edges: (
    (from: "actor", to: "system", relation: "call", label: "Zcall"),
    (from: "system", to: "queue", relation: "dependency", label: "Zdependency"),
    (from: "queue", to: "topic", relation: "pubsub", label: "Zpubsub"),
  ),
)'
out="$(compile_pdf aligned-relations)"
if [ -f "$WORK/aligned-relations.pdf" ]; then
  pdftotext -bbox "$WORK/aligned-relations.pdf" "$WORK/aligned-relations.xml" 2>/dev/null
  if python3 - "$WORK/aligned-relations.xml" <<'PYTEST'; then
import re, sys

xml = open(sys.argv[1], encoding="utf-8").read()
legend_end = xml.find(">LEGEND</word>")
legend_start = xml.rfind("<word", 0, legend_end)
if legend_start < 0:
    raise SystemExit("missing legend heading")
legend_xml = xml[legend_start:]
def boxes(word):
    return [
        tuple(map(float, match.groups()))
        for match in re.finditer(
            r'<word xMin="([0-9.]+)" yMin="([0-9.]+)" '
            r'xMax="([0-9.]+)" yMax="([0-9.]+)">%s</word>' % re.escape(word),
            legend_xml,
        )
    ]

def legend_box(word, last=False):
    values = boxes(word)
    if not values:
        raise SystemExit("missing legend word %s" % word)
    return (max if last else min)(values, key=lambda value: value[1])

def center(word, last=False):
    box = legend_box(word, last)
    return (box[0] + box[2]) / 2

columns = [center(word) for word in ("actor", "system", "queue", "topic", "database")]
steps = [right - left for left, right in zip(columns, columns[1:])]
if max(steps) - min(steps) > 5:
    raise SystemExit("five-column grid drift: %r" % columns)
for upper, lower, last in (
    ("actor", "event", True),
    ("system", "call", False),
    ("queue", "dependency", False),
    ("topic", "pubsub", False),
):
    if abs(center(upper) - center(lower, last)) > 5:
        raise SystemExit("wrapped cell %s does not align below %s" % (lower, upper))
def y(word, last=False):
    return legend_box(word, last)[1]

if "RELATIONS" in legend_xml:
    raise SystemExit("legend still emits a separate relations section")
if abs(y("call") - y("event", True)) > 5:
    raise SystemExit("relation cells do not flow through the merged grid")
if y("event", True) - y("actor") > 45:
    raise SystemExit("legend rows retain excessive vertical spacing")
if y("dotted") - y("LEGEND") > 125:
    raise SystemExit("merged legend retains excessive total vertical spacing")
PYTEST
    pass_line "five-column legend keeps relation columns aligned and rows compact"
  else
    fail_line "merged five-column legend geometry is not stable"
  fi
else
  fail_line "aligned-relations diagram did not render"
  printf '%s\n' "$out" | head -5 | sed 's/^/       /'
fi

# A normal A4 page keeps five readable columns even when all carriers are used.
# The second row remains visibly separate from the first, and relation captions
# sit below their names without overlapping adjacent content.
fixture legend-a4-wrap '#set page(paper: "a4", margin: (x: 18mm, y: 18mm))
#diagram(
  altitude: "L2",
  title: "Za4",
  nodes: (
    (id: "actor", label: "Zactor", kind: "actor"),
    (id: "system", label: "Zsystem", kind: "system"),
    (id: "queue", label: "Zqueue", kind: "queue"),
    (id: "topic", label: "Ztopic", kind: "topic"),
    (id: "database", label: "Zdatabase", kind: "database"),
    (id: "event", label: "Zevent", kind: "event"),
  ),
  edges: (
    (from: "actor", to: "system", relation: "call", label: "Zcalls"),
    (from: "system", to: "queue", relation: "dependency", label: "Zdepends"),
    (from: "queue", to: "topic", relation: "pubsub", label: "Zpublishes"),
  ),
)'
out="$(compile_pdf legend-a4-wrap)"
if [ -f "$WORK/legend-a4-wrap.pdf" ]; then
  pdftotext -bbox "$WORK/legend-a4-wrap.pdf" "$WORK/legend-a4-wrap.xml" 2>/dev/null
  if python3 - "$WORK/legend-a4-wrap.xml" <<'PYTEST'; then
import re, sys

xml = open(sys.argv[1], encoding="utf-8").read()
def boxes(word):
    return [
        tuple(map(float, match.groups()))
        for match in re.finditer(
        r'<word xMin="([0-9.]+)" yMin="([0-9.]+)" '
        r'xMax="([0-9.]+)" yMax="([0-9.]+)">%s</word>' % re.escape(word),
        xml,
        )
    ]

def box(word, last=False):
    values = boxes(word)
    if not values:
        raise SystemExit("missing A4 legend word %s" % word)
    return (max if last else min)(values, key=lambda value: value[1])

pubsub = box("pubsub")
dotted = box("dotted")
event_name = box("event", True)
first_row_bottom = max(box(word)[3] for word in ("role", "endpoint", "channel", "stream", "store"))
if dotted[1] <= pubsub[1]:
    raise SystemExit("relation description does not follow its name")
if abs(event_name[1] - pubsub[1]) > 5:
    raise SystemExit("second-row names do not share a baseline")
if event_name[1] - first_row_bottom < 12:
    raise SystemExit("second legend row overlaps the first row")
page = re.search(r'<page width="([0-9.]+)" height="([0-9.]+)">', xml)
if not page:
    raise SystemExit("A4 page bounds are missing")
page_width = float(page.group(1))
for word in ("actor", "database", "event", "pubsub", "consume", "solid"):
    if box(word)[2] > page_width:
        raise SystemExit("A4 legend word exceeds the page width")
PYTEST
    pass_line "five-column A4 legend separates rows and captions without overlap"
  else
    fail_line "five-column A4 legend captions overlap or escape their cells"
  fi
else
  fail_line "legend-a4-wrap diagram did not render"
  printf '%s\n' "$out" | head -5 | sed 's/^/       /'
fi

# Labels may contain quotes, backslashes, and an authored newline without a
# `sub` field. The public PDF proves the value renders and the line boxes prove
# the newline becomes a separate visual line rather than malformed DOT.
fixture safe-label '#diagram(
  altitude: "L2",
  nodes: (
    (id: "quoted", label: "Zquote " + str.from-unicode(34) + "quoted" + str.from-unicode(34) + " " + str.from-unicode(92) + "n" + str.from-unicode(10) + "Zsecond", kind: "system"),
    (id: "peer", label: "Zpeer", kind: "service"),
  ),
  edges: (("quoted", "peer", "Zlabel"),),
)'
out="$(compile_pdf safe-label)"
if [ -f "$WORK/safe-label.pdf" ]; then
  pdftotext -bbox "$WORK/safe-label.pdf" "$WORK/safe-label.xml" 2>/dev/null
  if python3 - "$WORK/safe-label.xml" <<'PYTEST'; then
import re, sys
xml = open(sys.argv[1], encoding="utf-8").read()
def box(word):
    match = re.search(
        r'<word xMin="([0-9.]+)" yMin="([0-9.]+)"[^>]*>%s</word>' % re.escape(word),
        xml,
    )
    if not match:
        raise SystemExit("missing %s" % word)
    return tuple(map(float, match.groups()))
first = box("Zquote")
second = box("Zsecond")
if second[1] <= first[1]:
    raise SystemExit("authored label newline did not produce a second line")
if "quoted" not in xml:
    raise SystemExit("quoted label text was lost")
PYTEST
    pass_line "diagram labels preserve quotes, backslashes, and authored line breaks"
  else
    fail_line "diagram label escaping or line separation changed the output"
  fi
else
  fail_line "safe-label diagram did not render"
  printf '%s\n' "$out" | head -5 | sed 's/^/       /'
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
