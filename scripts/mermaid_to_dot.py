#!/usr/bin/env python3
"""
Migration 0002 — mermaid fences into the renderer's native carriers.

Reads a host design.md (argv path or stdin), rewrites each ```mermaid fence by
diagram shape, and writes the result (to the same path if given, else stdout).

flowchart/graph and stateDiagram-v2 are converted to ```dot. sequenceDiagram is
NOT converted: its fence is relabelled and a marker comment is inserted naming
it for a human, because a mechanical rewrite would lose activation, alt/loop,
and note placement silently.

Deterministic and idempotent: a fence that is not ```mermaid is left untouched,
so running the script twice is a no-op on migrated docs. Needs only python3.
"""

import re
import sys

FENCE_RE = re.compile(r"^(?P<indent>\s*)(?P<ticks>```+|~~~+)\s*mermaid\s*$")

# ONE node grammar, used by the standalone matcher and the chain parser alike,
# so a node converts the same way wherever it is written.
NODE_BODY = (
    r"(?P<id>[A-Za-z_][\w-]*)\s*"
    r"(?:\(\(\((?P<dbl>[^)]*)\)\)\)"  # (((double circle)))
    r"|\(\((?P<circ>[^)]*)\)\)"  # ((circle))
    r"|\[\[(?P<sub>[^\]]*)\]\]"  # [[subroutine]]
    r"|\[\((?P<cyl>[^)]*)\)\]"  # [(cylinder)]
    r"|\[/(?P<trapa>[^\]]*)\\\]"  # [/trapezoid\]
    r"|\[\\(?P<trapb>[^\]]*)/\]"  # [\trapezoid/]
    r"|\[/(?P<para>[^\]]*)/\]"  # [/parallelogram/]
    r"|\[\\(?P<parb>[^\]]*)\\\]"  # [\parallelogram\]
    r"|\((\[(?P<stad>[^\]]*)\])\)"  # ([stadium])
    r"|>(?P<asym>[^\]]*)\]"  # >asymmetric]
    r"|\{\{(?P<hex>[^}]*)\}\}"  # {{hexagon}}
    r"|\[(?P<box>[^\]]*)\]"  # [box]
    r"|\((?P<round>[^)]*)\)"  # (rounded)
    r"|\{(?P<rhomb>[^}]*)\})?"  # {rhombus}
    r"(?::::[\w-]+)?"  # optional :::class styling
)
NODE_RE = re.compile(r"^\s*" + NODE_BODY + r"\s*$")
CHAIN_NODE_RE = re.compile(r"^" + NODE_BODY)
ARROWS = r"<-\.->|<-->|o--o|x--x|-\.->|--o|--x|-->|~~~|---|==>|-\.-"
EDGE_RE = re.compile(
    r"^\s*(?P<src>[A-Za-z_][\w-]*)\s*"
    r"(?P<arrow>" + ARROWS + r")\s*"
    r"(?:\|(?P<label>[^|]*)\|\s*)?"
    r"(?P<dst>[A-Za-z_][\w-]*)\s*$"
)
# `A & B --> C & D` — ampersand fan-out declares an edge per pair.
AMP_RE = re.compile(
    r"^\s*(?P<srcs>[A-Za-z_][\w-]*(?:\s*&\s*[A-Za-z_][\w-]*)*)\s*"
    r"(?P<arrow>" + ARROWS + r")\s*"
    r"(?:\|(?P<label>[^|]*)\|\s*)?"
    r"(?P<dsts>[A-Za-z_][\w-]*(?:\s*&\s*[A-Za-z_][\w-]*)*)\s*$"
)
# `<<fork>>` / `<<join>>` state, and `note <side> of X : text`
STATE_FORK_RE = re.compile(
    r"^\s*state\s+(?P<id>[A-Za-z_][\w-]*)\s*<<(?P<kind>fork|join|choice)>>\s*$"
)
STATE_NOTE_RE = re.compile(
    r"^\s*note\s+\w+\s+of\s+(?P<id>[A-Za-z_][\w-]*)\s*:\s*(?P<text>.+?)\s*$"
)
# mermaid's mid-arrow label form: A -. "text" .-> B  /  A -- text --> B
MIDLABEL_RE = re.compile(
    r"^\s*(?P<src>[A-Za-z_][\w-]*)\s*"
    r'(?P<open>-\.|--|==)\s*(?P<label>"[^"]*"|[^-=.|]+?)\s*(?P<close>\.->|-->|==>|---)\s*'
    r"(?P<dst>[A-Za-z_][\w-]*)\s*$"
)
SUBGRAPH_RE = re.compile(
    r"^\s*subgraph\s+(?P<id>[A-Za-z_][\w-]*)\s*(?:\[(?P<title>[^\]]*)\])?\s*$"
)
# --- stateDiagram-v2 forms -------------------------------------------------
# `A --> B: label`, where either side may be the [*] start/end pseudo-state.
STATE_EDGE_RE = re.compile(
    r"^\s*(?P<src>\[\*\]|[A-Za-z_][\w-]*)\s*-->\s*"
    r"(?P<dst>\[\*\]|[A-Za-z_][\w-]*)\s*"
    r"(?::\s*(?P<label>.+?))?\s*$"
)
# `state Name {` — a composite state, which becomes a cluster.
STATE_COMPOSITE_RE = re.compile(
    r'^\s*state\s+(?P<name>"[^"]*"|[A-Za-z_][\w-]*)\s*\{\s*$'
)
# `state "Long label" as Id` — a state with a display name.
STATE_ALIAS_RE = re.compile(
    r'^\s*state\s+"(?P<label>[^"]*)"\s+as\s+(?P<id>[A-Za-z_][\w-]*)\s*$'
)
DIRECTION_RE = re.compile(r"^\s*(?:direction\s+)?(?P<dir>TB|TD|LR|RL|BT)\s*$")
HEADER_RE = re.compile(
    r"^\s*(?P<kind>flowchart|graph|stateDiagram-v2|sequenceDiagram|classDiagram|erDiagram)\s*(?P<dir>TB|TD|LR|RL|BT)?\s*$"
)


