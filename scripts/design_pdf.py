"""Assemble design documents under one Typst shell and compile the PDF."""

from contextlib import ExitStack
from pathlib import Path
import json
import os
import re
import subprocess
import sys
import tempfile

from typst_policy import command as typst_command
from typst_policy import environment as typst_environment

from design_source import (
    LayerSource,
    LegacyMarkdownLayer,
    TermParseError,
    refuse_divergent_library,
    typst_string,
)


# ---------------------------------------------------------------------------
# the renderer's own warnings — a warning means the page is not what was written
# ---------------------------------------------------------------------------
# The compiler reports a whole class of corruption on every build, and the gate
# used to throw it away: the compile site ran with capture_output=True and wrote
# proc.stderr ONLY when the return code was non-zero. So a document that
# rendered "successfully" while Typst said `warning: no text within stars`
# passed the gate with its bold silently dropped.
#
# A warning is not advisory here. The author calls the library directly, so a
# warning means the compiler had to read something loosely — the page is not
# what the author wrote.
WARN_RE = re.compile(r"^warning: (.+)$", re.M)


def warns(stderr_text, src_path, report):
    """Report Typst warnings. Returns True when any were found."""
    found = WARN_RE.findall(stderr_text or "")
    if not found:
        return False
    for w in found:
        report(
            "design-aggregate: violation: %s: the renderer warned: %s\n" % (src_path, w)
        )
    report(
        "design-aggregate: %d renderer warning(s) — the rendered page is "
        "not what the author wrote.\n" % len(found)
    )
    return True


# ---------------------------------------------------------------------------
# the guideline trail — the library GUIDES, so the guidance has to be READ
# ---------------------------------------------------------------------------
# The library's structural rules do not stop a build: a layer missing a
# foundation kind, or ordering its sections differently, renders. What the
# library must not do is fall silent about it, because a check that passes over
# nothing is the failure this repo has been bitten by, and an advisory nobody
# reads is that same failure wearing a different hat.
#
# Typst has no author-callable warning, so each guideline records itself as
# `metadata` tagged <design-guideline> during the compile, and this reads the
# whole trail back afterwards with `typst query`. Metadata draws nothing, so the
# guidance never reaches the page — and never disturbs the byte-compare the
# freshness check rests on.
#
# The query is a SECOND compile of the same source. That is the cost of the
# channel, and it is paid only to report: the render itself has already
# succeeded by the time this runs.
def guidelines(typst, agg, root, lib, env):
    """Read the guideline trail out of a compiled document.

    Returns a list of {rule, message} dicts. A query that fails for any reason
    returns None, which the caller reports rather than silently treating as a
    clean run — a reporter that cannot read its own trail must say so.
    """
    proc = subprocess.run(
        [
            typst,
            "query",
            agg,
            "<design-guideline>",
            "--field",
            "value",
            "--root",
            os.path.commonpath(
                [os.path.abspath(os.path.join(root, "..", "..")), os.path.abspath(lib)]
            ),
        ],
        capture_output=True,
        text=True,
        env=env,
    )
    if proc.returncode != 0:
        return None
    try:
        found = json.loads(proc.stdout or "[]")
    except ValueError:
        return None
    return [g for g in found if isinstance(g, dict) and "rule" in g]


def report_guidelines(found, report):
    """Print every guideline, then a count summary naming what fired.

    ALWAYS prints, including the clean case. A run that says nothing leaves a
    reader unable to tell a clean layer from a reporter that never ran, which is
    the whole defect this channel exists to avoid.
    """
    if found is None:
        report(
            "design-aggregate: the guideline trail could not be read, so "
            "this render reports no guidance — treat it as unknown, not as "
            "clean.\n"
        )
        return
    for g in found:
        # rule, offending item, and what was expected all travel in the
        # message the library wrote; a guideline that does not say what to do
        # instead is noise, so the format keeps both halves visible.
        report(
            "design-aggregate: guideline: %s: %s\n"
            % (g.get("rule", "?"), g.get("message", ""))
        )
    if not found:
        report(
            "design-aggregate: 0 guideline(s) — every structural guideline "
            "is satisfied.\n"
        )
        return
    kinds = {}
    for g in found:
        # the rule name is `<area>.<rule>`; the area is what a reader counts by
        kinds[g.get("rule", "?").split(".")[0]] = (
            kinds.get(g.get("rule", "?").split(".")[0], 0) + 1
        )
    summary = ", ".join("%d %s" % (n, k) for k, n in sorted(kinds.items()))
    report(
        "design-aggregate: %d guideline(s): %s — none blocks the render; "
        "run with DESIGN_STRICT=1 to make them fail.\n" % (len(found), summary)
    )


