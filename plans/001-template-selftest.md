# Plan 001: Give the template a self-test suite and a CI job that runs only on the template repo

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 1984ab7..HEAD -- bootstrap TEMPLATE.md scripts/ .github/workflows/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `1984ab7`, 2026-09-23

## Why this matters

vibe-starter is a GitHub template repo. Its only executable code is `bootstrap` (personalizes
a new project, then deletes itself) and `scripts/check.sh` (pre-test guards). Neither has a
single automated test, and nothing runs CI on the template repo itself. So any edit to them
ships untested into every project created afterwards. Every other plan in `plans/` changes one
of those two scripts and needs a verification gate, which is why this plan comes first. When it
lands, `./scripts/template-selftest.sh` is a one-command answer to "does the template still
work?", locally and in CI.

## Current state

Files involved:

- `bootstrap` (repo root, 106 lines, bash) — run once in a fresh copy of the template. Replaces
  `{{PROJECT_NAME}}`/`{{YEAR}}`, runs `git init` if needed, optionally calls gstack's
  `gstack-slug`, prints a checklist, writes `.bootstrapped`, deletes `TEMPLATE.md` and itself.
- `scripts/check.sh` (32 lines, bash) — runs `gitleaks` and `editorconfig-checker` if installed.
- `TEMPLATE.md` — template-only explainer; `bootstrap` deletes it.
- `.github/workflows/ci.yml.example` — the *downstream* CI skeleton. Deliberately inert
  (`.example` suffix) so a new project is green on its first push. **Do not activate or edit it**
  (plan 002 edits it).

`bootstrap` today, lines 1–15:

```bash
#!/usr/bin/env bash
# vibe-starter bootstrap — run once on a fresh clone to personalize the template.
#
# Usage:
#   ./bootstrap                         # interactive (prompts for the name)
#   ./bootstrap --name my-project       # non-interactive name
#   ./bootstrap --name my-project --yes # no prompts at all
#
# It replaces the bootstrap-owned placeholders ({{PROJECT_NAME}}, {{YEAR}}),
# initializes git if needed, optionally notes gstack, prints a checklist of the
# placeholders you still need to hand-fill, then deletes itself and TEMPLATE.md.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
```

`bootstrap` today, lines 102–106 (the only part of `bootstrap` this plan changes):

```bash
# --- Finalize: mark done, drop template meta, self-delete (last) ------------
date +%Y-%m-%d > .bootstrapped
rm -f TEMPLATE.md
rm -f "$ROOT/bootstrap"
echo "Removed bootstrap. Welcome to $NAME."
```

`TEMPLATE.md` today, lines 14–15:

```markdown
`./bootstrap` personalizes the bootstrap-owned placeholders, optionally notes gstack, prints a
first-run checklist, and then deletes itself and this file.
```

Facts the tests rely on (all verified against the current code):

- `./bootstrap --name demo --yes` in a fresh, non-git copy exits 0, leaves no
  `{{PROJECT_NAME}}`/`{{YEAR}}`, writes `title = "demo gitleaks config"` into `.gitleaks.toml`,
  writes `**<year> — Founded.**` into `ENGINEERING.md`, keeps hand-fill placeholders such as
  `{{TRUST_BOUNDARY` (AGENTS.md) and `{{NAMED_INVARIANTS` (TESTING.md), creates `.git/` and
  `.bootstrapped`, deletes itself, and prints `Welcome to demo.`
- With `.bootstrapped` present it prints `Already bootstrapped (...)` and exits 0 without
  changing anything.
- `--name 'bad/name'` → exit 2, message contains `unexpected characters`. `--bogus` → exit 2,
  `Unknown arg: --bogus`. `--help` → exit 0, prints `Usage: ./bootstrap ...`, changes nothing.
- If `$HOME/.claude/skills/gstack/bin/gstack-slug` is executable, bootstrap `eval`s its output
  and prints `gstack detected (slug: <SLUG>).`. Otherwise it prints
  `gstack not found on this machine -> skipped (harmless).`

Constraints you must respect:

- **bash 3.2.** macOS ships `/bin/bash` 3.2.57 and the maintainer's `#!/usr/bin/env bash`
  resolves to it. Forbidden: `mapfile`/`readarray`, associative arrays (`declare -A`),
  `${var,,}`/`${var^^}`, `local -n`, `|&`, `;&`. CI runs Linux bash 5. The script must work on
  both.
