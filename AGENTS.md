# Agents working on {{PROJECT_NAME}}

This is your install + operating protocol. Claude Code reads `./CLAUDE.md` automatically.
Everyone else (Codex, Cursor, OpenClaw, Aider, Continue, or an LLM fetching via URL): start
here.

## Install

1. Clone: `{{CLONE_CMD: git clone <repo-url> && cd <dir>}}`
2. Install deps: `{{INSTALL_CMD: e.g. bun install / uv sync / cargo build}}`
3. Configure: `{{CONFIG_STEPS: env vars, API keys, local state — or "none"}}`

## Read this order

1. `./AGENTS.md` (this file) — install + operating protocol.
2. `./CLAUDE.md` — architecture reference, key files, trust boundaries, conventions.
3. `./DOCTRINE.md` — the cross-project engineering ethos this repo inherits.
4. `./TESTING.md` and `./ENGINEERING.md` — how we test and how we organize code.

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

## Before shipping

`{{SHIP_GATE: the one command that runs the full local gate — checks + tests, e.g.
./scripts/check.sh && <test cmd>. Ship via the /ship skill, not by hand.}}`

## Privacy

Never commit real names of people, companies, or funds, real user data, or secrets into public
artifacts. Use generic placeholders (`alice-example`, `acme-example`, `fund-a`).
