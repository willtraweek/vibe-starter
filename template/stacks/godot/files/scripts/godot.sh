#!/usr/bin/env bash
# Runs the pinned Godot on this project: ./scripts/godot.sh [Godot's options]. With no
# options it plays the game; --editor opens the editor. ./scripts/godot-kit.sh finds or
# installs that Godot.
set -euo pipefail
root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"   # a CDPATH entry must not pick it
godot="$("$root/scripts/godot-kit.sh" godot)"
exec "$godot" --path "$root" "$@"
