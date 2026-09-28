# Plan 009: Add the `omarchy-tui` stack pack (Rust + ratatui), and share the Rust gates through one partial pack

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Predecessor preflight (run first)**: plans 001–008 must be done, in order. Run
> `SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh` and record its summary line and
> named skips in `.context/plan-009-baseline.txt`; any failure is a STOP condition. Check the
> contracts under "Current state"; everything here about plans 007 and 008 comes from their plan
> files, because neither had run when this plan was written.

## Status

- **Priority**: P2 (requested by the maintainer)
- **Effort**: M
- **Risk**: MED. `bootstrap` learns partial packs, and three packs move their shared files into
  one; every existing Rust test must still pass. The new pack itself is small (182 crates).
- **Depends on**: 008 (pack descriptions, `SELFTEST_EXCLUDE`, `CHECK_CI`, the `heavy` CI job and
  the omarchy-app pack), 007 (the rust pack), 006 (the mechanism)
- **Category**: direction
- **Planned at**: commit `98063fc` with plans 007–008 applied in a rehearsal, 2026-09-25

## Why this matters

Plan 008 set out the Omarchy packs by what the app should do. This plan adds the second:

| The app should… | Pack | Stack |
|---|---|---|
| be a keyboard-driven tool in a terminal, light, fine over SSH | `omarchy-tui` | Rust + ratatui 0.30 |

Omarchy ships terminal apps as launcher entries that open a floating terminal:
`omarchy-tui-install` writes `Exec=xdg-terminal-exec --app-id=TUI.float -e <command>`, and
Omarchy's window rules float and centre the `TUI.float` class (`default/hypr/apps/system.lua`).
Its theme reaches terminal apps for free: `omarchy theme set` rewrites the terminal's 16 ANSI
colours and signals the terminal (kitty `SIGUSR1`, ghostty `SIGUSR2`, foot via OSC, alacritty by
touching its config), so an app that draws only in those colours follows every theme. Omarchy
preinstalls terminal apps this way (cliamp, a Go TUI).

It also settles a debt. The rust and omarchy-app packs carry byte-identical copies of five gate
files; a third Rust pack makes three copies, and `ENGINEERING.md`'s rule of three says extract
(plan 006 applied the same rule to the gitleaks action). So this plan adds **partial packs**:
directories named `template/stacks/_name/` whose `files/` other packs list in an `includes` file.
`bootstrap` copies them first, never offers them as a stack, and checks them before any write.

After this plan:

- `./bootstrap --stack omarchy-tui` creates a terminal app that:
  - draws with ratatui in the terminal's own 16 colours, so it follows `omarchy theme set`
    (a named test checks every cell of the screen, and a guard refuses `Color::Rgb(`,
    `Color::Indexed(` and colours made from numbers or strings in `src/`);
  - has pure logic, a CLI contract, and an event loop that tests drive with scripted keys
    into ratatui's `TestBackend`, at 90% line and region coverage with per-tier floors;
  - installs a launcher entry that opens it in a floating Omarchy terminal;
  - shares the rust pack's toolchain pin, lints and coverage gate, now kept once.
- `template/stacks/_rust-gates/` holds `rust-toolchain.toml`, `rustfmt.toml`,
  `scripts/coverage.sh`, `scripts/coverage_tiers.sh`, `scripts/check.d/rust.sh` and the Rust
  reserved-name rules; `rust`, `omarchy-app` and `omarchy-tui` include it.

## Design decisions (each verified while planning)

- **The event loop is testable.** `app::run(terminal, events)` is generic over the ratatui
  backend and takes any iterator of `io::Result<Event>`; `main.rs` passes the real terminal
  (`ratatui::run`) and `std::iter::repeat_with(crossterm::event::read)`. Tests pass a
  `TestBackend` and scripted keys, including a read error. ratatui 0.30's `TestBackend` has
  `Error = Infallible` and `io::Error` has no `From<Infallible>`, so drawing errors convert with
  `io::Error::other` under `B::Error: Send + Sync + 'static`.
