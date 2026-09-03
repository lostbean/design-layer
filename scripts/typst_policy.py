"""Shared Typst process policy for every gate subprocess.

The gate's PDF freshness contract compares bytes. Typst's default font search
includes host fonts, so the same source can resolve a different font file on
two hosts and produce different bytes. This module keeps the renderer's font
inputs inside the pinned Typst binary's embedded set.
"""

import os
from collections.abc import Mapping


def command() -> str:
    """Return the Typst executable supplied by the gate runtime.

    The gate runtime puts its policy wrapper first on ``PATH``. Direct gate
    scripts therefore select ``typst`` without accepting an executable
    override from the caller.
    """
    return "typst"


def environment(base: Mapping[str, str] | None = None) -> dict[str, str]:
    """Return an environment with deterministic embedded-font resolution."""
    env = dict(os.environ if base is None else base)
    env["SOURCE_DATE_EPOCH"] = "0"
    env["TYPST_IGNORE_SYSTEM_FONTS"] = "true"
    # Typst treats an empty TYPST_FONT_PATHS as an invalid path. Removing the
    # variable is the policy, and it also removes inherited host configuration.
    env.pop("TYPST_FONT_PATHS", None)
    # Embedded fonts are the reproducibility source. An inherited opt-out must
    # not make the required families depend on an ambient host installation.
    env.pop("TYPST_IGNORE_EMBEDDED_FONTS", None)
    return env
