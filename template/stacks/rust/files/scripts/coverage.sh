#!/usr/bin/env bash
# Coverage gate (TESTING.md): 90% line and region floors, then the per-tier gates.
# CI runs this; plain `cargo test` skips coverage on purpose. Stable Rust has no
# branch coverage yet (cargo-llvm-cov --branch is nightly-only), so region
# coverage stands in for it.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! cargo llvm-cov --version >/dev/null 2>&1; then
  echo "cargo-llvm-cov is not installed: cargo install --locked cargo-llvm-cov" >&2
  exit 1
fi
cargo llvm-cov --locked --all-features --no-report
cargo llvm-cov report --fail-under-lines 90 --fail-under-regions 90
cargo llvm-cov report --json --summary-only --output-path coverage.json
./scripts/coverage_tiers.sh --check coverage.json
