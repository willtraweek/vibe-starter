# Plan 007: Add the Rust stack pack (pinned toolchain, clippy pedantic, rustfmt, cargo-llvm-cov)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Predecessor preflight (run first)**: execute after revised plans 001–006, in order.
> Confirm their done criteria, including maintainer mode, stack preflight and retry provenance.
> Run `./scripts/template-selftest.sh` and record its discovered test count and any named skips
> in `.context/plan-007-baseline.txt`; failures stop this plan. Check the contracts listed under
> Current state. Use those contracts and the passing predecessor suite, not obsolete hashes
> or an assumed fixed predecessor test count.

## Status

- **Priority**: P2 (requested by the maintainer)
- **Effort**: M
- **Risk**: MEDIUM. It adds coverage validation and ratchets plus a new pack, uses plan 006's mechanism unchanged, and leaves
  the no-stack path untouched.
- **Depends on**: 006 (the stack-pack mechanism, the `stack_env` test helper, and the
  `install-gitleaks` action)
- **Category**: direction
- **Planned at**: commit `1984ab7` plus plans 001–006, 2026-09-23

## Why this matters

The maintainer asked for default sets for Rust and Python. Plan 006 built the mechanism and the
Python pack; this adds `./bootstrap --stack rust`.

The maintainer's three existing Rust repos have no Rust conventions at all: no
`rust-toolchain.toml`, no `[lints]`, no clippy or rustfmt in CI, and no coverage. So this pack
sets them from scratch. It instantiates `TESTING.md`'s gates with the best that stable Rust
offers. After this plan, a new Rust project:
- builds with a pinned toolchain;
- is linted with clippy pedantic, where warnings are errors;
- is formatted by rustfmt;
- has CLI contract tests;
- has a 90% coverage floor plus per-tier gates;
- has live CI that is green on its first push.

## Design decisions

- **Toolchain pinned to 1.98.1**, preserving the original plan’s chosen runtime.
  Release dates and tool versions below are planning snapshots; do not upgrade them as part of this revision.
  - With `channel = "stable"`, a new release's clippy lints could fail `-D warnings` with no
    commit. Pinning makes local and CI identical; the cost is a deliberate bump every six weeks.
  - `rust-version` (the minimum supported Rust version) is `1.85`, the minimum for edition
    2024. That's honest for this code and lets older local toolchains build it.
