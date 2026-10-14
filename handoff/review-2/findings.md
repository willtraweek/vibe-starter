# /review pass 2 — findings ledger (PR #22, HEAD 6e0b92c)

Status legend: PREPPED = fixed + regression test on scratch branch `willtraweek/review2-omarchy`
(.context/fixwt), mutation-checked; ASK = needs the decision round; DEFER = proposed for an issue/TODO.

## Known open findings (prior review), revalidated

| ID | Sev | Where | Finding | Status |
|---|---|---|---|---|
| K1 | CRIT (race) conf 10 | omarchy-plugin/files/scripts/omarchy-kit:26-28 | concurrent cold cache init deletes a checkout already returned (QA probes 002/003 replay) | PREPPED d77048f: publish with one no-clobber rename, never delete; stale entry reported, not deleted |
| K2 | INFO conf 10 | omarchy-app/tui commands:8 | SHIP_GATE omits `cargo test --locked --doc` | PREPPED 78a7991 + parity test loops every Rust pack |
| K3 | INFO conf 10 | omarchy install.sh:30, dev-link.sh:10, omarchy-kit:9, tests/run:6 | bare cd under CDPATH (QA probes 007/008 replay) | PREPPED c0ff6f3 + behavioral and static tests |
| K4 | INFO | omarchy commands STACK, heavy_ready `-ge 98` | toolchain pins unchecked | PREPPED 21b8a00, ce9d162 (every occurrence) |
| F1-F4 | INFO | plans/011 | stale anchors, historical SHAs, no manifest regeneration recipe, train move replays old pins | ASK (D4 plan 011 disposition) |
| F5 | INFO | foldkit/validate-name | blocklist rationale (playwright vs @playwright/test) | fix: explain bin-name protection |
| F6,F7,F22,F23,F26 | INFO (F22 P1) | foldkit check.d/foldkit.sh | boundary/mock/MCP/relay guards bypassable; grep errors read as no match; every policy error reported as age | ASK (D2 guard design) |
| F8 | INFO | selftest | no negative tests that type-aware oxlint / oxfmt fail closed | fix (heavy test cases) |
| F9 | INFO | foldkit package.json | @foldkit/ui not pinned | fix: pin 0.165.0, regen lockfile; check-pins side PREPPED 2979cb3 |
| F10,F11 | INFO | plan 011 lockfile helper, guide:60-63 | whole-scope age exemptions; guide disables the age rule for every command | ASK (D5) |
| F12 | INFO | vendor-foldkit.sh | tag not verified against an immutable commit (foldkit@0.165.0 = 0b2a4fd04171afa8c8911d22aa9bec2f22faae52) | fix: record + verify commit |
| F13 | INFO | selftest | no light test pins the pnpm-workspace.yaml policy lines | fix |
| F14 | INFO | foldkit scripts | bare node without actionable prerequisite | fix |
| F15 | INFO | plan 011 look helper | port 4000 not preflighted | follows D4 |
| F21 | INFO | coverage-tiers.mjs journeys | skipped/commented journeys count; ratchet ignores journeys; heavy asserts substring "1 passed" | ASK (D3) |
| F24 | INFO | foldkit after-bootstrap, ci.yml | unbounded install; no job timeout | ci timeout PREPPED 4bfd199 (all packs + test); install bound: fix |
| F25 | INFO | plan 011 lockfile helper | lockfile replaced without review | ASK (D6) |
| F27 | INFO | foldkit src/api/status.ts | fetch+decode has no timeout | fix + story test |
| F28 | INFO | foldkit gitignore | ignores only /repos/foldkit/ | fix: /repos/ |
| A16-A19 | ADVISORY | foldkit | coverage-tiers arg parsing/recursion; train.mjs scan; own peer checker; vite-env.d.ts | ASK (D9) |

## New findings this pass

### Codex adversarial (completed)
- CX1 P2 coverage-tiers.mjs:372 a live module can be "retired" to bypass its floor — PREPPED d9ab58b.
- CX2 P2 omarchy install.sh:17 BINARY ignores build.target-dir / CARGO_BUILD_TARGET → may install a stale binary (TODOS item 3 territory) — fix: ask cargo for the artifact path.
- CX3 P2 check-pins.mjs:78 + src/domain/version.ts refuse gstack's MICRO VERSION (0.1.0.1) — check-pins PREPPED 2979cb3; app display/e2e: fix (display npm form).
- CX4 P2 vitest coverage include 'src/**/*.ts' lets .mts/.cts escape — fix (guard or widen).
- CX5 P2 check-pins ignores optionalDependencies — PREPPED 2979cb3.

### Codex structured (completed, gate PASS: no P0/P1): 6 P2, all known (F22 inline-comment variant, F21, K1, F6, F7 doMock, F7 MCP dlx).

### Performance
- PF1 conf 8 template-selftest.yml:130 heavy cache key never changes with dependency drift — DEFER to TODOS item 1 (lockfile policy).
- PF2 conf 7 rust ci.yml no timeout-minutes — PREPPED 4bfd199.

