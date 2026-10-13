# Plan 011: Add the `foldkit` stack pack: a browser app on Foldkit (Effect v4), TypeScript 7, Vite 8, Vitest 5 and Playwright

> **Executed, 2026-10-13.** PR #22 landed this pack together with plans 007–010, and its
> pre-landing review resolved every finding of issue #20 there. `template/stacks/foldkit/` is
> the source of truth now. The steps, helper scripts, embedded files and checksum manifests
> below are the record of the 2026-10-02 rehearsal: they are not kept in sync with the pack and
> are not meant to be replayed (`step-2.sh` would write the rehearsed files over the current
> pack). For upkeep, use "Maintenance notes" at the end, which describe the pack as it is.

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **How to read this plan.** It is long because it carries every file of the pack. The blocks
> introduced by a line like `` `files/src/main.ts`: `` are data: scripts copy them out of this
> plan byte for byte, so you never retype them and need not read them. Read the prose, run the
> commands, compare the results.
>
> **Preflight (run first, in this order, from the repo root).** Run every command in this plan
> with `CI` unset (`unset CI`); a set `CI=true` would run the heavy tests early.
>
> 1. **Extract the helper scripts.** This plan's multi-line commands are small scripts, embedded
>    under "Helper scripts" and in step 1. This one command writes them to `.context/plan-011/`
>    (gitignored scratch):
>
>    ```sh
>    mkdir -p .context/plan-011 && sed -n -e '/^## Helper scripts/,/^## Scope/p' -e '/^### Step 1:/,/^### Step 2:/p' plans/011-stack-pack-foldkit.md | perl -ne 'if (!$in && /^`([^`\/]+)`:$/) { $p = ".context/plan-011/$1"; next } if (!$in && defined $p && /^````\w*$/) { open(F, ">", $p) or die; $in = 1; next } if ($in && /^````$/) { close F; $in = 0; undef $p; next } print F $_ if $in;'
>    ```
>
>    Then check them: `(cd .context/plan-011 && shasum -a 256 -c helpers.sha256)` → every line
>    ends in `OK`. A line that doesn't is a STOP condition.
>
>    Always run a helper from the repo root, exactly as this plan shows it (`bash
>    .context/plan-011/<name>.sh`, `node …`, `perl …`). Never paste a helper's body into your
>    shell: some shells carry on after a failed line, and these scripts rely on stopping.
> 2. **The train.** `node .context/plan-011/train.mjs` must end with `train ok` (exit 0). It
>    asks the npm registry whether the eight packages this plan pins are still published and not
>    deprecated. If it cannot reach the registry, retry once. `train FAILED` is a STOP condition.
>    A `NOTE:` line about a newer Foldkit release is not, yet: copy it into your report and carry
>    on with the plan's train. (Step 3 may then stop at its peer check, because pnpm picks the
>    newest `@foldkit/ui` on its own. That would be a STOP: the plan needs a train move first.)
> 3. **Tools.** `pnpm --version` must print 12.x. If pnpm is missing or on another major, STOP
>    and ask the operator to install pnpm 12 (`plans/README.md` → Operator actions); never
>    install it yourself. `node --version` must be v22 or newer. `git`, `perl`, `curl` and
>    `shasum` must exist.
> 4. **Baseline.** Plans 001–010 must be done, in order. Run
>    `SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh` and record its `selftest: …`
>    line and any named skips in `.context/plan-011/baseline.txt`. A failing test is a STOP
>    condition. A skip for a tool this machine lacks is not: write it down.
> 5. **Contracts.** `bash .context/plan-011/contracts.sh` must end with `contracts ok`. It
>    checks, read-only, every anchor under "Current state" that a later step relies on. A
>    `DIFFERS` line is a STOP condition, unless the plan index (`plans/README.md`) explains it.
>    It is a check for the tree before step 1: once step 1 is applied it only says so.

## Status

- **Priority**: P2 (requested by the maintainer)
- **Effort**: L
- **Risk**: MED–HIGH. New projects get a JavaScript toolchain (Node 24, pnpm 12; the lockfile
  lists about 280 packages, about 190 of which install on one machine) and a beta framework
  whose minor releases often break its API. The template's CI gets Node in the `selftest` job
  and pnpm plus Chromium in the `heavy` job. `bootstrap` and `scripts/check.sh` do not change;
  the no-stack path is untouched.
- **Depends on**: 006 (the stack-pack mechanism), 008 (pack `description` files, `CHECK_CI`,
  `SELFTEST_EXCLUDE`/`SELFTEST_HEAVY` and the `heavy` CI job), 010 (Node 24 in the `heavy`
  job). 007 and 009 only precede it in the linear order.
- **Category**: direction
- **Planned at**: first written at `98063fc` on 2026-09-25, for Foldkit 0.163.0. Rewritten on
  2026-10-02 at `b185770` (plans 007–010 implemented), for Foldkit 0.165.0 on Effect 4.0.0.
  Every file below was rehearsed end to end on that code (see "Rehearsal evidence").

## Why this matters

The maintainer asked for a JavaScript frontend stack pack built on Effect (effect.website), and
on 2026-09-25 chose, from three prototyped options, **Foldkit** as the first: the Elm
architecture (one Schema-typed Model, fact-named Messages, a pure `update`, side effects as
Commands) on Effect v4. Prototypes of the same starter on the pinned toolchain decided it:

- **Its tests fit this template's doctrine best.** Story tests drive the pure `update` and
  resolve Commands inline; Scene tests click the real view through accessible locators, with no
  browser and no mocks. The only test double is an `HttpClient` Layer at the network edge.
- **Trust boundaries become compile errors.** The Effect language service, patched into `tsc`
  by `@effect/tsgo`, rejects `Date.now()`, `Math.random()`, bare `fetch`, timers and
  `process.env` in app code, plus the Effect v3 APIs coding agents tend to write.
- **It is small**: 103 kB gzip for the starter, about 40 kB less than the React prototype with
  an Effect data layer.

The costs are real, and this plan's guardrails exist for them. Foldkit is beta (18 of the 20
minor releases before 0.163 forced app changes), one maintainer writes nearly all of it, and it
pins one exact Effect version. Its Vite plugin can also open a DevTools relay: the current one
sits behind a token, but a numeric port still opens the old one, which listens on every network
interface without authentication. A second JavaScript pack, React 19.3 + TanStack Router on an
Effect v4 data layer, goes to the template's backlog (`TODOS.md`), chosen by what the app does.

On 2026-10-02 the maintainer decided to build on Foldkit 0.165.0, the first release on stable
Effect 4.0.0, without waiting for it to be 24 hours old. Step 3 and "Maintenance notes" say
what that means for pnpm's release-age rule.

After this plan:

- `./bootstrap --stack foldkit` creates a browser app that:
  - shows its name, its version (from `VERSION`) and a status fetched from `/status.json` and
    decoded at the API boundary, with a Retry button;
  - installs a reviewed, locked dependency tree with pnpm 12 on a pinned Node 24, with a 24-hour
    release-age gate and dependency build scripts denied;
  - type-checks with TypeScript 7 plus the Effect rules, lints type-aware with Oxlint, and
    formats with Oxfmt;
  - holds pure logic and the API surface at 100% lines, branches and functions, the main UI at
    90%, and the whole app at 90% lines and 90% branches, fail-closed, with a named Playwright
    journey and a coverage ratchet on pull requests;
  - has live CI that is green on its first push, and keeps `package.json`'s version equal to
    `VERSION` for gstack;
  - gives agents Foldkit's own conventions (`FOLDKIT.md`) and Foldkit's source at the pinned
    release (`repos/foldkit`, gitignored), without Foldkit's maintainer-only agent files.
- `./bootstrap --help` lists the pack with one line on what it builds, and `TEMPLATE.md` says
  when to choose it.

## Design decisions (each verified while planning)

- **Name and description.** The pack is `foldkit`; its `description` is
  `Browser app, Elm-style: Foldkit on Effect v4, TypeScript 7, Vite 8, Vitest 5, Playwright`.
- **The train moves together, pinned exactly.** `foldkit` peers on one exact `effect` and
  `@effect/platform-browser` version; every `@foldkit/*` package peers on that same `effect`;
  `@foldkit/devtools` releases in lockstep with `foldkit`. So `foldkit`, every `@foldkit/*`,
  `effect` and every `@effect/*` package except `@effect/tsgo` move together in one change, all
  pinned exactly. This plan's train is foldkit 0.165.0, `@foldkit/devtools` 0.165.0,
  `@foldkit/vite-plugin` 0.26.0, `@foldkit/devtools-mcp` 0.24.0, `@foldkit/oxlint-plugin`
  0.15.1, and `effect`, `@effect/platform-browser` and `@effect/vitest` 4.0.0.
  `scripts/check-pins.mjs` fails the checks when the train drifts. It reads what `node_modules`
  actually holds: every direct dependency must be installed at exactly its pin, and the
  installed Foldkit packages' peers must name the pinned Effect.
- **The pack ships its lockfile.** `pnpm-lock.yaml` holds no project name or version (verified),
  so one file serves every project. CI's frozen install passes on the first push, and a gstack
  version bump leaves the lockfile byte-identical (verified). It is generated in a scratch copy
  with the tokens filled (step 3).
- **The toolchain, pinned where CI and laptops read it.**
  - Node 24.21.0: `devEngines.runtime` with `onFail: download`, plus `.node-version`.
  - pnpm 12.6.0: `packageManager` plus `devEngines.packageManager` with `onFail: download`. Any
    other local pnpm 12 switches itself to 12.6.0, while `onFail: error` would stop it, and npm
    refuses the project outright.
  - vite 8.3.1, vitest 5.0.1 with @vitest/coverage-v8 5.0.1, typescript 7.0.2 with @effect/tsgo
    0.45.0, oxlint 1.85.0 with oxlint-tsgolint 7.0.2003, oxfmt 0.70.0, @playwright/test 1.63.0
    and happy-dom 20.14.5.

  These were the newest versions at least 24 hours old on 2026-09-26, and the whole gate passed
  on them again, unchanged, with Effect 4.0.0 on 2026-10-02. Do not upgrade any of them in this
  plan. (`@effect/tsgo` 0.47 was tried and rejected: 0.47.0 cannot run the `prepare` script,
  and 0.47.2 turns Effect 4.0.0's HTTP modules into 21 failing "unstable API" warnings.)
- **TypeScript 7 carries the Effect rules through a patch.** TS 7 has no plugin API, so the
  root `prepare` script runs `effect-tsgo patch`, which rewrites the installed native `tsc`. An
  unpatched `tsc` exits 0 on the code the rules exist to catch, so the check fails unless
  `pnpm exec tsc --version` contains `+effect-tsgo`. Oxlint is deliberately *not* patched
  (`effect-tsgo patch --oxlint` would bind Oxlint's version to the patcher's support matrix):
  `tsc` owns the Effect rules, Oxlint the generic type-aware ones plus Foldkit's plugin.
- **Supply-chain policy.** `minimumReleaseAge: 1440`, `trustPolicy: no-downgrade`,
  `strictDepBuilds: true`, `blockExoticSubdeps: true` and `allowBuilds: {}` (no dependency
  needs a build script; verified). This follows 2026's npm incidents, including a worm that
  writes into `.claude/settings.json`. pnpm applies the age rule to every install, frozen ones
  included, so a lockfile that holds a release under 24 hours old fails until that release has
  matured. The pack's policy file ships unchanged all the same:
  - step 3 resolves the lockfile with only the train (`foldkit`, `@foldkit/*`, `effect`,
    `@effect/*`) exempt, and only in its scratch copy, so every other package in the shipped
    lockfile is at least 24 hours old;
  - while part of the train is younger than that, the plan's own heavy runs relax the rule
    through the environment (`pnpm_config_minimum_release_age=0`), which is safe for a frozen
    install of a reviewed lockfile;
  - the template's hosted `heavy` job and a new project's CI stay red until the train is a day
    old (`train.mjs` prints that time). That is the price of not waiting, and it ends by
    itself.
- **Coverage enforcement lives in `scripts/coverage-tiers.mjs`, not in Vitest.** Vitest 5 exits
  0 on a tier glob that matches no file, a Jest-style `global:` key and a misspelled metric key,
  so `vitest.config.ts` sets no thresholds. The checker (Node standard library only, a port of
  the python pack's `coverage_tiers.py`) reads `coverage/coverage-summary.json` and:
  - enforces 90% lines and 90% branches globally, independently, naming the files below the
    floor;
  - enforces each tier's minimum on lines, branches *and functions*: Foldkit's branching lives
    in `match` handlers, so branches read 0/0 in `update` and `view`, and only the function
    count proves every Message is handled;
  - fails when a tier member is missing from the report or has nothing to measure;
  - validates the config before any test (`--validate`, in the checks), including that every
    named E2E journey exists as a Playwright `test('…')` title;
  - ratchets on pull requests (`--ratchet REF`), with `retired` for reviewed moves.
- **Coverage stays out of the plain test command.** `TEST_CMD` is `pnpm exec vitest run`: one
  command, no floor. gstack's `/ship` and `/qa` run `<test command> <file>` on single generated
  tests and delete ones that "fail", so a floor there would delete good tests.
  `./scripts/coverage.sh` runs the floors (CI and `SHIP_GATE`).
- **Layout by tier**, in the shape FOLDKIT.md endorses (its kanban example):
  - `src/message.ts` holds the Messages, which breaks the `command.ts` ↔ `main.ts` cycle;
  - `src/main.ts` (Model, `init`, `update`) and `src/domain/version.ts` are tier 1;
  - `src/command.ts` (Commands) and `src/api/status.ts` (the network boundary) are tier 2;
  - `src/view.ts` and `src/components/status.ts` are tier 3, and `e2e/home.spec.ts` is tier 4;
  - `src/entry.ts` is the boot file, not measured.

  gstack's diff scoping counts `*/components/*` and `*.css` as frontend but plain `.ts` as
  backend, hence `src/components/` and `src/styles.css`. The starter has no routing, so every
  Command is testable at 100%.
- **`VERSION` is the version.** `src/build-info.ts` imports `../VERSION?raw`. `package.json`'s
  `version` mirrors it, because gstack `/ship` (1.91.1.0, `bin/gstack-version-bump`) rewrites
  `package.json` on every bump as `JSON.stringify(pkg, null, 2) + "\n"` and stops when the two
  disagree. `check-pins.mjs` enforces the byte form and the equality; Oxfmt ignores
  `package.json`.
- **gstack fit.** The dev server uses port 3000 and preview 4000, both with `strictPort`:
  gstack's `/qa` probes only 3000, 4000 and 8080, and a probe can't tell two apps apart (seen
  while prototyping). `/land-and-deploy`'s `bun test` fallback never applies, because the
  commands are documented. `/health` still calls a bare `tsc`, `eslint` and `biome` (not fixed
  here; see Maintenance notes).
- **The maintainer's five guardrails** (2026-09-25):
  1. *Exact pins; Foldkit and Effect upgrade together, only through the template self-test*:
     `check-pins.mjs`, the shipped lockfile and the heavy tests.
  2. *Vendor Foldkit at the pinned tag; point agent docs at FOLDKIT.md and the vendored copy*:
     `scripts/vendor-foldkit.sh` fetches Foldkit's repository at `foldkit@<pin>` into gitignored
     `repos/foldkit`. A committed `git subtree` of it (FOLDKIT.md's suggestion) would add about
     54 MB to every project, 40 MB of it Foldkit's own copy of Effect. The script leaves that
     copy out, and also Foldkit's maintainer-only agent files (root `AGENTS.md`, `CLAUDE.md`,
     `.claude/settings.json`, `.claude/skills/`, `.agents/`, and create-foldkit-app's template
     `AGENTS.md` and `.mcp.json`), which would otherwise load as instructions for this project's
     agents. `FOLDKIT.md` ships verbatim from the release tag, and CLAUDE.md's `RELEVANT_DOCS`
     names both plus `docs/guides/foldkit.md`.
  3. *Keep Foldkit out of `src/domain` and `src/api`*: a grep guard in the checks.
  4. *DevTools relay off; the MCP server pinned and run from the local bin*: see the next
     bullet.
  5. *The spine's lint config, not the scaffold's* (the scaffold turns Oxlint's correctness rules
     off and isn't type-aware); *Commands in their own file*; *function coverage gates*.
- **The DevTools relay stays off.** `@foldkit/vite-plugin` 0.25.0 and later serve a relay from
  the dev server *by default*, behind a random token, on Vite's `server.host`.
  `devToolsMcpPort: false` turns it off; a numeric port still opens the old relay, which listens
  on every interface with no token and no Origin check. So:
  - `vite.config.ts` calls `foldkit({ devToolsMcpPort: false })`;
  - the checks refuse a numeric `devToolsMcpPort` and any `npx` in `.mcp.json`;
  - `src/entry.ts` passes no `devTools: { Message }`, so nothing can dispatch Messages;
  - `docs/guides/foldkit.md` documents the safe opt-in.
- **Name limits.** `validate-name` rejects `node_modules` and the pack's unscoped, hyphen-free
  direct dependency names, and names over 50 characters. A project named `effect` fails `tsc`
  (duplicate package). `src/build-info.ts`'s `export const PROJECT_NAME = '…'` must fit Oxfmt's
  80 columns: 50 characters pass, 51 fail (verified).
- **CI for new projects** runs on `ubuntu-24.04`, so `playwright install --with-deps` can apt
  Chromium's libraries. It uses `pnpm/setup` pinned by commit (v3.0.0,
  `fbda4c85fc2e1e08721cd8763afea8f48d60f024`) with `require-lockfile: true`, which installs Node
  from `devEngines`, then pnpm, then runs a frozen install (and so `prepare`). There are no
  dependency caches. The workflow contains no `${{ }}` expressions, because pack files may carry
  only the three bootstrap tokens.
- **Template CI.** The `selftest` job gets `actions/setup-node@v7` (Node 24) for the light
  tests that run the Node checkers. The `heavy` job gets `pnpm/setup` (exact pnpm,
  `install: false`) for the four heavy tests; plan 010 already gave that job Node 24. A light
  test keeps the heavy job's pnpm version and `pnpm/setup` commit equal to the pack's.
- **The plan's commands are scripts.** Rehearsal showed that a pasted multi-line block does not
  stop at a failed line in every shell (zsh ignores `set -e` inside an `&&` list, which is how
  some agent harnesses run commands): a failed install was followed by "success". So every
  multi-line command here is a helper script run through `bash`, `node` or `perl`, and the
  files they write are checked against SHA-256 manifests.
- **Out of scope, on purpose:** routing in the starter, SSR/SSG, `@foldkit/ui`, Tailwind, a
  design system beyond CSS custom properties, deployment, turning the DevTools MCP on, the React
  pack (backlog), a shared JavaScript partial pack (rule of three: extract when a third
  JavaScript pack exists), editor setup for `@effect/tsgo`, gstack's `/health` stack, and moving
  to a newer train or toolchain than the one this plan pins.

## Current state

Plans 001–010 are implemented. `contracts.sh` (preflight step 5) checks each anchor below that a
later step relies on; this list says what they are.

- `bootstrap` (006, 008, 009):
  - a pack is `template/stacks/<name>/` with `files/`, `commands` and `gitignore`, plus optional
    `validate-name` (run before any write, from the template root, as
    `sh validate-name PACKAGE_NAME PROJECT_NAME`), `after-bootstrap` (run from the project root
    after the placeholders are filled and before `git init`; a failure only prints a note),
    `description` (008) and `includes` (009; the foldkit pack has none);
  - it replaces `{{PROJECT_NAME}}`, `{{PACKAGE_NAME}}` (the name in snake_case) and `{{YEAR}}`
    in every copied file, fills `{{KEY}}` and `{{KEY: …}}` from `commands`, swaps
    `.gitignore`'s commented language block for the pack's `gitignore`, and removes
    `ci.yml.example` when the pack ships `.github/workflows/ci.yml`;
  - `./bootstrap --help` lists every pack whose name does not start with `_`, with its
    `description`.
- `scripts/check.sh` exports `CHECK_CI` (1 in CI, else 0) and runs every
  `scripts/check.d/*.sh` with bash (008).
- `scripts/template-selftest.sh`:
  - captures tool homes near the top; the last of them is
    `REAL_RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"`;
  - still has this `stack_env` (006; no later plan changed it). It is indented here only because
    it sits in a list; in the file it starts at column 0:

    ```bash
    stack_env() {  # run "$@" with the real uv/cargo homes, so a sandboxed HOME doesn't
      # force fresh downloads of Python, crates, or toolchains on every test run.
      env UV_CACHE_DIR="$REAL_UV_CACHE_DIR" UV_PYTHON_INSTALL_DIR="$REAL_UV_PYTHON_DIR" \
        CARGO_HOME="$REAL_CARGO_HOME" RUSTUP_HOME="$REAL_RUSTUP_HOME" "$@"
    }
    ```

  - has the helpers `fresh_copy`, `run_bootstrap`, `tree_fingerprint`, `assert_*`, `fail` and
    `skip`, and `SELFTEST_EXCLUDE`/`SELFTEST_HEAVY` (008): tests named `test_heavy_*` skip
    locally unless `SELFTEST_HEAVY=1`, and the `selftest` CI job excludes them;
  - has `test_stack_pack_files_carry_only_bootstrap_owned_tokens` (006: no `{{` or `}}` in pack
    files except the three bootstrap tokens) and 008's test that every pack has a one-line
    `description`;
  - ends with the `# --- runner ---` section, directly below plan 010's test block.
- `.github/workflows/template-selftest.yml`:
  - the `selftest` job (on `ubuntu-slim`) has a step named `Lint shell scripts` and a
    `Template self-test` step with `SELFTEST_EXCLUDE: test_heavy_`;
  - the `heavy` job (008, `ubuntu-24.04`) has 010's step
    `- name: Node for the omarchy-plugin tests` (`actions/setup-node@v7`, node-version "24")
    and ends with `- name: Heavy stack-pack self-tests`.
- `TEMPLATE.md`:
  - `## Stack packs` has the interface bullets, then an "Available:" paragraph naming the packs,
    then `### Omarchy apps: choose by what the app should do` (008–010), then `## Note`;
  - `### Verifying a change` has the line "that need gitleaks or uv are skipped locally when it
    is missing; CI installs both and treats" and 008's paragraph that starts "Tests named
    `test_heavy_*` build real projects".
- `TODOS.md` uses gstack's TODOS format (`### Title`, **What/Why/Context/Effort/Priority/Depends
  on**), and `## Completed` is its last `##` section.
- New projects have `.github/actions/install-gitleaks/action.yml` (006), and CLAUDE.md's
  multi-line `{{RELEVANT_DOCS: …}}` placeholder, which this pack's `commands` fills.
- The root `.gitignore` ignores `.gstack/` and `.context/`, but no `node_modules/`, so never run
  a real `pnpm install` inside `template/`; the lockfile is generated in a scratch copy.

Conventions: bash 3.2 compatible (macOS `/bin/bash`), `#!/usr/bin/env bash` for scripts, POSIX
`sh` for `validate-name` and `after-bootstrap`, `# --- Section ---` dividers, errors to stderr.
Tests are `test_*` functions that `return 1` via `fail`, or `skip` with a reason. The pack's
TypeScript follows FOLDKIT.md's code style (no `switch`, braces always, `Array<T>`, uppercase
section headers such as `// MODEL`).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| The train | `node .context/plan-011/train.mjs` | one line per pinned package, then `train ok` |
| Contracts | `bash .context/plan-011/contracts.sh` | `contracts ok` |
| Self-test, all but heavy | `SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh` | baseline + 5 passed, 0 failed; skips only for tools missing locally, named |
| This plan's tests | `./scripts/template-selftest.sh stack_foldkit` | 5 passed, 4 skipped (the heavy ones, with the reason) |
| The heavy tests | `bash .context/plan-011/heavy.sh` | `heavy: ok, 4 passed in …s` (needs node, pnpm 12, git and the network; about 1 minute warm, several cold) |
| Shell lint | the `run:` command of the `Lint shell scripts` step in `.github/workflows/template-selftest.yml` | exit 0 (CI uses shellcheck 0.11.0) |
| YAML | `ruby -ryaml -e 'ARGV.each(&YAML.method(:load_file))' .github/workflows/template-selftest.yml template/stacks/foldkit/files/.github/workflows/ci.yml` | exit 0 |
| Checks | `./scripts/check.sh` | exit 0 |

Missing local tools produce named skips. Never install toolchains or global packages yourself.
Know what the pnpm steps and the heavy tests write outside the repo:

- pnpm's store and cache;
- `PNPM_HOME`, where pnpm puts the pinned Node 24.21.0 and, if your pnpm differs, pnpm 12.6.0;
- Playwright's browser cache, where the heavy tests install Chromium;
- scratch directories under `${TMPDIR:-/tmp}` (`plan-011-lock.*` is removed; `plan-011-look.*`
  is kept for you to look at).

`stack_env` points the tests at pnpm's and Playwright's real locations so nothing downloads
twice, and every self-test run now also runs `pnpm store path` once.

## Helper scripts

Preflight step 1 writes these to `.context/plan-011/`. They are part of the plan, not of the
repo: never commit them.

`train.mjs` asks the npm registry about the pinned train (preflight step 2):

`train.mjs`:

````js
// Plan 011 preflight: does the npm registry still serve the train this plan pins?
// Node standard library only (global fetch: Node 22 or newer). Prints one line per
// pinned package, then `train ok`; or the problems, and exits 1.
const TRAIN = {
  foldkit: '0.165.0',
  effect: '4.0.0',
  '@effect/platform-browser': '4.0.0',
  '@effect/vitest': '4.0.0',
  '@foldkit/vite-plugin': '0.26.0',
  '@foldkit/devtools': '0.165.0',
  '@foldkit/devtools-mcp': '0.24.0',
  '@foldkit/oxlint-plugin': '0.15.1',
}
const DAY = 24 * 3600 * 1000
const problems = []

const doc = async name => {
  const response = await fetch(`https://registry.npmjs.org/${name.replace('/', '%2F')}`)
  if (!response.ok) {
    throw new Error(`${name}: HTTP ${response.status}`)
  }
  return response.json()
}
// [major, minor, patch, rc]; a release sorts after its release candidates.
const parse = version => {
  const match = /^(\d+)\.(\d+)\.(\d+)(?:-rc\.(\d+))?$/.exec(version ?? '')
  return match ? [+match[1], +match[2], +match[3], match[4] === undefined ? Infinity : +match[4]] : undefined
}
const compare = (a, b) => {
  for (let index = 0; index < 4; index += 1) {
    if (a[index] !== b[index]) {
      return a[index] < b[index] ? -1 : 1
    }
  }
  return 0
}

const docs = {}
try {
  for (const name of Object.keys(TRAIN)) {
    docs[name] = await doc(name)
  }
} catch (error) {
  console.error(`train: FAIL cannot read the npm registry: ${error.message}`)
  console.log('train FAILED')
  process.exit(1)
}

let youngest
for (const [name, version] of Object.entries(TRAIN)) {
  const meta = docs[name].versions?.[version]
  if (meta === undefined) {
    problems.push(`${name} ${version} is not on the registry`)
    continue
  }
  if (meta.deprecated) {
    problems.push(`${name} ${version} is deprecated: ${meta.deprecated}`)
  }
  const published = docs[name].time[version]
  const peers = meta.peerDependencies ?? {}
  console.log(`${name} ${version} published ${published} peers ${JSON.stringify(peers)}`)
  if (youngest === undefined || Date.parse(published) > Date.parse(youngest.published)) {
    youngest = { name, version, published }
  }
  // foldkit and every @foldkit/* package pin one exact Effect.
  if (name === 'foldkit' || name.startsWith('@foldkit/')) {
    for (const peer of ['effect', '@effect/platform-browser']) {
      if (peers[peer] !== undefined && peers[peer] !== TRAIN.effect) {
        problems.push(`${name} ${version} needs ${peer} ${peers[peer]}, the plan pins ${TRAIN.effect}`)
      }
    }
  }
}
if (TRAIN['@foldkit/devtools'] !== TRAIN.foldkit) {
  problems.push('@foldkit/devtools must equal foldkit (they release together)')
}

// The newest stable, non-deprecated foldkit release on the pinned Effect or later.
const floor = parse(TRAIN.effect)
const eligible = Object.entries(docs.foldkit.versions)
  .filter(([version, meta]) => {
    const peer = parse(meta.peerDependencies?.effect)
    return /^\d+\.\d+\.\d+$/.test(version) && !meta.deprecated && peer !== undefined && compare(peer, floor) >= 0
  })
  .sort(([a], [b]) => compare(parse(a), parse(b)))
const newest = eligible.pop()
if (newest === undefined) {
  problems.push('no stable foldkit release on the pinned Effect or later')
} else if (newest[0] === TRAIN.foldkit) {
  console.log(`newest foldkit release: ${newest[0]} (the plan's train)`)
} else {
  console.log(
    `NOTE: foldkit ${newest[0]} (effect ${newest[1].peerDependencies.effect}) is newer than the plan's train. ` +
      `Build the plan's train anyway, and say so in your report.`,
  )
}
if (youngest !== undefined) {
  const ripe = Date.parse(youngest.published) + DAY
  console.log(
    `youngest: ${youngest.name} ${youngest.version}, 24 hours old at ${new Date(ripe).toISOString()}` +
      (ripe > Date.now() ? ' (not yet: step 3 handles pnpm\'s age rule)' : ''),
  )
}

for (const problem of problems) {
  console.error(`train: FAIL ${problem}`)
}
console.log(problems.length > 0 ? 'train FAILED' : 'train ok')
process.exitCode = problems.length > 0 ? 1 : 0
````

`contracts.sh` checks the anchors under "Current state" (preflight step 5):

`contracts.sh`:

````bash
#!/usr/bin/env bash
# Plan 011 preflight: check the contracts under "Current state" that later
# steps anchor on. Prints one line per contract; exits 1 if any differs.
# Read-only. Run from the repo root.
# shellcheck disable=SC2016,SC2329
set -uo pipefail
bad=0
check() {  # $1 = what, rest = a command that must succeed
  local what="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok       $what"; else echo "DIFFERS  $what"; bad=1; fi
}
once() { [ "$(grep -cF -- "$1" "$2")" = 1 ]; }      # the fixed string is on exactly one line
line_once() { [ "$(grep -cxF -- "$1" "$2")" = 1 ]; } # exactly one whole line equals it
selftest=scripts/template-selftest.sh
workflow=.github/workflows/template-selftest.yml
if grep -q 'foldkit stack pack (plan 011)' "$selftest" 2>/dev/null; then
  echo "contracts: step 1 is already applied here; this check is only for a tree before step 1"
  exit 0
fi

check "the foldkit pack does not exist yet" test ! -e template/stacks/foldkit
check "bootstrap lists packs with their description (008)" grep -qF 'template/stacks/$name/description' bootstrap
check "bootstrap hides partial packs and reads includes (009)" grep -qF '$pack/includes' bootstrap
check "bootstrap runs validate-name with the package and project names" grep -qF 'sh "$pack/validate-name" "$PACKAGE_NAME" "$NAME"' bootstrap
check "bootstrap runs after-bootstrap" grep -qF 'sh "template/stacks/$STACK/after-bootstrap"' bootstrap
check "a pack's ci.yml replaces ci.yml.example" grep -qF 'rm -f .github/workflows/ci.yml.example' bootstrap
check "check.sh exports CHECK_CI and runs scripts/check.d/*.sh (008)" grep -qF 'export CHECK_CI=1; else export CHECK_CI=0' scripts/check.sh
check "self-test: the REAL_RUSTUP_HOME line" line_once 'REAL_RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"' "$selftest"
check "self-test: stack_env is plan 006's" line_once '    CARGO_HOME="$REAL_CARGO_HOME" RUSTUP_HOME="$REAL_RUSTUP_HOME" "$@"' "$selftest"
check "self-test: the runner divider" line_once '# --- runner -------------------------------------------------------------------' "$selftest"
check "self-test: SELFTEST_EXCLUDE and SELFTEST_HEAVY (008)" grep -q 'SELFTEST_HEAVY=1' "$selftest"
check "self-test: the pack token test (006)" grep -q '^test_stack_pack_files_carry_only_bootstrap_owned_tokens() {' "$selftest"
for helper in fresh_copy run_bootstrap tree_fingerprint fail skip assert_exists assert_absent assert_contains assert_exit; do
  check "self-test: helper $helper" grep -q "^$helper() " "$selftest"
done
check "workflow: the selftest job's 'Lint shell scripts' step" line_once '      - name: Lint shell scripts' "$workflow"
check "workflow: the selftest job excludes the heavy tests" once 'SELFTEST_EXCLUDE: test_heavy_' "$workflow"
check "workflow: the heavy job's last step (008)" line_once '      - name: Heavy stack-pack self-tests' "$workflow"
check "workflow: Node 24 in the heavy job (010)" line_once '      - name: Node for the omarchy-plugin tests' "$workflow"
check "TEMPLATE.md: the 'Available:' paragraph" test "$(grep -c '^Available: ' TEMPLATE.md)" = 1
check "TEMPLATE.md: the Omarchy section" line_once '### Omarchy apps: choose by what the app should do' TEMPLATE.md
check "TEMPLATE.md: the skipped-locally line" line_once 'that need gitleaks or uv are skipped locally when it is missing; CI installs both and treats' TEMPLATE.md
check "TEMPLATE.md: the heavy-tests paragraph (008)" test "$(grep -c '^Tests named `test_heavy_\*` build real projects' TEMPLATE.md)" = 1
check "TEMPLATE.md: the 'Available:' paragraph ends with omarchy-plugin (010)" line_once "JavaScript logic at 100% coverage, Omarchy's own validator pinned)." TEMPLATE.md
check "TEMPLATE.md: the 'Available:' paragraph's line before that" line_once 'gates from `_rust-gates`) and `omarchy-plugin` (an Omarchy 4 shell plugin: a QML bar widget,' TEMPLATE.md
check "TEMPLATE.md: the heavy-tests paragraph ends with plan 010's sentence" line_once 'The omarchy-plugin heavy test also needs Node 22.8+ and a Qt 6 `qmltestrunner` (`QML_TEST_RUNNER`).' TEMPLATE.md
check "TEMPLATE.md: '## Note' follows the Omarchy section" line_once '## Note' TEMPLATE.md
check "TODOS.md: '## Completed' is the last section" test "$(grep '^## ' TODOS.md | tail -n 1)" = '## Completed'
check ".gitignore ignores .context/ and .gstack/" sh -c 'grep -qxF .context/ .gitignore && grep -qxF .gstack/ .gitignore'
check ".gitignore does not ignore node_modules/" sh -c '! grep -qxF node_modules/ .gitignore'
check "new projects get the install-gitleaks action (006)" test -f .github/actions/install-gitleaks/action.yml
check "CLAUDE.md has the RELEVANT_DOCS placeholder" grep -qF '{{RELEVANT_DOCS:' CLAUDE.md
if [ "$bad" = 0 ]; then echo "contracts ok"; else echo "contracts DIFFER: STOP"; fi
exit "$bad"
````

`step-1.pl` adds the tests to the self-test (step 1):

`step-1.pl`:

````perl
#!/usr/bin/env perl
# Plan 011, step 1: add the foldkit tests to scripts/template-selftest.sh.
# Three edits, each anchored on text that must appear exactly once. Nothing is
# written unless all three anchors match. Run from the repo root.
use strict;
use warnings;
use File::Basename qw(dirname);

my $here = dirname(__FILE__);
my $file = 'scripts/template-selftest.sh';

sub slurp {
  my ($path) = @_;
  open(my $in, '<', $path) or die "step-1: cannot read $path: $!\n";
  local $/;
  my $text = <$in>;
  close $in;
  return $text;
}

sub count {  # how many times $needle occurs in $text
  my ($text, $needle) = @_;
  my ($n, $at) = (0, -1);
  $n++ while ($at = index($text, $needle, $at + 1)) >= 0;
  return $n;
}

my $text = slurp($file);
my $homes = slurp("$here/selftest-homes.bash");
my $stack_env = slurp("$here/selftest-stack-env.bash");
my $tests = slurp("$here/selftest-tests.bash");

if ($text =~ /REAL_PNPM_STORE_DIR|foldkit stack pack \(plan 011\)/) {
  die "step-1: already applied (the foldkit additions are in $file)\n";
}

# 1. The last of the tool homes captured near the top.
my $homes_anchor = "\n" . 'REAL_RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"' . "\n";
# 2. The stack_env function, exactly as "Current state" quotes it.
my $old_stack_env = "\n" . <<'OLD';
stack_env() {  # run "$@" with the real uv/cargo homes, so a sandboxed HOME doesn't
  # force fresh downloads of Python, crates, or toolchains on every test run.
  env UV_CACHE_DIR="$REAL_UV_CACHE_DIR" UV_PYTHON_INSTALL_DIR="$REAL_UV_PYTHON_DIR" \
    CARGO_HOME="$REAL_CARGO_HOME" RUSTUP_HOME="$REAL_RUSTUP_HOME" "$@"
}
OLD
# 3. The divider above the runner, after the last test block.
my $runner_anchor = "\n# --- runner -------------------------------------------------------------------\n";

my @missing;
push @missing, 'the REAL_RUSTUP_HOME line' unless count($text, $homes_anchor) == 1;
push @missing, 'the stack_env function quoted under "Current state"' unless count($text, $old_stack_env) == 1;
push @missing, 'the "# --- runner ---" divider' unless count($text, $runner_anchor) == 1;
if (@missing) {
  die "step-1: STOP, $file does not contain exactly one of: " . join('; ', @missing) . "\n";
}

sub swap {  # replace the single occurrence of $old with $new
  my ($old, $new) = @_;
  substr($text, index($text, $old), length($old)) = $new;
}
swap($homes_anchor, $homes_anchor . $homes);
swap($old_stack_env, "\n" . $stack_env);
swap($runner_anchor, "\n" . $tests . $runner_anchor);

open(my $out, '>', $file) or die "step-1: cannot write $file: $!\n";
print {$out} $text;
close $out or die "step-1: cannot write $file: $!\n";
print "step-1: applied 3 edits to $file\n";
````

`step-2.sh` writes the pack out of this plan and fetches `FOLDKIT.md` (step 2):

`step-2.sh`:

````bash
#!/usr/bin/env bash
# Plan 011, step 2: write the foldkit pack out of the plan byte for byte, check
# every file against the rehearsed tree, set the executable bits, and fetch
# FOLDKIT.md from the pinned release tag. Run from the repo root.
set -euo pipefail
here="$(CDPATH='' cd "$(dirname "$0")" && pwd)"
plan=plans/011-stack-pack-foldkit.md
[ -f "$plan" ] && [ -d template/stacks ] || { echo "step-2: run this from the repo root" >&2; exit 1; }
sed -n '/^### Step 2:/,/^### Step 3:/p' "$plan" | perl -MFile::Path=make_path -MFile::Basename=dirname -ne '
  if (!$in && /^`([^`]+)`:$/) { $p = "template/stacks/foldkit/$1"; next }
  if (!$in && defined $p && /^````\w*$/) { make_path(dirname($p)); open(F, ">", $p) or die "cannot write $p\n"; $in = 1; next }
  if ($in && /^````$/) { close F; $in = 0; undef $p; next }
  print F $_ if $in;'
shasum -a 256 -c "$here/pack.sha256"
chmod +x template/stacks/foldkit/files/scripts/coverage.sh \
  template/stacks/foldkit/files/scripts/vendor-foldkit.sh \
  template/stacks/foldkit/files/scripts/coverage-tiers.mjs \
  template/stacks/foldkit/files/scripts/check-pins.mjs \
  template/stacks/foldkit/files/scripts/check.d/foldkit.sh
# FOLDKIT.md ships verbatim from Foldkit's release tag; Foldkit owns it.
curl -fsSL -o template/stacks/foldkit/files/FOLDKIT.md \
  'https://raw.githubusercontent.com/foldkit/foldkit/foldkit@0.165.0/packages/create-foldkit-app/templates/base/FOLDKIT.md'
echo '6edf2313c1102af74bb963c9dd1e8ed596876fbfe6d6c7b3356104c983e6be29  template/stacks/foldkit/files/FOLDKIT.md' | shasum -a 256 -c
echo "step-2: wrote $(find template/stacks/foldkit -type f | wc -l | tr -d ' ') files under template/stacks/foldkit"
````

`lockfile.sh` generates the pack's lockfile and records the age-rule verdict (step 3):

`lockfile.sh`:

````bash
#!/usr/bin/env bash
# Plan 011, step 3: generate the foldkit pack's pnpm-lock.yaml.
# pnpm must never install inside template/ (the root .gitignore has no
# node_modules/), so this installs a scratch copy with the tokens filled and
# copies only the lockfile back. Then it records whether the pack's own 24-hour
# age rule accepts that lockfile yet (age.env, read by heavy.sh and look.sh).
# Run from the repo root.
set -euo pipefail
unset CI pnpm_config_minimum_release_age PNPM_CONFIG_MINIMUM_RELEASE_AGE
here="$(CDPATH='' cd "$(dirname "$0")" && pwd)"
repo="$PWD"
files="$repo/template/stacks/foldkit/files"
[ -f "$files/package.json" ] || { echo "lockfile: run this from the repo root, after step 2" >&2; exit 1; }
rm -f "$here/age.env"
tmp="${TMPDIR:-/tmp}"
scratch="$(mktemp -d "${tmp%/}/plan-011-lock.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
cp -R "$files/." "$scratch/"
rm -f "$scratch/pnpm-lock.yaml"
printf '0.0.0\n' > "$scratch/VERSION"
cd "$scratch"
find . -type f -exec perl -pi -e 's/\{\{PROJECT_NAME\}\}/Demo App/g; s/\{\{PACKAGE_NAME\}\}/demo_app/g' {} +

# In this scratch copy only, exempt the train from the age rule. Every other
# package still has to be 24 hours old, and the pack's pnpm-workspace.yaml is
# never edited.
cat >> pnpm-workspace.yaml <<'YAML'
minimumReleaseAgeExclude:
  - foldkit
  - '@foldkit/*'
  - effect
  - '@effect/*'
YAML
pnpm install
node scripts/check-pins.mjs
pnpm peers check
if grep -n -e 'demo_app' -e 'Demo App' pnpm-lock.yaml; then
  echo "lockfile: the lockfile names the scratch project: STOP" >&2
  exit 1
fi
cp pnpm-lock.yaml "$files/pnpm-lock.yaml"
echo "lockfile: wrote template/stacks/foldkit/files/pnpm-lock.yaml ($(wc -c < pnpm-lock.yaml | tr -d ' ') bytes)"

# The pack's own policy, as a new project and CI will apply it.
cp "$files/pnpm-workspace.yaml" pnpm-workspace.yaml
if out="$(pnpm install --frozen-lockfile --lockfile-only 2>&1)"; then
  printf "AGE_ENV=''\n" > "$here/age.env"
  echo "age rule: the pack's own policy accepts the lockfile"
elif printf '%s\n' "$out" | grep -q 'ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION'; then
  printf "AGE_ENV='pnpm_config_minimum_release_age=0'\n" > "$here/age.env"
  echo "age rule: part of the train is under 24 hours old, so heavy.sh and look.sh relax the rule for their own runs"
else
  printf '%s\n' "$out" >&2
  echo "lockfile: the frozen check failed for another reason: STOP" >&2
  exit 1
fi
````

`heavy.sh` runs the four heavy tests and fails unless all four passed (steps 3 and 5):

`heavy.sh`:

````bash
#!/usr/bin/env bash
# Plan 011: run the four heavy foldkit tests, and fail unless all four passed.
# pnpm's age rule is relaxed for this run only when lockfile.sh found part of
# the train under 24 hours old. Run from the repo root.
set -euo pipefail
unset CI
here="$(CDPATH='' cd "$(dirname "$0")" && pwd)"
[ -f "$here/age.env" ] || { echo "heavy: run lockfile.sh first (it writes age.env)" >&2; exit 1; }
for tool in pnpm node git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "heavy: $tool is not on PATH, so the tests would skip" >&2; exit 1; }
done
# shellcheck source=/dev/null
. "$here/age.env"
if [ -n "$AGE_ENV" ]; then
  export "${AGE_ENV?}"
  echo "heavy: running with $AGE_ENV (part of the train is under 24 hours old)"
fi
SELFTEST_HEAVY=1 ./scripts/template-selftest.sh test_heavy_stack_foldkit 2>&1 | tee "$here/heavy.out" || true
if grep -qx 'selftest: 4 passed, 0 failed, 0 skipped' "$here/heavy.out"; then
  echo "heavy: ok, 4 passed in ${SECONDS}s"
else
  echo "heavy: FAILED, expected 'selftest: 4 passed, 0 failed, 0 skipped' (output kept in $here/heavy.out)" >&2
  exit 1
fi
````

`look.sh` bootstraps a real project and runs its gate (step 5):

`look.sh`:

````bash
#!/usr/bin/env bash
# Plan 011, last step: bootstrap a real "Demo App" in a scratch directory and
# run its whole gate. Bootstrap gets a sandboxed HOME, so its optional gstack
# call can't write to ~/.gstack; pnpm and Playwright keep their real homes, so
# nothing downloads twice. Run from the repo root.
set -euo pipefail
unset CI
here="$(CDPATH='' cd "$(dirname "$0")" && pwd)"
repo="$PWD"
[ -x "$repo/bootstrap" ] && [ -f "$repo/template/stacks/foldkit/files/pnpm-lock.yaml" ] \
  || { echo "look: run this from the repo root, after step 3" >&2; exit 1; }
[ -f "$here/age.env" ] || { echo "look: run lockfile.sh first (it writes age.env)" >&2; exit 1; }
# shellcheck source=/dev/null
. "$here/age.env"
if [ -n "$AGE_ENV" ]; then
  export "${AGE_ENV?}"
  echo "look: running with $AGE_ENV (part of the train is under 24 hours old)"
fi

store="$(pnpm store path | sed 's|/v[0-9][0-9]*$||')"
case "$(uname -s)" in
  Darwin) cache="$HOME/Library/Caches/pnpm" pnpm_home="$HOME/Library/pnpm"
    browsers="$HOME/Library/Caches/ms-playwright" ;;
  *) cache="${XDG_CACHE_HOME:-$HOME/.cache}/pnpm" pnpm_home="${XDG_DATA_HOME:-$HOME/.local/share}/pnpm"
    browsers="${XDG_CACHE_HOME:-$HOME/.cache}/ms-playwright" ;;
esac
export pnpm_config_store_dir="$store"
export pnpm_config_cache_dir="${pnpm_config_cache_dir:-${PNPM_CONFIG_CACHE_DIR:-$cache}}"
export PNPM_HOME="${PNPM_HOME:-$pnpm_home}"
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$browsers}"

tmp="${TMPDIR:-/tmp}"
base="$(mktemp -d "${tmp%/}/plan-011-look.XXXXXX")"
d="$base/demo-app"
mkdir -p "$d" "$base/home"
git ls-files -z --cached --others --exclude-standard | tar --null -T - -cf - | tar -xf - -C "$d"
cd "$d"
trap 'echo "look: FAILED (the project is left at $d)" >&2' ERR
HOME="$base/home" ./bootstrap --name "Demo App" --stack foldkit --yes
# editorconfig-checker is off, as in the self-test: the template's markdown does not pass it yet (TODOS.md).
EDITORCONFIG_CHECKER_BIN=/nonexistent ./scripts/check.sh
./scripts/coverage.sh
pnpm exec playwright install chromium
pnpm exec playwright test
pnpm build
pnpm exec tsc --version
ls repos/foldkit

if curl -fsS -o /dev/null http://localhost:3000/ 2>/dev/null; then
  echo "look: something already listens on port 3000, so the dev-server check is skipped"
else
  pnpm exec vite >"$base/vite.log" 2>&1 &
  vite_pid=$!
  trap 'kill "$vite_pid" 2>/dev/null || true' EXIT
  roots="$(curl -fs --retry 20 --retry-connrefused --retry-delay 1 http://localhost:3000/ | grep -c '<div id="root">' || true)"
  [ "$roots" = 1 ] || { echo "look: the dev server did not serve the app (see $base/vite.log)" >&2; exit 1; }
  echo "dev server: serves the app on port 3000"
fi
echo "look: ok in ${SECONDS}s, project kept at $d"
````

`pack.sha256` is the manifest `step-2.sh` checks the pack against:

`pack.sha256`:

````text
796ffe4332288ae1a13938f6058b8daf8a2f310607ac708641108736cac857b1  template/stacks/foldkit/after-bootstrap
2223efcbe5c65d03dcf065b080f0dbc65e4b440ebccdd828eae720ae8b06d4ae  template/stacks/foldkit/commands
3c8bdaa900ba050963396468769bd338f40b294fd1ad742218ba51275cf57dd3  template/stacks/foldkit/description
61bba052ac4eea040785088c25ea7f06c9c4fd234bfe422464700877139b1b50  template/stacks/foldkit/files/.github/workflows/ci.yml
c56a5fed03c9d4b83c95ea55298d3fe105fe3d073939780e845c16a756c5c52b  template/stacks/foldkit/files/.ignore
73fb1b615e2043a933be1c0895cde4358036acc28d785692509b822aa53c761f  template/stacks/foldkit/files/.node-version
c1dcc87657651503cb0dbfb58134afb42ee6b0614a55f2bbbfaaf04bbdab4a87  template/stacks/foldkit/files/.oxfmtrc.json
574d8e18679c49e5c1575106b818d059b13020552be8d4871afa7bdddfc1dd32  template/stacks/foldkit/files/.oxlintrc.json
9dc97b628ed642929a09af135c12b40920db7ee2d20dac510d8a905f154ae56d  template/stacks/foldkit/files/coverage-tiers.json
1dd318cd6e11fb367ae30720e17a2af0d0680ce0b038f988c7dbadbf20296128  template/stacks/foldkit/files/docs/guides/foldkit.md
7413cb5508fb301d76b5a84616b402b48da18cb20cdc903a44070b9dcd02ae0f  template/stacks/foldkit/files/e2e/home.spec.ts
f7f264e7eb13aa6ccc7ea310b4b70fc5935ca249485bb506f47052dc82935684  template/stacks/foldkit/files/index.html
7b42c7ef5ccca04a9c8a5340dba5990bfb647281ad362542bd347075b337e2e7  template/stacks/foldkit/files/package.json
3efcd35931caad7f61b635666a6281027651442f5d4702c8b4a74fcaacfe9826  template/stacks/foldkit/files/playwright.config.ts
f7954032a67748ad97d9215164ec2d01f40a498dac2c597afab99b71c5001dc2  template/stacks/foldkit/files/pnpm-workspace.yaml
7a514c239365685cf6284be31af30c2d8c18ed8a0ddb5b7e3b9994d2ba29c972  template/stacks/foldkit/files/public/status.json
1ca7d5e2467082ce016198f177685852bee142caf6b8c370d24e9758b1dd528c  template/stacks/foldkit/files/scripts/check-pins.mjs
1f959fe8afee1644e76a6fac2cf928dbbe844451af16dc9a822a2e4ec504c7a8  template/stacks/foldkit/files/scripts/check.d/foldkit.sh
02e64cf58a622a13a5eec6488e5f7876636c264a828fdea0c922405e2e170245  template/stacks/foldkit/files/scripts/coverage-tiers.mjs
7a72d9b3eb19176c4dd47c16dfe00cb807f544c8dfd8b2444afb8329a3355c53  template/stacks/foldkit/files/scripts/coverage.sh
af437c5bce38654c86657facb6323cdea2633af93a1cd33dddada089f8d69570  template/stacks/foldkit/files/scripts/vendor-foldkit.sh
7c8470e6b610f25dc41369a8917f81fd3b14cd2ffb870af18e81c299d19ec58c  template/stacks/foldkit/files/src/api/status.test.ts
b1ddfc910e5f16ec8a39849e2aa6d76c1016e284c97ac66474f3006aa40862e6  template/stacks/foldkit/files/src/api/status.ts
e89abd104579ed02fea5954b4c1d5e46a6b070765e3d7485ef0c8034a7c3a412  template/stacks/foldkit/files/src/build-info.ts
31c6d1696cdc9828f24c935056fbec97abe4425824fb61ee7acce33ee5b8f780  template/stacks/foldkit/files/src/command.test.ts
b155a537c2d48845bf82d9c5ce1b86bd2485e00ee46a06becf699ef3058a3d63  template/stacks/foldkit/files/src/command.ts
d185f7fa52d1eb5384dbe05c9cad6aaaf18d20103a819d2131c16011d9aa551c  template/stacks/foldkit/files/src/components/status.ts
5b0709c33d2666af26a51e7714d68059fcc24aeca7113e56592ea6a3aa658b35  template/stacks/foldkit/files/src/domain/version.test.ts
ad5a3d2ad5b1277329d3d77254acb29cab8041b71dd275cc886d31153311d93d  template/stacks/foldkit/files/src/domain/version.ts
bca63c93da480065f421b11ea0dde7fea2223addd488b4b005a0f4a7ed28981a  template/stacks/foldkit/files/src/entry.ts
10408857c5244c4a4142bf3de6d96fdfc63afe4fe82081d9c98443e9e6280850  template/stacks/foldkit/files/src/main.ts
362a6574c854432c1f372b7f51c62130492e78d69a33b9c9fde65baec405d1ab  template/stacks/foldkit/files/src/message.ts
98fdb6cf1be479c3eedf5c80000bdb62b706c90d6e072c8afb5253e997e97e35  template/stacks/foldkit/files/src/scene.test.ts
61d343bd7485b90ddf14c0508b10af2d26d222b4aa48d9e3150ab9eb26a1b3df  template/stacks/foldkit/files/src/story.test.ts
b6a325497ad19903f02c03be43beaee2ac30cf922276e02065eb2fd3321d6498  template/stacks/foldkit/files/src/styles.css
ad14a117c9a2a628c751465f4752fd2bca4a589f642bce14eb1c7c6807e1a96c  template/stacks/foldkit/files/src/view.ts
65996936fbb042915f7b74a200fcdde7e410f32a669b1ab9597cfaa4b0faddb5  template/stacks/foldkit/files/src/vite-env.d.ts
77a460a179fff1c4146a74484547860798c0ccb14af879afd104638afeb5fb74  template/stacks/foldkit/files/src/vitest-setup.ts
bbb2db25f4826eb005f67ce2ea4b25b864e70e4958c0767ecdb835fa7bfa03e7  template/stacks/foldkit/files/tsconfig.json
d729f31c6a37cc4d8a5f6379fb9885d70abfe26d2a2be12ac98b3981d3cb5549  template/stacks/foldkit/files/vite.config.ts
b8a0095aca8e29264f41b692e86c4ce352f8c73734ff1d71d9ef71d1341868c9  template/stacks/foldkit/files/vitest.config.ts
3704c44bd81fb9a9dfa02fb3b4607571db5d3b783167c3c152e401fe9b1e8356  template/stacks/foldkit/gitignore
0060b11ed419a91ffd0245a7f59f264d7a7729c5b5203da8f892d78233ae3c55  template/stacks/foldkit/validate-name
````

`helpers.sha256` is the manifest preflight step 1 checks the files above and step 1's three
blocks against:

`helpers.sha256`:

````text
d3e3e6eb89a18e9d4b732b5f6df2b63d2cbeb3967eda3a41983b75cbd72d9ee0  train.mjs
ec63e0c7e7413aecf0b905470ac3bd420989e9ad9d7f96fde2ce8da52a7e105c  contracts.sh
8b0fa6b05082454f1d7428464225083f9d01c56ac6b2a4fe95e00222769e0eaa  step-1.pl
5d471ccbe22faaded6b964e56cf8012261cb0180e1e6748179c676aaa4d092d4  step-2.sh
fb4642aa4f7232987da6423d9aecc1e494d6520db05ce000a008c6fda523975e  lockfile.sh
c1736aa6c4b8e49f3aa571bf80178b601b9ebcf008b4e5e9d065cf6f5bdaa007  heavy.sh
b13dd685de5f7b3098f0eeb0d40463eb633a43a7cddec0f762e9d0a943f340b8  look.sh
ae66b1ff4d2aa344fdd3b3ce57f201fa22dd99895d6296db99d57525415be64b  pack.sha256
e367c7bb5217ac31b0ee6a902a1a14c9937f193f9f37ef4b05c460aed7f2880a  selftest-homes.bash
24169f93bba596d56737a2bd52fedf7c35282598ea3358ab137e6a4e9aa6d212  selftest-stack-env.bash
b268deb317ab3f0683006a7266c0cfea7008ebdfc4d6114c8c56babbf7681d9d  selftest-tests.bash
````

## Scope

**In scope** (the only files you should modify or create):

- `scripts/template-selftest.sh` (step 1)
- everything under `template/stacks/foldkit/` (create, steps 2 and 3)
- `.github/workflows/template-selftest.yml` (step 2)
- `TEMPLATE.md`, `TODOS.md` (step 4)
- `plans/README.md` (your status row)

`.context/plan-011/` is gitignored scratch for the helpers; it is never committed.

**Out of scope** (do NOT touch):

- `bootstrap`, `scripts/check.sh` and the other packs: the mechanism is done.
- `AGENTS.md`, `CLAUDE.md`, `TESTING.md`, `README.md`, `DESIGN.md`: the pack fills or adds to
  them in new projects only; the template keeps its placeholders.
- `.gitleaks.toml`: the pack and a new project, lockfile included, scan clean with gitleaks
  8.30.1 (verified).
- `.editorconfig`: TypeScript, JSON and YAML use its 2-space default.
- `FOLDKIT.md`'s content: Foldkit owns it; copy it verbatim, never edit it.
- The pack's `pnpm-workspace.yaml`: never loosen it to get an install through.
- Any version other than the ones this plan pins, routing, SSR, `@foldkit/ui`, Tailwind, and the
  React pack.

## Git workflow

- Work on the branch you were given; do not rename it.
- Commit per step, plain imperative messages (e.g. `Add the foldkit stack pack`).
- Do NOT push or open a PR unless the operator told you to.

## Steps

### Step 1: Add the failing tests

Run `perl .context/plan-011/step-1.pl`. It must print `step-1: applied 3 edits to
scripts/template-selftest.sh`. It makes these three edits, and writes nothing unless all three
anchors are present exactly once (a message that starts `step-1: STOP` is a STOP condition):

1. Directly below the line `REAL_RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"`, it inserts
   `selftest-homes.bash`: the real pnpm and Playwright homes.
2. It replaces the `stack_env` function quoted under "Current state" with
   `selftest-stack-env.bash`, which also passes those homes on.
3. Directly above the line `# --- runner ---…`, after plan 010's block, it inserts
   `selftest-tests.bash`: the nine tests and their helpers.

**Verify** (with `CI` unset):

- `git diff --stat` → only `scripts/template-selftest.sh` changed.
- `./scripts/template-selftest.sh stack_foldkit` → the 5 light tests FAIL (the pack does not
  exist yet) and the 4 heavy tests skip with a reason: `selftest: 0 passed, 5 failed, 4
  skipped`. That is the expected red state.
- `shellcheck scripts/template-selftest.sh` → exit 0.

The three blocks follow. They are data for `step-1.pl`, which preflight step 1 already wrote to
`.context/plan-011/`: read them to see the tests, then go on to step 2 (search for
`### Step 2`).

`selftest-homes.bash`:

````bash
# pnpm 12 reads pnpm_config_* (and PNPM_CONFIG_*) variables, not npm_config_*.
# `pnpm store path` ends in the store layout version (/v11); the setting is its parent.
REAL_PNPM_STORE_DIR="$(pnpm store path 2>/dev/null | sed 's|/v[0-9][0-9]*$||' || true)"
REAL_PNPM_STORE_DIR="${REAL_PNPM_STORE_DIR:-$HOME/.pnpm-store}"
case "$(uname -s)" in
  Darwin) REAL_PNPM_CACHE_DIR="$HOME/Library/Caches/pnpm" REAL_PNPM_HOME="$HOME/Library/pnpm"
    REAL_PLAYWRIGHT_BROWSERS_PATH="$HOME/Library/Caches/ms-playwright" ;;
  *) REAL_PNPM_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pnpm" REAL_PNPM_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/pnpm"
    REAL_PLAYWRIGHT_BROWSERS_PATH="${XDG_CACHE_HOME:-$HOME/.cache}/ms-playwright" ;;
esac
REAL_PNPM_CACHE_DIR="${pnpm_config_cache_dir:-${PNPM_CONFIG_CACHE_DIR:-$REAL_PNPM_CACHE_DIR}}"
REAL_PNPM_HOME="${PNPM_HOME:-$REAL_PNPM_HOME}"
REAL_PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$REAL_PLAYWRIGHT_BROWSERS_PATH}"
````

`selftest-stack-env.bash`:

````bash
stack_env() {  # run "$@" with the real uv/cargo/pnpm/Playwright homes, so a sandboxed
  # HOME doesn't force fresh downloads of Python, crates, toolchains, npm packages,
  # pnpm's Node runtime or Chromium on every test run.
  env UV_CACHE_DIR="$REAL_UV_CACHE_DIR" UV_PYTHON_INSTALL_DIR="$REAL_UV_PYTHON_DIR" \
    CARGO_HOME="$REAL_CARGO_HOME" RUSTUP_HOME="$REAL_RUSTUP_HOME" \
    pnpm_config_store_dir="$REAL_PNPM_STORE_DIR" pnpm_config_cache_dir="$REAL_PNPM_CACHE_DIR" \
    PNPM_HOME="$REAL_PNPM_HOME" \
    PLAYWRIGHT_BROWSERS_PATH="$REAL_PLAYWRIGHT_BROWSERS_PATH" "$@"
}
````

`selftest-tests.bash`:

````bash
# --- tests: foldkit stack pack (plan 011) ---------------------------------------
foldkit_heavy_ready() {  # why the heavy foldkit tests can't run here; empty = run them
  if [ "${CI:-}" != "true" ] && [ "${SELFTEST_HEAVY:-}" != "1" ]; then
    echo "installs a real Foldkit project from the network: set SELFTEST_HEAVY=1 to run it here; CI runs it in the heavy job"
    return
  fi
  local tool
  for tool in node pnpm git; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool not installed"; return; }
  done
}
foldkit_files() {  # $1 = dir: the pack's files/, unbootstrapped, with the tokens filled
  mkdir -p "$1" || return 1
  (cd "$REPO/template/stacks/foldkit/files" && tar -cf - .) | tar -xf - -C "$1" || return 1
  printf '0.0.0\n' > "$1/VERSION"
  (cd "$1" && find . -type f -exec perl -pi -e 's/\{\{PROJECT_NAME\}\}/Demo App/g; s/\{\{PACKAGE_NAME\}\}/demo_app/g' {} +)
}
fk_node() {  # $1 = dir, rest = node args, run there -> "$1.node.out"
  local dir="$1"; shift
  (cd "$dir" && node "$@" >"$dir.node.out" 2>&1)
}
fk_json() {  # $1 = JSON file, $2 = a JS statement over `c` (the parsed file); rewrites it
  node -e 'const fs = require("fs"); const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); eval(process.argv[2]); fs.writeFileSync(process.argv[1], JSON.stringify(c, null, 2) + "\n")' "$1" "$2"
}
foldkit_project() {  # $1 = dir, $2 = project name: a fresh copy bootstrapped with the foldkit pack
  fresh_copy "$1" || return 1
  (cd "$1" && HOME="$WORK/home" stack_env ./bootstrap --name "$2" --stack foldkit --yes </dev/null >"$1.out" 2>&1) \
    || fail "bootstrap exited $?: $(tail -20 "$1.out")"
}
test_stack_foldkit_rejects_unusable_names_before_mutation() {
  # A project named like a direct dependency breaks its own install or type check
  # (named `effect`, the Effect language service reports a duplicate package on
  # every file), and past 50 characters Oxfmt wraps src/build-info.ts.
  local d name want before rc n=0
  while IFS='|' read -r name want; do
    n=$((n + 1))
    d="$WORK/stack-foldkit-names-$n/proj"
    fresh_copy "$d" || return 1
    before="$(tree_fingerprint "$d")"
    run_bootstrap "$d" --name "$name" --stack foldkit --yes; rc=$?
    assert_exit 2 "$rc" || return 1
    assert_contains "$d.out" "$want" || return 1
    [ "$before" = "$(tree_fingerprint "$d")" ] || fail "rejecting '$name' changed files" || return 1
  done <<'NAMES'
Effect|taken by a package the foldkit pack depends on
foldkit|taken by a package the foldkit pack depends on
VITE|taken by a package the foldkit pack depends on
vitest|taken by a package the foldkit pack depends on
TypeScript|taken by a package the foldkit pack depends on
oxlint|taken by a package the foldkit pack depends on
oxfmt|taken by a package the foldkit pack depends on
playwright|taken by a package the foldkit pack depends on
node_modules|reserved by Node.js
Acme Example Inventory Reconciliation Service Ok123|too long for the foldkit stack pack
NAMES
}
test_stack_foldkit_coverage_tiers_fail_closed() {
  # scripts/coverage-tiers.mjs is the only coverage enforcement (Vitest passes a
  # tier glob that matches nothing): every schema rule, every counter check and
  # every floor must fail closed, and --report prints only the snapshot table.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-tiers/demo" rc
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --validate; rc=$?
  assert_exit 0 "$rc" || { cat "$d.node.out"; return 1; }
  assert_contains "$d.node.out" "coverage-tiers: ok" || return 1
  cat > "$d/probe.mjs" <<'PROBE'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { mkdirSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import * as tiers from './scripts/coverage-tiers.mjs'

const root = realpathSync('.')
const config = JSON.parse(readFileSync('coverage-tiers.json', 'utf8'))
const members = Object.values(config.tiers).flatMap(tier => tier.include)
const metric = (total, covered = total) => ({ total, covered, skipped: 0, pct: 0 })
const entry = (lines = 10, lineHits = lines, branches = 2, branchHits = branches, fns = 2, fnHits = fns) =>
  ({ lines: metric(lines, lineHits), statements: metric(lines, lineHits), branches: metric(branches, branchHits), functions: metric(fns, fnHits) })
const summary = (overrides = {}, extra = {}) => {
  const files = {}
  for (const path of members) {
    if (overrides[path] !== null) files[join(root, path)] = overrides[path] ?? entry()
  }
  for (const [path, value] of Object.entries(extra)) files[path.startsWith('/') ? path : join(root, path)] = value
  const total = {}
  for (const name of ['lines', 'statements', 'branches', 'functions']) {
    const sum = field => Object.values(files).reduce((acc, file) => acc + file[name][field], 0)
    total[name] = metric(sum('total'), sum('covered'))
  }
  return { total, ...files }
}
const cli = (...args) => spawnSync(process.execPath, ['scripts/coverage-tiers.mjs', ...args], { encoding: 'utf8' })
const run = (data, expected, text = '', args = ['--check']) => {
  mkdirSync('coverage', { recursive: true })
  writeFileSync('coverage/coverage-summary.json', typeof data === 'string' ? data : JSON.stringify(data))
  const result = cli(...args)
  const out = result.stdout + result.stderr
  assert.equal(result.status, expected, out)
  assert.ok(out.includes(text), `expected ${JSON.stringify(text)} in: ${out}`)
  assert.ok(!/^\s+at /m.test(out), `stack trace in: ${out}`)
  return result
}

// Passing, then each floor independently: global lines and branches (90%, inclusive),
// and each tier's lines, branches and functions.
run(summary(), 0, 'coverage-tiers: ok')
const atFloor = summary({}, { 'src/extra.ts': entry(40, 30, 8, 6, 2, 0) })
run(atFloor, 0, 'coverage-tiers: ok')
run(summary({}, { 'src/extra.ts': entry(40, 29, 8, 8) }), 1, 'global: lines 89.00% is below its minimum 90% (below the floor: src/extra.ts 72.50%)')
run(summary({}, { 'src/extra.ts': entry(40, 40, 8, 5) }), 1, 'global: branches 85.00% is below its minimum 90%')
const big = { 'src/extra.ts': entry(1000, 1000, 100, 100) }
run(summary({ 'src/main.ts': entry(10, 9) }, big), 1, 'pure_logic: lines 95.00% is below its minimum 100%')
run(summary({ 'src/api/status.ts': entry(10, 10, 2, 1) }, big), 1, 'api_surface: branches 75.00% is below its minimum 100%')
run(summary({ 'src/view.ts': entry(10, 10, 2, 2, 10, 5) }, big), 1, 'main_components: functions 58.33% is below its minimum 90%')
run(summary({ 'src/view.ts': entry(10, 10, 0, 0, 1, 1), 'src/components/status.ts': entry(10, 10, 0, 0, 1, 1) }), 0, 'coverage-tiers: ok')
// Membership: a member missing from the report, or with nothing measurable, fails.
run(summary({ 'src/command.ts': null }), 1, 'api_surface: src/command.ts is not in the coverage report')
run(summary({ 'src/view.ts': entry(0, 0, 0, 0, 0, 0) }), 1, 'main_components: src/view.ts has no measurable lines')
// Malformed reports fail, for --check and --report alike.
const mutations = [
  data => { delete data[join(root, 'src/main.ts')].lines },
  data => { data[join(root, 'src/main.ts')].lines.covered = -1 },
  data => { data[join(root, 'src/main.ts')].branches.total = 1.5 },
  data => { data[join(root, 'src/main.ts')].functions.covered = 3 },
  data => { data[join(root, 'src/main.ts')] = 'x' },
  data => { data[join(root, 'src/main.ts')].lines.total = '10' },
  data => { delete data.total },
  data => { data.total.lines.covered -= 1 },
]
for (const mutate of mutations) {
  const data = summary()
  mutate(data)
  run(data, 1, 'coverage-tiers: FAIL')
  run(data, 1, 'coverage-tiers: FAIL', ['--report'])
}
run((() => { const data = summary(); data.total.branches.total += 1; data.total.branches.covered += 1; return data })(), 1, 'global: counters disagree with per-file sums')
run(summary({}, { '/elsewhere/src/x.ts': entry() }), 1, 'coverage summary names a file outside the project: /elsewhere/src/x.ts')
run({ total: summary().total }, 1, 'coverage summary has no per-file entries')
run(summary(Object.fromEntries(members.map(path => [path, entry(0, 0, 0, 0, 0, 0)]))), 1, 'global: no measurable lines')
run([], 1, 'coverage summary must be an object')
run('{', 1, 'coverage-tiers: FAIL cannot load valid configuration/report')
rmSync('coverage', { recursive: true, force: true })
let result = cli('--check')
assert.ok(result.status === 1 && result.stderr.includes('cannot load valid configuration/report'), result.stderr)

// --report: the table alone, with n/a for an explicitly empty tier and for a
// metric with nothing to measure. --input reads another file.
const original = readFileSync('coverage-tiers.json', 'utf8')
try {
  const withEmpty = JSON.parse(original)
  withEmpty.tiers.later = { title: 'Later', minimum: 0, target: 100, include: [], allow_empty: true }
  writeFileSync('coverage-tiers.json', JSON.stringify(withEmpty))
  const branchless = summary({ 'src/view.ts': entry(10, 10, 0, 0), 'src/components/status.ts': entry(10, 10, 0, 0) }, { 'src/extra.ts': entry(40, 30, 8, 6, 2, 0) })
  result = run(branchless, 0, '', ['--report'])
  assert.equal(result.stdout, [
    '| Tier | Lines | Branches | Functions | Minimum | Target |',
    '|---|---|---|---|---|---|',
    '| Global (lines and branches) | 90.00% | 87.50% | 85.71% | 90% | 100% |',
    '| Pure logic & utilities | 100.00% | 100.00% | 100.00% | 100% | 100% |',
    '| API / contract surface | 100.00% | 100.00% | 100.00% | 100% | 100% |',
    '| Main UI components | 100.00% | n/a (nothing to measure) | 100.00% | 90% | 90% |',
    '| Later | n/a (explicitly empty) | n/a (explicitly empty) | n/a (explicitly empty) | 0% | 100% |',
    '',
  ].join('\n'))
} finally {
  writeFileSync('coverage-tiers.json', original)
}
writeFileSync('alt.json', JSON.stringify(summary()))
run('{}', 0, 'coverage-tiers: ok', ['--check', '--input', 'alt.json'])
run('{}', 0, 'coverage-tiers: ok', ['--check', '--input=alt.json'])

// Usage errors exit 2.
for (const args of [[], ['--check', '--report'], ['--bogus'], ['--ratchet', ''], ['--ratchet'], ['--input'], ['--check=1']]) {
  result = cli(...args)
  assert.equal(result.status, 2, `${JSON.stringify(args)}: ${result.stdout}${result.stderr}`)
}

// Config validation: every rule names what it rejects.
const rejected = (text, mutate) => {
  const bad = structuredClone(config)
  mutate(bad)
  const errors = tiers.validate(bad)
  assert.ok(errors.some(error => error.includes(text)), `${text}: ${JSON.stringify(errors)}`)
}
assert.deepEqual(tiers.validate(config), [])
assert.ok(tiers.validate(null).some(error => error.includes('must be an object')))
rejected('unknown top-level keys: ["tier"]', c => { c.tier = {} })
rejected('tiers must be a nonempty object', c => { c.tiers = {} })
rejected('tiers must be a nonempty object', c => { c.tiers = [] })
rejected('global is reserved', c => { c.tiers.global = { title: 'G', minimum: 0, target: 0, include: [], allow_empty: true } })
rejected('later: tier must be an object', c => { c.tiers.later = [] })
rejected('unknown tier keys: ["minimun"]', c => { c.tiers.api_surface.minimun = 100 })
for (const value of [true, Number.NaN, Number.POSITIVE_INFINITY, '100', null]) {
  rejected('minimum and target must be finite numbers', c => { c.tiers.api_surface.minimum = value })
}
rejected('need 0 <= minimum <= target <= 100', c => { c.tiers.api_surface.target = 99 })
rejected('need 0 <= minimum <= target <= 100', c => { c.tiers.pure_logic.target = 101 })
rejected('need 0 <= minimum <= target <= 100', c => { c.tiers.main_components.minimum = -1 })
rejected('title must be a nonempty string', c => { c.tiers.api_surface.title = '  ' })
rejected('title must be a nonempty string', c => { c.tiers.api_surface.title = 1 })
rejected('allow_empty must be boolean', c => { c.tiers.api_surface.allow_empty = 'true' })
rejected('retired must be an array', c => { c.tiers.api_surface.retired = 'src/old.ts' })
rejected('retired must name canonical', c => { c.tiers.api_surface.retired = ['tests/old.ts'] })
rejected('is listed twice across include and retired', c => { c.tiers.api_surface.retired = ['src/old.ts', 'src/old.ts'] })
rejected('is listed twice across include and retired', c => { c.tiers.api_surface.retired = ['src/command.ts'] })
rejected('include must be an explicit array', c => { c.tiers.api_surface.include = 'src/command.ts' })
rejected('empty include requires allow_empty', c => { c.tiers.api_surface.include = [] })
for (const path of ['src/main.js', 'src\\main.ts', 'src//main.ts', 'src/./main.ts', 'src/../src/main.ts', '/tmp/main.ts', 'tests/main.ts', 'src/story.test.ts', 'src/vite-env.d.ts', 7]) {
  rejected('include must name canonical', c => { c.tiers.api_surface.include = [path] })
}
rejected('include "src/missing.ts" is not a file within the project', c => { c.tiers.api_surface.include = ['src/missing.ts'] })
writeFileSync(join(root, '..', 'outside.ts'), 'export const x = 1\n')
symlinkSync(join(root, '..', 'outside.ts'), 'src/escape.ts')
try {
  rejected('include "src/escape.ts" is not a file within the project', c => { c.tiers.api_surface.include = ['src/escape.ts'] })
} finally {
  rmSync('src/escape.ts')
}
rejected('src/main.ts: duplicate membership in "pure_logic" and "api_surface"', c => { c.tiers.api_surface.include.push('src/main.ts') })
rejected('journeys must be a nonempty array', c => { delete c.journeys })
rejected('journeys must be a nonempty array', c => { c.journeys = [] })
rejected('journeys: each must be a nonempty string', c => { c.journeys = [1] })
rejected('is listed twice', c => { c.journeys = [c.journeys[0], c.journeys[0]] })
rejected('journeys: no test("a journey nobody wrote") in e2e/**/*.spec.ts', c => { c.journeys.push('a journey nobody wrote') })
// Journey titles come from plain test('...') calls, quoted either way; a skipped test is not a journey.
writeFileSync('e2e/more.spec.ts', "import { test } from '@playwright/test'\n\ntest(\"it's double-quoted\", async () => {})\ntest('say \\'hi\\'', async () => {})\ntest.skip('skipped journey', async () => {})\n")
try {
  assert.deepEqual(tiers.validate({ ...config, journeys: [...config.journeys, "it's double-quoted", "say 'hi'"] }), [])
  rejected('no test("skipped journey")', c => { c.journeys.push('skipped journey') })
} finally {
  rmSync('e2e/more.spec.ts')
}
writeFileSync('coverage-tiers.json', original.replace('"minimum": 90', '"minimum": 91'))
result = cli('--validate')
assert.ok(result.status === 1 && result.stderr.includes('main_components: need 0 <= minimum <= target <= 100'), result.stderr)
writeFileSync('coverage-tiers.json', original)
console.log('coverage-tiers probes passed')
PROBE
  fk_node "$d" probe.mjs || fail "coverage-tiers probes failed: $(tail -25 "$d.node.out")" || return 1
  assert_contains "$d.node.out" "coverage-tiers probes passed"
}
test_stack_foldkit_coverage_tiers_ratchet() {
  # CI's ratchet compares coverage-tiers.json with the base branch: floors and
  # targets never drop, tiers never disappear, and a member leaves only through
  # `retired`. A base that predates the file passes; an unreadable one fails.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-ratchet/demo" rc
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  (cd "$d" && git init -q && git add -A && git commit -qm init \
    && git branch -f prepack "$(git commit-tree -m base "$(printf '100644 blob %s\tREADME.md\n' "$(git hash-object -w package.json)" | git mktree)")") \
    || fail "git setup failed" || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 0 "$rc" || { cat "$d.node.out"; return 1; }
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet prepack; rc=$?
  assert_exit 0 "$rc" || return 1
  assert_contains "$d.node.out" "no coverage-tiers.json at prepack; nothing to ratchet against" || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet no-such-ref; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "cannot read coverage-tiers.json at no-such-ref: unknown revision" || return 1
  fk_node "$d" scripts/coverage-tiers.mjs "--ratchet=--output=$d.leak"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "unknown revision" || return 1
  assert_absent "$d.leak" || return 1
  cp "$d/coverage-tiers.json" "$d.tiers.json" || return 1
  # Lowered minimum, lowered target, removed tier, removed member: each fails.
  fk_json "$d/coverage-tiers.json" 'c.tiers.api_surface.minimum = 90' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "api_surface: minimum lowered from 100 to 90" || return 1
  cp "$d.tiers.json" "$d/coverage-tiers.json" && fk_json "$d/coverage-tiers.json" 'c.tiers.main_components.target = 95; c.tiers.main_components.minimum = 95' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 0 "$rc" || { cat "$d.node.out"; return 1; }
  cp "$d.tiers.json" "$d/coverage-tiers.json" && fk_json "$d/coverage-tiers.json" 'c.tiers.pure_logic.target = 99; c.tiers.pure_logic.minimum = 99' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "pure_logic: target lowered from 100 to 99" || return 1
  cp "$d.tiers.json" "$d/coverage-tiers.json" && fk_json "$d/coverage-tiers.json" 'delete c.tiers.main_components' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "main_components: tier removed since HEAD" || return 1
  cp "$d.tiers.json" "$d/coverage-tiers.json" && fk_json "$d/coverage-tiers.json" 'c.tiers.api_surface.include = ["src/api/status.ts"]' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" 'api_surface: existing members removed since HEAD: ["src/command.ts"]' || return 1
  assert_contains "$d.node.out" "list its old path in the tier's retired" || return 1
  # An explicitly empty tier must not bypass membership either.
  cp "$d.tiers.json" "$d/coverage-tiers.json" && fk_json "$d/coverage-tiers.json" 'c.tiers.api_surface.include = []; c.tiers.api_surface.allow_empty = true' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "existing members removed since HEAD" || return 1
  # A reviewed move: the old path goes to `retired`.
  cp "$d.tiers.json" "$d/coverage-tiers.json" || return 1
  (cd "$d" && git mv src/command.ts src/commands.ts) || return 1
  fk_json "$d/coverage-tiers.json" 'c.tiers.api_surface.include = ["src/api/status.ts", "src/commands.ts"]; c.tiers.api_surface.retired = ["src/command.ts"]' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 0 "$rc" || { cat "$d.node.out"; return 1; }
  (cd "$d" && git mv src/commands.ts src/command.ts) && cp "$d.tiers.json" "$d/coverage-tiers.json" || return 1
  # Bases whose file is malformed, invalid, or unreadable fail (only a confirmed absence passes).
  base_with() {  # $1 = branch, $2 = coverage-tiers.json content
    (cd "$d" && git branch -f "$1" "$(git commit-tree -m "$1" "$(printf '100644 blob %s\tcoverage-tiers.json\n' \
      "$(printf '%s' "$2" | git hash-object -w --stdin)" | git mktree)")")
  }
  base_with notjson '{' || fail "git setup failed" || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet notjson; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "base config: coverage-tiers.json at notjson is not valid JSON" || return 1
  base_with invalid '{"tiers": {}, "journeys": []}' || fail "git setup failed" || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet invalid; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "base config: tiers must be a nonempty object" || return 1
  (cd "$d" && tree="$(git rev-parse 'invalid^{tree}')" \
    && rm -f ".git/objects/$(printf '%s' "$tree" | cut -c1-2)/$(printf '%s' "$tree" | cut -c3-)") \
    || fail "removing the base tree failed" || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet invalid; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "cannot read coverage-tiers.json at invalid"
}
test_stack_foldkit_pin_guard_fails_closed() {
  # scripts/check-pins.mjs keeps package.json in gstack's byte form and in step with
  # VERSION, every dependency exact and installed at its pin, and the Foldkit +
  # Effect train aligned with what node_modules holds. A synthetic node_modules
  # stands in for pnpm install. Every version comes from the pack's package.json,
  # so the test survives a train move.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-pins/demo" rc bad want f fk vp dt mcp ox effect vite_major fk_next
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  pin() { node -p 'const p = require(process.argv[1]); ({ ...p.dependencies, ...p.devDependencies })[process.argv[2]]' "$d/package.json" "$1"; }
  fk="$(pin foldkit)" vp="$(pin @foldkit/vite-plugin)" dt="$(pin @foldkit/devtools)" \
    mcp="$(pin @foldkit/devtools-mcp)" ox="$(pin @foldkit/oxlint-plugin)" effect="$(pin effect)" || return 1
  vite_major="$(pin vite | cut -d. -f1)"
  fk_next="$(printf '%s' "$fk" | awk -F. '{ print $1 "." $2 + 1 ".0" }')"
  for f in "$fk" "$vp" "$dt" "$mcp" "$ox" "$effect" "$vite_major" "$fk_next"; do
    case "$f" in ''|undefined) fail "cannot read the foldkit train from the pack's package.json" || return 1 ;; esac
  done
  fake() {  # $1 = package name, $2 = version, $3 = peerDependencies JSON
    mkdir -p "$d/node_modules/$1" && printf '{"name":"%s","version":"%s","peerDependencies":%s}\n' "$1" "$2" "$3" > "$d/node_modules/$1/package.json"
  }
  fake foldkit "$fk" "{\"effect\":\"$effect\",\"@effect/platform-browser\":\"$effect\"}" || return 1
  fake @foldkit/vite-plugin "$vp" "{\"vite\":\"^$vite_major.0.0\",\"effect\":\"$effect\",\"foldkit\":\">=0.0.0\"}" || return 1
  fake @foldkit/devtools "$dt" "{\"effect\":\"$effect\",\"foldkit\":\">=$fk\",\"@foldkit/ui\":\"^0\",\"@effect/platform-browser\":\"$effect\"}" || return 1
  fake @foldkit/devtools-mcp "$mcp" "{\"effect\":\"$effect\",\"foldkit\":\">=0.0.0\"}" || return 1
  fake @foldkit/oxlint-plugin "$ox" '{}' || return 1
  # Every other direct dependency is installed too, at its pin.
  fk_node "$d" -e 'const fs = require("fs"); const p = JSON.parse(fs.readFileSync("package.json", "utf8")); for (const [name, version] of Object.entries({ ...p.dependencies, ...p.devDependencies })) { const dir = "node_modules/" + name; if (!fs.existsSync(dir)) { fs.mkdirSync(dir, { recursive: true }); fs.writeFileSync(dir + "/package.json", JSON.stringify({ name, version }) + "\n") } }' \
    || fail "faking the other dependencies failed: $(cat "$d.node.out")" || return 1
  fk_node "$d" scripts/check-pins.mjs; rc=$?
  assert_exit 0 "$rc" || { cat "$d.node.out"; return 1; }
  assert_contains "$d.node.out" "check-pins: ok" || return 1
  for f in package.json VERSION .node-version; do cp "$d/$f" "$d.$f.orig" || return 1; done
  cp -R "$d/node_modules" "$d.node_modules.orig" || return 1
  # Each case: a mutation (run in the project, with the pins in its environment)
  # and the text its failure must contain (@FK@ and friends are the pins).
  while IFS='|' read -r bad want; do
    for f in package.json VERSION .node-version; do cp "$d.$f.orig" "$d/$f" || return 1; done
    rm -rf "$d/node_modules" && cp -R "$d.node_modules.orig" "$d/node_modules" || return 1
    (cd "$d" && FK="$fk" FK_NEXT="$fk_next" VITE_NEXT="^$((vite_major + 1)).0.0" eval "$bad") \
      || fail "mutation failed: $bad" || return 1
    want="$(printf '%s' "$want" | sed "s/@FK_NEXT@/$fk_next/g; s/@FK@/$fk/g; s/@VP@/$vp/g; s/@EFFECT@/$effect/g; s/@VITE_NEXT@/^$((vite_major + 1)).0.0/g")"
    fk_node "$d" scripts/check-pins.mjs; rc=$?
    [ "$rc" = 1 ] || fail "check-pins exited $rc after: $bad" || return 1
    assert_contains "$d.node.out" "$want" || return 1
    assert_contains "$d.node.out" "check-pins: FAILED" || return 1
  done <<'CASES'
