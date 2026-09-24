# Plan 002: Make `scripts/check.sh` trustworthy: scan only what git would commit, fail closed in CI, keep `.env.example` committable

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 1984ab7..HEAD -- scripts/check.sh .gitignore .gitleaks.toml .github/workflows/ci.yml.example`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans/001-template-selftest.md (adds `scripts/template-selftest.sh`, where the tests go)
- **Category**: security
- **Planned at**: commit `1984ab7`, 2026-09-23

## Why this matters

`scripts/check.sh` is the guard every project made from this template runs before its tests
(locally, and in CI once CI is activated). Today it lies in both directions:

1. **It goes red when nothing is wrong.** It runs `gitleaks detect --no-git`, which scans every
   file on disk, including gitignored ones. A normal gitignored `.env` holding real local
   credentials makes it exit 1 (reproduced). It doesn't even name the file. `CLAUDE.md` tells
   agents checks must exit 0, so an agent is pushed to delete the `.env` or allowlist it.
2. **It goes green when nothing was checked.** If gitleaks isn't installed, it prints "skipping"
   and exits 0. GitHub's `ubuntu-latest` runner doesn't ship gitleaks, so the CI example's
   "Checks" step scans nothing and passes.

Separately, `.gitignore` silently ignores `.env.example`, the most common name for the file
that documents required env vars, despite its own comment ("keep the *.example templates").

After this plan: the scan covers exactly what `git add -A` would commit (a force-added `.env`
*is* caught), findings name the file without printing the secret, CI fails if the scanner is
missing, and `.env.example` is committable.

## Current state

- `scripts/check.sh` — the stack-neutral guard runner (whole file below).
- `.gitignore` lines 7–10 — env-file rules.
- `.gitleaks.toml` — gitleaks config: default rules plus a path allowlist.
- `.github/workflows/ci.yml.example` — the *downstream* CI skeleton. Deliberately inert: GitHub
  only runs `*.yml`, and new projects rename it once they have a stack.
- `scripts/template-selftest.sh` — the template's self-test harness (created by plan 001). Tests
  are `test_*` functions above the `# --- runner ---` line. Helpers you'll use: `fresh_copy`,
  `fail`, `skip`, `assert_exit`, `assert_contains`, `assert_not_contains`, and `$WORK` (a
  per-run temp dir).

`scripts/check.sh` today (entire file, 32 lines):

```bash
#!/usr/bin/env bash
# Stack-neutral pre-test guards. Runs before the test suite, locally and in CI.
# Add project-specific checks here as the codebase grows (the "guards run before
# tests" convention). Each guard should fail loudly and set status=1.
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
ran_any=0

# --- Secret scanning (if gitleaks is installed) -----------------------------
if command -v gitleaks >/dev/null 2>&1; then
  ran_any=1
  echo "- gitleaks: scanning working tree for secrets..."
  gitleaks detect --no-git --no-banner --redact -c .gitleaks.toml || status=1
else
  echo "- gitleaks not installed - skipping secret scan (brew install gitleaks)."
fi

# --- Formatting conformance (if editorconfig-checker is installed) ----------
if command -v editorconfig-checker >/dev/null 2>&1; then
  ran_any=1
  echo "- editorconfig-checker: checking formatting..."
  editorconfig-checker || status=1
else
  echo "- editorconfig-checker not installed - skipping format check."
fi

if [ "$status" = "0" ]; then
  [ "$ran_any" = "1" ] && echo "OK: checks passed." || echo "OK: no checks configured yet."
fi
exit "$status"
```

`.gitignore` lines 7–10:

```gitignore
# --- Secrets / env (keep the *.example templates) ---
.env
.env.*
!.env.*.example
```

(`!.env.*.example` re-includes only `.env.<something>.example`. `git check-ignore -v .env.example`
reports it ignored by `.gitignore:9:.env.*`.)

`.gitleaks.toml` lines 7–13:

```toml
[allowlist]
description = "Paths that legitimately contain key-shaped placeholders"
paths = [
  '''\.env\..*\.example$''',
  '''(^|/)tests?/fixtures/''',
  '''(^|/)CHANGELOG\.md$''',
]
```

(The first regex needs `.env.<something>.example`, so it misses `.env.example`, same gap as
`.gitignore`.)

`.github/workflows/ci.yml.example` lines 11–31:

