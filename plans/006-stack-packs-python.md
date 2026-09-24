# Plan 006: Add opt-in stack packs to `bootstrap`, starting with Python (uv, ruff, ty)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Predecessor check (run first)**: complete plans 001–005 in order, then run their full
> checks and self-tests. Confirm the semantic contracts in Current state below. Step 4 makes
> targeted edits to that result; preserve plan 005's marker validation and retry-safe provenance.
> A changed hash alone is not drift; unexplained behavior or a failing predecessor test is.

## Status

- **Priority**: P2 (requested by the maintainer)
- **Effort**: L
- **Risk**: MED. `bootstrap` gains a code path, and a new project gets live CI. The no-stack path is
  pinned by an existing and a new test.
- **Depends on**: 001–005 (the harness, the guards, the hardened `bootstrap`, `AGENTS.md`/`TESTING.md`
  → Commands, and `template/`)
- **Category**: direction
- **Planned at**: commit `1984ab7` plus plans 001–005, 2026-09-23

## Why this matters

The maintainer wants a ready "default set" per language, and for Python specifically the Astral
tools: uv, ruff and ty. Today every project made from the template repeats the same manual steps
(add build files, uncomment `.gitignore`, activate CI, fill five command placeholders). None of
them ever get the doctrine's coverage gates: `TESTING.md` requires a 90% line+branch floor,
per-tier gates and a ratchet, but leaves wiring them "per stack".

The original planning inspection used native Claude gstack v1.87.5.0. Treat these as
host/version-specific observations and inspect the executor's installed skills before relying
on parser behavior; the installed Codex workflows can read AGENTS.md directly:

- When `/ship` finds tests but no documented test command, it asks and saves the answer to a
  `CLAUDE.md`. When it finds no tests at all, it sets up its own framework: it appends its "100%
  coverage" philosophy to `TESTING.md` (contradicting the tiered doctrine), adds
  `.github/workflows/test.yml`, and writes `CLAUDE.md`. A pack documents the command in
  `TESTING.md` → Commands, which is where `/ship` looks.
- gstack only ever bumps the root `VERSION` file. It never reads or writes `pyproject.toml`, and
  pointing `.gstack/version-path` at a TOML file would overwrite the whole file with the version
  string. The maintainer's own repos show the drift this causes (VERSION 1.4.15 vs Cargo 0.1.0 in
  one; hand-synced pyproject in another).
- `/ship` step 7 re-runs individual tests it generates and reverts "failing" ones. A 90% floor
  wired into every `pytest` call makes a single passing test file "fail", so `/ship` would revert
  good tests.

After this plan, `./bootstrap --stack python` produces a project that (after resolving the
best-effort lockfile hook warning, if any):

- installs with `uv sync` and uses Python 3.14;
- is linted and formatted by ruff and type-checked by ty;
- runs pytest, with the 90% line+branch floor and per-tier gates in `./scripts/coverage.sh`;
- has live CI that is green on its first push, and takes its version from the `VERSION` file
  gstack bumps;
- has every command placeholder filled in.

Without `--stack`, nothing changes. Rust follows in plan 007, using the same mechanism.

## Design decisions (each verified while planning)

- **Pack layout.** `template/stacks/<name>/` holds:
  - `files/`, copied into the project; a path segment `__package__` becomes the package name.
  - `commands`, with `KEY=value` lines that fill `{{KEY}}` and `{{KEY: description}}`
    placeholders.
  - `gitignore`, which replaces the commented language block of `.gitignore`.
  - `after-bootstrap`, an optional script that writes the lockfile, best effort.

  The pack's `files/.github/workflows/ci.yml` replaces `ci.yml.example`. `template/` is already
  deleted by `bootstrap` (plan 005), so packs never reach projects. A synthetic "fixture" pack in
  the self-test covers every mechanism step without needing uv.
- **Version: hatchling reads the root `VERSION`**:

  ```toml
  dynamic = ["version"]

  [tool.hatch.version]
  path = "VERSION"
  pattern = "(?P<version>.+)"

  [tool.uv]
  cache-keys = [{ file = "pyproject.toml" }, { file = "VERSION" }]
  ```

  Tested with uv:
  - `uv.lock` records no version for the root package.
  - After a gstack-style bump of `VERSION`, `uv lock --check` and `uv sync --locked` still pass.
  - Thanks to `cache-keys`, `--version` reports the new value.

  uv's own backend (`uv_build`) cannot read a dynamic version, so it can't keep `VERSION` as the
  single source of truth. Everything else is Astral tooling.
- **Coverage runs outside plain `pytest`.** `TEST_CMD` is `uv run pytest`: fast, with no floor, so
  it's safe for gstack's step 7. `./scripts/coverage.sh` runs `pytest --cov`, then `coverage json`, then independent
  global line and branch floors plus independent tier floors. Coverage.py's combined
  `fail_under` is disabled; it does not implement the doctrine's two separate 90% floors.
  CI and the ship gate run `coverage.sh`.
- **Tier gates.** `scripts/coverage_tiers.py` is stdlib-only and validates configuration and
  coverage JSON before using it. Global lines and branches independently meet 90%; each tier's
  `minimum` also applies separately to lines and branches. Counts must be nonnegative integers,
  hits cannot exceed totals, global totals must agree with file counters, and every declared
  member must have measurable statements. Missing/malformed counters fail closed.
  - A deliberately empty tier needs `allow_empty = true`. The initial pure-logic tier uses it.
  - Positive measured lines with explicit zero total/covered branches are genuinely branchless:
    the branch metric is `n/a (branchless)` and the line gate still applies. A missing branch
    field or an entirely unmeasured declared file is an error.
  - `--ratchet REF` rejects tier removal, lower minimum/target, and removal of established
    members even if the tier is changed to explicitly empty. Renames/removals need a dedicated
    reviewed policy migration recorded in TESTING.md's Decisions Log; silently emptying a tier
    is never a migration. Do not disable the ratchet to get a feature change green.
  - `--report` rejects malformed measurement data and prints separate line/branch columns.

  Tables live under `[tool.coverage_tiers.*]`.
