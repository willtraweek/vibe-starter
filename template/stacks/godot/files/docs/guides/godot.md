# Working on {{PROJECT_NAME}} in Godot

{{PROJECT_NAME}} is a Godot 4.7 game in typed GDScript, started from vibe-starter's `godot`
stack pack. This guide covers where things go, how the tests and the coverage gate work,
and how to export the game.

## Commands

| Run | To |
|---|---|
| `./scripts/godot-kit.sh` | install the pinned Godot and GDScript Formatter, if missing |
| `./scripts/godot.sh` | play the game (`./scripts/godot.sh --editor` opens the editor) |
| `./scripts/test.sh [filter]` | run the tests, or those whose `path::method` contains the filter |
| `./scripts/format.sh` | format and lint every GDScript file |
| `./scripts/check.sh` | the checks, before the tests |
| `./scripts/coverage.sh` | every test under the coverage gate: what CI runs |
| `./scripts/build.sh` | export `build/{{PACKAGE_NAME}}.pck` and start it headless |

Every script finds Godot through `./scripts/godot-kit.sh`, which only accepts the pinned
version: `GODOT_BIN`, then its cache, then `godot` on `PATH`. The scripts are bash: on Windows,
run them in Git Bash or WSL, with `GODOT_BIN` and `GDSCRIPT_FORMATTER_BIN` naming your own copies
of the pinned versions. The tests run headless at a
fixed 60 frames a second, so each physics tick is exactly 1/60 s and runs as fast as the
machine allows.

## Where things go

- `src/logic/`: the rules, as plain classes (`extends RefCounted`) with no nodes. They are
  quick to test, and their tier holds them at 100% of lines and branches.
- `src/scenes/`: scenes and their node scripts. Keep these thin: read input, call the rules,
  move nodes, show the result. Their tier holds them at 90%.
- `src/style.gd`: every colour and size (DESIGN.md). Nothing else names a colour.
- `tests/unit/`, `tests/scenes/`, `tests/journeys/`: the tests for each tier. A journey is a
  whole play-through that must never break, named in `coverage-tiers.json`.
- `tools/`: the test runner and the coverage tool, part of the project. Exports leave
  `tests/` and `tools/` out (`export_presets.cfg`).

Give a script used from elsewhere a `class_name`. Commit the `.uid` file Godot writes next
to each script, and the `.import` file next to each asset; `.godot/` is a cache, never
committed. `./scripts/import.sh` (run first by every other script) rebuilds it, so after a
fresh clone or a new `class_name`, nothing else is needed.

## Writing tests

A test file is `tests/**/test_*.gd` and `extends TestCase`; each method whose name starts
with `test_` is a test, run on a fresh instance. It may `await`. `before_each()` and
`after_each()` run around each test. From `tools/test/test_case.gd`:

- `assert_eq`, `assert_ne`, `assert_true`, `assert_false`, `assert_null`, `assert_not_null`,
  `assert_almost_eq` (numbers, `Vector2`, `Vector3`), `assert_has`, and `fail(reason)`.
  `assert_eq` compares type and value: `1` equals `1.0`, but `1` never equals `"1"`.
- `add(node)` and `add_scene(packed)` put nodes in the tree for one test, and free them after.
- `frames(n)` and `physics_frames(n)` wait; `press(action)` and `release(action)` hold
  input actions like a player, all released after the test.
- `watch(object, &"signal")` records each emission's arguments in `.emissions`.
- `expect_error("text")` expects an error containing that text.

A test fails on a failed assertion, on any error Godot reports while it runs (a
`push_error`, a failed engine check, a script error), on a node it leaves outside the tree,
and when it runs longer than 30 seconds (`./scripts/test.sh --timeout <ms>` changes that). A
run with no tests fails. Test a scene through
its public methods (the starter's `Main.step()`), and its input through `press()`;
calling another object's `_private` method fails the lint.

## The coverage gate

`./scripts/coverage.sh` copies the project into a temporary mirror whose scripts under
`src/` are instrumented: each statement gets a probe call in front of it, on its own line,
so line numbers in errors stay right. It runs every test there, then
`tools/coverage/report.gd` checks the counts:

- at least 90% of lines and 90% of branches overall;
- each tier in `coverage-tiers.json` at its `minimum`, for lines and for branches, where a
  member must name an existing script (a renamed one goes in the tier's `retired` list);
- each journey listed under `journeys` ran and passed, and every test under
  `tests/journeys/` is listed.

A line is a statement in a function, a property accessor or a lambda. A branch is an arm of
an `if` chain or a `match`; a chain without `else`, and a `match` without a catch-all
pattern, has one more arm: it ran when none of the others did. The tool does not see code
in a class-level initializer or inside a lambda passed in parentheses, and it never
measures `tests/`, `tools/` or `addons/`. `coverage/lcov.info` feeds editor coverage views.

On pull requests, CI also runs `./scripts/coverage.sh --ratchet origin/<base>`: a tier's
minimum and target never fall, and a member never leaves its tier unless it is listed in
`retired`. Raise a minimum when tests reach it; do not lower one to pass.

## Typed GDScript

`project.godot` makes every GDScript warning an error, including the typing ones
(`untyped_declaration`, `unsafe_*`): give every variable, parameter and return a type, and
cast a `Variant` by assigning it to a typed variable. Godot's analyzer is the type checker,
and `scripts/check.d/godot.sh` fails if the typing warnings stop being errors. Turning
another warning off is a decision: note it in ENGINEERING.md's Decisions Log.

## Exporting the game

`./scripts/build.sh` exports only the data pack, which needs no export templates, and starts
it to prove the export kept what the game needs. To ship an executable, install Godot's
export templates for 4.7.2 once (in the editor: Editor > Manage Export Templates), add a
preset for each platform (Project > Export), then:

```sh
./scripts/godot.sh --headless --export-release "Linux" build/{{PACKAGE_NAME}}.x86_64
```

Keep `tests/*, tools/*` in each preset's exclude filter.

## Updating Godot or GDScript Formatter

Bump the pins in `scripts/godot-kit.sh` on purpose, each version with all of its sums:
Godot's SHA-512 sums come from the release's `SHA512-SUMS.txt`, the formatter's SHA-256 sums
from its release assets on GitHub. For a new Godot minor version, change the `"4.7"` that
starts `config/features` in `project.godot` too. Then run `./scripts/godot-kit.sh` and the
whole gate.
