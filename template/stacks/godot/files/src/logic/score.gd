class_name Score
extends RefCounted
## The points of the round being played.

## Emitted with the new total whenever it changes.
signal changed(points: int)

var points := 0


func collect() -> void:
	points += 1
	changed.emit(points)


func reset() -> void:
	points = 0
	changed.emit(points)
