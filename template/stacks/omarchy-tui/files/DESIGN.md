# Design System — {{PROJECT_NAME}}

{{PROJECT_NAME}} is a terminal app for Omarchy, so its colours and font are the terminal's, and
Omarchy sets both: every `omarchy theme set` rewrites the terminal's 16 ANSI colours and asks
the terminal to reload, and `omarchy font set` changes its font. The rules below keep the app
inside that system, and QA holds the app to them.

## Aesthetic
A keyboard tool that looks at home in an Omarchy terminal: plain text, box-drawing borders and
one accent colour.

## Color
Only the terminal's own colours: the 16 named ANSI colours (`Color::Blue`, `Color::Red`, ...)
and `Color::Reset` for its default foreground and background. Never `Color::Rgb`,
`Color::Indexed` or a colour made from a number or a string (`Color::from_u32`,
`Color::from([r, g, b])`, a parsed `"#…"`): they ignore the theme, and
`scripts/check.d/omarchy.sh` refuses them. It reads text, not types, so `(r, g, b).into()` gets
past it; the rule still holds. Pick
one named colour as the accent (the starter uses blue), red for danger, yellow for warnings and
green for success.

## Typography
The terminal's font, which `omarchy font set` chooses. Bold for keys and for the one thing that
matters on screen; no other emphasis.

## Spacing & layout
Content centred in bordered blocks, with one blank line between groups. A small terminal must
still draw without panicking; draw what fits (`tests/view.rs` draws an 8×2 terminal).

## Motion
None. Redraw on input only.

## Anti-slop rules
- No RGB or 256-colour literals.
- Every action has a key, and the screen shows it.
- `q` and `Esc` leave. Ask for confirmation only before what can't be undone.
