# Combined implementation review

Pre-Landing Review: **INCOMPLETE — request changes before merge.** 28 unresolved non-advisory findings: 3 newly identified here, 23 required Foldkit findings carried from #20, and 2 existing Omarchy follow-ups revalidated. The checklist buckets are 1 critical (concurrency) and 27 informational; these are checklist categories, not P-levels. The known Foldkit relay finding remains P1. Four Foldkit simplification advisories are separate and do not block by themselves.

This report supports a **draft PR**, not merge approval. No tracked source was edited, no finding was marked fixed or explicitly skipped, and no GitHub review/comment was published.

## Snapshot and scope

Reviewed `origin/master` against HEAD `99595220f4a1c129150017b5e56b777ab7b80983` plus its combined staged/unstaged candidate: `gstack-wtree 147805b14f4b6b30e65255f935ad5e9300bcca44`. The candidate contains all five implementation lines (Rust, Omarchy app/TUI/plugin, Foldkit), 144 changed files and 10,262 additions / 62 deletions. The full input is [review-candidate.diff](review-candidate.diff). The tree was unchanged from the original start tokens through record persistence. Later release-bookkeeping or documentation edits require their own final-tree verification.

Scope is integration correctness and high-confidence merge blockers, not declaring every historical plan complete. Plan completion audit: not run (no plan is bound to this branch and no docs/designs/ file matches). Fix: add "Plan: <path>" to the PR body, or run /autoplan.

## New unresolved findings

1. **P2 / CRITICAL checklist category / confidence 10: concurrent Omarchy cache initialization deletes another caller's returned checkout.** `template/stacks/omarchy-plugin/files/scripts/omarchy-kit:26–28` checks HEAD, then removes and replaces the shared cache without serialization. Two cold callers can both pass the check; after A returns successfully, B removes the path while A's guard is about to execute the validator (`scripts/check.d/omarchy-plugin.sh:30`, `:37`). Fix publication so a returned cache remains immutable and usable, with serialized initialization or atomic publication that never removes an already valid checkout. The isolated exact-source fixture proves the interleaving; see [native report](native-adversarial.md) and [reproduction](native-adversarial-race.py).
2. **P2 / INFORMATIONAL / confidence 10: Rust is described as shipped before it has landed.** `TODOS.md:120–125` says Rust shipped/completed in v0.2.0 on 2026-10-04, while PR #19 remains unmerged and `plans/README.md` now correctly says integration/review is pending. Keep the combined entry pending, or split Python's shipped status from Rust's pending status; update completion only when its merge/release occurs.
3. **P3 / INFORMATIONAL / confidence 10: current maintenance instructions target a deleted toolchain file.** `plans/007-stack-pack-rust.md:1082` points a future toolchain bump at `template/stacks/rust/files/rust-toolchain.toml`; integration moved the active file to `template/stacks/_rust-gates/files/rust-toolchain.toml`. Update the maintenance instruction and shared consumers. Historical implementation snippets need not be rewritten.

## Existing unresolved findings, deduplicated

