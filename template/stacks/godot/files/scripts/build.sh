#!/usr/bin/env bash
# The build: exports the game's data pack, build/{{PACKAGE_NAME}}.pck, with the pinned Godot
# (no export templates needed), then starts it headless for 60 frames. A scene, script or
# asset the export left out fails here rather than on a player's machine. Executables for
# each platform need Godot's export templates: see docs/guides/godot.md.
set -euo pipefail
CDPATH='' cd -- "$(dirname -- "$0")/.."   # a CDPATH entry must not pick the directory
root="$(pwd -P)"
./scripts/import.sh
pck="build/{{PACKAGE_NAME}}.pck"
mkdir -p build
: >build/.gdignore
rm -f "$pck"
log="$(mktemp "${TMPDIR:-/tmp}/godot-build.XXXXXX")"
empty="$(mktemp -d "${TMPDIR:-/tmp}/godot-boot.XXXXXX")"
trap 'rm -rf "$log" "$empty"' EXIT
if ! ./scripts/godot.sh --headless --export-pack Linux "$pck" >"$log" 2>&1 || [ ! -s "$pck" ]; then
  cat "$log" >&2
  echo "build.sh: the export failed (above)" >&2
  exit 1
fi
godot="$(./scripts/godot-kit.sh godot)"
# From an empty directory, so that the pack is the whole project.
if ! (CDPATH='' cd "$empty" && "$godot" --headless --main-pack "$root/$pck" --quit-after 60) \
  >"$log" 2>&1 || grep -qE '^(USER )?(SCRIPT )?ERROR:' "$log"; then
  cat "$log" >&2
  echo "build.sh: the exported game does not start cleanly (above)" >&2
  exit 1
fi
echo "build.sh: wrote $pck"
