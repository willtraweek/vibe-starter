#!/usr/bin/env bash
# Coverage gate (TESTING.md): the 90% line and branch floors, then the per-tier
# gates, enforced by scripts/coverage-tiers.mjs. CI runs this. Plain
# `pnpm exec vitest run` skips coverage on purpose (fast, gate-free).
set -euo pipefail
CDPATH='' cd -- "$(dirname -- "$0")/.."   # a CDPATH entry must not pick the directory
rm -rf coverage
pnpm exec vitest run --coverage
node scripts/coverage-tiers.mjs --check
