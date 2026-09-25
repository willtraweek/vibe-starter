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

### Stack pack follow-ups from the v0.1.0 review

**What:** Decide on the findings the v0.1.0 ship review left open: pin the Python pack's build
backend (`hatchling>=1.27` is resolved fresh on every cold `uv sync`); make the gitleaks action
fail clearly on non-x64 runners; strip `TESTING.md`'s "stack-agnostic note" when a pack is
applied; align the filled `README.md` command block; share one helper for the self-test's
python-pack bootstraps.

**Why:** Each is small, but together they are the rough edges a new `--stack python` project
still shows.

**Context:** Listed in the v0.1.0 PR. The pack's dev tools use `>=` bounds on purpose: a new ruff
or ty release that breaks a fresh project turns the template's required CI red, which is the
warning we want.

**Effort:** S
**Priority:** P3
**Depends on:** None

## Completed
