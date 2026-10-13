#!/usr/bin/env bash
# Vendor the Foldkit repository at the pinned release into repos/foldkit: a
# gitignored, read-only reference for agents (FOLDKIT.md points at it). Rerun it
# after every Foldkit upgrade. Needs git and the network.
#
# Left out on purpose: repos/ (Foldkit's own copy of Effect; node_modules/effect
# ships Effect's source) and Foldkit's maintainer agent files (AGENTS.md,
# CLAUDE.md, .mcp.json, .claude/, .agents/), which would otherwise load as
# instructions for this project's agents.
set -euo pipefail
CDPATH='' cd -- "$(dirname -- "$0")/.."
pin="$(node -p 'require("./package.json").dependencies.foldkit')"
case "$pin" in
  ''|*[!0-9.]*|.*|*.) echo "vendor-foldkit: package.json must pin foldkit to an exact release (got '$pin')" >&2; exit 1 ;;
esac
tmp="$(mktemp -d "${TMPDIR:-/tmp}/vendor-foldkit.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
git -c advice.detachedHead=false clone --quiet --depth 1 --filter=blob:none --sparse \
  --branch "foldkit@$pin" https://github.com/foldkit/foldkit.git "$tmp/foldkit"
git -C "$tmp/foldkit" sparse-checkout set --no-cone \
  '/*' '!/repos/' '!AGENTS.md' '!CLAUDE.md' '!.mcp.json' '!.claude/' '!.agents/'
rm -rf "$tmp/foldkit/.git"
# Sparse patterns first; then make sure nothing matching slipped through.
find "$tmp/foldkit" -depth \( -name .claude -o -name .agents \) -type d -exec rm -rf {} +
find "$tmp/foldkit" \( -name AGENTS.md -o -name CLAUDE.md -o -name .mcp.json \) -type f -exec rm -f {} +
[ ! -e "$tmp/foldkit/repos" ] || { echo "vendor-foldkit: the sparse checkout still has repos/" >&2; exit 1; }
printf '%s\n' "$pin" > "$tmp/foldkit/.vendored-version"
mkdir -p repos
rm -rf repos/foldkit.previous
if [ -e repos/foldkit ]; then mv repos/foldkit repos/foldkit.previous; fi
mv "$tmp/foldkit" repos/foldkit
rm -rf repos/foldkit.previous
echo "Vendored foldkit@$pin into repos/foldkit ($(du -sh repos/foldkit | awk '{print $1}'), gitignored)."