printf '0.1.0\n' > VERSION|package.json version "0.0.0" differs from VERSION 0.1.0
printf 'v1\n' > VERSION|VERSION must hold MAJOR.MINOR.PATCH
node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));p.devDependencies.vite="^"+p.devDependencies.vite;fs.writeFileSync("package.json",JSON.stringify(p,null,2)+"\n")'|vite must be pinned to an exact version, got "^
node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));fs.writeFileSync("package.json",JSON.stringify(p)+"\n")'|package.json is not in JSON.stringify(pkg, null, 2)
printf '{\n' > package.json|package.json is not valid JSON
printf '0.0.1\n' > .node-version|devEngines.runtime must be node at .node-version's exact version ("0.0.1")
node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));p.packageManager="pnpm@0.0.1";fs.writeFileSync("package.json",JSON.stringify(p,null,2)+"\n")'|and packageManager (pnpm@<same>) must agree
node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));p.devDependencies["@effect/vitest"]="0.0.1";fs.writeFileSync("package.json",JSON.stringify(p,null,2)+"\n")'|@effect/vitest 0.0.1 must match effect @EFFECT@
node -e 'const fs=require("fs");const f="node_modules/foldkit/package.json";const p=JSON.parse(fs.readFileSync(f));p.peerDependencies.effect="0.0.1";fs.writeFileSync(f,JSON.stringify(p))'|foldkit @FK@ needs effect 0.0.1, package.json pins @EFFECT@
node -e 'const fs=require("fs");const f="node_modules/foldkit/package.json";const p=JSON.parse(fs.readFileSync(f));p.version=process.env.FK_NEXT;fs.writeFileSync(f,JSON.stringify(p))'|node_modules has foldkit @FK_NEXT@, package.json pins @FK@: run pnpm install
node -e 'const fs=require("fs");const f="node_modules/effect/package.json";const p=JSON.parse(fs.readFileSync(f));p.version="0.0.1";fs.writeFileSync(f,JSON.stringify(p))'|node_modules has effect 0.0.1, package.json pins @EFFECT@: run pnpm install (if it stays, pnpm-lock.yaml holds the other version: regenerate it)
node -e 'const fs=require("fs");const f="node_modules/typescript/package.json";const p=JSON.parse(fs.readFileSync(f));p.version="0.0.1";fs.writeFileSync(f,JSON.stringify(p))'|node_modules has typescript 0.0.1, package.json pins
rm -rf node_modules/foldkit|node_modules is missing foldkit: run pnpm install
rm -rf node_modules/@foldkit/devtools-mcp|node_modules is missing @foldkit/devtools-mcp: run pnpm install
rm -rf node_modules/effect node_modules/vitest|node_modules is missing effect, vitest: run pnpm install
node -e 'const fs=require("fs");const f="node_modules/@foldkit/vite-plugin/package.json";const p=JSON.parse(fs.readFileSync(f));p.peerDependencies.foldkit=">="+process.env.FK_NEXT;fs.writeFileSync(f,JSON.stringify(p))'|@foldkit/vite-plugin @VP@ needs foldkit >=@FK_NEXT@, package.json pins @FK@
node -e 'const fs=require("fs");const f="node_modules/@foldkit/vite-plugin/package.json";const p=JSON.parse(fs.readFileSync(f));p.peerDependencies.vite=process.env.VITE_NEXT;fs.writeFileSync(f,JSON.stringify(p))'|@foldkit/vite-plugin @VP@ needs vite @VITE_NEXT@
node -e 'const fs=require("fs");const f="node_modules/@foldkit/devtools-mcp/package.json";const p=JSON.parse(fs.readFileSync(f));p.peerDependencies.foldkit="~0.0";fs.writeFileSync(f,JSON.stringify(p))'|which check-pins cannot evaluate
node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));p.devDependencies["@foldkit/devtools"]=process.env.FK_NEXT;fs.writeFileSync("package.json",JSON.stringify(p,null,2)+"\n")'|@foldkit/devtools @FK_NEXT@ must equal foldkit @FK@
CASES
}
test_stack_foldkit_template_ci_matches_the_pack() {
  # The heavy job's pnpm is the version new projects pin, and both workflows pin
  # the same pnpm/setup commit.
  local want sha
  want="$(sed -n 's/.*"packageManager": "pnpm@\([0-9.]*\)".*/\1/p' "$REPO/template/stacks/foldkit/files/package.json")"
  [ -n "$want" ] || fail "no pnpm@ pin in the pack's package.json" || return 1
  grep -qF "version: \"$want\"" "$REPO/.github/workflows/template-selftest.yml" \
    || fail "template-selftest.yml's pnpm/setup is not pnpm $want" || return 1
  sha="$(sed -n 's/.*uses: pnpm\/setup@\([0-9a-f]\{40\}\).*/\1/p' "$REPO/template/stacks/foldkit/files/.github/workflows/ci.yml")"
  [ -n "$sha" ] || fail "the pack's ci.yml does not pin pnpm/setup by commit" || return 1
  grep -qF "pnpm/setup@$sha" "$REPO/.github/workflows/template-selftest.yml" \
    || fail "the two workflows pin different pnpm/setup commits"
}
test_heavy_stack_foldkit_project_is_green_on_first_run() {
  # The whole new-project gate, for real: bootstrap (its hook installs the pack's
  # locked tree, patching tsc, and vendors Foldkit), then check.sh, coverage.sh,
  # the Playwright journeys and the production build.
  local d="$WORK/heavy-foldkit/demo-app" why key f pw_deps=""
  why="$(foldkit_heavy_ready)"
  [ -z "$why" ] || { skip "$why"; return; }
  foldkit_project "$d" "Demo App" || return 1
  assert_contains "$d/package.json" '"name": "demo_app"' || return 1
  assert_contains "$d/package.json" '"description": "Demo App"' || return 1
  assert_contains "$d/src/build-info.ts" "export const PROJECT_NAME = 'Demo App'" || return 1
  assert_exists "$d/pnpm-lock.yaml" || return 1
  assert_exists "$d/.github/workflows/ci.yml" || return 1
  assert_absent "$d/.github/workflows/ci.yml.example" || return 1
  assert_absent "$d/template" || return 1
  assert_contains "$d/.bootstrapped" "with the foldkit stack pack" || return 1
  assert_contains "$d/TESTING.md" "Tests: \`pnpm exec vitest run\`" || return 1
  assert_contains "$d/CLAUDE.md" "docs/guides/foldkit.md" || return 1
  assert_contains "$d.out" "Installed the locked dependencies" || return 1
  cmp -s "$REPO/template/stacks/foldkit/files/pnpm-lock.yaml" "$d/pnpm-lock.yaml" || fail "the install changed the pack's lockfile" || return 1
  (cd "$d" && stack_env pnpm exec tsc --version) | grep -q '+effect-tsgo' || fail "tsc is not patched after bootstrap" || return 1
  [ "$(cat "$d/repos/foldkit/.vendored-version" 2>/dev/null)" = "$(node -p 'require(process.argv[1]).dependencies.foldkit' "$d/package.json")" ] \
    || fail "repos/foldkit is not the pinned release: $(tail -5 "$d.out")" || return 1
  [ -z "$(find "$d/repos/foldkit" \( -name AGENTS.md -o -name CLAUDE.md -o -name .mcp.json -o -name .claude -o -name .agents -o -path "$d/repos/foldkit/repos" \) -print)" ] \
    || fail "the vendored Foldkit carries agent files or its Effect copy" || return 1
  (cd "$d" && git add -A && git commit -qm init) || fail "commit failed" || return 1
  # No placeholder survives in what git commits (node_modules and repos/ are ignored).
  for key in $(sed -n 's/^\([A-Z_]*\)=.*/\1/p' "$REPO/template/stacks/foldkit/commands") PROJECT_NAME PACKAGE_NAME YEAR; do
    ! (cd "$d" && git grep -qF "{{$key") || fail "{{$key is left in: $(cd "$d" && git grep -lF "{{$key" | tr '\n' ' ')" || return 1
  done
  # git commits every pack file and ignores every build artifact.
  git -C "$REPO" ls-files --cached --others --exclude-standard -- template/stacks/foldkit/files \
    | sed 's|^template/stacks/foldkit/files/||' > "$d.expected" || return 1
  while IFS= read -r f; do
    git -C "$d" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || fail "git would not commit $f" || return 1
  done < "$d.expected"
  for f in node_modules/x dist/index.html coverage/coverage-summary.json test-results/x playwright-report/index.html \
    blob-report/x tsconfig.tsbuildinfo repos/foldkit/README.md; do
    git -C "$d" check-ignore -q -- "$f" || fail "git would commit the build artifact $f" || return 1
  done
  [ "${CI:-}" != "true" ] || pw_deps="--with-deps"
  (cd "$d" && stack_env env EDITORCONFIG_CHECKER_BIN=/nonexistent ./scripts/check.sh \
    && stack_env ./scripts/coverage.sh \
    && stack_env pnpm exec playwright install $pw_deps chromium \
    && stack_env pnpm exec playwright test \
    && stack_env pnpm build) >"$d.gate.out" 2>&1 \
    || fail "the new project's own gate failed: $(tail -25 "$d.gate.out")" || return 1
  assert_contains "$d.gate.out" "OK: checks passed." || return 1
  assert_contains "$d.gate.out" "coverage-tiers: ok" || return 1
  assert_contains "$d.gate.out" "1 passed" || return 1
  [ -z "$(git -C "$d" status --porcelain)" ] || fail "the gate left files git would commit: $(git -C "$d" status --porcelain | head -5)"
}
test_heavy_stack_foldkit_longest_name_passes_guards_and_tests() {
  # 50 characters, the most validate-name allows: Oxfmt must accept
  # src/build-info.ts as bootstrap wrote it, and the tests must pass.
  local d="$WORK/heavy-foldkit-long/proj" name="Acme Example Inventory Reconciliation Service Ok12" why
  why="$(foldkit_heavy_ready)"
  [ -z "$why" ] || { skip "$why"; return; }
  [ "${#name}" = 50 ] || fail "the test name is ${#name} characters, not 50" || return 1
  foldkit_project "$d" "$name" || return 1
  (cd "$d" && stack_env bash scripts/check.d/foldkit.sh && stack_env pnpm exec vitest run) \
    >"$d.gate.out" 2>&1 || fail "the foldkit guards or tests failed: $(tail -25 "$d.gate.out")"
}
test_heavy_stack_foldkit_version_bump_keeps_the_gate_green() {
  # gstack /ship writes VERSION and package.json's version (as
  # JSON.stringify(p, null, 2) + "\n"). The lockfile holds neither, so the frozen
  # install still passes, the guards pass, and the build shows the new version.
  local d="$WORK/heavy-foldkit-bump/demo" why
  why="$(foldkit_heavy_ready)"
  [ -z "$why" ] || { skip "$why"; return; }
  foldkit_project "$d" demo || return 1
  printf '0.1.0\n' > "$d/VERSION"
  fk_json "$d/package.json" 'c.version = "0.1.0"' || return 1
  (cd "$d" && stack_env pnpm install --frozen-lockfile && stack_env bash scripts/check.d/foldkit.sh \
    && stack_env pnpm build) >"$d.gate.out" 2>&1 || fail "the gate failed after a version bump: $(tail -25 "$d.gate.out")" || return 1
  cmp -s "$REPO/template/stacks/foldkit/files/pnpm-lock.yaml" "$d/pnpm-lock.yaml" || fail "the bump changed pnpm-lock.yaml" || return 1
  grep -qF '0.1.0' "$d"/dist/assets/*.js || fail "the build does not carry VERSION 0.1.0"
}
test_heavy_stack_foldkit_guards_fail_closed() {
  # Each guard fails closed on the change it exists to stop, and passes again
  # once the change is reverted.
  local d="$WORK/heavy-foldkit-guards/demo" why rc
  why="$(foldkit_heavy_ready)"
  [ -z "$why" ] || { skip "$why"; return; }
  foldkit_project "$d" demo || return 1
  (cd "$d" && git add -A && git commit -qm init) || fail "commit failed" || return 1
  guard() { (cd "$d" && stack_env bash scripts/check.d/foldkit.sh) >"$d.guard.out" 2>&1; }
  guard || fail "the guard failed on a fresh project: $(tail -20 "$d.guard.out")" || return 1
  expect_guard_failure() {  # $1 = text the failure must contain, $2 = what changed
    guard; rc=$?
    [ "$rc" -ne 0 ] || fail "the guard passed after: $2" || return 1
    assert_contains "$d.guard.out" "$1" || return 1
    (cd "$d" && git checkout -q -- . && git clean -qfd -e node_modules -e repos) || return 1
  }
  perl -pi -e 's/^\/\/ UPDATE$/export const now = () => Date.now()\n\n\/\/ UPDATE/' "$d/src/main.ts" || return 1
  expect_guard_failure "effect(globalDate)" "Date.now() in src/main.ts" || return 1
  printf "import { Command } from 'foldkit'\n\nexport const leak = Command\n" > "$d/src/domain/leak.ts"
  expect_guard_failure "src/domain and src/api must not import foldkit" "a foldkit import in src/domain" || return 1
  printf "import { vi } from 'vitest'\n\nvi.mock('./main')\n" > "$d/src/mocked.test.ts"
  expect_guard_failure "no vi.mock" "vi.mock( in a test" || return 1
  perl -pi -e 's/foldkit\((?:\{ devToolsMcpPort: false \})?\)/foldkit({ devToolsMcpPort: 9988 })/' "$d/vite.config.ts" || return 1
  grep -q 'devToolsMcpPort: 9988' "$d/vite.config.ts" || fail "the devToolsMcpPort mutation did not apply" || return 1
  expect_guard_failure "unauthenticated DevTools relay" "a numeric devToolsMcpPort in vite.config.ts" || return 1
  printf '{"mcpServers":{"foldkit-devtools":{"command":"npx","args":["-y","@foldkit/devtools-mcp"]}}}\n' > "$d/.mcp.json"
  expect_guard_failure ".mcp.json must call the pinned local bin" "npx in .mcp.json" || return 1
  fk_json "$d/package.json" 'c.version = "0.2.0"' || return 1
  expect_guard_failure "differs from VERSION" "package.json version drift" || return 1
  fk_json "$d/package.json" 'c.devDependencies.vitest = "^" + c.devDependencies.vitest' || return 1
  expect_guard_failure "vitest must be pinned to an exact version" "a caret range" || return 1
  node -e 'const fs=require("fs");fs.writeFileSync(process.argv[1],JSON.stringify(JSON.parse(fs.readFileSync(process.argv[1],"utf8")),null,4)+"\n")' "$d/package.json" || return 1
  expect_guard_failure "package.json is not in JSON.stringify" "a reformatted package.json" || return 1
  fk_json "$d/package.json" 'c.devDependencies["is-number"] = "7.0.0"' || return 1
  expect_guard_failure "node_modules is missing is-number: run pnpm install" "a dependency added without installing it" || return 1
  perl -0pi -e 's/(\n      vitest:\n        specifier: )[^\n]+/${1}0.0.1/' "$d/pnpm-lock.yaml" || return 1
  grep -q 'specifier: 0.0.1' "$d/pnpm-lock.yaml" || fail "the lockfile mutation did not apply" || return 1
  expect_guard_failure "pnpm-lock.yaml is missing or out of date" "a lockfile that no longer matches package.json" || return 1
  (cd "$d" && stack_env pnpm exec effect-tsgo unpatch) >"$d.unpatch.out" 2>&1 || fail "unpatch failed: $(cat "$d.unpatch.out")" || return 1
  expect_guard_failure "tsc is not patched by @effect/tsgo" "an unpatched tsc" || return 1
  (cd "$d" && stack_env pnpm exec effect-tsgo patch) >"$d.unpatch.out" 2>&1 || fail "re-patching failed: $(cat "$d.unpatch.out")" || return 1
  (cd "$d" && env PATH=/usr/bin:/bin /bin/bash scripts/check.d/foldkit.sh) >"$d.guard.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard.out" "pnpm is not installed" || return 1
  # A locked package that pnpm's supply-chain policy rejects (an impossible age rule
  # stands in for a release under 24 hours old) is reported as that, with the
  # packages named, not as a stale lockfile. The install stays usable: the plain
  # guard passes right after.
  (cd "$d" && stack_env env pnpm_config_minimum_release_age=5256000 bash scripts/check.d/foldkit.sh) >"$d.guard.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard.out" "pnpm's supply-chain policy (pnpm-workspace.yaml) rejects a locked package" || return 1
  assert_contains "$d.guard.out" "within the minimumReleaseAge cutoff" || return 1
  assert_not_contains "$d.guard.out" "pnpm-lock.yaml is missing or out of date" || return 1
  assert_not_contains "$d.guard.out" "relax the policy" || return 1
  guard || fail "the guard failed after the mutations were reverted: $(tail -20 "$d.guard.out")" || return 1
  # Coverage: an untested module fails the global floor and is named; a tier member
  # that coverage can't measure fails its tier.
  printf 'export const pick = (flag: boolean): number => {\n  if (flag) {\n    return 1\n  }\n  return 2\n}\n' > "$d/src/domain/extra.ts"
  (cd "$d" && stack_env bash scripts/coverage.sh) >"$d.cov.out" 2>&1; rc=$?
  rm -f "$d/src/domain/extra.ts"
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.cov.out" "src/domain/extra.ts" || return 1
  # Five lines keep the global line floor (50/54); its branches fail it, by name.
  assert_contains "$d.cov.out" "coverage-tiers: FAIL global: branches" || return 1
  printf 'export type Shape = { readonly name: string }\n' > "$d/src/domain/shape.ts"
  fk_json "$d/coverage-tiers.json" 'c.tiers.pure_logic.include.push("src/domain/shape.ts")' || return 1
  (cd "$d" && stack_env bash scripts/coverage.sh) >"$d.cov.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.cov.out" "pure_logic: src/domain/shape.ts" || return 1
  (cd "$d" && git checkout -q -- . && rm -f src/domain/shape.ts) || return 1
  # The ratchet against the committed state.
  fk_json "$d/coverage-tiers.json" 'c.tiers.main_components.minimum = 80' || return 1
  (cd "$d" && node scripts/coverage-tiers.mjs --ratchet HEAD) >"$d.ratchet.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.ratchet.out" "main_components: minimum lowered from 90 to 80" || return 1
  (cd "$d" && git checkout -q -- coverage-tiers.json) || return 1
  fk_json "$d/coverage-tiers.json" 'c.tiers.main_components.include = ["src/view.ts"]' || return 1
  (cd "$d" && node scripts/coverage-tiers.mjs --ratchet HEAD) >"$d.ratchet.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.ratchet.out" "existing members removed since HEAD" || return 1
  (cd "$d" && git checkout -q -- coverage-tiers.json) || return 1
}
````

### Step 2: Create the foldkit pack exactly as rehearsed, and give the template's CI Node and pnpm

1. Run `bash .context/plan-011/step-2.sh`. It writes the 43 files embedded below (paths are
   relative to `template/stacks/foldkit/`), checks each against `pack.sha256`, makes the five
   scripts executable, and downloads `FOLDKIT.md` from Foldkit's `foldkit@0.165.0` release tag,
   checking its hash. Expect 44 lines ending in `OK` and then
   `step-2: wrote 44 files under template/stacks/foldkit`. A line that says `FAILED`, or any
   error, is a STOP condition. (The 45th file, `pnpm-lock.yaml`, comes in step 3.)
2. In `.github/workflows/template-selftest.yml`, give the light tests Node and the heavy tests
   pnpm (the test `test_stack_foldkit_template_ci_matches_the_pack` checks the second against
   the pack). Make both edits by hand. In the `selftest` job, directly above the step
   `- name: Lint shell scripts`, add this step, followed by a blank line:

```yaml
      - name: Node for the foldkit stack-pack tests (its coverage-tier and pin checkers)
        uses: actions/setup-node@v7
        with:
          node-version: "24"
```

   In the `heavy` job, directly above its last step, `- name: Heavy stack-pack self-tests`, add
   this step, followed by a blank line:

```yaml
      - name: pnpm for the foldkit pack's projects (the tests install their own Node)
        uses: pnpm/setup@fbda4c85fc2e1e08721cd8763afea8f48d60f024 # v3.0.0
        with:
          version: "12.6.0"
          install: false
```

   Keep the six-space indentation shown. The template's own workflow may use `${{ }}`; the pack's
   `ci.yml` may not.

**Verify**:

- `./scripts/template-selftest.sh stack_foldkit` → 5 passed, 4 skipped.
- `./scripts/template-selftest.sh carry_only_bootstrap_owned_tokens` → 1 passed.
- `./bootstrap --help` → lists `foldkit` with its description.
- The Shell lint command and the YAML command → exit 0.
- Both workflow steps are where they belong. This one command must print `workflow ok`:

```sh
ruby -ryaml -e 'w = YAML.load_file(".github/workflows/template-selftest.yml"); s = w["jobs"]["selftest"]["steps"].map { |x| x["name"].to_s }; h = w["jobs"]["heavy"]["steps"].map { |x| x["name"].to_s }; i = s.index { |n| n.start_with?("Node for the foldkit") }; j = h.index { |n| n.start_with?("pnpm for the foldkit") }; abort "workflow: a foldkit step is missing or misplaced" unless i && s[i + 1] == "Lint shell scripts" && j && h[j + 1] == "Heavy stack-pack self-tests"; puts "workflow ok"'
```

- `git status --short` → the workflow modified and `template/stacks/foldkit/` new (plus
  `scripts/template-selftest.sh` modified if you have not committed step 1 yet), nothing else.

The 43 embedded files follow. They are data for `step-2.sh`: there is nothing to do in them.
Step 3 starts after the last one, `files/docs/guides/foldkit.md` (search for `### Step 3`).


`description`:

````text
Browser app, Elm-style: Foldkit on Effect v4, TypeScript 7, Vite 8, Vitest 5, Playwright
````

`commands`:

````text
# KEY=value lines. ./bootstrap --stack foldkit replaces {{KEY}} and {{KEY: description}}
# placeholders in the project's docs with these values.
INSTALL_CMD=pnpm install
DEV_CMD=pnpm dev
BUILD_CMD=pnpm build
CHECK_CMD=./scripts/check.sh
TEST_CMD=pnpm exec vitest run
SHIP_GATE=./scripts/check.sh && ./scripts/coverage.sh && pnpm exec playwright test
STACK=Foldkit (the Elm architecture on Effect v4) in the browser; TypeScript 7 with the Effect language service (patched tsc); Vite 8; Vitest 5 Story/Scene tests; Playwright journeys; Oxlint (type-aware) and Oxfmt; pnpm 12 on Node 24.
COVERAGE_ENFORCEMENT=./scripts/coverage.sh: vitest --coverage (v8, json-summary), then scripts/coverage-tiers.mjs independently enforces 90% lines and 90% branches globally plus per-tier line, branch and function floors from coverage-tiers.json; tier members missing from the report fail; fail-closed in CI, with a ratchet on pull requests
RELEVANT_DOCS=docs/guides/foldkit.md, FOLDKIT.md (Foldkit's conventions; Foldkit owns it), the vendored Foldkit source in repos/foldkit (scripts/vendor-foldkit.sh), ENGINEERING.md and TESTING.md
````

`gitignore`:

````text
# --- JavaScript / TypeScript (pnpm, Vite, Vitest, Playwright) ---
node_modules/
dist/
coverage/
test-results/
playwright-report/
blob-report/
*.tsbuildinfo
# Read-only Foldkit reference, re-created by scripts/vendor-foldkit.sh
/repos/foldkit/
````

`validate-name`:

````sh
#!/bin/sh
# Reject names a foldkit project can't use, before bootstrap writes anything.
# $1 is the package name (package.json "name"), $2 the project name.
# node_modules is reserved by Node.js.
# Then the pack's direct dependencies without a scope or hyphen (the only ones
# a normalized package name can equal). pnpm installs such a project, but tools
# that find packages by name see two: named `effect`, the Effect language
# service reports a duplicate package on every file and tsc fails.
# Last, the length: src/build-info.ts holds
# `export const PROJECT_NAME = '<name>'`, and past 50 characters Oxfmt's 80
# columns wrap it, so the first `oxfmt --check` fails.
if [ "$1" = node_modules ]; then
  echo "Package name 'node_modules' is reserved by Node.js; choose another project name." >&2
  exit 2
fi
for taken in effect foldkit oxfmt oxlint playwright typescript vite vitest; do
  [ "$1" = "$taken" ] || continue
  echo "Package name '$1' is taken by a package the foldkit pack depends on; choose another project name." >&2
  exit 2
done
if [ ${#2} -gt 50 ]; then
  echo "Project name is too long for the foldkit stack pack (50 characters at most): '$2'" >&2
  exit 2
fi
````

`after-bootstrap`:

````sh
#!/bin/sh
# Runs once at the end of ./bootstrap --stack foldkit, from the project root.
# 1. Install the reviewed dependency tree from the pack's pnpm-lock.yaml. The
#    root `prepare` script runs `effect-tsgo patch`, so tsc enforces the Effect
#    rules from the first check.
# 2. Vendor Foldkit's source into repos/foldkit (gitignored) for agents.
# Both need the network; bootstrap finishes either way.
if ! command -v pnpm >/dev/null 2>&1; then
  echo "pnpm not found: install pnpm 12 (https://pnpm.io/installation), then run 'pnpm install'."
elif pnpm install --frozen-lockfile; then
  echo "Installed the locked dependencies (tsc is patched by @effect/tsgo)."
else
  echo "pnpm install failed (see above; offline?): run 'pnpm install --frozen-lockfile' before your first commit."
fi
if command -v git >/dev/null 2>&1 && command -v node >/dev/null 2>&1 && bash scripts/vendor-foldkit.sh; then
  :
else
  echo "Vendoring Foldkit failed (offline?): run 'bash scripts/vendor-foldkit.sh' later; ./scripts/check.sh warns until you do."
fi
echo "Once per machine, for the E2E journeys: pnpm exec playwright install chromium"
````

`files/package.json`:

````json
{
  "name": "{{PACKAGE_NAME}}",
  "version": "0.0.0",
  "description": "{{PROJECT_NAME}}",
  "private": true,
  "type": "module",
  "packageManager": "pnpm@12.6.0",
  "devEngines": {
    "runtime": {
      "name": "node",
      "version": "24.21.0",
      "onFail": "download"
    },
    "packageManager": {
      "name": "pnpm",
      "version": "12.6.0",
      "onFail": "download"
    }
  },
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "prepare": "effect-tsgo patch"
  },
  "dependencies": {
    "@effect/platform-browser": "4.0.0",
    "effect": "4.0.0",
    "foldkit": "0.165.0"
  },
  "devDependencies": {
    "@effect/tsgo": "0.45.0",
    "@effect/vitest": "4.0.0",
    "@foldkit/devtools": "0.165.0",
    "@foldkit/devtools-mcp": "0.24.0",
    "@foldkit/oxlint-plugin": "0.15.1",
    "@foldkit/vite-plugin": "0.26.0",
    "@playwright/test": "1.63.0",
    "@vitest/coverage-v8": "5.0.1",
    "happy-dom": "20.14.5",
    "oxfmt": "0.70.0",
    "oxlint": "1.85.0",
    "oxlint-tsgolint": "7.0.2003",
    "typescript": "7.0.2",
    "vite": "8.3.1",
    "vitest": "5.0.1"
  }
}
````

`files/pnpm-workspace.yaml`:

````yaml
# Supply-chain policy for every install (pnpm 12). Keep these explicit even
# where they match pnpm's defaults: an upgrade must not silently loosen them.
minimumReleaseAge: 1440
trustPolicy: no-downgrade
strictDepBuilds: true
blockExoticSubdeps: true
allowBuilds: {}
````

`files/.node-version`:

````text
24.21.0
````

`files/tsconfig.json`:

````json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "lib": ["ESNext", "DOM", "DOM.Iterable"],
    "moduleResolution": "bundler",
    "types": ["vite/client"],
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "verbatimModuleSyntax": true,
    "erasableSyntaxOnly": true,
    "noImplicitOverride": true,
    "skipLibCheck": false,
    "noEmit": true,
    "plugins": [
      {
        "name": "@effect/language-service",
        "diagnosticSeverity": {
          "outdatedApi": "error",
          "floatingEffect": "error",
          "floatingEffectInVitest": "error",
          "obsoleteSchemaImport": "error"
        },
        "overrides": [
          {
            "include": ["src/**/*.ts"],
            "exclude": ["src/**/*.test.ts"],
            "options": {
              "diagnosticSeverity": {
                "outdatedApi": "error",
                "floatingEffect": "error",
                "floatingEffectInVitest": "error",
                "obsoleteSchemaImport": "error",
                "globalDate": "error",
                "globalDateInEffect": "error",
                "globalRandom": "error",
                "globalRandomInEffect": "error",
                "globalFetch": "error",
                "globalFetchInEffect": "error",
                "globalTimers": "error",
                "globalTimersInEffect": "error",
                "processEnv": "error",
                "processEnvInEffect": "error"
              }
            }
          }
        ]
      }
    ]
  },
  "include": [
    "src",
    "e2e",
    "vite.config.ts",
    "vitest.config.ts",
    "playwright.config.ts"
  ]
}
````