- **Lints.** Everything goes in the `[lints]` table:
  - `unsafe_code = "forbid"` and `missing_docs = "warn"`.
  - `unexpected_cfgs` declares `cfg(coverage)`/`cfg(coverage_nightly)`, which cargo-llvm-cov
    sets. Without the declaration, using them later fails under `-D warnings`.
  - Clippy `pedantic` at `priority = -1`. Clippy's `lint_groups_priority` makes the same
    priority an error.
  - Also `dbg_macro` and `todo`.
  - CI keeps an explicit `-- -D warnings` on clippy. The newer `CARGO_BUILD_WARNINGS=deny`
    (Cargo 1.97+) is set too, for build and test warnings, but clippy is known to swallow it
    (rust-clippy#16963).
- **Version comes from the root `VERSION` file.**
  - `src/lib.rs` has `pub const VERSION: &str = include_str!("../VERSION").trim_ascii_end();`,
    which works in const context and rebuilds when `VERSION` changes. This was tested.
  - `Cargo.toml` keeps `version = "0.0.0"` forever, so gstack's VERSION-only bumps never make
    `Cargo.lock` churn. Pointing gstack's `.gstack/version-path` at `Cargo.toml` would overwrite
    the whole file, so don't.
- **Coverage uses lines and regions.**
  - True branch coverage is nightly-only: `cargo llvm-cov --branch` is unstable in v0.9.1, rustc
    rust#79649 is still open, and there is no `--fail-under-branches` flag.
  - Region coverage is the closest stable proxy. It counts implicit `else` paths, `?` error
    paths and every `match` arm.
  - `coverage.sh` runs `cargo llvm-cov --no-report`, then
    `report --fail-under-lines 90 --fail-under-regions 90`, then
    `report --json --summary-only --output-path coverage.json`, then the tier check.
  - The original plan reported 100% lines and regions on its original starter. Re-run coverage
    against the revised CLI below in CI before marking implementation complete.
- **Tests go through the binary.** llvm-cov's per-file summaries take the best single compiled
  copy of a function, not the union. So `src/lib.rs` has no inline `#[cfg(test)]` module, and
  `tests/cli.rs` drives every branch through the real binary (`CARGO_BIN_EXE_<name>`). That also
  covers `main.rs`, and it is the doctrine's tier 2: the CLI is the contract.
- **Tier gates** are `scripts/coverage_tiers.sh`, written in bash and jq.
  - Tiers live in `Cargo.toml` under `[package.metadata.coverage_tiers.<tier>]`, with shared `title`, `minimum`, `target` and `include` fields. They are read through `cargo metadata`, so no TOML parser or
    Python is needed (macOS's system Python 3.9 has no `tomllib`).
  - Modes: `--validate`, `--check`, `--report`, `--ratchet REF`. A tier fails if its lines or
    regions fall below its minimum, or if any included file has missing, malformed, negative,
    impossible or zero-count counters. `--report` enforces the same checks.
  - llvm-cov writes `percent: 0` when a count is 0, so the script computes percentages from
    `covered/count`. Only an explicitly empty tier displays `n/a`; a nonempty tier must have
    positive line and region counts for every member. Filenames are absolute and physical
    (`/private/tmp` on macOS), so it strips `pwd -P`.
  - Ratchets protect tier membership, numeric floors and targets. Removing, renaming or moving a
    member fails even when the percentage is unchanged; additions and floor increases pass.
  - Version 1 supports one root package. Virtual and multi-package workspaces fail with a clear
    migration message. Select metadata by exact manifest path; restore the complete base tree
    for ratchets rather than inventing a dummy manifest target.
- **The self-test doesn't download toolchains.**
  - Rust tests invoke `rustup run "${SELFTEST_RUST_TOOLCHAIN:-stable}"` without `--install`.
    That command requires an already installed toolchain and sets the override for the entire
    subprocess, including bootstrap and its lockfile hook. Missing tools are named skips locally.
  - The template's CI explicitly installs the selected stable toolchain with clippy, rustfmt
    and llvm-tools, then installs cargo-llvm-cov. Only CI performs these installations.
  - The coverage test skips locally when cargo-llvm-cov or llvm-tools is missing. Generated
    project tests also need cargo, clippy, rustfmt and jq; verify their availability explicitly.
- **Format after naming** (amended 2026-09-25 while planning 008). rustfmt lays lines out
  by length, so the starter's layout depends on the package name: with a 52-character name
  it failed `cargo fmt --check` in 5 places (`src/lib.rs`, `tests/cli.rs`). `after-bootstrap`
  therefore runs `cargo fmt --all` (offline, no lockfile needed) before writing `Cargo.lock`.
- **Left out on purpose** (see Maintenance notes):
  - cargo-deny: no dependencies yet, and it's symmetric with the Python pack, which has no
    dependency audit either.
  - cargo-nextest: a one-line switch later.
  - A nightly branch-coverage job.
- **CI actions pinned by commit SHA:**
  - `taiki-e/install-action` v2.87.19, installing `cargo-llvm-cov@0.9.1` with `fallback: none`.
  - `Swatinem/rust-cache` v2.9.2.
  - `rustup toolchain install` (no arguments) installs whatever `rust-toolchain.toml` names.

## Current state

After revised plans 001–006, verify these contracts before editing:

- `.github/workflows/template-selftest.yml` runs on `ubuntu-slim` and has checkout,
  `install-gitleaks`, a pinned shellcheck install, pinned `setup-uv`, shellcheck and the
  self-test. Step 3 adds Rust setup to this workflow while preserving its predecessor checks,
  runner and repository guard.
- `.editorconfig` contains `[*.{py,go}]` with `indent_size = 4`.
- `TEMPLATE.md` has `## Stack packs` documenting the Python pack and separate 90% line and
  branch floors. Extend that paragraph; do not restore the old combined-floor wording.
- `bootstrap` accepts `--stack <name>` for packs with `files/`, invokes optional `validate-name`
  before writes, and leaves the no-stack path working even when `template/stacks/` is absent.
  No bootstrap change is needed in this plan.
- Both instruction files survive bootstrap with plan 004's reciprocal required reading.
  Commands and skill routing remain in CLAUDE.md; TESTING.md mirrors its check/test commands.
- `scripts/template-selftest.sh` has `stack_env`, captures `REAL_CARGO_HOME`/`REAL_RUSTUP_HOME`,
  and excludes `template/stacks/*` from ordinary project placeholder inventory.
- Record `grep -c '^test_[A-Za-z0-9_]*()' scripts/template-selftest.sh` before Step 1. This plan
  adds six test functions; the full suite must discover baseline + 6, with zero failures.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Self-test | `./scripts/template-selftest.sh` | baseline + 6 discovered; zero failures; zero skips in fully provisioned CI |
| Rust tests only | `./scripts/template-selftest.sh stack_rust` | 6 tests; log named skips for unavailable local tools |
| Shell lint | `shellcheck bootstrap scripts/*.sh template/stacks/*/files/scripts/*.sh template/stacks/*/files/scripts/check.d/*.sh template/stacks/*/after-bootstrap template/stacks/*/validate-name` | exit 0 |
| YAML | `ruby -ryaml -e 'ARGV.each(&YAML.method(:load_file))' .github/workflows/template-selftest.yml template/stacks/rust/files/.github/workflows/ci.yml` | exit 0 |
| Tools | `rustup run "${SELFTEST_RUST_TOOLCHAIN:-stable}" cargo --version && jq --version` | both print a version |

Missing local tools produce named skips; do not install toolchains, components or cargo tools
while executing this plan. CI provisions them explicitly and must run with zero skips.

## Suggested executor toolkit

- gstack `/review` on the finished diff; `/investigate` if a Rust test fails.
- Do not run gstack `/ship` unless asked.

## Scope

**In scope** (the only files you should modify or create):

- everything under `template/stacks/rust/` (create)
- `scripts/template-selftest.sh` (append one test block)
- `.github/workflows/template-selftest.yml` (extend)
- `.editorconfig` (one line), `TEMPLATE.md` (one line becomes two)
- `plans/README.md` (your status row)

**Out of scope** (do NOT touch):

- `bootstrap`, `scripts/check.sh` and the Python pack: the mechanism is done.
- `rust-toolchain.toml` on your machine and your installed toolchains: never run mutating `rustup` commands or
  `cargo install` unless the operator asked. `rustup run` without `--install` is required for safe verification; run even diagnostic
  commands such as `rustup toolchain list` inside that override, because a bare list command
  can resolve and install the current directory’s pinned toolchain.
- cargo-deny, nextest, and a nightly branch-coverage job (maintenance notes).

## Git workflow

- Work on the branch you were given; do not rename it or create a different branch here.
- Commit per step, plain imperative messages (e.g. `Add the Rust stack pack`).
- Do NOT push or open a PR unless the operator told you to.

## Steps

### Step 1: Add the failing tests

Insert this block into `scripts/template-selftest.sh` immediately **above** `# --- runner ---`:

```bash
# --- tests: rust stack pack (plan 007) ----------------------------------------
rust_env() {  # Without --install, rustup run cannot provision a missing toolchain.
  stack_env rustup run "${SELFTEST_RUST_TOOLCHAIN:-stable}" "$@"
}
rust_ready() {  # A named local skip; fully provisioned CI must have none.
  command -v rustup >/dev/null 2>&1 || { echo "rustup not installed"; return; }
  command -v cargo >/dev/null 2>&1 || { echo "cargo not installed"; return; }
  command -v jq >/dev/null 2>&1 || { echo "jq not installed"; return; }
  rust_env cargo --version >/dev/null 2>&1 || { echo "test toolchain is not installed"; return; }
  rust_env cargo clippy --version >/dev/null 2>&1 || { echo "clippy missing for test toolchain"; return; }
  rust_env cargo fmt --version >/dev/null 2>&1 || echo "rustfmt missing for test toolchain"
}
bootstrap_rust() {
  fresh_copy "$1"
  (cd "$1" && HOME="$WORK/home" rust_env ./bootstrap --name "Demo App" --stack rust --yes </dev/null >"$1.out" 2>&1) \
    || fail "bootstrap exited $?: $(tail -20 "$1.out")" || return 1
  assert_exists "$1/Cargo.lock" || return 1
  (cd "$1" && git add -A && git commit -qm init) || fail "commit failed"
}
rs_tiers() {
  local dir="$1"; shift
  (cd "$dir" && rust_env ./scripts/coverage_tiers.sh "$@" >"$dir.tiers.out" 2>&1)
}
rs_report() {  # Known-valid positive control, mutated independently by each probe.
  jq -n --arg root "$(cd "$1" && pwd -P)" '
    {type:"llvm.coverage.json.export",data:[{files:["src/lib.rs","src/main.rs"] |
      map({filename:($root+"/"+.),summary:{lines:{count:10,covered:10},regions:{count:4,covered:4}}})}]}' > "$1/coverage.json"
}
rs_expect_bad_report() {
  local dir="$1" filter="$2" rc
  rs_report "$dir" || return 1
  jq "$filter" "$dir/coverage.json" > "$dir/bad.json" || return 1
  rs_tiers "$dir" --check bad.json; rc=$?
  assert_exit 1 "$rc" || return 1
  rs_tiers "$dir" --report bad.json; rc=$?
  assert_exit 1 "$rc"
}
test_stack_rust_project_is_green_on_first_run() {
  local d="$WORK/stack-rust/demo-app" why before_toolchains
  why="$(rust_ready)"; [ -z "$why" ] || { skip "$why"; return; }
  before_toolchains="$(rust_env rustup toolchain list)" || return 1
  bootstrap_rust "$d" || return 1
  assert_contains "$d/Cargo.toml" 'name = "demo_app"' || return 1
  assert_exists "$d/.github/workflows/ci.yml" || return 1
  assert_absent "$d/.github/workflows/ci.yml.example" || return 1
  assert_contains "$d/.bootstrapped" "with the rust stack pack" || return 1
  assert_contains "$d/TESTING.md" "Tests: \`cargo test --locked\`" || return 1
  assert_contains "$d/CLAUDE.md" "Tests: \`cargo test --locked\`" || return 1
  assert_tree_lacks "$d" '{{PACKAGE_NAME}}' || return 1
  (cd "$d" && rust_env env EDITORCONFIG_CHECKER_BIN=/nonexistent ./scripts/check.sh \
    && rust_env cargo test --locked) >"$d.gate.out" 2>&1 \
    || fail "new project's checks/tests failed: $(tail -25 "$d.gate.out")" || return 1
  (cd "$d" && rust_env cargo run --locked -q -- --version) | grep -qx "demo_app $(cat "$d/VERSION")" \
    || fail "--version does not print VERSION" || return 1
  # Even diagnostics run under the installed override inside the pinned project.
  [ "$(cd "$d" && rust_env rustup toolchain list)" = "$before_toolchains" ] \
    || fail "verification changed installed toolchains"
}
test_stack_rust_coverage_gate_passes() {
  local d="$WORK/stack-rust-cov/demo-app" why
  why="$(rust_ready)"; [ -z "$why" ] || { skip "$why"; return; }
  rust_env cargo llvm-cov --version >/dev/null 2>&1 || { skip "cargo-llvm-cov not installed"; return; }
  rust_env rustup component list --installed | grep -q '^llvm-tools' || { skip "llvm-tools not installed"; return; }
  bootstrap_rust "$d" || return 1
  (cd "$d" && rust_env ./scripts/coverage.sh) >"$d.cov.out" 2>&1 \
    || fail "coverage.sh failed: $(tail -25 "$d.cov.out")"
}
test_stack_rust_coverage_tiers_fail_closed() {
  local d="$WORK/stack-rust-tiers/demo-app" why rc filter
  why="$(rust_ready)"; [ -z "$why" ] || { skip "$why"; return; }
  bootstrap_rust "$d" || return 1
  rs_report "$d" || return 1
  rs_tiers "$d" --check coverage.json || fail "valid measurements failed" || return 1
  rs_tiers "$d" --report coverage.json || return 1
  assert_contains "$d.tiers.out" "n/a (empty tier)" || return 1
  for filter in \
    '.data[0].files[0].summary.lines.covered = 5' \
    '.data[0].files[0].summary.regions.covered = 2' \
    '.data[0].files |= .[0:1]' \
    '.data[0].files[].summary = {}' \
    '.data[0].files[].summary.lines = {count:0,covered:0}' \
    '.data[0].files[].summary.regions = {count:0,covered:0}' \
    '.data[0].files[0].summary.lines.covered = -1' \
    '.data[0].files[0].summary.regions.covered = 5' \
    '.data[0].files[0].summary.lines.count = "10"' \
    '.data[0].files[0].summary.lines.count = 10.5' \
    '.data[0].files[0].summary.lines = {count:1e999,covered:1e999}' \
    '.data[0].files[0].summary.lines = {count:1e308,covered:1e308}' \
    '.data[0].files += [.data[0].files[0]]' \
    '.data[0].files += [(.data[0].files[0] | .filename = "src/lib.rs")]' \
    '.data = []' \
    'del(.type)'; do
    rs_expect_bad_report "$d" "$filter" || return 1
  done
  printf '{' > "$d/bad.json"
  rs_tiers "$d" --check bad.json; rc=$?
  assert_exit 1 "$rc" || return 1
  perl -pi -e 's|include = \[\]|include = ["src/missing.rs"]|' "$d/Cargo.toml"
  rs_tiers "$d" --validate; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "is not a file" || return 1
  (cd "$d" && git checkout -q -- Cargo.toml)
  perl -pi -e 's|include = \[\]|include = "src/lib.rs"|' "$d/Cargo.toml"
  rs_tiers "$d" --validate; rc=$?
  assert_exit 1 "$rc" || return 1
  (cd "$d" && git checkout -q -- Cargo.toml)
  perl -0pi -e 's/\n\[package\.metadata\.coverage_tiers\.pure_logic\].*//s' "$d/Cargo.toml"
  rs_tiers "$d" --validate; rc=$?
  assert_exit 1 "$rc"
}
test_stack_rust_ratchet_preserves_membership() {
  local d="$WORK/stack-rust-ratchet/demo-app" why rc
  why="$(rust_ready)"; [ -z "$why" ] || { skip "$why"; return; }
  bootstrap_rust "$d" || return 1
  rs_tiers "$d" --ratchet HEAD || fail "unchanged ratchet failed" || return 1
  perl -pi -e 's|include = \["src/lib.rs", "src/main.rs"\]|include = ["src/lib.rs"]|' "$d/Cargo.toml"
  rs_tiers "$d" --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "member removed" || return 1
  (cd "$d" && git checkout -q -- Cargo.toml)
  perl -pi -e 's/minimum = 100.0/minimum = 90.0/g' "$d/Cargo.toml"
  rs_tiers "$d" --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "minimum lowered" || return 1
  (cd "$d" && git checkout -q -- Cargo.toml)
  perl -0pi -e 's/\n\[package\.metadata\.coverage_tiers\.api_surface\].*//s' "$d/Cargo.toml"
  rs_tiers "$d" --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  (cd "$d" && git checkout -q -- Cargo.toml)
  printf '// extra module\n' > "$d/src/extra.rs"
  perl -pi -e 's|include = \[\]|include = ["src/extra.rs"]|' "$d/Cargo.toml"
  rs_tiers "$d" --ratchet HEAD || fail "adding membership failed" || return 1
  # A lower committed baseline permits an increase without confusing it with removal.
  perl -pi -e 's/minimum = 100.0/minimum = 90.0/g' "$d/Cargo.toml"
  (cd "$d" && git add Cargo.toml src/extra.rs && git commit -qm 'ratchet fixture') || return 1
  perl -pi -e 's/target = 100.0/target = 95.0/g' "$d/Cargo.toml"
  rs_tiers "$d" --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "target lowered" || return 1
  perl -pi -e 's/target = 95.0/target = 100.0/g; s/minimum = 90.0/minimum = 100.0/g' "$d/Cargo.toml"
  rs_tiers "$d" --ratchet HEAD || fail "raising floors failed"
}
test_stack_rust_rejects_workspaces() {
  local d="$WORK/stack-rust-workspace/demo-app" why rc
  why="$(rust_ready)"; [ -z "$why" ] || { skip "$why"; return; }
  bootstrap_rust "$d" || return 1
  mkdir -p "$d/another/src"
  printf '[package]\nname = "another"\nversion = "0.0.0"\nedition = "2024"\n' > "$d/another/Cargo.toml"
  printf '// member\n' > "$d/another/src/lib.rs"
  printf '\n[workspace]\nmembers = ["another"]\n' >> "$d/Cargo.toml"
  rs_tiers "$d" --validate; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "only one root package" || return 1
  printf '[workspace]\nmembers = ["another"]\nresolver = "3"\n' > "$d/Cargo.toml"
  rs_tiers "$d" --validate; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "only one root package"
}
test_stack_rust_reserved_name_fails_before_writes() {
  local d="$WORK/stack-rust-name/demo-app" name before rc
  for name in Async Self Gen Test Std; do
    fresh_copy "$d"
    before="$(tree_fingerprint "$d")"
    (cd "$d" && ./bootstrap --name "$name" --stack rust --yes >"$d.out" 2>&1); rc=$?
    assert_exit 2 "$rc" || return 1
    assert_contains "$d.out" "reserved Rust package name" || return 1
    [ "$(tree_fingerprint "$d")" = "$before" ] || fail "reserved name mutated the tree" || return 1
    rm -rf "$d"
  done
}
```

**Verify**: shellcheck passes. Run `./scripts/template-selftest.sh stack_rust` and record
expected failures caused by the absent pack (with installed tools); named tool skips are
allowed locally. Do not demand that a test requiring an uncreated pack pass at this step.

### Step 2: Create the Rust pack

Create each file below with exactly this content. Then run
`chmod +x template/stacks/rust/after-bootstrap template/stacks/rust/validate-name template/stacks/rust/files/scripts/*.sh template/stacks/rust/files/scripts/check.d/rust.sh`.

`template/stacks/rust/commands`:

```text
# KEY=value lines. ./bootstrap --stack rust replaces {{KEY}} and {{KEY: description}}
# placeholders in the project's docs with these values.
INSTALL_CMD=cargo build --locked
DEV_CMD=cargo run --locked -- --help
BUILD_CMD=cargo build --locked --release
CHECK_CMD=./scripts/check.sh
TEST_CMD=cargo test --locked
SHIP_GATE=./scripts/check.sh && ./scripts/coverage.sh
STACK=Rust 1.98 (edition 2024, pinned in rust-toolchain.toml); clippy (pedantic, warnings are errors); rustfmt; cargo test; cargo-llvm-cov.
COVERAGE_ENFORCEMENT=./scripts/coverage.sh: cargo llvm-cov with the 90% line and region floors (regions stand in for branches on stable Rust), then the per-tier gates of scripts/coverage_tiers.sh; CI runs it, fail-closed
```

`template/stacks/rust/gitignore`:

```gitignore
# --- Rust ---
/target/
coverage.json
lcov.info
*.profraw
```

`template/stacks/rust/validate-name` (called by plan 006 before any project writes):

```sh
#!/bin/sh
# Rust 2024 strict/reserved keywords, weak keywords unsafe as crate paths, and
# Cargo-reserved/artifact-colliding crate names. Generic identifier syntax was
# already checked by bootstrap. Normalization is lowercase before this hook.
case "$1" in
  as|async|await|break|const|continue|crate|dyn|else|enum|extern|false|fn|for|if|impl|in|let|loop|match|mod|move|mut|pub|ref|return|self|static|struct|super|trait|true|type|unsafe|use|where|while|abstract|become|box|do|final|gen|macro|override|priv|try|typeof|unsized|virtual|yield|union|macro_rules|raw|safe|_|std|core|alloc|proc_macro|test|build|deps|examples|incremental)
    echo "reserved Rust package name: $1" >&2
    exit 2 ;;
esac
```

`template/stacks/rust/after-bootstrap`:

```sh
#!/bin/sh
# Runs once at the end of ./bootstrap --stack rust, from the project root.
# rustfmt lays lines out by length, and the project's name just changed the
# starter's lines: format them first, or `cargo fmt --check` fails for long
# names. The crate has no dependencies yet, so Cargo.lock can be written
# offline; commit it so CI's --locked builds pass on the first push.
if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found: install Rust (https://rustup.rs), run 'cargo fmt --all && cargo generate-lockfile', commit Cargo.lock."
  exit 0
fi
cargo fmt --all || echo "cargo fmt failed: run 'cargo fmt --all' before your first commit."
if cargo generate-lockfile --offline --quiet; then
  echo "Wrote Cargo.lock - commit it."
else
  echo "cargo generate-lockfile failed: run it and commit Cargo.lock before your first push."
fi
```

`template/stacks/rust/files/rust-toolchain.toml`:

```toml
# Pinned so local builds and CI use the same compiler and clippy (a new release's
# lints can otherwise fail `-D warnings` with no commit). Bump it on purpose.
[toolchain]
channel = "1.98.1"
components = ["clippy", "rustfmt", "llvm-tools-preview"]
profile = "minimal"
```

`template/stacks/rust/files/Cargo.toml`:

```toml
[package]
name = "{{PACKAGE_NAME}}"
# The real version is the root VERSION file (gstack /ship bumps it), compiled in
# by src/lib.rs. This one stays 0.0.0 so Cargo.lock never churns.
version = "0.0.0"
edition = "2024"
# Oldest Rust this code builds with (edition 2024 needs 1.85). Raise it when you
# use newer features; rust-toolchain.toml pins the compiler you develop with.
rust-version = "1.85"
description = "{{PROJECT_NAME}}"
publish = false

[dependencies]

[lints.rust]
unsafe_code = "forbid"
missing_docs = "warn"
unexpected_cfgs = { level = "warn", check-cfg = ["cfg(coverage)", "cfg(coverage_nightly)"] }

[lints.clippy]
pedantic = { level = "warn", priority = -1 }
dbg_macro = "warn"
todo = "warn"

# Per-tier coverage gates (TESTING.md), enforced by scripts/coverage_tiers.sh.
# `minimum` is enforced and only ever rises; `target` is the doctrine's aim.
[package.metadata.coverage_tiers.pure_logic]
title = "Pure logic & utilities"
target = 100.0
minimum = 100.0
include = []

[package.metadata.coverage_tiers.api_surface]
title = "API / contract surface"
target = 100.0
minimum = 100.0
include = ["src/lib.rs", "src/main.rs"]
```

`template/stacks/rust/files/rustfmt.toml`:

```toml
# `cargo fmt` reads the edition from Cargo.toml; plain `rustfmt` (editors, hooks)
# needs it here.
edition = "2024"
style_edition = "2024"
```

`template/stacks/rust/files/src/lib.rs`:

```rust
//! {{PROJECT_NAME}}.

/// The project version, from the root `VERSION` file. gstack `/ship` bumps that
/// file; `Cargo.toml` keeps `0.0.0` so `Cargo.lock` never churns.
pub const VERSION: &str = include_str!("../VERSION").trim_ascii_end();

/// Runs the command line with `args` (program name excluded) and returns what to
/// print on stdout.
///
/// # Errors
///
/// Returns the message to print on stderr when the arguments are invalid.
pub fn run(args: &[String]) -> Result<String, String> {
    if args.len() > 1 {
        return Err("error: expected at most one argument\n".to_owned());
    }
    match args.first().map(String::as_str) {
        Some("--version") => Ok(format!("{{PACKAGE_NAME}} {VERSION}\n")),
        Some("--help") | None => Ok("usage: {{PACKAGE_NAME}} [--help | --version]\n".to_owned()),
        Some(other) => Err(format!("error: unexpected argument '{other}'\n")),
    }
}
```

`template/stacks/rust/files/src/main.rs`:

```rust
//! Command-line entry point: the machine contract for {{PROJECT_NAME}} (DOCTRINE.md §3).

use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match {{PACKAGE_NAME}}::run(&args) {
        Ok(out) => {
            print!("{out}");
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprint!("{err}");
            ExitCode::from(2)
        }
    }
}
```

`template/stacks/rust/files/tests/cli.rs`:

```rust
//! CLI contract tests (TESTING.md tier 2: exit code and output of every command).

use std::process::{Command, Output};

fn cli(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_{{PACKAGE_NAME}}"))
        .args(args)
        .output()
        .expect("the binary runs")
}

#[test]
fn version_flag_prints_the_version_file_and_exits_zero() {
    let version_file = concat!(env!("CARGO_MANIFEST_DIR"), "/VERSION");
    let version = std::fs::read_to_string(version_file).expect("VERSION exists");
    let out = cli(&["--version"]);
    assert!(out.status.success());
    assert_eq!(
        String::from_utf8_lossy(&out.stdout),
        format!("{{PACKAGE_NAME}} {}\n", version.trim_end())
    );
    assert!(out.stderr.is_empty());
}

#[test]
fn no_arguments_prints_usage_and_exits_zero() {
    let out = cli(&[]);
    assert!(out.status.success());
    assert_eq!(out.stdout, b"usage: {{PACKAGE_NAME}} [--help | --version]\n");
    assert!(out.stderr.is_empty());
}

#[test]
fn help_flag_prints_usage_and_exits_zero() {
    let out = cli(&["--help"]);
    assert!(out.status.success());
    assert_eq!(out.stdout, b"usage: {{PACKAGE_NAME}} [--help | --version]\n");
    assert!(out.stderr.is_empty());
}

#[test]
fn unknown_argument_exits_two_on_stderr() {
    let out = cli(&["--nope"]);
    assert_eq!(out.status.code(), Some(2));
    assert!(out.stdout.is_empty());
    assert_eq!(out.stderr, b"error: unexpected argument '--nope'\n");
}

#[test]
fn surplus_arguments_exit_two_on_stderr() {
    for args in [
        ["--version", "garbage"],
        ["--help", "garbage"],
        ["--nope", "other"],
    ] {
        let out = cli(&args);
        assert_eq!(out.status.code(), Some(2));
        assert!(out.stdout.is_empty());
        assert_eq!(out.stderr, b"error: expected at most one argument\n");
    }
}
```

`template/stacks/rust/files/scripts/check.d/rust.sh`:

```bash
#!/usr/bin/env bash
# Rust stack guards (from ./bootstrap --stack rust): formatting, lints, and the
# coverage-tier config (cheap; runs before any tests).
set -euo pipefail
if ! command -v cargo >/dev/null 2>&1; then
  echo "  cargo is not installed - this project needs Rust: https://rustup.rs" >&2
  exit 1
fi
cargo fmt --all --check
cargo clippy --locked --all-targets --all-features --quiet -- -D warnings
./scripts/coverage_tiers.sh --validate
```

`template/stacks/rust/files/scripts/coverage.sh`:

```bash
#!/usr/bin/env bash
# Coverage gate (TESTING.md): 90% line and region floors, then the per-tier gates.
# CI runs this; plain `cargo test` skips coverage on purpose. Stable Rust has no
# branch coverage yet (cargo-llvm-cov --branch is nightly-only), so region
# coverage stands in for it.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! cargo llvm-cov --version >/dev/null 2>&1; then
  echo "cargo-llvm-cov is not installed: cargo install --locked cargo-llvm-cov" >&2
  exit 1
fi
cargo llvm-cov --locked --all-features --no-report
cargo llvm-cov report --fail-under-lines 90 --fail-under-regions 90
cargo llvm-cov report --json --summary-only --output-path coverage.json
./scripts/coverage_tiers.sh --check coverage.json
```

`template/stacks/rust/files/scripts/coverage_tiers.sh`:

```bash
#!/usr/bin/env bash
# Line/region tier gates for one root package. Multi-package and virtual Cargo
# workspaces need a reviewed extension of both coverage collection and this gate.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "coverage-tiers: FAIL $*" >&2; exit 1; }
command -v cargo >/dev/null 2>&1 || fail "cargo is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"

tiers_of() {  # Read the package at this exact manifest, never .packages[0].
  local manifest root metadata
  root="$(cd "$(dirname "$1")" && pwd -P)"
  manifest="$root/$(basename "$1")"
  metadata="$(cargo metadata --offline --format-version 1 --no-deps --manifest-path "$manifest")" \
    || { echo "coverage-tiers: cannot read Cargo metadata for $manifest" >&2; return 1; }
  jq -ce --arg manifest "$manifest" --arg root "$root" '
    [.packages[] | select(.manifest_path == $manifest)] as $p |
    if ($p | length) != 1 or .workspace_root != $root
       or (.workspace_members | length) != 1 or .workspace_members[0] != $p[0].id
    then error("only one root package is supported; virtual and multi-package workspaces require a gate migration")
    else $p[0].metadata.coverage_tiers end' <<<"$metadata"
}

validate() {  # Explicit empty tiers are allowed; missing/malformed config is not.
  jq -e '
    def path_ok: type == "string" and test("^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$")
      and (test("(^|/)\\.\\.?(/|$)") | not);
    type == "object" and length > 0 and
    all(to_entries[]; (.key | test("^[a-z][a-z0-9_]*$")) and
      (.value | type == "object" and
        (.minimum | type == "number") and (.target | type == "number") and
        (0 <= .minimum and .minimum <= .target and .target <= 100) and
        (.include | type == "array" and all(.[]; path_ok)) and
        (.title == null or (.title | type == "string")))) and
    ([.[].include[]] | length > 0 and length == (unique | length))
  ' <<<"$1" >/dev/null || fail "invalid tier schema, empty membership, or duplicate membership"
  while IFS= read -r path; do
    [ -f "$path" ] || fail "include '$path' is not a file"
  done < <(jq -r '.[].include[]' <<<"$1")
}

measure() {  # Fail before printing any rows for malformed/missing measurements.
  jq -ce --arg root "$(pwd -P)/" --argjson tiers "$1" '
    def counter_ok:
      type == "object" and (.count | type == "number" and isfinite) and
      (.covered | type == "number" and isfinite) and
      (.count <= 9007199254740991) and
      (.count > 0 and .covered >= 0 and .covered <= .count) and
      (.count == (.count | floor) and .covered == (.covered | floor));
    if .type != "llvm.coverage.json.export" or (.data | type) != "array" or (.data | length) != 1
       or (.data[0].files | type) != "array" or (.data[0].files | length) == 0
    then error("invalid coverage report schema") else . end |
    .data[0].files as $entries |
    if (all($entries[]; (.filename | type) == "string") | not)
       or ([$entries[].filename | ltrimstr($root)] | length != (unique | length))
    then error("invalid or duplicate report filenames") else . end |
    [$entries[] | {key: (.filename | ltrimstr($root)), value: .summary}] | from_entries as $files |
    [$tiers | to_entries[] | .key as $k | .value as $tier |
      [$tier.include[] | . as $path |
        if $files[$path] == null then error("\($k): not in the coverage report: \($path)")
        elif ([$files[$path].lines, $files[$path].regions] | all(.[]; counter_ok) | not)
        then error("\($k): invalid or zero-count measurements for \($path)")
        else $files[$path] end] as $s |
      {key: $k, title: ($tier.title // $k), minimum: $tier.minimum, target: $tier.target,
       lines: (if ($s | length) == 0 then null else 100 * ([$s[].lines.covered] | add) / ([$s[].lines.count] | add) end),
       regions: (if ($s | length) == 0 then null else 100 * ([$s[].regions.covered] | add) / ([$s[].regions.count] | add) end)}]
  ' "$2"
}

mode="${1:-}"
case "$mode:$#" in
  --validate:1|--check:1|--check:2|--report:1|--report:2|--ratchet:2) ;;
  *) echo "usage: $0 --validate | --check [report] | --report [report] | --ratchet REF" >&2; exit 2 ;;
esac
tiers="$(tiers_of Cargo.toml)" || fail "cannot load tiers for the root package"
validate "$tiers"
case "$mode" in
  --validate) ;;
  --check|--report)
    report="${2:-coverage.json}"
    [ -f "$report" ] || fail "$report not found (run scripts/coverage.sh)"
    rows="$(measure "$tiers" "$report")" || fail "unusable coverage report"
    errors="$(jq -r '.[] | . as $t | ["lines", "regions"][] as $metric |
      select($t[$metric] != null and $t[$metric] < $t.minimum) |
      "\($t.key): \($metric) coverage \($t[$metric])% is below its minimum \($t.minimum)%"' <<<"$rows")"
    [ -z "$errors" ] || fail "$errors"
    if [ "$mode" = "--report" ]; then
      echo "| Tier | Lines | Regions | Minimum | Target |"
      echo "|---|---|---|---|---|"
      jq -r '.[] | "| \(.title) | \(.lines // "n/a (empty tier)") | \(.regions // "n/a (empty tier)") | \(.minimum)% | \(.target)% |"' <<<"$rows"
      exit 0
    fi ;;
  --ratchet)
    base="$(git rev-parse --verify "${2}^{commit}")" || fail "cannot resolve base $2"
    old_dir="$(mktemp -d)"; trap 'rm -rf "$old_dir"' EXIT
    # Restore the complete base tree so metadata sees its actual targets/paths.
    git archive "$base" | tar -x -C "$old_dir" || fail "cannot read base tree"
    old="$(tiers_of "$old_dir/Cargo.toml")" || fail "cannot read base tiers"
    (cd "$old_dir" && validate "$old") || fail "invalid base tiers"
    errors="$(jq -r --argjson new "$tiers" 'to_entries[] | .key as $k |
      if $new[$k] == null then "\($k): tier removed since the base"
      else
        (.value as $old | ["minimum", "target"][] as $field |
         if $new[$k][$field] < $old[$field]
         then "\($k): \($field) lowered from \($old[$field]) to \($new[$k][$field])" else empty end),
        ((.value.include - $new[$k].include)[] | "\($k): member removed since the base: \(.)")
      end' <<<"$old")"
    [ -z "$errors" ] || fail "$errors" ;;
esac
echo "coverage-tiers: $(jq 'length' <<<"$tiers") tier(s) ok"
```

`template/stacks/rust/files/.github/workflows/ci.yml`:

```yaml
# CI for {{PROJECT_NAME}} (vibe-starter rust stack pack): guards, then tests with
# the coverage gates from TESTING.md, then doctests.
name: ci

on:
  push:
    branches: [main, master]
  pull_request:

permissions:
  contents: read

env:
  CARGO_TERM_COLOR: always
  CARGO_BUILD_WARNINGS: deny

jobs:
  check-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - name: Install gitleaks
        uses: ./.github/actions/install-gitleaks

      - name: Install the pinned toolchain (rust-toolchain.toml)
        run: rustup toolchain install

      - name: Cache dependencies
        uses: Swatinem/rust-cache@6323deb102c322ba6fcbdcafc7e3dddab59af2b6 # v2.9.2

      - name: Install cargo-llvm-cov
        uses: taiki-e/install-action@7623a79cdfecb99d681017af368ca353d9f49bb5 # v2.87.19
        with:
          tool: cargo-llvm-cov@0.9.1
          fallback: none

      - name: Checks (guards run before tests)
        run: ./scripts/check.sh

      - name: Tests with the coverage gates (90% lines and regions, then per-tier)
        run: ./scripts/coverage.sh

      - name: Doctests (coverage runs on stable skip them)
        run: cargo test --locked --doc

      - name: Coverage tiers never slip (pull requests)
        if: github.event_name == 'pull_request'
        run: |
          git fetch --depth=1 origin "$GITHUB_BASE_REF"
          ./scripts/coverage_tiers.sh --ratchet "origin/$GITHUB_BASE_REF"
```

**Verify**: shell lint passes. Run all six `stack_rust` tests: zero failures, with any missing
local tool skips named explicitly. The generated CLI has five contract tests, including help
and the explicit policy that more than one argument fails with exit 2 and no stdout.

### Step 3: Give the template's CI what the Rust tests need

Extend `.github/workflows/template-selftest.yml` from revised plan 006, preserving its checks,
permissions and repository guard. The complete intended workflow below shows the Rust setup
and expanded shell-lint coverage. Preserve any stricter predecessor no-skip CI enforcement.

The job runs on `ubuntu-slim` (plan 001): one vCPU, a hard 15-minute job limit, and no Rust
preinstalled, so the workflow first installs a pinned, checksum-verified `rustup`. After the
first CI run on GitHub, check the job's duration. If it takes more than about 10 minutes, move
the Rust stack-pack tests to their own `ubuntu-latest` job (rustup preinstalled, no 15-minute
cap), or switch this job back to `ubuntu-latest` and drop the rustup install step.

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
    # 1-vCPU container runner, GitHub's lower-cost option for short jobs (15-minute
    # job cap). It ships bash, git, perl, GNU tar and curl; the tools are pinned below.
    runs-on: ubuntu-slim
    steps:
      - uses: actions/checkout@v7

      - name: Install gitleaks
        uses: ./.github/actions/install-gitleaks

      - name: Install shellcheck (pinned, checksum-verified)
        # The image ships shellcheck 0.9.0, which flags code that 0.11.0 accepts.
        env:
          SHELLCHECK_VERSION: 0.11.0
          SHELLCHECK_SHA256: b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6
        run: |
          tarball="shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.gz"
          curl -sSfL -o "$RUNNER_TEMP/$tarball" \
            "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/$tarball"
          echo "${SHELLCHECK_SHA256}  $RUNNER_TEMP/$tarball" | sha256sum -c -
          mkdir -p "$RUNNER_TEMP/bin"
          tar --no-same-owner -xzf "$RUNNER_TEMP/$tarball" -C "$RUNNER_TEMP/bin" \
            --strip-components=1 "shellcheck-v${SHELLCHECK_VERSION}/shellcheck"
          echo "$RUNNER_TEMP/bin" >> "$GITHUB_PATH"

      - name: Install uv (for the python stack-pack tests)
        uses: astral-sh/setup-uv@c18668ad3cf93ea998bef934396af7bb5c839dc7 # v10.2.0
        with:
          version: "0.12.17"

      - name: Install rustup (pinned, checksum-verified; ubuntu-slim has no Rust)
        env:
          RUSTUP_VERSION: 1.29.1
          RUSTUP_INIT_SHA256: dda7234360b7f578ca8b0ddcb80145646fa61a67c1720a5abc7051b35c9fcb71
        run: |
          curl -sSfL -o "$RUNNER_TEMP/rustup-init" \
            "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/x86_64-unknown-linux-gnu/rustup-init"
          echo "${RUSTUP_INIT_SHA256}  $RUNNER_TEMP/rustup-init" | sha256sum -c -
          chmod +x "$RUNNER_TEMP/rustup-init"
          "$RUNNER_TEMP/rustup-init" -y --no-modify-path --profile minimal --default-toolchain none
          echo "${CARGO_HOME:-$HOME/.cargo}/bin" >> "$GITHUB_PATH"

      - name: Install the pinned toolchain for the rust stack-pack tests (CI only)
        run: rustup toolchain install 1.98.1 --profile minimal --component clippy,rustfmt,llvm-tools-preview

      - name: Install cargo-llvm-cov (for the rust stack-pack tests)
        uses: taiki-e/install-action@7623a79cdfecb99d681017af368ca353d9f49bb5 # v2.87.19
        with:
          tool: cargo-llvm-cov@0.9.1
          fallback: none

      - name: Lint shell scripts
        run: shellcheck --version && shellcheck bootstrap scripts/*.sh template/stacks/*/files/scripts/*.sh template/stacks/*/files/scripts/check.d/*.sh template/stacks/*/after-bootstrap template/stacks/*/validate-name

      - name: Template self-test
        env:
          SELFTEST_RUST_TOOLCHAIN: "1.98.1"
        run: ./scripts/template-selftest.sh
```

**Verify**: YAML parses (command table). Inspect the diff against the preflight snapshot:
only Rust provisioning and broader shell lint are added; predecessor guards remain present.
The template CI override must match the generated project's toolchain pin; keep the local
installed-toolchain override available for rehearsal.

### Step 4: Rust files use 4-space indentation

In `.editorconfig`, change `[*.{py,go}]` to `[*.{py,go,rs}]` (rustfmt's default is 4 spaces; the
global default is 2).

**Verify**: `grep -c '^\[\*\.{py,go,rs}\]$' .editorconfig` → `1`.

### Step 5: List the pack in `TEMPLATE.md`

In `## Stack packs`, extend the existing Available paragraph to describe both packs:

```markdown
Available: `python` (uv, ruff, ty, pytest with separate 90% line and branch floors) and `rust`
(pinned toolchain, clippy pedantic, rustfmt, cargo-llvm-cov with 90% line and region floors).
```

**Verify**: `grep -c 'cargo-llvm-cov with 90% line and region floors' TEMPLATE.md` → `1`.

### Step 6: Full verification and a manual look

```sh
./scripts/template-selftest.sh             # baseline + 6 discovered; zero failures
./scripts/check.sh                         # exit 0
```

Record local skips with tool names. Fully provisioned CI must have zero skips. Do not claim
first-push CI or revised coverage is verified until that job has actually run.

Then inspect a generated project in a scratch directory. Run this in a subshell from the repo
root, after committing the pack, so the clone contains the intended changes. `rustup run`
without `--install` requires an existing toolchain and applies its override to bootstrap too:

```sh
(
  set -eu
  test_toolchain="${SELFTEST_RUST_TOOLCHAIN:-stable}"
  rustup run "$test_toolchain" cargo --version
  before_toolchains="$(rustup run "$test_toolchain" rustup toolchain list)"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  git clone -q "$PWD" "$tmp/demo-app"
  cd "$tmp/demo-app"
  git remote remove origin
  rustup run "$test_toolchain" ./bootstrap --name "Demo App" --stack rust --yes
  test -f Cargo.lock                       # bootstrap hook must actually have succeeded
  git add -A
  git commit -qm init
  rustup run "$test_toolchain" ./scripts/check.sh
  rustup run "$test_toolchain" cargo test --locked
  rustup run "$test_toolchain" cargo run --locked -q -- --version
  # Expect demo_app followed by the actual VERSION file, not a hardcoded version.
  test "$(rustup run "$test_toolchain" rustup toolchain list)" = "$before_toolchains"
)
```

## Test plan

- Six new template tests: generated project checks/tests/version; real coverage; malformed or
  absent coverage/config; tier floor/membership ratchets; workspace rejection; reserved-name
  preflight with unchanged tree. The coverage-data probes require no cargo-llvm-cov.
- Generated CLI tests cover no arguments, `--help`, `--version`, unknown arguments and surplus
  arguments; they assert the appropriate stdout/stderr and exit status.
- Coverage probes include valid positive controls, each independent line/region failure, an
  explicit empty tier, malformed schema, duplicate report filenames, missing includes, empty
  summaries, zero counters, negative, non-finite, counters beyond the safe integer range and over-covered counters. `--report` also fails closed.
- Ratchet probes cover unchanged configuration, additions, raised floors, removed members,
  removed tiers and lower floors/targets. Mechanism tests from revised 006 keep passing.

## Done criteria

ALL must hold:

- [ ] Full self-test discovers preflight baseline + 6 tests and has zero failures; every local
      skip is named, and fully provisioned CI has zero skips
- [ ] All five generated CLI tests pass on the selected installed toolchain
- [ ] Both shell-lint and YAML commands pass; predecessor workflow guards remain intact
- [ ] `./scripts/check.sh` exits 0 on the real repo
- [ ] Manual run creates Cargo.lock and prints `demo_app` plus the current VERSION value
- [ ] Toolchain listing under the installed override is unchanged from before local verification
- [ ] Real revised line/region coverage is 100% for both starter files before CI is called green
- [ ] `git status --porcelain` shows only in-scope paths
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- A predecessor contract or baseline test fails.
- clippy reports a lint in the pack’s Rust code. Report it; do not add `#[allow]`s or loosen
  `[lints]`. Local rehearsal on the installed toolchain does not certify the pinned CI toolchain.
- Local self-test or manual verification installs a toolchain/component or invokes an installer.
  Missing prerequisites must skip or fail with instructions, never trigger installation.
- In CI, `rustup toolchain install`, `taiki-e/install-action` or `cargo llvm-cov report
  --fail-under-*` behaves differently from what this plan describes. Report the log. Those three
  were verified against their docs and source (and cargo-llvm-cov locally), but this workflow has
  not run on GitHub yet.

## Maintenance notes

- **Toolchain bumps.** Change `channel` in `template/stacks/rust/files/rust-toolchain.toml` on
  purpose, fix any new clippy lints the new version raises, and keep
  `rust-version` at the oldest Rust the code really needs.
- **When a project takes its first dependency:**
  - Add cargo-deny: `deny.toml` covering advisories, licenses (`private = { ignore = true }`
    because of `publish = false`), bans and sources.
  - Add a CI step, `taiki-e/install-action` with `tool: cargo-deny@0.20.2`, then
    `cargo deny --locked check`, plus a weekly scheduled run. New advisories otherwise surface
    only on unrelated PRs.
  - Consider cargo-shear for unused dependencies.
- **Branch coverage.** When `cargo llvm-cov --branch` works on stable, add
  `--fail-under-branches` if it exists by then. Otherwise extend `coverage_tiers.sh` to gate
  `branches` like `lines` and `regions`, and drop "regions stand in for branches" from
  `coverage.sh` and the pack's `COVERAGE_ENFORCEMENT`.
- **Coverage migrations.** Tier/member removals or moves intentionally fail the ratchet. Make
  such changes in a dedicated, reviewed gate migration that demonstrates replacement coverage
  and records the new approved baseline; do not silence the failure by deleting tiers or lowering
  floors in an ordinary feature change. Adding workspace support likewise requires explicit
  package selection, collection scope and base-tree tests before removing the v1 rejection.
- **The multi-copy pitfall.** If you add unit tests inside `src/` for a function the integration
  tests also run, llvm-cov may under-count that file (it takes the best single copy, not the
  union; cargo-llvm-cov#512). Cover each function fully from one test binary.
- **gstack.**
  - `/ship` step 4 sees `tests/` and reads `cargo test --locked` from `TESTING.md` → Commands,
    synchronized with the retained `CLAUDE.md` → Commands, so it need not bootstrap a test framework.
  - `/health` detects only `cargo test` (no clippy or fmt).
  - Where the installed `/health` skill requires explicit settings, use the existing
    `CLAUDE.md` as described in plan 006's maintenance notes. Its optional `## Health Stack`
    can list `cargo clippy --all-targets -- -D warnings` and `cargo fmt --all --check`.
    Preserve reciprocal required reading; no shim or instruction-file guard is needed.
- Reviewer focus:
  - `coverage_tiers.sh`: the jq, the physical-path strip, and fail-closed on a zero count.
  - The pinned SHAs in both workflows.
