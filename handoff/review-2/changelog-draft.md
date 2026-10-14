## [0.3.0] - 2026-10-1X

### Added
- Five stack packs, chosen by what the app does. `./bootstrap --stack rust` starts a Rust
  project on a pinned toolchain with clippy pedantic, rustfmt and cargo-llvm-cov's 90% line and
  region floors plus per-tier gates. `omarchy-app` is an Omarchy desktop app in its own window
  (Rust, GPUI and gpui-omarchy, which follow the active theme), `omarchy-tui` a keyboard-driven
  terminal app (Rust and ratatui), and `omarchy-plugin` a QML bar widget for Omarchy's shell,
  checked by Omarchy's own validator at a pinned release. `foldkit` is a browser app on Foldkit
  (the Elm architecture on Effect v4) with TypeScript 7, Vite 8, Vitest 5 Story and Scene tests,
  Playwright journeys and pnpm 12 with a reviewed lockfile and a supply-chain policy.
- `./bootstrap --help` and the interactive prompt list each pack with a one-line description,
  and a pack can include a partial pack (`template/stacks/_name/`): the three Rust packs share
  one copy of their gates in `_rust-gates`.
- Guards in `scripts/check.d/` learn whether CI requires a missing tool (`CHECK_CI`), and the
  template's CI gains a `heavy` job that builds real projects from every pack.

### Fixed (found by the pre-landing review)
- (fill from the final review: omarchy-kit cache race and release-only pin; CDPATH; doctests in
  the Omarchy SHIP_GATE; installer hardening; foldkit guards rewritten on a restricted parser;
  journeys verified from Playwright's report; supply-chain policy and vendoring provenance;
  keyboard and orientation fixes; python names that bootstrap leaves unfilled; ...)
