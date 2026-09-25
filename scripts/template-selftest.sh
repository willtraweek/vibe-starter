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
PASS=0; FAIL=0; SKIP=0

# Real tool homes, captured before any test sandboxes HOME (see stack_env).
REAL_UV_CACHE_DIR="${UV_CACHE_DIR:-$(uv cache dir 2>/dev/null || echo "$HOME/.cache/uv")}"
REAL_UV_PYTHON_DIR="${UV_PYTHON_INSTALL_DIR:-$(uv python dir 2>/dev/null || echo "$HOME/.local/share/uv/python")}"
REAL_CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
REAL_RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"

# Hermetic git: ignore the user's global/system config (signing, hooks,
# templates) and use a fixed identity for any test commits.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.invalid
export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.invalid
unset GIT_TEMPLATE_DIR   # an env var, not config: it would still install the user's hooks
unset GITLEAKS_BIN EDITORCONFIG_CHECKER_BIN   # check.sh overrides: tests set them explicitly

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
stack_env() {  # run "$@" with the real uv/cargo homes, so a sandboxed HOME doesn't
  # force fresh downloads of Python, crates, or toolchains on every test run.
  env UV_CACHE_DIR="$REAL_UV_CACHE_DIR" UV_PYTHON_INSTALL_DIR="$REAL_UV_PYTHON_DIR" \
    CARGO_HOME="$REAL_CARGO_HOME" RUSTUP_HOME="$REAL_RUSTUP_HOME" "$@"
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
  for key in $(sed -n 's/^\([A-Z_]*\)=.*/\1/p' "$REPO/template/stacks/python/commands") PROJECT_NAME YEAR; do
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
  { git -C "$REPO" ls-files --cached --others --exclude-standard -- template/stacks/python/files \
      | sed 's|^template/stacks/python/files/||; s|__package__|demo|g'
    printf '%s\n' uv.lock .github/workflows/ci.yml .github/actions/install-gitleaks/action.yml
  } > "$root/committed" || return 1
  while IFS= read -r f; do
    git -C "$d" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || fail "git would not commit $f" || return 1
  done < "$root/committed"
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
  assert_contains "$root/typed/demo.out" "Stack pack [none fixture python" || return 1
  assert_contains "$root/typed/demo/src/demo/hello.txt" "package=demo" || return 1
  assert_contains "$root/typed/demo/.bootstrapped" "with the fixture stack pack" || return 1
  tty_bootstrap "$root/enter/demo" "" --name demo || fail "exited $?: $(cat "$root/enter/demo.out")" || return 1
  assert_contains "$root/enter/demo.out" "Stack pack [none fixture python" || return 1
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

# --- runner -------------------------------------------------------------------
if [ "$FILTER" = "--print-inventory" ]; then placeholder_inventory; exit $?; fi
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
