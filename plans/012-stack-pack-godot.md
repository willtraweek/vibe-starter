# Plan 012: Add the `godot` stack pack (a game in Godot 4.7, typed GDScript)

> **Record, not instructions.** This plan was written while the pack was built, at the
> maintainer's request ("Add a godot related option to vibe-starter for games", 2026-10-30), so it
> records decisions and evidence rather than steps for an executor. Its maintenance notes are the
> part to follow later.

## Status

- **Priority**: P2 (requested by the maintainer)
- **Effort**: L
- **Risk**: MED. It brings a new language (GDScript) and an engine binary into the template, and
  the new project's tooling downloads Godot and GDScript Formatter from GitHub at pinned sums. It
  changes no `bootstrap` code; the skeleton's `.editorconfig` gains a `[*.gd]` tab rule.
- **Depends on**: 006 (the pack mechanism), 008 (pack descriptions, `CHECK_CI`, the `heavy` job)
- **Category**: direction
- **Built at**: commit `94bb406`, 2026-10-30

## Why this matters

Packs are chosen by what the project should do, and none built games. Godot is the open-source
engine most games outside the big commercial engines are made in. A game also tests the
template's doctrine harder than an app: there is a scene tree, a frame loop and input, and Godot
ships no test runner or coverage tool, so the tiers in `TESTING.md` need tooling of their own.

## Design decisions (each verified while building)

1. **Godot 4.7.2, typed GDScript.** 4.7.2 (2026-08-18) is the latest stable; 4.8 is at beta 2.
   GDScript is Godot's own language: no .NET SDK, and it exports to every platform. Every GDScript
   warning is set to an error in `project.godot`, including `untyped_declaration` and the
   `unsafe_*` family, so Godot's analyzer is the type checker. Godot wrote that file itself
   (`ProjectSettings.save()`), so the editor does not rewrite it on first open. Loading a script
   with a warning fails (`can_instantiate()` is false), which `run.gd --check-only` uses.
