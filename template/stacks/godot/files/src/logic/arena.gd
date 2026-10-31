class_name Arena
extends RefCounted
## The playing field: where a body may be, and when two bodies touch. Pure logic, no nodes.

var size: Vector2


func _init(field_size: Vector2) -> void:
	size = field_size


func center() -> Vector2:
	return size / 2.0


## [param point], moved just far enough to keep a body of [param radius] inside the field.
## A body too big for the field sits as close to its middle as its radius allows.
func keep_inside(point: Vector2, radius: float) -> Vector2:
	var margin := Vector2(radius, radius)
	return point.clamp(margin, (size - margin).max(margin))


## True when bodies at [param a] and [param b] are no more than [param reach] apart.
func touching(a: Vector2, b: Vector2, reach: float) -> bool:
	return a.distance_to(b) <= reach
