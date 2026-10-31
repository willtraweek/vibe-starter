class_name Main
extends Node2D
## The game: the move_* actions steer the player, touching the orb scores a point and moves
## the orb, and the score shows in the corner. The rules live in src/logic.

## Pixels a second.
@export var speed := 360.0
## Seeds where the orbs appear: the same seed places the same orbs.
@export var spawn_seed := 7

var arena: Arena
var score := Score.new()
var _spawner: OrbSpawner

@onready var player: Player = $Player
@onready var orb: Orb = $Orb
@onready var score_label: Label = $Hud/ScoreLabel


func _ready() -> void:
	RenderingServer.set_default_clear_color(Style.BACKGROUND)
	var width: int = ProjectSettings.get_setting("display/window/size/viewport_width")
	var height: int = ProjectSettings.get_setting("display/window/size/viewport_height")
	arena = Arena.new(Vector2(width, height))
	_spawner = OrbSpawner.new(spawn_seed)
	score_label.position = Vector2(Style.HUD_MARGIN, Style.HUD_MARGIN)
	score_label.add_theme_color_override("font_color", Style.TEXT)
	score_label.add_theme_font_size_override("font_size", Style.HUD_FONT_SIZE)
	score.changed.connect(_show_score)
	player.position = arena.center()
	orb.position = _spawner.next_position(arena, player.position)
	_show_score(score.points)


func _physics_process(delta: float) -> void:
	step(Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down"), delta)


## One tick of play: moves the player along [param direction] for [param delta] seconds,
## then collects the orb if the player touches it.
func step(direction: Vector2, delta: float) -> void:
	player.position = arena.keep_inside(player.position + direction * speed * delta, Player.RADIUS)
	if arena.touching(player.position, orb.position, Player.RADIUS + Orb.RADIUS):
		score.collect()
		orb.position = _spawner.next_position(arena, player.position)


func _show_score(points: int) -> void:
	score_label.text = "Score: %d" % points
