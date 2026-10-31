class_name Player
extends Node2D
## The player's body: a square in the player colour.

const RADIUS := 18.0


func _draw() -> void:
	draw_rect(Rect2(-RADIUS, -RADIUS, RADIUS * 2.0, RADIUS * 2.0), Style.PLAYER)
