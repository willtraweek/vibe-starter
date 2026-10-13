#!/usr/bin/env bash
# Coverage gate (TESTING.md): the 90% line and branch floors, then the per-tier
# gates, enforced by scripts/coverage-tiers.mjs. CI runs this. Plain
# `pnpm exec vitest run` skips coverage on purpose (fast, gate-free).
set -euo pipefail
CDPATH='' cd -- "$(dirname -- "$0")/.."   # a CDPATH entry must not pick the directory
# coverage-tiers.mjs runs on the Node on PATH (pnpm's pinned Node runs only
# pnpm's own commands), and needs 22 or newer: say so before the tests run.
case "$(node --version 2>/dev/null)" in
  v2[2-9].*|v[3-9][0-9].*|v[1-9][0-9][0-9]*) ;;
  *) echo "coverage: Node.js 22 or newer must be on PATH (found: $(node --version 2>/dev/null || echo none)): install it from https://nodejs.org or with your version manager." >&2
     exit 1 ;;
esac
rm -rf coverage
pnpm exec vitest run --coverage
node scripts/coverage-tiers.mjs --check
