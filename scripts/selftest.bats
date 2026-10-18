#!/usr/bin/env bats
# Lane name for gstack pregate. scripts/pregate-lane.sh runs the suite when
# this file is selected. Quoted paths are the import-graph edges:
# 'scripts/check.sh' 'scripts/template-selftest.sh' 'scripts/pregate-lane.sh' 'bootstrap'

@test "template self-test covers the guard and the suite" {
  run ./scripts/template-selftest.sh
  [ "$status" -eq 0 ]
}