- **Measured** (Rust 1.98.1, `ubuntu:24.04`, with the pre-landing review's resize fix): 94.17%
  lines and 92.35% regions overall; `model.rs`, `cli.rs` and `view.rs` at 100%, `app.rs` at 100%
  lines and 91.30% regions (the unreachable `Infallible` error arms), `main.rs` 58.8% (its
  real-terminal branch). clippy pedantic and rustfmt pass. The lockfile has 182 packages; a cold gate takes seconds.
- **The real binary was driven in a real pseudo-terminal**: 24×80, it drew the box and title,
  space counted twice, `r` reset, `q` exited 0, and the alternate screen was left. The heavy
  test repeats the essentials with Python's `pty` module: it waits for the first frame, sends two
  presses and `q`, and checks the exit status and that the alternate screen is left.
- **Theme colours are the terminal's.** crossterm writes `Color::Blue` as palette index 4
  (`38;5;4`), which is one of the 16 colours Omarchy's themes set; `Color::Rgb`,
  `Color::Indexed` and colours made from numbers or strings (`Color::from_u32`,
  `Color::from([r, g, b])`, a parsed `"#…"`) bypass the theme, so the guard refuses them and
  `tests/view.rs` checks every cell (a named invariant).
- **The title fits the name.** A fixed-width box cut long project names; the box is now as wide
  as the title (at least 36 columns), verified with a 46-character name.
- **Same launcher conventions as Omarchy.** `Exec=xdg-terminal-exec --app-id=TUI.float -e
  "@BINDIR@/<binary>"` (validated by `desktop-file-validate`), the same `scripts/install.sh` as
  omarchy-app (byte-identical, a test keeps it so; two copies, not yet three), and a guide
  that shows `o.bind("SUPER + ALT + T", …, "omarchy-launch-tui --app-id=TUI.float <binary>")`
  (the chord is free in Omarchy's defaults).
- **Partial packs, not pack inheritance.** A pack lists partial packs in `includes`; `bootstrap`
  validates the list before any write (only `_name` directories with `files/`), copies them in
  order, then the pack's own files, so a pack can override a shared file. Partial packs have no
  `commands`, `gitignore` or `description`, are hidden from `--help` and the prompt, and
  `--stack _rust-gates` is refused by the existing stack-name rule. The Rust reserved names
  move to `_rust-gates/validate-name`; each Rust pack's `validate-name` delegates to it.
- **Formatting follows the name, for every Rust pack.** Plan 007 was amended on 2026-09-25 so the
  rust pack's `after-bootstrap` runs `cargo fmt --all` before locking (a 52-character name
  failed `cargo fmt --check` otherwise). This pack's hook does the same. Code names its own
  crate `::{{PACKAGE_NAME}}::…`, so a project named like one of its modules or imports (`cli`,
  `event`, `io`, `view`) still compiles; the heavy test checks those names.
- **Heavy, not slim.** The TUI's end-to-end test builds a real project and runs it in a
  pseudo-terminal, so it's a `test_heavy_*` test in 008's `heavy` job (which already has the
  toolchain, cargo-llvm-cov, desktop-file-utils and python3).

## Current state

Verify before editing (plans 007 and 008 as their plan files specify):

- `template/stacks/rust/` has `files/` with the five gate files, its own `validate-name`
  (printing `reserved Rust package name: <name>`), `after-bootstrap`, `commands`, `gitignore`,
  and (from 008) `description`.
- `template/stacks/omarchy-app/` has byte-identical copies of the five gate files,
  `validate-name` delegating with `rust_rules=template/stacks/rust/validate-name`, and
  `files/scripts/install.sh`.
- `bootstrap` (after 008) discovers packs twice with
  `find template/stacks -mindepth 1 -maxdepth 1 -type d -exec basename {} \;` (in `list_stacks`
  and when setting `STACKS`), validates a chosen pack by `files/`, `commands` and `gitignore`,
  and copies files in the "Apply the stack pack" block with
  `(CDPATH='' cd "$pack/files" && find . -type f) | while IFS= read -r src; do`.
- `scripts/template-selftest.sh` (after 008) has `test_bootstrap_help_lists_stack_packs_with_what_they_are_for`,
  `test_stack_omarchy_app_shares_the_rust_packs_gates`, `omarchy_app_project`, `rust_env`,
  `rust_ready`, and the heavy test `test_heavy_stack_omarchy_app_project_is_green`.
- `template/stacks/rust/after-bootstrap` runs `cargo fmt --all` before `cargo generate-lockfile`
  (plan 007 as amended). If it doesn't, step 3 adds it.
- The `heavy` CI job exists and runs `./scripts/template-selftest.sh test_heavy_`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Self-test (all but heavy) | `SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh` | baseline + 7 passed, 0 failed |
| This plan's light tests | `./scripts/template-selftest.sh omarchy_tui` | 3 passed, 1 skipped (the heavy one) |
| Heavy tests, locally | `SELFTEST_HEAVY=1 SELFTEST_RUST_TOOLCHAIN=1.98.1 ./scripts/template-selftest.sh test_heavy_` | 2 passed (needs Rust 1.98.1, cargo-llvm-cov, jq, python3; GPUI's libraries on Linux). Verified on Linux; on macOS a build failure is "not run locally", not a STOP |
| Shell lint | `shellcheck bootstrap scripts/*.sh template/stacks/*/files/scripts/*.sh template/stacks/*/files/scripts/check.d/*.sh template/stacks/*/after-bootstrap template/stacks/*/validate-name` | exit 0 |
| Checks | `./scripts/check.sh` | exit 0 |

Missing local tools produce named skips. Don't install toolchains while executing this plan.

## Scope

**In scope**:

- `bootstrap` (step 2), `scripts/template-selftest.sh` (step 1)
- `template/stacks/_rust-gates/` (create, by moving files, step 3)
- `template/stacks/rust/` and `template/stacks/omarchy-app/`: only the moves, `includes`,
  `validate-name` and (if needed) the rust pack's `after-bootstrap`, as step 3 lists
- `template/stacks/omarchy-tui/` (create, step 4)
- `TEMPLATE.md` (steps 2 and 5), `plans/README.md` (your row)

**Out of scope**: the gate files' content (they move unchanged), the python pack, the root
skeleton docs, the CI workflow (the `heavy` job already runs every `test_heavy_*` test and has
python3), and Hyprland or Omarchy config files (print snippets; never edit them).

## Git workflow

Work on the branch you were given; commit per step (e.g. `Share the Rust gates through
_rust-gates`); don't push or open a PR unless told to. Use `git mv` for the moved files so
history follows them.

## Steps

### Step 1: Add the failing tests

1. Delete the whole function `test_stack_omarchy_app_shares_the_rust_packs_gates` (from its
   `() {` line through its closing `}`). `test_rust_packs_share_one_copy_of_their_gates`
   replaces it.
2. In `test_bootstrap_help_lists_stack_packs_with_what_they_are_for`, directly below its line
   `    pack="$(basename "$pack")"`, insert:

   ```bash
       case "$pack" in _*) continue ;; esac  # partial packs are included, never offered
   ```

3. In `test_stack_omarchy_app_bootstrap_installs_the_pack`, add `part` to its `local` line and
   replace the two lines that list the pack's files,

   ```bash
     { git -C "$REPO" ls-files --cached --others --exclude-standard -- template/stacks/omarchy-app/files \
         | sed 's|^template/stacks/omarchy-app/files/||'
   ```

   with this loop, so the gates step 3 moves into `_rust-gates` are still expected in the
   project:

   ```bash
     { for part in _rust-gates omarchy-app; do
         git -C "$REPO" ls-files --cached --others --exclude-standard -- "template/stacks/$part/files" \
           | sed "s|^template/stacks/$part/files/||"
       done
   ```

4. Insert this block immediately **above** `# --- runner ---`, after plan 008's block:

```bash
# --- tests: partial packs and the omarchy-tui stack pack (plan 009) ----------
test_stack_pack_includes_copy_partial_packs_first() {
  # A pack's `includes` names partial packs (template/stacks/_name/files/), copied
  # before the pack's own files, so a pack can override a shared file.
  local d="$WORK/stack-includes/demo" p
  fresh_copy "$d" || return 1
  p="$d/template/stacks"
  fixture_pack "$p/fixture" || return 1
  mkdir -p "$p/_fixture-shared/files/scripts" || return 1
  printf 'shared {{PACKAGE_NAME}}\n' > "$p/_fixture-shared/files/scripts/shared.txt"
  printf 'from the partial pack\n' > "$p/_fixture-shared/files/override.txt"
  printf 'from the pack\n' > "$p/fixture/files/override.txt"
  printf 'shared, not executable\n' > "$p/_fixture-shared/files/run.sh"
  printf '#!/bin/sh\necho pack\n' > "$p/fixture/files/run.sh" && chmod +x "$p/fixture/files/run.sh" || return 1
  printf '# shared files\n_fixture-shared\n' > "$p/fixture/includes"
  run_bootstrap "$d" --name demo --stack fixture --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  assert_contains "$d/scripts/shared.txt" "shared demo" || return 1
  assert_contains "$d/override.txt" "from the pack" || return 1
  [ -x "$d/run.sh" ] || fail "the pack's executable run.sh kept the partial pack's mode" || return 1
  assert_absent "$d/template"
}
test_stack_pack_includes_are_checked_before_writes() {
  # An include that isn't a partial pack (_name) or doesn't exist fails the
  # bootstrap with exit 2 before any file changes.
  local d inc before rc
  for inc in fixture-shared _missing '_bad/name' _; do
    d="$WORK/stack-includes-bad/$(printf '%s' "$inc" | tr '/' '-')/demo"
    fresh_copy "$d" || return 1
    fixture_pack "$d/template/stacks/fixture" || return 1
    mkdir -p "$d/template/stacks/fixture-shared/files" || return 1
    printf '%s\n' "$inc" > "$d/template/stacks/fixture/includes"
    before="$(tree_fingerprint "$d")"
    run_bootstrap "$d" --name demo --stack fixture --yes; rc=$?
    assert_exit 2 "$rc" || return 1
    [ "$before" = "$(tree_fingerprint "$d")" ] || fail "include '$inc' changed files before its rejection" || return 1
  done
}
test_partial_packs_are_not_offered_as_stacks() {
  # _rust-gates only exists to be included: --help doesn't list it and --stack
  # refuses it.
  local d="$WORK/partial-not-a-stack/proj" rc
  fresh_copy "$d" || return 1
  (cd "$d" && ./bootstrap --help >"$d.out" 2>&1) || fail "--help exited $?" || return 1
  assert_not_contains "$d.out" "_rust-gates" || return 1
  run_bootstrap "$d" --name proj --stack _rust-gates --yes; rc=$?
  assert_exit 2 "$rc"
}
test_rust_packs_share_one_copy_of_their_gates() {
  # Three Rust packs include _rust-gates (the rule of three): none carries its own
  # copy of a gate file, and each project still gets them.
  local pack f d="$WORK/rust-gates/demo"
  for pack in rust omarchy-app omarchy-tui; do
    grep -qxF _rust-gates "$REPO/template/stacks/$pack/includes" \
      || fail "$pack does not include _rust-gates" || return 1
    for f in rust-toolchain.toml rustfmt.toml scripts/coverage.sh scripts/coverage_tiers.sh scripts/check.d/rust.sh; do
      assert_exists "$REPO/template/stacks/_rust-gates/files/$f" || return 1
      assert_absent "$REPO/template/stacks/$pack/files/$f" || return 1
    done
  done
  omarchy_tui_project "$d" || return 1
  for f in rust-toolchain.toml rustfmt.toml scripts/coverage.sh scripts/coverage_tiers.sh scripts/check.d/rust.sh; do
    assert_exists "$d/$f" || return 1
  done
  [ -x "$d/scripts/coverage_tiers.sh" ] || fail "an included script lost its exec bit"
}
test_omarchy_packs_share_one_install_script() {
  # Two copies (rule of three: not yet shared); they must not drift apart.
  cmp -s "$REPO/template/stacks/omarchy-app/files/scripts/install.sh" \
    "$REPO/template/stacks/omarchy-tui/files/scripts/install.sh" \
    || fail "omarchy-app's and omarchy-tui's scripts/install.sh differ"
}
omarchy_tui_project() {  # $1 = dir: a fresh copy bootstrapped as "Demo App" with omarchy-tui
  # cargo is a stub that fails and logs its calls to "$1.cargo-calls".
  mkdir -p "$1.stub" || return 1
  cat > "$1.stub/cargo" <<STUB || return 1
#!/bin/sh
echo "cargo \$*" >> "$1.cargo-calls"
exit 101
STUB
  chmod +x "$1.stub/cargo" || return 1
  fresh_copy "$1" || return 1
  PATH="$1.stub:$(printenv PATH)" run_bootstrap "$1" --name "Demo App" --stack omarchy-tui --yes \
    || fail "bootstrap exited $?: $(tail -20 "$1.out")"
}
test_stack_omarchy_tui_bootstrap_installs_the_pack() {
  local d="$WORK/omarchy-tui/demo-app" f s
  omarchy_tui_project "$d" || return 1
  assert_contains "$d/Cargo.toml" 'name = "demo_app"' || return 1
  assert_contains "$d/Cargo.toml" 'ratatui = "0.30.2"' || return 1
  assert_contains "$d/packaging/app.desktop.in" 'Exec=xdg-terminal-exec --app-id=TUI.float -e "@BINDIR@/demo_app"' || return 1
  assert_contains "$d/DESIGN.md" "16 named ANSI colours" || return 1
  assert_exists "$d/docs/guides/omarchy.md" || return 1
  assert_absent "$d/.github/workflows/ci.yml.example" || return 1
  assert_contains "$d/TESTING.md" "Tests: \`cargo test --locked\`" || return 1
  assert_contains "$d/.bootstrapped" "with the omarchy-tui stack pack" || return 1
  [ "$(cat "$d.cargo-calls")" = "$(printf 'cargo fmt --all\ncargo generate-lockfile --quiet')" ] \
    || fail "after-bootstrap ran: $(cat "$d.cargo-calls")" || return 1
  for s in '{{PACKAGE_NAME}}' '{{TEST_CMD' TEMPLATE.md template/stacks template-selftest; do
    assert_tree_lacks "$d" "$s" || return 1
  done
  : > "$d/Cargo.lock"
  (cd "$d" && git add -A) || fail "git add failed" || return 1
  { for part in _rust-gates omarchy-tui; do
      git -C "$REPO" ls-files --cached --others --exclude-standard -- "template/stacks/$part/files" \
        | sed "s|^template/stacks/$part/files/||"
    done
    printf '%s\n' Cargo.lock .github/actions/install-gitleaks/action.yml
  } > "$d.expected" || return 1
  while IFS= read -r f; do
    git -C "$d" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || fail "git would not commit $f" || return 1
  done < "$d.expected"
  for f in target/debug/demo_app coverage.json default_1.profraw; do
    git -C "$d" check-ignore -q -- "$f" || fail "git would commit the build artifact $f" || return 1
  done
}
test_stack_omarchy_tui_rejects_unusable_names_before_writes() {
  local d name before rc
  for name in Ratatui crossterm omarchy async; do
    d="$WORK/omarchy-tui-names/$name/proj"
    fresh_copy "$d" || return 1
    before="$(tree_fingerprint "$d")"
    run_bootstrap "$d" --name "$name" --stack omarchy-tui --yes; rc=$?
    assert_exit 2 "$rc" || return 1
    case "$name" in
      async) assert_contains "$d.out" "reserved Rust package name" || return 1 ;;
      *) assert_contains "$d.out" "is taken by a crate this pack builds on" || return 1 ;;
    esac
    [ "$before" = "$(tree_fingerprint "$d")" ] || fail "'$name' changed files before its rejection" || return 1
  done
}
test_stack_omarchy_tui_guard_refuses_rgb_and_256_colour_literals() {
  local d="$WORK/omarchy-tui-guard/demo-app" rc lit
  omarchy_tui_project "$d" || return 1
  (cd "$d" && CHECK_CI=0 DESKTOP_FILE_VALIDATE_BIN=/nonexistent bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1 \
    || fail "the starter failed the guard: $(cat "$d.guard")" || return 1
  for lit in 'Color::Rgb(0x12, 0x34, 0x56)' 'Color::Indexed(208)' 'Rgb(0x12, 0x34, 0x56)' \
    'Color::from_u32(0x0012_3456)' 'Color::from([0x12, 0x34, 0x56])' '"#123456".parse::<Color>().unwrap()'; do
    printf 'use ratatui::style::Color;\npub const X: Color = %s;\n' "$lit" > "$d/src/tint.rs"
    (cd "$d" && CHECK_CI=0 DESKTOP_FILE_VALIDATE_BIN=/nonexistent bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1; rc=$?
    assert_exit 1 "$rc" || return 1
    assert_contains "$d.guard" "src/tint.rs:2:" || return 1
  done
  # The 16 named colours pass.
  printf 'use ratatui::style::{Color, Style};\npub const X: Style = Style::new().fg(Color::Blue).bg(Color::Reset);\n' > "$d/src/tint.rs"
  (cd "$d" && CHECK_CI=0 DESKTOP_FILE_VALIDATE_BIN=/nonexistent bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1 \
    || fail "named colours failed the guard: $(cat "$d.guard")" || return 1
  rm -f "$d/src/tint.rs"
  (cd "$d" && CHECK_CI=1 DESKTOP_FILE_VALIDATE_BIN=/nonexistent bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard" "required in CI"
}
omarchy_tui_heavy_ready() {  # why the heavy omarchy-tui build can't run here; empty = run it
  if [ "${CI:-}" != "true" ] && [ "${SELFTEST_HEAVY:-}" != "1" ]; then
    echo "builds a real project: set SELFTEST_HEAVY=1 to run it here; CI runs it in the heavy job"
    return
  fi
  local why minor
  why="$(rust_ready)"
  [ -z "$why" ] || { echo "$why"; return; }
  minor="$(rust_env rustc --version 2>/dev/null | sed -n 's/^rustc 1\.\([0-9][0-9]*\)\..*/\1/p')"
  [ "${minor:-0}" -ge 98 ] \
    || { echo "the test toolchain is older than the pack's rust-version 1.98 (set SELFTEST_RUST_TOOLCHAIN=1.98.1)"; return; }
  rust_env cargo llvm-cov --version >/dev/null 2>&1 || { echo "cargo-llvm-cov not installed"; return; }
  command -v python3 >/dev/null 2>&1 || echo "python3 not installed (it drives the pseudo-terminal)"
}
test_heavy_stack_omarchy_tui_project_is_green() {
  # The whole new-project gate for real, then the real binary in a real
  # pseudo-terminal: it enters the alternate screen, `q` quits with exit 0, and
  # it restores the terminal.
  local d="$WORK/heavy-omarchy-tui/omarchy-disk-usage-explorer" why target name
  why="$(omarchy_tui_heavy_ready)"
  [ -z "$why" ] || { skip "$why"; return; }
  fresh_copy "$d" || return 1
  (cd "$d" && HOME="$WORK/home" rust_env ./bootstrap --name "Omarchy Disk Usage Explorer" \
    --stack omarchy-tui --yes </dev/null >"$d.out" 2>&1) || fail "bootstrap exited $?: $(tail -20 "$d.out")" || return 1
  assert_contains "$d.out" "Wrote Cargo.lock" || return 1
  (cd "$d" && git add -A && git commit -qm init) || fail "commit failed" || return 1
  target="${SELFTEST_CARGO_TARGET_DIR:+$SELFTEST_CARGO_TARGET_DIR/omarchy-tui}"
  target="${target:-$d/target}"
  (cd "$d" && CARGO_TARGET_DIR="$target" rust_env ./scripts/check.sh \
    && CARGO_TARGET_DIR="$target" rust_env ./scripts/coverage.sh \
    && CARGO_TARGET_DIR="$target" rust_env ./scripts/coverage_tiers.sh --ratchet HEAD \
    && CARGO_TARGET_DIR="$target" rust_env cargo build --locked -q) \
    >"$d.gate.out" 2>&1 || fail "the new project's gate failed: $(tail -30 "$d.gate.out")" || return 1
  python3 - "$target/debug/omarchy_disk_usage_explorer" >"$d.pty.out" 2>&1 <<'PY' || fail "the real terminal run failed: $(tail -5 "$d.pty.out")" || return 1
import fcntl, os, pty, select, struct, sys, termios, time
pid, fd = pty.fork()
if pid == 0:
    # Size the terminal before the app asks, so its first frame is 24x80.
    fcntl.ioctl(1, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    os.execv(sys.argv[1], [sys.argv[1]])
out, sent, deadline = b"", False, time.time() + 20
while time.time() < deadline:
    ready, _, _ = select.select([fd], [], [], 0.2)
    if ready:
        try:
            data = os.read(fd, 65536)
        except OSError:  # EIO once the app exits (Linux)
            break
        if not data:
            break
        out += data
    if not sent and b"\x1b[?1049h" in out and b"quit" in out:
        os.write(fd, b"  q")  # two presses, then quit
        sent = True
else:
    os.kill(pid, 9)
    sys.exit("timed out: " + repr(out[-200:]))
_, status = os.waitpid(pid, 0)
assert os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0, status
assert b"\x1b[?1049l" in out, "the terminal was not restored"
print("entered and left the alternate screen; exit 0")
PY
  # A project named like one of the starter's modules or imports still compiles,
  # tests included: the code names its own crate ::name::.
  for name in app cli event io model view; do
    fresh_copy "$d.$name" || return 1
    (cd "$d.$name" && HOME="$WORK/home" rust_env ./bootstrap --name "$name" --stack omarchy-tui --yes </dev/null \
      && CARGO_TARGET_DIR="$target" rust_env cargo clippy --locked --all-targets --all-features -- -D warnings) \
      >"$d.$name.out" 2>&1 || fail "a project named $name does not compile: $(tail -20 "$d.$name.out")" || return 1
  done
}
```

**Verify**: `shellcheck scripts/template-selftest.sh` → exit 0 (heavy tests pass
`CARGO_TARGET_DIR=…` per command rather than `export` in a subshell: shellcheck flags the second
`export` as SC2030/SC2031). `./scripts/template-selftest.sh omarchy_tui` and
`./scripts/template-selftest.sh includes` fail (no pack, no mechanism yet); the heavy test
skips; every predecessor test still passes.

### Step 2: Teach `bootstrap` partial packs

1. In both discovery commands (`list_stacks` and the `STACKS=` assignment), change
   `find template/stacks -mindepth 1 -maxdepth 1 -type d -exec basename {} \;` to
   `find template/stacks -mindepth 1 -maxdepth 1 -type d ! -name '_*' -exec basename {} \;`.
2. In "Stack pack preflight", directly below the block that ends
   `echo "Unknown stack '$STACK' (available: ${STACKS:-none})" >&2` / `exit 2` / `fi`, insert:

   ```bash
     # A pack may include partial packs (template/stacks/_name/files/), copied
     # before its own files so shared files live once. Checked before any write.
     if [ -f "$pack/includes" ]; then
       while IFS= read -r part || [ -n "$part" ]; do
         case "$part" in ''|'#'*) continue ;; esac
         case "$part" in
           _|[!_]*|_*[!abcdefghijklmnopqrstuvwxyz0123456789_-]*)
             echo "Invalid include '$part' in $pack/includes: name a partial pack, _name" >&2; exit 2 ;;
         esac
         if [ ! -d "template/stacks/$part/files" ]; then
           echo "$pack/includes names '$part', which has no files/" >&2
           exit 2
         fi
       done < "$pack/includes"
     fi
   ```

3. In "Apply the stack pack", replace the copy loop

   ```bash
     (CDPATH='' cd "$pack/files" && find . -type f) | while IFS= read -r src; do
       dest="$(printf '%s' "${src#./}" | PKG="$PACKAGE_NAME" perl -pe 's#(^|/)__package__(?=/|$)#$1$ENV{PKG}#g')"
       mkdir -p "$(dirname "$dest")"
       cp "$pack/files/$src" "$dest"
     done
   ```

   with

   ```bash
     # Included partial packs first, then the pack itself, so the pack's files win.
     { if [ -f "$pack/includes" ]; then grep -v '^#' "$pack/includes" | grep . || true; fi
       echo "$STACK"; } | while IFS= read -r part; do
       (CDPATH='' cd "template/stacks/$part/files" && find . -type f) | while IFS= read -r src; do
         dest="$(printf '%s' "${src#./}" | PKG="$PACKAGE_NAME" perl -pe 's#(^|/)__package__(?=/|$)#$1$ENV{PKG}#g')"
         mkdir -p "$(dirname "$dest")"
         rm -f "$dest"  # a fresh copy takes its own mode, not an included file's
         cp "template/stacks/$part/files/$src" "$dest"
       done
     done
   ```

4. In `TEMPLATE.md` → `## Stack packs`, add after the `description` bullet:

   ```markdown
   - `includes` (optional): partial packs to copy first, one per line. A partial pack is a
     directory `template/stacks/_name/` with only `files/` (and optionally shared scripts such as
     `validate-name` for packs to call). It is never offered as a stack; the including pack's own
     files win. `_rust-gates` holds the Rust toolchain pin, formatter config and coverage gates.
   ```

**Verify**: `./scripts/template-selftest.sh includes` → 2 passed; `./scripts/template-selftest.sh
test_bootstrap_` → all pass (the `omarchy_tui` tests still fail until step 4); `shellcheck
bootstrap` → exit 0.

### Step 3: Move the Rust gates into `_rust-gates`

```sh
mkdir -p template/stacks/_rust-gates/files/scripts/check.d
for f in rust-toolchain.toml rustfmt.toml scripts/coverage.sh scripts/coverage_tiers.sh scripts/check.d/rust.sh; do
  git mv "template/stacks/rust/files/$f" "template/stacks/_rust-gates/files/$f"
  git rm -q "template/stacks/omarchy-app/files/$f"
done
git mv template/stacks/rust/validate-name template/stacks/_rust-gates/validate-name
printf '_rust-gates\n' > template/stacks/rust/includes
printf '_rust-gates\n' > template/stacks/omarchy-app/includes
```

Then:

1. Create `template/stacks/rust/validate-name` (mode 755):

   ```sh
   #!/bin/sh
   # The rust pack's names are exactly Rust's rules, kept once in _rust-gates.
   # bootstrap runs this from the template root.
   exec sh template/stacks/_rust-gates/validate-name "$@"
   ```

2. Replace `template/stacks/omarchy-app/validate-name` with (keep mode 755):

   ```sh
   #!/bin/sh
   # Names an omarchy-app project can't use. Rust's rules come first (the shared
   # list in _rust-gates: keywords and Cargo-reserved names). Then the crates this
   # pack builds on: a crate can't depend on a crate with its own name. And
   # `omarchy`, the Omarchy command itself. bootstrap runs this from the template root.
   rust_rules=template/stacks/_rust-gates/validate-name
   if [ ! -f "$rust_rules" ]; then
     echo "The omarchy-app pack needs $rust_rules." >&2
     exit 2
   fi
   sh "$rust_rules" "$@" || exit 2
   case "$1" in
     gpui|gpui_pre|gpui_base|gpui_kit|gpui_kit_assets|gpui_omarchy|omarchy)
       echo "Package name '$1' is taken by a crate this pack builds on, or by the omarchy command; choose another project name." >&2
       exit 2 ;;
   esac
   ```
3. If `template/stacks/rust/after-bootstrap` doesn't already run `cargo fmt --all`, replace it
   with plan 007's amended version (in `plans/007-stack-pack-rust.md`, "`template/stacks/rust/after-bootstrap`").

**Verify**: `./scripts/template-selftest.sh stack_rust` → all pass (with the named local skips
plan 007 allows); `./scripts/template-selftest.sh omarchy_app` → all pass (heavy skipped);
`git status` shows the five files as renames.

### Step 4: Create the omarchy-tui pack

1. `mkdir -p template/stacks/omarchy-tui/files/scripts/check.d` and copy the install script
   unchanged: `cp -p template/stacks/omarchy-app/files/scripts/install.sh template/stacks/omarchy-tui/files/scripts/install.sh`.
   Copy the icon the same way: `mkdir -p template/stacks/omarchy-tui/files/assets && cp -p
   template/stacks/omarchy-app/files/assets/icon.svg template/stacks/omarchy-tui/files/assets/icon.svg`.
2. Create each file below with exactly this content (paths relative to
   `template/stacks/omarchy-tui/`), then `chmod +x validate-name after-bootstrap
   files/scripts/check.d/omarchy.sh` inside that directory.

`description`:

```text
Omarchy terminal app: Rust + ratatui
```

`commands`:

```text
# KEY=value lines. ./bootstrap --stack omarchy-tui replaces {{KEY}} and
# {{KEY: description}} placeholders in the project's docs with these values.
INSTALL_CMD=cargo build --locked
DEV_CMD=cargo run --locked
BUILD_CMD=cargo build --locked --release
CHECK_CMD=./scripts/check.sh
TEST_CMD=cargo test --locked
SHIP_GATE=./scripts/check.sh && ./scripts/coverage.sh
STACK=A keyboard-driven Omarchy terminal app: Rust 1.98 (edition 2024, pinned in rust-toolchain.toml) with ratatui 0.30 and its crossterm, drawn in the terminal's own 16 colours so it follows the Omarchy theme; clippy (pedantic, warnings are errors); rustfmt; cargo test driving the real event loop into a TestBackend; cargo-llvm-cov; ./scripts/install.sh adds a launcher entry that opens it in a floating terminal.
COVERAGE_ENFORCEMENT=./scripts/coverage.sh: cargo llvm-cov with the 90% line and region floors (regions stand in for branches on stable Rust), then the per-tier gates of scripts/coverage_tiers.sh (pure logic and the command line at 100%, the event loop and the screen at the 90% floor); CI runs it, fail-closed
```

`gitignore`:

```text
# --- Rust (omarchy-tui) ---
/target/
coverage.json
lcov.info
*.profraw
```

`includes`:

```text
_rust-gates
```

`validate-name`:

```sh
#!/bin/sh
# Names an omarchy-tui project can't use. Rust's rules come first (the shared
# list in _rust-gates: keywords and Cargo-reserved names). Then the crates this
# pack builds on, and `omarchy`, the Omarchy command. bootstrap runs this from
# the template root.
rust_rules=template/stacks/_rust-gates/validate-name
if [ ! -f "$rust_rules" ]; then
  echo "The omarchy-tui pack needs $rust_rules." >&2
  exit 2
fi
sh "$rust_rules" "$@" || exit 2
case "$1" in
  ratatui|ratatui_core|ratatui_widgets|ratatui_crossterm|crossterm|omarchy)
    echo "Package name '$1' is taken by a crate this pack builds on, or by the omarchy command; choose another project name." >&2
    exit 2 ;;
esac
```

`after-bootstrap`:

```sh
#!/bin/sh
# Runs once at the end of ./bootstrap --stack omarchy-tui, from the project root.
# 1. rustfmt lays lines out by length, and the project's name just changed the
#    starter's lines: format them so `cargo fmt --check` passes (no network).
# 2. Lock ratatui's dependencies (from crates.io, so this needs the network)
#    and commit Cargo.lock, so CI's --locked builds pass on the first push.
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

`files/.github/workflows/ci.yml`:

```yaml
# CI for {{PROJECT_NAME}} (vibe-starter omarchy-tui stack pack): guards, then tests
# with the coverage gates from TESTING.md, then doctests. ratatui needs no system
# libraries; desktop-file-utils checks the launcher entry.
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
    # Pinned, not ubuntu-latest: the apt package name below is Ubuntu 24.04's.
    runs-on: ubuntu-24.04
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v7

      - name: Install gitleaks
        uses: ./.github/actions/install-gitleaks

      - name: Install desktop-file-validate
        run: |
          sudo apt-get update
          sudo apt-get install -y --no-install-recommends desktop-file-utils

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

`files/Cargo.toml`:

```toml
[package]
name = "{{PACKAGE_NAME}}"
# The real version is the root VERSION file (gstack /ship bumps it), compiled in
# by src/lib.rs. This one stays 0.0.0 so Cargo.lock never churns.
version = "0.0.0"
edition = "2024"
# ratatui 0.30 needs Rust 1.88. Declare the pinned toolchain
# (rust-toolchain.toml), the only one CI builds with.
rust-version = "1.98"
description = "{{PROJECT_NAME}}"
publish = false

[dependencies]
# ratatui re-exports the crossterm it was built against (ratatui::crossterm);
# use that, never a second crossterm, so the two can't drift apart.
ratatui = "0.30.2"

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
include = ["src/app.rs", "src/view.rs"]
```

`files/DESIGN.md`:

```markdown
# Design System — {{PROJECT_NAME}}

{{PROJECT_NAME}} is a terminal app for Omarchy, so its colours and font are the terminal's, and
Omarchy sets both: every `omarchy theme set` rewrites the terminal's 16 ANSI colours and asks
the terminal to reload, and `omarchy font set` changes its font. The rules below keep the app
inside that system, and QA holds the app to them.

## Aesthetic
A keyboard tool that looks at home in an Omarchy terminal: plain text, box-drawing borders and
one accent colour.

## Color
Only the terminal's own colours: the 16 named ANSI colours (`Color::Blue`, `Color::Red`, ...)
and `Color::Reset` for its default foreground and background. Never `Color::Rgb`,
`Color::Indexed` or a colour made from a number or a string (`Color::from_u32`,
`Color::from([r, g, b])`, a parsed `"#…"`): they ignore the theme, and
`scripts/check.d/omarchy.sh` refuses them. It reads text, not types, so `(r, g, b).into()` gets
past it; the rule still holds. Pick
one named colour as the accent (the starter uses blue), red for danger, yellow for warnings and
green for success.

## Typography
The terminal's font, which `omarchy font set` chooses. Bold for keys and for the one thing that
matters on screen; no other emphasis.

## Spacing & layout
Content centred in bordered blocks, with one blank line between groups. A small terminal must
still draw without panicking; draw what fits (`tests/view.rs` draws an 8×2 terminal).

## Motion
None. Redraw on input only.

## Anti-slop rules
- No RGB or 256-colour literals.
- Every action has a key, and the screen shows it.
- `q` and `Esc` leave. Ask for confirmation only before what can't be undone.
```

`files/docs/guides/omarchy.md`:

````markdown
# Omarchy integration

How {{PROJECT_NAME}} fits into an Omarchy 4 desktop: Hyprland configured in Lua, terminals
themed by Omarchy, and the launcher on `Super + Space`.

## Run and test

- `cargo run --locked` runs it in this terminal; `q` or `Esc` leaves. It runs in any terminal,
  over SSH and on macOS too.
- `cargo test --locked` drives the real event loop with scripted key presses into ratatui's
  `TestBackend`; no terminal needed.

## Install it for yourself

`./scripts/install.sh` builds a release binary and installs, under `~/.local` (no root):

- `~/.local/bin/{{PACKAGE_NAME}}`
- `~/.local/share/applications/{{PACKAGE_NAME}}.desktop`, which the Omarchy launcher lists. It
  opens the app in a floating terminal, `xdg-terminal-exec --app-id=TUI.float -e ...`, the
  same kind of entry `omarchy-tui-install` writes: Omarchy's window rules float and centre the
  `TUI.float` class.
- `~/.local/share/icons/hicolor/scalable/apps/{{PACKAGE_NAME}}.svg`

`./scripts/install.sh --uninstall` removes exactly those three files. To install system-wide,
build as yourself, then run `sudo PREFIX=/usr/local ./scripts/install.sh --no-build`.

## Keybinding

Omarchy's Hyprland config is Lua with no drop-in directory, so nothing here edits it for you.
Add a binding by hand, after checking the key is free (`omarchy menu keybindings --print`):

```lua
-- ~/.config/hypr/bindings.lua: in a floating terminal...
o.bind("SUPER + ALT + T", "{{PROJECT_NAME}}", "omarchy-launch-tui --app-id=TUI.float {{PACKAGE_NAME}}")
-- ...or tiled, as the window class org.omarchy.{{PACKAGE_NAME}}:
-- o.bind("SUPER + ALT + T", "{{PROJECT_NAME}}", { tui = "{{PACKAGE_NAME}}" })
```

## Theme and fonts

Nothing to do. On `omarchy theme set`, Omarchy rewrites the terminal's colours and signals it
to reload, so the app changes with the theme as long as it uses only the 16 named colours
(`tests/view.rs` checks every cell). The font is the terminal's.

## Sharing it

As for any Omarchy app: release a tarball per architecture (the stripped binary,
`packaging/app.desktop.in` as `{{PACKAGE_NAME}}.desktop.in`, the icon as
`{{PACKAGE_NAME}}.svg`, `LICENSE` and `README.md`). An AUR `{{PACKAGE_NAME}}-bin` PKGBUILD
installs from those tarballs and renders the entry with `sed -e 's|@BINDIR@|/usr/bin|' -e
"s|@VERSION@|$pkgver|"`; it needs only `glibc` and `xdg-terminal-exec`. Omarchy's own package
repository (`omacom/omarchy-pkgs`) takes pull requests with such a PKGBUILD; that's how Omarchy
preinstalls terminal apps such as cliamp.
````

`files/packaging/app.desktop.in`:

```ini
[Desktop Entry]
Type=Application
Version=1.5
Name={{PROJECT_NAME}}
Comment={{PROJECT_NAME}}, an Omarchy terminal app
Exec=xdg-terminal-exec --app-id=TUI.float -e "@BINDIR@/{{PACKAGE_NAME}}"
Icon={{PACKAGE_NAME}}
Terminal=false
Categories=Utility;
StartupNotify=true
X-AppVersion=@VERSION@
```

`files/scripts/check.d/omarchy.sh`:

```bash
#!/usr/bin/env bash
# Omarchy guards (from ./bootstrap --stack omarchy-tui): colours are the
# terminal's own, never RGB or 256-colour literals in src/, and the desktop
# entry is valid.
set -euo pipefail

# Omarchy rewrites the terminal's 16 ANSI colours on `omarchy theme set`; RGB and
# 256-colour values would stay put. The check reads text, not types
# ((r, g, b).into() gets past it), so DESIGN.md's rule still holds. See src/view.rs.
if grep -rnE '\b(Rgb|Indexed)\(|Color::(from_u32|from_hsl|from_hsluv|from_str|from)\(|parse::<Color>' src; then
  echo "  RGB or 256-colour values in src/ (above): use the 16 named colours (DESIGN.md)" >&2
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

`files/src/app.rs`:

```rust
//! The event loop: read a key, update the model, draw. It is generic over the
//! terminal backend and the event source, so tests drive the real loop with
//! ratatui's `TestBackend` and a scripted list of events.

use std::io;

use ratatui::Terminal;
use ratatui::backend::Backend;
use ratatui::crossterm::event::Event;

use crate::model::{Model, action_for};
use crate::view;

/// Draws, then handles `events` until the user quits or they run out, and
/// returns the final model. A resize draws again, at the terminal's new size.
///
/// # Errors
///
/// When drawing fails, or an event cannot be read.
pub fn run<B>(
    terminal: &mut Terminal<B>,
    events: impl IntoIterator<Item = io::Result<Event>>,
) -> io::Result<Model>
where
    B: Backend,
    B::Error: Send + Sync + 'static,
{
    let mut model = Model::default();
    draw(terminal, model)?;
    for event in events {
        let key = match event? {
            Event::Key(key) => key,
            // ratatui fits the screen to the terminal's size when it draws.
            Event::Resize(..) => {
                draw(terminal, model)?;
                continue;
            }
            _ => continue,
        };
        let Some(action) = action_for(key) else {
            continue;
        };
        model.update(action);
        if model.should_quit() {
            break;
        }
        draw(terminal, model)?;
    }
    Ok(model)
}

fn draw<B>(terminal: &mut Terminal<B>, model: Model) -> io::Result<()>
where
    B: Backend,
    B::Error: Send + Sync + 'static,
{
    terminal
        .draw(|frame| view::render(model, frame))
        .map_err(io::Error::other)?;
    Ok(())
}
```

`files/src/cli.rs`:

```rust
//! The command line: the machine contract (DOCTRINE.md §3). Parsing is pure,
//! and `tests/cli.rs` checks every answer through the real binary. With no
//! arguments the binary takes over the terminal instead.

/// What the command line asked for.
#[derive(Debug, PartialEq, Eq)]
pub enum Command {
    /// Run the app in this terminal.
    Open,
    /// Print this on stdout and exit 0.
    Print(String),
}

/// The `--help` text.
pub const USAGE: &str = "usage: {{PACKAGE_NAME}} [--help | --version]\n\
    With no arguments, runs {{PROJECT_NAME}} in this terminal.\n";

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

`files/src/lib.rs`:

```rust
//! A keyboard-driven terminal app for Omarchy, built with ratatui.

pub mod app;
pub mod cli;
pub mod model;
pub mod view;

/// The project version, from the root `VERSION` file. gstack `/ship` bumps that
/// file; `Cargo.toml` keeps `0.0.0` so `Cargo.lock` never churns.
pub const VERSION: &str = include_str!("../VERSION").trim_ascii_end();

/// The installed binary's name, which the desktop entry and the icon share
/// (`packaging/app.desktop.in`, `scripts/install.sh`).
pub const APP_ID: &str = "{{PACKAGE_NAME}}";
```

`files/src/main.rs`:

```rust
//! Command-line entry point: prints what `cli::parse` returns, or runs the app
//! in this terminal. Everything testable lives in the library.

use std::process::ExitCode;

use ::{{PACKAGE_NAME}}::cli::{self, Command};
use ratatui::crossterm::event;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match cli::parse(&args) {
        Ok(Command::Print(out)) => {
            print!("{out}");
            ExitCode::SUCCESS
        }
        Ok(Command::Open) => {
            // The one path no test runs: the real terminal and its real keys.
            let events = std::iter::repeat_with(event::read);
            match ratatui::run(|terminal| ::{{PACKAGE_NAME}}::app::run(terminal, events)) {
                Ok(_) => ExitCode::SUCCESS,
                Err(err) => {
                    eprintln!("error: {err}");
                    ExitCode::FAILURE
                }
            }
        }
        Err(err) => {
            eprint!("{err}");
            ExitCode::from(2)
        }
    }
}
```

`files/src/model.rs`:

```rust
//! The app's state and what each key does to it, without a terminal. Pure, so
//! it is held to the pure-logic tier (100% lines and regions).

use ratatui::crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyModifiers};

/// Something the user asked for.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    /// Count one more press.
    Increment,
    /// Start counting from zero again.
    Reset,
    /// Leave the app.
    Quit,
}

/// The key map. Key releases and keys that mean nothing give `None`.
#[must_use]
pub fn action_for(key: KeyEvent) -> Option<Action> {
    if key.kind != KeyEventKind::Press {
        return None;
    }
    let control = key.modifiers.contains(KeyModifiers::CONTROL);
    match key.code {
        KeyCode::Char('c') if control => Some(Action::Quit),
        KeyCode::Char(' ') => Some(Action::Increment),
        KeyCode::Char('r') => Some(Action::Reset),
        KeyCode::Char('q') | KeyCode::Esc => Some(Action::Quit),
        _ => None,
    }
}

/// The app's state.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Model {
    count: u32,
    quit: bool,
}

impl Model {
    /// A model whose count starts at `count`.
    #[must_use]
    pub const fn starting_at(count: u32) -> Self {
        Self { count, quit: false }
    }

    /// How many presses were counted.
    #[must_use]
    pub const fn count(self) -> u32 {
        self.count
    }

    /// Whether the user asked to leave.
    #[must_use]
    pub const fn should_quit(self) -> bool {
        self.quit
    }

    /// Applies `action`. Counting stops at `u32::MAX` instead of wrapping.
    pub const fn update(&mut self, action: Action) {
        match action {
            Action::Increment => self.count = self.count.saturating_add(1),
            Action::Reset => self.count = 0,
            Action::Quit => self.quit = true,
        }
    }

    /// What the screen shows.
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

`files/src/view.rs`:

```rust
//! Drawing the model. Colours are the terminal's own: its 16 ANSI colours and
//! its default foreground and background, which Omarchy rewrites on every
//! `omarchy theme set`, so the app follows the theme with no code of its own.
//! `Color::Rgb` and `Color::Indexed` would stay put; `scripts/check.d` refuses
//! them.

use ratatui::Frame;
use ratatui::layout::{Constraint, Flex, Layout};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Paragraph};

use crate::model::Model;

/// The title on the box's top border.
pub const TITLE: &str = " {{PROJECT_NAME}} ";

/// Draws `model` centred in the frame.
pub fn render(model: Model, frame: &mut Frame) {
    // Wide enough for the title and the key hints; a narrow terminal cuts it.
    let width = u16::try_from(TITLE.chars().count() + 2).map_or(u16::MAX, |w| w.max(36));
    let [area] = Layout::vertical([Constraint::Length(5)])
        .flex(Flex::Center)
        .areas(frame.area());
    let [area] = Layout::horizontal([Constraint::Length(width)])
        .flex(Flex::Center)
        .areas(area);
    let accent = Style::new().fg(Color::Blue);
    let key = accent.add_modifier(Modifier::BOLD);
    let keys = Line::from(vec![
        Span::styled("space", key),
        Span::raw(" press  "),
        Span::styled("r", key),
        Span::raw(" reset  "),
        Span::styled("q", key),
        Span::raw(" quit"),
    ]);
    let block = Block::bordered().title(TITLE).border_style(accent);
    let text = vec![Line::from(model.label()), Line::default(), keys];
    frame.render_widget(Paragraph::new(text).block(block).centered(), area);
}
```

`files/tests/app.rs`:

```rust
//! The real event loop, driven by scripted key presses into a `TestBackend`.

use std::io;

use ::{{PACKAGE_NAME}}::app;
use ratatui::Terminal;
use ratatui::backend::TestBackend;
use ratatui::buffer::Cell;
use ratatui::crossterm::event::{Event, KeyCode, KeyEvent};

/// One key press per character of `typed`.
fn keys(typed: &str) -> Vec<io::Result<Event>> {
    typed
        .chars()
        .map(|c| Ok(Event::Key(KeyEvent::from(KeyCode::Char(c)))))
        .collect()
}

fn terminal() -> Terminal<TestBackend> {
    Terminal::new(TestBackend::new(60, 12)).expect("terminal")
}

#[test]
fn keys_count_reset_and_quit() {
    let mut terminal = terminal();
    let model = app::run(&mut terminal, keys("  r q ")).expect("run");
    // The press after `q` is never read.
    assert_eq!(model.count(), 1);
    assert!(model.should_quit());
}

#[test]
fn the_screen_shows_the_latest_count() {
    let mut terminal = terminal();
    app::run(&mut terminal, keys("  ")).expect("run");
    let screen: String = terminal
        .backend()
        .buffer()
        .content
        .iter()
        .map(Cell::symbol)
        .collect();
    assert!(screen.contains("Pressed 2 times"), "screen: {screen:?}");
}

#[test]
fn other_events_and_unbound_keys_are_ignored() {
    let mut terminal = terminal();
    let mut events = vec![Ok(Event::FocusGained)];
    events.extend(keys("x "));
    let model = app::run(&mut terminal, events).expect("run");
    assert_eq!(model.count(), 1);
    assert!(!model.should_quit());
}

#[test]
fn a_resize_draws_again_without_waiting_for_a_key() {
    let mut terminal = terminal();
    let model = app::run(&mut terminal, vec![Ok(Event::Resize(80, 24))]).expect("run");
    assert_eq!(model.count(), 0);
    // Two frames: the first draw, and the resize's.
    assert_eq!(terminal.get_frame().count(), 2);
}

#[test]
fn a_read_error_ends_the_loop_with_that_error() {
    let mut terminal = terminal();
    let mut events = keys(" ");
    events.push(Err(io::Error::other("terminal went away")));
    let err = app::run(&mut terminal, events).expect_err("the error");
    assert_eq!(err.to_string(), "terminal went away");
}
```

`files/tests/cli.rs`:

```rust
//! CLI contract tests (TESTING.md tier 2: exit code and output of every
//! command), through the real binary. No arguments takes over the terminal, which
//! `tests/app.rs` covers instead.

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
fn no_arguments_means_run_the_app() {
    // Asserted on the parser: the binary would take over this terminal.
    assert_eq!(::{{PACKAGE_NAME}}::cli::parse(&[]), Ok(::{{PACKAGE_NAME}}::cli::Command::Open));
}
```

`files/tests/desktop_entry.rs`:

```rust
//! Named invariant: the launcher entry runs the installed binary in a floating
//! Omarchy terminal (`TUI.float` is the class Omarchy's window rules float) and
//! shares its name with the binary and the icon.

#[test]
fn the_desktop_entry_launches_the_binary_in_a_floating_terminal() {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/packaging/app.desktop.in");
    let entry = std::fs::read_to_string(path).expect("packaging/app.desktop.in exists");
    let id = ::{{PACKAGE_NAME}}::APP_ID;
    for line in [
        format!("Exec=xdg-terminal-exec --app-id=TUI.float -e \"@BINDIR@/{id}\""),
        format!("Icon={id}"),
        "Terminal=false".to_owned(),
    ] {
        assert!(entry.lines().any(|l| l == line), "missing line: {line}");
    }
}
```

`files/tests/model.rs`:

```rust
//! Pure-logic tests (TESTING.md tier 1): the key map and every state change.

use ::{{PACKAGE_NAME}}::model::{Action, Model, action_for};
use ratatui::crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyModifiers};

