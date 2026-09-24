# Changelog

All notable changes to {{PROJECT_NAME}} are recorded here. Newest first, semver sections.

## [0.0.2] - 2026-09-24

### Added
- `./bootstrap` names the project after its `origin` repo (else the folder), so agent runs and
  Conductor workspaces no longer produce projects named after a workspace codename.
- `./bootstrap` refuses to run (exit 3) inside the vibe-starter template itself, whatever the
  case or shape of its origin URL, and in a folder whose `.git` git can't read. The message
  shows how to point `origin` at your own repo; `--force` overrides, with a warning if origin
  still points at the template.
- The first-run checklist now lists `docs/architecture.md`.

### Changed
- Bad arguments fail loudly with exit 2: `--name` with no value, an empty name, or a flag
  passed as the name. Names must start with a letter or digit and use plain ASCII on every
  platform, and a rejected default says where it came from and how to override it.

### Fixed
- Worktrees and submodules (where `.git` is a file) count as existing repositories: no stray
  `git init` or false "fresh repository" message, and an existing `.git` is never
  re-initialized.
- A copy nested inside another repo uses its own folder name instead of the outer repo's.
- The origin URL, which can carry a token, is never printed.
- Template maintenance: 23 new self-tests (34 in total) cover these paths, and the plan index
  marks plan 003 done.

## [0.0.1] - 2026-09-23

### Added
- Seven ordered implementation plans for template self-tests, safer checks and bootstrap,
  one shared agent instruction file, template maintenance, and optional Python and Rust stacks.
- A plan index with dependencies, verification evidence, and separate PR execution guidance.

## [Unreleased]

### Added
- Initial scaffold from the vibe-starter template.

<!--
## [0.1.0] - {{YEAR}}-MM-DD
### Added
### Changed
### Fixed
-->
