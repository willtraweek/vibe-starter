#!/usr/bin/env bash
# Omarchy plugin guards (from ./bootstrap --stack omarchy-plugin): VERSION and
# manifest.json in step, then Omarchy's own plugin rules at .omarchy-ref and
# DESIGN.md's QML rules (tokens only, plain-text Labels), run on exactly what
# `omarchy plugin add` would clone.
set -euo pipefail

# 1. gstack /ship bumps VERSION and, through .gstack/package-json-path, writes its
#    npm form (the first three parts) into manifest.json in its 2-space JSON form.
#    Keep all three true.
if [ "$(head -n 1 .gstack/package-json-path 2>/dev/null)" != manifest.json ]; then
  echo "  .gstack/package-json-path must hold the line manifest.json, or gstack /ship bumps VERSION alone: restore it and commit it" >&2
  exit 1
fi
version="$(tr -d '[:space:]' < VERSION | cut -d. -f1-3)"
manifest_version="$(jq -r .version manifest.json)"
if [ "$manifest_version" != "$version" ]; then
  echo "  manifest.json has version $manifest_version but VERSION says $version" >&2
  exit 1
fi
if ! jq --indent 2 . manifest.json | cmp -s - manifest.json; then
  echo "  manifest.json is not in 2-space JSON form (run: jq --indent 2 . manifest.json)" >&2
  exit 1
fi

# 2. The plugin as users get it: the files git would commit, nothing local. Links
#    stay links, so the validator sees (and refuses) them as users would get them.
kit="$(./scripts/omarchy-kit)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/plugin" "$tmp/scan/shell"
git ls-files -z --cached --others --exclude-standard \
  | while IFS= read -r -d '' f; do if [ -f "$f" ] || [ -L "$f" ]; then printf '%s\0' "$f"; fi; done \
  | tar --null -T - -cf - | tar -xf - -C "$tmp/plugin"
bash "$kit/bin/omarchy-plugin-validate" "$tmp/plugin"

# 3. The plugin's own QML as users get it, without its tests. Paths are kept,
#    so same-named files in two folders are both checked.
(cd "$tmp/plugin" && find . -name '*.qml' -not -path './tests/*' -print0 | tar --null -T - -cf -) \
  | tar -xf - -C "$tmp/scan/shell"

# 4. Tokens only (DESIGN.md): a colour or size written into QML stays put when
#    `omarchy theme set` or `omarchy display text size` changes the shell. The
#    checks read text, not types (`width: 2 * 12` gets past them), so DESIGN.md's
#    rule still holds.
refuse() {  # $1 = an extended regex for what DESIGN.md bans in QML, $2 = what it found
  if (cd "$tmp/scan/shell" && grep -rnE --include='*.qml' -- "$1" .) | sed 's|^\./||' >&2; then
    echo "  $2 (DESIGN.md)" >&2
    exit 1
  fi
}
refuse "[\"']#[0-9A-Fa-f]{3,12}[\"']|\bQt\.(rgba|rgb|hsla|hsva)\(" \
  "fixed colours in QML (above): bind to Color.* or the bar's colours"
refuse '\b([A-Z][A-Za-z]*)?Gradient\b' "gradients in QML (above): bind to the shell's colours"
# A whole number other than 0 and 1 bound on its own to a size.
refuse '(^|[^A-Za-z0-9_])(width|height|implicitWidth|implicitHeight|pixelSize|pointSize|spacing|margins|[A-Za-z]*Margin|radius)[[:space:]]*:[[:space:]]*-?([2-9]|[1-9][0-9]+)(\.[0-9]*)?[[:space:]]*(;|}|//|$)' \
  "fixed pixel sizes in QML (above): use Style.space(px), Style.spacing.*, Style.bar.* or Style.font.*"

# 5. Every Text whose text isn't a literal declares textFormat (Omarchy's own
#    scanner; the plugin directory's reviewers require it too).
findings="$(python3 "$kit/test/shell.d/qml-text-format-scan.py" "$tmp/scan")"
if [ -n "$findings" ]; then
  printf '%s\n' "$findings" >&2
  exit 1
fi

# 6. A QtQuick.Controls Label is a Text whose textFormat also defaults to
#    AutoText, but Omarchy's scanner reads only Text. So scan a copy in which
#    every Label is a Text and nothing else is, with each textFormat but
#    PlainText hidden: a Label whose text isn't a literal must be plain text
#    (DESIGN.md). The copy keeps every line where it was.
mkdir -p "$tmp/labels"
cp -R "$tmp/scan/shell" "$tmp/labels/shell"
find "$tmp/labels/shell" -name '*.qml' -exec perl -pi -e '
  s/\btextFormat(?=\s*:(?!\s*(?:[A-Za-z_]\w*\.)?(?:Text|Label)\.PlainText\b))/textFormatNotPlain/g;
  s/(^|[\s:.])Text(?=\s*(?:\{|$))/${1}NotText/g;
  s/(^|[\s:.])Label(?=\s*(?:\{|$))/${1}Text/g;
' {} +
findings="$(python3 "$kit/test/shell.d/qml-text-format-scan.py" "$tmp/labels")"
if [ -n "$findings" ]; then
  printf '%s\n' "$findings" >&2
  echo "  a Label above shows text that isn't a literal: give it textFormat: Text.PlainText (DESIGN.md)" >&2
  exit 1
fi
