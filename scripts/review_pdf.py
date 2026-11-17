"""Compose one PDF that shows each changed part of a design side by side.

The comparison of records decides what changed and names the part that draws
each change. This module only places: it reads where the renderer drew each
part, puts the old part on the left and the new part on the right, and marks
the changes on pages it never alters.
"""

from collections import Counter
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from pathlib import Path
import math
import os

import pymupdf

from review_model import FRONT, Parts, shorten

PART_MARKS = {"document", "section", "subsection", "unit", "pending-ledger", "glossary"}
BLOCK_MARKS = {"diagram", "figure-block", "formula"}
KINDS = ("changed", "added", "removed", "needs-review")

# A heading's glyphs rise a little above the place the renderer reports for it.
HEADING_RISE = 4.0

# The colours are the renderer's own palette, so the report reads as one family
# with the document while its furniture stays visibly apart from it.
INK = (0x17 / 255, 0x21 / 255, 0x26 / 255)
MUTED = (0x58 / 255, 0x65 / 255, 0x6B / 255)
HAIRLINE = (0xD7 / 255, 0xDD / 255, 0xDA / 255)
TONE = {
    "changed": (0x28 / 255, 0x70 / 255, 0xA6 / 255),
    "added": (0x08 / 255, 0x7F / 255, 0x79 / 255),
    "removed": (0xAD / 255, 0x34 / 255, 0x51 / 255),
    "needs-review": (0xA8 / 255, 0x64 / 255, 0x08 / 255),
}
SIDE_TONE = {"before": TONE["removed"], "after": TONE["added"]}

MARGIN = 28.0
GUTTER = 28.0
HEADER = 64.0
FOOT = 20.0
INDEX_HEIGHT = 842.0
INDEX_TOP = 150.0
INDEX_LINE = 15.0


# ---- where the renderer drew each part --------------------------------------
@dataclass(frozen=True)
class Mark:
    kind: str
    identity: str | None
    edge: str
    page: int
    x: float
    y: float
    top: float
    bottom: float


@dataclass(frozen=True)
class Region:
    """A band of one page that belongs to one part."""

    page: int
    top: float
    bottom: float


@dataclass(frozen=True)
class Block:
    """A diagram, custom figure, or formula, by the corners it reported."""

    kind: str
    identity: str | None
    turn: int | None
    page: int
    rect: tuple[float, float, float, float]


@dataclass(frozen=True)
class Part:
    key: str
    document: str
    title: str
    regions: tuple[Region, ...]
    blocks: tuple[Block, ...]

    def block(self, kind: str, turn: int) -> list[Block]:
        return [b for b in self.blocks if b.kind == kind and b.turn == turn]

    def label(self) -> str:
        if not self.document or self.key.startswith("document "):
            return self.title
        return f"{self.document} › {self.title}"


def number(value: object, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"a review place has no numeric {name}: {value!r}")
    if not math.isfinite(value):
        raise ValueError(f"a review place has a {name} that is not finite")
    return float(value)


def read_mark(value: object, pages: int) -> Mark:
    if not isinstance(value, dict):
        raise ValueError(f"a review place is not a record: {value!r}")
    kind, edge, identity = value.get("kind"), value.get("edge"), value.get("id")
    if not isinstance(kind, str) or edge not in ("start", "end"):
        raise ValueError(f"a review place has no kind or edge: {value!r}")
    if identity is not None and not isinstance(identity, str):
        raise ValueError(f"a review place has an id that is not text: {value!r}")
    page = value.get("page")
    if isinstance(page, bool) or not isinstance(page, int) or not 1 <= page <= pages:
        raise ValueError(f"a review place names a page the PDF does not have: {page!r}")
    return Mark(
        kind,
        identity,
        edge,
        page - 1,
        number(value.get("x"), "x"),
        number(value.get("y"), "y"),
        number(value.get("top", 0), "top margin"),
        number(value.get("bottom", 0), "bottom margin"),
    )