def _unquote(s):
    s = (s or "").strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
        s = s[1:-1]
    # mermaid allows <br/> and simple inline markup in labels; DOT wants \n
    s = re.sub(r"<br\s*/?>", r"\\n", s)
    s = re.sub(r"</?[bi]>|</?em>|</?strong>", "", s)
    # mermaid's numeric/named entity escapes
    s = s.replace("#quot;", '"').replace("#hash;", "#").replace("#semi;", ";")
    s = re.sub(r"#(\d+);", lambda m: chr(int(m.group(1))), s)
    return s.replace('"', r"\"")


# mermaid node shape -> the nearest DOT shape. Where DOT has no equivalent the
# closest available shape is used; the drawing keeps its meaning even when the
# silhouette differs slightly.
def _edge_attrs(arrow):
    """mermaid arrow -> DOT attributes. One home for the mapping."""
    a = []
    if arrow in ("-.->", "-.-", "<-.->"):
        a.append("style=dashed")
    if arrow == "~~~":
        a.append("style=invis")
    if arrow in ("---", "-.-", "~~~"):
        a.append("dir=none")
    if arrow in ("<-->", "<-.->", "o--o", "x--x"):
        a.append("dir=both")
    if arrow in ("--o", "o--o"):
        a.append("arrowhead=odot")
    if arrow in ("--x", "x--x"):
        a.append("arrowhead=tee")
    if arrow in ("o--o",):
        a.append("arrowtail=odot")
    if arrow in ("x--x",):
        a.append("arrowtail=tee")
    return a


def _shape_of(m):
    for grp, shape in (
        ("dbl", "doublecircle"),
        ("circ", "circle"),
        ("sub", "box3d"),
        ("cyl", "cylinder"),
        ("trapa", "trapezium"),
        ("trapb", "invtrapezium"),
        ("para", "parallelogram"),
        ("parb", "parallelogram"),
        ("stad", "box"),
        ("asym", "cds"),
        ("hex", "hexagon"),
    ):
        if m.groupdict().get(grp) is not None:
            return shape, m.group(grp)
    if m.group("rhomb") is not None:
        return "diamond", m.group("rhomb")
    if m.group("round") is not None:
        return "ellipse", m.group("round")
    return "box", m.group("box")


