# Plan 004: Keep `AGENTS.md` and `CLAUDE.md`, and require agents entering through either to read both

> **Executor instructions**: Follow this plan step by step, run its verification, and honor
> the STOP conditions. Update `plans/README.md` when implementation is complete.
>
> **Revision, 2026-09-24:** The maintainer chose to retain both instruction files with
> reciprocal required reading. This replaces the original consolidation, deletion, shim and
> instruction-file guard design. The historical filename is retained to preserve links.
> Implemented and verified on 2026-09-24; see the execution evidence below.

## Status

- **State**: DONE (six new tests; complete suite: 80 passed, 0 failed, 0 skipped)
- **Priority**: P1 (requested by the maintainer)
- **Effort**: S
- **Risk**: LOW. Preserve both entry points and their existing responsibilities.
- **Depends on**: 001–003 (landed harness and bootstrap behavior)
- **Category**: dx
- **Originally planned at**: `1984ab7`, 2026-09-23
- **Revised against**: `ba7ca85`, 2026-09-24; predecessor suite: 74 tests.

## Execution evidence — 2026-09-24

- Baseline checks passed; normal and CI-mode self-tests each passed 74/74 with zero skips.
- Before instruction edits, the six new tests produced the expected one pass and five
  failures. After implementation, all six and the existing checklist test passed.
- `git diff --check`, shellcheck 0.11.0, and `./scripts/check.sh` passed. Gitleaks found no
  leaks; optional editorconfig-checker was unavailable, so formatting was not checked by it.
- Full normal and `CI=true` suites each passed **80 tests, 0 failed, 0 skipped**. No hosted
  GitHub Actions run was performed for this implementation.
- All six AGENTS and 16 CLAUDE complete placeholder tokens are unchanged from `ba7ca85`;
  diff review confirmed preservation of the remaining substantive rules.
- Fresh generated-project smoke sessions passed with Codex CLI 0.155.1 (`gpt-6-astra`) and
  Claude Code 2.1.281 (`claude-opus-5-5[1m]`). Traces show one explicit read of each companion
  file, in AGENTS-first and CLAUDE-first order respectively. Both identified rule ownership
  and stopped following the reciprocal reference after reading both. Fixture contents stayed
  unchanged, and neither ran project checks.
- The first Claude smoke used `claude-fable-5-1` and preloaded both files through an existing
  user setting. The second invocation excluded user settings to verify CLAUDE-first reading;
  no global configuration was changed. These are observed smoke results, not a guarantee
  that every host or model will follow the instructions.
- Logs, host traces, and the placeholder baseline are saved locally in `.context/plan-004/`.

## Decision and intended behavior

Both files remain substantive, tracked files in the template and generated projects:

| Entry point | Required companion | Existing responsibilities retained |
|---|---|---|
| `AGENTS.md` | Read `./CLAUDE.md` in full | Install, read order, trust boundary, ship gate, privacy |
| `CLAUDE.md` | Read `./AGENTS.md` in full | Architecture, key files, commands, standards, skill routing |

