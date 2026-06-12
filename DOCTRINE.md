# Doctrine

The cross-project ethos every one of my repos inherits. These are not {{PROJECT_NAME}}-specific
rules; they are how I build, distilled from prior projects. A fresh agent should read this and
understand the priors before proposing anything. When a local decision conflicts with a
principle here, surface the tension — don't silently override it.

## 1. Completeness — boil the ocean, one lake at a time

When the marginal cost of doing the complete thing is near zero (and with AI it usually is), do
the complete thing. Tests, edge cases, error paths, the full primitive set — not the demo path.
The only thing genuinely out of scope is unrelated work; flag that as separate scope, never as
an excuse for a shortcut. When offered a complete-vs-shortcut choice, default to complete.

## 2. Primitives complete, integrations minimal

For infrastructure meant to live for years, ship the COMPLETE primitive set in v1 even if v1
only exercises a subset. v2+ then becomes pure composition — no schema migrations. The trade is
2-3x the v1 work for ~0x v2 schema work, and it is worth it when downstream integrations are
guaranteed to be plural. Build solid building blocks at the bottom; whatever structure comes
later is then cheap.

## 3. The CLI is the agent contract

For agent-operated systems, a CLI subcommand surface is usually a cleaner contract than
MCP/HTTP/RPC: text-in/text-out is LLM-native, shell-composable, trivially audit-loggable, and it
keeps the implementation language private. Make the command surface *the* machine contract, and
test it as the API (see `TESTING.md`, Tier 2).

## 4. Deterministic in code, AI for the gray space

In products that mix AI with deterministic logic, keep deterministic behavior in code (rules,
settings, validators) and reserve AI for the genuinely ambiguous. The boundary lives at
approval: AI proposes, a human approves, and the approved thing becomes deterministic code.
Operational surfaces hold deterministic behavior; contemplative surfaces hold AI-derived state.

## 5. Estimate in two axes, and convert weeks to hours

When the coding agent works solo (no human in the loop), the unit conversion is "weeks →
hours": a 6-8 week build is 6-8 agent-hours. The calendar is dominated by *my* time (spec
drafting, review loops, real-corpus extraction, device testing) and dogfood windows between
releases, not compute time. Present estimates with both axes labeled: agent-active hours +
my-time hours + calendar months. Total calendar is roughly 1-3x the my-time months; agent time
is nearly negligible.
