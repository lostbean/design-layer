"""Compare evaluated design records independently of page layout."""

from collections import Counter
from difflib import SequenceMatcher
import json
import re

MISSING = object()


def key(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False)


LAYOUT_CARRIERS = {
    "align",
    "block",
    "box",
    "columns",
    "move",
    "pad",
    "page",
    "place",
    "rotate",
    "scale",
    "stack",
}
LAYOUT_MARKERS = {"colbreak", "flush", "pagebreak", "v", "h"}


def normalize(value, diagrams):
    if isinstance(value, list):
        return [
            part for item in value if (part := normalize(item, diagrams)) is not MISSING
        ]
    if not isinstance(value, dict):
        return value
    function = value.get("func")
    if function == "metadata" and value.get("label") == "<design-semantic>":
        return normalize(value["value"], diagrams)
    if function in LAYOUT_CARRIERS:
        return normalize(
            value.get("body", value.get("children", value.get("child"))), diagrams
        )
    if function in LAYOUT_MARKERS or (
        function == "metadata" and value.get("label") == "<design-guideline>"
    ):
        return MISSING
    if function == "sequence":
        parts = normalize(value["children"], diagrams)
        while parts and parts[0] == {"func": "space"}:
            parts.pop(0)
        while parts and parts[-1] == {"func": "space"}:
            parts.pop()
        if not parts:
            return MISSING
        if len(parts) == 1:
            return parts[0]
        return {"func": "sequence", "children": parts}
    kind = value.get("kind")
    kind = kind if isinstance(kind, str) else None
    ignored = {"_guides"}
    if kind in ("warning", "info"):
        ignored.add("tint")
    elif kind == "cards":
        ignored.update(("tint", "size"))
        value = {
            **value,
            "items": [
                {k: v for k, v in card.items() if k != "tint"}
                for card in value["items"]
            ],
        }
    elif kind == "components":
        ignored.update(("accent", "cols"))
    elif kind in ("diagram", "diagram-native"):
        ignored.update(("accent", "layout", "flow", "spacing"))
        value = dict(value)
        for sub in ("groups", "nodes"):
            if len({item["id"] for item in value[sub]}) != len(value[sub]):
                raise ValueError(
                    f"duplicate diagram {sub} identity in {value.get('title')!r}"
                )
            value[sub] = {
                item["id"]: {
                    field: item_value
                    for field, item_value in item.items()
                    if field not in ("id", "pos", "tint")
                }
                for item in value[sub]
            }
        edges = []
        for edge in value["edges"]:
            if isinstance(edge, list):
                edge = dict(zip(("from", "to", "label"), edge[:3]))
            edges.append({k: v for k, v in edge.items() if k != "legacy-style"})
        value["edges"] = sorted(edges, key=key)
    if value.keys() == {"func", "text"} and value["func"] == "text":
        return value["text"]
    result = {
        field: None
        if (normalized := normalize(child, diagrams)) is MISSING
        else normalized
        for field, child in value.items()
        if field not in ignored
    }
    if kind in ("diagram", "diagram-native"):
        identity = result.get("review-id")
        if identity is not None:
            if not isinstance(identity, str) or not re.fullmatch(
                r"[A-Za-z0-9][A-Za-z0-9_-]*", identity
            ):
                raise ValueError(
                    "diagram review-id must contain letters, digits, underscores or hyphens"
                )
            if identity in diagrams:
                raise ValueError(f"duplicate diagram review-id: {identity}")
            diagrams[identity] = result
            return MISSING
    return result


def scope_name(value):
    if not isinstance(value, dict):
        return None
    kind = value.get("kind")
    if not isinstance(kind, str) or value.get("func"):
        return None
    label = next(
        (
            value.get(k)
            for k in ("review-id", "id", "title", "name")
            if isinstance(value.get(k), str) and value[k]
        ),
        None,
    )
    return f"{kind} {label}" if label else kind


def identity(value):
    if not isinstance(value, dict):
        return None
    kind = value.get("kind")
    if not isinstance(kind, str):
        return None
    name = (
        value.get("name")
        if kind == "document"
        else value.get("slug")
        if kind == "term"
        else value.get("id")
    )
    if isinstance(name, str) and name:
        return kind, name
    return None


def item_key(value):
    if stable := identity(value):
        return ("identity", *stable)
    return ("value", key(value))