- **Tool versions** (original planning snapshot; retain these choices, then verify installation
  and CI availability during the final gate):
  - Python 3.14 (3.14.4 was offered in the planning probe).
  - Tools: uv 0.12.18, ruff 0.16.8, ty 0.0.83. ty is still pre-1.0; `uv.lock` pins exact
    versions, and upgrades are deliberate.
  - CI uses `astral-sh/setup-uv` v10.2.0, pinned by commit SHA, with uv `0.12.17`.
    Its uv checksum was available to that action version in the planning probe.
  - A lockfile written by uv 0.11.6 (the maintainer's local version) passes `uv lock --check`
    and `uv sync --locked` under 0.12.17. This was tested.
- **gitleaks install moves into a composite action.** After this plan, three workflows need it
  (the template's self-test, `ci.yml.example`, the pack's `ci.yml`), so `ENGINEERING.md`'s rule of
  three says extract it. It moves to `.github/actions/install-gitleaks/action.yml`.
- **No `CLAUDE.md`.** Preserve plan 004's AGENTS.md architecture. Codex-generated gstack
  workflows may parse AGENTS.md; native Claude workflows may parse CLAUDE.md. TESTING.md's
  Commands section is the shared test-command surface. Keep host-specific advice qualified,
  and do not create a shim as part of this plan; CI's coverage gate is independent of the host.
- **Name preflight.** After normalization and before *any* file mutation, invoke an optional
  pack-local `validate-name` shell script with package name and display name. Python and Rust
  reject reserved identifiers through this interface without requiring their runtimes.

## Current state

The state after plans 001–005 is checked by behavior, not stale file hashes. Record the
passing predecessor test count as `baseline`; this revision has 40. Every final count below
means `baseline + 8` (48 for that predecessor), not a reason to delete a newly added test:

- `bootstrap` retains plan 003's argument/re-entry/worktree contracts and plan 005's skeleton
  swap, validated template-only markers, and original version persisted in
  `template/.bootstrap-version` across failed attempts.
- `scripts/check.sh` has all predecessor guards. Insert stack guards without replacing it.
- The self-test harness has 40 tests after revised plan 005. Helpers include `fresh_copy`,
  `run_bootstrap`, `tree_fingerprint`, `fail`, `skip`, `assert_*`, `$WORK`, `$REPO`, and the
  complete-token `placeholder_inventory` from plan 005. Preserve its digest and delimiter
  validation; extend only its exclusion list for stack-pack assets.
- The root instructions retain plan 005's maintainer-only blocks, and TESTING.md retains the
  shared Commands section. Preserve both when applying the pack; host-specific interpretation
  stays qualified in this plan rather than assuming plan 004's prose was rewritten.

If any contract differs, inspect the predecessor change before editing. Do not overwrite a
newer correction with one of this plan's historic prototype excerpts.

Placeholders a pack fills (all exist today): `{{INSTALL_CMD}}` (including
`{{INSTALL_CMD: e.g. ...}}`), `{{DEV_CMD}}`, `{{BUILD_CMD}}`, `{{CHECK_CMD}}`, `{{TEST_CMD}}` in
`AGENTS.md`, `README.md`, `TESTING.md`; `{{STACK: ...}}` in `README.md`; `{{SHIP_GATE: ...}}` in
`AGENTS.md`; `{{COVERAGE_ENFORCEMENT: ...}}` in `TESTING.md`.

Conventions: bash 3.2 compatible (macOS `/bin/bash`); `#!/usr/bin/env bash` + header comment +
`# --- Section ---` dividers; errors to stderr; `exit 2` for usage errors.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Self-test | `./scripts/template-selftest.sh` | `baseline + 8` passed, 0 failed/skipped (48 with revised plan 005) |
| This plan's tests | `./scripts/template-selftest.sh stack` | 8 tests, all ok |
| Shell lint | `shellcheck bootstrap scripts/*.sh template/stacks/*/files/scripts/*.sh template/stacks/*/files/scripts/check.d/*.sh template/stacks/*/after-bootstrap template/stacks/*/validate-name` | exit 0 |
| YAML | `ruby -ryaml -e 'ARGV.each(&YAML.method(:load_file))' <files>` | exit 0 |
| uv present | `uv --version` | `uv 0.11.x` or newer |

uv must be installed locally for 2 of the 8 new tests. Without it they skip, and CI (which gets
uv from `setup-uv`) treats skips as failures. They download Python 3.14 and a few PyPI packages
into your normal uv cache on first run.

## Suggested executor toolkit

- gstack `/review` on the finished diff; `/investigate` if the Python end-to-end test fails.
- Do not run gstack `/ship` unless asked.

## Scope

**In scope** (the only files you should modify or create):

- `scripts/template-selftest.sh` (step 1), `scripts/check.sh` (step 2)
- `.github/actions/install-gitleaks/action.yml` (create), `.github/workflows/template-selftest.yml`,
  `.github/workflows/ci.yml.example` (step 3)
- `bootstrap` (step 4)
- everything under `template/stacks/python/` (create, step 5)
- `TEMPLATE.md` (step 6)
- `plans/README.md` (your status row)

**Out of scope** (do NOT touch):

- `AGENTS.md`, `TESTING.md`, `README.md`: the pack fills their placeholders at bootstrap time;
  the template's copies keep them.
- Any `CLAUDE.md` (see Design decisions).
- A Rust pack (plan 007) or any other language.
- `.editorconfig` (plan 007 adds `rs` to the 4-space rule).

## Git workflow

- Work on the branch you were given (Conductor: `willtraweek/<topic>`). If you must create one:
  `willtraweek/plan-006-stack-packs-python`.
- Commit per step, plain imperative messages (e.g. `Add the Python stack pack`).
- Do NOT push or open a PR unless the operator told you to.

## Steps

### Step 1: Add the failing tests

1. In `scripts/template-selftest.sh`, directly **above** the line
   `export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1`, insert:

```bash
# Real tool homes, captured before any test sandboxes HOME (see stack_env).
REAL_UV_CACHE_DIR="${UV_CACHE_DIR:-$(uv cache dir 2>/dev/null || echo "$HOME/.cache/uv")}"
REAL_UV_PYTHON_DIR="${UV_PYTHON_INSTALL_DIR:-$(uv python dir 2>/dev/null || echo "$HOME/.local/share/uv/python")}"
REAL_CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
REAL_RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
```

2. In `placeholder_inventory`, change the `case` line
   `      bootstrap|TEMPLATE.md|plans/*|scripts/template-selftest.sh) continue ;;` to

   ```bash
         bootstrap|TEMPLATE.md|plans/*|scripts/template-selftest.sh|template/stacks/*) continue ;;
   ```

   Pack files carry placeholders on purpose. The end-to-end tests check a bootstrapped project
   has none left, so the golden inventory stays about the root skeleton.

3. Insert this block immediately **above** `# --- runner ---`:

```bash
# --- tests: stack packs (plan 006) --------------------------------------------
stack_env() {  # run "$@" with the real uv/cargo homes, so a sandboxed HOME doesn't
  # force fresh downloads of Python, crates, or toolchains on every test run.
  env UV_CACHE_DIR="$REAL_UV_CACHE_DIR" UV_PYTHON_INSTALL_DIR="$REAL_UV_PYTHON_DIR" \
    CARGO_HOME="$REAL_CARGO_HOME" RUSTUP_HOME="$REAL_RUSTUP_HOME" "$@"
}
py_tiers() {  # $1 = python-pack project dir, rest = coverage_tiers.py args -> "$1.tiers.out"
  local dir="$1"; shift
  (cd "$dir" && stack_env uv run --locked --quiet python scripts/coverage_tiers.py "$@" >"$dir.tiers.out" 2>&1)
}
test_bootstrap_rejects_unknown_stack() {
  local d="$WORK/stack-unknown/proj" before rc
  fresh_copy "$d"
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --name proj --stack cobol --yes; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "Unknown stack 'cobol'" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed despite the rejection"
}
test_stack_needs_a_letter_first_name() {
  local d="$WORK/stack-digit/proj" rc
  fresh_copy "$d"
  run_bootstrap "$d" --name 1up --stack python --yes; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "must start with a letter"
}
test_bootstrap_without_stack_directory_stays_stack_agnostic() {
  local d="$WORK/no-stack-directory/proj"
  fresh_copy "$d"
  rm -rf "$d/template/stacks"
  run_bootstrap "$d" --name proj --yes || fail "no-pack bootstrap exited $?" || return 1
  assert_contains "$d.out" "Then choose a stack" || return 1
  assert_absent "$d/pyproject.toml"
}
test_stack_python_rejects_keywords_before_mutation() {
  local d name before rc
  for name in class Async await; do
    d="$WORK/stack-keyword-$name/proj"
    fresh_copy "$d"
    before="$(tree_fingerprint "$d")"
    run_bootstrap "$d" --name "$name" --stack python --yes; rc=$?
    assert_exit 2 "$rc" || return 1
    assert_contains "$d.out" "reserved Python identifier" || return 1
    [ "$before" = "$(tree_fingerprint "$d")" ] || fail "keyword rejection changed files" || return 1
  done
}
test_bootstrap_without_stack_stays_stack_agnostic() {
  local d="$WORK/no-stack/proj"
  fresh_copy "$d"
  run_bootstrap "$d" --name proj --yes || fail "bootstrap exited $?" || return 1
  assert_exists "$d/.github/workflows/ci.yml.example" || return 1
  assert_absent "$d/.github/workflows/ci.yml" || return 1
  assert_absent "$d/pyproject.toml" || return 1
  assert_absent "$d/Cargo.toml" || return 1
  assert_contains "$d/.gitignore" "# Language sections" || return 1
  assert_contains "$d.out" "Then choose a stack"
}
test_stack_pack_mechanism_with_a_fixture_pack() {
  # Exercises every step of pack application with a synthetic pack, so the
  # mechanism is covered even where uv/cargo are not installed.
  local d="$WORK/stack-fixture/demo" p
  fresh_copy "$d"
  p="$d/template/stacks/fixture"
  mkdir -p "$p/files/src/__package__" "$p/files/.github/workflows"
  printf 'package={{PACKAGE_NAME}} project={{PROJECT_NAME}}\n' > "$p/files/src/__package__/hello.txt"
  printf 'name: ci\n' > "$p/files/.github/workflows/ci.yml"
  printf '# comment line\nTEST_CMD=fixture-test --all\nINSTALL_CMD=fixture-install\nSTACK=Fixture stack\n' > "$p/commands"
  printf '# --- Fixture ---\nfixture-out/\n' > "$p/gitignore"
  printf '#!/bin/sh\ntouch after-bootstrap-ran\n' > "$p/after-bootstrap"
  run_bootstrap "$d" --name "Demo Thing" --stack fixture --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  assert_contains "$d/src/demo_thing/hello.txt" "package=demo_thing project=Demo Thing" || return 1
  assert_contains "$d/TESTING.md" "Tests: \`fixture-test --all\`" || return 1
  assert_contains "$d/AGENTS.md" "Install deps: \`fixture-install\`" || return 1
  assert_contains "$d/README.md" "Fixture stack" || return 1
  assert_not_contains "$d/AGENTS.md" "This template is stack-agnostic" || return 1
  assert_not_contains "$d/.gitignore" "# Language sections" || return 1
  assert_contains "$d/.gitignore" "fixture-out/" || return 1
  assert_exists "$d/.github/workflows/ci.yml" || return 1
  assert_absent "$d/.github/workflows/ci.yml.example" || return 1
  assert_exists "$d/after-bootstrap-ran" || return 1
  assert_contains "$d/.bootstrapped" "with the fixture stack pack" || return 1
  assert_contains "$d.out" "Stack pack: fixture."
}
test_stack_python_coverage_tiers_fail_closed() {
  command -v uv >/dev/null 2>&1 || { skip "uv not installed"; return; }
  local d="$WORK/stack-tiers/demo" rc
  fresh_copy "$d"
  (cd "$d" && HOME="$WORK/home" stack_env ./bootstrap --name demo --stack python --yes </dev/null >"$d.out" 2>&1) \
    || fail "bootstrap exited $?: $(tail -20 "$d.out")" || return 1
  (cd "$d" && git add -A && git commit -qm init) || fail "commit failed" || return 1
  # 1. An include that is not a file fails --validate.
  perl -pi -e 's|include = \[\]|include = ["src/demo/missing.py"]|' "$d/pyproject.toml"
  py_tiers "$d" --validate; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "is not a file" || return 1
  (cd "$d" && git checkout -q pyproject.toml)
  # 2. Below the minimum, 3. missing from the report, 4. no branch data: all fail --check.
  printf '%s' '{"meta": {"branch_coverage": true}, "totals": {"covered_lines": 5, "num_statements": 10, "covered_branches": 0, "num_branches": 0}, "files": {"src/demo/cli.py": {"summary": {"covered_lines": 5, "num_statements": 10, "covered_branches": 0, "num_branches": 0}}}}' > "$d/coverage.json"
  py_tiers "$d" --check; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "below its minimum" || return 1
  printf '%s' '{"meta": {"branch_coverage": false}, "totals": {"covered_lines": 1, "num_statements": 1, "covered_branches": 0, "num_branches": 0}, "files": {"src/demo/other.py": {"summary": {"covered_lines": 1, "num_statements": 1, "covered_branches": 0, "num_branches": 0}}}}' > "$d/coverage.json"
  py_tiers "$d" --check; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "no branch data" || return 1
  assert_contains "$d.tiers.out" "not in the coverage report" || return 1
  # 5. Lowering a minimum fails --ratchet against the committed state.
  perl -0pi -e 's/(\[tool\.coverage_tiers\.api_surface\]\ntitle = "[^"]*"\ntarget = 100\.0\n)minimum = 100\.0/${1}minimum = 90.0/' "$d/pyproject.toml"
  py_tiers "$d" --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "minimum lowered from 100.0 to 90.0" || return 1
  (cd "$d" && git checkout -q pyproject.toml)
  # Independent dimensions, schema rejection, branchless/empty policy, and membership.
  (cd "$d" && stack_env uv run --locked --quiet python - "$d" >"$d.tiers.out" 2>&1 <<'PYPROBE'
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("tiers", root / "scripts/coverage_tiers.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
config = module.load_tiers()

def summary(lines=10, line_hits=10, branches=0, branch_hits=0):
    return dict(num_statements=lines, covered_lines=line_hits,
                num_branches=branches, covered_branches=branch_hits)

def report(cli=None, extra=None):
    files = {"src/demo/cli.py": {"summary": cli or summary()}}
    if extra is not None:
        files["src/demo/outside_tier.py"] = {"summary": extra}
    return dict(meta={"branch_coverage": True}, files=files,
                totals={key: sum(entry["summary"][key] for entry in files.values())
                        for key in module.COUNTERS})

def run(data, expected, text="", mode="--check"):
    (root / "coverage.json").write_text(json.dumps(data))
    result = subprocess.run([sys.executable, "scripts/coverage_tiers.py", mode],
                            cwd=root, text=True, capture_output=True)
    assert result.returncode == expected, result.stdout + result.stderr
    assert text in result.stdout + result.stderr, result.stdout + result.stderr

run(report(), 0)  # Positive lines with measured zero branches is deliberately branchless.
run(report(extra=summary(100, 100, 20, 8)), 1, "global: branch")
run(report(extra=summary(100, 40, 20, 20)), 1, "global: line")
run(report(cli=summary(100, 100, 20, 8), extra=summary(1000, 1000, 200, 200)),
    1, "api_surface: branch")
run(report(cli=summary(100, 40, 20, 20), extra=summary(1000, 1000, 200, 200)),
    1, "api_surface: line")
for mutation in (
    lambda data: data["files"]["src/demo/cli.py"]["summary"].pop("covered_branches"),
    lambda data: data["files"]["src/demo/cli.py"].update(summary={}),
    lambda data: data.update(totals={}),
    lambda data: data["totals"].update(covered_lines=True),
    lambda data: data["totals"].update(num_statements=-1),
    lambda data: data["totals"].update(covered_lines=11),
    lambda data: data["totals"].update(num_statements=11),
    lambda data: data.update(meta={"branch_coverage": False}),
    lambda data: data.update(files={}),
):
    data = report()
    mutation(data)
    run(data, 1)
    run(data, 1, mode="--report")  # Invalid inputs cannot produce a success snapshot.
run(report(cli=summary(0, 0)), 1, "no measurable statements")
run(report(cli=summary(0, 0), extra=summary()), 1, "no measurable statements")
data = report(extra=summary())
data["files"]["src/demo/renamed.py"] = data["files"].pop("src/demo/cli.py")
run(data, 1, "not in the coverage report")
for field, value in (
    ("minimum", True), ("minimum", float("nan")), ("target", float("inf")),
    ("include", "src/demo/cli.py"), ("include", ["src/demo/cli.py"] * 2),
    ("include", ["src/demo/../demo/cli.py"]), ("include", ["/tmp/foreign.py"]),
    ("include", []), ("allow_empty", "true"), ("title", 1),
):
    bad = copy.deepcopy(config)
    bad["api_surface"][field] = value
    assert module.validate(bad), (field, value)
assert module.validate({})
assert module.validate({"broken": []})
original = (root / "pyproject.toml").read_text()
try:
    # The explicit empty-tier opt-in must not bypass historical membership.
    changed = original.replace('include = ["src/demo/cli.py"]',
                               'include = []\nallow_empty = true')
    assert changed != original
    (root / "pyproject.toml").write_text(changed)
    result = subprocess.run([sys.executable, "scripts/coverage_tiers.py", "--ratchet", "HEAD"],
                            cwd=root, capture_output=True, text=True)
    assert result.returncode == 1 and "existing members removed" in result.stderr, result
finally:
    (root / "pyproject.toml").write_text(original)
print("coverage schema, separate floors, branchless policy, and membership probes passed")
PYPROBE
  ) || fail "coverage adversarial probes failed: $(tail -25 "$d.tiers.out")"
}
test_stack_python_project_is_green_on_first_run() {
  command -v uv >/dev/null 2>&1 || { skip "uv not installed"; return; }
  local d="$WORK/stack-python/demo-app"
  fresh_copy "$d"
  (cd "$d" && HOME="$WORK/home" stack_env ./bootstrap --name "Demo App" --stack python --yes </dev/null >"$d.out" 2>&1) \
    || fail "bootstrap exited $?: $(tail -20 "$d.out")" || return 1
  assert_contains "$d/pyproject.toml" 'name = "demo_app"' || return 1
  assert_exists "$d/src/demo_app/cli.py" || return 1
  assert_exists "$d/uv.lock" || return 1
  assert_exists "$d/.github/workflows/ci.yml" || return 1
  assert_absent "$d/.github/workflows/ci.yml.example" || return 1
  assert_absent "$d/template" || return 1
  assert_contains "$d/.bootstrapped" "with the python stack pack" || return 1
  assert_contains "$d/TESTING.md" "Tests: \`uv run pytest\`" || return 1
  assert_tree_lacks "$d" '{{TEST_CMD' || return 1
  assert_tree_lacks "$d" '{{PACKAGE_NAME}}' || return 1
  (cd "$d" && git add -A && git commit -qm init \
    && stack_env env EDITORCONFIG_CHECKER_BIN=/nonexistent ./scripts/check.sh \
    && stack_env ./scripts/coverage.sh) >"$d.gate.out" 2>&1 \
    || fail "the new project's own gate failed: $(tail -25 "$d.gate.out")"
}

```

**Verify**: `shellcheck scripts/template-selftest.sh` → exit 0. With uv installed,
`./scripts/template-selftest.sh` → `baseline + 2` passed, 6 failed, 0 skipped
(42 passed after the revised plan 005). Expected new failures:
unknown stack, digit-initial stack name, Python keyword name, fixture pack, Python coverage
checker, and Python first-run gate. Both no-stack tests already pass, including the copy with
no `template/stacks/` directory. Any predecessor test failure is unexpected. These failures are
intentional until the mechanism and pack are both installed; do not apply the final all-green
STOP condition to this test-first phase.

### Step 2: Let `scripts/check.sh` run stack guards

Insert this block directly **above** the `# --- Instruction files: AGENTS.md is the one agents read`
line:

```bash
# --- Stack guards: scripts/check.d/*.sh -------------------------------------
# Stack packs (./bootstrap --stack ...) and the project itself add guards here.
# Each runs from the repo root; a non-zero exit fails the check.
for guard in scripts/check.d/*.sh; do
  [ -f "$guard" ] || continue
  ran_any=1
  echo "- $(basename "$guard" .sh): running $guard..."
  bash "$guard" || status=1
done

```

**Verify**: `./scripts/check.sh` → exit 0 (the template has no `scripts/check.d/`, so nothing new
runs). `shellcheck scripts/check.sh` → exit 0.

### Step 3: Extract the gitleaks install into a composite action

Create `.github/actions/install-gitleaks/action.yml`:

```yaml
# Put a pinned, checksum-verified gitleaks on PATH. scripts/check.sh requires it
# in CI. To upgrade: change both values, taking the SHA256 from the release's
# gitleaks_<version>_checksums.txt.
name: Install gitleaks
description: Install a pinned, checksum-verified gitleaks binary onto PATH.
runs:
  using: composite
  steps:
    - name: Install gitleaks
      shell: bash
      env:
        GITLEAKS_VERSION: 8.30.1
        GITLEAKS_SHA256: 551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
      run: |
        tarball="gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
        curl -sSfL -o "$RUNNER_TEMP/$tarball" \
          "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/$tarball"
        echo "${GITLEAKS_SHA256}  $RUNNER_TEMP/$tarball" | sha256sum -c -
        mkdir -p "$RUNNER_TEMP/bin"
        tar -xzf "$RUNNER_TEMP/$tarball" -C "$RUNNER_TEMP/bin" gitleaks
        echo "$RUNNER_TEMP/bin" >> "$GITHUB_PATH"
```

Replace `.github/workflows/template-selftest.yml` with the content below. Compared with plan
001's version:
- gitleaks now comes from the composite action;
- a pinned `setup-uv` step lets the Python pack tests run;
- shellcheck also covers the pack scripts.

```yaml
# Template self-test — runs ONLY on willtraweek/vibe-starter itself.
#
# "Use this template" copies this file into new projects until ./bootstrap
# deletes it; the job-level `if:` keeps it inert in those copies meanwhile.

name: template-selftest

on:
  push:
    branches: [master]
  pull_request:

permissions:
  contents: read

jobs:
  selftest:
    if: github.repository == 'willtraweek/vibe-starter'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - name: Install gitleaks
        uses: ./.github/actions/install-gitleaks

      - name: Install uv (for the python stack-pack tests)
        uses: astral-sh/setup-uv@c18668ad3cf93ea998bef934396af7bb5c839dc7 # v10.2.0
        with:
          version: "0.12.17"

      - name: Lint shell scripts
        run: shellcheck bootstrap scripts/*.sh template/stacks/*/files/scripts/*.sh template/stacks/*/files/scripts/check.d/*.sh template/stacks/*/after-bootstrap template/stacks/*/validate-name

      - name: Template self-test
        run: ./scripts/template-selftest.sh
```

Replace `.github/workflows/ci.yml.example` with the content below. The only change is that the
inline gitleaks step becomes the composite action.

```yaml
# vibe-starter CI skeleton — INACTIVE.
#
# This file is named ci.yml.example on purpose: GitHub Actions only runs *.yml,
# so a freshly-cloned, stackless repo stays green instead of going red on its
# first push. Once you choose a stack:
#   1. rename this to ci.yml
#   2. uncomment the Install / Tests steps and fill in {{INSTALL_CMD}} / {{TEST_CMD}}
#
# The check step (scripts/check.sh) is stack-neutral and can run as-is.
# It REQUIRES gitleaks in CI, so keep the pinned install step below.

name: ci

on:
  push:
    branches: [main, master]
  pull_request:

permissions:
  contents: read

jobs:
  check-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - name: Install gitleaks
        uses: ./.github/actions/install-gitleaks

      # - name: Install
      #   run: {{INSTALL_CMD}}

      - name: Checks (guards run before tests)
        run: ./scripts/check.sh

      # - name: Tests
      #   run: {{TEST_CMD}}
```

**Verify**:
`ruby -ryaml -e 'ARGV.each(&YAML.method(:load_file))' .github/actions/install-gitleaks/action.yml .github/workflows/template-selftest.yml .github/workflows/ci.yml.example`
→ exit 0. `! grep -q 'GITLEAKS_SHA256' .github/workflows/*` → exit 0 (the value now
lives only in the action).

### Step 4: Extend `bootstrap` without replacing predecessor logic

Make these targeted changes to the post-005 file. Keep its marker preflight, failure handling,
retry-state file, skeleton swap, root-repository detection, instruction text, and final cleanup.
Do not paste a historical complete bootstrap over it.

1. Extend the usage/help text with `[--stack <name>]`. Initialize `STACK=""` and
   `STACK_GIVEN=0` with the existing argument state. Add these cases before `--help`:

   ```bash
   --stack)
     if [ $# -lt 2 ]; then echo "--stack needs a value" >&2; exit 2; fi
     STACK="$2"; STACK_GIVEN=1; shift 2 ;;
   --stack=*) STACK="${1#*=}"; STACK_GIVEN=1; shift ;;
   ```

   Reject an explicitly empty stack value just like the empty `--name` case:

   ```bash
   if [ "$STACK_GIVEN" = "1" ] && [ -z "$STACK" ]; then
     echo "--stack needs a non-empty value" >&2
     exit 2
   fi
   ```

2. After the existing project-name validation and before **any mutation** (in particular,
   before plan 005 writes `template/.bootstrap-version`), insert:

```bash
# --- Stack pack preflight (optional; no writes) -----------------------------
STACKS=""
if [ -d template/stacks ]; then
  STACKS="$(find template/stacks -mindepth 1 -maxdepth 1 -type d -exec basename {} \; \
    | LC_ALL=C sort | tr '\n' ' ' | sed 's/ *$//')"
fi
if [ "$STACK_GIVEN" = "0" ] && [ "$ASSUME_YES" != "1" ] && [ -t 0 ] && [ -n "$STACKS" ]; then
  printf "Stack pack [none %s]: " "$STACKS"
  read -r STACK </dev/tty || STACK=""
fi
if [ "$STACK" = "none" ]; then STACK=""; fi
# Normalization is shared; reserved words are language-specific.
PACKAGE_NAME="$(printf '%s' "$NAME" | LC_ALL=C tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//')"
if [ -n "$STACK" ]; then
  case "$STACK" in
    *[!a-z0-9_-]*|[-_]*) echo "Invalid stack name '$STACK'" >&2; exit 2 ;;
  esac
  pack="template/stacks/$STACK"
  if [ ! -d "$pack/files" ] || [ ! -f "$pack/commands" ] || [ ! -f "$pack/gitignore" ]; then
    echo "Unknown stack '$STACK' (available: ${STACKS:-none})" >&2
    exit 2
  fi
  case "$PACKAGE_NAME" in
    [a-z]*) ;;
    *) echo "With a stack pack the project name must start with a letter: '$NAME'" >&2; exit 2 ;;
  esac
  if [ -f "$pack/validate-name" ]; then
    sh "$pack/validate-name" "$PACKAGE_NAME" "$NAME" || exit 2
  fi
fi
```

   Missing `template/stacks/` is an ordinary stackless template. Keep `--stack none` equivalent
   to no stack. Both concrete packs' name checks run without their runtime installed.

3. Directly after plan 005's skeleton swap and before bootstrap-owned replacement, insert:

```bash
# --- Apply the stack pack -----------------------------------------------------
# Copy template/stacks/<stack>/files/ into the project (a path segment named
# __package__ becomes the package name), fill the command placeholders from its
# `commands` file, swap .gitignore's commented language sections for the pack's
# own, and activate the pack's CI workflow in place of ci.yml.example.
if [ -n "$STACK" ]; then
  pack="template/stacks/$STACK"
  (cd "$pack/files" && find . -type f) | while IFS= read -r src; do
    dest="$(printf '%s' "${src#./}" | sed "s#^__package__/#$PACKAGE_NAME/#; s#/__package__/#/$PACKAGE_NAME/#g")"
    mkdir -p "$(dirname "$dest")"
    cp "$pack/files/$src" "$dest"
  done
  grep -v '^#' "$pack/commands" | grep '=' | while IFS= read -r line; do
    key="${line%%=*}"
    hits="$(grep -rlI --exclude=bootstrap --exclude-dir=.git --exclude-dir=template \
      -e "{{$key" . 2>/dev/null || true)"
    [ -n "$hits" ] || continue
    printf '%s\n' "$hits" | while IFS= read -r f; do
      KEY="$key" VAL="${line#*=}" perl -0pi -e \
        's/\{\{\Q$ENV{KEY}\E(?::[^}]*)?\}\}/$ENV{VAL}/g' "$f"
    done
  done
  perl -0pi -e 's/^This template is stack-agnostic\. Fill these in once a stack is chosen, then delete this note\.\n//m' AGENTS.md
  perl -0pi -e 's/\n# =+\n# Language sections.*\z/\n/s' .gitignore
  cat "$pack/gitignore" >> .gitignore
  if [ -f .github/workflows/ci.yml ]; then rm -f .github/workflows/ci.yml.example; fi
  echo "Installed the $STACK stack pack."
fi
```

4. Add `-e '{{PACKAGE_NAME}}'` to the existing replacement scan, add `PKG="$PACKAGE_NAME"`
   alongside its `NAME`/`YEAR` environment variables, and append
   `s/\Q{{PACKAGE_NAME}}\E/$ENV{PKG}/g` to its Perl substitutions. Preserve existing exclusions
   and validated template-only stripping.

5. Between template-only stripping and git initialization insert:

   ```bash
   # --- Stack follow-up (best effort; lockfile absence is reported) ----------
   if [ -n "$STACK" ] && [ -f "template/stacks/$STACK/after-bootstrap" ]; then
     sh "template/stacks/$STACK/after-bootstrap" || echo "note: the $STACK pack follow-up failed; see above."
   fi
   ```

6. Keep the shared first-run checklist. Put its existing “Then choose a stack” block in an
   `else` branch of `if [ -n "$STACK" ]`; the stack branch prints:

   ```bash
   echo "Stack pack: $STACK. Commands, CI (.github/workflows/ci.yml) and .gitignore are set up."
   echo "  Run the gate and commit the lockfile before the first push; resolve any hook warning first."
   ```

7. Extend the existing successful `.bootstrapped` record to append
   `${STACK:+ with the $STACK stack pack}` after the preserved original `TEMPLATE_VERSION`.
   Keep plan 005's success-only cleanup of `template/` (including retry state), and keep
   self-deletion last. Update the header's optional-stack description.

**Verify now**: `shellcheck bootstrap` → exit 0; `./bootstrap --help` includes `--stack`.
`./scripts/template-selftest.sh bootstrap` and `./scripts/template-selftest.sh fixture` → all
selected tests pass, including both no-stack paths. Python-specific `stack` tests still need
step 5; do not demand those pass at this intermediate boundary. Inspect the diff to confirm
plan 005's marker validation and retry-safe provenance remain present.

### Step 5: Create the Python pack

Create each file below with exactly this content. Then run
`chmod +x template/stacks/python/after-bootstrap template/stacks/python/files/scripts/*.sh template/stacks/python/files/scripts/check.d/python.sh`.
Also create the empty marker `template/stacks/python/files/src/__package__/py.typed`
(`touch` it). It tells type checkers the package ships types.

`template/stacks/python/validate-name`:

```sh
#!/bin/sh
# Python 3.14 hard keywords that can survive lowercase normalization. No Python needed.
# Reject conservatively; the human-facing name is preserved separately by bootstrap.
case "$1" in
  and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield)
    echo "Package name '$1' is a reserved Python identifier; choose another project name." >&2
    exit 2 ;;
esac
```

`template/stacks/python/commands`:

```text
# KEY=value lines. ./bootstrap --stack python replaces {{KEY}} and {{KEY: description}}
# placeholders in the project's docs with these values.
INSTALL_CMD=uv sync
DEV_CMD=uv run {{PACKAGE_NAME}} --help
BUILD_CMD=uv build
CHECK_CMD=./scripts/check.sh
TEST_CMD=uv run pytest
SHIP_GATE=./scripts/check.sh && ./scripts/coverage.sh
STACK=Python 3.14 managed by uv; ruff (lint + format); ty (type checks); pytest with coverage.py branch coverage.
COVERAGE_ENFORCEMENT=./scripts/coverage.sh: pytest --cov and coverage JSON, then scripts/coverage_tiers.py independently enforces 90% lines and 90% branches plus per-tier floors; explicit branchless and empty-tier policy, fail-closed in CI
```

`template/stacks/python/gitignore`:

```gitignore
# --- Python (uv) ---
__pycache__/
*.py[cod]
.venv/
.pytest_cache/
.ruff_cache/
.coverage
.coverage.*
coverage.json
htmlcov/
dist/
```

`template/stacks/python/after-bootstrap`:

```sh
#!/bin/sh
# Runs once at the end of ./bootstrap --stack python, from the project root.
# Lock dependencies now so CI's `uv sync --locked` passes on the first push.
if ! command -v uv >/dev/null 2>&1; then
  echo "uv not found: install it (https://docs.astral.sh/uv/), then run 'uv lock' and commit uv.lock."
elif uv lock --quiet; then
  echo "Locked dependencies (uv.lock) - commit it."
else
  echo "uv lock failed (offline?): run 'uv lock' and commit uv.lock before your first push."
fi
```

`template/stacks/python/files/.python-version`:

```text
3.14
```

`template/stacks/python/files/pyproject.toml`:

```toml
[project]
name = "{{PACKAGE_NAME}}"
description = "{{PROJECT_NAME}}"
readme = "README.md"
requires-python = ">=3.14"
dependencies = []
# The version lives in the root VERSION file (gstack /ship bumps it); hatchling reads it.
dynamic = ["version"]

[project.scripts]
{{PACKAGE_NAME}} = "{{PACKAGE_NAME}}.cli:main"

[dependency-groups]
dev = [
  "pytest>=8.4",
  "pytest-cov>=7.0",
  "ruff>=0.16.8",
  "ty>=0.0.83",
]

[build-system]
requires = ["hatchling>=1.27"]
build-backend = "hatchling.build"

[tool.hatch.version]
path = "VERSION"
pattern = "(?P<version>.+)"

[tool.uv]
# Rebuild the editable install when VERSION changes, so --version stays current.
cache-keys = [{ file = "pyproject.toml" }, { file = "VERSION" }]

[tool.ruff]
line-length = 100

[tool.ruff.lint]
select = ["E", "W", "F", "I", "B", "UP", "SIM", "PT", "RUF"]

[tool.ty.src]
include = ["src", "tests", "scripts"]

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = ["--strict-markers", "--strict-config", "-ra"]

# Coverage gate (TESTING.md): 90% line+branch floor. Only runs with --cov
# (scripts/coverage.sh and CI); plain `uv run pytest` stays fast and gate-free.
[tool.coverage.run]
branch = true
source_pkgs = ["{{PACKAGE_NAME}}"]

[tool.coverage.report]
fail_under = 0  # Independent line and branch floors are enforced by coverage_tiers.py.
show_missing = true
exclude_also = ["if TYPE_CHECKING:", "@overload"]

# Per-tier gates (TESTING.md), enforced by scripts/coverage_tiers.py. `minimum` is
# enforced and only ever rises; `target` is the doctrine's aim.
[tool.coverage_tiers.pure_logic]
title = "Pure logic & utilities"
target = 100.0
minimum = 100.0
include = []
allow_empty = true  # Deliberate until the first pure-logic module exists.

[tool.coverage_tiers.api_surface]
title = "API / contract surface"
target = 100.0
minimum = 100.0
include = ["src/{{PACKAGE_NAME}}/cli.py"]
```

`template/stacks/python/files/src/__package__/__init__.py`:

```python
"""{{PROJECT_NAME}}."""

from importlib.metadata import version

__version__ = version("{{PACKAGE_NAME}}")
```

`template/stacks/python/files/src/__package__/cli.py`:

```python
"""Command-line entry point: the machine contract for {{PROJECT_NAME}} (DOCTRINE.md §3)."""

import argparse
from collections.abc import Sequence

from {{PACKAGE_NAME}} import __version__


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="{{PACKAGE_NAME}}", description="{{PROJECT_NAME}}")
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    build_parser().parse_args(argv)
    return 0
```

`template/stacks/python/files/tests/test_cli.py`:

```python
"""CLI contract tests (TESTING.md tier 2: exit code and output of every command)."""

from pathlib import Path

import pytest

from {{PACKAGE_NAME}} import __version__
from {{PACKAGE_NAME}}.cli import main

ROOT = Path(__file__).resolve().parents[1]


def test_version_comes_from_the_version_file() -> None:
    # gstack /ship bumps VERSION; hatchling feeds it to the package metadata.
    assert __version__ == (ROOT / "VERSION").read_text(encoding="utf-8").strip()


def test_version_flag_prints_version_and_exits_zero(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exc:
        main(["--version"])
    assert exc.value.code == 0
    assert capsys.readouterr().out.strip() == "{{PACKAGE_NAME}} " + __version__


def test_no_arguments_exits_zero() -> None:
    assert main([]) == 0
```

`template/stacks/python/files/scripts/check.d/python.sh`:

```bash
#!/usr/bin/env bash
# Python stack guards (from ./bootstrap --stack python): lockfile, lint, format,
# types, and the coverage-tier config (cheap; runs before any tests).
set -euo pipefail
if ! command -v uv >/dev/null 2>&1; then
  echo "  uv is not installed - this project needs it: https://docs.astral.sh/uv/" >&2
  exit 1
fi
uv lock --check --quiet
uv run --locked --quiet ruff check .
uv run --locked --quiet ruff format --check .
uv run --locked --quiet ty check
uv run --locked --quiet python scripts/coverage_tiers.py --validate
```

`template/stacks/python/files/scripts/coverage.sh`:

```bash
#!/usr/bin/env bash
# Coverage gate (TESTING.md): the 90% line+branch floor, then the per-tier gates.
# CI runs this. Plain `uv run pytest` skips coverage on purpose (fast, gate-free).
set -euo pipefail
cd "$(dirname "$0")/.."
uv run --locked pytest --cov
uv run --locked coverage json -q -o coverage.json
uv run --locked python scripts/coverage_tiers.py --check
```

`template/stacks/python/files/scripts/coverage_tiers.py`:

```python
"""Independent global and tier line/branch gates; stdlib only (TESTING.md).

Config lives in [tool.coverage_tiers.*]. Empty tiers require allow_empty=true.
Branchless code has no branch percentage; measured lines still meet the floor.
--ratchet REF forbids lowering floors/targets or removing existing tier members.
"""

import argparse
import json
import math
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
GLOBAL_MINIMUM = 90.0
COUNTERS = ("covered_lines", "num_statements", "covered_branches", "num_branches")


def load_tiers(text: str | None = None) -> dict[str, Any]:
    if text is None:
        text = (ROOT / "pyproject.toml").read_text(encoding="utf-8")
    return tomllib.loads(text).get("tool", {}).get("coverage_tiers", {})


def valid_path(path: Any) -> bool:
    return (
        isinstance(path, str)
        and path.startswith("src/")
        and path.endswith(".py")
        and "\\" not in path
        and all(part not in ("", ".", "..") for part in path.split("/"))
    )


def validate(tiers: Any, *, check_files: bool = True) -> list[str]:
    if not isinstance(tiers, dict) or not tiers:
        return ["coverage_tiers must be a nonempty table"]
    errors: list[str] = []
    owner: dict[str, str] = {}
    for key, tier in tiers.items():
        if key == "global":
            errors.append("global is reserved for the global floor, not a tier name")
        if not isinstance(tier, dict):
            errors.append(f"{key}: tier must be a table")
            continue
        allowed = {"title", "minimum", "target", "include", "allow_empty"}
        if set(tier) - allowed:
            errors.append(f"{key}: unknown tier keys: {sorted(set(tier) - allowed)}")
        minimum, target = tier.get("minimum"), tier.get("target")
        if not all(type(n) in (int, float) and math.isfinite(n) for n in (minimum, target)):
            errors.append(f"{key}: minimum and target must be finite numbers")
        elif not 0 <= minimum <= target <= 100:
            errors.append(f"{key}: need 0 <= minimum <= target <= 100")
        if not isinstance(tier.get("title"), str) or not tier["title"].strip():
            errors.append(f"{key}: title must be a nonempty string")
        if type(tier.get("allow_empty", False)) is not bool:
            errors.append(f"{key}: allow_empty must be boolean")
        members = tier.get("include")
        if not isinstance(members, list):
            errors.append(f"{key}: include must be an explicit array")
            continue
        if not members and tier.get("allow_empty") is not True:
            errors.append(f"{key}: empty include requires allow_empty = true")
        for path in members:
            if not valid_path(path):
                errors.append(f"{key}: include must name canonical src/*.py files: {path!r}")
                continue
            if check_files and (
                not (ROOT / path).is_file()
                or not (ROOT / path).resolve().is_relative_to(ROOT.resolve())
            ):
                errors.append(f"{key}: include {path!r} is not a file within the project")
            if path in owner:
                errors.append(f"{path}: duplicate membership in {owner[path]!r} and {key!r}")
            owner[path] = key
    return errors


def counters(summary: Any, label: str, errors: list[str]) -> dict[str, int] | None:
    if not isinstance(summary, dict) or any(
        type(summary.get(key)) is not int or summary[key] < 0 for key in COUNTERS
    ):
        errors.append(f"{label}: missing or invalid coverage counters")
        return None
    if (
        summary["covered_lines"] > summary["num_statements"]
        or summary["covered_branches"] > summary["num_branches"]
    ):
        errors.append(f"{label}: covered counters exceed totals")
        return None
    return {key: summary[key] for key in COUNTERS}


def measure(tiers: dict[str, Any], report: Any) -> tuple[dict[str, Any], list[str]]:
    errors: list[str] = []
    measured: dict[str, Any] = {}
    if not isinstance(report, dict):
        return measured, ["coverage report must be an object"]
    meta = report.get("meta")
    if not isinstance(meta, dict) or meta.get("branch_coverage") is not True:
        errors.append("coverage.json has no branch data; enable branch = true")
    files = report.get("files")
    if not isinstance(files, dict) or not files:
        return measured, [*errors, "coverage report files must be a nonempty object"]
    metrics: dict[str, dict[str, int]] = {}
    for path, entry in files.items():
        summary = entry.get("summary") if isinstance(entry, dict) else None
        value = counters(summary, str(path), errors)
        if value is not None:
            metrics[path] = value
    global_value = counters(report.get("totals"), "global", errors)
    if global_value is not None:
        if global_value["num_statements"] == 0:
            errors.append("global: no measurable statements")
        if len(metrics) == len(files) and any(
            global_value[key] != sum(value[key] for value in metrics.values()) for key in COUNTERS
        ):
            errors.append("global: counters disagree with per-file sums")
        measured["global"] = global_value
    for key, tier in tiers.items():
        if not tier["include"]:
            measured[key] = None  # validate() requires explicit allow_empty.
            continue
        total = dict.fromkeys(COUNTERS, 0)
        for path in tier["include"]:
            if path not in files:
                errors.append(f"{key}: {path} is not in the coverage report")
                continue
            value = metrics.get(path)
            if value is None:
                continue
            if value["num_statements"] == 0:
                errors.append(f"{key}: {path} has no measurable statements")
            for counter in COUNTERS:
                total[counter] += value[counter]
        measured[key] = total
    return measured, errors


def check(tiers: dict[str, Any], measured: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for key, value in measured.items():
        if value is None:
            continue
        floor = GLOBAL_MINIMUM if key == "global" else tiers[key]["minimum"]
        for metric, hit, count in (
            ("line", "covered_lines", "num_statements"),
            ("branch", "covered_branches", "num_branches"),
        ):
            if value[count] and 100 * value[hit] < floor * value[count]:
                actual = 100 * value[hit] / value[count]
                errors.append(f"{key}: {metric} {actual:.2f}% is below its minimum {floor}%")
    return errors


def percentage(value: dict[str, int], hit: str, total: str) -> str:
    return f"{100 * value[hit] / value[total]:.2f}%" if value[total] else "n/a (branchless)"


def report_markdown(tiers: dict[str, Any], measured: dict[str, Any]) -> str:
    lines = ["| Tier | Line | Branch | Minimum | Target |", "|---|---|---|---|---|"]
    for key, value in measured.items():
        tier = tiers.get(key, {"title": "Global", "minimum": GLOBAL_MINIMUM, "target": 100})
        line = branch = "n/a (explicitly empty)"
        if value is not None:
            line = percentage(value, "covered_lines", "num_statements")
            branch = percentage(value, "covered_branches", "num_branches")
        lines.append(
            f"| {tier['title']} | {line} | {branch} | {tier['minimum']}% | {tier['target']}% |"
        )
    return "\n".join(lines) + "\n"


def ratchet(tiers: dict[str, Any], ref: str) -> list[str]:
    shown = subprocess.run(
        ["git", "show", f"{ref}:pyproject.toml"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if shown.returncode:
        return [f"cannot read pyproject.toml at {ref}: {shown.stderr.strip()}"]
    old_tiers = load_tiers(shown.stdout)
    errors = validate(old_tiers, check_files=False)
    if errors:
        return [f"base config: {error}" for error in errors]
    for key, old in old_tiers.items():
        new = tiers.get(key)
        if new is None:
            errors.append(f"{key}: tier removed since {ref}")
            continue
        for field in ("minimum", "target"):
            if new[field] < old[field]:
                errors.append(f"{key}: {field} lowered from {old[field]} to {new[field]}")
        removed = set(old["include"]) - set(new["include"])
        if removed:
            errors.append(f"{key}: existing members removed since {ref}: {sorted(removed)}")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Independent line/branch coverage gates.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--validate", action="store_true")
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--report", action="store_true")
    mode.add_argument("--ratchet", metavar="REF")
    parser.add_argument("--input", default="coverage.json")
    args = parser.parse_args(argv)
    try:
        tiers = load_tiers()
        errors = validate(tiers)
        if not errors and args.ratchet:
            errors = ratchet(tiers, args.ratchet)
        elif not errors and (args.check or args.report):
            report = json.loads((ROOT / args.input).read_text(encoding="utf-8"))
            measured, errors = measure(tiers, report)
            if not errors and args.report:
                print(report_markdown(tiers, measured), end="")
                return 0
            if not errors:
                errors = check(tiers, measured)
    except (OSError, ValueError, TypeError, AttributeError) as exc:
        errors = [f"cannot load valid configuration/report: {exc}"]
    for error in errors:
        print(f"coverage-tiers: FAIL {error}", file=sys.stderr)
    print(f"coverage-tiers: {'FAILED' if errors else 'ok'}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
```

`template/stacks/python/files/.github/workflows/ci.yml`:

```yaml
# CI for {{PROJECT_NAME}} (vibe-starter python stack pack): guards, then tests
# with the 90% line+branch coverage floor from TESTING.md.
name: ci

on:
  push:
    branches: [main, master]
  pull_request:

permissions:
  contents: read

jobs:
  check-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - name: Install gitleaks
        uses: ./.github/actions/install-gitleaks

      - name: Install uv
        uses: astral-sh/setup-uv@c18668ad3cf93ea998bef934396af7bb5c839dc7 # v10.2.0
        with:
          version: "0.12.17"

      - name: Install (Python from .python-version, locked dependencies)
        run: uv sync --locked

      - name: Checks (guards run before tests)
        run: ./scripts/check.sh

      - name: Tests with the coverage gates (90% line+branch floor, then per-tier)
        run: ./scripts/coverage.sh

      - name: Coverage tiers never slip (pull requests)
        if: github.event_name == 'pull_request'
        run: |
          git fetch --depth=1 origin "$GITHUB_BASE_REF"
          uv run --locked python scripts/coverage_tiers.py --ratchet "origin/$GITHUB_BASE_REF"
```

**Verify**: the shell-lint command from the table → exit 0.
`./scripts/template-selftest.sh fixture` → ok. `./scripts/template-selftest.sh stack_python` → 3
tests ok (or 1 passed and 2 skipped without uv; then install uv and re-run: these must pass before you're done).

### Step 6: Document stack packs in `TEMPLATE.md`

1. In `## Use it`, replace steps 2 and 3:

   ```markdown
   2. `cd <name> && ./bootstrap`  (or `./bootstrap --name <name> --yes`)
   3. Fill in the placeholders the checklist prints, choose a stack, and start building.
   ```

   with

   ```markdown
   2. `cd <name> && ./bootstrap`  (or `./bootstrap --name <name> --yes`). Add `--stack python` to
     start with a ready-to-ship language pack (see Stack packs below).
   3. Fill in the placeholders the checklist prints and start building.
   ```

2. Insert this section directly **above** `## Note`:

```markdown
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
- `validate-name` (optional): runs before all file writes as `sh validate-name PACKAGE_NAME PROJECT_NAME`; reject reserved identifiers with a nonzero exit.
- `after-bootstrap` (optional): runs once at the end, for example to write the lockfile.

A pack's `files/.github/workflows/ci.yml` replaces `ci.yml.example`, activating the new project's
CI. Resolve any lockfile-hook warning and run the full gate before the first push. Stack guards go in `files/scripts/check.d/<name>.sh`;
`scripts/check.sh` runs every `scripts/check.d/*.sh`. The self-test runs each real pack end to
end: bootstrap a project, then run that project's own checks and tests.

Available: `python` (uv, ruff, ty, pytest with separate 90% line and branch floors).

```

**Verify**: `grep -c '^## Stack packs' TEMPLATE.md` → `1`.

### Step 7: Full verification and a manual look

The expected total is the recorded predecessor `baseline + 8` (48 in the verified sequence).

```sh
./scripts/template-selftest.sh            # 48 passed, 0 failed, 0 skipped
CI=true ./scripts/template-selftest.sh    # same (fails if anything skipped)
./scripts/check.sh                        # exit 0
```

Then look at a real result once (in a scratch dir, never in the template itself). Commit the
reviewed plan implementation before cloning: `git clone` reads commits, not uncommitted edits.
The shell below refuses a dirty source and cleans its scratch directory even on failure:

```sh
(
  set -e
  [ -z "$(git status --porcelain)" ] || { echo "Commit the reviewed implementation before this clone verification." >&2; exit 1; }
  demo_tmp="$(mktemp -d)"
  trap 'rm -rf "$demo_tmp"' EXIT
  git clone -q "$PWD" "$demo_tmp/demo-app"
  cd "$demo_tmp/demo-app"
  git remote remove origin
  ./bootstrap --name "Demo App" --stack python --yes
  test -f uv.lock
  git add -A
  git commit -qm init
  ./scripts/check.sh
  ./scripts/coverage.sh
  uv run --locked demo_app --version        # -> demo_app 0.0.0
)
```

Removing `origin` keeps plan 003's template-repo refusal from firing when the source checkout's
directory is named `vibe-starter`. A missing lockfile is a failed manual verification even
though bootstrap's lock hook is best effort.

## Test plan

- 8 new tests plus shared helpers (step 1):
  - unknown stacks, digit-initial names, and normalized Python keywords are rejected before file changes;
  - the no-stack path stays stack-agnostic, including when template/stacks is absent;
  - a synthetic fixture pack exercises every mechanism step: file copy with `__package__`,
    placeholder fill including the `{{KEY: description}}` form, `.gitignore` swap, CI activation,
    the after-bootstrap hook, and provenance;
  - the coverage checker independently enforces global/tier lines and branches; rejects malformed
    schemas, missing members, zero statements, impossible totals, and invalid snapshots; allows
    explicitly branchless/empty cases; and blocks lowering floors or removing established members;
  - a real `--stack python` project passes its own `check.sh` and `coverage.sh`.
- Final: `48 passed, 0 failed, 0 skipped`, with uv installed.

## Done criteria

ALL must hold:

- [ ] `./scripts/template-selftest.sh` exits 0 with `baseline + 8` passed (48 here), 0 failed/skipped
- [ ] `CI=true ./scripts/template-selftest.sh` exits 0
- [ ] All plan 005 marker/provenance contracts survive the targeted bootstrap diff
- [ ] The shell-lint and YAML commands from the table exit 0
- [ ] `./scripts/check.sh` exits 0 on the real repo
- [ ] The step-7 manual run printed `demo_app 0.0.0`
- [ ] `git status --porcelain` shows only in-scope paths
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- A semantic predecessor contract differs without explanation.
- The step-1 failure set differs from the 6 listed, or a test from plans 001–005 fails at any point.
- A final gate is skipped or fails; do not count an intentional intermediate failure as a final result.
- `test_stack_python_project_is_green_on_first_run` fails for a reason other than a missing uv or
  network. Report the tail of `$WORK/stack-python/demo-app.gate.out` (the test prints it). Do not
  loosen the pack's lint rules, the 90% floor, or the tier minimums to get green.
- `uv lock` fails in CI because PyPI does not have a version the pack's lower bounds require.
- You feel the need to add a `CLAUDE.md` to the pack.

## Maintenance notes

- **Adding a pack** (Rust in plan 007): create `template/stacks/<name>/` with the same pack
  interface, plus an end-to-end test modelled on `test_stack_python_project_is_green_on_first_run`.
  Name the pack in `TEMPLATE.md`'s "Available" line.
- **Upgrading tools.**
  - `ty` is pre-1.0, so bump it on purpose and expect new diagnostics.
  - When bumping uv in CI, keep `setup-uv`'s pinned SHA and the `version:` input in step. The
    uv version must be one the action's release lists in its known checksums.
  - `requires-python`, `.python-version` and ty's inferred target all move together.
- **Host-specific gstack integration.** Put shared check/test commands in TESTING.md. For
  Codex-generated workflows, inspect the installed skill's AGENTS.md parsing before adding
  settings there. Native Claude workflows may instead require explicit settings in a
  `CLAUDE.md` shim whose first line is `@AGENTS.md`; that optional, separately requested change
  must follow plan 004's guard. An import is not a promise that a skill's text parser follows
  the imported file. Do not claim universal defaults or add a shim in this plan. The required
  coverage gate remains `./scripts/coverage.sh`, independent of gstack's advisory estimates.
- **No stack after bootstrap.** Packs can only be applied at bootstrap, because `template/` is
  deleted afterwards. To add Python to an existing project, copy `template/stacks/python/files/`
  from the template repo by hand and fill the placeholders.
- **Tier membership is the project's job.** The pack starts with `api_surface = [cli.py]` at 100%
  and an explicitly empty `pure_logic` tier. As modules appear, add them to a tier's `include`
  and meet its existing floor; `--report` prints both dimensions. CI's `--ratchet` blocks lower
  minimums/targets and removal of existing members. Deliberate membership migrations need a
  reviewed policy change and Decisions Log entry, not a silent config deletion.
- Reviewer focus:
  - the "Apply the stack pack" block (the pack's `commands` values go through the environment
    into perl, never through a shell);
  - ordering: name + marker preflights → persist original provenance → swap skeletons → apply pack →
    replace placeholders → strip template-only blocks →
    after-bootstrap → git init;
  - the pack's `ci.yml`.
