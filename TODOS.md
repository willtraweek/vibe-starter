# TODOS

Backlog for the vibe-starter template itself, in gstack's TODOS format. Implementation plans for
selected items live in `plans/`. New projects start from their own blank backlog
(`template/skeleton/TODOS.md`).

## Template

### Offer projects a doctrine update path

**What:** A script that diffs a project's doctrine files against the template version recorded
in its `.bootstrapped`, as a report, not an automatic merge.

**Why:** Projects made from an older template never receive doctrine improvements.

**Context:** `.bootstrapped` records the template version since plan 005. The design doc
deferred an automatic generator ("Approach C").

**Effort:** M
**Priority:** P2
**Depends on:** None

### Opt-in stack packs (Python, Rust)

**What:** `bootstrap --stack python|rust` overlays that set up the per-stack gates `TESTING.md`
describes (coverage floor, tier checker, CI steps, `.gitignore` section).

**Why:** Every project repeats the same four manual checklist steps.

**Context:** Planned in `plans/006-stack-packs-python.md` and `plans/007-stack-pack-rust.md`.
Must stay opt-in to keep the spine stack-agnostic.

**Effort:** L
**Priority:** P2
**Depends on:** None

### Make the markdown pass editorconfig-checker

**What:** Run editorconfig-checker (v4.0.2) against the template and fix what it flags: likely
3-space list indentation in `TEMPLATE.md`. Then make it required in CI like gitleaks.

**Why:** `scripts/check.sh` runs it whenever it is installed, so it must pass on a clean template.

**Context:** Finding #8 in `plans/README.md`.

**Effort:** S
**Priority:** P3
**Depends on:** None

## Completed