```yaml
name: ci

on:
  push:
    branches: [main, master]
  pull_request:

jobs:
  check-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # - name: Install
      #   run: {{INSTALL_CMD}}

      - name: Checks (guards run before tests)
        run: ./scripts/check.sh

      # - name: Tests
      #   run: {{TEST_CMD}}
```

Facts verified while planning (gitleaks 8.30.1, macOS bash 3.2):

- `gitleaks detect` is deprecated: it no longer appears in `gitleaks --help`, and `dir` and
  `git` replace it. `gitleaks dir` accepts a single path.
- Gitleaks' default config already skips `node_modules/`, so vendored deps are not a
  false-positive source.
- With `-v`, gitleaks prints `File: <path>` per finding. With `--redact` the secret shows as
  `REDACTED`. Running it from inside the scan dir makes the paths repo-relative.
- The `git ls-files | tar` copy below correctly handles deleted-but-tracked files, paths with
  spaces, force-added ignored files (included), and gitignored files (excluded).
- `ubuntu-latest` (24.04) ships shellcheck but not gitleaks or editorconfig-checker (per the
  runner image's software list).
- `actions/checkout` is at v7.0.1. v7's only breaking change blocks fork checkouts under
  `pull_request_target`/`workflow_run`, which this workflow doesn't use.

Conventions: match `scripts/check.sh`'s existing style: `# --- Section ----` dividers, one
`- tool: ...` status line per guard, `status=1` on failure, never `exit` mid-script. The
downstream doctrine (`TESTING.md`) calls for gates that are "fail-closed in CI". This plan
applies that to the secret-scan guard.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Self-test | `./scripts/template-selftest.sh` | `selftest: 16 passed, 0 failed, 0 skipped` (9 from plan 001 + 7 here) |
| Just this plan's tests | `./scripts/template-selftest.sh check_` and `./scripts/template-selftest.sh gitignore` | all ok |
| Guard on the real repo | `./scripts/check.sh` | exit 0, `OK: checks passed.` |
| Shell lint | `shellcheck bootstrap scripts/check.sh scripts/template-selftest.sh` | exit 0 |
| YAML parses | `ruby -e 'require "yaml"; YAML.load_file(ARGV[0])' .github/workflows/ci.yml.example` | exit 0 |

gitleaks must be installed locally for the numbers above (`brew install gitleaks`; the
maintainer has 8.30.1). Without it, 5 of the new tests report `skip` and CI treats skips as
failures.

## Suggested executor toolkit

- gstack `/cso` (security audit) is optional: point it at the diff for a second opinion on the
  scan scope. Don't let it widen the scope.
- gstack `/review` on the finished diff.
- Do not run gstack `/ship` unless asked (see the shipping caveat in `plans/README.md`).

## Scope

**In scope** (the only files you should modify):

- `scripts/check.sh`
- `.gitignore` (the env block, lines 7–10)
- `.gitleaks.toml` (the first allowlist path, line 10)
- `.github/workflows/ci.yml.example`
- `scripts/template-selftest.sh` (append tests above the runner)
- `plans/README.md` (your status row)

**Out of scope** (do NOT touch):

- `bootstrap` (plans 001/003).
- `.editorconfig` and markdown indentation. editorconfig-checker stays *advisory*. Known
  finding #8 in `plans/README.md` says it likely fails on 3-space markdown list indents, so
  requiring it in CI now would turn CI red. Don't fix that here.
- `.github/workflows/template-selftest.yml` (plan 001's). Leave its install step alone even
  though it looks like the one you'll add to `ci.yml.example`.
- The other `.gitleaks.toml` allowlist entries (`tests?/fixtures/`, `CHANGELOG.md`). They're
  deliberate. Don't prune them.
- Renaming `ci.yml.example` to `ci.yml`. It must stay inert.

## Git workflow

- Work on the branch you were given (Conductor: `willtraweek/<topic>`). If you must create one:
  `willtraweek/plan-002-check-guards`.
- One commit per step, plain imperative messages, e.g.
  `Scope the secret scan to files git would commit`.
- Do NOT push or open a PR unless the operator told you to.

## Steps

### Step 1: Add the failing tests first

Insert this block into `scripts/template-selftest.sh` immediately **above** the
`# --- runner ---` line. It needs no changes to other tests.

```bash
# --- tests: check.sh secret-scan scope and CI behavior (plan 002) -------------
check_fixture() {  # $1 = dir: a committed git copy of the template, ready for check.sh
  fresh_copy "$1"
  (cd "$1" && git init -q && git add -A && git commit -qm init)
}
fake_token() {  # synthetic, freshly random GitHub-token-shaped string; never a real credential
  printf 'ghp_%s' "$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 36)"
}
run_check() {  # $1 = dir, rest = VAR=value env overrides. Output goes to "$1.out".
  # editorconfig-checker is hidden so these tests isolate the gitleaks guard.
  local dir="$1"; shift
  (cd "$dir" && env EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker "$@" \
    ./scripts/check.sh >"$dir.out" 2>&1)
}
test_check_ignores_gitignored_secret_file() {
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-ignored/proj"
  check_fixture "$d" || fail "fixture setup failed" || return 1
  # A deleted final tracked path must not make the copy pipeline fail under pipefail.
  printf 'delete me\n' > "$d/zzzz-deleted.txt"
  (cd "$d" && git add zzzz-deleted.txt && rm zzzz-deleted.txt) || return 1
  printf 'GITHUB_TOKEN=%s\n' "$(fake_token)" > "$d/.env"
  run_check "$d" || fail "check.sh flagged a gitignored file: $(tail -5 "$d.out")"
}
test_check_flags_force_added_secret_file_without_printing_it() {
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-forced/proj" tok rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  tok="$(fake_token)"
  printf 'GITHUB_TOKEN=%s\n' "$tok" > "$d/.env"
  (cd "$d" && git add -f .env) || fail "git add -f failed" || return 1
  run_check "$d"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" ".env" || return 1
  assert_not_contains "$d.out" "$tok"
}
test_check_flags_untracked_committable_secret_file() {
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-untracked/proj" rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  printf 'token = "%s"\n' "$(fake_token)" > "$d/notes.txt"
  run_check "$d"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "notes.txt"
}
test_check_fails_when_gitleaks_missing_in_ci() {
  local d="$WORK/check-ci-missing/proj" rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  run_check "$d" CI=true GITLEAKS_BIN=/nonexistent/gitleaks; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "REQUIRED in CI"
}
test_check_skips_missing_gitleaks_locally() {
  local d="$WORK/check-local-missing/proj"
  check_fixture "$d" || fail "fixture setup failed" || return 1
  run_check "$d" CI= GITLEAKS_BIN=/nonexistent/gitleaks \
    || fail "check.sh failed locally without gitleaks: $(tail -5 "$d.out")" || return 1
  assert_contains "$d.out" "gitleaks not installed - skipping"
}

# --- tests: .env example hygiene (plan 002) -----------------------------------
test_gitignore_keeps_env_example_files_committable() {
  local d="$WORK/gitignore/proj" f
  check_fixture "$d" || fail "fixture setup failed" || return 1
  for f in .env.example .env.local.example; do
    (cd "$d" && ! git check-ignore -q "$f") || fail "$f is gitignored" || return 1
  done
  for f in .env .env.local .env.production; do
    (cd "$d" && git check-ignore -q "$f") || fail "$f is NOT gitignored" || return 1
  done
}
test_check_allowlists_env_example_files() {
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-env-example/proj" f
  check_fixture "$d" || fail "fixture setup failed" || return 1
  for f in .env.example .env.local.example; do
    printf 'GITHUB_TOKEN=%s\n' "$(fake_token)" > "$d/$f"
  done
  (cd "$d" && git add .env.example .env.local.example) || fail "an .env example file is gitignored" || return 1
  run_check "$d" || fail "check.sh flagged an allowlisted example file: $(tail -5 "$d.out")"
}
```

The token is generated at run time on purpose. A token-shaped literal committed in the harness
would itself trip gitleaks on the template.

**Verify**: `./scripts/template-selftest.sh` → `selftest: 9 passed, 7 failed, 0 skipped`. The 7
failures are exactly the 7 new tests. This was checked against the current files. Every new
test fails for a real reason: no `-v` output, no `GITLEAKS_BIN`, the gitignore gap, or the
allowlist gap.

### Step 2: Rewrite `scripts/check.sh`

Replace the whole file with the following (prototyped; shellcheck-clean; bash 3.2 OK):

```bash
#!/usr/bin/env bash
# Stack-neutral pre-test guards. Runs before the test suite, locally and in CI.
# Add project-specific checks here as the codebase grows (the "guards run before
# tests" convention). Each guard should fail loudly and set status=1.
#
# A guard whose tool is missing is skipped locally with a notice, but FAILS in CI
# (CI=true, which GitHub Actions sets): a guard that silently skips in CI protects
# nothing. Exception: editorconfig-checker stays advisory everywhere for now.
# Override tool paths with GITLEAKS_BIN / EDITORCONFIG_CHECKER_BIN.
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
ran_any=0
root="$(pwd)"
GITLEAKS_BIN="${GITLEAKS_BIN:-gitleaks}"
EDITORCONFIG_CHECKER_BIN="${EDITORCONFIG_CHECKER_BIN:-editorconfig-checker}"

# --- Secret scanning: exactly the files git would commit --------------------
# Gitignored files (.env, local config) are deliberately NOT scanned: that is
# where local secrets belong. Tracked files and untracked-but-committable files
# are. A force-added .env is tracked, so it IS scanned.
if command -v "$GITLEAKS_BIN" >/dev/null 2>&1; then
  ran_any=1
  echo "- gitleaks: scanning the files git would commit..."
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    scan_dir="$(mktemp -d "${TMPDIR:-/tmp}/check-gitleaks.XXXXXX")"
    trap 'rm -rf "$scan_dir"' EXIT
    git ls-files -z --cached --others --exclude-standard \
      | while IFS= read -r -d '' f; do if [ -f "$f" ]; then printf '%s\0' "$f"; fi; done \
      | tar --null -T - -cf - | tar -xf - -C "$scan_dir"
    (cd "$scan_dir" && "$GITLEAKS_BIN" dir --no-banner --redact -v -c "$root/.gitleaks.toml" .) || status=1
  else
    "$GITLEAKS_BIN" dir --no-banner --redact -v -c .gitleaks.toml . || status=1
  fi
elif [ "${CI:-}" = "true" ]; then
  echo "- gitleaks not installed - REQUIRED in CI (see .github/workflows/ci.yml.example)." >&2
  status=1
else
  echo "- gitleaks not installed - skipping secret scan (brew install gitleaks)."
fi

# --- Formatting conformance (advisory; runs only if installed) ---------------
if command -v "$EDITORCONFIG_CHECKER_BIN" >/dev/null 2>&1; then
  ran_any=1
  echo "- editorconfig-checker: checking formatting..."
  "$EDITORCONFIG_CHECKER_BIN" || status=1
else
  echo "- editorconfig-checker not installed - skipping format check."
fi

if [ "$status" = "0" ]; then
  [ "$ran_any" = "1" ] && echo "OK: checks passed." || echo "OK: no checks configured yet."
fi
exit "$status"
```

Why a temp copy instead of scanning in place: `gitleaks dir` takes one path and has no
"respect .gitignore" option. Copying exactly `git ls-files --cached --others --exclude-standard`
is the precise "what `git add -A` would commit" set. The non-git branch covers a template copy
that hasn't been `git init`-ed yet.

**Verify**: `./scripts/template-selftest.sh` → `selftest: 14 passed, 2 failed, 0 skipped`. The
remaining failures are `test_gitignore_keeps_env_example_files_committable` and
`test_check_allowlists_env_example_files`. `./scripts/check.sh` → exit 0.
`shellcheck scripts/check.sh` → exit 0.

### Step 3: Make `.env.example` committable and allowlisted

In `.gitignore`, change lines 7–10 to:

```gitignore
# --- Secrets / env (keep the *.example templates) ---
.env
.env.*
!.env.example
!.env.*.example
```

In `.gitleaks.toml`, change the first allowlist path (line 10) from `'''\.env\..*\.example$''',`
to:

```toml
  '''\.env(\..*)?\.example$''',
```

(`(\..*)?` makes the middle segment optional, so it matches both `.env.example` and
`.env.local.example` but not `.env`.)

**Verify**: `./scripts/template-selftest.sh` → `selftest: 16 passed, 0 failed, 0 skipped`.
`cd "$(mktemp -d)" && git init -q && cp "$OLDPWD/.gitignore" . && git check-ignore .env.example; echo $?; cd "$OLDPWD"`
→ prints `1` (not ignored).

### Step 4: Harden the downstream CI skeleton

Replace the whole of `.github/workflows/ci.yml.example` with the content below. Compared with
today, it adds one header-comment line, a `permissions:` block, `actions/checkout@v7` (was
`@v4`), and a pinned gitleaks install step. The install step is the same block as plan 001's
template workflow; its SHA256 matches the published v8.30.1 checksum, and the step's shell
logic was run successfully while planning. The file stays inert (`.example`) and keeps its
`{{INSTALL_CMD}}` / `{{TEST_CMD}}` placeholders. This exact content was parsed with ruby's YAML
loader while planning.

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

      # - name: Install
      #   run: {{INSTALL_CMD}}

      - name: Checks (guards run before tests)
        run: ./scripts/check.sh

      # - name: Tests
      #   run: {{TEST_CMD}}
```

**Verify**:

- `ruby -e 'require "yaml"; YAML.load_file(ARGV[0])' .github/workflows/ci.yml.example` → exit 0
- `grep -c 'actions/checkout@v7' .github/workflows/ci.yml.example` → `1`
- `grep -c 'contents: read' .github/workflows/ci.yml.example` → `1`
- `grep -c '{{INSTALL_CMD}}\|{{TEST_CMD}}' .github/workflows/ci.yml.example` → `3` (unchanged)
- `ls .github/workflows/ci.yml 2>/dev/null` → no output (still inert)

## Test plan

- 7 new tests in `scripts/template-selftest.sh`, listed in step 1. Together they cover:
  gitignored secret file ignored, force-added one caught, untracked-committable one caught,
  secret value never printed, CI fail-closed, local skip, `.env.example` committable, and
  `.env.example` allowlisted.
- Pattern to follow: plan 001's `test_bootstrap_rejects_bad_name`.
- Final: `./scripts/template-selftest.sh` → `16 passed, 0 failed, 0 skipped`.

## Done criteria

ALL must hold:

- [ ] `./scripts/template-selftest.sh` exits 0 with `16 passed, 0 failed, 0 skipped` (gitleaks installed)
- [ ] `CI=true ./scripts/template-selftest.sh` exits 0
- [ ] `./scripts/check.sh` exits 0 on the real repo
- [ ] `grep -c 'detect --no-git' scripts/check.sh` → `0`
- [ ] `shellcheck bootstrap scripts/check.sh scripts/template-selftest.sh` exits 0
- [ ] `ruby -e 'require "yaml"; YAML.load_file(ARGV[0])' .github/workflows/ci.yml.example` exits 0
- [ ] `git status --porcelain` shows changes only to the in-scope files
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- After step 1, the failure count is not exactly 7, or a plan-001 test starts failing.
- `gitleaks dir` rejects `-v`/`--redact`/`-c` on your installed version. Report
  `gitleaks version`. Do not switch to a different subcommand on your own.
- `./scripts/check.sh` fails on the real repo after step 2 with a gitleaks finding. Something
  committable looks like a secret. Report the file and rule ID only, **never the value**, and
  do not allowlist it.
- Making a test pass seems to require editing `.editorconfig`, any markdown file, `bootstrap`,
  or `template-selftest.yml`.

## Maintenance notes

- **Two copies of the gitleaks install block** exist: `ci.yml.example` (downstream) and
  `template-selftest.yml` (plan 001). When bumping gitleaks, change the version and the SHA256
  in both, and take the SHA from the release's `gitleaks_<ver>_checksums.txt`. A third copy
  would justify extracting a composite action (rule of three).
- **editorconfig-checker is advisory by design here.** Once finding #8 is fixed (the template's
  markdown passes it), make it required in CI too. Mirror the gitleaks
  `elif [ "${CI:-}" = "true" ]` branch and add a pinned install step (v4.0.2's
  `editorconfig-checker-linux-amd64.tar.gz`, SHA256
  `44efaef3ed14c6ab52eb87481d78e5e5c204796dccf26e2f4598a61ba17f8003`, checked against its
  `checksums.txt`).
- The scan covers the working tree only, not git history. A secret committed and later deleted
  is still in history. If a project needs that, add a CI-only `gitleaks git` step (with a
  `.gitleaksignore` baseline for rotated secrets). Deferred: most template users won't need it
  on day one.
- The `.env*.example` allowlist is a deliberate trade-off: realistic placeholders don't raise
  false alarms, but a real key pasted into an example file won't be caught. If that trade-off
  flips, delete the first allowlist entry. `test_check_allowlists_env_example_files` will then
  need to invert.
- Reviewer focus: the `git ls-files ... | tar` pipeline (it defines what "committable" means)
  and the CI branch's message pointing to the install step.
