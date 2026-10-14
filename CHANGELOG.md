# Changelog

All notable changes to the vibe-starter template itself, newest first. gstack `/ship` adds each
release entry. New projects start from their own blank changelog (`template/skeleton/CHANGELOG.md`).

## [0.4.0] - 2026-10-14

### Added
- File bugs, feature improvements, engineering tasks, discoveries, decisions, and epics with
  six GitHub issue forms, each requiring one essential answer and offering optional context.
- Use shared filing guidance for browser, agent, and CLI submissions, including category
  selection, completion criteria, existing restrictions, and verification of applied labels.
- Set up each repository's type labels from the startup instructions, confirming the target
  repository and missing labels with the user before creation and preserving existing labels.

### Changed
- The issue chooser directs contributors to the forms. The guide explains GitHub's maintainer
  and CLI/API exceptions and how to configure a private reporting route.

## [0.3.0] - 2026-10-13

### Added
- Five stack packs, chosen by what the app does. `./bootstrap --stack rust` starts a Rust
  project on a pinned toolchain with clippy pedantic, rustfmt and cargo-llvm-cov's 90% line and
  region floors plus per-tier gates. `omarchy-app` is an Omarchy desktop app in its own window
  (Rust, GPUI and gpui-omarchy, which follow the active theme), `omarchy-tui` a keyboard-driven
  terminal app (Rust and ratatui), and `omarchy-plugin` a QML bar widget for Omarchy's shell,
  checked by Omarchy's own validator at a pinned release. `foldkit` is a browser app on Foldkit
  (the Elm architecture on Effect v4) with TypeScript 7, Vite 8, Vitest 5 Story and Scene tests,
  Playwright journeys and pnpm 12 with a reviewed lockfile and a supply-chain policy.
- `./bootstrap --help` and the interactive prompt list each pack with a one-line description,
  and a pack can include a partial pack (`template/stacks/_name/`): the three Rust packs share
  one copy of their gates in `_rust-gates`.
- Guards in `scripts/check.d/` learn whether CI requires a missing tool (`CHECK_CI`), and the
  template's CI gains a `heavy` job that builds real projects from every pack.

### Fixed
- Omarchy's validator cache now publishes without replacing another check's checkout and
  accepts only released commits, including on cache hits. Scripts ignore `CDPATH` when
  finding their project, and the desktop installers use the binary Cargo built, reject stale
  versions and relative install prefixes, and preserve unrelated installed tools. Failed installs
  remain recoverable, temporary-path symlinks stay untouched, and escaped launch commands survive
  reinstall and uninstall.
- Foldkit checks now validate imports, module mocks, relay configuration and MCP launchers
  with a restricted tokenizer, including executable `typeof` calls, ambiguous slash syntax,
  quoted and wrapped launch commands and Playwright config mutation, while accepting common type-only queries;
  validate every dependency section and the supply-chain policy; stop timed-out network process
  groups; distinguish command failures from deadlines and cancellation; and verify vendored
  release provenance in a separate Git checkout.
  MICRO versions display correctly, and status requests time out after ten seconds including
  response-body reads.
- Named browser journeys must run and pass in Playwright's report, and retired journeys and
  coverage members cannot remain in source. Retry preserves keyboard focus. The desktop
  button supports Tab and Enter, bar widgets support vertical layouts, and the Omarchy guards
  enforce design tokens and plain-text labels.
- All generated CI jobs have timeouts, Rust ship gates include doctests, and template tests
  verify each job's toolchain pins and commands. Offline bootstrap checks every pack's
  placeholders; Python rejects names whose source directories bootstrap would skip; plugin
  version metadata survives ordinary Git copies. Heavy lint regression checks accept both
  Oxlint diagnostic reporters without weakening their failure assertions.

## [0.2.1] - 2026-10-04

### Added
- An implementation plan for a `foldkit` stack pack (plan 011): a browser app on Foldkit, the Elm
  architecture on Effect v4, with TypeScript 7 and the Effect language service's checks, Vite 8,
  Vitest 5 tests that click the real view without a browser, a Playwright journey, and pnpm 12
  with a shipped lockfile. The pack doesn't exist yet: the plan runs after plans 007–010, one
  pull request at a time.
- The plan index records why Foldkit came first (a React + Effect pack stays on the backlog), the
  guardrails agreed for it, the alternatives rejected, the pnpm 12 install it needs, and what to
  check before the plan runs or ships.

## [0.1.1] - 2026-09-28