def read_layout(
    places: list[object], document: pymupdf.Document, outline: Parts
) -> dict[str, Part]:
    """The parts of one rendered revision, in the order they are drawn.

    The records name the parts and the places say where each one starts. The
    two lists are in document order, so they are matched by position, with the
    kind of each part and the id of a unit or document as the check. A title
    plays no role: its markup renders differently in the two compilations.
    """
    marks = [read_mark(place, len(document)) for place in places]
    top = max((m.top for m in marks if m.kind == "page"), default=0.0)
    bottom = max((m.bottom for m in marks if m.kind == "page"), default=0.0)
    unknown = {m.kind for m in marks} - PART_MARKS - BLOCK_MARKS - {"page"}
    if unknown:
        raise ValueError(f"unknown review place: {', '.join(sorted(unknown))}")

    heads = sorted(
        (m for m in marks if m.kind in PART_MARKS and m.edge == "start"),
        key=lambda m: (m.page, m.y),
    )
    named = ("document", "unit")
    drawn = [(m.kind, m.identity if m.kind in named else None) for m in heads]
    listed = [(kind, name) for _, kind, name in outline.order]
    titles = {FRONT: ("", "Front matter"), **outline.keys.titles}
    starts = [(FRONT, (0, 0.0))]
    # A heading the records do not name stays inside the part before it. A
    # part the places do not show has no region, and its changes count in the
    # part that encloses it.
    matcher = SequenceMatcher(a=listed, b=drawn, autojunk=False)
    for match in matcher.get_matching_blocks():
        for offset in range(match.size):
            mark = heads[match.b + offset]
            key = outline.order[match.a + offset][0]
            starts.append((key, (mark.page, max(mark.y - HEADING_RISE, 0.0))))

    def regions(start, end):
        for page in range(start[0], end[0] + 1):
            height = document[page].rect.height
            upper = max(start[1] if page == start[0] else 0.0, top)
            lower = min(end[1] if page == end[0] else height, height - bottom)
            if lower - upper > 1:
                yield Region(page, upper, lower)

    last = (len(document) - 1, document[-1].rect.height)
    spans = {
        key: tuple(regions(start, following[1] if following else last))
        for (key, start), following in zip(starts, [*starts[1:], None])
    }

    def owner(page: int, y: float) -> str | None:
        return next(
            (
                key
                for key, bands in spans.items()
                if any(r.page == page and r.top <= y < r.bottom for r in bands)
            ),
            None,
        )

    blocks: dict[str, list[Block]] = {key: [] for key in spans}
    turns: Counter[tuple[str, str]] = Counter()
    opened: dict[str, Mark] = {}
    for mark in (m for m in marks if m.kind in BLOCK_MARKS):
        if mark.edge == "start":
            opened[mark.kind] = mark
            continue
        start = opened.pop(mark.kind, None)
        if start is None or start.identity != mark.identity:
            raise ValueError(f"a {mark.kind} reported an end without its start")
        key = owner(start.page, start.y + 0.5)
        if key is None:
            continue
        turn = None
        if start.identity is None:
            turns[key, mark.kind] += 1
            turn = turns[key, mark.kind]
        left, right = min(start.x, mark.x), max(start.x, mark.x)
        if start.page == mark.page:
            pieces = [(start.page, (left, start.y, right, mark.y))]
        else:
            # A block that breaks across pages is boxed where it starts and
            # where it ends.
            height = document[start.page].rect.height
            pieces = [
                (start.page, (left, start.y, right, height - bottom)),
                (mark.page, (left, top, right, mark.y)),
            ]
        blocks[key] += [
            Block(mark.kind, start.identity, turn, page, rect) for page, rect in pieces
        ]
    return {
        key: Part(key, *titles[key], spans[key], tuple(blocks[key])) for key in spans
    }


# ---- one revision, ready to be placed ---------------------------------------
@dataclass
class Side:
    name: str
    document: pymupdf.Document | None
    parts: dict[str, Part]
    parents: dict[str, str | None]
    _words: dict[int, list] = field(default_factory=dict)

    @classmethod
    def absent(cls, name: str) -> "Side":
        return cls(name, None, {}, {})

    @classmethod
    def read(cls, name: str, pdf: Path, places: list[object], outline: Parts) -> "Side":
        document = pymupdf.open(pdf)
        parts = read_layout(places, document, outline)
        return cls(name, document, parts, outline.parents)

    def resolve(self, key: str | None) -> str | None:
        """A part the PDF does not show by itself falls back to its parent."""
        while key is not None and key not in self.parts:
            key = self.parents.get(key)
        return key

    def drawn(self, identity: str) -> tuple[str, list[Block]] | None:
        """The part that draws the diagram with this review-id, and its box."""
        for key, part in self.parts.items():
            found = [b for b in part.blocks if b.identity == identity]
            if found:
                return key, found
        return None

    def words(self, part: Part) -> list[tuple[str, int, pymupdf.Rect]]:
        found = []
        for index, region in enumerate(part.regions):
            assert self.document is not None
            if region.page not in self._words:
                self._words[region.page] = self.document[region.page].get_text("words")
            for x0, y0, x1, y1, text, *_ in self._words[region.page]:
                if region.top <= (y0 + y1) / 2 < region.bottom:
                    found.append((text, index, pymupdf.Rect(x0, y0, x1, y1)))
        return found