# `classDef name fill:#eee,stroke:#333` and `class A,B name` — mermaid styling.
# The renderer owns the semantic look, so styling declared in a diagram is
# dropped rather than translated: it is presentation the projection now supplies.
CLASSDEF_RE = re.compile(r"^\s*(?:classDef|class|style|linkStyle)\s+\S.*$")
CLICK_RE = re.compile(r"^\s*click\s+(?P<id>[A-Za-z_][\w-]*)\s+(?P<target>\S+).*$")

# An inline node: `Id["label"]` / `Id("label")` / `Id{"label"}` / `Id(("label"))`,
# optionally followed by mermaid's `:::class` styling suffix.
INLINE_NODE = (
    r"(?P<%s>[A-Za-z_][\w-]*)"
    r"(?:\(\((?P<%s_circ>[^)]*)\)\)|\[(?P<%s_box>[^\]]*)\]"
    r"|\((?P<%s_round>[^)]*)\)|\{(?P<%s_rhomb>[^}]*)\})?"
    r"(?::::[\w-]+)?"
)
ARROW = r"(?P<arrow%d>-\.->|-->|---|==>|-\.-)\s*(?:\|(?P<lbl%d>[^|]*)\|\s*)?"


def _chain_parts(line):
    """Split a mermaid chain `A[..] --> B[..] --> C` into nodes and arrows.

    Returns (nodes, arrows) where nodes is a list of (id, shape, label) and
    arrows a list of (arrow, label), or None when the line is not a chain.
    """
    # ONE node grammar, shared with NODE_RE: an inline node inside a chain must
    # accept every shape a standalone declaration accepts, or the same drawing
    # converts differently depending on where its node happens to be written.
    node_re = CHAIN_NODE_RE
    # arrow forms, including mermaid's MID-ARROW label — `-- text -->`,
    # `-. text .->`, `== text ==>` — where the label sits between the two
    # halves of the arrow rather than in a |bar| after it.
    arrow_re = re.compile(
        r"^\s*(?:"
        r'(?P<mopen>-\.|--|==)[ \t]*(?P<mlabel>"[^"]*"|[^-=.|>"][^-=.|]*?)[ \t]*'
        r"(?P<mclose>\.->|-->|==>|---)"
        r"|(?P<plain>" + ARROWS + r")[ \t]*(?:\|(?P<blabel>[^|]*)\|)?"
        r")\s*"
    )
    nodes, arrows, rest = [], [], line.strip()
    while rest:
        m = node_re.match(rest)
        if not m:
            return None
        ident = m.group("id")
        if any(
            m.groupdict().get(g) is not None
            for g in (
                "dbl",
                "circ",
                "sub",
                "cyl",
                "trapa",
                "trapb",
                "para",
                "parb",
                "stad",
                "asym",
                "hex",
                "box",
                "round",
                "rhomb",
            )
        ):
            shape, label = _shape_of(m)
        else:
            shape, label = None, None
        nodes.append((ident, shape, label))
        rest = rest[m.end() :].strip()
        if not rest:
            break
        a = arrow_re.match(rest)
        if not a:
            return None
        if a.group("mopen"):
            arrow = {"-->": "-->", "==>": "==>", ".->": "-.->", "---": "---"}[
                a.group("mclose")
            ]
            arrows.append((arrow, a.group("mlabel")))
        else:
            arrows.append((a.group("plain"), a.group("blabel")))
        rest = rest[a.end() :].strip()
    if len(nodes) < 2 or len(arrows) != len(nodes) - 1:
        return None
    return nodes, arrows


def _join_multiline_labels(lines):
    """A mermaid label may span source lines inside its quotes. Join those
    lines before parsing, so a wrapped label is one node declaration."""
    out, buf = [], None
    for line in lines:
        cur = line if buf is None else buf + " " + line.strip()
        if cur.count('"') % 2 == 1:
            buf = cur
            continue
        buf = None
        out.append(cur)
    if buf is not None:
        out.append(buf)
    return out


