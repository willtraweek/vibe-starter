# Already-known findings on this branch (do NOT re-report unless you add new evidence, a new variant, or a broader blast radius)

Source: prior report-only review of this same tree (.context/integration/review.md, issue20-audit.md). These remain OPEN; this review pass is expected to find what they MISSED.

## Omarchy
- K1 omarchy-plugin/files/scripts/omarchy-kit:26-28 — concurrent cold cache init can rm -rf a cache already returned to another caller (race, reproduced).
- K2 omarchy-app/commands:8 and omarchy-tui/commands:8 — SHIP_GATE omits `cargo test --locked --doc` that their ci.yml runs; parity test only checks the rust pack.
- K3 omarchy-app/tui files/scripts/install.sh:30, omarchy-plugin dev-link.sh:10, omarchy-kit:9, tests/run:6 — bare `cd` without `CDPATH=''`.
- K4 Toolchain pins: STACK=…Rust 1.98… in omarchy-app/tui commands unchecked by the pin-consistency test; omarchy_app_heavy_ready / omarchy_tui_heavy_ready hard-code `-ge 98` (duplicate rust_ready).

## Foldkit (issue #20 items, all open in template/stacks/foldkit and plans/011)
- 1-4 plan 011 stale anchors / historical SHAs / no manifest regeneration recipe / train move can replay old pins.
- 5 validate-name blocklist rationale (playwright vs @playwright/test).
- 6 check.d/foldkit.sh boundary guard misses subpath (`foldkit/schema`), side-effect and dynamic imports.
- 7 guard checks only vi.mock (not vi.doMock etc.); MCP check only greps .mcp.json for npx (pnpm dlx passes).
- 8 no negative tests proving type-aware oxlint / oxfmt fail closed.
- 9 @foldkit/ui not pinned directly.
- 10 age-rule exemptions cover whole @foldkit/* and @effect/* scopes.
- 11 docs/guides/foldkit.md tells users to disable the age rule for every pnpm command.
- 12 vendor-foldkit.sh clones a tag without verifying an immutable commit.
- 13 no light test pins the pnpm-workspace.yaml supply-chain policy lines.
- 14 bare `node` calls (check.d, coverage.sh, vendor script) without an actionable prerequisite error.
- 15 look helper does not preflight preview port 4000.
- 21 coverage-tiers.mjs counts commented/skipped Playwright journeys as present; ratchet ignores journeys; heavy assertion matches substring "1 passed".
- 22 (P1) devToolsMcpPort guard bypassable by alias, inline comment, alternate vite config file.
- 23 guard passes src/domain and src/api together to grep and treats status 2 (missing dir) as no match.
- 24 after-bootstrap unbounded network install; generated ci.yml has no timeout-minutes.
- 25 lockfile helper replaces lockfile without hash/diff review (decision item).
- 26 guard reports every supply-chain policy failure as the age error.
- 27 src/api/status.ts fetch+decode has no timeout.
- 28 pack gitignore ignores only /repos/foldkit/, not repos/foldkit.previous.
- Advisories 16-19: coverage-tiers hand-written arg parsing; train.mjs semver scan; check-pins own peer-range checker; vite-env.d.ts duplicate.

## Rust (deferred by the maintainer as GitHub issues; integration now spreads them via _rust-gates to omarchy-app/tui)
- #10 ratchet cannot retire a moved/deleted tier member; #12 starter CLI panics on non-UTF-8 arg / closed stdout (also omarchy main.rs print!); #13 selftest replays only the ratchet step of generated ci.yml; #14 default-feature lint/coverage + CARGO_BUILD_WARNINGS parity; #15 llvm-cov ignore list; #16 shared /tmp cargo/uv config; #17 coverage-exclusion approval; #18 ratchet export-ignore fail-open, macOS path case, name length.

## Checked and REJECTED by the prior review (do not re-raise without new evidence)
- foldkit after-bootstrap/validate-name mode 100644: bootstrap runs hooks via `sh`, so execution works.
- project-name quote/backslash injection into code literals: bootstrap's name allowlist excludes quotes/backslashes.
- light CI job missing python3/jq or exceeding 15 min: hosted run 38471060775 passed selftest (~4.5 min) and heavy (~12 min) with zero skips.
