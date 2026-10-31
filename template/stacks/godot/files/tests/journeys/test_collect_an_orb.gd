extends TestCase
## Journey: the player steers to the orb with the move actions, and the score shows a point.

const MAIN := preload("res://src/scenes/main.tscn")
const ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]


func test_steering_to_the_orb_scores_a_point() -> void:
	var main: Main = add_scene(MAIN)
	for _tick: int in 600:
		if main.score.points > 0:
			break
		_steer(main.orb.position - main.player.position)
		await physics_frames(1)
	assert_eq(main.score_label.text, "Score: 1")


## Holds the arrow keys that point along [param toward], as a player would.
func _steer(toward: Vector2) -> void:
	for action: StringName in ACTIONS:
		release(action)
	if toward.x < -1.0:
		press(&"move_left")
	elif toward.x > 1.0:
		press(&"move_right")
	if toward.y < -1.0:
		press(&"move_up")
	elif toward.y > 1.0:
		press(&"move_down")
