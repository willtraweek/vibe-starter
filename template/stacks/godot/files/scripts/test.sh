#!/usr/bin/env bash
# The tests: ./scripts/test.sh [filter]. Every test_* method of every tests/**/test_*.gd,
# headless, at a fixed 60 frames a second: each physics tick is exactly 1/60 s of game time,
# and ticks run as fast as the machine can. A filter keeps the tests whose id (path::method)
# contains it. No coverage here: ./scripts/coverage.sh is the gate.
set -euo pipefail
CDPATH='' cd -- "$(dirname -- "$0")/.."   # a CDPATH entry must not pick the directory
./scripts/import.sh
exec ./scripts/godot.sh --headless --fixed-fps 60 -s res://tools/test/run.gd -- "$@"
