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
# Override tool paths with GITLEAKS_BIN / EDITORCONFIG_CHECKER_BIN. The secret
# scan needs gitleaks 8.22 or newer, and GNU tar or bsdtar (for --null).

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
# Drop inherited git variables that pick a repository (GIT_DIR, GIT_WORK_TREE,
# GIT_INDEX_FILE and the rest of `git rev-parse --local-env-vars`). Hooks,
# aliases and dotfiles setups export them, and they would point git at another
# checkout, or at this one from the wrong directory after the cd below. Config
# passed as GIT_CONFIG_* (e.g. safe.directory) is kept. From here on git finds
# the repository from the working directory, linked worktrees included.
for v in $(git rev-parse --local-env-vars 2>/dev/null || true); do
  case "$v" in GIT_CONFIG*) ;; *) unset "$v" ;; esac
done

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
script_dir="$(CDPATH='' cd "$(dirname "$script")" && pwd -P)" || exit 1
script_name="$(basename "$script")"
script_rel="$(basename "$script_dir")/$script_name"   # from the project root
# Git runs hooks from the root of the worktree being committed, and linked
# worktrees share one hooks dir, so a hook (a link or a wrapper) reaches the main
# checkout's copy of this script. Run from another worktree of the same
# repository, hand over to that worktree's own copy at the same path (e.g.
# packages/app/scripts/check.sh), or refuse if it has none: checking a different
# checkout would pass whatever this one commits.
git_common_dir() {  # $1 = dir: its repository's shared git dir, as a physical path
  local d
  d="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" && [ -n "$d" ] \
    && (CDPATH='' cd "$1" && CDPATH='' cd "$d" && pwd -P)
}
here="" top=""
if [ -z "${CHECK_SH_HANDED_OVER:-}" ]; then
  here="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  top="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"
fi
unset CHECK_SH_HANDED_OVER
if [ -n "$here" ] && [ -n "$top" ] && [ "$here" != "$top" ] \
  && case "$script_dir" in "$top"/*) true ;; *) false ;; esac \
  && here_common="$(git_common_dir "$here")" && [ -n "$here_common" ] \
  && [ "$here_common" = "$(git_common_dir "$top")" ]; then
  rel="${script_dir#"$top"/}"   # e.g. scripts, or packages/app/scripts
  if [ -f "$here/$rel/$script_name" ]; then
    CHECK_SH_HANDED_OVER=1 exec bash "$here/$rel/$script_name" "$@"
  fi
  echo "check.sh: git is committing in $here, which has no $rel/$script_name - not checking a different checkout." >&2
  exit 1
fi
CDPATH='' cd "$script_dir/.." || exit 1

status=0
ran_any=0
root="$(pwd)"
GITLEAKS_BIN="${GITLEAKS_BIN:-gitleaks}"
EDITORCONFIG_CHECKER_BIN="${EDITORCONFIG_CHECKER_BIN:-editorconfig-checker}"

# --- Secret scanning: exactly the files git would commit --------------------
# Gitignored files (.env, local config) are deliberately NOT scanned: that is
# where local secrets belong. Tracked files and untracked-but-committable files
# are. A force-added .env is tracked, so it IS scanned. A project git would not
# commit (no repo of its own yet) has every file scanned, gitignored ones too.
if command -v "$GITLEAKS_BIN" >/dev/null 2>&1; then
  ran_any=1
  # Absolute path: the scan below runs from inside a temp dir.
  GITLEAKS_BIN="$(command -v "$GITLEAKS_BIN")"
  case "$GITLEAKS_BIN" in /*) ;; */*) GITLEAKS_BIN="$root/$GITLEAKS_BIN" ;; esac
  scan_tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-gitleaks.XXXXXX")"
  trap 'rm -rf "$scan_tmp"' EXIT
  scan_tmp="$(CDPATH='' cd "$scan_tmp" && pwd -P)"   # absolute, even for a relative TMPDIR
  # Report file:line:rule only. gitleaks -v prints ~20 characters around each
  # finding, which leaks a second secret sharing the line (--redact hides only
  # the finding's own). The Go template is written with <> and translated, since
  # a literal double brace in this repo reads as a hand-fill placeholder.
  printf '<<range .>><<.File>>:<<.StartLine>>:<<.RuleID>>\n<<end>>' | tr '<>' '{}' > "$scan_tmp/report.tmpl"
  scan_root=""
  case "$("$GITLEAKS_BIN" dir --help 2>&1 || true)" in
    *--report-template*)
      # Scan git's committable set when git would commit this project. A copy in
      # a folder an enclosing repo ignores is "inside a work tree" with nothing
      # listed, and a scan of nothing passes: scan every file there instead.
      scan_root="$root"
      if command -v git >/dev/null 2>&1; then
        if in_tree="$(LC_ALL=C git -C "$root" rev-parse --is-inside-work-tree 2>"$scan_tmp/git.err")"; then
          if [ "$in_tree" = true ] \
            && [ -n "$(git -C "$root" ls-files --cached --others --exclude-standard -- "$script_rel")" ]; then
            scan_root="$scan_tmp/tree"
          fi
        elif ! grep -q "not a git repository" "$scan_tmp/git.err"; then
          # Dubious ownership, a broken repo, ...: report git's error. Scanning
          # every file as if there were no repo would flag the gitignored .env.
          echo "- gitleaks: git failed here - secret scan NOT run:" >&2
          sed 's/^/    /' "$scan_tmp/git.err" >&2
          status=1
          scan_root=""
        fi
      fi ;;
    *)
      gitleaks_version="$("$GITLEAKS_BIN" version 2>/dev/null || true)"
      echo "- gitleaks ${gitleaks_version:-(unknown version)} is too old: 8.22 or newer is needed (dir --report-template) - secret scan NOT run." >&2
      status=1 ;;
  esac
  if [ "$scan_root" = "$root" ]; then
    echo "- gitleaks: git would not commit this project (no repo of its own yet?) - scanning every file..."
  elif [ -n "$scan_root" ]; then
    echo "- gitleaks: scanning the files git would commit..."
    mkdir "$scan_root"
    # Copy the committable set, skipping tracked paths deleted from disk. Keep the
    # if/fi: `[ -f ] && printf` ends the loop non-zero when the last path is deleted.
    if ! git -C "$root" ls-files -z --cached --others --exclude-standard \
      | while IFS= read -r -d '' f; do if [ -f "$f" ]; then printf '%s\0' "$f"; fi; done \
      | tar --null -T - -cf - | tar --no-same-owner -xf - -C "$scan_root"; then
      echo "- gitleaks: could not copy the files git would commit - secret scan NOT run." >&2
      status=1
      scan_root=""
    fi
  fi
  if [ -n "$scan_root" ]; then
    (CDPATH='' cd "$scan_root" && "$GITLEAKS_BIN" dir --no-banner --redact \
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