`files/vite.config.ts`:

````ts
import { defineConfig } from 'vite'

import { foldkit } from '@foldkit/vite-plugin'

// The DevTools MCP relay stays off (docs/guides/foldkit.md). A numeric
// devToolsMcpPort opens an unauthenticated relay on every network interface,
// so check.sh refuses one.
export default defineConfig({
  plugins: [foldkit({ devToolsMcpPort: false })],
  optimizeDeps: {
    entries: ['src/entry.ts'],
  },
  server: {
    port: 3000,
    strictPort: true,
    watch: { ignored: ['**/repos/**'] },
  },
  preview: { port: 4000, strictPort: true },
})
````

`files/vitest.config.ts`:

````ts
import { defineConfig } from 'vitest/config'

// Coverage has no thresholds here on purpose: scripts/coverage-tiers.mjs
// enforces the floors, because Vitest passes a tier glob that matches nothing.
export default defineConfig({
  test: {
    include: ['src/**/*.test.ts'],
    environment: 'happy-dom',
    setupFiles: ['./src/vitest-setup.ts'],
    server: {
      deps: {
        inline: ['foldkit', '@foldkit/devtools'],
      },
    },
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
      exclude: [
        'src/entry.ts',
        'src/vitest-setup.ts',
        'src/**/*.test.ts',
        'src/**/*.d.ts',
      ],
      reporter: ['text', 'json-summary'],
    },
  },
})
````

