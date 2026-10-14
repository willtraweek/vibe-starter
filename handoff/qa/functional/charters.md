# /review (pass 2) functional charters

Candidate: HEAD 6e0b92c (tree 65cce8b), clean worktree; base origin/master 9959522.
Surface: functional CLI (./bootstrap with the new packs; generated-project scripts). No browser, no installs, no network, no real user caches.
Isolation: every probe works in a fresh `mktemp -d` copy of `git ls-files` output with a sandboxed HOME, git-local env vars unset, and stub `cargo`/`git`/`rm` binaries at the network boundary; nothing in the checkout or the user's caches is written.
Permitted writes: this report directory and the probes' own temp dirs.
Exit: 300 s or 12 probes; exact replay of any failure.

1. Success: `bootstrap --stack omarchy-tui` copies the `_rust-gates` partial pack first and the pack's own files, exit 0, scripts executable. Source: bootstrap:225-240, 329-338; TEMPLATE.md "includes".
2. Riskiest changed failure: two cold `omarchy-kit` runs in parallel must never delete the cache path already returned to the first caller. Source: omarchy-kit:16-31 ("checks that start together never delete or half-read each other's clone"). Probe: the deterministic barrier harness from the prior review (.context/integration/native-adversarial-race.py), stub git/rm only.
3. Partial packs cannot be chosen: `bootstrap --stack _rust-gates` exits 2 with no writes. Source: TEMPLATE.md "never offered as a stack".
4. Foldkit relay guard (P1, #20 item 22): a relay port passed through an alias must fail the guard. Source: vite.config.ts comment + check.d/foldkit.sh:43-48. Probe: the current guard fragment against the saved alias fixture.
