"""Run the Typst projection shared by Markdown and semantic review."""

from pathlib import Path
from tempfile import TemporaryDirectory
import json
import os
import subprocess

from design_source import (
    LayerSource,
    ProjectionError,
    ProjectionOperationalError,
    TermParseError,
    typst_string,
)
from typst_policy import command as typst_command, environment as typst_environment

SEMANTIC_LABEL = "<design-semantic>"


def semantic_probe(layer: LayerSource, scratch: Path, library: Path) -> Path:
    probe = scratch / "probe.typ"
    documents = layer.named_documents
    try:
        terms = layer.terms
    except OSError as error:
        raise ProjectionOperationalError(str(error)) from error
    except TermParseError as error:
        raise ProjectionError(str(error)) from error
    lines = []
    lines.append(f"#import {typst_string(Path(os.path.relpath(library, scratch)))}: *")
    term_titles = ", ".join(
        f"{typst_string(Path(term['slug']))}: {typst_string(Path(term['title_text']))}"
        for term in sorted(terms, key=lambda item: str(item["slug"]))
    )
    term_owners = ", ".join(
        f"{typst_string(Path(term['slug']))}: {typst_string(Path(term['context']))}"
        for term in sorted(terms, key=lambda item: str(item["slug"]))
    )
    context_names = ", ".join(
        typst_string(Path(name)) for name, _ in documents if name != "root"
    )
    lines.extend(
        [
            "#declare-vocabulary(",
            f"  terms: ({term_titles + (',' if term_titles else '')}),",
            f"  term-owners: ({term_owners + (',' if term_owners else '')}),",
            f"  contexts: ({context_names + (',' if context_names else '')}),",
            ")",
        ]
    )
    for index, (name, source) in enumerate(documents):
        relative = Path(os.path.relpath(source, scratch))
        module = f"document_{index}"
        lines.extend(
            [
                f"#import {typst_string(relative)} as {module}",
                f"#let values_{index} = dictionary({module})",
                f'#let title_{index} = if "title" in values_{index} {{ values_{index}.title }} else {{ [{name} context] }}',
                # `context_command` is the one binding the folder-contract
                # generator reads off a design module. It travels in the
                # document record so that generator needs no second probe.
                f'#metadata((kind: "document", name: "{name}", level: {1 if index == 0 else 2}, title: title_{index}, body: {module}.body, "context-command": values_{index}.at("context_command", default: none))) <design-semantic>',
            ]
        )
    lines.append("")
    for term in sorted(
        terms, key=lambda item: (str(item["context"]), str(item["slug"]))
    ):
        lines.append(
            f'#metadata((kind: "term", owner: {typst_string(Path(str(term["context"])))}, '
            f"slug: {typst_string(Path(str(term['slug'])))}, "
            f"title: {term['title_src']}, body: {term['body_src']})) <design-semantic>"
        )
    lines.append("")
    probe.write_text("\n".join(lines), encoding="utf-8")
    return probe


def query_file(
    source: Path, *, root: str | None = None, review: bool = False
) -> list[object]:
    result = subprocess.run(
        [
            typst_command(),
            "query",
            str(source),
            SEMANTIC_LABEL,
            "--field",
            "value",
            "--input",
            "context=1",
            *(["--input", "review-projection=1"] if review else []),
            *(["--root", root] if root else []),
        ],
        capture_output=True,
        text=True,
        env=typst_environment(),
    )
    if result.returncode:
        raise ProjectionError(result.stderr.strip() or "Typst semantic query failed")
    try:
        records = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise ProjectionError("Typst returned invalid semantic JSON") from error
    if not isinstance(records, list):
        raise ProjectionError("Typst semantic query did not return an array")
    return records


def query_layer(
    layer: LayerSource, library: Path, *, review: bool = False
) -> list[object]:
    # Glossary bodies can import files relative to the generated probe.
    # Keep it at the same depth as the aggregate under .render/.
    with TemporaryDirectory(prefix="design-context.", dir=layer.root) as name:
        scratch = Path(name)
        probe = semantic_probe(layer, scratch, library)
        root = os.path.commonpath((layer.root.parent, scratch, library))
        return query_file(probe, root=root, review=review)
