#!/usr/bin/env bash
# Omarchy guards (from ./bootstrap --stack omarchy-tui): colours are the
# terminal's own, never RGB or 256-colour literals in src/, and the desktop
# entry is valid.
set -euo pipefail

# Omarchy rewrites the terminal's 16 ANSI colours on `omarchy theme set`; RGB and
# 256-colour values would stay put. The check reads text, not types
# ((r, g, b).into() gets past it), so DESIGN.md's rule still holds. See src/view.rs.
if grep -rnE '\b(Rgb|Indexed)\(|\bColor::(from_u32|from_hsl|from_hsluv|from_str|from)\(|\bparse::<(::)?([A-Za-z_][A-Za-z0-9_]*::)*Color>' src; then
  echo "  RGB or 256-colour values in src/ (above): use the 16 named colours (DESIGN.md)" >&2
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
