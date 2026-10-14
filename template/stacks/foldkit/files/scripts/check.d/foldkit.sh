#!/usr/bin/env bash
# Foldkit stack guards (from ./bootstrap --stack foldkit), cheapest first; each
# fails closed. Runs from the repo root, before any test.
set -euo pipefail
die() { echo "  $*" >&2; exit 1; }
if ! command -v pnpm >/dev/null 2>&1; then
  die "pnpm is not installed - this project needs it: https://pnpm.io/installation (or Corepack)"
fi
if ! command -v perl >/dev/null 2>&1; then
  die "Perl is not installed: install Perl (including its core POSIX and Errno modules) for the bounded network commands."
fi
# The checkers run on the Node on PATH (pnpm's pinned Node runs only pnpm's own
# commands), and need 22 or newer.
case "$(node --version 2>/dev/null)" in
  v2[2-9].*|v[3-9][0-9].*|v[1-9][0-9][0-9]*) ;;
  *) die "Node.js 22 or newer must be on PATH for the checks (found: $(node --version 2>/dev/null || echo none)): install it from https://nodejs.org or with your version manager." ;;
esac
# pnpm 12 reads pnpm_config_* and PNPM_CONFIG_* settings from the environment
# over pnpm-workspace.yaml: clear the supply-chain ones, so every pnpm command
# here runs under the file's policy (after-bootstrap clears the same list).
for setting in minimum_release_age minimum_release_age_exclude minimum_release_age_exclude_prune \
  minimum_release_age_ignore_missing_time minimum_release_age_strict trust_lockfile trust_policy \
  trust_policy_exclude trust_policy_exclude_prune trust_policy_ignore_after strict_dep_builds \
  block_exotic_subdeps allow_builds dangerously_allow_all_builds; do
  unset "pnpm_config_$setting" "PNPM_CONFIG_$(printf '%s' "$setting" | tr '[:lower:]' '[:upper:]')"
done
node scripts/check-pins.mjs
# The rules the type checker can't see: Foldkit stays out of src/domain and
# src/api, no module mocks, the DevTools relay off, the MCP server pinned, .ts
# modules only in src.
node scripts/check-rules.mjs
# The lockfile must match package.json and pass the policy. --lockfile-only writes
# neither the lockfile (frozen) nor node_modules; it needs the registry only when
# pnpm's supply-chain verification of the lockfile isn't cached yet, and offline
# with a cold cache it waits instead of failing, so its process group is bounded (
# FOLDKIT_TEST_TIMEOUT shortens the limit for the template's tests). (--offline
# can't work here: pnpm 12 won't resolve the devEngines Node runtime offline;
# --dry-run exits 0 on a stale lockfile.)
limit="${FOLDKIT_TEST_TIMEOUT:-300}"
lock_rc=0
lock_pid=''
lock_tmp="$(mktemp "${TMPDIR:-/tmp}/foldkit-lock.XXXXXX")"
lock_status=''
trap 'rm -f "$lock_tmp" "$lock_status"' EXIT
lock_status="$(mktemp "${TMPDIR:-/tmp}/foldkit-lock-status.XXXXXX")"
interrupted() {
  trap '' HUP INT TERM
  if [ -n "$lock_pid" ]; then
    kill -TERM "$lock_pid" 2>/dev/null || :
    wait "$lock_pid" 2>/dev/null || :
  fi
  exit "$1"
}
trap 'interrupted 129' HUP
trap 'interrupted 130' INT
trap 'interrupted 143' TERM
perl scripts/bounded-command.pl --status-file "$lock_status" "$limit" pnpm install --frozen-lockfile --lockfile-only <&0 >"$lock_tmp" 2>&1 &
lock_pid=$!
wait "$lock_pid" || lock_rc=$?
lock_pid=''
lock_out="$(cat "$lock_tmp")"
# One complete outcome record must agree with the observed exit, including 0.
# A second line or unterminated trailing data is invalid, even if the first fits.
read_outcome() {
  bounded_outcome='' outcome_extra=''
  { IFS= read -r bounded_outcome && ! IFS= read -r outcome_extra && [ -z "$outcome_extra" ]; } < "$1" || return 1
  # Shell read may discard NUL bytes; compare the exact ASCII record length.
  [ "$(wc -c < "$1")" -eq "$((${#bounded_outcome} + 1))" ] || return 1
  case "$bounded_outcome" in
    "exit $2") return 0 ;;
    "signal $2") [ "$2" -gt 128 ] && [ "$2" -le 255 ] ;;
    'timeout 142') [ "$2" = 142 ] ;;
    'internal 125') [ "$2" = 125 ] ;;
    *) return 1 ;;
  esac
}
if ! read_outcome "$lock_status" "$lock_rc"; then
  printf '%s\n' "$lock_out" >&2
  die "the command supervisor returned no valid outcome: check Perl and scripts/bounded-command.pl (exit $lock_rc)."