def convert_graph(body_lines):
    """flowchart/graph/stateDiagram-v2 -> DOT. Returns None if not confident."""
    body_lines = _join_multiline_labels(body_lines)
    out, depth, rankdir = [], 0, None
    unconverted = 0
    pseudo = []
    for raw in body_lines:
        line = raw.rstrip()
        if not line.strip():
            out.append("")
            continue
        h = HEADER_RE.match(line)
        if h:
            rankdir = h.group("dir") or rankdir
            continue
        d = DIRECTION_RE.match(line)
        if d and depth > 0:
            continue  # per-cluster direction has no DOT equivalent; drop it
        if d:
            rankdir = d.group("dir")
            continue
        sg = SUBGRAPH_RE.match(line)
        if sg:
            depth += 1
            title = _unquote(sg.group("title") or sg.group("id"))
            out.append("  " * depth + "subgraph cluster_%s {" % sg.group("id"))
            out.append("  " * (depth + 1) + 'label="%s";' % title)
            continue
        if line.strip() == "end" and depth > 0:
            out.append("  " * depth + "}")
            depth -= 1
            continue
        sa = STATE_ALIAS_RE.match(line)
        if sa:
            out.append(
                "  " * (depth + 1)
                + '%s [label="%s"];' % (sa.group("id"), _unquote(sa.group("label")))
            )
            continue
        sc = STATE_COMPOSITE_RE.match(line)
        if sc:
            depth += 1
            name = _unquote(sc.group("name"))
            ident = re.sub(r"\W", "_", name)
            out.append("  " * depth + "subgraph cluster_%s {" % ident)
            out.append("  " * (depth + 1) + 'label="%s";' % name)
            continue
        if line.strip() == "}" and depth > 0:
            out.append("  " * depth + "}")
            depth -= 1
            continue
        se = STATE_EDGE_RE.match(line)
        if se:
            src, dst = se.group("src"), se.group("dst")
            attrs = []
            if se.group("label"):
                attrs.append('label="%s"' % _unquote(se.group("label")))
            # [*] is mermaid's start/end pseudo-state: give each occurrence its
            # own small filled point node, so start and end never merge.
            for side in ("src", "dst"):
                if (src if side == "src" else dst) == "[*]":
                    pseudo.append(0)
                    ident = "_pseudo%d" % len(pseudo)
                    out.append(
                        "  " * (depth + 1)
                        + '%s [shape=point, width=0.12, label=""];' % ident
                    )
                    if side == "src":
                        src = ident
                    else:
                        dst = ident
            tail = (" [%s]" % ", ".join(attrs)) if attrs else ""
            out.append("  " * (depth + 1) + "%s -> %s%s;" % (src, dst, tail))
            continue
        n = NODE_RE.match(line)
        if n:
            shape, label = _shape_of(n)
            attrs = 'label="%s"' % _unquote(label)
            if shape != "box":
                attrs += ", shape=%s" % shape
            out.append("  " * (depth + 1) + "%s [%s];" % (n.group("id"), attrs))
            continue
        ml = MIDLABEL_RE.match(line)
        if ml:
            attrs = ['label="%s"' % _unquote(ml.group("label"))]
            if ml.group("open") == "-." or ml.group("close") == ".->":
                attrs.append("style=dashed")
            if ml.group("close") == "---":
                attrs.append("dir=none")
            out.append(
                "  " * (depth + 1)
                + "%s -> %s [%s];"
                % (ml.group("src"), ml.group("dst"), ", ".join(attrs))
            )
            continue
        e = EDGE_RE.match(line)
        if e:
            attrs = []
            attrs += _edge_attrs(e.group("arrow"))
            if e.group("label"):
                attrs.append('label="%s"' % _unquote(e.group("label")))
            tail = (" [%s]" % ", ".join(attrs)) if attrs else ""
            out.append(
                "  " * (depth + 1)
                + "%s -> %s%s;" % (e.group("src"), e.group("dst"), tail)
            )
            continue
        sf = STATE_FORK_RE.match(line)
        if sf:
            out.append(
                "  " * (depth + 1)
                + '%s [shape=%s, label="", width=0.6, height=0.06, style=filled, fillcolor=black];'
                % (sf.group("id"), "box")
            )
            continue
        sn = STATE_NOTE_RE.match(line)
        if sn:
            ident = "_note_" + sn.group("id")
            out.append(
                "  " * (depth + 1)
                + '%s [shape=note, label="%s"];' % (ident, _unquote(sn.group("text")))
            )
            out.append(
                "  " * (depth + 1)
                + "%s -> %s [style=dotted, dir=none];" % (sn.group("id"), ident)
            )
            continue
        amp = AMP_RE.match(line)
        if amp and ("&" in amp.group("srcs") or "&" in amp.group("dsts")):
            srcs = [x.strip() for x in amp.group("srcs").split("&")]
            dsts = [x.strip() for x in amp.group("dsts").split("&")]
            attrs = _edge_attrs(amp.group("arrow"))
            if amp.group("label"):
                attrs.append('label="%s"' % _unquote(amp.group("label")))
            tail = (" [%s]" % ", ".join(attrs)) if attrs else ""
            for a in srcs:
                for b in dsts:
                    out.append("  " * (depth + 1) + "%s -> %s%s;" % (a, b, tail))
            continue
        if CLASSDEF_RE.match(line):
            continue  # styling is dropped: the renderer owns the semantic look
        ck = CLICK_RE.match(line)
        if ck:
            out.append(
                "  " * (depth + 1)
                + '%s [href="%s"];' % (ck.group("id"), ck.group("target").strip('"'))
            )
            continue
        chain = _chain_parts(line)
        if chain:
            nodes, arrows = chain
            for ident, shape, label in nodes:
                if label is None:
                    continue
                attrs = 'label="%s"' % _unquote(label)
                if shape and shape != "box":
                    attrs += ", shape=%s" % shape
                out.append("  " * (depth + 1) + "%s [%s];" % (ident, attrs))
            for k, (arrow, lbl) in enumerate(arrows):
                attrs = []
                if arrow in ("-.->", "-.-"):
                    attrs.append("style=dashed")
                if arrow in ("---", "-.-"):
                    attrs.append("dir=none")
                if lbl:
                    attrs.append('label="%s"' % _unquote(lbl))
                tail = (" [%s]" % ", ".join(attrs)) if attrs else ""
                out.append(
                    "  " * (depth + 1)
                    + "%s -> %s%s;" % (nodes[k][0], nodes[k + 1][0], tail)
                )
            continue
        # anything else: keep it, visibly, and count it
        unconverted += 1
        out.append("  " * (depth + 1) + "// UNCONVERTED: " + line.strip())
    if unconverted:
        out.insert(
            0,
            "  // MIGRATION 0002: %d line(s) need a human (marked UNCONVERTED)"
            % unconverted,
        )
    head = ["digraph {"]
    if rankdir:
        head.append("  rankdir=%s;" % ("TB" if rankdir == "TD" else rankdir))
    head.append("  node [shape=box, style=rounded];")
    return head + out + ["}"]