def render_layer(layer: LayerSource, out_pdf, check, lib, *, review_diagrams=None):
    """Assemble the layer into the one rendered document.

    There is no conversion step: each context's design.typ is imported as a
    Typst module and its `body` is placed under the chapter heading. Nothing
    parses the authored file, so no construct can be half-translated.

    The per-document page shell is NOT applied — the aggregate supplies one
    shell for the whole layer. A context's design.typ therefore exports its
    content as `body` rather than calling `design-doc` itself.

    WHERE THE DOCUMENT-LEVEL CONTRACTS GO. They belong to the library, which
    can hold them because the author calls it directly: a `section` cannot omit
    its title, a `pending-entry` cannot carry a malformed date, and an ordering
    rule is a call-order the document itself expresses. A second parser over
    the authored source would be a second reader of one vocabulary, free to
    disagree with the library about what the document says.

    The foundation ORDER is enforced that way here. Each foundation statement
    records its kind in a state as it is called, and `assert-foundation-order`
    reads the trail back. The scope is ONE CONTEXT — the trail is cleared before
    each chapter's body and judged at the end of it — because a layer renders
    many chapters into one document, and a chapter opening on a goal does not
    follow the previous chapter's principle.
    """
    root, docs, terms = str(layer.root), layer.documents, layer.terms
    gen_dir = os.path.join(root, ".render")
    os.makedirs(gen_dir, exist_ok=True)
    rel_lib = os.path.relpath(os.path.abspath(lib), os.path.abspath(gen_dir))
    L = ['#import "%s": *' % rel_lib, ""]

    # Import every design module before declaring the shared vocabulary. The
    # optional module-level `accent` is the one authored palette binding for a
    # context, so citations and glossary ownership chips can resolve it without
    # repeating a tint at every call site.
    module_names = {}
    for name, doc in docs:
        stem = "root" if name is None else name
        rel_doc = os.path.relpath(os.path.abspath(doc), os.path.abspath(gen_dir))
        mod = "_ctx_%s" % re.sub(r"[^A-Za-z0-9]", "_", stem)
        module_names[(name, doc)] = mod
        L.append("#import %s as %s" % (typst_string(rel_doc), mod))
        L.append("#let _m_%s = dictionary(%s)" % (mod, mod))
    L.append("")

    L.append("#show: aggregate-doc.with(")
    L.append("  title: [Design layer],")
    L.append("  subtitle: [the whole layer, as one document],")
    L.append(")")
    L.append("")

    # THE LAYER'S VOCABULARY, declared before any body renders. `term()` and
    # `ctx()` resolve against this registry, so a citation prints the term's
    # TITLE and an undeclared slug stops the compile at the citing line. It is
    # emitted here rather than beside the glossary because a citation appears
    # in the very first chapter, long before the glossary is assembled.
    #
    # The title is taken as PLAIN TEXT. A title carrying markup would need the
    # markup evaluated to be placed inline, and a chip renders a short phrase;
    # the plain reading is what a reader sees either way.
    _titles = ", ".join(
        "%s: %s" % (typst_string(t["slug"]), typst_string(t["title_text"]))
        for t in sorted(terms, key=lambda x: x["slug"])
    )
    _owners = ", ".join(
        "%s: %s" % (typst_string(t["slug"]), typst_string(t["context"]))
        for t in sorted(terms, key=lambda x: x["slug"])
    )
    # A Typst array literal needs a TRAILING COMMA to stay an array at length
    # one: `("alpha")` is the string "alpha", while `("alpha",)` is the
    # one-element array. Without it a single-context layer declared its context
    # list as a string, and `ctx()` then tested membership against that string's
    # characters and called `.join` on it — so a layer with exactly one context
    # got a type error instead of the citation check.
    _ctx_names = "".join(
        "%s, " % typst_string(name) for name, _doc in docs if name is not None
    )
    _ctx_accents = ", ".join(
        '%s: _m_%s.at("accent", default: none)'
        % (
            typst_string("root" if name is None else name),
            module_names[(name, doc)],
        )
        for name, doc in docs
    )
    L.append("#declare-vocabulary(")
    L.append("  terms: (%s)," % (_titles if _titles else ":"))
    L.append("  term-owners: (%s)," % (_owners if _owners else ":"))
    L.append("  contexts: %s," % ("(%s)" % _ctx_names if _ctx_names else "()"))
    L.append("  context-accents: (%s)," % _ctx_accents)
    L.append(")")
    L.append("")

    for name, doc in docs:
        stem = "root" if name is None else name
        mod = module_names[(name, doc)]
        L.append("#let _m = _m_%s" % mod)
        # The chapter heading carries the context label, so a cross-document
        # reference resolves to it. A document declaring its own `title` names
        # the chapter; otherwise the directory name does. A Typst module is not
        # a dictionary, so the presence test goes through dictionary(), which
        # is the conversion that lets a missing binding fall back rather than
        # fail the build.
        L.append("#let _m = dictionary(%s)" % mod)
        L.append(
            '#let _t = if "title" in _m { _m.title } else { %s }'
            % typst_string(stem + " context")
        )
        L.append(
            "#chapter-page(_t, kind: %s)"
            % typst_string("root design" if stem == "root" else "context")
        )
        L.append("#pagebreak()")
        L.append("= #_t <ctx-%s>" % stem)
        # The foundation is judged per context, so the trail is cleared before
        # each chapter's body. Without the reset a later chapter opening on a
        # goal would read as following the previous chapter's principle, and a
        # context with no foundation of its own would pass the per-kind minimum
        # on the strength of the previous chapter's statements.
        L.append("#foundation-scope-reset")
        L.append("#%s.body" % mod)
        # ...and judged at the end of that body, while the trail still holds
        # this context's calls and no other's. ORDER and the per-kind MINIMUM
        # both read the same trail.
        #
        # `index_only` waives the minimum for a root that merely indexes its
        # contexts. It is read from the document's own module, the same way its
        # title is, so the waiver is the author's declaration rather than a
        # guess this script makes about which documents look like index roots.
        L.append("#assert-foundation-order")
        L.append('#let _io = if "index_only" in _m { _m.index_only } else { false }')
        # The per-kind minimum binds the ROOT document only; a context may
        # omit any foundation kind. Which document is the root is this
        # script's knowledge — it is the one discovered at the layer root — so
        # it is passed rather than left for the library to guess.
        L.append(
            "#assert-foundation-cardinality(index-only: _io, root: %s)"
            % ("true" if name is None else "false")
        )
        L.append("")

    # Entity, state-type, attribute, and state-machine calls contribute one
    # document-wide trail. Their ids cross context boundaries, so this assertion
    # runs once after every body rather than once per chapter.
    L.append("#assert-state-links")
    L.append("")

    if terms:
        L.append("#heading(level: 1, numbering: none)[Glossary] <glossary>")
        L.append("Every term the layer declares, with the context that owns it.")
        L.append("")
        # A term's title and body are SPLICED here as the source text the author
        # wrote, into a document that has already imported the library. That
        # scope is the whole reason the splice survives: a term body cites its
        # siblings — `#term("term-unit")`, `#ctx("core")` — and those names
        # resolve because they are in scope AT THE SPLICE SITE. A CONTEXT.typ
        # imports nothing and is not expected to; the aggregate supplies the
        # scope, which is the contract every host was written against.
        #
        # Importing CONTEXT.typ as a module instead would evaluate it in its OWN
        # scope, where those names are unbound, and a Typst module is imported
        # EAGERLY — so a single cross-reference in any term body fails the whole
        # build before a page is laid out. That is not a hypothetical: it broke
        # every layer whose terms cite each other.
        #
        # The splice carries a `#` so the captured brackets are the content
        # block's OWN DELIMITERS. That prefix is the entire bracket fix. The old
        # code re-wrapped the captured text in a second pair — `[%s]` around an
        # already-bracketed `[Accent]` — which made the inner pair literal
        # characters, so every term headed itself `[Accent]` and closed its body
        # on a stray `]`. Nothing was wrong with the splice; the extra wrap was.
        for t in sorted(terms, key=lambda x: x["sort_key"]):
            L.append(
                "#heading(level: 2, numbering: none, outlined: false)[%s] <%s>"
                % (_splice(t["title_src"]), t["slug"])
            )
            L.append("#context-owner(%s)" % typst_string(t["context"]))
            L.append(_splice(t["body_src"]))
            L.append("")

    # Every citation is resolvable, judged once the whole document has been
    # laid out and every term() call has recorded itself. This closes the
    # empty-registry fallback: a layer that cites terms while declaring none
    # would otherwise print raw slugs and exit 0.
    L.append("#assert-references-resolvable")
    L.append("")

    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", prefix="_aggregate-", suffix=".typ", dir=gen_dir
    ) as stream:
        stream.write("\n".join(L) + "\n")
        stream.flush()
        return compile_and_verify(
            stream.name,
            root,
            out_pdf,
            check,
            lib,
            len(docs),
            len(terms),
            review_diagrams,
        )


