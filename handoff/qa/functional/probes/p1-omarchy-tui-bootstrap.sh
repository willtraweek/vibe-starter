#!/usr/bin/env bash
# Probe 1: bootstrap --stack omarchy-tui in an owned scratch copy (stub cargo, no network).
set -uo pipefail
repo="$1"
for v in $(git -C "$repo" rev-parse --local-env-vars); do unset "$v"; done
work="$(mktemp -d "${TMPDIR:-/tmp}/qa-p1.XXXXXX")"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/proj" "$work/bin" "$work/home"
(cd "$repo" && git ls-files -z --cached --others --exclude-standard | xargs -0 tar -cf -) | tar -xf - -C "$work/proj"
printf '#!/bin/sh\necho "cargo $*" >> "%s/cargo.calls"\nexit 101\n' "$work" > "$work/bin/cargo"; chmod +x "$work/bin/cargo"
(cd "$work/proj" && git init -q && git add -A && git -c user.name=qa -c user.email=qa@example.invalid commit -qm base)
(cd "$work/proj" && HOME="$work/home" PATH="$work/bin:$PATH" ./bootstrap --name "Demo App" --stack omarchy-tui --yes </dev/null >"$work/out" 2>&1); rc=$?
present=0; for f in rust-toolchain.toml rustfmt.toml scripts/coverage.sh scripts/coverage_tiers.sh scripts/check.d/rust.sh scripts/install.sh scripts/check.d/omarchy.sh src/main.rs; do [ -f "$work/proj/$f" ] && present=$((present+1)); done
execs=0; for f in scripts/coverage.sh scripts/coverage_tiers.sh scripts/check.d/rust.sh scripts/install.sh; do [ -x "$work/proj/$f" ] && execs=$((execs+1)); done
template_left=0; [ -d "$work/proj/template" ] && template_left=1
printf '{"bootstrap_exit":%d,"expected_files_present":"%d/8","executable":"%d/4","template_dir_left":%d,"cargo_calls":"%s"}\n' "$rc" "$present" "$execs" "$template_left" "$(tr '\n' ';' < "$work/cargo.calls" 2>/dev/null)"
