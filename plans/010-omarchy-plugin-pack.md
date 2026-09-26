# Plan 010: Add the `omarchy-plugin` stack pack (an Omarchy 4 shell plugin in QML)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Predecessor preflight (run first)**: plans 001–009 must be done, in order. Run
> `SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh` and record its summary line and
> named skips in `.context/plan-010-baseline.txt`; any failure is a STOP condition. Check the
> contracts under "Current state"; what this plan says about 007–009 comes from their plan files.

## Status

- **Priority**: P2 (requested by the maintainer)
- **Effort**: M
- **Risk**: MED. It brings a new language (QML with plain JavaScript) into the template, and its
  host checks fetch Omarchy's own scripts from GitHub at a pinned commit. It adds no Rust and
  doesn't touch `bootstrap`.
- **Depends on**: 008 (pack descriptions, `SELFTEST_EXCLUDE`, the `heavy` job), 009 (its
  `includes` support, `_*` hiding and test block, which this plan builds on), 006 (the mechanism).
- **Category**: direction
- **Planned at**: commit `98063fc` with plans 007–009 applied in a rehearsal, 2026-09-25

## Why this matters

Plan 008 set out the Omarchy packs by what the app should do. This plan adds the third:

| The app should… | Pack | Stack |
|---|---|---|
| live inside the desktop itself: a bar widget, a panel, a menu, an overlay, a background service | `omarchy-plugin` | QML shell plugin for Omarchy 4's `omarchy-shell` |

Omarchy 4 (v4.0.0, 2026-08-14) replaced Waybar, Walker and Mako with one Quickshell process,
`omarchy-shell`, in which almost everything on screen is a plugin. A third-party plugin is a git
repository with a `manifest.json` at its root, installed with `omarchy plugin add <url>`,
validated by `omarchy plugin validate`, and hot-reloaded on save
(`manual/32-shell-plugins.md`). It is the dominant way people extend Omarchy: the plugin
directory (plugins.omarchy.org) listed about 4,100 plugins within two months. The reference
repositories are `omacom/elsewhen` (Omarchy's own world-clock plugin) and
`basecamp/omarchy-hey-plugin`.

After this plan, `./bootstrap --stack omarchy-plugin` creates a plugin that:

- is a bar widget built from Omarchy's own `qs.Ui` components (so it looks like its neighbours
  and follows `omarchy theme set`), with a setting declared in its manifest;
- keeps its logic in plain JavaScript that both QML and Node load, held at 100% lines, branches
  and functions by Node's test runner;
- tests the real `Widget.qml` under Qt 6's `qmltestrunner`, offscreen, against stand-ins for
  the `qs.Ui` components it uses;
- checks itself with Omarchy's own validator and Text-format scanner, pinned to a released
  Omarchy commit, on exactly the files `omarchy plugin add` would clone;
- keeps `manifest.json`'s version equal to `VERSION`, with gstack `/ship` writing both;
- has live CI (about half a minute) and a `dev-link.sh` for the edit-reload loop on Omarchy.

## Design decisions (each verified while planning)

- **The starter is the smallest real shape.** Omarchy's `shell/plugins/menu/BarWidget.qml` is a
  `BarWidget` holding one `WidgetButton` whose `onPressed(button)` gets the mouse button. The
  starter is that, counting presses: a click counts, a right-click resets, and the label comes
  from a `label` setting declared in `barWidget.defaults`/`schema` and read with
  `setting(name, fallback)`. Panels, menus, overlays and services are documented pointers, not
  starter code.
- **Logic in plain JavaScript**, ending in
  `if (typeof module !== "undefined") module.exports = {…}`, the pattern Omarchy's own 26 JS
  modules use: QML imports it with `import "Logic.js" as Logic`, Node with `require()`. Node's
  test runner enforces `--test-coverage-lines/branches/functions=100` (Node 22.8+; CI uses 24),
  and a test that loads every root `*.js` keeps an untested module from hiding (Node reports
  only files it loaded). Verified: 100/100/100 on the starter; an untested `Extra.js` drops it
  to 96.43% lines and fails.
- **QML tests use stand-ins, by necessity.** Ubuntu 24.04 ships Qt 6.4.2, and Quickshell needs
  Qt 6.6 or newer; even Arch's quickshell package keeps its C++ types inside the binary. So
  `tests/qml/imports/qs/Ui/` holds stand-ins for `BarWidget` (`bar`, `moduleName`, `settings`,
  `setting()`) and `WidgetButton` (`bar`, `text`, `tooltipText`, `signal pressed(int button)`,
  `triggerPress(button)`), copied from Omarchy's real components. Verified on Qt 6.4.2 in
  `ubuntu:24.04`: `Totals: 5 passed, 0 failed`.
- **Omarchy's own rules, pinned.** `scripts/omarchy-kit` sparse-clones `omacom/omarchy` at the
  commit in `.omarchy-ref` (`c668141e9c42b13c80c9ca4ea108e11708c5e8a5`, v4.0.4) into a cache
  outside the plugin (`~/.cache/omarchy-kit`, or `OMARCHY_KIT_DIR`). The guard runs its
  `bin/omarchy-plugin-validate` and `test/shell.d/qml-text-format-scan.py` on a `git ls-files`
  export: the validator refuses any symlink in the folder, and local scratch such as
  `.context/` isn't part of the plugin anyway. Verified: a Text without `textFormat`, a
  reserved `omarchy.clock` id, a version mismatch and a one-line manifest each fail.
- **One version, written twice by gstack.** Omarchy never reads a plugin's `version`
  (`omarchy plugin add` clones the default branch and `update` fast-forwards it), but the
  manifest requires one, and a drift from `VERSION` would mislead. gstack 1.91's
  `bin/gstack-version-bump` writes the version into the file named in `.gstack/package-json-path`
  as `JSON.stringify(m, null, 2) + "\n"`; the pack ships that pin pointing at `manifest.json`,
  and its guard requires the manifest's `version` to equal `VERSION` (its first three parts,
  the npm form gstack writes when `VERSION` has four) and the same 2-space form (checked with
  `jq --indent 2`, which prints manifests identically). Two `.gitignore` details:
  - In projects, the skeleton ignores `.gstack/`; the pack's `gitignore` block re-includes only
    the pin (`!/.gstack/`, `/.gstack/*`, `!/.gstack/package-json-path`, verified with
    `git check-ignore`).
  - In the template repo that same `.gstack/` rule matches the pack's `files/.gstack/` at any
    depth, so step 2 force-adds the pin (`git add -f`); a test fails if it's missing.
- **CI for new projects**: `ubuntu-24.04`, `actions/setup-node@v7` with Node 24, five apt
  packages for Qt 6's QML test runner, then `check.sh` and `tests/run`. elsewhen's equivalent
  job takes about 30 s.
- **The dev loop**: `scripts/dev-link.sh` links the checkout into
  `~/.config/omarchy/plugins/<id>`, runs `omarchy-shell shell rescanPlugins` and
  `omarchy plugin enable <id> --section right` once Omarchy lists the plugin (the rescan
  finishes in the background, so it waits as `omarchy plugin add` does); `--reload` rescans after
  an edit (Omarchy's watcher doesn't follow symlinked folders); `--unlink` runs
  `omarchy plugin remove --yes` only when the link points at this checkout, since `remove`
  deletes a cloned plugin folder outright.
