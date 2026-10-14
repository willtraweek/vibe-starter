#!/usr/bin/env bash
# Template self-test for vibe-starter. TEMPLATE-ONLY: ./bootstrap deletes this
# file, so it never ships into projects created from the template.
#
# Exercises ./bootstrap and scripts/check.sh against throwaway copies of this
# working tree (exactly the files git would commit, uncommitted edits included).
# Nothing in the real checkout is modified.
#
# Usage: scripts/template-selftest.sh [substring]   # only tests whose name contains it
#        scripts/template-selftest.sh --print-inventory   # the golden placeholder inventory
#        SELFTEST_EXCLUDE=<substring>   # skip tests whose name contains it; not counted as skips
#        SELFTEST_HEAVY=1               # also build real projects locally (test_heavy_*)
#        SELFTEST_RUST_TOOLCHAIN=<channel>  # run the Rust tests on it (default: stable)
#        SELFTEST_CARGO_TARGET_DIR=<dir>    # the heavy Rust tests build under <dir>/<pack>
#
# Portability: must run on macOS /bin/bash 3.2 and on Linux bash 5. No mapfile,
# no associative arrays, no ${var,,}, no `local -n`.
set -uo pipefail   # no -e: one failing assertion must not abort the whole run

# git exports GIT_DIR and friends to aliases, hooks, `rebase -x` and
# `bisect run`. Left set, the `git init` in a temp copy re-initializes the
# caller's repository instead (as bare, from a linked worktree), so drop them.
for v in $(git rev-parse --local-env-vars); do unset "$v"; done

# Same resolution as scripts/check.sh: follow symlinks, and clear CDPATH for the cd only.
script="$0"
while [ -L "$script" ]; do
  link=$(readlink "$script")
  case "$link" in
    /*) script="$link" ;;
    *) script="$(dirname "$script")/${link}" ;;
  esac
done
REPO="$(CDPATH='' cd "$(dirname "$script")/.." && pwd)" || exit 1
if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "selftest: $REPO is not a git checkout (fresh_copy needs git ls-files)" >&2
  exit 2
fi
# Unchecked, a failed mktemp leaves WORK empty and roots every fixture at /.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/vs-selftest.XXXXXX")" || {
  echo "selftest: cannot create a temp dir under ${TMPDIR:-/tmp}" >&2
  exit 2
}
trap 'rm -rf "$WORK"' EXIT
FILTER="${1:-}"
EXCLUDE="${SELFTEST_EXCLUDE:-}"
PASS=0; FAIL=0; SKIP=0; EXCLUDED=0

# Real tool homes, captured before any test sandboxes HOME (see stack_env).
REAL_UV_CACHE_DIR="${UV_CACHE_DIR:-$(uv cache dir 2>/dev/null || echo "$HOME/.cache/uv")}"
REAL_UV_PYTHON_DIR="${UV_PYTHON_INSTALL_DIR:-$(uv python dir 2>/dev/null || echo "$HOME/.local/share/uv/python")}"
REAL_CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
REAL_RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
# pnpm 12 reads pnpm_config_* (and PNPM_CONFIG_*) variables, not npm_config_*.
# `pnpm store path` ends in the store layout version (/v11); the setting is its parent.
REAL_PNPM_STORE_DIR="$(pnpm store path 2>/dev/null | sed 's|/v[0-9][0-9]*$||' || true)"
REAL_PNPM_STORE_DIR="${REAL_PNPM_STORE_DIR:-$HOME/.pnpm-store}"
case "$(uname -s)" in
  Darwin) REAL_PNPM_CACHE_DIR="$HOME/Library/Caches/pnpm" REAL_PNPM_HOME="$HOME/Library/pnpm"
    REAL_PLAYWRIGHT_BROWSERS_PATH="$HOME/Library/Caches/ms-playwright" ;;
  *) REAL_PNPM_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pnpm" REAL_PNPM_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/pnpm"
    REAL_PLAYWRIGHT_BROWSERS_PATH="${XDG_CACHE_HOME:-$HOME/.cache}/ms-playwright" ;;
esac
REAL_PNPM_CACHE_DIR="${pnpm_config_cache_dir:-${PNPM_CONFIG_CACHE_DIR:-$REAL_PNPM_CACHE_DIR}}"
REAL_PNPM_HOME="${PNPM_HOME:-$REAL_PNPM_HOME}"
REAL_PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$REAL_PLAYWRIGHT_BROWSERS_PATH}"

# Hermetic git: ignore the user's global/system config (signing, hooks,
# templates) and use a fixed identity for any test commits.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.invalid
export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.invalid
unset GIT_TEMPLATE_DIR   # an env var, not config: it would still install the user's hooks
unset GITLEAKS_BIN EDITORCONFIG_CHECKER_BIN   # check.sh overrides: tests set them explicitly
unset CARGO_TARGET_DIR   # a test that builds picks its own (the heavy ones: SELFTEST_CARGO_TARGET_DIR)
unset PREFIX BINDIR APPDIR ICONDIR DESKTOP_FILE_VALIDATE_BIN   # install.sh and guard overrides

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
  assert_absent "$d/template" || return 1
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
  (cd "$d" && ./scripts/check.sh >"$d.out" 2>&1) || fail "check.sh exited $?: $(tail -5 "$d.out")" || return 1
  # Exit 0 alone would also cover check.sh quietly skipping the scan.
  assert_contains "$d.out" "- gitleaks: scanning"
}

# --- tests: the harness itself ------------------------------------------------
# These re-run the harness; VS_SELFTEST_NESTED keeps a nested run from recursing.
test_selftest_ignores_inherited_git_env() {
  # git hands GIT_DIR (and, from hooks, GIT_INDEX_FILE) to aliases, hooks,
  # `rebase -x` and `bisect run`, and users may export GIT_TEMPLATE_DIR. Nested
  # runs under all of them must still use only their own temp repos. The
  # worktree-style gitdir makes git guess "bare"; the template hook rejects
  # every commit. The check_passes leg is the one that runs `git add`/`commit`.
  [ -z "${VS_SELFTEST_NESTED:-}" ] || { skip "nested run"; return; }
  local d="$WORK/inherited-git-env" legs="happy_path" leg
  command -v gitleaks >/dev/null 2>&1 && legs="$legs check_passes"
  mkdir -p "$d/templates/hooks"
  printf '#!/bin/sh\necho "inherited template hook ran" >&2\nexit 1\n' > "$d/templates/hooks/commit-msg"
  chmod +x "$d/templates/hooks/commit-msg"
  git init -q --separate-git-dir "$d/caller.git" "$d/caller" || fail "caller repo setup failed" || return 1
  for leg in $legs; do
    VS_SELFTEST_NESTED=1 GIT_DIR="$d/caller.git" GIT_WORK_TREE="$d/caller" \
      GIT_INDEX_FILE="$d/caller.git/index" GIT_TEMPLATE_DIR="$d/templates" \
      "$REPO/scripts/template-selftest.sh" "$leg" >"$d.$leg.out" 2>&1 \
      || fail "nested $leg run failed: $(tail -3 "$d.$leg.out")" || return 1
    assert_contains "$d.$leg.out" "selftest: 1 passed" || return 1
  done
  [ "$(git --git-dir="$d/caller.git" config --bool core.bare)" = "false" ] \
    || fail "a nested run re-initialized the GIT_DIR repository" || return 1
  assert_absent "$d/caller.git/index" || return 1
  ! git --git-dir="$d/caller.git" rev-parse -q --verify HEAD >/dev/null \
    || fail "a nested run committed into the GIT_DIR repository"
}
test_selftest_refuses_an_unusable_tmpdir() {
  # The filter matches no test, so even a regressed harness creates nothing.
  [ -z "${VS_SELFTEST_NESTED:-}" ] || { skip "nested run"; return; }
  local d="$WORK/bad-tmpdir" rc
  mkdir -p "$d"
  VS_SELFTEST_NESTED=1 TMPDIR="$d/missing" "$REPO/scripts/template-selftest.sh" no-such-test >"$d.out" 2>&1; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "cannot create a temp dir"
}

# --- tests: check.sh secret-scan scope and CI behavior (plan 002) -------------
check_fixture() {  # $1 = dir: a committed git copy of the template, ready for check.sh
  fresh_copy "$1"
  # core.excludesFile: GIT_CONFIG_GLOBAL=/dev/null still leaves ~/.config/git/ignore on.
  (cd "$1" && git init -q && git config core.excludesFile /dev/null && git add -A && git commit -qm init)
}
fake_token() {  # synthetic, freshly random GitHub-token-shaped string; never a real credential
  printf 'ghp_%s' "$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 36)"
}
run_check() {  # $1 = dir, rest = VAR=value env overrides. Output goes to "$1.out".
  # editorconfig-checker is hidden so these tests isolate the gitleaks guard.
  # Blank vendor CI variables first: GitHub sets GITHUB_ACTIONS, and a later
  # VAR=value argument (same names as ci_requires_gitleaks) overrides the blank.
  local dir="$1"; shift
  (cd "$dir" && env EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker \
    GITHUB_ACTIONS= GITLAB_CI= JENKINS_URL= BUILDKITE= CIRCLECI= TRAVIS= \
    TF_BUILD= APPVEYOR= DRONE= WOODPECKER= TEAMCITY_VERSION= \
    CODEBUILD_BUILD_ID= BITBUCKET_BUILD_NUMBER= CIRRUS_CI= CONTINUOUS_INTEGRATION= \
    "$@" ./scripts/check.sh >"$dir.out" 2>&1)
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
# $1 = output file, $2 = secret or fragment. The failure text never includes $2.
assert_omits_secret() {
  if grep -qF -- "$2" "$1"; then
    fail "secret scan output included a secret or an 8-character fragment"
    return 1
  fi
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
  assert_contains "$d.out" ".env:1:github-pat" || return 1
  assert_omits_secret "$d.out" "$tok" || return 1
  assert_omits_secret "$d.out" "${tok:4:8}"
}
test_check_flags_two_secrets_on_one_line_without_printing_them() {
  # -v prints ~20 characters of context around each finding, so redacting one
  # secret still leaks the other when both share a line.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-two-secrets/proj" tok_a tok_b rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  tok_a="$(fake_token)"
  tok_b="$(fake_token)"
  printf 'GITHUB_TOKEN=%s %s\n' "$tok_a" "$tok_b" > "$d/.env"
  (cd "$d" && git add -f .env) || fail "git add -f failed" || return 1
  run_check "$d"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" ".env:1:github-pat" || return 1
  assert_omits_secret "$d.out" "$tok_a" || return 1
  assert_omits_secret "$d.out" "$tok_b" || return 1
  assert_omits_secret "$d.out" "${tok_a:4:8}" || return 1
  assert_omits_secret "$d.out" "${tok_b:4:8}"
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
test_check_scans_this_repo_when_git_env_points_elsewhere() {
  # GIT_DIR / GIT_WORK_TREE for another repository must not redirect the scan.
  # A clean fixture exits 0 and must not mention that repo's secret; a
  # committable secret here must still be reported. The token is checked only
  # against the output file so a failure message never prints it.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-foreign-git-env/proj" other="$WORK/check-foreign-git-env/other"
  local foreign foreign_git foreign_wt rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  foreign="$(fake_token)"
  mkdir -p "$other"
  (
    cd "$other" \
      && git init -q \
      && git config core.excludesFile /dev/null \
      && printf '%s' "$foreign" > leak.txt \
      && git add leak.txt \
      && git commit -qm leak
  ) || fail "foreign repo setup failed" || return 1
  foreign_git="$(git -C "$other" rev-parse --absolute-git-dir)"
  foreign_wt="$(git -C "$other" rev-parse --show-toplevel)"
  run_check "$d" GIT_DIR="$foreign_git" GIT_WORK_TREE="$foreign_wt"; rc=$?
  assert_omits_secret "$d.out" "$foreign" || return 1
  assert_exit 0 "$rc" || fail "clean fixture failed under a foreign GIT_DIR: $(tail -8 "$d.out")" || return 1
  printf 'token = "%s"\n' "$(fake_token)" > "$d/zz-committable-secret.txt"
  run_check "$d" GIT_DIR="$foreign_git" GIT_WORK_TREE="$foreign_wt"; rc=$?
  assert_omits_secret "$d.out" "$foreign" || return 1
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "zz-committable-secret.txt:1:github-pat" || return 1
  # GIT_DIR alone makes this directory that repo's work tree. Its index lacks
  # this repo's force-added .env, which .gitignore then hides from the listing.
  rm "$d/zz-committable-secret.txt"
  printf 'GITHUB_TOKEN=%s\n' "$(fake_token)" > "$d/.env"
  (cd "$d" && git add -f .env) || fail "git add -f failed" || return 1
  run_check "$d" GIT_DIR="$foreign_git"; rc=$?
  assert_omits_secret "$d.out" "$foreign" || return 1
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" ".env:1:github-pat"
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
test_check_fails_when_gitleaks_missing_ci_is_1() {
  local d="$WORK/check-ci-1/proj" rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  run_check "$d" CI=1 GITLEAKS_BIN=/nonexistent/gitleaks; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "REQUIRED in CI"
}
test_check_fails_when_gitleaks_missing_ci_is_True() {
  local d="$WORK/check-ci-True/proj" rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  run_check "$d" CI=True GITLEAKS_BIN=/nonexistent/gitleaks; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "REQUIRED in CI"
}
test_check_fails_when_gitleaks_missing_github_actions() {
  local d="$WORK/check-gha-missing/proj" rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  # CI= clears an inherited CI=true so this asserts the vendor variable alone.
  run_check "$d" CI= GITHUB_ACTIONS=true GITLEAKS_BIN=/nonexistent/gitleaks; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "REQUIRED in CI"
}
test_check_skips_missing_gitleaks_when_ci_false_overrides_github_actions() {
  local d="$WORK/check-ci-false-gha/proj"
  check_fixture "$d" || fail "fixture setup failed" || return 1
  run_check "$d" CI=false GITHUB_ACTIONS=true GITLEAKS_BIN=/nonexistent/gitleaks \
    || fail "CI=false did not override GITHUB_ACTIONS: $(tail -5 "$d.out")" || return 1
  assert_contains "$d.out" "gitleaks not installed - skipping"
}
test_check_skips_missing_gitleaks_when_ci_is_0() {
  local d="$WORK/check-ci-0/proj"
  check_fixture "$d" || fail "fixture setup failed" || return 1
  # CI=0 is an explicit local skip and beats a vendor variable.
  run_check "$d" CI=0 GITHUB_ACTIONS=true GITLEAKS_BIN=/nonexistent/gitleaks \
    || fail "CI=0 did not skip: $(tail -5 "$d.out")" || return 1
  assert_contains "$d.out" "gitleaks not installed - skipping"
}
test_check_ci_requires_gitleaks_predicate() {
  # Every vendor variable, every CI spelling. The driver is a separate script
  # so it does not execute check.sh.
  local d="$WORK/check-ci-predicate"
  mkdir -p "$d"
  sed -n '/^ci_requires_gitleaks()/,/^}/p' "$REPO/scripts/check.sh" > "$d/predicate.sh"
  [ -s "$d/predicate.sh" ] || fail "could not extract ci_requires_gitleaks" || return 1
  cat > "$d/driver.sh" << 'EOF'
#!/bin/bash
set -u
d="$1"
# shellcheck disable=SC1091
. "$d/predicate.sh"
vendors="GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILDKITE CIRCLECI TRAVIS TF_BUILD APPVEYOR DRONE WOODPECKER TEAMCITY_VERSION CODEBUILD_BUILD_ID BITBUCKET_BUILD_NUMBER CIRRUS_CI CONTINUOUS_INTEGRATION"
unset CI
for name in $vendors; do
  unset "$name"
done
if ci_requires_gitleaks; then
  echo "nothing set was treated as CI"
  exit 1
fi
for name in $vendors; do
  unset CI
  printf -v "$name" '%s' 'x'
  ci_requires_gitleaks || { echo "$name was not treated as CI"; exit 1; }
  CI=false
  if ci_requires_gitleaks; then
    echo "CI=false did not win over $name"
    exit 1
  fi
  unset "$name"
done
GITHUB_ACTIONS=true
for v in 0 no NO False FALSE; do
  CI="$v"
  if ci_requires_gitleaks; then
    echo "CI=$v did not win over GITHUB_ACTIONS"
    exit 1
  fi
done
unset GITHUB_ACTIONS
# Any other non-empty value counts (Woodpecker sets CI=woodpecker).
for v in 1 true True yes YES woodpecker; do
  CI="$v"
  ci_requires_gitleaks || { echo "CI=$v was not treated as CI"; exit 1; }
done
EOF
  /bin/bash "$d/driver.sh" "$d" >"$d.out" 2>&1 \
    || fail "ci_requires_gitleaks: $(cat "$d.out")" || return 1
}
test_check_honors_a_relative_gitleaks_bin() {
  # The scan runs from a temp copy, so a relative GITLEAKS_BIN (here in an
  # ignored tools dir, absent from that copy) must be resolved beforehand.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-relbin/proj"
  check_fixture "$d" || fail "fixture setup failed" || return 1
  mkdir -p "$d/.tools" && printf '.tools/\n' >> "$d/.git/info/exclude" || return 1
  printf '#!/bin/sh\ntouch "%s"\nexec "%s" "$@"\n' "$d.used" "$(command -v gitleaks)" > "$d/.tools/gitleaks"
  chmod +x "$d/.tools/gitleaks"
  run_check "$d" GITLEAKS_BIN=.tools/gitleaks \
    || fail "check.sh failed with a relative GITLEAKS_BIN: $(tail -3 "$d.out")" || return 1
  assert_exists "$d.used"
}
test_check_scans_every_file_when_git_would_not_commit_it() {
  # A template copy with no `git init` of its own, inside a gitignored folder of
  # another repo. rev-parse finds the outer repo, which lists nothing here, and a
  # scan of nothing would pass: check.sh must scan every file instead.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local outer="$WORK/outer-checkout/repo" copy="$WORK/outer-checkout/repo/nested"
  local out="$WORK/outer-checkout/check.out" before head_before rc
  mkdir -p "$outer"
  (cd "$outer" && git init -q && git config core.excludesFile /dev/null) \
    || fail "outer git init failed" || return 1
  printf 'nested/\n' > "$outer/.gitignore"
  printf 'outer\n' > "$outer/README"
  (cd "$outer" && git add .gitignore README && git commit -qm init) \
    || fail "outer commit failed" || return 1
  fresh_copy "$copy" || fail "fresh_copy failed" || return 1
  printf 'token = "%s"\n' "$(fake_token)" > "$copy/notes.txt"
  assert_absent "$copy/.git" || return 1
  [ -z "$(cd "$outer" && git status --porcelain)" ] || fail "setup left the outer repo dirty" || return 1
  before="$(tree_fingerprint "$outer")"
  head_before="$(cd "$outer" && git rev-parse HEAD)"
  # Output goes outside the outer repo, which must stay untouched.
  (
    cd "$copy" && env EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker \
      ./scripts/check.sh >"$out" 2>&1
  ); rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$out" "git would not commit this project" || return 1
  assert_contains "$out" "notes.txt:1:github-pat" || return 1
  [ "$(cd "$outer" && git status --porcelain && git rev-parse HEAD)" = "$head_before" ] \
    || fail "outer repo HEAD or status changed" || return 1
  [ "$before" = "$(tree_fingerprint "$outer")" ] || fail "outer repo was modified" || return 1
  assert_absent "$copy/.git"
}
test_check_scans_a_project_in_a_subdirectory_of_a_repo() {
  # A project can live below the root of a larger repository. It still gets
  # git's committable set: its gitignored .env is skipped, a committable secret
  # is caught.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local outer="$WORK/check-monorepo/repo" d="$WORK/check-monorepo/repo/packages/app" rc
  fresh_copy "$d" || fail "fresh_copy failed" || return 1
  (cd "$outer" && git init -q && git config core.excludesFile /dev/null \
    && git add -A && git commit -qm init) || fail "outer repo setup failed" || return 1
  printf 'GITHUB_TOKEN=%s\n' "$(fake_token)" > "$d/.env"
  run_check "$d" || fail "check.sh failed in a subdirectory project: $(tail -5 "$d.out")" || return 1
  assert_contains "$d.out" "scanning the files git would commit" || return 1
  printf 'token = "%s"\n' "$(fake_token)" > "$d/notes.txt"
  run_check "$d"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "notes.txt:1:github-pat"
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
  local d="$WORK/check-env-example/proj" f tok rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  mkdir -p "$d/config"
  for f in .env.example .env.local.example config/.env.example; do
    printf 'GITHUB_TOKEN=%s\n' "$(fake_token)" > "$d/$f"
  done
  (cd "$d" && git add .env.example .env.local.example config/.env.example) \
    || fail "an .env example file is gitignored" || return 1
  run_check "$d" || fail "check.sh flagged an allowlisted example file: $(tail -5 "$d.out")" || return 1
  # Shares only the .env.example suffix, so the allowlist must not cover it.
  tok="$(fake_token)"
  printf 'GITHUB_TOKEN=%s\n' "$tok" > "$d/prod.env.example"
  run_check "$d"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "prod.env.example" || return 1
  assert_omits_secret "$d.out" "$tok" || return 1
  assert_omits_secret "$d.out" "${tok:4:8}"
}
test_check_cdpath_does_not_redirect_the_scan() {
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-cdpath/proj" decoy="$WORK/check-cdpath/cdpath-decoy" rc invoke
  check_fixture "$d" || fail "fixture setup failed" || return 1
  # CDPATH is tried before `.`. A decoy that contains scripts/ wins `cd scripts/..`,
  # and a committable token there shows up only if that tree was the one scanned.
  check_fixture "$decoy" || fail "decoy setup failed" || return 1
  printf 'token = "%s"\n' "$(fake_token)" > "$decoy/decoy-secret.txt"
  (cd "$decoy" && git add decoy-secret.txt) || fail "git add failed" || return 1
  # bash does not search CDPATH for a target starting with / or ./. The bare
  # relative form does, and a CDPATH hit prints the chosen directory on stdout.
  for invoke in ./scripts/check.sh scripts/check.sh; do
    (cd "$d" && env EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker \
      CDPATH="$decoy" "$invoke" >"$d.out" 2>&1); rc=$?
    assert_exit 0 "$rc" || fail "$invoke exited $rc: $(tail -8 "$d.out")" || return 1
    assert_contains "$d.out" "- gitleaks: scanning" || return 1
    assert_not_contains "$d.out" "decoy-secret.txt" || return 1
    assert_not_contains "$d.out" "$decoy" || return 1
  done
}
test_check_symlinked_hook_scans_repo_root() {
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-symlink-hook/proj" rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  mkdir -p "$d/.git/hooks"
  ln -s ../../scripts/check.sh "$d/.git/hooks/pre-commit"
  # Relative path, as git invokes the hook (cwd is the work tree root).
  (cd "$d" && env EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker \
    .git/hooks/pre-commit >"$d.out" 2>&1); rc=$?
  assert_exit 0 "$rc" || fail "clean hook exited $rc: $(tail -8 "$d.out")" || return 1
  assert_contains "$d.out" "- gitleaks: scanning" || return 1
  printf 'token = "%s"\n' "$(fake_token)" > "$d/hook-secret.txt"
  (cd "$d" && env EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker \
    .git/hooks/pre-commit >"$d.out" 2>&1); rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "hook-secret.txt"
}
test_check_symlinked_hook_scans_the_worktree_being_committed() {
  # Linked worktrees share one hooks dir, so the link resolves to the main
  # checkout's check.sh. git runs it from the worktree being committed, and that
  # is the tree to scan: a clean main checkout must not let a secret through.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local main="$WORK/check-wt-hook/main" wt="$WORK/check-wt-hook/wt"
  check_fixture "$main" || fail "fixture setup failed" || return 1
  git -C "$main" worktree add -q -b wt "$wt" || fail "git worktree add failed" || return 1
  mkdir -p "$main/.git/hooks"
  ln -s ../../scripts/check.sh "$main/.git/hooks/pre-commit" || return 1
  printf 'clean\n' > "$wt/clean.txt"
  (cd "$wt" && git add clean.txt && EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker \
    git commit -qm clean >"$wt.out" 2>&1) \
    || fail "the hook blocked a clean commit: $(tail -5 "$wt.out")" || return 1
  printf 'token = "%s"\n' "$(fake_token)" > "$wt/wt-secret.txt"
  (cd "$wt" && git add wt-secret.txt && ! EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker \
    git commit -qm secret >"$wt.out" 2>&1) \
    || fail "the hook let a secret through: $(tail -5 "$wt.out")" || return 1
  assert_contains "$wt.out" "wt-secret.txt:1:github-pat"
}
test_check_symlinked_hook_scans_a_subdirectory_project_in_the_worktree() {
  # The same for a project below the repo root: the hook links to
  # packages/app/scripts/check.sh, and the worktree's own copy must be scanned.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local main="$WORK/check-wt-sub/main" wt="$WORK/check-wt-sub/wt"
  fresh_copy "$main/packages/app" || fail "fresh_copy failed" || return 1
  (cd "$main" && git init -q && git config core.excludesFile /dev/null \
    && git add -A && git commit -qm init) || fail "repo setup failed" || return 1
  git -C "$main" worktree add -q -b wt "$wt" || fail "git worktree add failed" || return 1
  mkdir -p "$main/.git/hooks"
  ln -s ../../packages/app/scripts/check.sh "$main/.git/hooks/pre-commit" || return 1
  printf 'token = "%s"\n' "$(fake_token)" > "$wt/packages/app/wt-secret.txt"
  (cd "$wt" && git add packages/app/wt-secret.txt \
    && ! EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker git commit -qm secret >"$wt.out" 2>&1) \
    || fail "the hook let a secret through: $(tail -5 "$wt.out")" || return 1
  assert_contains "$wt.out" "wt-secret.txt:1:github-pat"
}
test_check_symlinked_hook_refuses_a_worktree_without_check_sh() {
  # A linked worktree on a branch without check.sh (say gh-pages) has no copy to
  # run. Checking the main checkout instead would let any commit through.
  local main="$WORK/check-wt-bare/main" wt="$WORK/check-wt-bare/site"
  check_fixture "$main" || fail "fixture setup failed" || return 1
  git -C "$main" worktree add -q -b site "$wt" || fail "git worktree add failed" || return 1
  (cd "$wt" && git rm -rq scripts && git commit -qm "no scripts") || fail "branch setup failed" || return 1
  mkdir -p "$main/.git/hooks"
  ln -s ../../scripts/check.sh "$main/.git/hooks/pre-commit" || return 1
  printf 'token = "%s"\n' "$(fake_token)" > "$wt/leak.txt"
  (cd "$wt" && git add leak.txt \
    && ! EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker git commit -qm leak >"$wt.out" 2>&1) \
    || fail "the hook let a commit through: $(tail -5 "$wt.out")" || return 1
  assert_contains "$wt.out" "not checking a different checkout"
}

# --- tests: check.sh paths found by the /ship coverage audit (plan 002) --------
test_check_scans_the_committable_set_before_the_first_commit() {
  # ./bootstrap runs git init and commits nothing, so check.sh itself is only
  # untracked-but-committable. It still gets git's committable set: the
  # gitignored .env is skipped and an untracked secret is caught.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-first-commit/proj" rc
  fresh_copy "$d" || fail "fresh_copy failed" || return 1
  (cd "$d" && git init -q && git config core.excludesFile /dev/null) || fail "git init failed" || return 1
  printf 'GITHUB_TOKEN=%s\n' "$(fake_token)" > "$d/.env"
  run_check "$d" || fail "check.sh flagged a gitignored file before the first commit: $(tail -5 "$d.out")" || return 1
  assert_contains "$d.out" "- gitleaks: scanning the files git would commit" || return 1
  printf 'token = "%s"\n' "$(fake_token)" > "$d/notes.txt"
  run_check "$d"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "notes.txt:1:github-pat"
}
test_check_scans_its_own_project_when_run_from_elsewhere() {
  # CI steps, Makefiles and agents call check.sh by path from other directories:
  # from inside another repository, through a link from outside any repository,
  # or from a subdirectory. It scans its own project every time.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local base="$WORK/check-elsewhere" d="$WORK/check-elsewhere/proj" other="$WORK/check-elsewhere/other" rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  mkdir -p "$other" "$base/bin" && (cd "$other" && git init -q) || fail "other repo setup failed" || return 1
  printf 'token = "%s"\n' "$(fake_token)" > "$other/other-secret.txt"
  ln -s "$d/scripts/check.sh" "$base/bin/proj-check" || return 1
  (cd "$other" && env EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker \
    "$d/scripts/check.sh" >"$d.out" 2>&1); rc=$?
  assert_exit 0 "$rc" || fail "clean project failed when run from another repo: $(tail -5 "$d.out")" || return 1
  assert_contains "$d.out" "- gitleaks: scanning the files git would commit" || return 1
  assert_not_contains "$d.out" "other-secret.txt" || return 1
  (cd "$base" && env EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker \
    bin/proj-check >"$d.out" 2>&1); rc=$?
  assert_exit 0 "$rc" || fail "clean project failed through a link from outside a repo: $(tail -5 "$d.out")" || return 1
  assert_contains "$d.out" "- gitleaks: scanning the files git would commit" || return 1
  printf 'token = "%s"\n' "$(fake_token)" > "$d/proj-secret.txt"
  (cd "$d/docs" && env EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker \
    ../scripts/check.sh >"$d.out" 2>&1); rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "proj-secret.txt:1:github-pat"
}
test_check_hook_follows_a_link_chain_to_an_absolute_target() {
  # Hooks are often installed as `ln -s "$PWD/scripts/check.sh" ...`, sometimes
  # through a hooks dir of their own. Every hop, relative or absolute, must be
  # followed to the real check.sh, or the hook checks the wrong directory.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-link-chain/proj"
  check_fixture "$d" || fail "fixture setup failed" || return 1
  mkdir -p "$d/.git/hooks" "$d/tools/hooks"
  ln -s "$d/scripts/check.sh" "$d/tools/hooks/pre-commit" || return 1
  ln -s ../../tools/hooks/pre-commit "$d/.git/hooks/pre-commit" || return 1
  printf 'clean\n' > "$d/clean.txt"
  (cd "$d" && git add clean.txt && EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker \
    git commit -qm clean >"$d.out" 2>&1) \
    || fail "the hook blocked a clean commit: $(tail -5 "$d.out")" || return 1
  printf 'token = "%s"\n' "$(fake_token)" > "$d/hook-secret.txt"
  (cd "$d" && git add hook-secret.txt && ! EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker \
    git commit -qm secret >"$d.out" 2>&1) \
    || fail "the hook let a secret through: $(tail -5 "$d.out")" || return 1
  assert_contains "$d.out" "hook-secret.txt:1:github-pat"
}
test_check_scans_files_whose_names_git_would_quote() {
  # Without -z, git prints a non-ASCII path quoted and escaped. That name fails
  # [ -f ] and silently drops out of the copy, so its secret would pass.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-quoted-names/proj" name rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  name="$(printf 'caf\303\251 notes.txt')"
  printf 'token = "%s"\n' "$(fake_token)" > "$d/$name"
  run_check "$d"; rc=$?
  assert_exit 1 "$rc" || return 1
  # macOS bsdtar extracts the name as NFD, so match only its ASCII tail.
  assert_contains "$d.out" " notes.txt:1:github-pat"
}
test_check_fails_closed_when_the_copy_fails() {
  # A listing or copy that fails part-way (corrupt index, unreadable file, no
  # temp dir) must fail the guard: a partial or empty copy would pass files
  # nobody scanned. The git stub stands in for a corrupt index, and unlike
  # chmod 000 it also works as root.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-copy-fails/proj" bin="$WORK/check-copy-fails/bin" tmp="$WORK/check-copy-fails/tmp" rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  mkdir -p "$bin" "$tmp" || return 1
  printf '#!/bin/sh\ncase " $* " in *" ls-files -z "*) echo "stub: index unreadable" >&2; exit 128 ;; esac\nexec "%s" "$@"\n' \
    "$(command -v git)" > "$bin/git" && chmod +x "$bin/git" || fail "git stub setup failed" || return 1
  # printenv, not $PATH: shellcheck ties any $PATH read to the subshell PATH edit
  # in test_bootstrap_reports_a_failed_git_init (SC2030/SC2031).
  run_check "$d" PATH="$bin:$(printenv PATH)" TMPDIR="$tmp"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "could not copy the files git would commit - secret scan NOT run." || return 1
  assert_not_contains "$d.out" "OK:" || return 1
  [ -z "$(ls -A "$tmp")" ] || fail "the temp copy outlived a failed copy" || return 1
  run_check "$d" TMPDIR="$WORK/check-copy-fails/missing"; rc=$?
  [ "$rc" -ne 0 ] || fail "check.sh passed with no temp dir to copy into" || return 1
  assert_not_contains "$d.out" "OK:"
}
test_check_removes_its_temp_copy() {
  # The copy holds every committable file, force-added secrets included. It must
  # not outlive the run, whether the scan passes or finds something.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-cleanup/proj" tmp="$WORK/check-cleanup/tmp" rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  mkdir -p "$tmp" || return 1
  run_check "$d" TMPDIR="$tmp" || fail "clean scan failed: $(tail -5 "$d.out")" || return 1
  [ -z "$(ls -A "$tmp")" ] || fail "the temp copy outlived a clean scan" || return 1
  printf 'GITHUB_TOKEN=%s\n' "$(fake_token)" > "$d/.env"
  (cd "$d" && git add -f .env) || fail "git add -f failed" || return 1
  run_check "$d" TMPDIR="$tmp"; rc=$?
  assert_exit 1 "$rc" || return 1
  [ -z "$(ls -A "$tmp")" ] || fail "the temp copy outlived a scan with findings"
}
test_check_removes_its_temp_copy_when_interrupted() {
  # The EXIT trap covers a run killed mid-scan (Ctrl-C, a CI job timeout). The
  # stand-in scanner records its pid, then waits to be interrupted.
  local d="$WORK/check-interrupted/proj" bin="$WORK/check-interrupted/bin" tmp="$WORK/check-interrupted/tmp" pid i=0
  check_fixture "$d" || fail "fixture setup failed" || return 1
  mkdir -p "$bin" "$tmp" || return 1
  # It answers check.sh's `dir --help` version probe, then stands in for the scan.
  printf '#!/bin/sh\ncase "$*" in *--help*) echo "--report-template"; exit 0 ;; esac\necho $$ > "%s"\nexec sleep 30\n' \
    "$d.scanning" > "$bin/gitleaks" && chmod +x "$bin/gitleaks" \
    || fail "gitleaks stub setup failed" || return 1
  (cd "$d" && exec env EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker \
    GITLEAKS_BIN="$bin/gitleaks" TMPDIR="$tmp" ./scripts/check.sh >"$d.out" 2>&1) &
  pid=$!
  while [ ! -s "$d.scanning" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  [ -s "$d.scanning" ] || { kill "$pid" 2>/dev/null; fail "the stub scan never started: $(tail -3 "$d.out")"; return 1; }
  kill -TERM "$pid"; wait "$pid" 2>/dev/null
  kill "$(cat "$d.scanning")" 2>/dev/null
  [ -z "$(ls -A "$tmp")" ] || fail "the temp copy outlived an interrupted run"
}
test_check_honors_an_exported_function_as_gitleaks_bin() {
  # command -v prints a bare name for a function: call it as-is, not as $root/<name>.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-fn-bin/proj"
  check_fixture "$d" || fail "fixture setup failed" || return 1
  (
    # shellcheck disable=SC2329  # invoked through GITLEAKS_BIN
    fn_gitleaks() { touch "$FN_USED" && "$FN_REAL" "$@"; }
    export -f fn_gitleaks
    run_check "$d" GITLEAKS_BIN=fn_gitleaks FN_USED="$d.used" FN_REAL="$(command -v gitleaks)"
  ) || fail "check.sh failed with a function GITLEAKS_BIN: $(tail -3 "$d.out")" || return 1
  assert_exists "$d.used"
}
test_check_runs_an_installed_editorconfig_checker() {
  # Advisory means optional when missing; once installed, its verdict counts. With
  # gitleaks hidden, the final line also says whether any guard ran at all.
  local d="$WORK/check-ec/proj" bin="$WORK/check-ec/bin" rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  mkdir -p "$bin" || return 1
  printf '#!/bin/sh\nexit 0\n' > "$bin/ec-pass"
  printf '#!/bin/sh\necho "ec-fail: formatting error" >&2\nexit 1\n' > "$bin/ec-fail"
  chmod +x "$bin/ec-pass" "$bin/ec-fail" || return 1
  run_check "$d" CI= GITLEAKS_BIN=/nonexistent/gitleaks \
    || fail "check.sh failed with no tools installed: $(tail -5 "$d.out")" || return 1
  assert_contains "$d.out" "OK: no checks configured yet." || return 1
  run_check "$d" CI= GITLEAKS_BIN=/nonexistent/gitleaks EDITORCONFIG_CHECKER_BIN="$bin/ec-pass" \
    || fail "a passing editorconfig-checker failed the run: $(tail -5 "$d.out")" || return 1
  assert_contains "$d.out" "- editorconfig-checker: checking formatting..." || return 1
  assert_contains "$d.out" "OK: checks passed." || return 1
  run_check "$d" CI= GITLEAKS_BIN=/nonexistent/gitleaks EDITORCONFIG_CHECKER_BIN="$bin/ec-fail"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "ec-fail: formatting error" || return 1
  assert_not_contains "$d.out" "OK:"
}
test_check_env_example_allowlist_stops_at_a_directory() {
  # The allowlist matches a file name, not a path through a .env.<x>/ directory.
  # .gitignore hides such a directory, so only a force-added file reaches the scan.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-env-dir/proj" rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  mkdir -p "$d/.env.d"
  printf 'GITHUB_TOKEN=%s\n' "$(fake_token)" > "$d/.env.d/app.example"
  (cd "$d" && git add -f .env.d/app.example) || fail "git add -f failed" || return 1
  run_check "$d"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" ".env.d/app.example:1:github-pat"
}
test_ci_example_installs_the_gitleaks_the_template_ci_runs() {
  # ci.yml.example and the stack packs' ci.yml never run here. They must install
  # gitleaks exactly as template-selftest.yml does on every push: through the one
  # pinned, checksum-verified action (plan 006), never an inline copy that can drift.
  local wf f
  assert_contains "$REPO/.github/actions/install-gitleaks/action.yml" "GITLEAKS_SHA256: " || return 1
  for wf in "$REPO/.github/workflows/template-selftest.yml" "$REPO/.github/workflows/ci.yml.example" \
    "$REPO"/template/stacks/*/files/.github/workflows/ci.yml; do
    [ -f "$wf" ] || continue
    f="${wf#"$REPO"/}"
    grep -Eq '^ +uses: \./\.github/actions/install-gitleaks$' "$wf" \
      || fail "$f does not install gitleaks with ./.github/actions/install-gitleaks" || return 1
    assert_not_contains "$wf" "GITLEAKS_SHA256" || return 1
  done
}
test_selftest_finds_its_repo_through_a_link_or_cdpath() {
  # Same resolution as check.sh: a linked harness, or a bare relative call with a
  # CDPATH entry that has scripts/, must still find this checkout. The filter
  # matches no test, so each nested run only resolves REPO and reports 0 tests.
  [ -z "${VS_SELFTEST_NESTED:-}" ] || { skip "nested run"; return; }
  local d="$WORK/selftest-resolution"
  mkdir -p "$d/bin" "$d/decoy/scripts" || return 1
  ln -s "$REPO/scripts/template-selftest.sh" "$d/bin/vs-selftest" || return 1
  VS_SELFTEST_NESTED=1 "$d/bin/vs-selftest" no-such-test >"$d.link.out" 2>&1
  assert_contains "$d.link.out" "selftest: 0 passed, 0 failed, 0 skipped" || return 1
  (cd "$REPO" && CDPATH="$d/decoy" VS_SELFTEST_NESTED=1 scripts/template-selftest.sh no-such-test) >"$d.cdpath.out" 2>&1
  assert_contains "$d.cdpath.out" "selftest: 0 passed, 0 failed, 0 skipped"
}

# --- tests: hooks, git errors and gitleaks versions (/ship review, plan 002) --
test_check_hook_runs_the_committing_worktrees_own_check_sh() {
  # However a hook reaches the main checkout's check.sh (here a wrapper script,
  # not a link), a commit in a linked worktree runs that worktree's own copy
  # against that worktree: its secret is caught and its script edits apply.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local main="$WORK/check-wt-own/main" wt="$WORK/check-wt-own/wt" f
  check_fixture "$main" || fail "fixture setup failed" || return 1
  git -C "$main" worktree add -q -b wt "$wt" || fail "git worktree add failed" || return 1
  mkdir -p "$main/.git/hooks"
  cat > "$main/.git/hooks/pre-commit" << 'EOF'
#!/bin/sh
exec "$(dirname "$0")/../../scripts/check.sh" "$@"
EOF
  chmod +x "$main/.git/hooks/pre-commit" || return 1
  f="$wt/scripts/check.sh"
  { head -n 1 "$f"; echo 'echo "- the worktree copy of check.sh ran"'; tail -n +2 "$f"; } > "$f.new" \
    && mv "$f.new" "$f" && chmod +x "$f" || fail "could not edit the worktree copy" || return 1
  printf 'token = "%s"\n' "$(fake_token)" > "$wt/wt-secret.txt"
  (cd "$wt" && git add wt-secret.txt \
    && ! EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker git commit -qm secret >"$wt.out" 2>&1) \
    || fail "the hook let a secret through: $(tail -5 "$wt.out")" || return 1
  assert_contains "$wt.out" "- the worktree copy of check.sh ran" || return 1
  assert_contains "$wt.out" "wt-secret.txt:1:github-pat"
}
test_check_foreign_git_env_cannot_redirect_a_linked_check() {
  # Called through a link with GIT_DIR / GIT_WORK_TREE exported for another
  # checkout that also has check.sh, the scan must stay on this project.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local base="$WORK/check-foreign-link" d="$WORK/check-foreign-link/proj" rc
  local other="$WORK/check-foreign-link/other"
  check_fixture "$d" || fail "fixture setup failed" || return 1
  check_fixture "$other" || fail "foreign fixture setup failed" || return 1
  mkdir -p "$base/bin" && ln -s "$d/scripts/check.sh" "$base/bin/check" || return 1
  printf 'token = "%s"\n' "$(fake_token)" > "$d/notes.txt"
  (cd "$d" && env EDITORCONFIG_CHECKER_BIN=/nonexistent/editorconfig-checker \
    GIT_DIR="$other/.git" GIT_WORK_TREE="$other" "$base/bin/check" >"$d.out" 2>&1); rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "notes.txt:1:github-pat"
}
test_check_reports_git_errors_instead_of_scanning_every_file() {
  # git refusing the repository (here: owned by someone else) fails with git's
  # own error instead of scanning every file and flagging the gitignored .env.
  # A safe.directory exception passed as GIT_CONFIG_* is honored.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-git-error/proj" rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  printf 'GITHUB_TOKEN=%s\n' "$(fake_token)" > "$d/.env"
  run_check "$d" GIT_TEST_ASSUME_DIFFERENT_OWNER=1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "git failed here - secret scan NOT run" || return 1
  assert_contains "$d.out" "dubious ownership" || return 1
  assert_not_contains "$d.out" ".env:1:" || return 1
  run_check "$d" GIT_TEST_ASSUME_DIFFERENT_OWNER=1 GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*' \
    || fail "check.sh failed with safe.directory passed as GIT_CONFIG_*: $(tail -5 "$d.out")" || return 1
  assert_contains "$d.out" "- gitleaks: scanning the files git would commit"
}
test_check_rejects_a_gitleaks_too_old_for_the_report_template() {
  # Before 8.22 gitleaks has no `dir --report-template` (Ubuntu's apt package is
  # 8.16). Name the version and the minimum rather than fail on a flag error.
  local d="$WORK/check-old-gitleaks/proj" bin="$WORK/check-old-gitleaks/bin" rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  mkdir -p "$bin" || return 1
  cat > "$bin/gitleaks" << 'EOF'
#!/bin/sh
case "$1" in version) echo 8.16.0 ;; *) echo "Usage: gitleaks [command]" ;; esac
EOF
  chmod +x "$bin/gitleaks" || return 1
  run_check "$d" GITLEAKS_BIN="$bin/gitleaks"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "gitleaks 8.16.0 is too old: 8.22 or newer is needed" || return 1
  assert_not_contains "$d.out" "OK:"
}
test_check_works_with_a_relative_tmpdir() {
  # mktemp returns a relative path for a relative TMPDIR. The report template
  # must still be found once the scan runs from inside the copy.
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local d="$WORK/check-rel-tmp/proj" rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  mkdir -p "$WORK/check-rel-tmp/tmp" || return 1
  run_check "$d" TMPDIR=../tmp || fail "check.sh failed with a relative TMPDIR: $(tail -5 "$d.out")" || return 1
  printf 'token = "%s"\n' "$(fake_token)" > "$d/notes.txt"
  run_check "$d" TMPDIR=../tmp; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "notes.txt:1:github-pat"
}

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
test_bootstrap_nested_copy_ignores_the_enclosing_repo() {
  # A copy inside another repo is its own project: it must not take that repo's
  # name, nor be refused because that repo is the template.
  local outer="$WORK/nested/outer" d="$WORK/nested/outer/packages/newsvc"
  mkdir -p "$outer"
  (cd "$outer" && git init -q && git remote add origin https://github.com/acme-example/vibe-starter.git) \
    || fail "outer repo setup failed" || return 1
  fresh_copy "$d"
  run_bootstrap "$d" --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  assert_contains "$d/.gitleaks.toml" 'title = "newsvc gitleaks config"' || return 1
  assert_contains "$d.out" "Initialized a fresh git repository." || return 1
  assert_contains "$d.out" "Note: this directory is inside another repository" || return 1
  [ -d "$d/.git" ] || fail "expected a nested repo: $d/.git is not a directory"
}
test_bootstrap_refusal_covers_origin_variants_and_hides_the_url() {
  # Any case or URL shape, even with an explicit --name. The URL can carry a token
  # (spliced in at run time so credential scanners don't flag this file).
  local i=0 url d rc tok=not-a-real-token
  for url in git@github.com:acme-example/Vibe-Starter.git \
             https://github.com/acme-example/VIBE-STARTER.git \
             ssh://git@github.com/acme-example/vibe-starter \
             git@git.example.com:vibe-starter.git \
             https://github.com/acme-example/vibe-starter/ \
             https://github.com/acme-example/vibe-starter.GIT// \
             /srv/git/vibe-starter/.git \
             /srv/git/vibe-starter.git/.git \
             /srv/git/vibe-starter/.git/. \
             /srv/git/vibe-starter/.git/.. \
             "https://user-example:${tok}@github.com/acme-example/vibe-starter.git"; do
    i=$((i + 1)); d="$WORK/refuse-variants/$i/proj"
    fresh_copy "$d"
    (cd "$d" && git init -q && git remote add origin "$url") || fail "git setup failed" || return 1
    run_bootstrap "$d" --name other --yes; rc=$?
    [ "$rc" -eq 3 ] || fail "origin $url: expected exit 3, got $rc" || return 1
    assert_not_contains "$d.out" "$tok" || return 1
  done
}
test_bootstrap_forced_run_on_the_template_warns_about_origin() {
  local d="$WORK/forced-warns/proj" rc
  fresh_copy "$d"
  (cd "$d" && git init -q && git remote add origin https://github.com/acme-example/vibe-starter.git) \
    || fail "git setup failed" || return 1
  run_bootstrap "$d" --yes; rc=$?
  assert_exit 3 "$rc" || return 1
  assert_contains "$d.out" "git remote set-url origin" || return 1
  run_bootstrap "$d" --force --name forced --yes; rc=$?
  assert_exit 0 "$rc" || return 1
  assert_contains "$d.out" "origin still points at the vibe-starter template" || return 1
  assert_contains "$d/.gitleaks.toml" 'title = "forced gitleaks config"'
}
test_bootstrap_name_equals_form() {
  local d="$WORK/name-equals/proj" before rc
  fresh_copy "$d"
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --name= --yes; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "--name needs a non-empty value" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed despite the rejection" || return 1
  run_bootstrap "$d" --name=eqform --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  assert_contains "$d/.gitleaks.toml" 'title = "eqform gitleaks config"'
}
test_bootstrap_repo_reached_through_a_symlink_skips_git_init() {
  # Pins the path comparison on Linux too, where /tmp is not a symlink.
  local real="$WORK/symlinked/real" link="$WORK/symlinked/link"
  fresh_copy "$real"
  (cd "$real" && git init -q) || fail "git setup failed" || return 1
  ln -s "$real" "$link" || fail "symlink setup failed" || return 1
  run_bootstrap "$link" --name proj --yes || fail "bootstrap exited $?: $(cat "$link.out")" || return 1
  assert_contains "$link.out" "Already a git repository"
}
test_bootstrap_refuses_the_template_from_a_worktree() {
  # The maintainer's real layout: a Conductor workspace is a linked worktree of
  # the template, so .git is a file and origin lives in the main repo's config.
  local main="$WORK/wt-template/main" wt="$WORK/wt-template/montreal" before rc
  fresh_copy "$main"
  (cd "$main" && git init -q && git remote add origin https://github.com/acme-example/vibe-starter.git \
    && git add -A && git commit -qm init && git worktree add -q "$wt" -b feature) \
    || fail "worktree setup failed" || return 1
  before="$(tree_fingerprint "$wt")"
  run_bootstrap "$wt" --yes; rc=$?
  assert_exit 3 "$rc" || return 1
  assert_contains "$wt.out" "vibe-starter template repo itself" || return 1
  [ "$before" = "$(tree_fingerprint "$wt")" ] || fail "files changed despite the refusal"
}
test_bootstrap_reports_a_failed_git_init() {
  # A git that fails every call (here: a stub standing in for "not installed")
  # must not abort the run: bootstrap says so and finishes without a repo.
  local d="$WORK/no-git/proj" bin="$WORK/no-git/bin" rc
  fresh_copy "$d"
  mkdir -p "$bin" && printf '#!/bin/sh\nexit 127\n' > "$bin/git" && chmod +x "$bin/git" \
    || fail "git stub setup failed" || return 1
  (PATH="$bin:$PATH"; run_bootstrap "$d" --name proj --yes); rc=$?
  assert_exit 0 "$rc" || return 1
  assert_contains "$d.out" "git init failed (is git installed?) - skipped." || return 1
  assert_not_contains "$d.out" "Initialized a fresh git repository" || return 1
  assert_absent "$d/.git" || return 1
  assert_contains "$d/.gitleaks.toml" 'title = "proj gitleaks config"' || return 1
  assert_exists "$d/.bootstrapped" || return 1
  assert_absent "$d/bootstrap"
}
test_bootstrap_name_must_start_with_a_letter_or_digit() {
  # Explicit names and an origin-derived default get the same leading-character
  # rule, and a rejected default is recoverable with --name.
  local d="$WORK/leading-char/proj" before rc name
  fresh_copy "$d"
  (cd "$d" && git init -q && git remote add origin git@github.com:acme-example/.dotfiles.git) \
    || fail "git setup failed" || return 1
  before="$(tree_fingerprint "$d")"
  for name in .hidden _private .. ' spaced'; do
    run_bootstrap "$d" --name "$name" --yes; rc=$?
    [ "$rc" -eq 2 ] || fail "name '$name': expected exit 2, got $rc" || return 1
    assert_contains "$d.out" "must start with a letter or digit: '$name'" || return 1
  done
  run_bootstrap "$d" --yes; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "must start with a letter or digit: '.dotfiles'" || return 1
  assert_contains "$d.out" "(from the origin remote; pass --name <project>)" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed despite the rejections" || return 1
  run_bootstrap "$d" --name 9lives --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  assert_contains "$d/.gitleaks.toml" 'title = "9lives gitleaks config"'
}
test_bootstrap_name_checks_are_ascii_only() {
  # Bracket ranges collate per-locale; en_US.UTF-8 on macOS bash 3.2 folds
  # accented letters into A-Za-z, so both checks must still catch them.
  local d="$WORK/ascii-only/proj" before cafe eclair loc locales rc
  fresh_copy "$d"
  before="$(tree_fingerprint "$d")"
  cafe=$(printf 'caf\303\251')
  eclair=$(printf '\303\251clair')
  locales="C"
  case "$(locale -a 2>/dev/null)" in
    *en_US.UTF-8*|*en_US.utf8*) locales="$locales en_US.UTF-8" ;;
  esac
  for loc in $locales; do
    (LC_ALL="$loc"; export LC_ALL; run_bootstrap "$d" --name "$cafe" --yes); rc=$?
    assert_exit 2 "$rc" || return 1
    assert_contains "$d.out" "unexpected characters" || return 1
    (LC_ALL="$loc"; export LC_ALL; run_bootstrap "$d" --name "$eclair" --yes); rc=$?
    assert_exit 2 "$rc" || return 1
    assert_contains "$d.out" "must start with a letter or digit" || return 1
  done
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed despite the rejections"
}
test_bootstrap_defaults_name_from_directory_in_a_repo_without_origin() {
  # Its own repo but no origin remote: fall back to the directory name.
  local d="$WORK/no-origin/localproj"
  fresh_copy "$d"
  (cd "$d" && git init -q) || fail "git setup failed" || return 1
  run_bootstrap "$d" --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  assert_contains "$d/.gitleaks.toml" 'title = "localproj gitleaks config"' || return 1
  assert_contains "$d.out" "Already a git repository"
}
test_bootstrap_leaves_an_unreadable_git_alone() {
  # The old `[ -d .git ]` check never re-initialized an existing .git, even one
  # git can't read (corrupt, or owned by another user). Keep it that way under
  # --force, which is now required here since an unreadable .git otherwise
  # refuses outright (see test_bootstrap_refuses_when_git_cannot_read_the_repo).
  local d="$WORK/unreadable-git/proj"
  fresh_copy "$d"
  (cd "$d" && git init -q && rm .git/HEAD) || fail "git setup failed" || return 1
  run_bootstrap "$d" --name proj --yes --force || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  assert_contains "$d.out" "Found a .git that git can't read" || return 1
  assert_not_contains "$d.out" "Initialized a fresh git repository" || return 1
  assert_absent "$d/.git/HEAD"
}
test_bootstrap_leaves_a_dangling_git_symlink_alone() {
  # -e follows symlinks, so a dangling .git link looked absent and git init
  # created a repository at its target, outside the project. --force is now
  # required here too (see test_bootstrap_refuses_when_git_cannot_read_the_repo).
  local d="$WORK/dangling-link/proj" target="$WORK/dangling-link/elsewhere/.git"
  fresh_copy "$d"
  mkdir -p "${target%/.git}" && ln -s "$target" "$d/.git" || fail "symlink setup failed" || return 1
  run_bootstrap "$d" --name proj --yes --force || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  assert_contains "$d.out" "Found a .git that git can't read" || return 1
  assert_absent "$target"
}
test_bootstrap_refuses_when_git_cannot_read_the_repo() {
  # OWN_REPO is 0 whenever git can't read .git (corrupt, a dangling gitfile,
  # dubious ownership) -- exactly the gap where the refusal used to fail open
  # and bootstrap would personalize (and delete plans/ from) someone's repo.
  local d before rc

  d="$WORK/refuses-unreadable-git/corrupt/proj"
  fresh_copy "$d"
  (cd "$d" && git init -q && rm .git/HEAD) || fail "git setup failed" || return 1
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --name proj --yes; rc=$?
  assert_exit 3 "$rc" || return 1
  assert_contains "$d.out" "there is a .git here that git can't read" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed despite the refusal" || return 1

  d="$WORK/refuses-unreadable-git/dangling-gitfile/proj"
  fresh_copy "$d"
  printf 'gitdir: %s\n' "$WORK/refuses-unreadable-git/gone" > "$d/.git"
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --name proj --yes; rc=$?
  assert_exit 3 "$rc" || return 1
  assert_contains "$d.out" "there is a .git here that git can't read" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed despite the refusal" || return 1

  # Optional third case: dubious ownership, simulated the same way git's own
  # test suite does (real different-UID setup needs privileges we don't have).
  d="$WORK/refuses-unreadable-git/dubious-ownership/proj"
  fresh_copy "$d"
  (cd "$d" && git init -q) || fail "git setup failed" || return 1
  before="$(tree_fingerprint "$d")"
  GIT_TEST_ASSUME_DIFFERENT_OWNER=1 run_bootstrap "$d" --name proj --yes; rc=$?
  assert_exit 3 "$rc" || return 1
  assert_contains "$d.out" "there is a .git here that git can't read" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed despite the refusal" || return 1

  # Inside another repo, git skips a corrupt .git silently: still refuse, and
  # say why instead of printing an empty error.
  d="$WORK/refuses-unreadable-git/nested/outer/proj"
  mkdir -p "${d%/proj}" && (cd "${d%/proj}" && git init -q) || fail "outer repo setup failed" || return 1
  fresh_copy "$d"
  (cd "$d" && git init -q && rm .git/HEAD) || fail "git setup failed" || return 1
  run_bootstrap "$d" --name proj --yes; rc=$?
  assert_exit 3 "$rc" || return 1
  assert_contains "$d.out" "git ignores it: not a valid repository"
}
test_bootstrap_origin_shapes_give_the_repo_name() {
  # The name is the repo after the last / or :, near-misses of the template's
  # name are not refused, and a token in a URL with no repo path never shows.
  local i=0 pair url want d tok=not-a-real-token
  for pair in 'git@git.example.com:widget.git|widget' \
              'git@github.com:acme-example/vibe-starter-app.git|vibe-starter-app' \
              'https://github.com/vibe-starter/widget.git|widget' \
              "https://user-example:${tok}@git.example.com/|git.example.com"; do
    url="${pair%|*}"; want="${pair#*|}"
    i=$((i + 1)); d="$WORK/origin-shapes/$i/proj"
    fresh_copy "$d"
    (cd "$d" && git init -q && git remote add origin "$url") || fail "git setup failed" || return 1
    run_bootstrap "$d" --yes || fail "origin $url: bootstrap exited $?: $(cat "$d.out")" || return 1
    assert_contains "$d/.gitleaks.toml" "title = \"$want gitleaks config\"" || return 1
    assert_not_contains "$d.out" "$tok" || return 1
  done
}
test_bootstrap_non_tty_without_yes_takes_the_default_silently() {
  # Plan 003 defect 1's agent path: no --name, no --yes, stdin not a TTY.
  local d="$WORK/no-yes/montreal"
  fresh_copy "$d"
  (cd "$d" && git init -q && git remote add origin git@github.com:acme-example/widget.git) \
    || fail "git setup failed" || return 1
  run_bootstrap "$d" || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  assert_not_contains "$d.out" "Project name [" || return 1
  assert_contains "$d/.gitleaks.toml" 'title = "widget gitleaks config"'
}

# --- tests: companion instruction files (plan 004) -----------------------------
test_instruction_pair_ships_both_files() {
  local d="$WORK/instruction-pair-files/demo" dir heading
  fresh_copy "$d" || fail "fixture copy failed" || return 1
  run_bootstrap "$d" --name demo --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  for dir in "$REPO" "$d"; do
    [ -f "$dir/AGENTS.md" ] && [ ! -L "$dir/AGENTS.md" ] \
      || fail "$dir/AGENTS.md must be a substantive regular file" || return 1
    [ -f "$dir/CLAUDE.md" ] && [ ! -L "$dir/CLAUDE.md" ] \
      || fail "$dir/CLAUDE.md must be a substantive regular file" || return 1
    for heading in '## Install' '## Trust boundary (critical)' '## Before shipping' '## Privacy'; do
      grep -qxF -- "$heading" "$dir/AGENTS.md" || fail "AGENTS.md lost $heading" || return 1
    done
    for heading in '## Architecture' '## Commands' '## Skill routing'; do
      grep -qxF -- "$heading" "$dir/CLAUDE.md" || fail "CLAUDE.md lost $heading" || return 1
    done
  done
}
test_instruction_pair_agents_requires_claude() {
  local d="$WORK/instruction-pair-agents/demo" f
  fresh_copy "$d" || fail "fixture copy failed" || return 1
  run_bootstrap "$d" --name demo --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  for f in "$REPO/AGENTS.md" "$d/AGENTS.md"; do
    grep -qxF '## Required companion instructions' "$f" || fail "AGENTS.md lacks companion instructions" || return 1
    assert_contains "$f" "Before starting task work, read \`./CLAUDE.md\` in full. Both files' instructions apply." || return 1
    assert_contains "$f" 'Read each file once per task; if you already read the companion, do not follow the reference back again.' || return 1
    ! grep -Eq '^[[:space:]]*@(\./)?CLAUDE\.md[[:space:]]*$' "$f" \
      || fail "AGENTS.md uses an import instead of companion reading" || return 1
  done
}
test_instruction_pair_claude_requires_agents() {
  local d="$WORK/instruction-pair-claude/demo" f
  fresh_copy "$d" || fail "fixture copy failed" || return 1
  run_bootstrap "$d" --name demo --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  for f in "$REPO/CLAUDE.md" "$d/CLAUDE.md"; do
    grep -qxF '## Required companion instructions' "$f" || fail "CLAUDE.md lacks companion instructions" || return 1
    assert_contains "$f" "Before starting task work, read \`./AGENTS.md\` in full. Both files' instructions apply." || return 1
    assert_contains "$f" 'Read each file once per task; if you already read the companion, do not follow the reference back again.' || return 1
    ! grep -Eq '^[[:space:]]*@(\./)?AGENTS\.md[[:space:]]*$' "$f" \
      || fail "CLAUDE.md uses an import instead of companion reading" || return 1
  done
}
test_instruction_pair_preserves_skill_routing() {
  local d="$WORK/instruction-pair-routing/demo" f skill
  fresh_copy "$d" || fail "fixture copy failed" || return 1
  run_bootstrap "$d" --name demo --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  for f in "$REPO/CLAUDE.md" "$d/CLAUDE.md"; do
    [ "$(grep -cx '## Skill routing' "$f")" = "1" ] || fail "CLAUDE.md must have one Skill routing heading" || return 1
    for skill in context-save context-restore run; do
      grep -Eq "^\|.*\| \`$skill\` \|$" "$f" || fail "CLAUDE.md does not route to $skill" || return 1
    done
    ! grep -Eq "^\|.*\| \`(checkpoint|verify)\` \|$" "$f" || fail "CLAUDE.md invokes a stale skill" || return 1
    assert_contains "$f" "When the user's request matches an available skill, invoke it before doing the task." || return 1
    assert_contains "$f" "Use the host's supported skill mechanism; if no Skill tool exists, read and follow that skill's SKILL.md." || return 1
    assert_contains "$f" 'Load the required repository instructions first.' || return 1
  done
}
test_instruction_pair_documents_test_commands() {
  local d="$WORK/instruction-pair-commands/demo" dir
  fresh_copy "$d" || fail "fixture copy failed" || return 1
  run_bootstrap "$d" --name demo --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  for dir in "$REPO" "$d"; do
    [ "$(grep -cx '## Commands' "$dir/TESTING.md")" = "1" ] || fail "TESTING.md must have one Commands heading" || return 1
    awk '/^## Commands$/ {commands=NR} /^## Why Tiers, Not One Number$/ {tiers=NR}
         END {exit !(commands && tiers && commands < tiers)}' "$dir/TESTING.md" \
      || fail "TESTING.md Commands must precede Why Tiers" || return 1
    assert_contains "$dir/TESTING.md" "- Checks (guards that run before tests): \`{{CHECK_CMD}}\`" || return 1
    assert_contains "$dir/TESTING.md" "- Tests: \`{{TEST_CMD}}\`" || return 1
    assert_contains "$dir/TESTING.md" "The exact commands for this repo; keep them in sync with \`CLAUDE.md\` → Commands." || return 1
    assert_contains "$dir/CLAUDE.md" "Keep the check and test commands in sync with \`TESTING.md\` → Commands." || return 1
  done
}
test_instruction_pair_documents_both_entry_points() {
  local d="$WORK/instruction-pair-entry-points/demo" f
  fresh_copy "$d" || fail "fixture copy failed" || return 1
  run_bootstrap "$d" --name demo --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  for f in "$REPO/README.md" "$d/README.md"; do
    assert_contains "$f" "- \`CLAUDE.md\` — architecture, commands, conventions, and skill routing; also requires \`AGENTS.md\`." || return 1
    assert_contains "$f" "- \`AGENTS.md\` — install, trust boundary, ship gate, and privacy; also requires \`CLAUDE.md\`." || return 1
    assert_contains "$f" 'Every agent reads both files, regardless of its entry point.' || return 1
    assert_not_contains "$f" "There is deliberately no \`CLAUDE.md\`." || return 1
  done
  # TEMPLATE.md is deliberately deleted from generated projects.
  assert_contains "$REPO/TEMPLATE.md" "- \`CLAUDE.md\`, \`AGENTS.md\` — companion instructions for every coding agent. Each requires reading" || return 1
  assert_contains "$REPO/TEMPLATE.md" 'the other once; keep both files and preserve their division of responsibilities.' || return 1
  assert_not_contains "$REPO/TEMPLATE.md" "There is deliberately no \`CLAUDE.md\`." || return 1
  assert_contains "$d.out" 'CLAUDE.md   - tagline, architecture, key files, commands, skill routing; read with AGENTS.md' || return 1
  assert_contains "$d.out" 'AGENTS.md   - install command, trust boundary, ship gate, privacy; read with CLAUDE.md' || return 1
  assert_contains "$d.out" 'Every agent must read both CLAUDE.md and AGENTS.md once before starting task work.'
}

# --- tests: template-owned files, skeletons, template-only blocks (plan 005) --
placeholder_tokens() {  # complete tokens, whitespace-normalized and sorted; bad delimiters fail
  perl -0777 -ne '
    my @tokens;
    # A brace touching a token ({{{X}}}) makes it no token, so the check below fails.
    while (/(?<!\{)\{\{([^{}]*)\}\}(?!\})/g) {
      my $t = $1; $t =~ s/\s+/ /g; push @tokens, "{{$t}}";
    }
    s/(?<!\{)\{\{([^{}]*)\}\}(?!\})//g;
    die "malformed placeholder delimiters in $ARGV\n" if /\{\{|\}\}/;
    print "$_\n" for sort @tokens;
  ' "$1"
}
placeholder_inventory() {  # "<file> <token count> <token sha256>" for each skeleton file
  local f tokens n digest
  while IFS= read -r -d '' f; do
    case "$f" in
      bootstrap|TEMPLATE.md|plans/*|scripts/template-selftest.sh|template/stacks/*) continue ;;
      .github/workflows/template-selftest.yml) continue ;;
      CHANGELOG.md|TODOS.md|VERSION) continue ;;  # template-owned: /ship writes them
    esac
    [ -f "$REPO/$f" ] || continue
    tokens="$(placeholder_tokens "$REPO/$f")" || return 1
    [ -n "$tokens" ] || continue
    n="$(printf '%s\n' "$tokens" | wc -l | tr -d ' ')"
    digest="$(printf '%s\n' "$tokens" | shasum -a 256 | awk '{print $1}')"
    printf '%s %s %s\n' "$f" "$n" "$digest"
  done < <(cd "$REPO" && git ls-files -z --cached --others --exclude-standard | LC_ALL=C sort -zu)
}
template_markers_valid() {  # same rules as validate_template_markers in bootstrap
  awk '
    /^(   |  | )?<!--[ \t]*template-only/ && !/^<!-- template-only:(start|end) -->$/ {
      print FILENAME ":" FNR ": template-only marker must be alone on its line, at column 0" > "/dev/stderr"
      bad=1; next
    }
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
  # A release entry may quote a {{TOKEN}}; the skeletons' own lines may not appear.
  assert_not_contains "$REPO/CHANGELOG.md" 'All notable changes to {{PROJECT_NAME}}' || return 1
  assert_not_contains "$REPO/TODOS.md" 'The working backlog for {{PROJECT_NAME}}' || return 1
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
  PATH="$shim:$(printenv PATH)" run_bootstrap "$d" --name proj --yes; rc=$?
  assert_exit 42 "$rc" || return 1
  [ "$(cat "$d/VERSION")" = "0.0.0" ] || fail "failure did not occur after the version swap" || return 1
  assert_absent "$d/.bootstrapped" || return 1
  [ "$(cat "$d/template/.bootstrap-version")" = "2.3.4" ] || fail "original version was not saved" || return 1
  run_bootstrap "$d" --name proj --yes || fail "retry failed: $(cat "$d.out")" || return 1
  # The retry must finish the swap, not just record the saved version.
  [ "$(cat "$d/VERSION")" = "0.0.0" ] || fail "retry left the template VERSION" || return 1
  assert_contains "$d/CHANGELOG.md" "All notable changes to proj" || return 1
  assert_contains "$d/TODOS.md" "The working backlog for proj" || return 1
  assert_contains "$d/.bootstrapped" 'from vibe-starter 2.3.4' || return 1
  assert_absent "$d/template"
}


# --- tests: plan 005 review fixes ----------------------------------------------
test_bootstrap_strips_blocks_in_a_nested_plans_dir() {
  # Only the root plans/ is template-only; a docs/plans/ ships to the project.
  local d="$WORK/nested-plans/proj"
  fresh_copy "$d" || return 1
  mkdir -p "$d/docs/plans"
  printf 'KEEP\n<!-- template-only:start -->\nMAINTAINER PRIVATE\n<!-- template-only:end -->\n' > "$d/docs/plans/design.md"
  run_bootstrap "$d" --name proj --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  [ "$(cat "$d/docs/plans/design.md")" = "KEEP" ] || fail "block in docs/plans/ was not stripped"
}
test_bootstrap_rejects_an_invalid_version_before_changes() {
  local d="$WORK/bad-version/proj" before rc
  fresh_copy "$d" || return 1
  printf 'v1.2.3\n' > "$d/VERSION"
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --name proj --yes; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "Invalid template version in VERSION: 'v1.2.3'" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed before the rejection" || return 1
  # The bad value was not saved, so fixing VERSION is enough to retry.
  printf '1.2.3\n' > "$d/VERSION"
  run_bootstrap "$d" --name proj --yes || fail "retry failed: $(cat "$d.out")" || return 1
  assert_contains "$d/.bootstrapped" 'from vibe-starter 1.2.3'
}
test_template_owned_files_may_quote_a_placeholder() {
  # A /ship changelog entry can quote a token; that is not a skeleton leak.
  local d="$WORK/owned-quote/tpl" expected f
  fresh_copy "$d" || return 1
  (cd "$d" && git init -q) || fail "git init failed" || return 1
  expected="$(placeholder_inventory)" || return 1
  printf -- '- Stack packs fill {{TEST_CMD}}.\n' >> "$d/CHANGELOG.md"
  printf -- '- Explain how to fill {{FIRST_TASK}} in the starter backlog.\n' >> "$d/TODOS.md"
  [ "$(REPO="$d" placeholder_inventory)" = "$expected" ] || fail "template-owned files joined the skeleton inventory" || return 1
  REPO="$d" test_template_owned_files_are_not_skeletons || fail "a quoted token counted as a skeleton" || return 1
  # A real skeleton leak still fails, file by file.
  for f in CHANGELOG.md TODOS.md; do
    cp "$d/$f" "$d/$f.orig" && cp "$d/template/skeleton/$f" "$d/$f" || return 1
    ! REPO="$d" test_template_owned_files_are_not_skeletons >/dev/null || fail "skeleton $f at the root went unnoticed" || return 1
    mv "$d/$f.orig" "$d/$f" || return 1
  done
}
test_placeholder_tokens_reject_extra_braces() {
  # {{{X}}} extracts the same {{X}} token, so the delimiter check must catch it.
  local f="$WORK/braces.md" rc
  printf '{{{CHECK_CMD}}}\n' > "$f"
  placeholder_tokens "$f" > "$f.out" 2>&1; rc=$?
  [ "$rc" -ne 0 ] || fail "triple braces accepted" || return 1
  printf '{{CHECK_CMD}}}\n' > "$f"
  placeholder_tokens "$f" > "$f.out" 2>&1; rc=$?
  [ "$rc" -ne 0 ] || fail "an extra closing brace accepted" || return 1
  printf '{{CHECK_CMD}}{{TEST_CMD}}\n' > "$f"
  [ "$(placeholder_tokens "$f")" = "$(printf '{{CHECK_CMD}}\n{{TEST_CMD}}')" ] || fail "adjacent tokens rejected"
}
test_bootstrap_rejects_near_miss_markers_before_changes() {
  # The strip only matches exact marker lines, so a near miss must fail first.
  local kind d before rc
  for kind in indented trailing-space crlf trailing-text no-inner-space; do
    d="$WORK/near-miss-$kind/proj"
    fresh_copy "$d" || return 1
    case "$kind" in
      indented) printf '  <!-- template-only:start -->\nPRIVATE\n  <!-- template-only:end -->\n' > "$d/canary.md" ;;
      trailing-space) printf '<!-- template-only:start --> \nPRIVATE\n<!-- template-only:end --> \n' > "$d/canary.md" ;;
      crlf) printf '<!-- template-only:start -->\r\nPRIVATE\r\n<!-- template-only:end -->\r\n' > "$d/canary.md" ;;
      trailing-text) printf '<!-- template-only:start --> (maintainer)\nPRIVATE\n<!-- template-only:end --> (maintainer)\n' > "$d/canary.md" ;;
      no-inner-space) printf '<!--template-only:start-->\nPRIVATE\n<!--template-only:end-->\n' > "$d/canary.md" ;;
    esac
    before="$(tree_fingerprint "$d")"
    run_bootstrap "$d" --name proj --yes; rc=$?
    assert_exit 1 "$rc" || return 1
    assert_contains "$d.out" "must be alone on its line" || return 1
    [ "$before" = "$(tree_fingerprint "$d")" ] || fail "$kind markers changed files before rejection" || return 1
  done
}

test_bootstrap_leaves_indented_marker_examples_alone() {
  # Four spaces or a tab make a markdown code example, not a directive.
  local d="$WORK/marker-example/proj" want
  fresh_copy "$d" || return 1
  want="$(printf 'Example:\n\n    <!-- template-only:start -->\n    PRIVATE\n    <!-- template-only:end -->\n\n\t<!-- template-only:end -->')"
  printf '%s\n' "$want" > "$d/example.md"
  run_bootstrap "$d" --name proj --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  [ "$(cat "$d/example.md")" = "$want" ] || fail "an indented marker example was changed"
}

test_bootstrap_provenance_line_is_the_documented_contract() {
  # One line, '<YYYY-MM-DD> from vibe-starter <version>' (plan 005 maintenance notes).
  local d="$WORK/provenance/proj" tver
  tver="$(head -n 1 "$REPO/VERSION" | sed 's/\./\\./g')"
  fresh_copy "$d" || return 1
  run_bootstrap "$d" --name proj --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  [ "$(wc -l < "$d/.bootstrapped" | tr -d ' ')" = "1" ] || fail ".bootstrapped is not one line" || return 1
  grep -Eqx "[0-9]{4}-[0-9]{2}-[0-9]{2} from vibe-starter $tver" "$d/.bootstrapped" \
    || fail ".bootstrapped is not '<YYYY-MM-DD> from vibe-starter <version>': $(cat "$d/.bootstrapped")"
}
test_bootstrap_strip_keeps_blank_line_layout() {
  # The real blocks sit between blank lines; two in one file must both go, bytes exact.
  local d="$WORK/strip-layout/proj"
  fresh_copy "$d" || return 1
  printf 'A\n\n<!-- template-only:start -->\none\n<!-- template-only:end -->\n\nB\n\n<!-- template-only:start -->\ntwo\n<!-- template-only:end -->\n\nC\n' > "$d/layout.md"
  printf 'A\n\nB\n\nC\n' > "$d.want"
  run_bootstrap "$d" --name proj --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  cmp -s "$d.want" "$d/layout.md" || fail "strip changed the layout: $(od -c "$d/layout.md" | head -3)"
}
test_bootstrap_fails_closed_when_find_fails() {
  # The markdown list is piped, so pipefail stops bootstrap when find can't read
  # a directory. The stub lists everything, then fails like a Permission denied.
  local d="$WORK/find-fails/proj" bin="$WORK/find-fails/bin" before rc
  fresh_copy "$d" || return 1
  mkdir -p "$bin" || return 1
  printf '#!/bin/sh\n"%s" "$@"\necho "find: ./secret: Permission denied" >&2\nexit 1\n' \
    "$(command -v find)" > "$bin/find" && chmod +x "$bin/find" || fail "find stub setup failed" || return 1
  before="$(tree_fingerprint "$d")"
  PATH="$bin:$(printenv PATH)" run_bootstrap "$d" --name proj --yes; rc=$?
  [ "$rc" -ne 0 ] || fail "bootstrap ignored a find failure" || return 1
  assert_contains "$d.out" "Permission denied" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed although markdown was not fully listed"
}
test_bootstrap_refuses_missing_skeletons_before_changes() {
  local f d before rc
  for f in VERSION CHANGELOG.md TODOS.md; do
    d="$WORK/missing-skeleton-$f/proj"
    fresh_copy "$d" || return 1
    rm "$d/template/skeleton/$f"
    before="$(tree_fingerprint "$d")"
    run_bootstrap "$d" --name proj --yes; rc=$?
    assert_exit 1 "$rc" || return 1
    assert_contains "$d.out" "Missing skeleton: $f" || return 1
    [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed before the missing $f was reported" || return 1
  done
}

test_bootstrapped_project_has_no_template_references() {
  # The token inventory can't see added prose: /document-release, /sync-gbrain or an
  # agent syncing Commands could point skeleton docs at template-only files.
  local d="$WORK/no-template-refs/proj" s
  fresh_copy "$d" || return 1
  run_bootstrap "$d" --name proj --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  for s in TEMPLATE.md template/skeleton template-selftest bootstrap-version 'configured by /'; do
    assert_tree_lacks "$d" "$s" || return 1
  done
}
test_bootstrap_checklist_says_to_commit_before_shipping() {
  # /ship calls any VERSION that differs from the base branch already bumped.
  local d="$WORK/commit-first/proj"
  fresh_copy "$d" || return 1
  run_bootstrap "$d" --name proj --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  assert_contains "$d.out" "Commit this to your default branch before you branch or run gstack /ship"
}

# --- tests: plan 005 paths found by the /ship coverage audit -------------------
test_bootstrap_leaves_markdown_in_pruned_dirs_alone() {
  # Vendored and scratch markdown is neither validated nor stripped: a malformed
  # marker there must not block bootstrap, and a block there must survive. The
  # root plans/ is pruned too (bootstrap deletes it anyway).
  local d="$WORK/pruned-dirs/proj" dirs dir
  dirs=".git .context node_modules packages/app/node_modules .venv target dist"
  fresh_copy "$d" || return 1
  (cd "$d" && git init -q) || fail "git init failed" || return 1
  printf 'KEEP\n<!-- template-only:start -->\nVENDORED\n<!-- template-only:end -->\n' > "$d.block"
  for dir in $dirs plans; do
    mkdir -p "$d/$dir" || return 1
    printf '<!-- template-only:start -->\nunclosed\n' > "$d/$dir/unclosed.md"
    cp "$d.block" "$d/$dir/block.md" || return 1
  done
  run_bootstrap "$d" --name proj --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  for dir in $dirs; do
    cmp -s "$d.block" "$d/$dir/block.md" || fail "$dir/block.md was changed" || return 1
  done
}
test_bootstrap_fails_closed_when_the_strip_listing_fails() {
  # The strip pass is piped too. A find that fails only on its second markdown
  # listing (the strip; other finds pass through) must stop bootstrap before
  # .bootstrapped, and a plain rerun finishes.
  local d="$WORK/strip-find-fails/proj" bin="$WORK/strip-find-fails/bin" tver rc
  tver="$(head -n 1 "$REPO/VERSION")"
  fresh_copy "$d" || return 1
  printf 'KEEP\n<!-- template-only:start -->\nPRIVATE\n<!-- template-only:end -->\n' > "$d/canary.md"
  mkdir -p "$bin" || return 1
  printf '#!/bin/sh\ncase " $* " in *" *.md "*) ;; *) exec "%s" "$@" ;; esac\nif [ -e "%s" ]; then echo "find: .: Permission denied" >&2; exit 1; fi\n: > "%s"\nexec "%s" "$@"\n' \
    "$(command -v find)" "$bin/listed" "$bin/listed" "$(command -v find)" > "$bin/find" && chmod +x "$bin/find" \
    || fail "find stub setup failed" || return 1
  PATH="$bin:$(printenv PATH)" run_bootstrap "$d" --name proj --yes; rc=$?
  [ "$rc" -ne 0 ] || fail "bootstrap ignored a find failure in the strip pass" || return 1
  assert_exists "$bin/listed" || return 1
  assert_contains "$d.out" "Permission denied" || return 1
  assert_contains "$d/canary.md" "PRIVATE" || return 1
  assert_contains "$d/.gitleaks.toml" 'title = "proj gitleaks config"' || return 1  # failed after personalizing
  assert_absent "$d/.bootstrapped" || return 1
  assert_exists "$d/bootstrap" || return 1
  run_bootstrap "$d" --name proj --yes || fail "rerun failed: $(cat "$d.out")" || return 1
  [ "$(cat "$d/canary.md")" = "KEEP" ] || fail "the rerun did not strip the block" || return 1
  assert_contains "$d/.bootstrapped" "from vibe-starter $tver"
}
test_bootstrap_checks_every_version_source() {
  # gstack's four-part VERSION is valid; two or five parts are not. A saved retry
  # version is checked too, and a missing VERSION fails before any change.
  local d="$WORK/version-sources" v rc before
  for v in 1.2 1.2.3.4.5; do
    fresh_copy "$d/$v" || return 1
    printf '%s\n' "$v" > "$d/$v/VERSION"
    before="$(tree_fingerprint "$d/$v")"
    run_bootstrap "$d/$v" --name proj --yes; rc=$?
    assert_exit 1 "$rc" || return 1
    assert_contains "$d/$v.out" "Invalid template version in VERSION: '$v'" || return 1
    [ "$before" = "$(tree_fingerprint "$d/$v")" ] || fail "VERSION $v changed files before rejection" || return 1
  done
  fresh_copy "$d/saved" || return 1
  printf 'garbage\n' > "$d/saved/template/.bootstrap-version"
  before="$(tree_fingerprint "$d/saved")"
  run_bootstrap "$d/saved" --name proj --yes; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d/saved.out" "Invalid template version in template/.bootstrap-version: 'garbage'" || return 1
  [ "$before" = "$(tree_fingerprint "$d/saved")" ] || fail "a bad saved version changed files" || return 1
  fresh_copy "$d/missing" || return 1
  rm "$d/missing/VERSION"
  before="$(tree_fingerprint "$d/missing")"
  run_bootstrap "$d/missing" --name proj --yes; rc=$?
  [ "$rc" -ne 0 ] || fail "bootstrap ran without a template VERSION" || return 1
  [ "$before" = "$(tree_fingerprint "$d/missing")" ] || fail "a missing VERSION changed files" || return 1
  fresh_copy "$d/four" || return 1
  printf '1.2.3.4\n' > "$d/four/VERSION"
  run_bootstrap "$d/four" --name proj --yes || fail "four-part VERSION rejected: $(cat "$d/four.out")" || return 1
  assert_contains "$d/four/.bootstrapped" 'from vibe-starter 1.2.3.4'
}

test_bootstrap_fails_when_a_block_is_not_removed() {
  # perl -i only warns (exit 0) when it can't rewrite a file, e.g. in an
  # unwritable directory. The stub does the same for the strip.
  local d="$WORK/strip-skipped/proj" bin="$WORK/strip-skipped/bin" real rc
  fresh_copy "$d" || return 1
  mkdir -p "$bin" || return 1
  real="$(command -v perl)"
  cat > "$bin/perl" <<STUB || return 1
#!/bin/sh
[ "\$1" = "-0pi" ] && exit 0
exec "$real" "\$@"
STUB
  chmod +x "$bin/perl" || fail "perl stub setup failed" || return 1
  PATH="$bin:$(printenv PATH)" run_bootstrap "$d" --name proj --yes; rc=$?
  [ "$rc" -ne 0 ] || fail "bootstrap finished with a template-only block in place" || return 1
  assert_contains "$d.out" "template-only block not removed" || return 1
  assert_absent "$d/.bootstrapped"
}
test_bootstrap_retries_a_failed_cleanup() {
  # .bootstrapped is written only after the template-only paths are gone, and
  # template/ (the retry state) goes last, so a failed removal can be retried.
  local d="$WORK/cleanup-retry/proj" bin="$WORK/cleanup-retry/bin" real rc
  fresh_copy "$d" || return 1
  printf '2.3.4\n' > "$d/VERSION"
  mkdir -p "$bin" || return 1
  real="$(command -v rm)"
  cat > "$bin/rm" <<STUB || return 1
#!/bin/sh
[ "\$2" = "plans" ] && exit 1
exec "$real" "\$@"
STUB
  chmod +x "$bin/rm" || fail "rm stub setup failed" || return 1
  PATH="$bin:$(printenv PATH)" run_bootstrap "$d" --name proj --yes; rc=$?
  [ "$rc" -ne 0 ] || fail "a failed cleanup went unnoticed" || return 1
  assert_absent "$d/.bootstrapped" || return 1
  assert_exists "$d/template/.bootstrap-version" || return 1
  run_bootstrap "$d" --name proj --yes || fail "retry failed: $(cat "$d.out")" || return 1
  assert_absent "$d/plans" || return 1
  assert_absent "$d/template" || return 1
  assert_contains "$d/.bootstrapped" 'from vibe-starter 2.3.4'
}

test_bootstrap_marker_passes_skip_nested_checkouts() {
  # A worktree or submodule inside the project is another repo, often a full
  # copy of the template (.claude/worktrees/*): the marker check and strip
  # must not touch it.
  local d="$WORK/nested-checkout/proj" n want
  fresh_copy "$d" || return 1
  n="$d/.claude/worktrees/x"
  mkdir -p "$n/plans" || return 1
  printf 'gitdir: /elsewhere\n' > "$n/.git"
  want="$(printf 'KEEP\n<!-- template-only:start -->\nTHEIRS\n<!-- template-only:end -->')"
  printf '%s\n' "$want" > "$n/AGENTS.md"
  printf '   <!-- template-only:start -->\n' > "$n/plans/example.md"
  run_bootstrap "$d" --name proj --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  [ "$(cat "$n/AGENTS.md")" = "$want" ] || fail "the strip changed a nested checkout"
}

# --- tests: stack packs (plan 006) --------------------------------------------
stack_env() {  # run "$@" with the real uv/cargo/pnpm/Playwright homes, so a sandboxed
  # HOME doesn't force fresh downloads of Python, crates, toolchains, npm packages,
  # pnpm's Node runtime or Chromium on every test run.
  env UV_CACHE_DIR="$REAL_UV_CACHE_DIR" UV_PYTHON_INSTALL_DIR="$REAL_UV_PYTHON_DIR" \
    CARGO_HOME="$REAL_CARGO_HOME" RUSTUP_HOME="$REAL_RUSTUP_HOME" \
    pnpm_config_store_dir="$REAL_PNPM_STORE_DIR" pnpm_config_cache_dir="$REAL_PNPM_CACHE_DIR" \
    PNPM_HOME="$REAL_PNPM_HOME" \
    PLAYWRIGHT_BROWSERS_PATH="$REAL_PLAYWRIGHT_BROWSERS_PATH" "$@"
}
pack_files() {  # rest = pack parts: each file they ship, relative to the new project. A
  # pack file deleted but not yet staged is left out, as fresh_copy leaves it out.
  local part
  for part in "$@"; do
    git -C "$REPO" ls-files --cached --others --exclude-standard -- "template/stacks/$part/files" \
      | while IFS= read -r f; do [ ! -f "$REPO/$f" ] || printf '%s\n' "$f"; done \
      | sed "s|^template/stacks/$part/files/||" || return 1
  done
}
assert_committed() {  # $1 = project dir, $2 = a file listing the paths git must commit there
  local f
  [ -s "$2" ] || fail "no files listed in ${2#"$WORK"/}" || return 1
  while IFS= read -r f; do
    git -C "$1" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || fail "git would not commit $f" || return 1
  done < "$2"
}
py_tiers() {  # $1 = python-pack project dir, rest = coverage_tiers.py args -> "$1.tiers.out"
  local dir="$1"; shift
  (cd "$dir" && stack_env uv run --locked --quiet python scripts/coverage_tiers.py "$@" >"$dir.tiers.out" 2>&1)
}
test_bootstrap_rejects_unknown_stack() {
  local d="$WORK/stack-unknown/proj" before rc
  fresh_copy "$d"
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --name proj --stack cobol --yes; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "Unknown stack 'cobol'" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed despite the rejection"
}
test_stack_needs_a_letter_first_name() {
  local d="$WORK/stack-digit/proj" rc
  fresh_copy "$d"
  run_bootstrap "$d" --name 1up --stack python --yes; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "must start with a letter"
}
test_bootstrap_without_stack_directory_stays_stack_agnostic() {
  local d="$WORK/no-stack-directory/proj"
  fresh_copy "$d"
  rm -rf "$d/template/stacks"
  run_bootstrap "$d" --name proj --yes || fail "no-pack bootstrap exited $?" || return 1
  assert_contains "$d.out" "Then choose a stack" || return 1
  assert_absent "$d/pyproject.toml"
}
test_stack_python_rejects_keywords_before_mutation() {
  local d name before rc
  for name in class Async await; do
    d="$WORK/stack-keyword-$name/proj"
    fresh_copy "$d"
    before="$(tree_fingerprint "$d")"
    run_bootstrap "$d" --name "$name" --stack python --yes; rc=$?
    assert_exit 2 "$rc" || return 1
    assert_contains "$d.out" "reserved Python identifier" || return 1
    [ "$before" = "$(tree_fingerprint "$d")" ] || fail "keyword rejection changed files" || return 1
  done
}
test_stack_python_rejects_unusable_names_before_mutation() {
  # The editable src/ path comes after the standard library and the pack's tools on
  # sys.path, so a package named like one of them is shadowed, and names over 60
  # characters break ruff's 100 columns: either way the new project's first gate fails.
  local d name want before rc n=0
  while IFS='|' read -r name want; do
    n=$((n + 1))
    d="$WORK/stack-unusable-$n/proj"
    fresh_copy "$d"
    before="$(tree_fingerprint "$d")"
    run_bootstrap "$d" --name "$name" --stack python --yes; rc=$?
    assert_exit 2 "$rc" || return 1
    assert_contains "$d.out" "$want" || return 1
    [ "$before" = "$(tree_fingerprint "$d")" ] || fail "rejecting '$name' changed files" || return 1
  done <<'NAMES'
Calendar|taken by the Python standard library
json|taken by the Python standard library
pytest|taken by the Python standard library
ruff|taken by the Python standard library
colorama|taken by the Python standard library
Python|reserved by Python or uv
activate|reserved by Python or uv
SiteCustomize|reserved by Python or uv
target|a directory bootstrap leaves unfilled
Dist|a directory bootstrap leaves unfilled
node_modules|a directory bootstrap leaves unfilled
Acme Example Inventory Reconciliation Service Version Two Ok1|too long for the python stack pack
NAMES
}
test_bootstrap_without_stack_stays_stack_agnostic() {
  local d="$WORK/no-stack/proj"
  fresh_copy "$d"
  run_bootstrap "$d" --name proj --yes || fail "bootstrap exited $?" || return 1
  assert_exists "$d/.github/workflows/ci.yml.example" || return 1
  assert_absent "$d/.github/workflows/ci.yml" || return 1
  assert_absent "$d/pyproject.toml" || return 1
  assert_absent "$d/Cargo.toml" || return 1
  assert_contains "$d/.gitignore" "# Language sections" || return 1
  assert_contains "$d/CLAUDE.md" "This template is stack-agnostic" || return 1
  assert_contains "$d.out" "Then choose a stack"
}
test_stack_pack_mechanism_with_a_fixture_pack() {
  # Exercises every step of pack application with a synthetic pack, so the
  # mechanism is covered even where uv/cargo are not installed.
  local d="$WORK/stack-fixture/demo" p
  fresh_copy "$d"
  p="$d/template/stacks/fixture"
  mkdir -p "$p/files/src/__package__" "$p/files/.github/workflows" "$p/files/a/__package__/__package__"
  printf 'package={{PACKAGE_NAME}} project={{PROJECT_NAME}}\n' > "$p/files/src/__package__/hello.txt"
  printf 'nested\n' > "$p/files/a/__package__/__package__/x.txt"
  printf 'name: ci\n' > "$p/files/.github/workflows/ci.yml"
  printf '# comment line\nTEST_CMD=fixture-test --all\nINSTALL_CMD=fixture-install\nSTACK=Fixture stack\nSHIP_GATE=fixture-gate && fixture-test\n' > "$p/commands"
  printf '# --- Fixture ---\nfixture-out/\n' > "$p/gitignore"
  printf '#!/bin/sh\ntouch after-bootstrap-ran\n' > "$p/after-bootstrap"
  run_bootstrap "$d" --name "Demo Thing" --stack fixture --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  assert_contains "$d/src/demo_thing/hello.txt" "package=demo_thing project=Demo Thing" || return 1
  assert_exists "$d/a/demo_thing/demo_thing/x.txt" || return 1
  assert_contains "$d/TESTING.md" "Tests: \`fixture-test --all\`" || return 1
  assert_contains "$d/CLAUDE.md" "Tests: \`fixture-test --all\`" || return 1
  assert_contains "$d/CLAUDE.md" "Install / bootstrap: \`fixture-install\`" || return 1
  assert_contains "$d/AGENTS.md" "Install deps: \`fixture-install\`" || return 1
  assert_contains "$d/AGENTS.md" "\`fixture-gate && fixture-test\`" || return 1  # a multi-line placeholder
  assert_contains "$d/README.md" "Fixture stack" || return 1
  assert_not_contains "$d/CLAUDE.md" "This template is stack-agnostic" || return 1
  assert_not_contains "$d/.gitignore" "# Language sections" || return 1
  assert_contains "$d/.gitignore" "fixture-out/" || return 1
  assert_exists "$d/.github/workflows/ci.yml" || return 1
  assert_absent "$d/.github/workflows/ci.yml.example" || return 1
  assert_exists "$d/after-bootstrap-ran" || return 1
  assert_contains "$d/.bootstrapped" "with the fixture stack pack" || return 1
  assert_contains "$d.out" "Stack pack: fixture."
}
test_check_runs_stack_guards_and_fails_when_one_fails() {
  # Stack packs put their guards (lint, types, lockfile) in scripts/check.d; if a
  # failing one didn't fail check.sh, CI's "Checks" step would pass regardless.
  local d="$WORK/check-guards/proj" rc
  fresh_copy "$d" || return 1
  mkdir -p "$d/scripts/check.d" || return 1
  printf 'echo "guard a ran from:"\npwd -P\n' > "$d/scripts/check.d/a.sh"
  run_check "$d" GITLEAKS_BIN=/nonexistent CI=false; rc=$?
  assert_exit 0 "$rc" || return 1
  assert_contains "$d.out" "- a: running scripts/check.d/a.sh..." || return 1
  assert_contains "$d.out" "guard a ran from:" || return 1
  assert_contains "$d.out" "$(cd "$d" && pwd -P)" || return 1  # from the project root
  assert_contains "$d.out" "OK: checks passed." || return 1
  printf 'exit 1\n' > "$d/scripts/check.d/b.sh"
  run_check "$d" GITLEAKS_BIN=/nonexistent CI=false; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "- b: running scripts/check.d/b.sh..." || return 1
  assert_not_contains "$d.out" "OK: checks passed."
}
test_stack_pack_retry_matches_a_clean_run() {
  # A failed bootstrap is retried with the same arguments (plan 005). Reapplying
  # the pack must converge on a clean run's tree: no second .gitignore block (with
  # LF or CRLF line endings), and CLAUDE.md keeps one blank line where the
  # stack-agnostic note was. The clock is frozen: the trees hold the date and year.
  local root="$WORK/stack-retry" bin="$WORK/stack-retry/bin" clock="$WORK/stack-retry/clock" real d rc eol
  mkdir -p "$bin" "$clock" || return 1
  cat > "$clock/date" <<STUB || return 1
#!/bin/sh
case "\$1" in +%Y) echo 2026 ;; +%Y-%m-%d) echo 2026-01-02 ;; *) exec "$(command -v date)" "\$@" ;; esac
STUB
  chmod +x "$clock/date" || fail "date stub setup failed" || return 1
  real="$(command -v rm)"
  cat > "$bin/rm" <<STUB || return 1
#!/bin/sh
[ "\$2" = "plans" ] && exit 1
exec "$real" "\$@"
STUB
  chmod +x "$bin/rm" || fail "rm stub setup failed" || return 1
  for eol in lf crlf; do
    for d in "$root/$eol/clean/demo" "$root/$eol/retried/demo"; do
      fresh_copy "$d" || return 1
      mkdir -p "$d/template/stacks/fixture/files/src/__package__" || return 1
      printf 'package={{PACKAGE_NAME}}\n' > "$d/template/stacks/fixture/files/src/__package__/hello.txt"
      printf 'TEST_CMD=fixture-test\n' > "$d/template/stacks/fixture/commands"
      printf '# --- Fixture ---\nfixture-out/\n' > "$d/template/stacks/fixture/gitignore"
      [ "$eol" = lf ] || perl -pi -e 's/\n/\r\n/' "$d/.gitignore"
    done
    PATH="$clock:$(printenv PATH)" run_bootstrap "$root/$eol/clean/demo" --name demo --stack fixture --yes \
      || fail "clean $eol run exited $?" || return 1
    d="$root/$eol/retried/demo"
    PATH="$bin:$clock:$(printenv PATH)" run_bootstrap "$d" --name demo --stack fixture --yes; rc=$?
    [ "$rc" -ne 0 ] || fail "the stubbed cleanup did not fail" || return 1
    PATH="$clock:$(printenv PATH)" run_bootstrap "$d" --name demo --stack fixture --yes \
      || fail "$eol retry failed: $(cat "$d.out")" || return 1
    assert_contains "$d/.bootstrapped" "2026-01-02 from vibe-starter" || return 1  # the frozen clock
    [ "$(grep -c '^# --- Fixture ---$' "$d/.gitignore")" = 1 ] || fail "$eol: the pack's .gitignore block is not there exactly once" || return 1
    assert_not_contains "$d/.gitignore" "# Language sections" || return 1
    [ "$(tree_fingerprint "$root/$eol/clean/demo")" = "$(tree_fingerprint "$d")" ] || fail "$eol: the retried tree differs from a clean run" || return 1
  done
  perl -0ne 'exit(/^## Commands\n\nKeep the check/m ? 0 : 1)' "$d/CLAUDE.md" \
    || fail "CLAUDE.md's Commands section lost its layout: $(grep -A3 '^## Commands' "$d/CLAUDE.md")"
}
test_stack_pack_gitignore_swap_keeps_real_rules() {
  # The pack replaces .gitignore's commented language block. A rule a user
  # uncommented or appended there before bootstrapping must survive the swap:
  # dropping it would make those paths committable.
  local d="$WORK/stack-gitignore-keep/demo"
  fresh_copy "$d" || return 1
  fixture_pack "$d/template/stacks/fixture" || return 1
  perl -pi -e 's|^# node_modules/$|node_modules/|' "$d/.gitignore" || return 1
  printf 'secrets.local.json\n #private\n' >> "$d/.gitignore"
  run_bootstrap "$d" --name demo --stack fixture --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  grep -qx 'node_modules/' "$d/.gitignore" || fail "the uncommented node_modules/ rule was dropped" || return 1
  grep -qx ' #private' "$d/.gitignore" || fail "the ' #private' pattern (# only comments in column 0) was dropped" || return 1
  grep -qx 'secrets.local.json' "$d/.gitignore" || fail "the appended secrets.local.json rule was dropped" || return 1
  grep -qx 'fixture-out/' "$d/.gitignore" || fail "the pack's rules are missing" || return 1
  assert_not_contains "$d/.gitignore" "# Language sections" || return 1
  assert_not_contains "$d/.gitignore" "# .turbo/" || return 1
  # With the language block edited away, the pack's rules are appended instead.
  d="$WORK/stack-gitignore-noblock/demo"
  fresh_copy "$d" || return 1
  fixture_pack "$d/template/stacks/fixture" || return 1
  perl -0pi -e 's/\n# =+\n# Language sections.*\z/\n/s' "$d/.gitignore" || return 1
  assert_not_contains "$d/.gitignore" "# Language sections" || return 1
  printf '# --- Fixture ---\n' >> "$d/.gitignore"   # the pack's header without its rules
  run_bootstrap "$d" --name demo --stack fixture --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  [ "$(grep -cx 'fixture-out/' "$d/.gitignore")" = 1 ] || fail "the pack's rules did not land once without a language block"
}
test_stack_name_rejections_say_where_a_default_name_came_from() {
  # Same rule as the generic name checks: a rejected default names its source.
  local name d rc
  for name in json 3d-viewer; do
    d="$WORK/stack-hint/$name"
    fresh_copy "$d" || return 1
    run_bootstrap "$d" --stack python --yes; rc=$?
    assert_exit 2 "$rc" || return 1
    assert_contains "$d.out" "(from the directory name; pass --name <project>)" || return 1
  done
}
test_stack_pack_files_carry_only_bootstrap_owned_tokens() {
  # Pack files skip the golden inventory and the no-stack checklist test, yet ship
  # downstream: a hand-fill token or a GitHub expression there would go unnamed.
  local hits
  hits="$(cd "$REPO" && find template/stacks/*/files -type f -exec perl -ne \
    's/\{\{(?:PROJECT_NAME|PACKAGE_NAME|YEAR)\}\}//g; print "$ARGV:$.: $_" if /\{\{|\}\}/; close ARGV if eof' {} +)" \
    || fail "cannot scan the pack files" || return 1
  [ -z "$hits" ] || fail "pack files carry tokens the bootstrap checklist won't name: $hits"
}
test_stack_python_rejected_names_track_the_pinned_python() {
  # validate-name copies sys.stdlib_module_names by hand; a .python-version bump that
  # adds modules must fail here instead of reopening the shadowing bug.
  command -v uv >/dev/null 2>&1 || { skip "uv not installed"; return; }
  local py want got
  py="$(cat "$REPO/template/stacks/python/files/.python-version")"
  want="$(cd "$WORK" && stack_env uv run --no-project --quiet --python "$py" python -c \
    'import sys; print("\n".join(sorted(n for n in sys.stdlib_module_names if n[0] != "_" and n == n.lower())))')" \
    || fail "cannot list Python $py's standard library" || return 1
  got="$(sed -n '/^stdlib="/,/"$/p' "$REPO/template/stacks/python/validate-name" | tr -d '"' \
    | sed 's/^stdlib=//' | tr ' ' '\n' | grep . | LC_ALL=C sort)"
  [ "$want" = "$got" ] || fail "validate-name's stdlib list drifted from Python $py: $(diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | tr '\n' ' ')"
}
test_stack_python_ratchet_passes_when_the_base_predates_the_pack() {
  # A project's first PR into a protected default branch compares against the
  # template commit, which has no pyproject.toml: nothing to ratchet, so it passes.
  # An unknown ref, or one git would read as an option, still fails.
  command -v uv >/dev/null 2>&1 || { skip "uv not installed"; return; }
  local d="$WORK/stack-ratchet-nobase/demo" rc
  python_project "$d" || return 1
  (cd "$d" && git add -A && git commit -qm init \
    && git branch -f prepack "$(git commit-tree -m base "$(printf '100644 blob %s\tREADME.md\n' "$(git hash-object -w README.md)" | git mktree)")") \
    || fail "git setup failed" || return 1
  py_tiers "$d" --ratchet prepack; rc=$?
  assert_exit 0 "$rc" || return 1
  assert_contains "$d.tiers.out" "no pyproject.toml at prepack; nothing to ratchet against" || return 1
  assert_contains "$d.tiers.out" "coverage-tiers: ok" || return 1
  py_tiers "$d" "--ratchet=--output=$d.leak"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "unknown revision" || return 1
  assert_absent "$d.leak" || return 1
  # Bases made of one pyproject.toml: absent table passes; malformed, emptied or
  # unreadable ones fail (only a confirmed absence means "no baseline").
  base_with() {  # $1 = branch, $2 = pyproject.toml content
    (cd "$d" && git branch -f "$1" "$(git commit-tree -m "$1" "$(printf '100644 blob %s\tpyproject.toml\n' \
      "$(printf '%b' "$2" | git hash-object -w --stdin)" | git mktree)")")
  }
  base_with notiers '[project]
name = "demo"
' || fail "git setup failed" || return 1
  py_tiers "$d" --ratchet notiers; rc=$?
  assert_exit 0 "$rc" || return 1
  assert_contains "$d.tiers.out" "no [tool.coverage_tiers] at notiers" || return 1
  base_with malformed '[tool]
coverage_tiers = false
' || fail "git setup failed" || return 1
  py_tiers "$d" --ratchet malformed; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "base config: " || return 1
  base_with emptied '[tool.coverage_tiers]
' || fail "git setup failed" || return 1
  py_tiers "$d" --ratchet emptied; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "base config: coverage_tiers must be a nonempty table" || return 1
  (cd "$d" && tree="$(git rev-parse 'emptied^{tree}')" \
    && rm -f ".git/objects/$(printf '%s' "$tree" | cut -c1-2)/$(printf '%s' "$tree" | cut -c3-)") \
    || fail "removing the base tree failed" || return 1
  py_tiers "$d" --ratchet emptied; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "cannot read pyproject.toml at emptied"
}
test_stack_python_ratchet_accepts_retired_members() {
  # Renaming, moving or deleting a tier member is a reviewed migration: the old path
  # goes into the tier's `retired`. Any other removal still fails the ratchet, and
  # the schema rejects retired entries that are malformed, repeated or still included.
  command -v uv >/dev/null 2>&1 || { skip "uv not installed"; return; }
  local d="$WORK/stack-retired/demo" rc bad
  python_project "$d" || return 1
  (cd "$d" && git add -A && git commit -qm init && git mv src/demo/cli.py src/demo/command.py) \
    || fail "git setup failed" || return 1
  perl -pi -e 's|^include = \["src/demo/cli\.py"\]$|include = ["src/demo/command.py"]\nretired = ["src/demo/cli.py"]|' \
    "$d/pyproject.toml" || return 1
  assert_contains "$d/pyproject.toml" 'retired = ["src/demo/cli.py"]' || return 1
  py_tiers "$d" --ratchet HEAD; rc=$?
  assert_exit 0 "$rc" || { cat "$d.tiers.out"; return 1; }
  cp "$d/pyproject.toml" "$d.pyproject" || return 1
  perl -ni -e 'print unless /^retired = /' "$d/pyproject.toml" || return 1
  py_tiers "$d" --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "existing members removed since HEAD" || return 1
  assert_contains "$d.tiers.out" "list its old path in the tier's retired" || return 1
  while IFS= read -r bad; do
    cp "$d.pyproject" "$d/pyproject.toml" || return 1
    BAD="$bad" perl -pi -e 's|^retired = .*$|$ENV{BAD}|' "$d/pyproject.toml" || return 1
    assert_contains "$d/pyproject.toml" "$bad" || return 1
    py_tiers "$d" --validate; rc=$?
    assert_exit 1 "$rc" || { echo "    accepted: $bad"; return 1; }
  done <<'CASES'
retired = "src/demo/cli.py"
retired = ["tests/test_cli.py"]
retired = ["src/demo/command.py"]
retired = ["src/demo/cli.py", "src/demo/cli.py"]
CASES
}
test_stack_pack_retry_keeps_the_first_runs_stack() {
  # A retry must finish the pack the first attempt started. Without --stack it
  # reuses that choice (the prompt's default, none, would leave a half-applied
  # pack); an explicit different stack is refused before any write.
  local d="$WORK/stack-retry-choice/demo" bin="$WORK/stack-retry-choice/bin" real before rc
  fresh_copy "$d" || return 1
  fixture_pack "$d/template/stacks/fixture" || return 1
  mkdir -p "$bin" || return 1
  real="$(command -v rm)"
  cat > "$bin/rm" <<STUB || return 1
#!/bin/sh
[ "\$2" = "plans" ] && exit 1
exec "$real" "\$@"
STUB
  chmod +x "$bin/rm" || fail "rm stub setup failed" || return 1
  PATH="$bin:$(printenv PATH)" run_bootstrap "$d" --name demo --stack fixture --yes; rc=$?
  [ "$rc" -ne 0 ] || fail "the stubbed cleanup did not fail" || return 1
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --name demo --stack none --yes; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "This bootstrap was started with --stack fixture" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "a refused retry changed files" || return 1
  run_bootstrap "$d" --name demo || fail "the retry without --stack failed: $(cat "$d.out")" || return 1
  assert_contains "$d/.bootstrapped" "with the fixture stack pack" || return 1
  assert_contains "$d/src/demo/hello.txt" "package=demo"
}
test_stack_python_coverage_tiers_fail_closed() {
  command -v uv >/dev/null 2>&1 || { skip "uv not installed"; return; }
  local d="$WORK/stack-tiers/demo" rc
  fresh_copy "$d"
  (cd "$d" && HOME="$WORK/home" stack_env ./bootstrap --name demo --stack python --yes </dev/null >"$d.out" 2>&1) \
    || fail "bootstrap exited $?: $(tail -20 "$d.out")" || return 1
  (cd "$d" && git add -A && git commit -qm init) || fail "commit failed" || return 1
  # 1. An include that is not a file fails --validate.
  perl -pi -e 's|include = \[\]|include = ["src/demo/missing.py"]|' "$d/pyproject.toml"
  py_tiers "$d" --validate; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "is not a file" || return 1
  (cd "$d" && git checkout -q pyproject.toml)
  # 2. Below the minimum, 3. missing from the report, 4. no branch data: all fail --check.
  printf '%s' '{"meta": {"branch_coverage": true}, "totals": {"covered_lines": 5, "num_statements": 10, "covered_branches": 0, "num_branches": 0}, "files": {"src/demo/cli.py": {"summary": {"covered_lines": 5, "num_statements": 10, "covered_branches": 0, "num_branches": 0}}}}' > "$d/coverage.json"
  py_tiers "$d" --check; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "below its minimum" || return 1
  printf '%s' '{"meta": {"branch_coverage": false}, "totals": {"covered_lines": 1, "num_statements": 1, "covered_branches": 0, "num_branches": 0}, "files": {"src/demo/other.py": {"summary": {"covered_lines": 1, "num_statements": 1, "covered_branches": 0, "num_branches": 0}}}}' > "$d/coverage.json"
  py_tiers "$d" --check; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "no branch data" || return 1
  assert_contains "$d.tiers.out" "not in the coverage report" || return 1
  # 5. Lowering a minimum fails --ratchet against the committed state.
  perl -0pi -e 's/(\[tool\.coverage_tiers\.api_surface\]\ntitle = "[^"]*"\ntarget = 100\.0\n)minimum = 100\.0/${1}minimum = 90.0/' "$d/pyproject.toml"
  py_tiers "$d" --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "minimum lowered from 100.0 to 90.0" || return 1
  (cd "$d" && git checkout -q pyproject.toml)
  # Independent dimensions, schema rejection, branchless/empty policy, and membership.
  (cd "$d" && stack_env uv run --locked --quiet python - "$d" >"$d.tiers.out" 2>&1 <<'PYPROBE'
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("tiers", root / "scripts/coverage_tiers.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
config = module.load_tiers()

def summary(lines=10, line_hits=10, branches=0, branch_hits=0):
    return dict(num_statements=lines, covered_lines=line_hits,
                num_branches=branches, covered_branches=branch_hits)

def report(cli=None, extra=None):
    files = {"src/demo/cli.py": {"summary": cli or summary()}}
    if extra is not None:
        files["src/demo/outside_tier.py"] = {"summary": extra}
    return dict(meta={"branch_coverage": True}, files=files,
                totals={key: sum(entry["summary"][key] for entry in files.values())
                        for key in module.COUNTERS})

def run(data, expected, text="", mode="--check"):
    (root / "coverage.json").write_text(data if isinstance(data, str) else json.dumps(data))
    result = subprocess.run([sys.executable, "scripts/coverage_tiers.py", mode],
                            cwd=root, text=True, capture_output=True)
    assert result.returncode == expected, result.stdout + result.stderr
    assert text in result.stdout + result.stderr, result.stdout + result.stderr

run(report(), 0)  # Positive lines with measured zero branches is deliberately branchless.
run(report(extra=summary(100, 100, 20, 8)), 1, "global: branch")
run(report(extra=summary(100, 40, 20, 20)), 1, "global: line")
run(report(cli=summary(100, 100, 20, 8), extra=summary(1000, 1000, 200, 200)),
    1, "api_surface: branch")
run(report(cli=summary(100, 40, 20, 20), extra=summary(1000, 1000, 200, 200)),
    1, "api_surface: line")
for mutation in (
    lambda data: data["files"]["src/demo/cli.py"]["summary"].pop("covered_branches"),
    lambda data: data["files"]["src/demo/cli.py"].update(summary={}),
    lambda data: data.update(totals={}),
    lambda data: data["totals"].update(covered_lines=True),
    lambda data: data["totals"].update(num_statements=-1),
    lambda data: data["totals"].update(covered_lines=11),
    lambda data: data["totals"].update(num_statements=11),
    lambda data: data.update(meta={"branch_coverage": False}),
    lambda data: data.update(files={}),
):
    data = report()
    mutation(data)
    run(data, 1)
    run(data, 1, mode="--report")  # Invalid inputs cannot produce a success snapshot.
run(report(cli=summary(0, 0)), 1, "no measurable statements")
run(report(cli=summary(10**309, 10**309)), 1, "coverage-tiers: FAIL")  # No traceback.
run("[" * 100000 + "]" * 100000, 1, "coverage-tiers: FAIL")  # Nesting too deep to decode.
result = subprocess.run([sys.executable, "scripts/coverage_tiers.py", "--ratchet", ""],
                        cwd=root, capture_output=True, text=True)
assert result.returncode == 2 and "needs a git ref" in result.stderr, result
run(report(cli=summary(0, 0), extra=summary()), 1, "no measurable statements")
data = report(extra=summary())
data["files"]["src/demo/renamed.py"] = data["files"].pop("src/demo/cli.py")
run(data, 1, "not in the coverage report")
for field, value in (
    ("minimum", True), ("minimum", float("nan")), ("target", float("inf")),
    ("include", "src/demo/cli.py"), ("include", ["src/demo/cli.py"] * 2),
    ("include", ["src/demo/../demo/cli.py"]), ("include", ["/tmp/foreign.py"]),
    ("include", []), ("allow_empty", "true"), ("title", 1),
):
    bad = copy.deepcopy(config)
    bad["api_surface"][field] = value
    assert module.validate(bad), (field, value)
assert module.validate({})
assert module.validate({"broken": []})
original = (root / "pyproject.toml").read_text()
try:
    # The explicit empty-tier opt-in must not bypass historical membership.
    changed = original.replace('include = ["src/demo/cli.py"]',
                               'include = []\nallow_empty = true')
    assert changed != original
    (root / "pyproject.toml").write_text(changed)
    result = subprocess.run([sys.executable, "scripts/coverage_tiers.py", "--ratchet", "HEAD"],
                            cwd=root, capture_output=True, text=True)
    assert result.returncode == 1 and "existing members removed" in result.stderr, result
finally:
    (root / "pyproject.toml").write_text(original)
print("coverage schema, separate floors, branchless policy, and membership probes passed")
PYPROBE
  ) || fail "coverage adversarial probes failed: $(tail -25 "$d.tiers.out")"
}
test_stack_python_longest_name_passes_guards_and_tests() {
  # Names are substituted into Python source: at the 60-character maximum, ruff's
  # 100 columns (lint and format --check) must hold, and the exact --version test
  # must pass in a narrow terminal (argparse wraps help text to the width).
  command -v uv >/dev/null 2>&1 || { skip "uv not installed"; return; }
  local d="$WORK/stack-long-name/proj"
  fresh_copy "$d"
  (cd "$d" && HOME="$WORK/home" stack_env ./bootstrap --name "Acme Example Inventory Reconciliation Service Version Two Ok" \
    --stack python --yes </dev/null >"$d.out" 2>&1) || fail "bootstrap exited $?: $(tail -20 "$d.out")" || return 1
  (cd "$d" && stack_env bash scripts/check.d/python.sh && COLUMNS=20 stack_env uv run --locked pytest -q) \
    >"$d.gate.out" 2>&1 || fail "the python guards or tests failed: $(tail -25 "$d.gate.out")"
}
test_stack_python_coverage_counts_untested_namespace_modules() {
  # A module in a subdirectory without __init__.py that no test imports must still
  # count against the floor, or the gate passes at 100% while it goes untested.
  command -v uv >/dev/null 2>&1 || { skip "uv not installed"; return; }
  local d="$WORK/stack-namespace/demo" rc
  fresh_copy "$d"
  (cd "$d" && HOME="$WORK/home" stack_env ./bootstrap --name demo --stack python --yes </dev/null >"$d.out" 2>&1) \
    || fail "bootstrap exited $?: $(tail -20 "$d.out")" || return 1
  mkdir -p "$d/src/demo/extra" || return 1
  printf 'def pick(flag: bool) -> int:\n    if flag:\n        return 1\n    return 2\n' > "$d/src/demo/extra/service.py"
  # Run as `bash scripts/coverage.sh` with a CDPATH decoy: its cd must stay in the project.
  mkdir -p "$d.decoy/scripts" || return 1
  (cd "$d" && CDPATH="$d.decoy" stack_env bash scripts/coverage.sh) >"$d.gate.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.gate.out" "src/demo/extra/service.py" || return 1
  assert_contains "$d.gate.out" "global: line"
}
test_stack_python_project_is_green_on_first_run() {
  command -v uv >/dev/null 2>&1 || { skip "uv not installed"; return; }
  local d="$WORK/stack-python/demo-app" key
  fresh_copy "$d"
  (cd "$d" && HOME="$WORK/home" stack_env ./bootstrap --name "Demo App" --stack python --yes </dev/null >"$d.out" 2>&1) \
    || fail "bootstrap exited $?: $(tail -20 "$d.out")" || return 1
  assert_contains "$d/pyproject.toml" 'name = "demo_app"' || return 1
  assert_exists "$d/src/demo_app/cli.py" || return 1
  assert_exists "$d/uv.lock" || return 1
  assert_exists "$d/.github/workflows/ci.yml" || return 1
  assert_absent "$d/.github/workflows/ci.yml.example" || return 1
  assert_absent "$d/template" || return 1
  assert_contains "$d/.bootstrapped" "with the python stack pack" || return 1
  assert_contains "$d/TESTING.md" "Tests: \`uv run pytest\`" || return 1
  assert_tree_lacks "$d" '{{TEST_CMD' || return 1
  assert_tree_lacks "$d" '{{PACKAGE_NAME}}' || return 1
  # Spell out the shared keys so a misspelled command key cannot hide a leftover.
  # Other packs can fill optional placeholders (e.g. Foldkit's RELEVANT_DOCS).
  for key in INSTALL_CMD DEV_CMD BUILD_CMD CHECK_CMD TEST_CMD SHIP_GATE STACK \
    COVERAGE_ENFORCEMENT PROJECT_NAME YEAR; do
    assert_tree_lacks "$d" "{{$key" || return 1
  done
  (cd "$d" && git add -A && git commit -qm init \
    && stack_env env EDITORCONFIG_CHECKER_BIN=/nonexistent ./scripts/check.sh \
    && stack_env ./scripts/coverage.sh) >"$d.gate.out" 2>&1 \
    || fail "the new project's own gate failed: $(tail -25 "$d.gate.out")"
}

# --- tests: stack packs, ship coverage audit (plan 006) -------------------------
fixture_pack() {  # $1 = pack dir: a minimal complete pack (files/, commands, gitignore)
  mkdir -p "$1/files/src/__package__" || return 1
  printf 'package={{PACKAGE_NAME}} project={{PROJECT_NAME}}\n' > "$1/files/src/__package__/hello.txt"
  printf 'TEST_CMD=fixture-test\n' > "$1/commands"
  printf '# --- Fixture ---\nfixture-out/\n' > "$1/gitignore"
}
python_project() {  # $1 = dir: a fresh copy bootstrapped as "demo" with the python pack
  fresh_copy "$1" || return 1
  (cd "$1" && HOME="$WORK/home" stack_env ./bootstrap --name demo --stack python --yes </dev/null >"$1.out" 2>&1) \
    || fail "bootstrap exited $?: $(tail -20 "$1.out")"
}
test_bootstrap_rejects_a_missing_or_empty_stack_value() {
  local d="$WORK/stack-empty-value/proj" before rc
  fresh_copy "$d" || return 1
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --name proj --yes --stack; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "--stack needs a value" || return 1
  run_bootstrap "$d" --name proj --yes --stack=; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "--stack needs a non-empty value" || return 1
  run_bootstrap "$d" --name proj --stack "" --yes; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "--stack needs a non-empty value" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed despite the rejections" || return 1
  run_bootstrap "$d" --help || fail "bootstrap --help exited $?" || return 1
  assert_contains "$d.out" "[--stack <name>]"
}
test_bootstrap_stack_none_equals_form_and_non_tty_default() {
  # --stack none is the explicit no-pack choice, and a run without --stack or a
  # TTY (an agent) never prompts: both stay stack-agnostic. --stack=<name> works too.
  local d mode
  for mode in none no-tty; do
    d="$WORK/stack-$mode/proj"
    fresh_copy "$d" || return 1
    if [ "$mode" = none ]; then
      run_bootstrap "$d" --name proj --stack none --yes || fail "--stack none exited $?: $(cat "$d.out")" || return 1
    else
      run_bootstrap "$d" --name proj || fail "the no-TTY run exited $?: $(cat "$d.out")" || return 1
    fi
    assert_not_contains "$d.out" "Stack pack [" || return 1
    assert_contains "$d.out" "Then choose a stack" || return 1
    assert_exists "$d/.github/workflows/ci.yml.example" || return 1
    assert_absent "$d/pyproject.toml" || return 1
    assert_contains "$d/.gitignore" "# Language sections" || return 1
    assert_not_contains "$d/.bootstrapped" "stack pack" || return 1
  done
  d="$WORK/stack-equals/demo"
  fresh_copy "$d" || return 1
  fixture_pack "$d/template/stacks/fixture" || return 1
  run_bootstrap "$d" --name demo --stack=fixture --yes || fail "--stack=fixture exited $?: $(cat "$d.out")" || return 1
  assert_contains "$d/src/demo/hello.txt" "package=demo project=demo" || return 1
  assert_contains "$d/.bootstrapped" "with the fixture stack pack"
}
test_bootstrap_rejects_stack_names_that_leave_template_stacks() {
  # The stack name becomes a path under template/stacks/. A complete pack outside
  # it must stay unreachable through ../, and odd names are refused before any write.
  local d="$WORK/stack-traversal/proj" before stack rc
  fresh_copy "$d" || return 1
  fixture_pack "$d/template/decoy" || return 1
  before="$(tree_fingerprint "$d")"
  for stack in ../decoy ../../template/decoy Python -x _x a/b . ..; do
    run_bootstrap "$d" --name proj --stack "$stack" --yes; rc=$?
    assert_exit 2 "$rc" || return 1
    assert_contains "$d.out" "Invalid stack name '$stack'" || return 1
  done
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "files changed despite the rejections"
}
test_bootstrap_rejects_an_incomplete_stack_pack() {
  # A pack needs files/, commands and gitignore. Missing any one stops the run
  # before any write and lists what is available.
  local d part before rc
  for part in files commands gitignore; do
    d="$WORK/stack-incomplete-$part/proj"
    fresh_copy "$d" || return 1
    fixture_pack "$d/template/stacks/half" || return 1
    rm -rf "$d/template/stacks/half/$part"
    before="$(tree_fingerprint "$d")"
    run_bootstrap "$d" --name proj --stack half --yes; rc=$?
    assert_exit 2 "$rc" || return 1
    assert_contains "$d.out" "Unknown stack 'half' (available: " || return 1
    assert_contains "$d.out" "python" || return 1
    [ "$before" = "$(tree_fingerprint "$d")" ] || fail "a pack without $part changed files" || return 1
  done
  d="$WORK/stack-incomplete-dir/proj"
  fresh_copy "$d" || return 1
  rm -rf "$d/template/stacks"
  run_bootstrap "$d" --name proj --stack python --yes; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.out" "Unknown stack 'python' (available: none)"
}
test_stack_pack_validate_name_gets_both_names_before_any_write() {
  # TEMPLATE.md's pack interface: `sh validate-name PACKAGE_NAME PROJECT_NAME` runs
  # before any write, and any nonzero exit rejects the name (bootstrap exits 2).
  local d="$WORK/stack-validate/demo" before rc
  fresh_copy "$d" || return 1
  fixture_pack "$d/template/stacks/fixture" || return 1
  cat > "$d/template/stacks/fixture/validate-name" <<STUB || return 1
printf '%s|%s\n' "\$1" "\$2" > "$d.args"
exit 3
STUB
  before="$(tree_fingerprint "$d")"
  run_bootstrap "$d" --name "Demo Thing" --stack fixture --yes; rc=$?
  assert_exit 2 "$rc" || return 1
  [ "$(cat "$d.args" 2>/dev/null)" = "demo_thing|Demo Thing" ] \
    || fail "validate-name got '$(cat "$d.args" 2>/dev/null)', want 'demo_thing|Demo Thing'" || return 1
  [ "$before" = "$(tree_fingerprint "$d")" ] || fail "a rejected name changed files" || return 1
  printf 'exit 0\n' > "$d/template/stacks/fixture/validate-name"
  run_bootstrap "$d" --name "Demo Thing" --stack fixture --yes || fail "an accepted name failed: $(cat "$d.out")" || return 1
  assert_contains "$d/src/demo_thing/hello.txt" "package=demo_thing"
}
test_stack_pack_fills_values_literally_and_normalizes_the_package_name() {
  # Values reach the docs verbatim: no shell or regex expansion of $, \, & or @.
  # Lines that aren't KEY=value, or whose key has no placeholder, are skipped. Each
  # run of other characters in the name becomes one underscore, trimmed at the ends.
  local d="$WORK/stack-literal/acme" value
  # shellcheck disable=SC2016  # the value must stay unexpanded, here and in the docs
  value='run $HOME "\1" $1 @ARGV & $(id) \\ /x/'
  fresh_copy "$d" || return 1
  fixture_pack "$d/template/stacks/fixture" || return 1
  printf 'not a key value line\nNO_SUCH_PLACEHOLDER=x\nTEST_CMD=%s\n' "$value" > "$d/template/stacks/fixture/commands"
  run_bootstrap "$d" --name "Acme--Web.App 2_" --stack fixture --yes || fail "bootstrap exited $?: $(cat "$d.out")" || return 1
  assert_contains "$d/TESTING.md" "Tests: \`$value\`" || return 1
  assert_contains "$d/CLAUDE.md" "Tests: \`$value\`" || return 1
  assert_contains "$d/src/acme_web_app_2/hello.txt" "package=acme_web_app_2 project=Acme--Web.App 2_" || return 1
  # A pack without a CI workflow leaves the inert example in place, and says so.
  assert_exists "$d/.github/workflows/ci.yml.example" || return 1
  assert_absent "$d/.github/workflows/ci.yml" || return 1
  assert_not_contains "$d.out" "CI (.github/workflows/ci.yml)" || return 1
  assert_contains "$d.out" "this pack has no CI workflow"
}
test_bootstrap_finishes_when_the_stack_follow_up_fails() {
  # after-bootstrap is best effort: its failure is reported, and bootstrap still
  # initializes git, marks itself done and self-deletes (set -e must not stop it).
  local d="$WORK/stack-hook-fails/demo"
  fresh_copy "$d" || return 1
  fixture_pack "$d/template/stacks/fixture" || return 1
  printf 'echo "hook ran"\nexit 7\n' > "$d/template/stacks/fixture/after-bootstrap"
  run_bootstrap "$d" --name demo --stack fixture --yes \
    || fail "bootstrap exited $? after a failed follow-up: $(cat "$d.out")" || return 1
  assert_contains "$d.out" "hook ran" || return 1
  assert_contains "$d.out" "note: the fixture pack follow-up failed" || return 1
  assert_exists "$d/.git" || return 1
  assert_contains "$d/.bootstrapped" "with the fixture stack pack" || return 1
  assert_absent "$d/bootstrap"
}
test_stack_python_bootstrap_survives_missing_or_failing_uv() {
  # With uv missing or offline, bootstrap still finishes and the hook says how to
  # lock later. Stubs stand in for uv, so this needs neither uv nor a network.
  local root="$WORK/stack-no-uv" d="$WORK/stack-no-uv/demo" rc
  mkdir -p "$root/empty" "$root/bin" "$root/hook" || return 1
  (cd "$root/hook" && env PATH="$root/empty" /bin/sh "$REPO/template/stacks/python/after-bootstrap") >"$root/hook.out" 2>&1; rc=$?
  assert_exit 0 "$rc" || return 1
  assert_contains "$root/hook.out" "uv not found: install it" || return 1
  assert_absent "$root/hook/uv.lock" || return 1
  cat > "$root/bin/uv" <<STUB || return 1
#!/bin/sh
echo "uv \$*" >> "$root/uv.calls"
echo "error: Failed to fetch: network unreachable" >&2
exit 2
STUB
  chmod +x "$root/bin/uv" || return 1
  fresh_copy "$d" || return 1
  PATH="$root/bin:$(printenv PATH)" run_bootstrap "$d" --name demo --stack python --yes \
    || fail "bootstrap exited $? with uv failing: $(cat "$d.out")" || return 1
  assert_contains "$root/uv.calls" "uv lock" || return 1
  assert_contains "$d.out" "uv lock failed (see above; offline?)" || return 1
  assert_absent "$d/uv.lock" || return 1
  assert_contains "$d/.bootstrapped" "with the python stack pack"
}
test_bootstrap_ships_what_new_project_ci_uses() {
  # Every workflow a new project gets (the no-stack example, the python pack's live
  # ci.yml) uses ./.github/actions/install-gitleaks, so that action must ship. git
  # must also commit every file the pack's CI needs, uv.lock included, and ignore
  # the pack's build artifacts. A stub uv writes the lockfile.
  local root="$WORK/ci-inputs" d wf action f n
  mkdir -p "$root/bin" || return 1
  cat > "$root/bin/uv" <<'STUB' || return 1
#!/bin/sh
if [ "$1" = lock ]; then : > uv.lock; fi
STUB
  chmod +x "$root/bin/uv" || return 1
  fresh_copy "$root/agnostic/proj" && fresh_copy "$root/python/demo" || return 1
  run_bootstrap "$root/agnostic/proj" --name proj --yes || fail "no-stack bootstrap exited $?" || return 1
  PATH="$root/bin:$(printenv PATH)" run_bootstrap "$root/python/demo" --name demo --stack python --yes \
    || fail "python bootstrap exited $?: $(cat "$root/python/demo.out")" || return 1
  for d in "$root/agnostic/proj" "$root/python/demo"; do
    n=0
    for wf in "$d"/.github/workflows/*; do
      [ -f "$wf" ] || continue
      sed -n 's|^ *uses: \(\./[^ #]*\).*$|\1|p' "$wf" > "$root/uses" || return 1
      while IFS= read -r action; do
        n=$((n + 1))
        [ -f "$d/$action/action.yml" ] || fail "${wf#"$d"/} uses $action, which the new project lacks" || return 1
      done < "$root/uses"
    done
    [ "$n" -gt 0 ] || fail "no local action found in ${d#"$WORK"/}'s workflows" || return 1
  done
  d="$root/python/demo"
  (cd "$d" && git add -A) || fail "git add failed" || return 1
  { pack_files python | sed 's|__package__|demo|g'
    printf '%s\n' uv.lock .github/workflows/ci.yml .github/actions/install-gitleaks/action.yml
  } > "$root/committed" || return 1
  assert_committed "$d" "$root/committed" || return 1
  for f in .venv/bin/python src/demo/__pycache__/cli.cpython-314.pyc .coverage coverage.json \
    .pytest_cache/v .ruff_cache/v dist/demo-0.0.0.tar.gz; do
    git -C "$d" check-ignore -q -- "$f" || fail "git would commit the build artifact $f" || return 1
  done
}
test_check_runs_every_guard_and_only_guard_scripts() {
  # A failing guard must not hide the rest (one run reports every problem), and
  # only regular *.sh files in scripts/check.d are guards.
  local d="$WORK/check-guards-all/proj" rc
  fresh_copy "$d" || return 1
  mkdir -p "$d/scripts/check.d/dir.sh" || return 1
  printf 'echo "guard a failed"\nexit 3\n' > "$d/scripts/check.d/a.sh"
  printf 'echo "guard b ran"\n' > "$d/scripts/check.d/b.sh"
  printf 'echo "notes ran"\nexit 1\n' > "$d/scripts/check.d/notes.txt"
  run_check "$d" GITLEAKS_BIN=/nonexistent CI=false; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "guard a failed" || return 1
  assert_contains "$d.out" "guard b ran" || return 1
  assert_not_contains "$d.out" "notes ran" || return 1
  assert_not_contains "$d.out" "dir.sh"
}
tty_bootstrap() {  # $1 = dir, $2 = what to type at the stack prompt, rest = bootstrap args -> "$1.out"
  # A maintainer at a terminal: ./bootstrap runs on a pseudo-terminal (Python's
  # pty module, through uv), and $2 is typed once the stack prompt appears.
  local dir="$1" answer="$2"; shift 2
  mkdir -p "$WORK/home"
  (cd "$WORK" && HOME="$WORK/home" stack_env uv run --no-project --quiet python - "$dir" "$answer" "$@" \
    >"$dir.out" 2>&1 <<'PY'
import os
import pty
import select
import sys

cwd, answer, *args = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(cwd)
    os.execv("./bootstrap", ["./bootstrap", *args])
out, typed = b"", False
while True:
    ready, _, _ = select.select([fd], [], [], 30)
    if not ready:  # a prompt nobody answers must not hang the suite
        os.kill(pid, 9)
        out += b"\n[tty driver: timed out waiting for bootstrap]\n"
        break
    try:
        data = os.read(fd, 4096)
    except OSError:  # Linux: EIO once bootstrap has exited
        break
    if not data:
        break
    out += data
    if not typed and b"Stack pack [" in out:
        os.write(fd, answer.encode() + b"\n")
        typed = True
_, status = os.waitpid(pid, 0)
sys.stdout.write(out.decode(errors="replace").replace("\r\n", "\n"))
sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1)
PY
  )
}
test_bootstrap_stack_prompt_at_a_terminal() {
  # At a terminal with no --stack, bootstrap offers "none" and the sorted packs;
  # the typed pack is installed and Enter means none. --yes means no prompts at all.
  command -v uv >/dev/null 2>&1 || { skip "uv not installed (it drives the pseudo-terminal)"; return; }
  local root="$WORK/stack-prompt" case
  for case in typed enter yes; do
    fresh_copy "$root/$case/demo" || return 1
    fixture_pack "$root/$case/demo/template/stacks/fixture" || return 1
  done
  tty_bootstrap "$root/typed/demo" fixture --name demo || fail "exited $?: $(cat "$root/typed/demo.out")" || return 1
  assert_contains "$root/typed/demo.out" "Stack pack [none fixture " || return 1
  [ -s "$REPO/template/stacks/omarchy-app/description" ] || fail "omarchy-app has no description" || return 1
  assert_contains "$root/typed/demo.out" "$(printf '  %-15s %s' omarchy-app "$(head -n 1 "$REPO/template/stacks/omarchy-app/description")")" || return 1
  assert_contains "$root/typed/demo/src/demo/hello.txt" "package=demo" || return 1
  assert_contains "$root/typed/demo/.bootstrapped" "with the fixture stack pack" || return 1
  tty_bootstrap "$root/enter/demo" "" --name demo || fail "exited $?: $(cat "$root/enter/demo.out")" || return 1
  assert_contains "$root/enter/demo.out" "Stack pack [none fixture " || return 1
  assert_contains "$root/enter/demo.out" "Then choose a stack" || return 1
  assert_not_contains "$root/enter/demo/.bootstrapped" "stack pack" || return 1
  tty_bootstrap "$root/yes/demo" fixture --name demo --yes || fail "exited $?: $(cat "$root/yes/demo.out")" || return 1
  assert_not_contains "$root/yes/demo.out" "Stack pack [" || return 1
  assert_not_contains "$root/yes/demo/.bootstrapped" "stack pack"
}
test_stack_python_guard_fails_closed() {
  # scripts/check.d/python.sh runs under set -e: a lint, format or type error, a
  # missing or stale uv.lock, or no uv must each fail it, not only its last
  # command. check.sh must pick the guard up from the pack's scripts/check.d.
  command -v uv >/dev/null 2>&1 || { skip "uv not installed"; return; }
  local d="$WORK/stack-guard/demo" rc bad
  python_project "$d" || return 1
  (cd "$d" && stack_env bash scripts/check.d/python.sh) >"$d.guard.out" 2>&1 \
    || fail "the guard failed on a fresh project: $(tail -20 "$d.guard.out")" || return 1
  # Each snippet trips exactly one tool: ruff check, ruff format, then ty.
  while IFS= read -r bad; do
    printf '%b' "$bad" > "$d/src/demo/bad.py"
    (cd "$d" && stack_env bash scripts/check.d/python.sh) >"$d.guard.out" 2>&1; rc=$?
    rm -f "$d/src/demo/bad.py"
    [ "$rc" -ne 0 ] || fail "the guard passed src/demo/bad.py containing: $bad" || return 1
    assert_contains "$d.guard.out" "bad.py" || return 1
  done <<'CASES'
import os\n
x=1\n
x: int = "a"\n
CASES
  mv "$d/uv.lock" "$d.lock" || return 1
  (cd "$d" && stack_env bash scripts/check.d/python.sh) >"$d.guard.out" 2>&1; rc=$?
  mv "$d.lock" "$d/uv.lock" || return 1
  [ "$rc" -ne 0 ] || fail "the guard passed without uv.lock" || return 1
  assert_contains "$d.guard.out" "uv.lock" || return 1
  cp "$d/pyproject.toml" "$d.pyproject" || return 1
  perl -0pi -e 's/\n  "ty>=[^"\n]*",//' "$d/pyproject.toml" || return 1
  ! cmp -s "$d/pyproject.toml" "$d.pyproject" || fail "the pyproject.toml edit did not apply" || return 1
  (cd "$d" && stack_env bash scripts/check.d/python.sh) >"$d.guard.out" 2>&1; rc=$?
  cp "$d.pyproject" "$d/pyproject.toml" || return 1
  [ "$rc" -ne 0 ] || fail "the guard passed a uv.lock that no longer matches pyproject.toml" || return 1
  assert_contains "$d.guard.out" "uv.lock is missing or out of date" || return 1
  mkdir -p "$d.empty" || return 1
  (cd "$d" && env PATH="$d.empty" /bin/bash scripts/check.d/python.sh) >"$d.guard.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard.out" "uv is not installed" || return 1
  printf 'import os\n' > "$d/src/demo/bad.py"
  (cd "$d" && stack_env env EDITORCONFIG_CHECKER_BIN=/nonexistent GITLEAKS_BIN=/nonexistent CI=false \
    ./scripts/check.sh) >"$d.check.out" 2>&1; rc=$?
  rm -f "$d/src/demo/bad.py"
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.check.out" "- python: running scripts/check.d/python.sh..." || return 1
  assert_contains "$d.check.out" "F401" || return 1
  assert_not_contains "$d.check.out" "OK: checks passed."
}
test_stack_python_version_bump_keeps_the_gate_green() {
  # gstack /ship bumps only VERSION. hatchling reads it, uv.lock must not pin it, and
  # uv's cache-keys must rebuild the existing editable install, or the project
  # reports its old version and its own VERSION test fails after every /ship.
  command -v uv >/dev/null 2>&1 || { skip "uv not installed"; return; }
  local d="$WORK/stack-bump/demo" want
  python_project "$d" || return 1
  for want in 0.0.0 0.1.0; do
    [ "$want" = 0.0.0 ] || printf '%s\n' "$want" > "$d/VERSION"
    (cd "$d" && stack_env uv run --locked --quiet demo --version) >"$d.version" 2>"$d.version.err" \
      || fail "demo --version failed at VERSION $want: $(cat "$d.version.err")" || return 1
    [ "$(cat "$d.version")" = "demo $want" ] || fail "at VERSION $want the project reports: $(cat "$d.version")" || return 1
  done
  (cd "$d" && stack_env bash scripts/check.d/python.sh && stack_env uv run --locked --quiet pytest -q) \
    >"$d.gate.out" 2>&1 || fail "the gate failed after a VERSION bump: $(tail -20 "$d.gate.out")"
}
test_stack_python_ci_job_on_a_shallow_pr_checkout() {
  # The new project's own ci.yml, run as GitHub runs it for a pull request: a fresh
  # shallow checkout of the PR (committed files only), each one-line `run:` step in
  # order, then the ratchet step, which fetches the base branch itself. A PR that
  # adds a tested module to a tier passes; one that drops a tier fails the ratchet.
  command -v uv >/dev/null 2>&1 || { skip "uv not installed"; return; }
  command -v gitleaks >/dev/null 2>&1 || { skip "gitleaks not installed"; return; }
  local root="$WORK/stack-ci" d="$WORK/stack-ci/demo" wf ci step ratchet pr rc
  python_project "$d" || return 1
  wf="$d/.github/workflows/ci.yml"
  sed -n 's/^ *run: \([^|].*\)$/\1/p' "$wf" > "$root/steps" || return 1
  ratchet="$(sed -n '/name: Coverage tiers never slip/,$p' "$wf" | sed '1,/run: |/d' | sed 's/^ *//')"
  [ -s "$root/steps" ] && [ -n "$ratchet" ] || fail "cannot find ci.yml's run steps" || return 1
  git init -q --bare "$root/origin.git" || return 1
  (cd "$d" && git add -A && git commit -qm init && git branch -M main && git push -q "$root/origin.git" main \
    && git checkout -q -b pr1) || fail "pushing main failed" || return 1
  printf 'def double(n: int) -> int:\n    return 2 * n\n' > "$d/src/demo/core.py"
  printf 'from demo.core import double\n\n\ndef test_double() -> None:\n    assert double(2) == 4\n' \
    > "$d/tests/test_core.py"
  perl -0pi -e 's|include = \[\]\nallow_empty = true[^\n]*|include = ["src/demo/core.py"]|' "$d/pyproject.toml"
  assert_contains "$d/pyproject.toml" 'include = ["src/demo/core.py"]' || return 1
  (cd "$d" && git add -A && git commit -qm pr1 && git push -q "$root/origin.git" pr1 \
    && git checkout -q -b pr2 main) || fail "pushing pr1 failed" || return 1
  perl -0pi -e 's/\n\[tool\.coverage_tiers\.api_surface\]\n.*\z/\n/s' "$d/pyproject.toml"
  assert_not_contains "$d/pyproject.toml" "api_surface" || return 1
  (cd "$d" && git commit -qam pr2 && git push -q "$root/origin.git" pr2) || fail "pushing pr2 failed" || return 1
  for pr in 1 2; do
    ci="$root/pr$pr"
    mkdir -p "$ci" || return 1
    (cd "$ci" && git init -q && git remote add origin "file://$root/origin.git" \
      && git fetch -q --depth=1 origin "+refs/heads/pr$pr:refs/remotes/pull/$pr/merge" \
      && git checkout -q "refs/remotes/pull/$pr/merge") || fail "checking out PR $pr failed" || return 1
    if [ "$pr" = 1 ]; then
      while IFS= read -r step; do
        (cd "$ci" && stack_env env CI=true GITHUB_ACTIONS=true EDITORCONFIG_CHECKER_BIN=/nonexistent \
          bash -eo pipefail -c "$step") >>"$ci.out" 2>&1 \
          || fail "PR 1: CI step '$step' failed: $(tail -20 "$ci.out")" || return 1
      done < "$root/steps"
    fi
    (cd "$ci" && stack_env env CI=true GITHUB_ACTIONS=true GITHUB_BASE_REF=main \
      bash -eo pipefail -c "$ratchet") >"$ci.ratchet.out" 2>&1; rc=$?
    if [ "$pr" = 1 ]; then
      assert_exit 0 "$rc" || { cat "$ci.ratchet.out"; return 1; }
      assert_contains "$ci.ratchet.out" "coverage-tiers: ok" || return 1
    else
      [ "$rc" -ne 0 ] || fail "the ratchet step passed a PR that removed a tier" || return 1
      assert_contains "$ci.ratchet.out" "api_surface: tier removed since origin/main" || return 1
    fi
  done
}
test_stack_python_coverage_tiers_boundaries_report_and_errors() {
  # Floors are inclusive: exactly 90% (global) or exactly the tier minimum passes and
  # a hair below fails. --report prints only the snapshot table. Schema, CLI and
  # ratchet error paths fail cleanly, and an unchanged config passes the ratchet.
  command -v uv >/dev/null 2>&1 || { skip "uv not installed"; return; }
  local d="$WORK/stack-tiers-edges/demo" rc
  python_project "$d" || return 1
  (cd "$d" && git add -A && git commit -qm init) || fail "commit failed" || return 1
  py_tiers "$d" --ratchet HEAD; rc=$?
  assert_exit 0 "$rc" || return 1
  assert_contains "$d.tiers.out" "coverage-tiers: ok" || return 1
  py_tiers "$d" --ratchet no-such-ref; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "cannot read pyproject.toml at no-such-ref" || return 1
  py_tiers "$d" --check; rc=$?  # no coverage.json yet
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "coverage-tiers: FAIL cannot load valid configuration/report" || return 1
  assert_not_contains "$d.tiers.out" "Traceback" || return 1
  py_tiers "$d"; rc=$?
  assert_exit 2 "$rc" || return 1
  (cd "$d" && stack_env uv run --locked --quiet python - "$d" >"$d.tiers.out" 2>&1 <<'PYPROBE'
import copy
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("tiers", root / "scripts/coverage_tiers.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
config = module.load_tiers()

def summary(lines, line_hits, branches=0, branch_hits=0):
    return dict(num_statements=lines, covered_lines=line_hits,
                num_branches=branches, covered_branches=branch_hits)

def report(cli, extra=None):
    files = {"src/demo/cli.py": {"summary": cli}}
    if extra is not None:
        files["src/demo/other.py"] = {"summary": extra}
    return dict(meta={"branch_coverage": True}, files=files,
                totals={key: sum(entry["summary"][key] for entry in files.values())
                        for key in module.COUNTERS})

def run(data, *args, name="coverage.json"):
    (root / name).write_text(json.dumps(data))
    return subprocess.run([sys.executable, "scripts/coverage_tiers.py", *(args or ["--check"])],
                          cwd=root, text=True, capture_output=True)

def fails(result, text):
    assert result.returncode == 1 and text in result.stderr, result

# Exactly at the global floor (lines 90/100, branches 9/10) and the tier's 100% passes.
at_floor = report(summary(10, 10), summary(90, 80, 10, 9))
result = run(at_floor)
assert result.returncode == 0, result
fails(run(report(summary(10, 10), summary(990, 889))), "global: line 89.90% is below its minimum 90.0%")
fails(run(report(summary(10, 10), summary(10, 10, 1000, 899))),
      "global: branch 89.90% is below its minimum 90.0%")
fails(run(report(summary(1000, 999))), "api_surface: line 99.90% is below its minimum 100.0%")
# --report: the table alone, explicit about empty tiers and branchless code.
result = run(at_floor, "--report")
assert result.returncode == 0, result
assert result.stdout == (
    "| Tier | Line | Branch | Minimum | Target |\n|---|---|---|---|---|\n"
    "| Global | 90.00% | 90.00% | 90.0% | 100% |\n"
    "| Pure logic & utilities | n/a (explicitly empty) | n/a (explicitly empty) | 100.0% | 100.0% |\n"
    "| API / contract surface | 100.00% | n/a (branchless) | 100.0% | 100.0% |\n"
), result.stdout
# --input reads the named report instead of coverage.json.
(root / "coverage.json").write_text("{}")
result = run(report(summary(10, 10)), "--check", "--input", "alt.json", name="alt.json")
assert result.returncode == 0, result

def rejected(text, mutate):
    bad = copy.deepcopy(config)
    mutate(bad)
    errors = module.validate(bad)
    assert any(text in error for error in errors), (text, errors)

empty = {"title": "Reserved", "minimum": 0.0, "target": 0.0, "include": [], "allow_empty": True}
rejected("global is reserved", lambda c: c.update({"global": empty}))
rejected("unknown tier keys: ['minimun']", lambda c: c["api_surface"].update(minimun=100.0))
for tier, field, value in (("api_surface", "target", 99.0), ("pure_logic", "target", 101.0),
                           ("pure_logic", "minimum", -1.0)):
    rejected("need 0 <= minimum <= target <= 100", lambda c: c[tier].update({field: value}))
rejected("title must be a nonempty string", lambda c: c["api_surface"].update(title="  "))
for path in ("src/demo/cli.txt", "src/demo\\cli.py", "src//demo/cli.py", "src/./demo/cli.py",
             "tests/test_cli.py"):
    rejected("include must name canonical src/*.py files", lambda c: c["api_surface"].update(include=[path]))
rejected("duplicate membership", lambda c: c["pure_logic"].update(include=["src/demo/cli.py"]))
outside = root.parent / "outside.py"
outside.write_text("x = 1\n")
link = root / "src/demo/escape.py"
link.symlink_to(outside)
try:
    rejected("is not a file within the project",
             lambda c: c["pure_logic"].update(include=["src/demo/escape.py"]))
finally:
    link.unlink()
print("coverage tier boundaries, report, input and schema probes passed")
PYPROBE
  ) || fail "coverage tier probes failed: $(tail -25 "$d.tiers.out")" || return 1
  # A base branch whose tier config is invalid fails the ratchet instead of passing.
  perl -pi -e 's/^minimum = 100\.0$/minimum = 101.0/' "$d/pyproject.toml" || return 1
  (cd "$d" && git commit -qam "invalid tiers" && git checkout -q HEAD~1 -- pyproject.toml) \
    || fail "git setup failed" || return 1
  py_tiers "$d" --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "base config: " || return 1
  assert_contains "$d.tiers.out" "need 0 <= minimum <= target <= 100"
}

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
  rust_env cargo fmt --version >/dev/null 2>&1 || { echo "rustfmt missing for test toolchain"; return; }
  # The starter declares the pinned toolchain as its rust-version, so an older
  # compiler refuses to build it: a named skip, not a failure.
  local need have
  need="$(sed -n 's/^rust-version = "1\.\([0-9][0-9]*\)"$/\1/p' "$REPO/template/stacks/rust/files/Cargo.toml")"
  have="$(rust_env rustc --version 2>/dev/null | sed -n 's/^rustc 1\.\([0-9][0-9]*\)\..*/\1/p')"
  [ "${have:-0}" -ge "${need:-0}" ] || echo "the test toolchain is older than the pack's rust-version 1.$need (set SELFTEST_RUST_TOOLCHAIN to the channel rust-toolchain.toml pins)"
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
  local d="$WORK/stack-rust/demo-app" why before_toolchains key f part
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
  # Spell out the shared keys so a misspelled command key cannot hide a leftover.
  # Other packs can fill optional placeholders (e.g. Foldkit's RELEVANT_DOCS).
  for key in INSTALL_CMD DEV_CMD BUILD_CMD CHECK_CMD TEST_CMD SHIP_GATE STACK \
    COVERAGE_ENFORCEMENT PROJECT_NAME YEAR; do
    assert_tree_lacks "$d" "{{$key" || return 1
  done
  (cd "$d" && rust_env env EDITORCONFIG_CHECKER_BIN=/nonexistent ./scripts/check.sh \
    && rust_env cargo test --locked) >"$d.gate.out" 2>&1 \
    || fail "new project's checks/tests failed: $(tail -25 "$d.gate.out")" || return 1
  (cd "$d" && rust_env cargo run --locked -q -- --version) | grep -qx "demo_app $(cat "$d/VERSION")" \
    || fail "--version does not print VERSION" || return 1
  # git commits the lockfile CI's --locked steps need and ignores the build output.
  git -C "$d" ls-files --error-unmatch -- Cargo.lock >/dev/null 2>&1 || fail "Cargo.lock is not committed" || return 1
  pack_files _rust-gates rust > "$d.files" || return 1
  assert_committed "$d" "$d.files" || return 1
  for f in coverage.json lcov.info default.profraw; do
    git -C "$d" check-ignore -q -- "$f" || fail "git would commit the coverage output $f" || return 1
  done
  [ -z "$(cd "$d" && git status --porcelain)" ] \
    || fail "the first run left files git would commit: $(cd "$d" && git status --porcelain | head -5)" || return 1
  # gstack /ship bumps VERSION to four parts; the next build reports the new one.
  printf '0.1.0.0\n' > "$d/VERSION"
  (cd "$d" && rust_env cargo run --locked -q -- --version) | grep -qx "demo_app 0.1.0.0" \
    || fail "--version does not follow a VERSION bump" || return 1
  (cd "$d" && rust_env cargo test --locked) >"$d.gate.out" 2>&1 \
    || fail "the tests failed after a VERSION bump: $(tail -25 "$d.gate.out")" || return 1
  # Even diagnostics run under the installed override inside the pinned project.
  [ "$(cd "$d" && rust_env rustup toolchain list)" = "$before_toolchains" ] \
    || fail "verification changed installed toolchains"
}
test_stack_rust_coverage_gate_passes() {
  # The starter passes the real gate, which then fails when it should. One project
  # serves every case: each instrumented build is slow on the 1-vCPU CI runner.
  local d="$WORK/stack-rust-cov/demo-app" why rc
  why="$(rust_ready)"; [ -z "$why" ] || { skip "$why"; return; }
  rust_env cargo llvm-cov --version >/dev/null 2>&1 || { skip "cargo-llvm-cov not installed"; return; }
  rust_env rustup component list --installed | grep -q '^llvm-tools' || { skip "llvm-tools not installed"; return; }
  bootstrap_rust "$d" || return 1
  (cd "$d" && rust_env ./scripts/coverage.sh) >"$d.cov.out" 2>&1 \
    || fail "coverage.sh failed: $(tail -25 "$d.cov.out")" || return 1
  # Regression test. `cargo llvm-cov --no-report` keeps earlier runs' profiles, so
  # without a clean step a second run merged the first one's coverage: a project
  # could delete its tests and still pass the 90% floors and the 100% tiers.
  rm "$d/tests/cli.rs" || return 1
  (cd "$d" && rust_env ./scripts/coverage.sh) >"$d.cov.out" 2>&1; rc=$?
  (cd "$d" && git checkout -q -- tests/cli.rs) || return 1
  assert_exit 1 "$rc" || return 1
  assert_not_contains "$d.cov.out" "tier(s) ok" || return 1
  # --all-features: untested code behind a Cargo feature counts against the gates.
  perl -0pi -e 's|\[dependencies\]\n|[dependencies]\n\n[features]\nextra = []\n|' "$d/Cargo.toml"
  assert_contains "$d/Cargo.toml" "extra = []" || return 1
  printf '\n/// Spare.\n#[cfg(feature = "extra")]\npub fn spare() {}\n' >> "$d/src/lib.rs"
  (cd "$d" && rust_env ./scripts/coverage.sh) >"$d.cov.out" 2>&1; rc=$?
  (cd "$d" && git checkout -q -- Cargo.toml src/lib.rs) || return 1
  assert_exit 1 "$rc" || { tail -20 "$d.cov.out"; return 1; }
  # Every step is --locked: without Cargo.lock the gate fails and writes none.
  rm "$d/Cargo.lock" || return 1
  (cd "$d" && rust_env ./scripts/coverage.sh) >"$d.cov.out" 2>&1; rc=$?
  [ "$rc" -ne 0 ] || fail "coverage.sh passed without Cargo.lock" || return 1
  assert_absent "$d/Cargo.lock"
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
    'del(.type)' \
    '., .' \
    '(.data[0].files[0].summary.lines = {count:0,covered:0}), .'; do
    rs_expect_bad_report "$d" "$filter" || return 1
  done
  # With the minimums at 0 only the counter checks can reject these: a negative or
  # fractional counter, or one member with nothing to measure (the other member
  # keeps the tier's totals positive).
  perl -pi -e 's/minimum = 100\.0/minimum = 0.0/g' "$d/Cargo.toml"
  assert_contains "$d/Cargo.toml" "minimum = 0.0" || return 1
  for filter in \
    '.data[0].files[0].summary.lines.covered = -1' \
    '.data[0].files[0].summary.lines.count = 10.5' \
    '.data[0].files[0].summary.regions.covered = 3.5' \
    '.data[0].files[0].summary.lines = {count:0,covered:0}' \
    '.data[0].files[0].summary.regions = {count:0,covered:0}'; do
    rs_expect_bad_report "$d" "$filter" || return 1
  done
  (cd "$d" && git checkout -q -- Cargo.toml) || return 1
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
  assert_exit 1 "$rc" || return 1
  # Extended by the /ship coverage audit.
  # Value: protects=coverage_tiers.sh rejects each schema rule by itself (ranges,
  # types, tier keys, non-canonical, duplicate or empty membership) and misuse
  # with exit 2; fails_when=a jq schema clause or the path_ok pattern is loosened,
  # the argument-count check is dropped, or a missing report stops naming the
  # fix; why_new=only a string include and a missing file were fed in: the other
  # clauses, the usage branch and the missing-report branch had no test; seam=none
  # Every row is otherwise valid TOML naming files that exist, so only the rule
  # under test can reject it.
  local edit
  (cd "$d" && git checkout -q -- Cargo.toml) || return 1
  while IFS= read -r edit; do
    perl -pi -e "$edit" "$d/Cargo.toml" || return 1
    ! (cd "$d" && git diff --quiet -- Cargo.toml) || fail "the Cargo.toml edit did not apply: $edit" || return 1
    rs_tiers "$d" --validate; rc=$?
    (cd "$d" && git checkout -q -- Cargo.toml) || return 1
    assert_exit 1 "$rc" || { echo "    accepted: $edit"; return 1; }
    assert_contains "$d.tiers.out" "invalid tier schema, empty membership, or duplicate membership" \
      || { echo "    for: $edit"; return 1; }
  done <<'CASES'
s|include = \[\]|include = ["src/lib.rs"]|
s|"src/lib.rs", "src/main.rs"|"src/lib.rs", "src/lib.rs"|
s|"src/lib.rs", "src/main.rs"\]|]|
s|"src/lib.rs", |"./src/lib.rs", |
s|"src/lib.rs", |"src//lib.rs", |
s|"src/lib.rs", |"src/../src/lib.rs", |
s|"src/lib.rs", |"/etc/passwd", |
s|target = 100.0|target = 99.0|
s|target = 100.0|target = 101.0|
s|minimum = 100.0|minimum = -1.0|
s|minimum = 100.0|minimum = "100"|
s|title = "API / contract surface"|title = 5|
s|coverage_tiers\.pure_logic|coverage_tiers.Pure-Logic|
CASES
  rs_tiers "$d"; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.tiers.out" "usage: " || return 1
  rs_tiers "$d" --ratchet; rc=$?
  assert_exit 2 "$rc" || return 1
  rs_tiers "$d" --validate extra; rc=$?
  assert_exit 2 "$rc" || return 1
  # --check and --report without a name read coverage.json; with none written,
  # the failure says how to make one.
  rs_report "$d" || return 1
  rs_tiers "$d" --check || fail "--check did not read coverage.json: $(cat "$d.tiers.out")" || return 1
  assert_contains "$d.tiers.out" "coverage-tiers: 2 tier(s) ok" || return 1
  rs_tiers "$d" --report || fail "--report did not read coverage.json: $(cat "$d.tiers.out")" || return 1
  assert_contains "$d.tiers.out" "| Tier | Lines | Regions | Minimum | Target |" || return 1
  assert_contains "$d.tiers.out" "| API / contract surface | 100 | 100 | " || return 1
  rm -f "$d/coverage.json"
  rs_tiers "$d" --check; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "coverage.json not found (run scripts/coverage.sh)"
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
  rs_tiers "$d" --ratchet HEAD || fail "raising floors failed" || return 1
  # Extended by the /ship coverage audit.
  # Value: protects=the ratchet names a tier removed since the base and refuses a
  # base whose tiers are invalid; fails_when=the removed-tier branch or the base
  # validation is dropped or reworded into a pass; why_new=the removal above
  # leaves no members, so validate rejects it before the ratchet compares
  # anything, and an invalid base had no test; seam=none
  # Dropping the tier that is not the only one with members keeps the config
  # valid, so the ratchet is what objects.
  (cd "$d" && git checkout -q -- Cargo.toml) || return 1
  perl -0pi -e 's/\n\[package\.metadata\.coverage_tiers\.pure_logic\].*?(?=\n\[package\.metadata\.coverage_tiers\.api_surface\])//s' "$d/Cargo.toml"
  assert_not_contains "$d/Cargo.toml" "pure_logic" || return 1
  assert_contains "$d/Cargo.toml" "coverage_tiers.api_surface" || return 1
  rs_tiers "$d" --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "pure_logic: tier removed since the base" || return 1
  (cd "$d" && git checkout -q -- Cargo.toml) || return 1
  perl -pi -e 's/minimum = 90.0/minimum = 101.0/' "$d/Cargo.toml"
  (cd "$d" && git commit -qam 'invalid tiers' && git checkout -q HEAD~1 -- Cargo.toml) \
    || fail "git setup failed" || return 1
  rs_tiers "$d" --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "invalid base tiers"
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
  # A plain path dependency is a second crate too: its code would escape the lints
  # and coverage, which see only the root package.
  (cd "$d" && git checkout -q -- Cargo.toml) || return 1
  perl -0pi -e 's|\[dependencies\]\n|[dependencies]\nanother = { path = "another" }\n|' "$d/Cargo.toml"
  assert_contains "$d/Cargo.toml" 'another = { path = "another" }' || return 1
  rs_tiers "$d" --validate; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "local path dependencies require a gate migration" || return 1
  # A crate patched in by path, from Cargo.toml or .cargo/config.toml, is another
  # local crate that cargo metadata does not show as a path dependency.
  (cd "$d" && git checkout -q -- Cargo.toml) || return 1
  perl -0pi -e 's|\[dependencies\]\n|[dependencies]\nanother = "0.0.0"\n|' "$d/Cargo.toml"
  for patch in Cargo.toml .cargo/config.toml; do
    mkdir -p "$d/.cargo" || return 1
    printf '\n[patch.crates-io]\nanother = { path = "another" }\n' >> "$d/$patch"
    (cd "$d" && rust_env cargo generate-lockfile --offline -q) >"$d.lock.out" 2>&1 \
      || fail "cannot lock the [patch] fixture in $patch: $(tail -5 "$d.lock.out")" || return 1
    rs_tiers "$d" --validate; rc=$?
    assert_exit 1 "$rc" || return 1
    assert_contains "$d.tiers.out" "local path dependencies require a gate migration" || return 1
    # Valid TOML for the second crate's entry that a strict text scan would miss:
    # a CRLF ending, a spaced header, a quoted header with a comment.
    cp "$d/Cargo.lock" "$d.patched.lock" || return 1
    for form in 's/\[\[package\]\]\nname = "another"/[[package]]\r\nname = "another"/' \
      's/\[\[package\]\]\nname = "another"/[[ package ]]\nname = "another"/' \
      's/\[\[package\]\]\nname = "another"/[["package"]] # local\nname = "another"/'; do
      perl -0pi -e "$form" "$d/Cargo.lock" || return 1
      cmp -s "$d/Cargo.lock" "$d.patched.lock" && { fail "the lockfile edit did not apply: $form"; return 1; }
      rs_tiers "$d" --validate; rc=$?
      cp "$d.patched.lock" "$d/Cargo.lock" || return 1
      assert_exit 1 "$rc" || return 1
      assert_contains "$d.tiers.out" "local path dependencies require a gate migration" || return 1
    done
    (cd "$d" && git checkout -q -- Cargo.lock) && rm -rf "$d/.cargo" || return 1
    perl -0pi -e 's|\n\[patch\.crates-io\]\nanother = \{ path = "another" \}\n||' "$d/Cargo.toml"
  done
  # Cargo.lock lists every platform's crates: a crate patched in for Windows only
  # counts on any host.
  (cd "$d" && git checkout -q -- Cargo.toml) || return 1
  printf "\n[target.'cfg(windows)'.dependencies]\nanother = \"0.0.0\"\n\n[patch.crates-io]\nanother = { path = \"another\" }\n" >> "$d/Cargo.toml"
  (cd "$d" && rust_env cargo generate-lockfile --offline -q) >"$d.lock.out" 2>&1 \
    || fail "cannot lock the Windows-only [patch] fixture: $(tail -5 "$d.lock.out")" || return 1
  rs_tiers "$d" --validate; rc=$?
  (cd "$d" && git checkout -q -- Cargo.toml Cargo.lock) || return 1
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "local path dependencies require a gate migration" || return 1
  # A `paths` override never reaches Cargo.lock, so the project's cargo config may
  # set neither it nor an include (which could set it), at its root: with a BOM,
  # in the extensionless file, or ahead of 70 KB more config.
  mkdir -p "$d/.cargo" || return 1
  while IFS='|' read -r file config pad; do
    printf '%b\n' "$config" > "$d/.cargo/$file" || return 1
    printf '# more config\n' > "$d/.cargo/more.toml" || return 1
    [ -z "$pad" ] || awk 'BEGIN { for (i = 0; i < 3000; i++) print "# padding padding padding" }' >> "$d/.cargo/$file"
    rs_tiers "$d" --validate; rc=$?
    rm -f "$d/.cargo/config.toml" "$d/.cargo/config" || return 1
    assert_exit 1 "$rc" || { echo "    for .cargo/$file: $config"; return 1; }
    assert_contains "$d.tiers.out" "overrides crates with paths or includes other config" || return 1
  done <<'CONFIGS'
config.toml|paths = ["another"]|
config.toml|include = ["more.toml"]|
config.toml|[[include]]\npath = "more.toml"|
config.toml|\0357\0273\0277paths = ["another"]|
config|paths = ["another"]|
config.toml|paths = ["another"]|pad
CONFIGS
  # The same key inside a table is something else (here an alias): no false failure.
  printf '[alias]\npaths = "tree --edges normal"\n' > "$d/.cargo/config.toml" || return 1
  rs_tiers "$d" --validate || fail "a paths alias failed the gate: $(cat "$d.tiers.out")" || return 1
  rm -rf "$d/.cargo" || return 1
  # Registry and git crates and an unused patch come from elsewhere: only the root
  # counts. An empty lockfile names no root at all.
  cp "$d/Cargo.lock" "$d.lock" || return 1
  printf '\n[[package]]\nname = "regdep"\nversion = "1.0.0"\nsource = "registry+https://github.com/rust-lang/crates.io-index"\nchecksum = "%064d"\n\n[[package]]\nname = "gitdep"\nversion = "0.1.0"\nsource = "git+https://example.invalid/gitdep#%040d"\n\n[[patch.unused]]\nname = "unuseddep"\nversion = "0.2.0"\n' 0 0 >> "$d/Cargo.lock"
  rs_tiers "$d" --validate; rc=$?
  : > "$d/Cargo.lock"
  rs_tiers "$d" --validate >/dev/null; rc2=$?
  cp "$d.lock" "$d/Cargo.lock" || return 1
  assert_exit 0 "$rc" || { cat "$d.tiers.out"; return 1; }
  assert_exit 1 "$rc2" || return 1
  assert_contains "$d.tiers.out" "Cargo.lock lists no package from this checkout" || return 1
  rs_tiers "$d" --validate || fail "the root package alone failed: $(cat "$d.tiers.out")" || return 1
  mv "$d/Cargo.lock" "$d.lock" || return 1
  rs_tiers "$d" --validate; rc=$?
  mv "$d.lock" "$d/Cargo.lock" || return 1
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "Cargo.lock not found" || return 1
  printf '[workspace]\nmembers = ["another"]\nresolver = "3"\n' > "$d/Cargo.toml"
  rs_tiers "$d" --validate; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "only one root package"
}
test_stack_rust_reserved_name_fails_before_writes() {
  local d="$WORK/stack-rust-name/demo-app" stub="$WORK/stack-rust-name/stub" name before rc
  # If validate-name ever let a name through, bootstrap would go on to its hook:
  # a failing stub cargo and run_bootstrap's sandboxed HOME keep that run away
  # from real toolchains and the real ~/.gstack.
  mkdir -p "$stub" || return 1
  printf '#!/bin/sh\nexit 101\n' > "$stub/cargo" && chmod +x "$stub/cargo" || return 1
  for name in Async Self Gen Test Std; do
    fresh_copy "$d"
    before="$(tree_fingerprint "$d")"
    PATH="$stub:$(printenv PATH)" run_bootstrap "$d" --name "$name" --stack rust --yes; rc=$?
    assert_exit 2 "$rc" || return 1
    assert_contains "$d.out" "reserved Rust package name" || return 1
    [ "$(tree_fingerprint "$d")" = "$before" ] || fail "reserved name mutated the tree" || return 1
    rm -rf "$d"
  done
}
test_stack_rust_packs_keep_names_out_of_doc_comments() {
  # clippy's pedantic doc_markdown (warnings are errors) rejects a name like MyApp
  # or my_tool in a doc comment, so no Rust pack puts the project's name in one.
  local hits
  hits="$(cd "$REPO" && grep -rnE '^[[:space:]]*//[/!].*\{\{(PROJECT_NAME|PACKAGE_NAME)\}\}' \
    --include='*.rs' template/stacks || true)"
  [ -z "$hits" ] || fail "a project name in a Rust doc comment: $hits"
}
test_stack_rust_after_bootstrap_formats_before_locking() {
  # The name changes the starter's line lengths, so the hook formats before it
  # locks, and without cargo it names both steps. The stub cargo fails and logs
  # its calls, so no toolchain or network is needed.
  local d="$WORK/stack-rust-hook/demo-app" rc
  mkdir -p "$d.empty" || return 1
  stub_cargo_project "$d" rust || return 1
  [ "$(cat "$d.cargo-calls")" = "$(printf 'cargo fmt --all\ncargo generate-lockfile --offline --quiet')" ] \
    || fail "after-bootstrap ran: $(cat "$d.cargo-calls")" || return 1
  # Both steps failed, and the hook says so instead of claiming a lockfile.
  assert_contains "$d.out" "cargo fmt failed: run 'cargo fmt --all' before your first commit." || return 1
  assert_contains "$d.out" "cargo generate-lockfile failed: run it and commit Cargo.lock before your first push." || return 1
  assert_not_contains "$d.out" "Wrote Cargo.lock" || return 1
  (cd "$d.empty" && PATH="$d.empty" /bin/sh "$REPO/template/stacks/rust/after-bootstrap") >"$d.hook" 2>&1; rc=$?
  assert_exit 0 "$rc" || return 1
  assert_contains "$d.hook" "run 'cargo fmt --all && cargo generate-lockfile'"
}
test_stack_rust_ratchet_passes_when_the_base_predates_the_pack() {
  # A project's first PR into a protected default branch compares against the
  # template commit: no Cargo.toml, or one without tiers, is nothing to ratchet,
  # as for the python pack. An unknown ref, an unreadable tree or unreadable
  # metadata still fails.
  local d="$WORK/stack-rust-ratchet-nobase/demo-app" why rc
  why="$(rust_ready)"; [ -z "$why" ] || { skip "$why"; return; }
  bootstrap_rust "$d" || return 1
  (cd "$d" && git branch -f prepack "$(git commit-tree -m base "$(printf '100644 blob %s\tREADME.md\n' "$(git hash-object -w README.md)" | git mktree)")" \
    && git branch -f broken "$(git commit-tree -m broken "$(printf '100644 blob %s\tCargo.toml\n' "$(printf 'not [valid toml\n' | git hash-object -w --stdin)" | git mktree)")" \
    && git branch -f unreadable "$(git commit-tree -m unreadable "$(printf '100644 blob %s\tCargo.toml\n' 0123456789abcdef0123456789abcdef01234567 | git mktree --missing)")") \
    || fail "git setup failed" || return 1
  rs_tiers "$d" --ratchet prepack || fail "a base without Cargo.toml failed: $(cat "$d.tiers.out")" || return 1
  assert_contains "$d.tiers.out" "no Cargo.toml at prepack; nothing to ratchet against" || return 1
  perl -0pi -e 's/\n\[package\.metadata\.coverage_tiers\..*//s' "$d/Cargo.toml"
  (cd "$d" && git commit -qam 'no tiers' && git branch -f notiers && git reset -q --hard HEAD~1) \
    || fail "git setup failed" || return 1
  rs_tiers "$d" --ratchet notiers || fail "a base without tiers failed: $(cat "$d.tiers.out")" || return 1
  assert_contains "$d.tiers.out" "no coverage tiers at notiers; nothing to ratchet against" || return 1
  rs_tiers "$d" --ratchet no-such-ref; rc=$?
  assert_exit 1 "$rc" || return 1
  rs_tiers "$d" --ratchet broken; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "cannot read base tiers" || return 1
  rs_tiers "$d" --ratchet unreadable; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "cannot read base tree"
}
test_stack_rust_guard_fails_closed() {
  # Generated by the /ship coverage audit.
  # Value: protects=the rust guard fails on a rustfmt diff, a lint warning, a
  # missing Cargo.lock, a bad tier config or no cargo, passes code under the
  # coverage cfgs Cargo.toml's check-cfg allows, and check.sh runs it;
  # fails_when=rust.sh drops -D warnings, --all-targets, --all-features, --locked,
  # set -e or --validate, a [lints] entry or check-cfg name is removed, unsafe_code
  # drops below forbid, or check.sh stops running the guard; why_new=a clean
  # starter was the only input, so a guard that checked nothing, or a check-cfg
  # list missing a coverage cfg, passed every test; seam=none
  local d="$WORK/stack-rust-guard/demo-app" why rc want bad
  why="$(rust_ready)"; [ -z "$why" ] || { skip "$why"; return; }
  bootstrap_rust "$d" || return 1
  (cd "$d" && rust_env bash scripts/check.d/rust.sh) >"$d.guard.out" 2>&1 \
    || fail "the guard failed on a fresh project: $(tail -20 "$d.guard.out")" || return 1
  # Cargo.toml's check-cfg allowance: code gated on the cfgs cargo-llvm-cov sets
  # passes, though -D warnings turns any other unexpected cfg into an error.
  printf '\n/// Coverage runs only.\n#[cfg(coverage)]\npub fn spare() {}\n' >> "$d/src/lib.rs"
  printf '\n/// Nightly coverage runs only.\n#[cfg(coverage_nightly)]\npub fn spare_nightly() {}\n' >> "$d/src/lib.rs"
  (cd "$d" && rust_env bash scripts/check.d/rust.sh) >"$d.guard.out" 2>&1; rc=$?
  (cd "$d" && git checkout -q -- src/lib.rs) || return 1
  [ "$rc" -eq 0 ] || fail "the guard failed code under cfg(coverage) or cfg(coverage_nightly): $(tail -20 "$d.guard.out")" || return 1
  # Each snippet trips one check: rustfmt, then rustc's missing_docs, the
  # unsafe_code forbid (an #[allow] cannot lift it) and an undeclared cfg name,
  # then clippy's pedantic, dbg_macro and todo.
  while IFS='|' read -r want bad; do
    printf '%b' "$bad" >> "$d/src/lib.rs"
    (cd "$d" && rust_env bash scripts/check.d/rust.sh) >"$d.guard.out" 2>&1; rc=$?
    (cd "$d" && git checkout -q -- src/lib.rs) || return 1
    [ "$rc" -ne 0 ] || fail "the guard passed src/lib.rs ending in: $bad" || return 1
    assert_contains "$d.guard.out" "$want" || return 1
  done <<'CASES'
Diff in|\n/// Spare.\npub fn  spare() {}\n
missing documentation|\npub fn spare() {}\n
incompatible with previous forbid|\n/// Spare.\n#[allow(unsafe_code)]\npub fn spare() {\n    unsafe {}\n}\n
unexpected-cfgs|\n/// Spare.\n#[cfg(coverage_typo)]\npub fn spare() {}\n
must_use|\n/// Spare.\npub fn spare() -> u8 {\n    1\n}\n
dbg_macro|\n/// Spare.\npub fn spare() {\n    dbg!(1);\n}\n
clippy::todo|\n/// Spare.\npub fn spare() {\n    todo!();\n}\n
CASES
  # --all-targets: a warning in tests/ fails the guard too.
  printf '\nfn spare() {}\n' >> "$d/tests/cli.rs"
  (cd "$d" && rust_env bash scripts/check.d/rust.sh) >"$d.guard.out" 2>&1; rc=$?
  (cd "$d" && git checkout -q -- tests/cli.rs) || return 1
  [ "$rc" -ne 0 ] || fail "the guard passed a warning in tests/cli.rs" || return 1
  assert_contains "$d.guard.out" "is never used" || return 1
  # --all-features: code behind a Cargo feature is linted too.
  perl -0pi -e 's|\[dependencies\]\n|[dependencies]\n\n[features]\nextra = []\n|' "$d/Cargo.toml"
  assert_contains "$d/Cargo.toml" "extra = []" || return 1
  printf '\n#[cfg(feature = "extra")]\npub fn spare() {}\n' >> "$d/src/lib.rs"
  (cd "$d" && rust_env bash scripts/check.d/rust.sh) >"$d.guard.out" 2>&1; rc=$?
  (cd "$d" && git checkout -q -- Cargo.toml src/lib.rs) || return 1
  [ "$rc" -ne 0 ] || fail "the guard passed undocumented code behind a feature" || return 1
  assert_contains "$d.guard.out" "missing documentation" || return 1
  mv "$d/Cargo.lock" "$d.lock" || return 1
  (cd "$d" && rust_env bash scripts/check.d/rust.sh) >"$d.guard.out" 2>&1; rc=$?
  mv "$d.lock" "$d/Cargo.lock" || return 1
  [ "$rc" -ne 0 ] || fail "the guard passed without Cargo.lock" || return 1
  assert_contains "$d.guard.out" "Cargo.lock" || return 1
  perl -pi -e 's|include = \[\]|include = ["src/missing.rs"]|' "$d/Cargo.toml"
  (cd "$d" && rust_env bash scripts/check.d/rust.sh) >"$d.guard.out" 2>&1; rc=$?
  (cd "$d" && git checkout -q -- Cargo.toml) || return 1
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard.out" "include 'src/missing.rs' is not a file" || return 1
  mkdir -p "$d.empty" || return 1
  (cd "$d" && env PATH="$d.empty" /bin/bash scripts/check.d/rust.sh) >"$d.guard.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard.out" "cargo is not installed" || return 1
  printf '\npub fn spare() {}\n' >> "$d/src/lib.rs"
  (cd "$d" && rust_env env EDITORCONFIG_CHECKER_BIN=/nonexistent GITLEAKS_BIN=/nonexistent CI=false \
    ./scripts/check.sh) >"$d.check.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.check.out" "- rust: running scripts/check.d/rust.sh..." || return 1
  assert_contains "$d.check.out" "missing documentation" || return 1
  assert_not_contains "$d.check.out" "OK: checks passed."
}
test_stack_rust_coverage_gate_fails_closed() {
  # Generated by the /ship coverage audit.
  # Value: protects=scripts/coverage.sh exits 1 with an install hint when
  # cargo-llvm-cov is missing, clears earlier coverage data before the run,
  # stops at a failing test run or a missed 90% floor, and ends on the tier gate
  # over the report it just wrote; fails_when=the tool guard becomes a skip, the
  # clean step is dropped, a floor is lowered, a step's failure is swallowed or
  # the tier gate stops reading coverage.json; why_new=the real-tool coverage test
  # skips without cargo-llvm-cov and cannot fail each step in turn; seam=none
  # A stub cargo fails at the step named in fail-at and logs every call, so this
  # needs no toolchain and behaves the same where cargo-llvm-cov is installed.
  command -v jq >/dev/null 2>&1 || { skip "jq not installed"; return; }
  local root="$WORK/stack-rust-cov-closed" d="$WORK/stack-rust-cov-closed/demo-app" rc fail_at stopped real
  mkdir -p "$root/bin" || return 1
  cat > "$root/bin/cargo" <<STUB || return 1
#!/bin/sh
echo "cargo \$*" >> "$root/calls"
case "\$*" in *"\$(cat "$root/fail-at")"*) exit 101 ;; esac
case "\$*" in
  metadata*) cat "$root/metadata.json" ;;
  *"--output-path coverage.json"*) cp "$root/report.json" coverage.json ;;
esac
STUB
  chmod +x "$root/bin/cargo" || return 1
  echo "no step" > "$root/fail-at"
  fresh_copy "$d" || return 1
  PATH="$root/bin:$(printenv PATH)" run_bootstrap "$d" --name "Demo App" --stack rust --yes \
    || fail "bootstrap exited $?: $(tail -20 "$d.out")" || return 1
  echo "llvm-cov --version" > "$root/fail-at"
  : > "$root/calls"
  (cd "$d" && PATH="$root/bin:$(printenv PATH)" ./scripts/coverage.sh) >"$d.cov.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.cov.out" "cargo-llvm-cov is not installed: cargo install --locked cargo-llvm-cov" || return 1
  [ "$(cat "$root/calls")" = "cargo llvm-cov --version" ] \
    || fail "coverage.sh went on without the tool: $(cat "$root/calls")" || return 1
  while IFS='|' read -r fail_at stopped; do
    printf '%s\n' "$fail_at" > "$root/fail-at"
    : > "$root/calls"
    (cd "$d" && PATH="$root/bin:$(printenv PATH)" ./scripts/coverage.sh) >"$d.cov.out" 2>&1; rc=$?
    [ "$rc" -ne 0 ] || fail "coverage.sh passed with '$fail_at' failing" || return 1
    assert_contains "$root/calls" "$fail_at" || return 1
    assert_not_contains "$root/calls" "$stopped" || return 1
  done <<'CASES'
llvm-cov clean --locked --workspace|--no-report
--no-report|--fail-under
--fail-under-lines 90 --fail-under-regions 90|--output-path
CASES
  # With every cargo step passing, the tier gate reads the report coverage.sh just
  # wrote: 95% of the api_surface lines clears the 90% floor, not the tier's 100%.
  real="$(cd "$d" && pwd -P)" || return 1
  jq -n --arg r "$real" '{packages: [{id: "demo", manifest_path: ($r + "/Cargo.toml"), dependencies: [],
    metadata: {coverage_tiers: {api_surface: {minimum: 100, target: 100, include: ["src/lib.rs", "src/main.rs"]}}}}],
    workspace_members: ["demo"], workspace_root: $r}' > "$root/metadata.json" || return 1
  jq -n --arg r "$real" '{type: "llvm.coverage.json.export", data: [{files: [
    {filename: ($r + "/src/lib.rs"), summary: {lines: {count: 10, covered: 9}, regions: {count: 4, covered: 4}}},
    {filename: ($r + "/src/main.rs"), summary: {lines: {count: 10, covered: 10}, regions: {count: 4, covered: 4}}}]}]}' \
    > "$root/report.json" || return 1
  printf 'version = 4\n\n[[package]]\nname = "demo_app"\nversion = "0.0.0"\n' > "$d/Cargo.lock" || return 1
  echo "no step" > "$root/fail-at"
  : > "$root/calls"
  (cd "$d" && PATH="$root/bin:$(printenv PATH)" ./scripts/coverage.sh) >"$d.cov.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.cov.out" "api_surface: lines coverage 95% is below its minimum 100%" || return 1
  # Old coverage data is cleared before the run, never after it, and --locked so
  # that even this step cannot write Cargo.lock.
  if [ "$(sed -n 2p "$root/calls")" != "cargo llvm-cov clean --locked --workspace" ] \
    || ! sed -n 3p "$root/calls" | grep -q -- '--no-report'; then
    fail "coverage.sh does not clear old coverage data before the run: $(cat "$root/calls")"
  fi
}
test_stack_rust_ci_ratchet_step_on_a_shallow_pr_checkout() {
  # Generated by the /ship coverage audit.
  # Value: protects=the new project's ci.yml ratchet step works on a shallow
  # pull-request checkout: it passes an added tier member and fails a removed
  # one; fails_when=the step's fetch, ref or script arguments drift, the script
  # loses its exec bit in git, or git archive cannot read the depth-1 base;
  # why_new=the ratchet tests call the script against local refs, and nothing ran
  # the workflow's own step the way GitHub does; seam=none
  local root="$WORK/stack-rust-ci" d="$WORK/stack-rust-ci/demo-app" why ratchet pr ci rc
  why="$(rust_ready)"; [ -z "$why" ] || { skip "$why"; return; }
  bootstrap_rust "$d" || return 1
  ratchet="$(sed -n '/name: Coverage tiers never slip/,$p' "$d/.github/workflows/ci.yml" | sed '1,/run: |/d' | sed 's/^ *//')"
  [ -n "$ratchet" ] || fail "cannot find ci.yml's ratchet step" || return 1
  git init -q --bare "$root/origin.git" || return 1
  (cd "$d" && git branch -M main && git push -q "$root/origin.git" main && git checkout -q -b pr1) \
    || fail "pushing main failed" || return 1
  printf '//! Extra.\n' > "$d/src/extra.rs"
  perl -pi -e 's|include = \[\]|include = ["src/extra.rs"]|' "$d/Cargo.toml"
  assert_contains "$d/Cargo.toml" 'include = ["src/extra.rs"]' || return 1
  (cd "$d" && git add -A && git commit -qm pr1 && git push -q "$root/origin.git" pr1 \
    && git checkout -q -b pr2 main) || fail "pushing pr1 failed" || return 1
  perl -pi -e 's|include = \["src/lib.rs", "src/main.rs"\]|include = ["src/lib.rs"]|' "$d/Cargo.toml"
  assert_contains "$d/Cargo.toml" 'include = ["src/lib.rs"]' || return 1
  (cd "$d" && git commit -qam pr2 && git push -q "$root/origin.git" pr2) || fail "pushing pr2 failed" || return 1
  for pr in 1 2; do
    ci="$root/pr$pr"
    mkdir -p "$ci" || return 1
    (cd "$ci" && git init -q && git remote add origin "file://$root/origin.git" \
      && git fetch -q --depth=1 origin "+refs/heads/pr$pr:refs/remotes/pull/$pr/merge" \
      && git checkout -q "refs/remotes/pull/$pr/merge") || fail "checking out PR $pr failed" || return 1
    (cd "$ci" && rust_env env CI=true GITHUB_ACTIONS=true GITHUB_BASE_REF=main \
      bash -eo pipefail -c "$ratchet") >"$ci.ratchet.out" 2>&1; rc=$?
    if [ "$pr" = 1 ]; then
      assert_exit 0 "$rc" || { cat "$ci.ratchet.out"; return 1; }
      assert_contains "$ci.ratchet.out" "coverage-tiers: 2 tier(s) ok" || return 1
    else
      assert_exit 1 "$rc" || { cat "$ci.ratchet.out"; return 1; }
      assert_contains "$ci.ratchet.out" "api_surface: member removed since the base: src/main.rs" || return 1
    fi
  done
}
test_stack_rust_template_ci_tests_the_pinned_toolchain() {
  # Value: protects=template CI tests the rust packs on the compiler, components
  # and cargo-llvm-cov their files pin, and the pack names that version;
  # fails_when=a pin is bumped in one place only, or a component leaves
  # rust-toolchain.toml (rust_env's rustup run overrides the toolchain file and
  # template CI installs components by hand, so the suite would stay green);
  # why_new=nothing read the pins together; seam=none
  local f pin comps c tool stale job n=0 m=0 wf="$REPO/.github/workflows/template-selftest.yml"
  for f in "$REPO"/template/stacks/*/files/rust-toolchain.toml; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    pin="$(sed -n 's/^channel = "\([^"]*\)"$/\1/p' "$f")"
    [ -n "$pin" ] || fail "no channel in ${f#"$REPO"/}" || return 1
    # Each job installs and tests on the pin, and no line names another toolchain.
    for job in selftest heavy; do
      awk -v job="  $job:" '$0 == job { on = 1; next } on && /^  [A-Za-z0-9_-]+:$/ { on = 0 } on' "$wf" > "$WORK/pin-job.yml"
      assert_contains "$WORK/pin-job.yml" "rustup toolchain install $pin " || { echo "    in the $job job"; return 1; }
      assert_contains "$WORK/pin-job.yml" "SELFTEST_RUST_TOOLCHAIN: \"$pin\"" || { echo "    in the $job job"; return 1; }
    done
    [ "$(sed -n 's/^ *run: rustup toolchain install \([^ ]*\) .*/\1/p' "$wf" | LC_ALL=C sort -u)" = "$pin" ] \
      || fail "a template-selftest.yml job installs another toolchain than $pin" || return 1
    [ "$(sed -n 's/^ *SELFTEST_RUST_TOOLCHAIN: "\([^"]*\)"$/\1/p' "$wf" | LC_ALL=C sort -u)" = "$pin" ] \
      || fail "a template-selftest.yml job tests another toolchain than $pin" || return 1
    assert_contains "$REPO/template/stacks/rust/commands" "STACK=Rust ${pin%.*} " || return 1
    # Every pack that names its Rust (STACK lines, --help descriptions) names this
    # one, and so do TEMPLATE.md's commands for running the Rust tests locally.
    stale="$(grep -ohE 'Rust 1\.[0-9]+' "$REPO"/template/stacks/*/commands "$REPO"/template/stacks/*/description \
      | grep -vxF "Rust ${pin%.*}" || true)"
    [ -z "$stale" ] || fail "a pack names another Rust than ${pin%.*}: $stale" || return 1
    stale="$(grep -ohE 'SELFTEST_RUST_TOOLCHAIN(=|: ")[0-9.]+' "$REPO/TEMPLATE.md" "$wf" \
      | grep -vE "(=|: \")${pin//./\\.}\$" || true)"
    [ -z "$stale" ] || fail "a SELFTEST_RUST_TOOLCHAIN pin is not $pin: $stale" || return 1
    # A new project's CI gets only the components its toolchain file lists.
    comps="$(sed -n "s/^ *run: rustup toolchain install $pin .*--component \([^ ]*\).*/\1/p" "$wf")"
    [ -n "$comps" ] || fail "template CI installs no components for $pin" || return 1
    for c in $(printf '%s\n' "$comps" | tr ',' ' '); do
      assert_contains "$f" "\"$c\"" || return 1
    done
  done
  [ "$n" -gt 0 ] || fail "no pack pins a Rust toolchain" || return 1
  for f in "$REPO"/template/stacks/*/files/.github/workflows/ci.yml; do
    tool="$(sed -n 's/^ *tool: \(cargo-llvm-cov@[^ ]*\)$/\1/p' "$f")"
    [ -n "$tool" ] || continue
    m=$((m + 1))
    # The light and heavy jobs each install it; both must use the pack's pin.
    [ "$(sed -n 's/^ *tool: \(cargo-llvm-cov@[^ ]*\)$/\1/p' "$wf" | LC_ALL=C sort -u)" = "$tool" ] \
      || fail "template CI pins another cargo-llvm-cov than ${f#"$REPO"/}: $tool" || return 1
  done
  [ "$m" -gt 0 ] || fail "no pack pins cargo-llvm-cov" || return 1
  # Each pack declares that compiler as its rust-version: a lower one makes Cargo
  # hold dependencies back for a compiler nothing tests.
  for f in "$REPO"/template/stacks/*/files/Cargo.toml; do
    grep -q '^rust-version' "$f" || continue
    assert_contains "$f" "rust-version = \"${pin%.*}\"" || return 1
  done
}
test_stack_rust_ship_gate_runs_every_ci_gate() {
  # Value: protects=AGENTS.md's SHIP_GATE runs each gate the new project's CI
  # runs, in every pack built on the Rust gates; fails_when=a CI gate step is
  # added or changed without SHIP_GATE (the doctest drift the first review fixed,
  # which came back in the Omarchy packs), including a command inside a
  # multi-line run: step; why_new=nothing compared them; seam=none
  local inc pack gate kind step packs=0 n ci
  for inc in "$REPO"/template/stacks/*/includes; do
    grep -qxF _rust-gates "$inc" || continue
    pack="$(basename "$(dirname "$inc")")"
    packs=$((packs + 1))
    ci="$REPO/template/stacks/$pack/files/.github/workflows/ci.yml"
    gate="$(sed -n 's/^SHIP_GATE=//p' "$REPO/template/stacks/$pack/commands")"
    [ -n "$gate" ] || fail "no SHIP_GATE in the $pack pack" || return 1
    n=0
    # One line per command of every run: step, multi-line (| or >) ones read to
    # their end: "step|cmd" for a command, "cont|text" for a line continuing the
    # previous one (it ended in a backslash).
    while IFS='|' read -r kind step; do
      # shellcheck disable=SC2016  # the patterns are ci.yml's literal text
      case "$kind|$step" in
        "step|rustup toolchain install"|"step|sudo apt-get update") ;;
        "step|sudo apt-get install -y --no-install-recommends "*)
          case "${step#sudo apt-get install -y --no-install-recommends }" in
            *[!a-z0-9.+\ \\-]*|'') fail "$pack: not a package list in the apt-get step: $step" || return 1 ;;
          esac ;;
        'step|git fetch --depth=1 origin "$GITHUB_BASE_REF"') ;;
        'step|./scripts/coverage_tiers.sh --ratchet "origin/$GITHUB_BASE_REF"') ;;  # PR-only
        "step|./scripts/"*|"step|cargo "*)
          n=$((n + 1))
          case " && $gate && " in
            *" && $step && "*) ;;
            *) fail "$pack: SHIP_GATE lacks the CI step: $step" || return 1 ;;
          esac ;;
        cont\|*[!a-z0-9.+\ \\-]*) fail "$pack: not a package list in the apt-get step: $step" || return 1 ;;
        cont\|*) ;;
        *) fail "$pack: unclassified ci.yml run: step: $step" || return 1 ;;
      esac
    done < <(awk '
      function indent(l) { match(l, /^ */); return RLENGTH }
      function emit(l) { sub(/^ */, "", l); print (cont ? "cont|" : "step|") l; cont = (l ~ /\\$/) }
      inblock && $0 !~ /^ *$/ && indent($0) <= depth { inblock = 0 }
      inblock { if ($0 !~ /^ *$/) emit($0); next }
      /^ *run: *[|>][-+]? *$/ { inblock = 1; depth = indent($0); cont = 0; next }
      /^ *run: / { cont = 0; line = $0; sub(/^ *run: /, "", line); emit(line) }
    ' "$ci")
    [ "$n" -gt 0 ] || fail "no gate steps found in $pack's ci.yml" || return 1
  done
  [ "$packs" -ge 3 ] || fail "expected the rust, omarchy-app and omarchy-tui packs; found $packs"
}
test_stack_rust_long_name_passes_guards_and_tests() {
  # Value: protects=a long project name still passes the new project's guard and
  # tests right after bootstrap; fails_when=the hook stops formatting the starter
  # once the name is substituted; why_new=the hook test checks a stub cargo's
  # call order, and the green test uses the 8-character demo_app; seam=none
  local d="$WORK/stack-rust-long/proj" why
  why="$(rust_ready)"; [ -z "$why" ] || { skip "$why"; return; }
  fresh_copy "$d" || return 1
  mkdir -p "$WORK/home" || return 1
  (cd "$d" && HOME="$WORK/home" rust_env ./bootstrap --name "Acme Example Inventory Reconciliation Service Version Two Ok" \
    --stack rust --yes </dev/null >"$d.out" 2>&1) || fail "bootstrap exited $?: $(tail -20 "$d.out")" || return 1
  (cd "$d" && rust_env bash scripts/check.d/rust.sh && rust_env cargo test --locked -q) >"$d.gate.out" 2>&1 \
    || fail "the rust guards or tests failed for a long name: $(tail -25 "$d.gate.out")"
}
test_stack_rust_scripts_stay_in_the_project_under_cdpath() {
  # Regression test. Run by a bare relative path with an exported CDPATH whose
  # entry holds scripts/, the gate scripts' cd picked that directory: the tier
  # gate checked a decoy project and passed. Each cd must stay in this project.
  local d="$WORK/stack-rust-cdpath/demo-app" decoy="$WORK/stack-rust-cdpath/decoy" why rc
  why="$(rust_ready)"; [ -z "$why" ] || { skip "$why"; return; }
  bootstrap_rust "$d" || return 1
  mkdir -p "$decoy" && cp -R "$d/." "$decoy/" || return 1
  perl -pi -e 's|include = \[\]|include = ["src/missing.rs"]|' "$d/Cargo.toml"
  (cd "$d" && CDPATH="$decoy" rust_env bash scripts/coverage_tiers.sh --validate) >"$d.tiers.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.tiers.out" "include 'src/missing.rs' is not a file" || return 1
  assert_not_contains "$d.tiers.out" "$decoy" || return 1
  # coverage.sh: a stub cargo records where each of its calls runs.
  mkdir -p "$d.bin" || return 1
  printf '#!/bin/sh\npwd -P >> "%s"\n' "$d.where" > "$d.bin/cargo" && chmod +x "$d.bin/cargo" || return 1
  (cd "$d" && CDPATH="$decoy" PATH="$d.bin:$(printenv PATH)" bash scripts/coverage.sh) >"$d.cov.out" 2>&1
  [ "$(sort -u "$d.where")" = "$(cd "$d" && pwd -P)" ] \
    || fail "coverage.sh ran cargo in: $(sort -u "$d.where" | tr '\n' ' ')"
}
test_stack_rust_ratchet_ignores_files_missing_from_the_base() {
  # A base that lists a member it never committed must not block the pull request
  # that adds the file: like the python pack's ratchet, only the base's schema counts.
  local d="$WORK/stack-rust-ratchet-basefiles/demo-app" why
  why="$(rust_ready)"; [ -z "$why" ] || { skip "$why"; return; }
  bootstrap_rust "$d" || return 1
  perl -pi -e 's|include = \[\]|include = ["src/new.rs"]|' "$d/Cargo.toml"
  (cd "$d" && git commit -qam 'base lists src/new.rs without the file') || return 1
  printf '//! New.\n' > "$d/src/new.rs"
  (cd "$d" && git add src/new.rs && git commit -qm 'add src/new.rs') || return 1
  rs_tiers "$d" --ratchet HEAD~1 || fail "a pull request completing the base failed the ratchet: $(cat "$d.tiers.out")" || return 1
  # Only the head's Cargo.lock is checked: a base committed without one still ratchets.
  (cd "$d" && git rm -q --cached Cargo.lock && git commit -qm 'base without Cargo.lock' \
    && git add Cargo.lock && git commit -qm 'add Cargo.lock') || return 1
  rs_tiers "$d" --ratchet HEAD~1 || fail "a base without Cargo.lock failed the ratchet: $(cat "$d.tiers.out")"
}

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
    case "$pack" in _*) continue ;; esac  # partial packs are included, never offered
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
stub_cargo_project() {  # $1 = dir, $2 = pack: a fresh copy bootstrapped as "Demo App"
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
  PATH="$1.stub:$(printenv PATH)" run_bootstrap "$1" --name "Demo App" --stack "$2" --yes \
    || fail "bootstrap exited $?: $(tail -20 "$1.out")"
}
omarchy_app_project() { stub_cargo_project "$1" omarchy-app; }
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
  { pack_files _rust-gates omarchy-app
    printf '%s\n' Cargo.lock .github/actions/install-gitleaks/action.yml
  } > "$d.expected" || return 1
  assert_committed "$d" "$d.expected" || return 1
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
stub_app_binary() {  # $1 = path: a stand-in release binary whose --version prints $2
  mkdir -p "$(dirname "$1")" || return 1
  cat > "$1" <<STUB || return 1
#!/bin/sh
[ "\$1" = --version ] && echo "$2"
STUB
  chmod +x "$1"
}
omarchy_install_artifact_state() {  # bytes, modes and link targets of the three managed paths
  local prefix="$1" path
  for path in "$prefix/bin/demo_app" "$prefix/share/applications/demo_app.desktop" "$prefix/share/icons/hicolor/scalable/apps/demo_app.svg"; do
    printf '%s: ' "${path#"$prefix"/}"
    if [ -L "$path" ]; then
      printf 'symlink '; readlink "$path"
    elif [ -f "$path" ]; then
      perl -e 'printf "%04o ", (stat shift)[2] & 07777' "$path"
      cksum < "$path"
    elif [ -e "$path" ]; then
      echo 'other object'
    else
      echo absent
    fi
  done
}
assert_no_omarchy_install_stage() {
  [ -z "$(find "$1/share/applications" -name '.demo_app.install.*' -print)" ] \
    || fail "private installer staging was not cleaned"
}
test_stack_omarchy_install_stages_before_publication() {
  local pack d prefix kind path rc before
  for pack in omarchy-app omarchy-tui; do
    d="$WORK/staged-$pack/demo-app"
    stub_cargo_project "$d" "$pack" || return 1
    stub_app_binary "$d/target/release/demo_app" 'demo_app 0.0.0' || return 1
    cp "$d/assets/icon.svg" "$d.icon" && cp "$d/packaging/app.desktop.in" "$d.desktop" || return 1
    for kind in missing-icon missing-marker duplicate-exec; do
      prefix="$WORK/staged-$pack/$kind"
      case "$kind" in
        missing-icon) rm "$d/assets/icon.svg" ;;
        missing-marker) sed '/^X-Vibe-Starter-AppId=/d' "$d.desktop" > "$d/packaging/app.desktop.in" ;;
        duplicate-exec) cat "$d.desktop" > "$d/packaging/app.desktop.in"; sed -n '/^Exec=/p' "$d.desktop" >> "$d/packaging/app.desktop.in" ;;
      esac
      (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --no-build) > "$d.install" 2>&1; rc=$?
      [ "$rc" -ne 0 ] || fail "$pack accepted $kind before publication" || return 1
      for path in "$prefix/bin/demo_app" "$prefix/share/applications/demo_app.desktop" "$prefix/share/icons/hicolor/scalable/apps/demo_app.svg"; do
        { [ ! -e "$path" ] && [ ! -L "$path" ]; } || fail "$pack $kind published an unowned artifact" || return 1
      done
      assert_no_omarchy_install_stage "$prefix" || return 1
      cp "$d.icon" "$d/assets/icon.svg" && cp "$d.desktop" "$d/packaging/app.desktop.in" || return 1
      (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --no-build) > "$d.install" 2>&1 || return 1
      before="$(omarchy_install_artifact_state "$prefix")"
      printf '# pending staged upgrade\n' >> "$d/target/release/demo_app"
      rm "$d/assets/icon.svg"
      (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --no-build) > "$d.install" 2>&1; rc=$?
      [ "$rc" -ne 0 ] || fail "$pack accepted a missing upgrade icon" || return 1
      [ "$before" = "$(omarchy_install_artifact_state "$prefix")" ] || fail "$pack changed an installed set before staging completed" || return 1
      assert_no_omarchy_install_stage "$prefix" || return 1
      cp "$d.icon" "$d/assets/icon.svg" || return 1
    done
  done
}
test_stack_omarchy_install_recovers_after_payload_failure_or_interrupt() {
  # The seam is the real install utility's final icon destination, present in
  # both the old direct installer and the staged installer. Staging copies pass.
  local pack d prefix fault recovery rc path
  local real_install
  real_install="$(command -v install)"
  for pack in omarchy-app omarchy-tui; do
    d="$WORK/recovery-$pack/demo-app"
    stub_cargo_project "$d" "$pack" || return 1
    stub_app_binary "$d/target/release/demo_app" 'demo_app 0.0.0' || return 1
    mkdir -p "$d/fault-bin"
    cat > "$d/fault-bin/install" <<'STUB' || return 1
#!/usr/bin/env bash
for last do :; done
if [ "$last" = "$INSTALLER_FAULT_TARGET" ]; then
  echo "$INSTALLER_FAULT" >> "$INSTALLER_FAULT_LOG"
  if [ "$INSTALLER_FAULT" = interrupt ]; then kill -TERM "$PPID"; fi
  exit 42
fi
exec "$INSTALLER_REAL_INSTALL" "$@"
STUB
    chmod +x "$d/fault-bin/install" || return 1
    for fault in failure interrupt; do
      # Recovery operations get independent failed installs: uninstall must
      # succeed directly, not only after a successful retry repaired the set.
      for recovery in retry uninstall; do
        prefix="$WORK/recovery-$pack/$fault-$recovery"
        : > "$d.fault-log"
        (cd "$d" && PATH="$d/fault-bin:$(printenv PATH)" PREFIX="$prefix" INSTALLER_FAULT="$fault" \
          INSTALLER_FAULT_TARGET="$prefix/share/icons/hicolor/scalable/apps/demo_app.svg" \
          INSTALLER_FAULT_LOG="$d.fault-log" INSTALLER_REAL_INSTALL="$real_install" ./scripts/install.sh --no-build) > "$d.install" 2>&1; rc=$?
        case "$fault" in
          failure) assert_exit 42 "$rc" || return 1 ;;
          interrupt) assert_exit 143 "$rc" || return 1 ;;
        esac
        [ "$(cat "$d.fault-log")" = "$fault" ] || fail "the final-icon fault seam did not fire once" || return 1
        path="$prefix/share/applications/demo_app.desktop"
        { [ -f "$path" ] && [ ! -L "$path" ]; } || fail "$pack $fault left payloads without an ownership entry" || return 1
        (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --print-desktop-entry) | cmp -s - "$path" \
          || fail "the retained ownership entry is not the complete rendered entry" || return 1
        assert_no_omarchy_install_stage "$prefix" || return 1
        if [ "$recovery" = retry ]; then
          (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --no-build) > "$d.install" 2>&1 || fail "$pack cannot retry a $fault install" || return 1
          cmp -s "$d/assets/icon.svg" "$prefix/share/icons/hicolor/scalable/apps/demo_app.svg" || return 1
        fi
        (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --uninstall) > "$d.install" 2>&1 || fail "$pack cannot uninstall a $fault install" || return 1
        for path in "$prefix/bin/demo_app" "$prefix/share/applications/demo_app.desktop" "$prefix/share/icons/hicolor/scalable/apps/demo_app.svg"; do
          { [ ! -e "$path" ] && [ ! -L "$path" ]; } || fail "$pack left a managed artifact after recovery" || return 1
        done
      done
    done
  done
}
test_stack_omarchy_install_entry_publication_failure_preserves_installed_files() {
  local pack d prefix kind before rc real_mv
  real_mv="$(command -v mv)"
  for pack in omarchy-app omarchy-tui; do
    d="$WORK/entry-failure-$pack/demo-app"
    stub_cargo_project "$d" "$pack" || return 1
    stub_app_binary "$d/target/release/demo_app" 'demo_app 0.0.0' || return 1
    mkdir -p "$d/fault-bin"
    cat > "$d/fault-bin/mv" <<'STUB' || return 1
#!/usr/bin/env bash
for last do :; done
if [ "$last" = "$INSTALLER_FAULT_TARGET" ]; then echo fired >> "$INSTALLER_FAULT_LOG"; exit 42; fi
exec "$INSTALLER_REAL_MV" "$@"
STUB
    chmod +x "$d/fault-bin/mv" || return 1
    for kind in fresh upgrade; do
      prefix="$WORK/entry-failure-$pack/$kind"
      if [ "$kind" = upgrade ]; then
        (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --no-build) > "$d.install" 2>&1 || return 1
        printf '# new release artifact\n' >> "$d/target/release/demo_app"
      fi
      before="$(omarchy_install_artifact_state "$prefix")"
      : > "$d.fault-log"
      (cd "$d" && PATH="$d/fault-bin:$(printenv PATH)" PREFIX="$prefix" INSTALLER_FAULT_TARGET="$prefix/share/applications/demo_app.desktop" \
        INSTALLER_FAULT_LOG="$d.fault-log" INSTALLER_REAL_MV="$real_mv" ./scripts/install.sh --no-build) > "$d.install" 2>&1; rc=$?
      assert_exit 42 "$rc" || return 1
      [ "$(cat "$d.fault-log")" = fired ] || fail "entry-publication fault seam did not fire once" || return 1
      [ "$before" = "$(omarchy_install_artifact_state "$prefix")" ] || fail "$pack $kind changed managed files before entry publication" || return 1
      assert_no_omarchy_install_stage "$prefix" || return 1
    done
  done
}
test_stack_omarchy_install_preserves_obsolete_temp_collisions() {
  local pack d prefix kind obsolete target before_mode before_contents before_link before_object_mode rc
  for pack in omarchy-app omarchy-tui; do
    d="$WORK/temp-collisions-$pack/demo-app"
    stub_cargo_project "$d" "$pack" || return 1
    stub_app_binary "$d/target/release/demo_app" 'demo_app 0.0.0' || return 1
    for kind in symlink dangling file directory; do
      prefix="$WORK/temp-collisions-$pack/$kind"
      mkdir -p "$prefix/share/applications"
      obsolete="$prefix/share/applications/demo_app.desktop.tmp"
      target="$prefix/sentinel"
      printf 'unrelated bytes\n' > "$target"; chmod 600 "$target"
      before_mode="$(perl -e 'printf "%04o", (stat shift)[2] & 07777' "$target")"
      before_contents="$(cat "$target")"
      case "$kind" in
        symlink) ln -s "$target" "$obsolete" ;;
        dangling) ln -s "$prefix/missing" "$obsolete" ;;
        file) printf 'unrelated temporary file\n' > "$obsolete"; chmod 600 "$obsolete" ;;
        directory) mkdir "$obsolete"; chmod 700 "$obsolete" ;;
      esac
      before_link="$(readlink "$obsolete" 2>/dev/null || true)"
      before_object_mode="$(perl -e 'printf "%04o", (lstat shift)[2] & 07777' "$obsolete")"
      (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --no-build) > "$d.install" 2>&1; rc=$?
      assert_exit 0 "$rc" || return 1
      { [ -f "$prefix/share/applications/demo_app.desktop" ] && [ ! -L "$prefix/share/applications/demo_app.desktop" ]; } \
        || fail "$pack installed a symlink as the ownership entry" || return 1
      (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --no-build) > "$d.install" 2>&1 || return 1
      (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --uninstall) > "$d.install" 2>&1 || return 1
      [ "$before_contents" = "$(cat "$target")" ] && [ "$before_mode" = "$(perl -e 'printf "%04o", (stat shift)[2] & 07777' "$target")" ] \
        || fail "$pack changed the unrelated sentinel bytes or mode" || return 1
      [ "$before_object_mode" = "$(perl -e 'printf "%04o", (lstat shift)[2] & 07777' "$obsolete")" ] \
        || fail "$pack removed or changed the obsolete object mode" || return 1
      case "$kind" in
        symlink|dangling) [ -L "$obsolete" ] && [ "$before_link" = "$(readlink "$obsolete")" ] || return 1 ;;
        file) [ -f "$obsolete" ] && [ ! -L "$obsolete" ] && [ "$(cat "$obsolete")" = 'unrelated temporary file' ] || return 1 ;;
        directory) [ -d "$obsolete" ] && [ ! -L "$obsolete" ] && [ -z "$(ls -A "$obsolete")" ] || return 1 ;;
      esac
      { [ ! -e "$prefix/missing" ] && [ ! -L "$prefix/missing" ]; } || fail "installer created a dangling-link target" || return 1
      assert_no_omarchy_install_stage "$prefix" || return 1
    done
  done
}
test_stack_omarchy_install_compares_exec_bytes_without_unescaping() {
  local pack d prefix entry before rc
  for pack in omarchy-app omarchy-tui; do
    d="$WORK/exec-bytes-$pack/demo-app"; prefix="$WORK/exec-bytes-$pack/prefix"
    stub_cargo_project "$d" "$pack" || return 1
    stub_app_binary "$d/target/release/demo_app" 'demo_app 0.0.0' || return 1
    # Desktop entries encode a literal backslash with four backslashes in a
    # quoted argument. Neither the renderer nor ownership comparison unescapes it.
    perl -pi -e 's/^(Exec=.*)$/$1 . q{ "} . ("\\" x 4) . q{example"}/e' "$d/packaging/app.desktop.in" || return 1
    (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --no-build) > "$d.install" 2>&1 || return 1
    (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --no-build) > "$d.install" 2>&1 \
      || fail "$pack rejected an unchanged backslash-bearing Exec" || return 1
    entry="$prefix/share/applications/demo_app.desktop"
    cp "$entry" "$d.entry" || return 1
    perl -pi -e 's/example/exampleX/' "$entry"
    before="$(omarchy_install_artifact_state "$prefix")"
    (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --uninstall) > "$d.install" 2>&1; rc=$?
    assert_exit 1 "$rc" || return 1
    [ "$before" = "$(omarchy_install_artifact_state "$prefix")" ] || fail "mismatched Exec changed owned paths" || return 1
    cp "$d.entry" "$entry" || return 1
    (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --uninstall) > "$d.install" 2>&1 || return 1
    (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --no-build) > "$d.install" 2>&1 || return 1
    cp "$d/packaging/app.desktop.in" "$d.desktop" || return 1
    perl -pi -e 's/^(Exec=.*)$/$1 %U/' "$d/packaging/app.desktop.in"
    before="$(omarchy_install_artifact_state "$prefix")"
    (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --uninstall) > "$d.install" 2>&1; rc=$?
    assert_exit 1 "$rc" || return 1
    [ "$before" = "$(omarchy_install_artifact_state "$prefix")" ] || fail "new-template uninstall changed old install" || return 1
    cp "$d.desktop" "$d/packaging/app.desktop.in" || return 1
    (cd "$d" && PREFIX="$prefix" ./scripts/install.sh --uninstall) > "$d.install" 2>&1 \
      || fail "old-template uninstall did not permit launch-command migration" || return 1
  done
}
test_stack_omarchy_app_install_script_installs_and_uninstalls() {
  # install.sh puts exactly three files under PREFIX and removes exactly those;
  # stubs stand in for cargo and the release binary, so nothing is compiled.
  command -v jq >/dev/null 2>&1 || { skip "jq not installed"; return; }
  local w="$WORK/omarchy-app-install" d="$WORK/omarchy-app-install/demo-app" p="$WORK/omarchy-app-install/prefix" rc f entry
  omarchy_app_project "$d" || return 1
  mkdir -p "$w/elsewhere/release" || return 1
  stub_app_binary "$d/target/release/demo_app" "demo_app 0.0.0" || return 1
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
  # With --no-build, the binary is found where CARGO_TARGET_DIR put it.
  mv "$d/target/release/demo_app" "$w/elsewhere/release/demo_app" || return 1
  (cd "$d" && CARGO_TARGET_DIR="$w/elsewhere" PREFIX="$p" ./scripts/install.sh --no-build) \
    >"$d.install" 2>&1 || fail "install with CARGO_TARGET_DIR exited $?: $(cat "$d.install")" || return 1
  assert_exists "$p/bin/demo_app" || return 1
  (cd "$d" && PREFIX="$p" ./scripts/install.sh --no-build) >"$d.install" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.install" "is missing; build it first" || return 1
  # Regression test. install.sh guessed target/release/<app id>, but cargo's
  # build.target-dir, CARGO_BUILD_TARGET_DIR and build.target move the binary,
  # and sudo drops CARGO_TARGET_DIR: it now installs the one cargo reports.
  stub_app_binary "$w/built/demo_app" "demo_app 0.0.0" && echo '# the one cargo built' >> "$w/built/demo_app" || return 1
  mkdir -p "$w/bin" || return 1
  cat > "$w/bin/cargo" <<STUB || return 1
#!/bin/sh
echo "cargo \$*" > "$w/cargo.args"
echo '{"reason":"compiler-artifact","target":{"kind":["lib"],"name":"demo_app"},"executable":null}'
echo '{"reason":"compiler-artifact","target":{"kind":["bin"],"name":"demo_app"},"executable":"$w/built/demo_app"}'
echo '{"reason":"build-finished","success":true}'
STUB
  chmod +x "$w/bin/cargo" || return 1
  (cd "$d" && PATH="$w/bin:$(printenv PATH)" PREFIX="$p" ./scripts/install.sh) >"$d.install" 2>&1 \
    || fail "install with a build exited $?: $(cat "$d.install")" || return 1
  assert_contains "$w/cargo.args" "cargo build --locked --release --message-format=json-render-diagnostics" || return 1
  cmp -s "$w/built/demo_app" "$p/bin/demo_app" || fail "install did not take the binary cargo reported" || return 1
  # Regression test. A binary built before the last VERSION bump installed under
  # the new version's entry: its --version must name this app at this VERSION.
  cp "$d/VERSION" "$d.VERSION" && printf '0.0.1\n' > "$d/VERSION" || return 1
  for f in "" --no-build; do
    (cd "$d" && PATH="$w/bin:$(printenv PATH)" CARGO_TARGET_DIR="$w/elsewhere" PREFIX="$p" ./scripts/install.sh ${f:+"$f"}) \
      >"$d.install" 2>&1; rc=$?
    assert_exit 1 "$rc" || { echo "    for: install.sh $f"; return 1; }
    assert_contains "$d.install" "reports 'demo_app 0.0.0', not 'demo_app 0.0.1': rebuild it" || return 1
  done
  cp "$d.VERSION" "$d/VERSION" || return 1
  assert_contains "$entry" "X-AppVersion=0.0.0" || return 1
  cmp -s "$w/built/demo_app" "$p/bin/demo_app" || fail "a refused install changed the installed binary" || return 1
  # Regression test. BINDIR, APPDIR and ICONDIR came from the environment, and
  # every AppImage exports APPDIR to its children: only PREFIX moves the install.
  (cd "$d" && BINDIR="$w/env" APPDIR="$w/env" ICONDIR="$w/env" PATH="$w/bin:$(printenv PATH)" PREFIX="$p" \
    ./scripts/install.sh) >"$d.install" 2>&1 || fail "install with BINDIR, APPDIR and ICONDIR set exited $?: $(cat "$d.install")" || return 1
  (cd "$d" && BINDIR="$w/env" PREFIX="$p" ./scripts/install.sh --print-desktop-entry) | cmp -s - "$entry" \
    || fail "BINDIR in the environment changed the desktop entry" || return 1
  assert_absent "$w/env" || return 1
  # Regression test. A relative PREFIX resolved against the project, not the
  # caller, and wrote a relative Exec=: it is refused before anything is written.
  for f in "" --print-desktop-entry; do
    (cd "$d" && PATH="$w/bin:$(printenv PATH)" PREFIX=rel ./scripts/install.sh ${f:+"$f"}) >"$d.install" 2>&1; rc=$?
    assert_exit 2 "$rc" || { echo "    for: install.sh $f"; return 1; }
    assert_contains "$d.install" "PREFIX must be an absolute path: rel" || return 1
  done
  assert_absent "$d/rel" || return 1
  # Regression test. install.sh replaced any <prefix>/bin/<app id>, and
  # --uninstall removed it. One without this app's desktop entry is another
  # tool's: both now leave it alone, and say so.
  mkdir -p "$w/other/bin" && printf 'another tool\n' > "$w/other/bin/demo_app" || return 1
  for f in "" --no-build --uninstall; do
    (cd "$d" && PATH="$w/bin:$(printenv PATH)" PREFIX="$w/other" ./scripts/install.sh ${f:+"$f"}) >"$d.install" 2>&1; rc=$?
    assert_exit 1 "$rc" || { echo "    for: install.sh $f"; return 1; }
    assert_contains "$d.install" "no valid ownership entry at $w/other/share/applications/demo_app.desktop" || return 1
    [ "$(cat "$w/other/bin/demo_app")" = "another tool" ] || fail "install.sh $f replaced or removed another tool's binary" || return 1
  done
  assert_absent "$w/other/share" || return 1
  # A same-named desktop entry does not prove ownership. Check both launch
  # formats, all three destinations, and every mutating mode without building.
  local pack owned prefix kind mode path before after
  for pack in omarchy-app omarchy-tui; do
    owned="$w/ownership-$pack/demo-app"
    stub_cargo_project "$owned" "$pack" || return 1
    stub_app_binary "$owned/target/release/demo_app" "demo_app 0.0.0" || return 1
    for kind in unrelated entry-only icon-only wrong-marker wrong-exec duplicate-marker duplicate-exec \
      dir-binary dir-entry dir-icon link-binary link-entry link-icon dangling-binary dangling-entry dangling-icon; do
      prefix="$w/collision-$pack-$kind"
      mkdir -p "$prefix/bin" "$prefix/share/applications" "$prefix/share/icons/hicolor/scalable/apps" || return 1
      path="$prefix/share/applications/demo_app.desktop"
      case "$kind" in
        unrelated)
          printf 'another binary\n' > "$prefix/bin/demo_app"
          printf '[Desktop Entry]\nName=Another app\nExec=/other/app\n' > "$path"
          printf 'another icon\n' > "$prefix/share/icons/hicolor/scalable/apps/demo_app.svg" ;;
        entry-only) printf '[Desktop Entry]\nExec=/other/app\n' > "$path" ;;
        icon-only) printf 'another icon\n' > "$prefix/share/icons/hicolor/scalable/apps/demo_app.svg" ;;
        *)
          (cd "$owned" && PREFIX="$prefix" ./scripts/install.sh --print-desktop-entry) > "$path" || return 1
          case "$kind" in
            wrong-marker) sed 's/X-Vibe-Starter-AppId=demo_app/X-Vibe-Starter-AppId=other_app/' "$path" > "$path.new" && mv "$path.new" "$path" ;;
            wrong-exec) sed 's|^Exec=.*|Exec=/other/app|' "$path" > "$path.new" && mv "$path.new" "$path" ;;
            duplicate-marker) printf 'X-Vibe-Starter-AppId=demo_app\n' >> "$path" ;;
            duplicate-exec) sed -n '/^Exec=/p' "$path" >> "$path.dup" && cat "$path.dup" >> "$path" && rm "$path.dup" ;;
            *)
              case "$kind" in
                *-binary) path="$prefix/bin/demo_app" ;;
                *-icon) path="$prefix/share/icons/hicolor/scalable/apps/demo_app.svg" ;;
              esac
              rm -f "$path"
              case "$kind" in
                dir-*) mkdir "$path" ;;
                link-*) printf 'external file\n' > "$prefix/external"; ln -s "$prefix/external" "$path" ;;
                dangling-*) ln -s "$prefix/missing" "$path" ;;
              esac ;;
          esac ;;
      esac
      before="$(tree_fingerprint "$prefix"; (cd "$prefix" && find . -type d -print && find . -type l -exec ls -ld {} +))"
      for mode in "" --no-build --uninstall; do
        (cd "$owned" && PATH="$w/bin:$(printenv PATH)" PREFIX="$prefix" ./scripts/install.sh ${mode:+"$mode"}) > "$owned.install" 2>&1; rc=$?
        assert_exit 1 "$rc" || { echo "    for $pack $kind ${mode:-install}"; return 1; }
        after="$(tree_fingerprint "$prefix"; (cd "$prefix" && find . -type d -print && find . -type l -exec ls -ld {} +))"
        [ "$before" = "$after" ] || fail "$pack $kind ${mode:-install} changed unowned artifacts" || return 1
      done
    done
    # A real owned install can advance its version and remove its managed set.
    prefix="$w/upgrade-$pack"
    (cd "$owned" && PREFIX="$prefix" ./scripts/install.sh --no-build) > "$owned.install" 2>&1 || return 1
    printf '0.0.1\n' > "$owned/VERSION"
    stub_app_binary "$owned/target/release/demo_app" "demo_app 0.0.1" || return 1
    (cd "$owned" && PREFIX="$prefix" ./scripts/install.sh --no-build) > "$owned.install" 2>&1 || return 1
    assert_contains "$prefix/share/applications/demo_app.desktop" 'X-AppVersion=0.0.1' || return 1
    (cd "$owned" && PREFIX="$prefix" ./scripts/install.sh --uninstall) > "$owned.install" 2>&1 || return 1
    for path in bin/demo_app share/applications/demo_app.desktop share/icons/hicolor/scalable/apps/demo_app.svg; do
      assert_absent "$prefix/$path" || return 1
    done
  done
  (cd "$d" && ./scripts/install.sh --bogus) >/dev/null 2>&1; rc=$?
  assert_exit 2 "$rc" || return 1
  (cd "$d/scripts" && ./install.sh --help) >"$d.help" 2>&1 \
    || fail "--help from scripts/ exited $?: $(cat "$d.help")" || return 1
  assert_contains "$d.help" "--print-desktop-entry" || return 1
  (cd "$d" && PREFIX='/tmp/a"b' ./scripts/install.sh --print-desktop-entry) >"$d.install" 2>&1; rc=$?
  assert_exit 2 "$rc" || return 1
  assert_contains "$d.install" "unsupported character in PREFIX"
}
test_stack_omarchy_app_guard_refuses_colour_literals_and_needs_its_validator_in_ci() {
  local d="$WORK/omarchy-app-guard/demo-app" rc lit f
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
    'gpui_kit::transparent_black()' 'gpui_kit::Rgba::try_from("#123456").unwrap()' 'gpui_kit::green()' \
    'gpui_kit::blue()' 'gpui_kit::yellow()' 'gpui_kit::transparent_white()'; do
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
  # Regression test. DESIGN.md bans shadows, glass and rounded pills too, but the
  # guard refused only colours and gradients: each of these passed it.
  while IFS='|' read -r lit want; do
    printf 'pub fn style(el: gpui_kit::Div) -> gpui_kit::Div {\n    %s\n}\n' "$lit" > "$d/src/tint.rs"
    (cd "$d" && CHECK_CI=0 DESKTOP_FILE_VALIDATE_BIN=/nonexistent bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1; rc=$?
    assert_exit 1 "$rc" || { echo "    for: $lit"; return 1; }
    assert_contains "$d.guard" "$want" || return 1
    assert_contains "$d.guard" "src/tint.rs:2:" || return 1
  done <<'CASES'
el.shadow_lg()|shadows in src/
el.shadow_2xl()|shadows in src/
el.shadow(vec![])|shadows in src/
let shadows: Vec<gpui_kit::BoxShadow> = Vec::new();|shadows in src/
el.rounded_full()|rounded pills in src/
el.rounded_lg()|rounded pills in src/
el.rounded_tl_3xl()|rounded pills in src/
el.bg(gpui_kit::pattern_slash(cx.omarchy().border, 1.0, 4.0))|pattern fills in src/
el.bg(gpui_kit::checkerboard(cx.omarchy().border, 8.0))|pattern fills in src/
window_background: gpui_kit::WindowBackgroundAppearance::Blurred,|see-through window in src/
window_background: gpui_kit::WindowBackgroundAppearance::Transparent,|see-through window in src/
CASES
  # Colours from the theme's roles pass, and so does a helper named like a colour.
  printf 'pub fn tint(cx: &gpui_kit::App) -> gpui_kit::Hsla {\n    redraw_hint(cx.omarchy().accent.opacity(0.5))\n}\n' > "$d/src/tint.rs"
  (cd "$d" && CHECK_CI=0 DESKTOP_FILE_VALIDATE_BIN=/nonexistent bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1 \
    || fail "theme-derived colours failed the guard: $(cat "$d.guard")" || return 1
  # Small radii, removing a shadow, an opaque window and helpers named like a
  # banned call pass too.
  printf 'pub fn style(el: gpui_kit::Div) -> gpui_kit::Div {\n    shadowed_text(el.rounded_sm().rounded_none().shadow_none(), rounded_full_hint())\n}\npub const BG: gpui_kit::WindowBackgroundAppearance = gpui_kit::WindowBackgroundAppearance::Opaque;\n' > "$d/src/tint.rs"
  (cd "$d" && CHECK_CI=0 DESKTOP_FILE_VALIDATE_BIN=/nonexistent bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1 \
    || fail "flat, square styling failed the guard: $(cat "$d.guard")" || return 1
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
  # ...and a plain rust project's own guards, the Rust gates included, accept
  # colour, gradient and shadow text (needs a Rust toolchain, as the rust pack's tests do).
  if [ -z "$(rust_ready)" ]; then
    bootstrap_rust "$d.rust" || return 1
    printf '// rgb(0) white() red() linear_gradient( Color::Rgb( shadow_lg( rounded_full( are fine outside Omarchy packs\n' >> "$d.rust/src/lib.rs"
    (cd "$d.rust" && for g in scripts/check.d/*.sh; do rust_env bash "$g" || exit 1; done) >"$d.rust.guard" 2>&1 \
      || fail "a plain rust project refused colour text: $(tail -20 "$d.rust.guard")" || return 1
  fi
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
omarchy_app_heavy_ready() {  # why the heavy omarchy-app build can't run here; empty = run it
  if [ "${CI:-}" != "true" ] && [ "${SELFTEST_HEAVY:-}" != "1" ]; then
    echo "builds GPUI (minutes): set SELFTEST_HEAVY=1 to run it here; CI runs it in the heavy job"
    return
  fi
  local why
  why="$(rust_ready)"
  [ -z "$why" ] || { echo "$why"; return; }
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
  # CI caches one target directory per pack, named after it, so coverage never
  # mixes two packs' builds; locally it lives in the copy.
  target="${SELFTEST_CARGO_TARGET_DIR:+$SELFTEST_CARGO_TARGET_DIR/omarchy-app}"
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
  # An include that isn't a partial pack's name (_ and lowercase letters, digits,
  # _ or -) or has no files/ is a broken template: exit 1 (no other --name can
  # help) before any file changes. Each malformed name has a files/ directory, so
  # only the name rule can reject it.
  local d inc before rc want
  while IFS='|' read -r inc want; do
    d="$WORK/stack-includes-bad/$(printf '%s' "$inc" | tr '/.' '--')/demo"
    fresh_copy "$d" || return 1
    fixture_pack "$d/template/stacks/fixture" || return 1
    case "$inc" in _missing) ;; *) mkdir -p "$d/template/stacks/$inc/files" || return 1 ;; esac
    printf '%s\n' "$inc" > "$d/template/stacks/fixture/includes"
    before="$(tree_fingerprint "$d")"
    run_bootstrap "$d" --name demo --stack fixture --yes; rc=$?
    assert_exit 1 "$rc" || { echo "    for: $inc"; return 1; }
    assert_contains "$d.out" "$want" || return 1
    assert_not_contains "$d.out" "pass --name" || return 1
    [ "$before" = "$(tree_fingerprint "$d")" ] || fail "include '$inc' changed files before its rejection" || return 1
  done <<'CASES'
fixture-shared|Invalid include 'fixture-shared'
_missing|names '_missing', which has no files/
_bad/name|Invalid include '_bad/name'
_Upper|Invalid include '_Upper'
_dot.dot|Invalid include '_dot.dot'
CASES
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
test_template_gitignore_ignores_no_tracked_file() {
  # Regression test. The root .gitignore (every new project's too) ignores .gstack/,
  # and the omarchy-plugin pack's .gstack/package-json-path survived only because it
  # was force-added: a ZIP or degit copy committed with `git add -A` dropped it, and
  # the new plugin's first /ship then bumped VERSION alone.
  local rc
  git -C "$REPO" ls-files -z > "$WORK/tracked.z" || fail "git ls-files failed" || return 1
  [ -s "$WORK/tracked.z" ] || fail "git ls-files listed nothing" || return 1
  git -C "$REPO" check-ignore --no-index -z --stdin < "$WORK/tracked.z" > "$WORK/ignored.z"; rc=$?
  # check-ignore exits 1 when nothing matched, 0 when something did, 128 on error.
  [ "$rc" -ne 0 ] || fail "a .gitignore ignores tracked files: $(tr '\0' ' ' < "$WORK/ignored.z")" || return 1
  [ "$rc" -eq 1 ] || fail "git check-ignore failed with $rc"
}
test_stack_pack_ci_jobs_have_timeouts() {
  # Regression test. The rust, python and foldkit packs' CI jobs had no
  # timeout-minutes, so a hung test or download held a runner for GitHub's
  # 6-hour default on every push of every new project.
  local ci jobs timeouts n=0
  for ci in "$REPO"/template/stacks/*/files/.github/workflows/ci.yml; do
    n=$((n + 1))
    jobs="$(awk '/^jobs:/ { in_jobs = 1; next } in_jobs && /^[^ #]/ { in_jobs = 0 } in_jobs && /^  [A-Za-z0-9_-]+:$/ { n++ } END { print n + 0 }' "$ci")"
    timeouts="$(grep -cE '^    timeout-minutes: [1-9][0-9]*$' "$ci")"
    [ "$jobs" -gt 0 ] && [ "$jobs" = "$timeouts" ] \
      || fail "${ci#"$REPO"/}: $jobs job(s), $timeouts with timeout-minutes" || return 1
  done
  [ "$n" -ge 6 ] || fail "expected every pack's ci.yml; found $n"
}
test_stack_every_pack_fills_every_command_placeholder() {
  # TEMPLATE.md: each pack's new project has none of the pack's command
  # placeholders left. The omarchy tests checked only {{TEST_CMD, so a pack
  # missing SHIP_GATE left {{SHIP_GATE: ...}} in a new project's AGENTS.md.
  # Network tools are stubs that fail, so each hook takes its offline path.
  local stub="$WORK/fill-all.stub" pack d key tool n=0
  mkdir -p "$stub" || return 1
  for tool in cargo pnpm node uv; do
    printf '#!/bin/sh\nexit 101\n' > "$stub/$tool" && chmod +x "$stub/$tool" || return 1
  done
  for pack in "$REPO"/template/stacks/*/; do
    pack="$(basename "$pack")"
    case "$pack" in _*) continue ;; esac
    n=$((n + 1))
    d="$WORK/fill-all/$pack/demo-app"
    fresh_copy "$d" || return 1
    PATH="$stub:$(printenv PATH)" run_bootstrap "$d" --name "Demo App" --stack "$pack" --yes \
      || fail "$pack: bootstrap exited $?: $(tail -5 "$d.out")" || return 1
    for key in INSTALL_CMD DEV_CMD BUILD_CMD CHECK_CMD TEST_CMD SHIP_GATE STACK COVERAGE_ENFORCEMENT \
      $(sed -n 's/^\([A-Z_]*\)=.*/\1/p' "$REPO/template/stacks/$pack/commands") PROJECT_NAME PACKAGE_NAME YEAR; do
      assert_tree_lacks "$d" "{{$key" || { echo "    in the $pack pack's project"; return 1; }
    done
  done
  [ "$n" -ge 6 ] || fail "expected at least six packs; found $n"
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
test_rust_gates_packs_name_jq_in_their_stack() {
  # _rust-gates' coverage_tiers.sh fails without jq; README's Stack line is the
  # only prerequisite list a new project gets, so every pack including it says so.
  local inc pack n=0
  for inc in "$REPO"/template/stacks/*/includes; do
    grep -qxF _rust-gates "$inc" || continue
    pack="$(basename "$(dirname "$inc")")"
    n=$((n + 1))
    grep -q '^STACK=.*jq (scripts/coverage_tiers.sh)' "$REPO/template/stacks/$pack/commands" \
      || fail "$pack's STACK does not name jq, which scripts/coverage_tiers.sh needs" || return 1
  done
  [ "$n" -ge 3 ] || fail "expected the three Rust packs; found $n"
}
test_omarchy_packs_share_one_install_script() {
  # Two copies (rule of three: not yet shared); they must not drift apart.
  cmp -s "$REPO/template/stacks/omarchy-app/files/scripts/install.sh" \
    "$REPO/template/stacks/omarchy-tui/files/scripts/install.sh" \
    || fail "omarchy-app's and omarchy-tui's scripts/install.sh differ"
}
test_stack_omarchy_scripts_stay_in_the_project_under_cdpath() {
  # Regression test. Run as `bash scripts/install.sh` with an exported CDPATH
  # whose entry also holds scripts/, the bare cd picked that directory:
  # install.sh printed its path and the decoy's desktop entry, and exited 0.
  local d="$WORK/omarchy-cdpath/demo-app" decoy="$WORK/omarchy-cdpath/decoy" bad
  omarchy_app_project "$d" || return 1
  mkdir -p "$decoy/scripts" "$decoy/packaging" || return 1
  printf 'Name=DECOY @BINDIR@\n' > "$decoy/packaging/app.desktop.in"
  printf '9.9.9\n' > "$decoy/VERSION"
  (cd "$d" && PREFIX=/usr/local ./scripts/install.sh --print-desktop-entry) > "$d.want" || return 1
  (cd "$d" && CDPATH="$decoy" PREFIX=/usr/local bash scripts/install.sh --print-desktop-entry) > "$d.got" 2>&1 \
    || fail "install.sh failed under CDPATH: $(cat "$d.got")" || return 1
  cmp -s "$d.want" "$d.got" || fail "install.sh under CDPATH printed: $(head -3 "$d.got")" || return 1
  # Every pack script that finds a directory from a path clears CDPATH for that cd.
  bad="$(git -C "$REPO" grep -n 'cd [^|;&]*dirname' -- template/stacks | grep -v "CDPATH=''" || true)"
  [ -z "$bad" ] || fail "a cd without CDPATH='': $bad"
}
omarchy_tui_project() { stub_cargo_project "$1" omarchy-tui; }
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
  { pack_files _rust-gates omarchy-tui
    printf '%s\n' Cargo.lock .github/actions/install-gitleaks/action.yml
  } > "$d.expected" || return 1
  assert_committed "$d" "$d.expected" || return 1
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
    'Color::from_u32(0x0012_3456)' 'Color::from([0x12, 0x34, 0x56])' '"#123456".parse::<Color>().unwrap()' \
    '"#123456".parse::<ratatui::style::Color>().unwrap()' '"#123456".parse::<::ratatui::style::Color>().unwrap()' \
    'Color::from_str("#123456").unwrap()' 'Color::from_hsl(hsl)' 'Color::from_hsluv(hsluv)'; do
    printf 'use ratatui::style::Color;\npub const X: Color = %s;\n' "$lit" > "$d/src/tint.rs"
    (cd "$d" && CHECK_CI=0 DESKTOP_FILE_VALIDATE_BIN=/nonexistent bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1; rc=$?
    assert_exit 1 "$rc" || return 1
    assert_contains "$d.guard" "src/tint.rs:2:" || return 1
  done
  # The 16 named colours pass, and so do a type whose name ends in Color and a
  # helper whose name ends in parse.
  printf 'use ratatui::style::{Color, Style};\npub const X: Style = Style::new().fg(Color::Blue).bg(Color::Reset);\npub fn accent(t: &Theme) -> ThemeColor { ThemeColor::from(t.accent) }\npub fn load(s: &str) -> Color { reparse::<Color>(s) }\n' > "$d/src/tint.rs"
  (cd "$d" && CHECK_CI=0 DESKTOP_FILE_VALIDATE_BIN=/nonexistent bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1 \
    || fail "named colours failed the guard: $(cat "$d.guard")" || return 1
  rm -f "$d/src/tint.rs"
  (cd "$d" && CHECK_CI=1 DESKTOP_FILE_VALIDATE_BIN=/nonexistent bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard" "required in CI" || return 1
  # The validator gets exactly the entry install.sh writes, and its failure fails the guard.
  # shellcheck disable=SC2016  # $1 belongs to the stub
  printf '#!/bin/sh\ncp "$1" "%s"\n' "$d.validated" > "$d.stub/validate" && chmod +x "$d.stub/validate" || return 1
  (cd "$d" && CHECK_CI=1 DESKTOP_FILE_VALIDATE_BIN="$d.stub/validate" bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1 \
    || fail "the guard failed with a passing validator: $(cat "$d.guard")" || return 1
  (cd "$d" && PREFIX=/usr/local ./scripts/install.sh --print-desktop-entry) | cmp -s - "$d.validated" \
    || fail "the validator did not get install.sh's entry" || return 1
  printf '#!/bin/sh\necho "validator: bad entry" >&2\nexit 1\n' > "$d.stub/validate"
  (cd "$d" && CHECK_CI=1 DESKTOP_FILE_VALIDATE_BIN="$d.stub/validate" bash scripts/check.d/omarchy.sh) >"$d.guard" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard" "validator: bad entry"
}
omarchy_tui_heavy_ready() {  # why the heavy omarchy-tui build can't run here; empty = run it
  if [ "${CI:-}" != "true" ] && [ "${SELFTEST_HEAVY:-}" != "1" ]; then
    echo "builds a real project: set SELFTEST_HEAVY=1 to run it here; CI runs it in the heavy job"
    return
  fi
  local why
  why="$(rust_ready)"
  [ -z "$why" ] || { echo "$why"; return; }
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
  # Setup only fetches Omarchy's pinned tools; loading the plugin into the desktop
  # is the explicit dev step.
  assert_contains "$d/CLAUDE.md" "Install / bootstrap: \`./scripts/omarchy-kit\`" || return 1
  assert_contains "$d/CLAUDE.md" "Dev / run locally: \`./scripts/dev-link.sh\`" || return 1
  assert_contains "$d/.bootstrapped" "with the omarchy-plugin stack pack" || return 1
  # This pack writes no lockfile, so the closing note must not order one committed.
  assert_contains "$d.out" "commit the lockfile if the pack wrote one" || return 1
  for s in '{{PACKAGE_NAME}}' '{{TEST_CMD' TEMPLATE.md template/stacks template-selftest; do
    assert_tree_lacks "$d" "$s" || return 1
  done
  # The gstack pin is committed; the rest of .gstack/ stays local.
  mkdir -p "$d/.gstack" && : > "$d/.gstack/state"
  (cd "$d" && git add -A) || fail "git add failed" || return 1
  git -C "$d" ls-files --error-unmatch -- .gstack/package-json-path >/dev/null 2>&1 \
    || fail "git would not commit .gstack/package-json-path" || return 1
  git -C "$d" check-ignore -q -- .gstack/state || fail "git would commit other .gstack/ state" || return 1
  pack_files omarchy-plugin > "$d.expected" || return 1
  assert_committed "$d" "$d.expected"
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
  # Without the gstack pin, /ship would bump VERSION alone: the guard says so first.
  (cd "$d" && git checkout -q -- manifest.json) || return 1
  rm "$d/.gstack/package-json-path" || return 1
  (cd "$d" && bash scripts/check.d/omarchy-plugin.sh) >"$d.guard" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard" ".gstack/package-json-path must hold the line manifest.json" || return 1
  printf 'package.json\n' > "$d/.gstack/package-json-path"
  (cd "$d" && bash scripts/check.d/omarchy-plugin.sh) >"$d.guard" 2>&1; rc=$?
  (cd "$d" && git checkout -q -- .gstack/package-json-path) || return 1
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard" ".gstack/package-json-path must hold the line manifest.json" || return 1
  # Omarchy's validator failing fails the guard, with its reason.
  printf '#!/bin/sh\necho "omarchy-plugin-validate: rejected" >&2\nexit 1\n' > "$d.kit/bin/omarchy-plugin-validate"
  (cd "$d" && bash scripts/check.d/omarchy-plugin.sh) >"$d.guard" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard" "omarchy-plugin-validate: rejected"
}
test_stack_omarchy_plugin_guard_refuses_fixed_colours_and_sizes_in_qml() {
  # Regression test. DESIGN.md says "No hex colours or fixed pixel sizes in QML:
  # tokens only", but nothing enforced it: each of these passed the guard.
  command -v jq >/dev/null 2>&1 || { skip "jq not installed"; return; }
  command -v python3 >/dev/null 2>&1 || { skip "python3 not installed"; return; }
  local d="$WORK/omarchy-plugin-tokens/demo-app" rc lit want
  omarchy_plugin_project "$d" || return 1
  stub_omarchy_kit "$d" || return 1
  (cd "$d" && git add -A && git commit -qm init) || fail "commit failed" || return 1
  mkdir -p "$d/bar" || return 1
  while IFS='|' read -r lit want; do
    printf 'import QtQuick\n\nRectangle {\n  %s\n}\n' "$lit" > "$d/bar/Extra.qml"
    (cd "$d" && bash scripts/check.d/omarchy-plugin.sh) >"$d.guard" 2>&1; rc=$?
    assert_exit 1 "$rc" || { echo "    for: $lit"; return 1; }
    assert_contains "$d.guard" "bar/Extra.qml:4:" || return 1
    assert_contains "$d.guard" "$want" || return 1
  done <<'CASES'
color: "#ff0000"|fixed colours in QML
border.color: '#fff'|fixed colours in QML
color: "#80ff0000"|fixed colours in QML
color: Qt.rgba(1, 0, 0, 1)|fixed colours in QML
color: Qt.rgb(1, 0, 0)|fixed colours in QML
color: Qt.hsla(0.5, 1, 0.5, 1)|fixed colours in QML
color: Qt.hsva(0.5, 1, 1, 1)|fixed colours in QML
gradient: Gradient { GradientStop { position: 0; color: Color.accent } }|gradients in QML
LinearGradient {|gradients in QML
width: 24|fixed pixel sizes in QML
height: 2|fixed pixel sizes in QML
implicitWidth: 120;|fixed pixel sizes in QML
implicitHeight: 30 // the bar's|fixed pixel sizes in QML
font.pixelSize: 14|fixed pixel sizes in QML
font { pointSize: 10 }|fixed pixel sizes in QML
spacing: 4|fixed pixel sizes in QML
anchors.margins: 8|fixed pixel sizes in QML
anchors.leftMargin: -6|fixed pixel sizes in QML
Layout.topMargin: 12|fixed pixel sizes in QML
radius: 4|fixed pixel sizes in QML
CASES
  # Tokens pass, and so do 0 and 1, sizes worked out from tokens, a # in text,
  # and the tests' own QML.
  cat > "$d/bar/Extra.qml" <<'QML'
import QtQuick
import qs.Commons

Rectangle {
  width: Style.space(8)
  height: Style.bar.sizeHorizontal
  implicitWidth: 2 * Style.spacing.md
  spacing: Style.spacing.sm
  radius: 0
  border.width: 1
  anchors.margins: 0
  color: Color.accent
  Text { text: "#1 in the queue"; textFormat: Text.PlainText; font.pixelSize: Style.font.body }
}
QML
  printf 'import QtQuick\n\nRectangle { width: 24; color: "#ffffff" }\n' > "$d/tests/qml/Fixture.qml"
  (cd "$d" && bash scripts/check.d/omarchy-plugin.sh) >"$d.guard" 2>&1 \
    || fail "tokens failed the guard: $(cat "$d.guard")"
}
test_stack_omarchy_plugin_dev_link_links_rescans_and_enables() {
  command -v jq >/dev/null 2>&1 || { skip "jq not installed"; return; }
  local d="$WORK/omarchy-plugin-link/demo-app" home="$WORK/omarchy-plugin-link/home" rc
  omarchy_plugin_project "$d" || return 1
  mkdir -p "$d.bin" "$home" || return 1
  for tool in omarchy omarchy-shell; do
    # Omarchy lists the plugin only on the third query, like a rescan that
    # finishes in the background.
    cat > "$d.bin/$tool" <<STUB || return 1
#!/bin/sh
echo "$tool \$*" >> "$d.calls"
if [ "\$*" = "plugin list --json" ]; then
  n=\$((\$(cat "$d.lists" 2>/dev/null || echo 0) + 1)); echo "\$n" > "$d.lists"
  if [ "\$n" -ge 3 ]; then echo '[{"id": "demo_app"}]'; else echo '[]'; fi
fi
STUB
    chmod +x "$d.bin/$tool" || return 1
  done
  (cd "$d" && HOME="$home" PATH="$d.bin:$(printenv PATH)" ./scripts/dev-link.sh) >"$d.link" 2>&1 \
    || fail "dev-link exited $?: $(cat "$d.link")" || return 1
  [ -L "$home/.config/omarchy/plugins/demo_app" ] || fail "no link in the plugin folder" || return 1
  [ "$home/.config/omarchy/plugins/demo_app" -ef "$d" ] || fail "the link points elsewhere" || return 1
  # dev-link waits until Omarchy lists the plugin, and only then enables it.
  [ "$(cat "$d.calls")" = "$(printf '%s\n' 'omarchy-shell shell rescanPlugins' 'omarchy plugin list --json' \
      'omarchy plugin list --json' 'omarchy plugin list --json' 'omarchy plugin enable demo_app --section right')" ] \
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
  [ ! -s "$d.calls" ] || fail "--unlink called Omarchy: $(cat "$d.calls")" || return 1
  # A plugin Omarchy never lists is an error, never a blind enable.
  rmdir "$home/.config/omarchy/plugins/demo_app" && printf '%s\n' -1000 > "$d.lists" || return 1
  (cd "$d" && HOME="$home" PATH="$d.bin:$(printenv PATH)" ./scripts/dev-link.sh) >"$d.link" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.link" "doesn't list demo_app" || return 1
  assert_not_contains "$d.calls" "plugin enable"
}
test_stack_omarchy_plugin_tests_run_fails_closed() {
  # tests/run, the pack's only coverage gate, ran only in the heavy job on the
  # green starter: dropping its thresholds, the all-modules loader or an output
  # check kept every selftest green. A stub stands in for Qt 6's qmltestrunner.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/omarchy-plugin-run/demo-app" rc out want
  omarchy_plugin_project "$d" || return 1
  printf '#!/bin/sh\ncat "%s"\n' "$d.qml-out" > "$d.qmlrunner" && chmod +x "$d.qmlrunner" || return 1
  printf 'Config: Using QtTest library 6.4.2\nPASS   : Widget::test_x()\nTotals: 3 passed, 0 failed, 0 skipped\n' > "$d.qml-out"
  (cd "$d" && QML_TEST_RUNNER="$d.qmlrunner" ./tests/run) >"$d.run" 2>&1 \
    || fail "the starter failed tests/run: $(tail -20 "$d.run")" || return 1
  # An uncovered branch in Logic.js, then a module no test requires.
  cp "$d/Logic.js" "$d.Logic.js" || return 1
  printf '\nfunction spare(x) {\n  return x ? 1 : 2\n}\nmodule.exports.spare = spare\n' >> "$d/Logic.js"
  (cd "$d" && QML_TEST_RUNNER="$d.qmlrunner" ./tests/run) >"$d.run" 2>&1; rc=$?
  cp "$d.Logic.js" "$d/Logic.js" || return 1
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.run" "does not meet threshold of 100%" || return 1
  printf 'function hidden(x) {\n  return x ? 1 : 2\n}\nmodule.exports = { hidden: hidden }\n' > "$d/Extra.js"
  (cd "$d" && QML_TEST_RUNNER="$d.qmlrunner" ./tests/run) >"$d.run" 2>&1; rc=$?
  rm -f "$d/Extra.js"
  assert_exit 1 "$rc" || return 1
  # Regression test. Coverage measured only *.js and the loader found only *.js,
  # so an ECMAScript module QML imports (Extra.mjs) escaped the gate untested.
  mkdir -p "$d/logic" && printf 'export function hidden(x) {\n  return x ? 1 : 2\n}\n' > "$d/logic/Extra.mjs" || return 1
  (cd "$d" && QML_TEST_RUNNER="$d.qmlrunner" ./tests/run) >"$d.run" 2>&1; rc=$?
  rm -rf "$d/logic"
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.run" "Extra.mjs" || return 1
  assert_contains "$d.run" "does not meet threshold of 100%" || return 1
  # A failed QML run, one with no real test, and a Qt 5 runner each fail.
  while IFS='|' read -r out want; do
    printf '%b' "$out" > "$d.qml-out"
    (cd "$d" && QML_TEST_RUNNER="$d.qmlrunner" ./tests/run) >"$d.run" 2>&1; rc=$?
    assert_exit 1 "$rc" || { echo "    for: $out"; return 1; }
    assert_contains "$d.run" "$want" || return 1
  done <<'CASES'
Config: Using QtTest library 6.4.2\nPASS   : Widget::test_x()\nTotals: 2 passed, 1 failed, 0 skipped\n|QML tests failed
Config: Using QtTest library 6.4.2\nPASS   : Widget::initTestCase()\nTotals: 2 passed, 0 failed, 0 skipped\n|no QML tests ran
Config: Using QtTest library 5.15.2\nPASS   : Widget::test_x()\nTotals: 3 passed, 0 failed, 0 skipped\n|not a Qt 6 runner
CASES
}
test_stack_omarchy_plugin_kit_refuses_an_unpinned_ref() {
  # One pin drives every host check; a branch name would drift under CI.
  # A short or uppercase SHA never equals `git rev-parse HEAD`, so it would re-clone
  # on every check (and turn ambiguous): only a full lowercase SHA passes.
  local d="$WORK/omarchy-plugin-kit/demo-app" rc ref
  omarchy_plugin_project "$d" || return 1
  for ref in quattro c668141 C668141E9C42B13C80C9CA4EA108E11708C5E8A5; do
    printf '%s\n' "$ref" > "$d/.omarchy-ref"
    (cd "$d" && OMARCHY_KIT_DIR="$WORK/omarchy-plugin-kit/cache" ./scripts/omarchy-kit) >"$d.kit" 2>&1; rc=$?
    assert_exit 1 "$rc" || { echo "    for: $ref"; return 1; }
    assert_contains "$d.kit" "must be a full commit SHA" || return 1
  done
  assert_absent "$WORK/omarchy-plugin-kit/cache"
}
test_stack_omarchy_plugin_kit_never_deletes_a_published_checkout() {
  # Regression test. Two checks starting together on a cold cache both cloned,
  # then the second one's `rm -rf` deleted the checkout the first had already
  # handed to its guard, which lost Omarchy's validator mid-run. Stub git and rm
  # (no network) hold the two runs in that window; the first checkout must stay.
  local d="$WORK/omarchy-plugin-kit-race/demo-app" r="$WORK/omarchy-plugin-kit-race/run" ref kit pa pb rca rcb n ok
  omarchy_plugin_project "$d" || return 1
  ref="$(tr -d '[:space:]' < "$d/.omarchy-ref")"
  kit="$r/cache/$ref"
  mkdir -p "$r/bin" || return 1
  cat > "$r/bin/git" <<'STUB' || return 1
#!/bin/sh
# clone, sparse-checkout and checkout fake a checkout of $REF; rev-parse reads it.
# A run's second rev-parse waits until both runs have reached theirs.
dir=.
while :; do
  case "$1" in
    -C) dir="$2"; shift 2 ;;
    -c) shift 2 ;;
    *) break ;;
  esac
done
case "$1" in
  rev-parse)
    n=$(( $(cat "$PROBE_ROOT/$PROBE_ID.revparse" 2>/dev/null || echo 0) + 1 ))
    echo "$n" > "$PROBE_ROOT/$PROBE_ID.revparse"
    if [ "$n" = 2 ] && [ "${PROBE_BARRIER:-1}" = 1 ]; then
      : > "$PROBE_ROOT/$PROBE_ID.checked"
      i=0
      while { [ ! -e "$PROBE_ROOT/a.checked" ] || [ ! -e "$PROBE_ROOT/b.checked" ]; } && [ "$i" -lt 1000 ]; do
        sleep 0.01; i=$((i + 1))
      done
    fi
    [ -f "$dir/.head" ] && cat "$dir/.head" ;;
  clone)
    for dest; do :; done
    mkdir -p "$dest/bin" && echo "validator cloned by $PROBE_ID" > "$dest/bin/omarchy-plugin-validate" ;;
  checkout) printf '%s\n' "$REF" > "$dir/.head" ;;
  tag) [ "${PROBE_RELEASED:-1}" = 1 ] && echo v4.0.4 ;;
esac
STUB
  cat > "$r/bin/rm" <<'STUB' || return 1
#!/bin/sh
# Holds the second run's `rm -rf <cache entry>` until the first run has returned,
# then lets the test look before the second run goes on.
for last; do :; done
if [ "$PROBE_ID" = b ] && [ "$last" = "$KIT" ]; then
  i=0; while [ ! -e "$PROBE_ROOT/a.returned" ] && [ "$i" -lt 1000 ]; do sleep 0.01; i=$((i + 1)); done
  /bin/rm -rf "$last" && : > "$PROBE_ROOT/cache.deleted"
  i=0; while [ ! -e "$PROBE_ROOT/continue" ] && [ "$i" -lt 1000 ]; do sleep 0.01; i=$((i + 1)); done
  exit 0
fi
exec /bin/rm "$@"
STUB
  chmod +x "$r/bin/git" "$r/bin/rm" || return 1
  (cd "$d" && PATH="$r/bin:$(printenv PATH)" PROBE_ROOT="$r" PROBE_ID=a KIT="$kit" REF="$ref" \
    OMARCHY_KIT_DIR="$r/cache" bash scripts/omarchy-kit >"$r/a.out" 2>"$r/a.err") & pa=$!
  (cd "$d" && PATH="$r/bin:$(printenv PATH)" PROBE_ROOT="$r" PROBE_ID=b KIT="$kit" REF="$ref" \
    OMARCHY_KIT_DIR="$r/cache" bash scripts/omarchy-kit >"$r/b.out" 2>"$r/b.err") & pb=$!
  wait "$pa"; rca=$?
  : > "$r/a.returned"
  n=0
  while kill -0 "$pb" 2>/dev/null && [ ! -e "$r/cache.deleted" ] && [ "$n" -lt 1000 ]; do
    sleep 0.01; n=$((n + 1))
  done
  ok=1; [ -f "$kit/bin/omarchy-plugin-validate" ] || ok=0
  : > "$r/continue"
  wait "$pb"; rcb=$?
  assert_exit 0 "$rca" || { cat "$r/a.err"; return 1; }
  assert_exit 0 "$rcb" || { cat "$r/b.err"; return 1; }
  [ "$ok" = 1 ] || fail "the second run deleted the checkout the first had returned" || return 1
  { [ "$(cat "$r/a.out")" = "$kit" ] && [ "$(cat "$r/b.out")" = "$kit" ]; } \
    || fail "the runs printed: $(cat "$r/a.out" "$r/b.out")" || return 1
  # The losing clone is gone: nothing beside the cache entry, nothing inside it.
  [ "$(LC_ALL=C ls -A "$r/cache")" = "$ref" ] || fail "left in the cache: $(ls -A "$r/cache")" || return 1
  # shellcheck disable=SC2012  # the stub writes only .head and bin
  [ "$(LC_ALL=C ls -A "$kit" | tr '\n' ' ')" = ".head bin " ] || fail "left in the checkout: $(ls -A "$kit")" || return 1
  # Something at the cache path that isn't the pinned checkout is reported, never deleted.
  rm -rf "$r/cache" && mkdir -p "$kit" && : > "$kit/keep-me" || return 1
  (cd "$d" && PATH="$r/bin:$(printenv PATH)" PROBE_ROOT="$r" PROBE_ID=c PROBE_BARRIER=0 KIT="$kit" REF="$ref" \
    OMARCHY_KIT_DIR="$r/cache" bash scripts/omarchy-kit >"$r/c.out" 2>&1); rca=$?
  assert_exit 1 "$rca" || return 1
  assert_contains "$r/c.out" "is not Omarchy at $ref; delete it" || return 1
  [ "$(LC_ALL=C ls -A "$kit")" = keep-me ] || fail "the stale entry changed: $(ls -A "$kit")" || return 1
  [ "$(LC_ALL=C ls -A "$r/cache")" = "$ref" ] || fail "left in the cache: $(ls -A "$r/cache")" || return 1
  # Regression test. GitHub serves an unmerged pull request's commit by SHA too,
  # and the kit runs its validator and scanner on every check: a commit in no
  # Omarchy release (no v* tag contains it) is refused before checkout.
  rm -rf "$r/cache" || return 1
  (cd "$d" && PATH="$r/bin:$(printenv PATH)" PROBE_ROOT="$r" PROBE_ID=d PROBE_BARRIER=0 PROBE_RELEASED=0 KIT="$kit" \
    REF="$ref" OMARCHY_KIT_DIR="$r/cache" bash scripts/omarchy-kit >"$r/d.out" 2>&1); rca=$?
  assert_exit 1 "$rca" || return 1
  assert_contains "$r/d.out" "is in no Omarchy release" || return 1
  [ -z "$(ls -A "$r/cache" 2>/dev/null)" ] || fail "a refused commit left: $(ls -A "$r/cache")" || return 1
  # ...and so is one already in the cache (put there before this check existed).
  mkdir -p "$kit/bin" && printf '%s\n' "$ref" > "$kit/.head" || return 1
  (cd "$d" && PATH="$r/bin:$(printenv PATH)" PROBE_ROOT="$r" PROBE_ID=e PROBE_BARRIER=0 PROBE_RELEASED=0 KIT="$kit" \
    REF="$ref" OMARCHY_KIT_DIR="$r/cache" bash scripts/omarchy-kit >"$r/e.out" 2>&1); rca=$?
  assert_exit 1 "$rca" || return 1
  assert_contains "$r/e.out" "is in no Omarchy release"
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
  local d="$WORK/heavy-omarchy-plugin/demo-app" why kit fmt rc line
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
  assert_contains "$d.guard.out" "without textFormat" || return 1
  # Regression test. A QtQuick.Controls Label is a Text whose textFormat also
  # defaults to AutoText, but Omarchy's scanner reads only Text, so a Label
  # showing a setting passed. It must be plain text: no textFormat and a
  # RichText one both fail, Text.PlainText passes.
  for fmt in "" "textFormat: Text.RichText" "textFormat: Text.PlainText"; do
    (cd "$d" && git checkout -q HEAD -- Widget.qml) || return 1
    LABEL_FORMAT="$fmt" perl -0pi -e 's/  WidgetButton \{/  Label {\n    text: root.setting("label", "Pressed")\n    $ENV{LABEL_FORMAT}\n  }\n  WidgetButton {/' "$d/Widget.qml"
    line="$(grep -n '^    text: root\.setting("label", "Pressed")$' "$d/Widget.qml" | cut -d: -f1)"
    (cd "$d" && OMARCHY_KIT_DIR="$kit" bash scripts/check.d/omarchy-plugin.sh) >"$d.guard.out" 2>&1; rc=$?
    case "$fmt" in
      *PlainText) assert_exit 0 "$rc" || { tail -5 "$d.guard.out"; return 1; } ;;
      *) assert_exit 1 "$rc" || { echo "    for a Label with '${fmt:-no textFormat}'"; return 1; }
        assert_contains "$d.guard.out" "shell/Widget.qml:$line: text binding without textFormat" || return 1
        assert_contains "$d.guard.out" "give it textFormat: Text.PlainText" || return 1 ;;
    esac
  done
}

# --- tests: foldkit stack pack (plan 011) ---------------------------------------
foldkit_heavy_ready() {  # why the heavy foldkit tests can't run here; empty = run them
  if [ "${CI:-}" != "true" ] && [ "${SELFTEST_HEAVY:-}" != "1" ]; then
    echo "installs a real Foldkit project from the network: set SELFTEST_HEAVY=1 to run it here; CI runs it in the heavy job"
    return
  fi
  local tool
  for tool in node pnpm git; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool not installed"; return; }
  done
}
foldkit_files() {  # $1 = dir: the pack's files/, unbootstrapped, with the tokens filled
  mkdir -p "$1" || return 1
  (cd "$REPO/template/stacks/foldkit/files" && tar -cf - .) | tar -xf - -C "$1" || return 1
  printf '0.0.0\n' > "$1/VERSION"
  (cd "$1" && find . -type f -exec perl -pi -e 's/\{\{PROJECT_NAME\}\}/Demo App/g; s/\{\{PACKAGE_NAME\}\}/demo_app/g' {} +)
}
fk_node() {  # $1 = dir, rest = node args, run there -> "$1.node.out"
  local dir="$1"; shift
  (cd "$dir" && node "$@" >"$dir.node.out" 2>&1)
}
fk_json() {  # $1 = JSON file, $2 = a JS statement over `c` (the parsed file); rewrites it
  node -e 'const fs = require("fs"); const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); eval(process.argv[2]); fs.writeFileSync(process.argv[1], JSON.stringify(c, null, 2) + "\n")' "$1" "$2"
}
fk_rules() {  # $1 = dir from foldkit_files, stdin = probe cases calling check(); runs them there
  # The probe sits beside the project: check-rules reads every script inside it.
  { cat <<'HARNESS'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'

// A backslash, for escape sequences in fixture source.
const bs = String.fromCharCode(92)
const stash = `${process.cwd()}.stash`
// check(files, status, ...texts): write files (null removes a file or directory),
// run scripts/check-rules.mjs, expect its exit status and every text in its
// output, then put the project back.
const check = (files, status, ...texts) => {
  const undo = []
  for (const [path, content] of Object.entries(files)) {
    const saved = `${stash}/${undo.length}`
    mkdirSync(stash, { recursive: true })
    const existed = existsSync(path)
    if (existed) {
      renameSync(path, saved)
    }
    const created = content === null ? undefined : mkdirSync(dirname(path), { recursive: true })
    if (content !== null) {
      writeFileSync(path, content)
    }
    undo.push(() => {
      rmSync(created ?? path, { recursive: true, force: true })
      if (existed) {
        renameSync(saved, path)
      }
    })
  }
  try {
    const result = spawnSync(process.execPath, ['scripts/check-rules.mjs'], { encoding: 'utf8' })
    const out = result.stdout + result.stderr
    assert.equal(result.status, status, `${JSON.stringify(files)}:\n${out}`)
    for (const text of texts) {
      assert.ok(out.includes(text), `expected ${JSON.stringify(text)} after ${JSON.stringify(files)} in:\n${out}`)
    }
    assert.ok(!/^\s+at /m.test(out), `stack trace in: ${out}`)
  } finally {
    for (const step of undo.reverse()) {
      step()
    }
  }
}
const lineOf = (text, needle) => text.slice(0, text.indexOf(needle)).split('\n').length
HARNESS
    cat
    echo "console.log('check-rules probes passed')"
  } > "$1.rules.mjs" || return 1
  fk_node "$1" "$1.rules.mjs" || fail "check-rules probes failed: $(tail -25 "$1.node.out")" || return 1
  assert_contains "$1.node.out" "check-rules probes passed"
}
fk_installed() {  # $1 = dir from foldkit_files: node_modules as pnpm install leaves it, each dependency at its pin
  fk_node "$1" -e '
    const fs = require("fs")
    const p = JSON.parse(fs.readFileSync("package.json", "utf8"))
    const deps = { ...p.dependencies, ...p.devDependencies }
    for (const [name, version] of Object.entries(deps)) {
      const peerDependencies = name === "foldkit" ? { effect: deps.effect, "@effect/platform-browser": deps["@effect/platform-browser"] } : {}
      fs.mkdirSync("node_modules/" + name, { recursive: true })
      fs.writeFileSync("node_modules/" + name + "/package.json", JSON.stringify({ name, version, peerDependencies }) + "\n")
    }'
}
fk_stub_pnpm() {  # $1 = bin dir: a pnpm for the guard's light tests
  mkdir -p "$1" && cat > "$1/pnpm" <<'STUB' && chmod +x "$1/pnpm"
#!/bin/sh
# Logs each call to $FK_PNPM_LOG, runs $FK_PNPM_INSTALL for `pnpm install`, says
# tsc is patched, and passes every other command.
[ -z "${FK_PNPM_LOG:-}" ] || echo "$*" >> "$FK_PNPM_LOG"
case "$1 $2 $3" in
  install*) eval "${FK_PNPM_INSTALL:-:}" ;;
  "exec tsc --version") echo 'Version 7.0.2+effect-tsgo' ;;
esac
STUB
}
fk_guard() {  # $1 = dir, rest = env assignments: the guard there, the stub pnpm from "$1.bin" first -> "$1.guard.out"
  local dir="$1"; shift
  (cd "$dir" && env PATH="$dir.bin:$(printenv PATH)" "$@" bash scripts/check.d/foldkit.sh) >"$dir.guard.out" 2>&1
}
# pnpm's supply-chain settings, read from the environment as pnpm_config_<name>
# and PNPM_CONFIG_<NAME>: the guard and after-bootstrap clear every one first.
FK_POLICY_SETTINGS="minimum_release_age minimum_release_age_exclude minimum_release_age_strict
  minimum_release_age_ignore_missing_time trust_lockfile trust_policy trust_policy_exclude
  trust_policy_ignore_after strict_dep_builds block_exotic_subdeps allow_builds dangerously_allow_all_builds"
fk_policy_kept() {  # $1 = an `env` dump: fails if it holds any of those settings
  ! grep -iE '^pnpm_config_(minimum_release_age|trust_|strict_dep_builds|block_exotic_subdeps|allow_builds|dangerously)' "$1" \
    || fail "pnpm ran with a supply-chain setting from the environment"
}
foldkit_project() {  # $1 = dir, $2 = project name: a fresh copy bootstrapped with the foldkit pack
  fresh_copy "$1" || return 1
  (cd "$1" && HOME="$WORK/home" stack_env ./bootstrap --name "$2" --stack foldkit --yes </dev/null >"$1.out" 2>&1) \
    || fail "bootstrap exited $?: $(tail -20 "$1.out")"
}
test_stack_foldkit_rejects_unusable_names_before_mutation() {
  # A project named like a direct dependency breaks its own install or type check
  # (named `effect`, the Effect language service reports a duplicate package on
  # every file), and past 50 characters Oxfmt wraps src/build-info.ts.
  local d name want before rc n=0
  while IFS='|' read -r name want; do
    n=$((n + 1))
    d="$WORK/stack-foldkit-names-$n/proj"
    fresh_copy "$d" || return 1
    before="$(tree_fingerprint "$d")"
    run_bootstrap "$d" --name "$name" --stack foldkit --yes; rc=$?
    assert_exit 2 "$rc" || return 1
    assert_contains "$d.out" "$want" || return 1
    [ "$before" = "$(tree_fingerprint "$d")" ] || fail "rejecting '$name' changed files" || return 1
  done <<'NAMES'
Effect|taken by a package the foldkit pack depends on
foldkit|taken by a package the foldkit pack depends on
VITE|taken by a package the foldkit pack depends on
vitest|taken by a package the foldkit pack depends on
TypeScript|taken by a package the foldkit pack depends on
oxlint|taken by a package the foldkit pack depends on
oxfmt|taken by a package the foldkit pack depends on
playwright|taken by a package the foldkit pack depends on
node_modules|reserved by Node.js
Acme Example Inventory Reconciliation Service Ok123|too long for the foldkit stack pack
NAMES
}
test_stack_foldkit_coverage_tiers_fail_closed() {
  # scripts/coverage-tiers.mjs is the only coverage enforcement (Vitest passes a
  # tier glob that matches nothing): every schema rule, every counter check and
  # every floor must fail closed, and --report prints only the snapshot table.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-tiers/demo" rc
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --validate; rc=$?
  assert_exit 0 "$rc" || { cat "$d.node.out"; return 1; }
  assert_contains "$d.node.out" "coverage-tiers: ok" || return 1
  cat > "$d/probe.mjs" <<'PROBE'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { mkdirSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import * as tiers from './scripts/coverage-tiers.mjs'

const root = realpathSync('.')
const config = JSON.parse(readFileSync('coverage-tiers.json', 'utf8'))
const members = Object.values(config.tiers).flatMap(tier => tier.include)
const metric = (total, covered = total) => ({ total, covered, skipped: 0, pct: 0 })
const entry = (lines = 10, lineHits = lines, branches = 2, branchHits = branches, fns = 2, fnHits = fns) =>
  ({ lines: metric(lines, lineHits), statements: metric(lines, lineHits), branches: metric(branches, branchHits), functions: metric(fns, fnHits) })
const summary = (overrides = {}, extra = {}) => {
  const files = {}
  for (const path of members) {
    if (overrides[path] !== null) files[join(root, path)] = overrides[path] ?? entry()
  }
  for (const [path, value] of Object.entries(extra)) files[path.startsWith('/') ? path : join(root, path)] = value
  const total = {}
  for (const name of ['lines', 'statements', 'branches', 'functions']) {
    const sum = field => Object.values(files).reduce((acc, file) => acc + file[name][field], 0)
    total[name] = metric(sum('total'), sum('covered'))
  }
  return { total, ...files }
}
const cli = (...args) => spawnSync(process.execPath, ['scripts/coverage-tiers.mjs', ...args], { encoding: 'utf8' })
const run = (data, expected, text = '', args = ['--check']) => {
  mkdirSync('coverage', { recursive: true })
  writeFileSync('coverage/coverage-summary.json', typeof data === 'string' ? data : JSON.stringify(data))
  const result = cli(...args)
  const out = result.stdout + result.stderr
  assert.equal(result.status, expected, out)
  assert.ok(out.includes(text), `expected ${JSON.stringify(text)} in: ${out}`)
  assert.ok(!/^\s+at /m.test(out), `stack trace in: ${out}`)
  return result
}

// Passing, then each floor independently: global lines and branches (90%, inclusive),
// and each tier's lines, branches and functions.
run(summary(), 0, 'coverage-tiers: ok')
const atFloor = summary({}, { 'src/extra.ts': entry(40, 30, 8, 6, 2, 0) })
run(atFloor, 0, 'coverage-tiers: ok')
run(summary({}, { 'src/extra.ts': entry(40, 29, 8, 8) }), 1, 'global: lines 89.00% is below its minimum 90% (below the floor: src/extra.ts 72.50%)')
run(summary({}, { 'src/extra.ts': entry(40, 40, 8, 5) }), 1, 'global: branches 85.00% is below its minimum 90%')
const big = { 'src/extra.ts': entry(1000, 1000, 100, 100) }
run(summary({ 'src/main.ts': entry(10, 9) }, big), 1, 'pure_logic: lines 95.00% is below its minimum 100%')
run(summary({ 'src/api/status.ts': entry(10, 10, 2, 1) }, big), 1, 'api_surface: branches 75.00% is below its minimum 100%')
run(summary({ 'src/view.ts': entry(10, 10, 2, 2, 10, 5) }, big), 1, 'main_components: functions 58.33% is below its minimum 90%')
run(summary({ 'src/view.ts': entry(10, 10, 0, 0, 1, 1), 'src/components/status.ts': entry(10, 10, 0, 0, 1, 1) }), 0, 'coverage-tiers: ok')
// Membership: a member missing from the report, or with nothing measurable, fails.
run(summary({ 'src/command.ts': null }), 1, 'api_surface: src/command.ts is not in the coverage report')
run(summary({ 'src/view.ts': entry(0, 0, 0, 0, 0, 0) }), 1, 'main_components: src/view.ts has no measurable lines')
// Malformed reports fail, for --check and --report alike.
const mutations = [
  data => { delete data[join(root, 'src/main.ts')].lines },
  data => { data[join(root, 'src/main.ts')].lines.covered = -1 },
  data => { data[join(root, 'src/main.ts')].branches.total = 1.5 },
  data => { data[join(root, 'src/main.ts')].functions.covered = 3 },
  data => { data[join(root, 'src/main.ts')] = 'x' },
  data => { data[join(root, 'src/main.ts')].lines.total = '10' },
  data => { delete data.total },
  data => { data.total.lines.covered -= 1 },
]
for (const mutate of mutations) {
  const data = summary()
  mutate(data)
  run(data, 1, 'coverage-tiers: FAIL')
  run(data, 1, 'coverage-tiers: FAIL', ['--report'])
}
run((() => { const data = summary(); data.total.branches.total += 1; data.total.branches.covered += 1; return data })(), 1, 'global: counters disagree with per-file sums')
run(summary({}, { '/elsewhere/src/x.ts': entry() }), 1, 'coverage summary names a file outside the project: /elsewhere/src/x.ts')
run({ total: summary().total }, 1, 'coverage summary has no per-file entries')
run(summary(Object.fromEntries(members.map(path => [path, entry(0, 0, 0, 0, 0, 0)]))), 1, 'global: no measurable lines')
run([], 1, 'coverage summary must be an object')
run('{', 1, 'coverage-tiers: FAIL cannot load valid configuration/report')
rmSync('coverage', { recursive: true, force: true })
let result = cli('--check')
assert.ok(result.status === 1 && result.stderr.includes('cannot load valid configuration/report'), result.stderr)

// --report: the table alone, with n/a for an explicitly empty tier and for a
// metric with nothing to measure. --input reads another file.
const original = readFileSync('coverage-tiers.json', 'utf8')
try {
  const withEmpty = JSON.parse(original)
  withEmpty.tiers.later = { title: 'Later', minimum: 0, target: 100, include: [], allow_empty: true }
  writeFileSync('coverage-tiers.json', JSON.stringify(withEmpty))
  const branchless = summary({ 'src/view.ts': entry(10, 10, 0, 0), 'src/components/status.ts': entry(10, 10, 0, 0) }, { 'src/extra.ts': entry(40, 30, 8, 6, 2, 0) })
  result = run(branchless, 0, '', ['--report'])
  assert.equal(result.stdout, [
    '| Tier | Lines | Branches | Functions | Minimum | Target |',
    '|---|---|---|---|---|---|',
    '| Global (lines and branches) | 90.00% | 87.50% | 85.71% | 90% | 100% |',
    '| Pure logic & utilities | 100.00% | 100.00% | 100.00% | 100% | 100% |',
    '| API / contract surface | 100.00% | 100.00% | 100.00% | 100% | 100% |',
    '| Main UI components | 100.00% | n/a (nothing to measure) | 100.00% | 90% | 90% |',
    '| Later | n/a (explicitly empty) | n/a (explicitly empty) | n/a (explicitly empty) | 0% | 100% |',
    '',
  ].join('\n'))
} finally {
  writeFileSync('coverage-tiers.json', original)
}
writeFileSync('alt.json', JSON.stringify(summary()))
run('{}', 0, 'coverage-tiers: ok', ['--check', '--input', 'alt.json'])
run('{}', 0, 'coverage-tiers: ok', ['--check', '--input=alt.json'])

// Usage errors exit 2.
for (const args of [[], ['--check', '--report'], ['--bogus'], ['--ratchet', ''], ['--ratchet'], ['--input'], ['--check=1']]) {
  result = cli(...args)
  assert.equal(result.status, 2, `${JSON.stringify(args)}: ${result.stdout}${result.stderr}`)
}

// Config validation: every rule names what it rejects.
const rejected = (text, mutate) => {
  const bad = structuredClone(config)
  mutate(bad)
  const errors = tiers.validate(bad)
  assert.ok(errors.some(error => error.includes(text)), `${text}: ${JSON.stringify(errors)}`)
}
assert.deepEqual(tiers.validate(config), [])
assert.ok(tiers.validate(null).some(error => error.includes('must be an object')))
rejected('unknown top-level keys: ["tier"]', c => { c.tier = {} })
rejected('tiers must be a nonempty object', c => { c.tiers = {} })
rejected('tiers must be a nonempty object', c => { c.tiers = [] })
rejected('global is reserved', c => { c.tiers.global = { title: 'G', minimum: 0, target: 0, include: [], allow_empty: true } })
rejected('later: tier must be an object', c => { c.tiers.later = [] })
rejected('unknown tier keys: ["minimun"]', c => { c.tiers.api_surface.minimun = 100 })
for (const value of [true, Number.NaN, Number.POSITIVE_INFINITY, '100', null]) {
  rejected('minimum and target must be finite numbers', c => { c.tiers.api_surface.minimum = value })
}
rejected('need 0 <= minimum <= target <= 100', c => { c.tiers.api_surface.target = 99 })
rejected('need 0 <= minimum <= target <= 100', c => { c.tiers.pure_logic.target = 101 })
rejected('need 0 <= minimum <= target <= 100', c => { c.tiers.main_components.minimum = -1 })
rejected('title must be a nonempty string', c => { c.tiers.api_surface.title = '  ' })
rejected('title must be a nonempty string', c => { c.tiers.api_surface.title = 1 })
rejected('allow_empty must be boolean', c => { c.tiers.api_surface.allow_empty = 'true' })
rejected('retired must be an array', c => { c.tiers.api_surface.retired = 'src/old.ts' })
rejected('retired must name canonical', c => { c.tiers.api_surface.retired = ['tests/old.ts'] })
rejected('is listed twice across include and retired', c => { c.tiers.api_surface.retired = ['src/old.ts', 'src/old.ts'] })
rejected('is listed twice across include and retired', c => { c.tiers.api_surface.retired = ['src/command.ts'] })
rejected('include must be an explicit array', c => { c.tiers.api_surface.include = 'src/command.ts' })
rejected('empty include requires allow_empty', c => { c.tiers.api_surface.include = [] })
for (const path of ['src/main.js', 'src\\main.ts', 'src//main.ts', 'src/./main.ts', 'src/../src/main.ts', '/tmp/main.ts', 'tests/main.ts', 'src/story.test.ts', 'src/vite-env.d.ts', 7]) {
  rejected('include must name canonical', c => { c.tiers.api_surface.include = [path] })
}
rejected('include "src/missing.ts" is not a file within the project', c => { c.tiers.api_surface.include = ['src/missing.ts'] })
writeFileSync(join(root, '..', 'outside.ts'), 'export const x = 1\n')
symlinkSync(join(root, '..', 'outside.ts'), 'src/escape.ts')
try {
  rejected('include "src/escape.ts" is not a file within the project', c => { c.tiers.api_surface.include = ['src/escape.ts'] })
} finally {
  rmSync('src/escape.ts')
}
rejected('src/main.ts: duplicate membership in "pure_logic" and "api_surface"', c => { c.tiers.api_surface.include.push('src/main.ts') })
rejected('journeys must be a nonempty array', c => { delete c.journeys })
rejected('journeys must be a nonempty array', c => { c.journeys = [] })
rejected('journeys: each must be a nonempty string', c => { c.journeys = [1] })
rejected('is listed twice', c => { c.journeys = [c.journeys[0], c.journeys[0]] })
rejected('journeys: no test("a journey nobody wrote") in e2e/', c => { c.journeys.push('a journey nobody wrote') })
// Journey titles come from plain test('...') calls, quoted either way; a skipped test is not a journey.
writeFileSync('e2e/more.spec.ts', "import { test } from '@playwright/test'\n\ntest(\"it's double-quoted\", async () => {})\ntest('say \\'hi\\'', async () => {})\ntest.skip('skipped journey', async () => {})\n")
try {
  assert.deepEqual(tiers.validate({ ...config, journeys: [...config.journeys, "it's double-quoted", "say 'hi'"] }), [])
  rejected('no test("skipped journey")', c => { c.journeys.push('skipped journey') })
} finally {
  rmSync('e2e/more.spec.ts')
}
// Regression test. The scan read raw source, so a commented-out test still
// counted as a journey. Comments are stripped; a // or /* inside a string,
// template or regex literal is not a comment, and what follows it still counts.
writeFileSync('e2e/comments.test.ts', [
  "import { expect, test } from '@playwright/test'",
  "// test('line comment journey', async () => {})",
  "/* test('block comment journey', async () => {})",
  "   test('second line of the block', async () => {}) */",
  "const url = 'http://example.invalid/*'; test('after a string', async () => {})",
  "const path = `//${url}/*`; test('after a template', async () => {})",
  "test('after a regex', async () => { expect('//').toMatch(/\\/\\/|'|`|\\/\\*/) }); test('second on the line', async () => {})",
  "test('trailing comment', async () => {}) // test('in the trailing comment', async () => {})",
  '',
].join('\n'))
try {
  const kept = ['after a string', 'after a template', 'after a regex', 'second on the line', 'trailing comment']
  assert.deepEqual(tiers.validate({ ...config, journeys: [...config.journeys, ...kept] }), [])
  for (const title of ['line comment journey', 'block comment journey', 'second line of the block', 'in the trailing comment']) {
    rejected(`no test(${JSON.stringify(title)}) in e2e/`, c => { c.journeys.push(title) })
  }
} finally {
  rmSync('e2e/comments.test.ts')
}
// retired_journeys: titles, each once, never also a journey (its test-file rule
// is tested with the ratchet).
rejected('retired_journeys must be an array of journey titles', c => { c.retired_journeys = 'old' })
rejected('retired_journeys: each must be a nonempty string', c => { c.retired_journeys = [' '] })
rejected('retired_journeys: each must be a nonempty string', c => { c.retired_journeys = [7] })
rejected('"old" is listed twice across journeys and retired_journeys', c => { c.retired_journeys = ['old', 'old'] })
rejected('is listed twice across journeys and retired_journeys', c => { c.retired_journeys = [c.journeys[0]] })
assert.deepEqual(tiers.validate({ ...config, retired_journeys: ['a journey since deleted'] }), [])
writeFileSync('coverage-tiers.json', original.replace('"minimum": 90', '"minimum": 91'))
result = cli('--validate')
assert.ok(result.status === 1 && result.stderr.includes('main_components: need 0 <= minimum <= target <= 100'), result.stderr)
writeFileSync('coverage-tiers.json', original)
console.log('coverage-tiers probes passed')
PROBE
  fk_node "$d" probe.mjs || fail "coverage-tiers probes failed: $(tail -25 "$d.node.out")" || return 1
  assert_contains "$d.node.out" "coverage-tiers probes passed"
}
test_stack_foldkit_coverage_tiers_ratchet() {
  # CI's ratchet compares coverage-tiers.json with the base branch: floors and
  # targets never drop, tiers never disappear, and a member leaves only through
  # `retired`. A base that predates the file passes; an unreadable one fails.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-ratchet/demo" rc
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  (cd "$d" && git init -q && git add -A && git commit -qm init \
    && git branch -f prepack "$(git commit-tree -m base "$(printf '100644 blob %s\tREADME.md\n' "$(git hash-object -w package.json)" | git mktree)")") \
    || fail "git setup failed" || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 0 "$rc" || { cat "$d.node.out"; return 1; }
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet prepack; rc=$?
  assert_exit 0 "$rc" || return 1
  assert_contains "$d.node.out" "no coverage-tiers.json at prepack; nothing to ratchet against" || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet no-such-ref; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "cannot read coverage-tiers.json at no-such-ref: unknown revision" || return 1
  fk_node "$d" scripts/coverage-tiers.mjs "--ratchet=--output=$d.leak"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "unknown revision" || return 1
  assert_absent "$d.leak" || return 1
  cp "$d/coverage-tiers.json" "$d.tiers.json" || return 1
  # Lowered minimum, lowered target, removed tier, removed member: each fails.
  fk_json "$d/coverage-tiers.json" 'c.tiers.api_surface.minimum = 90' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "api_surface: minimum lowered from 100 to 90" || return 1
  cp "$d.tiers.json" "$d/coverage-tiers.json" && fk_json "$d/coverage-tiers.json" 'c.tiers.main_components.target = 95; c.tiers.main_components.minimum = 95' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 0 "$rc" || { cat "$d.node.out"; return 1; }
  cp "$d.tiers.json" "$d/coverage-tiers.json" && fk_json "$d/coverage-tiers.json" 'c.tiers.pure_logic.target = 99; c.tiers.pure_logic.minimum = 99' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "pure_logic: target lowered from 100 to 99" || return 1
  cp "$d.tiers.json" "$d/coverage-tiers.json" && fk_json "$d/coverage-tiers.json" 'delete c.tiers.main_components' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "main_components: tier removed since HEAD" || return 1
  cp "$d.tiers.json" "$d/coverage-tiers.json" && fk_json "$d/coverage-tiers.json" 'c.tiers.api_surface.include = ["src/api/status.ts"]' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" 'api_surface: existing members removed since HEAD: ["src/command.ts"]' || return 1
  assert_contains "$d.node.out" "list its old path in the tier's retired" || return 1
  # An explicitly empty tier must not bypass membership either.
  cp "$d.tiers.json" "$d/coverage-tiers.json" && fk_json "$d/coverage-tiers.json" 'c.tiers.api_surface.include = []; c.tiers.api_surface.allow_empty = true' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "existing members removed since HEAD" || return 1
  # A reviewed move: the old path goes to `retired`.
  cp "$d.tiers.json" "$d/coverage-tiers.json" || return 1
  (cd "$d" && git mv src/command.ts src/commands.ts) || return 1
  fk_json "$d/coverage-tiers.json" 'c.tiers.api_surface.include = ["src/api/status.ts", "src/commands.ts"]; c.tiers.api_surface.retired = ["src/command.ts"]' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 0 "$rc" || { cat "$d.node.out"; return 1; }
  (cd "$d" && git mv src/commands.ts src/command.ts) && cp "$d.tiers.json" "$d/coverage-tiers.json" || return 1
  # Regression test. Retiring a member whose file still exists is not a move: it
  # dropped a live module out of its tier's floor while validation and the
  # ratchet stayed green.
  fk_json "$d/coverage-tiers.json" 'c.tiers.api_surface.include = ["src/api/status.ts"]; c.tiers.api_surface.retired = ["src/command.ts"]' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" 'api_surface: retired "src/command.ts" still exists' || return 1
  cp "$d.tiers.json" "$d/coverage-tiers.json" || return 1
  # Regression test. The ratchet compared tiers only: a journey dropped from
  # coverage-tiers.json left the gate unnoticed. It leaves only through
  # retired_journeys, once no test in e2e/ declares its title, skipped or not.
  local journey spec_form
  journey="$(node -p 'require(process.argv[1]).journeys[0]' "$d/coverage-tiers.json")" || return 1
  cp "$d/e2e/home.spec.ts" "$d.home.spec.ts" || return 1
  OLD="$journey" perl -pi -e 's/\Q$ENV{OLD}\E/renamed journey/' "$d/e2e/home.spec.ts" || return 1
  OLD="$journey" fk_json "$d/coverage-tiers.json" 'c.journeys[c.journeys.indexOf(process.env.OLD)] = "renamed journey"' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "journeys removed since HEAD: [\"$journey\"] (to rename or delete one, list its old title in retired_journeys)" || return 1
  # A reviewed rename: the old title goes to retired_journeys.
  OLD="$journey" fk_json "$d/coverage-tiers.json" 'c.retired_journeys = [process.env.OLD]' || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
  assert_exit 0 "$rc" || { cat "$d.node.out"; return 1; }
  # A retired title still declared as a test, in any form, is not retired; a
  # commented-out one is gone.
  while IFS= read -r spec_form; do
    OLD="$journey" node -e 'require("fs").writeFileSync(process.argv[1], "import { test } from \"@playwright/test\"\n\n" + process.argv[2].replaceAll("TITLE", JSON.stringify(process.env.OLD)) + "\n")' \
      "$d/e2e/old.spec.ts" "$spec_form" || return 1
    fk_node "$d" scripts/coverage-tiers.mjs --ratchet HEAD; rc=$?
    case "$spec_form" in
      //*) assert_exit 0 "$rc" || { cat "$d.node.out"; return 1; } ;;
      *) assert_exit 1 "$rc" || { echo "    retired while declared: $spec_form"; return 1; }
        assert_contains "$d.node.out" "retired_journeys: \"$journey\" is still a test in e2e/ (skipped or not)" || return 1 ;;
    esac
  done <<'FORMS'
test(TITLE, async () => {})
test.skip(TITLE, async () => {})
test.fixme(TITLE, async () => {})
test.describe.skip('group', () => { test(TITLE, async () => {}) })
test.fail.only(TITLE, async () => {})
// test(TITLE, async () => {})
FORMS
  rm -f "$d/e2e/old.spec.ts" && cp "$d.home.spec.ts" "$d/e2e/home.spec.ts" && cp "$d.tiers.json" "$d/coverage-tiers.json" || return 1
  # Bases whose file is malformed, invalid, or unreadable fail (only a confirmed absence passes).
  base_with() {  # $1 = branch, $2 = coverage-tiers.json content
    (cd "$d" && git branch -f "$1" "$(git commit-tree -m "$1" "$(printf '100644 blob %s\tcoverage-tiers.json\n' \
      "$(printf '%s' "$2" | git hash-object -w --stdin)" | git mktree)")")
  }
  base_with notjson '{' || fail "git setup failed" || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet notjson; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "base config: coverage-tiers.json at notjson is not valid JSON" || return 1
  base_with invalid '{"tiers": {}, "journeys": []}' || fail "git setup failed" || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet invalid; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "base config: tiers must be a nonempty object" || return 1
  (cd "$d" && tree="$(git rev-parse 'invalid^{tree}')" \
    && rm -f ".git/objects/$(printf '%s' "$tree" | cut -c1-2)/$(printf '%s' "$tree" | cut -c3-)") \
    || fail "removing the base tree failed" || return 1
  fk_node "$d" scripts/coverage-tiers.mjs --ratchet invalid; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.node.out" "cannot read coverage-tiers.json at invalid"
}
test_stack_foldkit_journeys_must_run_and_pass() {
  # Regression test. A journey counted once its title appeared in e2e/ source, so
  # one inside test.describe.skip, or one calling test.skip() at runtime, kept
  # the gate green without running. --journeys reads Playwright's JSON report:
  # every attempt of every test with a journey's title must have passed, in
  # every project and repeat. Hand-written reports in the format of
  # @playwright/test's reporters/json stand in for real runs.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-journeys/demo"
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  cat > "$d/probe.mjs" <<'PROBE'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'

const journeys = JSON.parse(readFileSync('coverage-tiers.json', 'utf8')).journeys
const [journey] = journeys
const name = JSON.stringify(journey)
const attempt = (status, retry) => ({ workerIndex: 0, parallelIndex: 0, status, duration: 5, errors: [], stdout: [], stderr: [], retry, startTime: '2026-10-13T00:00:00.000Z', attachments: [], annotations: [] })
const test = (statuses = ['passed'], project = 'chromium', expectedStatus = 'passed') =>
  ({ timeout: 30000, annotations: [], expectedStatus, projectId: project, projectName: project, results: statuses.map(attempt), status: 'expected' })
const spec = (title, tests = [test()], line = 5) => ({ title, ok: true, tags: [], tests, id: `${title}-${line}`, file: 'home.spec.ts', line, column: 1 })
// A passing run of every journey, with `specs` (the first journey's) swapped in.
const report = ({ specs = [spec(journey)], errors = [], nested = [] } = {}) => ({
  config: { rootDir: '/project/e2e' },
  suites: [{ title: 'home.spec.ts', file: 'home.spec.ts', line: 0, column: 0, specs: [...specs, ...journeys.slice(1).map((title, index) => spec(title, [test()], 20 + index))], suites: nested.length > 0 ? nested : undefined }],
  errors,
  stats: { startTime: '2026-10-13T00:00:00.000Z', duration: 9, expected: 1, skipped: 0, unexpected: 0, flaky: 0 },
})
const run = (data, expected, text, args = ['--journeys']) => {
  mkdirSync('test-results', { recursive: true })
  writeFileSync('test-results/journeys.json', typeof data === 'string' ? data : JSON.stringify(data))
  const result = spawnSync(process.execPath, ['scripts/coverage-tiers.mjs', ...args], { encoding: 'utf8' })
  const out = result.stdout + result.stderr
  assert.equal(result.status, expected, out)
  assert.ok(out.includes(text), `expected ${JSON.stringify(text)} in: ${out}`)
  assert.ok(!/^\s+at /m.test(out), `stack trace in: ${out}`)
}

// Passed, in one project or several, and once per --repeat-each copy.
run(report(), 0, `coverage-tiers: journey ${name} passed`)
run(report({ specs: [spec(journey, [test(['passed'], 'chromium'), test(['passed'], 'firefox')])] }), 0, 'coverage-tiers: ok')
run(report({ specs: [spec(journey), spec(journey)] }), 0, 'coverage-tiers: ok')
// Every attempt counts, in every project and every copy.
run(report({ specs: [spec(journey, [test(['skipped'])])] }), 1, `journey ${name} did not pass in project "chromium": skipped`)
run(report({ specs: [spec(journey, [test(['failed'])])] }), 1, `journey ${name} did not pass in project "chromium": failed`)
run(report({ specs: [spec(journey, [test(['failed', 'failed'])])] }), 1, 'did not pass in project "chromium": failed, then failed')
run(report({ specs: [spec(journey, [test(['failed', 'passed'])])] }), 1, 'failed, then passed (flaky: a journey must pass on every attempt')
run(report({ specs: [spec(journey, [test(['timedOut'])])] }), 1, `journey ${name} did not pass in project "chromium": timedOut`)
run(report({ specs: [spec(journey, [test(['interrupted'])])] }), 1, `journey ${name} did not pass in project "chromium": interrupted`)
run(report({ specs: [spec(journey, [test(['passed'], 'chromium'), test(['failed'], 'firefox')])] }), 1, `journey ${name} did not pass in project "firefox": failed`)
run(report({ specs: [spec(journey), spec(journey, [test(['skipped'])])] }), 1, 'did not pass in project "chromium": skipped')
run(report({ specs: [spec(journey, [test([]), test(['passed'], 'firefox')])] }), 1, `journey ${name} did not run in project "chromium" (no results)`)
run(report({ specs: [spec(journey, [test(['passed'], 'chromium', 'failed')])] }), 1, `journey ${name} is expected to end "failed"`)
// Missing: renamed, filtered out by --grep, or never declared.
run(report({ specs: [spec('another test')] }), 1, `journey ${name} has no results in the Playwright report`)
// The same title declared twice in one project: in two places, or two describes.
run(report({ specs: [spec(journey, [test()], 5), spec(journey, [test()], 9)] }), 1, `journey ${name} is declared 2 times in project "chromium": home.spec.ts:5:1; home.spec.ts:9:1`)
const describe = title => ({ title, file: 'home.spec.ts', line: 3, column: 1, specs: [spec(journey)] })
run(report({ specs: [], nested: [describe('first'), describe('second')] }), 1, `journey ${name} is declared 2 times in project "chromium": home.spec.ts:5:1 (home.spec.ts › first); home.spec.ts:5:1 (home.spec.ts › second)`)
// A report that is not a complete run fails whatever it says about journeys.
run(report({ errors: [{ message: 'Error: http://localhost:4000 is already used\n  more detail' }] }), 1, 'the Playwright run reported errors: Error: http://localhost:4000 is already used')
run({ ...report(), suites: [] }, 1, 'the Playwright report has no suites: no test ran')
run({ ...report(), suites: [{ title: 'home.spec.ts', file: 'home.spec.ts', line: 0, column: 0, specs: journeys.map(title => spec(title, [test([])])) }] }, 1, 'the Playwright report has no test results: no test ran')
run({ ...report(), errors: undefined }, 1, 'is it a Playwright JSON report?')
run({ ...report(), suites: [{ title: 'home.spec.ts' }] }, 1, 'the Playwright report is malformed')
run([], 1, 'the Playwright report must be a JSON object')
run('{', 1, 'coverage-tiers: FAIL cannot load valid configuration/report')
rmSync('test-results', { recursive: true, force: true })
let result = spawnSync(process.execPath, ['scripts/coverage-tiers.mjs', '--journeys'], { encoding: 'utf8' })
assert.ok(result.status === 1 && result.stderr.includes('no Playwright report at test-results/journeys.json: run pnpm exec playwright test first'), result.stderr)
// --input reads another report; --journeys takes no value of its own.
writeFileSync('other.json', JSON.stringify(report()))
run('{', 0, 'coverage-tiers: ok', ['--journeys', '--input', 'other.json'])
run('{', 0, 'coverage-tiers: ok', ['--journeys', '--input=other.json'])
for (const args of [['--journeys=yes'], ['--journeys', '--check']]) {
  result = spawnSync(process.execPath, ['scripts/coverage-tiers.mjs', ...args], { encoding: 'utf8' })
  assert.equal(result.status, 2, `${JSON.stringify(args)}: ${result.stdout}${result.stderr}`)
}
console.log('journeys probes passed')
PROBE
  fk_node "$d" probe.mjs || fail "journeys probes failed: $(tail -25 "$d.node.out")" || return 1
  assert_contains "$d.node.out" "journeys probes passed"
}
test_stack_foldkit_pin_guard_fails_closed() {
  # scripts/check-pins.mjs keeps package.json in gstack's byte form and in step with
  # VERSION, every dependency exact and installed at its pin, and the Foldkit +
  # Effect train aligned with what node_modules holds, .foldkit-ref on the pinned
  # release, and pnpm-workspace.yaml's supply-chain policy as the pack ships it
  # (age exemptions only for pinned train releases). A synthetic node_modules
  # stands in for pnpm install. Every version comes from the pack's package.json,
  # so the test survives a train move.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-pins/demo" rc bad want f fk vp dt mcp ox effect vite_major fk_next
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  pin() { node -p 'const p = require(process.argv[1]); ({ ...p.dependencies, ...p.devDependencies })[process.argv[2]]' "$d/package.json" "$1"; }
  fk="$(pin foldkit)" vp="$(pin @foldkit/vite-plugin)" dt="$(pin @foldkit/devtools)" \
    mcp="$(pin @foldkit/devtools-mcp)" ox="$(pin @foldkit/oxlint-plugin)" effect="$(pin effect)" || return 1
  vite_major="$(pin vite | cut -d. -f1)"
  fk_next="$(printf '%s' "$fk" | awk -F. '{ print $1 "." $2 + 1 ".0" }')"
  for f in "$fk" "$vp" "$dt" "$mcp" "$ox" "$effect" "$vite_major" "$fk_next"; do
    case "$f" in ''|undefined) fail "cannot read the foldkit train from the pack's package.json" || return 1 ;; esac
  done
  fake() {  # $1 = package name, $2 = version, $3 = peerDependencies JSON
    mkdir -p "$d/node_modules/$1" && printf '{"name":"%s","version":"%s","peerDependencies":%s}\n' "$1" "$2" "$3" > "$d/node_modules/$1/package.json"
  }
  fake foldkit "$fk" "{\"effect\":\"$effect\",\"@effect/platform-browser\":\"$effect\"}" || return 1
  fake @foldkit/vite-plugin "$vp" "{\"vite\":\"^$vite_major.0.0\",\"effect\":\"$effect\",\"foldkit\":\">=0.0.0\"}" || return 1
  fake @foldkit/devtools "$dt" "{\"effect\":\"$effect\",\"foldkit\":\">=$fk\",\"@foldkit/ui\":\"^0\",\"@effect/platform-browser\":\"$effect\"}" || return 1
  fake @foldkit/devtools-mcp "$mcp" "{\"effect\":\"$effect\",\"foldkit\":\">=0.0.0\"}" || return 1
  fake @foldkit/oxlint-plugin "$ox" '{}' || return 1
  # Every other direct dependency is installed too, at its pin.
  fk_node "$d" -e 'const fs = require("fs"); const p = JSON.parse(fs.readFileSync("package.json", "utf8")); for (const [name, version] of Object.entries({ ...p.dependencies, ...p.devDependencies })) { const dir = "node_modules/" + name; if (!fs.existsSync(dir)) { fs.mkdirSync(dir, { recursive: true }); fs.writeFileSync(dir + "/package.json", JSON.stringify({ name, version }) + "\n") } }' \
    || fail "faking the other dependencies failed: $(cat "$d.node.out")" || return 1
  fk_node "$d" scripts/check-pins.mjs; rc=$?
  assert_exit 0 "$rc" || { cat "$d.node.out"; return 1; }
  assert_contains "$d.node.out" "check-pins: ok" || return 1
  for f in package.json VERSION .node-version pnpm-workspace.yaml .foldkit-ref; do cp "$d/$f" "$d.$f.orig" || return 1; done
  cp -R "$d/node_modules" "$d.node_modules.orig" || return 1
  # Each case: a mutation (run in the project, with the pins in its environment)
  # and the text its failure must contain (@FK@ and friends are the pins).
  # Regression case (the last): @foldkit/ui, a peer of @foldkit/devtools, had no
  # pin, so pnpm resolved it on its own and no check held it to the train.
  while IFS='|' read -r bad want; do
    for f in package.json VERSION .node-version pnpm-workspace.yaml .foldkit-ref; do cp "$d.$f.orig" "$d/$f" || return 1; done
    rm -rf "$d/node_modules" && cp -R "$d.node_modules.orig" "$d/node_modules" || return 1
    (cd "$d" && FK="$fk" FK_NEXT="$fk_next" EFFECT="$effect" VITE_NEXT="^$((vite_major + 1)).0.0" eval "$bad") \
      || fail "mutation failed: $bad" || return 1
    want="$(printf '%s' "$want" | sed "s/@FK_NEXT@/$fk_next/g; s/@FK@/$fk/g; s/@VP@/$vp/g; s/@EFFECT@/$effect/g; s/@VITE_NEXT@/^$((vite_major + 1)).0.0/g")"
    fk_node "$d" scripts/check-pins.mjs; rc=$?
    [ "$rc" = 1 ] || fail "check-pins exited $rc after: $bad" || return 1
    assert_contains "$d.node.out" "$want" || return 1
    assert_contains "$d.node.out" "check-pins: FAILED" || return 1
  done <<'CASES'
printf '0.1.0\n' > VERSION|package.json version "0.0.0" differs from VERSION 0.1.0
printf 'v1\n' > VERSION|VERSION must hold MAJOR.MINOR.PATCH
printf '0.1.0.1\n' > VERSION|package.json version "0.0.0" differs from VERSION 0.1.0.1 (npm form 0.1.0): set it to 0.1.0
node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));p.optionalDependencies={"left-pad":"^1.3.0"};fs.writeFileSync("package.json",JSON.stringify(p,null,2)+"\n")'|left-pad must be pinned to an exact version, got "^1.3.0"
node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));p.dependencies.vite="^"+p.devDependencies.vite;fs.writeFileSync("package.json",JSON.stringify(p,null,2)+"\n")'|vite must be pinned to an exact version, got "^
node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));p.dependencies.vite=p.devDependencies.vite;fs.writeFileSync("package.json",JSON.stringify(p,null,2)+"\n")'|vite is listed in both dependencies and devDependencies: keep one
node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));p.devDependencies["@foldkit/ui"]=process.env.FK_NEXT;fs.writeFileSync("package.json",JSON.stringify(p,null,2)+"\n")'|@foldkit/ui @FK_NEXT@ must equal foldkit @FK@
node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));p.devDependencies.vite="^"+p.devDependencies.vite;fs.writeFileSync("package.json",JSON.stringify(p,null,2)+"\n")'|vite must be pinned to an exact version, got "^
node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));fs.writeFileSync("package.json",JSON.stringify(p)+"\n")'|package.json is not in JSON.stringify(pkg, null, 2)
printf '{\n' > package.json|package.json is not valid JSON
printf '0.0.1\n' > .node-version|devEngines.runtime must be node at .node-version's exact version ("0.0.1")
node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));p.packageManager="pnpm@0.0.1";fs.writeFileSync("package.json",JSON.stringify(p,null,2)+"\n")'|and packageManager (pnpm@<same>) must agree
node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));p.devDependencies["@effect/vitest"]="0.0.1";fs.writeFileSync("package.json",JSON.stringify(p,null,2)+"\n")'|@effect/vitest 0.0.1 must match effect @EFFECT@
node -e 'const fs=require("fs");const f="node_modules/foldkit/package.json";const p=JSON.parse(fs.readFileSync(f));p.peerDependencies.effect="0.0.1";fs.writeFileSync(f,JSON.stringify(p))'|foldkit @FK@ needs effect 0.0.1, package.json pins @EFFECT@
node -e 'const fs=require("fs");const f="node_modules/foldkit/package.json";const p=JSON.parse(fs.readFileSync(f));p.version=process.env.FK_NEXT;fs.writeFileSync(f,JSON.stringify(p))'|node_modules has foldkit @FK_NEXT@, package.json pins @FK@: run pnpm install
node -e 'const fs=require("fs");const f="node_modules/effect/package.json";const p=JSON.parse(fs.readFileSync(f));p.version="0.0.1";fs.writeFileSync(f,JSON.stringify(p))'|node_modules has effect 0.0.1, package.json pins @EFFECT@: run pnpm install (if it stays, pnpm-lock.yaml holds the other version: regenerate it)
node -e 'const fs=require("fs");const f="node_modules/typescript/package.json";const p=JSON.parse(fs.readFileSync(f));p.version="0.0.1";fs.writeFileSync(f,JSON.stringify(p))'|node_modules has typescript 0.0.1, package.json pins
rm -rf node_modules/foldkit|node_modules is missing foldkit: run pnpm install
rm -rf node_modules/@foldkit/devtools-mcp|node_modules is missing @foldkit/devtools-mcp: run pnpm install
rm -rf node_modules/effect node_modules/vitest|node_modules is missing effect, vitest: run pnpm install
node -e 'const fs=require("fs");const f="node_modules/@foldkit/vite-plugin/package.json";const p=JSON.parse(fs.readFileSync(f));p.peerDependencies.foldkit=">="+process.env.FK_NEXT;fs.writeFileSync(f,JSON.stringify(p))'|@foldkit/vite-plugin @VP@ needs foldkit >=@FK_NEXT@, package.json pins @FK@
node -e 'const fs=require("fs");const f="node_modules/@foldkit/vite-plugin/package.json";const p=JSON.parse(fs.readFileSync(f));p.peerDependencies.vite=process.env.VITE_NEXT;fs.writeFileSync(f,JSON.stringify(p))'|@foldkit/vite-plugin @VP@ needs vite @VITE_NEXT@
node -e 'const fs=require("fs");const f="node_modules/@foldkit/devtools-mcp/package.json";const p=JSON.parse(fs.readFileSync(f));p.peerDependencies.foldkit="~0.0";fs.writeFileSync(f,JSON.stringify(p))'|which check-pins cannot evaluate
node -e 'const fs=require("fs");const f="node_modules/@foldkit/vite-plugin/package.json";const p=JSON.parse(fs.readFileSync(f));p.peerDependencies.effect="0.0.1";fs.writeFileSync(f,JSON.stringify(p))'|@foldkit/vite-plugin @VP@ needs effect 0.0.1, package.json pins @EFFECT@
node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));p.peerDependencies={"left-pad":"github:alice-example/left-pad"};fs.writeFileSync("package.json",JSON.stringify(p,null,2)+"\n")'|left-pad must be pinned to an exact version, got "github:alice-example/left-pad"
node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));p.devDependencies["@foldkit/devtools"]=process.env.FK_NEXT;fs.writeFileSync("package.json",JSON.stringify(p,null,2)+"\n")'|@foldkit/devtools @FK_NEXT@ must equal foldkit @FK@
node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync("package.json"));delete p.devDependencies["@foldkit/ui"];fs.writeFileSync("package.json",JSON.stringify(p,null,2)+"\n")'|@foldkit/devtools needs @foldkit/ui as a peer: pin @foldkit/ui to foldkit @FK@
perl -pi -e 's/^minimumReleaseAge: .*/minimumReleaseAge: 1439/' pnpm-workspace.yaml|pnpm-workspace.yaml: minimumReleaseAge must be a whole number of minutes, at least 1440 (a day), got "1439"
perl -pi -e 's/^minimumReleaseAge: .*/minimumReleaseAge: 0x5a0/' pnpm-workspace.yaml|minimumReleaseAge must be a whole number of minutes, at least 1440 (a day), got "0x5a0"
perl -ni -e 'print unless /^minimumReleaseAge:/' pnpm-workspace.yaml|pnpm-workspace.yaml must set minimumReleaseAge: a whole number of minutes
printf 'minimumReleaseAge: 2880\n' >> pnpm-workspace.yaml|pnpm-workspace.yaml:8: minimumReleaseAge is given twice
perl -pi -e "s/^trustPolicy: .*/trustPolicy: 'no-downgrade'/" pnpm-workspace.yaml|trustPolicy must be no-downgrade, got "'no-downgrade'"
perl -pi -e 's/^trustPolicy: .*/trustPolicy: off/' pnpm-workspace.yaml|trustPolicy must be no-downgrade, got "off"
perl -pi -e 's/^strictDepBuilds: .*/strictDepBuilds: false/' pnpm-workspace.yaml|strictDepBuilds must be true, got "false"
perl -pi -e 's/^blockExoticSubdeps: .*/blockExoticSubdeps: false/' pnpm-workspace.yaml|blockExoticSubdeps must be true, got "false"
perl -pi -e 's/^allowBuilds: .*/allowBuilds: { esbuild: true }/' pnpm-workspace.yaml|allowBuilds must be {}, got "{ esbuild: true }"
printf 'dangerouslyAllowAllBuilds: true\n' >> pnpm-workspace.yaml|dangerouslyAllowAllBuilds is not a policy setting check-pins knows: adding one is a reviewed change to scripts/check-pins.mjs
printf 'overrides:\n  vite: 1.0.0\n' >> pnpm-workspace.yaml|overrides is not a policy setting check-pins knows
printf '\tminimumReleaseAge: 1440\n' >> pnpm-workspace.yaml|check-pins cannot read this line unambiguously
printf -- '---\n' >> pnpm-workspace.yaml|check-pins cannot read this line unambiguously
printf '  - foldkit@%s\n' "$FK" >> pnpm-workspace.yaml|check-pins cannot read this line unambiguously
rm pnpm-workspace.yaml|pnpm-workspace.yaml is missing
printf 'minimumReleaseAgeExclude:\n  - foldkit\n' >> pnpm-workspace.yaml|minimumReleaseAgeExclude entry "foldkit" must be an exact name@version (no bare name, scope or range)
printf "minimumReleaseAgeExclude:\n  - '@foldkit/*'\n" >> pnpm-workspace.yaml|minimumReleaseAgeExclude entry "@foldkit/*" must be an exact name@version
printf 'minimumReleaseAgeExclude:\n  - foldkit@^%s\n' "$FK" >> pnpm-workspace.yaml|minimumReleaseAgeExclude entry "foldkit@^@FK@" must be an exact name@version
printf 'minimumReleaseAgeExclude:\n  - foldkit@%s\n' "$FK_NEXT" >> pnpm-workspace.yaml|minimumReleaseAgeExclude entry "foldkit@@FK_NEXT@": package.json pins foldkit @FK@
printf 'minimumReleaseAgeExclude:\n  - vite@1.0.0\n' >> pnpm-workspace.yaml|only the Foldkit and Effect train (foldkit, @foldkit/*, effect, @effect/*) may skip the age rule
printf "minimumReleaseAgeExclude:\n  - '@effect/platform-node@%s'\n" "$EFFECT" >> pnpm-workspace.yaml|package.json pins no @effect/platform-node
printf 'minimumReleaseAgeExclude:\n  - foldkit@%s\n  - foldkit@%s\n' "$FK" "$FK" >> pnpm-workspace.yaml|minimumReleaseAgeExclude lists "foldkit@@FK@" twice
printf 'minimumReleaseAgeExclude: [foldkit]\n' >> pnpm-workspace.yaml|write minimumReleaseAgeExclude as a block list
printf 'minimumReleaseAgeExclude:\n  - @effect/vitest@%s\n' "$EFFECT" >> pnpm-workspace.yaml|quote a scoped name
printf '%s 0123456789abcdef0123456789abcdef01234567\n' "$FK_NEXT" > .foldkit-ref|.foldkit-ref records foldkit @FK_NEXT@, package.json pins @FK@: a train move updates both
printf '%s 0123456789abcdef0123456789abcdef01234567\n\n' "$FK" > .foldkit-ref|.foldkit-ref must be one line, "<version> <40-character lowercase commit>"
printf '%s 0123456789abcdef0123456789abcdef01234567' "$FK" > .foldkit-ref|.foldkit-ref must be one line
printf '%s 0123456789ABCDEF0123456789abcdef01234567\n' "$FK" > .foldkit-ref|.foldkit-ref must be one line
printf '%s 0123456789abcdef\n' "$FK" > .foldkit-ref|.foldkit-ref must be one line
printf 'foldkit@%s 0123456789abcdef0123456789abcdef01234567\n' "$FK" > .foldkit-ref|.foldkit-ref must be one line
rm .foldkit-ref|.foldkit-ref is missing
CASES
  # Regression test. gstack's four-part VERSION (a MICRO release) leaves
  # package.json at its npm form, the first three parts; check-pins refused it.
  # An exactly pinned optional dependency may be absent: pnpm skips one off-platform.
  for f in package.json VERSION .node-version pnpm-workspace.yaml .foldkit-ref; do cp "$d.$f.orig" "$d/$f" || return 1; done
  rm -rf "$d/node_modules" && cp -R "$d.node_modules.orig" "$d/node_modules" || return 1
  printf '%s.7\n' "$(cat "$d/VERSION")" > "$d/VERSION"
  fk_json "$d/package.json" 'c.optionalDependencies = { fsevents: "2.3.3" }' || return 1
  fk_node "$d" scripts/check-pins.mjs; rc=$?
  assert_exit 0 "$rc" || { cat "$d.node.out"; return 1; }
  assert_contains "$d.node.out" "check-pins: ok" || return 1
  # Exact exemptions for the train releases package.json pins pass, quoted or not,
  # with a note on when they go; so does a stricter age rule.
  for f in package.json VERSION .node-version pnpm-workspace.yaml .foldkit-ref; do cp "$d.$f.orig" "$d/$f" || return 1; done
  perl -pi -e 's/^minimumReleaseAge: .*/minimumReleaseAge: 2880/' "$d/pnpm-workspace.yaml" || return 1
  printf "minimumReleaseAgeExclude:\n  - foldkit@%s  # remove once it is a day old\n  - '@foldkit/vite-plugin@%s'\n  - \"effect@%s\"\n" \
    "$fk" "$vp" "$effect" >> "$d/pnpm-workspace.yaml"
  fk_node "$d" scripts/check-pins.mjs; rc=$?
  assert_exit 0 "$rc" || { cat "$d.node.out"; return 1; }
  assert_contains "$d.node.out" "check-pins: ok"
}
test_stack_foldkit_rules_keep_foldkit_out_of_domain_and_api() {
  # Regression test (#20 items 6 and 23). The guard grepped src/domain and src/api
  # for `from 'foldkit'`: a subpath, side-effect, dynamic or require import passed,
  # and with src/api missing, grep's error counted as no match.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-rules-boundary/demo"
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  fk_rules "$d" <<'PROBE'
const leak = text => ({ 'src/domain/leak.ts': text })
check({}, 0, 'check-rules: ok')
check(leak("import { defineTaggedUnion } from 'foldkit/schema'\n"), 1,
  'src/domain/leak.ts:1: loads "foldkit/schema": src/domain and src/api must not import foldkit', 'docs/guides/foldkit.md')
check({ ...leak("import { Command } from 'foldkit'\n"), 'src/api': null }, 1, 'src/domain/leak.ts:1: loads "foldkit"')
for (const [text, specifier] of [
  ["import type { Html } from 'foldkit/html'\n", 'foldkit/html'],
  ["export { Command } from '@foldkit/devtools'\n", '@foldkit/devtools'],
  ["export * from 'foldkit'\n", 'foldkit'],
  ["import 'foldkit'\n", 'foldkit'],
  ["export const load = () => import('foldkit/html')\n", 'foldkit/html'],
  ["export const load = () => import(`foldkit`)\n", 'foldkit'],
  ["export const f = require('foldkit')\n", 'foldkit'],
  ["import fk = require('foldkit')\n", 'foldkit'],
  ['/// <reference types="foldkit" />\n', 'foldkit'],
  ["import x from '../../node_modules/foldkit/dist/index.js'\n", '../../node_modules/foldkit/dist/index.js'],
  [`import { x } from '${bs}u0066oldkit/schema'\n`, 'foldkit/schema'],
  [`import { x } from '${bs}x66oldkit'\n`, 'foldkit'],
  [`export const f = ${bs}u0072equire('foldkit')\n`, 'foldkit'],
  ["const s = '//'\nexport const load = () => import('foldkit')\n", 'foldkit'],
]) {
  check(leak(text), 1, `loads ${JSON.stringify(specifier)}`)
}
check({ 'src/api/leak.mts': "export * from '@foldkit/ui'\n" }, 1, 'src/api/leak.mts:1: loads "@foldkit/ui"')
// A module name the check can't read is refused.
for (const text of [
  'export const load = (name: string) => import(name)\n',
  "export const load = () => import(`fold${'kit'}`)\n",
  "export const f = require('fold' + 'kit')\n",
]) {
  check(leak(text), 1, 'of a computed module name')
}
// Comments, strings and regular expressions import nothing.
check(leak("// import { Command } from 'foldkit'\n/* import('foldkit') */\nexport const hint = \"import { Command } from 'foldkit'\"\nexport const re = /from 'foldkit'/\n"), 0, 'check-rules: ok')
// A tagged template may hold any escape (String.raw with a regex backreference,
// as coverage-tiers.mjs does); it reads fine and names no module.
check(leak("export const re = String.raw`\\(\\s*(['\"])\\1`\n"), 0, 'check-rules: ok')
check(leak("export const load = () => import(String.raw`fold\\1kit`)\n"), 1, 'of a computed module name')
// What the tokenizer cannot read fails closed.
check(leak("export const s = 'unterminated\n"), 1, 'src/domain/leak.ts:1: check-rules cannot read this file: unterminated string')
check(leak("export const f = (a: number) => {\n  switch (a) {\n    case 1: {}\n    /x/.test('y')\n  }\n}\n"), 1, 'cannot tell whether this / after } starts a regular expression')
// So does a directory it cannot list (root reads it anyway).
if (process.getuid?.() !== 0) {
  mkdirSync('src/api/locked')
  chmodSync('src/api/locked', 0)
  try {
    check({}, 1, 'src/api/locked:1: cannot read this directory')
  } finally {
    chmodSync('src/api/locked', 0o755)
    rmSync('src/api/locked', { recursive: true })
  }
}
PROBE
}
test_stack_foldkit_rules_refuse_module_mocks() {
  # Regression test (#20 item 7). The guard grepped for `vi.mock(`: vi.doMock, an
  # aliased import (`import { vi as v }`), a namespace import or an alias of vi
  # mocked modules unseen.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-rules-mocks/demo"
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  fk_rules "$d" <<'PROBE'
const test = text => ({ 'src/mocked.test.ts': text })
const NO_MOCK = 'no vi.mock, vi.doMock or vi.importMock'
check({}, 0, 'check-rules: ok')
for (const [text, call] of [
  ["import { vi } from 'vitest'\n\nvi.mock('./main')\n", 'src/mocked.test.ts:3: vi.mock'],
  ["vi.doMock('./main')\n", 'vi.doMock'],
  ["import { vi } from 'vitest'\nawait vi.importMock('./main')\n", 'vi.importMock'],
  ["import { vitest } from 'vitest'\nvitest.mock('./main')\n", 'vitest.mock'],
  ["import { vi as v } from 'vitest'\nv.mock('./main')\n", 'v.mock'],
  ["import { it, vi as mocker } from '@effect/vitest'\nmocker.doMock('./main')\n", 'mocker.doMock'],
  ["import * as V from 'vitest'\nV.vi.mock('./main')\n", 'V.vi.mock'],
  ["import * as E from '@effect/vitest'\nE.vitest.doMock('./main')\n", 'E.vitest.doMock'],
  ["import { vi } from 'vitest'\nexport const mocked = typeof vi.doMock('./main')\n", 'vi.doMock'],
  ["import { vi as v } from 'vitest'\nconst mocked = typeof v.mock('./main')\n", 'v.mock'],
  ["import * as V from 'vitest'\nconst mocked = typeof V.vi.importMock('./main')\n", 'V.vi.importMock'],
  [`${bs}u0076i.mock('./main')\n`, 'vi.mock'],
]) {
  check(test(text), 1, `${call}: ${NO_MOCK}`)
}
// Any other use of vi, or of a vitest namespace, could hide a mock.
for (const [text, shown] of [
  ["import { vi } from 'vitest'\nconst v = vi\nv.mock('./main')\n", 'vi'],
  ["import { vi } from 'vitest'\nregister(vi)\n", 'vi'],
  ["import { vi } from 'vitest'\nvi['mock']('./main')\n", 'vi'],
  ["import { vi } from 'vitest'\nconst { mock } = vi\n", 'vi'],
  ["import * as V from 'vitest'\nconst t = V\n", 'V'],
  ["import * as V from 'vitest'\nV['vi'].mock('./main')\n", 'V'],
  ["import * as V from 'vitest'\nconst v = V.vi\n", 'V.vi'],
  ["import { vi } from 'vitest'\nconst mocked = typeof vi['doMock']('./main')\n", 'vi'],
  ["import * as V from 'vitest'\nconst mocked = typeof V['vi'].mock('./main')\n", 'V'],
  ["import { vi } from 'vitest'\nconst mocked = typeof (alias = vi)\n", 'vi'],
]) {
  check(test(text), 1, `${shown} is used other than as ${shown}.<method>(...)`)
}
check({ 'src/test-utils.ts': "export { vi } from 'vitest'\n" }, 1, 're-exports vi from vitest')
check({ 'src/test-utils.ts': "export * from '@effect/vitest'\n" }, 1, 're-exports vi from @effect/vitest')
check({ 'src/test-utils.ts': "import { vi } from 'vitest'\nexport { vi }\n" }, 1, 'vi is used other than')
check(test("const { vi } = await import('vitest')\n"), 1, 'import() loads vitest: import { vi } statically')
check(test("import vitest from 'vitest'\n"), 1, 'a default import from vitest')
check({ 'e2e/mocked.spec.ts': "import { vi } from 'vitest'\nvi.mock('./x')\n" }, 1, `e2e/mocked.spec.ts:2: vi.mock: ${NO_MOCK}`)
// Spies, fakes and typed fns are fine; so are comments, strings and other objects' mock().
check(test([
  "import { vi } from 'vitest'",
  'const spy = vi.fn<() => number>()',
  "vi.spyOn(console, 'log')",
  'vi.useFakeTimers()',
  'type Spy = typeof vi.fn',
  'type Helpers = typeof vi',
  "// vi.mock('./main')",
  "export const s = \"vi.mock('./main')\"",
  'declare const lib: { mock: (path: string) => void }',
  "lib.mock('./main')",
  '',
].join('\n')), 0, 'check-rules: ok')
check(test("import { vi as v } from 'vitest'\nimport * as V from 'vitest'\ntype Alias = typeof v.fn; type Namespace = typeof V; type Helpers = typeof V.vi; type Spy = typeof V.vi.fn\n"), 0, 'check-rules: ok')
PROBE
}
test_stack_foldkit_rules_keep_the_devtools_relay_off() {
  # Regression test (#20 item 22, P1). The guard skipped any vite.config.ts line
  # holding `devToolsMcpPort: false` and read no other file: an alias
  # (`devToolsMcpPort: falsePort`), the text in a trailing comment, a second
  # config or `vite --config` opened the unauthenticated relay unseen.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-rules-relay/demo"
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  fk_rules "$d" <<'PROBE'
const PLUGIN = '@foldkit/vite-plugin'
const RELAY = ['docs/guides/foldkit.md', 'extend scripts/check-rules.mjs if the change is safe']
const vite = readFileSync('vite.config.ts', 'utf8')
const CALL = 'foldkit({ devToolsMcpPort: false })'
assert.ok(vite.includes(CALL) && vite.includes(`import { foldkit } from '${PLUGIN}'`), 'the starter vite.config.ts changed: update this test')
const config = (from, to) => ({ 'vite.config.ts': vite.replace(from, to) })
check({}, 0, 'check-rules: ok')
// The token-protected relay, and a formatter's trailing commas.
check(config(CALL, 'foldkit()'), 0, 'check-rules: ok')
check(config(CALL, 'foldkit({\n      devToolsMcpPort: false,\n    },)'), 0, 'check-rules: ok')
// A function/class expression ends an operand, not a statement block. Treating
// the following division as a regex hid a second plugin call from the guard.
const exportedPlugins = expression => ({ 'vite.config.ts': `import { foldkit } from '${PLUGIN}'\nconst p = [${CALL}]\n${expression}\nexport default { plugins: p }\n` })
for (const expression of [
  '+function(){return 0}', '+function named(){return 0}',
  '+async function(){return 0}', '+function*(){yield 0}', '+async function*(){yield 0}',
  '+class {}', '+class Named {}', '+class extends Object {}',
  '+class Named extends Object {}', '+class extends (Object) {}',
]) {
  check(exportedPlugins(`const _x = ${expression} / p.push(foldkit({devToolsMcpPort:9988})) / 1`), 1,
    'cannot tell whether this / after } starts a regular expression')
}
for (const expression of [
  'const _x = 12 / 3', 'const _x = (function(){return 0}) / 2',
  'const _x = {} / 2', 'const re = /foldkit.*devToolsMcpPort:9988/',
  'if (true) {} /literal/.test("literal")',
  'if (true) {} else {} /literal/.test("literal")',
  'do {} while (false); /literal/.test("literal")',
  'try {} finally {} /literal/.test("literal")',
]) {
  check(exportedPlugins(expression), 0, 'check-rules: ok')
}
check(config(`[${CALL}]`, '[\n    foldkit({ devToolsMcpPort: 9988 }), // foldkit({ devToolsMcpPort: false })\n  ]'), 1,
  `vite.config.ts:${lineOf(vite, CALL) + 1}: foldkit(...) takes another argument than { devToolsMcpPort: false } or none`)
for (const call of [
  'foldkit({ devToolsMcpPort: 9988 })',
  'foldkit({ devToolsMcpPort: falsePort })',
  "foldkit({ devToolsMcpPort: 'false' })",
  'foldkit({ devToolsMcpPort: false, ...relay })',
  'foldkit({ devToolsMcpPort: false && 9988 })',
]) {
  check(config(CALL, call), 1, `vite.config.ts:${lineOf(vite, CALL)}: foldkit(...) takes another argument than { devToolsMcpPort: false } or none`,
    'a numeric devToolsMcpPort opens an unauthenticated DevTools relay', ...RELAY)
}
// The foldkit binding appears only in its import and the one call.
for (const [from, to, text] of [
  ['export default', 'const relay = foldkit\nexport const extra = relay({ devToolsMcpPort: 3001 })\n\nexport default', 'uses foldkit other than as the one plugin call'],
  [CALL, 'foldkit.call(null, { devToolsMcpPort: 3001 })', 'uses foldkit other than as the one plugin call'],
  [CALL, `${CALL}, ...[foldkit].map(plugin => plugin({ devToolsMcpPort: 3001 }))`, 'uses foldkit other than as the one plugin call'],
  [CALL, `${CALL}, wrap({ foldkit })`, 'uses foldkit other than as the one plugin call'],
  [CALL, `${CALL}, foldkit({ devToolsMcpPort: 3001 })`, 'calls foldkit(...) 2 times'],
  ['import { foldkit } from', 'import { foldkit as fk } from', `imports ${PLUGIN} other than as import { foldkit } from`],
  [`import { foldkit } from '${PLUGIN}'`, `import foldkit from '${PLUGIN}'`, `imports ${PLUGIN} other than as`],
  [`import { foldkit } from '${PLUGIN}'`, `import * as plugin from '${PLUGIN}'\nconst { foldkit } = plugin`, `imports ${PLUGIN} other than as`],
  [`import { foldkit } from '${PLUGIN}'`, `import { foldkit } from '${PLUGIN}'\nimport '${PLUGIN}'`, `imports ${PLUGIN} other than as`],
  ['export default', "const plugin = await import(`@foldkit/${'vite-plugin'}`)\n\nexport default", 'import() of a computed module name, which check-rules cannot follow'],
]) {
  check(config(from, to), 1, text, ...RELAY)
}
check({ 'vite.config.ts': null }, 1, 'vite.config.ts:1: is missing')
// Nothing else loads the plugin, however the name is spelled.
for (const [file, text] of [
  ['scripts/dev.mjs', `const { foldkit } = await import('${PLUGIN}')\n`],
  ['scripts/dev.mjs', 'await import(`' + PLUGIN + '`)\n'],
  ['scripts/dev.mjs', `await import('${bs}u0040foldkit/vite-plugin')\n`],
  ['scripts/dev.cjs', `const { foldkit } = require('${PLUGIN}')\n`],
  ['src/plugin.ts', `export { foldkit } from '${PLUGIN}'\n`],
  ['vitest.config.ts', `import { foldkit } from '${PLUGIN}'\n`],
]) {
  check({ [file]: text }, 1, `${file}:1: names ${PLUGIN}: only vite.config.ts loads it, once`, ...RELAY)
}
// Only the root vite.config.ts configures Vite...
for (const file of ['vite.config.mjs', 'vite.config.js', 'tools/vite.config.ts', 'e2e/vite.config.mts']) {
  check({ [file]: 'export default {}\n' }, 1, `${file}:1: only the root vite.config.ts may configure Vite`, ...RELAY)
}
// ...outside generated and vendored trees and other repositories (a worktree).
check({
  'node_modules/x/vite.config.ts': 'export default {}\n',
  'dist/vite.config.js': 'export default {}\n',
  'repos/foldkit/vite.config.ts': `import { foldkit } from '${PLUGIN}'\n`,
  '.claude/worktrees/w/.git': 'gitdir: /elsewhere\n',
  '.claude/worktrees/w/vite.config.ts': `import { foldkit } from '${PLUGIN}'\n`,
}, 0, 'check-rules: ok')
// ...and nothing points vite at another config.
const pkg = JSON.parse(readFileSync('package.json', 'utf8'))
const script = command => ({ 'package.json': `${JSON.stringify({ ...pkg, scripts: { ...pkg.scripts, dev: command } }, null, 2)}\n` })
const alternateConfigs = [
  'vite --config other.ts', 'vite -c other.ts', 'vite build --config=other.ts',
  'pnpm exec vite preview -c=other.ts', 'node node_modules/vite/bin/vite.js --config other.ts',
  'vite --"config" other.ts', 'vi"te" --"config" other.ts',
  String.raw`v\ite --con\fig other.ts`, 'pnpm exec "vi"te -"c" other.ts',
  'vite "--config"="other.ts"', "vite --'config' other.ts",
  'vite "" --config other.ts', 'vite --con' + bs + '\nfig other.ts',
  'env MODE=production vite --config other.ts', 'command vite --config other.ts',
  'exec vite --config other.ts', '/usr/bin/env MODE=production vite --"config" other.ts',
]
for (const command of alternateConfigs) {
  check(script(command), 1, 'script "dev" must be a command that passes no --config to vite', ...RELAY)
}
const literalCommands = [
  'vite --port 3001 && vitest --config vitest.config.ts',
  'vi"te" --port 3001', String.raw`v\ite --port 3001`,
  'pnpm exec vite --port 3001', 'node node_modules/vite/bin/vite.js build',
  'vite --port 3001 || vite preview; vitest run\nnode scripts/check-pins.mjs',
  'echo "--config && vite"; vite', 'echo "vite; --config" && vite',
  "echo 'vite --config $IGNORED *.ts' && vite", 'echo "" && vite',
  'echo "quoted ' + bs + '$literal ' + bs + '`tick ' + bs + 'q" && vite',
  String.raw`echo vite\;\ --config && vite`,
  'env MODE=production vite', 'command vite', 'exec vite', '/usr/bin/env MODE=production vite',
]
for (const command of literalCommands) {
  check(script(command), 0, 'check-rules: ok')
}
const unsupportedCommands = [
  'vite --config "$CONFIG"', 'vite ${FLAGS}', 'vite $(cat flags)',
  'vite `cat flags`', 'vite > output.txt', 'vite | tee output.txt',
  'vite &', '(vite)', 'vite *.ts', 'vite [ab].ts', 'vite {a,b}',
  'vite "unterminated', 'vite \\', "sh -c 'vite --config other.ts'",
  "eval 'vite --config other.ts'", "env bash -c 'vite --config other.ts'",
  "env -i sh -c 'vite --config other.ts'", "command -p sh -c 'vite --config other.ts'",
  "/usr/bin/env sh -c 'vite --config other.ts'", "/usr/bin/env -i sh -c 'vite --config other.ts'",
]
for (const command of unsupportedCommands) {
  check(script(command), 1, 'unsupported shell syntax', ...RELAY)
}
const playwright = readFileSync('playwright.config.ts', 'utf8')
const [web, command] = /command: '([^']*)'/.exec(playwright) ?? []
assert.ok(web !== undefined && command.includes('vite'), 'playwright.config.ts has no webServer command: update this test')
check({ 'playwright.config.ts': playwright.replace(web, `command: '${command.replace('vite build', 'vite build -c other.ts')}'`) }, 1,
  `playwright.config.ts:${lineOf(playwright, web)}: a command passes --config to vite`, ...RELAY)
check({ 'playwright.config.ts': playwright.replace(web, 'command: `vite build ${process.env.FLAGS}`') }, 1, 'the webServer command must be one plain string')
for (const command of alternateConfigs) {
  check({ 'playwright.config.ts': playwright.replace(web, `command: ${JSON.stringify(command)}`) }, 1, 'a command passes --config to vite', ...RELAY)
}
for (const command of literalCommands) {
  check({ 'playwright.config.ts': playwright.replace(web, `command: ${JSON.stringify(command)}`) }, 0, 'check-rules: ok')
}
for (const command of unsupportedCommands) {
  check({ 'playwright.config.ts': playwright.replace(web, `command: ${JSON.stringify(command)}`) }, 1, 'unsupported shell syntax', ...RELAY)
}
check({ 'playwright.config.ts': playwright.replace("testDir: 'e2e',", "testDir: 'e2e', testMatch: '**/*.spec.ts', metadata: { command: 'echo $UNRELATED', hint: './fixtures/{case}/docs.ts' },") }, 0, 'check-rules: ok')
check({ 'playwright.config.ts': playwright.replace('webServer: {', 'webServer: [{').replace('reuseExistingServer: false,\n  },', 'reuseExistingServer: false,\n  }],').replace(web, '"command": \'vi"te" --"config" other.ts\'') }, 1, 'a command passes --config to vite', ...RELAY)
// Keep the previous scan's protection when the literal lives in a separate
// server object; unsupported globs/paths elsewhere are not shell commands.
const aliasedServer = command => ({ 'playwright.config.ts': `import { defineConfig } from '@playwright/test'\nconst server = { command: ${JSON.stringify(command)}, port: 4000 }\nexport default defineConfig({ webServer: server })\n` })
check(aliasedServer('vite build && vite preview'), 0, 'check-rules: ok')
for (const command of alternateConfigs) {
  check(aliasedServer(command), 1, 'a command passes --config to vite', ...RELAY)
}
const serverAliases = (command, value) => ({ 'playwright.config.ts': `import { defineConfig } from '@playwright/test'\nconst server = { command: ${command}, port: 4000 }\nconst alias = server\nconst servers = [server, alias]\nexport default defineConfig({ webServer: ${value} })\n` })
for (const value of ['server', 'alias', '[server]', 'servers', '[alias, ...[]]']) {
  const supported = !value.includes('...')
  if (supported) {
    check(serverAliases("'vite build && vite preview'", value), 0, 'check-rules: ok')
    check(serverAliases("'vite ' + '--config other.ts'", value), 1, 'the webServer command must be one plain string')
    check(serverAliases("'vite --config other.ts > /tmp/vite-log'", value), 1, 'unsupported shell syntax', ...RELAY)
  } else {
    check(serverAliases("'vite'", value), 1, 'cannot follow this webServer value')
  }
}
for (const declarations of [
  'const a = b; const b = a;',
  "let a = { command: 'vite' };",
  "const a = { command: 'vite' }; function other() { const a = { command: 'vite' }; return a }",
]) {
  check({ 'playwright.config.ts': `import { defineConfig } from '@playwright/test'\n${declarations}\nexport default defineConfig({ webServer: a })\n` }, 1, 'cannot follow this webServer value')
}
check({ 'playwright.config.ts': "import { defineConfig } from '@playwright/test'\nconst webServer = [{ command: 'vite build && vite preview', port: 4000 }]\nexport default defineConfig({ webServer, metadata: { command: 'echo $UNRELATED', glob: '**/*.spec.ts' } })\n" }, 0, 'check-rules: ok')
// A non-command shorthand property does not alter the literal launch string.
for (const value of ["{ command: 'vite build && vite preview', port }", 'server', '[server]']) {
  check({ 'playwright.config.ts': `import { defineConfig } from '@playwright/test'\nconst port = 4000\nconst server = { command: 'vite build && vite preview', port }\nexport default defineConfig({ webServer: ${value} })\n` }, 0, 'check-rules: ok')
}
check({ 'playwright.config.ts': "import { defineConfig } from '@playwright/test'\nconst command = 'vite build && vite preview'\nexport default defineConfig({ webServer: { command, port: 4000 } })\n" }, 1, 'the webServer command must be one plain string')
check({ 'playwright.config.ts': "import { defineConfig } from '@playwright/test'\nconst override = { command: 'vite --config other.ts > /tmp/vite-log' }\nexport default defineConfig({ webServer: { command: 'vite', ...override } })\n" }, 1, 'cannot follow this webServer value')
PROBE
}
test_stack_foldkit_rules_refuse_contextual_keyword_slash_ambiguity() {
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-rules-contextual-slash/demo"
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  fk_rules "$d" <<'PROBE'
const exported = expression => ({ 'vite.config.ts': `import { foldkit } from '@foldkit/vite-plugin'\nconst plugins = [foldkit({ devToolsMcpPort: false })]\n${expression}\nexport default { plugins }\n` })
for (const name of ['of', 'as', 'satisfies']) {
  for (const suffix of ['', '!', '!!']) {
    check(exported(`const ${name} = 1\nconst result = ${name}${suffix} / plugins.push(foldkit({ devToolsMcpPort: 9988 })) / 1`), 1,
      'cannot tell whether this /', 'extend scripts/check-rules.mjs')
    check({ 'src/domain/leak.ts': `const ${name} = 1\nexport const result = ${name}${suffix} / Number(import('foldkit')) / 1\n` }, 1,
      'cannot tell whether this /')
  }
}
check({ 'scripts/leak.mjs': `const of = 1\nexport const result = of / Number(import('@foldkit${bs}x2fvite-plugin')) / 1\n` }, 1,
  'cannot tell whether this /')
// A real regex after for-of is equally ambiguous to this bounded tokenizer:
// refusing it is safer than silently reading either syntax the wrong way.
check(exported('for (const value of /safe/.source) {}'), 1, 'cannot tell whether this /')
for (const expression of [
  'const of = 4; const result = (of) / 2',
  'const of = 4; const result = (of!) / 2',
  'const value = 4; const result = value!! / 2',
  'const result = ! ! /safe/.test("safe")',
  'const obj = { of: 4, as: 4, satisfies: 4 }; const result = obj.of / obj.as / obj.satisfies',
  `const ${bs}u006ff = 4; const result = ${bs}u006ff / 2`,
  'for (const value of (/safe/.source)) {}',
]) {
  check(exported(expression), 0, 'check-rules: ok')
}
PROBE
}
test_stack_foldkit_rules_follow_shell_execution_wrappers() {
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-rules-shell-wrappers/demo"
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  fk_rules "$d" <<'PROBE'
const pkg = JSON.parse(readFileSync('package.json', 'utf8'))
const script = command => ({ 'package.json': `${JSON.stringify({ ...pkg, scripts: { ...pkg.scripts, dev: command } }, null, 2)}\n` })
const web = command => ({ 'playwright.config.ts': `import { defineConfig } from '@playwright/test'\nexport default defineConfig({ webServer: { command: ${JSON.stringify(command)}, port: 4000 } })\n` })
const nested = [
  "pnpm exec sh -c 'vite --config other.ts'",
  "nohup sh -c 'vite --config other.ts'",
  "timeout 60 sh -c 'vite --config other.ts'",
  "if true; then sh -c 'vite --config other.ts'; fi",
  "ash -c 'vite --config other.ts'", "mksh -c 'vite --config other.ts'",
  "npx sh -c 'vite --config other.ts'",
  "env MODE=production pnpm exec nohup timeout 60 /bin/sh -c 'vite --config other.ts'",
  "nohup -- sh -c 'vite --config other.ts'", "timeout -k 1 60 sh -c 'vite --config other.ts'",
  "pnpm --dir other exec sh -c 'vite --config other.ts'", "npx -y sh -c 'vite --config other.ts'",
]
for (const command of nested) {
  for (const source of [script, web]) {
    check(source(command), 1, 'unsupported shell syntax', 'docs/guides/foldkit.md')
  }
}
for (const command of [
  'npx vite@8.3.1 -c other.ts', 'npx vite@8.3.1 --config=other.ts',
  'vite --c other.ts', 'vite --c=other.ts', 'pnpm exec vite --c other.ts',
  'npm exec vite --config other.ts', 'pnpm dlx vite --config other.ts',
]) {
  for (const source of [script, web]) {
    check(source(command), 1, '--config', 'docs/guides/foldkit.md')
  }
}
// Keep literal echo arguments separate from an executable's identity.
for (const command of [
  "echo 'sh -c' && vite", 'echo sh && vite', 'pnpm exec vite --port 3001',
  'env MODE=production vite', "echo 'vite --config' && vite", 'npx vite@8.3.1 --port 3001',
]) {
  for (const source of [script, web]) check(source(command), 0, 'check-rules: ok')
}
PROBE
}
test_stack_foldkit_rules_refuse_mutable_playwright_server_aliases() {
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-rules-mutable-server/demo"
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  fk_rules "$d" <<'PROBE'
const config = body => ({ 'playwright.config.ts': `import { defineConfig } from '@playwright/test'\n${body}\n` })
const unsafe = 'vite --config other.ts > /dev/null'
for (const member of ['.webServer', "['webServer']"]) {
  check(config(`const config = defineConfig({ testDir: 'e2e' });\nconfig${member} = { command: ${JSON.stringify(unsafe)}, port: 4000 };\nexport default config;`), 1,
    'cannot follow this webServer value')
}
for (const mutation of [
  `server.command = ${JSON.stringify(unsafe)};`,
  `server['command'] = ${JSON.stringify(unsafe)};`,
  `Object.assign(server, { command: ${JSON.stringify(unsafe)} });`,
  `const alias = server; alias.command = ${JSON.stringify(unsafe)};`,
  `const envelope = { server }; envelope.server.command = ${JSON.stringify(unsafe)};`,
  `const envelope = { nested: { server } }; change(envelope);`,
  `change(server);`,
]) {
  check(config(`const server = { command: 'vite build', port: 4000 };\n${mutation}\nexport default defineConfig({ webServer: server });`), 1,
    'cannot follow this webServer value')
}
check(config(`const servers = [{ command: 'vite build', port: 4000 }];\nservers.push({ command: ${JSON.stringify(unsafe)}, port: 4001 });\nexport default defineConfig({ webServer: servers });`), 1,
  'cannot follow this webServer value')
for (const initializer of ["{ testDir: 'e2e' }", "defineConfig({ testDir: 'e2e' })"]) {
  for (const mutation of [
    'change(config);',
    'const alias = config; change(alias);',
    'const envelope = { config }; change(envelope);',
  ]) {
    check(config(`const config = ${initializer};\n${mutation}\nexport default config;`), 1,
      'cannot follow this webServer value')
  }
}
// Existing accepted grammar remains immutable aliases, arrays and shorthand ports.
check(config("const port = 4000;\nconst server = { command: 'vite build && vite preview', port };\nconst alias = server;\nconst servers = [server, alias];\nexport default defineConfig({ webServer: servers, metadata: { command: 'echo $UNRELATED', glob: '**/*.spec.ts' } });"), 0,
  'check-rules: ok')
check(config("const server = { command: 'vite build', port: 4000 };\nconst envelope = { nested: { server } };\nconst config = defineConfig({ webServer: server, metadata: envelope });\nexport default config;"), 0,
  'check-rules: ok')
for (const body of [
  "const config = defineConfig({ testDir: 'e2e' },);\nconfig.webServer = { command: 'vite --config other.ts' };\nexport default config;",
  "const server = { command: 'vite build', port: 4000 };\nserver.command = 'vite --config other.ts';\nexport default defineConfig({ webServer: server },);",
  "export default defineConfig({ webServer: { command: 'vite build' } }, { webServer: { command: 'vite --config other.ts' } },);",
]) check(config(body), 1, 'cannot follow this webServer value')
PROBE
}
test_stack_foldkit_rules_accept_single_config_argument_with_trailing_comma() {
  # The mutation guard must preserve valid single-argument call punctuation.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-rules-trailing-comma/demo"
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  fk_rules "$d" <<'PROBE'
const config = body => ({ 'playwright.config.ts': `import { defineConfig } from '@playwright/test'\n${body}\n` })
for (const body of [
  "export default defineConfig({ webServer: { command: 'vite build', port: 4000 } },);",
  "const server = { command: 'vite build', port: 4000 };\nconst config = defineConfig({ webServer: server },);\nexport default config;",
  "const config = { webServer: { command: 'vite build', port: 4000 } };\nexport default defineConfig(config,);",
]) check(config(body), 0, 'check-rules: ok')
PROBE
}
test_stack_foldkit_rules_accept_noncalling_type_queries() {
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-rules-type-queries/demo"
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  fk_rules "$d" <<'PROBE'
const test = text => ({ 'src/query.test.ts': `import { vi, describe, it, test } from 'vitest'\ntype Box<T> = { value: T }\n${text}\n` })
for (const text of [
  'let spy: ReturnType<typeof vi.spyOn>',
  'type Spy = Box<Box<typeof vi.spyOn>>',
  'type Spy = Box<Box<Box<typeof vi.spyOn>>>',
  'const fn: typeof vi.fn = vi.fn()',
  "type Spy = typeof vi.fn\ndescribe('suite', () => {})",
  "type Spy = typeof vi.fn\nit('case', () => {})",
  "type Spy = typeof vi.fn\ntest('case', () => {})",
]) check(test(text), 0, 'check-rules: ok')
for (const text of [
  "const mocked = typeof vi.mock('./main')",
  "const mocked = typeof vi.mock\n('./main')",
  "const mocked = typeof vi.mock?.('./main')",
  "const mocked = typeof vi['mock']('./main')",
  "const mocked = typeof vi.mock!('./main')",
  "const mocked = typeof vi.mock<string>('./main')",
]) check(test(text), 1, 'no vi.mock, vi.doMock or vi.importMock')
PROBE
}

test_stack_foldkit_rules_pin_the_devtools_mcp() {
  # Regression test (#20 item 7). The guard grepped .mcp.json for npx: `pnpm dlx`,
  # pnpx, bunx or yarn dlx ran an unpinned MCP server, and .cursor/mcp.json and
  # .vscode/mcp.json went unread.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-rules-mcp/demo"
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  fk_rules "$d" <<'PROBE'
const BIN = 'node_modules/.bin/foldkit-devtools-mcp'
const servers = (key, server) => `${JSON.stringify({ [key]: { 'foldkit-devtools': server } }, null, 2)}\n`
for (const [file, key] of [['.mcp.json', 'mcpServers'], ['.cursor/mcp.json', 'mcpServers'], ['.vscode/mcp.json', 'servers']]) {
  check({ [file]: servers(key, { command: BIN }) }, 0, 'check-rules: ok')
  check({ [file]: servers(key, { type: 'stdio', command: BIN, env: { DEBUG: '1' } }) }, 0, 'check-rules: ok')
  for (const server of [
    { command: 'npx', args: ['-y', '@foldkit/devtools-mcp'] },
    { command: 'pnpm', args: ['dlx', '@foldkit/devtools-mcp@latest'] },
    { command: 'pnpx', args: ['@foldkit/devtools-mcp'] },
    { command: 'bunx', args: ['@foldkit/devtools-mcp'] },
    { command: 'yarn', args: ['dlx', '@foldkit/devtools-mcp'] },
    { command: BIN, args: ['--port', '9988'] },
    { command: 'sh', args: ['-c', BIN] },
    { command: 'npx', args: ['-y', '$PACKAGE'], env: { PACKAGE: '@foldkit/devtools-mcp' } },
  ]) {
    check({ [file]: servers(key, server) }, 1, `${file}:3: server "foldkit-devtools" must call the pinned local bin`, 'docs/guides/foldkit.md')
  }
  check({ [file]: '{ "mcpServers": {' }, 1, `${file}:1: is not valid JSON`)
}
// Other servers are not this check's business.
check({ '.mcp.json': servers('mcpServers', { command: 'npx', args: ['-y', 'some-server'] }) }, 0, 'check-rules: ok')
check({ '.mcp.json': JSON.stringify({ mcpServers: [] }) }, 1, '.mcp.json:1: mcpServers must be an object')
PROBE
}
test_stack_foldkit_rules_keep_src_to_ts_modules() {
  # Regression test (Codex review CX4). Coverage measures src/**/*.ts only, so a
  # .mts, .tsx or .js module under src escaped every floor while tests passed.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-rules-sources/demo"
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  fk_rules "$d" <<'PROBE'
for (const ext of ['mts', 'cts', 'tsx', 'js', 'mjs', 'cjs', 'jsx', 'd.mts']) {
  check({ [`src/domain/extra.${ext}`]: 'export const x = 1\n' }, 1, `src/domain/extra.${ext}:1: coverage measures src/**/*.ts only`)
}
check({ 'src/domain/extra.ts': 'export const x = 1\n', 'src/domain/extra.d.ts': 'export {}\n', 'scripts/tool.mjs': 'export const x = 1\n' }, 0, 'check-rules: ok')
PROBE
}
test_stack_foldkit_guard_runs_its_checkers_first() {
  # The guard runs check-rules.mjs, and before any pnpm command (cheapest first):
  # a module mock fails it offline. A stub pnpm and a faked install stand in.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-guard-order/demo" rc
  { foldkit_files "$d" && fk_installed "$d" && fk_stub_pnpm "$d.bin"; } || fail "fixture setup failed" || return 1
  fk_guard "$d"; rc=$?
  assert_exit 0 "$rc" || { cat "$d.guard.out"; return 1; }
  assert_contains "$d.guard.out" "check-rules: ok" || return 1
  printf "vi.doMock('./main')\n" > "$d/src/mocked.test.ts"
  fk_guard "$d" FK_PNPM_LOG="$d.pnpm.log"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard.out" "src/mocked.test.ts:1: vi.doMock: no vi.mock" || return 1
  assert_absent "$d.pnpm.log"
}
test_stack_foldkit_guard_reports_lockfile_failures_accurately() {
  # Regression test (#20 item 26). The lockfile check gave its 24-hour advice for
  # every supply-chain failure, a tampered tarball URL included, with pnpm's help
  # cut; and pnpm_config_* settings in the environment beat pnpm-workspace.yaml
  # (pnpm_config_trust_lockfile=true skips the policy check altogether).
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-guard-lockfile/demo" rc setting policy=()
  { foldkit_files "$d" && fk_installed "$d" && fk_stub_pnpm "$d.bin"; } || fail "fixture setup failed" || return 1
  # pnpm 12.6.0's reports, abridged.
  cat > "$d.age" <<'OUT'
Error: ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION
  -> 1 lockfile entries failed verification:
       foldkit@0.165.0 was published at 2026-10-01T01:47:28.062Z, within the minimumReleaseAge cutoff (2026-10-12T22:58:36.307Z)
  help: The lockfile contains entries that the active policies reject. [...]
        Alternatively, relax the policy that flagged them.
OUT
  cat > "$d.url" <<'OUT'
Error: ERR_PNPM_LOCKFILE_RESOLUTION_VERIFICATION
  -> 1 lockfile entries failed verification:
       foldkit@0.165.0 has a tarball URL (https://registry.npmjs.org/foldkit/-/foldkit-0.0.1.tgz) that does not match the registry's published metadata
  help: The lockfile contains entries that the active policies reject. [...]
        Alternatively, relax the policy that flagged them.
OUT
  printf 'Error: ERR_PNPM_TRUST_DOWNGRADE\n  help: Check who published it.\n' > "$d.trust"
  printf 'Error: ERR_PNPM_OUTDATED_LOCKFILE\n  -> pnpm-lock.yaml is not up to date with package.json.\n  help: Regenerate the lockfile.\n' > "$d.stale"
  fk_guard "$d" FK_PNPM_INSTALL="cat '$d.age'; exit 1"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard.out" "foldkit@0.165.0 was published at" || return 1
  assert_contains "$d.guard.out" "a locked release is younger than pnpm-workspace.yaml's minimumReleaseAge" || return 1
  assert_not_contains "$d.guard.out" "relax the policy" || return 1
  assert_not_contains "$d.guard.out" "tampered" || return 1
  for f in url trust; do
    fk_guard "$d" FK_PNPM_INSTALL="cat '$d.$f'; exit 1"; rc=$?
    assert_exit 1 "$rc" || return 1
    assert_contains "$d.guard.out" "$(sed -n 's/^  help: //p' "$d.$f")" || return 1
    assert_contains "$d.guard.out" "pnpm-lock.yaml or a dependency may have been tampered with" || return 1
    assert_not_contains "$d.guard.out" "minimumReleaseAge, 24 hours" || return 1
  done
  assert_contains "$d.guard.out" "ERR_PNPM_TRUST_DOWNGRADE" || return 1
  fk_guard "$d" FK_PNPM_INSTALL="cat '$d.stale'; exit 1"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard.out" "help: Regenerate the lockfile." || return 1
  assert_contains "$d.guard.out" "pnpm-lock.yaml is missing or out of date with package.json" || return 1
  assert_not_contains "$d.guard.out" "tampered" || return 1
  # Every policy setting, in both spellings pnpm reads, is cleared; others stay.
  for setting in $FK_POLICY_SETTINGS; do
    policy+=("pnpm_config_$setting=1" "PNPM_CONFIG_$(printf '%s' "$setting" | tr '[:lower:]' '[:upper:]')=1")
  done
  fk_guard "$d" "${policy[@]}" pnpm_config_store_dir=/tmp/kept FK_PNPM_INSTALL="env > '$d.env'"; rc=$?
  assert_exit 0 "$rc" || { cat "$d.guard.out"; return 1; }
  assert_contains "$d.env" "pnpm_config_store_dir=/tmp/kept" || return 1
  fk_policy_kept "$d.env"
}
test_stack_foldkit_bootstrap_installs_under_the_file_policy() {
  # Regression test (#20 items 11 and 26). pnpm reads pnpm_config_* settings from
  # the environment over pnpm-workspace.yaml, so a shell that exported
  # pnpm_config_minimum_release_age=0 (as the guide advised) resolved bootstrap's
  # install without the age rule. Network tools are stubs; pnpm logs its env.
  local d="$WORK/stack-foldkit-bootstrap-policy/demo-app" setting policy=()
  mkdir -p "$d.stub" "$WORK/home" || return 1
  cat > "$d.stub/pnpm" <<'STUB'
#!/bin/sh
[ "$1" != install ] || env > "$FK_ENV"
exit 1
STUB
  printf '#!/bin/sh\nexit 1\n' > "$d.stub/node"
  chmod +x "$d.stub/pnpm" "$d.stub/node" || return 1
  fresh_copy "$d" || return 1
  for setting in $FK_POLICY_SETTINGS; do
    policy+=("pnpm_config_$setting=1" "PNPM_CONFIG_$(printf '%s' "$setting" | tr '[:lower:]' '[:upper:]')=1")
  done
  # run_bootstrap's sandbox, with the settings in bootstrap's environment.
  (cd "$d" && env "${policy[@]}" pnpm_config_store_dir=/tmp/kept FK_ENV="$d.env" PATH="$d.stub:$(printenv PATH)" \
    HOME="$WORK/home" ./bootstrap --name "Demo App" --stack foldkit --yes </dev/null >"$d.out" 2>&1) \
    || fail "bootstrap exited $?: $(tail -5 "$d.out")" || return 1
  assert_contains "$d.out" "pnpm install failed" || return 1
  assert_contains "$d.env" "pnpm_config_store_dir=/tmp/kept" || return 1
  fk_policy_kept "$d.env"
}
test_stack_foldkit_scripts_need_node_22() {
  # Regression test (#20 item 14). The guard, coverage.sh and vendor-foldkit.sh
  # run the Node on PATH, not the one pnpm pins; with none, or one too old for the
  # checkers, they died on "command not found" or a syntax error. Each now stops
  # before any other command and says what to install.
  local d="$WORK/stack-foldkit-node/demo" script version rc
  foldkit_files "$d" || fail "copying the pack failed" || return 1
  mkdir -p "$d.bin" || return 1
  cat > "$d.bin/node" <<'STUB'
#!/bin/sh
# Answers --version with $FK_NODE_VERSION (unset: fails silently, like no node);
# logs any other call.
if [ "$1" = --version ] && [ -n "${FK_NODE_VERSION:-}" ]; then echo "$FK_NODE_VERSION"; exit 0; fi
[ "$1" = --version ] || echo "node $*" >> "$FK_LOG"
exit 99
STUB
  cat > "$d.bin/pnpm" <<'STUB'
#!/bin/sh
echo "pnpm $*" >> "$FK_LOG"
STUB
  cat > "$d.bin/git" <<'STUB'
#!/bin/sh
echo "git $*" >> "$FK_LOG"
exit 1
STUB
  chmod +x "$d.bin/node" "$d.bin/pnpm" "$d.bin/git" || return 1
  for version in v20.11.1 v21.7.3 ''; do
    for script in scripts/check.d/foldkit.sh scripts/coverage.sh scripts/vendor-foldkit.sh; do
      rm -f "$d.log"
      (cd "$d" && FK_NODE_VERSION="$version" FK_LOG="$d.log" PATH="$d.bin:$(printenv PATH)" bash "$script") >"$d.out" 2>&1; rc=$?
      assert_exit 1 "$rc" || { echo "    ($script with node ${version:-missing})"; return 1; }
      assert_contains "$d.out" "Node.js 22 or newer must be on PATH" || return 1
      assert_contains "$d.out" "(found: ${version:-none})" || return 1
      assert_absent "$d.log" || { echo "    $script ran: $(cat "$d.log")"; return 1; }
    done
  done
}
test_stack_foldkit_network_steps_time_out() {
  # Regression test (#20 item 24). Offline with a cold cache, bootstrap's pnpm
  # install, the guard's lockfile check and vendoring's git clone could wait
  # without end (a 420-second hang was seen). Stubs that sleep past a one-second
  # limit stand in for the network.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  command -v python3 >/dev/null 2>&1 || { skip "python3 not installed"; return; }
  local d="$WORK/stack-foldkit-timeouts/demo" b="$WORK/stack-foldkit-timeouts/boot/demo-app" rc
  { foldkit_files "$d" && fk_installed "$d" && fk_stub_pnpm "$d.bin"; } || fail "fixture setup failed" || return 1
  fk_guard "$d" FOLDKIT_TEST_TIMEOUT=1 FK_PNPM_INSTALL='exec sleep 5'; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard.out" "the lockfile check timed out after 1s (offline?" || return 1
  mkdir -p "$d.git" && cat > "$d.git/git" <<'STUB' && chmod +x "$d.git/git" || return 1
#!/bin/sh
# Hangs on clone, as git can offline.
[ "$1" = -c ] && shift 2
[ "$1" != clone ] || exec sleep 5
exit 1
STUB
  (cd "$d" && FOLDKIT_TEST_TIMEOUT=1 PATH="$d.git:$(printenv PATH)" bash scripts/vendor-foldkit.sh) >"$d.out" 2>&1; rc=$?
  [ "$rc" -ne 0 ] || fail "vendor-foldkit.sh passed with git hanging" || return 1
  assert_contains "$d.out" "vendor-foldkit: git clone timed out after 1s (offline?)" || return 1
  assert_absent "$d/repos" || return 1
  # Bootstrap's install; node fails, so vendoring stays offline too.
  printf '#!/bin/sh\nexit 1\n' > "$d.bin/node" && chmod +x "$d.bin/node" || return 1
  fresh_copy "$b" || return 1
  FOLDKIT_TEST_TIMEOUT=1 FK_PNPM_INSTALL='exec sleep 5' PATH="$d.bin:$(printenv PATH)" \
    run_bootstrap "$b" --name "Demo App" --stack foldkit --yes || fail "bootstrap exited $?: $(tail -5 "$b.out")" || return 1
  assert_contains "$b.out" "pnpm install timed out after 1s (offline?)" || return 1
  # R5: an alarm on an execed leader left its real descendants alive, holding
  # captured stdout open beyond the limit. Exercise the public callers as well
  # as the helper's status/signal contract; no network or process-name killing.
  rm "$d.bin/node" || return 1
  python3 - "$d" "$REPO/template/stacks/foldkit/after-bootstrap" <<'PROBE'
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

project = Path(sys.argv[1])
hook = sys.argv[2]
worker = Path(str(project) + '.worker.py')
pids = Path(str(project) + '.pids')
worker.write_text('''import os, time
from pathlib import Path
child = os.fork()
if child == 0:
    time.sleep(6)
    os._exit(0)
Path(os.environ['FK_PIDS']).write_text(str(os.getpid()) + ' ' + str(child))
if os.environ.get('FK_EARLY') == '1':
    os._exit(0)
os.waitpid(child, 0)
''')
env = dict(os.environ, PATH=str(project) + '.bin:' + os.environ['PATH'],
           FOLDKIT_TEST_TIMEOUT='1', FK_WORKER=str(worker), FK_PIDS=str(pids),
           FK_PNPM_INSTALL='exec python3 "$FK_WORKER"', CHECK_CI='1')
unrelated = subprocess.Popen(['sleep', '30'])

def live(pid):
    state = subprocess.run(['ps', '-o', 'stat=', '-p', str(pid)],
                           stdout=subprocess.PIPE, text=True).stdout.strip()
    return bool(state) and not state.startswith('Z')

def cleanup():
    if pids.exists():
        for pid in map(int, pids.read_text().split()):
            if live(pid):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

def run(args, expected, text='', extra=None, interrupt=None, input_text=None):
    cleanup()
    pids.unlink(missing_ok=True)
    started = time.monotonic()
    proc = subprocess.Popen(args, cwd=project, env=dict(env, **(extra or {})),
                            stdin=subprocess.PIPE if input_text is not None else None,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        if interrupt is not None:
            until = time.monotonic() + 3
            while not pids.exists() and time.monotonic() < until:
                time.sleep(.02)
            assert pids.exists(), 'command did not start before interruption'
            proc.send_signal(interrupt)
        output = proc.communicate(input=input_text, timeout=8)[0]
        elapsed = time.monotonic() - started
        assert elapsed < 3.5, f'{args}: descendants kept output open for {elapsed:.2f}s: {output}'
        assert proc.returncode == expected, f'{args}: exit {proc.returncode}, expected {expected}: {output}'
        assert text in output, f'{args}: missing {text!r}: {output}'
        if pids.exists():
            until = time.monotonic() + 1
            owned = list(map(int, pids.read_text().split()))
            while any(live(pid) for pid in owned) and time.monotonic() < until:
                time.sleep(.02)
            assert not any(live(pid) for pid in owned), f'owned process survived: {owned}'
        assert unrelated.poll() is None, 'unrelated process was killed'
    finally:
        if proc.poll() is None:
            proc.kill()
        cleanup()
        proc.communicate()

try:
    # This fails against the old alarm wrapper in its elapsed-time assertion.
    run(['bash', 'scripts/check.d/foldkit.sh'], 1, 'lockfile check timed out after 1s')
    # An exited leader must not leave a capture-blocking descendant until 6s.
    run(['bash', 'scripts/check.d/foldkit.sh'], 0, extra={'FK_EARLY': '1'})
    helper = ['perl', 'scripts/bounded-command.pl', '1']
    run(helper + ['sh', '-c', 'printf bounded-ok'], 0, 'bounded-ok')
    run(helper + ['sh', '-c', 'read -r value; printf "%s" "$value"'], 0,
        'inherited input', input_text='inherited input\n')
    run(helper + ['python3', '-c', 'import sys; print(sys.argv[1])', 'literal $(false); *'],
        0, 'literal $(false); *')
    run(helper + ['sh', '-c', 'exit 23'], 23)
    run(helper + ['sh', '-c', 'kill -TERM $$'], 143)
    run(helper + ['python3', str(worker)], 142)
    run(helper + ['python3', str(worker)], 0, extra={'FK_EARLY': '1'})
    for sig in [signal.SIGHUP, signal.SIGINT, signal.SIGTERM]:
        run(helper + ['python3', str(worker)], 128 + sig, interrupt=sig)
        run(['bash', 'scripts/check.d/foldkit.sh'], 128 + sig, interrupt=sig)

    git = Path(str(project) + '.bin/git')
    git.write_text('''#!/bin/sh
[ -z "${FK_GIT_LOG:-}" ] || echo called >> "$FK_GIT_LOG"
[ "$1" != -c ] || shift 2
if [ "$1" = clone ]; then
  [ "$FK_GIT_PHASE" != clone ] || exec python3 "$FK_WORKER"
  for dest do :; done
  mkdir -p "$dest"
elif [ "$3" = rev-parse ]; then
  echo "$FK_COMMIT"
elif [ "$3" = sparse-checkout ]; then
  exec python3 "$FK_WORKER"
else
  exit 1
fi
''')
    git.chmod(0o755)
    commit = (project / '.foldkit-ref').read_text().split()[1]
    for phase, message in [('clone', 'git clone'), ('sparse', 'the sparse checkout')]:
        run(['bash', 'scripts/vendor-foldkit.sh'], 142, message + ' timed out after 1s',
            extra={'FK_GIT_PHASE': phase, 'FK_COMMIT': commit})
    for sig in [signal.SIGHUP, signal.SIGINT, signal.SIGTERM]:
        run(['bash', 'scripts/vendor-foldkit.sh'], 128 + sig, interrupt=sig,
            extra={'FK_GIT_PHASE': 'clone', 'FK_COMMIT': commit})
    # A signal to the hook itself must clean up its install and stop before Git.
    git_log = Path(str(project) + '.git-calls')
    for sig in [signal.SIGHUP, signal.SIGINT, signal.SIGTERM]:
        git_log.unlink(missing_ok=True)
        run(['sh', hook], 128 + sig, interrupt=sig,
            extra={'FK_GIT_LOG': str(git_log), 'FK_GIT_PHASE': 'clone'})
        assert not git_log.exists(), 'bootstrap continued to vendoring after interruption'
        # Also interrupt the hook after install succeeded and vendoring started.
        run(['sh', hook], 128 + sig, interrupt=sig,
            extra={'FK_PNPM_INSTALL': ':', 'FK_GIT_PHASE': 'clone', 'FK_COMMIT': commit})
finally:
    cleanup()
    unrelated.terminate()
    unrelated.wait()
PROBE
}
test_stack_foldkit_supervisor_outcomes_are_unambiguous() {
  # Opus 6: helper failures and reserved-looking command exits are not pnpm
  # policy errors, timeouts or cancellation. Validate outcomes even on exit 0.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  command -v python3 >/dev/null 2>&1 || { skip "python3 not installed"; return; }
  local d="$WORK/stack-foldkit-outcomes/demo"
  { foldkit_files "$d" && fk_installed "$d" && fk_stub_pnpm "$d.bin"; } || fail "fixture setup failed" || return 1
  python3 - "$d" "$REPO/template/stacks/foldkit/after-bootstrap" <<'PROBE'
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys

project = Path(sys.argv[1])
hook = sys.argv[2]
bin_dir = Path(str(project) + '.bin')
helper = project / 'scripts/bounded-command.pl'
original = helper.read_text()
status_file = Path(str(project) + '.outcome')
pnpm_log = Path(str(project) + '.pnpm-log')
git_log = Path(str(project) + '.git-log')
commit = (project / '.foldkit-ref').read_text().split()[1]
git_driver = Path(str(project) + '.git.py')
git_driver.write_text('''import os, pathlib, subprocess, sys, time
with open(os.environ['FK_GIT_LOG'], 'a') as log: log.write('called\\n')
a = sys.argv[1:]
if a[:1] == ['-c']: a = a[2:]
if a[:1] == ['clone'] or (len(a) > 2 and a[2] == 'sparse-checkout'):
    mode = os.environ.get('FK_GIT_MODE', '0')
    if mode == 'sleep': time.sleep(5)
    elif mode == 'signal': os.kill(os.getpid(), 15)
    elif mode == 'missing':
        try: os.execv('/nonexistent-foldkit-command', ['missing'])
        except OSError as error:
            print('cannot run nonexistent-foldkit-command: ' + str(error), file=sys.stderr)
            sys.exit(127)
    else:
        code = int(mode)
        if code: sys.exit(code)
    if a[:1] == ['clone']: pathlib.Path(a[-1]).mkdir()
elif len(a) > 2 and a[2] == 'rev-parse': print(os.environ['FK_COMMIT'])
else: sys.exit(1)
''')
(bin_dir / 'git').write_text('#!/bin/sh\nexec python3 "$FK_GIT_DRIVER" "$@"\n')
(bin_dir / 'git').chmod(0o755)
env = dict(os.environ, PATH=str(bin_dir) + ':' + os.environ['PATH'], CHECK_CI='1',
           FOLDKIT_TEST_TIMEOUT='1', FK_PNPM_LOG=str(pnpm_log), FK_GIT_LOG=str(git_log),
           FK_GIT_DRIVER=str(git_driver), FK_COMMIT=commit)
callers = {'guard': ['bash', 'scripts/check.d/foldkit.sh'],
           'hook': ['sh', hook], 'vendor': ['bash', 'scripts/vendor-foldkit.sh']}

def run(args, expected, text='', extra=None):
    result = subprocess.run(args, cwd=project, env=dict(env, **(extra or {})),
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, timeout=10)
    assert result.returncode == expected, (args, result.returncode, expected, result.stdout)
    assert text in result.stdout, (args, text, result.stdout)
    return result.stdout

def caller(name, expected, text='', extra=None, vendor_expected=None):
    git_log.unlink(missing_ok=True)
    pnpm_log.unlink(missing_ok=True)
    output = run(callers[name], expected, text, extra)
    if name == 'hook' and vendor_expected is not None:
        assert git_log.exists() == vendor_expected, (name, vendor_expected, output)
    return output

def direct(args, expected, record, text='', extra=None):
    status_file.write_text('stale result\n')
    output = run(['perl', str(helper), '--status-file', str(status_file), '1', *args],
                 expected, text, extra)
    assert status_file.read_text() == record + '\n', (record, status_file.read_text())
    return output

try:
    # The helper's optional protocol preserves ordinary exit codes exactly.
    for code in [0, 23, 125, 127, 129, 130, 142, 143]:
        direct(['sh', '-c', f'exit {code}'], code, f'exit {code}')
    direct(['/nonexistent-foldkit-command'], 127, 'exit 127', 'cannot run')
    for sig in [signal.SIGHUP, signal.SIGINT, signal.SIGTERM, signal.SIGALRM, signal.SIGPIPE]:
        direct(['sh', '-c', f'kill -{sig.value} $$'], 128 + sig, f'signal {128 + sig}')
    direct(['sleep', '5'], 142, 'timeout 142')
    # A reportable setup error is internal; no command can start.
    status_file.write_text('stale result\n')
    run(['perl', str(helper), '--status-file', str(status_file), '0', 'false'], 125, 'usage:')
    assert status_file.read_text() == 'internal 125\n'
    # Force the leader's waitpid failure through Perl's documented override
    # seam. The supervisor's real wait/reap remains unchanged.
    module = Path(str(project) + '.wait-module')
    module.mkdir()
    (module / 'FailedWait.pm').write_text('''package FailedWait;
use Errno qw(ECHILD);
BEGIN {
    my $supervisor = $$;
    *CORE::GLOBAL::waitpid = sub ($$) {
        if ($$ != $supervisor) { $! = ECHILD; return -1; }
        return CORE::waitpid($_[0], $_[1]);
    };
}
1;
''')
    direct(['sleep', '5'], 125, 'internal 125', 'command supervisor failed',
           {'PERL5OPT': '-MFailedWait', 'PERL5LIB': str(module)})
    # Without --status-file the old argv/stdin/exit API remains available.
    run(['perl', str(helper), '1', 'sh', '-c', 'exit 23'], 23)

    for name in callers:
        caller(name, 0, vendor_expected=True)
        for code in [125, 127, 129, 130, 142, 143]:
            extra = {'FK_GIT_MODE': str(code)} if name == 'vendor' else {'FK_PNPM_INSTALL': f'exit {code}'}
            expected = code if name == 'vendor' else (0 if name == 'hook' else 1)
            output = caller(name, expected, f'exit {code}', extra, vendor_expected=True)
            assert 'timed out' not in output and 'tampered' not in output, output
        extra = {'FK_GIT_MODE': 'signal'} if name == 'vendor' else {'FK_PNPM_INSTALL': 'kill -TERM $$'}
        caller(name, 143, extra=extra, vendor_expected=False)
        extra = {'FK_GIT_MODE': 'sleep'} if name == 'vendor' else {'FK_PNPM_INSTALL': 'exec sleep 5'}
        caller(name, 142 if name == 'vendor' else (0 if name == 'hook' else 1),
               'timed out after 1s', extra, vendor_expected=True)
        caller(name, 125 if name == 'vendor' else 1, 'supervisor failed',
               {'FOLDKIT_TEST_TIMEOUT': '0'}, vendor_expected=False)
        extra = {'FK_GIT_MODE': 'missing'} if name == 'vendor' else {'FK_PNPM_INSTALL': 'exec /nonexistent-foldkit-command'}
        output = caller(name, 127 if name == 'vendor' else (0 if name == 'hook' else 1),
                        'nonexistent-foldkit-command', extra, vendor_expected=True)
        assert 'tampered' not in output and 'timed out' not in output, output

    # Missing Perl is distinct from missing pnpm or an offline registry. Use a
    # genuinely Perl-free PATH, not a perl stub returning command-not-found.
    bare = Path(str(project) + '.without-perl')
    bare.mkdir()
    for command in ['dirname', 'node', 'pnpm']:
        source = bin_dir / command if (bin_dir / command).exists() else Path(shutil.which(command))
        (bare / command).symlink_to(source)
    for name, args in callers.items():
        git_log.unlink(missing_ok=True)
        pnpm_log.unlink(missing_ok=True)
        absolute = [shutil.which(args[0]), *args[1:]]
        output = run(absolute, 1, 'Perl is not installed', {'PATH': str(bare)})
        assert not git_log.exists() and not pnpm_log.exists(), output

    # Compile/core-module failure never reaches the helper's reporting code.
    helper.write_text('use MissingFoldkitCoreModule;\n')
    for name in callers:
        caller(name, 1, 'supervisor returned no valid outcome', vendor_expected=False)
    helper.write_text(original)

    # Even apparent success cannot bypass validation. Stub only the helper,
    # keeping each caller real, and cover complete/duplicate/trailing records.
    invalid = [(None, 0), (None, 2), (None, 255), ('exit 0', 0), ('exit 0\nexit 0\n', 0),
               ('exit 0\n\n', 0), ('exit 0\njunk', 0), ('exit 1\n', 0), ('exit 0\n', 1),
               ('exit 00\n', 0), ('exit -1\n', 0), ('signal 0\n', 0), ('signal 128\n', 128),
               ('timeout 0\n', 0), ('timeout 142\n', 0), ('internal 0\n', 0),
               ('internal 125\n', 0), ('exit 256\n', 0), ('ex\0it 0\n', 0),
               ('exit 0\0\n', 0), ('exit 0\n\0', 0)]
    for record, code in invalid:
        text = 'use strict; use warnings;\nmy $path = $ARGV[1];\n'
        if record is not None:
            # Hex avoids Perl interpolation, escaping and arbitrary test code.
            text += f'open(my $out, ">", $path) or die $!; print $out pack("H*", "{record.encode().hex()}"); close $out;\n'
        text += f'print STDERR "controlled startup/output failure\\n"; exit {code};\n'
        helper.write_text(text)
        for name in callers:
            output = caller(name, 1, 'supervisor returned no valid outcome', vendor_expected=False)
            assert 'tampered' not in output and 'timed out' not in output, output

    helper.write_text('unlink $ARGV[1]; exit 0;\n')
    for name in callers:
        caller(name, 1, 'supervisor returned no valid outcome', vendor_expected=False)

    # The second vendoring invocation must not reuse the clone's valid record.
    helper.write_text('''use strict; use warnings;
my ($flag, $path, $limit) = splice(@ARGV, 0, 3);
if (grep { $_ eq 'clone' } @ARGV) {
    system @ARGV;
    open(my $out, '>', $path) or die $!;
    print $out "exit 0\\n"; close $out;
}
exit 0;
''')
    caller('vendor', 1, 'supervisor returned no valid outcome')
finally:
    helper.write_text(original)
print('supervisor outcome probes passed')
PROBE
}
test_stack_foldkit_supervisor_signal_boundaries_clean_up() {
  # Opus 7: cancellation just outside eval must retain its status and cleanup;
  # a dead supervisor must not make the leader's report write skip EOF cleanup.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  command -v python3 >/dev/null 2>&1 || { skip "python3 not installed"; return; }
  local d="$WORK/stack-foldkit-signal-boundaries/demo"
  { foldkit_files "$d" && fk_installed "$d" && fk_stub_pnpm "$d.bin"; } || fail "fixture setup failed" || return 1
  python3 - "$d" "$REPO/template/stacks/foldkit/after-bootstrap" <<'PROBE'
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

project = Path(sys.argv[1])
hook = sys.argv[2]
helper = project / 'scripts/bounded-command.pl'
source = helper.read_text().splitlines()
lines = {'before': source.index('my $ok = eval {') + 1,
         'after': source.index('my $error = $@;') + 1}
bin_dir = Path(str(project) + '.bin')
worker = Path(str(project) + '.worker.py')
pids = Path(str(project) + '.pids')
release = Path(str(project) + '.release')
status_file = Path(str(project) + '.outcome')
captured = Path(str(project) + '.captured-outcome')
git_log = Path(str(project) + '.git-log')
real_perl = shutil.which('perl')
worker.write_text('''import json, os, time
from pathlib import Path
child = os.fork()
if child == 0:
    time.sleep(8)
    os._exit(0)
Path(os.environ['FK_PIDS']).write_text(json.dumps([os.getppid(), os.getpid(), child]))
if os.environ.get('FK_WAIT') == '1':
    while not Path(os.environ['FK_RELEASE']).exists(): time.sleep(.01)
os._exit(0)
''')
debugger = Path(str(project) + '.debugger.pl')
debugger.write_text('''package DB;
our $fired = 0;
sub DB {
    my ($package, $file, $line) = caller;
    if (!$fired && $file =~ /bounded-command\\.pl$/ && $line == $ENV{FK_LINE}) {
        $fired = 1;
        kill $ENV{FK_SIGNAL}, $$;
    }
}
1;
''')
# The wrapper only selects Perl's debugger and preserves its real outcome for
# assertions after each caller removes its own private result file.
(bin_dir / 'perl').write_text('''#!/bin/sh
"$FK_REAL_PERL" -d "$@"
rc=$?
[ "$2" != --status-file ] || cat "$3" > "$FK_CAPTURE"
exit "$rc"
''')
(bin_dir / 'perl').chmod(0o755)
(bin_dir / 'git').write_text('''#!/bin/sh
echo called >> "$FK_GIT_LOG"
exec python3 "$FK_WORKER"
''')
(bin_dir / 'git').chmod(0o755)
env = dict(os.environ, PATH=str(bin_dir) + ':' + os.environ['PATH'], CHECK_CI='1',
           FOLDKIT_TEST_TIMEOUT='3', FK_REAL_PERL=real_perl, FK_CAPTURE=str(captured),
           FK_WORKER=str(worker), FK_PIDS=str(pids), FK_RELEASE=str(release),
           FK_GIT_LOG=str(git_log), FK_PNPM_INSTALL='exec python3 "$FK_WORKER"',
           PERL5DB=f'BEGIN {{ require q({debugger}) }}')
unrelated = subprocess.Popen(['sleep', '30'])

def live(pid):
    state = subprocess.run(['ps', '-o', 'stat=', '-p', str(pid)],
                           stdout=subprocess.PIPE, text=True).stdout.strip()
    return bool(state) and not state.startswith('Z')

def cleanup():
    if pids.exists():
        for pid in json.loads(pids.read_text()):
            if live(pid):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

def assert_clean():
    if pids.exists():
        owned = json.loads(pids.read_text())
        until = time.monotonic() + 1
        while any(live(pid) for pid in owned) and time.monotonic() < until:
            time.sleep(.01)
        assert not any(live(pid) for pid in owned), ('owned survivor', owned)
    assert unrelated.poll() is None, 'unrelated control was killed'

try:
    for boundary, line in lines.items():
        for sig in [signal.SIGHUP, signal.SIGINT, signal.SIGTERM]:
            for caller, args in {
                'helper': [real_perl, '-d', str(helper), '--status-file', str(status_file), '3', 'python3', str(worker)],
                'guard': ['bash', 'scripts/check.d/foldkit.sh'],
                'hook': ['sh', hook],
                'vendor': ['bash', 'scripts/vendor-foldkit.sh'],
            }.items():
                pids.unlink(missing_ok=True)
                git_log.unlink(missing_ok=True)
                captured.unlink(missing_ok=True)
                status_file.write_text('stale result\n')
                result = subprocess.run(args, cwd=project,
                                        env=dict(env, FK_LINE=str(line), FK_SIGNAL=str(sig.value)),
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                        text=True, timeout=8)
                assert result.returncode == 128 + sig, (boundary, sig, caller, result.returncode, result.stdout)
                outcome = status_file if caller == 'helper' else captured
                assert outcome.exists(), (boundary, sig, caller, result.stdout)
                assert outcome.read_text() == f'signal {128 + sig}\n', (caller, outcome.read_text())
                assert pids.exists() == (boundary == 'after'), (boundary, caller, result.stdout)
                if caller == 'hook':
                    assert not git_log.exists(), 'hook vendored after cancellation'
                assert_clean()

    # An executed command retains normal SIGPIPE handling.
    result = subprocess.run([real_perl, str(helper), '--status-file', str(status_file),
                             '1', 'sh', '-c', 'kill -PIPE $$; echo survived'],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=4)
    assert result.returncode == 141 and not result.stdout, result
    assert status_file.read_text() == 'signal 141\n'

    # SIGKILL ends the timer guarantee. Once the command returns, however, the
    # surviving leader must still reach EOF cleanup instead of dying on PIPE.
    pids.unlink(missing_ok=True)
    release.unlink(missing_ok=True)
    with Path(str(project) + '.kill.log').open('w') as log:
        proc = subprocess.Popen([real_perl, str(helper), '--status-file', str(status_file),
                                 '3', 'python3', str(worker)], cwd=project,
                                env=dict(env, FK_WAIT='1'), stdout=log, stderr=subprocess.STDOUT)
        try:
            until = time.monotonic() + 3
            while not pids.exists() and time.monotonic() < until:
                time.sleep(.01)
            assert pids.exists(), 'owned command did not start'
            proc.kill()
            proc.wait(timeout=3)
            release.touch()
            assert_clean()
            assert status_file.read_text() == '', 'killed supervisor fabricated an outcome'
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
finally:
    cleanup()
    unrelated.terminate()
    unrelated.wait()
print('supervisor signal boundary probes passed')
PROBE
}
test_stack_foldkit_vendoring_checks_the_release_commit() {
  # Regression test (#20 item 12; security review SE2). vendor-foldkit.sh trusted
  # the release tag, which can move, and deleted the clone's .git: repos/foldkit
  # then sat in this project's repository, and Foldkit's `prepare`
  # (simple-git-hooks) run there wrote this project's .git/hooks. A stub git
  # stands in for GitHub.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-vendor/demo" real_git commit pin rc
  real_git="$(command -v git)"
  { foldkit_files "$d" && git -C "$d" init -q; } || fail "fixture setup failed" || return 1
  read -r pin commit < "$d/.foldkit-ref" || fail "cannot read .foldkit-ref" || return 1
  mkdir -p "$d.bin" || return 1
  cat > "$d.bin/git" <<STUB && chmod +x "$d.bin/git" || return 1
#!/bin/sh
# clone: a new repository holding Foldkit's hook-installing package.json and
# agent files vendoring must drop; rev-parse HEAD: \$FK_COMMIT. Logs clones.
[ "\$1" = -c ] && shift 2
case "\$1" in
  clone) echo clone >> "\$FK_LOG"; for a; do dest="\$a"; done
    "$real_git" init -q "\$dest" || exit 1
    echo '{"scripts":{"prepare":"simple-git-hooks"},"simple-git-hooks":{"commit-msg":"exit 1"}}' > "\$dest/package.json"
    mkdir -p "\$dest/.claude" "\$dest/packages/app" || exit 1
    touch "\$dest/AGENTS.md" "\$dest/.mcp.json" "\$dest/.claude/settings.json" "\$dest/packages/app/CLAUDE.md"
    exit ;;
  -C) [ "\$3" = sparse-checkout ] && exit 0
    [ "\$3 \$4" = "rev-parse HEAD" ] && { echo "\$FK_COMMIT"; exit 0; } ;;
esac
exec "$real_git" "\$@"
STUB
  vendor() {  # $1 = the commit the tag names now
    rm -f "$d.log"
    (cd "$d" && FK_COMMIT="$1" FK_LOG="$d.log" PATH="$d.bin:$(printenv PATH)" bash scripts/vendor-foldkit.sh) >"$d.out" 2>&1
  }
  vendor 1111111111111111111111111111111111111111; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "the tag foldkit@$pin is commit 1111111111111111111111111111111111111111, but .foldkit-ref records $commit" || return 1
  assert_absent "$d/repos" || return 1
  vendor "$commit"; rc=$?
  assert_exit 0 "$rc" || { cat "$d.out"; return 1; }
  assert_exists "$d/repos/foldkit/.git" || return 1
  [ -z "$(find "$d/repos/foldkit" \( -name AGENTS.md -o -name CLAUDE.md -o -name .mcp.json -o -name .claude \) -print)" ] \
    || fail "vendoring kept Foldkit's agent files" || return 1
  # A hook installer run in the clone writes into the nearest .git above it, as
  # simple-git-hooks 2.14 does: the clone's own, not this project's.
  (cd "$d/repos/foldkit" && node -e 'const fs = require("fs"); const path = require("path"); let dir = process.cwd(); while (!fs.existsSync(path.join(dir, ".git"))) { dir = path.dirname(dir) } fs.mkdirSync(path.join(dir, ".git", "hooks"), { recursive: true }); fs.writeFileSync(path.join(dir, ".git", "hooks", "commit-msg"), "exit 1\n")') \
    || fail "the hook installer failed" || return 1
  assert_exists "$d/repos/foldkit/.git/hooks/commit-msg" || return 1
  assert_absent "$d/.git/hooks/commit-msg" || return 1
  # .foldkit-ref is read strictly, before any clone.
  printf '0.0.1 %s\n' "$commit" > "$d/.foldkit-ref"
  vendor "$commit"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" ".foldkit-ref records foldkit 0.0.1, package.json pins $pin" || return 1
  printf '%s %s\n# reviewed\n' "$pin" "$commit" > "$d/.foldkit-ref"
  vendor "$commit"; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" ".foldkit-ref must be one line" || return 1
  assert_absent "$d.log"
}
test_stack_foldkit_guide_examples_pass_the_checks() {
  # The guide is where a project learns the age-exemption and MCP forms (#20 item
  # 11 replaced its advice to export pnpm_config_minimum_release_age=0): its
  # examples, moved to this train, must pass check-pins and check-rules.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  local d="$WORK/stack-foldkit-guide/demo" guide pin rc
  { foldkit_files "$d" && fk_installed "$d"; } || fail "fixture setup failed" || return 1
  guide="$d/docs/guides/foldkit.md"
  pin="$(node -p 'require(process.argv[1]).dependencies.foldkit' "$d/package.json")" || return 1
  perl -ne 'print if /^```yaml$/ ... /^```$/ and !/^```/' "$guide" | PIN="$pin" perl -pe 's/\@\d+\.\d+\.\d+/\@$ENV{PIN}/' > "$d.exempt.yaml"
  grep -q '^minimumReleaseAgeExclude:$' "$d.exempt.yaml" || fail "the guide shows no minimumReleaseAgeExclude example" || return 1
  cat "$d.exempt.yaml" >> "$d/pnpm-workspace.yaml" || return 1
  fk_node "$d" scripts/check-pins.mjs; rc=$?
  assert_exit 0 "$rc" || { cat "$d.node.out"; return 1; }
  perl -ne 'print if /^  ```json$/ ... /^  ```$/ and !/^  ```/' "$guide" | sed 's/^  //' > "$d/.mcp.json"
  assert_contains "$d/.mcp.json" '"command": "node_modules/.bin/foldkit-devtools-mcp"' || return 1
  fk_node "$d" scripts/check-rules.mjs; rc=$?
  assert_exit 0 "$rc" || { cat "$d.node.out"; return 1; }
}
test_stack_foldkit_bootstrap_takes_its_offline_path() {
  # Every other pack's bootstrap runs in the light job; foldkit's ran only in the
  # heavy job, and nothing reached its hook's fallbacks. With pnpm and node
  # failing, bootstrap still finishes, says what to run, and keeps exec bits.
  local d="$WORK/stack-foldkit-offline/demo-app" t f
  mkdir -p "$d.stub" || return 1
  for t in pnpm node; do
    printf '#!/bin/sh\nexit 1\n' > "$d.stub/$t" && chmod +x "$d.stub/$t" || return 1
  done
  fresh_copy "$d" || return 1
  PATH="$d.stub:$(printenv PATH)" run_bootstrap "$d" --name "Demo App" --stack foldkit --yes \
    || fail "bootstrap exited $?: $(tail -20 "$d.out")" || return 1
  assert_contains "$d.out" "pnpm install failed" || return 1
  assert_contains "$d.out" "vendor-foldkit: Node.js 22 or newer must be on PATH (found: none)" || return 1
  assert_contains "$d.out" "Vendoring Foldkit failed (offline?)" || return 1
  assert_contains "$d/.bootstrapped" "with the foldkit stack pack" || return 1
  for f in scripts/coverage.sh scripts/check.d/foldkit.sh scripts/vendor-foldkit.sh; do
    [ -x "$d/$f" ] || fail "$f lost its exec bit" || return 1
  done
  assert_absent "$d/repos" || return 1
  # Without pnpm at all, the hook says how to install it (the system PATH has
  # bootstrap's own tools; pnpm lives elsewhere).
  PATH=/usr/bin:/bin command -v pnpm >/dev/null 2>&1 && return 0
  d="$WORK/stack-foldkit-offline/no-pnpm"
  fresh_copy "$d" || return 1
  (cd "$d" && PATH=/usr/bin:/bin ./bootstrap --name "Demo App" --stack foldkit --yes </dev/null >"$d.out" 2>&1) \
    || fail "bootstrap without pnpm exited $?: $(tail -20 "$d.out")" || return 1
  assert_contains "$d.out" "pnpm not found: install pnpm 12"
}
test_stack_foldkit_gitignore_covers_what_its_scripts_write() {
  # Regression test. vendor-foldkit.sh parks the old copy in repos/foldkit.previous
  # while it swaps in the new one; the pack ignored only /repos/foldkit/, so a run
  # interrupted there left a 20 MB tree git would commit.
  local d="$WORK/stack-foldkit-gitignore/demo" f
  mkdir -p "$d" && cp "$REPO/template/stacks/foldkit/gitignore" "$d/.gitignore" && git -C "$d" init -q || return 1
  assert_contains "$REPO/template/stacks/foldkit/files/scripts/vendor-foldkit.sh" 'repos/foldkit.previous' || return 1
  for f in repos/foldkit/README.md repos/foldkit.previous/README.md node_modules/x dist/index.html \
    coverage/coverage-summary.json test-results/x playwright-report/index.html blob-report/x tsconfig.tsbuildinfo; do
    git -C "$d" check-ignore -q -- "$f" || fail "git would commit $f" || return 1
  done
}
test_stack_foldkit_design_md_records_every_token() {
  # Regression test (design review). styles.css says its tokens come from
  # DESIGN.md, but the pack shipped none, so a new project kept the template's
  # placeholder DESIGN.md. The pack's own replaces it: no placeholder left, and
  # every token styles.css defines is named with its value.
  local d="$WORK/stack-foldkit-design/demo-app" t token value n=0
  mkdir -p "$d.stub" || return 1
  for t in pnpm node; do
    printf '#!/bin/sh\nexit 1\n' > "$d.stub/$t" && chmod +x "$d.stub/$t" || return 1
  done
  fresh_copy "$d" || return 1
  PATH="$d.stub:$(printenv PATH)" run_bootstrap "$d" --name "Demo App" --stack foldkit --yes \
    || fail "bootstrap exited $?: $(tail -20 "$d.out")" || return 1
  assert_contains "$d/DESIGN.md" "# Design System — Demo App" || return 1
  assert_not_contains "$d/DESIGN.md" '{{' || return 1
  while IFS='|' read -r token value; do
    n=$((n + 1))
    assert_contains "$d/DESIGN.md" "\`$token\`" || return 1
    assert_contains "$d/DESIGN.md" "\`$value\`" || return 1
  done < <(sed -n 's/^  \(--[a-z0-9-]*\): \(.*\);$/\1|\2/p' "$d/src/styles.css")
  [ "$n" -ge 10 ] || fail "found only $n tokens in src/styles.css" || return 1
  assert_contains "$d/DESIGN.md" "Light only" || return 1
  assert_contains "$d/DESIGN.md" "system-ui"
}
test_stack_foldkit_button_has_states_and_a_44px_target() {
  # Regression test (design review). .button had no :hover, :focus-visible or
  # :active rule and stood about 27px tall. A static check of styles.css: each
  # state has its own rule, through tokens; focus shows an accent outline 2px
  # off the button; the button is at least 44px each way; every var() names a
  # :root token.
  command -v node >/dev/null 2>&1 || { skip "node not installed"; return; }
  node -e '
    const css = require("fs").readFileSync(process.argv[1], "utf8").replace(/\/\*[\s\S]*?\*\//g, "")
    const rules = new Map()
    for (const [, selectors, body] of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
      const declarations = Object.fromEntries(body.split(";").filter(line => line.includes(":"))
        .map(line => [line.slice(0, line.indexOf(":")).trim(), line.slice(line.indexOf(":") + 1).trim()]))
      for (const selector of selectors.split(",")) rules.set(selector.trim(), { ...rules.get(selector.trim()), ...declarations })
    }
    const rule = selector => rules.get(selector) ?? {}
    const root = rule(":root")
    const resolve = value => value?.replace(/var\((--[\w-]+)\)/g, (_, name) => root[name] ?? "undefined")
    const px = value => { const m = /^([\d.]+)(px|rem)$/.exec(resolve(value) ?? ""); return m ? Number(m[1]) * (m[2] === "rem" ? 16 : 1) : 0 }
    const problems = []
    for (const state of [":hover", ":active"]) {
      const background = rule(".button" + state).background
      if (!/^var\(--[\w-]+\)$/.test(background ?? "") || background === rule(".button").background) problems.push(".button" + state + " needs its own background token, got " + background)
    }
    const focus = rule(".button:focus-visible")
    if (focus.outline !== "2px solid var(--color-accent)" || focus["outline-offset"] !== "2px") problems.push(".button:focus-visible needs outline: 2px solid var(--color-accent) and outline-offset: 2px, got " + JSON.stringify(focus))
    for (const size of ["min-height", "min-width"]) {
      if (!/^var\(--[\w-]+\)$/.test(rule(".button")[size] ?? "") || px(rule(".button")[size]) < 44) problems.push(".button " + size + " must be a token of at least 44px, got " + rule(".button")[size])
    }
    for (const [, name] of css.matchAll(/var\((--[\w-]+)\)/g)) if (root[name] === undefined) problems.push("var(" + name + ") is not a :root token")
    if (problems.length > 0) { console.error(problems.join("\n")); process.exit(1) }
  ' "$REPO/template/stacks/foldkit/files/src/styles.css" >"$WORK/foldkit-button.out" 2>&1 \
    || fail "styles.css: $(cat "$WORK/foldkit-button.out")"
}
test_stack_foldkit_ship_gate_runs_every_ci_gate() {
  # Regression test. Neither gate checked that the named journeys ran: Playwright
  # exits 0 when a journey is skipped. SHIP_GATE runs CI's gate steps in CI's
  # order, and both read the journeys report right after the Playwright run
  # (Playwright empties test-results/ when a run starts, so it is that run's).
  local gate steps
  gate="$(sed -n 's/^SHIP_GATE=//p' "$REPO/template/stacks/foldkit/commands")"
  [ -n "$gate" ] || fail "no SHIP_GATE in the foldkit pack" || return 1
  # Every single-line run: step but the browser install; the PR-only ratchet is a block.
  steps="$(sed -n 's/^ *run: //p' "$REPO/template/stacks/foldkit/files/.github/workflows/ci.yml" \
    | grep -v -e '^|' -e '^pnpm exec playwright install ' | awk 'NR > 1 { printf " && " } { printf "%s", $0 }')"
  [ "$steps" = "$gate" ] || fail "SHIP_GATE ($gate) does not run ci.yml's gate steps in order ($steps)" || return 1
  case " && $gate && " in
    *" && pnpm exec playwright test && node scripts/coverage-tiers.mjs --journeys && "*) ;;
    *) fail "SHIP_GATE must check the journeys right after pnpm exec playwright test: $gate" ;;
  esac
}
test_stack_foldkit_template_ci_matches_the_pack() {
  # The heavy job's pnpm is the version new projects pin, and both workflows pin
  # the same pnpm/setup commit.
  local want sha
  want="$(sed -n 's/.*"packageManager": "pnpm@\([0-9.]*\)".*/\1/p' "$REPO/template/stacks/foldkit/files/package.json")"
  [ -n "$want" ] || fail "no pnpm@ pin in the pack's package.json" || return 1
  grep -qF "version: \"$want\"" "$REPO/.github/workflows/template-selftest.yml" \
    || fail "template-selftest.yml's pnpm/setup is not pnpm $want" || return 1
  sha="$(sed -n 's/.*uses: pnpm\/setup@\([0-9a-f]\{40\}\).*/\1/p' "$REPO/template/stacks/foldkit/files/.github/workflows/ci.yml")"
  [ -n "$sha" ] || fail "the pack's ci.yml does not pin pnpm/setup by commit" || return 1
  grep -qF "pnpm/setup@$sha" "$REPO/.github/workflows/template-selftest.yml" \
    || fail "the two workflows pin different pnpm/setup commits"
}
test_heavy_stack_foldkit_project_is_green_on_first_run() {
  # The whole new-project gate, for real: bootstrap (its hook installs the pack's
  # locked tree, patching tsc, and vendors Foldkit), then check.sh, coverage.sh,
  # the Playwright journeys and the production build.
  local d="$WORK/heavy-foldkit/demo-app" why key f pw_deps=""
  why="$(foldkit_heavy_ready)"
  [ -z "$why" ] || { skip "$why"; return; }
  foldkit_project "$d" "Demo App" || return 1
  assert_contains "$d/package.json" '"name": "demo_app"' || return 1
  assert_contains "$d/package.json" '"description": "Demo App"' || return 1
  assert_contains "$d/src/build-info.ts" "export const PROJECT_NAME = 'Demo App'" || return 1
  assert_exists "$d/pnpm-lock.yaml" || return 1
  assert_exists "$d/.github/workflows/ci.yml" || return 1
  assert_absent "$d/.github/workflows/ci.yml.example" || return 1
  assert_absent "$d/template" || return 1
  assert_contains "$d/.bootstrapped" "with the foldkit stack pack" || return 1
  assert_contains "$d/TESTING.md" "Tests: \`pnpm exec vitest run\`" || return 1
  assert_contains "$d/CLAUDE.md" "docs/guides/foldkit.md" || return 1
  assert_contains "$d.out" "Installed the locked dependencies" || return 1
  cmp -s "$REPO/template/stacks/foldkit/files/pnpm-lock.yaml" "$d/pnpm-lock.yaml" || fail "the install changed the pack's lockfile" || return 1
  (cd "$d" && stack_env pnpm exec tsc --version) | grep -q '+effect-tsgo' || fail "tsc is not patched after bootstrap" || return 1
  [ "$(cat "$d/repos/foldkit/.vendored-version" 2>/dev/null)" = "$(node -p 'require(process.argv[1]).dependencies.foldkit' "$d/package.json")" ] \
    || fail "repos/foldkit is not the pinned release: $(tail -5 "$d.out")" || return 1
  [ -z "$(find "$d/repos/foldkit" \( -name AGENTS.md -o -name CLAUDE.md -o -name .mcp.json -o -name .claude -o -name .agents -o -path "$d/repos/foldkit/repos" \) -print)" ] \
    || fail "the vendored Foldkit carries agent files or its Effect copy" || return 1
  # repos/foldkit is its own repository, checked out at the commit .foldkit-ref records.
  assert_exists "$d/repos/foldkit/.git" || return 1
  [ "$(git -C "$d/repos/foldkit" rev-parse HEAD 2>/dev/null)" = "$(cut -d' ' -f2 "$d/.foldkit-ref")" ] \
    || fail "repos/foldkit is not at .foldkit-ref's commit" || return 1
  (cd "$d" && git add -A && git commit -qm init) || fail "commit failed" || return 1
  # No placeholder survives in what git commits (node_modules and repos/ are ignored).
  for key in $(sed -n 's/^\([A-Z_]*\)=.*/\1/p' "$REPO/template/stacks/foldkit/commands") PROJECT_NAME PACKAGE_NAME YEAR; do
    ! (cd "$d" && git grep -qF "{{$key") || fail "{{$key is left in: $(cd "$d" && git grep -lF "{{$key" | tr '\n' ' ')" || return 1
  done
  # git commits every pack file and ignores every build artifact.
  pack_files foldkit > "$d.expected" || return 1
  assert_committed "$d" "$d.expected" || return 1
  for f in node_modules/x dist/index.html coverage/coverage-summary.json test-results/x playwright-report/index.html \
    blob-report/x tsconfig.tsbuildinfo repos/foldkit/README.md; do
    git -C "$d" check-ignore -q -- "$f" || fail "git would commit the build artifact $f" || return 1
  done
  [ "${CI:-}" != "true" ] || pw_deps="--with-deps"
  (cd "$d" && stack_env env EDITORCONFIG_CHECKER_BIN=/nonexistent ./scripts/check.sh \
    && stack_env ./scripts/coverage.sh \
    && stack_env pnpm exec playwright install $pw_deps chromium \
    && stack_env pnpm exec playwright test \
    && stack_env node scripts/coverage-tiers.mjs --journeys \
    && stack_env pnpm build) >"$d.gate.out" 2>&1 \
    || fail "the new project's own gate failed: $(tail -25 "$d.gate.out")" || return 1
  assert_contains "$d.gate.out" "OK: checks passed." || return 1
  assert_contains "$d.gate.out" "coverage-tiers: ok" || return 1
  # Every named journey ran and passed, read from Playwright's own JSON report
  # (a "1 passed" anywhere in the output proved neither).
  (cd "$d" && node -e '
    const report = require("./test-results/journeys.json")
    const specs = suite => [...suite.specs, ...(suite.suites ?? []).flatMap(specs)]
    const all = report.suites.flatMap(specs)
    if (report.errors.length > 0) throw new Error("the run reported errors: " + JSON.stringify(report.errors))
    for (const title of require("./coverage-tiers.json").journeys) {
      const statuses = all.filter(spec => spec.title === title).flatMap(spec => spec.tests).flatMap(test => test.results).map(result => result.status)
      if (statuses.length === 0 || statuses.some(status => status !== "passed")) throw new Error(title + ": " + JSON.stringify(statuses))
      console.log("journey passed: " + title)
    }') >"$d.journeys.out" 2>&1 || fail "a named journey did not pass: $(cat "$d.journeys.out")" || return 1
  [ -z "$(git -C "$d" status --porcelain)" ] || fail "the gate left files git would commit: $(git -C "$d" status --porcelain | head -5)"
}
test_heavy_stack_foldkit_longest_name_passes_guards_and_tests() {
  # 50 characters, the most validate-name allows: Oxfmt must accept
  # src/build-info.ts as bootstrap wrote it, and the tests must pass.
  local d="$WORK/heavy-foldkit-long/proj" name="Acme Example Inventory Reconciliation Service Ok12" why
  why="$(foldkit_heavy_ready)"
  [ -z "$why" ] || { skip "$why"; return; }
  [ "${#name}" = 50 ] || fail "the test name is ${#name} characters, not 50" || return 1
  foldkit_project "$d" "$name" || return 1
  (cd "$d" && stack_env bash scripts/check.d/foldkit.sh && stack_env pnpm exec vitest run) \
    >"$d.gate.out" 2>&1 || fail "the foldkit guards or tests failed: $(tail -25 "$d.gate.out")"
}
test_heavy_stack_foldkit_version_bump_keeps_the_gate_green() {
  # gstack /ship writes VERSION and package.json's version (as
  # JSON.stringify(p, null, 2) + "\n"). The lockfile holds neither, so the frozen
  # install still passes, the guards pass, and the build shows the new version.
  local d="$WORK/heavy-foldkit-bump/demo" why pw_deps=""
  why="$(foldkit_heavy_ready)"
  [ -z "$why" ] || { skip "$why"; return; }
  foldkit_project "$d" demo || return 1
  printf '0.1.0\n' > "$d/VERSION"
  fk_json "$d/package.json" 'c.version = "0.1.0"' || return 1
  (cd "$d" && stack_env pnpm install --frozen-lockfile && stack_env bash scripts/check.d/foldkit.sh \
    && stack_env pnpm build) >"$d.gate.out" 2>&1 || fail "the gate failed after a version bump: $(tail -25 "$d.gate.out")" || return 1
  cmp -s "$REPO/template/stacks/foldkit/files/pnpm-lock.yaml" "$d/pnpm-lock.yaml" || fail "the bump changed pnpm-lock.yaml" || return 1
  grep -qF '0.1.0' "$d"/dist/assets/*.js || fail "the build does not carry VERSION 0.1.0" || return 1
  # Regression test. A gstack MICRO release writes VERSION 0.1.0.1 and leaves
  # package.json at its npm form, 0.1.0; the page said "Version unknown". The
  # E2E journey compares the page with package.json's version.
  printf '0.1.0.1\n' > "$d/VERSION"
  [ "${CI:-}" != "true" ] || pw_deps="--with-deps"
  (cd "$d" && stack_env bash scripts/check.d/foldkit.sh && stack_env pnpm exec playwright install $pw_deps chromium \
    && stack_env pnpm exec playwright test && stack_env node scripts/coverage-tiers.mjs --journeys) >"$d.micro.out" 2>&1 \
    || fail "the gate failed on the MICRO VERSION 0.1.0.1: $(tail -25 "$d.micro.out")"
}
test_heavy_stack_foldkit_guards_fail_closed() {
  # Each guard fails closed on the change it exists to stop, and passes again
  # once the change is reverted.
  local d="$WORK/heavy-foldkit-guards/demo" why rc pin all
  why="$(foldkit_heavy_ready)"
  [ -z "$why" ] || { skip "$why"; return; }
  foldkit_project "$d" demo || return 1
  (cd "$d" && git add -A && git commit -qm init) || fail "commit failed" || return 1
  guard() { (cd "$d" && stack_env bash scripts/check.d/foldkit.sh) >"$d.guard.out" 2>&1; }
  guard || fail "the guard failed on a fresh project: $(tail -20 "$d.guard.out")" || return 1
  expect_guard_failure() {  # $1 = text the failure must contain, $2 = what changed
    guard; rc=$?
    [ "$rc" -ne 0 ] || fail "the guard passed after: $2" || return 1
    assert_contains "$d.guard.out" "$1" || return 1
    (cd "$d" && git checkout -q -- . && git clean -qfd -e node_modules -e repos) || return 1
  }
  perl -pi -e 's/^\/\/ UPDATE$/export const now = () => Date.now()\n\n\/\/ UPDATE/' "$d/src/main.ts" || return 1
  expect_guard_failure "effect(globalDate)" "Date.now() in src/main.ts" || return 1
  # tsconfig's src/** override (production files) lists only the rules it adds:
  # the patched tsc merges it with the base rule by rule, so the base's errors
  # still hold there. Production and test files are checked one at a time.
  printf "import { Effect } from 'effect'\n\nexport const leak = () => {\n  Effect.log('lost')\n}\n" > "$d/src/domain/floating.ts"
  expect_guard_failure "effect(floatingEffect)" "a floating Effect in src/domain" || return 1
  printf "import { Effect } from 'effect'\n\nimport { it } from '@effect/vitest'\n\nit('floats', () => {\n  Effect.log('lost')\n})\n" > "$d/src/floating.test.ts"
  expect_guard_failure "effect(floatingEffect)" "a floating Effect in a test file" || return 1
  # outdatedApi defaults to a warning: reported as an error in a production
  # file, the base's severity reached a file the override matches.
  printf "import { Effect } from 'effect'\n\nexport const legacy = Effect.succeed(1).pipe(\n  Effect.catchAll(() => Effect.succeed(2)),\n)\n" > "$d/src/domain/legacy.ts"
  guard; rc=$?
  [ "$rc" -ne 0 ] || fail "the guard passed with an Effect v3 API in src/domain" || return 1
  grep -qE '^src/domain/legacy\.ts\([0-9]+,[0-9]+\): error TS[0-9]+: .*effect\(outdatedApi\)' "$d.guard.out" \
    || fail "outdatedApi is not an error in a production file: $(grep -F 'legacy.ts' "$d.guard.out" | head -3)" || return 1
  (cd "$d" && git checkout -q -- . && git clean -qfd -e node_modules -e repos) || return 1
  printf "import { Command } from 'foldkit'\n\nexport const leak = Command\n" > "$d/src/domain/leak.ts"
  expect_guard_failure "src/domain and src/api must not import foldkit" "a foldkit import in src/domain" || return 1
  printf "import { defineTaggedUnion } from 'foldkit/schema'\n\nexport const Leak = defineTaggedUnion({ A: {} })\n" > "$d/src/domain/leak.ts"
  expect_guard_failure 'src/domain/leak.ts:1: loads "foldkit/schema"' "a foldkit subpath import in src/domain" || return 1
  printf "import { vi } from 'vitest'\n\nvi.mock('./main')\n" > "$d/src/mocked.test.ts"
  expect_guard_failure "no vi.mock" "vi.mock( in a test" || return 1
  # Regression test (#20 item 8): nothing showed that type-aware Oxlint and Oxfmt
  # fail the guard. tsc passes both files below.
  printf 'export const start = (): void => {\n  Promise.resolve(1)\n}\n' > "$d/src/domain/floating.ts"
  guard; rc=$?
  assert_exit 1 "$rc" || return 1
  # Oxlint's agent and graphical reporters lay out the same diagnostic
  # differently; colors can also split its path from the line and column.
  perl -pe 's/\e\[[0-9;]*m//g' "$d.guard.out" > "$d.guard.plain"
  assert_contains "$d.guard.plain" "typescript(no-floating-promises)" || return 1
  assert_contains "$d.guard.plain" "src/domain/floating.ts:2:3" || return 1
  (cd "$d" && git checkout -q -- . && git clean -qfd -e node_modules -e repos) || return 1
  printf 'export const spaced   =   1;\n' > "$d/src/domain/spaced.ts"
  expect_guard_failure "Format issues found" "a file Oxfmt would reformat" || return 1
  perl -pi -e 's/foldkit\((?:\{ devToolsMcpPort: false \})?\)/foldkit({ devToolsMcpPort: 9988 })/' "$d/vite.config.ts" || return 1
  grep -q 'devToolsMcpPort: 9988' "$d/vite.config.ts" || fail "the devToolsMcpPort mutation did not apply" || return 1
  expect_guard_failure "unauthenticated DevTools relay" "a numeric devToolsMcpPort in vite.config.ts" || return 1
  printf '{"mcpServers":{"foldkit-devtools":{"command":"npx","args":["-y","@foldkit/devtools-mcp"]}}}\n' > "$d/.mcp.json"
  expect_guard_failure 'server "foldkit-devtools" must call the pinned local bin' "npx in .mcp.json" || return 1
  fk_json "$d/package.json" 'c.version = "0.2.0"' || return 1
  expect_guard_failure "differs from VERSION" "package.json version drift" || return 1
  fk_json "$d/package.json" 'c.devDependencies.vitest = "^" + c.devDependencies.vitest' || return 1
  expect_guard_failure "vitest must be pinned to an exact version" "a caret range" || return 1
  node -e 'const fs=require("fs");fs.writeFileSync(process.argv[1],JSON.stringify(JSON.parse(fs.readFileSync(process.argv[1],"utf8")),null,4)+"\n")' "$d/package.json" || return 1
  expect_guard_failure "package.json is not in JSON.stringify" "a reformatted package.json" || return 1
  fk_json "$d/package.json" 'c.devDependencies["is-number"] = "7.0.0"' || return 1
  expect_guard_failure "node_modules is missing is-number: run pnpm install" "a dependency added without installing it" || return 1
  perl -0pi -e 's/(\n      vitest:\n        specifier: )[^\n]+/${1}0.0.1/' "$d/pnpm-lock.yaml" || return 1
  grep -q 'specifier: 0.0.1' "$d/pnpm-lock.yaml" || fail "the lockfile mutation did not apply" || return 1
  expect_guard_failure "pnpm-lock.yaml is missing or out of date" "a lockfile that no longer matches package.json" || return 1
  (cd "$d" && stack_env pnpm exec effect-tsgo unpatch) >"$d.unpatch.out" 2>&1 || fail "unpatch failed: $(cat "$d.unpatch.out")" || return 1
  expect_guard_failure "tsc is not patched by @effect/tsgo" "an unpatched tsc" || return 1
  (cd "$d" && stack_env pnpm exec effect-tsgo patch) >"$d.unpatch.out" 2>&1 || fail "re-patching failed: $(cat "$d.unpatch.out")" || return 1
  (cd "$d" && env PATH=/usr/bin:/bin /bin/bash scripts/check.d/foldkit.sh) >"$d.guard.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard.out" "pnpm is not installed" || return 1
  # A locked release under 24 hours old (a ten-year age rule in pnpm-workspace.yaml
  # stands in for one) is reported as that, with the packages named, not as a stale
  # lockfile and without pnpm's "relax the policy" help. Settings in the
  # environment can't loosen the file's rule. The install stays usable: the plain
  # guard passes right after.
  perl -pi -e 's/^minimumReleaseAge: \d+$/minimumReleaseAge: 5256000/' "$d/pnpm-workspace.yaml" || return 1
  grep -qx 'minimumReleaseAge: 5256000' "$d/pnpm-workspace.yaml" || fail "the age-rule mutation did not apply" || return 1
  guard; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard.out" "a locked release is younger than pnpm-workspace.yaml's minimumReleaseAge" || return 1
  assert_contains "$d.guard.out" "within the minimumReleaseAge cutoff" || return 1
  assert_not_contains "$d.guard.out" "out of date" || return 1
  assert_not_contains "$d.guard.out" "relax the policy" || return 1
  (cd "$d" && stack_env env pnpm_config_minimum_release_age=0 PNPM_CONFIG_MINIMUM_RELEASE_AGE=0 \
    pnpm_config_trust_lockfile=true bash scripts/check.d/foldkit.sh) >"$d.guard.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard.out" "within the minimumReleaseAge cutoff" || return 1
  # The pinned pnpm (devEngines switches the project to it) honors an exact
  # name@version exemption: under that rule it takes exactly that release off the
  # report, and another version of the package takes nothing off. check-pins
  # accepts the exact entry and refuses a bare name.
  [ "$(cd "$d" && stack_env pnpm --version)" = "$(node -p 'require(process.argv[1]).devEngines.packageManager.version' "$d/package.json")" ] \
    || fail "pnpm in the project is not the pinned one" || return 1
  rejected() { (cd "$d" && stack_env pnpm install --frozen-lockfile --lockfile-only 2>&1) | sed -n 's/.* \([0-9][0-9]*\) lockfile entries failed verification.*/\1/p'; }
  pin="$(node -p 'require(process.argv[1]).devDependencies["@effect/vitest"]' "$d/package.json")"
  all="$(rejected)"
  [ -n "$all" ] || fail "no count of rejected releases in pnpm's report" || return 1
  cp "$d/pnpm-workspace.yaml" "$d.policy.yaml" || return 1
  printf "minimumReleaseAgeExclude:\n  - '@effect/vitest@0.0.1'\n" >> "$d/pnpm-workspace.yaml"
  [ "$(rejected)" = "$all" ] || fail "an exemption for another version took a release off the report" || return 1
  cp "$d.policy.yaml" "$d/pnpm-workspace.yaml" || return 1
  printf "minimumReleaseAgeExclude:\n  - '@effect/vitest@%s'\n" "$pin" >> "$d/pnpm-workspace.yaml"
  [ "$(rejected)" = "$((all - 1))" ] || fail "exempting @effect/vitest@$pin did not take exactly it off the report ($all rejected without it)" || return 1
  guard; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard.out" "check-pins: ok" || return 1
  assert_contains "$d.guard.out" "a locked release is younger than" || return 1
  cp "$d.policy.yaml" "$d/pnpm-workspace.yaml" || return 1
  printf "minimumReleaseAgeExclude:\n  - '@effect/vitest'\n" >> "$d/pnpm-workspace.yaml"
  guard; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.guard.out" 'minimumReleaseAgeExclude entry "@effect/vitest" must be an exact name@version' || return 1
  (cd "$d" && git checkout -q -- pnpm-workspace.yaml) || return 1
  # A tarball URL the registry never published for that release may be a tamper,
  # not a young release: pnpm's report and help pass through whole.
  perl -0pi -e 's|(\n  foldkit\@[^:\n]+:\n    resolution: \{integrity: [^,}]+)\}|$1, tarball: https://registry.npmjs.org/foldkit/-/foldkit-0.0.1.tgz}|' "$d/pnpm-lock.yaml" || return 1
  grep -q 'foldkit-0.0.1.tgz' "$d/pnpm-lock.yaml" || fail "the tarball mutation did not apply" || return 1
  guard; rc=$?
  assert_exit 1 "$rc" || return 1
  # pnpm wraps its report at 80 columns: these fragments stay on one line.
  assert_contains "$d.guard.out" "ERR_PNPM_LOCKFILE_RESOLUTION_VERIFICATION" || return 1
  assert_contains "$d.guard.out" "has a tarball URL" || return 1
  assert_contains "$d.guard.out" "help: The lockfile contains entries" || return 1
  assert_contains "$d.guard.out" "pnpm-lock.yaml or a dependency may have been tampered with" || return 1
  assert_not_contains "$d.guard.out" "minimumReleaseAge, 24 hours" || return 1
  (cd "$d" && git checkout -q -- pnpm-lock.yaml) || return 1
  guard || fail "the guard failed after the mutations were reverted: $(tail -20 "$d.guard.out")" || return 1
  # Coverage: an untested module fails the global floor and is named; a tier member
  # that coverage can't measure fails its tier.
  printf 'export const pick = (flag: boolean): number => {\n  if (flag) {\n    return 1\n  }\n  return 2\n}\n' > "$d/src/domain/extra.ts"
  (cd "$d" && stack_env bash scripts/coverage.sh) >"$d.cov.out" 2>&1; rc=$?
  rm -f "$d/src/domain/extra.ts"
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.cov.out" "src/domain/extra.ts" || return 1
  # Five lines keep the global line floor (50/54); its branches fail it, by name.
  assert_contains "$d.cov.out" "coverage-tiers: FAIL global: branches" || return 1
  printf 'export type Shape = { readonly name: string }\n' > "$d/src/domain/shape.ts"
  fk_json "$d/coverage-tiers.json" 'c.tiers.pure_logic.include.push("src/domain/shape.ts")' || return 1
  (cd "$d" && stack_env bash scripts/coverage.sh) >"$d.cov.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.cov.out" "pure_logic: src/domain/shape.ts" || return 1
  (cd "$d" && git checkout -q -- . && rm -f src/domain/shape.ts) || return 1
  # The ratchet against the committed state.
  fk_json "$d/coverage-tiers.json" 'c.tiers.main_components.minimum = 80' || return 1
  (cd "$d" && node scripts/coverage-tiers.mjs --ratchet HEAD) >"$d.ratchet.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.ratchet.out" "main_components: minimum lowered from 90 to 80" || return 1
  (cd "$d" && git checkout -q -- coverage-tiers.json) || return 1
  fk_json "$d/coverage-tiers.json" 'c.tiers.main_components.include = ["src/view.ts"]' || return 1
  (cd "$d" && node scripts/coverage-tiers.mjs --ratchet HEAD) >"$d.ratchet.out" 2>&1; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.ratchet.out" "existing members removed since HEAD" || return 1
  (cd "$d" && git checkout -q -- coverage-tiers.json) || return 1
}

# --- runner -------------------------------------------------------------------
if [ "$FILTER" = "--print-inventory" ]; then placeholder_inventory; exit $?; fi
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  case "$t" in *"$FILTER"*) ;; *) continue ;; esac
  if [ -n "$EXCLUDE" ]; then
    case "$t" in *"$EXCLUDE"*) EXCLUDED=$((EXCLUDED + 1)); continue ;; esac
  fi
  echo "- $t"
  "$t"; rc=$?
  case "$rc" in
    0)  PASS=$((PASS + 1)); echo "  ok" ;;
    77) SKIP=$((SKIP + 1)) ;;
    *)  FAIL=$((FAIL + 1)) ;;
  esac
done
if [ "$EXCLUDED" -gt 0 ]; then
  echo "selftest: $PASS passed, $FAIL failed, $SKIP skipped ($EXCLUDED excluded by SELFTEST_EXCLUDE=$EXCLUDE)"
else
  echo "selftest: $PASS passed, $FAIL failed, $SKIP skipped"
fi
if [ "${CI:-}" = "true" ] && [ "$SKIP" -gt 0 ]; then
  echo "selftest: skipped tests count as failures in CI (install the missing tool)" >&2
  exit 1
fi
[ "$FAIL" -eq 0 ] && [ $((PASS + SKIP)) -gt 0 ]
