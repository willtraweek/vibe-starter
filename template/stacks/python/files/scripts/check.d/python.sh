#!/usr/bin/env bash
# Python stack guards (from ./bootstrap --stack python): lockfile, lint, format,
# types, and the coverage-tier config (cheap; runs before any tests).
set -euo pipefail
if ! command -v uv >/dev/null 2>&1; then
  echo "  uv is not installed - this project needs it: https://docs.astral.sh/uv/" >&2
  exit 1
fi
uv lock --check --quiet || { echo "  uv.lock is missing or out of date: run 'uv lock' and commit it." >&2; exit 1; }
uv run --locked --quiet ruff check .
uv run --locked --quiet ruff format --check .
uv run --locked --quiet ty check
uv run --locked --quiet python scripts/coverage_tiers.py --validate
