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
# Runs before pnpm has installed anything, on the Node on PATH: 22 or newer.
case "$(node --version 2>/dev/null)" in
  v2[2-9].*|v[3-9][0-9].*|v[1-9][0-9][0-9]*) ;;
  *) echo "vendor-foldkit: Node.js 22 or newer must be on PATH (found: $(node --version 2>/dev/null || echo none)): install it from https://nodejs.org or with your version manager." >&2
     exit 1 ;;
esac
pin="$(node -p 'require("./package.json").dependencies.foldkit')"
case "$pin" in
  ''|*[!0-9.]*|.*|*.) echo "vendor-foldkit: package.json must pin foldkit to an exact release (got '$pin')" >&2; exit 1 ;;
esac
tmp="$(mktemp -d "${TMPDIR:-/tmp}/vendor-foldkit.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
# The clone and the sparse checkout (which downloads the files) are bounded:
# offline, git can wait a long time. FOLDKIT_TEST_TIMEOUT shortens the limit for
# the template's tests.
limit="${FOLDKIT_TEST_TIMEOUT:-600}"
bounded() {  # $1 = what it does, rest = the command
  local what="$1" rc=0
  shift
  perl -e 'alarm shift; exec { $ARGV[0] } @ARGV or die "cannot run $ARGV[0]: $!\n"' "$limit" "$@" || rc=$?
  [ "$rc" != 142 ] || echo "vendor-foldkit: $what timed out after ${limit}s (offline?)" >&2
  return "$rc"
}
bounded "git clone" git -c advice.detachedHead=false clone --quiet --depth 1 --filter=blob:none --sparse \
  --branch "foldkit@$pin" https://github.com/foldkit/foldkit.git "$tmp/foldkit"
bounded "the sparse checkout" git -C "$tmp/foldkit" sparse-checkout set --no-cone \
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