@dataclass
class Row:
    """One part with a listed change, and the marks that show it."""

    key: str
    counts: Counter = field(default_factory=Counter)
    elsewhere: int = 0
    boxes: dict[str, dict[tuple, str]] = field(
        default_factory=lambda: {"before": {}, "after": {}}
    )
    reviews: list[dict] = field(default_factory=list)
    first_sheet: int = 0

    def box(self, side: str, block: Block, tone: str) -> None:
        marked = self.boxes[side]
        place = (block.page, block.rect, block.kind)
        if marked.get(place) != "needs-review":
            marked[place] = tone


def place_changes(changes: list[dict], sides: dict[str, Side]) -> dict[str, Row]:
    """Count every change on the row of one part, and collect its boxes."""
    rows: dict[str, Row] = {}
    for change in changes:
        tone = "needs-review" if change["kind"] == "needs-review" else "changed"
        homes: dict[str, str | None] = {}
        marks: list[tuple[str, str, Block]] = []
        for name, side in sides.items():
            wanted = change["part"][name]
            key = side.resolve(wanted) if wanted else None
            if change["anchor"] and (
                found := side.drawn(change["anchor"].removeprefix("diagram/"))
            ):
                # Where a diagram is drawn is where its change is shown.
                key = found[0]
                marks += [(name, key, block) for block in found[1]]
            elif (
                key and key == wanted and (ref := (change.get("block") or {}).get(name))
            ):
                marks += [(name, key, b) for b in side.parts[key].block(ref[0], ref[1])]
            homes[name] = key
        home = homes["after"] or homes["before"]
        if home is None:
            raise ValueError(f"no part draws the change at {shorten(change['path'])}")
        row = rows.setdefault(home, Row(home))
        row.counts[change["kind"]] += 1
        if change["kind"] == "needs-review":
            row.reviews.append(change)
        other = homes["before"]
        if other and other != home:
            rows.setdefault(other, Row(other)).elsewhere += 1
        for name, key, block in marks:
            rows.setdefault(key, Row(key)).box(name, block, tone)
    return rows


def reading_order(rows: dict[str, Row], sides: dict[str, Side]) -> list[Row]:
    """The new design's order, with each removed part where it used to stand."""
    new = {key: index for index, key in enumerate(sides["after"].parts)}
    old = list(sides["before"].parts)

    def position(key: str) -> tuple[int, int]:
        if key in new:
            return new[key], 1
        following = (new[k] for k in old[old.index(key) + 1 :] if k in new)
        return next(following, len(new)), 0

    return sorted(rows.values(), key=lambda row: position(row.key))


# ---- drawing ------------------------------------------------------------------
class Pen:
    """Text in one family, measured so that nothing runs off the sheet."""

    def __init__(self):
        directory = os.environ.get("DESIGN_REVIEW_FONT_DIR")
        files = {}
        if directory:
            for name, file in (
                ("review", "DejaVuSans.ttf"),
                ("review-bold", "DejaVuSans-Bold.ttf"),
            ):
                found = sorted(Path(directory).rglob(file))
                if found:
                    files[name] = str(found[0])
        self.files = files
        self.fonts = {
            "review": pymupdf.Font(fontfile=files["review"])
            if "review" in files
            else pymupdf.Font("helv"),
            "review-bold": pymupdf.Font(fontfile=files["review-bold"])
            if "review-bold" in files
            else pymupdf.Font("hebo"),
        }

    def fit(self, text: str, size: float, width: float, bold: bool = False) -> str:
        font = self.fonts["review-bold" if bold else "review"]
        text = " ".join(text.split())
        if font.text_length(text, size) <= width:
            return text
        while text and font.text_length(text + "…", size) > width:
            text = text[:-1]
        return text.rstrip() + "…"

    def width(self, text: str, size: float, bold: bool = False) -> float:
        return self.fonts["review-bold" if bold else "review"].text_length(text, size)

    def write(
        self, page, at, text, size=9.0, color=INK, bold=False, width=None
    ) -> float:
        name = "review-bold" if bold else "review"
        if width is not None:
            text = self.fit(text, size, width, bold)
        if name in self.files:
            page.insert_text(
                at,
                text,
                fontname=name,
                fontfile=self.files[name],
                fontsize=size,
                color=color,
            )
        else:
            page.insert_text(
                at,
                text,
                fontname="hebo" if bold else "helv",
                fontsize=size,
                color=color,
            )
        return self.width(text, size, bold)


