# Testing Doctrine

**Status:** Locked v1 for {{PROJECT_NAME}}. Future revisions append to `## Decisions Log`.

This file is the source of truth for every testing decision in {{PROJECT_NAME}} — what to
test, how hard, and what to leave alone. Any test, coverage gate, or CI change must conform.
Deviations require explicit approval and a new entry in the Decisions Log.

> **Stack-agnostic note.** This template carries the testing *philosophy*. The concrete
> enforcement (coverage tooling, CI config) is per-stack. **Do not scaffold a coverage gate
> until you have chosen a language and test runner** — wiring a 90% gate before there is code
> to cover just breeds empty-shell tests. Pick the stack, then instantiate the gates below.

## Commands

The exact commands for this repo; keep them in sync with `CLAUDE.md` → Commands.
Fill these in as soon as a stack exists so agents and workflow skills can discover them.

- Checks (guards that run before tests): `{{CHECK_CMD}}`
- Tests: `{{TEST_CMD}}`

## Why Tiers, Not One Number

Testing is the most-neglected part of vibe-coded projects, so the reflex is to over-correct
toward a single big coverage number. But blind 100% is wasteful: it spends the most effort on
the code that is hardest to test and least likely to break, and it breeds empty-shell tests
that assert nothing. Allocate by return on investment instead — four tiers, each with a
coverage aim and the technique that earns it. A global **90% floor** (line *and* branch) backs
the whole thing as a fail-closed safety net; the tiers say *where the effort goes* to clear
and exceed it.

## The Four Tiers

### 1. Pure logic & utilities → 100%
Easiest to test, highest ROI, and it breaks silently. Deterministic transforms with no I/O
beyond reading immutable inputs: parsing, validation, ranking/scoring, hashing and chains, ID
minting, any rules engine, canonical render, the error-envelope taxonomy.

`{{TIER1_MODULES: list your pure-logic modules here}}`

Technique: unit tests for the truth table; **property-based** tests for the invariants
(round-trips, determinism, idempotency-key dedup); **golden** fixtures + an expected-output
drift gate for canonical text/JSON.

### 2. API / contract surface → 100%
Every entry point needs request/response tests. Whatever your machine-facing contract is — a
CLI command surface, HTTP routes, an RPC layer — gate it here. Test every command/endpoint's
exit code or status, output shape, and error envelope: the success path and each documented
failure mode.

`{{API_SURFACES: name your contract surface(s) — CLI verbs, routes, etc.}}`

Technique: integration tests that drive the *real* surface against a temp environment — no
endpoint mocked. A broad command/route surface makes 100% a tall, deliberate bar; ratchet
toward it (see Coverage Gates).

### 3. UI components → main components only
Cover the **main** components, not every surface permutation. Technique: golden/surface tests
asserting structure and the design contract — not pixel diffs. Held at the global floor,
**not** 100%: chasing every presentational branch is exactly the waste this doctrine rejects.
(Skip this tier entirely if the project has no UI.)

`{{MAIN_COMPONENTS: list the few components worth covering}}`

### 4. E2E smoke → critical paths only
The journeys that, if broken, make the product worthless. Each gets one named end-to-end test;
do not permute them.

`{{CRITICAL_JOURNEYS: list the 3-6 journeys that must never break}}`

Promote a path to browser-level smoke only when a real regression escapes the integration test.

## What NOT To Test

As important as the tiers. Effort spent here is stolen from the tiers above.

- **Framework internals.** Not the test runner, not the HTTP server plumbing, not the database
  engine, not third-party libraries. Test *our* use of them, never their behavior.
- **What the type system already guarantees.** No tests that a typed struct rejects an unknown
  field or that an enum value is one of its variants. **But do** test the deserialization
  boundary — where untyped input (JSON load, CSV parse, request body) crosses into typed land
  and the type system has no say.
- **Empty-shell mocks.** Mock only at the trust boundary: wall-clock time, randomness, network
  and model calls, auth verification. Everything below that runs for real. A test that mocks
  the domain logic it claims to exercise is worse than no test — it goes green while the code
  rots.
- **Real data and secrets.** Fixtures are synthetic only. Never commit real user, customer, or
  financial data, credentials, or licensed assets — in tests or anywhere.

## Coverage Gates (instantiate per stack)

The pattern, once a stack exists:

- **Global floor: 90%** line *and* branch, fail-closed in CI. The build fails below it.
- **Per-tier gates** layered on top, enforced off the same coverage data. A tier fails if it
  sits below its `minimum` **or** a declared member matched no file in the report — so a
  renamed, un-imported, or typo'd module can't silently drop out and leave its tier reporting
  100%. Keep tier membership and thresholds declarative.
- **Config validated before the suite.** A cheap, coverage-free check that every declared path
  exists and tiers are disjoint, run first in CI, so a broken tier table fails in seconds.
- **Ratchet, never slip.** Each tier's enforced `minimum` initialises from the measured audit
  (so CI is green on landing) and only ever rises. `target` is the doctrine aim — 100% for
  tiers 1–2. Close the gap by writing tests, then raise the floor; never lower it to make a
  change pass.
- Keep a live snapshot (current vs minimum vs target + the per-module backfill work-list) in
  `docs/testing-coverage-audit.md`, regenerated by your coverage tool.

`{{COVERAGE_ENFORCEMENT: wire this into your stack's config + CI once chosen — e.g. a coverage
fail-under flag plus a small tier-checking script. Until then this section is philosophy, not
an active gate.}}`

## Mandatory Named-Test Invariants

Coverage is necessary, not sufficient. Some invariants must each have an explicit, *named* test
— not merely incidental line coverage — because their violation is catastrophic and silent.
List yours:

`{{NAMED_INVARIANTS: list your catastrophic-if-broken invariants, each with a named test. The
*kind* of thing this means: "data is append-only and never silently mutated", "the same input
always produces a byte-identical result", "a locked/sealed record refuses writes", "a
confidence gate fires at the threshold and not below it".}}`

## Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| {{YEAR}} | Founded — tiered doctrine adopted from the vibe-starter template | Blind 100% is wasteful; allocate by ROI. Pure-logic & contract → 100% target, UI → floor, E2E → critical paths. Global 90% line+branch floor, fail-closed. |
