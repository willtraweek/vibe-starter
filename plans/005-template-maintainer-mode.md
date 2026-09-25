# Plan 005: Separate the template's own VERSION, CHANGELOG and TODOS from the new-project skeletons, so gstack `/ship` can run on the template safely

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 1984ab7..HEAD -- VERSION CHANGELOG.md TODOS.md`
> A change here is only expected if someone already ran gstack `/ship` on this repo. Step 3
> handles that case explicitly. Plans 001–004 (dependencies) legitimately changed `bootstrap`,
> `AGENTS.md`, `CLAUDE.md`, `README.md`, `TESTING.md`, `TEMPLATE.md` and `scripts/`. Compare those
> against the post-004 excerpts below.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED. It changes which files a new project receives. It is guarded by 10 new tests, including retry and malformed-input regressions.
- **Depends on**: 001, 002, 003, 004 (all edit the same files. 004 put `AGENTS.md`/`CLAUDE.md`/`TESTING.md`
  in the shape this plan extends.)
- **Category**: tech-debt
- **Planned at**: commit `1984ab7`, 2026-09-23

## Why this matters

In this repo, the root `VERSION`, `CHANGELOG.md` and `TODOS.md` are **skeletons**: the blank
copies every new project starts from. The maintainer ships with gstack `/ship`, and
`CLAUDE.md` says never to hand-roll a ship. Facts verified in gstack 1.87.5.0 while planning:

- `/ship` step 12 **always bumps the root `VERSION`**. A 3-part `0.0.0` stays 3-part and
  becomes `0.0.1`. There is no config key, environment variable or marker file to opt out.
  `.gstack/version-path` only moves the file, the template's own `.gitignore` ignores `.gstack/`,
  and several gstack consumers read the root `VERSION` regardless.
- `/ship` step 13 **writes a `CHANGELOG.md` entry**. Step 14 **checks `TODOS.md` against
  gstack's TODOS format** (items under `## <Component>` headings, a `**Priority:** P0–P4` per
  item, `## Completed` last) and asks to "Reorganize now (recommended)" when it doesn't match.
  The skeleton's `High priority / Backlog / Wishlist / Known issues` checklist doesn't match, so
  the first `/ship` of *every new project* nags too.
- `/ship` needs a documented test command. Native Claude skills read `CLAUDE.md`/`TESTING.md`;
  Codex-generated skills read `AGENTS.md`/`TESTING.md`. Shared `TESTING.md` works for both. Without one, it asks what language the project is and doesn't run
  the self-test.
- `/document-release` (which `/ship` runs as a subagent) audits every `*.md` at most two levels
  deep (`find . -maxdepth 2 -name "*.md"`). It auto-applies "factual" fixes, and inside `/ship`
  it auto-picks the recommended option.

So the next `/ship` of this repo, including the one that ships these plans, writes the
template's version and history into files every future project inherits. After this plan:

- The root `VERSION`/`CHANGELOG.md`/`TODOS.md` belong to the template, and gstack maintains them
  freely.
- The skeleton copies live in `template/skeleton/`, three levels deep and out of
  `/document-release`'s reach. `./bootstrap` swaps them in and records which template version
  the project came from.
- A template-only block tells agents and `/ship` how to test the template. `./bootstrap` strips
  that block from new projects.
- A golden test fails if a doc tool fills in or drops a skeleton placeholder.

## Current state

Root files today (skeletons; unchanged since `1984ab7` unless someone ran `/ship`):

`VERSION`: `0.0.0`

`CHANGELOG.md` (15 lines):

```markdown
# Changelog

All notable changes to {{PROJECT_NAME}} are recorded here. Newest first, semver sections.

## [Unreleased]

### Added
- Initial scaffold from the vibe-starter template.

<!--
## [0.1.0] - {{YEAR}}-MM-DD
### Added
### Changed
### Fixed
-->
```

`TODOS.md` (19 lines): `# TODOs`, the `{{PROJECT_NAME}}` intro line, then
`## High priority` (with `- [ ] {{FIRST_TASK: the first real thing to build.}}`), and
`## Backlog`, `## Wishlist`, `## Known issues` (each with an empty `-` bullet).

After plans 001–004:

- `AGENTS.md` starts with `# Agents working on {{PROJECT_NAME}}`, followed by its operating
  protocol. `CLAUDE.md` retains the project tagline, architecture, Commands and exact
  `## Skill routing` heading. Each file requires reading the other in full once per task;
  preserve that reciprocal reading requirement and the split ownership from revised plan 004.
- `TESTING.md` has a `## Commands` section (from plan 004) ending with:

  ```markdown
  - Checks (guards that run before tests): `{{CHECK_CMD}}`
  - Tests: `{{TEST_CMD}}`
  ```

  followed by a blank line and `## Why Tiers, Not One Number`.
