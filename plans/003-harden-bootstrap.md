# Plan 003: Harden `bootstrap`: name from the git remote, refuse to run on the template itself, strict args, worktree-aware git init

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff 1984ab7..HEAD -- bootstrap`
> Plan 001 (a dependency) legitimately changed two regions of `bootstrap`: the last lines of the
> header comment and the `# --- Finalize` block. Those differences are expected. Any change to
> the regions quoted in "Current state" below is a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans/001-template-selftest.md (the self-test harness these tests go into)
- **Category**: bug
- **Planned at**: commit `1984ab7`, 2026-09-23

## Why this matters

`bootstrap` personalizes a new project from the template. Five defects, all reproduced in
throwaway copies:

1. **It names the project after the Conductor workspace.** The default name is the directory
   name, and it's used silently with `--yes` or whenever stdin is not a TTY (every agent run).
   The maintainer works in Conductor, where the directory is a workspace codename such as
   `montreal`. Running there produced `Project: montreal` and
   `title = "montreal gitleaks config"`. Workspace codenames are never project names.
2. **It will personalize the template repo itself.** Nothing stops `./bootstrap --yes` inside a
   vibe-starter workspace. It rewrites every doc and deletes itself and `TEMPLATE.md`.
3. **`--name` with no value exits 1 silently.** `shift 2` fails under `set -e` with no message.
4. **`--name --yes` names the project `--yes`** and completes irreversibly: the flag is
   swallowed as the value and passes the character check.
5. **`[ ! -d .git ]` misreads worktrees and submodules.** There `.git` is a *file*, so bootstrap
   runs a harmless re-init and falsely prints `Initialized a fresh git repository.`

Also, the printed checklist omits `docs/architecture.md`, which still holds 3 placeholders
after bootstrap.

After this plan the default name matches the one gstack's `gstack-slug` derives (remote first,
then directory), the template can't be clobbered by accident, and bad args fail loudly with
exit 2.

## Current state

`bootstrap` is a bash script at the repo root. It runs once in a fresh copy of the template and
deletes itself at the end. The self-test harness `scripts/template-selftest.sh` (plan 001) runs
it in throwaway copies. Tests are `test_*` functions above the `# --- runner ---` line, and the
helpers are `fresh_copy`, `run_bootstrap` (sandboxed `HOME`, non-TTY stdin, output in
`"$dir.out"`), `tree_fingerprint`, `fail`, `assert_exit`, `assert_contains`,
`assert_not_contains`, and `$WORK`.

Regions this plan changes, as they are at `1984ab7` (plan 001 does not touch them):

Header usage lines (lines 4–7):

```bash
# Usage:
#   ./bootstrap                         # interactive (prompts for the name)
#   ./bootstrap --name my-project       # non-interactive name
#   ./bootstrap --name my-project --yes # no prompts at all
```

Arg parsing and name (lines 23–49):

```bash
# --- Parse args -------------------------------------------------------------
NAME=""
ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --name)   NAME="${2:-}"; shift 2 ;;
    --name=*) NAME="${1#*=}"; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) echo "Usage: ./bootstrap [--name <project>] [--yes]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- Project name -----------------------------------------------------------
default="$(basename "$ROOT")"
if [ -z "$NAME" ]; then
  if [ "$ASSUME_YES" = "1" ] || [ ! -t 0 ]; then
    NAME="$default"
  else
    printf "Project name [%s]: " "$default"
    read -r NAME </dev/tty || NAME=""
    [ -z "$NAME" ] && NAME="$default"
  fi
fi
case "$NAME" in
  *[!A-Za-z0-9._\ -]*) echo "Project name has unexpected characters: '$NAME'" >&2; exit 2 ;;
esac
```

git init (lines 72–75):

```bash
# --- git init (only if not already a repo) ----------------------------------
if [ ! -d .git ]; then
  git init -q && echo "Initialized a fresh git repository."
fi
```

Checklist (lines 87–100, inside `cat <<'CHECKLIST' ... CHECKLIST`):

