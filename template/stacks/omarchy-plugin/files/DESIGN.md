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
Every `Text` whose text isn't a literal sets `textFormat: Text.PlainText`: Omarchy's scanner
(run by `scripts/check.d/omarchy-plugin.sh`) and the plugin directory's reviewers require it.

## Spacing & layout
`Style.space(px)` and `Style.spacing.*`, which scale with `omarchy display text size`; bar
geometry from `Style.bar.*`. Work in both bar orientations (`vertical`).

## Motion
The shell's own; add none.

## Anti-slop rules
- No hex colours or fixed pixel sizes in QML: tokens only.
- Logic lives in `Logic.js`, plain JavaScript at 100% coverage, not in QML handlers.
- Never build a shell command from a setting: run argv lists (`Util.execArgv`), never `sh -c`.