- `bootstrap` contains, in order: the header comment; the re-entry guard; `# --- Parse args`;
  `# --- Refuse to personalize the template itself`; `# --- Project name` (ending with
  `YEAR="$(date +%Y)"` and `echo "Personalizing template -> name='$NAME', year='$YEAR'"`);
  `# --- Replace bootstrap-owned placeholders` (ending `echo "Replaced {{PROJECT_NAME}} / {{YEAR}} across the docs."`
  and `fi`); `# --- git init`; the gstack block; the checklist; and `# --- Finalize`,
  which contains:

  ```bash
  TEMPLATE_ONLY="TEMPLATE.md scripts/template-selftest.sh .github/workflows/template-selftest.yml plans"
  date +%Y-%m-%d > .bootstrapped
  for p in $TEMPLATE_ONLY; do rm -rf "$p"; done
  ```

  The header comment's last lines (from plans 001/003) read:

  ```bash
  # placeholders you still need to hand-fill, then deletes itself and the
  # template-only paths (TEMPLATE.md, the template self-test, plans/).
  ```

- `TEMPLATE.md` ends with the `## Maintaining the template` section from plan 001. Line 23
  reads ``- `README.md`, `CHANGELOG.md`, `TODOS.md`, `VERSION`, `docs/`, `.context/` — working scaffold.``
- `scripts/template-selftest.sh` has 80 tests (74 before revised plan 004, plus its six). Plan 001's
  `test_bootstrap_removes_template_only_paths` contains the line
  `assert_absent "$d/plans" || return 1`. The runner section starts at
  `# --- runner ---`, and `FILTER="${1:-}"` is set near the top.

gstack's TODOS format (from gstack's `review/TODOS-format.md`): `# TODOS`, then `## <Component>`
groups, each item an `### <Title>` with `**What:**`, `**Why:**`, `**Context:**`, `**Effort:**`,
`**Priority:** P0–P4`, `**Depends on:**`, and a `## Completed` section at the bottom.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Self-test | `./scripts/template-selftest.sh` | `selftest: 90 passed, 0 failed, 0 skipped` (80 + 10 new) |
| Print the placeholder inventory | `./scripts/template-selftest.sh --print-inventory` | the 14-line list in step 7 |
| Guard | `./scripts/check.sh` | exit 0 |
| Shell lint | `shellcheck bootstrap scripts/check.sh scripts/template-selftest.sh` | exit 0 |

## Suggested executor toolkit

- gstack `/review` on the finished diff.
- Do **not** run `/ship` or `/document-release` before implementing and validating this plan.
  After its checks and tests pass, use `/ship` when the operator requests shipping; do not
  require this PR to be merged before it can be shipped.

## Scope

**In scope** (the only files you should modify):

