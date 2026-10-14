# Handoff: /review + /ship of PR #22 (five stack packs), paused 2026-10-13

This branch (`willtraweek/review2-handoff`) is a WIP snapshot for moving the work to another
machine. Its last commit only adds this `handoff/` directory: **drop that commit before
shipping** (`git reset --hard HEAD~1` after copying `handoff/` somewhere outside the repo, e.g.
`.context/handoff/`, which is gitignored). Delete the remote branch once the work has landed.

## What the maintainer asked for
`/ship and /review` on draft PR #22 (`willtraweek/unsafe-code-rust-restriction` → `master`),
which integrates the rust, omarchy-app, omarchy-tui, omarchy-plugin and foldkit packs plus the
shared `_rust-gates`. A previous report-only review left 26 open findings (23 from issue #20).

## Where things stand
1. **/review pass 1 is complete** (gstack review skill): core pass, 7 specialists (testing,
   maintainability, security, performance, api-contract, design, simplification), red team,
   Claude adversarial, Codex adversarial and Codex structured (gate PASS, no P0/P1). The
   ledger is `handoff/review-2/findings.md`; QA smoke + replays in `handoff/qa/`.
2. **Decisions D1–D11** (`handoff/review-2/decisions.md`) were cross-reviewed by Codex
   (`handoff/review-2/codex-xreview.txt`) under the maintainer's standing rule (Codex reviews
   each decision; agreed ones are executed; disagreements go back to the maintainer). Codex
   disagreed with D2, D4 and D6 as first written; each time its position was stricter and
   was adopted, so **nothing is pending for the maintainer**. Durable ones are in the gstack
   decision log (`handoff/review-2/decisions-logged.jsonl`; D4 supersedes the 2026-10-04
   "plan 011 stays byte-identical" decision).
3. **Every agreed fix is implemented on this branch**, each with a regression test proven to
   fail without the fix (mutation-checked):
   - mine: omarchy-kit cache race (publish by one no-clobber rename; never delete), release-only
     `.omarchy-ref` (cache hits too), CDPATH in every self-locating cd, omarchy SHIP_GATE
     doctests + a parity test that reads whole multi-line CI steps, every Rust pin checked per
     CI job, CI job timeouts in every pack, check-pins (MICRO VERSION, every dependency section,
     duplicates, root peers), retired tier paths must not exist, foldkit gitignore `/repos/`,
     includes errors exit 1, every pack bootstrapped offline with every placeholder checked,
     plugin `tests/run` fail-closed test, plugin `.gstack` pin re-included via
     `template/.gitignore` + guard check + "no tracked file is ignored" test, python names that
     bootstrap leaves unfilled (pre-existing bug), docs (plan 011 marked executed with live
     maintenance notes; plans/README acceptance gate; TODOS).
   - WS-C (Omarchy): app guard refuses shadows/pills/glass; Tab reaches Press; Enter is bound;
     install.sh installs what cargo built, refuses stale/unrelated binaries, reads only PREFIX,
     refuses a relative PREFIX; plugin vertical bars; QML token guard; Label must be
     `Text.PlainText`; `.mjs` under the coverage gate. Heavy omarchy tests passed 3/3 in a Linux
     container.
   - WS-B (foldkit app): `@foldkit/ui` pinned (+3 lockfile lines), MICRO VERSION shown as npm
     form, 10 s status timeout (body included), journeys verified from Playwright's JSON report
     (`coverage-tiers.mjs --journeys`, `retired_journeys` ratchet), Retry keeps focus (second
     journey), button states/44px, pack `DESIGN.md`, simplifications. Foldkit heavy 4/4 locally.
   - WS-A (foldkit guards): `scripts/check-rules.mjs` (restricted tokenizer: boundary imports,
     module mocks incl. aliases, relay allowlist, MCP launcher, src file types), age advice only
     for `ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION`, policy env cleared, `pnpm-workspace.yaml`
     policy validated (exact train exemptions only), Node 22 prerequisite, bounded network
     steps, `.foldkit-ref` + clone `.git` kept, negative oxlint/oxfmt tests, guide rewritten.
     Heavy foldkit 4/4 on its branch; tokenizer cross-checked against @babel/parser on 12,231
     files. Its stated limits: a trust-downgrade error is covered only by a canned report; the
     alarm can miss a lifecycle-script grandchild; check-rules is syntactic, not a sandbox
     (eval/createRequire outside src/domain, src/api and vite.config.ts get past it).
   - Integration fix (mine, after merging): check-rules refused `String.raw` escapes that WS-B's
     coverage-tiers.mjs uses; tagged templates now tokenize (test added, mutation-checked).