def compatible(before, after):
    if not isinstance(before, dict) or not isinstance(after, dict):
        return True
    left, right = identity(before), identity(after)
    return before.get("kind", before.get("func")) == after.get(
        "kind", after.get("func")
    ) and (left == right or left is None and right is None)


def coverage(records):
    counts = Counter()

    def visit(value):
        if isinstance(value, list):
            for item in value:
                visit(item)
        elif isinstance(value, dict):
            kind = value.get("kind")
            if kind in ("figure-block", "formula"):
                counts[kind] += 1
            for child in value.values():
                visit(child)

    visit(records)
    return dict(sorted(counts.items()))


def edge_name(edge):
    return edge.get("label") or f"{edge.get('from', '?')} → {edge.get('to', '?')}"


def compare(old_records, new_records):
    changes = []

    def note(path, old, new, anchor, reason=None):
        changes.append(
            {
                "kind": "needs-review"
                if reason
                else (
                    "added"
                    if old is MISSING
                    else "removed"
                    if new is MISSING
                    else "changed"
                ),
                "path": path,
                "before": None if old is MISSING else old,
                "after": None if new is MISSING else new,
                "anchor": anchor,
                **({"reason": reason} if reason else {}),
            }
        )

    def edge_edits(a, b, path, anchor):
        old = a.copy()
        new = b.copy()
        for edge in a:
            if edge in new:
                old.remove(edge)
                new.remove(edge)
        for identity in (
            lambda edge: (edge.get("from"), edge.get("to")),
            lambda edge: (key(edge.get("label")), edge.get("relation")),
        ):
            old_counts = Counter(map(identity, old))
            new_counts = Counter(map(identity, new))
            for before in old.copy():
                token = identity(before)
                if old_counts[token] == new_counts[token] == 1:
                    after = next(edge for edge in new if identity(edge) == token)
                    note(path + [edge_name(before)], before, after, anchor)
                    old.remove(before)
                    new.remove(after)
        for before in old:
            note(path + [edge_name(before)], before, MISSING, anchor)
        for after in new:
            note(path + [edge_name(after)], MISSING, after, anchor)

    def visit(a, b, path, anchor=None):
        if a == b:
            return
        if isinstance(a, dict) and isinstance(b, dict):
            kind = a.get("kind")
            if kind == b.get("kind") and (name := scope_name(a)):
                path = path + [name]
                if (
                    kind in ("diagram", "diagram-native")
                    and a.get("review-id") == b.get("review-id")
                    and a.get("review-id")
                ):
                    anchor = f"diagram/{a['review-id']}"
            for field in sorted(a.keys() | b.keys()):
                left, right = a.get(field, MISSING), b.get(field, MISSING)
                child = path + [field]
                if left == right:
                    continue
                if kind == "figure-block" and field == "body":
                    note(
                        child,
                        left,
                        right,
                        anchor,
                        "Native drawing code changed. Its meaning needs review.",
                    )
                elif kind == "formula" and field == "body":
                    note(
                        child,
                        left,
                        right,
                        anchor,
                        "Formula notation changed. Mathematical equivalence needs review.",
                    )
                elif kind in ("diagram", "diagram-native") and field == "edges":
                    edge_edits(left, right, child, anchor)
                else:
                    visit(left, right, child, anchor)
        elif isinstance(a, list) and isinstance(b, list):
            match = SequenceMatcher(
                a=list(map(item_key, a)), b=list(map(item_key, b)), autojunk=False
            )
            for tag, i, j, k, l in match.get_opcodes():
                candidates = list(zip(a[i:j], b[k:l]))
                if tag == "equal" or (
                    tag == "replace"
                    and j - i == l - k
                    and all(compatible(left, right) for left, right in candidates)
                ):
                    for index, (left, right) in enumerate(zip(a[i:j], b[k:l]), i):
                        visit(left, right, path + [str(index + 1)], anchor)
                else:
                    for left in a[i:j]:
                        note(path + [scope_name(left) or "item"], left, MISSING, anchor)
                    for right in b[k:l]:
                        note(
                            path + [scope_name(right) or "item"], MISSING, right, anchor
                        )
        else:
            note(path, a, b, anchor)

    old_diagrams, new_diagrams = {}, {}
    visit(
        normalize(old_records, old_diagrams), normalize(new_records, new_diagrams), []
    )
    for identity in sorted(old_diagrams.keys() | new_diagrams.keys()):
        before = old_diagrams.get(identity, MISSING)
        after = new_diagrams.get(identity, MISSING)
        anchor = f"diagram/{identity}"
        if before is MISSING or after is MISSING:
            note([f"diagram {identity}"], before, after, anchor)
        else:
            visit(before, after, [], anchor)
    return changes