`files/playwright.config.ts`:

````ts
import { defineConfig, devices } from '@playwright/test'

// The named journeys (TESTING.md tier 4) run against the production build,
// served by `vite preview` on 4000 (strictPort: a busy port fails the run).
// Not `pnpm build && pnpm preview`: under pnpm 12.6 that server outlived
// Playwright's shutdown and the run hung after the tests passed.
export default defineConfig({
  testDir: 'e2e',
  forbidOnly: true,
  retries: 0,
  use: { baseURL: 'http://localhost:4000' },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: 'vite build && vite preview',
    url: 'http://localhost:4000',
    reuseExistingServer: false,
  },
})
````

`files/.oxlintrc.json`:

````json
{
  "$schema": "./node_modules/oxlint/configuration_schema.json",
  "extends": [
    "./node_modules/@foldkit/oxlint-plugin/recommended.json"
  ],
  "plugins": [
    "typescript",
    "oxc",
    "import"
  ],
  "options": {
    "typeAware": true
  },
  "categories": {
    "correctness": "error",
    "suspicious": "error"
  },
  "rules": {
    "no-unused-vars": [
      "error",
      {
        "argsIgnorePattern": "^_",
        "varsIgnorePattern": "^_",
        "caughtErrorsIgnorePattern": "^_",
        "destructuredArrayIgnorePattern": "^_"
      }
    ],
    "eslint/require-yield": "off",
    "typescript/no-explicit-any": "error",
    "typescript/consistent-type-assertions": [
      "error",
      {
        "assertionStyle": "never"
      }
    ],
    "typescript/no-floating-promises": "error",
    "typescript/no-misused-promises": "error",
    "typescript/await-thenable": "error",
    "typescript/switch-exhaustiveness-check": "error",
    "eslint/no-underscore-dangle": "off",
    "import/no-unassigned-import": [
      "error",
      {
        "allow": [
          "**/*.css"
        ]
      }
    ]
  },
  "overrides": [
    {
      "files": [
        "src/**/*.test.ts",
        "e2e/**/*.ts"
      ],
      "rules": {
        "eslint/no-shadow": "off"
      }
    }
  ],
  "ignorePatterns": [
    "node_modules/**",
    "dist/**",
    "coverage/**",
    "repos/**",
    "test-results/**",
    "playwright-report/**",
    "blob-report/**",
    "**/*.d.ts"
  ]
}
````

