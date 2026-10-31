extends TestCase

var arena := Arena.new(Vector2(1280, 720))


func test_orbs_appear_inside_the_margin_and_away_from_the_player() -> void:
	var spawner := OrbSpawner.new(1)
	for _i: int in 50:
		var spot := spawner.next_position(arena, arena.center())
		assert_true(spot.x >= OrbSpawner.MARGIN and spot.x <= arena.size.x - OrbSpawner.MARGIN)
		assert_true(spot.y >= OrbSpawner.MARGIN and spot.y <= arena.size.y - OrbSpawner.MARGIN)
		assert_true(spot.distance_to(arena.center()) >= OrbSpawner.MIN_DISTANCE)


func test_the_same_seed_places_the_same_orbs() -> void:
	var first := OrbSpawner.new(42)
	var second := OrbSpawner.new(42)
	for _i: int in 5:
		assert_eq(
			first.next_position(arena, Vector2.ZERO),
			second.next_position(arena, Vector2.ZERO),
		)


func test_a_field_too_small_for_the_distance_gives_the_farthest_spot_tried() -> void:
	var small := Arena.new(Vector2(200, 200))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var spots: Array[Vector2] = []
	for _i: int in OrbSpawner.ATTEMPTS:
		spots.append(
			Vector2(
				rng.randf_range(OrbSpawner.MARGIN, small.size.x - OrbSpawner.MARGIN),
				rng.randf_range(OrbSpawner.MARGIN, small.size.y - OrbSpawner.MARGIN),
			)
		)
	var by_distance: Array[Vector2] = spots.duplicate()
	by_distance.sort_custom(
		func(a: Vector2, b: Vector2) -> bool:
			return a.distance_to(small.center()) > b.distance_to(small.center()),
	)
	assert_true(by_distance[0].distance_to(small.center()) < OrbSpawner.MIN_DISTANCE)
	assert_eq(OrbSpawner.new(3).next_position(small, small.center()), by_distance[0])