def count_text(counts: Counter) -> str:
    names = {
        "changed": "changed",
        "added": "added",
        "removed": "removed",
        "needs-review": "need review",
    }
    return " · ".join(f"{counts[kind]} {names[kind]}" for kind in KINDS if counts[kind])


def word_runs(marks: list[tuple[int, pymupdf.Rect]]) -> list[tuple[int, pymupdf.Rect]]:
    """Join marked words that sit beside each other on one line."""
    joined: list[list] = []
    for index, rect in marks:
        last = joined[-1] if joined else None
        if (
            last
            and last[0] == index
            and abs(last[1].y0 - rect.y0) < 2
            and 0 <= rect.x0 - last[1].x1 < 8
        ):
            last[1].include_rect(rect)
        else:
            joined.append([index, pymupdf.Rect(rect)])
    return [(index, rect) for index, rect in joined]


def changed_words(old: list, new: list) -> tuple[list, list]:
    matcher = SequenceMatcher(
        a=[w[0] for w in old], b=[w[0] for w in new], autojunk=False
    )
    gone, came = [], []
    for tag, i, j, k, l in matcher.get_opcodes():
        if tag != "equal":
            gone += [(w[1], w[2]) for w in old[i:j]]
            came += [(w[1], w[2]) for w in new[k:l]]
    return word_runs(gone), word_runs(came)


def region_of(part: Part, page: int, y: float) -> int | None:
    return next(
        (
            i
            for i, r in enumerate(part.regions)
            if r.page == page and r.top <= y < r.bottom
        ),
        None,
    )


