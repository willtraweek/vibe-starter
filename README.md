# {{PROJECT_NAME}}

{{PROJECT_TAGLINE: one-line hook — what this is and who it's for.}}

## What it does

{{WHAT: 3-5 bullets on the core capability.}}

## Why it matters

{{WHY: the pain it removes or the leverage it gives.}}

## Install

```sh
{{INSTALL_CMD}}
```

## Common commands

```sh
{{DEV_CMD}}     # run locally
{{TEST_CMD}}    # run the tests
{{BUILD_CMD}}   # build
```

## Stack

{{STACK: languages, frameworks, key dependencies.}}

## Docs

- `CLAUDE.md` — architecture, commands, conventions, and skill routing; also requires `AGENTS.md`.
- `AGENTS.md` — install, trust boundary, ship gate, and privacy; also requires `CLAUDE.md`.
  Every agent reads both files, regardless of its entry point.
- `DOCTRINE.md` — the cross-project engineering ethos this repo inherits.
- `TESTING.md` — the testing doctrine (tiers, gates, named invariants).
- `ENGINEERING.md` — code-organization standards (file-size smells, the agent token cap, rule-of-three).
- `DESIGN.md` — design system (delete if this project has no UI).
- `MISSION.md` — what this project is and what it guarantees (optional).
- `docs/` — architecture, decisions, guides, and the `.context/` handoff workflow.
