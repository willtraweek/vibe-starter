# Foldkit issue #20 audit

Audited 2026-10-13 against immutable source commit `e5a64fd` (the local Foldkit implementation tip), plus current GitHub issue state and master. No tracked files changed; no comments, issue updates, pushes, or PR operations performed.

## Result

**23 required findings remain unresolved at `e5a64fd`; 4 are optional advisories; item 20 alone is already fixed on master by PR #21.** The implementation predates the findings: its tip is 2026-10-02, while the issue review is 2026-10-04. The issue is CLOSED, but its last comment explicitly says items 1–19 and 21–28 remain open for the implementation PR. The closed state is not clearance to merge.

Source: https://github.com/willtraweek/vibe-starter/issues/20 and final disposition comment https://github.com/willtraweek/vibe-starter/issues/20#issuecomment-5985594106. Full fetched body/comments are saved in `issue20-source.json` beside this report.

The issue's explicit gate: before the implementation merges or row 011 is DONE, give each item a disposition; advisories may be declined. After fixes, regenerate `pack.sha256` and then `helpers.sha256`, rerun preflight, steps 1–3 and `heavy.sh`, and update rehearsal evidence. This audit does not approve deferrals or mark items fixed.

## Required findings still open

Paths below are relative to the repository, at `e5a64fd`. `pack/` means `template/stacks/foldkit/`, and `files/` means `template/stacks/foldkit/files/`.

| Item | Current evidence | Required action |
|---|---|---|
| 1 | `plans/011-stack-pack-foldkit.md:510` still anchors TEMPLATE to the old missing-tools sentence; step 4.3 and its verification retain it. Rust PR #19 rewrites that sentence. | Re-anchor all four locations to the final integrated predecessor tree; recheck the 009/010 anchors too. |
| 2 | Plan prose still identifies local rehearsal SHAs `98b35eb`/`b185770` as the starting tree. | Describe them as historical local implementations, and name the real integrated starting point/contracts. |
| 3 | Plan:842 explains manifests but gives no regeneration recipe. | Add the recipe and required replay order; keep embedded files, manifests, and implementation synchronized. |
| 4 | Plan:4042 tells maintainers to update `train.mjs` and `step-2.sh`; the latter reconstructs pack files. | Ensure a train move cannot replay old embedded package pins over updated files. |
| 5 | `pack/validate-name:5–16` and self-test:3816 call the blocklist direct dependencies but include `playwright` rather than direct `@playwright/test`. | Explain the bin/transitive-name protection or remove the extra restriction deliberately. |
| 6 | `files/scripts/check.d/foldkit.sh:34` matches root `foldkit`, not `foldkit/schema`; side-effect and dynamic imports are also omitted. Scratch reproduction exits 0. | Cover supported import spellings/subpaths; add negative cases. |
| 7 | Same guard:37 checks only `vi.mock`, and :48 only searches `.mcp.json` for `npx`. `vi.doMock` and pnpm dlx config both pass scratch probes. | Parse/allowlist the MCP command and cover mock variants; decide supported config surfaces explicitly. |
| 8 | Self-test:4262–4344 lacks a floating-promise or formatting failure mutation. | Prove type-aware Oxlint and Oxfmt fail closed with meaningful negative cases. |
| 9 | `files/package.json` omits direct `@foldkit/ui`; plan TRAIN also omits it. Self-test mocks a devtools peer on ui but does not pin ui. | Pin the matching ui release, update train/pin checks, and regenerate reviewed lockfile/manifests. |
| 10 | Plan:663–668 exempts entire `@foldkit/*` and `@effect/*` scopes and bare package names. | Use exact train name@version pairs and reject an age exception outside the train. |
| 11 | `files/docs/guides/foldkit.md:60–63` recommends disabling the age rule for every pnpm command, including the resolving install at :52. | Separate reviewed resolution from frozen execution; preserve protection for unrelated transitive dependencies. |
| 12 | `files/scripts/vendor-foldkit.sh:19–23` clones a tag and immediately removes `.git`; no commit comparison exists. | Record and verify the immutable release commit before installing vendored source. |
| 13 | The only supply-chain policy assertion in the harness tests an environment override (:4313); no light test pins the five policy lines. | Add source-policy assertions to an existing light case. |
| 14 | `files/scripts/check.d/foldkit.sh:9`, coverage.sh:8, and vendor-foldkit.sh:12 call bare Node; only pnpm is guarded. after-bootstrap has no documented Node prerequisite. | Use the pinned runtime where possible and fail with an actionable system-Node prerequisite where needed. |
| 15 | Plan look helper:774 runs Playwright before its :779 check of port 3000; port 4000 is not preflighted. | Check the preview port and distinguish environment occupancy from product failure. |
| 21 | `files/scripts/coverage-tiers.mjs:64–73` scans raw source test titles. All three scratch probes (commented, describe.skip, runtime test.skip) report the named journey. Ratchet:330–382 compares tiers, not journeys. Self-test:4233 accepts substring `1 passed`. | Verify actual named journey results (e.g. reporter JSON), enforce required-journey continuity, and make the heavy assertion unambiguous. |
| 22 | Guard:44 excludes any line containing `devToolsMcpPort: false`, accepting falsePort and inline-comment bypasses, and reads only vite.config.ts. All three scratch bypasses pass. | Validate the actual configured relay value, cover alternate config files/script --config, and add negative cases. This was rated P1 in the issue. |
| 23 | Guard:34 passes both src/domain and src/api to grep and treats status 2 as no match. A root forbidden import plus absent src/api prints the match/error yet exits 0. | Scan existing folders and distinguish grep errors from no matches. |
| 24 | `pack/after-bootstrap:11` has an unbounded network install; generated ci.yml has no job timeout. | Bound bootstrap installation and hosted runtime. Historical 420-second offline hang was not repeated in this audit. |
| 25 | Plan lockfile helper:655 deletes the old lockfile; :677 copies the newly resolved lockfile without hash/diff approval. | Choose a reproducibility control: lock hash or explicit package-change review before replacement. This is a decision requirement, not merely a test edit. |
| 26 | Guard:18 groups generic `failed supply-chain policy check` with the age-specific error and advises waiting a day. | Emit age advice only for the age-specific error; preserve other policy failures accurately. No live compromised-package scenario was attempted. |
| 27 | `files/src/api/status.ts:47–60` fetches and decodes without a timeout. | Timeout the complete fetch/decode operation, map it to the failure message, and cover it with a story test. |
| 28 | `pack/gitignore:10` ignores only `/repos/foldkit/`; vendor script creates sibling `repos/foldkit.previous`. | Ignore the full generated repos directory (and test interruption leftovers remain ignored). |

