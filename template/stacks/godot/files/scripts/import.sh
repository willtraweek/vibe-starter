#!/usr/bin/env bash
# Brings .godot/ up to date: Godot imports new and changed assets and refreshes its list of
# global classes. The test, coverage and build scripts and the checks run this first, so a
# fresh clone works. Quiet unless it fails.
set -euo pipefail
CDPATH='' cd -- "$(dirname -- "$0")/.."   # a CDPATH entry must not pick the directory
log="$(mktemp "${TMPDIR:-/tmp}/godot-import.XXXXXX")"
trap 'rm -f "$log"' EXIT
if ! ./scripts/godot.sh --headless --import >"$log" 2>&1; then
  cat "$log" >&2
  echo "import.sh: Godot's import failed (above)" >&2
  exit 1
fi
