class_name ArenaStars
extends Control
## Evolution rank is one visual language on the board, shelf and reserves.
var count := 1


static func add_to(parent: Control, rank: int, at: Vector2) -> ArenaStars:
	var stars := ArenaStars.new()
	stars.count = clampi(rank, 1, 3)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.position = at
	stars.custom_minimum_size = Vector2(stars.count * 14 - 2, 12)
	parent.add_child(stars)
	return stars


static func draw_rank(canvas: CanvasItem, at: Vector2, rank: int, scale_factor := 1.0) -> void:
	for i in clampi(rank, 1, 3):
		var points := PackedVector2Array()
		var center := at + Vector2(i * 14 + 6, 6) * scale_factor
		for vertex in 10:
			var angle := -PI / 2 + vertex * PI / 5
			points.append(center + Vector2(cos(angle), sin(angle)) * (5.5 if vertex % 2 == 0 else 2.5) * scale_factor)
		canvas.draw_colored_polygon(points, ArenaCreatureCard.PAPER if rank == 1 else ArenaCreatureCard.GOLD)
		points.append(points[0])
		canvas.draw_polyline(points, Color("302819"), scale_factor, true)


func _draw() -> void:
	draw_rank(self, Vector2.ZERO, count)