- **The plugin id** is the package name (`demo_app`): the validator's
  `^[A-Za-z0-9][A-Za-z0-9._-]*$` and the directory's lowercase rule both accept it, and
  `validate-name` refuses `omarchy`. The guide says to prefix your handle before sharing.
- **A conflict the maintainer must decide, documented rather than resolved.** A plugin's
  repository root is the installed plugin folder, and the plugin directory's reviewers have
  turned plugins away for a root `AGENTS.md` (agent tools could read it inside a user's config).
  vibe-starter requires `AGENTS.md` and `CLAUDE.md` at the root. The pack keeps them, and the
  generated guide says to decide before submitting. `omarchy plugin add <url>` works either
  way. The same reviewers list `.gstack/` among the dev artifacts that get a tree blocked, and
  the pack commits `.gstack/package-json-path` (the version decision above). The directory also
  wants a root LICENSE and an `author`; the pack chooses neither.
- **Out of scope**: a release workflow (tags are informational for plugins), a host-contract
  `qmllint` job against real Quickshell in an Arch container (a follow-up), and starter code for
  the other plugin kinds.

## Current state

Verify before editing (plans 008–009 as their plan files specify):

- `bootstrap` lists packs with their `description` in `--help` and at the prompt, supports
  `includes` (009), and hides `_*` partial packs.
- `scripts/check.sh` exports `CHECK_CI` to `scripts/check.d/*.sh`.
- `scripts/template-selftest.sh` has `SELFTEST_EXCLUDE`/`SELFTEST_HEAVY`, `fresh_copy`,
  `run_bootstrap`, `tree_fingerprint`, and the tests
  `test_bootstrap_help_lists_stack_packs_with_what_they_are_for` (every non-`_` pack needs a
  `description`) and `test_stack_pack_files_carry_only_bootstrap_owned_tokens` (no `{{`/`}}`
  besides the three bootstrap tokens in pack files: keep JSON and QML braces on their own lines,
  and no `${{ }}` in the pack's workflow).
- `.github/workflows/template-selftest.yml` has the `heavy` job (ubuntu-24.04) that runs
  `./scripts/template-selftest.sh test_heavy_`, with an apt step installing
  `pkg-config libfontconfig-dev libxkbcommon-x11-dev desktop-file-utils`.
- The root `.gitignore` ignores `.gstack/` (unanchored) and `.context/`.
- The `selftest` job's `ubuntu-slim` image ships jq 1.7.1 and Python 3.12 (runner-images'
  `ubuntu-slim-Readme.md`), which three light tests need; locally they skip, named, without them.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Self-test (all but heavy) | `SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh` | baseline + 5 passed, 0 failed |
| This plan's light tests | `./scripts/template-selftest.sh omarchy_plugin` | 5 passed, 1 skipped (the heavy one) |
| The heavy test, locally | `SELFTEST_HEAVY=1 ./scripts/template-selftest.sh heavy_stack_omarchy_plugin` | 1 passed (needs Node 22.8+, jq, python3, git, the network, and Qt 6's `qmltestrunner` at `/usr/lib/qt6/bin` or `QML_TEST_RUNNER`). Verified on Linux; elsewhere a missing Qt 6 is a named skip |
| Shell lint | `shellcheck bootstrap scripts/*.sh template/stacks/*/files/scripts/*.sh template/stacks/*/files/scripts/check.d/*.sh template/stacks/*/after-bootstrap template/stacks/*/validate-name template/stacks/omarchy-plugin/files/scripts/omarchy-kit template/stacks/omarchy-plugin/files/tests/run` | exit 0 |
| JSON form | `jq --indent 2 . template/stacks/omarchy-plugin/files/manifest.json \| cmp - template/stacks/omarchy-plugin/files/manifest.json` | exit 0 |

## Scope

**In scope**: `scripts/template-selftest.sh` (step 1), `template/stacks/omarchy-plugin/`
(create, step 2), `.github/workflows/template-selftest.yml` (the `heavy` job and the shell-lint
line, step 3), `TEMPLATE.md` (step 4), `plans/README.md` (your row).

**Out of scope**: `bootstrap`, `scripts/check.sh`, the other packs, the root `.gitignore` (the
force-add avoids changing every project's ignore rules), root `AGENTS.md`/`CLAUDE.md` and
their conflict with the plugin directory (the maintainer's call), and any code that edits a
user's Omarchy config.

## Git workflow

Work on the branch you were given; commit per step; don't push or open a PR unless told to.

## Steps

### Step 1: Add the failing tests

Insert this block immediately **above** `# --- runner ---`, after plan 009's block:

```bash
# --- tests: omarchy-plugin stack pack (plan 010) -----------------------------
omarchy_plugin_project() {  # $1 = dir: a fresh copy bootstrapped as "Demo App" with omarchy-plugin
  fresh_copy "$1" || return 1
  run_bootstrap "$1" --name "Demo App" --stack omarchy-plugin --yes \
    || fail "bootstrap exited $?: $(tail -20 "$1.out")"
}
stub_omarchy_kit() {  # $1 = project dir: replace scripts/omarchy-kit with a local stand-in
  # The real one clones Omarchy (network); this kit's validator and scanner log
  # what they were given and pass, so the guard's own checks can be tested.
  mkdir -p "$1.kit/bin" "$1.kit/test/shell.d" || return 1
  cat > "$1.kit/bin/omarchy-plugin-validate" <<STUB || return 1
#!/bin/sh
ls -A "\$1" > "$1.validated"
STUB
  cat > "$1.kit/test/shell.d/qml-text-format-scan.py" <<STUB || return 1
import os, sys
top = os.path.join(sys.argv[1], "shell")
open("$1.scanned", "w").write("\n".join(sorted(os.path.relpath(os.path.join(r, f), top) for r, _, fs in os.walk(top) for f in fs)))
STUB
  printf '#!/bin/sh\necho "%s"\n' "$1.kit" > "$1/scripts/omarchy-kit"
}
test_stack_omarchy_plugin_bootstrap_installs_the_pack() {
  command -v jq >/dev/null 2>&1 || { skip "jq not installed"; return; }
  local d="$WORK/omarchy-plugin/demo-app" f s
  omarchy_plugin_project "$d" || return 1
  assert_contains "$d/manifest.json" '"id": "demo_app"' || return 1
  assert_contains "$d/manifest.json" '"name": "Demo App"' || return 1
  [ "$(jq -r .version "$d/manifest.json")" = "$(cat "$d/VERSION")" ] \
    || fail "manifest.json's version differs from VERSION" || return 1
  jq --indent 2 . "$d/manifest.json" | cmp -s - "$d/manifest.json" \
    || fail "manifest.json is not in the 2-space form gstack writes" || return 1
  assert_contains "$d/Widget.qml" 'moduleName: "demo_app"' || return 1
  assert_contains "$d/tests/qml/tst_widget.qml" 'compare(item.moduleName, "demo_app")' || return 1
  { [ -x "$d/tests/run" ] && [ -x "$d/scripts/omarchy-kit" ] && [ -x "$d/scripts/dev-link.sh" ]; } \
    || fail "the pack's scripts lost their exec bit" || return 1
  assert_contains "$d/TESTING.md" "Tests: \`./tests/run\`" || return 1
  assert_contains "$d/CLAUDE.md" "Tests: \`./tests/run\`" || return 1
  assert_contains "$d/.bootstrapped" "with the omarchy-plugin stack pack" || return 1
  for s in '{{PACKAGE_NAME}}' '{{TEST_CMD' TEMPLATE.md template/stacks template-selftest; do
    assert_tree_lacks "$d" "$s" || return 1
  done
  # The gstack pin is committed; the rest of .gstack/ stays local.
  mkdir -p "$d/.gstack" && : > "$d/.gstack/state"
  (cd "$d" && git add -A) || fail "git add failed" || return 1
  git -C "$d" ls-files --error-unmatch -- .gstack/package-json-path >/dev/null 2>&1 \
    || fail "git would not commit .gstack/package-json-path" || return 1
  git -C "$d" check-ignore -q -- .gstack/state || fail "git would commit other .gstack/ state" || return 1
  git -C "$REPO" ls-files --cached --others --exclude-standard -- template/stacks/omarchy-plugin/files \
    | sed 's|^template/stacks/omarchy-plugin/files/||' > "$d.expected" || return 1
  while IFS= read -r f; do
    git -C "$d" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || fail "git would not commit $f" || return 1
  done < "$d.expected"
}
test_stack_omarchy_plugin_rejects_the_omarchy_name() {
  local d="$WORK/omarchy-plugin-name/proj" before rc
  fresh_copy "$d" || return 1
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --name Omarchy --stack omarchy-plugin --yes; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "reserved for Omarchy's own plugins" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "the rejection changed files"
}
test_stack_omarchy_plugin_guard_keeps_version_and_manifest_in_step() {
  # Omarchy's validator sees exactly what git would commit (nothing local), and
  # VERSION, manifest.json's version and its 2-space form are held together.
  command -v jq >/dev/null 2>&1 || { skip "jq not installed"; return; }
  command -v python3 >/dev/null 2>&1 || { skip "python3 not installed"; return; }
  local d="$WORK/omarchy-plugin-guard/demo-app" rc
  omarchy_plugin_project "$d" || return 1
  stub_omarchy_kit "$d" || return 1
  (cd "$d" && git add -A && git commit -qm init) || fail "commit failed" || return 1
  mkdir -p "$d/.context" && : > "$d/.context/scratch"
  (cd "$d" && bash scripts/check.d/omarchy-plugin.sh) >"$d.guard" 2>&1 \
    || fail "the starter failed the guard: $(cat "$d.guard")" || return 1
  assert_contains "$d.validated" "manifest.json" || return 1
  assert_not_contains "$d.validated" ".context" || return 1
  assert_contains "$d.scanned" "Widget.qml" || return 1
  assert_not_contains "$d.scanned" "tst_widget.qml" || return 1
  # Same-named components in two folders are both scanned, and a link users
  # would get reaches Omarchy's validator, which refuses every symlink.
  mkdir -p "$d/bar" "$d/panel" || return 1
  : > "$d/bar/Row.qml" && : > "$d/panel/Row.qml" && ln -s missing "$d/dangling" || return 1
  (cd "$d" && git add -A && bash scripts/check.d/omarchy-plugin.sh) >"$d.guard" 2>&1 \
    || fail "the guard failed: $(cat "$d.guard")" || return 1
  assert_contains "$d.scanned" "bar/Row.qml" || return 1
  assert_contains "$d.scanned" "panel/Row.qml" || return 1
  assert_contains "$d.validated" "dangling" || return 1
  (cd "$d" && git rm -rq --cached bar panel dangling && rm -rf bar panel dangling) || return 1
  # gstack writes a four-part VERSION to manifest.json as its first three parts.
  printf '0.0.0.1\n' > "$d/VERSION"
  (cd "$d" && bash scripts/check.d/omarchy-plugin.sh) >"$d.guard" 2>&1 \
    || fail "a four-part VERSION failed the guard: $(cat "$d.guard")" || return 1
  printf '0.0.1\n' > "$d/VERSION"
  (cd "$d" && bash scripts/check.d/omarchy-plugin.sh) >"$d.guard" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard" "manifest.json has version 0.0.0 but VERSION says 0.0.1" || return 1
  (cd "$d" && git checkout -q -- VERSION && jq -c . manifest.json > m.tmp && mv m.tmp manifest.json) || return 1
  (cd "$d" && bash scripts/check.d/omarchy-plugin.sh) >"$d.guard" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard" "not in 2-space JSON form" || return 1
  # Omarchy's validator failing fails the guard, with its reason.
  (cd "$d" && git checkout -q -- manifest.json) || return 1
  printf '#!/bin/sh\necho "omarchy-plugin-validate: rejected" >&2\nexit 1\n' > "$d.kit/bin/omarchy-plugin-validate"
  (cd "$d" && bash scripts/check.d/omarchy-plugin.sh) >"$d.guard" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard" "omarchy-plugin-validate: rejected"
}
test_stack_omarchy_plugin_dev_link_links_rescans_and_enables() {
  command -v jq >/dev/null 2>&1 || { skip "jq not installed"; return; }
  local d="$WORK/omarchy-plugin-link/demo-app" home="$WORK/omarchy-plugin-link/home" rc
  omarchy_plugin_project "$d" || return 1
  mkdir -p "$d.bin" "$home" || return 1
  for tool in omarchy omarchy-shell; do
    cat > "$d.bin/$tool" <<STUB || return 1
#!/bin/sh
echo "$tool \$*" >> "$d.calls"
if [ "\$*" = "plugin list --json" ]; then echo '[{"id": "demo_app"}]'; fi
STUB
    chmod +x "$d.bin/$tool" || return 1
  done
  (cd "$d" && HOME="$home" PATH="$d.bin:$(printenv PATH)" ./scripts/dev-link.sh) >"$d.link" 2>&1 \
    || fail "dev-link exited $?: $(cat "$d.link")" || return 1
  [ -L "$home/.config/omarchy/plugins/demo_app" ] || fail "no link in the plugin folder" || return 1
  [ "$home/.config/omarchy/plugins/demo_app" -ef "$d" ] || fail "the link points elsewhere" || return 1
  # Omarchy rescans in the background, so dev-link waits until it lists the plugin.
  [ "$(cat "$d.calls")" = "$(printf 'omarchy-shell shell rescanPlugins\nomarchy plugin list --json\nomarchy plugin enable demo_app --section right')" ] \
    || fail "dev-link ran: $(cat "$d.calls")" || return 1
  (cd "$d" && HOME="$home" PATH="$d.bin:$(printenv PATH)" ./scripts/dev-link.sh --unlink) >/dev/null 2>&1 \
    || fail "--unlink failed" || return 1
  assert_contains "$d.calls" "omarchy plugin remove demo_app --yes" || return 1
  rm -f "$home/.config/omarchy/plugins/demo_app"
  mkdir -p "$home/.config/omarchy/plugins/demo_app" || return 1
  (cd "$d" && HOME="$home" PATH="$d.bin:$(printenv PATH)" ./scripts/dev-link.sh) >"$d.link" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.link" "exists and is not a link" || return 1
  # --unlink never removes a real plugin folder: Omarchy's remove would delete it.
  : > "$d.calls"
  (cd "$d" && HOME="$home" PATH="$d.bin:$(printenv PATH)" ./scripts/dev-link.sh --unlink) >"$d.link" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.link" "is not a link to this checkout" || return 1
  [ ! -s "$d.calls" ] || fail "--unlink called Omarchy: $(cat "$d.calls")"
}
test_stack_omarchy_plugin_kit_refuses_an_unpinned_ref() {
  # One pin drives every host check; a branch name would drift under CI.
  local d="$WORK/omarchy-plugin-kit/demo-app" rc
  omarchy_plugin_project "$d" || return 1
  printf 'quattro\n' > "$d/.omarchy-ref"
  (cd "$d" && OMARCHY_KIT_DIR="$WORK/omarchy-plugin-kit/cache" ./scripts/omarchy-kit) >"$d.kit" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.kit" "must be a full commit SHA" || return 1
  assert_absent "$WORK/omarchy-plugin-kit/cache"
}
omarchy_plugin_heavy_ready() {  # why the heavy plugin test can't run here; empty = run it
  if [ "${CI:-}" != "true" ] && [ "${SELFTEST_HEAVY:-}" != "1" ]; then
    echo "needs Qt 6 and the network: set SELFTEST_HEAVY=1 to run it here; CI runs it in the heavy job"
    return
  fi
  local tool
  for tool in node jq python3 git; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool not installed"; return; }
  done
  [ -x "${QML_TEST_RUNNER:-/usr/lib/qt6/bin/qmltestrunner}" ] \
    || echo "Qt 6's qmltestrunner not found (apt: qt6-declarative-dev-tools; or set QML_TEST_RUNNER)"
}
test_heavy_stack_omarchy_plugin_project_is_green() {
  # The new project's own gate, for real: Omarchy's validator and Text-format
  # scanner at .omarchy-ref (fetched), then Logic.js at 100% and the QML tests.
  local d="$WORK/heavy-omarchy-plugin/demo-app" why kit
  why="$(omarchy_plugin_heavy_ready)"
  [ -z "$why" ] || { skip "$why"; return; }
  omarchy_plugin_project "$d" || return 1
  (cd "$d" && git add -A && git commit -qm init) || fail "commit failed" || return 1
  kit="${OMARCHY_KIT_DIR:-$WORK/omarchy-kit}"
  (cd "$d" && OMARCHY_KIT_DIR="$kit" ./scripts/check.sh && ./tests/run) >"$d.gate.out" 2>&1 \
    || fail "the new project's gate failed: $(tail -30 "$d.gate.out")" || return 1
  assert_contains "$d.gate.out" "Totals: " || return 1
  # Omarchy's own scanner rejects a dynamic Text without textFormat.
  perl -0pi -e 's/  WidgetButton \{/  Text { text: root.count }\n  WidgetButton {/' "$d/Widget.qml"
  (cd "$d" && git add -A) || return 1
  if (cd "$d" && OMARCHY_KIT_DIR="$kit" bash scripts/check.d/omarchy-plugin.sh) >"$d.guard.out" 2>&1; then
    fail "a Text without textFormat passed the guard" || return 1
  fi
  assert_contains "$d.guard.out" "without textFormat"
}
```

**Verify**: `shellcheck scripts/template-selftest.sh` → exit 0.
`./scripts/template-selftest.sh omarchy_plugin` → the five light tests fail (no pack yet) and the
heavy test skips; `help_lists` still passes. Every predecessor test passes.

### Step 2: Create the omarchy-plugin pack

Create each file below with exactly this content (paths relative to
`template/stacks/omarchy-plugin/`). Then, from the repo root:

```sh
cd template/stacks/omarchy-plugin
chmod +x validate-name files/scripts/omarchy-kit files/scripts/dev-link.sh \
  files/scripts/check.d/omarchy-plugin.sh files/tests/run
cd -
# The root .gitignore's `.gstack/` matches this at any depth; force-add the pin.
git add -f template/stacks/omarchy-plugin/files/.gstack/package-json-path
```

`description`:

```text
Omarchy shell plugin (a bar widget, panel, menu or service): QML
```

`commands`:

```text
# KEY=value lines. ./bootstrap --stack omarchy-plugin replaces {{KEY}} and
# {{KEY: description}} placeholders in the project's docs with these values.
INSTALL_CMD=./scripts/dev-link.sh
DEV_CMD=./scripts/dev-link.sh --reload
BUILD_CMD=omarchy plugin validate .
CHECK_CMD=./scripts/check.sh
TEST_CMD=./tests/run
SHIP_GATE=./scripts/check.sh && ./tests/run
STACK=An Omarchy 4 shell plugin: a QML bar widget for omarchy-shell (Quickshell) built from qs.Ui components, which follow the active Omarchy theme; logic in plain JavaScript under Node's test runner at 100% coverage; the widget under Qt 6's qmltestrunner against qs.Ui stand-ins; Omarchy's own plugin validator and Text-format scanner, pinned in .omarchy-ref.
COVERAGE_ENFORCEMENT=./tests/run: Node's test runner holds the plain-JavaScript logic (Logic.js and any other *.js outside tests/) at 100% lines, branches and functions, and a test that loads every module stops one from hiding; QML has no coverage tool, so each QML component gets a qmltestrunner test; CI runs both, fail-closed
```

`gitignore`:

```text
# --- Omarchy plugin ---
# The tests use only Node's own runner; an installed package never ships.
/node_modules/
# gstack /ship keeps manifest.json's version in step with VERSION through this pin;
# commit it, and keep the rest of .gstack/ local.
!/.gstack/
/.gstack/*
!/.gstack/package-json-path
```

`validate-name`:

```sh
#!/bin/sh
# The package name becomes the plugin id. Omarchy reserves `omarchy` and the
# `omarchy.` prefix for its own plugins (a package name has no dots).
case "$1" in
  omarchy)
    echo "Plugin id '$1' is reserved for Omarchy's own plugins; choose another project name." >&2
    exit 2 ;;
esac
```

`files/.github/workflows/ci.yml`:

```yaml
# CI for {{PROJECT_NAME}} (vibe-starter omarchy-plugin stack pack): the version
# check and Omarchy's own plugin rules, then Logic.js at 100% coverage and the
# QML tests. Ubuntu 24.04's Qt 6.4 runs the widget against the qs.Ui stand-ins
# in tests/qml/imports; Omarchy itself runs Qt 6.11.
name: ci

on:
  push:
    branches: [main, master]
  pull_request:

permissions:
  contents: read

jobs:
  check-and-test:
    # Pinned, not ubuntu-latest: the apt package names below are Ubuntu 24.04's.
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v7

      - name: Install gitleaks
        uses: ./.github/actions/install-gitleaks

      - uses: actions/setup-node@v7
        with:
          node-version: "24"

      - name: Qt 6's QML test runner
        run: |
          sudo apt-get update
          sudo apt-get install -y --no-install-recommends \
            qt6-declarative-dev-tools qml6-module-qtquick qml6-module-qtquick-window \
            qml6-module-qtqml-workerscript qml6-module-qttest

      - name: Checks (guards run before tests)
        run: OMARCHY_KIT_DIR="$RUNNER_TEMP/omarchy-kit" ./scripts/check.sh

      - name: Tests (Logic.js at 100% coverage, then the QML tests)
        run: ./tests/run
```

`files/.gstack/package-json-path`:

```text
manifest.json
```

`files/.omarchy-ref`:

```text
c668141e9c42b13c80c9ca4ea108e11708c5e8a5
```

`files/DESIGN.md`:

```markdown
# Design System — {{PROJECT_NAME}}

{{PROJECT_NAME}} is an Omarchy shell plugin: it draws inside `omarchy-shell`, next to Omarchy's
own widgets, so its design system is the shell's. Build from `qs.Ui` components (`BarWidget`,
`WidgetButton`, `Panel`, `KeyboardPanel`, ...) and bind to `qs.Commons` tokens; then
`omarchy theme set` and `omarchy font set` restyle it with the rest of the desktop.

## Aesthetic
Indistinguishable from a built-in widget: the same size, font and colours as its neighbours.

## Color
Bind to the bar's colours or to `Color.*` from `qs.Commons` (`foreground`, `background`,
`accent`, `urgent`, `muted`, and surfaces such as `Color.popups.*`). Bind, never copy into a
property of your own: the shell replaces them on every theme change. No hex colours in QML.

## Typography
`Style.font.*` (`family`, `body`, `caption`, `title`, ...), which follow `omarchy font set`.
Every `Text` whose text isn't a literal sets `textFormat: Text.PlainText`: Omarchy's scanner
(run by `scripts/check.d/omarchy-plugin.sh`) and the plugin directory's reviewers require it.

## Spacing & layout
`Style.space(px)` and `Style.spacing.*`, which scale with `omarchy display text size`; bar
geometry from `Style.bar.*`. Work in both bar orientations (`vertical`).

## Motion
The shell's own; add none.

## Anti-slop rules
- No hex colours or fixed pixel sizes in QML: tokens only.
- Logic lives in `Logic.js`, plain JavaScript at 100% coverage, not in QML handlers.
- Never build a shell command from a setting: run argv lists (`Util.execArgv`), never `sh -c`.
```

`files/Logic.js`:

```js
// Pure logic for the widget, with no Qt: QML imports this file with
// `import "Logic.js" as Logic`, and the unit tests load it in Node with
// require(), where coverage is held at 100% (tests/run).

// The count stops here, so the bar button stays narrow.
var MAX_COUNT = 999

function next(count, action) {
  if (action === "reset") return 0
  if (action === "count") return Math.min(count + 1, MAX_COUNT)
  return count
}

function barText(label, count) {
  return label + " " + count
}

function tooltip(count) {
  if (count === 0) return "Not pressed yet"
  if (count === 1) return "Pressed once"
  return "Pressed " + count + " times"
}

if (typeof module !== "undefined") {
  module.exports = { MAX_COUNT: MAX_COUNT, next: next, barText: barText, tooltip: tooltip }
}
```

`files/Widget.qml`:

```qml
import QtQuick
import qs.Ui
import "Logic.js" as Logic

// The bar widget: a button that counts presses. Click counts, right-click
// resets. The bar's own button (qs.Ui) supplies colour, font and size, so the
// widget follows `omarchy theme set`; the label is this widget's setting.
BarWidget {
  id: root
  moduleName: "{{PACKAGE_NAME}}"

  property int count: 0

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Logic.barText(root.setting("label", "Pressed"), root.count)
    tooltipText: Logic.tooltip(root.count)
    onPressed: function(mouseButton) {
      root.count = Logic.next(root.count, mouseButton === Qt.RightButton ? "reset" : "count")
    }
  }
}
```

`files/docs/guides/omarchy.md`:

```markdown
# Omarchy integration

How {{PROJECT_NAME}} runs inside Omarchy 4's desktop shell, `omarchy-shell` (a Quickshell
process), where the bar, its panels and its menus are all plugins.

## Develop it

1. `./scripts/dev-link.sh` links this checkout to `~/.config/omarchy/plugins/{{PACKAGE_NAME}}`,
   rescans plugins and puts the widget on the right of the bar.
2. After an edit, `./scripts/dev-link.sh --reload`: a linked folder doesn't reload on save
   (one cloned straight into `~/.config/omarchy/plugins/` does).
3. `./scripts/dev-link.sh --unlink` takes it out of the bar and removes the link.

`omarchy dev ui-preview` shows the `qs.Ui` components you can build from, and
`$OMARCHY_PATH/shell/plugins/` holds Omarchy's own plugins to learn from.

## Test it

`./tests/run` runs `Logic.js`'s unit tests under Node, at 100% lines, branches and functions,
then `Widget.qml` under Qt 6's `qmltestrunner`, offscreen, against stand-ins for the `qs.Ui`
components it uses (`tests/qml/imports`). The stand-ins copy only what the widget uses from
Omarchy's real components; when the widget uses more, add it there, following
`$OMARCHY_PATH/shell/Ui`.

`./scripts/check.sh` runs Omarchy's own `omarchy plugin validate` rules and its Text-format
scanner, on the files git would commit, at the Omarchy commit pinned in `.omarchy-ref` (fetched
once into `~/.cache/omarchy-kit`). Bump `.omarchy-ref` on purpose, to a released Omarchy.

## Settings

`manifest.json` → `barWidget.defaults` and `barWidget.schema` declare the widget's settings
(types: string, boolean, integer with `min`/`max`, enum, multiselect, path). Omarchy's bar
settings edit them, and the widget reads them with `setting(name, fallback)`.

## Versions

`VERSION` is the version, and gstack `/ship` bumps it. `.gstack/package-json-path` points gstack
at `manifest.json`, so `/ship` writes the same version there, and the guard fails if the two
differ. Omarchy itself never reads the version: `omarchy plugin add` clones your default branch
and `omarchy plugin update` fast-forwards it, so the default branch is the release channel.

## Sharing it

- Anyone can install it: `omarchy plugin add https://github.com/<you>/<repo>.git --enable`.
  Plugins run unsandboxed in the user's desktop process, so keep the code small and readable.
- Before sharing, set `manifest.json`'s `id` to `<your-handle>.{{PACKAGE_NAME}}`: people's
  settings are keyed by it, and the owner prefix avoids collisions.
- The Omarchy plugin directory (plugins.omarchy.org) lists plugins after review. It wants an
  `author` and a `description` in `manifest.json`, a root README and LICENSE, no piped
  `curl | sh` installers, and its reviewers have turned plugins away for a root `AGENTS.md`
  (the repository is installed as the plugin folder, where agent tools could read it) and for
  dev artifacts such as `.gstack/`. This project keeps `AGENTS.md` and `CLAUDE.md` for its own
  agents and `.gstack/package-json-path` for gstack `/ship`; decide before you submit.
```

`files/manifest.json`:

```json
{
  "schemaVersion": 1,
  "id": "{{PACKAGE_NAME}}",
  "name": "{{PROJECT_NAME}}",
  "version": "0.0.0",
  "description": "{{PROJECT_NAME}}: an Omarchy bar widget that counts presses.",
  "kinds": [
    "bar-widget"
  ],
  "entryPoints": {
    "barWidget": "Widget.qml"
  },
  "barWidget": {
    "displayName": "{{PROJECT_NAME}}",
    "description": "Counts presses: click to count, right-click to reset.",
    "category": "Widgets",
    "allowMultiple": false,
    "defaultSection": "right",
    "defaults": {
      "label": "Pressed"
    },
    "schema": [
      {
        "key": "label",
        "type": "string",
        "label": "Label",
        "defaultValue": "Pressed"
      }
    ]
  }
}
```

`files/scripts/check.d/omarchy-plugin.sh`:

```bash
#!/usr/bin/env bash
# Omarchy plugin guards (from ./bootstrap --stack omarchy-plugin): VERSION and
# manifest.json in step, then Omarchy's own plugin rules at .omarchy-ref, run
# on exactly what `omarchy plugin add` would clone.
set -euo pipefail

# 1. gstack /ship bumps VERSION and, through .gstack/package-json-path, writes its
#    npm form (the first three parts) into manifest.json in its 2-space JSON form.
#    Keep both true.
version="$(tr -d '[:space:]' < VERSION | cut -d. -f1-3)"
manifest_version="$(jq -r .version manifest.json)"
if [ "$manifest_version" != "$version" ]; then
  echo "  manifest.json has version $manifest_version but VERSION says $version" >&2
  exit 1
fi
if ! jq --indent 2 . manifest.json | cmp -s - manifest.json; then
  echo "  manifest.json is not in 2-space JSON form (run: jq --indent 2 . manifest.json)" >&2
  exit 1
fi

# 2. The plugin as users get it: the files git would commit, nothing local. Links
#    stay links, so the validator sees (and refuses) them as users would get them.
kit="$(./scripts/omarchy-kit)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/plugin" "$tmp/scan/shell"
git ls-files -z --cached --others --exclude-standard \
  | while IFS= read -r -d '' f; do if [ -f "$f" ] || [ -L "$f" ]; then printf '%s\0' "$f"; fi; done \
  | tar --null -T - -cf - | tar -xf - -C "$tmp/plugin"
bash "$kit/bin/omarchy-plugin-validate" "$tmp/plugin"

# 3. Every Text whose text isn't a literal declares textFormat (Omarchy's own
#    scanner; the plugin directory's reviewers require it too). Tests are exempt;
#    paths are kept, so same-named files in two folders are both scanned.
(cd "$tmp/plugin" && find . -name '*.qml' -not -path './tests/*' -print0 | tar --null -T - -cf -) \
  | tar -xf - -C "$tmp/scan/shell"
findings="$(python3 "$kit/test/shell.d/qml-text-format-scan.py" "$tmp/scan")"
if [ -n "$findings" ]; then
  printf '%s\n' "$findings" >&2
  exit 1
fi
```

`files/scripts/dev-link.sh`:

```bash
#!/usr/bin/env bash
# Develop the plugin in place: link this checkout into Omarchy's plugin folder
# and put the widget in the bar.
#
#   ./scripts/dev-link.sh            # link, rescan, enable (right side of the bar)
#   ./scripts/dev-link.sh --reload   # rescan after an edit (a link doesn't reload on save)
#   ./scripts/dev-link.sh --unlink   # disable it and remove the link
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
cd "$(dirname "$0")/.."
id="$(jq -r .id manifest.json)"
dest="$HOME/.config/omarchy/plugins/$id"
case "${1:-}" in
  "")
    command -v omarchy >/dev/null 2>&1 || { echo "dev-link.sh: omarchy not found; this needs an Omarchy 4 desktop" >&2; exit 1; }
    if [ "$dest" -ef "$PWD" ]; then
      :  # already linked, or cloned straight into the plugin folder
    elif [ -e "$dest" ] && [ ! -L "$dest" ]; then
      echo "dev-link.sh: $dest exists and is not a link; move it aside first ('omarchy plugin remove' deletes it)" >&2
      exit 1
    else
      mkdir -p "$(dirname "$dest")"
      ln -sfn "$PWD" "$dest"
    fi
    omarchy-shell shell rescanPlugins
    # The rescan finishes in the background: wait until Omarchy lists the plugin,
    # as `omarchy plugin add` does, or enabling it fails.
    for (( attempt = 0; attempt < 40; attempt++ )); do
      omarchy plugin list --json | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null && break
      sleep 0.05
    done
    omarchy plugin enable "$id" --section right
    echo "Linked $dest -> $PWD and enabled $id." ;;
  --reload) omarchy-shell shell rescanPlugins ;;
  --unlink)
    # --yes skips Omarchy's prompt, and its remove deletes a cloned plugin
    # outright, so only ever remove this checkout's own link.
    if [ ! -L "$dest" ] || [ ! "$dest" -ef "$PWD" ]; then
      echo "dev-link.sh: $dest is not a link to this checkout" >&2
      exit 1
    fi
    omarchy plugin remove "$id" --yes ;;
  *) echo "dev-link.sh: unknown argument: $1" >&2; exit 2 ;;
