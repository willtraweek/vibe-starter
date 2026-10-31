extends TestCase

const MAIN := preload("res://src/scenes/main.tscn")

var main: Main


func before_each() -> void:
	main = add_scene(MAIN)


func test_the_round_starts_with_the_player_centered_and_no_score() -> void:
	assert_eq(main.player.position, main.arena.center())
	assert_eq(main.score_label.text, "Score: 0")
	assert_true(main.orb.position.distance_to(main.player.position) >= OrbSpawner.MIN_DISTANCE)


func test_a_step_moves_the_player_at_its_speed() -> void:
	main.step(Vector2.RIGHT, 0.5)
	assert_almost_eq(main.player.position, main.arena.center() + Vector2(main.speed * 0.5, 0))


func test_touching_the_orb_scores_a_point_and_moves_the_orb() -> void:
	var first_orb := main.orb.position
	main.player.position = first_orb
	main.step(Vector2.ZERO, 0.0)
	assert_eq(main.score.points, 1)
	assert_eq(main.score_label.text, "Score: 1")
	assert_ne(main.orb.position, first_orb)


func test_the_move_actions_steer_the_player() -> void:
	press(&"move_left")
	press(&"move_up")
	await physics_frames(10)
	assert_true(main.player.position.x < main.arena.center().x)
	assert_true(main.player.position.y < main.arena.center().y)