def _splice(src):
    """A captured Typst value, ready to place in content position.

    A content block keeps its own brackets and gains a `#` so they delimit the
    block rather than printing as characters; a quoted string is placed as the
    expression it already is. Either way the value is spliced, never re-wrapped
    — the re-wrap is what put literal brackets on every glossary heading.
    """
    return "#" + src


def compile_and_verify(
    agg, root, out_pdf, check, lib, n_contexts, n_terms, review_diagrams
):
    """Compile the visual document and retain the render and freshness checks."""
    env = typst_environment()
    strict = ["--input", "strict=1"] if os.environ.get("DESIGN_STRICT") else []
    with ExitStack() as scratch:
        target = os.path.abspath(out_pdf)
        if check:
            tmpdir = scratch.enter_context(
                tempfile.TemporaryDirectory(prefix="design-aggregate.")
            )
            target = os.path.join(tmpdir, "fresh.pdf")
        proc = subprocess.run(
            [
                typst_command(),
                "compile",
                agg,
                target,
                *strict,
                *(
                    ["--input", "design-review-diagrams=" + ",".join(review_diagrams)]
                    if review_diagrams
                    else []
                ),
                "--root",
                os.path.commonpath(
                    [
                        os.path.abspath(os.path.join(root, "..", "..")),
                        os.path.abspath(lib),
                    ]
                ),
            ],
            capture_output=True,
            text=True,
            env=env,
        )
        if proc.returncode:
            sys.stderr.write(proc.stderr)
            return 1
        if warns(proc.stderr, out_pdf, report=sys.stderr.write):
            return 1
        if review_diagrams is not None:
            # Review prints a change report. The compiled companions still
            # enforce render diagnostics and strict mode.
            return 0

        found = [] if strict else guidelines(typst_command(), agg, root, lib, env)
        report_guidelines(found, sys.stderr.write)
        if check:
            if not os.path.exists(out_pdf):
                sys.stderr.write(
                    "design-aggregate: %s is missing (the layer has "
                    "no rendered document)\n" % out_pdf
                )
                return 1
            if Path(out_pdf).read_bytes() != Path(target).read_bytes():
                sys.stderr.write(
                    "design-aggregate: %s is stale (does not match a "
                    "fresh render)\n" % out_pdf
                )
                return 1

        verb = f"{out_pdf} is fresh" if check else f"wrote {out_pdf}"
        sys.stdout.write(
            f"design-aggregate: {verb} ({n_contexts} context(s), {n_terms} term(s))\n"
        )
        return 0


