# Engineering Standards

**Status:** Locked v1 for {{PROJECT_NAME}}. Future revisions append to `## Decisions Log`.

This file is the source of truth for code-organization decisions in {{PROJECT_NAME}} — how
large a module gets before it splits, and when shared logic earns its own home. It sits
alongside `TESTING.md` (how we test) and, if the project has a UI, `DESIGN.md` (how surfaces
look). Any deviation requires explicit approval and a new entry in the Decisions Log.

## Large File Splitting

Treat line count as a smell, not a hard limit:

- **~300 lines — worth a look.** Roughly the point past which a file can no longer be
  understood without heavy scrolling.
- **~500 lines — probably needs splitting.** Usually a sign of mixed concerns that belong in
  separate modules.

These numbers are prompts to *look*, not thresholds that fire on their own.

**The reverse constraint outranks the number.** A cohesive module is never forced apart to
satisfy a line count. Shattering one coherent 300-line module into five fragments that all
import each other makes the code *harder* to follow, not easier. Split along seams of
responsibility, never mid-concern.

Line count is not what the pre-commit check measures. The hard gate is the token cap below.

## Agent token cap

A staged file over **5,000 tokens** fails `scripts/check.sh`. Tokens are the staged blob's
bytes divided by 4, rounding down. 20,000 through 20,003 bytes are still 5,000 tokens and
pass; 20,004 bytes is 5,001 and fails. The worktree copy does not count, and neither does
a deletion.

The cap is about what an agent can hold and edit. It is a hard gate. The line-count smells
above stay advisory, and the cohesion rule still outranks a tidy number: split on a seam of
responsibility, never mid-concern, and do not invent a grab-bag module to get under the cap.
The check prints those steps when it fails.

These paths are not counted. An agent did not author them, and splitting them does not help:

- Lockfiles, by name: `pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `npm-shrinkwrap.json`,
  `go.sum`, `Package.resolved`, `packages.lock.json`, `gradle.lockfile`, and any `*.lock` or
  `*.lockb` file (`Cargo.lock`, `uv.lock`, `bun.lock`, and the rest).
- Generated code: a `generated/`, `codegen/`, or `__generated__/` directory, and names such as
  `*.generated.ts`, `*.gen.go`, `*.pb.go`, `*.pb.ts`, `*_pb2.py`, `*.sql.go`, `*.min.js`,
  `*.min.css`.
- Vendored trees: `vendor/`, `third_party/`, `third-party/`.

A gitlink (a submodule entry) has no blob and is not counted. Every other staged file is,
including assets, because the unit is bytes.

The check looks at the index the commit would record. A normal `git add` uses the
default index. `git commit -a` and `git commit -- <path>` put that commit in a
temporary index, and the cap reads that index too. A clean tree, including CI on a
fresh checkout, has nothing staged, so the cap does not re-litigate history. It fires
when a commit is about to record an oversized file. Link the guard in so `git commit`
runs it:

```bash
ln -s ../../scripts/check.sh .git/hooks/pre-commit
```

That link is from `.git/hooks/` in a normal clone. Linked worktrees share one hooks
directory; `scripts/check.sh` already switches to the worktree being committed.

## Shared Code Extraction

DRY is well known; knowing *when* to apply it is the hard part.

**Extract only when the same logic appears three or more times.** Two occurrences may be
coincidence — abstracting them prematurely couples two call sites that were free to diverge,
and the abstraction is usually wrong because it was drawn from only two examples. Wait for the
third.

**Never create a catch-all `utils` module.** A grab-bag utility module owns no single concept,
becomes an import magnet, and turns into a dependency hub everything reaches into. Organize
shared code by domain instead — put it in the module that owns the concept — and keep each
module's responsibility nameable in one sentence.

## Decisions Log

- **{{YEAR}} — Founded.** Adopted from the vibe-starter template: the file-size smell
  thresholds (~300 worth a look, ~500 probably split) with the cohesion override, and the
  rule-of-three for shared-code extraction with the no-catch-all-utils rule. Organize shared
  code by domain.
- **{{YEAR}} — Agent token cap.** Adopted from the vibe-starter template: `scripts/check.sh`
  rejects a staged file over 5,000 tokens (bytes/4, rounding down), except lockfiles,
  generated code, vendored trees, and gitlinks. Line-count smells stay advisory; the cohesion
  rule still outranks the cap.