`files/.oxfmtrc.json`:

````json
{
  "$schema": "./node_modules/oxfmt/configuration_schema.json",
  "semi": false,
  "singleQuote": true,
  "arrowParens": "avoid",
  "trailingComma": "all",
  "printWidth": 80,
  "sortImports": {
    "ignoreCase": false,
    "customGroups": [
      { "groupName": "scoped", "elementNamePattern": ["@*", "@*/**"] }
    ],
    "groups": [
      ["builtin", "external"],
      "scoped",
      ["parent", "sibling", "index"],
      "unknown"
    ]
  },
  "sortPackageJson": false,
  "ignorePatterns": [
    "node_modules",
    "dist",
    "coverage",
    "repos",
    "test-results",
    "playwright-report",
    "blob-report",
    "*.tsbuildinfo",
    "pnpm-lock.yaml",
    "package.json",
    "**/*.md"
  ]
}
````

`files/.ignore`:

````text
repos/
````

`files/index.html`:

````html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>{{PROJECT_NAME}}</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="./src/entry.ts"></script>
  </body>
</html>
````

`files/public/status.json`:

````json
{"status":"ok","checkedAt":"2026-09-25T00:00:00Z"}
````

`files/coverage-tiers.json`:

````json
{
  "tiers": {
    "pure_logic": {
      "title": "Pure logic & utilities",
      "minimum": 100,
      "target": 100,
      "include": ["src/domain/version.ts", "src/main.ts"]
    },
    "api_surface": {
      "title": "API / contract surface",
      "minimum": 100,
      "target": 100,
      "include": ["src/api/status.ts", "src/command.ts"]
    },
    "main_components": {
      "title": "Main UI components",
      "minimum": 90,
      "target": 90,
      "include": ["src/view.ts", "src/components/status.ts"]
    }
  },
  "journeys": ["home renders the project name, version and status"]
}
````

`files/.github/workflows/ci.yml`:

````yaml
# CI for {{PROJECT_NAME}} (vibe-starter foldkit stack pack): guards, then tests
# with the 90% line and branch floors from TESTING.md, then the E2E journeys.
name: ci

on:
  push:
    branches: [main, master]
  pull_request:

permissions:
  contents: read

jobs:
  check-and-test:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7

      - name: Install gitleaks
        uses: ./.github/actions/install-gitleaks

      - name: Install Node and pnpm (from devEngines), then the locked dependencies
        uses: pnpm/setup@fbda4c85fc2e1e08721cd8763afea8f48d60f024 # v3.0.0
        with:
          require-lockfile: true

      - name: Checks (guards run before tests)
        run: ./scripts/check.sh

      - name: Tests with the coverage gates (90% line+branch floor, then per-tier)
        run: ./scripts/coverage.sh

      - name: Install Chromium for the E2E journeys
        run: pnpm exec playwright install --with-deps chromium

      - name: E2E journeys (Playwright, against the production build)
        run: pnpm exec playwright test

      - name: Coverage tiers never slip (pull requests)
        if: github.event_name == 'pull_request'
        run: |
          git fetch --depth=1 origin "$GITHUB_BASE_REF"
          node scripts/coverage-tiers.mjs --ratchet "origin/$GITHUB_BASE_REF"
````

`files/scripts/coverage.sh`:

````sh
#!/usr/bin/env bash
# Coverage gate (TESTING.md): the 90% line and branch floors, then the per-tier
# gates, enforced by scripts/coverage-tiers.mjs. CI runs this. Plain
# `pnpm exec vitest run` skips coverage on purpose (fast, gate-free).
set -euo pipefail
CDPATH='' cd -- "$(dirname -- "$0")/.."   # a CDPATH entry must not pick the directory
rm -rf coverage
pnpm exec vitest run --coverage
node scripts/coverage-tiers.mjs --check
````

`files/scripts/coverage-tiers.mjs`:

````js
#!/usr/bin/env node
// Independent global and tier coverage gates; Node standard library only (TESTING.md).
//
// Config lives in coverage-tiers.json: tiers (explicit src/**/*.ts members) and the
// named E2E journeys. Empty tiers require allow_empty. A metric with nothing to
// measure (total 0) is n/a. --ratchet REF forbids lowering floors or targets and
// removing tiers or members; renaming, moving or deleting a member means listing
// its old path in the tier's `retired`.
//
//   node scripts/coverage-tiers.mjs --validate          # config only (before tests)
//   node scripts/coverage-tiers.mjs --check             # after vitest --coverage
//   node scripts/coverage-tiers.mjs --report            # markdown snapshot table
//   node scripts/coverage-tiers.mjs --ratchet origin/main
//   ... --input coverage/coverage-summary.json          # the default
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, readdirSync, realpathSync, statSync } from 'node:fs'
import { dirname, join, relative, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const CONFIG = 'coverage-tiers.json'
const GLOBAL_MINIMUM = 90
const METRICS = ['lines', 'branches', 'functions']
const GLOBAL_METRICS = ['lines', 'branches']
const TIER_KEYS = new Set(['title', 'minimum', 'target', 'include', 'allow_empty', 'retired'])
const TOP_KEYS = new Set(['tiers', 'journeys'])

const isObject = value => typeof value === 'object' && value !== null && !Array.isArray(value)
const isNumber = value => typeof value === 'number' && Number.isFinite(value)
const own = (object, key) => Object.prototype.hasOwnProperty.call(object, key)

export const validPath = path =>
  typeof path === 'string' &&
  path.startsWith('src/') &&
  path.endsWith('.ts') &&
  !path.endsWith('.d.ts') &&
  !path.endsWith('.test.ts') &&
  !path.includes('\\') &&
  path.split('/').every(part => part !== '' && part !== '.' && part !== '..')

const insideRoot = path => {
  try {
    const real = realpathSync(join(ROOT, path))
    const root = realpathSync(ROOT)
    return statSync(real).isFile() && real.startsWith(root + sep)
  } catch {
    return false
  }
}

const specFiles = dir => {
  if (!existsSync(dir)) {
    return []
  }
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) {
      return specFiles(path)
    }
    return entry.isFile() && entry.name.endsWith('.spec.ts') ? [path] : []
  })
}

