#!/usr/bin/env bash
# Probe 7: omarchy-app install.sh run as `bash scripts/install.sh` with an exported CDPATH
# whose entry also has scripts/: the project's own desktop entry must be printed.
set -uo pipefail
repo="$1"
for v in $(git -C "$repo" rev-parse --local-env-vars); do unset "$v"; done
work="$(mktemp -d "${TMPDIR:-/tmp}/qa-p7.XXXXXX")"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/proj" "$work/bin" "$work/home" "$work/decoy/scripts" "$work/decoy/packaging"
(cd "$repo" && git ls-files -z --cached --others --exclude-standard | xargs -0 tar -cf -) | tar -xf - -C "$work/proj"
printf '#!/bin/sh\nexit 101\n' > "$work/bin/cargo"; chmod +x "$work/bin/cargo"
(cd "$work/proj" && git init -q && git add -A && git -c user.name=qa -c user.email=qa@example.invalid commit -qm base)
(cd "$work/proj" && HOME="$work/home" PATH="$work/bin:$PATH" ./bootstrap --name "Demo App" --stack omarchy-app --yes </dev/null >"$work/out" 2>&1) || { echo '{"setup":"bootstrap failed"}'; exit 0; }
printf 'Name=DECOY @BINDIR@\n' > "$work/decoy/packaging/app.desktop.in"; printf '9.9.9\n' > "$work/decoy/VERSION"
(cd "$work/proj" && CDPATH="$work/decoy" bash scripts/install.sh --print-desktop-entry >"$work/entry" 2>"$work/err"); rc=$?
printf '{"exit":%d,"first_line":"%s","mentions_decoy":%s}\n' "$rc" "$(head -1 "$work/entry" | sed "s|$work|WORK|g")" "$(grep -q DECOY "$work/entry" && echo true || echo false)"
