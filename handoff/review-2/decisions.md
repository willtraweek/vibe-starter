# /review pass 2 — decision brief (for Codex cross-review)

Context: vibe-starter (a GitHub template repo) PR #22 integrates five stack packs (rust, omarchy-app,
omarchy-tui, omarchy-plugin, foldkit) plus shared `_rust-gates`. A prior report-only review left 26
non-advisory findings (23 from issue #20 on the foldkit pack, an omarchy-kit cache race, two Omarchy
follow-ups). This pass ran 7 specialists, a Claude adversarial pass and two Codex passes; the
ledger is `.context/review-2/findings.md`. Mechanical fixes with regression tests are already on a
scratch branch (`git -C .context/fixwt log --oneline 6e0b92c..`), each test checked to fail
without its fix. The maintainer's standing rule: Codex reviews each recommendation; agreed ones
are executed, disagreements go back to him.

For each decision answer AGREE or DISAGREE, with caveats, and say what you would do instead.

## D1. Scope of this PR
Recommendation: fix every non-advisory finding in this PR, including the rest of TODOS.md's
"Omarchy follow-ups" items 3 (install.sh hardening: find the binary through cargo, refuse a
stale binary, stop reading generic APPDIR/BINDIR/ICONDIR, never replace an unrelated
~/.local/bin/<name>, absolute paths only) and 4 (omarchy-kit pins only a commit inside an
Omarchy release; already prepped). Defer, with tracking:
- heavy CI cache key never changes with dependency drift (PF1) and the Omarchy Rust packs
  resolving ~860 crates fresh at bootstrap with no reviewed Cargo.lock or cargo-deny (AD2):
  both belong to TODOS item 1 (the Rust packs' lockfile policy), still undecided;
- coverage-ignore comments (`/* v8 ignore */`, `node:coverage ignore`) and unpinned vitest
  include/exclude letting tiers pass without tests (AD5): widen issue #17 ("coverage exclusions
  need recorded approval in every stack pack") to name foldkit and the plugin;
- Rust follow-ups #10, #12-#18 stay deferred (the maintainer chose that on 2026-10-03/04); add a
  comment to each that `_rust-gates` now carries it into omarchy-app and omarchy-tui;
- omarchy-plugin BUILD_CMD runs the desktop's unpinned validator (conf 4): note only.

## D2. Foldkit guard redesign (#20 items 6, 7, 22 [P1], 23, 26; CX4; SE3-like aliasing)
The guard (`scripts/check.d/foldkit.sh`) greps lines; seven bypasses reproduce (subpath imports,
missing dir read as no match, vi.doMock, pnpm dlx MCP, relay alias, inline comment, alternate
config). Recommendation: one Node-stdlib checker, `scripts/check-rules.mjs`, run by the guard
after the pin checks, with light selftests on fixture files (no pnpm needed):
- boundary: in src/domain and src/api, after stripping comments (string-aware), no module
  specifier `foldkit`, `foldkit/...` or `@foldkit/...` in import/export-from, side-effect import,
  `import()` or `require()`; type-only imports count; unreadable files fail;
- mocks: in src and e2e, no `mock`/`doMock`/`importMock` call on `vi`, `vitest`, or any name
  imported as them from vitest or @effect/vitest (aliases), or via a namespace import;
- relay: only `vite.config.ts` may configure Vite (no other `vite.config.*` anywhere outside
  node_modules/repos/dist, no `--config`/`-c` in package.json scripts or Playwright's webServer);
  it imports `{ foldkit }` from `@foldkit/vite-plugin` exactly once, nothing else imports that
  package, and its single `foldkit(` call's argument is exactly `{ devToolsMcpPort: false }`
  (relay off) or empty (the token-protected default the guide documents). Anything else fails
  with "extend scripts/check-rules.mjs if this is safe";
- MCP: `.mcp.json`, `.cursor/mcp.json`, `.vscode/mcp.json`: any server whose command or args
  mention foldkit must be exactly `{"command": "node_modules/.bin/foldkit-devtools-mcp"}`;
- sources: src/ holds TypeScript only as `.ts` (coverage measures `src/**/*.ts`): `.mts`, `.cts`,
  `.tsx`, `.js`, `.mjs`, `.cjs`, `.jsx` under src/ fail.
Also in the guard: age advice only for `ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION`, every other
policy error (e.g. `ERR_PNPM_TARBALL_URL_MISMATCH`) passes through with pnpm's help intact;
pnpm runs with policy env vars (`pnpm_config_minimum_release_age*`, `trust_policy*`, ...)
cleared; a missing or old system Node (<22) fails with an actionable message; network steps
bounded with a wall-clock timeout (perl alarm).
Rejected: oxlint `no-restricted-imports` (misses `import()`/`require()`), evaluating the Vite
config at runtime with a module hook (fragile, env-dependent).

## D3. Named journeys must actually run (#20 item 21)
Recommendation: Playwright writes a JSON report (`test-results/journeys.json`, list reporter
kept); `node scripts/coverage-tiers.mjs --journeys` fails unless every configured journey has
results and all of them passed (skipped, interrupted or missing fail). SHIP_GATE and CI run it
right after `pnpm exec playwright test`. The ratchet fails when a base journey disappears unless
its title is listed in `retired_journeys` (mirrors tiers' `retired`); a retired journey title
must no longer exist in e2e/. The source scan ignores comments. The heavy test asserts on the
JSON, not the substring "1 passed".

## D4. Plan 011 disposition (#20 items 1-4, 15, and the README gate)
plans/README.md says every #20 finding needs a disposition "with pack.sha256 and helpers.sha256
regenerated, before row 011 is marked DONE". Recommendation: this PR executes plan 011, so mark
it DONE; keep its embedded pack, helpers and manifests as the historical record of the
2026-10-02 rehearsal (not regenerated, not replayed); say so at the top of the plan; rewrite its
Maintenance notes (which TEMPLATE.md points to for train moves) to work directly on
template/stacks/foldkit with no `step-2.sh` replay (closes item 4's hazard), and include D5's and
D6's procedures. Items 1, 2, 3 and 15 become "superseded: plan executed". Log this as a reversal
of the 2026-10-04 decision ("plan 011 stays byte-identical to the implementation branch").
Alternative: regenerate both manifests and re-anchor the plan for a replay nobody will run.

## D5. The 24-hour release-age rule (#20 items 10, 11, 13)
Recommendation: the generated guide and the maintenance notes say: wait a day by default; the
only fast path is exact `name@version` entries for the new train's releases in
`minimumReleaseAgeExclude` (pnpm 12.6.0 supports exact versions), removed once they mature;
never `pnpm_config_minimum_release_age=0`, never bare names or scopes. `check-pins.mjs` validates
`pnpm-workspace.yaml`: `minimumReleaseAge` >= 1440, `trustPolicy: no-downgrade`,
`strictDepBuilds: true`, `blockExoticSubdeps: true`, `allowBuilds: {}`, exemptions only as exact
versions of train packages (foldkit, @foldkit/*, effect, @effect/*), and no other keys (so
`overrides`, `dangerouslyAllowAllBuilds`, `minimumReleaseAgeStrict: false`, `trustPolicyExclude`
need a reviewed change to the checker). A light test pins all of it.

## D6. Lockfile replacement control (#20 item 25)
Recommendation: a process control in the maintenance notes: regenerate in a scratch copy, then
compare old and new lockfiles' `packages:` keys (a documented one-line diff command) and list
every added, removed or changed `name@version` in the PR description; the reviewed lockfile
only lands through that PR, and the heavy test installs it `--frozen-lockfile`. No hash pin
(it would just be bumped alongside the lockfile).

## D7. Vendored Foldkit provenance and isolation (#20 item 12, SE2)
Recommendation: keep the clone's `.git` in `repos/foldkit` (a git boundary, so Foldkit's own
`prepare`/simple-git-hooks can't rewrite the project's `.git/hooks` if someone runs pnpm there),
add `.foldkit-ref` holding `<version> <commit>` (foldkit@0.165.0 = 0b2a4fd0…), have
vendor-foldkit.sh refuse a tag that doesn't resolve to that commit, and have check-pins require
`.foldkit-ref`'s version to equal the foldkit pin (a train move updates both).

## D8. Design findings
Recommendation: fix DS1 (plugin widget in vertical bars), DS2 (omarchy-app Tab never reaches
Press), DS3 (Primary button with Enter unbound: bind Enter), DS4 (foldkit Retry loses focus),
DS5 (plugin guard: refuse hex colours, Qt.rgba/Gradient and fixed px sizes in QML), DS6
(omarchy-app guard: shadows, glass, rounded pills, per DESIGN.md's flat-surface rule, as the
maintainer's 2026-09-26 D4 widened it), DS7 (ship a foldkit DESIGN.md recording its tokens),
DS9 (button hover/focus-visible/active and a 44px target), SE3 (Label with dynamic text and no
textFormat: scan Label as Text, widen DESIGN.md's rule). Defer DS8 (plain-language status copy:
taste, not a defect).

## D9. Advisories (ASK-only)
Accept: SM3 (one stub-cargo project helper), SM5 (tsconfig duplicate severities), SM8 (inline
the single-use UpdateReturn alias, as FOLDKIT.md says), SM9 (Object.hasOwn), #20-19
(vite-env.d.ts duplicates tsconfig's types). Decline with reason: SM1 (drop
@foldkit/devtools-mcp: the maintainer's guardrail 4 keeps the MCP pinned locally), SM4 (move
after-bootstrap bodies into _rust-gates: refactor with no defect behind it, PR already large),
SM6 (readdirSync recursive: specFiles changes with D3 anyway), SM7 (heavy opt-in gate into the
runner: harness restructure), #20-16, #20-17, #20-18 (keep; 18 is now tested).

## D10. Version
Recommendation: MINOR, 0.2.1 -> 0.3.0 (five new opt-in packs; new projects can get different
files), matching the 0.1.0 precedent. PR #19 (v0.2.0, Rust alone) is superseded by this PR:
close it with a pointer here after this merges.

## D11. Red-team and security additions
- RT2: the plugin pack's `files/.gstack/package-json-path` matches the template's own
  `.gitignore` (`.gstack/`) and survives only because it was force-added; a ZIP/degit copy
  committed with `git add -A` drops it, and the new project's first `/ship` then bumps VERSION
  only and the guard fails with a misleading message. Recommendation: a template-only
  `template/.gitignore` re-including that directory (bootstrap deletes `template/`), the plugin
  guard failing with an actionable message when `.gstack/package-json-path` is missing or does
  not name `manifest.json`, and a selftest that no tracked file matches any .gitignore.
- RT3 (pre-existing on master, python pack): a project named `target`, `dist` or `node_modules`
  gets literal placeholders in src/<name>/ because bootstrap's placeholder pass skips those
  directory names at any depth. Recommendation: reject the three names in
  `template/stacks/python/validate-name`, with a test; small and found by this review.
- SE2 is folded into D7; SE3 into D8.
