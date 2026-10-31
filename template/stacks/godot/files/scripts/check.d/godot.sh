#!/usr/bin/env bash
# Godot guards (from ./bootstrap --stack godot). project.godot names the Godot that
# scripts/godot-kit.sh pins and keeps GDScript's typing warnings errors; colours come only
# from src/style.gd (DESIGN.md); every GDScript file passes GDScript Formatter's format and
# lint rules; Godot loads every script, scene and resource; coverage-tiers.json is valid.
# A missing tool is skipped here and fails in CI: ./scripts/godot-kit.sh installs both.
set -euo pipefail
status=0
refuse() {  # each argument is one line of the problem
  printf '  %s\n' "$@" >&2
  status=1
}
log="$(mktemp "${TMPDIR:-/tmp}/godot-guard.XXXXXX")"
trap 'rm -f "$log"' EXIT
missing() {  # $1 = why the tool can't be used, from the kit
  if [ "${CHECK_CI:-0}" = 1 ]; then
    refuse "$1" "REQUIRED in CI: install it in an earlier step"
  else
    echo "  $1 - skipping its checks"
  fi
}

# 1. The engine: the feature version project.godot declares is the one the kit pins.
pinned="$(sed -n 's/^GODOT_VERSION=\([0-9][0-9]*\.[0-9][0-9]*\)\..*/\1/p' scripts/godot-kit.sh)"
if ! grep -q "^config/features=PackedStringArray(\"$pinned\"" project.godot; then
  refuse "project.godot's config/features must start with \"$pinned\", the Godot scripts/godot-kit.sh pins"
fi

# 2. Typed GDScript: Godot's analyzer is the type checker only while these stay errors.
if grep -qx 'gdscript/warnings/enable=false' project.godot; then
  refuse "project.godot turns GDScript's warnings off (gdscript/warnings/enable=false)"
fi
for warning in untyped_declaration unsafe_property_access unsafe_method_access unsafe_cast \
  unsafe_call_argument unsafe_void_return; do
  grep -qx "gdscript/warnings/$warning=2" project.godot \
    || refuse "project.godot must keep gdscript/warnings/$warning=2 (an error)"
done

# 3. Colours are Style tokens (DESIGN.md): none written in another script or in a scene.
# This reads text, not types; a colour built another way still breaks the rule.
hits="$(find src -name '*.gd' ! -path src/style.gd -exec perl -ne \
  '(my $code = $_) =~ s/#.*//;
  print "$ARGV:$.: $_" if $code =~ /\bColor8?\(|\bColor\.(?:html|hex|hex64|from_\w+)\(|\bColor\.[A-Z][A-Z_]+\b/;
  close ARGV if eof' {} + 2>/dev/null || true)"
scenes="$(find src -name '*.tscn' -exec grep -Hn 'Color(' {} + 2>/dev/null || true)"
if [ -n "$hits$scenes" ]; then
  if [ -n "$hits" ]; then printf '%s\n' "$hits" >&2; fi
  if [ -n "$scenes" ]; then printf '%s\n' "$scenes" >&2; fi
  refuse "colours written outside src/style.gd (above): name a Style token instead (DESIGN.md)"
fi

# 4. GDScript Formatter: format and lint.
if why="$(./scripts/godot-kit.sh formatter 2>&1 >/dev/null)"; then
  ./scripts/format.sh --check >"$log" 2>&1 \
    || { cat "$log" >&2; refuse "GDScript is not formatted or not lint-clean (above): run ./scripts/format.sh"; }
else
  missing "${why#godot-kit: }"
fi

# 5. Godot loads everything, with warnings as errors, and reads the tier config.
if why="$(./scripts/godot-kit.sh godot 2>&1 >/dev/null)"; then
  if ./scripts/import.sh >"$log" 2>&1 \
    && ./scripts/godot.sh --headless -s res://tools/test/run.gd -- --check-only >"$log" 2>&1; then
    ./scripts/godot.sh --headless -s res://tools/coverage/report.gd -- --validate >"$log" 2>&1 \
      || { cat "$log" >&2; refuse "coverage-tiers.json is not valid (above)"; }
  else
    cat "$log" >&2
    refuse "Godot cannot load everything (above)"
  fi
else
  missing "${why#godot-kit: }"
fi
exit "$status"
