#!/usr/bin/env bash
# Vendor the Foldkit repository at the pinned release into repos/foldkit: a
# gitignored, read-only reference for agents (FOLDKIT.md points at it). Rerun it
# after every Foldkit upgrade. Needs git, the network and Node 22 or newer.
#
# The release tag must still name the commit .foldkit-ref records (a tag can
# move), and the clone keeps its .git: repos/foldkit is its own repository, so
# a hook installer run there (Foldkit's `prepare` runs simple-git-hooks) writes
# into it, not into this project's .git.
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
# .foldkit-ref is one line, "<version> <commit>": the pinned release (check-pins.mjs
# holds it to the pin too) and the commit its tag named when it was reviewed.
commit="$(node -e '
const fail = message => {
  console.error("vendor-foldkit: " + message)
  process.exit(1)
}
let text = ""
try {
  text = require("fs").readFileSync(".foldkit-ref", "utf8")
} catch (error) {
  fail("cannot read .foldkit-ref (" + error.code + ")")
}
const ref = /^(\d+\.\d+\.\d+) ([0-9a-f]{40})\n$/.exec(text)
if (ref === null) {
  fail(".foldkit-ref must be one line, \"<version> <40-character lowercase commit>\", got " + JSON.stringify(text))
}
if (ref[1] !== process.argv[1]) {
  fail(".foldkit-ref records foldkit " + ref[1] + ", package.json pins " + process.argv[1] + ": update both together")
}
console.log(ref[2])' "$pin")"
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
cloned="$(git -C "$tmp/foldkit" rev-parse HEAD)"
if [ "$cloned" != "$commit" ]; then
  echo "vendor-foldkit: the tag foldkit@$pin is commit $cloned, but .foldkit-ref records $commit: it moved, or the record is wrong. Nothing was vendored; review the release before you change .foldkit-ref." >&2
  exit 1
fi
bounded "the sparse checkout" git -C "$tmp/foldkit" sparse-checkout set --no-cone \
  '/*' '!/repos/' '!AGENTS.md' '!CLAUDE.md' '!.mcp.json' '!.claude/' '!.agents/'
# Sparse patterns first; then make sure nothing matching slipped through (the
# clone's .git holds none of these names).
find "$tmp/foldkit" -depth \( -name .claude -o -name .agents \) -type d -not -path "$tmp/foldkit/.git/*" -exec rm -rf {} +
find "$tmp/foldkit" \( -name AGENTS.md -o -name CLAUDE.md -o -name .mcp.json \) -type f -not -path "$tmp/foldkit/.git/*" -exec rm -f {} +
[ ! -e "$tmp/foldkit/repos" ] || { echo "vendor-foldkit: the sparse checkout still has repos/" >&2; exit 1; }
printf '%s\n' "$pin" > "$tmp/foldkit/.vendored-version"
mkdir -p repos
rm -rf repos/foldkit.previous
if [ -e repos/foldkit ]; then mv repos/foldkit repos/foldkit.previous; fi
mv "$tmp/foldkit" repos/foldkit
rm -rf repos/foldkit.previous
echo "Vendored foldkit@$pin into repos/foldkit ($(du -sh repos/foldkit | awk '{print $1}'), gitignored)."
