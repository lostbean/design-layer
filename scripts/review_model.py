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


# ---- the part of the document that draws a record ---------------------------
# A part is what a reader finds by its heading: a document, a section, a
# subsection, a unit, a pending ledger, or the glossary. Its key is its
# identity across revisions. The same key is built from the places the
# renderer reports, so a change and the page region that shows it meet by key.
FRONT = "front matter"
GLOSSARY = "glossary"
BLOCK_KINDS = {
    "diagram": "diagram",
    "diagram-native": "diagram",
    "figure-block": "figure-block",
    "formula": "formula",
}


def plain(value):
    """The text of a content tree, as a reader sees it."""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "".join(map(plain, value))
    if isinstance(value, dict):
        if value.get("func") == "space":
            return " "
        for field in ("text", "children", "body", "child"):
            if field in value:
                return plain(value[field])
    return ""


class PartKeys:
    """Names parts in document order, from records or from rendered places.

    A unit is known by its id and a document by its name. A section is known
    by its title within its document, and a repeated title by its turn.
    """

    def __init__(self):
        self.document = ""
        self.document_title = ""
        self.turns = Counter()
        self.titles = {}

    def open(self, kind, name=None, title=None):
        label = " ".join(plain(title).split()) if title is not None else ""
        if kind == "document":
            self.document = name or ""
            self.document_title = label or self.document
            key = f"document {self.document}"
        elif kind == "unit":
            key = f"unit {name}"
        elif kind in ("glossary", "term"):
            key, label = GLOSSARY, "Glossary"
        elif kind in ("section", "subsection", "pending-ledger"):
            if kind == "pending-ledger":
                label = "Pending updates"
            base = f"{kind} {self.document}/{label}"
            self.turns[base] += 1
            turn = self.turns[base]
            key = base if turn == 1 else f"{base} #{turn}"
        else:
            return None
        self.titles.setdefault(key, (self.document_title, label or key))
        return key


class Parts:
    """Where each record of one revision is drawn, by object identity."""

    def __init__(self, tree):
        self.opened = {}  # a record that opens a part -> the part
        self.inside = {}  # a record or list that opens parts -> the last one
        self.blocks = {}  # a diagram, figure, or formula -> (kind, turn in part)
        self.diagrams = {}  # a diagram's review-id -> the part that draws it
        self.holds = {}  # a record or list -> the parts opened inside it
        self.parents = {FRONT: None}
        self.order = []  # (part, kind, id of a unit or name of a document)
        self.keys = PartKeys()
        self._turns = Counter()
        self._walk(tree, FRONT, FRONT)

    def _walk(self, node, enclosing, flow):
        first = len(self.order)
        if isinstance(node, list):
            entered = flow
            for item in node:
                flow = self._walk(item, enclosing, flow)
            if flow != entered:
                self.inside[id(node)] = flow
            self._hold(node, first, None)
            return flow
        if not isinstance(node, dict):
            return flow
        kind = None if node.get("func") else node.get("kind")
        key = None
        if kind == "term":
            key = self.keys.open("term")
        elif kind == "document":
            key = self.keys.open(kind, node.get("name"), node.get("title"))
        elif kind == "unit":
            key = self.keys.open(kind, node.get("id"), node.get("title"))
        elif kind in ("section", "subsection", "pending-ledger"):
            key = self.keys.open(kind, title=node.get("title"))
        entered = flow
        if key:
            self.opened[id(node)] = key
            if key not in self.parents:
                self.parents[key] = enclosing
                named = node.get("name") if kind == "document" else node.get("id")
                self.order.append(
                    (
                        key,
                        "glossary" if kind == "term" else kind,
                        named if kind in ("document", "unit") else None,
                    )
                )
            enclosing = flow = key
        elif kind in BLOCK_KINDS:
            identity = node.get("review-id")
            if isinstance(identity, str):
                self.diagrams.setdefault(identity, flow)
            else:
                turn = (flow, BLOCK_KINDS[kind])
                self._turns[turn] += 1
                self.blocks[id(node)] = (BLOCK_KINDS[kind], self._turns[turn])
        for child in node.values():
            flow = self._walk(child, enclosing, flow)
        if flow != entered:
            self.inside[id(node)] = flow
        self._hold(node, first, key)
        return flow

    def _hold(self, node, first, own):
        held = [key for key, _, _ in self.order[first:] if key != own]
        if held:
            self.holds[id(node)] = held

    def after(self, node, flow):
        """The part in effect once a record is drawn: its last heading wins."""
        if isinstance(node, (dict, list)):
            return self.inside.get(id(node), flow)
        return flow


def part_outline(records):
    """The parts of a revision in the order they are drawn, with their titles."""
    return Parts(normalize(records, {}))