An agent entering through either file must read both before starting task work. A file already
read for the task does not need to be reread merely because its companion points back to it.
These are explicit instructions, not a claim that every host automatically loads both
filenames. Codex's documented discovery loads `AGENTS.md`; the companion is reached by
following its instruction. See the [OpenAI discovery documentation](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

At the revised baseline, `AGENTS.md` already listed `CLAUDE.md` in its read order. The missing direction was
`CLAUDE.md` back to `AGENTS.md`, where privacy and trust-boundary guidance live. Make both
links conspicuous and mandatory. Keep shared rules consistent; neither file silently overrides
a contradictory instruction in the other.

Use plain-language references. Do not add reciprocal `@` imports, a symlink, a settings-only
shim, or a rule forbidding `CLAUDE.md`. This design does not depend on Claude Code natively
loading `AGENTS.md` or require changing global host settings. Retaining `CLAUDE.md` also leaves
a normal home for workflow settings that tools persist there.

## Scope

Implementation changes:

- `AGENTS.md`: strengthen companion reading and correct the description of `CLAUDE.md`.
- `CLAUDE.md`: add reciprocal reading, retain its routing heading, update stale skill rows,
  and make skill invocation wording usable by different hosts.
- `TESTING.md`: retain the original plan's shared Commands section, pointing to `CLAUDE.md`.
- `README.md`, `TEMPLATE.md`, `bootstrap`: describe both files; preserve both checklist rows.
- `scripts/template-selftest.sh`: six regression tests for the two-file contract.
- `plans/README.md`: record implementation status and verification evidence after execution.

Out of scope: merging/deleting either file; duplicating their full contents; changing
`scripts/check.sh`; blocking `.claude/CLAUDE.md` or `CLAUDE.local.md`; changing global settings,
installed skills, tool versions, or unrelated doctrine. Plans 005–007 retain their own scope;
their dependent references were aligned during this revision.

## Preconditions and baseline

1. Inspect `git status --short`. Preserve unrelated work. Do not rename the current branch.
2. Review drift with:

   ```sh
   git diff ba7ca85 -- AGENTS.md CLAUDE.md TESTING.md README.md TEMPLATE.md bootstrap scripts/template-selftest.sh
   ```

   At this baseline, both instruction files are still the original template files,
   `TESTING.md` has no Commands heading, and the harness includes approved 001–003 fixes.
   Retain later additive tests and record their baseline; do not revert them to match a count.
   Stop if intended edits would overwrite newer instructions.
3. Run `./scripts/check.sh`, then `./scripts/template-selftest.sh` and
   `CI=true ./scripts/template-selftest.sh`. Each must exit 0. Expected at `ba7ca85`:
   `selftest: 74 passed, 0 failed, 0 skipped`. Resolve missing test prerequisites before
   claiming a fully passing baseline; do not weaken guards or hide failures.
4. Record each instruction file's placeholder inventory using step 5's comparison. Every
   placeholder must survive in its existing file, including its complete contents.

No Claude Code upgrade or native `AGENTS.md` setting change is a prerequisite. Record actual
hosts/models when performing the manual read-through below, rather than inferring success
from their version numbers.

## Implementation

### Step 1: Add six tests for the retained two-file contract

Add six functions with the `test_instruction_pair_` prefix before the harness runner. Use
existing `fresh_copy`, `run_bootstrap`, assertion and `fail` helpers with independent fixtures.
Bootstrap generated fixtures with `--name demo --yes`; check exit status before assertions.
Keep all predecessor tests and their expectations.

| Test suffix | Required assertions |
|---|---|
| `ships_both_files` | Source and generated projects contain both substantive files: AGENTS retains Install, Trust boundary, Before shipping, Privacy; CLAUDE retains Architecture, Commands, Skill routing. |
| `agents_requires_claude` | Source/generated AGENTS contain step 2's Required companion instructions heading, exact required-read and read-once sentences; no standalone `@CLAUDE.md` or `@./CLAUDE.md` import line. |
| `claude_requires_agents` | Source/generated CLAUDE contain the corresponding heading and sentences; no standalone `@AGENTS.md` or `@./AGENTS.md` import line. |
| `preserves_skill_routing` | Source/generated CLAUDE have exactly one `## Skill routing` heading; table invokes `context-save`, `context-restore`, and `run`, with no `checkpoint` or `verify` invocation row; step 3's host-neutral invocation sentence is present. |
| `documents_test_commands` | Source/generated TESTING have exactly one Commands heading before Why Tiers, both command placeholders from step 3, and its CLAUDE pointer; CLAUDE points to TESTING for matching commands. |
| `documents_both_entry_points` | Source README/TEMPLATE contain step 4's descriptions; generated README describes both files; bootstrap output includes both checklist rows and the read-both instruction. README/TEMPLATE descriptions make no claim that CLAUDE is absent. |

Inspect `TEMPLATE.md` in the source only: bootstrap deletes it from generated projects. Match
whole lines for import checks and use literal strings for prose containing backticks. These
tests validate the published instructions, not whether an LLM will always obey them.

**Verify before implementation:** `./scripts/template-selftest.sh instruction_pair` discovers
six tests: `ships_both_files` passes; the other five fail for the intended missing requirements.
Diagnose any different failure set before proceeding.

### Step 2: Require companion reading in both files

Insert this section after the existing introductory paragraph in `AGENTS.md`, before Install:

```markdown
## Required companion instructions

Before starting task work, read `./CLAUDE.md` in full. Both files' instructions apply.
Read each file once per task; if you already read the companion, do not follow the reference back again.
Keep shared rules consistent. If the two files conflict, surface the conflict instead of silently choosing one.
```

Insert the same section after `CLAUDE.md`'s introductory paragraph, before Architecture,
changing only its required-read sentence:

```markdown
Before starting task work, read `./AGENTS.md` in full. Both files' instructions apply.
```

Replace `AGENTS.md`'s existing introductory paragraph with:

```markdown
This is the install and operating protocol for every coding agent in this repo.
AGENTS.md and CLAUDE.md are companion instruction files; read both regardless of where your host starts.
```

Keep its Read this order list, correcting the CLAUDE description to:

```markdown
2. `./CLAUDE.md` — architecture, key files, commands, conventions, skill routing.
```

Trust boundaries remain in AGENTS. Add `./docs/architecture.md` as step 5, described as the
detailed map to read before changing anything load-bearing. Preserve all existing sections,
placeholders, and substantive rules in both files.

**Verify:** the two companion-reading tests and `ships_both_files` pass. Read both files in
each entry order to confirm the read-once instruction terminates the loop.

### Step 3: Retain the independent routing and command-discovery fixes

Keep `## Skill routing` in `CLAUDE.md`, with that exact spelling and capitalization. Replace
the paragraph requiring every host to use a Skill tool with:

```markdown
When the user's request matches an available skill, invoke it before doing the task.
Use the host's supported skill mechanism; if no Skill tool exists, read and follow that skill's SKILL.md.
Load the required repository instructions first. These skills carry specialized workflows
that produce better results than an ad-hoc answer.
```

This allows companion reading before skill work and avoids requiring an unavailable tool.
Preserve the shipping policy and unrelated routing rows. Replace checkpoint/resume with:

```markdown
| Save progress / checkpoint | `context-save` |
| "Where was I" / resume saved work | `context-restore` |
```

Replace the separate `verify` and `run` rows with:

```markdown
| Run / launch / screenshot the app, or verify a change works in it | `run` |
```

Routing applies when the skill is available, as the introduction states. Do not install
missing skills or claim that every host exposes every listed skill.

In `CLAUDE.md` → Commands, after the stack-agnostic note, add:

```markdown
Keep the check and test commands in sync with `TESTING.md` → Commands.
```

In `TESTING.md`, after the stack-agnostic blockquote and before Why Tiers, add:

```markdown
## Commands

The exact commands for this repo; keep them in sync with `CLAUDE.md` → Commands.
Fill these in as soon as a stack exists so agents and workflow skills can discover them.

- Checks (guards that run before tests): `{{CHECK_CMD}}`
- Tests: `{{TEST_CMD}}`
```

Keep the tiered testing doctrine unchanged. This retains the shared Commands location used
by later plans without moving any command placeholders out of `CLAUDE.md`.

**Verify:** `preserves_skill_routing` and `documents_test_commands` pass.

### Step 4: Align template descriptions and bootstrap output

Replace the two instruction-file bullets in `README.md` with:

```markdown
- `CLAUDE.md` — architecture, commands, conventions, and skill routing; also requires `AGENTS.md`.
- `AGENTS.md` — install, trust boundary, ship gate, and privacy; also requires `CLAUDE.md`.
  Every agent reads both files, regardless of its entry point.
```

Replace the instruction-file bullet in `TEMPLATE.md` with:

```markdown
- `CLAUDE.md`, `AGENTS.md` — companion instructions for every coding agent. Each requires reading
  the other once; keep both files and preserve their division of responsibilities.
```

Keep both instruction-file checklist rows in `bootstrap`. Use:

```text
  CLAUDE.md   - tagline, architecture, key files, commands, skill routing; read with AGENTS.md
  AGENTS.md   - install command, trust boundary, ship gate, privacy; read with CLAUDE.md
  TESTING.md  - check/test commands, tier modules, API surfaces, NAMED_INVARIANTS, critical journeys
```

Preserve all other rows and bootstrap behavior. Add this standalone instruction before the
existing `Then choose a stack and:` line:

```text
Every agent must read both CLAUDE.md and AGENTS.md once before starting task work.
```

**Verify:** `documents_both_entry_points` and the existing checklist test pass. The complete
`instruction_pair` selection now reports six passes with no failures or skips.

### Step 5: Verify content preservation and the complete gate

Compare per-file placeholder-name inventories with the revised baseline. Run in Bash:

```bash
mkdir -p .context/plan-004
for instruction_file in AGENTS.md CLAUDE.md; do
  git show "ba7ca85:$instruction_file" | grep -o '{{[A-Z_]*' | LC_ALL=C sort > ".context/plan-004/$instruction_file.before"
  grep -o '{{[A-Z_]*' "$instruction_file" | LC_ALL=C sort > ".context/plan-004/$instruction_file.after"
  diff -u ".context/plan-004/$instruction_file.before" ".context/plan-004/$instruction_file.after" || exit 1
done
```

Expected: no differences. Inspect the full diff too: names alone do not prove that complete
placeholder contents and substantive instructions survived. TESTING's two new command
placeholders are intentional and outside this comparison. If approved later work changed
placeholders, use its recorded baseline and explain the difference; do not discard it.

Run checks, then tests:

```sh
git diff --check
shellcheck bootstrap scripts/check.sh scripts/template-selftest.sh
./scripts/check.sh
./scripts/template-selftest.sh
CI=true ./scripts/template-selftest.sh
```

All must exit 0. Expected at the recorded baseline: **80 passed, 0 failed, 0 skipped** (74
predecessor tests plus six here). Report any locally skipped optional formatting tool; do not
call it a formatting pass. Preserve additional tests if the predecessor suite grows.

Manually exercise fresh agent sessions from both available entry points with this read-only
prompt: "Read the repository instructions and list which files you read, where privacy and
trust-boundary rules live, where commands and skill routing live, and how you handle the
companion-file reference. Do not edit files or run project checks."

Expected: both files are read, ownership matches the table above, and references do not cause
repeated reads. Where tool traces are available, verify file reads as well as the answer.
Report the tested host/model and any unavailable host as a limitation. This is a manual smoke
check, not a deterministic guarantee or CI test.

## Done criteria

- [x] Both substantive files survive in source and generated projects.
- [x] Both explicitly require the companion and include the read-once rule.
- [x] CLAUDE retains exactly one Skill routing section with the approved row updates.
- [x] TESTING Commands and CLAUDE Commands point to one another with matching placeholders.
- [x] Descriptions and bootstrap output require reading both files.
- [x] Per-file placeholder inventories and substantive-content review pass.
- [x] All six new tests and all predecessor tests pass; CI mode has zero skips.
- [x] Shell lint, existing guards, and `git diff --check` exit 0.
- [x] Manual host smoke-check evidence or an explicit availability limitation is reported.
- [x] No instruction-file deletion, single-file guard, shim, symlink, or global setting change.
- [x] `plans/README.md` records implementation status and actual verification totals.

## STOP conditions

Stop and report if the baseline fails, a predecessor test regresses, the initial six-test
failure set differs for an unexplained reason, either file loses a placeholder or substantive
rule, or companion references create contradictory guidance. Do not overwrite newer routing
edits or silently broaden into global tool configuration. Inspect and report unexpected skill
edits outside the implementation scope.

## Maintenance and downstream plans

- Keep the ownership table accurate. Add rules to their natural home and rely on companion
  reading; avoid copying whole sections into both files.
- Plan 005 adds template-only blocks to AGENTS and TESTING. An agent entering through CLAUDE
  reaches the AGENTS block through its required companion instruction.
- Plans 006–007 personalize command placeholders in retained CLAUDE and shared TESTING,
  along with existing placeholders elsewhere. No settings-only shim is needed.
- Workflow settings can remain in the file their host uses. Preserve both companion sections
  and the exact CLAUDE Skill routing heading.
- If a host does not follow the reference, investigate with a focused read-only reproduction;
  do not silently reintroduce the superseded deletion plan.
