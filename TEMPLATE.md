# vibe-starter

A stack-agnostic project template that ships a doctrine spine, so a new repo starts carrying
my conventions instead of empty. This file is removed by `./bootstrap`.

## Use it

1. Create a repo from this template:
   - GitHub: **Use this template**, or `gh repo create <name> --template willtraweek/vibe-starter`
   - or a no-history copy: `npx degit willtraweek/vibe-starter <name>`
2. `cd <name> && ./bootstrap`  (or `./bootstrap --name <name> --yes`)
3. Fill in the placeholders the checklist prints, choose a stack, and start building.

`./bootstrap` personalizes the bootstrap-owned placeholders, optionally notes gstack, prints a
first-run checklist, and then deletes itself and the template-only paths listed below.

The project name defaults to the `origin` remote's repo name, else the directory name. Bad
arguments exit 2. In the vibe-starter template repo itself, or where git can't read the
directory's `.git`, it refuses with exit 3; pass `--force --name <name>` to run anyway.

## What's inside

- `CLAUDE.md`, `AGENTS.md` — companion instructions for every coding agent. Each requires reading
  the other once; keep both files and preserve their division of responsibilities.
- `DOCTRINE.md` — the cross-project ethos (completeness, primitives-complete, CLI-as-contract,
  deterministic/gray-space, estimate framing).
- `TESTING.md`, `ENGINEERING.md` — the testing doctrine and code-organization standards.
- `README.md`, `CHANGELOG.md`, `TODOS.md`, `VERSION`, `docs/`, `.context/` — working scaffold.
- `DESIGN.md`, `MISSION.md` — optional; delete if a project doesn't need them.
- config: `.gitignore`, `.editorconfig`, `.gitleaks.toml`, an inert `.github/workflows/ci.yml.example`.
- `scripts/check.sh` — the stack-neutral pre-test guard: a gitleaks scan of what git would commit
  (gitleaks 8.22+; skipped locally if missing, required in CI) and editorconfig-checker if present.

## Note

The testing doctrine is carried as *philosophy*; the coverage gates are per-stack. Don't
scaffold a coverage gate until you've chosen a language and test runner.

## Maintaining the template

Changes to `bootstrap` or `scripts/check.sh` must keep the self-test and shellcheck green:

```sh
./scripts/template-selftest.sh             # every test
./scripts/template-selftest.sh bootstrap   # only tests whose name contains "bootstrap"
shellcheck bootstrap scripts/*.sh          # CI lints first, with shellcheck 0.11.0
```

The self-test copies this working tree into a temp dir and exercises `./bootstrap` and
`scripts/check.sh` there; your checkout is never modified. It needs git, perl, and tar. Tests
that need gitleaks are skipped locally when it is missing; CI installs it and treats skips as
failures. CI runs it via `.github/workflows/template-selftest.yml`, which only runs on
`willtraweek/vibe-starter`.

Template-only paths, deleted by `./bootstrap`: `TEMPLATE.md`, `scripts/template-selftest.sh`,
`.github/workflows/template-selftest.yml`, `plans/`. A repo created with **Use this template**
still has them in its initial commit; `npx degit` copies no history.
