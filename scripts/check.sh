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
