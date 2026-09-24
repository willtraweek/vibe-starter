#!/usr/bin/env bash
# Stack-neutral pre-test guards. Runs before the test suite, locally and in CI.
# Add project-specific checks here as the codebase grows (the "guards run before
# tests" convention). Each guard should fail loudly and set status=1.
#
# A guard whose tool is missing is skipped locally with a notice, but FAILS in CI:
# CI set to anything but empty, false, 0 or no (any letter case), or a known CI
# vendor variable. A guard that silently skips in CI protects nothing. Explicit
# CI=false, CI=0, or CI=no forces the local skip.
# Exception: editorconfig-checker stays advisory everywhere for now.
# Override tool paths with GITLEAKS_BIN / EDITORCONFIG_CHECKER_BIN.

# Returns 0 when a missing gitleaks binary must fail the run.
# Explicit CI=false, CI=0, or CI=no (any letter case) forces the local skip
# and wins over vendor CI variables.
ci_requires_gitleaks() {
  local ci name
  ci="$(printf '%s' "${CI:-}" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  case "$ci" in
    false|0|no) return 1 ;;
    ?*) return 0 ;;
  esac
  for name in \
    GITHUB_ACTIONS GITLAB_CI JENKINS_URL BUILDKITE CIRCLECI TRAVIS \
    TF_BUILD APPVEYOR DRONE WOODPECKER TEAMCITY_VERSION \
    CODEBUILD_BUILD_ID BITBUCKET_BUILD_NUMBER CIRRUS_CI CONTINUOUS_INTEGRATION
  do
    if [ -n "${!name:-}" ]; then
      return 0
    fi
  done
  return 1
}

set -euo pipefail
# Follow $0 through symlinks so a hook at .git/hooks/pre-commit ->
# ../../scripts/check.sh finds the project, not .git. CDPATH is cleared for
# each cd: a relative target can match a CDPATH entry, and bash prints that
# directory on stdout.
script="$0"
while [ -L "$script" ]; do
  link=$(readlink "$script")
  case "$link" in
    /*) script="$link" ;;
    *) script="$(dirname "$script")/${link}" ;;
  esac
done
# Git runs hooks from the root of the worktree being committed. Linked worktrees
# share one hooks dir, so a symlinked hook resolves to the main checkout's copy:
# when $0 was a link and the current directory has its own copy of this script,
# check the current directory instead.
script_rel="$(basename "$(CDPATH='' cd "$(dirname "$script")" && pwd)")/$(basename "$script")"
if [ "$script" = "$0" ] || [ ! -f "$script_rel" ]; then
  CDPATH='' cd "$(dirname "$script")/.." || exit 1
fi

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
  # Absolute path: the scan below runs from inside a temp dir.
  GITLEAKS_BIN="$(command -v "$GITLEAKS_BIN")"
  case "$GITLEAKS_BIN" in /*) ;; */*) GITLEAKS_BIN="$root/$GITLEAKS_BIN" ;; esac
  scan_tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-gitleaks.XXXXXX")"
  trap 'rm -rf "$scan_tmp"' EXIT
  # Report file:line:rule only. gitleaks -v prints ~20 characters around each
  # finding, which leaks a second secret sharing the line (--redact hides only
  # the finding's own). The Go template is written with <> and translated, since
  # a literal double brace in this repo reads as a hand-fill placeholder.
  printf '<<range .>><<.File>>:<<.StartLine>>:<<.RuleID>>\n<<end>>' | tr '<>' '{}' > "$scan_tmp/report.tmpl"
  # Inherited repo-local git variables (GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE,
  # and the rest of `git rev-parse --local-env-vars`) override `git -C`. A value
  # exported for a different repository makes `git ls-files` list that tree, or
  # nothing. Strip them only for the subprocesses that choose what to scan, and
  # leave them set in this shell so a hook's later git commands still see the
  # repository git exported. The name list is static: it does not read $GIT_DIR.
  # `git -C "$root"` discovers a linked worktree, where .git is a file.
  git_env_u=()
  git_env_names="$(git rev-parse --local-env-vars 2>/dev/null)" || git_env_names=""
  for git_env_name in $git_env_names; do
    [ -n "$git_env_name" ] || continue
    git_env_u+=("-u" "$git_env_name")
  done
  unset git_env_name git_env_names
  # bash 3.2 with `set -u` rejects "${arr[@]}" when arr is empty.
  git_at_root() {
    if [ "${#git_env_u[@]}" -eq 0 ]; then
      git -C "$root" "$@"
    else
      env "${git_env_u[@]}" git -C "$root" "$@"
    fi
  }
  # Scan git's committable set only when git would commit this project. A copy
  # inside a folder that an enclosing repo ignores is still "inside a work
  # tree", but git lists nothing there, and a scan of nothing passes.
  scan_root="$root"
  if [ "$(git_at_root rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ] \
    && [ -n "$(git_at_root ls-files --cached --others --exclude-standard -- "$script_rel")" ]; then
    echo "- gitleaks: scanning the files git would commit..."
    scan_root="$scan_tmp/tree"
    mkdir "$scan_root"
    # Copy the committable set, skipping tracked paths deleted from disk. Keep the
    # if/fi: `[ -f ] && printf` ends the loop non-zero when the last path is deleted.
    if ! git_at_root ls-files -z --cached --others --exclude-standard \
      | while IFS= read -r -d '' f; do if [ -f "$f" ]; then printf '%s\0' "$f"; fi; done \
      | tar --null -T - -cf - | tar --no-same-owner -xf - -C "$scan_root"; then
      echo "- gitleaks: could not copy the files git would commit - secret scan NOT run." >&2
      status=1
      scan_root=""
    fi
  else
    echo "- gitleaks: git would not commit this project (no repo of its own yet?) - scanning every file..."
  fi
  if [ -n "$scan_root" ]; then
    (cd "$scan_root" && "$GITLEAKS_BIN" dir --no-banner --redact \
      --report-format template --report-path - \
      --report-template "$scan_tmp/report.tmpl" \
      -c "$root/.gitleaks.toml" .) || status=1
  fi
  rm -rf "$scan_tmp"; trap - EXIT
elif ci_requires_gitleaks; then
  echo "- gitleaks not installed - REQUIRED in CI: install it in an earlier step (see 'Install gitleaks' in .github/workflows/ci.yml[.example]). Not CI? Set CI=false." >&2
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
