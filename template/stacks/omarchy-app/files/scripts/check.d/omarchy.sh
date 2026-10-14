#!/usr/bin/env bash
# Omarchy guards (from ./bootstrap --stack omarchy-app): colours come from the
# Omarchy theme and surfaces stay flat (no colour literals, gradients, shadows,
# glass or rounded pills in src/), and the desktop entry is valid.
set -euo pipefail

refuse() {  # $1 = an extended regex for what DESIGN.md bans in src/, $2 = what it found
  if grep -rnE "$1" src; then
    echo "  $2 (DESIGN.md)" >&2
    exit 1
  fi
}

# gpui-omarchy's Theme (cx.omarchy()) follows `omarchy theme set` live; a colour
# built from fixed values would stay put when the theme changes. The checks read
# text, not types (an Hsla struct literal gets past them), so DESIGN.md's rules
# still hold.
refuse '\b(rgb|rgba|hsla|black|white|red|green|blue|yellow|opaque_grey|transparent_black|transparent_white)\(|\bRgba::try_from\(' \
  "colour literals in src/ (above): use the theme's roles, cx.omarchy()"
# Omarchy surfaces are flat: no gradients or pattern fills, whatever their
# colours, and no shadows (GPUI's sized ones, shadow_sm() to shadow_2xl(), are
# fixed black; shadow_none() removes one, so it passes).
refuse '\b(linear_gradient|pattern_slash|checkerboard)\(' "gradients or pattern fills in src/ (above): Omarchy surfaces are flat"
refuse '\bshadow(_([0-9]*x[sl]|sm|md|lg))?\(|\bBoxShadow\b' "shadows in src/ (above): Omarchy surfaces are flat"
# Square corners: a small radius (rounded_sm()) is fine, a pill on any side is not.
refuse '\brounded(_(t|b|l|r|tl|tr|bl|br))?_(lg|xl|2xl|3xl|full)\(' "rounded pills in src/ (above): Omarchy corners are square"
# No glass: the window is opaque, like the rest of the desktop.
refuse 'WindowBackgroundAppearance::(Blurred|Transparent)' "a see-through window in src/ (above): Omarchy windows are opaque"

# The entry install.sh writes, checked by desktop-file-utils. check.sh sets
# CHECK_CI=1 where a missing tool must fail (CI) and 0 where it may be skipped.
validator="${DESKTOP_FILE_VALIDATE_BIN:-desktop-file-validate}"
if command -v "$validator" >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  PREFIX=/usr/local ./scripts/install.sh --print-desktop-entry > "$tmp/{{PACKAGE_NAME}}.desktop"
  "$validator" "$tmp/{{PACKAGE_NAME}}.desktop"
elif [ "${CHECK_CI:-0}" = 1 ]; then
  echo "  desktop-file-validate is required in CI (apt: desktop-file-utils)" >&2
  exit 1
else
  echo "  desktop-file-validate not installed - skipping the desktop entry check"
fi