def main():
    args = [a for a in sys.argv[1:] if a != "--check"]
    check = "--check" in sys.argv[1:]
    if len(args) != 2:
        sys.stderr.write("usage: design-aggregate <layer-root> <out.pdf> [--check]\n")
        return 2
    root, out_pdf = args
    if not os.path.isdir(root):
        sys.stderr.write("design-aggregate: error: no layer root at %s\n" % root)
        return 2

    # $DESIGN_LIB_DIR wins so the projected library can live outside the layer
    # — in a read-only bundle, say — with the layer-root copy as the fallback.
    lib_dir = os.environ.get("DESIGN_LIB_DIR") or os.path.join(root, ".render")
    lib = os.path.join(lib_dir, "designlib.typ")
    if not os.path.exists(lib):
        sys.stderr.write(
            "design-aggregate: error: no projected library at %s "
            "(run render-project, or set DESIGN_LIB_DIR)\n" % lib
        )
        return 2

    rc = refuse_divergent_library(root, lib)
    if rc:
        return rc

    try:
        layer = LayerSource.discover(Path(root))
    except LegacyMarkdownLayer as exc:
        sys.stderr.write(str(exc))
        return 2
    if not layer.documents:
        sys.stderr.write("design-aggregate: error: no design.typ under %s\n" % root)
        return 2

    try:
        return render_layer(layer, out_pdf, check, lib)
    except TermParseError as exc:
        sys.stderr.write("design-aggregate: error: %s\n" % exc)
        return 2
