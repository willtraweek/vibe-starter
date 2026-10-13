# Design System — {{PROJECT_NAME}}

{{PROJECT_NAME}} is an Omarchy shell plugin: it draws inside `omarchy-shell`, next to Omarchy's
own widgets, so its design system is the shell's. Build from `qs.Ui` components (`BarWidget`,
`WidgetButton`, `Panel`, `KeyboardPanel`, ...) and bind to `qs.Commons` tokens; then
`omarchy theme set` and `omarchy font set` restyle it with the rest of the desktop.

## Aesthetic
Indistinguishable from a built-in widget: the same size, font and colours as its neighbours.

## Color
Bind to the bar's colours or to `Color.*` from `qs.Commons` (`foreground`, `background`,
`accent`, `urgent`, `muted`, and surfaces such as `Color.popups.*`). Bind, never copy into a
property of your own: the shell replaces them on every theme change. No hex colours in QML.

## Typography
`Style.font.*` (`family`, `body`, `caption`, `title`, ...), which follow `omarchy font set`.
Every `Text` whose text isn't a literal sets `textFormat: Text.PlainText`, and so does every type
derived from `Text`, such as QtQuick.Controls' `Label`: left at `AutoText`, it renders markup that
comes from outside the shell. `scripts/check.d/omarchy-plugin.sh` runs Omarchy's scanner, which
the plugin directory's reviewers also apply and which requires a `textFormat` on such a `Text`,
and holds each such `Label` to `Text.PlainText`.

## Spacing & layout
`Style.space(px)` and `Style.spacing.*`, which scale with `omarchy display text size`; bar
geometry from `Style.bar.*`. Work in both bar orientations (`vertical`): a vertical bar fixes a
widget's width to its `barSize`, so show less there (the starter shows only its count).

## Motion
The shell's own; add none.

## Anti-slop rules
- No hex colours or fixed pixel sizes in QML: tokens only. In QML outside `tests/`,
  `scripts/check.d/omarchy-plugin.sh` refuses a hex colour string (`"#…"`), `Qt.rgba()`,
  `Qt.rgb()`, `Qt.hsla()` and `Qt.hsva()`, any `Gradient`, and a whole number other than 0 and
  1 bound on its own to `width`, `height`, `implicitWidth`, `implicitHeight`, `pixelSize`,
  `pointSize`, `spacing`, `margins`, a `*Margin` or `radius`. It reads text, not types, so
  `width: 2 * 12` gets past it; the rule still holds.
- Logic lives in `Logic.js`, plain JavaScript at 100% coverage, not in QML handlers.
- Never build a shell command from a setting: run argv lists (`Util.execArgv`), never `sh -c`.