2. **GDScript Formatter 0.27.0 (GDQuest), not gdtoolkit.** gdtoolkit's last release is 4.5.0
   (2025-10). GDQuest's formatter is a single Rust binary with a linter, released monthly; 0.27.0
   (2026-09-25) rather than 0.28.0, released the day this was built. It reads `.editorconfig`,
   whose `[*]` rule says two spaces, so the skeleton gains `[*.gd]` with tabs (GDScript's style).
3. **A pinned kit, not a setup action.** `scripts/godot-kit.sh` downloads Godot from
   `godotengine/godot-builds` and the formatter from its releases, checks the SHA-512 sums from
   Godot's `SHA512-SUMS.txt` and the SHA-256 digests GitHub records for the formatter, and
   publishes into a cache with one rename (the omarchy-kit pattern). It accepts any copy that
   reports the pinned version (`GODOT_BIN`, the cache, `PATH`), so a Homebrew or Steam Godot 4.7.2
   is used as is; a wrong `GODOT_BIN` or cached copy is refused, never passed over.
4. **A test runner in the project, not GUT or gdUnit4.** Both are addons under `addons/`, which
   the 5,000-token cap does not exempt (20 of GUT 9.7.1's files are over it, `test.gd` five times
   over), so they would have to be fetched at install time like `node_modules`. `tools/test/run.gd` is about 250
   lines: it runs each `test_*` method on a fresh `TestCase`, at a fixed 60 fps
   (`--fixed-fps 60`: each tick is exactly 1/60 s and 120 ticks take a few milliseconds). Godot's
   `OS.add_logger()` lets it fail a test on any error Godot reports, including runtime
   script errors that GDScript otherwise prints and moves past. `Engine.capture_script_backtraces()`
   names the failing line without a debugger. A watchdog quits the run: a `-s` script that errors
   before `quit()` keeps Godot running forever.
5. **Coverage by instrumenting a mirror.** `scripts/coverage.sh` links the project into a
   temporary mirror and writes instrumented copies of the scripts under `src/` into it: each
   statement gets `preload("res://tools/coverage/probe.gd").hit(N); ` in front of it on the same
   line, so line numbers stay right. Recompiling scripts in memory instead (`take_over_path`) was
   tried and rejected: a subclass compiled before its parent keeps the uninstrumented parent. A
   branch is an arm of an `if` chain or a `match`; the arm with no code of its own (no `else`, no
   catch-all pattern) counts as taken whenever the `if` or `match` line ran more often than its
   arms did. The gate holds 90% of lines and branches overall and each tier of
   `coverage-tiers.json`, requires every named journey to pass, and ratchets on pull requests,
   matching the python pack's rules (`retired`, `allow_empty`).
6. **The build exports the data pack.** `--export-pack` needs no export templates (about 1.3 GB);
   `scripts/build.sh` then starts the `.pck` headless for 60 frames and fails on any error, which
   catches a scene or script the export filter dropped. Native executables are documented, not
   gated.
7. **No `validate-name` or `after-bootstrap`.** The project name appears only as a string
   (`config/name`) and the package name only in file names, so no name breaks the pack, and there
   is nothing to lock.

## What shipped

- `template/stacks/godot/`: `description`, `commands`, `gitignore`, and `files/`:
  `project.godot`, `export_presets.cfg`, `icon.svg` (+ `.import`), `coverage-tiers.json`, the
  starter (`src/logic/` arena, orb spawner and score; `src/scenes/` main, player and orb;
  `src/style.gd` tokens), its tests (`tests/unit`, `tests/scenes`, one journey), `tools/test`,
  `tools/coverage`, `scripts/` (kit, godot, import, test, format, coverage, build,
  `check.d/godot.sh`), CI, `DESIGN.md` and `docs/guides/godot.md`. Every script has its `.uid`.
- `.editorconfig`: `[*.gd]` with tabs. `TEMPLATE.md`: the pack, a games table, maintenance notes.
- `scripts/template-selftest.sh`: 7 light and 5 heavy tests (below).

## Tests

Light: bootstrap installs the pack (names, exec bits, placeholders, committed and ignored paths);
the kit's pins agree with every doc; the kit accepts only pinned versions; a download that fails
its sum is refused and leaves nothing; the guard skips missing tools locally and fails in CI; the
guard keeps colours in the style tokens; the guard keeps typed GDScript and the engine pin.

Heavy (real Godot): the new project's whole gate passes and leaves the tree clean; the runner fails
each way a test can go wrong; the guard refuses untyped and unformatted code; the coverage tool's
exact counts on a fixture of awkward constructs (lcov record compared line for line); tiers,
journeys and the ratchet.

## Verification (2026-10-30, macOS 27 arm64, Godot 4.7.2 from Homebrew)

- The starter: 15 tests pass; coverage 41/41 lines and 6/6 branches; the export boots; `git
  status` is clean after `check.sh`, `test.sh`, `coverage.sh` and `build.sh`.
- The fixture's counts were checked by hand against the code paths the test takes: 47 lines (42
  run) and 13 branch arms (8 taken).
- ShellCheck 0.11.0 (CI's command) passes. Hosted CI evidence is in the pull request.

## Maintenance

- **Bump Godot**: set `GODOT_VERSION` and all three `GODOT_SHA512_*` sums in
  `files/scripts/godot-kit.sh` from the release's `SHA512-SUMS.txt`; for a new minor version, also
  the `"4.7"` that starts `config/features` in `files/project.godot` and the versions the
  description, `STACK`, the guide and `TEMPLATE.md` name (`test_stack_godot_kit_pins_agree_everywhere`
  lists them). Run the heavy tests: a new Godot may write different `.uid`, `.import` or scene
  files, and `test_heavy_stack_godot_project_is_green` fails on any change git sees.
- **Bump the formatter**: `FORMATTER_VERSION` and the four `FORMATTER_SHA256_*` digests together
  (`gh api repos/GDQuest/GDScript-formatter/releases/tags/<v>` shows them). If it formats
  differently, reformat the starter and the coverage fixture in the heavy test, whose line numbers
  follow the formatter's output.
- **New starter scripts or assets**: let Godot write their `.uid` and `.import` files (import a
  copy of the pack, then copy them back), and add each script to a tier.

## Out of scope

C# (.NET) projects, export templates and native builds in CI, Windows shells (the scripts are
bash; `GODOT_BIN` and `GDSCRIPT_FORMATTER_BIN` let Git Bash or WSL use your own copies), and
measuring lambdas passed in parentheses or class-level initializers.