esac
```

`files/scripts/omarchy-kit`:

```sh
#!/usr/bin/env bash
# Prints the path of a sparse Omarchy checkout at the commit in .omarchy-ref:
# Omarchy's own plugin validator, Text-format scanner and shell components. It
# lives outside the plugin, in a cache (OMARCHY_KIT_DIR, else
# ~/.cache/omarchy-kit), because Omarchy's validator refuses any symlink inside
# a plugin folder and Omarchy's repository has some. Needs git and, once, the
# network. Bump .omarchy-ref on purpose, to a released Omarchy commit.
set -euo pipefail
cd "$(dirname "$0")/.."
ref="$(tr -d '[:space:]' < .omarchy-ref)"
case "$ref" in
  *[!0123456789abcdef]*|'') echo "omarchy-kit: .omarchy-ref must be a full commit SHA" >&2; exit 1 ;;
esac
[ "${#ref}" -eq 40 ] || { echo "omarchy-kit: .omarchy-ref must be a full commit SHA" >&2; exit 1; }
kit="${OMARCHY_KIT_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-kit}/$ref"
if [ "$(git -C "$kit" rev-parse HEAD 2>/dev/null || true)" != "$ref" ]; then
  # Clone beside the cache and move the finished copy into place, so checks that
  # start together never delete or half-read each other's clone.
  mkdir -p "$(dirname "$kit")"
  new="$(mktemp -d "$kit.XXXXXX")"
  trap 'rm -rf "$new"' EXIT
  git clone --quiet --filter=blob:none --no-checkout https://github.com/omacom/omarchy.git "$new" >&2
  git -C "$new" sparse-checkout set --no-cone /bin/omarchy-plugin-validate \
    /test/shell.d/qml-text-format-scan.py /shell/Commons/ /shell/Ui/ >&2
  git -C "$new" -c advice.detachedHead=false checkout --quiet "$ref" >&2
  if [ "$(git -C "$kit" rev-parse HEAD 2>/dev/null || true)" != "$ref" ]; then
    rm -rf "$kit"
    mv "$new" "$kit"
  fi
