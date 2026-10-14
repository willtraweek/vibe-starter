# Foldkit in this project

This project is a browser app built with [Foldkit](https://foldkit.dev): the Elm architecture
(Model, Messages, `update`, `view`, Commands) on Effect v4. `FOLDKIT.md` holds Foldkit's own
conventions; Foldkit owns that file, so never edit it. This guide covers what the vibe-starter
pack adds on top: the layout, the gates and the upgrade train.

## Layout and test tiers

| File | What it holds | TESTING.md tier | Tested by |
|---|---|---|---|
| `src/domain/version.ts` | pure `parseVersion` / `displayVersion`; no Foldkit | 1, pure logic (100%) | `src/domain/version.test.ts` (truth table + property) |
| `src/main.ts` | Model, `init`, `update` | 1, pure logic (100%) | `src/story.test.ts` (Story tests) |
| `src/api/status.ts` | the network boundary: `GET /status.json`, Schema-decoded, typed errors; no Foldkit | 2, API surface (100%) | `src/api/status.test.ts` |
| `src/command.ts` | `FetchStatus`, mapping every outcome to a Message | 2, API surface (100%) | `src/command.test.ts` |
| `src/view.ts`, `src/components/status.ts` | the root view and the status component | 3, main UI (90%) | `src/scene.test.ts` (Scene tests) |
| `e2e/home.spec.ts` | the named journeys, against the production build | 4, E2E journeys | Playwright |
| `src/message.ts` | the Message union (its own file breaks the `command.ts` / `main.ts` cycle) | global floor | |
| `src/entry.ts` | the boot file: `Runtime.makeApplication` + `Runtime.run` | not measured | E2E |

`coverage-tiers.json` lists every tier member explicitly, plus the E2E journey titles. Files
outside a tier still count toward the global floor. Tests never mock modules (`vi.mock`,
`vi.doMock`, `vi.importMock`; the checks refuse them): tier 2 swaps the `HttpClient` Layer, the
only trust boundary.

## Commands

You need pnpm 12 and Node.js 22 or newer on `PATH`. pnpm runs the project's own commands on the
Node that `devEngines` pins, but the checks, the coverage gate and vendoring run their checkers
on the Node on `PATH`, and stop with a message when it is missing or older than 22.

| Purpose | Command |
|---|---|
| Install (also patches tsc, via the `prepare` script) | `pnpm install` |
| Dev server on http://localhost:3000 | `pnpm dev` |
| Production build / preview on 4000 | `pnpm build` / `pnpm preview` |
| Guards: pins and policy, source rules, lockfile, types, lint, format, tier config | `./scripts/check.sh` |
| Tests, fast and gate-free (one file: add its path) | `pnpm exec vitest run` |
| Coverage gates: 90% lines and branches, then per tier | `./scripts/coverage.sh` |
| E2E journeys (once per machine: `pnpm exec playwright install chromium`) | `pnpm exec playwright test` |
| Coverage snapshot table | `node scripts/coverage-tiers.mjs --report` |
| Refresh the vendored Foldkit source | `bash scripts/vendor-foldkit.sh` |

The full gate is `./scripts/check.sh && ./scripts/coverage.sh && pnpm exec playwright test`.
Dependencies install only once they are 24 hours old (`minimumReleaseAge` in
`pnpm-workspace.yaml`), and dependency build scripts are denied. The steps that need the network
give up instead of waiting offline: bootstrap's install and vendoring after 10 minutes, the
checks' lockfile verification after 5. Rerun them once you are online.

## What `./scripts/check.sh` enforces

Before tsc, Oxlint and Oxfmt run, two Node scripts check what those can't see:

- `scripts/check-pins.mjs`: `package.json` in the form gstack `/ship` writes and at `VERSION`;
  every dependency exact and installed at its pin; the Foldkit + Effect train in step;
  `.foldkit-ref` on the pinned Foldkit release; `pnpm-workspace.yaml` holding the supply-chain
  policy (below). A new policy setting, or a looser value, is a reviewed change to this script.
- `scripts/check-rules.mjs`, each violation reported as `file:line`:
  - `src/domain` and `src/api` import no `foldkit`, `foldkit/...` or `@foldkit/...` module in any
    form (type-only, `export ... from`, `import()`, `require()`), and name every module they
    load with a plain string;
  - `src` and `e2e` call no `mock`, `doMock` or `importMock` on Vitest's `vi`, under any name: `vi`
    is only ever used as `vi.method(...)`;
  - only the root `vite.config.ts` configures Vite. It imports `{ foldkit }` from
    `@foldkit/vite-plugin` once and calls `foldkit({ devToolsMcpPort: false })` or `foldkit()`
    once; no other file names the plugin, and no script passes `--config` to `vite`;
  - an agent's Foldkit MCP server, in `.mcp.json`, `.cursor/mcp.json` or `.vscode/mcp.json`, runs
    the pinned local bin;
  - `src` holds `.ts` modules only: coverage measures `src/**/*.ts`.

`check-rules.mjs` reads code through a small tokenizer, not a full parser, and refuses what it
cannot follow (an alias of `vi` or `foldkit`, a computed module name, a `/` after `}` it cannot
place) rather than guess. When it refuses a change that is safe, extend the rule in
`scripts/check-rules.mjs`, in a reviewed change that says why, instead of working around it.

## The upgrade train

Foldkit pins one exact Effect version, and every `@foldkit/*` package pins the same one. So
these move together, all exactly pinned, in one change:

1. `foldkit`, every `@foldkit/*` package, `effect` and every `@effect/*` package except
   `@effect/tsgo` (the patcher has its own versions and a support matrix: check its README for
   the TypeScript version it supports). Keep `devToolsMcpPort: false` in `vite.config.ts`
   unless you mean to turn the relay on (below).
2. `.foldkit-ref`: one line, `<version> <commit>`, for the new Foldkit release.
   `git ls-remote https://github.com/foldkit/foldkit.git refs/tags/foldkit@<version>` prints
   the commit its tag names; review that release before you record it.
3. `pnpm install`, then `node scripts/check-pins.mjs`: it fails until the installed Foldkit's
   peers name exactly the pinned Effect, whenever `node_modules` holds a version other than a
   pin, and while `.foldkit-ref` names another release.
4. `bash scripts/vendor-foldkit.sh`, then replace `FOLDKIT.md` whole with
   `repos/foldkit/packages/create-foldkit-app/templates/base/FOLDKIT.md`.
5. The full gate. Foldkit's minor releases often break its API; its changelog is in
   `repos/foldkit/packages/foldkit/CHANGELOG.md`.

A release under 24 hours old fails every install, frozen ones included (and
`./scripts/check.sh`), until it is a day old. Wait, or add exact `name@version` entries for the
new train releases to `minimumReleaseAgeExclude` in `pnpm-workspace.yaml`, in the same change,
and remove them once they are a day old:

```yaml
minimumReleaseAgeExclude:
  - foldkit@0.166.0
  - '@foldkit/devtools@0.166.0'
```

`check-pins.mjs` accepts an entry only for a train release `package.json` pins. Never set
`pnpm_config_minimum_release_age=0`, and never exempt a bare name or a scope: either lets far
more than the new releases skip the rule. The checks and bootstrap clear pnpm's supply-chain
settings from the environment (`pnpm_config_*` and `PNPM_CONFIG_*`), so `pnpm-workspace.yaml`
is the policy that applies.

## Where this project deviates from FOLDKIT.md

- **The DevTools MCP is off.** FOLDKIT.md says `@foldkit/devtools-mcp` is pre-wired. Here it is
  installed but not connected, and `src/entry.ts` passes no `devTools: { Message }`, so no
  client can dispatch Messages. The relay comes from `@foldkit/vite-plugin` (0.25.0 and later):
  - By default the plugin serves the relay from the dev server, behind a random token, on
    Vite's `server.host` (localhost unless you change it). This project turns it off with
    `foldkit({ devToolsMcpPort: false })` in `vite.config.ts`; call `foldkit()` to turn it on.
  - A numeric `devToolsMcpPort` still opens the old relay: every network interface, no token
    and no Origin check. That is why the checks accept only those two calls.

  To let the agent dispatch Messages as well, pass `devTools: { Message }` in `src/entry.ts`.
  Point your agent at the pinned local bin, never `npx`, `pnpm dlx`, `pnpx`, `bunx` or
  `yarn dlx` (the checks refuse them in `.mcp.json`, `.cursor/mcp.json` and `.vscode/mcp.json`),
  with a `.mcp.json` like this:

  ```json
  {
    "mcpServers": {
      "foldkit-devtools": { "command": "node_modules/.bin/foldkit-devtools-mcp" }
    }
  }
  ```
- **Vendoring is a script, not `git subtree`.** `scripts/vendor-foldkit.sh` clones Foldkit's
  repository at the pinned release tag into `repos/foldkit`, which is gitignored, and refuses it
  unless the tag still names the commit `.foldkit-ref` records (a tag can move). The clone keeps
  its own `.git`, so `repos/foldkit` is a separate repository: a hook installer run there
  (Foldkit's `prepare` script runs simple-git-hooks) writes into it, never into this project's
  `.git`. It leaves out Foldkit's own copy of Effect and its maintainer agent files
  (`AGENTS.md`, `CLAUDE.md`, `.mcp.json`, `.claude/`, `.agents/`), which would otherwise load as
  instructions for this project. `AGENTS.md` here is the project's own; it has no
  `subtree_prompted` line, and nobody needs to offer the subtree.
- **Lint is stricter than the scaffold's.** `.oxlintrc.json` keeps Oxlint's correctness and
  suspicious categories on, type-aware (oxlint-tsgolint), with Foldkit's plugin on top.

## Trust-boundary rules the patched tsc enforces

`pnpm install` runs `effect-tsgo patch`, and `./scripts/check.sh` fails unless
`pnpm exec tsc --version` says `+effect-tsgo`. The patched `tsc --noEmit` then reports, as errors:

- everywhere: `outdatedApi` (Effect v3 APIs), `floatingEffect`, `floatingEffectInVitest`,
  `obsoleteSchemaImport`;
- in `src/**` except tests, where effects belong in Commands and Layers: `globalDate`,
  `globalRandom`, `globalFetch`, `globalTimers` and `processEnv`, each with its `*InEffect`
  variant. Use `Clock`, `DateTime`, `Random`, `HttpClient`, `Effect.sleep` and `Config` instead.

Oxlint is not patched on purpose (`effect-tsgo patch --oxlint` would tie Oxlint's version to
the patcher's support matrix): tsc owns the Effect rules.
