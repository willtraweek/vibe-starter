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

### Omarchy stack pack follow-ups from the plans' review

**What:** Two gaps the pre-landing review of plans 008–010 left open, each done when its check
holds:
1. Decide the Rust packs' lockfile policy: ship a reviewed `Cargo.lock` per pack (its root
   entry renamed to the project's package at bootstrap, re-resolved with `cargo update
   --workspace`, refreshed with each pin bump) or record why they resolve fresh like the Python
   pack. Done when `TEMPLATE.md` states the policy (and, if adopted, the heavy tests build
   `--locked` against it) and the heavy job's cache key changes when the dependency set does.
   The five-pack review (PR #22) found both halves biting: omarchy-app and omarchy-tui resolve
   about 860 crates fresh at bootstrap with no reviewed lockfile, release-age gate or
   cargo-deny, and the heavy job's cache, keyed on the packs' `Cargo.toml` files only, never
   re-saves as those crates drift.
2. Test the rest of what generated Rust projects promise: their `ci.yml` steps, a `--release`
   build (which `install.sh` needs), doctests, and GPUI window tests that neither read nor watch
   the developer's `$HOME` theme. Done when a test exercises each.

**Why:** Each is a real gap in a generated project, but none blocks the packs.

**Context:** Found by gstack `/ship`'s review of the Omarchy plans (see `plans/README.md` →
"Pre-landing review, 2026-09-26"). The Python pack resolves its tools fresh on purpose (see the
v0.1.0 follow-ups below), so item 1 starts with that policy call. The other two items of that
review (installer hardening and the release-only `.omarchy-ref`) landed in PR #22.

**Effort:** M
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

### A second JavaScript pack: React 19.3 + TanStack Router on Effect v4

**What:** A `react` stack pack beside `foldkit`, for browser apps that want React's component
ecosystem and a router: React 19.3 and TanStack Router for the UI, an Effect v4 data and state
layer (Atom through `@effect/atom-react`), Vitest Browser Mode on Playwright, and the foldkit
pack's pins, shipped lockfile, tier checker and CI shape.

**Why:** Packs are chosen by what the app does. foldkit suits apps whose state fits one
Elm-style Model; many browser apps want React components and libraries instead.

**Context:** Prototyped on 2026-09-25 while choosing the first JavaScript pack (every gate
passed; Effect + Atom added about 51 kB gzip over plain React + Router). Lessons from that
prototype, on Effect 4.0.0-rc.117, to re-check on the stable release: a component test that
seeds the result atom through `RegistryProvider` still runs the live layer and makes a real
`fetch` (seeded values count as stale), so seed the Atom runtime's layer with the service over a
fake `HttpClient`; `@effect/atom-react` peered on `scheduler <0.28.0` while React 19.3 needs
`^0.28.0`, so two schedulers got bundled; Vitest Browser Mode needs `optimizeDeps.include` for
React on a cold cache.

**Effort:** L
**Priority:** P3
**Depends on:** plan 011 (its pnpm, lockfile and tier-checker patterns; extract a shared
partial pack when a third JavaScript pack appears)

### Foldkit starter: plain-language status copy

**What:** Map the status component's failure reasons to plain language ("Couldn't reach the
server", "The server answered 503") and show `checkedAt` as a localized `<time>`, keeping the raw
detail for logs.

**Why:** The starter prints reason codes, library error messages and ISO timestamps as its copy,
and agents copy the starter.

**Context:** Found by the design review of PR #22 and deferred there as copy taste rather than a
defect. Update the copy pinned in `scene.test.ts` and `e2e/home.spec.ts` with it.

**Effort:** S
**Priority:** P3
**Depends on:** None

### omarchy-plugin: one validator for BUILD_CMD and the gate

**What:** `BUILD_CMD` is `omarchy plugin validate .`: the desktop's installed, unpinned Omarchy
on the raw working tree. The gate runs Omarchy's validator at `.omarchy-ref` on what git would
commit. Make both run the pinned one on the same files, or document `BUILD_CMD` as the
live-desktop check.

**Why:** The two can disagree, and `BUILD_CMD` doesn't exist off an Omarchy desktop.

**Context:** A low-confidence note from the PR #22 review; not reproduced (no Omarchy desktop
here).

**Effort:** S
**Priority:** P3
**Depends on:** None

### godot pack follow-ups

**What:** Three things the first version of the `godot` pack (plan 012) leaves out, each done
when its check holds:
1. Native exports in CI: install Godot's export templates (about 1.3 GB, pinned by SHA-512 like
   the engine, and cached) and export one platform's executable. Done when a heavy test runs the
   exported binary.
2. Coverage of lambdas passed in a call's parentheses and of class-level initializers. Done when
   the coverage fixture in `test_heavy_stack_godot_coverage_counts_lines_and_branches` measures
   both.
3. A C# variant (Godot's .NET build): a separate pack, chosen when a game needs .NET libraries.

**Why:** Each is a gap a game project may hit, but none blocks the pack.

**Context:** See plan 012's "Out of scope". The kit's pins and the starter's generated files are
maintained as its "Maintenance" section says.

**Effort:** M
**Priority:** P3
**Depends on:** None

## Completed

### Opt-in stack packs (Python, Rust)

**What:** `bootstrap --stack python|rust` overlays that set up the per-stack gates `TESTING.md`
describes (coverage floor, tier checker, CI steps, `.gitignore` section).

**Completed:** Python in v0.1.0 (plan 006); Rust in v0.3.0 (plan 007), with the omarchy-app,
omarchy-tui, omarchy-plugin and foldkit packs (plans 008–011, PR #22).

### Omarchy installer hardening and a release-only `.omarchy-ref`

**What:** Items 3 and 4 of the Omarchy plans' review follow-ups: `install.sh` installs exactly
what cargo built and refuses a stale or unrelated binary, reads only `PREFIX`, and clears
`CDPATH`; `omarchy-kit` accepts only a commit inside an Omarchy release.

**Completed:** v0.3.0 (PR #22).

