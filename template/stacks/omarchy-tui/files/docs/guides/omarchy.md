# Omarchy integration

How {{PROJECT_NAME}} fits into an Omarchy 4 desktop: Hyprland configured in Lua, terminals
themed by Omarchy, and the launcher on `Super + Space`.

## Run and test

- `cargo run --locked` runs it in this terminal; `q` or `Esc` leaves. It runs in any terminal,
  over SSH and on macOS too.
- `cargo test --locked` drives the real event loop with scripted key presses into ratatui's
  `TestBackend`; no terminal needed.

## Install it for yourself

`./scripts/install.sh` builds a release binary and installs the one cargo reports building
(wherever `CARGO_TARGET_DIR`, `build.target-dir` or `build.target` put it), under `~/.local`
(no root):

- `~/.local/bin/{{PACKAGE_NAME}}`
- `~/.local/share/applications/{{PACKAGE_NAME}}.desktop`, which the Omarchy launcher lists. It
  opens the app in a floating terminal, `xdg-terminal-exec --app-id=TUI.float -e ...`, the
  same kind of entry `omarchy-tui-install` writes: Omarchy's window rules float and centre the
  `TUI.float` class.
- `~/.local/share/icons/hicolor/scalable/apps/{{PACKAGE_NAME}}.svg`

`./scripts/install.sh --uninstall` removes exactly those three files. To install system-wide,
build as yourself, then run `sudo PREFIX=/usr/local ./scripts/install.sh --no-build`.

## Keybinding

Omarchy's Hyprland config is Lua with no drop-in directory, so nothing here edits it for you.
Add a binding by hand, after checking the key is free (`omarchy menu keybindings --print`):

```lua
-- ~/.config/hypr/bindings.lua: in a floating terminal...
o.bind("SUPER + ALT + T", "{{PROJECT_NAME}}", "omarchy-launch-tui --app-id=TUI.float {{PACKAGE_NAME}}")
-- ...or tiled, as the window class org.omarchy.{{PACKAGE_NAME}}:
-- o.bind("SUPER + ALT + T", "{{PROJECT_NAME}}", { tui = "{{PACKAGE_NAME}}" })
```

## Theme and fonts

Nothing to do. On `omarchy theme set`, Omarchy rewrites the terminal's colours and signals it
to reload, so the app changes with the theme as long as it uses only the 16 named colours
(`tests/view.rs` checks every cell). The font is the terminal's.

## Sharing it

As for any Omarchy app: release a tarball per architecture (the stripped binary,
`packaging/app.desktop.in` as `{{PACKAGE_NAME}}.desktop.in`, the icon as
`{{PACKAGE_NAME}}.svg`, `LICENSE` and `README.md`). An AUR `{{PACKAGE_NAME}}-bin` PKGBUILD
installs from those tarballs and renders the entry with `sed -e 's|@BINDIR@|/usr/bin|' -e
"s|@VERSION@|$pkgver|"`; it needs only `glibc` and `xdg-terminal-exec`. Omarchy's own package
repository (`omacom/omarchy-pkgs`) takes pull requests with such a PKGBUILD; that's how Omarchy
preinstalls terminal apps such as cliamp.
