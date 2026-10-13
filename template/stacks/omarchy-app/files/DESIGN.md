# Design System — {{PROJECT_NAME}}

{{PROJECT_NAME}} is an Omarchy app, so its design system is Omarchy's. It draws with
[gpui-omarchy](https://github.com/huacnlee/gpui-omarchy), which reads the active Omarchy theme
(`~/.local/state/omarchy/current/theme/colors.toml`) and follows `omarchy theme set` live; away
from Omarchy (macOS, CI) it falls back to Tokyo Night. The rules below keep the app inside that
system, and QA holds the app to them.

## Aesthetic
Part of the desktop: flat, square, dense and keyboard-first. In every Omarchy theme, light or
dark, it should look like it shipped with Omarchy.

## Color
Never write a colour. Use the active theme's roles through `cx.omarchy()`: `background`,
`surface`, `inset`, `foreground`, `secondary`, `bright`, `accent`, `on_accent`, `selection`,
`border`, `danger`, `warning` and `success`. Derive a tint from a role (`.opacity(...)`) rather
than inventing a hue. `scripts/check.d/omarchy.sh` refuses GPUI's fixed-colour constructors in
`src/` (`rgb(`, `rgba(`, `hsla(`, `white()` and the other named colours, `opaque_grey()`,
`transparent_*()`, `Rgba::try_from`) and any `linear_gradient(`. It reads text, not types, so a
struct literal such as `Hsla { h, s, l, a }` gets past it; the rule above still holds.

## Typography
The theme's `font` (the system UI face) for text and its `mono_font` (fontconfig's monospace,
which `omarchy font set` changes) for keys and code. Sizes in `rems`, never pixels, so interface
zoom keeps its proportions.

## Spacing & layout
`rems` for padding, gaps and sizes; pixels only for the window's own geometry and one-pixel
borders. Square corners, gpui-omarchy's default. Compose gpui-omarchy's components (`panel`,
`button`, `keycap`, `focus_scope`, ...) before styling raw `div`s.

## Motion
None by default. Anything that animates must not delay input and must also work from the
keyboard alone.

## Anti-slop rules
- No colour literals, gradients, shadows, glass or rounded pills: Omarchy surfaces are flat.
- Every action has a key, and the window shows it (`keycap`).
- `ButtonVariant::Primary` only for what Enter does; ask for confirmation only before what can't
  be undone.
- Both appearances stay tested: `tests/window.rs` draws Tokyo Night (dark) and Flexoki Light.
