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