def shorten(path):
    decorations = {"children", "body", "visual", "child", "value"}
    return " / ".join(
        part
        for i, part in enumerate(path)
        if part not in decorations
        and not (part.isdecimal() and (i == 0 or path[i - 1] == "children"))
    )


def display(value):
    if isinstance(value, str):
        return value
    if isinstance(value, dict) and {"from", "to", "label"} <= value.keys():
        return f"{value['from']} → {value['to']} ({value['label']})"
    return key(value)


SUMMARY_ROWS = 40
SUMMARY_TEXT_LENGTH = 200
SHARED_RECORDS = "Document and shared records"


def section_of(change):
    return next(
        (
            part.removeprefix("section ")
            for part in change["path"]
            if part.startswith("section ")
        ),
        SHARED_RECORDS,
    )


def code_span(text, table=False):
    """A Markdown code span that keeps design text inert where it is posted."""
    text = " ".join(str(text).split()) or " "
    if len(text) > SUMMARY_TEXT_LENGTH:
        text = text[: SUMMARY_TEXT_LENGTH - 1] + "…"
    fence = "`" * (max(map(len, re.findall(r"`+", text)), default=0) + 1)
    pad = " " if text[0] == "`" or text[-1] == "`" else ""
    span = f"{fence}{pad}{text}{pad}{fence}"
    return span.replace("|", "\\|") if table else span


def render_summary(report, pdf_error=None, limit=SUMMARY_ROWS):
    """A Markdown summary short enough to post as one pull request comment."""
    changes = report["changes"]
    uncertain = [item for item in changes if item["kind"] == "needs-review"]
    source = report["sources"]
    lines = [
        f"<!-- design-review changes={len(changes)} -->",
        "## Design review",
        "",
        f"{code_span(source['before'])} → {code_span(source['after'])}",
        "",
        f"**{len(changes) - len(uncertain)} confirmed · {len(uncertain)} need review**",
    ]
    if pdf_error:
        lines += ["", "The before and after PDFs could not be rendered."]
    if changes:
        sections = {}
        for change in changes:
            sections.setdefault(section_of(change), Counter())[change["kind"]] += 1
        kinds = ("changed", "added", "removed", "needs-review")
        lines += [
            "",
            "| Section | Changed | Added | Removed | Need review |",
            "| --- | ---: | ---: | ---: | ---: |",
        ]
        for section, counts in list(sections.items())[:limit]:
            cells = " | ".join(str(counts[kind]) for kind in kinds)
            lines.append(f"| {code_span(section, table=True)} | {cells} |")
        if len(sections) > limit:
            lines += [
                "",
                f"{len(sections) - limit} more sections are in the full report.",
            ]
    else:
        lines += ["", "No changes in the projected fields."]
    if uncertain:
        lines += ["", "Need review:", ""]
        lines += [
            f"- {code_span(shorten(item['path']))}: {item['reason']}"
            for item in uncertain[:limit]
        ]
        if len(uncertain) > limit:
            lines += ["", f"{len(uncertain) - limit} more are in the full report."]
    if any(report["coverage"].values()):
        lines += [
            "",
            "Native figures and mathematical equivalence may require manual review.",
        ]
    return "\n".join(lines) + "\n"