- **gstack side effect.** The real `gstack-slug` writes a cache file per working directory under
  `~/.gstack/slug-cache/`. Running bootstrap in temp dirs with your real `HOME` litters that
  cache (gstack-slug's own header complains about thousands of stale temp-dir entries). The
  harness must run bootstrap with a sandboxed `HOME`.
- **Hermetic git.** The maintainer's global git config may enable signing, hooks, or templates.
  Test commits must ignore global and system config and use a fixed identity.
- **"Use this template" copies every file**, including `.github/workflows/*`. A workflow meant
  only for the template must be guarded so it is inert in copies. `./bootstrap` must also delete
  it.
- The template repo is `willtraweek/vibe-starter` (private, default branch `master`, marked as
  a template).

Repo conventions to match (see `scripts/check.sh` as the exemplar): `#!/usr/bin/env bash`,
header comment explaining purpose, 2-space indent, `# --- Section ----` dividers, lowercase
local variables, UPPERCASE for script-level settings, short plain-English status lines.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Self-test (after step 1) | `./scripts/template-selftest.sh` | last line `selftest: 9 passed, 0 failed, 0 skipped`, exit 0 (with gitleaks installed; without it: `8 passed, 0 failed, 1 skipped`) |
| Subset of tests | `./scripts/template-selftest.sh bootstrap` | only tests whose name contains `bootstrap` run |
| Shell lint | `shellcheck bootstrap scripts/check.sh scripts/template-selftest.sh` | exit 0, no output |
| Existing guard | `./scripts/check.sh` | exit 0 |
| YAML parses | `ruby -e 'require "yaml"; YAML.load_file(ARGV[0])' .github/workflows/template-selftest.yml` | exit 0, no output |

`shellcheck`, `gitleaks`, `ruby`, `perl`, `tar`, `git` are all present on the maintainer's Mac.
If `ruby` is missing, use
`python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' <file>`.

## Suggested executor toolkit

The maintainer runs the gstack skill suite. If available in your environment:

- gstack `/investigate` — if a characterization test fails against the *unmodified*
  `bootstrap`, root-cause it before touching anything (and see STOP conditions).
- gstack `/review` — run on your finished diff before reporting back.
- Do **not** run gstack `/ship` unless the operator asks. See the shipping caveat in
  `plans/README.md`: until plan 005 lands, `/ship` on this repo bumps the downstream skeleton
  `VERSION`/`CHANGELOG.md`.

## Scope

**In scope** (the only files you should modify):

- `scripts/template-selftest.sh` (create)
- `.github/workflows/template-selftest.yml` (create)
- `bootstrap` — header comment (lines 9–11) and the Finalize block (lines 102–106) only
- `TEMPLATE.md` — lines 14–15 and a new section at the end
- `plans/README.md` — your status row only

**Out of scope** (do NOT touch, even though they look related):

- `scripts/check.sh`, `.github/workflows/ci.yml.example`, `.gitignore`, `.gitleaks.toml` —
  plan 002 changes them. Tests here must pass against their *current* behavior.
- The rest of `bootstrap` (arg parsing, name default, `git init`, checklist). Plan 003 fixes
  known bugs there. If you notice them, list them in your report; do not fix them.
- `CLAUDE.md`, `AGENTS.md` — plans 004/005 restructure them. Do not add instructions there.
- `VERSION`, `CHANGELOG.md`, `README.md`, `TODOS.md` — downstream skeletons (plan 005).

## Git workflow

- Work on the branch you were given. Conductor names branches `willtraweek/<topic>`. If you
  must create one: `willtraweek/plan-001-template-selftest`.
- Commit per step. Match the repo's plain imperative commit style (e.g.
  `Scaffold vibe-starter: stack-agnostic doctrine template`). Example:
  `Add template self-test harness for bootstrap and check.sh`.
- Do NOT push or open a PR unless the operator told you to.

## Steps

### Step 1: Create the self-test harness

Create `scripts/template-selftest.sh` with exactly this content, then `chmod +x` it. This code
was prototyped and passes 9/9 against the current repo under macOS `/bin/bash` 3.2, and is
shellcheck-clean.