fn press(code: KeyCode) -> KeyEvent {
    KeyEvent::new(code, KeyModifiers::NONE)
}

#[test]
fn the_key_map() {
    assert_eq!(
        action_for(press(KeyCode::Char(' '))),
        Some(Action::Increment)
    );
    assert_eq!(action_for(press(KeyCode::Char('r'))), Some(Action::Reset));
    assert_eq!(action_for(press(KeyCode::Char('q'))), Some(Action::Quit));
    assert_eq!(action_for(press(KeyCode::Esc)), Some(Action::Quit));
    let ctrl_c = KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL);
    assert_eq!(action_for(ctrl_c), Some(Action::Quit));
    assert_eq!(action_for(press(KeyCode::Char('c'))), None);
    assert_eq!(action_for(press(KeyCode::Enter)), None);
}

#[test]
fn key_releases_do_nothing() {
    let mut release = press(KeyCode::Char(' '));
    release.kind = KeyEventKind::Release;
    assert_eq!(action_for(release), None);
}

#[test]
fn increment_counts_and_the_label_follows() {
    let mut model = Model::default();
    assert_eq!(model.label(), "Not pressed yet");
    model.update(Action::Increment);
    assert_eq!(model.label(), "Pressed once");
    model.update(Action::Increment);
    assert_eq!(model.count(), 2);
    assert_eq!(model.label(), "Pressed 2 times");
}