def render_viewer(report, pdf_links, pdf_error):
    """A portable HTML report with escaped data and no remote assets."""
    from html import escape

    changes = report["changes"]
    counts = Counter(item["kind"] for item in changes)
    links = "".join(
        f'<a href="{escape(link, quote=True)}">{side.title()} PDF</a>'
        for side, link in pdf_links.items()
    )
    groups = {}
    for change in changes:
        heading = escape(shorten(change["path"]))
        status = change["kind"].replace("-", " ").capitalize()
        anchor = (
            "<small>Diagram marked where it appears</small>"
            if change["anchor"] and pdf_links and change["kind"] != "needs-review"
            else ""
        )
        if change["kind"] == "needs-review":
            values = f"<p>{escape(change['reason'])}</p>"
        else:
            values = (
                '<div class="values">'
                + "".join(
                    f"<div><h4>{side.title()}</h4><pre>{escape(display(change[side]) if change[side] is not None else '—')}</pre></div>"
                    for side in ("before", "after")
                )
                + "</div>"
            )
        groups.setdefault(section_of(change), []).append(
            f'<article class="{change["kind"]}"><p class="status">{status}</p><h3>{heading}</h3>{values}{anchor}</article>'
        )
    body = (
        "".join(
            f'<section class="group"><h2>{escape(section)}</h2>{"".join(entries)}</section>'
            for section, entries in groups.items()
        )
        or "<p>No changes in the projected fields.</p>"
    )
    search = (
        '<label id="filter-label" hidden>Filter changes <input id="filter" type="search"></label>'
        if changes
        else ""
    )
    warning = f'<p role="status">{escape(pdf_error)}</p>' if pdf_error else ""
    source = report["sources"]
    limitation = ""
    if any(report["coverage"].values()):
        limitation = "<p>Native figures and mathematical equivalence may require manual review.</p>"
    return f"""<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Design review</title>
<style>
:root {{ color-scheme: light; font: 1rem system-ui, sans-serif; color: #172126; background: #fbfbf8; }}
body {{ margin: 0 auto; max-width: 66rem; padding: 1.5rem clamp(1rem, 5vw, 4rem); }}
header {{ border-bottom: 1px solid #d7ddda; margin-bottom: 1.5rem; padding-bottom: 1rem; }}
h1 {{ font-family: Georgia, serif; font-size: 2.4rem; margin: 0 0 .5rem; }}
h2 {{ font-family: Georgia, serif; font-size: 1.35rem; margin: 1.5rem 0 .7rem; }}
h3 {{ font-size: 1rem; margin: .25rem 0 .9rem; overflow-wrap: anywhere; }}
h4, .status {{ font-size: .8rem; margin: 0; color: #58656b; }}
#filter-label {{ margin-top: 1rem; }}
#filter {{ font: inherit; padding: .4rem .55rem; margin: 0 .4rem; border: 1px solid #8f9a95; border-radius: .2rem; max-width: 60%; }}
[hidden] {{ display: none; }}
header p {{ color: #58656b; overflow-wrap: anywhere; }}
nav {{ display: flex; gap: 1.25rem; flex-wrap: wrap; }}
a {{ color: #235b83; }}
article {{ padding: 1rem 1.2rem; margin: 0 0 .75rem; border: 1px solid #d7ddda; border-left: .25rem solid #2870a6; background: white; }}
article.added {{ border-left-color: #087f79; }} article.removed {{ border-left-color: #a8492a; }}
article.needs-review {{ border-left-color: #a86408; }}
.values {{ display: grid; grid-template-columns: minmax(0,1fr) minmax(0,1fr); gap: 1rem; }}
pre {{ font: inherit; white-space: pre-wrap; overflow-wrap: anywhere; margin: .3rem 0; }}
small {{ color: #58656b; }}
@media (max-width: 40rem) {{ .values {{ grid-template-columns: 1fr; }} }}
</style></head>
<body><header><h1>Design review</h1>
<p>{escape(source["before"])} → {escape(source["after"])}</p>
<p>{len(changes) - counts["needs-review"]} confirmed · {counts["needs-review"]} need review</p>
<nav aria-label="PDF context">{links}</nav>{search}</header>
<main>{warning}{limitation}{body}<p id="empty-filter" role="status" hidden>No matching changes.</p></main>
<script>
const filter = document.getElementById("filter");
if (filter) {{
  document.getElementById("filter-label").hidden = false;
  filter.addEventListener("input", () => {{
    const query = filter.value.trim().toLowerCase();
    let visible = false;
    for (const group of document.querySelectorAll(".group")) {{
      let matched = false;
      for (const entry of group.querySelectorAll("article")) {{
        entry.hidden = !entry.textContent.toLowerCase().includes(query);
        matched ||= !entry.hidden;
      }}
      group.hidden = !matched;
      visible ||= matched;
    }}
    document.getElementById("empty-filter").hidden = visible;
  }});
}}
</script></body></html>
"""
