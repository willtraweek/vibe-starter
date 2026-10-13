#!/usr/bin/env bash
# Omarchy guards (from ./bootstrap --stack omarchy-app): colours come from the
# Omarchy theme, never literals or gradients in src/, and the desktop entry is valid.
set -euo pipefail

# gpui-omarchy's Theme (cx.omarchy()) follows `omarchy theme set` live; a colour
# built from fixed values would stay put when the theme changes. The check reads
# text, not types (an Hsla struct literal gets past it), so DESIGN.md's rule
# still holds.
if grep -rnE '\b(rgb|rgba|hsla|black|white|red|green|blue|yellow|opaque_grey|transparent_black|transparent_white)\(|\bRgba::try_from\(' src; then
  echo "  colour literals in src/ (above): use the theme's roles, cx.omarchy() (DESIGN.md)" >&2
  exit 1
fi
# Omarchy surfaces are flat: no gradients, whatever their colours (DESIGN.md).
if grep -rnE '\blinear_gradient\(' src; then
  echo "  gradients in src/ (above): Omarchy surfaces are flat (DESIGN.md)" >&2
  exit 1
fi

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