fi
printf '%s\n' "$kit"
```

`files/tests/qml/imports/qs/Ui/BarWidget.qml`:

```qml
import QtQuick

// Stand-in for Omarchy's qs.Ui BarWidget ($OMARCHY_PATH/shell/Ui/BarWidget.qml):
// only the properties and function the widget uses. Keep it in step with the
// real one when you use more of it.
Item {
  property QtObject bar: null
  property string moduleName: ""
  property var settings: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
}
```

`files/tests/qml/imports/qs/Ui/WidgetButton.qml`:

```qml
import QtQuick

// Stand-in for Omarchy's qs.Ui WidgetButton ($OMARCHY_PATH/shell/Ui/WidgetButton.qml):
// the bar sets its look; tests press it through triggerPress(), as its own
// MouseArea does.
Item {
  property var bar: null
  property string text: ""
  property string tooltipText: ""

  signal pressed(int button)

  function triggerPress(button) {
    pressed(button)
  }
}
```

`files/tests/qml/imports/qs/Ui/qmldir`:

```text
module qs.Ui
BarWidget 1.0 BarWidget.qml
WidgetButton 1.0 WidgetButton.qml
```

`files/tests/qml/tst_widget.qml`:

```qml
import QtQuick
import QtTest
import "../.." as Plugin

