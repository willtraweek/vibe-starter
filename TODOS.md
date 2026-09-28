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
Must stay opt-in to keep the spine stack-agnostic. Plans 008–010 add three Omarchy packs (an
app, a terminal app and a shell plugin) on the same mechanism.

**Effort:** L
**Priority:** P2
**Depends on:** None

### Omarchy stack pack follow-ups from the plans' review

**What:** Four gaps the pre-landing review of plans 008–010 left open, each done when its check
holds:
1. Decide the Rust packs' lockfile policy: ship a reviewed `Cargo.lock` per pack (its root
   entry renamed to the project's package at bootstrap, re-resolved with `cargo update
   --workspace`, refreshed with each pin bump) or record why they resolve fresh like the Python
   pack. Done when `TEMPLATE.md`
   states the policy (and, if adopted, the heavy tests build `--locked` against it) and the heavy
   job's cache key changes when the dependency set does.
2. Test the rest of what generated Rust projects promise: their `ci.yml` steps, a `--release`
   build (which `install.sh` needs), doctests, and GPUI window tests that neither read nor watch
   the developer's `$HOME` theme. Done when a test exercises each.
3. Harden `install.sh`: find the binary through cargo's configured target dir, stop reading
   generic `APPDIR`/`BINDIR`/`ICONDIR` from the environment (AppImage exports `APPDIR`), never
   silently replace an unrelated `~/.local/bin/<name>`, and clear `CDPATH` before `cd` there and
   in the Python pack's scripts. Done when a test covers each.
4. Make `omarchy-kit` require `.omarchy-ref` to be a commit in an upstream Omarchy release, not
   just any SHA the upstream URL serves (a fork's commit can be fetched that way). Done when it
   refuses such a commit and a test covers it.

**Why:** Each is a real gap in a generated project, but none blocks executing the plans.

**Context:** Found by gstack `/ship`'s review of the Omarchy plans (see `plans/README.md` →
"Pre-landing review, 2026-09-26"). The Python pack resolves its tools fresh on purpose (see the
v0.1.0 follow-ups below), so item 1 starts with that policy call. Items 1–3 touch plans 008 and
009, item 4 plan 010.

**Effort:** M
**Priority:** P2
**Depends on:** Plans 008–010 landing

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
