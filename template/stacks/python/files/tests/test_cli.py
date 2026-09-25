"""CLI contract tests (TESTING.md tier 2: exit code and output of every command)."""

from pathlib import Path

import pytest

from {{PACKAGE_NAME}} import __version__
from {{PACKAGE_NAME}}.cli import main

ROOT = Path(__file__).resolve().parents[1]


def test_version_comes_from_the_version_file() -> None:
    # gstack /ship bumps VERSION; hatchling feeds it to the package metadata.
    assert __version__ == (ROOT / "VERSION").read_text(encoding="utf-8").strip()


def test_version_flag_prints_version_and_exits_zero(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exc:
        main(["--version"])
    assert exc.value.code == 0
    out = capsys.readouterr().out.strip()
    assert out == "{{PACKAGE_NAME}} " + __version__


def test_no_arguments_exits_zero() -> None:
    assert main([]) == 0
