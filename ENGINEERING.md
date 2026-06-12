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
