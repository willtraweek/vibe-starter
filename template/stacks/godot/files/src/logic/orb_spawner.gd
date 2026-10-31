class_name OrbSpawner
extends RefCounted
## Picks where the next orb appears: a seeded random spot, away from the player.

## How far an orb stays from the field's edges.
const MARGIN := 48.0
## How far from the player an orb should appear.
const MIN_DISTANCE := 160.0
## Spots tried before settling for the farthest one.
const ATTEMPTS := 16

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int) -> void:
	_rng.seed = seed_value


## The next orb's position in [param arena]: the first spot at least MIN_DISTANCE from
## [param avoid], or, if no spot tried is that far, the farthest of them.
func next_position(arena: Arena, avoid: Vector2) -> Vector2:
	var best := arena.center()
	var best_distance := -1.0
	for _attempt: int in ATTEMPTS:
		var spot := Vector2(
			_rng.randf_range(MARGIN, arena.size.x - MARGIN),
			_rng.randf_range(MARGIN, arena.size.y - MARGIN),
		)
		var distance := spot.distance_to(avoid)
		if distance >= MIN_DISTANCE:
			return spot
		if distance > best_distance:
			best = spot
			best_distance = distance
	return best