// Titles of plain test('...') calls: test.skip/fixme/only do not count as journeys.
export const journeyTitles = () => {
  const titles = new Set()
  const call = /(?<![.\w])test\(\s*(['"])((?:\\.|(?!\1)[^\\\n])*)\1/g
  for (const file of specFiles(join(ROOT, 'e2e'))) {
    for (const match of readFileSync(file, 'utf8').matchAll(call)) {
      titles.add(match[2].replace(/\\(.)/g, '$1'))
    }
  }
  return titles
}

export const validate = (config, { checkFiles = true } = {}) => {
  if (!isObject(config)) {
    return ['coverage-tiers.json must be an object with tiers and journeys']
  }
  const errors = []
  const unknown = Object.keys(config).filter(key => !TOP_KEYS.has(key))
  if (unknown.length > 0) {
    errors.push(`unknown top-level keys: ${JSON.stringify(unknown.toSorted())}`)
  }
  const tiers = config.tiers
  if (!isObject(tiers) || Object.keys(tiers).length === 0) {
    errors.push('tiers must be a nonempty object')
  } else {
    const owner = new Map()
    for (const [key, tier] of Object.entries(tiers)) {
      if (key === 'global') {
        errors.push('global is reserved for the global floor, not a tier name')
      }
      if (!isObject(tier)) {
        errors.push(`${key}: tier must be an object`)
        continue
      }
      const extra = Object.keys(tier).filter(name => !TIER_KEYS.has(name))
      if (extra.length > 0) {
        errors.push(`${key}: unknown tier keys: ${JSON.stringify(extra.toSorted())}`)
      }
      if (!isNumber(tier.minimum) || !isNumber(tier.target)) {
        errors.push(`${key}: minimum and target must be finite numbers`)
      } else if (!(tier.minimum >= 0 && tier.minimum <= tier.target && tier.target <= 100)) {
        errors.push(`${key}: need 0 <= minimum <= target <= 100`)
      }
      if (typeof tier.title !== 'string' || tier.title.trim() === '') {
        errors.push(`${key}: title must be a nonempty string`)
      }
      if (own(tier, 'allow_empty') && typeof tier.allow_empty !== 'boolean') {
        errors.push(`${key}: allow_empty must be boolean`)
      }
      const members = tier.include
      let retired = own(tier, 'retired') ? tier.retired : []
      if (!Array.isArray(retired)) {
        errors.push(`${key}: retired must be an array`)
        retired = []
      }
      const seen = new Set()
      for (const path of retired) {
        if (!validPath(path)) {
          errors.push(`${key}: retired must name canonical src/**/*.ts files: ${JSON.stringify(path)}`)
        } else if (seen.has(path) || (Array.isArray(members) && members.includes(path))) {
          errors.push(`${key}: ${path} is listed twice across include and retired`)
        } else {
          seen.add(path)
        }
      }
      if (!Array.isArray(members)) {
        errors.push(`${key}: include must be an explicit array`)
        continue
      }
      if (members.length === 0 && tier.allow_empty !== true) {
        errors.push(`${key}: empty include requires allow_empty: true`)
      }
      for (const path of members) {
        if (!validPath(path)) {
          errors.push(`${key}: include must name canonical src/**/*.ts files (no tests or .d.ts): ${JSON.stringify(path)}`)
          continue
        }
        if (checkFiles && !insideRoot(path)) {
          errors.push(`${key}: include ${JSON.stringify(path)} is not a file within the project`)
        }
        if (owner.has(path)) {
          errors.push(`${path}: duplicate membership in ${JSON.stringify(owner.get(path))} and ${JSON.stringify(key)}`)
        }
        owner.set(path, key)
      }
    }
  }
  const journeys = config.journeys
  if (!Array.isArray(journeys) || journeys.length === 0) {
    errors.push('journeys must be a nonempty array of Playwright test titles')
  } else {
    const titles = checkFiles ? journeyTitles() : new Set()
    const seen = new Set()
    for (const journey of journeys) {
      if (typeof journey !== 'string' || journey.trim() === '') {
        errors.push(`journeys: each must be a nonempty string: ${JSON.stringify(journey)}`)
      } else if (seen.has(journey)) {
        errors.push(`journeys: ${JSON.stringify(journey)} is listed twice`)
      } else {
        seen.add(journey)
        if (checkFiles && !titles.has(journey)) {
          errors.push(`journeys: no test(${JSON.stringify(journey)}) in e2e/**/*.spec.ts`)
        }
      }
    }
  }
  return errors
}

const counters = (entry, label, errors) => {
  if (!isObject(entry)) {
    errors.push(`${label}: missing or invalid coverage counters`)
    return undefined
  }
  const value = {}
  for (const metric of METRICS) {
    const summary = entry[metric]
    if (
      !isObject(summary) ||
      !Number.isSafeInteger(summary.total) ||
      !Number.isSafeInteger(summary.covered) ||
      summary.total < 0 ||
      summary.covered < 0
    ) {
      errors.push(`${label}: missing or invalid coverage counters`)
      return undefined
    }
    if (summary.covered > summary.total) {
      errors.push(`${label}: covered counters exceed totals`)
      return undefined
    }
    value[metric] = { total: summary.total, covered: summary.covered }
  }
  return value
}

export const measure = (config, report) => {
  const errors = []
  const measured = new Map()
  if (!isObject(report)) {
    return { measured, errors: ['coverage summary must be an object'] }
  }
  const root = realpathSync(ROOT)
  const files = new Map()
  let entries = 0
  for (const [path, entry] of Object.entries(report)) {
    if (path === 'total') {
      continue
    }
    entries += 1
    const rel = relative(root, path).split(sep).join('/')
    if (!path.startsWith(root + sep) || rel.startsWith('..')) {
      errors.push(`coverage summary names a file outside the project: ${path}`)
      continue
    }
    const value = counters(entry, rel, errors)
    if (value !== undefined) {
      files.set(rel, value)
    }
  }
  if (entries === 0) {
    return { measured, errors: [...errors, 'coverage summary has no per-file entries'] }
  }
  const total = counters(report.total, 'global', errors)
  if (total !== undefined) {
    if (total.lines.total === 0) {
      errors.push('global: no measurable lines')
    }
    if (files.size === entries) {
      for (const metric of METRICS) {
        for (const field of ['total', 'covered']) {
          const sum = [...files.values()].reduce((acc, value) => acc + value[metric][field], 0)
          if (sum !== total[metric][field]) {
            errors.push('global: counters disagree with per-file sums')
          }
        }
      }
    }
    measured.set('global', total)
  }
  for (const [key, tier] of Object.entries(config.tiers)) {
    if (tier.include.length === 0) {
      measured.set(key, undefined)
      continue
    }
    const sum = Object.fromEntries(METRICS.map(metric => [metric, { total: 0, covered: 0 }]))
    for (const path of tier.include) {
      const value = files.get(path)
      if (value === undefined) {
        if (!own(report, join(root, path))) {
          errors.push(`${key}: ${path} is not in the coverage report (never imported, or excluded from coverage)`)
        }
        continue
      }
      if (value.lines.total === 0) {
        errors.push(`${key}: ${path} has no measurable lines (types only?)`)
      }
      for (const metric of METRICS) {
        sum[metric].total += value[metric].total
        sum[metric].covered += value[metric].covered
      }
    }
    measured.set(key, sum)
  }
  return { measured, errors: [...new Set(errors)], files }
}

const percent = (covered, total) => (100 * covered) / total

export const check = (config, measured, files = new Map()) => {
  const errors = []
  for (const [key, value] of measured) {
    if (value === undefined) {
      continue
    }
    const isGlobal = key === 'global'
    const floor = isGlobal ? GLOBAL_MINIMUM : config.tiers[key].minimum
    for (const metric of isGlobal ? GLOBAL_METRICS : METRICS) {
      const { covered, total } = value[metric]
      if (total > 0 && 100 * covered < floor * total) {
        let hint = ''
        if (isGlobal) {
          const low = [...files]
            .filter(([, file]) => file[metric].total > 0 && 100 * file[metric].covered < floor * file[metric].total)
            .map(([path, file]) => `${path} ${percent(file[metric].covered, file[metric].total).toFixed(2)}%`)
          hint = low.length > 0 ? ` (below the floor: ${low.join(', ')})` : ''
        }
        errors.push(`${key}: ${metric} ${percent(covered, total).toFixed(2)}% is below its minimum ${floor}%${hint}`)
      }
    }
  }
  return errors
}

const cell = (value, metric) => {
  if (value === undefined) {
    return 'n/a (explicitly empty)'
  }
  const { covered, total } = value[metric]
  return total > 0 ? `${percent(covered, total).toFixed(2)}%` : 'n/a (nothing to measure)'
}

export const reportMarkdown = (config, measured) => {
  const lines = [
    '| Tier | Lines | Branches | Functions | Minimum | Target |',
    '|---|---|---|---|---|---|',
  ]
  for (const [key, value] of measured) {
    const tier = key === 'global'
      ? { title: 'Global (lines and branches)', minimum: GLOBAL_MINIMUM, target: 100 }
      : config.tiers[key]
    lines.push(
      `| ${tier.title} | ${cell(value, 'lines')} | ${cell(value, 'branches')} | ${cell(value, 'functions')} | ${tier.minimum}% | ${tier.target}% |`,
    )
  }
  return `${lines.join('\n')}\n`
}

const git = (...args) => {
  try {
    return { status: 0, stdout: execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }), stderr: '' }
  } catch (error) {
    return { status: error.status ?? 1, stdout: String(error.stdout ?? ''), stderr: String(error.stderr ?? error.message) }
  }
}

export const ratchet = (config, ref) => {
  // rev-parse first: it also refuses a ref that git would read as an option.
  if (git('rev-parse', '--verify', '--quiet', `${ref}^{commit}`).status !== 0) {
    return [`cannot read ${CONFIG} at ${ref}: unknown revision`]
  }
  // A base that predates the file (the project's first PR) has no floors to keep.
  // Only a confirmed absence counts: an unreadable tree still fails.
  const listed = git('ls-tree', '--name-only', ref, '--', CONFIG)
  if (listed.status !== 0) {
    return [`cannot read ${CONFIG} at ${ref}: ${listed.stderr.trim()}`]
  }
  if (listed.stdout.trim() === '') {
    console.log(`coverage-tiers: no ${CONFIG} at ${ref}; nothing to ratchet against`)
    return []
  }
  const shown = git('show', `${ref}:${CONFIG}`)
  if (shown.status !== 0) {
    return [`cannot read ${CONFIG} at ${ref}: ${shown.stderr.trim()}`]
  }
  let old
  try {
    old = JSON.parse(shown.stdout)
  } catch (error) {
    return [`base config: ${CONFIG} at ${ref} is not valid JSON: ${error.message}`]
  }
  const baseErrors = validate(old, { checkFiles: false })
  if (baseErrors.length > 0) {
    return baseErrors.map(error => `base config: ${error}`)
  }
  const errors = []
  for (const [key, before] of Object.entries(old.tiers)) {
    const now = config.tiers[key]
    if (now === undefined) {
      errors.push(`${key}: tier removed since ${ref}`)
      continue
    }
    for (const field of ['minimum', 'target']) {
      if (now[field] < before[field]) {
        errors.push(`${key}: ${field} lowered from ${before[field]} to ${now[field]}`)
      }
    }
    // A reviewed migration lists the old path in `retired`; any other removal fails.
    const kept = new Set([...now.include, ...(now.retired ?? [])])
    const removed = before.include.filter(path => !kept.has(path)).toSorted()
    if (removed.length > 0) {
      errors.push(
        `${key}: existing members removed since ${ref}: ${JSON.stringify(removed)} ` +
          "(to rename, move or delete one, list its old path in the tier's retired)",
      )
    }
  }
  return errors
}

const usage = message => {
  console.error(`coverage-tiers: ${message}`)
  console.error('usage: node scripts/coverage-tiers.mjs (--validate | --check | --report | --ratchet REF) [--input FILE]')
  process.exit(2)
}

const parseArgs = argv => {
  let mode
  let ref
  let input = 'coverage/coverage-summary.json'
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    const [flag, inline] = arg.startsWith('--') && arg.includes('=') ? [arg.slice(0, arg.indexOf('=')), arg.slice(arg.indexOf('=') + 1)] : [arg, undefined]
    const value = () => {
      if (inline !== undefined) {
        return inline
      }
      index += 1
      if (index >= argv.length) {
        usage(`${flag} needs a value`)
      }
      return argv[index]
    }
    if (['--validate', '--check', '--report', '--ratchet'].includes(flag)) {
      if (mode !== undefined) {
        usage('choose exactly one of --validate, --check, --report, --ratchet')
      }
      mode = flag
      if (flag === '--ratchet') {
        ref = value()
        if (ref.trim() === '') {
          usage('--ratchet needs a git ref')
        }
      } else if (inline !== undefined) {
        usage(`${flag} takes no value`)
      }
    } else if (flag === '--input') {
      input = value()
    } else {
      usage(`unknown argument: ${arg}`)
    }
  }
  if (mode === undefined) {
    usage('choose one of --validate, --check, --report, --ratchet')
  }
  return { mode, ref, input }
}

const main = argv => {
  const { mode, ref, input } = parseArgs(argv)
  let errors
  try {
    const config = JSON.parse(readFileSync(join(ROOT, CONFIG), 'utf8'))
    errors = validate(config)
    if (errors.length === 0 && mode === '--ratchet') {
      errors = ratchet(config, ref)
    } else if (errors.length === 0 && (mode === '--check' || mode === '--report')) {
      const report = JSON.parse(readFileSync(join(ROOT, input), 'utf8'))
      const measured = measure(config, report)
      errors = measured.errors
      if (errors.length === 0 && mode === '--report') {
        process.stdout.write(reportMarkdown(config, measured.measured))
        return 0
      }
      if (errors.length === 0) {
        errors = check(config, measured.measured, measured.files)
      }
    }
  } catch (error) {
    errors = [`cannot load valid configuration/report: ${error instanceof Error ? error.message : String(error)}`]
  }
  for (const error of errors) {
    console.error(`coverage-tiers: FAIL ${error}`)
  }
  console.log(`coverage-tiers: ${errors.length > 0 ? 'FAILED' : 'ok'}`)
  return errors.length > 0 ? 1 : 0
}

if (process.argv[1] !== undefined && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2))
}
````

`files/scripts/check-pins.mjs`:

````js
#!/usr/bin/env node
// Pin guard (Node standard library only), run by scripts/check.d/foldkit.sh:
// package.json stays in the byte form gstack /ship writes, its version is VERSION,
// every dependency is exact, the runtime and package manager are pinned once,
// node_modules holds each dependency at its pin, and the Foldkit + Effect train
// moves together.
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)))
const EXACT = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/
const SEMVER3 = /^\d+\.\d+\.\d+$/
const errors = []

const read = path => readFileSync(join(ROOT, path), 'utf8')
const installed = name => {
  const path = join(ROOT, 'node_modules', name, 'package.json')
  return existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : undefined
}

// Numeric semver compare for exact versions (prerelease sorts before release).
const compare = (a, b) => {
  const [coreA, preA = ''] = a.split('-', 2)
  const [coreB, preB = ''] = b.split('-', 2)
  const partsA = coreA.split('.').map(Number)
  const partsB = coreB.split('.').map(Number)
  for (let index = 0; index < 3; index += 1) {
    if (partsA[index] !== partsB[index]) {
      return partsA[index] - partsB[index]
    }
  }
  if (preA === preB) {
    return 0
  }
  if (preA === '' || preB === '') {
    return preA === '' ? 1 : -1
  }
  return preA < preB ? -1 : 1
}

// The peer range forms the @foldkit packages publish: exact, >=X.Y.Z, ^X[.Y[.Z]].
// Anything else is reported, not guessed.
const satisfies = (version, range) => {
  if (EXACT.test(range)) {
    return version === range
  }
  const atLeast = /^>=(\d+\.\d+\.\d+)$/.exec(range)
  if (atLeast) {
    return compare(version, atLeast[1]) >= 0
  }
  const caret = /^\^(\d+)(?:\.(\d+))?(?:\.(\d+))?$/.exec(range)
  if (caret) {
    const [major, minor, patch] = caret.slice(1)
    const core = version.split('-')[0]
    const [vMajor, vMinor] = core.split('.')
    const sameLine = major === '0' && minor !== undefined ? vMajor === '0' && vMinor === minor : vMajor === major
    return sameLine && compare(core, `${major}.${minor ?? 0}.${patch ?? 0}`) >= 0
  }
  return undefined
}

const parse = text => {
  try {
    return JSON.parse(text)
  } catch (error) {
    console.error(`check-pins: FAIL package.json is not valid JSON: ${error.message}`)
    console.log('check-pins: FAILED')
    return process.exit(1)
  }
}
const raw = read('package.json')
const pkg = parse(raw)
if (raw !== `${JSON.stringify(pkg, null, 2)}\n`) {
  errors.push('package.json is not in JSON.stringify(pkg, null, 2) + "\\n" form (gstack /ship rewrites it that way): reformat it')
}
const version = existsSync(join(ROOT, 'VERSION')) ? read('VERSION').trim() : ''
if (!SEMVER3.test(version)) {
  errors.push(`VERSION must hold MAJOR.MINOR.PATCH, got ${JSON.stringify(version)}`)
} else if (pkg.version !== version) {
  errors.push(`package.json version ${JSON.stringify(pkg.version)} differs from VERSION ${version}: set it to ${version}`)
}

const deps = { ...pkg.dependencies, ...pkg.devDependencies }
for (const [name, spec] of Object.entries(deps)) {
  if (typeof spec !== 'string' || !EXACT.test(spec)) {
    errors.push(`${name} must be pinned to an exact version, got ${JSON.stringify(spec)}`)
  }
}

const nodeVersion = existsSync(join(ROOT, '.node-version')) ? read('.node-version').trim() : ''
const runtime = pkg.devEngines?.runtime
if (runtime?.name !== 'node' || runtime?.version !== nodeVersion || !SEMVER3.test(nodeVersion)) {
  errors.push(`devEngines.runtime must be node at .node-version's exact version (${JSON.stringify(nodeVersion)}), got ${JSON.stringify(runtime)}`)
}
const manager = pkg.devEngines?.packageManager
if (manager?.name !== 'pnpm' || !SEMVER3.test(String(manager?.version)) || pkg.packageManager !== `pnpm@${manager.version}`) {
  errors.push(`devEngines.packageManager (pnpm, exact) and packageManager (pnpm@<same>) must agree, got ${JSON.stringify(manager)} and ${JSON.stringify(pkg.packageManager)}`)
}

// The train: effect and every @effect/* package (the language-service patcher
// @effect/tsgo has its own versions) share one version, and Foldkit names it.
const effect = deps.effect
if (effect === undefined) {
  errors.push('effect must be a dependency')
}
for (const [name, spec] of Object.entries(deps)) {
  if (name.startsWith('@effect/') && name !== '@effect/tsgo' && spec !== effect) {
    errors.push(`${name} ${spec} must match effect ${effect}: the Effect train moves together`)
  }
}

// node_modules holds every direct dependency at its pin. pnpm can keep another
// version than the one package.json names (12.6.0 keeps a locked prerelease when
// the pin moves to its stable release), and no other check would notice.
const missing = []
for (const [name, spec] of Object.entries(deps)) {
  const meta = installed(name)
  if (meta === undefined) {
    missing.push(name)
  } else if (EXACT.test(String(spec)) && meta.version !== spec) {
    errors.push(`node_modules has ${name} ${meta.version}, package.json pins ${spec}: run pnpm install (if it stays, pnpm-lock.yaml holds the other version: regenerate it)`)
  }
}
if (missing.length > 0) {
  errors.push(`node_modules is missing ${missing.join(', ')}: run pnpm install`)
}

const foldkit = installed('foldkit')
if (foldkit !== undefined) {
  for (const peer of ['effect', '@effect/platform-browser']) {
    const wanted = foldkit.peerDependencies?.[peer]
    if (wanted !== deps[peer]) {
      errors.push(`foldkit ${foldkit.version} needs ${peer} ${wanted}, package.json pins ${deps[peer]}: move the train together (docs/guides/foldkit.md)`)
    }
  }
  // Every @foldkit/* package pins the same exact Effect and names a foldkit range;
  // @foldkit/devtools is released in lockstep with foldkit itself.
  for (const name of Object.keys(deps).filter(dep => dep.startsWith('@foldkit/'))) {
    const meta = installed(name)
    if (meta === undefined) {
      continue
    }
    for (const [peer, range] of Object.entries(meta.peerDependencies ?? {})) {
      const pinned = peer === 'foldkit' ? foldkit.version : deps[peer]
      if (pinned === undefined) {
        continue
      }
      const ok = satisfies(pinned, range)
      if (ok === undefined) {
        errors.push(`${name} declares ${peer} ${JSON.stringify(range)}, which check-pins cannot evaluate: review the train by hand and extend scripts/check-pins.mjs`)
      } else if (!ok) {
        errors.push(`${name} ${meta.version} needs ${peer} ${range}, package.json pins ${pinned}: move the train together`)
      }
    }
  }
  if (deps['@foldkit/devtools'] !== undefined && deps['@foldkit/devtools'] !== deps.foldkit) {
    errors.push(`@foldkit/devtools ${deps['@foldkit/devtools']} must equal foldkit ${deps.foldkit} (they release together)`)
  }
}

for (const error of errors) {
  console.error(`check-pins: FAIL ${error}`)
}
console.log(`check-pins: ${errors.length > 0 ? 'FAILED' : 'ok'}`)
process.exitCode = errors.length > 0 ? 1 : 0
````

`files/scripts/check.d/foldkit.sh`:

````sh
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
````

`files/scripts/vendor-foldkit.sh`:

````sh
#!/usr/bin/env bash
# Vendor the Foldkit repository at the pinned release into repos/foldkit: a
# gitignored, read-only reference for agents (FOLDKIT.md points at it). Rerun it
# after every Foldkit upgrade. Needs git and the network.
#
# Left out on purpose: repos/ (Foldkit's own copy of Effect; node_modules/effect
# ships Effect's source) and Foldkit's maintainer agent files (AGENTS.md,
# CLAUDE.md, .mcp.json, .claude/, .agents/), which would otherwise load as
# instructions for this project's agents.
set -euo pipefail
CDPATH='' cd -- "$(dirname -- "$0")/.."
pin="$(node -p 'require("./package.json").dependencies.foldkit')"
case "$pin" in
  ''|*[!0-9.]*|.*|*.) echo "vendor-foldkit: package.json must pin foldkit to an exact release (got '$pin')" >&2; exit 1 ;;
esac
tmp="$(mktemp -d "${TMPDIR:-/tmp}/vendor-foldkit.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
git -c advice.detachedHead=false clone --quiet --depth 1 --filter=blob:none --sparse \
  --branch "foldkit@$pin" https://github.com/foldkit/foldkit.git "$tmp/foldkit"
git -C "$tmp/foldkit" sparse-checkout set --no-cone \
  '/*' '!/repos/' '!AGENTS.md' '!CLAUDE.md' '!.mcp.json' '!.claude/' '!.agents/'
rm -rf "$tmp/foldkit/.git"
# Sparse patterns first; then make sure nothing matching slipped through.
find "$tmp/foldkit" -depth \( -name .claude -o -name .agents \) -type d -exec rm -rf {} +
find "$tmp/foldkit" \( -name AGENTS.md -o -name CLAUDE.md -o -name .mcp.json \) -type f -exec rm -f {} +
[ ! -e "$tmp/foldkit/repos" ] || { echo "vendor-foldkit: the sparse checkout still has repos/" >&2; exit 1; }
printf '%s\n' "$pin" > "$tmp/foldkit/.vendored-version"
mkdir -p repos
rm -rf repos/foldkit.previous
if [ -e repos/foldkit ]; then mv repos/foldkit repos/foldkit.previous; fi
mv "$tmp/foldkit" repos/foldkit
rm -rf repos/foldkit.previous
echo "Vendored foldkit@$pin into repos/foldkit ($(du -sh repos/foldkit | awk '{print $1}'), gitignored)."
````

`files/src/entry.ts`:

````ts
import { Http, Runtime } from 'foldkit'

import { Model, init, update } from './main'
import './styles.css'
import { view } from './view'

const application = Runtime.makeApplication({
  Model,
  init,
  update,
  view,
  container: document.getElementById('root'),
  resources: Http.layer,
})

Runtime.run(application)
````

`files/src/message.ts`:

````ts
import { Schema } from 'effect'
import { defineMessageUnion } from 'foldkit/message'

import { StatusPayload } from './api/status'

// MESSAGE

export const FailureReason = Schema.Literals([
  'http',
  'malformed',
  'unreachable',
])
export type FailureReason = typeof FailureReason.Type

export const Message = defineMessageUnion({
  ClickedRetryStatus: {},
  SucceededFetchStatus: { payload: StatusPayload },
  FailedFetchStatus: { reason: FailureReason, detail: Schema.String },
})
export type Message = typeof Message.Type
````

