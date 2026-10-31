extends TestCase

var arena := Arena.new(Vector2(400, 300))


func test_the_center_is_half_the_size() -> void:
	assert_eq(arena.center(), Vector2(200, 150))


func test_a_body_inside_stays_where_it_is() -> void:
	assert_eq(arena.keep_inside(Vector2(100, 120), 10.0), Vector2(100, 120))


func test_a_body_past_an_edge_comes_back_inside() -> void:
	assert_eq(arena.keep_inside(Vector2(-50, 500), 10.0), Vector2(10, 290))
	assert_eq(arena.keep_inside(Vector2(900, -5), 10.0), Vector2(390, 10))


func test_a_body_too_big_for_the_field_sits_at_its_radius() -> void:
	assert_eq(arena.keep_inside(Vector2(300, 0), 200.0), Vector2(200, 200))


func test_bodies_touch_within_reach_and_not_beyond() -> void:
	assert_true(arena.touching(Vector2(0, 0), Vector2(3, 4), 5.0))
	assert_false(arena.touching(Vector2(0, 0), Vector2(3, 4), 4.9))
