# Omarchy integration

How {{PROJECT_NAME}} fits into an Omarchy 4 desktop: Hyprland configured in Lua, the Quickshell
desktop shell, and the active theme in `~/.local/state/omarchy/current`.

## Run and test

- `cargo run --locked` opens the window. On Omarchy, Rust comes from rustup; GPUI links against
  fontconfig and libxkbcommon, which Omarchy already has. On macOS it builds and runs too, in
  Tokyo Night.
- `cargo test --locked` needs no display: GPUI's test platform draws frames headlessly.

## Install it for yourself

`./scripts/install.sh` builds a release binary and installs the one cargo reports building
(wherever `CARGO_TARGET_DIR`, `build.target-dir` or `build.target` put it), under `~/.local`
(no root):

- `~/.local/bin/{{PACKAGE_NAME}}`
- `~/.local/share/applications/{{PACKAGE_NAME}}.desktop`, which the Omarchy launcher
  (`Super + Space`) lists
- `~/.local/share/icons/hicolor/scalable/apps/{{PACKAGE_NAME}}.svg`

`./scripts/install.sh --uninstall` removes exactly those three files. `PREFIX`, an absolute path,
moves all three; nothing else in the environment does. To install system-wide, build as
yourself, then run `sudo PREFIX=/usr/local ./scripts/install.sh --no-build`.
`--no-build` takes `target/release/{{PACKAGE_NAME}}` (or the one under `$CARGO_TARGET_DIR`) and
refuses it unless its `--version` names this `VERSION`. That is all it can check: an older build
of the same version still gets through, while the default build installs exactly what cargo
just built.

## Keybinding and window rule

Omarchy's Hyprland config is Lua with no drop-in directory, so nothing here edits it for you.
Add what you want by hand, after checking the key is free (`omarchy menu keybindings --print`):

```lua
-- ~/.config/hypr/bindings.lua
o.bind("SUPER + ALT + D", "{{PROJECT_NAME}}", { launch = "{{PACKAGE_NAME}}" })

-- ~/.config/hypr/hyprland.lua, below the require(...) lines: float it, centred
o.window("{{PACKAGE_NAME}}", { tag = "+floating-window" })
```

The window class is `{{PACKAGE_NAME}}`: `src/lib.rs` sets it as the Wayland app id, and the
desktop entry's `StartupWMClass` matches it (`tests/desktop_entry.rs` keeps them in step).
Renaming the app changes the class, so update these lines too.

## Theme and fonts

Nothing to do. gpui-omarchy re-reads the theme whenever `omarchy theme set` swaps it, and keys
use the monospace font `omarchy font set` chose. Try a light theme (`catppuccin-latte`) now and
then; `tests/window.rs` draws both appearances.

## Sharing it

Omarchy users install apps as packages. disktree shows the path:

1. Release a tarball per architecture, `{{PACKAGE_NAME}}-<version>-<arch>-linux.tar.gz`, holding
   the stripped binary, `packaging/app.desktop.in` as `{{PACKAGE_NAME}}.desktop.in`, the icon as
   `{{PACKAGE_NAME}}.svg`, `LICENSE` and `README.md`. Build Linux releases on the oldest Ubuntu
   runner you support: its glibc is the floor.
2. An AUR `{{PACKAGE_NAME}}-bin` PKGBUILD installs from those tarballs, renders the entry with
   `sed -e 's|@BINDIR@|/usr/bin|' -e "s|@VERSION@|$pkgver|"`, and depends on `libxcb`,
   `libxkbcommon`, `libxkbcommon-x11`, `wayland`, `libglvnd` and `vulkan-icd-loader`. Add
   `options=('!lto')`: makepkg's LTO flags break Rust's linker.
3. Omarchy's own package repository (`omacom/omarchy-pkgs`) takes pull requests with such a
   PKGBUILD plus a `.omarchy/package.json` that follows your GitHub releases.