Note: `test_bootstrap_removes_template_only_paths` will FAIL until step 2 lands (it is the
test for step 2). That is expected after step 1.

```bash
#!/usr/bin/env bash
# Template self-test for vibe-starter. TEMPLATE-ONLY: ./bootstrap deletes this
# file, so it never ships into projects created from the template.
#
# Exercises ./bootstrap and scripts/check.sh against throwaway copies of this
# working tree (exactly the files git would commit, uncommitted edits included).
# Nothing in the real checkout is modified.
#
# Usage: scripts/template-selftest.sh [substring]   # only tests whose name contains it
#
# Portability: must run on macOS /bin/bash 3.2 and on Linux bash 5. No mapfile,
# no associative arrays, no ${var,,}, no `local -n`.
set -uo pipefail   # no -e: one failing assertion must not abort the whole run

REPO="$(cd "$(dirname "$0")/.." && pwd)"
if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "selftest: $REPO is not a git checkout (fresh_copy needs git ls-files)" >&2
  exit 2
fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/vs-selftest.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
FILTER="${1:-}"
PASS=0; FAIL=0; SKIP=0

# Hermetic git: ignore the user's global/system config (signing, hooks,
# templates) and use a fixed identity for any test commits.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.invalid
export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.invalid

# --- assertion helpers: print a reason, return non-zero on failure ------------
fail()                { echo "    FAIL: $*"; return 1; }
skip()                { echo "    SKIP: $*"; return 77; }
assert_exists()       { [ -e "$1" ] || fail "expected to exist: ${1#"$WORK"/}"; }
assert_absent()       { [ ! -e "$1" ] || fail "expected NOT to exist: ${1#"$WORK"/}"; }
assert_contains()     { grep -qF -- "$2" "$1" || fail "expected ${1#"$WORK"/} to contain: $2"; }
assert_not_contains() { ! grep -qF -- "$2" "$1" || fail "expected ${1#"$WORK"/} NOT to contain: $2"; }
assert_exit()         { [ "$1" -eq "$2" ] || fail "expected exit $1, got $2"; }
assert_tree_lacks() {  # $1 = dir, $2 = fixed string that must appear in no file under it
  local hits
  hits="$(grep -rlF --exclude-dir=.git -- "$2" "$1" || true)"
  [ -z "$hits" ] || fail "'$2' still present in: $(echo "$hits" | sed "s|$1/||" | tr '\n' ' ')"
}
tree_fingerprint() {  # stable listing of every file + checksum (excluding .git)
  (cd "$1" && find . -path ./.git -prune -o -type f -exec cksum {} + | LC_ALL=C sort)
}

# --- fixtures -----------------------------------------------------------------
fresh_copy() {  # $1 = new dir: a copy of the working tree exactly as git would commit it
  mkdir -p "$1"
  (cd "$REPO" && git ls-files -z --cached --others --exclude-standard \
    | while IFS= read -r -d '' f; do if [ -f "$f" ]; then printf '%s\0' "$f"; fi; done \
    | tar --null -T - -cf -) | tar -xf - -C "$1"
}
run_bootstrap() {  # $1 = dir, rest = bootstrap args. Output goes to "$1.out".
  # Sandboxed HOME: keeps bootstrap's optional gstack-slug call from writing
  # into the real ~/.gstack, and makes "gstack present" opt-in per test.
  # stdin is not a TTY, exactly like an agent running bootstrap.
  local dir="$1"; shift
  mkdir -p "$WORK/home"
  (cd "$dir" && HOME="$WORK/home" ./bootstrap "$@" </dev/null >"$dir.out" 2>&1)
}

# --- tests: bootstrap ---------------------------------------------------------
test_bootstrap_happy_path() {
  local d="$WORK/happy/demo" year
  year="$(date +%Y)"
  fresh_copy "$d"
  run_bootstrap "$d" --name demo --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  assert_tree_lacks "$d" '{{PROJECT_NAME}}' || return 1
  assert_tree_lacks "$d" '{{YEAR}}' || return 1
  assert_contains "$d/.gitleaks.toml" 'title = "demo gitleaks config"' || return 1
  assert_contains "$d/AGENTS.md" 'demo' || return 1
  assert_contains "$d/ENGINEERING.md" "**$year — Founded.**" || return 1
  # Hand-fill placeholders are not bootstrap's job: they must survive untouched.
  assert_contains "$d/AGENTS.md" '{{TRUST_BOUNDARY' || return 1
  assert_contains "$d/TESTING.md" '{{NAMED_INVARIANTS' || return 1
  assert_exists "$d/.bootstrapped" || return 1
  assert_exists "$d/.git" || return 1
  assert_absent "$d/bootstrap" || return 1
  assert_contains "$d.out" "Welcome to demo."
}
test_bootstrap_removes_template_only_paths() {
  local d="$WORK/template-only/proj"
  fresh_copy "$d"
  mkdir -p "$d/plans" && echo "# probe" > "$d/plans/999-probe.md"
  run_bootstrap "$d" --name proj --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  assert_absent "$d/TEMPLATE.md" || return 1
  assert_absent "$d/scripts/template-selftest.sh" || return 1
  assert_absent "$d/.github/workflows/template-selftest.yml" || return 1
  assert_absent "$d/plans" || return 1
  # The downstream CI skeleton and the check guard must survive.
  assert_exists "$d/.github/workflows/ci.yml.example" || return 1
  assert_exists "$d/scripts/check.sh"
}
test_bootstrap_reentry_guard_is_a_noop() {
  local d="$WORK/reentry/proj" before
  fresh_copy "$d"
  echo 2026-01-01 > "$d/.bootstrapped"
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --name demo --yes || fail "bootstrap exited $?" || return 1
  assert_contains "$d.out" "Already bootstrapped" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed on re-entry"
}
test_bootstrap_rejects_bad_name() {
  local d="$WORK/bad-name/proj" before rc
  fresh_copy "$d"
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --name 'bad/name' --yes; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "unexpected characters" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed despite the rejection"
}
test_bootstrap_rejects_unknown_arg() {
  local d="$WORK/bad-arg/proj" before rc
  fresh_copy "$d"
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --bogus; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "Unknown arg: --bogus" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed despite the rejection"
}
test_bootstrap_help_changes_nothing() {
  local d="$WORK/help/proj" before
  fresh_copy "$d"
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --help || fail "bootstrap --help exited $?" || return 1
  assert_contains "$d.out" "Usage: ./bootstrap" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed on --help"
}
test_bootstrap_reports_gstack_slug_when_present() {
  local d="$WORK/gstack/proj" bin="$WORK/home/.claude/skills/gstack/bin" rc
  fresh_copy "$d"
  mkdir -p "$bin"
  printf '#!/bin/sh\necho SLUG=fake-slug\n' > "$bin/gstack-slug"
  chmod +x "$bin/gstack-slug"
  run_bootstrap "$d" --name demo --yes; rc=$?
  rm -rf "$WORK/home/.claude"
  assert_exit 0 "$rc" || return 1
  assert_contains "$d.out" "gstack detected (slug: fake-slug)."
}
test_bootstrap_without_gstack_is_harmless() {
  local d="$WORK/no-gstack/proj"
  fresh_copy "$d"
  run_bootstrap "$d" --name demo --yes || fail "bootstrap exited $?" || return 1
  assert_contains "$d.out" "gstack not found on this machine"
}

# --- tests: scripts/check.sh --------------------------------------------------
test_check_passes_on_clean_template() {
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-clean/proj"
  fresh_copy "$d"
  (cd "$d" && git init -q && git add -A && git commit -qm init) || fail "git setup failed" || return 1
  (cd "$d" && ./scripts/check.sh >"$d.out" 2>&1) || fail "check.sh exited $?: $(tail -5 "$d.out")"
}

# --- runner -------------------------------------------------------------------
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  case "$t" in *"$FILTER"*) ;; *) continue ;; esac
  echo "- $t"
  "$t"; rc=$?
  case "$rc" in
    0)  PASS=$((PASS + 1)); echo "  ok" ;;
    77) SKIP=$((SKIP + 1)) ;;
    *)  FAIL=$((FAIL + 1)) ;;
  esac
done
echo "selftest: $PASS passed, $FAIL failed, $SKIP skipped"
if [ "${CI:-}" = "true" ] && [ "$SKIP" -gt 0 ]; then
  echo "selftest: skipped tests count as failures in CI (install the missing tool)" >&2
  exit 1
fi
[ "$FAIL" -eq 0 ] && [ $((PASS + SKIP)) -gt 0 ]
```