def compare(old_records, new_records):
    changes = []
    old_diagrams, new_diagrams = {}, {}
    old_tree = normalize(old_records, old_diagrams)
    new_tree = normalize(new_records, new_diagrams)
    old_parts, new_parts = Parts(old_tree), Parts(new_tree)

    def note(path, old, new, anchor, parts, blocks=(None, None), reason=None):
        change = {
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
            "part": {"before": parts[0], "after": parts[1]},
        }
        # An added or removed record takes the parts inside it along: they
        # have no change of their own, and they are part of this one.
        held = (
            old_parts.holds.get(id(old)) if isinstance(old, (dict, list)) else None,
            new_parts.holds.get(id(new)) if isinstance(new, (dict, list)) else None,
        )
        if any(held):
            change["holds"] = {"before": held[0] or [], "after": held[1] or []}
        if any(blocks):
            change["block"] = {
                side: list(block) if block else None
                for side, block in zip(("before", "after"), blocks)
            }
        if reason:
            change["reason"] = reason
        changes.append(change)

    def edge_edits(a, b, path, anchor, parts, blocks):
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
                    note(
                        path + [edge_name(before)], before, after, anchor, parts, blocks
                    )
                    old.remove(before)
                    new.remove(after)
        for before in old:
            note(path + [edge_name(before)], before, MISSING, anchor, parts, blocks)
        for after in new:
            note(path + [edge_name(after)], MISSING, after, anchor, parts, blocks)

    def visit(a, b, path, anchor, parts, blocks):
        if a == b:
            return
        if isinstance(a, dict) and isinstance(b, dict):
            kind = a.get("kind")
            parts = (
                old_parts.opened.get(id(a), parts[0]),
                new_parts.opened.get(id(b), parts[1]),
            )
            blocks = (
                old_parts.blocks.get(id(a), blocks[0]),
                new_parts.blocks.get(id(b), blocks[1]),
            )
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
                        parts,
                        blocks,
                        "Native drawing code changed. Its meaning needs review.",
                    )
                elif kind == "formula" and field == "body":
                    note(
                        child,
                        left,
                        right,
                        anchor,
                        parts,
                        blocks,
                        "Formula notation changed. Mathematical equivalence needs review.",
                    )
                elif kind in ("diagram", "diagram-native") and field == "edges":
                    edge_edits(left, right, child, anchor, parts, blocks)
                else:
                    visit(left, right, child, anchor, parts, blocks)
        elif isinstance(a, list) and isinstance(b, list):
            # A record is drawn under the last heading before it, so each item
            # starts in the part its earlier siblings left open.
            old_flow, new_flow = [parts[0]], [parts[1]]
            for item in a:
                old_flow.append(old_parts.after(item, old_flow[-1]))
            for item in b:
                new_flow.append(new_parts.after(item, new_flow[-1]))
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
                    for offset, (left, right) in enumerate(candidates):
                        visit(
                            left,
                            right,
                            path + [str(i + offset + 1)],
                            anchor,
                            (old_flow[i + offset], new_flow[k + offset]),
                            blocks,
                        )
                else:
                    for offset, left in enumerate(a[i:j], i):
                        note(
                            path + [scope_name(left) or "item"],
                            left,
                            MISSING,
                            anchor,
                            (old_parts.opened.get(id(left), old_flow[offset]), None),
                            (old_parts.blocks.get(id(left), blocks[0]), None),
                        )
                    for offset, right in enumerate(b[k:l], k):
                        note(
                            path + [scope_name(right) or "item"],
                            MISSING,
                            right,
                            anchor,
                            (None, new_parts.opened.get(id(right), new_flow[offset])),
                            (None, new_parts.blocks.get(id(right), blocks[1])),
                        )
        else:
            note(path, a, b, anchor, parts, blocks)

    visit(old_tree, new_tree, [], None, (FRONT, FRONT), (None, None))
    # A diagram with a review-id is compared by that id wherever it is drawn,
    # so its part comes from the records as they stood before it was set aside.
    old_drawn, new_drawn = Parts(old_records).diagrams, Parts(new_records).diagrams
    for identity in sorted(old_diagrams.keys() | new_diagrams.keys()):
        before = old_diagrams.get(identity, MISSING)
        after = new_diagrams.get(identity, MISSING)
        anchor = f"diagram/{identity}"
        parts = (old_drawn.get(identity), new_drawn.get(identity))
        if before is MISSING or after is MISSING:
            note([f"diagram {identity}"], before, after, anchor, parts)
        else:
            visit(before, after, [], anchor, parts, (None, None))
    return changes


def shorten(path):
    decorations = {"children", "body", "visual", "child", "value"}
    return " / ".join(
        part
        for i, part in enumerate(path)
        if part not in decorations
        and not (part.isdecimal() and (i == 0 or path[i - 1] == "children"))
    )


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


def empty_notice(label):
    """Name a side with no design layer, such as the base before adoption."""
    return f"{label} has no design layer, so it is compared as an empty one."


def render_summary(report, pdf_error=None, limit=SUMMARY_ROWS, empty=()):
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
    for side in empty:
        lines += ["", empty_notice(code_span(source[side]))]
    if pdf_error:
        lines += ["", "The side-by-side PDF could not be rendered."]
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
                f"{len(sections) - limit} more sections are in the PDF.",
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
            lines += ["", f"{len(uncertain) - limit} more are in the PDF."]
    if any(report["coverage"].values()):
        lines += [
            "",
            "Native figures and mathematical equivalence may require manual review.",
        ]
    return "\n".join(lines) + "\n"
