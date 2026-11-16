"""Discover a layer and read its glossary once per command."""

from dataclasses import dataclass
from functools import cached_property
from pathlib import Path
import os
import re
import sys
from typing import TypedDict


class GlossaryTerm(TypedDict):
    slug: str
    sort_key: str
    title_text: str
    title_src: str
    body_src: str
    context: str


@dataclass(frozen=True)
class LayerSource:
    root: Path
    documents: tuple[tuple[str | None, str], ...]

    @classmethod
    def discover(cls, root: Path) -> "LayerSource":
        return cls(root, tuple(contexts_of(str(root))))

    @property
    def named_documents(self) -> list[tuple[str, Path]]:
        return [
            ("root" if name is None else name, Path(path))
            for name, path in self.documents
        ]

    @cached_property
    def terms(self) -> list[GlossaryTerm]:
        return typst_glossary_terms(str(self.root), self.documents)


def projection_layer(root: Path) -> LayerSource:
    try:
        return LayerSource.discover(root)
    except OSError as error:
        raise ProjectionOperationalError(str(error)) from error
    except LegacyMarkdownLayer as error:
        raise ProjectionError(str(error)) from error


class LegacyMarkdownLayer(Exception):
    """A layer still authored as design.md, after markdown authoring was removed."""


class TermParseError(Exception):
    """A declared term the glossary scan could not read.

    Raised rather than skipped. Every path this replaces dropped the term and
    carried on, so the document rendered without it and the summary line
    reported the smaller count as though it were the whole vocabulary.
    """


class ProjectionError(Exception):
    """The source compiled but its semantic tree cannot be represented."""


class ProjectionOperationalError(Exception):
    """The projection could not run because its execution inputs are invalid."""


def typst_glossary_terms(root, docs) -> list[GlossaryTerm]:
    """Every term the layer declares, with its owning context.

    A CONTEXT.typ exports `terms`, an array of (slug, title, body) — the three
    facts a glossary entry carries: what the concept is called, the id every
    citation resolves against, and the definition.

    THE SOURCE TEXT IS WHAT GETS RENDERED, and that is deliberate. The title
    and body are spliced into the generated aggregate exactly as the author
    wrote them, so they are evaluated where the library is already imported and
    a citation like `#term("term-unit")` resolves. A CONTEXT.typ imports
    nothing; the aggregate supplies the scope. Importing it as a module instead
    evaluates it in its own scope, where every library name is unbound, and the
    import is EAGER — one cross-reference anywhere fails the entire build.

    The title is additionally read as plain text for ONE purpose, the sort key,
    and a title carrying markup sorts by the characters it is written with;
    nothing on the rendered page depends on that reading.

    THE BRACKET SCAN IS NOT DECORATION. A title or body is a Typst content
    block, and content blocks NEST — `title: [The #emph[X] name]` is ordinary
    authoring. A regex bounded by the first `]` stops inside such a title,
    fails to match the term, and silently omits it: the glossary loses an entry
    and the summary line reports the smaller count as though it were right.
    Matching brackets by depth is what makes the scan see every term an author
    actually wrote.
    """
    found = []
    for name, doc in docs:
        stem = "root" if name is None else name
        ctx = os.path.join(os.path.dirname(doc), "CONTEXT.typ")
        if not os.path.exists(ctx):
            continue
        src = Path(ctx).read_text(encoding="utf-8")
        rel = os.path.relpath(ctx, root)
        # THE DECLARED COUNT, read independently of the parse below. Every
        # `slug:` in the file is a term the author wrote; the scan that follows
        # is the only thing that can lose one, so the two numbers are compared
        # rather than trusted. A slug that stops matching — renamed to a form
        # the pattern does not accept, or followed by a field the scan cannot
        # read — used to fall out through one of three `continue` paths, and
        # the summary reported the smaller count as though it were right.
        declared = re.findall(r'\bslug:\s*"([^"]*)"', src)
        parsed = []
        for m in re.finditer(
            r'slug:\s*"(?P<slug>term-[a-z0-9-]+)"\s*,\s*title:\s*', src
        ):
            title = _typst_value_at(src, m.end())
            if title is None:
                raise TermParseError(
                    "%s: term %r declares a title the scan cannot read. A "
                    "title is a content block `[...]` or a quoted string."
                    % (rel, m.group("slug"))
                )
            b = re.compile(r"\s*,\s*body:\s*").match(src, title["end"])
            if b is None:
                raise TermParseError(
                    "%s: term %r has no `body:` after its title. A term "
                    "carries a slug, a title, and a body, in that order."
                    % (rel, m.group("slug"))
                )
            body = _typst_value_at(src, b.end())
            if body is None:
                raise TermParseError(
                    "%s: term %r declares a body the scan cannot read. A body "
                    "is a content block `[...]` or a quoted string."
                    % (rel, m.group("slug"))
                )
            # THE ENTRY MUST CLOSE AFTER ITS BODY. The scan reads each
            # slug/title/body run on its own, so two entries fused into one
            # dictionary (the `),` `(` between them lost, typically while
            # resolving a merge) still parse as two terms and match the slug
            # count. Typst rejects the repeated keys, but nothing here
            # evaluates CONTEXT.typ as written, so the fault is caught here.
            close = re.compile(r"(?:\s|//[^\n]*)*(?:,(?:\s|//[^\n]*)*)?\)").match(
                src, body["end"]
            )
            if close is None:
                rest = src[body["end"] :]
                stray = body["end"] + len(rest) - len(rest.lstrip(" \t\n,"))
                line = src.count("\n", 0, stray) + 1
                ahead = src[stray : stray + 24]
                raise TermParseError(
                    "%s:%d: term %r is not closed after its body; found %r "
                    "where the `)` ending the entry belongs. Two entries have "
                    "probably fused into one dictionary with repeated keys, "
                    "which Typst rejects. Restore the `),` `(` between them."
                    % (rel, line, m.group("slug"), ahead)
                )
            parsed.append(m.group("slug"))
            found.append(
                {
                    "slug": m.group("slug"),
                    "sort_key": title["text"].lower(),
                    # the title as plain text, which is what an inline citation
                    # renders; the source form is what the glossary heading splices.
                    "title_text": title["text"].strip(),
                    "title_src": title["src"],
                    "body_src": body["src"],
                    "context": stem,
                }
            )
        # A slug the file declares and the scan did not reach is a term the
        # glossary would silently lose. Naming it is the whole point: the
        # failure it replaces was a count quietly one lower than the truth.
        if len(parsed) != len(declared):
            lost = [s for s in declared if s not in parsed]
            raise TermParseError(
                "%s declares %d term(s) and only %d parsed; unreachable: %s. "
                "A term slug is `term-` followed by lowercase words joined by "
                "single hyphens."
                % (rel, len(declared), len(parsed), ", ".join(repr(s) for s in lost))
            )
    return found