### Added
- Three implementation plans for Omarchy stack packs, chosen by what the app should do: an app
  in its own window (Rust with GPUI and gpui-omarchy, plan 008), a keyboard-driven terminal app
  (Rust with ratatui, plan 009), and a shell plugin for the bar (QML, checked by Omarchy's own
  plugin validator at a pinned commit, plan 010). The packs don't exist yet: each plan is ready
  to hand to an agent, one pull request at a time, after plan 007.
- Each plan's code was built and gated in a rehearsal of the template, and its pre-landing review
  is recorded in the plan index. New projects from these packs follow the Omarchy theme: colour
  guards (in the Omarchy packs only) refuse fixed colours and gradients, a plugin's setup step
  never loads it into the desktop, and projects named like a starter module (`app`, `cli`)
  still compile.

### Changed
- Plan 007 (the plain Rust pack) now formats the starter after naming it, keeps the project's
  name out of doc comments so names like `MyApp` or `my_tool` pass clippy, and lets a first pull
  request pass the coverage ratchet when its base predates the pack. It adds three tests.

## [0.1.0] - 2026-09-25

### Added
- `./bootstrap --stack python` starts a project ready to ship: Python 3.14 managed by uv, ruff for
  lint and format, ty for type checks, and pytest. It has live CI from its first push, takes its
  version from the `VERSION` file gstack `/ship` bumps, and has every command placeholder in its
  docs filled in.
- New Python projects enforce the testing doctrine's coverage gates. `./scripts/coverage.sh`
  checks separate 90% line and branch floors plus per-tier minimums, and CI's ratchet stops a pull
  request from lowering a floor or dropping a module from its tier. A rename or deletion goes
  through the tier's `retired` list, so it shows up in review.
- Stack packs are an opt-in mechanism in `template/stacks/<name>/`, so more languages can follow.
  Without `--stack`, or with `--stack none`, a project stays stack-agnostic exactly as before; at
  a terminal, bootstrap offers the available packs. Bad stack names and project names a Python
  project can't use are rejected before anything changes, and a retried bootstrap finishes with
  the pack the first attempt chose.
- `scripts/check.sh` runs every guard in `scripts/check.d/`, so a project or a stack pack can add
  its own pre-test checks.

### Changed
- Every workflow installs gitleaks through one pinned, checksum-verified action
  (`.github/actions/install-gitleaks`), which new projects keep.
- The template's CI installs a pinned uv and lints the stack packs' scripts, so every pull request
  bootstraps a Python project and runs its checks, coverage gates and CI steps end to end.
- `TEMPLATE.md` documents stack packs and how to add one.
- Template maintenance: 35 new self-tests (143 in total), and the plan index marks plan 006 done.

## [0.0.5] - 2026-09-25

### Added
- New projects start from their own blank `VERSION` (0.0.0), `CHANGELOG.md` and `TODOS.md`, kept in
  `template/skeleton/`, so gstack `/ship` can version and log the template itself without that
  history reaching every project made from it.
- `.bootstrapped` records which template version a project came from:
  `<date> from vibe-starter <version>`.
- Markdown between `<!-- template-only:start -->` and `<!-- template-only:end -->` lines is removed
  by `./bootstrap`. `AGENTS.md` uses it to tell agents they are in the template itself, and
  `TESTING.md` uses it to give `/ship` the template's test and check commands.
- The bootstrap checklist tells a new project to commit the result to its default branch before
  branching or running `/ship`, which compares `VERSION` with the base branch.

### Changed
- The root `VERSION`, `CHANGELOG.md` and `TODOS.md` belong to the template now. The template's
  `TODOS.md` and the new-project skeleton follow gstack's TODOS format, so `/ship` no longer asks
  to reorganize them.
- `TEMPLATE.md` explains skeleton, template-owned and template-only files, how to ship the
  template with gstack, and bootstrap's new exit 1.

### Fixed
- `./bootstrap` checks template-only markers before it changes anything: an unmatched, nested,
  unclosed, indented, trailing-space or CRLF marker stops it with exit 1 instead of shipping
  maintainer notes. A bad `VERSION` or a missing skeleton is also caught first, and a run that
  fails later, including during the final cleanup, can be retried with the same arguments.
- `./bootstrap` stops before marking the project done if a template-only block could not be
  removed, and it leaves nested checkouts (worktrees, submodules) alone.
- Template maintenance: 28 new self-tests (108 in total), including a golden inventory of every
  skeleton placeholder that fails if a doc tool fills one in or drops it, and the plan index
  marks plan 005 done.