## Verification so far (this branch minus the handoff commit)
- Full light suite: **210 passed, 0 failed, 0 skipped** (7 heavy excluded), before WS-A's
  last guide test (+1, passes):
  `SELFTEST_RUST_TOOLCHAIN=1.98.1 SELFTEST_EXCLUDE=test_heavy_ ./scripts/template-selftest.sh`.
  Foldkit light: 23 passed. `./scripts/check.sh`: OK (gitleaks clean).
- Heavy: omarchy 3/3 (WS-C, Linux ARM64 container) and foldkit 4/4 (WS-A and WS-B, macOS) on
  their branches; **not yet run on the merged tree** (do it in step 1).
- NOTE: with the `handoff/` commit present, two template tests fail (they scan the tree for
  `TEMPLATE.md` mentions and template-only markers): expected; drop the commit first.
- shellcheck (CI's exact file list, 0.11.0) clean on the merged tree. CI's lint step fails on
  *info* findings too: run shellcheck after every selftest edit.
- QA replays on the fixed tree: cache race contract (via the selftest), install CDPATH, partial
  packs, omarchy-tui bootstrap all pass. Still to replay: the foldkit relay alias against
  `check-rules.mjs` (expected: exit 1).

## Next steps, in order
1. Verify the merged branch: full light suite (command above), `./scripts/check.sh`, shellcheck
   (`grep -n 'Lint shell scripts' -A1 .github/workflows/template-selftest.yml` has the list),
   and the heavy suite (`SELFTEST_HEAVY=1 SELFTEST_RUST_TOOLCHAIN=1.98.1
   ./scripts/template-selftest.sh test_heavy_`; GPUI and Qt need Linux: see
   `handoff/integration/heavy-provision.sh` for the toolchain the earlier container used).
   Fix anything red, with a test.
2. Apply WS-B's guide notes to `template/stacks/foldkit/files/docs/guides/foldkit.md` (WS-A
   owned that file): layout table rows for `version.ts` (MAJOR.MINOR.PATCH[.MICRO], npm form
   shown), `api/status.ts` (10 s timeout, body included, fails as unreachable "timed out after
   10 seconds"), `command.ts` (`FocusStatusPanel`), `components/status.ts` (one `section`
   panel in every state), `e2e/home.spec.ts` (two journeys, checked by `--journeys`),
   `DESIGN.md`; a paragraph on `--journeys` (reads `test-results/journeys.json`; fails on a
   skipped, failed, flaky, interrupted, timed-out, missing or twice-declared journey;
   `retired_journeys`); the Commands table and full gate
   (`... && pnpm exec playwright test && node scripts/coverage-tiers.mjs --journeys`); the
   train note that `@foldkit/ui` equals foldkit (devtools' peer).
3. Focused re-review (review cycle 2 of max 3): `codex review --base origin/master`, a Codex
   adversarial `codex exec` and a Claude adversarial subagent on `git diff 6e0b92c..HEAD`
   (the fix delta). Fix confirmed findings with tests; re-run Codex on that delta.
4. /ship (gstack): MINOR **0.3.0** (decided, Codex agreed); CHANGELOG from
   `handoff/review-2/changelog-draft.md`; TODOS already updated; set plans 007–011 to DONE in
   `plans/README.md` only once its "Plan 011's acceptance" gate holds (every #20 item
   dispositioned in the PR body, light + heavy + hosted CI green), with the final test counts;
   run the Step 14.5 `/document-release` audit (mandatory on every ship). Rebuild the PR
   branch from this branch minus the handoff commit (squash or keep history; the PR is squash-
   merged), push to `willtraweek/unsafe-code-rust-restriction`, rewrite PR #22's body (every
   finding's disposition; #20 items 1–28; deferrals), mark it ready, and wait for hosted CI
   (`selftest` and `heavy`) to pass. Never merge before CI is green; never `gh pr merge --admin`.
   The maintainer merges.
5. Issue comments: #10, #12–#18 (their files moved to `template/stacks/_rust-gates`; the gates
   now ship in omarchy-app and omarchy-tui too, so each affects three packs); #17 also covers
   foldkit's `/* v8 ignore */`, unpinned vitest include/exclude, and the plugin's
   `node:coverage ignore`. After merge: close #19 pointing at #22.
6. File the outcome to gbrain (`projects/willtraweek-vibe-starter`).

## Deferred on purpose (recorded)
TODOS item 1 (Rust lockfile policy; heavy cache key; ~860 crates resolved fresh), the foldkit
status copy (P3 TODO), the plugin's unpinned BUILD_CMD validator (P3 TODO), coverage-ignore
comments (issue #17), Rust follow-ups #10/#12–#18, and the declined simplifications (SM1 keeps
`@foldkit/devtools-mcp` per guardrail 4; SM4, SM6, SM7; #20 advisories 16–18).
