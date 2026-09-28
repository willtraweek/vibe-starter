# Plan 008: Add the `omarchy-app` stack pack (Rust + GPUI + gpui-omarchy), and list every pack by what it builds

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Predecessor preflight (run first)**: plans 001–007 must be done, in order. This plan was
> written at `98063fc` (plan 006 merged as v0.1.0) with plan 007 still TODO, so everything it
> says about plan 007 comes from `plans/007-stack-pack-rust.md`, not from code. Before editing:
> run `./scripts/template-selftest.sh`, record its `selftest: N passed, …` line and any named
> skips in `.context/plan-008-baseline.txt`, and check every contract under "Current state".
> A failing predecessor test, or a contract that differs without an explanation in the plan
> index, is a STOP condition. A changed hash alone is not.

## Status

- **Priority**: P2 (requested by the maintainer)
- **Effort**: L
- **Risk**: MED. New projects get a large dependency tree (GPUI, about 860 crates in
  `Cargo.lock`, about 530 compiled on Linux), and the template gets a second, heavier CI job.
  `bootstrap` changes only how it lists packs; the no-stack path is untouched.
- **Depends on**: 006 (the stack-pack mechanism, merged), 007 (the rust pack, whose gates this
  pack shares byte for byte, and the `rust_env`/`rust_ready` self-test helpers)
- **Category**: direction
- **Planned at**: commit `98063fc`, 2026-09-25. Plans 009 (`omarchy-tui`) and 010
  (`omarchy-plugin`) follow and build on this one.

## Why this matters

