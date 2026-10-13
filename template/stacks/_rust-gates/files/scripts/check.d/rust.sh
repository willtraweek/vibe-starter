#!/usr/bin/env bash
# Rust stack guards (from a vibe-starter Rust stack pack): formatting, lints, and the
# coverage-tier config (cheap; runs before any tests).
set -euo pipefail
if ! command -v cargo >/dev/null 2>&1; then
  echo "  cargo is not installed - this project needs Rust: https://rustup.rs" >&2
  exit 1
fi
cargo fmt --all --check
cargo clippy --locked --all-targets --all-features --quiet -- -D warnings
./scripts/coverage_tiers.sh --validate
