#!/usr/bin/env bash
# Probe 3: --stack _rust-gates must exit 2 before any write.
set -uo pipefail
repo="$1"
for v in $(git -C "$repo" rev-parse --local-env-vars); do unset "$v"; done
work="$(mktemp -d "${TMPDIR:-/tmp}/qa-p3.XXXXXX")"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/proj" "$work/home"
(cd "$repo" && git ls-files -z --cached --others --exclude-standard | xargs -0 tar -cf -) | tar -xf - -C "$work/proj"
before="$(cd "$work/proj" && find . -type f -exec shasum {} + | sort | shasum)"
(cd "$work/proj" && HOME="$work/home" ./bootstrap --name demo --stack _rust-gates --yes </dev/null >"$work/out" 2>&1); rc=$?
after="$(cd "$work/proj" && find . -type f -exec shasum {} + | sort | shasum)"
printf '{"exit":%d,"unchanged":%s,"message":"%s"}\n' "$rc" "$([ "$before" = "$after" ] && echo true || echo false)" "$(head -1 "$work/out" | tr '"' "'")"