def convert(text):
    lines = text.split("\n")
    out, i = [], 0
    while i < len(lines):
        m = FENCE_RE.match(lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue
        ticks, indent = m.group("ticks"), m.group("indent")
        close = re.compile(r"^\s*" + re.escape(ticks) + r"\s*$")
        j = i + 1
        body = []
        while j < len(lines) and not close.match(lines[j]):
            body.append(lines[j])
            j += 1
        kind = ""
        for b in body:
            h = HEADER_RE.match(b)
            if h:
                kind = h.group("kind")
                break
        if kind == "sequenceDiagram":
            out.append(indent + ticks + "seq")
            out.append(
                "// MIGRATION 0002: sequence diagrams need a human — activation,"
            )
            out.append(
                "// alt/opt/loop blocks, and note placement do not convert mechanically."
            )
            out.extend(body)
        elif kind in ("flowchart", "graph", "stateDiagram-v2"):
            converted = convert_graph(body)
            out.append(indent + ticks + "dot")
            out.extend(converted)
        else:
            # unknown diagram kind: leave the fence exactly as it was
            out.append(lines[i])
            out.extend(body)
        out.append(indent + ticks)
        i = j + 1
    return "\n".join(out)


def main():
    if len(sys.argv) > 1:
        path = sys.argv[1]
        with open(path, encoding="utf-8") as f:
            src = f.read()
        with open(path, "w", encoding="utf-8") as f:
            f.write(convert(src))
    else:
        sys.stdout.write(convert(sys.stdin.read()))


if __name__ == "__main__":
    main()