- **23 required Foldkit findings:** [per-item evidence and actions](issue20-audit.md), items 1–15 and 21–28. They include code defects, acceptance-test gaps, and documentation/decision requirements; they are not 23 separate exploitable bugs. `git diff e5a64fd -- template/stacks/foldkit plans/011-stack-pack-foldkit.md` is empty on the frozen integration candidate, so the audited pack and plan have not changed. The [closed issue's final comment](https://github.com/willtraweek/vibe-starter/issues/20#issuecomment-5985594106) leaves those items open for implementation; only item 20 was fixed by master PR #21. Most consequential: the P1 relay check (`foldkit.sh:42–45`) accepts aliases, comments, and alternate config files; import guards accept subpaths and grep errors; journey checks count disabled/commented tests; dependency-age and vendoring controls remain incomplete. Seven isolated guard bypasses and three journey-title false acceptances are saved in [probe results](issue20-probes/results.json). Those probes isolate unchanged guard logic, not a whole-app exploit.
- **P2 / INFORMATIONAL / confidence 10, existing Omarchy TODO item 2:** both `template/stacks/omarchy-app/commands:8` and `template/stacks/omarchy-tui/commands:8` omit `cargo test --locked --doc`, although their generated CI runs it. Add doctests to both local ship gates and extend parity coverage to both packs. A green current starter does not close this future generated-project gate mismatch.
- **P2 / INFORMATIONAL / confidence 10, existing Omarchy TODO item 3:** app/TUI `files/scripts/install.sh:30` use a bare `cd` inside command substitution. With a nonempty CDPATH, the installer can change to a different project and emit its path into the output while exiting 0. Native scratch execution reproduced this; use `CDPATH='' cd -- ...` consistently. This is existing tracked debt, not a newly discovered integration defect.

Rust issues #10 and #12–18 remain disclosed follow-ups from PR #19. The outside reviewers repeated them; they were not independently re-derived as eight additional new defects here and are excluded from the 28 count. Their prior deferral must remain visible in the PR. Issue #11's fix survived integration.

The #20 gate requires explicit dispositions, manifest regeneration after fixes, and the prescribed preflight/step/heavy replays. The four optional simplification items 16–19 may be retained with rationale; no current acceptance or skip was manufactured by this review.

## Review coverage and synthesis

- Parent checklist pass completed, including shared-pack include validation, guards, CI/runtime pins, and consumers beyond the changed snippets. `git diff --check origin/master` passed. No SQL, migration, enum expansion, or product LLM trust-boundary surface required additional applicable checks.
- Independent in-host adversarial pass completed. Full non-fixture source read; test/fixture payloads were **SUMMARY-only** for that reviewer; lock metadata and resolution URLs were inspected without independently re-resolving dependencies. [Native report](native-adversarial.md).
- Two Claude Code outside passes completed against the full captured diff with tools disabled. Structured gate: **FAIL**, including P1 carried Foldkit findings. Adversarial result: issues found, informational gate. Both raw JSON files preserve reported `modelUsage`, including `claude-opus-5-5` and `claude-haiku-5-5`; no single primary model identity is inferred. Native harness model identity was not reported.
- High-confidence overlap: required Foldkit cluster, Omarchy doctest drift, stale Rust toolchain maintenance path. Unique independently reproduced native finding: cache race. Outside-only new confirmed finding: false Rust shipped/completed status. No Review Army exists in this installed skill; `specialists: {}` is missing specialist coverage, not a specialist pass. The mandated default score 10.0 is not evidence of quality.
- No PR existed on the current branch at review time, so no Greptile review was available. No queue claim existed; advisory next patch was 0.2.2. Root owns release bookkeeping.

Rejected/speculative outside suggestions were checked against source: bootstrap invokes both hooks through `sh`, so 100644 hooks do not break execution; bootstrap's project-name allowlist excludes quotes/backslashes before interpolation, so the proposed quote injection is impossible; the plugin's `.gstack/` file is tracked. Upstream dev-link unlink semantics and `node`/`pnpm` name collisions were not demonstrated and are not findings. Hosted ubuntu-slim tool availability/time budget is pending CI evidence, not an asserted defect. Future Omarchy version-display pin drift is noted in the outside output but not counted separately from the confirmed maintenance issue.

## Exploratory QA and Verification Results

**Verdict: FAIL — the cache publication contract failed and replayed.** This prevents a completed/converged core `/review` record. It does not mean the supplied broad regression suites failed.

The 300-second functional smoke budget started 2026-10-13T21:17:32.744Z and was not reset. [Charters](review-qa/charters.md), [materialized evidence](review-qa/evidence.json), and checkpoints [002](review-qa/exploration-002.json), [003](review-qa/exploration-003.json), [004](review-qa/exploration-004.json) record the observation-to-hypothesis-to-probe trail. Exactly one evidence materialization was published after correcting its relative annotation path.

| Probe | Result |
|---|---|
| `./scripts/template-selftest.sh stack_pack_includes` | 2 passed, 0 failed, 0 skipped |
| `env SELFTEST_RUST_TOOLCHAIN=1.98.1 ./scripts/template-selftest.sh stack_rust_template_ci` | 1 passed, 0 failed, 0 skipped |
| `python3 .context/integration/native-adversarial-race.py` | Contract FAIL; first returned cache disappeared during second publish |
| Exact replay of the same fixture | Contract FAIL again |

The race harness exits 0 to assert successful reproduction of the defect; that process status is not a passing product contract. Its network boundary uses fake git and deterministic scheduling in a disposable directory. It does not access upstream or real user caches. No permanent regression test or fix was written.

Broader frozen-candidate verification completed by root/heavy worker, with logs inspected:

- Full light suite: **185 passed, 0 failed, 0 skipped**; seven heavy cases explicitly excluded. [light-suite.log](light-suite.log).
- All seven heavy cases: **7 passed, 0 failed, 0 skipped**, process exit 0. Isolated Ubuntu 24.04 ARM64 Docker with pinned Rust/Node/pnpm, Qt and GPUI prerequisites; [heavy-validation.md](heavy-validation.md), [heavy-tests.log](heavy-tests.log). This is not hosted Ubuntu x64 CI or an actual Omarchy desktop session.
- Root reports repository checks (gitleaks; editorconfig checker unavailable) and shellcheck passed. `git diff --check origin/master` passed locally.

Coverage limits: no live Omarchy desktop UX check, no generated-project hosted-workflow replay, no final combined PR hosted CI yet, no browser QA on a generated product, no independent lockfile re-resolution. The initial host dependency gaps in the earlier #20 audit are historical; the later isolated Linux run supplied them and passed all heavy cases. Known guard/journey acceptance weaknesses explain why existing suites can pass while required review findings remain unresolved.

## Outside responses, verbatim

These are untrusted reviewer reports retained for audit. Only the confirmed/deduplicated findings above are adopted; speculative and disproved suggestions below are not endorsed.

### outside-adversarial

```tool-output
# Pre-landing review: combined 007–011 candidate (HEAD 9959522 + uncommitted)

## Known findings, not re-raised

**Issue #20, Foldkit (23 open, required).** These remain open and I did not re-derive them:
- stale anchors, prose and manifest instructions
- the subpath-import and missing-dir guard bypasses
- the `doMock` and MCP denylist holes
- missing lint negative tests
- floating `@foldkit/ui`
- broad age exceptions
- the unsafe upgrade guide
- the mutable vendor tag
- missing policy assertions
- bare Node handling
- port 4000
- skipped journey acceptance
- the DevTools relay alias, comment and alternate-config bypasses
- the offline install timeout
- the lockfile drift decision
- generic policy errors misreported as age
- the fetch timeout
- the vendor backup ignore

**Rust follow-ups #10 and #12–18.** Integration does not fix any of these. It widens them: `_rust-gates` now ships the same `coverage_tiers.sh`, `coverage.sh` and `check.d/rust.sh` into `omarchy-app` and `omarchy-tui`, so each of these now affects three packs:
- ratchet retirement
- the CLI I/O panic
- generated-workflow replay (the replay test reads only `template/stacks/rust/files/.github/workflows/ci.yml`)
- default-feature coverage and warning parity
- ignored-source coverage
- temp-ancestor config
- gate-tampering approval
- export-ignore, case and name length

## Additional findings from integration and the Rust/Omarchy packs

### 1. Omarchy SHIP_GATE skips a gate that CI runs (the doctest drift again) — FIXABLE
- `template/stacks/omarchy-app/commands:8`: `SHIP_GATE=./scripts/check.sh && ./scripts/coverage.sh`
- `template/stacks/omarchy-tui/commands:8`: same value.
- Both packs' CI still run doctests:
  - `template/stacks/omarchy-app/files/.github/workflows/ci.yml:54`: `run: cargo test --locked --doc`
  - `template/stacks/omarchy-tui/files/.github/workflows/ci.yml:53`: same step.
- The rust pack fixed exactly this drift. Its comment says SHIP_GATE "runs each gate the new project's CI runs … (the doctest drift the first review fixed)".
- The guard, `test_stack_rust_ship_gate_runs_every_ci_gate`, only reads one pack: `ci="$REPO/template/stacks/rust/files/.github/workflows/ci.yml"` and `template/stacks/rust/commands`.
- **Effect:** a broken doc example in either Omarchy project passes the local gate that `/ship` runs, then fails CI.
- **Fix:** append `&& cargo test --locked --doc` to both SHIP_GATE lines, and loop the test over every pack that has a `ci.yml`.

### 2. `cd` without `CDPATH=''` in the Omarchy scripts — FIXABLE
- The Rust gates fixed this and added a regression test: `CDPATH='' cd -- "$(dirname -- "$0")/.."   # a CDPATH entry must not pick the directory`.
- The Omarchy scripts still use the bare form:
  - `omarchy-app/files/scripts/install.sh:30` and `omarchy-tui/files/scripts/install.sh:30`: `cd "$(dirname "$0")/.."`
  - `omarchy-plugin/files/scripts/dev-link.sh:10`
  - `omarchy-plugin/files/scripts/omarchy-kit:9`
  - `omarchy-plugin/files/tests/run:6`
- When the script is invoked as `bash scripts/dev-link.sh` with an exported `CDPATH`, `dirname` returns `scripts`, so `cd scripts/..` searches `CDPATH`.
- `dev-link.sh` then runs `ln -sfn "$PWD" "$dest"` on the decoy directory. That links someone else's tree into `~/.config/omarchy/plugins/`, where it runs unsandboxed in the desktop shell.
- `install.sh` would install the decoy's binary. Separately, `cd` echoes the path it picked, which corrupts `--print-desktop-entry` output.
- The documented `./…` invocations are not affected.

### 3. `dev-link.sh --unlink` hands a symlinked checkout to Omarchy's destructive remove — INVESTIGATE
- `dev-link.sh:47`: `omarchy plugin remove "$id" --yes`
- The script's own comment (lines 41–42) says Omarchy's remove "deletes a cloned plugin outright".
- If `omarchy plugin remove` resolves the link or deletes `"$dir/"`, it wipes the developer's working checkout.
- The only test, `test_stack_omarchy_plugin_dev_link_links_rescans_and_enables`, uses a stub `omarchy`, so this behaviour is unverified.
- **Fix if confirmed:** for a link, run `omarchy plugin disable` then `rm "$dest"`, and never call remove.

### 4. The project name goes unescaped into code and markup literals — INVESTIGATE
This depends on bootstrap's name validation, which is not in this diff.
- `omarchy-app/files/src/app.rs`: `title: Some("{{PROJECT_NAME}}".into())`
- `omarchy-app/files/src/cli.rs` and `omarchy-tui/files/src/cli.rs`: the `USAGE` string literal.
- `omarchy-tui/files/src/view.rs`: `pub const TITLE: &str = " {{PROJECT_NAME}} ";`
- `foldkit/files/src/build-info.ts:4`: `export const PROJECT_NAME = '{{PROJECT_NAME}}'`
- `foldkit/files/index.html:6`: `<title>{{PROJECT_NAME}}</title>`
- JSON strings in `package.json` and `manifest.json`, the desktop entry's `Name=`, and the Lua snippets in the Omarchy guide.

If bootstrap accepts `"`, `'`, `\` or `<` in the name, a name like `x"); …; ("` becomes compiled Rust code, and the others break the build or inject markup. The foldkit `validate-name` checks only the length of `$2`.

### 5. Light CI job may lack tools that some tests need — INVESTIGATE
- The workflow comment claims `ubuntu-slim` "ships … jq". Nothing installs jq or python3.
- `test_stack_omarchy_plugin_guard_keeps_version_and_manifest_in_step` calls `skip "python3 not installed"` without python3.
- Several rust and omarchy-plugin tests skip without jq.
- In CI a skip fails the job, so a slim image without these tools turns the run red.
- The 15-minute, 1-vCPU cap also now covers an extra real Rust bootstrap plus clippy, from `test_stack_omarchy_app_guard_…` via `bootstrap_rust "$d.rust"`.
- **Fix:** install jq and python3 explicitly, or verify the image ships them.

### 6. Toolchain-bump instructions and pins drift after the move into `_rust-gates` — FIXABLE
- `plans/007-stack-pack-rust.md` (maintenance notes) still says to change `channel` in `template/stacks/rust/files/rust-toolchain.toml`. That file is now `template/stacks/_rust-gates/files/rust-toolchain.toml`.
- `test_stack_rust_template_ci_tests_the_pinned_toolchain` asserts `STACK=Rust ${pin%.*} ` only in `template/stacks/rust/commands`. The omarchy-app and omarchy-tui `STACK=` lines also hard-code "Rust 1.98", and nothing checks them.
- `omarchy_app_heavy_ready` and `omarchy_tui_heavy_ready` hard-code `[ "${minor:-0}" -ge 98 ]` instead of reading `rust-version`.
- A bump will silently leave these stale.

### 7. The foldkit pack's `validate-name` misses two names its lockfile uses — INVESTIGATE
- `foldkit/validate-name:16`: `for taken in effect foldkit oxfmt oxlint playwright typescript vite vitest`
- The shipped `pnpm-lock.yaml` also has a root dependency `node` (`specifier: runtime:24.21.0`) and `packageManagerDependencies.pnpm`.
- A project named `node` or `pnpm` collides with those. Whether pnpm actually breaks was not run.

### 8. foldkit hooks are mode 100644 where every other pack's are 100755 — INVESTIGATE
- `template/stacks/foldkit/after-bootstrap` and `template/stacks/foldkit/validate-name` are 100644.
- `validate-name` is documented to run as `sh validate-name`, so that one is fine.
- The `after-bootstrap` invocation is not in this diff. If bootstrap executes it directly, the foldkit install and vendoring hook never runs.

### 9. The generated foldkit CI job has no `timeout-minutes` — INVESTIGATE
- `foldkit/files/.github/workflows/ci.yml` sets no job timeout.
- `playwright.config.ts` itself documents that, under pnpm 12.6, the preview server "outlived Playwright's shutdown and the run hung".
- A recurrence would burn the 6-hour default on every new project.

## Checked and found sound
- **`bootstrap` `includes` handling:** the case pattern rejects names with a path separator, a dot, a bare `_`, CR or whitespace. Validation happens before any write, and the copy loop filters the same lines.
- **`SELFTEST_EXCLUDE` accounting:** excluded tests are not counted as skips.
- **`CHECK_CI` export** in `check.sh`.
- **The heavy job's cache key**, which includes `_rust-gates`.

Recommendation: Do not merge because the 23 required Foldkit findings from #20 are still open, including the DevTools-relay alias, comment and alternate-config bypasses that let a numeric `devToolsMcpPort` open an unauthenticated relay on every interface, and the integration adds a confirmed gate gap: omarchy-app and omarchy-tui SHIP_GATE skip CI's `cargo test --locked --doc`.
```

### outside-structured

```tool-output
# Pre-landing review: combined Rust, Omarchy (app, TUI, plugin) and Foldkit candidate

**Scope:** HEAD 9959522 plus the uncommitted changes shown (gstack-wtree 147805b1…). I reviewed the diff as data only and ran nothing. The new integration defects I found are all P2 or P3. The carried Foldkit findings from #20 still block landing.

## Known findings, carried and still open (not re-derived)

**[P1] Foldkit #20: 23 required findings remain unresolved in this tree.**
- Stale anchors, prose and manifest instructions.
- Bypasses of the subpath-import and missing-dir guards.
- Holes in the `doMock` and MCP denylists.
- No lint negative tests.
- `@foldkit/ui` floats, and the age exceptions are broad.
- The upgrade guide is unsafe, and the vendor tag is mutable.
- Policy assertions are missing, and bare Node is not handled.
- The preview uses port 4000.
- Journey acceptance can be skipped.
- The DevTools relay check can be bypassed by an alias, a comment or an alternate config.
- The offline install can time out.
- The lockfile-drift decision is still open.
- Generic policy errors are reported as age errors.
- The fetch has no timeout, and the vendor backup is not ignored.

Nothing in the diff closes any of these. `template/stacks/foldkit/files/scripts/check.d/foldkit.sh`, `vite.config.ts`, `playwright.config.ts` (`baseURL: 'http://localhost:4000'`) and `scripts/vendor-foldkit.sh` (`--branch "foldkit@$pin"`, `repos/foldkit.previous`) all match the reviewed state.

**[P2] Rust #10 and #12–18 are still open, and the shared gates now spread them to the Omarchy packs.**
- The follow-ups are: ratchet retirement, CLI I/O panic, generated-workflow replay, default-feature coverage and warning parity, ignored source coverage, temp ancestor config, gate-tampering approval, and export-ignore/case/name-length.
- `_rust-gates` is now included by `rust`, `omarchy-app` and `omarchy-tui`. Every gate defect therefore reaches all three packs.
- The #12 pattern is copied into both Omarchy entry points:
  - `template/stacks/omarchy-app/files/src/main.rs`: `print!("{out}");`
  - `template/stacks/omarchy-tui/files/src/main.rs`: `print!("{out}");`
- Fix these once in `_rust-gates` and in all three `main.rs` files.

## Additional defects found in this integration

**[P2] The Omarchy packs' `SHIP_GATE` skips a gate their CI runs, and no test covers it.**
- Both `template/stacks/omarchy-app/commands` and `template/stacks/omarchy-tui/commands` have `SHIP_GATE=./scripts/check.sh && ./scripts/coverage.sh`.
- Their `ci.yml` files also run `run: cargo test --locked --doc` ("Doctests (coverage runs on stable skip them)").
- This is the same doctest drift the Rust review already fixed. `test_stack_rust_ship_gate_runs_every_ci_gate` reads only `template/stacks/rust/files/.github/workflows/ci.yml`.
- `test_stack_rust_ci_ratchet_step_on_a_shallow_pr_checkout` likewise replays only the rust pack's ratchet step. The two Omarchy copies of that step are untested.
- Effect: a local `/ship` gate passes while CI fails on the first doctest.
- Fix: add `&& cargo test --locked --doc` to both `SHIP_GATE` lines. Then loop both selftests over every pack whose `ci.yml` has these steps.

**[P2] Release state contradicts itself, which re-accepts the old DONE label this integration is meant to reject.**
- `TODOS.md` moves "Opt-in stack packs (Python, Rust)" to **Completed** with "Rust in v0.2.0 (plan 007)" and "**Completed:** v0.2.0 (2026-10-04)".
- `plans/README.md` in the same diff marks 007 "IN PROGRESS (implementation integrated; combined review and validation pending)". It also says "Current suite after 001–007: **160 tests** (live)".
- master's history has no v0.2.0 commit. The log goes v0.1.0, v0.1.1, then v0.2.1 (9959522). PR #19 (v0.2.0) was never merged, so a "Completed v0.2.0" entry names a release older than master's current version that never landed.
- Fix: keep the TODOS entry open, or point it at this PR's version. Change "160 (live)" to a projected count.

**[P3] The plan 007 maintenance note points at a file that no longer exists, and the bump check misses three pins.**
- `plans/007-stack-pack-rust.md` says "Change `channel` in `template/stacks/rust/files/rust-toolchain.toml`". The pin now lives in `template/stacks/_rust-gates/files/rust-toolchain.toml`.
- The same note says the selftest "fails until all of them agree". That test checks only `template/stacks/rust/commands` (`STACK=Rust ${pin%.*} `).
- These pins are not checked:
  - `STACK=… Rust 1.98 …` in the `omarchy-app` and `omarchy-tui` `commands` files.
  - The hard-coded `[ "${minor:-0}" -ge 98 ]` and "set SELFTEST_RUST_TOOLCHAIN=1.98.1" in `omarchy_app_heavy_ready` and `omarchy_tui_heavy_ready`.
- After a toolchain bump these go stale silently.

**[P3] Foldkit's `after-bootstrap` and `validate-name` are mode 100644, unlike every other pack's hooks.**
- `new file mode 100644` appears for both `template/stacks/foldkit/after-bootstrap` and `template/stacks/foldkit/validate-name`. The rust and Omarchy hooks are 100755.
- `TEMPLATE.md` says `validate-name` runs as `sh validate-name`, so that one is fine.
- How bootstrap invokes `after-bootstrap` is not in the diff. If it runs the hook directly rather than through `sh`, the foldkit install and vendoring step never runs.
- The heavy test's `assert_contains "$d.out" "Installed the locked dependencies"` would catch this, but only in the heavy job.

**[P3] An apostrophe or double quote in the project name breaks the new Foldkit and plugin starters, unless bootstrap already restricts the name.**
- `src/build-info.ts` has `export const PROJECT_NAME = '{{PROJECT_NAME}}'`, so a name like "Ann's App" is a TypeScript syntax error.
- `package.json` (`"description": "{{PROJECT_NAME}}"`) and the plugin's `manifest.json` (`"name": "{{PROJECT_NAME}}"`) become invalid JSON if the name contains `"`.
- `template/stacks/foldkit/validate-name` checks only the name's length (`${#2} -gt 50`).
- The bootstrap code that sanitises names is not in the diff, so check it before relying on it.

**[P3] The light CI job may be missing python3 and may hit the 15-minute cap; worth confirming.**
- `test_stack_omarchy_plugin_guard_keeps_version_and_manifest_in_step` skips without `python3`, and CI counts skips as failures.
- The selftest job's own comment lists the ubuntu-slim tools as "bash, git, perl, GNU tar, curl and jq". Nothing in the job installs python3.
- The same job, on 1 vCPU with a 15-minute cap, now also runs about 15 real cargo, clippy and llvm-cov Rust builds. It sets no `timeout-minutes`.
- CI would show either problem, so neither can land silently, but confirm both on the first run.

## Context I could not see

- **`CHANGELOG.md` and `VERSION`:** status shows both as `MM`, but neither appears in the diff. I could not check the version bump or the release notes.
- **The template repo's root `.gitignore`:** if it ignores `.gstack/` or `coverage/`, files under `template/stacks/omarchy-plugin/files/.gstack/` could be left out of the commit. The selftests would then pass locally and fail in CI.
- **Unchanged parts of `bootstrap`:** I could not see how it invokes `after-bootstrap` or how it sanitises the name.
- **`ci_requires_gitleaks` in `scripts/check.sh`:** its body is not in the diff. I could not confirm that the guards still run when gitleaks is missing in CI, which `test_check_tells_guards_whether_ci_requires_tools` depends on.

VERDICT: findings
```

## Persistence receipt

All four original start tokens were consumed once on the frozen candidate. [Command receipts](review-log-results.json); [binding/freshness receipts](review-binding-receipts.json). Native and outside attempts have matching verified start/end snapshots but unresolved findings. The core record is explicitly `completed:false`, `converged:false`, binding `incomplete`, and freshness `UNVERIFIED` because required QA failed. No clear-to-merge receipt exists.
