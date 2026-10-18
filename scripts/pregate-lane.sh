#!/bin/bash
# gstack pregate substitutes the selected test files for {files}. This
# template has one suite, scripts/template-selftest.sh. The lane file
# scripts/selftest.bats is only the name pregate can see. A pack test can
# also be selected when it names a template path (the Python pack's
# test_cli.py joins a path ending in VERSION). Those files still contain
# bootstrap placeholders, so the lane runs the template suite once.
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "pregate-lane: expected scripts/selftest.bats" >&2
  exit 1
fi

for f in "$@"; do
  case "$f" in
    scripts/selftest.bats|template/stacks/*) ;;
    *)
      echo "pregate-lane: unknown test file: $f" >&2
      exit 1
      ;;
  esac
done

# Local lane. GitHub Actions sets CI=true on the workflow; an agent harness
# that exports CI=true would turn the suite's allowed local skips into failures.
unset CI
exec ./scripts/template-selftest.sh