`files/src/main.ts`:

````ts
import { Schema } from 'effect'
import type { HttpClient } from 'effect/http'
import type { Runtime, Update } from 'foldkit'
import { defineTaggedUnion } from 'foldkit/schema'
import { modifyFields } from 'foldkit/struct'

import { StatusPayload } from './api/status'
import { FetchStatus } from './command'
import { FailureReason, Message } from './message'

// MODEL

export const StatusState = defineTaggedUnion({
  Loading: {},
  Loaded: { payload: StatusPayload },
  Failed: { reason: FailureReason, detail: Schema.String },
})
export type StatusState = typeof StatusState.Type

export const Model = Schema.Struct({
  status: StatusState,
})
export type Model = typeof Model.Type

// INIT

export const init: Runtime.ApplicationInit<
  Model,
  Message,
  void,
  HttpClient.HttpClient
> = () => ({
  model: { status: StatusState.Loading() },
  commands: [FetchStatus()],
})

// UPDATE

type UpdateReturn = Update.Return<Model, Message, HttpClient.HttpClient>

export const update = (model: Model, message: Message) =>
  Message.match<UpdateReturn>(message, {
    ClickedRetryStatus: () => ({
      model: modifyFields(model, { status: () => StatusState.Loading() }),
      commands: [FetchStatus()],
    }),
    SucceededFetchStatus: ({ payload }) => ({
      model: modifyFields(model, {
        status: () => StatusState.Loaded({ payload }),
      }),
    }),
    FailedFetchStatus: ({ reason, detail }) => ({
      model: modifyFields(model, {
        status: () => StatusState.Failed({ reason, detail }),
      }),
    }),
  })
````

`files/src/command.ts`:

````ts
import { Effect } from 'effect'
import { Command } from 'foldkit'

import { fetchStatus } from './api/status'
import { Message } from './message'

// COMMAND

export const FetchStatus = Command.define('FetchStatus', {
  messages: [Message.SucceededFetchStatus, Message.FailedFetchStatus],
  execute: fetchStatus.pipe(
    Effect.map(payload => Message.SucceededFetchStatus({ payload })),
    Effect.catchTags({
      StatusHttpError: error =>
        Effect.succeed(
          Message.FailedFetchStatus({
            reason: 'http',
            detail: `HTTP ${error.status}`,
          }),
        ),
      StatusMalformedError: error =>
        Effect.succeed(
          Message.FailedFetchStatus({
            reason: 'malformed',
            detail: error.detail,
          }),
        ),
      StatusUnreachableError: error =>
        Effect.succeed(
          Message.FailedFetchStatus({
            reason: 'unreachable',
            detail: error.detail,
          }),
        ),
    }),
  ),
})
````

`files/src/api/status.ts`:

````ts
import { Data, Effect, Schema } from 'effect'
import { HttpClient, type HttpClientError } from 'effect/http'

// The one network boundary: GET /status.json, decoded through a Schema.

export const STATUS_PATH = '/status.json'

export const StatusPayload = Schema.Struct({
  status: Schema.Literals(['ok', 'degraded', 'down']),
  checkedAt: Schema.String,
})
export type StatusPayload = typeof StatusPayload.Type

export class StatusHttpError extends Data.TaggedError('StatusHttpError')<{
  readonly status: number
}> {}

export class StatusMalformedError extends Data.TaggedError(
  'StatusMalformedError',
)<{
  readonly detail: string
}> {}

export class StatusUnreachableError extends Data.TaggedError(
  'StatusUnreachableError',
)<{
  readonly detail: string
}> {}

export type StatusError =
  | StatusHttpError
  | StatusMalformedError
  | StatusUnreachableError

const toRequestFailure = (
  error: HttpClientError.HttpClientError,
): StatusHttpError | StatusUnreachableError => {
  if (error.reason._tag === 'StatusCodeError') {
    return new StatusHttpError({ status: error.reason.response.status })
  }
  return new StatusUnreachableError({ detail: error.message })
}

const toMalformed = (error: { readonly message: string }) =>
  new StatusMalformedError({ detail: error.message })

export const fetchStatus: Effect.Effect<
  StatusPayload,
  StatusError,
  HttpClient.HttpClient
> = Effect.gen(function* () {
  const client = HttpClient.filterStatusOk(yield* HttpClient.HttpClient)
  const response = yield* client
    .get(STATUS_PATH)
    .pipe(Effect.mapError(toRequestFailure))
  const body = yield* response.json.pipe(Effect.mapError(toMalformed))
  return yield* Schema.decodeUnknownEffect(StatusPayload)(body).pipe(
    Effect.mapError(toMalformed),
  )
})
````

`files/src/domain/version.ts`:

````ts
import { Option } from 'effect'

const SEMVER = /^\d+\.\d+\.\d+$/

export const parseVersion = (raw: string): Option.Option<string> => {
  const trimmed = raw.trim()
  if (SEMVER.test(trimmed)) {
    return Option.some(trimmed)
  }
  return Option.none()
}

export const displayVersion = (raw: string): string =>
  Option.match(parseVersion(raw), {
    onNone: () => 'unknown',
    onSome: version => version,
  })
````

`files/src/build-info.ts`:

````ts
import rawVersion from '../VERSION?raw'
import { displayVersion } from './domain/version'

export const PROJECT_NAME = '{{PROJECT_NAME}}'

export const VERSION = displayVersion(rawVersion)
````

`files/src/view.ts`:

````ts
import type { Document, HtmlBuilder } from 'foldkit/html'

import { PROJECT_NAME, VERSION } from './build-info'
import { statusView } from './components/status'
import type { Model } from './main'
import type { Message } from './message'

// VIEW

export const view = (model: Model, h: HtmlBuilder<Message>): Document => ({
  title: PROJECT_NAME,
  body: h.main(
    [h.Class('page')],
    [
      h.h1([h.Class('title')], [PROJECT_NAME]),
      h.p([h.Class('version')], [`Version ${VERSION}`]),
      statusView(model.status, h),
    ],
  ),
})
````

`files/src/components/status.ts`:

````ts
import type { Html, HtmlBuilder } from 'foldkit/html'

import { StatusState } from '../main'
import { Message } from '../message'

// VIEW

export const statusView = (
  status: StatusState,
  h: HtmlBuilder<Message>,
): Html =>
  StatusState.match(status, {
    Loading: () =>
      h.p([h.Role('status'), h.Class('status')], ['Checking status...']),
    Loaded: ({ payload }) =>
      h.p(
        [h.Role('status'), h.Class(`status status-${payload.status}`)],
        [`Status: ${payload.status} (checked ${payload.checkedAt})`],
      ),
    Failed: ({ reason, detail }) =>
      h.div(
        [h.Class('status-failed')],
        [
          h.p(
            [h.Role('alert'), h.Class('status status-error')],
            [`Status check failed (${reason}): ${detail}`],
          ),
          h.button(
            [
              h.Type('button'),
              h.Class('button'),
              h.OnClick(Message.ClickedRetryStatus()),
            ],
            ['Retry'],
          ),
        ],
      ),
  })
````

`files/src/styles.css`:

````css
/* Design tokens (DESIGN.md): views use these through classes, never inline. */
:root {
  --color-background: #ffffff;
  --color-text: #1f2328;
  --color-muted: #59636e;
  --color-ok: #1a7f37;
  --color-warning: #9a6700;
  --color-error: #cf222e;
  --color-accent: #0969da;
  --color-on-accent: #ffffff;
  --font-sans: system-ui, -apple-system, 'Segoe UI', sans-serif;
  --space-1: 0.25rem;
  --space-2: 0.5rem;
  --space-4: 1rem;
  --space-8: 2rem;
  --radius: 0.375rem;
}

body {
  margin: 0;
  background: var(--color-background);
  color: var(--color-text);
  font-family: var(--font-sans);
}

.page {
  max-width: 40rem;
  margin: 0 auto;
  padding: var(--space-8) var(--space-4);
}

.title {
  margin: 0 0 var(--space-2);
}

.version {
  margin: 0 0 var(--space-4);
  color: var(--color-muted);
}

.status {
  margin: 0 0 var(--space-2);
}

.status-ok {
  color: var(--color-ok);
}

.status-degraded {
  color: var(--color-warning);
}

.status-down {
  color: var(--color-error);
}

.status-error {
  color: var(--color-error);
}

.button {
  padding: var(--space-1) var(--space-4);
  border: 0;
  border-radius: var(--radius);
  background: var(--color-accent);
  color: var(--color-on-accent);
  font: inherit;
  cursor: pointer;
}
````

`files/src/vite-env.d.ts`:

````ts
/// <reference types="vite/client" />
````

`files/src/vitest-setup.ts`:

````ts
import { setup } from 'foldkit/test/vitest'

setup()
````

`files/src/story.test.ts`:

````ts
import { Command, given, message, model, story } from 'foldkit/story'
import { describe, expect, test } from 'vitest'

import type { StatusPayload } from './api/status'
import { FetchStatus } from './command'
import { Model, StatusState, init, update } from './main'
import { Message } from './message'

const payload: StatusPayload = {
  status: 'ok',
  checkedAt: '2026-09-25T00:00:00Z',
}

const loading = Model.make({ status: StatusState.Loading() })

const failed = Model.make({
  status: StatusState.Failed({ reason: 'http', detail: 'HTTP 503' }),
})

describe('init', () => {
  test('starts loading and fetches the status', () => {
    const init_ = init()
    expect(init_.model).toEqual(loading)
    expect(init_.commands).toEqual([FetchStatus()])
  })
})

describe('update', () => {
  test('a successful status fetch stores the payload', () => {
    story(
      update,
      given(loading),
      message(Message.SucceededFetchStatus({ payload })),
      model(model => {
        expect(model.status).toEqual(StatusState.Loaded({ payload }))
      }),
      Command.expectNone(),
    )
  })

  test('a failed status fetch stores the reason', () => {
    story(
      update,
      given(loading),
      message(
        Message.FailedFetchStatus({ reason: 'malformed', detail: 'bad json' }),
      ),
      model(model => {
        expect(model.status).toEqual(
          StatusState.Failed({ reason: 'malformed', detail: 'bad json' }),
        )
      }),
      Command.expectNone(),
    )
  })

  test('retrying re-fetches and a success resolves inline', () => {
    story(
      update,
      given(failed),
      message(Message.ClickedRetryStatus()),
      model(model => {
        expect(model.status).toEqual(StatusState.Loading())
      }),
      Command.expectExact(FetchStatus()),
      Command.resolve(FetchStatus, Message.SucceededFetchStatus({ payload })),
      model(model => {
        expect(model.status).toEqual(StatusState.Loaded({ payload }))
      }),
    )
  })

  test('retrying re-fetches and a failure resolves inline', () => {
    story(
      update,
      given(failed),
      message(Message.ClickedRetryStatus()),
      Command.resolve(
        FetchStatus,
        Message.FailedFetchStatus({ reason: 'unreachable', detail: 'offline' }),
      ),
      model(model => {
        expect(model.status).toEqual(
          StatusState.Failed({ reason: 'unreachable', detail: 'offline' }),
        )
      }),
    )
  })
})
````

`files/src/scene.test.ts`:

````ts
import { Command, click, expect, given, role, scene, text } from 'foldkit/scene'
import { describe, test } from 'vitest'

import { PROJECT_NAME, VERSION } from './build-info'
import { FetchStatus } from './command'
import { Model, StatusState, update } from './main'
import { Message } from './message'
import { view } from './view'

const withStatus = (status: StatusState) => Model.make({ status })

describe('view', () => {
  test('shows the project name, the version and a loading status', () => {
    scene(
      { update, view },
      given(withStatus(StatusState.Loading())),
      expect(role('heading', { name: PROJECT_NAME })).toExist(),
      expect(text(`Version ${VERSION}`)).toExist(),
      expect(role('status')).toHaveText('Checking status...'),
    )
  })

  test('shows the loaded status', () => {
    scene(
      { update, view },
      given(
        withStatus(
          StatusState.Loaded({
            payload: { status: 'ok', checkedAt: '2026-09-25T00:00:00Z' },
          }),
        ),
      ),
      expect(role('status')).toHaveText(
        'Status: ok (checked 2026-09-25T00:00:00Z)',
      ),
      expect(role('alert')).toBeAbsent(),
    )
  })

  test('each loaded status gets its own style', () => {
    scene(
      { update, view },
      given(
        withStatus(
          StatusState.Loaded({
            payload: { status: 'down', checkedAt: '2026-09-25T00:00:00Z' },
          }),
        ),
      ),
      expect(role('status')).toHaveAttr('class', 'status status-down'),
    )
  })

  test('a failed check shows an alert, and Retry recovers', () => {
    scene(
      { update, view },
      given(
        withStatus(StatusState.Failed({ reason: 'http', detail: 'HTTP 503' })),
      ),
      expect(role('alert')).toHaveText('Status check failed (http): HTTP 503'),
      click(role('button', { name: 'Retry' })),
      expect(role('status')).toHaveText('Checking status...'),
      Command.expectExact(FetchStatus()),
      Command.resolve(
        FetchStatus,
        Message.SucceededFetchStatus({
          payload: { status: 'degraded', checkedAt: '2026-09-25T01:00:00Z' },
        }),
      ),
      expect(role('status')).toHaveText(
        'Status: degraded (checked 2026-09-25T01:00:00Z)',
      ),
      expect(role('alert')).toBeAbsent(),
    )
  })
})
````

`files/src/command.test.ts`:

````ts
import { Effect, Layer } from 'effect'
import { HttpClient, HttpClientError, HttpClientResponse } from 'effect/http'

import { assert, describe, it } from '@effect/vitest'

import { FetchStatus } from './command'
import { Message } from './message'

// Tier 2: FetchStatus maps every outcome of the status request to a Message.
// Only the HttpClient Layer (the network edge) is swapped.

const answering = (response: Response) =>
  Layer.succeed(
    HttpClient.HttpClient,
    HttpClient.make(request =>
      Effect.succeed(HttpClientResponse.fromWeb(request, response)),
    ),
  )

const offline = Layer.succeed(
  HttpClient.HttpClient,
  HttpClient.make(request =>
    Effect.fail(
      new HttpClientError.HttpClientError({
        reason: new HttpClientError.TransportError({
          request,
          description: 'offline',
        }),
      }),
    ),
  ),
)

const run = (layer: Layer.Layer<HttpClient.HttpClient>) =>
  FetchStatus().effect.pipe(Effect.provide(layer))

describe('FetchStatus', () => {
  it.effect('reports a well-formed status', () =>
    Effect.gen(function* () {
      const checkedAt = '2026-09-25T00:00:00Z'
      assert.deepStrictEqual(
        yield* run(answering(Response.json({ status: 'ok', checkedAt }))),
        Message.SucceededFetchStatus({ payload: { status: 'ok', checkedAt } }),
      )
    }),
  )

  it.effect('reports a non-2xx response as an http failure', () =>
    Effect.gen(function* () {
      assert.deepStrictEqual(
        yield* run(answering(new Response(null, { status: 404 }))),
        Message.FailedFetchStatus({ reason: 'http', detail: 'HTTP 404' }),
      )
    }),
  )

  it.effect('reports a malformed payload', () =>
    Effect.gen(function* () {
      const result = yield* run(answering(new Response('nope')))
      assert.deepStrictEqual(
        result._tag === 'FailedFetchStatus' ? result.reason : result._tag,
        'malformed',
      )
    }),
  )

  it.effect('reports a transport failure as unreachable', () =>
    Effect.gen(function* () {
      const result = yield* run(offline)
      assert.deepStrictEqual(
        result._tag === 'FailedFetchStatus' ? result.reason : result._tag,
        'unreachable',
      )
    }),
  )
})
````

`files/src/api/status.test.ts`:

````ts
import { Effect, Layer } from 'effect'
import { HttpClient, HttpClientError, HttpClientResponse } from 'effect/http'

import { assert, describe, it } from '@effect/vitest'

import { STATUS_PATH, fetchStatus } from './status'

// Tier 2: the network edge is the only thing swapped. Each test provides an
// HttpClient Layer that answers with a canned Response or a transport error.

const answering = (respond: () => Response) =>
  Layer.succeed(
    HttpClient.HttpClient,
    HttpClient.make((request, url) =>
      Effect.sync(() => {
        assert.strictEqual(url.pathname, STATUS_PATH)
        return HttpClientResponse.fromWeb(request, respond())
      }),
    ),
  )

const offline = Layer.succeed(
  HttpClient.HttpClient,
  HttpClient.make(request =>
    Effect.fail(
      new HttpClientError.HttpClientError({
        reason: new HttpClientError.TransportError({
          request,
          description: 'offline',
        }),
      }),
    ),
  ),
)

const okBody = { status: 'ok', checkedAt: '2026-09-25T00:00:00Z' }

describe('fetchStatus', () => {
  it.effect('decodes a well-formed payload', () =>
    Effect.gen(function* () {
      const payload = yield* fetchStatus.pipe(
        Effect.provide(answering(() => Response.json(okBody))),
      )
      assert.deepStrictEqual(payload, okBody)
    }),
  )

  it.effect('fails with StatusHttpError on a non-2xx response', () =>
    Effect.gen(function* () {
      const error = yield* fetchStatus.pipe(
        Effect.provide(answering(() => new Response('down', { status: 503 }))),
        Effect.flip,
      )
      assert.deepStrictEqual(
        error._tag === 'StatusHttpError' ? error.status : error._tag,
        503,
      )
    }),
  )

  it.effect('fails with StatusMalformedError when the body is not JSON', () =>
    Effect.gen(function* () {
      const error = yield* fetchStatus.pipe(
        Effect.provide(answering(() => new Response('<html>'))),
        Effect.flip,
      )
      assert.strictEqual(error._tag, 'StatusMalformedError')
    }),
  )

  it.effect('fails with StatusMalformedError on the wrong shape', () =>
    Effect.gen(function* () {
      const error = yield* fetchStatus.pipe(
        Effect.provide(
          answering(() => Response.json({ status: 'maybe', checkedAt: 1 })),
        ),
        Effect.flip,
      )
      assert.strictEqual(error._tag, 'StatusMalformedError')
    }),
  )

  it.effect('fails with StatusUnreachableError on a transport error', () =>
    Effect.gen(function* () {
      const error = yield* fetchStatus.pipe(
        Effect.provide(offline),
        Effect.flip,
      )
      assert.strictEqual(error._tag, 'StatusUnreachableError')
    }),
  )
})
````

`files/src/domain/version.test.ts`:

````ts
import { Option, Schema } from 'effect'

import { describe, expect, it } from '@effect/vitest'

import { displayVersion, parseVersion } from './version'

const Part = Schema.Int.pipe(Schema.check(Schema.isGreaterThanOrEqualTo(0)))

describe('parseVersion', () => {
  it.each([
    ['0.0.0\n', Option.some('0.0.0')],
    ['  1.2.3  ', Option.some('1.2.3')],
    ['10.20.30', Option.some('10.20.30')],
    ['v1.2.3', Option.none()],
    ['1.2', Option.none()],
    ['1.2.3.4', Option.none()],
    ['1.2.3-rc.1', Option.none()],
    ['', Option.none()],
  ])('parseVersion(%j)', (raw, expected) => {
    expect(parseVersion(raw)).toEqual(expected)
  })
})

describe('displayVersion', () => {
  it('shows the parsed version', () => {
    expect(displayVersion('1.2.3\n')).toBe('1.2.3')
  })

  it('falls back to unknown', () => {
    expect(displayVersion('not a version')).toBe('unknown')
  })

  it.prop(
    'shows any MAJOR.MINOR.PATCH read from the VERSION file',
    [Part, Part, Part],
    ([major, minor, patch]) => {
      const version = `${major}.${minor}.${patch}`
      expect(displayVersion(`${version}\n`)).toBe(version)
    },
  )
})
````

`files/e2e/home.spec.ts`:

````ts
import { expect, test } from '@playwright/test'

import packageJson from '../package.json' with { type: 'json' }

test('home renders the project name, version and status', async ({ page }) => {
  await page.goto('/')
  await expect(page).toHaveTitle(packageJson.description)
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    packageJson.description,
  )
  await expect(page.getByText(`Version ${packageJson.version}`)).toBeVisible()
  await expect(page.getByRole('status')).toHaveText(
    'Status: ok (checked 2026-09-25T00:00:00Z)',
  )
})
````

`files/docs/guides/foldkit.md`:

````markdown
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
outside a tier still count toward the global floor. Tests never use `vi.mock`: tier 2 swaps the
`HttpClient` Layer, the only trust boundary.

## Commands

| Purpose | Command |
|---|---|
| Install (also patches tsc, via the `prepare` script) | `pnpm install` |
| Dev server on http://localhost:3000 | `pnpm dev` |
| Production build / preview on 4000 | `pnpm build` / `pnpm preview` |
| Guards: pins, lockfile, types, lint, format, boundaries, tier config | `./scripts/check.sh` |
| Tests, fast and gate-free (one file: add its path) | `pnpm exec vitest run` |
| Coverage gates: 90% lines and branches, then per tier | `./scripts/coverage.sh` |
| E2E journeys (once per machine: `pnpm exec playwright install chromium`) | `pnpm exec playwright test` |
| Coverage snapshot table | `node scripts/coverage-tiers.mjs --report` |
| Refresh the vendored Foldkit source | `bash scripts/vendor-foldkit.sh` |

The full gate is `./scripts/check.sh && ./scripts/coverage.sh && pnpm exec playwright test`.
Dependencies install only once they are 24 hours old (`minimumReleaseAge` in
`pnpm-workspace.yaml`), and dependency build scripts are denied.

## The upgrade train

Foldkit pins one exact Effect version, and every `@foldkit/*` package pins the same one. So
these move together, all exactly pinned, in one change:

1. `foldkit`, every `@foldkit/*` package, `effect` and every `@effect/*` package except
   `@effect/tsgo` (the patcher has its own versions and a support matrix: check its README for
   the TypeScript version it supports). Keep `devToolsMcpPort: false` in `vite.config.ts`
   unless you mean to turn the relay on (below).
2. `pnpm install`, then `node scripts/check-pins.mjs`: it fails until the installed Foldkit's
   peers name exactly the pinned Effect, and whenever `node_modules` holds a version other
   than a pin.
3. `bash scripts/vendor-foldkit.sh`, then replace `FOLDKIT.md` whole with
   `repos/foldkit/packages/create-foldkit-app/templates/base/FOLDKIT.md`.
4. The full gate. Foldkit's minor releases often break its API; its changelog is in
   `repos/foldkit/packages/foldkit/CHANGELOG.md`.

A release under 24 hours old fails every install, frozen ones included (and
`./scripts/check.sh`), until it is a day old. To move the train sooner, export
`pnpm_config_minimum_release_age=0` for that shell session, for every pnpm command or for none;
CI stays red until the release has matured. Never edit `pnpm-workspace.yaml` for it.

## Where this project deviates from FOLDKIT.md

- **The DevTools MCP is off.** FOLDKIT.md says `@foldkit/devtools-mcp` is pre-wired. Here it is
  installed but not connected, and `src/entry.ts` passes no `devTools: { Message }`, so no
  client can dispatch Messages. The relay comes from `@foldkit/vite-plugin` (0.25.0 and later):
  - By default the plugin serves the relay from the dev server, behind a random token, on
    Vite's `server.host` (localhost unless you change it). This project turns it off with
    `devToolsMcpPort: false` in `vite.config.ts`; delete that option to turn it on.
  - A numeric `devToolsMcpPort` still opens the old relay: every network interface, no token
    and no Origin check. That is why `./scripts/check.sh` refuses one.

  To let the agent dispatch Messages as well, pass `devTools: { Message }` in `src/entry.ts`.
  Point your agent at the pinned local bin, never `npx` (the check refuses `npx` in
  `.mcp.json`), with a `.mcp.json` like this:

  ```json
  {
    "mcpServers": {
      "foldkit-devtools": { "command": "node_modules/.bin/foldkit-devtools-mcp" }
    }
  }
  ```
- **Vendoring is a script, not `git subtree`.** `scripts/vendor-foldkit.sh` copies Foldkit's
  repository at the pinned release tag into `repos/foldkit`, which is gitignored. It leaves out
  Foldkit's own copy of Effect and its maintainer agent files (`AGENTS.md`, `CLAUDE.md`,
  `.mcp.json`, `.claude/`, `.agents/`), which would otherwise load as instructions for this
  project. `AGENTS.md` here is the project's own; it has no `subtree_prompted` line, and nobody
  needs to offer the subtree.
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
````

### Step 3: Generate the pack's lockfile, and prove the pack green

