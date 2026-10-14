# Agents working on {{PROJECT_NAME}}

<!-- template-only:start -->
> **You are in the vibe-starter template itself, not in a project made from it.** Everything
> outside the template-only blocks is the skeleton each new project starts from, so the
> `{{...}}` placeholders are intentional: never fill them in or "fix" them here. Verify every
> change with `./scripts/template-selftest.sh`. The root `VERSION`, `CHANGELOG.md` and
> `TODOS.md` belong to the template (gstack `/ship` maintains them); new projects get the
> copies in `template/skeleton/`. Maintainer guide: `TEMPLATE.md`. `./bootstrap` removes this
> block.
<!-- template-only:end -->

This is the install and operating protocol for every coding agent in this repo.
AGENTS.md and CLAUDE.md are companion instruction files; read both regardless of where your host starts.

## Required companion instructions

Before starting task work, read `./CLAUDE.md` in full. Both files' instructions apply.
Read each file once per task; if you already read the companion, do not follow the reference back again.
Keep shared rules consistent. If the two files conflict, surface the conflict instead of silently choosing one.

## Install

1. Clone: `{{CLONE_CMD: git clone <repo-url> && cd <dir>}}`
2. Install deps: `{{INSTALL_CMD: e.g. bun install / uv sync / cargo build}}`
3. Configure: `{{CONFIG_STEPS: env vars, API keys, local state — or "none"}}`
4. GitHub issue intake: follow [Filing issues](docs/guides/filing-issues.md). Inspect the
   repository's existing labels, show the target repository and missing type labels, and
   ask the user to confirm before creating any. Preserve existing labels.

## Read this order

1. `./AGENTS.md` (this file) — install + operating protocol.
2. `./CLAUDE.md` — architecture, key files, commands, conventions, skill routing.
3. `./DOCTRINE.md` — the cross-project engineering ethos this repo inherits.
4. `./TESTING.md` and `./ENGINEERING.md` — how we test and how we organize code.
5. `./docs/architecture.md` — the detailed map to read before changing anything load-bearing.

## Trust boundary (critical)

`{{TRUST_BOUNDARY: if this system has trusted (local CLI) vs untrusted (agent / remote)
callers, describe the distinction and which operations tighten under the untrusted path. If
there is no such boundary yet, say so — and add one before exposing anything to remote agents.}}`

## How to work here

- Keep changes small and reviewable; avoid refactors unless asked. Preserve contracts and
  public surfaces (APIs, on-disk formats, config keys, CLI verbs).
- Run the checks then the tests before marking anything done; both must exit 0. See
  `TESTING.md`.
- If the project has a UI, align with `DESIGN.md` tokens — no hardcoded colors, fonts, or
  spacing.
- When filing GitHub issues, follow [Filing issues](docs/guides/filing-issues.md). The same
  category and content rules apply to browser forms, skills, and CLI/API submissions.

## Before shipping

`{{SHIP_GATE: the one command that runs the full local gate — checks + tests, e.g.
./scripts/check.sh && <test cmd>. Ship via the /ship skill, not by hand.}}`

## Privacy

Never commit real names of people, companies, or funds, real user data, or secrets into public
artifacts. Use generic placeholders (`alice-example`, `acme-example`, `fund-a`).
