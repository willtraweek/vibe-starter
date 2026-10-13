#!/usr/bin/env bash
# Foldkit stack guards (from ./bootstrap --stack foldkit), cheapest first; each
# fails closed. Runs from the repo root, before any test.
set -euo pipefail
die() { echo "  $*" >&2; exit 1; }
if ! command -v pnpm >/dev/null 2>&1; then
  die "pnpm is not installed - this project needs it: https://pnpm.io/installation (or Corepack)"
fi
node scripts/check-pins.mjs
# The lockfile must match package.json. --lockfile-only writes neither the lockfile
# (frozen) nor node_modules; it needs the registry only when pnpm's supply-chain
# verification of the lockfile isn't cached yet. (--offline can't work here: pnpm
# 12 won't resolve the devEngines Node runtime offline; --dry-run exits 0 on a
# stale lockfile.) pnpm also fails it when the supply-chain policy rejects a locked
# package, a release under 24 hours old for one: that is not a stale lockfile, and
# pnpm's own help (rebuild the lockfile, or relax the policy) is the wrong advice.
if ! lock_out="$(pnpm install --frozen-lockfile --lockfile-only 2>&1)"; then
  case "$lock_out" in
    *"failed supply-chain policy check"*|*ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION*)
      printf '%s\n' "$lock_out" | sed '/^[[:space:]]*help:/,$d' >&2
      die "pnpm's supply-chain policy (pnpm-workspace.yaml) rejects a locked package (above). A release under 24 hours old passes once it is a day old; see docs/guides/foldkit.md." ;;
  esac
  printf '%s\n' "$lock_out" | tail -n 8 >&2
  die "pnpm-lock.yaml is missing or out of date with package.json: run pnpm install and commit pnpm-lock.yaml."
fi
case "$(pnpm exec tsc --version 2>/dev/null || true)" in
  *+effect-tsgo*) ;;
  *) die "tsc is not patched by @effect/tsgo, so the Effect rules would not run: run pnpm install (its prepare script runs effect-tsgo patch)." ;;
esac
pnpm exec tsc --noEmit
# --disable-nested-config: oxlint would otherwise load repos/foldkit/.oxlintrc.json
# (the vendored copy) despite ignorePatterns, whenever .gitignore doesn't hide it.
pnpm exec oxlint --type-aware --deny-warnings --disable-nested-config
echo "  oxlint: clean"
pnpm exec oxfmt --check src e2e vite.config.ts vitest.config.ts playwright.config.ts
# Boundaries the type checker can't see.
if grep -rnE "from ['\"](foldkit|@foldkit/[^'\"]+)['\"]" src/domain src/api; then
  die "src/domain and src/api must not import foldkit (they stay framework-free; see docs/guides/foldkit.md)."
fi
if grep -rn 'vi\.mock(' src e2e; then
  die "no vi.mock: swap a Layer at the network edge instead (TESTING.md: mocks only at trust boundaries)."
fi
# The DevTools relay: off, or the token-protected one (docs/guides/foldkit.md).
# Comment lines don't count: vite.config.ts names the option in one.
if grep -n 'devToolsMcpPort' vite.config.ts | grep -v 'devToolsMcpPort: false' \
  | grep -vE '^[0-9]+:[[:space:]]*//'; then
  die "a numeric devToolsMcpPort opens an unauthenticated DevTools relay on every network interface; see docs/guides/foldkit.md."
fi
if [ -f .mcp.json ] && grep -n 'npx' .mcp.json; then
  die ".mcp.json must call the pinned local bin (node_modules/.bin/foldkit-devtools-mcp), not npx."
fi
node scripts/coverage-tiers.mjs --validate
if [ "${CHECK_CI:-0}" != 1 ]; then
  pin="$(node -p 'require("./package.json").dependencies.foldkit')"
  if [ "$(cat repos/foldkit/.vendored-version 2>/dev/null || true)" != "$pin" ]; then
    echo "  WARNING: repos/foldkit is missing or not foldkit@$pin: run bash scripts/vendor-foldkit.sh (agents read it; see FOLDKIT.md)."
  fi
fi
