#!/usr/bin/env bash
# Omarchy plugin guards (from ./bootstrap --stack omarchy-plugin): VERSION and
# manifest.json in step, then Omarchy's own plugin rules at .omarchy-ref, run
# on exactly what `omarchy plugin add` would clone.
set -euo pipefail

# 1. gstack /ship bumps VERSION and, through .gstack/package-json-path, writes its
#    npm form (the first three parts) into manifest.json in its 2-space JSON form.
#    Keep both true.
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

# 3. Every Text whose text isn't a literal declares textFormat (Omarchy's own
#    scanner; the plugin directory's reviewers require it too). Tests are exempt;
#    paths are kept, so same-named files in two folders are both scanned.
(cd "$tmp/plugin" && find . -name '*.qml' -not -path './tests/*' -print0 | tar --null -T - -cf -) \
  | tar -xf - -C "$tmp/scan/shell"
findings="$(python3 "$kit/test/shell.d/qml-text-format-scan.py" "$tmp/scan")"
if [ -n "$findings" ]; then
  printf '%s\n' "$findings" >&2
  exit 1
fi
