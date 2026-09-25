# CLAUDE.md

Project: {{PROJECT_NAME}}

{{PROJECT_TAGLINE: one or two sentences on what this project is and who it's for.}}

This file tells an agent how to work in this repo. Read it before making changes. Start broad,
narrow down, prefer small surgical edits over sweeping rewrites, and always leave the repo green
(checks and tests both exit 0).

## Required companion instructions

Before starting task work, read `./AGENTS.md` in full. Both files' instructions apply.
Read each file once per task; if you already read the companion, do not follow the reference back again.
Keep shared rules consistent. If the two files conflict, surface the conflict instead of silently choosing one.

## Architecture

{{ARCHITECTURE: describe the high-level design and the main modules / boundaries. Note any
contracts or invariants an agent must preserve.}}

## Key files

{{KEY_FILES: list the load-bearing files and what each is responsible for, one per line. Update
this whenever you add or significantly change a core file.}}

## Commands

This template is stack-agnostic. Fill these in once a stack is chosen, then delete this note.

Keep the check and test commands in sync with `TESTING.md` → Commands.

- Install / bootstrap: `{{INSTALL_CMD}}`
- Dev / run locally: `{{DEV_CMD}}`
- Build: `{{BUILD_CMD}}`
- Lint / typecheck / static checks: `{{CHECK_CMD}}`
- Tests: `{{TEST_CMD}}`

{{OTHER_COMMANDS: any project-specific commands worth knowing — codegen, migrations, deploy, etc.}}

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

## Design

If this project has a UI, see `DESIGN.md` for the design system (aesthetic, typography, color,
spacing, motion) and the visual bar to hold the work to.

## Doctrine

`DOCTRINE.md` holds the cross-project engineering ethos that applies to all of my projects. Read
it once; it's the "why" behind the standards above.

## Skill routing

When the user's request matches an available skill, invoke it before doing the task.
Use the host's supported skill mechanism; if no Skill tool exists, read and follow that skill's SKILL.md.
Load the required repository instructions first. These skills carry specialized workflows
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