// The real Widget.qml (TESTING.md tier 3), against stand-ins for the qs.Ui
// components it uses (tests/qml/imports), offscreen: no shell, no compositor.
TestCase {
  name: "Widget"

  Component {
    id: widget
    Plugin.Widget {}
  }

  function button(item) {
    return item.children[0]
  }

  function test_click_counts_and_right_click_resets() {
    var item = createTemporaryObject(widget, null)
    verify(item !== null, "Widget.qml loads against the qs.Ui stand-ins")
    compare(button(item).text, "Pressed 0")
    button(item).triggerPress(Qt.LeftButton)
    button(item).triggerPress(Qt.LeftButton)
    compare(item.count, 2)
    compare(button(item).text, "Pressed 2")
    compare(button(item).tooltipText, "Pressed 2 times")
    button(item).triggerPress(Qt.RightButton)
    compare(item.count, 0)
  }

  function test_the_label_comes_from_the_widget_settings() {
    var item = createTemporaryObject(widget, null, { settings: { label: "Taps" } })
    compare(button(item).text, "Taps 0")
  }

  function test_the_widget_reports_its_module_name() {
    var item = createTemporaryObject(widget, null)
    compare(item.moduleName, "{{PACKAGE_NAME}}")
  }
}
```

`files/tests/run`:

```sh
#!/usr/bin/env bash
# The test gate: Logic.js under Node at 100% lines, branches and functions, then
# the QML tests under Qt 6's qmltestrunner, offscreen. Fails closed: a missing
# tool, an old Node, a Qt 5 runner or zero QML tests is a failure, not a skip.
set -euo pipefail
cd "$(dirname "$0")/.."

