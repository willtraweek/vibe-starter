class_name Style
extends RefCounted
## The design tokens DESIGN.md names: every colour and size the game draws with. Other
## scripts and scenes refer to these; scripts/check.d/godot.sh refuses a colour written
## anywhere else under src/.

const BACKGROUND := Color("#14161f")
const PLAYER := Color("#4fd1c5")
const ORB := Color("#f6c35b")
const TEXT := Color("#e8e6e3")
const HUD_FONT_SIZE := 28
const HUD_MARGIN := 24.0
