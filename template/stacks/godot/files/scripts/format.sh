#!/usr/bin/env bash
# Formats every GDScript file git would commit with the pinned GDScript Formatter, then lints
# them: ./scripts/format.sh. --check changes nothing and fails on a file that is not
# formatted (scripts/check.d/godot.sh runs that). addons/ is others' code: left alone.
set -euo pipefail
CDPATH='' cd -- "$(dirname -- "$0")/.."   # a CDPATH entry must not pick the directory
check=()
case "${1:-}" in
  --check) check=(--check) ;;
  '') ;;
  *) echo "usage: ./scripts/format.sh [--check]" >&2; exit 2 ;;
esac
formatter="$(./scripts/godot-kit.sh formatter)"
files=()
while IFS= read -r -d '' file; do
  case "$file" in
    addons/*) ;;
    *) if [ -f "$file" ]; then files+=("$file"); fi ;;
  esac
done < <(git ls-files -z --cached --others --exclude-standard -- '*.gd')
if [ "${#files[@]}" -eq 0 ]; then
  echo "format.sh: no GDScript files" >&2
  exit 1
fi
"$formatter" ${check[@]+"${check[@]}"} "${files[@]}"
"$formatter" lint "${files[@]}"
