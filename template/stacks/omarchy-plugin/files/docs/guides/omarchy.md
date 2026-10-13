# Omarchy integration

How {{PROJECT_NAME}} runs inside Omarchy 4's desktop shell, `omarchy-shell` (a Quickshell
process), where the bar, its panels and its menus are all plugins.

## Develop it

1. `./scripts/dev-link.sh` links this checkout to `~/.config/omarchy/plugins/{{PACKAGE_NAME}}`,
   rescans plugins and puts the widget on the right of the bar.
2. After an edit, `./scripts/dev-link.sh --reload`: a linked folder doesn't reload on save
   (one cloned straight into `~/.config/omarchy/plugins/` does).
3. `./scripts/dev-link.sh --unlink` takes it out of the bar and removes the link.

`omarchy dev ui-preview` shows the `qs.Ui` components you can build from, and
`$OMARCHY_PATH/shell/plugins/` holds Omarchy's own plugins to learn from.

## Test it

`./tests/run` runs `Logic.js`'s unit tests under Node, at 100% lines, branches and functions
(every other `.js` or `.mjs` module outside `tests/` too), then `Widget.qml` under Qt 6's
`qmltestrunner`, offscreen, against stand-ins for the `qs.Ui` components it uses
(`tests/qml/imports`). The stand-ins copy only what the widget uses from Omarchy's real
components; when the widget uses more, add it there, following `$OMARCHY_PATH/shell/Ui`.

`./scripts/check.sh` runs Omarchy's own `omarchy plugin validate` rules and its Text-format
scanner, on the files git would commit, at the Omarchy commit pinned in `.omarchy-ref` (fetched
once into `~/.cache/omarchy-kit`). Bump `.omarchy-ref` on purpose, to a released Omarchy.

## Settings

`manifest.json` → `barWidget.defaults` and `barWidget.schema` declare the widget's settings
(types: string, boolean, integer with `min`/`max`, enum, multiselect, path). Omarchy's bar
settings edit them, and the widget reads them with `setting(name, fallback)`.

## Versions

`VERSION` is the version, and gstack `/ship` bumps it. `.gstack/package-json-path` points gstack
at `manifest.json`, so `/ship` writes the same version there, and the guard fails if the two
differ. Omarchy itself never reads the version: `omarchy plugin add` clones your default branch
and `omarchy plugin update` fast-forwards it, so the default branch is the release channel.

## Sharing it

- Anyone can install it: `omarchy plugin add https://github.com/<you>/<repo>.git --enable`.
  Plugins run unsandboxed in the user's desktop process, so keep the code small and readable.
- Before sharing, set `manifest.json`'s `id` to `<your-handle>.{{PACKAGE_NAME}}`: people's
  settings are keyed by it, and the owner prefix avoids collisions.
- The Omarchy plugin directory (plugins.omarchy.org) lists plugins after review. It wants an
  `author` and a `description` in `manifest.json`, a root README and LICENSE, no piped
  `curl | sh` installers, and its reviewers have turned plugins away for a root `AGENTS.md`
  (the repository is installed as the plugin folder, where agent tools could read it) and for
  dev artifacts such as `.gstack/`. This project keeps `AGENTS.md` and `CLAUDE.md` for its own
  agents and `.gstack/package-json-path` for gstack `/ship`; decide before you submit.
