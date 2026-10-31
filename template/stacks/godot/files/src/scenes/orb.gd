class_name Orb
extends Node2D
## The orb to collect: a circle in the orb colour.

const RADIUS := 12.0


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Style.ORB)