#[test]
fn increment_saturates_instead_of_wrapping() {
    let mut model = Model::starting_at(u32::MAX);
    model.update(Action::Increment);
    assert_eq!(model.count(), u32::MAX);
}

#[test]
fn reset_goes_to_zero_and_quit_is_remembered() {
    let mut model = Model::starting_at(7);
    model.update(Action::Reset);
    assert_eq!(model.count(), 0);
    assert!(!model.should_quit());
    model.update(Action::Quit);
    assert!(model.should_quit());
}
```

`files/tests/view.rs`:

```rust
//! The screen (TESTING.md tier 3), drawn into ratatui's `TestBackend`.

use ::{{PACKAGE_NAME}}::model::{Action, Model};
use ::{{PACKAGE_NAME}}::view;
use ratatui::Terminal;
use ratatui::backend::TestBackend;
use ratatui::buffer::Buffer;
use ratatui::style::Color;

fn draw(model: Model, width: u16, height: u16) -> Buffer {
    let mut terminal = Terminal::new(TestBackend::new(width, height)).expect("terminal");
    terminal
        .draw(|frame| view::render(model, frame))
        .expect("draw");
    terminal.backend().buffer().clone()
}

fn text(buffer: &Buffer) -> String {
    let area = buffer.area;
    (area.top()..area.bottom())
        .map(|y| {
            (area.left()..area.right())
                .map(|x| buffer[(x, y)].symbol())
                .collect::<String>()
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[test]
fn the_screen_shows_the_title_the_count_and_the_keys() {
    let mut model = Model::default();
    model.update(Action::Increment);
    let screen = text(&draw(model, 160, 12));
    for expected in [view::TITLE.trim(), "Pressed once", "space press", "r reset", "q quit"] {
        assert!(screen.contains(expected), "missing {expected:?} in\n{screen}");
    }
}

/// Named invariant: every cell uses the terminal's own colours (the 16 ANSI
/// colours or its default), which Omarchy rewrites on `omarchy theme set`.
#[test]
fn every_cell_uses_theme_colours() {
    let buffer = draw(Model::default(), 160, 12);
    for cell in &buffer.content {
        for colour in [cell.fg, cell.bg] {
            assert!(
                !matches!(colour, Color::Rgb(..) | Color::Indexed(_)),
                "{colour:?} ignores the Omarchy theme"
            );
        }
    }
}

#[test]
fn a_tiny_terminal_still_draws() {
    let buffer = draw(Model::default(), 8, 2);
    assert_eq!(buffer.area.width, 8);
}
```

**Verify**: shell lint → exit 0; `./scripts/template-selftest.sh omarchy_tui` → 3 passed, 1
skipped; `./scripts/template-selftest.sh rust_packs_share` → 1 passed;
`./scripts/template-selftest.sh carry_only` → 1 passed; `./bootstrap --help` lists
`omarchy-tui` and not `_rust-gates`.

### Step 5: Document the pack in `TEMPLATE.md`

1. Add a row to the "Omarchy apps: choose by what the app should do" table:

   ```markdown
   | be a keyboard-driven tool in a terminal, light, fine over SSH | `omarchy-tui` | Rust + ratatui 0.30, drawn in the terminal's 16 colours |
   ```

2. Extend the "Available:" paragraph with `omarchy-tui` (a terminal app for Omarchy: Rust +
   ratatui, with the Rust gates from `_rust-gates`).

**Verify**: `grep -c 'omarchy-tui' TEMPLATE.md` → at least `2`.

### Step 6: Full verification and a manual look

```sh
SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh          # baseline + 7 passed, 0 failed
./scripts/check.sh                                                   # exit 0
```

Name any local skips; zero skips is required in the `selftest` CI job.

With Rust 1.98.1, cargo-llvm-cov, jq and python3 installed: `SELFTEST_HEAVY=1
SELFTEST_RUST_TOOLCHAIN=1.98.1 ./scripts/template-selftest.sh test_heavy_` → 2 passed (both
Omarchy packs). Otherwise the `heavy` CI job must pass before this plan counts as done.

Then, after committing, in a scratch clone (as plan 008 step 8 does, with
`--stack omarchy-tui`): bootstrap, `test -f Cargo.lock`, commit, `./scripts/check.sh`,
`./scripts/coverage.sh`, and run `cargo run --locked` in a terminal: space counts, `r` resets,
`q` leaves. On Omarchy, `./scripts/install.sh` and open it from the launcher: it should appear in
a floating terminal, in the current theme's colours.

## Test plan

Nine new test functions and two changes:

- `test_stack_pack_includes_copy_partial_packs_first`: a fixture pack including a fixture
  partial pack gets both sets of files, the pack's own copy wins, placeholders are filled.
- `test_stack_pack_includes_are_checked_before_writes`: `fixture-shared`, `_missing`,
  `_bad/name` and `_` each exit 2 with no file changed.
- `test_partial_packs_are_not_offered_as_stacks`: `--help` omits `_rust-gates`;
  `--stack _rust-gates` exits 2.
- `test_rust_packs_share_one_copy_of_their_gates`: rust, omarchy-app and omarchy-tui include
  `_rust-gates`, carry none of its files, and a bootstrapped project still gets them,
  executable.
- `test_omarchy_packs_share_one_install_script`: the two `install.sh` copies are identical.
- `test_stack_omarchy_tui_bootstrap_installs_the_pack`, `…_rejects_unusable_names_before_writes`,
  `…_guard_refuses_rgb_and_256_colour_literals`: as for omarchy-app (RGB, 256-colour and
  number- or string-made colours fail; the 16 named colours pass).
- `test_heavy_stack_omarchy_tui_project_is_green` (heavy job): real bootstrap, `check.sh`,
  `coverage.sh`, ratchet, then the real binary in a 24×80 pseudo-terminal: it enters the
  alternate screen, `q` exits 0, and it leaves the alternate screen. Projects named `app`,
  `cli`, `event`, `io`, `model` and `view` pass clippy on every target.
- Changed: `test_bootstrap_help_lists_stack_packs_with_what_they_are_for` skips `_*` directories;
  `test_stack_omarchy_app_bootstrap_installs_the_pack` expects the `_rust-gates` files;
  `test_stack_pack_includes_copy_partial_packs_first` checks that an override keeps its own
  mode; `test_stack_omarchy_app_shares_the_rust_packs_gates` is deleted (replaced, as above).

Net: +8 tests (7 in the `selftest` job, 1 heavy). Rehearsed while planning: the full suite on
macOS bash 3.2 (163 passed; the only skip was cargo-llvm-cov, not installed there), and both
heavy tests plus all six rust-pack tests on Linux with Rust 1.98.1.

## Done criteria

ALL must hold:

- [ ] `SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh` → baseline + 7 passed, 0 failed; local skips named; the `selftest` CI job has 0 skipped
- [ ] Both heavy tests passed, locally or in the `heavy` CI job (say which)
- [ ] Shell lint exits 0; `./scripts/check.sh` exits 0
- [ ] `find template/stacks/rust/files template/stacks/omarchy-app/files template/stacks/omarchy-tui/files -name rust-toolchain.toml` prints nothing
- [ ] `./bootstrap --help` lists `omarchy-app`, `omarchy-tui`, `python` and `rust`, not `_rust-gates`
- [ ] `git status --porcelain` shows only in-scope paths; `plans/README.md` row updated

## STOP conditions

Stop and report back (do not improvise) if:

- A contract under "Current state" differs, or any plan 006–008 test fails.
- A rust-pack or omarchy-app test fails after the move in step 3: the move must be invisible to
  generated projects.
- clippy or coverage fails on the TUI starter; report, don't loosen lints or floors.
- The pseudo-terminal test hangs or the binary doesn't restore the terminal.
- You'd need pack inheritance beyond `includes` (a pack including a full pack, or includes that
  include), or a partial pack with `commands`/`gitignore`: that is a design change.

## Maintenance notes

- **Adding a Rust pack** now means `includes` with `_rust-gates` and no copies. A toolchain bump
  still spans files: the channel in `_rust-gates/files/rust-toolchain.toml`, both jobs' `rustup
  toolchain install` and `SELFTEST_RUST_TOOLCHAIN` in `.github/workflows/template-selftest.yml`,
  the Omarchy packs' `rust-version` and the `-ge 98` checks in their `*_heavy_ready` helpers, and
  the Rust version the packs' `commands` STACK lines and `rust/description` name. `grep -rn
  '1\.98' .github scripts template TEMPLATE.md` lists them.
- **A third copy of `install.sh`** (a fourth native Omarchy pack) should move it into a
  partial pack, `_omarchy-launcher`, the same way.
- **ratatui upgrades**: ratatui re-exports crossterm; keep using `ratatui::crossterm` so the two
  never diverge. 0.30 changed `Backend` to an associated `Error` type; `app::run`'s bound reflects
  that. The version is also named in `commands`' STACK line and `TEMPLATE.md`'s table; bump them
  with the pin.
- **Terminal colours**: crossterm writes the 16 named colours as palette indices 0–15, which
  Omarchy's themes set. Keep the guard: a single `Color::Rgb` quietly breaks theming.
- Reviewer focus: the `includes` validation (exit 2 before writes) and copy order; the `git mv`
  renames; `app::run`'s error handling; the pseudo-terminal harness.