```text
Bootstrap done. Hand-fill the placeholders that remain (grep the repo for '{{' ):
  CLAUDE.md   - tagline, architecture, key files, command placeholders
  AGENTS.md   - install command, trust boundary, ship gate
  TESTING.md  - tier modules, API surfaces, NAMED_INVARIANTS, critical journeys
  README.md   - what / why / stack
  TODOS.md    - the first real task
Then choose a stack and:
```

Facts verified while planning (macOS `/bin/bash` 3.2):

- `git remote get-url origin` → strip one trailing `/` and one `.git` → take everything after
  the last `/` or `:` (`${url##*[/:]}`). This yields `widget` for
  `https://github.com/acme-example/widget.git`, `git@github.com:acme-example/widget.git`,
  `ssh://git@github.com/acme-example/widget` and `https://github.com/acme-example/widget/`.
  It yields an empty string (exit 0) when there's no origin or no repo.
- On macOS, `/tmp` is a symlink to `/private/tmp`. `git rev-parse --show-toplevel` returns the
  *physical* path, so compare it with `pwd -P`, not `pwd`.
- gstack's `gstack-slug` (the maintainer's workflow tool) resolves project identity remote
  first, then basename. After this plan, bootstrap's default agrees with it.

Conventions: keep bootstrap's style: `# --- Section ----` dividers, UPPERCASE script-level
variables, plain status lines on stdout, errors on stderr, and `exit 2` for usage errors.
**bash 3.2 only**: no `mapfile`, associative arrays, `${x,,}`, or `local -n`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Self-test | `./scripts/template-selftest.sh` | all pass; totals below |
| This plan's tests | `./scripts/template-selftest.sh bootstrap` | all ok |
| Shell lint | `shellcheck bootstrap scripts/check.sh scripts/template-selftest.sh` | exit 0 |

Totals depend on which plans have landed. With plan 001 only: 9 + 8 new = **17**. With 001 and
002: 16 + 8 = **24**. In both cases 0 failed and 0 skipped (gitleaks installed).

## Suggested executor toolkit

- gstack `/investigate` if a characterization test from plan 001 starts failing. That would mean
  your edit changed existing behavior.
- gstack `/review` on the finished diff.
- Do not run gstack `/ship` unless asked (see the shipping caveat in `plans/README.md`).

## Scope

**In scope** (the only files you should modify):

- `bootstrap`
- `scripts/template-selftest.sh` (append tests above the runner)
- `plans/README.md` (your status row)

**Out of scope** (do NOT touch):

- The `# --- Replace bootstrap-owned placeholders` block, the gstack block, and the Finalize
  block of `bootstrap`. They work, and plans 001/005 own the Finalize block.
- The **CLAUDE.md line of the checklist**. Plan 004 removes CLAUDE.md and rewrites that line.
  Only *add* the `docs/architecture.md` line here.
- The `eval "$("$GSTACK_SLUG" ...)"` line. It looks risky but is by design: gstack-slug
  sanitizes its output to `[a-zA-Z0-9._-]` and sets only `SLUG`/`BRANCH`.
- `TEMPLATE.md`, `CLAUDE.md`, `AGENTS.md`, and all docs.

## Git workflow

- Work on the branch you were given (Conductor: `willtraweek/<topic>`). If you must create one:
  `willtraweek/plan-003-harden-bootstrap`.
- Commit per step, plain imperative messages (e.g.
  `Default the project name to the origin repo name`).
- Do NOT push or open a PR unless the operator told you to.

## Steps

### Step 1: Add the failing tests

Insert this block into `scripts/template-selftest.sh` immediately **above** `# --- runner ---`:

```bash
# --- tests: bootstrap hardening (plan 003) ------------------------------------
test_bootstrap_name_flag_requires_a_value() {
  local d="$WORK/name-no-value/proj" before rc
  fresh_copy "$d"
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --name; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "--name needs a value" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed despite the rejection"
}
test_bootstrap_rejects_empty_name() {
  local d="$WORK/name-empty/proj" rc
  fresh_copy "$d"
  run_bootstrap "$d" --name '' --yes; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "--name needs a non-empty value"
}
test_bootstrap_rejects_a_flag_as_the_name() {
  local d="$WORK/name-flag/proj" before rc
  fresh_copy "$d"
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --name --yes; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "must start with a letter or digit" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed despite the rejection"
}
test_bootstrap_defaults_name_from_origin_remote_not_workspace_dir() {
  local d="$WORK/conductor/widget/montreal"
  fresh_copy "$d"
  (cd "$d" && git init -q && git remote add origin git@github.com:acme-example/widget.git) \
    || fail "git setup failed" || return 1
  run_bootstrap "$d" --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  assert_contains "$d/.gitleaks.toml" 'title = "widget gitleaks config"' || return 1
  assert_not_contains "$d/.gitleaks.toml" "montreal"
}
test_bootstrap_defaults_name_from_directory_without_remote() {
  local d="$WORK/no-remote/plainproj"
  fresh_copy "$d"
  run_bootstrap "$d" --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  assert_contains "$d/.gitleaks.toml" 'title = "plainproj gitleaks config"'
}
test_bootstrap_refuses_the_template_repo_itself() {
  local d="$WORK/template-itself/proj" before rc
  fresh_copy "$d"
  (cd "$d" && git init -q && git remote add origin https://github.com/willtraweek/vibe-starter.git) \
    || fail "git setup failed" || return 1
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --yes; rc=$?
  assert_exit 3 "$rc" || return 1
  assert_contains "$d.out" "vibe-starter template repo itself" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed despite the refusal" || return 1
  run_bootstrap "$d" --name forced --yes --force || fail "--force run exited $?: $(cat "$d.out")" || return 1
  assert_contains "$d/.gitleaks.toml" 'title = "forced gitleaks config"'
}
test_bootstrap_in_a_worktree_skips_git_init() {
  local main="$WORK/wt/main" wt="$WORK/wt/workspace"
  fresh_copy "$main"
  (cd "$main" && git init -q && git add -A && git commit -qm init && git worktree add -q "$wt" -b feature) \
    || fail "worktree setup failed" || return 1
  run_bootstrap "$wt" --name proj --yes || fail "bootstrap exited $?: $(cat "$wt.out")" || return 1
  assert_contains "$wt.out" "Already a git repository" || return 1
  assert_not_contains "$wt.out" "Initialized a fresh git repository" || return 1
  [ -f "$wt/.git" ] || fail "worktree .git file was replaced"
}
test_bootstrap_checklist_names_every_file_with_placeholders() {
  local d="$WORK/checklist/proj" f missing=""
  fresh_copy "$d"
  run_bootstrap "$d" --name proj --yes || fail "bootstrap exited $?" || return 1
  for f in $(cd "$d" && grep -rl --exclude-dir=.git '{{' . | sed 's|^\./||'); do
    grep -qF -- "$f" "$d.out" || missing="$missing $f"
  done
  [ -z "$missing" ] || fail "checklist does not mention:$missing"
}
```

**Verify**: `./scripts/template-selftest.sh bootstrap` → exactly 7 failures:
`checklist_names_every_file_with_placeholders`,
`defaults_name_from_origin_remote_not_workspace_dir`, `in_a_worktree_skips_git_init`,
`name_flag_requires_a_value`, `refuses_the_template_repo_itself`,
`rejects_a_flag_as_the_name`, `rejects_empty_name`.
`test_bootstrap_defaults_name_from_directory_without_remote` must **pass**: it pins existing
behavior that has to survive. (Checked while planning: against the post-001 bootstrap,
7 fail and 17 pass across the whole suite with 001+002 landed.)

### Step 2: Strict argument parsing

Replace the whole `# --- Parse args ---` block (quoted above, ending at `done`) with:

```bash
# --- Parse args -------------------------------------------------------------
NAME=""
NAME_GIVEN=0
ASSUME_YES=0
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --name)
      if [ $# -lt 2 ]; then echo "--name needs a value" >&2; exit 2; fi
      NAME="$2"; NAME_GIVEN=1; shift 2 ;;
    --name=*) NAME="${1#*=}"; NAME_GIVEN=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --force)  FORCE=1; shift ;;
    -h|--help) echo "Usage: ./bootstrap [--name <project>] [--yes] [--force]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
if [ "$NAME_GIVEN" = "1" ] && [ -z "$NAME" ]; then
  echo "--name needs a non-empty value" >&2
  exit 2
fi
```

**Verify**: `./scripts/template-selftest.sh name_` → `name_flag_requires_a_value` and
`rejects_empty_name` now pass. `rejects_a_flag_as_the_name` still fails (fixed in step 3).

### Step 3: Remote-derived default name, template refusal, and stricter validation

Replace the whole `# --- Project name ---` block (from its divider through the closing `esac`
of the character check, quoted above) with the following two blocks:

```bash
# --- Refuse to personalize the template itself ------------------------------
# Default name source: the `origin` remote's repo name. NOT the directory name
# alone: in a Conductor workspace that is the workspace codename (e.g.
# "montreal"), which is never the project's name.
remote_repo_name() {
  local url
  url="$(git remote get-url origin 2>/dev/null)" || return 0
  url="${url%/}"; url="${url%.git}"
  printf '%s\n' "${url##*[/:]}"
}
REMOTE_NAME="$(remote_repo_name)"
if [ "$REMOTE_NAME" = "vibe-starter" ] && [ "$FORCE" != "1" ]; then
  echo "Refusing to run: this looks like the vibe-starter template repo itself" >&2
  echo "(origin: $(git remote get-url origin)). Run ./bootstrap in a repo created" >&2
  echo "from the template, or pass --force if you really mean it." >&2
  exit 3
fi

# --- Project name -----------------------------------------------------------
default="${REMOTE_NAME:-$(basename "$ROOT")}"
if [ -z "$NAME" ]; then
  if [ "$ASSUME_YES" = "1" ] || [ ! -t 0 ]; then
    NAME="$default"
  else
    printf "Project name [%s]: " "$default"
    read -r NAME </dev/tty || NAME=""
    [ -z "$NAME" ] && NAME="$default"
  fi
fi
case "$NAME" in
  [A-Za-z0-9]*) ;;
  *) echo "Project name must start with a letter or digit: '$NAME'" >&2; exit 2 ;;
esac
case "$NAME" in
  *[!A-Za-z0-9._\ -]*) echo "Project name has unexpected characters: '$NAME'" >&2; exit 2 ;;
esac
```

Leave the next two lines (`YEAR="$(date +%Y)"` and the `echo "Personalizing template -> ..."`)
unchanged. Keep the exact message `Project name has unexpected characters`: plan 001's
`test_bootstrap_rejects_bad_name` asserts it.

**Verify**: `./scripts/template-selftest.sh bootstrap` → only
`in_a_worktree_skips_git_init` and `checklist_names_every_file_with_placeholders` still fail.

### Step 4: Worktree-aware `git init`

Replace the `# --- git init ---` block (quoted above) with:

```bash
# --- git init (only if this directory is not already a repository root) ------
# `git rev-parse`, not `[ -d .git ]`: in worktrees and submodules .git is a file.
# Physical paths on both sides: on macOS /tmp is a symlink to /private/tmp.
toplevel="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ "$toplevel" = "$(pwd -P)" ]; then
  echo "Already a git repository - skipped git init."
elif git init -q 2>/dev/null; then
  echo "Initialized a fresh git repository."
  if [ -n "$toplevel" ]; then
    echo "Note: this directory is inside another repository ($toplevel); it now has its own nested repo."
  fi
else
  echo "git init failed (is git installed?) - skipped."
fi
```