def draw_row(
    report, pen: Pen, row: Row, sides: dict[str, Side], page_width: float
) -> None:
    parts = {name: side.parts.get(row.key) for name, side in sides.items()}
    present = parts["after"] or parts["before"]
    assert present is not None
    status = (
        "changed"
        if parts["before"] and parts["after"]
        else "added"
        if parts["after"]
        else "removed"
    )
    highlights: dict[str, list] = {"before": [], "after": []}
    if status == "changed":
        highlights["before"], highlights["after"] = changed_words(
            sides["before"].words(parts["before"]), sides["after"].words(parts["after"])
        )
    boxes: dict[str, list[tuple[int, tuple, str, str]]] = {"before": [], "after": []}
    for name, part in parts.items():
        for (page, rect, kind), tone in row.boxes[name].items():
            index = region_of(part, page, rect[1] + 0.5) if part else None
            if index is not None:
                boxes[name].append((index, rect, kind, tone))

    count = max(len(part.regions) if part else 0 for part in parts.values())
    marked = {index for name in parts for index, _ in highlights[name]}
    marked |= {box[0] for name in parts for box in boxes[name]}
    shown = sorted(marked) if status == "changed" else list(range(count))
    silent = not shown
    shown = shown or [0]

    for index in shown:
        bands = {
            name: part.regions[index] if part and index < len(part.regions) else None
            for name, part in parts.items()
        }
        widths = {
            name: sides[name].document[band.page].rect.width
            for name, band in bands.items()
            if band
        }
        panel = max([page_width, *widths.values()])
        width = MARGIN * 2 + panel * 2 + GUTTER
        origin = {"before": MARGIN, "after": MARGIN + panel + GUTTER}
        tallest = max(
            (band.bottom - band.top for band in bands.values() if band), default=0.0
        )
        sheet = report.new_page(width=width, height=HEADER + max(tallest, 36.0) + FOOT)
        row.first_sheet = row.first_sheet or len(report)
        tone = TONE[status]
        used = pen.write(sheet, (MARGIN, 22), status.upper(), 9, tone, bold=True)
        pen.write(
            sheet,
            (MARGIN + used + 10, 22),
            present.label(),
            11,
            INK,
            bold=True,
            width=width - 2 * MARGIN - used - 10,
        )
        detail = count_text(row.counts)
        if row.elsewhere:
            detail += (
                " · " if detail else ""
            ) + f"holds the old place of {row.elsewhere} counted in another part"
        if silent:
            detail += " · no visible mark: the change does not show on the page"
        pen.write(sheet, (MARGIN, 36), detail, 8, MUTED, width=width - 2 * MARGIN)
        for name, band in bands.items():
            x = origin[name]
            caption = name.capitalize()
            if band is None:
                caption += (
                    " · not in this revision"
                    if parts[name] is None
                    else " · this part ends earlier here"
                )
                pen.write(sheet, (x, 54), caption, 8.5, MUTED)
                continue
            pen.write(sheet, (x, 54), f"{caption} · page {band.page + 1}", 8.5, MUTED)
            height = band.bottom - band.top
            clip = pymupdf.Rect(0, band.top, widths[name], band.bottom)
            sheet.show_pdf_page(
                pymupdf.Rect(x, HEADER, x + widths[name], HEADER + height),
                sides[name].document,
                band.page,
                clip=clip,
            )
            sheet.draw_rect(
                pymupdf.Rect(x, HEADER, x + widths[name], HEADER + height),
                color=HAIRLINE,
                width=0.5,
            )
            shift = (x, HEADER - band.top, x, HEADER - band.top)
            if status != "changed":
                sheet.draw_rect(
                    pymupdf.Rect(x, HEADER, x + 3, HEADER + height),
                    color=None,
                    fill=SIDE_TONE[name],
                )
            for at, rect in highlights[name]:
                if at == index:
                    sheet.draw_rect(
                        rect + shift + (-1, -0.5, 1, 0.5),
                        color=None,
                        fill=SIDE_TONE[name],
                        fill_opacity=0.24,
                    )
            for at, rect, kind, kind_tone in boxes[name]:
                if at != index:
                    continue
                stroke = (
                    TONE["needs-review"]
                    if kind_tone == "needs-review"
                    else SIDE_TONE[name]
                )
                frame = pymupdf.Rect(rect) + shift + (-4, -4, 4, 4)
                sheet.draw_rect(frame, color=stroke, width=1.3)
                noun = {
                    "diagram": "diagram",
                    "figure-block": "figure",
                    "formula": "formula",
                }[kind]
                text = (
                    f"{noun} needs review"
                    if kind_tone == "needs-review"
                    else f"{noun} changed"
                )
                tag = pymupdf.Rect(
                    frame.x0,
                    frame.y0 - 10,
                    frame.x0 + pen.width(text, 6.5) + 8,
                    frame.y0,
                )
                sheet.draw_rect(tag, color=None, fill=stroke)
                pen.write(sheet, (tag.x0 + 4, tag.y1 - 2.6), text, 6.5, (1, 1, 1))