## [0.0.4] - 2026-09-24

### Changed
- Agents entering through either `AGENTS.md` or `CLAUDE.md` must read both files once before
  task work; each file keeps its existing responsibilities and placeholders.
- Agent skill routing uses host-supported invocation and current context-save, context-restore
  and run names; `TESTING.md` exposes check/test commands alongside `CLAUDE.md`.
- README, template guidance and the bootstrap checklist describe the companion instruction
  files, and the remaining implementation plans preserve this layout.

### Added
- Six source/generated-project regression tests for companion reading, skill routing,
  command discovery and onboarding, bringing the template suite to 80 tests.

## [0.0.3] - 2026-09-24

### Added
- `scripts/check.sh` fails in CI when gitleaks is missing, instead of passing without a scan.
  Any `CI` value except empty, `false`, `0` or `no`, or a known CI vendor variable, counts as
  CI; `CI=false` keeps the local skip.
- The inert CI skeleton (`ci.yml.example`) installs a pinned, checksum-verified gitleaks 8.30.1
  before the check, runs with read-only repository permissions, and uses `actions/checkout@v7`.
- `check.sh` works as a git pre-commit hook, linked or wrapped. Committing in a linked worktree
  runs that worktree's own copy against it, and a worktree whose branch has no `check.sh` is
  refused rather than checked against another checkout.

### Changed
- The secret scan covers exactly what git would commit: a gitignored `.env` holding real local
  credentials no longer fails the check, while a force-added or untracked committable file does.
- Findings print as `file:line:rule`, never the secret or the text around it (gitleaks' verbose
  output could show a second secret on the same line).
- `.env.example` can be committed, and example env files (`.env.example`,
  `.env.<name>.example`) are allowlisted by file name only.
- The secret scan needs gitleaks 8.22 or newer; an older one gets a clear message instead of a
  flag error.

### Fixed
- The check scans its own project when run from another directory, through a symlink, with
  `CDPATH` set, with a relative `GITLEAKS_BIN` or `TMPDIR`, or with `GIT_DIR`/`GIT_WORK_TREE`
  exported for another repository.
- A project in a subdirectory of a larger repo gets its committable files scanned, and a copy no
  repository would commit (not yet `git init`-ed) has every file scanned instead of none.
- git errors such as dubious ownership are reported as such instead of triggering a misleading
  scan of every file, and a `safe.directory` passed through `GIT_CONFIG_*` is honored.
- A failed copy of the files to scan fails the check, and the temporary copy is always removed.
- Template maintenance: 40 new self-tests (74 in total) cover these paths, and the plan index
  marks plan 002 done.

## [0.0.2] - 2026-09-24

### Added
- `./bootstrap` names the project after its `origin` repo (else the folder), so agent runs and
  Conductor workspaces no longer produce projects named after a workspace codename.
- `./bootstrap` refuses to run (exit 3) inside the vibe-starter template itself, whatever the
  case or shape of its origin URL, and in a folder whose `.git` git can't read. The message
  shows how to point `origin` at your own repo; `--force` overrides, with a warning if origin
  still points at the template.
- The first-run checklist now lists `docs/architecture.md`.

### Changed
- Bad arguments fail loudly with exit 2: `--name` with no value, an empty name, or a flag
  passed as the name. Names must start with a letter or digit and use plain ASCII on every
  platform, and a rejected default says where it came from and how to override it.

### Fixed
- Worktrees and submodules (where `.git` is a file) count as existing repositories: no stray
  `git init` or false "fresh repository" message, and an existing `.git` is never
  re-initialized.
- A copy nested inside another repo uses its own folder name instead of the outer repo's.
- The origin URL, which can carry a token, is never printed.
- Template maintenance: 23 new self-tests (34 in total) cover these paths, and the plan index
  marks plan 003 done.

## [0.0.1] - 2026-09-23

### Added
- Seven ordered implementation plans for template self-tests, safer checks and bootstrap,
  one shared agent instruction file, template maintenance, and optional Python and Rust stacks.
- A plan index with dependencies, verification evidence, and separate PR execution guidance.

## [0.0.0] - 2026-06-12

### Added
- Initial template scaffold (#1): doctrine files (`CLAUDE.md`, `AGENTS.md`, `DOCTRINE.md`,
  `TESTING.md`, `ENGINEERING.md`), working-doc skeletons, config, an inert CI example,
  `./bootstrap`, and `scripts/check.sh`.
