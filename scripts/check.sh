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
