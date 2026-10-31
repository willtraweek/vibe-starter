#!/usr/bin/env bash
# The coverage gate (TESTING.md): every test, run against instrumented copies of the
# scripts under src/, then at least 90% of lines and of branches overall, each tier of
# coverage-tiers.json at its minimum, and every named journey run and passed. CI runs it;
# ./scripts/test.sh is the quicker loop without coverage. It writes coverage/: the map of
# probes, their counts, each test's outcome and lcov.info for editors.
#
#   ./scripts/coverage.sh --ratchet <git ref>   only compare coverage-tiers.json with its
#                                               copy at <ref>: nothing lowered or dropped
set -euo pipefail
CDPATH='' cd -- "$(dirname -- "$0")/.."   # a CDPATH entry must not pick the directory
root="$(pwd -P)"
./scripts/import.sh

if [ "${1:-}" = --ratchet ]; then
  if [ -z "${2:-}" ] || ! git rev-parse --verify --quiet "${2}^{commit}" >/dev/null; then
    echo "coverage.sh: --ratchet needs a git ref that exists here (fetch the base branch first)" >&2
    exit 2
  fi
  base="$(mktemp "${TMPDIR:-/tmp}/coverage-base.XXXXXX")"
  trap 'rm -f "$base"' EXIT
  # A base without the file predates this pack: there is nothing to hold yet.
  if git cat-file -e "$2:coverage-tiers.json" 2>/dev/null; then
    git show "$2:coverage-tiers.json" >"$base"
  fi
  ./scripts/godot.sh --headless -s res://tools/coverage/report.gd -- --ratchet "$base"
  exit
fi

[ -d src ] || { echo "coverage.sh: there is no src/ to measure" >&2; exit 1; }
out="$root/coverage"
rm -rf "$out"
mkdir -p "$out"
: >"$out/.gdignore"
mirror="$(mktemp -d "${TMPDIR:-/tmp}/godot-coverage.XXXXXX")"
trap 'rm -rf "$mirror"' EXIT
# The mirror is this project as Godot sees it, but for one thing: the scripts under src/
# are instrumented copies. Everything else links to the real file.
for entry in * .godot; do
  case "$entry" in src | coverage | build) continue ;; esac
  if [ -e "$entry" ]; then ln -s "$root/$entry" "$mirror/$entry"; fi
done
(CDPATH='' cd src && find . -type d) | while IFS= read -r dir; do mkdir -p "$mirror/src/$dir"; done
(CDPATH='' cd src && find . -type f ! -name '*.gd') | while IFS= read -r file; do
  ln -s "$root/src/$file" "$mirror/src/$file"
done
./scripts/godot.sh --headless -s res://tools/coverage/instrument.gd -- "$mirror" "$out/map.json" \
  >"$out/instrument.log" 2>&1 || { cat "$out/instrument.log" >&2; exit 1; }

godot="$(./scripts/godot-kit.sh godot)"
if ! "$godot" --headless --path "$mirror" -s res://tools/test/run.gd -- --check-only \
  >"$out/check.log" 2>&1; then
  cat "$out/check.log" >&2
  echo "coverage.sh: an instrumented copy does not compile (above). If ./scripts/test.sh --check-only passes, that is a bug in tools/coverage." >&2
  exit 1
fi
status=0
"$godot" --headless --fixed-fps 60 --path "$mirror" -s res://tools/test/run.gd -- \
  --results "$out/results.json" --coverage "$out/hits.json" || status=$?
./scripts/godot.sh --headless -s res://tools/coverage/report.gd -- --map "$out/map.json" \
  --hits "$out/hits.json" --results "$out/results.json" --lcov "$out/lcov.info" || status=1
exit "$status"