def refuse_divergent_library(root, lib):
    """Refuse a layer-local library that disagrees with the one being used.

    THE FAILURE THIS PREVENTS IS SILENT, which is why it is a hard error. A
    Typst context imports its library by a LAYER-RELATIVE path — `design.typ`
    opens `#import ".render/designlib.typ"` — while the aggregate compiles
    against $DESIGN_LIB_DIR, which for a host is a pinned read-only bundle. When
    those two are the same file nothing is wrong. When the layer's own `.render`
    is left over from an older pin, every context is validated by the OLD
    library while the aggregate believes it used the new one.

    Nothing about that looks broken. The document renders, the chapters are all
    present, the summary line counts them, and the exit status is 0 — while
    every per-block contract and every document-level assertion that the newer
    library added is simply absent. A foundation authored out of order rendered
    clean exactly this way: the check existed, was wired correctly, and was
    read from a `.render` that predated it.

    `.render` is generated and usually gitignored, so it is the one input no
    reviewer sees and no commit records. Refusing here — naming both paths and
    the fix — turns a check that quietly does not run into a build that stops.
    """
    local = os.path.join(root, ".render", "designlib.typ")
    if not os.path.exists(local):
        return 0
    if os.path.abspath(local) == os.path.abspath(lib):
        return 0

    # EVERY LIBRARY FILE IS COMPARED, not just designlib.typ. The library is a
    # DIRECTORY of hand-written Typst files now, and designlib.typ is the entry
    # point that imports the rest — a short, stable file. Comparing it alone
    # would compare the one file least likely to change while every rule that
    # actually moved sits in a sibling, which is exactly the silent divergence
    # this refusal exists to stop.
    #
    # THE SCHEMA IS DELIBERATELY EXCLUDED, and that is a different question
    # rather than an oversight. The assembled directory carries a copy of the
    # schema so the library can read it by a relative path, but that copy is an
    # INPUT THE CONSUMER OWNS, not part of the library's identity. A consumer's
    # schema is legitimately a strict SUPERSET of the bundle's: the public copy
    # holds only the machine-checkable half the renderer decides, while a host
    # adds whatever else its own skills cite. Comparing the two would refuse
    # every correct layer, because no real consumer's schema is byte-identical
    # to the bundle's.
    #
    # Whether the two schemas AGREE where they overlap is a real question, and
    # it already has an owner: schema-drift-check compares the shared subset and
    # states outright that a key present on only one side is not drift. Two
    # checks, two questions, no overlap — this one asks whether the LIBRARY
    # differs, and answers only that.
    local_dir = os.path.dirname(local)
    lib_dir_abs = os.path.dirname(os.path.abspath(lib))

    def _snapshot(d):
        out = {}
        for name in sorted(os.listdir(d)):
            if not name.endswith(".typ"):
                continue
            with open(os.path.join(d, name), "rb") as f:
                out[name] = f.read()
        return out

    try:
        a = _snapshot(local_dir)
        b = _snapshot(lib_dir_abs)
    except OSError as e:
        sys.stderr.write(
            "design-aggregate: error: cannot compare the layer's "
            "projected library with the one in use: %s\n" % e
        )
        return 2
    if a == b:
        return 0
    # Name WHICH files disagree, so the reader is not left diffing two
    # directories by hand to find out what went stale.
    differing = sorted(set(a) ^ set(b) | {k for k in set(a) & set(b) if a[k] != b[k]})
    sys.stderr.write(
        "design-aggregate: error: the layer's own projected library differs "
        "from the one this run compiles against, so each context would be "
        "validated by a DIFFERENT library than the document.\n"
        "  the layer's copy : %s\n"
        "  the one in use   : %s\n"
        "  differing file(s): %s\n"
        "A Typst context imports the layer-relative path, so a stale copy "
        "silently disables every contract the current library added — the "
        "document still renders and still exits 0. Delete the layer's .render "
        "(it is generated), or re-run render-project into it.\n"
        % (local_dir, lib_dir_abs, ", ".join(differing))
    )
    return 2