fi
rm -f "$lock_tmp" "$lock_status"
trap - EXIT HUP INT TERM
case "$bounded_outcome" in
  signal\ *) exit "$lock_rc" ;;
  internal\ *) printf '%s\n' "$lock_out" >&2; die "the command supervisor failed: check its error above." ;;
esac
if [ "$bounded_outcome" = 'timeout 142' ]; then
  printf '%s\n' "$lock_out" >&2
  die "the lockfile check timed out after ${limit}s (offline? pnpm verifies the lockfile against the registry once per cache)."
elif [ "$lock_rc" != 0 ]; then
  case "$lock_out" in
    # Only a young release: pnpm's help (rebuild the lockfile, or relax the
    # policy) is the wrong advice for it.
    *ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION*)
      printf '%s\n' "$lock_out" | sed '/^[[:space:]]*help:/,$d' >&2
      die "a locked release is younger than pnpm-workspace.yaml's minimumReleaseAge, 24 hours (above): it installs once it is a day old. Wait, or exempt the new train releases exactly (name@version) in minimumReleaseAgeExclude; see docs/guides/foldkit.md." ;;
    *ERR_PNPM_OUTDATED_LOCKFILE*|*ERR_PNPM_FROZEN_LOCKFILE_WITH_OUTDATED_LOCKFILE*|*ERR_PNPM_NO_LOCKFILE*|*ERR_PNPM_LOCKFILE_NOT_FOUND*)
      printf '%s\n' "$lock_out" >&2
      die "pnpm-lock.yaml is missing or out of date with package.json: run pnpm install and commit pnpm-lock.yaml." ;;
  esac
  # Only pnpm's actual supply-chain evidence warrants integrity advice.
  printf '%s\n' "$lock_out" >&2
  case "$lock_out" in
    *ERR_PNPM_LOCKFILE_RESOLUTION_VERIFICATION*|*ERR_PNPM_TRUST_DOWNGRADE*|*ERR_PNPM_TARBALL_INTEGRITY*)
      die "pnpm rejected the locked dependencies (above). pnpm-lock.yaml or a dependency may have been tampered with: review pnpm-lock.yaml's recent changes before you regenerate it (docs/guides/foldkit.md)." ;;
  esac
  die "the lockfile command failed (exit $lock_rc; see above): check command startup, network access and pnpm's reported error before retrying."
fi
case "$(pnpm exec tsc --version 2>/dev/null || true)" in
  *+effect-tsgo*) ;;
  *) die "tsc is not patched by @effect/tsgo, so the Effect rules would not run: run pnpm install (its prepare script runs effect-tsgo patch)." ;;
esac
pnpm exec tsc --noEmit
# --disable-nested-config: oxlint would otherwise load repos/foldkit/.oxlintrc.json
# (the vendored copy) despite ignorePatterns, whenever .gitignore doesn't hide it.
pnpm exec oxlint --type-aware --deny-warnings --disable-nested-config
echo "  oxlint: clean"
pnpm exec oxfmt --check src e2e vite.config.ts vitest.config.ts playwright.config.ts
node scripts/coverage-tiers.mjs --validate
if [ "${CHECK_CI:-0}" != 1 ]; then
  pin="$(node -p 'require("./package.json").dependencies.foldkit')"
  if [ "$(cat repos/foldkit/.vendored-version 2>/dev/null || true)" != "$pin" ]; then
    echo "  WARNING: repos/foldkit is missing or not foldkit@$pin: run bash scripts/vendor-foldkit.sh (agents read it; see FOLDKIT.md)."
  fi
fi