How to add a test later (other plans do this): define a new `test_<area>_<behavior>()`
function above the runner. Return 0 for pass, 77 (via `skip`) for skip, anything else for
fail. Chain assertions with `|| return 1`. Always work in a fresh dir under `$WORK`.

**Verify**: `chmod +x scripts/template-selftest.sh && ./scripts/template-selftest.sh` → exactly
one failure, `test_bootstrap_removes_template_only_paths`. Last line:
`selftest: 8 passed, 1 failed, 0 skipped` (without gitleaks: `7 passed, 1 failed, 1 skipped`).
Also `shellcheck scripts/template-selftest.sh` → exit 0.

### Step 2: Make bootstrap delete every template-only path

In `bootstrap`, replace the Finalize block (lines 102–106 shown above) with:

```bash
# --- Finalize: mark done, drop template-only paths, self-delete (last) ------
# Template-only paths exist to maintain vibe-starter itself; they must never
# ship into a project created from it. Keep this list in sync with TEMPLATE.md.
TEMPLATE_ONLY="TEMPLATE.md scripts/template-selftest.sh .github/workflows/template-selftest.yml plans"
date +%Y-%m-%d > .bootstrapped
for p in $TEMPLATE_ONLY; do rm -rf "$p"; done
rm -f "$ROOT/bootstrap"
echo "Removed bootstrap. Welcome to $NAME."
```

