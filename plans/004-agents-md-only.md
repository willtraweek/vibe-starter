# Plan 004: Fold `CLAUDE.md` into `AGENTS.md` so the template ships one instruction file, and keep gstack from quietly recreating `CLAUDE.md`

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 1984ab7..HEAD -- CLAUDE.md AGENTS.md README.md TEMPLATE.md TESTING.md`
> Plans 001–003 (dependencies) legitimately changed `TEMPLATE.md` (a new section at the end),
> `bootstrap`, `scripts/check.sh` and `scripts/template-selftest.sh`. Any change to `CLAUDE.md`,
> `AGENTS.md`, `README.md` or `TESTING.md` since `1984ab7` is a STOP condition.

## Status

- **Priority**: P1 (requested by the maintainer)
- **Effort**: M
- **Risk**: MED. It changes which file every agent reads first. It is mitigated by tests and a
  guard.
- **Depends on**: 001 (harness), 002 (`check_fixture`/`run_check` test helpers and the current
  `scripts/check.sh` layout), 003 (checklist lines in `bootstrap`)
- **Category**: dx
- **Planned at**: commit `1984ab7`, 2026-09-23

## Why this matters

The maintainer wants one instruction file. Today the template ships two that overlap:
`CLAUDE.md` (136 lines: architecture, commands, standards, skill routing) and `AGENTS.md`
(43 lines: install, trust boundary, protocol). Non-Claude agents are told to read both.
`AGENTS.md` is the cross-agent standard. Codex, OpenClaw, Hermes and gstack's own `codex` host
treat it as *the* instructions file, and Claude Code reads it natively since v2.1.277.

Two ecosystem facts shape how this must be done. Both were verified against the tools' docs and
source while planning:

1. **Claude Code only reads `AGENTS.md` when no `CLAUDE.md` exists.** Its default setting reads
   `AGENTS.md` only when there is no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` in
   the working directory or above. A `CLAUDE.md` that reappears silently hides `AGENTS.md`.
   The exception is a `CLAUDE.md` that imports it with an `@AGENTS.md` line. (The maintainer's
   own `~/.claude/settings.json` sets `instructionFiles: claude-md-and-agents-md`, which loads
   both. Other machines and collaborators use the default.)