The maintainer wants to build software for [Omarchy](https://omarchy.org), the opinionated
Arch Linux + Hyprland desktop (repository `omacom/omarchy`, v4.0.4 at planning time). There are
three kinds of thing to build, and the right stack depends on **what the app should do**:

| The app should… | Pack | Stack | Plan |
|---|---|---|---|
| open its own window, with rich visuals, mouse and keyboard (a treemap, an editor, a dashboard) | `omarchy-app` | Rust + GPUI (gpui-kit) + gpui-omarchy | **008** |
| be a keyboard-driven tool in a terminal, light, fine over SSH | `omarchy-tui` | Rust + ratatui | 009 |
| live inside the desktop itself: a bar widget, a panel, a menu, an overlay, a background service | `omarchy-plugin` | QML shell plugin for Omarchy 4's `omarchy-shell` | 010 |

This plan adds the first, and the shared pieces all three need. The evidence for the stack:
Tobi Lütke's [disktree](https://github.com/tobi/disktree) (a disk-usage treemap, "for Omarchy.
Rust + GPUI.", 2026-09-24) uses exactly gpui-kit 0.6.6 and gpui-omarchy 0.1.3. It ships release
tarballs that an AUR `disktree-bin` package installs, and Omarchy has open changes to preinstall
it (`omacom/omarchy-pkgs#624`, `omacom/omarchy#13262`). gpui-omarchy (by huacnlee, the author
of gpui-component/gpui-kit) is the component library that makes a GPUI app look and behave like
Omarchy, and it follows the active Omarchy theme live.

After this plan:

- `./bootstrap --stack omarchy-app` creates an app that:
  - opens a GPUI window in the active Omarchy theme and switches live on `omarchy theme set`
    (Tokyo Night away from Omarchy, so it builds and runs on macOS too);
  - has pure logic, a CLI contract and a main window tested headlessly (no display, no GPU),
    at 90% line and region coverage with per-tier floors;
  - is linted by clippy pedantic with warnings as errors and formatted by rustfmt, on the
    same pinned Rust 1.98.1 as the rust pack;
  - installs into the Omarchy launcher with `./scripts/install.sh` (binary, desktop entry,
    icon under `~/.local`), with a window class that Hyprland rules can match;
  - has live CI that is green on its first push, and takes its version from `VERSION`.
- `./bootstrap --help` and the interactive prompt list every pack with one line saying what it
  builds, so a person or an agent can choose by purpose.
- The template's CI builds a real `omarchy-app` project on every pull request, in a separate
  job, because GPUI is too big for the 1-vCPU, 15-minute `ubuntu-slim` job.

## Design decisions (each verified while planning)

- **A pack family, named by what it builds.** `omarchy-app` now, `omarchy-tui` (009) and
  `omarchy-plugin` (010) next. Each pack gets a one-line `description` file (`Omarchy app in
  its own window: Rust + GPUI + gpui-omarchy`). `bootstrap --help` and the interactive prompt
  print them; `TEMPLATE.md` carries the "what should the app do?" table above. The existing
  `python` and `rust` packs get descriptions too; a new self-test requires one for every pack.
- **GPUI comes from gpui-kit, pinned exactly.** `gpui-kit = "=0.6.6"` (Longbridge, Apache-2.0)
  republishes Zed's GPUI as `gpui-pre =0.3.6`; the official `gpui` crate stopped at 0.2.2 in
  2025. gpui-kit shipped seven releases between 2026-09-03 and 09-21 (0.6.5 was yanked), and a
  caret requirement once broke it overnight (longbridge/gpui-kit#3156). `gpui-omarchy = "=0.1.3"`
  (MIT, released 2026-09-25) pins `gpui-kit =0.6.6` itself, so the two move together, on
  purpose. Never depend on `gpui` or `gpui-pre` directly.
- **Same toolchain as the rust pack; honest `rust-version`.** `rust-toolchain.toml`,
  `rustfmt.toml`, `scripts/coverage.sh`, `scripts/coverage_tiers.sh` and
  `scripts/check.d/rust.sh` are byte-identical copies of the rust pack's (a self-test enforces
  it; with two Rust packs, the rule of three says copy, not abstract). `rust-version` is
  `"1.98"`, not the rust pack's `"1.85"`: GPUI's dependency graph needs 1.92 or newer, and a
  lower value makes Cargo's MSRV-aware resolver hold dependencies back.
- **The theme is Omarchy's, live.** `gpui_omarchy::init` reads
  `~/.local/state/omarchy/current/theme/colors.toml` (falling back to the pre-4.0
  `~/.config/omarchy/current`), watches it with inotify through `notify`, and survives
  Omarchy's `rm -rf` + `mv` theme swap. Required keys: `background`, `foreground`, `accent`, and
  `red`/`yellow`/`green` (or ANSI `color1..3`). Any failure falls back to Tokyo Night as a
  whole. The pack's `scripts/check.d/omarchy.sh` refuses GPUI's fixed-colour constructors
  (`rgb(`, `white()` and the rest) and `linear_gradient(` in `src/`, so colours come from the
  theme's roles (`cx.omarchy()`) and surfaces stay flat. The check reads text, not types; the
  pack's `DESIGN.md`, which replaces the skeleton's with Omarchy's design rules, says so. Only
  the Omarchy packs carry these guards, and a test keeps it that way.
- **Testable by construction.** Verified in an `ubuntu:24.04` container on Rust 1.98.1:
  - `#[gpui_kit::test]` runs a seeded test platform with no renderer: window tests draw frames,
    press keys and click, with no display, xvfb or GPU. 14 starter tests pass.
  - Start-up lives in the library as `app::start(cx)`, which a test calls; `main.rs` keeps one
    untestable call, `gpui_kit::application().with_assets(Assets).run(app::start)`.
  - Tests live in `tests/*.rs` (the rust pack's rule), which cargo-llvm-cov excludes from the
    report.
  - Measured: 93.20% lines and 93.87% regions overall; `src/model.rs` and `src/cli.rs` at 100%;
    `src/app.rs` at 94.06%/94.90% (the quit-on-close closure is untestable: GPUI's test
    platform makes `quit` a no-op). Without the `start` split the total was 89.8% and failed.
  - clippy pedantic passes with `unsafe_code = "forbid"`; every `actions!` entry needs a `///`
    doc because of `missing_docs`.
- **rustfmt's layout depends on the project name.** With package names `ab` and a 49-character
  one, `cargo fmt --check` failed on the starter as written. `after-bootstrap` therefore runs
  `cargo fmt --all` first (it works offline, before any lockfile), then
  `cargo generate-lockfile` (network). Verified for both names, and for `MyApp` (a CamelCase
  name in a doc comment would trip clippy's `doc_markdown`, so names appear only in strings).
  Code names its own crate `::{{PACKAGE_NAME}}::…`, so a project named like one of its modules
  or imports (`app`, `cli`) still compiles; the heavy test checks those names.
- **Desktop integration uses stable surfaces only.** `APP_ID` (the package name) is the Wayland
  app id, which Hyprland reports as the window class; the desktop entry's `StartupWMClass`, the
  installed binary and the icon share it, and a named test keeps them in step. `install.sh`
  installs under `~/.local` (on the session `PATH` in Omarchy). Omarchy 4's Hyprland config is
  Lua with no drop-in directory (so Omarchy's own apps print snippets, never edit it), so the
  generated `docs/guides/omarchy.md` shows the `o.bind(...)` and `o.window(...)` lines to add by
  hand. Both helpers exist in v4.0.4; `o.rebind` does not, so the guide doesn't use it.
- **CI for new projects** runs on `ubuntu-24.04` (pinned: `ubuntu-latest` moves to 26.04 and
  the apt names below are 24.04's) with three build packages, verified in a fresh container:
  `pkg-config libfontconfig-dev libxkbcommon-x11-dev` (they pull in freetype, xcb and
  xkbcommon), plus `desktop-file-utils`. On x86_64, Rust links with rust-lld by default, which
  keeps GPUI's links small (an 8 GB aarch64 container running GNU ld was OOM-killed linking five
  test binaries at once).
- **The template's CI gets a `heavy` job.** Tests named `test_heavy_*` build real projects. The
  existing job excludes them with a new `SELFTEST_EXCLUDE` (excluded tests are neither run nor
  counted, so "skips fail CI" still holds), and a new `ubuntu-24.04` job runs only them, with a
  cache. Locally they skip unless `SELFTEST_HEAVY=1`. Cost, from real runs: a cold GPUI test
  build takes 2.5–3.3 min on a 4-vCPU public runner and about twice that on the 2-vCPU runners
  private repositories get; the whole gate took 1 min 45 s cold on 4 fast cores. Warm runs take
  about a minute.
- **Guards learn whether CI requires their tools.** `check.sh` already decides that a missing
  gitleaks fails in CI and is skipped locally (`ci_requires_gitleaks`). It now exports
  `CHECK_CI=1` or `0` to `scripts/check.d/*.sh`, so the omarchy guard applies the same rule to
  `desktop-file-validate`.
- **Out of scope, on purpose:** a release workflow, AUR packaging and a macOS app bundle (the
  generated guide documents disktree's release layout for later); the TUI and plugin packs
  (009, 010).

## Current state

Verify these before editing. Plan 006 is merged; plan 007 is described by its plan file.

- `bootstrap` (as merged in 006):
  - the help case is one line, around line 60:
    `    -h|--help) echo "Usage: ./bootstrap [--name <project>] [--stack <name>] [--yes] [--force]"; exit 0 ;;`
  - the stack prompt, inside "Stack pack preflight", is
    `  printf "Stack pack [none %s]: " "$STACKS"`, directly under
    `elif [ "$STACK_GIVEN" = "0" ] && [ "$ASSUME_YES" != "1" ] && [ -t 0 ] && [ -n "$STACKS" ]; then`;
  - a pack is valid when it has `files/`, `commands` and `gitignore`; `validate-name` runs
    before any write, from the template root, as `sh validate-name PACKAGE_NAME PROJECT_NAME`;
    `after-bootstrap` runs near the end and its failure only prints a note.
- `scripts/check.sh` defines `ci_requires_gitleaks` and, near the end, runs every guard:
  ```bash
  # --- Stack guards: scripts/check.d/*.sh -------------------------------------
  # Stack packs (./bootstrap --stack ...) and the project itself add guards here.
  # Each runs from the repo root; a non-zero exit fails the check.
  for guard in scripts/check.d/*.sh; do
  ```
- `scripts/template-selftest.sh`:
  - lines 9–10 are the usage comment; lines 41–42 are `FILTER="${1:-}"` and
    `PASS=0; FAIL=0; SKIP=0`; the runner at the end prints
    `echo "selftest: $PASS passed, $FAIL failed, $SKIP skipped"` and, under `CI=true`, fails
    on any skip;
  - helpers from 006: `fresh_copy`, `run_bootstrap`, `run_check`, `check_fixture`,
    `tree_fingerprint`, `assert_*`, `fail`, `skip`, `stack_env`, `tty_bootstrap`,
    `fixture_pack`; from 007: `rust_env` (runs a command under
    `rustup run "${SELFTEST_RUST_TOOLCHAIN:-stable}"`) and `rust_ready` (prints why the Rust
    tools are missing, or nothing);
  - `test_bootstrap_stack_prompt_at_a_terminal` asserts `"Stack pack [none fixture python"`
    twice. Adding `omarchy-app` (which sorts before `python`) breaks that prefix, so step 1
    loosens it.
  - `test_stack_pack_files_carry_only_bootstrap_owned_tokens` rejects any `{{` or `}}` in pack
    files other than `{{PROJECT_NAME}}`, `{{PACKAGE_NAME}}` and `{{YEAR}}`. So pack workflows
    must not use GitHub `${{ }}` expressions, and the pack below doesn't.
- `template/stacks/rust/` exists as plan 007 specifies: `validate-name` prints
  `reserved Rust package name: <name>`; `files/` holds `rust-toolchain.toml` (channel `1.98.1`),
  `rustfmt.toml`, `scripts/coverage.sh`, `scripts/coverage_tiers.sh` and
  `scripts/check.d/rust.sh`. This plan copies those five files; it does not restate them.
- `.github/workflows/template-selftest.yml` has one job, `selftest`, on `ubuntu-slim` (1 vCPU,
  15-minute cap). After 007 it also installs a pinned rustup, Rust 1.98.1 (clippy, rustfmt,
  llvm-tools-preview) and cargo-llvm-cov 0.9.1, lints the pack scripts with shellcheck 0.11.0,
  and runs `./scripts/template-selftest.sh` with `SELFTEST_RUST_TOOLCHAIN: "1.98.1"`. Master's
  ruleset requires the `selftest` check.
- `TEMPLATE.md` has `## Stack packs` (the pack interface as bullets, then an "Available:" line
  naming `python` and, after 007, `rust`) and `### Verifying a change`.

Conventions: bash 3.2 compatible (macOS `/bin/bash`), `#!/usr/bin/env bash`, `# --- Section ---`
dividers, errors to stderr, `exit 2` for usage errors. Values reach perl through the
environment, never through a shell. Tests are `test_*` functions that `return 1` via `fail`, or
`skip` with a reason.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Self-test (all but heavy) | `SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh` | baseline + 8 passed, 0 failed; skips only for tools missing locally (name them) |
| This plan's light tests | `./scripts/template-selftest.sh omarchy_app` | 5 passed, 1 skipped (the heavy one) |
| The heavy test, locally | `SELFTEST_HEAVY=1 SELFTEST_RUST_TOOLCHAIN=1.98.1 ./scripts/template-selftest.sh test_heavy_` | 1 passed (needs Rust 1.98.1, cargo-llvm-cov, jq; on Linux the three apt packages). It was verified on Linux; on macOS, a build failure is "not run locally", not a STOP |
| Shell lint | `shellcheck bootstrap scripts/*.sh template/stacks/*/files/scripts/*.sh template/stacks/*/files/scripts/check.d/*.sh template/stacks/*/after-bootstrap template/stacks/*/validate-name` | exit 0 (CI uses shellcheck 0.11.0) |
| YAML | `ruby -ryaml -e 'ARGV.each(&YAML.method(:load_file))' .github/workflows/template-selftest.yml template/stacks/omarchy-app/files/.github/workflows/ci.yml` | exit 0 |
| Checks | `./scripts/check.sh` | exit 0 |

Missing local tools produce named skips. Never install toolchains, components or cargo tools
while executing this plan; CI installs them.

## Suggested executor toolkit

- gstack `/review` on the finished diff; `/investigate` if the heavy test fails.
- Do not run gstack `/ship` unless asked.

## Scope

**In scope** (the only files you should modify or create):

- `scripts/template-selftest.sh` (steps 1–2), `scripts/check.sh` (step 3), `bootstrap` (step 4)
- `template/stacks/python/description`, `template/stacks/rust/description` (create, step 4)
- everything under `template/stacks/omarchy-app/` (create, step 5)
- `.github/workflows/template-selftest.yml` (step 6), `TEMPLATE.md` (steps 4 and 7)
- `plans/README.md` (your status row)

**Out of scope** (do NOT touch):

- The python and rust packs' other files. If a byte-identity test fails, the omarchy-app copy
  is wrong, not the rust pack.
- `AGENTS.md`, `CLAUDE.md`, `TESTING.md`, `README.md` and the root `DESIGN.md`: packs fill or
  replace them in new projects only; the template keeps its placeholders.
- `.gitleaks.toml`: a GPUI `Cargo.lock` (864 packages, 861 checksums) scans clean with
  gitleaks 8.30.1 and the template's config (verified).
- A release workflow, AUR files, a macOS bundle, and the `omarchy-tui`/`omarchy-plugin` packs.

## Git workflow

- Work on the branch you were given; do not rename it.
- Commit per step, plain imperative messages (e.g. `Add the omarchy-app stack pack`).
- Do NOT push or open a PR unless the operator told you to.

## Steps

### Step 1: Add the failing tests

1. In `test_bootstrap_stack_prompt_at_a_terminal`, change both occurrences of
   `"Stack pack [none fixture python"` to `"Stack pack [none fixture "`. Then, directly above
   its line `  assert_contains "$root/typed/demo/src/demo/hello.txt" "package=demo" || return 1`,
   insert (the `-s` check keeps the second line from passing on an empty description):

   ```bash
     [ -s "$REPO/template/stacks/omarchy-app/description" ] || fail "omarchy-app has no description" || return 1
     assert_contains "$root/typed/demo.out" "$(printf '  %-15s %s' omarchy-app "$(head -n 1 "$REPO/template/stacks/omarchy-app/description")")" || return 1
   ```

2. Insert this block immediately **above** `# --- runner ---`, after plan 007's block:

```bash
# --- tests: omarchy-app stack pack and the pack family (plan 008) -------------
test_bootstrap_help_lists_stack_packs_with_what_they_are_for() {
  # --help is where an agent looks before choosing --stack: every pack is listed
  # with its one-line description (so each pack must have one); nothing changes.
  local d="$WORK/help-stacks/proj" before rc pack desc n=0
  fresh_copy "$d" || return 1
  before="$(tree_fingerprint "$d")"
  (cd "$d" && ./bootstrap --help >"$d.out" 2>&1); rc=$?
  assert_exit 0 "$rc" || return 1
  for pack in "$d"/template/stacks/*/; do
    pack="$(basename "$pack")"
    desc="$(head -n 1 "$d/template/stacks/$pack/description" 2>/dev/null)"
    [ -n "$desc" ] || fail "template/stacks/$pack has no description" || return 1
    grep -qxF -- "$(printf '  %-15s %s' "$pack" "$desc")" "$d.out" \
      || fail "--help does not list $pack with its description: $(cat "$d.out")" || return 1
    n=$((n + 1))
  done
  [ "$n" -ge 3 ] || fail "expected at least the python, rust and omarchy-app packs; found $n" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "--help changed files"
}
test_check_tells_guards_whether_ci_requires_tools() {
  # A guard in scripts/check.d may skip a missing tool locally but must fail in
  # CI: check.sh hands it CHECK_CI, decided by the same rule as gitleaks.
  local d="$WORK/check-ci-flag/proj" setting
  check_fixture "$d" || fail "fixture setup failed" || return 1
  mkdir -p "$d/scripts/check.d" || return 1
  cat > "$d/scripts/check.d/probe.sh" <<'GUARD'
echo "guard saw CHECK_CI=${CHECK_CI:-unset}"
GUARD
  for setting in CI=true:1 CI=1:1 GITHUB_ACTIONS=true:1 CI=false:0 CI=no:0 CI=:0; do
    # CI= first: GitHub exports CI=true, which would otherwise answer for GITHUB_ACTIONS.
    run_check "$d" GITLEAKS_BIN=/nonexistent/gitleaks CI= "${setting%:*}"
    assert_contains "$d.out" "guard saw CHECK_CI=${setting##*:}" || return 1
  done
}
test_selftest_exclude_skips_matching_tests_without_counting_them() {
  # The 1-vCPU CI job runs everything but test_heavy_* and fails on any skip, so
  # SELFTEST_EXCLUDE must neither run nor count what it excludes.
  local out="$WORK/selftest-exclude.out" rc
  SELFTEST_EXCLUDE=_unknown_arg "$REPO/scripts/template-selftest.sh" _rejects_unknown_ >"$out" 2>&1; rc=$?
  assert_exit 0 "$rc" || return 1
  assert_contains "$out" "- test_bootstrap_rejects_unknown_stack" || return 1
  assert_not_contains "$out" "- test_bootstrap_rejects_unknown_arg" || return 1
  assert_contains "$out" "selftest: 1 passed, 0 failed, 0 skipped (1 excluded by SELFTEST_EXCLUDE=_unknown_arg)"
}
omarchy_app_project() {  # $1 = dir: a fresh copy bootstrapped as "Demo App" with omarchy-app
  # cargo is a stub that fails and logs its calls to "$1.cargo-calls": no
  # network, and after-bootstrap has to report that it couldn't lock.
  mkdir -p "$1.stub" || return 1
  cat > "$1.stub/cargo" <<STUB || return 1
#!/bin/sh
echo "cargo \$*" >> "$1.cargo-calls"
exit 101
STUB
  chmod +x "$1.stub/cargo" || return 1
  fresh_copy "$1" || return 1
  PATH="$1.stub:$(printenv PATH)" run_bootstrap "$1" --name "Demo App" --stack omarchy-app --yes \
    || fail "bootstrap exited $?: $(tail -20 "$1.out")"
}
test_stack_omarchy_app_bootstrap_installs_the_pack() {
  local d="$WORK/omarchy-app/demo-app" f s
  omarchy_app_project "$d" || return 1
  assert_contains "$d/Cargo.toml" 'name = "demo_app"' || return 1
  assert_contains "$d/src/lib.rs" 'pub const APP_ID: &str = "demo_app";' || return 1
  assert_contains "$d/packaging/app.desktop.in" 'StartupWMClass=demo_app' || return 1
  assert_contains "$d/DESIGN.md" "gpui-omarchy" || return 1
  assert_exists "$d/docs/guides/omarchy.md" || return 1
  assert_exists "$d/.github/workflows/ci.yml" || return 1
  assert_absent "$d/.github/workflows/ci.yml.example" || return 1
  { [ -x "$d/scripts/install.sh" ] && [ -x "$d/scripts/check.d/omarchy.sh" ]; } \
    || fail "the pack's scripts lost their exec bit" || return 1
  assert_contains "$d/TESTING.md" "Tests: \`cargo test --locked\`" || return 1
  assert_contains "$d/CLAUDE.md" "Tests: \`cargo test --locked\`" || return 1
  assert_contains "$d/.bootstrapped" "with the omarchy-app stack pack" || return 1
  # after-bootstrap formats first (the name changed line lengths), then locks.
  [ "$(cat "$d.cargo-calls")" = "$(printf 'cargo fmt --all\ncargo generate-lockfile --quiet')" ] \
    || fail "after-bootstrap ran: $(cat "$d.cargo-calls")" || return 1
  assert_contains "$d.out" "cargo generate-lockfile failed (offline?)" || return 1
  for s in '{{PACKAGE_NAME}}' '{{TEST_CMD' TEMPLATE.md template/stacks template-selftest; do
    assert_tree_lacks "$d" "$s" || return 1
  done
  # git commits every pack file and the lockfile, and ignores the build output.
  : > "$d/Cargo.lock"
  (cd "$d" && git add -A) || fail "git add failed" || return 1
  { git -C "$REPO" ls-files --cached --others --exclude-standard -- template/stacks/omarchy-app/files \
      | sed 's|^template/stacks/omarchy-app/files/||'
    printf '%s\n' Cargo.lock .github/actions/install-gitleaks/action.yml
  } > "$d.expected" || return 1
  while IFS= read -r f; do
    git -C "$d" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || fail "git would not commit $f" || return 1
  done < "$d.expected"
  for f in target/debug/demo_app coverage.json lcov.info default_1.profraw; do
    git -C "$d" check-ignore -q -- "$f" || fail "git would commit the build artifact $f" || return 1
  done
}
test_stack_omarchy_app_rejects_unusable_names_before_writes() {
  # The crates it builds on, the omarchy command, and (from the rust pack) Rust's
  # reserved names: each exits 2 before any file changes.
  local d name before rc
  for name in "gpui kit" GPUI-Omarchy omarchy async Std; do
    d="$WORK/omarchy-app-names/$(printf '%s' "$name" | tr ' ' '_')/proj"
    fresh_copy "$d" || return 1
    before="$(tree_fingerprint "$d")"
    run_bootstrap "$d" --name "$name" --stack omarchy-app --yes; rc=$?
    assert_exit 2 "$rc" || return 1
    case "$name" in
      async|Std) assert_contains "$d.out" "reserved Rust package name" || return 1 ;;
      *) assert_contains "$d.out" "is taken by a crate this pack builds on" || return 1 ;;
    esac
    [ "$before" = "$(tree_fingerprint "$d")" ] || fail "'$name' changed files before its rejection" || return 1
  done
}
test_stack_omarchy_app_install_script_installs_and_uninstalls() {
  # install.sh puts exactly three files under PREFIX and removes exactly those;
  # the stub stands in for the release binary, so nothing is compiled.
  local d="$WORK/omarchy-app-install/demo-app" p="$WORK/omarchy-app-install/prefix" rc f entry
  omarchy_app_project "$d" || return 1
  mkdir -p "$d/target/release" "$WORK/omarchy-app-install/elsewhere/release" || return 1
  printf '#!/bin/sh\necho demo_app\n' > "$d/target/release/demo_app"
  chmod +x "$d/target/release/demo_app" || return 1
  (cd "$d" && PREFIX="$p" ./scripts/install.sh --no-build) >"$d.install" 2>&1 \
    || fail "install exited $?: $(cat "$d.install")" || return 1
  entry="$p/share/applications/demo_app.desktop"
  [ -x "$p/bin/demo_app" ] || fail "the binary is not installed and executable" || return 1
  assert_exists "$p/share/icons/hicolor/scalable/apps/demo_app.svg" || return 1
  assert_contains "$entry" "Exec=\"$p/bin/demo_app\"" || return 1
  assert_contains "$entry" "X-AppVersion=0.0.0" || return 1
  (cd "$d" && PREFIX="$p" ./scripts/install.sh --print-desktop-entry) | cmp -s - "$entry" \
    || fail "--print-desktop-entry differs from the installed entry" || return 1
  : > "$p/bin/keep-me" && : > "$p/share/applications/other.desktop" || return 1
  (cd "$d" && PREFIX="$p" ./scripts/install.sh --uninstall) >/dev/null 2>&1 || fail "uninstall failed" || return 1
  for f in bin/demo_app share/applications/demo_app.desktop share/icons/hicolor/scalable/apps/demo_app.svg; do
    assert_absent "$p/$f" || return 1
  done
  assert_exists "$p/bin/keep-me" || return 1
  assert_exists "$p/share/applications/other.desktop" || return 1
  # The binary is found where CARGO_TARGET_DIR put it.
  mv "$d/target/release/demo_app" "$WORK/omarchy-app-install/elsewhere/release/demo_app" || return 1
  (cd "$d" && CARGO_TARGET_DIR="$WORK/omarchy-app-install/elsewhere" PREFIX="$p" ./scripts/install.sh --no-build) \
    >"$d.install" 2>&1 || fail "install with CARGO_TARGET_DIR exited $?: $(cat "$d.install")" || return 1
  assert_exists "$p/bin/demo_app" || return 1
  (cd "$d" && PREFIX="$p" ./scripts/install.sh --no-build) >"$d.install" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.install" "is missing; build it first" || return 1
  (cd "$d" && ./scripts/install.sh --bogus) >/dev/null 2>&1; rc=$?
  assert_exit 2 "$rc" || return 1
  (cd "$d/scripts" && ./install.sh --help) >"$d.help" 2>&1 \
    || fail "--help from scripts/ exited $?: $(cat "$d.help")" || return 1
  assert_contains "$d.help" "--print-desktop-entry" || return 1
  (cd "$d" && BINDIR='/tmp/a"b' ./scripts/install.sh --print-desktop-entry) >/dev/null 2>&1; rc=$?
  assert_exit 2 "$rc"
}
test_stack_omarchy_app_guard_refuses_colour_literals_and_needs_its_validator_in_ci() {
  local d="$WORK/omarchy-app-guard/demo-app" rc
  omarchy_app_project "$d" || return 1
  # The starter passes; a missing validator is a notice locally...
  (cd "$d" && CHECK_CI=0 DESKTOP_FILE_VALIDATE_BIN=/nonexistent bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1 \
    || fail "the starter failed the guard: $(cat "$d.guard")" || return 1
  assert_contains "$d.guard" "skipping the desktop entry check" || return 1
  # ...and a failure where check.sh says CI.
  (cd "$d" && CHECK_CI=1 DESKTOP_FILE_VALIDATE_BIN=/nonexistent bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard" "required in CI" || return 1
  # Every fixed-colour spelling fails, and the guard says where (never the
  # signature line, which names Hsla too)...
  for lit in 'gpui_kit::rgb(0x12_34_56)' 'gpui_kit::rgba(0x1234_56ff)' 'gpui_kit::hsla(0.1, 0.2, 0.3, 1.0)' \
    'gpui_kit::white()' 'gpui_kit::Hsla::black()' 'gpui_kit::red()' 'gpui_kit::opaque_grey(0.5, 1.0)' \
    'gpui_kit::transparent_black()' 'gpui_kit::Rgba::try_from("#123456").unwrap()'; do
    printf 'pub fn tint() -> gpui_kit::Hsla {\n    %s.into()\n}\n' "$lit" > "$d/src/tint.rs"
    (cd "$d" && CHECK_CI=0 DESKTOP_FILE_VALIDATE_BIN=/nonexistent bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1; rc=$?
    assert_exit 1 "$rc" || return 1
    assert_contains "$d.guard" "colour literals" || return 1
    assert_contains "$d.guard" "src/tint.rs:2:" || return 1
    assert_not_contains "$d.guard" "src/tint.rs:1:" || return 1
  done
  # ...and so does a gradient, whatever its colours: Omarchy surfaces are flat.
  printf 'pub fn fill(stops: [gpui_kit::LinearColorStop; 2]) -> gpui_kit::Background {\n    gpui_kit::linear_gradient(90.0, stops[0], stops[1])\n}\n' > "$d/src/tint.rs"
  (cd "$d" && CHECK_CI=0 DESKTOP_FILE_VALIDATE_BIN=/nonexistent bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard" "Omarchy surfaces are flat" || return 1
  # Colours from the theme's roles pass, and so does a helper named like a colour.
  printf 'pub fn tint(cx: &gpui_kit::App) -> gpui_kit::Hsla {\n    redraw_hint(cx.omarchy().accent.opacity(0.5))\n}\n' > "$d/src/tint.rs"
  (cd "$d" && CHECK_CI=0 DESKTOP_FILE_VALIDATE_BIN=/nonexistent bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1 \
    || fail "theme-derived colours failed the guard: $(cat "$d.guard")" || return 1
  rm -f "$d/src/tint.rs"
  # The Omarchy guards ship only with Omarchy packs: no other pack, and not the
  # shared Rust gates, refuses colours or gradients.
  for f in "$REPO"/template/stacks/*/files/scripts/check.d/omarchy*.sh; do
    [ -e "$f" ] || continue
    case "$f" in
      "$REPO"/template/stacks/omarchy-*) ;;
      *) fail "an Omarchy guard outside an Omarchy pack: $f" || return 1 ;;
    esac
  done
  # The validator gets exactly the entry install.sh writes.
  cat > "$d.stub/validate" <<STUB || return 1
#!/bin/sh
cp "\$1" "$d.validated"
STUB
  chmod +x "$d.stub/validate" || return 1
  (cd "$d" && CHECK_CI=1 DESKTOP_FILE_VALIDATE_BIN="$d.stub/validate" bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1 \
    || fail "the guard failed with a passing validator: $(cat "$d.guard")" || return 1
  (cd "$d" && PREFIX=/usr/local ./scripts/install.sh --print-desktop-entry) | cmp -s - "$d.validated" \
    || fail "the validator did not get install.sh's entry"
}
test_stack_omarchy_app_shares_the_rust_packs_gates() {
  # One toolchain pin, formatter config and coverage gate for both Rust packs:
  # byte-identical copies until a third Rust pack extracts them (rule of three).
  local f
  for f in rust-toolchain.toml rustfmt.toml scripts/coverage.sh scripts/coverage_tiers.sh scripts/check.d/rust.sh; do
    cmp -s "$REPO/template/stacks/rust/files/$f" "$REPO/template/stacks/omarchy-app/files/$f" \
      || fail "omarchy-app/files/$f differs from rust/files/$f" || return 1
  done
}
omarchy_app_heavy_ready() {  # why the heavy omarchy-app build can't run here; empty = run it
  if [ "${CI:-}" != "true" ] && [ "${SELFTEST_HEAVY:-}" != "1" ]; then
    echo "builds GPUI (minutes): set SELFTEST_HEAVY=1 to run it here; CI runs it in the heavy job"
    return
  fi
  local why minor
  why="$(rust_ready)"
  [ -z "$why" ] || { echo "$why"; return; }
  minor="$(rust_env rustc --version 2>/dev/null | sed -n 's/^rustc 1\.\([0-9][0-9]*\)\..*/\1/p')"
  [ "${minor:-0}" -ge 98 ] \
    || { echo "the test toolchain is older than the pack's rust-version 1.98 (set SELFTEST_RUST_TOOLCHAIN=1.98.1)"; return; }
  rust_env cargo llvm-cov --version >/dev/null 2>&1 || { echo "cargo-llvm-cov not installed"; return; }
  if [ "$(uname -s)" = Linux ] && ! pkg-config --exists fontconfig xkbcommon-x11 2>/dev/null; then
    echo "GPUI's build libraries are missing (apt: pkg-config libfontconfig-dev libxkbcommon-x11-dev)"
  fi
}
test_heavy_stack_omarchy_app_project_is_green() {
  # The whole new-project gate, for real: bootstrap (its hook formats the code and
  # locks GPUI's crates from crates.io), then the project's own check.sh,
  # coverage.sh and ratchet. A long name, because rustfmt's layout depends on it.
  local d="$WORK/heavy-omarchy-app/omarchy-disk-usage-explorer" why target name
  why="$(omarchy_app_heavy_ready)"
  [ -z "$why" ] || { skip "$why"; return; }
  fresh_copy "$d" || return 1
  (cd "$d" && HOME="$WORK/home" rust_env ./bootstrap --name "Omarchy Disk Usage Explorer" \
    --stack omarchy-app --yes </dev/null >"$d.out" 2>&1) || fail "bootstrap exited $?: $(tail -20 "$d.out")" || return 1
  assert_contains "$d.out" "Wrote Cargo.lock" || return 1
  (cd "$d" && git add -A && git commit -qm init) || fail "commit failed" || return 1
  # CI caches one target directory per generated project (one name per pack), so
  # coverage never mixes two projects' builds; locally it lives in the copy.
  target="${SELFTEST_CARGO_TARGET_DIR:+$SELFTEST_CARGO_TARGET_DIR/omarchy_disk_usage_explorer}"
  target="${target:-$d/target}"
  (cd "$d" && CARGO_TARGET_DIR="$target" rust_env ./scripts/check.sh \
    && CARGO_TARGET_DIR="$target" rust_env ./scripts/coverage.sh \
    && CARGO_TARGET_DIR="$target" rust_env ./scripts/coverage_tiers.sh --ratchet HEAD) \
    >"$d.gate.out" 2>&1 || fail "the new project's gate failed: $(tail -30 "$d.gate.out")" || return 1
  if command -v desktop-file-validate >/dev/null 2>&1; then
    # The guard ran the real validator above; prove it would catch a bad entry.
    perl -ni -e 'print unless /^Type=/' "$d/packaging/app.desktop.in"
    if (cd "$d" && CHECK_CI=1 bash scripts/check.d/omarchy.sh) >"$d.guard.out" 2>&1; then
      fail "a desktop entry without Type= passed the guard" || return 1
    fi
  fi
  # A project named like one of the starter's modules or imports still compiles,
  # tests included: the code names its own crate ::name::.
  for name in app cli model; do
    fresh_copy "$d.$name" || return 1
    (cd "$d.$name" && HOME="$WORK/home" rust_env ./bootstrap --name "$name" --stack omarchy-app --yes </dev/null \
      && CARGO_TARGET_DIR="$target" rust_env cargo clippy --locked --all-targets --all-features -- -D warnings) \
      >"$d.$name.out" 2>&1 || fail "a project named $name does not compile: $(tail -20 "$d.$name.out")" || return 1
  done
}
```

**Verify**: `shellcheck scripts/template-selftest.sh` → exit 0. Then run
`./scripts/template-selftest.sh omarchy_app`, `./scripts/template-selftest.sh help_lists`,
`./scripts/template-selftest.sh check_tells` and `./scripts/template-selftest.sh selftest_exclude`.
Expected at this point: `test_stack_omarchy_app_shares_the_rust_packs_gates` and every other
`omarchy_app` test fail (no pack yet), `help_lists` fails (no descriptions), `check_tells` fails
(no `CHECK_CI`), `selftest_exclude` fails (no `SELFTEST_EXCLUDE`), and the heavy test skips
with "set SELFTEST_HEAVY=1". The prompt test fails too if uv is installed (no omarchy-app
description yet). Every predecessor test still passes. Do not apply the final all-green STOP
condition to this test-first step.

### Step 2: Let the self-test exclude heavy tests

In `scripts/template-selftest.sh`:

1. Below the usage line `#        scripts/template-selftest.sh --print-inventory   # the golden placeholder inventory`, add:

   ```bash
   #        SELFTEST_EXCLUDE=<substring>   # skip tests whose name contains it; not counted as skips
   #        SELFTEST_HEAVY=1               # also build real projects locally (test_heavy_*)
   ```

2. Replace `FILTER="${1:-}"` and the `PASS=0; FAIL=0; SKIP=0` line below it with:

   ```bash
   FILTER="${1:-}"
   EXCLUDE="${SELFTEST_EXCLUDE:-}"
   PASS=0; FAIL=0; SKIP=0; EXCLUDED=0
   ```

3. In the runner loop, directly below `  case "$t" in *"$FILTER"*) ;; *) continue ;; esac`, add:

   ```bash
     if [ -n "$EXCLUDE" ]; then
       case "$t" in *"$EXCLUDE"*) EXCLUDED=$((EXCLUDED + 1)); continue ;; esac
     fi
   ```

4. Directly below the line `unset GITLEAKS_BIN EDITORCONFIG_CHECKER_BIN   # check.sh overrides: tests set them explicitly`, add:

   ```bash
   unset CARGO_TARGET_DIR   # a test that builds picks its own (the heavy ones: SELFTEST_CARGO_TARGET_DIR)
   unset PREFIX BINDIR APPDIR ICONDIR DESKTOP_FILE_VALIDATE_BIN   # install.sh and guard overrides
   ```

   An exported `CARGO_TARGET_DIR` would send every generated project's build to one directory,
   where cargo-llvm-cov then reports two projects' files together. An exported `BINDIR` (or
   `PREFIX`, `APPDIR`, `ICONDIR`) would send the install test's files into the caller's own
   directories; tests set what they need.

5. Replace `echo "selftest: $PASS passed, $FAIL failed, $SKIP skipped"` with:

   ```bash
   if [ "$EXCLUDED" -gt 0 ]; then
     echo "selftest: $PASS passed, $FAIL failed, $SKIP skipped ($EXCLUDED excluded by SELFTEST_EXCLUDE=$EXCLUDE)"
   else
     echo "selftest: $PASS passed, $FAIL failed, $SKIP skipped"
   fi
   ```

   Keep the unexcluded line byte-for-byte: other tooling reads it.

**Verify**: `./scripts/template-selftest.sh selftest_exclude` → 1 passed. `shellcheck
scripts/template-selftest.sh` → exit 0.

### Step 3: Tell guards whether CI requires their tools

In `scripts/check.sh`, replace

```bash
# Each runs from the repo root; a non-zero exit fails the check.
for guard in scripts/check.d/*.sh; do
```

with

```bash
# Each runs from the repo root; a non-zero exit fails the check. CHECK_CI tells
# a guard whether a missing tool must fail it (1, the gitleaks rule above) or
# may be skipped with a notice (0).
if ci_requires_gitleaks; then export CHECK_CI=1; else export CHECK_CI=0; fi
for guard in scripts/check.d/*.sh; do
```

**Verify**: `./scripts/template-selftest.sh check_tells` → 1 passed; `./scripts/template-selftest.sh check_` → all pass; `shellcheck scripts/check.sh` → exit 0.

### Step 4: List packs with what they build

1. Create `template/stacks/python/description` containing the single line
   `Python project: Python 3.14, uv, ruff, ty, pytest`, and `template/stacks/rust/description`
   containing `Rust project: Rust 1.98, clippy pedantic, rustfmt, cargo-llvm-cov`.
2. In `bootstrap`, directly above `# --- Parse args ---…`, insert:

   ```bash
   # --- Stack packs, listed by --help and the prompt ---------------------------
   # One line per pack: its name and the one-line `description` of what it builds,
   # in the order the prompt offers them.
   list_stacks() {
     local name
     [ -d template/stacks ] || return 0
     find template/stacks -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort \
       | while IFS= read -r name; do
           printf '  %-15s %s\n' "$name" "$(head -n 1 "template/stacks/$name/description" 2>/dev/null || true)"
         done
   }

   ```

3. Replace the one-line help case with:

   ```bash
       -h|--help)
         echo "Usage: ./bootstrap [--name <project>] [--stack <name>] [--yes] [--force]"
         if [ -d template/stacks ]; then
           echo
           echo "Stack packs (--stack <name>; without one the project stays stack-agnostic):"
           list_stacks
         fi
         exit 0 ;;
   ```

4. Directly above `  printf "Stack pack [none %s]: " "$STACKS"`, insert:

   ```bash
     echo "Stack packs (none keeps the project stack-agnostic):"
     list_stacks
   ```

   The pseudo-terminal test types its answer when it sees `Stack pack [`; the new header says
   `Stack packs (`, so it can't trigger early.
5. In `TEMPLATE.md` → `## Stack packs`, add this bullet after the `after-bootstrap` bullet:

   ```markdown
   - `description`: one line saying what the pack builds, e.g. `Omarchy app in its own window:
     Rust + GPUI + gpui-omarchy`. `./bootstrap --help` and the interactive prompt list it; every
     pack needs one.
   ```

**Verify**: `./bootstrap --help` prints the usage line, a blank line, the header and one line per
pack (`python`, `rust`; `omarchy-app` arrives in step 5). `./scripts/template-selftest.sh
test_bootstrap_` → all pass except two that need step 5's pack:
`test_bootstrap_help_lists_stack_packs_with_what_they_are_for` (it expects a third pack) and, with
uv installed, `test_bootstrap_stack_prompt_at_a_terminal` (it needs the omarchy-app description).
`shellcheck bootstrap` → exit 0.

### Step 5: Create the omarchy-app pack

1. Copy the five shared files from the rust pack, unchanged:

   ```sh
   mkdir -p template/stacks/omarchy-app/files/scripts/check.d
   for f in rust-toolchain.toml rustfmt.toml scripts/coverage.sh scripts/coverage_tiers.sh scripts/check.d/rust.sh; do
     cp -p "template/stacks/rust/files/$f" "template/stacks/omarchy-app/files/$f"
   done
   ```

2. Create each file below with exactly this content. Paths are relative to
   `template/stacks/omarchy-app/`.

`description`:

```text
Omarchy app in its own window: Rust + GPUI + gpui-omarchy
```

`commands`:

```text
# KEY=value lines. ./bootstrap --stack omarchy-app replaces {{KEY}} and
# {{KEY: description}} placeholders in the project's docs with these values.
INSTALL_CMD=cargo build --locked
DEV_CMD=cargo run --locked
BUILD_CMD=cargo build --locked --release
CHECK_CMD=./scripts/check.sh
TEST_CMD=cargo test --locked
SHIP_GATE=./scripts/check.sh && ./scripts/coverage.sh
STACK=An Omarchy desktop app in its own window: Rust 1.98 (edition 2024, pinned in rust-toolchain.toml) with GPUI through gpui-kit 0.6.6 and gpui-omarchy 0.1.3, which follow the active Omarchy theme; clippy (pedantic, warnings are errors); rustfmt; cargo test with GPUI's headless window harness; cargo-llvm-cov; ./scripts/install.sh adds it to the Omarchy launcher.
COVERAGE_ENFORCEMENT=./scripts/coverage.sh: cargo llvm-cov with the 90% line and region floors (regions stand in for branches on stable Rust), then the per-tier gates of scripts/coverage_tiers.sh (pure logic and the command line at 100%, the main window at the 90% floor); CI runs it, fail-closed
```

`gitignore`:

```gitignore
# --- Rust (omarchy-app) ---
/target/
coverage.json
lcov.info
*.profraw
```

`validate-name`:

```sh
#!/bin/sh
# Names an omarchy-app project can't use. Rust's rules come first, from the rust
# pack (keywords and Cargo-reserved names). Then the crates this pack builds on:
# a crate can't depend on a crate with its own name. And `omarchy`, the Omarchy
# command itself. bootstrap runs this from the template root.
rust_rules=template/stacks/rust/validate-name
if [ ! -f "$rust_rules" ]; then
  echo "The omarchy-app pack needs the rust pack ($rust_rules)." >&2
  exit 2
fi
sh "$rust_rules" "$@" || exit 2
case "$1" in
  gpui|gpui_pre|gpui_base|gpui_kit|gpui_kit_assets|gpui_omarchy|omarchy)
    echo "Package name '$1' is taken by a crate this pack builds on, or by the omarchy command; choose another project name." >&2
    exit 2 ;;
esac
```

`after-bootstrap`:

```sh
#!/bin/sh
# Runs once at the end of ./bootstrap --stack omarchy-app, from the project root.
# 1. rustfmt lays lines out by length, and the project's name just changed the
#    starter's lines: format them so `cargo fmt --check` passes (no network).
# 2. Lock GPUI's dependencies (from crates.io, so this needs the network) and
#    commit Cargo.lock, so CI's --locked builds pass on the first push.
if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found: install Rust (https://rustup.rs), run 'cargo fmt --all && cargo generate-lockfile', and commit Cargo.lock."
  exit 0
fi
cargo fmt --all || echo "cargo fmt failed: run 'cargo fmt --all' before your first commit."
if cargo generate-lockfile --quiet; then
  echo "Wrote Cargo.lock - commit it."
else
  echo "cargo generate-lockfile failed (offline?): run it and commit Cargo.lock before your first push."
fi
```

`files/Cargo.toml`:

```toml
[package]
name = "{{PACKAGE_NAME}}"
# The real version is the root VERSION file (gstack /ship bumps it), compiled in
# by src/lib.rs. This one stays 0.0.0 so Cargo.lock never churns.
version = "0.0.0"
edition = "2024"
# GPUI's dependencies need Rust 1.92 or newer. Declare the pinned toolchain
# (rust-toolchain.toml), the only one CI builds with: a lower value makes
# Cargo's MSRV-aware resolver hold dependencies back.
rust-version = "1.98"
description = "{{PROJECT_NAME}}"
publish = false

[dependencies]
# Pinned exactly and bumped together: gpui-kit is pre-1.0 and moves weekly, and
# gpui-omarchy pins the exact gpui-kit it was built against. Never depend on
# gpui or gpui-pre directly; gpui-kit re-exports them.
gpui-kit = { version = "=0.6.6", default-features = false, features = ["assets"] }
gpui-omarchy = "=0.1.3"

[dev-dependencies]
# The window harness: TestAppContext draws real frames and presses real keys,
# with no display or GPU.
gpui-kit = { version = "=0.6.6", default-features = false, features = ["assets", "test-support"] }

[lints.rust]
unsafe_code = "forbid"
missing_docs = "warn"
unexpected_cfgs = { level = "warn", check-cfg = ["cfg(coverage)", "cfg(coverage_nightly)"] }

[lints.clippy]
pedantic = { level = "warn", priority = -1 }
dbg_macro = "warn"
todo = "warn"

[profile.dev]
# GPUI is large. Line tables for this crate keep backtraces readable; no debug
# info for dependencies keeps every test binary's link small and fast.
debug = "line-tables-only"

[profile.dev.package."*"]
debug = false

# gpui-pre-macros leaves a helper ungated in release builds while its module is
# gated on debug_assertions; enable it for the host proc-macro only.
[profile.release.package.gpui-pre-macros]
debug-assertions = true

# Per-tier coverage gates (TESTING.md), enforced by scripts/coverage_tiers.sh.
# `minimum` is enforced and only ever rises; `target` is the doctrine's aim.
[package.metadata.coverage_tiers.pure_logic]
title = "Pure logic & utilities"
target = 100.0
minimum = 100.0
include = ["src/model.rs"]

[package.metadata.coverage_tiers.api_surface]
title = "API / contract surface"
target = 100.0
minimum = 100.0
include = ["src/cli.rs"]

[package.metadata.coverage_tiers.ui]
title = "UI components (main only)"
target = 90.0
minimum = 90.0
include = ["src/app.rs"]
```

`files/src/lib.rs`:

```rust
//! An Omarchy desktop app built with GPUI and gpui-omarchy.

pub mod app;
pub mod cli;
pub mod model;

/// The project version, from the root `VERSION` file. gstack `/ship` bumps that
/// file; `Cargo.toml` keeps `0.0.0` so `Cargo.lock` never churns.
pub const VERSION: &str = include_str!("../VERSION").trim_ascii_end();

/// The Wayland app id, which Hyprland reports as the window class: window rules
/// match it, and so do the desktop entry's `StartupWMClass`, the installed
/// binary and the icon (`packaging/app.desktop.in`, `scripts/install.sh`).
pub const APP_ID: &str = "{{PACKAGE_NAME}}";
```

`files/src/cli.rs`:

```rust
//! The command line: the machine contract (DOCTRINE.md §3). Parsing is pure,
//! and `tests/cli.rs` checks every answer through the real binary. With no
//! arguments the binary opens the window instead.

/// What the command line asked for.
#[derive(Debug, PartialEq, Eq)]
pub enum Command {
    /// Open the main window.
    Open,
    /// Print this on stdout and exit 0.
    Print(String),
}

/// The `--help` text.
pub const USAGE: &str = "usage: {{PACKAGE_NAME}} [--help | --version]\n\
    With no arguments, opens the {{PROJECT_NAME}} window.\n";

/// Parses `args` (program name excluded).
///
/// # Errors
///
/// Returns the message to print on stderr when the arguments are invalid.
pub fn parse(args: &[String]) -> Result<Command, String> {
    if args.len() > 1 {
        return Err("error: expected at most one argument\n".to_owned());
    }
    match args.first().map(String::as_str) {
        None => Ok(Command::Open),
        Some("--version") => Ok(Command::Print(format!(
            "{} {}\n",
            crate::APP_ID,
            crate::VERSION
        ))),
        Some("--help") => Ok(Command::Print(USAGE.to_owned())),
        Some(other) => Err(format!("error: unexpected argument '{other}'\n")),
    }
}
```

`files/src/model.rs`:

```rust
//! The window's state without GPUI: what each action does to it. Pure, so it
//! is held to the pure-logic tier (100% lines and regions).

/// How many times the main action ran.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Counter {
    count: u32,
}

impl Counter {
    /// A counter that starts at `count`.
    #[must_use]
    pub const fn starting_at(count: u32) -> Self {
        Self { count }
    }

    /// The current count.
    #[must_use]
    pub const fn count(self) -> u32 {
        self.count
    }

    /// One more, stopping at `u32::MAX` instead of wrapping to zero.
    pub const fn increment(&mut self) {
        self.count = self.count.saturating_add(1);
    }

    /// Back to zero.
    pub const fn reset(&mut self) {
        self.count = 0;
    }

    /// What the window shows.
    #[must_use]
    pub fn label(self) -> String {
        match self.count {
            0 => "Not pressed yet".to_owned(),
            1 => "Pressed once".to_owned(),
            n => format!("Pressed {n} times"),
        }
    }
}
```

`files/src/app.rs`:

```rust
//! The main window: a panel that counts presses, in the active Omarchy theme.
//!
//! Colours, type and spacing come from gpui-omarchy (`cx.omarchy()` and its
//! components), which follows `omarchy theme set` live. Never hardcode them.

use gpui_kit::{
    App, AppContext as _, Context, FocusHandle, Focusable, InteractiveElement as _, IntoElement,
    KeyBinding, ParentElement as _, Render, Styled as _, TitlebarOptions, Window, WindowHandle,
    WindowOptions, actions, div, rems,
};
use gpui_omarchy::{ActiveTheme as _, ButtonVariant, button, focus_scope, keycap, panel};

use crate::model::Counter;

/// The key context the window's bindings are scoped to.
const KEY_CONTEXT: &str = "MainWindow";

actions!(
    {{PACKAGE_NAME}},
    [
        /// Count one more press.
        Increment,
        /// Start counting from zero again.
        Reset,
        /// Quit the application.
        Quit,
    ]
);

/// Registers the Omarchy theme, the key bindings and quit-on-close. Call it
/// once at startup, before opening a window.
pub fn init(cx: &mut App) {
    gpui_omarchy::init(cx);
    cx.bind_keys([
        KeyBinding::new("space", Increment, Some(KEY_CONTEXT)),
        KeyBinding::new("r", Reset, Some(KEY_CONTEXT)),
        KeyBinding::new("q", Quit, Some(KEY_CONTEXT)),
        KeyBinding::new("ctrl-q", Quit, None),
    ]);
    cx.on_action(|_: &Quit, cx| cx.quit());
    // One window is the whole app: closing it (super+w on Omarchy) quits.
    cx.on_window_closed(|cx, _| {
        if cx.windows().is_empty() {
            cx.quit();
        }
    })
    .detach();
}

/// Starts the app inside a running GPUI application: the theme, the key
/// bindings and the main window, focused. `main` hands this to
/// `gpui_kit::application().run`; tests call it on a test application.
pub fn start(cx: &mut App) {
    init(cx);
    open_window(cx);
    cx.activate(true);
}

/// The main window's options. `app_id` is the class Hyprland window rules match.
#[must_use]
pub fn window_options() -> WindowOptions {
    WindowOptions {
        titlebar: Some(TitlebarOptions {
            title: Some("{{PROJECT_NAME}}".into()),
            ..TitlebarOptions::default()
        }),
        app_id: Some(crate::APP_ID.to_owned()),
        ..WindowOptions::default()
    }
}

/// Opens the main window with the keyboard on its root.
///
/// # Panics
///
/// When the platform cannot open a window.
pub fn open_window(cx: &mut App) -> WindowHandle<MainWindow> {
    let window = cx
        .open_window(window_options(), |_, cx| cx.new(MainWindow::new))
        .expect("open the main window");
    window
        .update(cx, |view, window, cx| window.focus(&view.focus, cx))
        .expect("focus the main window");
    window
}

/// The main window's root view.
pub struct MainWindow {
    counter: Counter,
    focus: FocusHandle,
}

impl MainWindow {
    /// A fresh window state.
    pub fn new(cx: &mut Context<Self>) -> Self {
        Self {
            counter: Counter::default(),
            focus: cx.focus_handle(),
        }
    }

    /// What the window is counting.
    #[must_use]
    pub const fn counter(&self) -> Counter {
        self.counter
    }

    fn increment(&mut self, cx: &mut Context<Self>) {
        self.counter.increment();
        cx.notify();
    }

    fn reset(&mut self, cx: &mut Context<Self>) {
        self.counter.reset();
        cx.notify();
    }
}

impl Focusable for MainWindow {
    fn focus_handle(&self, _: &App) -> FocusHandle {
        self.focus.clone()
    }
}

impl Render for MainWindow {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let background = cx.omarchy().background;
        div()
            .id("main-window")
            .track_focus(&self.focus)
            .key_context(KEY_CONTEXT)
            .on_action(cx.listener(|this, _: &Increment, _, cx| this.increment(cx)))
            .on_action(cx.listener(|this, _: &Reset, _, cx| this.reset(cx)))
            .size_full()
            .flex()
            .items_center()
            .justify_center()
            .bg(background)
            .child(
                focus_scope("controls").child(
                    panel("{{PROJECT_NAME}}", cx)
                        .child(self.counter.label())
                        .child(
                            div().debug_selector(|| "press".into()).child(
                                button("press", "Press", ButtonVariant::Primary, cx)
                                    .on_click(cx.listener(|this, _, _, cx| this.increment(cx))),
                            ),
                        )
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap(rems(0.5))
                                .child(keycap("space", cx))
                                .child("press")
                                .child(keycap("r", cx))
                                .child("reset")
                                .child(keycap("q", cx))
                                .child("quit"),
                        ),
                ),
            )
    }
}
```

`files/src/main.rs`:

```rust
//! Command-line entry point: prints what `cli::parse` returns, or opens the
//! window. Everything testable lives in the library; this only wires it up.

use std::process::ExitCode;

use ::{{PACKAGE_NAME}}::cli::{self, Command};
use gpui_kit::assets::Assets;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match cli::parse(&args) {
        Ok(Command::Print(out)) => {
            print!("{out}");
            ExitCode::SUCCESS
        }
        Ok(Command::Open) => {
            // The one line no test can run: it hands the process to the
            // platform's event loop until the window closes.
            gpui_kit::application()
                .with_assets(Assets)
                .run(::{{PACKAGE_NAME}}::app::start);
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprint!("{err}");
            ExitCode::from(2)
        }
    }
}
```

`files/tests/cli.rs`:

```rust
//! CLI contract tests (TESTING.md tier 2: exit code and output of every
//! command), through the real binary. No arguments opens the window, which
//! `tests/window.rs` covers instead.

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
fn help_flag_prints_usage_and_exits_zero() {
    let out = cli(&["--help"]);
    assert!(out.status.success());
    assert_eq!(out.stdout, ::{{PACKAGE_NAME}}::cli::USAGE.as_bytes());
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
    for args in [["--version", "x"], ["--help", "x"], ["--nope", "y"]] {
        let out = cli(&args);
        assert_eq!(out.status.code(), Some(2));
        assert!(out.stdout.is_empty());
        assert_eq!(out.stderr, b"error: expected at most one argument\n");
    }
}

#[test]
fn no_arguments_means_open_the_window() {
    // Asserted on the parser: the binary would open a real window here.
    assert_eq!(::{{PACKAGE_NAME}}::cli::parse(&[]), Ok(::{{PACKAGE_NAME}}::cli::Command::Open));
}
```

`files/tests/model.rs`:

```rust
//! Pure-logic tests (TESTING.md tier 1): every rule of the window's state.

use ::{{PACKAGE_NAME}}::model::Counter;

#[test]
fn a_new_counter_starts_at_zero() {
    assert_eq!(Counter::default().count(), 0);
    assert_eq!(Counter::default().label(), "Not pressed yet");
}

#[test]
fn increment_counts_and_the_label_follows() {
    let mut counter = Counter::default();
    counter.increment();
    assert_eq!(counter.label(), "Pressed once");
    counter.increment();
    assert_eq!(counter.count(), 2);
    assert_eq!(counter.label(), "Pressed 2 times");
}

#[test]
fn increment_saturates_instead_of_wrapping() {
    let mut counter = Counter::starting_at(u32::MAX);
    counter.increment();
    assert_eq!(counter.count(), u32::MAX);
}

#[test]
fn reset_goes_back_to_zero() {
    let mut counter = Counter::starting_at(7);
    counter.reset();
    assert_eq!(counter, Counter::default());
}
```

`files/tests/window.rs`:

```rust
//! The main window through GPUI's test harness (TESTING.md tier 3): real
//! frames and real key presses, with no display or GPU.

use ::{{PACKAGE_NAME}}::app::{self, MainWindow};
use gpui_kit::{Entity, Modifiers, TestAppContext, VisualTestContext};
use gpui_omarchy::Theme;

fn open(cx: &mut TestAppContext) -> (Entity<MainWindow>, &mut VisualTestContext) {
    cx.update(app::init);
    let (view, cx) = cx.add_window_view(|_, cx| MainWindow::new(cx));
    let focus = view.read_with(cx, gpui_kit::Focusable::focus_handle);
    cx.update(|window, cx| window.focus(&focus, cx));
    draw(cx);
    (view, cx)
}

fn draw(cx: &mut VisualTestContext) {
    cx.update(|window, cx| window.draw(cx).clear(cx));
}

fn count(view: &Entity<MainWindow>, cx: &mut VisualTestContext) -> u32 {
    view.read_with(cx, |view, _| view.counter().count())
}

#[gpui_kit::test]
fn space_counts_and_r_resets(cx: &mut TestAppContext) {
    let (view, cx) = open(cx);
    cx.simulate_keystrokes("space space");
    assert_eq!(count(&view, cx), 2);
    draw(cx);
    cx.simulate_keystrokes("r");
    assert_eq!(count(&view, cx), 0);
}

#[gpui_kit::test]
fn clicking_the_button_counts(cx: &mut TestAppContext) {
    let (view, cx) = open(cx);
    let bounds = cx.debug_bounds("press").expect("the press button is drawn");
    cx.simulate_click(bounds.center(), Modifiers::default());
    assert_eq!(count(&view, cx), 1);
}

#[gpui_kit::test]
fn the_window_draws_in_dark_and_light_themes(cx: &mut TestAppContext) {
    let (_, cx) = open(cx);
    for theme in [Theme::tokyo_night(), Theme::flexoki_light()] {
        cx.update(|_, cx| theme.apply(cx));
        draw(cx);
        assert!(cx.debug_bounds("press").is_some());
    }
}

#[gpui_kit::test]
fn starting_opens_one_focused_window_under_the_app_id(cx: &mut TestAppContext) {
    cx.update(app::start);
    let windows = cx.windows();
    assert_eq!(windows.len(), 1);
    let window = windows[0]
        .downcast::<MainWindow>()
        .expect("the main window");
    let focused = window
        .update(cx, |view, window, cx| {
            gpui_kit::Focusable::focus_handle(view, cx).is_focused(window)
        })
        .expect("the window is open");
    assert!(focused);
    // Hyprland window rules and the desktop entry match this class.
    assert_eq!(
        app::window_options().app_id.as_deref(),
        Some(::{{PACKAGE_NAME}}::APP_ID)
    );
}
```

`files/tests/desktop_entry.rs`:

```rust
//! Named invariant: the desktop entry, the installed binary and icon, and the
//! window class Hyprland sees all use one name, `APP_ID`. If they drift, the
//! launcher loses the window and window rules stop matching.

fn entry() -> String {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/packaging/app.desktop.in");
    std::fs::read_to_string(path).expect("packaging/app.desktop.in exists")
}

#[test]
fn the_desktop_entry_names_the_app_id_everywhere() {
    let entry = entry();
    let id = ::{{PACKAGE_NAME}}::APP_ID;
    for line in [
        format!("Exec=\"@BINDIR@/{id}\""),
        format!("Icon={id}"),
        format!("StartupWMClass={id}"),
    ] {
        assert!(entry.lines().any(|l| l == line), "missing line: {line}");
    }
}
```

`files/packaging/app.desktop.in`:

```ini
[Desktop Entry]
Type=Application
Version=1.5
Name={{PROJECT_NAME}}
Comment={{PROJECT_NAME}}, an Omarchy app
Exec="@BINDIR@/{{PACKAGE_NAME}}"
Icon={{PACKAGE_NAME}}
Terminal=false
Categories=Utility;
StartupNotify=true
StartupWMClass={{PACKAGE_NAME}}
X-AppVersion=@VERSION@
```

`files/assets/icon.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <rect x="6" y="6" width="52" height="52" fill="#1a1b26"/>
  <rect x="6" y="6" width="52" height="52" fill="none" stroke="#7aa2f7" stroke-width="4"/>
  <rect x="18" y="18" width="12" height="28" fill="#7aa2f7"/>
  <rect x="34" y="30" width="12" height="16" fill="#9ece6a"/>
</svg>
```

`files/scripts/install.sh`:

```bash
#!/usr/bin/env bash
# Install {{PROJECT_NAME}} for this user: the release binary, a desktop entry and
# an icon, so it shows up in the Omarchy launcher. No root needed.
#
#   ./scripts/install.sh                        # build, then install under ~/.local
#   ./scripts/install.sh --no-build             # install the binary cargo already built
#   ./scripts/install.sh --uninstall            # remove exactly what install put there
#   ./scripts/install.sh --print-desktop-entry  # print the entry install would write
#   sudo PREFIX=/usr/local ./scripts/install.sh --no-build  # system-wide, after a build
set -euo pipefail

APP_ID="{{PACKAGE_NAME}}"
PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="${BINDIR:-$PREFIX/bin}"
APPDIR="${APPDIR:-$PREFIX/share/applications}"
ICONDIR="${ICONDIR:-$PREFIX/share/icons/hicolor/scalable/apps}"
BINARY="${CARGO_TARGET_DIR:-target}/release/$APP_ID"

mode=install
build=1
for arg in "$@"; do
  case "$arg" in
    --no-build) build=0 ;;
    --uninstall) mode=uninstall ;;
    --print-desktop-entry) mode=print ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown argument: $arg" >&2; exit 2 ;;
  esac
done
cd "$(dirname "$0")/.."  # after --help, which reads this script by its path

# Exec quotes the binary's path; these characters would need escaping there
# (desktop entry spec), so refuse them rather than write a broken entry.
case "$BINDIR" in
  *[\"\`\$\\%]*|*$'\n'*) echo "install.sh: unsupported character in BINDIR: $BINDIR" >&2; exit 2 ;;
esac

desktop_entry() {
  BINDIR="$BINDIR" VERSION="$(head -n 1 VERSION)" perl -pe \
    's/\@BINDIR\@/$ENV{BINDIR}/g; s/\@VERSION\@/$ENV{VERSION}/g' packaging/app.desktop.in
}

refresh_launcher() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPDIR" 2>/dev/null || true
  fi
}

case "$mode" in
  print)
    desktop_entry ;;
  uninstall)
    rm -f "$BINDIR/$APP_ID" "$APPDIR/$APP_ID.desktop" "$ICONDIR/$APP_ID.svg"
    refresh_launcher
    echo "Removed $APP_ID from $PREFIX." ;;
  install)
    if [ "$build" = 1 ]; then cargo build --locked --release; fi
    [ -x "$BINARY" ] || { echo "install.sh: $BINARY is missing; build it first" >&2; exit 1; }
    install -d "$BINDIR" "$APPDIR" "$ICONDIR"
    install -m 755 "$BINARY" "$BINDIR/$APP_ID"
    install -m 644 assets/icon.svg "$ICONDIR/$APP_ID.svg"
    desktop_entry > "$APPDIR/$APP_ID.desktop.tmp"
    chmod 644 "$APPDIR/$APP_ID.desktop.tmp"
    mv "$APPDIR/$APP_ID.desktop.tmp" "$APPDIR/$APP_ID.desktop"
    refresh_launcher
    echo "Installed $APP_ID $(head -n 1 VERSION):"
    echo "  $BINDIR/$APP_ID"
    echo "  $APPDIR/$APP_ID.desktop"
    echo "  $ICONDIR/$APP_ID.svg"
    case ":$PATH:" in *":$BINDIR:"*) ;; *) echo "Note: $BINDIR is not on PATH in this shell." ;; esac
    echo "Keybinding and window rule: docs/guides/omarchy.md" ;;
esac
```

`files/scripts/check.d/omarchy.sh`:

```bash
#!/usr/bin/env bash
# Omarchy guards (from ./bootstrap --stack omarchy-app): colours come from the
# Omarchy theme, never literals or gradients in src/, and the desktop entry is valid.
set -euo pipefail

# gpui-omarchy's Theme (cx.omarchy()) follows `omarchy theme set` live; a colour
# built from fixed values would stay put when the theme changes. The check reads
# text, not types (an Hsla struct literal gets past it), so DESIGN.md's rule
# still holds.
if grep -rnE '\b(rgb|rgba|hsla|black|white|red|green|blue|yellow|opaque_grey|transparent_black|transparent_white)\(|\bRgba::try_from\(' src; then
  echo "  colour literals in src/ (above): use the theme's roles, cx.omarchy() (DESIGN.md)" >&2
  exit 1
fi
# Omarchy surfaces are flat: no gradients, whatever their colours (DESIGN.md).
if grep -rnE '\blinear_gradient\(' src; then
  echo "  gradients in src/ (above): Omarchy surfaces are flat (DESIGN.md)" >&2
  exit 1
fi

# The entry install.sh writes, checked by desktop-file-utils. check.sh sets
# CHECK_CI=1 where a missing tool must fail (CI) and 0 where it may be skipped.
validator="${DESKTOP_FILE_VALIDATE_BIN:-desktop-file-validate}"
if command -v "$validator" >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  PREFIX=/usr/local ./scripts/install.sh --print-desktop-entry > "$tmp/{{PACKAGE_NAME}}.desktop"
  "$validator" "$tmp/{{PACKAGE_NAME}}.desktop"
elif [ "${CHECK_CI:-0}" = 1 ]; then
  echo "  desktop-file-validate is required in CI (apt: desktop-file-utils)" >&2
  exit 1
else
  echo "  desktop-file-validate not installed - skipping the desktop entry check"
fi
```

`files/.github/workflows/ci.yml`:

```yaml
# CI for {{PROJECT_NAME}} (vibe-starter omarchy-app stack pack): guards, then tests
# with the coverage gates from TESTING.md, then doctests. GPUI links against
# fontconfig and xkbcommon; its tests need no display or GPU.
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
    # Pinned, not ubuntu-latest: the apt package names below are Ubuntu 24.04's.
    runs-on: ubuntu-24.04
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v7

      - name: Install gitleaks
        uses: ./.github/actions/install-gitleaks

      - name: System libraries GPUI links against, and desktop-file-validate
        run: |
          sudo apt-get update
          sudo apt-get install -y --no-install-recommends \
            pkg-config libfontconfig-dev libxkbcommon-x11-dev desktop-file-utils

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

`files/DESIGN.md`:

```markdown
# Design System — {{PROJECT_NAME}}

{{PROJECT_NAME}} is an Omarchy app, so its design system is Omarchy's. It draws with
[gpui-omarchy](https://github.com/huacnlee/gpui-omarchy), which reads the active Omarchy theme
(`~/.local/state/omarchy/current/theme/colors.toml`) and follows `omarchy theme set` live; away
from Omarchy (macOS, CI) it falls back to Tokyo Night. The rules below keep the app inside that
system, and QA holds the app to them.

## Aesthetic
Part of the desktop: flat, square, dense and keyboard-first. In every Omarchy theme, light or
dark, it should look like it shipped with Omarchy.

## Color
Never write a colour. Use the active theme's roles through `cx.omarchy()`: `background`,
`surface`, `inset`, `foreground`, `secondary`, `bright`, `accent`, `on_accent`, `selection`,
`border`, `danger`, `warning` and `success`. Derive a tint from a role (`.opacity(...)`) rather
than inventing a hue. `scripts/check.d/omarchy.sh` refuses GPUI's fixed-colour constructors in
`src/` (`rgb(`, `rgba(`, `hsla(`, `white()` and the other named colours, `opaque_grey()`,
`transparent_*()`, `Rgba::try_from`) and any `linear_gradient(`. It reads text, not types, so a
struct literal such as `Hsla { h, s, l, a }` gets past it; the rule above still holds.

## Typography
The theme's `font` (the system UI face) for text and its `mono_font` (fontconfig's monospace,
which `omarchy font set` changes) for keys and code. Sizes in `rems`, never pixels, so interface
zoom keeps its proportions.

## Spacing & layout
`rems` for padding, gaps and sizes; pixels only for the window's own geometry and one-pixel
borders. Square corners, gpui-omarchy's default. Compose gpui-omarchy's components (`panel`,
`button`, `keycap`, `focus_scope`, ...) before styling raw `div`s.

## Motion
None by default. Anything that animates must not delay input and must also work from the
keyboard alone.

## Anti-slop rules
- No colour literals, gradients, shadows, glass or rounded pills: Omarchy surfaces are flat.
- Every action has a key, and the window shows it (`keycap`).
- `ButtonVariant::Primary` only for what Enter does; ask for confirmation only before what can't
  be undone.
- Both appearances stay tested: `tests/window.rs` draws Tokyo Night (dark) and Flexoki Light.
```

`files/docs/guides/omarchy.md`:

````markdown
# Omarchy integration

How {{PROJECT_NAME}} fits into an Omarchy 4 desktop: Hyprland configured in Lua, the Quickshell
desktop shell, and the active theme in `~/.local/state/omarchy/current`.

## Run and test

- `cargo run --locked` opens the window. On Omarchy, Rust comes from rustup; GPUI links against
  fontconfig and libxkbcommon, which Omarchy already has. On macOS it builds and runs too, in
  Tokyo Night.
- `cargo test --locked` needs no display: GPUI's test platform draws frames headlessly.

## Install it for yourself

`./scripts/install.sh` builds a release binary and installs, under `~/.local` (no root):

- `~/.local/bin/{{PACKAGE_NAME}}`
- `~/.local/share/applications/{{PACKAGE_NAME}}.desktop`, which the Omarchy launcher
  (`Super + Space`) lists
- `~/.local/share/icons/hicolor/scalable/apps/{{PACKAGE_NAME}}.svg`

`./scripts/install.sh --uninstall` removes exactly those three files. To install system-wide,
build as yourself, then run `sudo PREFIX=/usr/local ./scripts/install.sh --no-build`.

## Keybinding and window rule

Omarchy's Hyprland config is Lua with no drop-in directory, so nothing here edits it for you.
Add what you want by hand, after checking the key is free (`omarchy menu keybindings --print`):

```lua
-- ~/.config/hypr/bindings.lua
o.bind("SUPER + ALT + D", "{{PROJECT_NAME}}", { launch = "{{PACKAGE_NAME}}" })

-- ~/.config/hypr/hyprland.lua, below the require(...) lines: float it, centred
o.window("{{PACKAGE_NAME}}", { tag = "+floating-window" })
```

The window class is `{{PACKAGE_NAME}}`: `src/lib.rs` sets it as the Wayland app id, and the
desktop entry's `StartupWMClass` matches it (`tests/desktop_entry.rs` keeps them in step).
Renaming the app changes the class, so update these lines too.

## Theme and fonts

Nothing to do. gpui-omarchy re-reads the theme whenever `omarchy theme set` swaps it, and keys
use the monospace font `omarchy font set` chose. Try a light theme (`catppuccin-latte`) now and
then; `tests/window.rs` draws both appearances.

## Sharing it

Omarchy users install apps as packages. disktree shows the path:

1. Release a tarball per architecture, `{{PACKAGE_NAME}}-<version>-<arch>-linux.tar.gz`, holding
   the stripped binary, `packaging/app.desktop.in` as `{{PACKAGE_NAME}}.desktop.in`, the icon as
   `{{PACKAGE_NAME}}.svg`, `LICENSE` and `README.md`. Build Linux releases on the oldest Ubuntu
   runner you support: its glibc is the floor.
2. An AUR `{{PACKAGE_NAME}}-bin` PKGBUILD installs from those tarballs, renders the entry with
   `sed -e 's|@BINDIR@|/usr/bin|' -e "s|@VERSION@|$pkgver|"`, and depends on `libxcb`,
   `libxkbcommon`, `libxkbcommon-x11`, `wayland`, `libglvnd` and `vulkan-icd-loader`. Add
   `options=('!lto')`: makepkg's LTO flags break Rust's linker.
3. Omarchy's own package repository (`omacom/omarchy-pkgs`) takes pull requests with such a
   PKGBUILD plus a `.omarchy/package.json` that follows your GitHub releases.
````

3. Make the pack's own scripts executable (the copied ones kept their mode):

   ```sh
   chmod +x template/stacks/omarchy-app/validate-name template/stacks/omarchy-app/after-bootstrap \
     template/stacks/omarchy-app/files/scripts/install.sh template/stacks/omarchy-app/files/scripts/check.d/omarchy.sh
   ```

**Verify**: the shell-lint command → exit 0. `./scripts/template-selftest.sh omarchy_app` → 5
passed, 1 skipped (the heavy test). `./scripts/template-selftest.sh help_lists` → 1 passed.
`./scripts/template-selftest.sh carry_only` → 1 passed (no stray `{{`/`}}` in the pack).
`./bootstrap --help` now lists `omarchy-app` first.

### Step 6: Run the heavy tests in their own CI job

Edit `.github/workflows/template-selftest.yml` (post-007). Keep everything plan 007 left there.

1. In the `selftest` job, give the `Template self-test` step an `env` entry, next to
   `SELFTEST_RUST_TOOLCHAIN`:

   ```yaml
             SELFTEST_EXCLUDE: test_heavy_
   ```

2. Append this job (same indentation as `selftest:`):

   ```yaml
     heavy:
       # Builds real projects from the stack packs, too big for the 1-vCPU job:
       # the omarchy-app pack compiles GPUI (about 530 crates). Only tests named
       # test_heavy_* run here; the selftest job excludes them.
       if: github.repository == 'willtraweek/vibe-starter'
       runs-on: ubuntu-24.04
       timeout-minutes: 45
       env:
         SELFTEST_RUST_TOOLCHAIN: "1.98.1"
         SELFTEST_CARGO_TARGET_DIR: /home/runner/selftest-target
       steps:
         - uses: actions/checkout@v7

         - name: Install gitleaks
           uses: ./.github/actions/install-gitleaks

         - name: System libraries GPUI links against, and desktop-file-validate
           run: |
             sudo apt-get update
             sudo apt-get install -y --no-install-recommends \
               pkg-config libfontconfig-dev libxkbcommon-x11-dev desktop-file-utils

         - name: Install the pinned toolchain (the runner image ships rustup)
           run: rustup toolchain install 1.98.1 --profile minimal --component clippy,rustfmt,llvm-tools-preview

         - name: Install cargo-llvm-cov
           uses: taiki-e/install-action@7623a79cdfecb99d681017af368ca353d9f49bb5 # v2.87.19
           with:
             tool: cargo-llvm-cov@0.9.1
             fallback: none

         - name: Cache crates and build output
           uses: actions/cache@v6
           with:
             path: |
               ~/.cargo/registry/index
               ~/.cargo/registry/cache
               ~/.cargo/git/db
               /home/runner/selftest-target
             key: heavy-${{ runner.os }}-${{ hashFiles('template/stacks/*/files/Cargo.toml', 'template/stacks/*/files/rust-toolchain.toml') }}
             restore-keys: heavy-${{ runner.os }}-

         - name: Heavy stack-pack self-tests
           run: ./scripts/template-selftest.sh test_heavy_
   ```

   GitHub sets `CI=true`, so the heavy test runs without `SELFTEST_HEAVY`, and a missing tool
   is a skip, which fails the run. The `${{ }}` expressions are fine here: this workflow is the
   template's, not a pack file.

**Verify**: the YAML command → exit 0. `grep -c 'SELFTEST_EXCLUDE: test_heavy_'
.github/workflows/template-selftest.yml` → `1`. `grep -c '^  heavy:$' .github/workflows/template-selftest.yml` → `1`.

### Step 7: Document the Omarchy packs in `TEMPLATE.md`

1. In `## Stack packs`, extend the "Available:" paragraph so it also names
   `omarchy-app` (for example: "…and `omarchy-app` (an Omarchy app in its own window: Rust +
   GPUI + gpui-omarchy, with the rust pack's gates)."). Keep the existing wording for `python`
   and `rust`.
2. Directly after that paragraph, add:

   ```markdown
   ### Omarchy apps: choose by what the app should do

   [Omarchy](https://omarchy.org) is an opinionated Arch Linux + Hyprland desktop. Its packs
   build things that follow the active Omarchy theme and appear in its launcher; the new
   project's `docs/guides/omarchy.md` covers keybindings, window rules and sharing the app.

   | The app should… | Pack | Stack |
   |---|---|---|
   | open its own window, with rich visuals, mouse and keyboard | `omarchy-app` | Rust + GPUI (gpui-kit 0.6.6) + gpui-omarchy 0.1.3 |

   gpui-kit and gpui-omarchy are pinned exactly and bumped together: gpui-omarchy pins the
   gpui-kit it was built against, and gpui-kit is pre-1.0.
   ```

3. In `### Verifying a change`, add after the paragraph about skipped tests:

   ```markdown
   Tests named `test_heavy_*` build real projects (the omarchy-app pack compiles GPUI) and skip
   locally unless `SELFTEST_HEAVY=1`. CI runs them in their own `heavy` job; the `selftest`
   job sets `SELFTEST_EXCLUDE=test_heavy_`, which drops matching tests without counting them
   as skips. Build one locally with
   `SELFTEST_HEAVY=1 SELFTEST_RUST_TOOLCHAIN=1.98.1 ./scripts/template-selftest.sh test_heavy_`.
   ```

**Verify**: `grep -c '^### Omarchy apps: choose by what the app should do$' TEMPLATE.md` → `1`.

### Step 8: Full verification and a manual look

```sh
SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh         # baseline + 8 passed, 0 failed
./scripts/check.sh                                                  # exit 0
```

Record any local skips by name (a missing gitleaks, uv or cargo-llvm-cov); don't install tools to
clear them. Zero skips is required in the `selftest` CI job, where `CI=true` turns a skip into a
failure.

If Rust 1.98.1, cargo-llvm-cov and jq are installed (and, on Linux, the three apt packages),
also run the heavy test: `SELFTEST_HEAVY=1 SELFTEST_RUST_TOOLCHAIN=1.98.1
./scripts/template-selftest.sh test_heavy_` → 1 passed. Otherwise record it as not run
locally; the `heavy` CI job must pass before this plan counts as done.

Then look at a real project once, in a scratch directory, after committing the plan's work
(`git clone` reads commits). This needs Rust 1.98.1 already installed (`rustup run` never installs
one); without it, record "step 8 not run locally" and rely on the heavy CI job. Run it in a
subshell from the repo root:

```sh
(
  set -eu
  [ -z "$(git status --porcelain)" ] || { echo "Commit the implementation first." >&2; exit 1; }
  tc="${SELFTEST_RUST_TOOLCHAIN:-1.98.1}"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  git clone -q "$PWD" "$tmp/demo-app"
  cd "$tmp/demo-app"
  git remote remove origin
  rustup run "$tc" ./bootstrap --name "Demo App" --stack omarchy-app --yes
  test -f Cargo.lock
  git add -A && git commit -qm init
  rustup run "$tc" cargo run --locked -q -- --version   # -> demo_app 0.0.0
  rustup run "$tc" ./scripts/check.sh
  if rustup run "$tc" cargo llvm-cov --version >/dev/null 2>&1; then
    rustup run "$tc" ./scripts/coverage.sh
  else
    echo "cargo-llvm-cov not installed: coverage.sh not run here (the heavy CI job runs it)"
  fi
)
```

On an Omarchy machine, also run `./scripts/install.sh`, open "Demo App" from the launcher
(`Super + Space`), and switch themes with `omarchy theme set <name>`: the window should change
with it. Report whether you could do this; it is not required.

## Test plan

Eight new test functions, one heavy test, and one adapted predecessor test:

- `test_bootstrap_help_lists_stack_packs_with_what_they_are_for`: `--help` lists every pack with
  its description, every pack has one, and nothing changes.
- `test_bootstrap_stack_prompt_at_a_terminal` (006, adapted): the prompt prefix no longer pins
  the full pack list, and the typed run shows the omarchy-app description.
- `test_check_tells_guards_whether_ci_requires_tools`: `CHECK_CI` is 1 for `CI=true`, `CI=1` and
  `GITHUB_ACTIONS=true`, and 0 for `CI=false`, `CI=no` and an empty `CI`.
- `test_selftest_exclude_skips_matching_tests_without_counting_them`: a nested run shows the
  excluded test neither ran nor counted.
- `test_stack_omarchy_app_bootstrap_installs_the_pack`: the files, filled commands, CI and the
  `.gitignore`; after-bootstrap formats before it locks; no placeholders or template paths are
  left; git commits every pack file and ignores the build output.
- `test_stack_omarchy_app_rejects_unusable_names_before_writes`: dependency names, `omarchy`
  and, through the rust pack's rules, Rust reserved names all exit 2 with no file changed.
- `test_stack_omarchy_app_install_script_installs_and_uninstalls`: three files in and out;
  `--print-desktop-entry` matches the installed entry; `CARGO_TARGET_DIR` is honoured; a
  missing binary exits 1; bad arguments or a `BINDIR` with `"` exit 2.
- `test_stack_omarchy_app_guard_refuses_colour_literals_and_needs_its_validator_in_ci`:
  every fixed-colour spelling and a gradient fail, with the location, and theme-derived colours
  pass; only Omarchy packs carry the guards; a missing validator is a local notice but a CI
  failure; the validator gets exactly install.sh's entry.
- `test_stack_omarchy_app_shares_the_rust_packs_gates`: the five shared files are byte-identical.
- `test_heavy_stack_omarchy_app_project_is_green` (heavy job): a real bootstrap (hook formats
  and locks), then the project's own `check.sh`, `coverage.sh` and ratchet, then a broken
  desktop entry fails the guard, and projects named `app`, `cli` and `model` pass clippy on
  every target.

The generated project's own tests: 5 CLI tests through the binary, 4 pure-logic tests, 4
window-harness tests and 1 desktop-entry invariant. All were rehearsed while planning:
the light tests on macOS bash 3.2, the heavy test on Linux, and the generated project on
Rust 1.98.1 in `ubuntu:24.04`.

## Done criteria

ALL must hold:

- [ ] `SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh` → baseline + 8 passed,
      0 failed; local skips are named; the `selftest` CI job has 0 skipped
- [ ] The heavy test passed, locally or in the `heavy` CI job (say which)
- [ ] Shell lint and YAML commands exit 0; `./scripts/check.sh` exits 0
- [ ] `./bootstrap --help` lists `omarchy-app`, `python` and `rust`, each with its description
- [ ] The step 8 clone printed `demo_app 0.0.0`, or you recorded why it couldn't run locally
- [ ] `git status --porcelain` shows only in-scope paths
- [ ] `plans/README.md` status row updated, with the new baseline

## STOP conditions

Stop and report back (do not improvise) if:

- A predecessor contract under "Current state" is missing or different: for example, no
  `template/stacks/rust/`, no `rust_env`/`rust_ready`, or a different help or prompt line.
- gpui-kit `=0.6.6` or gpui-omarchy `=0.1.3` can't be resolved, or the starter doesn't build on
  Rust 1.98.1. Report it; don't bump the pins or the toolchain as part of this plan.
- clippy reports a lint in the pack's Rust code, or coverage falls below a floor. Report the
  lint or the numbers; don't add `#[allow]`s, loosen `[lints]`, lower a floor, or exclude files
  from coverage.
- A window-harness test fails in CI. They pass headlessly in `ubuntu:24.04` containers; a
  failure means the runner differs, which the plan must account for.
- The `heavy` job takes more than 30 minutes cold, or `selftest` still runs a `test_heavy_*`
  test. Report the timings from the job log.
- You feel the need to edit Hyprland or Omarchy config files from a script, or to add
  `/usr/bin/omarchy-*` commands: both are fragile surfaces this plan avoids on purpose.

## Maintenance notes

- **Bumping GPUI.** gpui-kit and gpui-omarchy move as a pair: find the gpui-omarchy release
  that pins the gpui-kit you want (crates.io API), change both exact pins and the versions that
  `commands`' STACK line and `TEMPLATE.md`'s table name, and run the heavy test. Watch the `gpui-pre-macros` release-profile workaround (both upstream apps carry it)
  and the rust-version floor of the new dependency graph.
- **Toolchain bumps** are shared with the rust pack: the byte-identity test makes you change
  both `rust-toolchain.toml` files, and the pack's `rust-version` with them. The workflow's
  `rustup toolchain install` and `SELFTEST_RUST_TOOLCHAIN` (both jobs), the `-ge 98` check in
  `omarchy_app_heavy_ready` and the STACK lines name it too: `grep -rn '1\.98' .github scripts
  template TEMPLATE.md`.
- **Operator actions:** after the first green run, add the `heavy` check to master's ruleset
  next to `selftest`. Its cold run costs minutes on every pull request; cache hits bring it to
  about 2–4 minutes.
- **Rule of three.** Plan 009 adds a third Rust pack (`omarchy-tui`). With three copies of the
  shared gates, it should extract them instead of copying a third time; see plan 009.
- **Coverage shape.** Real GPUI apps land lower than the starter: disktree's app crate measures
  about 81% lines. Keep start-up in `app::start`, painting logic in tested functions, and pure
  logic in modules listed in `pure_logic`. Raise the `ui` tier only as tests earn it.
- **Renaming a project** changes `APP_ID`, the window class; users' `o.window(...)` rules must
  follow (the generated guide says so).
- **Deferred:** release automation (the guide documents disktree's tarball layout, which both
  the AUR and Omarchy's package repository consume), and a macOS bundle.
- Reviewer focus: the `list_stacks` change and the prompt test adaptation; `CHECK_CI` in
  `check.sh`; the runner's exclusion; `after-bootstrap`'s order; `install.sh`'s quoting and
  refusals; the `heavy` job's cache key.
