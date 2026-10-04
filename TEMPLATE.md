# vibe-starter

A stack-agnostic project template that ships a doctrine spine, so a new repo starts carrying
my conventions instead of empty. This file is removed by `./bootstrap`.

## Use it

1. Create a repo from this template:
   - GitHub: **Use this template**, or `gh repo create <name> --template willtraweek/vibe-starter`
   - or a no-history copy: `npx degit willtraweek/vibe-starter <name>`
2. `cd <name> && ./bootstrap`  (or `./bootstrap --name <name> --yes`). Add `--stack python` to
   start with a ready-to-ship language pack (see Stack packs below). Then commit the result to
   the default branch before you branch or run gstack `/ship`: `/ship` compares `VERSION` with
   the base branch, which holds the template's version until then.
3. Fill in the placeholders the checklist prints and start building.

`./bootstrap` personalizes the bootstrap-owned placeholders, optionally notes gstack, prints a
first-run checklist, and then deletes itself and the template-only paths listed below.

The project name defaults to the `origin` remote's repo name, else the directory name. Bad
arguments exit 2. In the vibe-starter template repo itself, or where git can't read the
directory's `.git`, it refuses with exit 3; pass `--force --name <name>` to run anyway. A
malformed template-only marker, a missing `template/skeleton/` file or an invalid template
version stops it with exit 1 before it changes anything; after a later failure, fix the cause
and rerun with the same arguments.

## What's inside

- `CLAUDE.md`, `AGENTS.md` — companion instructions for every coding agent. Each requires reading
  the other once; keep both files and preserve their division of responsibilities.
- `DOCTRINE.md` — the cross-project ethos (completeness, primitives-complete, CLI-as-contract,
  deterministic/gray-space, estimate framing).
- `TESTING.md`, `ENGINEERING.md` — the testing doctrine and code-organization standards.
- `README.md`, `docs/`, `.context/` — working scaffold; a new project's own `VERSION`,
  `CHANGELOG.md`, `TODOS.md` come from `template/skeleton/`.
- `DESIGN.md`, `MISSION.md` — optional; delete if a project doesn't need them.
- config: `.gitignore`, `.editorconfig`, `.gitleaks.toml`, an inert `.github/workflows/ci.yml.example`,
  and `.github/actions/install-gitleaks/` (the pinned gitleaks install every workflow uses).
- `scripts/check.sh` — the stack-neutral pre-test guard: a gitleaks scan of what git would commit
  (gitleaks 8.22+; skipped locally if missing, required in CI) and editorconfig-checker if present.

## Stack packs

`./bootstrap --stack <name>` also installs an opt-in language pack from `template/stacks/<name>/`.
Without `--stack`, the project stays stack-agnostic, exactly as before. A pack is:

- `files/`: copied into the project root. A path segment named `__package__` becomes the
  package name (the project name in snake_case). `{{PROJECT_NAME}}`, `{{PACKAGE_NAME}}` and
  `{{YEAR}}` are replaced like everywhere else.
- `commands`: `KEY=value` lines that fill the matching `{{KEY}}` / `{{KEY: ...}}` placeholders
  (install, dev, build, check, test commands, the stack summary, the ship gate, and coverage
  enforcement).