node_version="$(node -p process.versions.node 2>/dev/null)" \
  || { echo "tests/run: Node 22.8 or newer is required" >&2; exit 1; }
major="${node_version%%.*}"
minor="${node_version#*.}"
minor="${minor%%.*}"
if [ "$major" -lt 22 ] || { [ "$major" -eq 22 ] && [ "$minor" -lt 8 ]; }; then
  echo "tests/run: Node 22.8 or newer is required (coverage thresholds)" >&2
  exit 1
fi
node --test --experimental-test-coverage \
  --test-coverage-include='**/*.js' --test-coverage-exclude='tests/**' \
  --test-coverage-lines=100 --test-coverage-branches=100 --test-coverage-functions=100 \
  'tests/unit/*.test.js'

# Arch's /usr/bin/qmltestrunner is Qt 5's and runs nothing; Qt 6 keeps its own.
runner="${QML_TEST_RUNNER:-/usr/lib/qt6/bin/qmltestrunner}"
[ -x "$runner" ] || { echo "tests/run: Qt 6 qmltestrunner not found at $runner (set QML_TEST_RUNNER)" >&2; exit 1; }
out="$(QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  "$runner" -import tests/qml/imports -input tests/qml -o -,txt 2>&1)" || { printf '%s\n' "$out"; exit 1; }
printf '%s\n' "$out"
# Here-strings, not pipes: grep -q stops reading early, which pipefail would turn
# into a failure once the output outgrows the pipe.
grep -q 'Using QtTest library 6\.' <<<"$out" || { echo "tests/run: not a Qt 6 runner" >&2; exit 1; }
grep -Eq '^Totals: [0-9]+ passed, 0 failed' <<<"$out" || { echo "tests/run: QML tests failed" >&2; exit 1; }
# QtTest counts initTestCase and cleanupTestCase as passes: require a real test.
grep -Eq '^PASS +: .*::test_' <<<"$out" || { echo "tests/run: no QML tests ran" >&2; exit 1; }
```

`files/tests/unit/all-modules.test.js`:

```js
// Loads every logic module outside tests/, so none can hide from the coverage
// gate: Node reports only files that were loaded.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.join(__dirname, "..", "..")