2. **gstack (the maintainer's workflow suite) defaults to `CLAUDE.md`** and recreates it:
   - Every gstack skill's preamble offers to *create and commit* a `CLAUDE.md` with routing
     rules. It skips the offer only if `CLAUDE.md` or `AGENTS.md` contains the exact,
     case-sensitive text `## Skill routing`.
   - `/ship` (step 4) looks for the test command only in `CLAUDE.md` and `TESTING.md`. If it
     has to ask, it saves the answer into `CLAUDE.md`, creating it.
   - `/setup-deploy`, `/health`, `/design-consultation` and `/setup-gbrain` write their settings
     into `CLAUDE.md` and create it if it is missing.

So "delete `CLAUDE.md`" alone would be undone by the next gstack run, and on default Claude Code
settings that undo would silently drop every instruction in `AGENTS.md`. This plan merges the
content, keeps the exact routing heading gstack looks for, and puts the test command where
`/ship` reads it (`TESTING.md`). It also adds a guard to `scripts/check.sh`: the only
`CLAUDE.md` allowed is a gstack-settings shim whose first line is `@AGENTS.md`. That keeps
`AGENTS.md` loaded and authoritative without breaking gstack features that can only persist
settings in `CLAUDE.md`.

## Preconditions (operator, not executor)

These live outside the repo. The executor must **not** change them. **Both were done and
verified on 2026-09-23**: the terminal CLI reports `2.1.281`, and the stale symlink is gone. They
stay listed because every *other* machine that works in these repos needs the same. Report
`claude --version` in your summary anyway.

- **Claude Code version on every machine that works in these repos must be ≥ v2.1.281.** It
  reads `AGENTS.md` natively from v2.1.277, and from v2.1.281 also in Bedrock and
  telemetry-disabled sessions. At planning time the maintainer's terminal `claude --version`
  was `2.1.261`. That version would load **no** project instructions once `CLAUDE.md` is gone.
  The Conductor-embedded agent already reads `AGENTS.md`. Fix: `claude update`.
- **Stale gstack skill on the maintainer's machine:** `~/.claude/skills/checkpoint/SKILL.md` is a
  symlink to an old gstack v0.17 checkout (`~/gstack/checkpoint/SKILL.md`). That old skill only
  looks for `## Skill routing` in `CLAUDE.md`, so it will create and commit a `CLAUDE.md` even
  when `AGENTS.md` has the heading. Current gstack (1.87.5.0) replaced it with
  `/context-save` and `/context-restore`. This plan re-routes to those. The operator should also
  delete the stale symlink.

## Current state

- `CLAUDE.md` (136 lines). Sections: title + `Project: {{PROJECT_NAME}}` + tagline + intro (1–9),
  Architecture (11–14), Key files (16–19), Commands (21–31), Engineering standards (33–44),
  Testing (46–57), Change philosophy (59–69), Working in this repo (71–88), Design (90–93),
  Doctrine (95–98), Skill routing (100–136, with a table of 20 skill rows and a
  `{{PROJECT_SKILLS}}` placeholder).
- `AGENTS.md` (43 lines). Sections: title (1), intro (3–5), Install (7–11),
  Read this order (13–18), Trust boundary (20–24), How to work here (26–33),
  Before shipping (35–38), Privacy (40–43).

Lines that change meaning:

```markdown
AGENTS.md:3   This is your install + operating protocol. Claude Code reads `./CLAUDE.md` automatically.
AGENTS.md:16  2. `./CLAUDE.md` — architecture reference, key files, trust boundaries, conventions.
CLAUDE.md:102 When the user's request matches an available skill, ALWAYS invoke it using the Skill tool as
CLAUDE.md:129 | Save progress / checkpoint / "where was I" / resume | `checkpoint` |
CLAUDE.md:132 | Verify a change actually works by running the app | `verify` |
CLAUDE.md:133 | Run / launch / screenshot the app | `run` |
```

(`checkpoint` is a stale skill, see Preconditions. `verify` is not installed on the maintainer's
machine; `run` covers "confirm a change works in the real app". AGENTS.md:16 is also wrong
today: trust boundaries live in AGENTS.md, not CLAUDE.md.)

Other references to `CLAUDE.md` (the whole list, from `git grep -n CLAUDE`):

```text
README.md:33    - `CLAUDE.md` — how agents work in this repo (routing, conventions, change philosophy).
README.md:34    - `AGENTS.md` — install + operating protocol for non-Claude agents.
TEMPLATE.md:19  - `CLAUDE.md`, `AGENTS.md` — how Claude and other agents work in the repo (routing, protocol).
bootstrap       (checklist heredoc)   CLAUDE.md   - tagline, architecture, key files, command placeholders
```

In `bootstrap`, after plan 003, the checklist lines this plan changes are:

```text
  CLAUDE.md   - tagline, architecture, key files, command placeholders
  AGENTS.md   - install command, trust boundary, ship gate
  TESTING.md  - tier modules, API surfaces, NAMED_INVARIANTS, critical journeys
```

`TESTING.md` lines 9–12 are the blockquote you'll insert after:

```markdown
> **Stack-agnostic note.** This template carries the testing *philosophy*. The concrete
> enforcement (coverage tooling, CI config) is per-stack. **Do not scaffold a coverage gate
> until you have chosen a language and test runner** — wiring a 90% gate before there is code
> to cover just breeds empty-shell tests. Pick the stack, then instantiate the gates below.
```

`scripts/check.sh` after plan 002 ends with:

```bash
if [ "$status" = "0" ]; then
  [ "$ran_any" = "1" ] && echo "OK: checks passed." || echo "OK: no checks configured yet."
fi
exit "$status"
```

Harness helpers available (from plans 001/002): `fresh_copy`, `run_bootstrap`, `check_fixture`,
`run_check <dir> VAR=value...` (runs `scripts/check.sh` with editorconfig-checker hidden),
`fail`, `assert_exit`, `assert_contains`, `assert_not_contains`, `assert_absent`, `$REPO`,
`$WORK`.

Conventions: keep existing wording wherever the content isn't changing. This plan is a merge,
not a rewrite. Markdown continuation lines are indented **2 spaces**, not 3. The repo's
`.editorconfig` sets `indent_size = 2` for `*.md`, and editorconfig-checker flags 3.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Self-test | `./scripts/template-selftest.sh` | `selftest: 30 passed, 0 failed, 0 skipped` (24 from plans 001–003 + 6 here) |
| This plan's tests | `./scripts/template-selftest.sh claude` / `... gstack_routing` | all ok |
| Guard on the real repo | `./scripts/check.sh` | exit 0; prints `- instruction files: checking AGENTS.md stays the one agents read...` |
| Shell lint | `shellcheck bootstrap scripts/check.sh scripts/template-selftest.sh` | exit 0 |

## Suggested executor toolkit

- gstack `/review` on the finished diff. It already handles `AGENTS.md`.
- **Do NOT run** gstack `/health`, `/setup-deploy`, `/design-consultation`, `/setup-gbrain`,
  `/checkpoint`, or `/document-generate` while working on this plan. Each can write a
  `CLAUDE.md`. If gstack's preamble offers to "add routing rules to CLAUDE.md", answer **no**.
  After step 2 it should stop offering.
- Do not run gstack `/ship` unless asked (see the shipping caveat in `plans/README.md`).

## Scope

**In scope** (the only files you should modify):

- `AGENTS.md` (rewrite as below)
- `CLAUDE.md` (delete with `git rm`)
- `TESTING.md` (insert one `## Commands` section, nothing else)
- `README.md` (lines 33–34 only)
- `TEMPLATE.md` (line 19 only)
- `bootstrap` (the three checklist lines above only)
- `scripts/check.sh` (add one guard block)
- `scripts/template-selftest.sh` (append tests above the runner)
- `plans/README.md` (your status row)

**Out of scope** (do NOT touch):

- The doctrine text in `TESTING.md`, `ENGINEERING.md`, `DOCTRINE.md`: no rewording, and no
  Decisions Log rows. The new `## Commands` section is the only `TESTING.md` change.
- Adding or removing skills in the routing table beyond the three row changes specified.
- The maintainer's machine: `~/.claude/...`, the stale `checkpoint` symlink, the Claude Code
  version. These are operator actions (see Preconditions).
- `.gitignore` (leave `CLAUDE.local.md` un-ignored; the guard handles it).
- Adding a `CLAUDE.md` shim to the template. The template ships **no** `CLAUDE.md`.

## Git workflow

- Work on the branch you were given (Conductor: `willtraweek/<topic>`). If you must create one:
  `willtraweek/plan-004-agents-md-only`.
- Commit per step, plain imperative messages (e.g.
  `Merge CLAUDE.md into AGENTS.md as the single instruction file`).
- Do NOT push or open a PR unless the operator told you to.

## Steps

### Step 1: Add the failing tests

Insert this block into `scripts/template-selftest.sh` immediately **above** `# --- runner ---`:

```bash
# --- tests: AGENTS.md is the only instruction file (plan 004) -----------------
test_template_ships_no_claude_md() {
  local d="$WORK/no-claude/proj"
  fresh_copy "$d"
  assert_absent "$d/CLAUDE.md" || return 1
  assert_absent "$d/.claude/CLAUDE.md"
}
test_agents_md_keeps_gstack_routing_heading() {
  # gstack's skill preamble greps CLAUDE.md and AGENTS.md for this exact heading;
  # when it is missing, gstack offers to create a CLAUDE.md with its own routing.
  grep -qx '## Skill routing' "$REPO/AGENTS.md" || fail "AGENTS.md lacks an exact '## Skill routing' line"
}
test_new_project_mentions_claude_md_only_where_intended() {
  local d="$WORK/claude-refs/proj" hits
  fresh_copy "$d"
  run_bootstrap "$d" --name proj --yes || fail "bootstrap exited $?" || return 1
  assert_not_contains "$d.out" "CLAUDE.md" || return 1
  # Until plan 005 separates skeletons, /ship history can name the removed file.
  hits="$(cd "$d" && grep -rl --exclude-dir=.git 'CLAUDE' . | sed 's|^\./||' \
    | grep -vxE 'AGENTS\.md|TESTING\.md|CHANGELOG\.md|scripts/check\.sh' || true)"
  [ -z "$hits" ] || fail "unexpected CLAUDE.md references in: $(echo "$hits" | tr '\n' ' ')"
}
test_check_rejects_claude_md_without_agents_import() {
  local d="$WORK/check-claude/proj" rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  printf '# Project instructions\n' > "$d/CLAUDE.md"
  run_check "$d" GITLEAKS_BIN=/nonexistent/gitleaks CI=; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" "Claude Code would stop reading AGENTS.md"
}
test_check_accepts_claude_md_that_imports_agents_md() {
  local d="$WORK/check-claude-shim/proj"
  check_fixture "$d" || fail "fixture setup failed" || return 1
  printf '@AGENTS.md\n\n## Deploy Configuration (configured by /setup-deploy)\n- Platform: example\n' > "$d/CLAUDE.md"
  run_check "$d" GITLEAKS_BIN=/nonexistent/gitleaks CI= \
    || fail "check.sh rejected a CLAUDE.md that imports AGENTS.md: $(tail -5 "$d.out")"
}
test_check_rejects_dot_claude_claude_md() {
  local d="$WORK/check-dot-claude/proj" rc
  check_fixture "$d" || fail "fixture setup failed" || return 1
  mkdir -p "$d/.claude" && printf '@../AGENTS.md\n' > "$d/.claude/CLAUDE.md"
  run_check "$d" GITLEAKS_BIN=/nonexistent/gitleaks CI=; rc=$?
  assert_exit 1 "$rc" || return 1
  assert_contains "$d.out" ".claude/CLAUDE.md exists"
}
```

**Verify**: `./scripts/template-selftest.sh` → `selftest: 25 passed, 5 failed, 0 skipped`. The 5
failures are all of the above except `test_check_accepts_claude_md_that_imports_agents_md`,
which passes already. It guards against making the check too strict. (This was checked against
the post-003 files while planning.)

### Step 2: Replace `AGENTS.md` with the merged file

Overwrite `AGENTS.md` with exactly this content. It keeps every placeholder from both old files.
The one exception is the duplicate `{{PROJECT_NAME}}` from `CLAUDE.md:3`; the title already
carries the name. Every continuation line is indented 2 spaces.

```markdown
# Agents working on {{PROJECT_NAME}}

{{PROJECT_TAGLINE: one or two sentences on what this project is and who it's for.}}

This is the one instruction file for every coding agent in this repo: Claude Code, Codex,
Cursor, and the rest. Claude Code reads it natively because the repo has no `CLAUDE.md` (see
"One instruction file" below). Read it before making changes. Start broad, narrow down, prefer
small surgical edits over sweeping rewrites, and always leave the repo green (checks and tests
both exit 0).

## Install

1. Clone: `{{CLONE_CMD: git clone <repo-url> && cd <dir>}}`
2. Install deps: `{{INSTALL_CMD: e.g. bun install / uv sync / cargo build}}`
3. Configure: `{{CONFIG_STEPS: env vars, API keys, local state — or "none"}}`

## Commands

This template is stack-agnostic. Fill these in once a stack is chosen, then delete this note.
Mirror the check and test commands in `TESTING.md` → Commands, which is where gstack's `/ship`
looks for them.

- Install / bootstrap: `{{INSTALL_CMD}}`
- Dev / run locally: `{{DEV_CMD}}`
- Build: `{{BUILD_CMD}}`
- Lint / typecheck / static checks: `{{CHECK_CMD}}`
- Tests: `{{TEST_CMD}}`

{{OTHER_COMMANDS: any project-specific commands worth knowing — codegen, migrations, deploy, etc.}}

## Read this order

1. `./AGENTS.md` (this file) — install, commands, architecture, conventions, skill routing.
2. `./DOCTRINE.md` — the cross-project engineering ethos this repo inherits.
3. `./TESTING.md` and `./ENGINEERING.md` — how we test and how we organize code.
4. `./docs/architecture.md` — the detailed map; read it before changing anything load-bearing.

## Architecture

{{ARCHITECTURE: describe the high-level design and the main modules / boundaries. Note any
contracts or invariants an agent must preserve.}}

## Key files

{{KEY_FILES: list the load-bearing files and what each is responsible for, one per line. Update
this whenever you add or significantly change a core file.}}

## Trust boundary (critical)

`{{TRUST_BOUNDARY: if this system has trusted (local CLI) vs untrusted (agent / remote)
callers, describe the distinction and which operations tighten under the untrusted path. If
there is no such boundary yet, say so — and add one before exposing anything to remote agents.}}`

## Engineering standards

Defer to `ENGINEERING.md` for the full doctrine. The short version:

- **File-size smells** — when a file gets large, that's a signal to look for a seam, not a
  mandate to split. Split on cohesion, not line count.
- **Rule of three** — don't abstract on the second occurrence. Wait for the third before
  extracting a shared helper.
- **Cohesion over fragmentation** — keep things that change together in the same place. Prefer
  one well-named module over five tiny ones that must be read in concert.

See `DOCTRINE.md` for the cross-project engineering ethos shared across all of my projects.

## Testing

Defer to `TESTING.md` for the testing doctrine (what to test, what not to, how the tiers are
structured, how to run the integration tiers).

The non-negotiables that apply to any stack:

- Run the checks (`{{CHECK_CMD}}`) and the tests (`{{TEST_CMD}}`) before considering a change
  done. Both must exit 0.
- Every behavior change needs test coverage. A bug fix without a regression test is incomplete.
- Do not skip the slower / integration / end-to-end tiers just because they need setup (a
  database, API keys, a container). Stand the dependency up, run them, tear it down.

## Change philosophy

- **Small changes.** Make the smallest change that fully solves the task. Don't gold-plate;
  don't leave it half-done either.
- **No unrequested refactors.** If you spot something worth cleaning up that's outside the task,
  note it — don't fold it into this change.
- **Preserve contracts.** Don't break public APIs, exported signatures, on-disk formats, config
  keys, or CLI surfaces unless that IS the task. When a contract must change, call it out
  explicitly.
- **Match the surrounding code.** Follow the conventions already in the file over your own
  preferences.

## Working in this repo (before / after checklist)

**Before you start:**

1. Read this file, plus `{{RELEVANT_DOCS: the docs that matter for the area you're touching —
  e.g. ENGINEERING.md, TESTING.md, a design doc}}`.
2. Understand the existing contracts and invariants in the area you're changing (see
  Architecture / Key files above).
3. Make sure you're on a branch, not the default branch.

**After you finish:**

1. Run the checks: `{{CHECK_CMD}}` → must exit 0.
2. Run the tests: `{{TEST_CMD}}` → must exit 0.
3. Update docs that drifted (this file's Key files section, plus any guide that describes what
  you changed).
4. Only commit / push / open a PR when asked — and prefer `/ship` over hand-rolling git
  operations (see Skill routing).

## Before shipping

`{{SHIP_GATE: the one command that runs the full local gate — checks + tests, e.g.
./scripts/check.sh && <test cmd>. Ship via the /ship skill, not by hand.}}`

## Design

If this project has a UI, see `DESIGN.md` for the design system (aesthetic, typography, color,
spacing, motion) and the visual bar to hold the work to. Align with its tokens — no hardcoded
colors, fonts, or spacing.

## Doctrine

`DOCTRINE.md` holds the cross-project engineering ethos that applies to all of my projects. Read
it once; it's the "why" behind the standards above.

## Privacy

Never commit real names of people, companies, or funds, real user data, or secrets into public
artifacts. Use generic placeholders (`alice-example`, `acme-example`, `fund-a`).

## One instruction file (no CLAUDE.md)

All agent instructions live here, on purpose. Keep it that way:

- **Claude Code** (v2.1.277 or later) reads `AGENTS.md` natively, but only while there is no
  `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` in this directory or above it. Adding
  one makes Claude Code silently skip this file, unless your Claude Code setting
  `instructionFiles` is `claude-md-and-agents-md`.
- **gstack** skills still write some of their settings into `CLAUDE.md` and create it if it is
  missing: `/setup-deploy` (deploy configuration), `/health` (health stack),
  `/design-consultation` (design-system pointer), `/setup-gbrain` and `/sync-gbrain` (gbrain
  guidance), and `/ship` or `/qa` when they had to ask for the test command. Decline when you
  can. When a setting must persist for gstack to read it, let the skill write `CLAUDE.md`, then
  make `@AGENTS.md` its first line (the import keeps this file loaded) and keep nothing in it
  but that gstack section. `scripts/check.sh` fails on any other `CLAUDE.md`.
- Keep the `## Skill routing` heading below exactly as written. gstack checks for it and, if
  it is missing, offers to create a `CLAUDE.md` with routing rules of its own.
- gstack's `/ship` reads the test command from `TESTING.md` → Commands, not from this file.

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it as your FIRST action (in
Claude Code, via the Skill tool; in other agents, invoke the skill by name, e.g. `/ship`). Do
NOT answer directly, and do NOT use other tools first. These skills carry specialized workflows
that produce better results than an ad-hoc answer.

**NEVER hand-roll ship operations.** Do not manually run git commit + push + `gh pr create` when
`/ship` is available. `/ship` handles version bump, CHANGELOG, doc updates, pre-landing review,
test-coverage audit, and adversarial review — a manual PR skips all of that. If the user says
"commit and ship", "push and ship", or any phrasing that ends in shipping, invoke `/ship` and
let it own the commits.

| When the user wants to… | Invoke |
|---|---|
| Float a product idea, "is this worth building", brainstorm scope | `office-hours` |
| Turn vague intent into a precise, executable spec | `spec` |
| Review a plan's architecture / engineering approach | `plan-eng-review` |
| Review a plan as a founder / CEO would | `plan-ceo-review` |
| Review a plan for design / UX | `plan-design-review` |
| Review a plan for developer experience | `plan-devex-review` |
| Debug a bug, error, 500, "why is this broken" | `investigate` |
| QA the app and fix what's found | `qa` |
| QA the app, report only (no fixes) | `qa-only` |
| Review a diff / PR before landing | `review` |
| Visual audit, design polish, find AI-slop / spacing / hierarchy issues | `design-review` |
| Stand up a design system / brand | `design-consultation` |
| Ship: bump version, changelog, test, PR | `ship` |
| Land and deploy | `land-and-deploy` |
| Update docs after shipping | `document-release` |
| Save progress / checkpoint | `context-save` |
| "Where was I" / resume saved work | `context-restore` |
| Code-health dashboard / quality check | `health` |
| Weekly engineering retro | `retro` |
| Run / launch / screenshot the app, or verify a change works in it | `run` |

{{PROJECT_SKILLS: add any project-specific skills here, and prune rows above that don't apply to
this project.}}
```

What moved where (for your report and the reviewer):

| Old location | New location in AGENTS.md |
|---|---|
| CLAUDE.md:1–3 (title, `Project:` line) | dropped; the title `# Agents working on {{PROJECT_NAME}}` carries the name |
| CLAUDE.md:5 tagline; CLAUDE.md:7–9 intro | line 3; intro paragraph (reworded: one file for all agents) |
| CLAUDE.md Architecture, Key files, Commands, Engineering standards, Testing, Change philosophy, Working in this repo, Design, Doctrine | same headings, same text; Commands gains a sentence pointing at `TESTING.md`; list continuations re-indented to 2 spaces |
| CLAUDE.md Skill routing | same heading; first sentence made host-neutral; `checkpoint` → `context-save` + `context-restore`; `verify` + `run` rows merged into one `run` row |
| AGENTS.md Install, Trust boundary, Before shipping, Privacy | unchanged |
| AGENTS.md Read this order | CLAUDE.md step removed; `docs/architecture.md` added |
| AGENTS.md How to work here | merged: first two bullets were already covered by Change philosophy and Testing; the DESIGN.md-tokens bullet moved into Design |
| (new) | `## One instruction file (no CLAUDE.md)` |

**Verify**:

- `grep -cx '## Skill routing' AGENTS.md` → `1`
- `grep -nE '^( {2})* [^ ]' AGENTS.md` → no output (no odd indentation)
- Placeholder parity. The only difference must be one fewer `{{PROJECT_NAME`:

  ```sh
  diff <( (git show 1984ab7:CLAUDE.md; git show 1984ab7:AGENTS.md) | grep -o '{{[A-Z_]*' | sort ) \
       <(grep -o '{{[A-Z_]*' AGENTS.md | sort) | grep '^[<>]'
  ```

  → exactly one line of output: `< {{PROJECT_NAME`
- No routing row invokes the stale skills. This must print `0`:

  ```sh
  grep -cE '\| `(checkpoint|verify)` \|' AGENTS.md
  ```

### Step 3: Delete `CLAUDE.md`

`git rm CLAUDE.md`

**Verify**: `test ! -e CLAUDE.md && echo gone` → `gone`.
`./scripts/template-selftest.sh claude` → `test_template_ships_no_claude_md` ok.

### Step 4: Put the check and test commands where gstack's `/ship` reads them

In `TESTING.md`, directly after the stack-agnostic blockquote (the 4 lines quoted in Current
state, ending `...Pick the stack, then instantiate the gates below.`), insert a blank line and
this section:

```markdown
## Commands

The exact commands for this repo; keep them in sync with `AGENTS.md` → Commands. gstack's
`/ship` looks for the test command here (and in a `CLAUDE.md`, which this repo does not have)
before deciding whether to set up a test framework of its own. Fill these in as soon as a stack
exists so it never has to.

- Checks (guards that run before tests): `{{CHECK_CMD}}`
- Tests: `{{TEST_CMD}}`
```

It must end up between the blockquote and `## Why Tiers, Not One Number`, separated by blank
lines.

Why this matters beyond `CLAUDE.md`: when `/ship` finds no documented test command in a project
that has a stack, it sets up a framework itself. It appends gstack's own "100% test coverage is
the key..." philosophy to `TESTING.md` (which contradicts this doctrine's tiered, "blind 100% is
wasteful" stance), adds a `.github/workflows/test.yml`, and writes `CLAUDE.md`. A filled-in
command here prevents all three.

**Verify**: `grep -n '^## Commands' TESTING.md` → one line, before `## Why Tiers, Not One Number`
(compare with `grep -n '^## Why Tiers' TESTING.md`).

### Step 5: Update the remaining references

1. `README.md` lines 33–34: replace the two lines

   ```markdown
   - `CLAUDE.md` — how agents work in this repo (routing, conventions, change philosophy).
   - `AGENTS.md` — install + operating protocol for non-Claude agents.
   ```

   with

   ```markdown
   - `AGENTS.md` — the one instruction file for every coding agent (Claude Code reads it natively):
     install, commands, conventions, skill routing.
   ```

   (The second line is indented 2 spaces.)

2. `TEMPLATE.md` line 19: replace
   `` - `CLAUDE.md`, `AGENTS.md` — how Claude and other agents work in the repo (routing, protocol).``
   with these two lines (second indented 2 spaces):

   ```markdown
   - `AGENTS.md` — the one instruction file for Claude Code, Codex, and other agents (routing,
     protocol). There is deliberately no `CLAUDE.md`.
   ```

3. `bootstrap` checklist: replace the three lines quoted in Current state with these two:

   ```text
     AGENTS.md   - tagline, install, commands, architecture, key files, trust boundary, ship gate
     TESTING.md  - check/test commands (gstack /ship reads them here), tiers, NAMED_INVARIANTS
   ```

**Verify**: `git grep -n 'CLAUDE' -- . ':!plans'` → matches only in `AGENTS.md`, `TESTING.md`,
`TEMPLATE.md` (the "deliberately no" line), `scripts/check.sh` (after step 6) and
`scripts/template-selftest.sh` (tests), plus historical entries in `CHANGELOG.md`.
`./scripts/template-selftest.sh checklist` → ok.

### Step 6: Add the instruction-file guard to `scripts/check.sh`

Insert this block immediately **above** the final `if [ "$status" = "0" ]; then` block:

```bash
# --- Instruction files: AGENTS.md is the one agents read -----------------
# Claude Code skips AGENTS.md whenever a CLAUDE.md exists (default settings)
# unless that CLAUDE.md imports it. gstack skills may create CLAUDE.md to
# persist their own settings: allowed only with "@AGENTS.md" as the first line.
ran_any=1
echo "- instruction files: checking AGENTS.md stays the one agents read..."
if [ -f .claude/CLAUDE.md ]; then
  echo "- .claude/CLAUDE.md exists: move its instructions into AGENTS.md and delete it." >&2
  status=1
fi
if [ -f CLAUDE.md ] && [ "$(head -n 1 CLAUDE.md)" != "@AGENTS.md" ]; then
  echo "- CLAUDE.md exists without '@AGENTS.md' as its first line, so Claude Code would stop reading AGENTS.md." >&2
  echo "  Move its instructions into AGENTS.md; keep only gstack-managed settings there, under an '@AGENTS.md' first line." >&2
  status=1
fi
if [ -f CLAUDE.local.md ]; then
  echo "- note: CLAUDE.local.md exists; with Claude Code's default settings it hides AGENTS.md from you."
fi
```

This guard needs no external tool, so it always runs.

**Verify**: `./scripts/check.sh` → exit 0 and prints the `- instruction files:` line.
`shellcheck scripts/check.sh` → exit 0. `./scripts/template-selftest.sh` →
`selftest: 30 passed, 0 failed, 0 skipped`.

## Test plan

- 6 new tests (step 1). They cover: no CLAUDE.md shipped; the exact gstack routing heading; no
  stale CLAUDE.md references in a new project or in bootstrap's output; the guard rejects a
  plain CLAUDE.md and `.claude/CLAUDE.md` and accepts an `@AGENTS.md` shim.
- Plan 001's happy-path test keeps asserting `AGENTS.md` carries the project name and
  `{{TRUST_BOUNDARY`. It must still pass. Plan 003's checklist test must still pass with the new
  checklist lines.
- Final: `30 passed, 0 failed, 0 skipped`.

## Done criteria

ALL must hold:

- [ ] `./scripts/template-selftest.sh` exits 0 with `30 passed, 0 failed, 0 skipped`
- [ ] `CI=true ./scripts/template-selftest.sh` exits 0
- [ ] `test ! -e CLAUDE.md`
- [ ] `grep -cx '## Skill routing' AGENTS.md` → `1`
- [ ] Placeholder-parity command from step 2 prints exactly one line: `< {{PROJECT_NAME`
- [ ] `./scripts/check.sh` exits 0 on the real repo
- [ ] `shellcheck bootstrap scripts/check.sh scripts/template-selftest.sh` exits 0
- [ ] `git status --porcelain` shows changes only to in-scope files
- [ ] Your report includes the output of `claude --version` (if the CLI exists in your
      environment), for the operator precondition
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The step-1 failure set is not the 5 tests listed, or any plan-001–003 test fails at any point.
- The placeholder-parity diff shows anything other than `< {{PROJECT_NAME`. You dropped or
  invented a placeholder.
- A gstack skill (or its preamble) creates or modifies `CLAUDE.md` while you work. Report which
  skill and what it wrote. Don't commit that file.
- The maintainer's routing table in `CLAUDE.md` has changed since `1984ab7`. The table in step 2
  would silently overwrite their edits.
- You're tempted to keep a `CLAUDE.md` "for safety". The shim is an operator choice for
  environments that can't read `AGENTS.md` (see Maintenance notes), not part of this plan.

## Maintenance notes

- **Strict alternative.** To forbid `CLAUDE.md` outright, change the guard's condition to a
  plain `[ -f CLAUDE.md ]` and delete `test_check_accepts_claude_md_that_imports_agents_md`.
  The cost: gstack features that persist settings only in `CLAUDE.md` would then have nowhere
  to put them, and would re-ask on every run. That covers `/land-and-deploy` deploy config,
  `/health` tool list, and `/ship` coverage thresholds (`## Test Coverage`, which falls back to
  gstack's 60/80 defaults rather than this doctrine's 90%).
- **Environments that can't read AGENTS.md** (Claude Code older than v2.1.277, the `agents-md`
  plugin disabled, or the first session after upgrading from ≤ v2.1.276): a one-line
  `CLAUDE.md` containing `@AGENTS.md` is Anthropic's documented workaround. It passes the guard.
- **gstack limitations that remain** (upstream issues worth filing on gstack, not fixable here):
  - routing injection always targets `CLAUDE.md`;
  - `/ship` step 4 and `/land-and-deploy`'s readiness gate read the test command from
    `CLAUDE.md`/`TESTING.md` only; `/land-and-deploy` falls back to `bun test` if it finds
    nothing, so check what it proposes;
  - `/health`, `/setup-deploy`, `/design-consultation` and `/setup-gbrain` write `CLAUDE.md`
    even when `AGENTS.md` exists.
- The `## Skill routing` match is a plain `grep` on the text, so a later edit that renames the
  heading (even to `## Skill Routing`) re-arms gstack's offer to create `CLAUDE.md`.
  `test_agents_md_keeps_gstack_routing_heading` guards this.
- Plan 005 adds a template-only block to `AGENTS.md` and `TESTING.md`. It must keep the routing
  heading and the `## Commands` section intact.
- Reviewer focus: read the new `AGENTS.md` top to bottom as a first-time agent would, check the
  "what moved where" table, and confirm the guard's messages tell a human exactly what to do.
