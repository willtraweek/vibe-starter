# Design System — {{PROJECT_NAME}}

{{PROJECT_NAME}} is a Godot game. Every colour and size it draws with is a token in
`src/style.gd` (`Style.PLAYER`, `Style.HUD_FONT_SIZE`, ...), so a new palette is one edit, and
QA holds the game to the rules below. The tokens are the starter's: replace them with the
game's own once it has a look, and keep them in that one file.

## Aesthetic
A dark field with two bright, distinct shapes: the player and the thing to collect. Flat
colour, no textures, nothing competing with them for the eye.

## Color
| Token | Hex | Use |
|---|---|---|
| `Style.BACKGROUND` | `#14161f` | the field, behind everything |
| `Style.PLAYER` | `#4fd1c5` | the player's body |
| `Style.ORB` | `#f6c35b` | the orb to collect |
| `Style.TEXT` | `#e8e6e3` | the score and any other HUD text |

Each of the other three is above 7:1 against the background. A colour written anywhere else
under `src/` fails `scripts/check.d/godot.sh`: `Color(...)`, `Color8(...)`, `Color.html(...)`,
a named `Color.RED`, or a `Color(...)` in a scene. Add a token instead. The check reads text,
not types, so a colour built another way gets past it; the rule still holds. A theme resource
(`.tres`) may hold colours, taken from this table.

## Typography
Godot's built-in font, at `Style.HUD_FONT_SIZE` (28 px on the 1280×720 field) for the HUD.
Numbers are plain digits: "Score: 3".

## Spacing & layout
The field is 1280×720 pixels (`project.godot`). Other window shapes letterbox it
(`canvas_items` stretch, `keep` aspect), so positions are field pixels everywhere. The HUD sits
`Style.HUD_MARGIN` in from the top-left corner; keep anything a player must see out of that
margin at every edge.

## Motion
The player moves at `Main.speed` pixels a second, in any of eight directions; nothing else
animates. Nothing flashes more than three times a second.

## Anti-slop rules
- No colour or size literals outside `src/style.gd`.
- Every action has a keyboard and a gamepad binding in the input map (`project.godot`,
  `[input]`); no script reads a key directly.
- The game's icon (`icon.svg`) is its own, never Godot's logo.