Then change the last line of the header comment (line 11) from
`# placeholders you still need to hand-fill, then deletes itself and TEMPLATE.md.` to:

```bash
# placeholders you still need to hand-fill, then deletes itself and the
# template-only paths (TEMPLATE.md, the template self-test, plans/).
```

`plans/` is on the list on purpose: it holds implementation plans for the *template*. Without
this line, every project created from the template would inherit them.

**Verify**: `./scripts/template-selftest.sh` → `selftest: 9 passed, 0 failed, 0 skipped`
(or `8 passed, 0 failed, 1 skipped` without gitleaks). `shellcheck bootstrap` → exit 0.

### Step 3: Add the template-only CI workflow

Create `.github/workflows/template-selftest.yml` with exactly this content. The gitleaks
SHA256 below was checked against the file published in the v8.30.1 release
(`gitleaks_8.30.1_checksums.txt`).

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

      - name: Install gitleaks (pinned, checksum-verified)
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

      - name: Lint shell scripts
        run: shellcheck bootstrap scripts/*.sh

      - name: Template self-test
        run: ./scripts/template-selftest.sh
```

Notes: GitHub Actions sets `CI=true`, so the harness treats any skipped test as a failure.
`shellcheck` comes preinstalled on `ubuntu-latest`. `actions/checkout@v7` is the current major
version (v7.0.1). Its only breaking change affects `pull_request_target`/`workflow_run`, which
this workflow doesn't use.

**Verify**:
`ruby -e 'require "yaml"; YAML.load_file(ARGV[0])' .github/workflows/template-selftest.yml` →
exit 0. `grep -c "github.repository == 'willtraweek/vibe-starter'" .github/workflows/template-selftest.yml`
→ `1`.

### Step 4: Document how to maintain the template

In `TEMPLATE.md`, replace lines 14–15 (quoted in Current state) with:

```markdown
`./bootstrap` personalizes the bootstrap-owned placeholders, optionally notes gstack, prints a
first-run checklist, and then deletes itself and the template-only paths listed below.
```

Append this section at the end of `TEMPLATE.md`:

````markdown
## Maintaining the template

Changes to `bootstrap` or `scripts/check.sh` must keep the self-test green:

```sh
./scripts/template-selftest.sh             # every test
./scripts/template-selftest.sh bootstrap   # only tests whose name contains "bootstrap"
```

It copies this working tree into a temp dir and exercises `./bootstrap` and `scripts/check.sh`
there; your checkout is never modified. It needs git, perl, and tar. Tests that need gitleaks
are skipped locally when it is missing; CI installs it and treats skips as failures. CI runs it
via `.github/workflows/template-selftest.yml`, which only runs on `willtraweek/vibe-starter`.

Template-only paths (deleted by `./bootstrap`, never shipped to new projects): `TEMPLATE.md`,
`scripts/template-selftest.sh`, `.github/workflows/template-selftest.yml`, `plans/`.
````

**Verify**: `grep -c 'template-selftest' TEMPLATE.md` → `3` or more.
`grep -n 'deletes itself and this file' TEMPLATE.md` → no output.

### Step 5: Prove the tests have teeth (negative control)

Commit your work first. Then, in a throwaway clone:

```sh
tmp="$(mktemp -d)"; git clone -q "$PWD" "$tmp/negctl"
perl -pi -e 's/\$ENV\{NAME\}/MUTANT/' "$tmp/negctl/bootstrap"   # break name substitution
"$tmp/negctl/scripts/template-selftest.sh" happy_path; echo "exit=$?"
rm -rf "$tmp"
```

**Verify**: the run prints
`FAIL: expected happy/demo/.gitleaks.toml to contain: title = "demo gitleaks config"` and
`exit=1`. Your real checkout is untouched (`git status --porcelain` is empty).

## Test plan

- The harness *is* the deliverable: 9 tests covering bootstrap's happy path, placeholder
  handling, re-entry guard, argument errors, `--help`, both gstack paths, template-only path
  removal, and `check.sh` passing on a clean copy.
- The step-5 negative control proves a real regression turns the suite red.
- Structural pattern for future tests: `test_bootstrap_rejects_bad_name` (fresh copy →
  fingerprint → run → assert exit code, message, and unchanged tree).

## Done criteria

ALL must hold:

- [ ] `./scripts/template-selftest.sh` exits 0 with `selftest: 9 passed, 0 failed, 0 skipped`
      (gitleaks installed) or `8 passed, 0 failed, 1 skipped` (gitleaks absent)
- [ ] `CI=true ./scripts/template-selftest.sh` exits 0 when gitleaks is installed
- [ ] `shellcheck bootstrap scripts/check.sh scripts/template-selftest.sh` exits 0
- [ ] `ruby -e 'require "yaml"; YAML.load_file(ARGV[0])' .github/workflows/template-selftest.yml` exits 0
- [ ] Step-5 negative control printed `exit=1`
- [ ] `./scripts/check.sh` exits 0
- [ ] `git diff --name-only 1984ab7..HEAD` lists only: `bootstrap`, `TEMPLATE.md`,
      `scripts/template-selftest.sh`, `.github/workflows/template-selftest.yml`,
      `plans/README.md` (plus any `plans/*.md` that already existed)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Any test other than `test_bootstrap_removes_template_only_paths` fails against the
  unmodified `bootstrap`/`check.sh`. The plan's facts about current behavior are then wrong.
  Report the test name and output.
- `test_check_passes_on_clean_template` fails because gitleaks reports a finding in the copy.
  Something committable looks like a secret. Report the file and rule ID, **never the value**.
- `test_check_passes_on_clean_template` fails because *editorconfig-checker* (installed on your
  machine) reports `Wrong amount of left-padding spaces` in `*.md` files. That is known,
  unplanned finding #8 (see `plans/README.md`), not a bug in your work. Report it rather than
  editing markdown or `.editorconfig`.
- `tar --null -T -` is rejected by your platform's tar, or the harness needs a bash-4-only
  feature to work.
- Making a test pass seems to require changing `check.sh`, the rest of `bootstrap`, or any
  out-of-scope file.

## Maintenance notes

- Every later plan (002–005) appends tests to this file. At about 500 lines (the
  `ENGINEERING.md` smell threshold), split it by subject (`bootstrap` vs `check`) and keep one
  runner.
- The template-only list lives in two places: `TEMPLATE_ONLY` in `bootstrap` and the last
  paragraph of `TEMPLATE.md`. `test_bootstrap_removes_template_only_paths` guards the behavior,
  not the doc. Update both when adding a template-only file.
- If the repo is renamed or transferred, update the `if: github.repository == ...` guard.
  Otherwise the job is silently skipped forever. It shows as "skipped", not red.
- gstack `/ship` runs a repo's tests before shipping. Plan 005 makes this suite the test
  command agents and `/ship` use for the template. Until then, run it by hand.
- Reviewer focus: the sandboxed `HOME` in `run_bootstrap` (must stay; see gstack side effect)
  and the job-level `if:` guard.