def _typst_value_at(src, i):
    """The Typst value starting at `i`, or None if none starts there.

    Returns {"src", "text", "end"} — the value's OWN SOURCE including its
    delimiters, which is what gets spliced; the text inside them, which is what
    sorts; and the offset just past it, which is where the caller resumes
    scanning for the next field.

    Handles the two forms a term field takes — a content block `[...]`, read
    with BALANCED brackets so a nested block does not end it early, and a
    quoted string `"..."`.
    """
    if i >= len(src):
        return None
    if src[i] == '"':
        j = src.find('"', i + 1)
        if j < 0:
            return None
        return {"src": src[i : j + 1], "text": src[i + 1 : j], "end": j + 1}
    if src[i] != "[":
        return None
    depth, j = 0, i
    while j < len(src):
        if src[j] == "[":
            depth += 1
        elif src[j] == "]":
            depth -= 1
            if depth == 0:
                return {"src": src[i : j + 1], "text": src[i + 1 : j], "end": j + 1}
        j += 1
    return None


def _homes(root):
    """Every place a design document may live, in a stable order.

    (context-name-or-None, directory). The root document first, then each
    context directory alphabetically — the order the chapters render in.
    """
    homes = [(None, root)]
    for name in sorted(os.listdir(root)):
        d = os.path.join(root, name)
        if name.startswith(".") or not os.path.isdir(d):
            continue
        homes.append((name, d))
    return homes


def contexts_of(root):
    """The layer's design documents, in chapter order.

    Returns [(context-name-or-None, path), ...] over the design.typ files.

    TYPST IS THE ONLY AUTHORING NOTATION. A layer still carrying design.md is a
    LEGACY layer, and it is refused by name rather than ignored: walking past it
    would report "no design layer" against a directory visibly full of design
    documents, and the reader would look for the wrong fault. The refusal names
    every markdown file and points at the migration.
    """
    md, typ = [], []
    for name, d in _homes(root):
        m = os.path.join(d, "design.md")
        t = os.path.join(d, "design.typ")
        if os.path.exists(m):
            md.append((name, m))
        if os.path.exists(t):
            typ.append((name, t))

    if md:
        lines = [
            "design-aggregate: error: this layer is authored in Markdown, "
            "and the framework now authors Typst.\n"
        ]
        lines.append("  markdown (design.md):\n")
        for _n, p in md:
            lines.append("    %s\n" % os.path.relpath(p, root))
        lines.append(
            "  Markdown authoring was removed: a design document is a "
            "design.typ calling the library directly, and its glossary "
            "a CONTEXT.typ. See migration 0008.\n"
        )
        raise LegacyMarkdownLayer("".join(lines))

    return typ


def typst_string(path: str | Path) -> str:
    value = str(path).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{value}"'


def renderer_library(layer: Path) -> Path:
    """Resolve and validate the renderer library used by the projection."""
    configured = os.environ.get("DESIGN_LIB_DIR")
    library_dir = Path(configured) if configured else layer / ".render"
    library = library_dir / "designlib.typ"
    if not library.is_file():
        raise ProjectionOperationalError(f"projected library not found: {library}")
    if configured:
        try:
            result = refuse_divergent_library(str(layer), str(library))
        except Exception as error:
            raise ProjectionOperationalError(
                "cannot compare the projected libraries"
            ) from error
        if result:
            raise ProjectionOperationalError(
                "the layer's projected library differs from the bundled library"
            )
    return library.resolve()