function modules(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(dir, entry.name)
    if (!entry.isDirectory()) return entry.name.endsWith(".js") ? [file] : []
    const skip = entry.name.startsWith(".") || entry.name === "node_modules" || file === path.join(root, "tests")
    return skip ? [] : modules(file)
  })
}

test("every *.js module outside tests/ loads under Node", () => {
  const found = modules(root)
  assert.ok(found.length > 0, "found no logic modules")
  for (const file of found) assert.equal(typeof require(file), "object", path.relative(root, file))
})
```

`files/tests/unit/logic.test.js`:

```js
// Pure-logic tests (TESTING.md tier 1): every rule in Logic.js.
const test = require("node:test")
const assert = require("node:assert/strict")
const Logic = require("../../Logic.js")

test("a click counts and a right-click resets", () => {
  assert.equal(Logic.next(0, "count"), 1)
  assert.equal(Logic.next(41, "count"), 42)
  assert.equal(Logic.next(42, "reset"), 0)
})

test("the count stops at MAX_COUNT instead of growing the button", () => {
  assert.equal(Logic.next(Logic.MAX_COUNT, "count"), Logic.MAX_COUNT)
})

test("an unknown action leaves the count alone", () => {
  assert.equal(Logic.next(7, "wheel"), 7)
})

test("the bar text is the label and the count", () => {
  assert.equal(Logic.barText("Pressed", 3), "Pressed 3")
})