def draw_index(
    report,
    pen: Pen,
    summary: dict,
    rows: list[Row],
    sides: dict[str, Side],
    width: float,
) -> None:
    """The first pages: what was compared, the counts, and where each part is."""
    lines: list[tuple] = [("row", row) for row in rows]
    reviews = [(row, change) for row in rows for change in row.reviews]
    if reviews:
        lines += [("gap", None), ("head", "Need review")]
        lines += [("review", item) for item in reviews]
    per_page = int((INDEX_HEIGHT - INDEX_TOP - MARGIN) // INDEX_LINE)
    chunks = [lines[i : i + per_page] for i in range(0, len(lines), per_page)] or [[]]
    count_x, sheet_x = width - MARGIN - 330, width - MARGIN - 52
    # Every index page is inserted before any link is drawn: a link resolves
    # its target page when it is made, and a later insertion would shift it.
    # An inserted page also invalidates the page objects made before it, so
    # each index page is fetched again once all of them are in place.
    for number_ in range(len(chunks)):
        report.new_page(pno=number_, width=width, height=INDEX_HEIGHT)
    for number_, chunk in enumerate(chunks):
        page = report[number_]
        pen.write(page, (MARGIN, 44), "Design review", 20, INK, bold=True)
        pen.write(
            page,
            (MARGIN, 64),
            f"{summary['before']}  →  {summary['after']}",
            9,
            MUTED,
            width=width - 2 * MARGIN,
        )
        pen.write(page, (MARGIN, 84), summary["counts"], 11, INK, bold=True)
        y = 100.0
        for notice in summary["notices"]:
            pen.write(page, (MARGIN, y), notice, 8.5, MUTED, width=width - 2 * MARGIN)
            y += 12
        x = MARGIN
        for tone, text in (
            (TONE["removed"], "removed, on the left"),
            (TONE["added"], "added, on the right"),
            (TONE["needs-review"], "a drawing or formula a person must compare"),
        ):
            page.draw_rect(
                pymupdf.Rect(x, 120, x + 14, 129),
                color=None,
                fill=tone,
                fill_opacity=0.45,
            )
            x += 20 + pen.write(page, (x + 19, 128), text, 8, MUTED) + 16
        pen.write(
            page,
            (x, 128),
            "Old design on the left, new design on the right. Parts without a change are left out.",
            8,
            MUTED,
        )
        y = INDEX_TOP
        for kind, item in chunk:
            if kind == "head":
                pen.write(page, (MARGIN, y), item, 10, INK, bold=True)
            elif kind == "row":
                parts = {name: side.parts.get(item.key) for name, side in sides.items()}
                present = parts["after"] or parts["before"]
                status = (
                    "changed"
                    if parts["before"] and parts["after"]
                    else "added"
                    if parts["after"]
                    else "removed"
                )
                pen.write(page, (MARGIN, y), status, 8.5, TONE[status], bold=True)
                pen.write(
                    page,
                    (MARGIN + 62, y),
                    present.label(),
                    9,
                    INK,
                    width=count_x - MARGIN - 74,
                )
                pen.write(
                    page,
                    (count_x, y),
                    count_text(item.counts) or "old place only",
                    8.5,
                    MUTED,
                    width=sheet_x - count_x - 10,
                )
            elif kind == "review":
                row, change = item
                pen.write(
                    page,
                    (MARGIN + 62, y),
                    f"{shorten(change['path'])}: {change['reason']}",
                    8.5,
                    INK,
                    width=sheet_x - MARGIN - 74,
                )
            if kind in ("row", "review"):
                target = (item if kind == "row" else item[0]).first_sheet + len(chunks)
                pen.write(page, (sheet_x, y), f"page {target}", 8.5, MUTED)
                page.insert_link(
                    {
                        "kind": pymupdf.LINK_GOTO,
                        "from": pymupdf.Rect(MARGIN, y - 10, width - MARGIN, y + 4),
                        "page": target - 1,
                        "to": pymupdf.Point(0, 0),
                    }
                )
            y += INDEX_LINE
        if not lines:
            pen.write(page, (MARGIN, y), "No changes in the projected fields.", 10, INK)


def compose(
    report: dict, sides: dict[str, Side], notices: list[str], output: Path
) -> None:
    """Write the side-by-side PDF of one review to a path that does not exist."""
    changes = report["changes"]
    rows = place_changes(changes, sides)
    ordered = reading_order(rows, sides)
    documents = [side.document for side in sides.values() if side.document is not None]
    page_width = max((document[0].rect.width for document in documents), default=595.0)
    width = MARGIN * 2 + page_width * 2 + GUTTER
    pen = Pen()
    uncertain = sum(change["kind"] == "needs-review" for change in changes)
    counted = sum(sum(row.counts.values()) for row in rows.values())
    if counted != len(changes):
        raise ValueError(f"{counted} of {len(changes)} changes were placed")
    with pymupdf.open() as composed:
        for row in ordered:
            draw_row(composed, pen, row, sides, page_width)
        summary = {
            "before": report["sources"]["before"],
            "after": report["sources"]["after"],
            "counts": f"{len(changes) - uncertain} confirmed · {uncertain} need review",
            "notices": notices,
        }
        draw_index(composed, pen, summary, ordered, sides, width)
        composed.set_metadata({"title": "Design review"})
        composed.save(output, garbage=3, deflate=True)