- `gitignore`: replaces the commented "Language sections" block of `.gitignore`.
- `validate-name` (optional): runs before any file is written, as
  `sh validate-name PACKAGE_NAME PROJECT_NAME`; it rejects unusable names with a nonzero exit
  (Python: keywords, names the standard library, uv or the pack's tools already use, and names
  over 60 characters; Rust: keywords, the standard library's crate names, and names that clash
  with Cargo's build directories).
- `after-bootstrap` (optional): runs once at the end, for example to write the lockfile.

A pack's `files/.github/workflows/ci.yml` replaces `ci.yml.example`, activating the new project's
CI. Resolve any lockfile-hook warning and run the full gate before the first push. Stack guards
go in `files/scripts/check.d/<name>.sh`; `scripts/check.sh` runs every `scripts/check.d/*.sh`.
The self-test runs each real pack end to end: bootstrap a project, then run that project's own
checks and tests.

Available: `python` (uv, ruff, ty, pytest with separate 90% line and branch floors) and `rust`
(pinned toolchain, clippy pedantic, rustfmt, cargo-llvm-cov with 90% line and region floors).

## Note

The testing doctrine is carried as *philosophy*; the coverage gates are per-stack. Don't
scaffold a coverage gate until you've chosen a language and test runner.

## Maintaining the template

This repo is two things at once: the template's own project, and the skeleton every new
project starts from. Keep them apart:

- **Skeleton files** are what a new project starts with: `AGENTS.md`, `CLAUDE.md`, `DOCTRINE.md`,
  `TESTING.md`, `ENGINEERING.md`, `README.md`, `DESIGN.md`, `MISSION.md`, `docs/`, the config
  files, `scripts/check.sh`, `.github/workflows/ci.yml.example`, and `template/skeleton/` (the
  project's own `VERSION`, `CHANGELOG.md`, `TODOS.md`). Their `{{...}}` placeholders are
  intentional.
- **Template-owned files** describe the template itself: the root `VERSION`, `CHANGELOG.md` and
  `TODOS.md`. gstack `/ship` bumps and writes them. `./bootstrap` swaps in the skeleton copies
  and records the template version in the new project's `.bootstrapped`.
- **Template-only paths** are deleted by `./bootstrap`: `TEMPLATE.md`, `template/`, `plans/`,
  `scripts/template-selftest.sh`, `.github/workflows/template-selftest.yml`, and any markdown
  between `<!-- template-only:start -->` and `<!-- template-only:end -->` lines. A repo created
  with **Use this template** still has them in its initial commit; `npx degit` copies no history.

### Verifying a change

```sh
./scripts/template-selftest.sh             # every test
./scripts/template-selftest.sh bootstrap   # only tests whose name contains "bootstrap"
SELFTEST_RUST_TOOLCHAIN="$(sed -n 's/^channel = "\(.*\)"$/\1/p' template/stacks/rust/files/rust-toolchain.toml)" \
  ./scripts/template-selftest.sh           # every test, the Rust ones on CI's pinned toolchain
shellcheck bootstrap scripts/*.sh template/stacks/*/files/scripts/*.sh \
  template/stacks/*/files/scripts/check.d/*.sh template/stacks/*/after-bootstrap \
  template/stacks/*/validate-name          # CI lints first, with shellcheck 0.11.0
```

The self-test copies this working tree into a temp dir and exercises `./bootstrap` and
`scripts/check.sh` there; your checkout is never modified. It needs git, perl, and tar. Tests
that need a missing tool are skipped locally: gitleaks; uv for the Python pack; rustup with
clippy and rustfmt, and jq, for the Rust pack, plus cargo-llvm-cov and llvm-tools for its
coverage test. CI installs them all and treats skips as failures. The Rust tests use your default
stable toolchain unless `SELFTEST_RUST_TOOLCHAIN` names another, and most of them skip on one
older than the pack's pinned channel; the third command above runs them on that channel. The
Python pack tests download Python 3.14 and a few PyPI packages into your normal uv cache on first
run. CI runs it via `.github/workflows/template-selftest.yml`, which only runs on
`willtraweek/vibe-starter`.

### Shipping with gstack

`/ship` works here. It runs the self-test (TESTING.md's template-only block tells it to), bumps
the template's own `VERSION`, and writes the template's `CHANGELOG.md` and `TODOS.md`. Its docs
step may propose edits to skeleton files. Accept only changes meant for every future project,
and never let it fill in a placeholder: `test_skeleton_placeholders_are_intact` fails if one
changes.

### Placeholders

- `{{PROJECT_NAME}}` and `{{YEAR}}` are bootstrap-owned: `./bootstrap` replaces them (and
  `{{PACKAGE_NAME}}` in stack-pack files). Stack-pack files under `template/stacks/` are not in
  the golden inventory: a self-test checks they carry only those three tokens, and each pack's
  end-to-end test checks a new project has none of the pack's command placeholders left.
- Everything else is filled in by hand in the new project. The bootstrap checklist must name
  every file that still has one (`test_bootstrap_checklist_names_every_file_with_placeholders`).
- After an intentional placeholder change, review the token diff, then print the inventory with
  `./scripts/template-selftest.sh --print-inventory` and paste it into
  `test_skeleton_placeholders_are_intact`.