1. Run `bash .context/plan-011/lockfile.sh`. It copies the pack to a scratch directory, fills
   the tokens, installs with pnpm, checks the pins and the peers, and copies only
   `pnpm-lock.yaml` back; pnpm never installs inside `template/`. Expect exit 0 and, near the
   end:
   - pnpm reporting that the `prepare` script patched typescript;
   - `check-pins: ok` and `No peer dependency issues found`;
   - `lockfile: wrote template/stacks/foldkit/files/pnpm-lock.yaml (… bytes)`, about 99,000;
   - one `age rule:` line. Copy it into your report. Either wording is fine:
     - `age rule: the pack's own policy accepts the lockfile`: nothing more to do;
     - `age rule: part of the train is under 24 hours old, …`: `heavy.sh` and `look.sh` will
       relax pnpm's age rule for their own runs. The pack's files do not change. Until the time
       `train.mjs` printed after `youngest:`, a new project's install and the hosted CI jobs
       fail on that rule; say so in your report.

   Any other failure is a STOP condition: an install that fails on trust, release age (of a
   package outside the train) or build scripts, a pin or peer problem (likely if `train.mjs`
   printed a `NOTE:` about a newer release), or a lockfile that names the scratch project. Never
   edit the pack's `pnpm-workspace.yaml` to get past one.

   Then check:
   - `head -2 template/stacks/foldkit/files/pnpm-lock.yaml` → `---` and `lockfileVersion: '9.0'`;
   - `git status --short template/` → only paths under `template/stacks/foldkit/`, none under
     `node_modules`.
2. Run the heavy tests and the checks:
   - `bash .context/plan-011/heavy.sh` → `selftest: 4 passed, 0 failed, 0 skipped`, then
     `heavy: ok, 4 passed in …s` (write the time down). The first run downloads the packages, the
     pinned Node and Playwright's Chromium. The script exits 1 on anything else, skips included.
   - `./scripts/check.sh` → exit 0 (gitleaks scans the pack and its lockfile).

If a heavy test fails here, STOP and report its output: the rehearsed pack passed, so something
differs in your environment or in a newer transitive dependency. Do not edit the pack to make
it pass.

### Step 4: Document the pack, and record the second JavaScript pack

1. In `TEMPLATE.md` → `## Stack packs`, extend the "Available:" paragraph so it also names
   `foldkit`. Replace its last two lines,

```markdown
gates from `_rust-gates`) and `omarchy-plugin` (an Omarchy 4 shell plugin: a QML bar widget,
JavaScript logic at 100% coverage, Omarchy's own validator pinned).
```

   with these four:

```markdown
gates from `_rust-gates`), `omarchy-plugin` (an Omarchy 4 shell plugin: a QML bar widget,
JavaScript logic at 100% coverage, Omarchy's own validator pinned) and `foldkit` (a browser app:
Foldkit on Effect v4, TypeScript 7 with the Effect language service, Vite 8, Vitest 5 Story and
Scene tests, Playwright journeys, pnpm 12, with per-tier line, branch and function floors).
```

2. Directly above the line `## Note` (after the Omarchy table and its paragraphs), add this
   section, followed by a blank line:

```markdown
### Browser apps: choose by what the app should do

| The app should… | Pack | Stack |
|---|---|---|
| run in the browser, with real client-side state | `foldkit` | Foldkit (the Elm architecture) on Effect v4, TypeScript 7 |

The foldkit pack pins its whole train exactly (`foldkit`, every `@foldkit/*`, `effect` and
every `@effect/*` but the `@effect/tsgo` patcher move together; Foldkit pins one exact Effect
version) and ships a reviewed `pnpm-lock.yaml`, so a new project installs exactly the tree the
self-test built. Installs honor a 24-hour release age and deny dependency build scripts
(`pnpm-workspace.yaml`). To move the train or the toolchain, follow the maintenance notes of
`plans/011-stack-pack-foldkit.md`: never run pnpm inside `template/`.
```

3. In `### Verifying a change`:
   - replace the whole line
     `that need gitleaks or uv are skipped locally when it is missing; CI installs both and treats`
     with
     `that need gitleaks, uv or node are skipped locally when it is missing; CI installs them and treats`
     (the sentence is wrapped, so edit that one line; the rest of the paragraph stays);
   - at the end of the paragraph that starts "Tests named `test_heavy_*` build real projects",
     directly below its last line (plan 010's
     ``The omarchy-plugin heavy test also needs Node 22.8+ and a Qt 6 `qmltestrunner` (`QML_TEST_RUNNER`).``),
     add these two lines:

```markdown
The foldkit heavy tests need pnpm 12 and the network: they install the pack's locked tree into
your normal pnpm store, vendor Foldkit from GitHub and run Playwright's Chromium.
```

4. In `TODOS.md`, directly above `## Completed`, add this item, followed by a blank line:

```markdown
### A second JavaScript pack: React 19.3 + TanStack Router on Effect v4

**What:** A `react` stack pack beside `foldkit`, for browser apps that want React's component
ecosystem and a router: React 19.3 and TanStack Router for the UI, an Effect v4 data and state
layer (Atom through `@effect/atom-react`), Vitest Browser Mode on Playwright, and the foldkit
pack's pins, shipped lockfile, tier checker and CI shape.

**Why:** Packs are chosen by what the app does. foldkit suits apps whose state fits one
Elm-style Model; many browser apps want React components and libraries instead.

**Context:** Prototyped on 2026-09-25 while choosing the first JavaScript pack (every gate
passed; Effect + Atom added about 51 kB gzip over plain React + Router). Lessons from that
prototype, on Effect 4.0.0-rc.117, to re-check on the stable release: a component test that
seeds the result atom through `RegistryProvider` still runs the live layer and makes a real
`fetch` (seeded values count as stale), so seed the Atom runtime's layer with the service over a
fake `HttpClient`; `@effect/atom-react` peered on `scheduler <0.28.0` while React 19.3 needs
`^0.28.0`, so two schedulers got bundled; Vitest Browser Mode needs `optimizeDeps.include` for
React on a cold cache.

**Effort:** L
**Priority:** P3
**Depends on:** plan 011 (its pnpm, lockfile and tier-checker patterns; extract a shared
partial pack when a third JavaScript pack appears)
```

**Verify**:

- `grep -c 'Browser apps: choose by what the app should do' TEMPLATE.md` → `1`;
- `grep -c 'uv or node are skipped locally' TEMPLATE.md` → `1`;
- `grep -c 'and `foldkit` (a browser app:' TEMPLATE.md` → `1`;
- `grep -c 'The foldkit heavy tests need pnpm 12' TEMPLATE.md` → `1`;
- `grep -c 'A second JavaScript pack' TODOS.md` → `1`;
- gstack's TODOS structure (`## Completed` last, a `**Priority:**` on every item), checked on
  the root file with this one command, which must print `TODOS ok`:

```sh
[ "$(grep '^## ' TODOS.md | tail -n 1)" = "## Completed" ] && awk '/^### /{ if (item && !prio) bad=1; item=1; prio=0 } /^\*\*Priority:\*\* P[0-4]/{ prio=1 } /^## /{ if (item && !prio) bad=1; item=0 } END { if (item && !prio) bad=1; exit bad }' TODOS.md && echo "TODOS ok"
```


### Step 5: Full verification and a manual look

Run these three, one at a time:

```sh
SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh   # baseline + 5 passed, 0 failed
bash .context/plan-011/heavy.sh                                # heavy: ok, 4 passed in …s
./scripts/check.sh                                             # exit 0
```

If the first command reported `0 skipped`, also run
`CI=true SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh` (same result; under
`CI=true` any skip fails). If it skipped tests for tools missing on this machine (the baseline's
named skips), don't run it; record the skips instead. They are not a STOP.

Then look at a real project: `bash .context/plan-011/look.sh`. It copies the working tree to a
scratch directory, bootstraps "Demo App" there with a sandboxed `HOME`, and runs the project's
whole gate. Expect exit 0 and, in order:

- bootstrap printing "Installed the locked dependencies" and "Vendored foldkit@0.165.0";
- `OK: checks passed.` from `check.sh`;
- a coverage summary of 100% statements, branches, functions and lines, then
  `coverage-tiers: ok`;
- Playwright reporting `1 passed`;
- the production build listing `dist/assets/index-….js` at about 314 kB (103 kB gzip);
- a `tsc --version` line that contains `+effect-tsgo`;
- a listing of `repos/foldkit` with no `AGENTS.md`, `CLAUDE.md` or `repos`;
- `dev server: serves the app on port 3000` (or the note that port 3000 was busy), then
  `look: ok in …s, project kept at …`. On a failure it prints `look: FAILED` and where it left
  the project.

Record the suite lines, the times `heavy.sh` and `look.sh` printed, the `age rule:` line and any
`NOTE:` from `train.mjs` in this plan's status row.

## Test plan

Nine new tests in `scripts/template-selftest.sh` (step 1), modeled on the python pack's tests
(`test_stack_python_*`) and plan 008's heavy tests:

- Light, run in the `selftest` job:
  - `test_stack_foldkit_rejects_unusable_names_before_mutation`: dependency names (any case),
    `node_modules` and a 51-character name exit 2 with no file changed.
  - `test_stack_foldkit_coverage_tiers_fail_closed` (node): every floor at and below its
    boundary, missing and unmeasurable members, malformed and inconsistent summaries, files
    outside the project, `--report`'s exact table, `--input`, usage errors, and every config
    validation rule including journey titles.
  - `test_stack_foldkit_coverage_tiers_ratchet` (node, git): unchanged, pre-pack base, unknown
    and option-shaped refs, lowered minimum and target, removed tier and member, emptied tier,
    a `retired` move, and malformed, invalid and unreadable bases.
  - `test_stack_foldkit_pin_guard_fails_closed` (node): `check-pins.mjs` against a synthetic
    `node_modules`, with every version read from the pack's `package.json` so it survives a
    train move: version drift, bad `VERSION`, ranges, the byte form, invalid JSON, runtime and
    package-manager pins, the Effect train, an installed package at another version than its
    pin, missing packages, foldkit's peers, sibling peers, unknown range forms and devtools
    lockstep.
  - `test_stack_foldkit_template_ci_matches_the_pack`: the heavy job's pnpm and `pnpm/setup`
    commit equal the pack's.
- Heavy, run in the `heavy` job:
  - `test_heavy_stack_foldkit_project_is_green_on_first_run`: bootstrap "Demo App"; the filled
    names; the installed, patched and vendored project; no placeholder left; git commits every
    pack file and ignores every artifact; then check.sh, coverage.sh, Playwright and the build,
    leaving a clean tree.
  - `test_heavy_stack_foldkit_longest_name_passes_guards_and_tests`: the 50-character name.
  - `test_heavy_stack_foldkit_version_bump_keeps_the_gate_green`: a gstack-style bump keeps the
    lockfile, the guards and the build green.
  - `test_heavy_stack_foldkit_guards_fail_closed`: `Date.now()` in `src/main.ts`, a Foldkit
    import in `src/domain`, `vi.mock`, a numeric `devToolsMcpPort`, `npx` in `.mcp.json`,
    version drift, a caret range, a reformatted `package.json`, a stale lockfile, a lockfile the
    supply-chain policy rejects (named as such, not as stale), an unpatched `tsc` and a missing
    pnpm each fail the guard; an untested module fails the global floor by name; an
    unmeasurable tier member fails its tier; the ratchet catches a lowered minimum and a removed
    member.

The rehearsals mutation-checked these assertions: each test failed when the behavior it guards
was broken. The pin-guard test also passed against a made-up future train. After you add a test
of your own, check it the same way: break the behavior it guards, see it fail, restore.

## Done criteria

- [ ] `SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh` exits 0 with baseline + 5
      passed; with `CI=true` too, unless this machine skips tests for missing tools (then the
      skips are recorded, not a failure)
- [ ] `bash .context/plan-011/heavy.sh` ends with `heavy: ok, 4 passed in …s`
- [ ] `./scripts/check.sh` exits 0; the Shell lint command and the YAML command exit 0
- [ ] `shasum -a 256 -c .context/plan-011/pack.sha256` → 43 lines, all `OK` (the pack is still
      the rehearsed one)
- [ ] `template/stacks/foldkit/files/pnpm-lock.yaml` exists, and
      `git status --short template/` shows nothing under `node_modules`
- [ ] `grep -rnE '\{\{|\}\}' template/stacks/foldkit/files | grep -vE '\{\{(PROJECT_NAME|PACKAGE_NAME|YEAR)\}\}'` prints nothing
- [ ] `bash .context/plan-011/look.sh` ends with `look: ok in …s, project kept at …`
- [ ] `git status --short` shows only in-scope files (nothing from `.context/`)
- [ ] `plans/README.md` status row updated with the counts, the train, the timings and the
      `age rule:` line

## STOP conditions

Stop and report back (do not improvise) if:

- **The helpers.** A line of `helpers.sha256` is not `OK`, or a helper prints `STOP`.
- **The train.** `train.mjs` ends with `train FAILED` (a pinned release was unpublished or
  deprecated, or its peers changed).
- **Tools.** pnpm 12 or Node 22+ is missing.
- **Predecessors.** `contracts.sh` prints `DIFFERS` without an explanation in the plan index,
  or a predecessor test fails.
- **The rehearsed pack.** `step-2.sh` shows a checksum line that says `FAILED`, or the heavy
  tests fail in step 3. (A failed download in `step-2.sh` is not a STOP: run it again.)
- **Installs.** `lockfile.sh` fails for any reason. Never edit the pack's `pnpm-workspace.yaml`,
  never add a dependency, and never change a pin to get past it.
- **Scope.** A step would need an edit outside "In scope", a changed test assertion, or a
  lowered floor.
- **Hosted CI** (only once the operator has pushed: this plan never pushes).
  - Expected, not a STOP: until the train is 24 hours old, the template's `heavy` job and a new
    project's CI fail with `ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION`. Re-run them after the time
    `train.mjs` prints.
  - A STOP: a GitHub Actions run fails on `pnpm/setup`, `actions/setup-node` on `ubuntu-slim`,
    or `playwright install --with-deps`. None of these was testable before execution.
  - A STOP: the `heavy` job's first run takes more than 30 minutes (its timeout is 45).

## Maintenance notes

- **Every Foldkit or Effect bump is a train.** Work on `template/stacks/foldkit/`, and run pnpm
  only in a scratch copy (a bootstrapped project, or `files/` copied out with the placeholders
  filled), never inside `template/`:
  1. Pin the new train in the pack's `package.json`, keeping `JSON.stringify(pkg, null, 2)`
     form: `foldkit`, every `@foldkit/*` (`@foldkit/ui` included: it is `@foldkit/devtools`'s
     peer), `effect` and every `@effect/*` except `@effect/tsgo`. `@foldkit/devtools` and
     `@foldkit/ui` equal `foldkit`; each sibling is the release published with that Foldkit
     release, and all of them peer on the same exact `effect`.
  2. Point `.foldkit-ref` at the new `foldkit@<version>` tag's commit (`git ls-remote
     https://github.com/foldkit/foldkit.git refs/tags/foldkit@<version>`): `check-pins.mjs`
     fails until its version matches the pin, and `vendor-foldkit.sh` refuses a tag that
     resolves to another commit.
  3. Replace the pack's `FOLDKIT.md` whole with the new tag's
     `packages/create-foldkit-app/templates/base/FOLDKIT.md`. It must contain no `{{` or `}}`.
  4. Regenerate the lockfile in the scratch copy with `pnpm install --lockfile-only`, starting
     from the current lockfile so only what moved re-resolves. pnpm 12.6.0 can keep an old
     locked version when a pin moves from a prerelease to its release (`4.0.0-rc.116` →
     `4.0.0`; fixed in pnpm 12.8.2); `check-pins.mjs` catches that, and deleting that one
     package's entries before resolving avoids it. The new `pnpm-lock.yaml` comes back only
     through a pull request whose reviewer reads the complete lockfile diff: both YAML
     documents, the `importers`, every `packages` resolution and integrity, and the
     `snapshots`. List every added, removed or changed `name@version` in the description as a
     guide to that diff, not a substitute for it.
  5. Run the heavy tests; fix only the starter (`src/**`, `e2e/**`, the configs) for API
     changes, following Foldkit's changelog (`packages/foldkit/CHANGELOG.md` at the release
     tag). Keep tiers 1 and 2 at 100%.

  New projects copy the pack as it is at bootstrap; a project upgrades on its own schedule with
  the steps in its `docs/guides/foldkit.md`.
- **The 24-hour rule and a same-day train.** A release under 24 hours old fails every install
  under the pack's policy, frozen ones included. Wait a day, or add exact `name@version`
  entries for the new train's releases to `minimumReleaseAgeExclude` in `pnpm-workspace.yaml`
  in the same change that moves the pins, and remove them once the releases are a day old.
  `check-pins.mjs` accepts an exemption only for a train package at the version `package.json`
  pins. Never exempt a bare name or a scope, and never set `pnpm_config_minimum_release_age=0`:
  the guard and `after-bootstrap` clear pnpm's policy variables from the environment, so the
  file's policy is the one that applies.
- **A manual look** at the starter: `pnpm dev` serves on 3000 and `pnpm preview` on 4000, both
  with `strictPort`. Check that neither port is taken first (`lsof -iTCP:3000 -iTCP:4000
  -sTCP:LISTEN` prints nothing), so a busy port isn't mistaken for a broken app.
- **Toolchain bumps** (TypeScript, @effect/tsgo, Oxlint, Oxfmt, Vite, Vitest, Playwright, pnpm,
  Node) are separate, deliberate changes: check @effect/tsgo's support matrix for the
  TypeScript version, regenerate the lockfile, run the heavy tests. Move Node to 26 once it is
  LTS (2026-10-28), in `.node-version` and `devEngines.runtime` together. Move pnpm to 12.8.2
  or later with the next bump. Keep the heavy job's pnpm equal to `packageManager` (a light
  test enforces it).
- **The DevTools relay.** The pack sets `devToolsMcpPort: false`, and `scripts/check-rules.mjs`
  accepts only that or no option at all (the token-protected relay) in the one `foldkit()` call
  of `vite.config.ts`. Whether to turn the token-protected relay on by default is the
  maintainer's call; the guide documents the opt-in.
- **gstack `/health`** calls a bare `tsc`, `eslint` and `biome`; in a foldkit project none is on
  `PATH`, and a missing tool counts as a failure. A skeleton-level "Health Stack" section in
  CLAUDE.md naming `pnpm exec tsc --noEmit`, `pnpm exec oxlint …` would fix it for every pack;
  that is a separate change to the skeleton.
- **FOLDKIT.md** still says the DevTools MCP is pre-wired, and asks agents to offer a `git
  subtree` when AGENTS.md says `subtree_prompted: false`. This project's AGENTS.md has no such
  line, and `docs/guides/foldkit.md` documents both deviations. Never edit FOLDKIT.md; Foldkit
  replaces it whole.
- **The vendored copy** keeps Foldkit's published skills plugin (`.claude-plugin/` and
  `skills/`). They are Foldkit's user-facing skills, not its maintainer files, and nothing loads
  them from `repos/foldkit` by itself. If an agent host starts to, add them to
  `vendor-foldkit.sh`'s exclusions.
- **The lockfile check** (`pnpm install --frozen-lockfile --lockfile-only`) needs the registry
  once per pnpm cache, for pnpm's supply-chain verification; with a cold cache and no network
  it hangs instead of failing. `pnpm exec` also installs silently after `package.json`
  changes, so the guard runs its package.json checks first.
- **`@foldkit/vite-plugin` depends on `@effect/platform-node`**, which brings `redis`, `undici`
  and `ws` into a browser starter's lockfile. None of them reaches the bundle.
- **Effect 4.0.0 marks its HTTP client as unstable API.** `@effect/tsgo` 0.45.0 does not report
  it; newer patchers do, as a warning that the guard treats as a failure. Decide what to do
  about it when the patcher is bumped.
- **A second JavaScript pack** (TODOS.md) should copy this pack's `check-pins.mjs`,
  `coverage-tiers.mjs`, CI shape and lockfile pattern; extract a shared partial pack only with
  the third.
- **Review focus**: the version-agnostic tests (they must keep passing after every train move),
  the guard's fail-closed order (package.json checks before the first `pnpm exec`), and the
  vendoring script's exclusions.

## Rehearsal evidence (2026-09-25 to 2026-10-02)

Four passes on scratch copies, on macOS arm64, with pnpm 12.6.0 (pnpm ran the pinned Node
24.21.0 for project commands), gitleaks 8.30.1 and shellcheck 0.11.0:

1. 2026-09-25: built the pack on Foldkit 0.163.0 and Effect 4.0.0-rc.116, on `98063fc` plus
   stand-ins for the unbuilt plans 008 and 010.
2. 2026-09-26: applied review fixes.
3. 2026-10-02: moved the train to Foldkit 0.165.0 and Effect 4.0.0 with the toolchain pins
   unchanged. Seven pack files changed: the pins, four import paths (`effect/unstable/http`
   became `effect/http`), `devToolsMcpPort: false`, and the guide.
4. 2026-10-02: moved the work onto the real plans 007–009 (`98b35eb`) and hardened the pin
   guard and the lockfile guard's message. Every file in step 2 is this pass's final tree,
   copied mechanically into this plan.

- **Suite, pass 4** (on `98b35eb`, before plan 010 existed; these are not your numbers).
  - The baseline was 166 passed and 1 skipped: `test_stack_rust_coverage_gate_passes`, because
    cargo-llvm-cov is not installed on the rehearsal machine.
  - Final: 171 light tests passed with the same skip (the 6 heavy tests excluded), and the 4
    heavy foldkit tests passed in 64 s. Because of the skip, no `CI=true` run was made.
- **This plan's own mechanics** (on `b185770`, the code you start from). On a fresh clone,
  the preflight command, the helpers and steps 1–3 and 5 were replayed as written.
  - The extracted helpers and the pack came out byte-identical to the rehearsed tree.
  - The red state after step 1 was `0 passed, 5 failed, 4 skipped`.
  - `lockfile.sh`, `heavy.sh` (4 passed, about a minute) and `look.sh` exited 0.
  - On that machine the light suite went from 171 passed and 1 skipped (3 heavy excluded) to
    176 passed and 1 skipped (7 heavy excluded). The skip is the cargo-llvm-cov one.
- **A new "Demo App" project, the full gate.**
  - `./scripts/check.sh` exited 0, and gitleaks found no leaks, lockfile included.
  - `./scripts/coverage.sh` reported 29 tests and 100% lines, branches and functions, then
    `coverage-tiers: ok`.
  - Playwright: 1 passed.
  - `pnpm build`: 314.31 kB, 103.28 kB gzip.
  - `pnpm exec vite` served HTTP 200 on port 3000, and nothing listened on the old relay's port
    9988.
- **Fail-closed evidence.**
  - Ten assertions in the new tests failed when the behavior they guard was broken, including a
    guard without the `vi.mock` grep, a guard that accepts an unpatched `tsc`, and a vendoring
    script that keeps `AGENTS.md`. The CI-alignment test failed on each of three breakages.
  - Six mutants of `check-pins.mjs`'s installed-version check and four of the guard's
    policy-rejection branch each failed their test.
  - The pin-guard test passed with a made-up future train (foldkit 0.170.0 and siblings), where
    a hardcoded version would have failed.
- **Facts the design rests on.**
  - pnpm 12.6.0 honors `minimumReleaseAgeExclude` patterns for resolution and for the frozen
    check. With only the train exempt, a from-nothing resolution on 2026-10-02 picked
    `@types/node` 26.6.3; with the rule off it picked 26.6.4, then hours old.
  - Under the pack's own policy, every install fails while a locked release is under 24 hours
    old: `pnpm install --frozen-lockfile`, the guard's lockfile check, and every `pnpm exec` in
    a project that was installed under another setting.
  - pnpm 12.6.0 kept `effect@4.0.0-rc.116` locked when the pin moved to `4.0.0`, and exited 0.
    `check-pins.mjs` now fails that state with "node_modules has effect 4.0.0-rc.116,
    package.json pins 4.0.0".
  - `( set -eu; false; echo survived )` prints `survived` when zsh runs it inside an `&&` list.
    The same lines in a file run by bash stop at `false`.
  - After the `@effect/tsgo` patch, `node_modules/typescript/package.json` still says 7.0.2.
  - Projects named `foldkit` or `vite` pass the whole gate; one named `effect` fails `tsc`
    (`duplicatePackage`).
  - A project name of 50 characters passes `oxfmt --check`; 51 fails.
  - With another pnpm 12 first on `PATH`, `onFail: "download"` switches to the pinned 12.6.0,
    while `onFail: "error"` stops with `ERR_PNPM_BAD_PM_VERSION`. npm 11 refuses the project with
    `EBADDEVENGINES`.
  - `pnpm install --frozen-lockfile --lockfile-only` writes nothing and fails on a stale
    lockfile. Every `--offline` install fails under a `devEngines.runtime` pin, and `--dry-run`
    passes a stale lockfile.
  - pnpm 12 reads `pnpm_config_*` variables (not `npm_config_*`), and `pnpm exec` silently
    installs after `package.json` changes.
  - The vendored Foldkit copy is 21 MB and 2,685 files, with no agent files and no `repos/`.
  - The lockfile is about 99 kB and contains no project name.
- **Not verified.** No GitHub Actions job has run: `pnpm/setup` in the pack's CI and the
  `heavy` job, `actions/setup-node` on `ubuntu-slim`, and `playwright install --with-deps` on
  `ubuntu-24.04`. Linux was not rehearsed locally.

The research behind the choice (Effect's state as of 2026-09-25, and prototypes of the three
candidate stacks) lives in the planning workspace's gitignored `.context/`. It is not
committed, and this plan does not need it.
