"""Publish generated artifacts atomically to paths that must be fresh."""

from pathlib import Path
from typing import BinaryIO
import os
import shutil
import tempfile


def write_new_output(output: Path, content: bytes | BinaryIO) -> None:
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            prefix=f".{output.name}.", dir=output.parent, delete=False
        ) as stream:
            temporary = Path(stream.name)
            if isinstance(content, bytes):
                stream.write(content)
            else:
                shutil.copyfileobj(content, stream)
        os.link(temporary, output)
    finally:
        if temporary is not None:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass
