"""Command-line entry point: the project's machine contract (DOCTRINE.md §3)."""

import argparse
from collections.abc import Sequence

from {{PACKAGE_NAME}} import __version__


def build_parser() -> argparse.ArgumentParser:
    # One argument per line (the trailing comma keeps it so): long project names
    # still fit the 100-column limit that ruff enforces.
    parser = argparse.ArgumentParser(
        prog="{{PACKAGE_NAME}}",
        description="{{PROJECT_NAME}}",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    build_parser().parse_args(argv)
    return 0
