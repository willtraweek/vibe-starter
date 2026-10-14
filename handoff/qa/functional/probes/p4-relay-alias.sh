#!/usr/bin/env bash
# Probe 4: the CURRENT foldkit relay guard lines against an aliased numeric port.
set -uo pipefail
repo="$1"
work="$(mktemp -d "${TMPDIR:-/tmp}/qa-p4.XXXXXX")"; trap 'rm -rf "$work"' EXIT
printf 'const falsePort = 9988\nfoldkit({ devToolsMcpPort: falsePort })\n' > "$work/vite.config.ts"
# Lines 45-48 of the shipped guard, verbatim.
sed -n '45,48p' "$repo/template/stacks/foldkit/files/scripts/check.d/foldkit.sh" > "$work/fragment.sh"
(cd "$work" && bash -c 'die() { echo "$*" >&2; exit 1; }; set -euo pipefail; . ./fragment.sh' >"$work/out" 2>&1); rc=$?
printf '{"guard_exit":%d,"expected_exit":1,"guard_output":"%s"}\n' "$rc" "$(tr '\n"' "; " < "$work/out")"