Behavior note: a copy placed *inside another repository's subdirectory* still gets its own
nested repo, as today; the new note line just makes that visible. Don't change that
behavior.

**Verify**: `./scripts/template-selftest.sh worktree` → ok. Also `happy_path` → ok. A fresh
non-git copy must still print `Initialized a fresh git repository.`

### Step 5: Name every placeholder file in the checklist, and document `--force`

1. In the checklist heredoc, add this line directly after the `TODOS.md    - the first real task`
   line. Do not change the other lines. The CLAUDE.md line belongs to plan 004.

   ```text
     docs/architecture.md - modules, contracts & invariants
   ```

2. In the header comment, add a usage line directly after
   `#   ./bootstrap --name my-project --yes # no prompts at all`:

   ```bash
   #   ./bootstrap --force                 # allow running inside the vibe-starter repo itself
   ```

3. Directly above `set -euo pipefail`, add a blank comment line and these three comment lines
   (they document behavior the tests pin):

   ```bash
   #
   # The default name is the repo name of the `origin` remote, else the directory
   # name. Exit codes: 0 done (or already bootstrapped), 2 usage or name error,
   # 3 refused because this is the vibe-starter template repo itself.
   ```

**Verify**: `./scripts/template-selftest.sh` → all pass (17 or 24 total, see the table), 0
failed. `shellcheck bootstrap` → exit 0. `./bootstrap --help` is safe to run in the real repo
(it exits before touching anything) and prints
`Usage: ./bootstrap [--name <project>] [--yes] [--force]`.

## Test plan

- 8 new tests (step 1): 7 regressions for the defects above, plus 1 characterization test
  (no-remote directory default) that must stay green.
- Pattern: plan 001's `test_bootstrap_rejects_bad_name` (fingerprint → run → exit code →
  message → unchanged tree).
- Final: the full suite passes with 0 failures and 0 skips (gitleaks installed).

## Done criteria

ALL must hold:

- [ ] `./scripts/template-selftest.sh` exits 0 (17 passed if only 001 landed; 24 if 001+002)
- [ ] `CI=true ./scripts/template-selftest.sh` exits 0
- [ ] `shellcheck bootstrap scripts/check.sh scripts/template-selftest.sh` exits 0
- [ ] `grep -c '\[ ! -d .git \]' bootstrap` → `0`
- [ ] `grep -c 'docs/architecture.md' bootstrap` → `1`
- [ ] `./bootstrap --help` prints `Usage: ./bootstrap [--name <project>] [--yes] [--force]` and `git status --porcelain` is unchanged afterwards
- [ ] `git status --porcelain` shows changes only to in-scope files
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- After step 1 the failure set differs from the 7 tests listed, or any plan-001/002 test fails.
- A plan-001 characterization test (`happy_path`, `rejects_bad_name`, `help_changes_nothing`,
  gstack tests) fails after your edit. You changed behavior the plan says to keep.
- You find yourself editing the placeholder-replacement block, the gstack block, or the
  Finalize block.
- The maintainer's template repo is no longer named `vibe-starter` (check
  `git remote get-url origin`). The refusal check keys on that exact name.

## Maintenance notes

- The template-repo refusal keys on the **exact** remote repo name `vibe-starter`. If the repo
  is renamed, update the string in `bootstrap` and the URL in
  `test_bootstrap_refuses_the_template_repo_itself`. Forks named `vibe-starter` are refused too,
  which is correct (they are templates). `--force` is the escape hatch.
- Plan 004 (CLAUDE.md → AGENTS.md) rewrites the checklist's CLAUDE.md line.
  `test_bootstrap_checklist_names_every_file_with_placeholders` will catch any file it
  forgets.
- Plan 005 changes the Finalize block and adds VERSION/CHANGELOG regeneration. It must keep
  the exit-code contract documented in the header (0/2/3).
- Reviewer focus: `remote_repo_name` parsing, and the `pwd -P` comparison (a plain `pwd` breaks
  on macOS `/tmp`).