- `template/skeleton/VERSION`, `template/skeleton/CHANGELOG.md`, `template/skeleton/TODOS.md` (create)
- `CHANGELOG.md`, `TODOS.md` (rewrite as the template's own; `VERSION` keeps its value)
- `AGENTS.md`, `TESTING.md` (insert one template-only block each; nothing else)
- `bootstrap` (header comment, marker preflight and retry-safe swap after the `Personalizing` echo, one new block
  after the placeholder-replacement block, and two lines in Finalize)
- `TEMPLATE.md` (line 23, and replace the `## Maintaining the template` section)
- `scripts/template-selftest.sh` (one line in an existing test; new tests; a `--print-inventory`
  hook)
- `plans/README.md` (your status row)

**Out of scope** (do NOT touch):

- The **value** in root `VERSION`. gstack owns it from now on. Don't bump or reset it.
- `CLAUDE.md`, `README.md`, `DOCTRINE.md`, `ENGINEERING.md`, `DESIGN.md`, `MISSION.md`, `docs/`. They stay
  skeletons at the root. The complete-token inventory protects placeholders; it does not freeze arbitrary prose.
- `.gitignore` (don't un-ignore `.gstack/`, and don't add a `.gstack/version-path`).
- The gstack installation itself.

## Git workflow

- Work on the branch you were given (Conductor: `willtraweek/<topic>`). If you must create one:
  `willtraweek/plan-005-template-maintainer-mode`.
- Commit per step, plain imperative messages (e.g.
  `Move new-project VERSION/CHANGELOG/TODOS skeletons to template/skeleton`).
- Do NOT push or open a PR unless the operator told you to.

## Steps

### Step 1: Add the failing tests

1. In `scripts/template-selftest.sh`, in `test_bootstrap_removes_template_only_paths`, add a
   line directly after `assert_absent "$d/plans" || return 1`:

   ```bash
     assert_absent "$d/template" || return 1
   ```

2. Insert this block immediately **above** `# --- runner ---`:

```bash
# --- tests: template-owned files, skeletons, template-only blocks (plan 005) --
placeholder_tokens() {  # complete tokens, whitespace-normalized and sorted; bad delimiters fail
  perl -0777 -ne '
    my @tokens;
    while (/\{\{([^{}]*)\}\}/g) {
      my $t = $1; $t =~ s/\s+/ /g; push @tokens, "{{$t}}";
    }
    s/\{\{([^{}]*)\}\}//g;
    die "malformed placeholder delimiters in $ARGV\n" if /\{\{|\}\}/;
    print "$_\n" for sort @tokens;
  ' "$1"
}
placeholder_inventory() {  # "<file> <token count> <token sha256>" for each skeleton file
  local f tokens n digest
  while IFS= read -r -d '' f; do
    case "$f" in
      bootstrap|TEMPLATE.md|plans/*|scripts/template-selftest.sh) continue ;;
    esac
    [ -f "$REPO/$f" ] || continue
    tokens="$(placeholder_tokens "$REPO/$f")" || return 1
    [ -n "$tokens" ] || continue
    n="$(printf '%s\n' "$tokens" | wc -l | tr -d ' ')"
    digest="$(printf '%s\n' "$tokens" | shasum -a 256 | awk '{print $1}')"
    printf '%s %s %s\n' "$f" "$n" "$digest"
  done < <(cd "$REPO" && git ls-files -z --cached --others --exclude-standard | LC_ALL=C sort -zu)
}
template_markers_valid() {
  awk '
    /^<!-- template-only:start -->$/ {
      if (inside) { print FILENAME ": nested template-only start" > "/dev/stderr"; bad=1 }
      inside=1; next
    }
    /^<!-- template-only:end -->$/ {
      if (!inside) { print FILENAME ": unmatched template-only end" > "/dev/stderr"; bad=1 }
      inside=0
    }
    END {
      if (inside) { print FILENAME ": unclosed template-only start" > "/dev/stderr"; bad=1 }
      exit bad
    }
  ' "$1"
}
test_skeleton_placeholders_are_intact() {
  # Golden inventory. gstack's /document-release (run inside /ship) auto-applies
  # "factual" doc fixes; token identities, descriptions and delimiters must survive.
  # After an intentional change: ./scripts/template-selftest.sh --print-inventory
  local expected actual
  expected='.github/workflows/ci.yml.example 4 b54d42db089f26e1efd40c8fe67b923da6ecedea8d23d323c76e4e64d3371c80
.gitleaks.toml 1 bdd5d674e42dda7388efe0e56de5fa3d928ea21b6a1e705bd7ca9a44df10d2d0
AGENTS.md 7 24b65e92ead6eaca62bf62f865263db7846d12a25a7f6ece7e519385ebfeb9be
CLAUDE.md 16 ad5fecd2b2c16cbe94f4ab75a68957d336bdcb852f52df0bb006db3368dfe4cf
DESIGN.md 7 d7d0105be65334da5869323f56bbc467181a4fd9fae7f38db570ef000a945790
DOCTRINE.md 1 bdd5d674e42dda7388efe0e56de5fa3d928ea21b6a1e705bd7ca9a44df10d2d0
ENGINEERING.md 3 5a25f6421a333ad79cb00b36e89f756be496e290a103349eafd3d29322296243
MISSION.md 4 9941f9fb5142a080db73acdae6db4846842550bd9f87d64edf2690597b454ee3
README.md 9 6f4012246e96c2d2e4c0e4d699530443a57548c4be1f343b3b5f138b696ade64
TESTING.md 11 e1735bde2b46fbc18e18d17e3104173fd3431b55a6e863badb6ef272b35f8c94
docs/architecture.md 4 3b5f13e48bbc3e83fc93660a1d8665316f1ea124393c006de40eb8277a819244
docs/guides/README.md 1 bdd5d674e42dda7388efe0e56de5fa3d928ea21b6a1e705bd7ca9a44df10d2d0
template/skeleton/CHANGELOG.md 2 033352f6b40172964595ffde23b7c162618fe6a2ce8c7f3a26e7657ce556ecf5
template/skeleton/TODOS.md 2 54fdbe3163f63aa797cde77414a02b1fcdf26fabe1afa24f7a8b824bbe7875f6'
  actual="$(placeholder_inventory)" || return 1
  [ "$expected" = "$actual" ] || fail "placeholder inventory changed (expected vs actual):
$(diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))"
}
test_template_owned_files_are_not_skeletons() {
  assert_not_contains "$REPO/CHANGELOG.md" '{{' || return 1
  assert_not_contains "$REPO/TODOS.md" '{{' || return 1
  assert_exists "$REPO/template/skeleton/VERSION" || return 1
  [ "$(cat "$REPO/template/skeleton/VERSION")" = "0.0.0" ] || fail "skeleton VERSION is not 0.0.0"
}
test_template_only_markers_are_balanced() {
  local f
  while IFS= read -r -d '' f; do
    [ -f "$REPO/$f" ] || continue
    template_markers_valid "$REPO/$f" || return 1
  done < <(cd "$REPO" && git ls-files -z --cached --others --exclude-standard -- '*.md' ':!:plans/**' | LC_ALL=C sort -zu)
}
test_testing_md_gives_gstack_the_selftest_command() {
  assert_contains "$REPO/TESTING.md" "the test command is \`./scripts/template-selftest.sh\`"
}
test_skeleton_todos_pass_gstack_structure_check() {
  # gstack /ship step 14 wants: items under ## groups, a **Priority:** P0-P4 per item,
  # and ## Completed as the last section. Otherwise it asks to "reorganize" TODOS.md.
  local f="$REPO/template/skeleton/TODOS.md"
  [ "$(grep '^## ' "$f" | tail -n 1)" = "## Completed" ] || fail "## Completed is not the last section" || return 1
  awk '/^### /{ if (item && !prio) bad=1; item=1; prio=0 } /^\*\*Priority:\*\* P[0-4]/{ prio=1 }
       /^## /{ if (item && !prio) bad=1; item=0 } END { if (item && !prio) bad=1; exit bad }' "$f" \
    || fail "an item in the skeleton TODOS.md lacks a **Priority:** P0-P4 line"
}
test_bootstrap_installs_project_skeletons_and_provenance() {
  local d="$WORK/skeletons/demo" tver
  tver="$(head -n 1 "$REPO/VERSION")"
  fresh_copy "$d"
  run_bootstrap "$d" --name demo --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  [ "$(cat "$d/VERSION")" = "0.0.0" ] || fail "project VERSION is not 0.0.0" || return 1
  assert_contains "$d/CHANGELOG.md" "All notable changes to demo" || return 1
  assert_not_contains "$d/CHANGELOG.md" "vibe-starter template itself" || return 1
  assert_contains "$d/TODOS.md" "The working backlog for demo" || return 1
  assert_contains "$d/.bootstrapped" "from vibe-starter $tver"
}
test_bootstrap_strips_template_only_blocks() {
  local d="$WORK/strip/proj" hits
  fresh_copy "$d"
  printf 'PROJECT BEFORE\n<!-- template-only:start -->\nMAINTAINER PRIVATE\n<!-- template-only:end -->\nPROJECT AFTER\n' > "$d/canary.md"
  printf 'EOF BEFORE\n<!-- template-only:start -->\nMAINTAINER PRIVATE\n<!-- template-only:end -->' > "$d/eof-canary.md"
  run_bootstrap "$d" --name proj --yes || fail "bootstrap exited $?" || return 1
  [ "$(cat "$d/eof-canary.md")" = "EOF BEFORE" ] || fail "EOF marker was not stripped" || return 1
  [ "$(cat "$d/canary.md")" = "$(printf 'PROJECT BEFORE\nPROJECT AFTER')" ] || fail "stripping damaged surrounding content" || return 1
  hits="$(grep -rl --exclude-dir=.git 'template-only' "$d" || true)"
  [ -z "$hits" ] || fail "template-only markers survived in: $hits" || return 1
  assert_not_contains "$d/AGENTS.md" "You are in the vibe-starter template itself" || return 1
  assert_not_contains "$d/TESTING.md" "template-selftest" || return 1
  grep -qx '## Skill routing' "$d/CLAUDE.md" || fail "CLAUDE.md lost its routing heading" || return 1
  grep -qx '## Commands' "$d/TESTING.md" || fail "TESTING.md lost its Commands section"
}
test_placeholder_inventory_detects_same_count_corruption() {
  local f="$WORK/tokens.md" before after rc
  printf '{{CHECK_CMD}}\n{{TEST_CMD}}\n' > "$f"
  before="$(placeholder_tokens "$f")" || return 1
  printf '{{CHECK_CMD}}\n{{CHECK_CMD}}\n' > "$f"
  after="$(placeholder_tokens "$f")" || return 1
  [ "$before" != "$after" ] || fail "same-count token replacement was invisible" || return 1
  printf '{{CHECK_CMD}\n' > "$f"
  placeholder_tokens "$f" > "$f.out" 2>&1; rc=$?
  [ "$rc" -ne 0 ] || fail "malformed delimiter accepted" || return 1
  printf '{{CHECK_CMD{{TEST_CMD}}}}\n' > "$f"
  placeholder_tokens "$f" > "$f.out" 2>&1; rc=$?
  [ "$rc" -ne 0 ] || fail "nested placeholders accepted"
}
test_bootstrap_rejects_malformed_markers_before_changes() {
  local kind d before rc
  for kind in reversed nested unclosed; do
    d="$WORK/markers-$kind/proj"
    fresh_copy "$d" || return 1
    case "$kind" in
      reversed) printf '<!-- template-only:end -->\nkeep\n<!-- template-only:start -->\n' > "$d/canary.md" ;;
      nested) printf '<!-- template-only:start -->\n<!-- template-only:start -->\n<!-- template-only:end -->\n<!-- template-only:end -->\n' > "$d/canary.md" ;;
      unclosed) printf '<!-- template-only:start -->\nkeep\n' > "$d/canary.md" ;;
    esac
    before="$(tree_fingerprint "$d")"
    run_bootstrap "$d" --name proj --yes; rc=$?
    assert_exit 1 "$rc" || return 1
    assert_contains "$d.out" "template-only" || return 1
    [ "$before" = "$(tree_fingerprint "$d")" ] || fail "$kind markers changed files before rejection" || return 1
  done
}
test_bootstrap_retry_preserves_template_version() {
  local d="$WORK/retry/proj" shim="$WORK/cp-shim" rc
  fresh_copy "$d" || return 1
  printf '2.3.4\n' > "$d/VERSION"
  mkdir -p "$shim"
  cat > "$shim/cp" <<'SHIM'
#!/bin/sh
if [ "$1" = "template/skeleton/CHANGELOG.md" ]; then exit 42; fi
exec /bin/cp "$@"
SHIM
  chmod +x "$shim/cp"
  PATH="$shim:$PATH" run_bootstrap "$d" --name proj --yes; rc=$?
  assert_exit 42 "$rc" || return 1
  [ "$(cat "$d/VERSION")" = "0.0.0" ] || fail "failure did not occur after the version swap" || return 1
  assert_absent "$d/.bootstrapped" || return 1
  [ "$(cat "$d/template/.bootstrap-version")" = "2.3.4" ] || fail "original version was not saved" || return 1
  run_bootstrap "$d" --name proj --yes || fail "retry failed: $(cat "$d.out")" || return 1
  assert_contains "$d/.bootstrapped" 'from vibe-starter 2.3.4' || return 1
  assert_absent "$d/template"
}
```

3. Directly **below** the `# --- runner ---` line (before the `for t in ...` loop), add:

   ```bash
   if [ "$FILTER" = "--print-inventory" ]; then placeholder_inventory; exit $?; fi
   ```

**Verify**: `shellcheck scripts/template-selftest.sh` → exit 0. Run the suite and confirm
the original 80 tests remain green. The new skeleton/provenance tests must fail until the
implementation steps below; the helpers and preservation checks can already pass. Do not
weaken tests to make this intentionally red intermediate state green.

### Step 2: Create the new-project skeletons

```sh
mkdir -p template/skeleton
git show 1984ab7:VERSION      > template/skeleton/VERSION        # 0.0.0
git show 1984ab7:CHANGELOG.md > template/skeleton/CHANGELOG.md   # the 15-line skeleton above, verbatim
```

(Take them from `1984ab7`, not from the working tree, so a `/ship` that already touched the
root files can't leak into the skeleton.)

Create `template/skeleton/TODOS.md` with exactly this content. It is gstack's TODOS format. It
keeps the old skeleton's intent: P0–P1 high priority, P2–P3 backlog, P4 wishlist, a
`## Known issues` group, and the `{{FIRST_TASK}}` placeholder.

```markdown
# TODOS

The working backlog for {{PROJECT_NAME}}. Source of truth for "what's next."

This follows gstack's TODOS format, which `/ship` checks and keeps current: items grouped under
a component heading (`## Core`, `## Known issues`, ...), each item an `###` heading with a
`**Priority:**` from P0 to P4 (P0–P1 high priority, P2–P3 backlog, P4 wishlist), and finished
items moved to `## Completed` at the bottom.

## Core

### {{FIRST_TASK: the first real thing to build.}}

**What:** One line on the work.

**Why:** The problem it solves or the value it unlocks.

**Effort:** S
**Priority:** P1
**Depends on:** None

## Known issues

## Completed
```

**Verify**: `cat template/skeleton/VERSION` → `0.0.0`.
`./scripts/template-selftest.sh gstack_structure` → ok.

### Step 3: Make the root CHANGELOG.md and TODOS.md the template's own

**`CHANGELOG.md`.** The final file must contain, in this order:

1. This header:

   ```markdown
   # Changelog

   All notable changes to the vibe-starter template itself, newest first. gstack `/ship` adds each
   release entry. New projects start from their own blank changelog (`template/skeleton/CHANGELOG.md`).

   ```

2. Every release entry gstack `/ship` has **already** written to this file (headings shaped
   `## [<version>] - <YYYY-MM-DD>`, with their bodies), unchanged, in their existing order. If
   nobody has shipped yet, there are none.
3. This entry, last:

   ```markdown
   ## [0.0.0] - 2026-06-12

   ### Added
   - Initial template scaffold (#1): doctrine files (`CLAUDE.md`, `AGENTS.md`, `DOCTRINE.md`,
     `TESTING.md`, `ENGINEERING.md`), working-doc skeletons, config, an inert CI example,
     `./bootstrap`, and `scripts/check.sh`.
   ```

Everything that belonged to the skeleton goes away: the `{{PROJECT_NAME}}` intro line, the
`## [Unreleased]` section with its `Initial scaffold from the vibe-starter template.` bullet,
and the commented-out `{{YEAR}}` block. They now live in `template/skeleton/CHANGELOG.md`.

**`TODOS.md`.** Replace it entirely with this. If the current root `TODOS.md` holds real items
(anything beyond the `{{FIRST_TASK...}}` line and empty `-` bullets), copy them under
`## Template` first and mention it in your report.

```markdown
# TODOS

Backlog for the vibe-starter template itself, in gstack's TODOS format. Implementation plans for
selected items live in `plans/`. New projects start from their own blank backlog
(`template/skeleton/TODOS.md`).

## Template

### Offer projects a doctrine update path

**What:** A script that diffs a project's doctrine files against the template version recorded
in its `.bootstrapped`, as a report, not an automatic merge.

**Why:** Projects made from an older template never receive doctrine improvements.

**Context:** `.bootstrapped` records the template version since plan 005. The design doc
deferred an automatic generator ("Approach C").

**Effort:** M
**Priority:** P2
**Depends on:** None

### Opt-in stack packs (Python, Rust)

**What:** `bootstrap --stack python|rust` overlays that set up the per-stack gates `TESTING.md`
describes (coverage floor, tier checker, CI steps, `.gitignore` section).

**Why:** Every project repeats the same four manual checklist steps.

**Context:** Planned in `plans/006-stack-packs-python.md` and `plans/007-stack-pack-rust.md`.
Must stay opt-in to keep the spine stack-agnostic.

**Effort:** L
**Priority:** P2
**Depends on:** None

### Make the markdown pass editorconfig-checker

**What:** Run editorconfig-checker (v4.0.2) against the template and fix what it flags: likely
3-space list indentation in `TEMPLATE.md`. Then make it required in CI like gitleaks.

**Why:** `scripts/check.sh` runs it whenever it is installed, so it must pass on a clean template.

**Context:** Finding #8 in `plans/README.md`.

**Effort:** S
**Priority:** P3
**Depends on:** None

## Completed
```

Leave `VERSION` exactly as it is.

**Verify**: `./scripts/template-selftest.sh template_owned` → ok.
`grep -c '{{' CHANGELOG.md TODOS.md` → `CHANGELOG.md:0` and `TODOS.md:0`.

### Step 4: Add the two template-only blocks

1. `AGENTS.md`: directly after the title line and its blank line, before the opening operating
   protocol and reciprocal reading instructions, insert:

   ```markdown
   <!-- template-only:start -->
   > **You are in the vibe-starter template itself, not in a project made from it.** Everything
   > outside the template-only blocks is the skeleton each new project starts from, so the
   > `{{...}}` placeholders are intentional: never fill them in or "fix" them here. Verify every
   > change with `./scripts/template-selftest.sh`. The root `VERSION`, `CHANGELOG.md` and
   > `TODOS.md` belong to the template (gstack `/ship` maintains them); new projects get the
   > copies in `template/skeleton/`. Maintainer guide: `TEMPLATE.md`. `./bootstrap` removes this
   > block.
   <!-- template-only:end -->

   ```

   (The markers must be on their own lines, starting at column 0. Keep one blank line after
   the end marker.)

2. `TESTING.md`: directly after the ``- Tests: `{{TEST_CMD}}` `` line of `## Commands`, insert a
   blank line and:

   ```markdown
   <!-- template-only:start -->
   **Testing the template itself:** the test command is `./scripts/template-selftest.sh` and the
   checks are `./scripts/check.sh`. gstack's `/ship` reads this block. `./bootstrap` removes it.
   <!-- template-only:end -->
   ```

   Keep a blank line between the end marker and `## Why Tiers, Not One Number`.

**Verify**: `./scripts/template-selftest.sh template_only_markers_are_balanced` → ok.
The bootstrap rejection test is intentionally still red until step 5 adds its preflight.
`./scripts/template-selftest.sh selftest_command` → ok. `grep -cx '## Skill routing' CLAUDE.md`
→ `1`.

### Step 5: Teach bootstrap to swap skeletons, strip template-only blocks, and record provenance

1. Header comment: replace

   ```bash
   # placeholders you still need to hand-fill, then deletes itself and the
   # template-only paths (TEMPLATE.md, the template self-test, plans/).
   ```

   with

   ```bash
   # placeholders you still need to hand-fill, then deletes itself and the
   # template-only paths (TEMPLATE.md, template/, the template self-test, plans/).
   # It also installs the project's own VERSION / CHANGELOG.md / TODOS.md from
   # template/skeleton/ and strips <!-- template-only --> markdown blocks.
   ```

2. Directly after the line `echo "Personalizing template -> name='$NAME', year='$YEAR'"`, add
   (keep a blank line before it):

   ```bash
   # --- Validate template-only markers before any writes -----------------------
   validate_template_markers() {
     awk '
       /^<!-- template-only:start -->$/ {
         if (inside) { print FILENAME ": nested template-only start" > "/dev/stderr"; bad=1 }
         inside=1; next
       }
       /^<!-- template-only:end -->$/ {
         if (!inside) { print FILENAME ": unmatched template-only end" > "/dev/stderr"; bad=1 }
         inside=0
       }
       END {
         if (inside) { print FILENAME ": unclosed template-only start" > "/dev/stderr"; bad=1 }
         exit bad
       }
     ' "$1"
   }
   while IFS= read -r -d '' f; do
     validate_template_markers "$f" || exit 1
   done < <(find . -type d \( -name .git -o -name .context -o -name plans \
     -o -name node_modules -o -name .venv -o -name target -o -name dist \) -prune \
     -o -type f -name '*.md' -print0)

   # --- Swap in the project skeletons, retaining the template version on retry --
   # Save provenance outside root VERSION: the first copy replaces VERSION with 0.0.0.
   # Retry the same bootstrap arguments after fixing a failed operation.
   for f in VERSION CHANGELOG.md TODOS.md; do
     [ -f "template/skeleton/$f" ] || { echo "Missing skeleton: $f" >&2; exit 1; }
   done
   if [ ! -f template/.bootstrap-version ]; then
     TEMPLATE_VERSION="$(head -n 1 VERSION)"
     printf '%s\n' "$TEMPLATE_VERSION" > template/.bootstrap-version.tmp
     mv template/.bootstrap-version.tmp template/.bootstrap-version
   fi
   TEMPLATE_VERSION="$(cat template/.bootstrap-version)"
   if ! printf '%s\n' "$TEMPLATE_VERSION" | grep -Eq '^[0-9]+(\.[0-9]+){2,3}$'; then
     echo "Invalid saved template version: template/.bootstrap-version" >&2
     exit 1
   fi
   for f in VERSION CHANGELOG.md TODOS.md; do
     cp "template/skeleton/$f" "$f"
   done
   echo "Installed the project's own VERSION, CHANGELOG.md and TODOS.md."
   ```

   It must run **before** the placeholder-replacement block, so the skeletons'
   `{{PROJECT_NAME}}`/`{{YEAR}}` get replaced.

3. Directly after the placeholder-replacement block (after its closing `fi`), add:

   ```bash

   # --- Strip the validated template-only blocks -------------------------------
   while IFS= read -r -d '' f; do
     perl -0pi -e 's/^<!-- template-only:start -->\n.*?^<!-- template-only:end -->(?:\n|\z)\n?//gms' "$f"
   done < <(find . -type d \( -name .git -o -name .context -o -name plans \
     -o -name node_modules -o -name .venv -o -name target -o -name dist \) -prune \
     -o -type f -name '*.md' -print0)
   echo "Removed template-only blocks."
   ```

4. In the Finalize block, change two lines:

   ```bash
   TEMPLATE_ONLY="TEMPLATE.md template scripts/template-selftest.sh .github/workflows/template-selftest.yml plans"
   printf '%s from vibe-starter %s\n' "$(date +%Y-%m-%d)" "$TEMPLATE_VERSION" > .bootstrapped
   ```

   (`template` is added to the list, and `.bootstrapped` gains the provenance suffix. It stays
   one line, so the re-entry guard's `Already bootstrapped (...)` message still reads well.)

**Verify**: `shellcheck bootstrap` → exit 0. `./scripts/template-selftest.sh bootstrap` → all
ok. The new project from `test_bootstrap_installs_project_skeletons_and_provenance` has
`VERSION` `0.0.0`, and its `.bootstrapped` reads `<date> from vibe-starter <root VERSION>`.

### Step 6: Rewrite the maintainer guide in TEMPLATE.md

1. Line 23: replace
   ``- `README.md`, `CHANGELOG.md`, `TODOS.md`, `VERSION`, `docs/`, `.context/` — working scaffold.``
   with these two lines (second indented 2 spaces):

   ```markdown
   - `README.md`, `docs/`, `.context/` — working scaffold; a new project's own `VERSION`,
     `CHANGELOG.md`, `TODOS.md` come from `template/skeleton/`.
   ```

2. Replace the whole `## Maintaining the template` section (from its heading to the end of the
   file) with:

````markdown
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
shellcheck bootstrap scripts/*.sh          # CI lints first, with shellcheck 0.11.0
```

The self-test copies this working tree into a temp dir and exercises `./bootstrap` and
`scripts/check.sh` there; your checkout is never modified. It needs git, perl, and tar. Tests
that need gitleaks are skipped locally when it is missing; CI installs it and treats skips as
failures. CI runs it via `.github/workflows/template-selftest.yml`, which only runs on
`willtraweek/vibe-starter`.

### Shipping with gstack

`/ship` works here. It runs the self-test (TESTING.md's template-only block tells it to), bumps
the template's own `VERSION`, and writes the template's `CHANGELOG.md` and `TODOS.md`. Its docs
step may propose edits to skeleton files. Accept only changes meant for every future project,
and never let it fill in a placeholder: `test_skeleton_placeholders_are_intact` fails if one
changes.

### Placeholders

- `{{PROJECT_NAME}}` and `{{YEAR}}` are bootstrap-owned: `./bootstrap` replaces them.
- Everything else is filled in by hand in the new project. The bootstrap checklist must name
  every file that still has one (`test_bootstrap_checklist_names_every_file_with_placeholders`).
- After an intentional placeholder change, review the token diff, then print the inventory with
  `./scripts/template-selftest.sh --print-inventory` and paste it into
  `test_skeleton_placeholders_are_intact`.
````

**Verify**: `grep -c 'template/skeleton' TEMPLATE.md` → `2`. One is the line-23 replacement; the
other is the "Skeleton files" bullet. `grep -n 'Shipping with gstack' TEMPLATE.md` → one line.
`./scripts/template-selftest.sh` still passes (TEMPLATE.md is not under test).

### Step 7: Check the placeholder inventory

Run `./scripts/template-selftest.sh --print-inventory`. It must print exactly the list in
`test_skeleton_placeholders_are_intact`. The original scratch-build inventory assumed the
superseded single-file plan 004. This revised expected inventory preserves the current
AGENTS.md and CLAUDE.md tokens separately and adds this plan's template-only block; each SHA256
hashes the sorted, complete whitespace-normalized tokens. Verify the full result after
implementing plans 004 and 005; this plan edit is not a new implementation rehearsal.

```text
.github/workflows/ci.yml.example 4 b54d42db089f26e1efd40c8fe67b923da6ecedea8d23d323c76e4e64d3371c80
.gitleaks.toml 1 bdd5d674e42dda7388efe0e56de5fa3d928ea21b6a1e705bd7ca9a44df10d2d0
AGENTS.md 7 24b65e92ead6eaca62bf62f865263db7846d12a25a7f6ece7e519385ebfeb9be
CLAUDE.md 16 ad5fecd2b2c16cbe94f4ab75a68957d336bdcb852f52df0bb006db3368dfe4cf
DESIGN.md 7 d7d0105be65334da5869323f56bbc467181a4fd9fae7f38db570ef000a945790
DOCTRINE.md 1 bdd5d674e42dda7388efe0e56de5fa3d928ea21b6a1e705bd7ca9a44df10d2d0
ENGINEERING.md 3 5a25f6421a333ad79cb00b36e89f756be496e290a103349eafd3d29322296243
MISSION.md 4 9941f9fb5142a080db73acdae6db4846842550bd9f87d64edf2690597b454ee3
README.md 9 6f4012246e96c2d2e4c0e4d699530443a57548c4be1f343b3b5f138b696ade64
TESTING.md 11 e1735bde2b46fbc18e18d17e3104173fd3431b55a6e863badb6ef272b35f8c94
docs/architecture.md 4 3b5f13e48bbc3e83fc93660a1d8665316f1ea124393c006de40eb8277a819244
docs/guides/README.md 1 bdd5d674e42dda7388efe0e56de5fa3d928ea21b6a1e705bd7ca9a44df10d2d0
template/skeleton/CHANGELOG.md 2 033352f6b40172964595ffde23b7c162618fe6a2ce8c7f3a26e7657ce556ecf5
template/skeleton/TODOS.md 2 54fdbe3163f63aa797cde77414a02b1fcdf26fabe1afa24f7a8b824bbe7875f6
```

**Verify**: `./scripts/template-selftest.sh` → `selftest: 90 passed, 0 failed, 0 skipped`.
`./scripts/check.sh` → exit 0.

## Test plan

- 10 new tests plus one extended test (step 1):
  - the golden inventory of complete placeholder tokens and malformed-delimiter rejection;
  - template-owned files carry no placeholders;
  - template-only markers are ordered, non-nested and closed; malformed markers fail before writes;
  - `TESTING.md` gives `/ship` the self-test command;
  - the skeleton `TODOS.md` passes gstack's structure check;
  - bootstrap installs the skeletons and preserves original provenance across a failure and retry;
  - bootstrap strips the blocks without touching reciprocal reading instructions,
    CLAUDE.md's `## Skill routing` or TESTING.md's `## Commands`;
  - `template/` is removed.
- Final: `90 passed, 0 failed, 0 skipped`. `CI=true` gives the same.

## Done criteria

ALL must hold:

- [ ] `./scripts/template-selftest.sh` exits 0 with `90 passed, 0 failed, 0 skipped`
- [ ] `CI=true ./scripts/template-selftest.sh` exits 0
- [ ] `./scripts/template-selftest.sh --print-inventory` matches the list in step 7
- [ ] `cat template/skeleton/VERSION` → `0.0.0`; the root `VERSION` value is unchanged from before this plan
- [ ] `grep -c '{{' CHANGELOG.md TODOS.md` → both `0`
- [ ] `./scripts/check.sh` exits 0; `shellcheck bootstrap scripts/check.sh scripts/template-selftest.sh` exits 0
- [ ] `git status --porcelain` shows changes only to in-scope files
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The root `CHANGELOG.md` contains content you can't classify as either a gstack release entry
  or one of the listed skeleton lines.
- `--print-inventory` differs from step 7 in any way other than a token change you can explain by an
  earlier plan's recorded deviation. Report the diff. Do not just paste your output into the
  test.
- A test from plans 001–004 fails at any point.
- Making something pass seems to require moving `README.md`, `AGENTS.md`, `CLAUDE.md`, or any doctrine file
  into `template/`.

## Maintenance notes

- **Why only three files moved.** `/ship` *rewrites* `VERSION`, `CHANGELOG.md` and `TODOS.md`
  on every run, so those had to leave the root. The other skeleton docs only risk occasional
  "factual" edits from `/document-release`, which the token inventory catches when they alter placeholders. If that
  proves too weak (for example, `/document-release` starts rewriting prose in `README.md`), the
  next step is moving all skeleton docs into `template/skeleton/` and giving the root a real
  template README. That's a bigger restructure, deliberately deferred.
- **The provenance line is a contract.** `.bootstrapped` = `<YYYY-MM-DD> from vibe-starter
  <version>`. The future doctrine-update script (root `TODOS.md`) will parse the date and template-version
  fields. Plan 006 may append ` with the <stack> stack pack`; consumers must allow that suffix.
- The saved `template/.bootstrap-version` survives failures after the skeleton swap. Retry
  with the same arguments; successful finalization removes that state with `template/`.
- If gstack changes its TODOS format or adds a version opt-out, revisit
  `test_skeleton_todos_pass_gstack_structure_check` and this plan's rationale.
- Reviewer focus: the order of the swap, replace and strip steps in `bootstrap`, and a
  manual read of a freshly bootstrapped project's `AGENTS.md`/`CLAUDE.md`/`TESTING.md` for leftover blank
  lines around the stripped blocks.
