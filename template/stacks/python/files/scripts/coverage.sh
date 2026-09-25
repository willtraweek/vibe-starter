#!/usr/bin/env bash
# Coverage gate (TESTING.md): the 90% line+branch floor, then the per-tier gates.
# CI runs this. Plain `uv run pytest` skips coverage on purpose (fast, gate-free).
set -euo pipefail
CDPATH='' cd -- "$(dirname -- "$0")/.."   # a CDPATH entry must not pick the directory
uv run --locked pytest --cov
uv run --locked coverage json -q -o coverage.json
uv run --locked python scripts/coverage_tiers.py --check
