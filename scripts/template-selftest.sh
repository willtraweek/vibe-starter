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

REPO="$(cd "$(dirname "$0")/.." && pwd)"
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