## Advisories and fixed item

| Item | Classification | Evidence / disposition needed |
|---|---|---|
| 16 | Optional simplification | coverage-tiers still has hand-written argument parsing, recursion, and execFileSync error handling. May retain with rationale; not an independently demonstrated bug. |
| 17 | Optional simplification | train.mjs uses a semver scan rather than dist-tags.latest. May retain; review semantics before changing because its predicate excludes deprecated or wrong-Effect releases. |
| 18 | Optional simplification | check-pins uses its own peer-range checker. May retain with rationale; pnpm peers check would change runtime/test dependencies. |
| 19 | Optional simplification | `src/vite-env.d.ts` duplicates vite/client loading via tsconfig types. May retain; deleting it requires manifest/file-count adjustments. |
| 20 | Already fixed on master | PR #21 dates the 2026-10-02 age-rule decision. The older implementation index lacks that date; preserve master's fix while merging. |

## Fresh scratch reproductions

`issue20-probes/results.json` contains results. Guard probes execute the exact boundary/relay/MCP fragment extracted from `e5a64fd`, after omitting unrelated dependency installation/lint prerequisites. These prove the guard logic defects, not a complete end-to-end app exploit.

Seven forbidden variants returned exit 0: subpath import, root import with missing api directory, vi.doMock, pnpm dlx MCP, relay alias, relay inline comment, alternate vite.config.mjs. The clean baseline returned 0; the ordinary numeric relay control returned 1. The missing-directory case printed both the forbidden import and `grep: src/api: No such file or directory` while returning 0.

Direct imports of the unchanged coverage-tier module returned `["named journey"]` for a commented-out test, a test inside describe.skip, and a runtime-skipped test. Playwright was not installed/run by this audit.

## Execution dependencies on this Mac

Observed via read-only command/path probes, 2026-10-13:

| Requirement | Availability |
|---|---|
| Host | macOS 27.0.1, arm64; `/bin/bash` available. |
| Rust | `1.98.1-aarch64-apple-darwin` installed; rustc 1.98.1. clippy, rustfmt, llvm-tools installed for it. |
| Coverage | cargo-llvm-cov 0.9.1 installed and runnable with pinned toolchain. |
| Light tools | uv, gitleaks, shellcheck, git, Node and pnpm on PATH. |
| JavaScript | System Node v22.23.1; pnpm 12.8.1. Pack pins its own pnpm 12.6.0 / Node 24.21.0, whose download/cache availability was not tested. |
| Playwright | `~/Library/Caches/ms-playwright` exists; exact compatible Chromium revision is not established. No current listener found on ports 3000 or 4000. |
| Qt | qmltestrunner absent from PATH and common Homebrew Qt paths; qmake6/qml absent. Local plugin heavy case will skip unless supplied a Qt 6 runner via QML_TEST_RUNNER. |
| GPUI / Linux | pkg-config, wayland-scanner, xvfb-run absent. Xcode selection is CommandLineTools, not full Xcode. Native GPUI gate was not run, so availability is unverified. |
| Docker | Docker.app and `/usr/local/bin/docker` exist, but `docker info` fails because the daemon socket is absent. No containers started. |

The e5a64fd workflow supplies Linux GPUI libraries, desktop-file-utils, Qt 6 tools/modules, Node 24, pinned Rust + llvm-cov, pnpm 12.6.0, and runs all seven heavy cases in a 45-minute job. No implementation PR has ever run that heavy workflow. The template's actual GitHub ruleset currently requires only selftest; adding heavy was reserved as an operator action after its first green run.

Suggested verification lanes once integrated: full light suite with pinned Rust and no skips; Rust/TUI/Foldkit heavy cases locally where prerequisites permit; plugin/GPUI heavy verification in the provisioned Linux environment or hosted workflow. Missing dependencies are missing coverage, not passing acceptance.
