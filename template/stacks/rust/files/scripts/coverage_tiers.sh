#!/usr/bin/env bash
# Line/region tier gates for one root package. Multi-package and virtual Cargo
# workspaces, and local path dependencies (a second crate the lints and coverage
# never see), need a reviewed extension of both coverage collection and this gate.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "coverage-tiers: FAIL $*" >&2; exit 1; }
command -v cargo >/dev/null 2>&1 || fail "cargo is required"
command -v jq >/dev/null 2>&1 || fail "jq is required: https://jqlang.org/download/"

tiers_of() {  # Read the package at this exact manifest, never .packages[0].
  local manifest root metadata
  root="$(cd "$(dirname "$1")" && pwd -P)"
  manifest="$root/$(basename "$1")"
  metadata="$(cargo metadata --offline --format-version 1 --no-deps --manifest-path "$manifest")" \
    || { echo "coverage-tiers: cannot read Cargo metadata for $manifest" >&2; return 1; }
  jq -ce --arg manifest "$manifest" --arg root "$root" '
    [.packages[] | select(.manifest_path == $manifest)] as $p |
    if ($p | length) != 1 or .workspace_root != $root
      or (.workspace_members | length) != 1 or .workspace_members[0] != $p[0].id
      or any($p[0].dependencies[]; .path != null)
    then error("only one root package is supported; workspaces and local path dependencies require a gate migration")
    else $p[0].metadata.coverage_tiers end' <<<"$metadata"
}

validate_schema() {  # Explicit empty tiers are allowed; missing/malformed config is not.
  jq -e '
    def path_ok: type == "string" and test("^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$")
      and (test("(^|/)\\.\\.?(/|$)") | not);
    type == "object" and length > 0 and
    all(to_entries[]; (.key | test("^[a-z][a-z0-9_]*$")) and
      (.value | type == "object" and
        (.minimum | type == "number") and (.target | type == "number") and
        (0 <= .minimum and .minimum <= .target and .target <= 100) and
        (.include | type == "array" and all(.[]; path_ok)) and
        (.title == null or (.title | type == "string")))) and
    ([.[].include[]] | length > 0 and length == (unique | length))
  ' <<<"$1" >/dev/null || fail "invalid tier schema, empty membership, or duplicate membership"
}

validate() {  # The schema, then every member must be a file in this tree.
  validate_schema "$1"
  while IFS= read -r path; do
    [ -f "$path" ] || fail "include '$path' is not a file"
  done < <(jq -r '.[].include[]' <<<"$1")
}

measure() {  # Fail before printing any rows for malformed/missing measurements.
  jq -ce --arg root "$(pwd -P)/" --argjson tiers "$1" '
    def counter_ok:
      type == "object" and (.count | type == "number" and isfinite) and
      (.covered | type == "number" and isfinite) and
      (.count <= 9007199254740991) and
      (.count > 0 and .covered >= 0 and .covered <= .count) and
      (.count == (.count | floor) and .covered == (.covered | floor));
    if .type != "llvm.coverage.json.export" or (.data | type) != "array" or (.data | length) != 1
      or (.data[0].files | type) != "array" or (.data[0].files | length) == 0
    then error("invalid coverage report schema") else . end |
    .data[0].files as $entries |
    if (all($entries[]; (.filename | type) == "string") | not)
      or ([$entries[].filename | ltrimstr($root)] | length != (unique | length))
    then error("invalid or duplicate report filenames") else . end |
    [$entries[] | {key: (.filename | ltrimstr($root)), value: .summary}] | from_entries as $files |
    [$tiers | to_entries[] | .key as $k | .value as $tier |
      [$tier.include[] | . as $path |
        if $files[$path] == null then error("\($k): not in the coverage report: \($path)")
        elif ([$files[$path].lines, $files[$path].regions] | all(.[]; counter_ok) | not)
        then error("\($k): invalid or zero-count measurements for \($path)")
        else $files[$path] end] as $s |
      {key: $k, title: ($tier.title // $k), minimum: $tier.minimum, target: $tier.target,
        lines: (if ($s | length) == 0 then null else 100 * ([$s[].lines.covered] | add) / ([$s[].lines.count] | add) end),
        regions: (if ($s | length) == 0 then null else 100 * ([$s[].regions.covered] | add) / ([$s[].regions.count] | add) end)}]
  ' "$2"
}

mode="${1:-}"
case "$mode:$#" in
  --validate:1|--check:1|--check:2|--report:1|--report:2|--ratchet:2) ;;
  *) echo "usage: $0 --validate | --check [report] | --report [report] | --ratchet REF" >&2; exit 2 ;;
esac
tiers="$(tiers_of Cargo.toml)" || fail "cannot load tiers for the root package"
validate "$tiers"
case "$mode" in
  --validate) ;;
  --check|--report)
    report="${2:-coverage.json}"
    [ -f "$report" ] || fail "$report not found (run scripts/coverage.sh)"
    rows="$(measure "$tiers" "$report")" || fail "unusable coverage report"
    errors="$(jq -r '.[] | . as $t | ["lines", "regions"][] as $metric |
      select($t[$metric] != null and $t[$metric] < $t.minimum) |
      "\($t.key): \($metric) coverage \($t[$metric])% is below its minimum \($t.minimum)%"' <<<"$rows")"
    [ -z "$errors" ] || fail "$errors"
    if [ "$mode" = "--report" ]; then
      echo "| Tier | Lines | Regions | Minimum | Target |"
      echo "|---|---|---|---|---|"
      jq -r '.[] | "| \(.title) | \(.lines // "n/a (empty tier)") | \(.regions // "n/a (empty tier)") | \(.minimum)% | \(.target)% |"' <<<"$rows"
      exit 0
    fi ;;
  --ratchet)
    base="$(git rev-parse --verify "${2}^{commit}")" || fail "cannot resolve base $2"
    old_dir="$(mktemp -d)"; trap 'rm -rf "$old_dir"' EXIT
    # Restore the complete base tree so metadata sees its actual targets/paths.
    git archive "$base" | tar -x -C "$old_dir" || fail "cannot read base tree"
    # A base from before the pack (a new project's first pull request) has nothing
    # to ratchet against; an unreadable tree (above) or unreadable metadata fails.
    if [ ! -f "$old_dir/Cargo.toml" ]; then
      echo "coverage-tiers: no Cargo.toml at $2; nothing to ratchet against"; exit 0
    fi
    # tiers_of prints null (and fails) only when the base package has no tiers.
    old="$(tiers_of "$old_dir/Cargo.toml")" || {
      [ "$old" = null ] || fail "cannot read base tiers"
      echo "coverage-tiers: no coverage tiers at $2; nothing to ratchet against"; exit 0; }
    # Only the base's schema counts: a base that lists a member it never committed
    # must not block the pull request that adds the file.
    (validate_schema "$old") || fail "invalid base tiers"
    errors="$(jq -r --argjson new "$tiers" 'to_entries[] | .key as $k |
      if $new[$k] == null then "\($k): tier removed since the base"
      else
        (.value as $old | ["minimum", "target"][] as $field |
          if $new[$k][$field] < $old[$field]
          then "\($k): \($field) lowered from \($old[$field]) to \($new[$k][$field])" else empty end),
        ((.value.include - $new[$k].include)[] | "\($k): member removed since the base: \(.)")
      end' <<<"$old")"
    [ -z "$errors" ] || fail "$errors" ;;
esac
echo "coverage-tiers: $(jq 'length' <<<"$tiers") tier(s) ok"