### Maintainability
- MT1 conf 9 pin test assert_contains passes if one job matches — PREPPED ce9d162.
- MT2 conf 6 rust/description + TEMPLATE.md:167 hardcode 1.98 — PREPPED 21b8a00.
- MT3 conf 9 omarchy/foldkit tests check few placeholders — PREPPED 9b7541e (every pack sets every shared key).
- MT4 conf 8 four pack tests lack the deleted-file filter — PREPPED 9b7541e (pack_files helper).
- MT5 conf 5 TEMPLATE.md skip list lacks python3/jq; usage header lacks env vars — PREPPED ce9d162.
- MT6 conf 5 heavy target dirs named inconsistently — PREPPED ce9d162.
- MT7 conf 4 (appendix) omarchy-plugin BUILD_CMD runs the unpinned desktop validator.

### Simplification (all advisory)
- SM1 drop @foldkit/devtools-mcp (93 lockfile packages) — conflicts with guardrail 4 (MCP pinned to local bin).
- SM2 pack-file listing helper — DONE with MT4.
- SM3 omarchy_tui_project duplicates omarchy_app_project (+ rust hook test).
- SM4 three Rust after-bootstrap bodies → _rust-gates/after-bootstrap.
- SM5 tsconfig override repeats base severities.
- SM6 coverage-tiers specFiles → readdirSync recursive.
- SM7 heavy opt-in gate duplicated ×4 → runner.
- SM8 main.ts UpdateReturn alias contradicts FOLDKIT.md.
- SM9 coverage-tiers `own` → Object.hasOwn.

### Design
- DS1 conf 8 omarchy-plugin Widget ignores vertical bars (DESIGN.md requires both).
- DS2 conf 9 omarchy-app Tab never reaches Press (focus_scope nested under the focused root).
- DS3 conf 9 omarchy-app Press is Primary but Enter is unbound.
- DS4 conf 8 foldkit Retry loses keyboard focus on re-render.
- DS5 conf 8 omarchy-plugin guard does not enforce "no hex colours / fixed px" in QML.
- DS6 conf 7 omarchy-app guard misses shadows/glass/rounded pills.
- DS7 conf 8 foldkit pack ships no DESIGN.md though styles.css cites it.
- DS8 conf 6 status copy shows raw reason codes and ISO dates.
- DS9 conf 6 .button has no hover/focus-visible/active; 27px target.

### Pending: testing, security, api-contract, red team, Claude adversarial.

## Completed after the first write-up

### Claude adversarial
- AD1 HIGH conf 9 omarchy-kit runs any commit GitHub serves by SHA (unmerged PR heads) — PREPPED 8dd1a8e-ish (refuse a commit no v* tag contains) + test; closes TODOS Omarchy item 4.
- AD2 MEDIUM Omarchy Rust packs resolve ~860 crates fresh, no reviewed Cargo.lock/cargo-deny — DEFER (TODOS item 1).
- AD3 = CX2 install.sh stale binary (+ sudo drops CARGO_TARGET_DIR) — fix in WS-C with TODOS item 3.
- AD4 = F26 verified: ERR_PNPM_TARBALL_URL_MISMATCH rewritten as age advice — fix (D2).
- AD5 coverage-ignore comments / vitest include-exclude unpinned / plugin .mjs — DEFER to #17 (widen); plugin .mjs coverage glob: fix.
- AD6 = CX5 + dependencies hidden by same-name devDependencies — PREPPED (sections checked separately, duplicates refused).
- AD7 = PF2 PREPPED. AD8 = CX3 (app part pending).
- Rejected with evidence: dev-link --unlink deleting a checkout (Omarchy's remove only unlinks a symlink); a foldkit project named `node`.

### Testing
- T1 CRIT conf 9 plugin tests/run never exercised failing — PREPPED (light test, 3 mutations caught).
- T2 = MT3 (placeholders) — PREPPED (every pack bootstrapped offline, every key checked).
- T3 conf 9 colour-guard rows missing — PREPPED. T4 conf 9 tui validator call untested — PREPPED.
- T5 = MT1 PREPPED. T6 conf 9 check-pins exact-peer branch untested — PREPPED.
- T7 conf 8 include-name rule not isolated — PREPPED (with AC2).
- T8 conf 8 omarchy-kit 40-char check untested — PREPPED.
- T9 conf 7 omarchy-app window test name overclaims the app id — fix in WS-C.
- T10 conf 7 foldkit bootstrap never in the light job; fallbacks untested — PREPPED.

### API contract
- AC1 = MT3 PREPPED. AC2 conf 6 broken includes exit 2 (usage) instead of 1 (template) — PREPPED.
- AC3 conf 5 omarchy STACK lines omit jq — PREPPED. AC4 = MT2 PREPPED.
- AC5 conf 5 install.sh accepts relative PREFIX/BINDIR → relative Exec= — fix in WS-C.

### Security
- SE1 conf 8 = CX5/AD6 + root peerDependencies — PREPPED.
- SE2 conf 6 vendored Foldkit's prepare/simple-git-hooks can rewrite the project's .git/hooks — fix (D7).
- SE3 conf 5 plugin: Label with dynamic text and no textFormat passes the scanner — fix (D8).

### Red team
- RT1 = MT1 PREPPED.
- RT2 conf 8 plugin's .gstack/package-json-path is ignored by the template's own .gitignore; a ZIP/degit copy drops it and the first /ship breaks — fix: template-only template/.gitignore re-include, guard checks the pin, selftest that no tracked file is ignored.
- RT3 conf 9 PRE-EXISTING (python pack): names target/dist/node_modules leave placeholders unfilled — fix in python/validate-name (small, found during review).
