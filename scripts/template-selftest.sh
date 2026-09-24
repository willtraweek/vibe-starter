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

# Hermetic git: ignore the user's global/system config (signing, hooks,
# templates) and use a fixed identity for any test commits.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.invalid
export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.invalid
unset GIT_TEMPLATE_DIR   # an env var, not config: it would still install the user's hooks

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
  assert_not_contains "$d.out" "$tok" || return 1
  assert_not_contains "$d.out" "${tok:4:8}"
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