test("the tooltip says how many presses", () => {
  assert.equal(Logic.tooltip(0), "Not pressed yet")
  assert.equal(Logic.tooltip(1), "Pressed once")
  assert.equal(Logic.tooltip(2), "Pressed 2 times")
})
```

**Verify**: shell lint and the JSON-form command → exit 0.
`git ls-files template/stacks/omarchy-plugin/files/.gstack` prints the pin.
`./scripts/template-selftest.sh omarchy_plugin` → 5 passed, 1 skipped;
`./scripts/template-selftest.sh help_lists` and `carry_only` → pass; `./bootstrap --help` lists
`omarchy-plugin`.

### Step 3: Give the heavy job Node and Qt 6

In `.github/workflows/template-selftest.yml`:

1. In the `heavy` job, extend the apt install line with the QML test runner's packages:

   ```yaml
               pkg-config libfontconfig-dev libxkbcommon-x11-dev desktop-file-utils \
               qt6-declarative-dev-tools qml6-module-qtquick qml6-module-qtquick-window \
               qml6-module-qtqml-workerscript qml6-module-qttest
   ```

   and add, directly after that step:

   ```yaml
         - name: Node for the omarchy-plugin tests
           uses: actions/setup-node@v7
           with:
             node-version: "24"
   ```

2. In the `selftest` job's shell-lint step, append the plugin's two extensionless scripts:
   ` template/stacks/omarchy-plugin/files/scripts/omarchy-kit template/stacks/omarchy-plugin/files/tests/run`.

The heavy test clones Omarchy (sparse, blob-filtered) each run; it took seconds while planning.

**Verify**: `ruby -ryaml -e 'ARGV.each(&YAML.method(:load_file))' .github/workflows/template-selftest.yml template/stacks/omarchy-plugin/files/.github/workflows/ci.yml` → exit 0.

### Step 4: Document the pack in `TEMPLATE.md`

1. Add a row to the "Omarchy apps: choose by what the app should do" table:

   ```markdown
   | live inside the desktop itself: a bar widget, a panel, a menu, an overlay, a background service | `omarchy-plugin` | QML plugin for Omarchy 4's `omarchy-shell`, logic in plain JavaScript |
   ```

2. Extend the "Available:" paragraph with `omarchy-plugin` (an Omarchy 4 shell plugin: a QML
   bar widget, JavaScript logic at 100% coverage, Omarchy's own validator pinned).
3. After the paragraph that follows the table (the one about exact pins), add: "A plugin's
   repository root is the folder users install. Omarchy's plugin directory has turned plugins
   away for a root `AGENTS.md` or a committed `.gstack/`; the generated guide explains the
   choice."
4. In `### Verifying a change`, add the plugin's two extensionless scripts to the `shellcheck`
   command (as step 3 did for CI), and extend the heavy-tests paragraph: "The omarchy-plugin heavy
   test also needs Node 22.8+ and a Qt 6 `qmltestrunner` (`QML_TEST_RUNNER`)."

**Verify**: `grep -c 'omarchy-plugin' TEMPLATE.md` → at least `2`.

### Step 5: Full verification and a manual look

```sh
SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh          # baseline + 5 passed, 0 failed
./scripts/check.sh                                                   # exit 0
```

Name any local skips; zero skips is required in the `selftest` CI job.

With Node 22.8+, jq, python3 and a Qt 6 `qmltestrunner` (set `QML_TEST_RUNNER` if it isn't at
`/usr/lib/qt6/bin`), run `SELFTEST_HEAVY=1 ./scripts/template-selftest.sh
heavy_stack_omarchy_plugin`; otherwise the `heavy` CI job must pass before this plan counts as
done.

Then, on an Omarchy 4 machine if you have one: bootstrap a scratch clone with
`--stack omarchy-plugin`, run `./scripts/dev-link.sh`, and check that "Pressed 0" appears on the
right of the bar, that clicks count and a right-click resets, and that `omarchy theme set` restyles
it. Report whether you could; it is not required.

## Test plan

Six new test functions:

- `test_stack_omarchy_plugin_bootstrap_installs_the_pack`: the manifest is filled, equal to
  `VERSION` and in 2-space form; the widget and its test carry the id; scripts are executable;
  commands are filled; no placeholders or template paths are left; git commits every pack file
  and the gstack pin, and ignores the rest of `.gstack/`.
- `test_stack_omarchy_plugin_rejects_the_omarchy_name`: exit 2, nothing changed.
- `test_stack_omarchy_plugin_guard_keeps_version_and_manifest_in_step`: with a stubbed kit, the
  validator sees exactly the committable files (no `.context/`, links kept), the scanner sees the
  widget and same-named files in two folders but not the tests, a four-part VERSION matches its
  npm form, and a version drift, a one-line manifest or a failing validator fails.
- `test_stack_omarchy_plugin_dev_link_links_rescans_and_enables`: stubbed `omarchy` and
  `omarchy-shell`: the link, the rescan, the wait until Omarchy lists the plugin and the enable
  (right section), `--unlink --yes`, and refusing a real folder in the way, for both.
- `test_stack_omarchy_plugin_kit_refuses_an_unpinned_ref`: a branch name in `.omarchy-ref` exits
  1 and clones nothing.
- `test_heavy_stack_omarchy_plugin_project_is_green` (heavy job): the project's own `check.sh`
  (real Omarchy kit) and `tests/run`, then a Text without `textFormat` fails the guard.

Rehearsed while planning: the light tests on macOS bash 3.2 and the heavy test in `ubuntu:24.04`
with Qt 6.4.2 and Node 24.21.

## Done criteria

ALL must hold:

- [ ] `SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh` → baseline + 5 passed, 0 failed; local skips named; the `selftest` CI job has 0 skipped
- [ ] The heavy test passed, locally or in the `heavy` CI job (say which)
- [ ] Shell lint, YAML and JSON-form commands exit 0; `./scripts/check.sh` exits 0
- [ ] `git ls-files template/stacks/omarchy-plugin/files/.gstack/package-json-path` prints the path
- [ ] `git status --porcelain` shows only in-scope paths; `plans/README.md` row updated

## STOP conditions

Stop and report back (do not improvise) if:

- A contract under "Current state" differs, or a plan 006–009 test fails.
- Omarchy's validator or scanner at `.omarchy-ref` rejects the starter, or the QML test fails
  on the runner's Qt: report the output; don't weaken the guard or the stand-ins' fidelity.
- `jq --indent 2` and gstack disagree on the manifest's form (e.g. after a gstack upgrade):
  report both outputs.
- You'd need to remove `AGENTS.md`/`CLAUDE.md` from generated plugins, add a LICENSE, or change
  the root `.gitignore`: those are the maintainer's decisions.

## Maintenance notes

- **Bumping Omarchy**: set `.omarchy-ref` in the pack to a newer released commit, re-run the
  heavy test, and diff `shell/Ui/BarWidget.qml` and `shell/Ui/WidgetButton.qml` against the
  stand-ins in `tests/qml/imports/qs/Ui/`.
- **Stand-in drift** is the known weakness: a follow-up can add a scheduled `host-contract` job
  that runs `qmllint` against real Quickshell in a digest-pinned Arch container (as
  `yordanbuilds/rig` and `stateset-omarchy-plugin` do).
- **Qt versions**: the runner's Qt 6.4 lacks 6.5+ features (`QtQuick.Effects`, newer pragmas)
  that Omarchy's Qt 6.11 has; keep them out of components the tests load, or move CI to an Arch
  container. `ubuntu-latest` becomes 26.04 (Qt 6.10) in November 2026; the pack pins 24.04.
- **gstack**: `/ship`'s evidence check allow-lists `package.json` but not `manifest.json`, so
  each ship re-runs the tests once. That's harmless.
- **Marketplace**: approval is tied to an exact commit. Its security baseline flags `curl | sh`,
  `sudo`, package-manager calls and unpinned installs; keep them out of the README and scripts.
- Reviewer focus: the guard's export (what `omarchy plugin add` would clone); the kit's pinning
  and cache location; the stand-ins' fidelity to Omarchy's components; the `.gitignore`
  re-include and the force-add.
