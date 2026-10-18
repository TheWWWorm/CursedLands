class_name ArenaStars
extends Control
## Evolution rank is one visual language on the board, shelf and reserves.
const PAPER_STAR: Texture2D = preload("res://assets/arena/star_paper.svg")
const GOLD_STAR: Texture2D = preload("res://assets/arena/star_gold.svg")
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
	# The 18 combatants can have 54 moving stars. Reuse the authored shape
	# instead of tessellating a filled polygon and antialiased outline per star.
	var texture: Texture2D = PAPER_STAR if rank == 1 else GOLD_STAR
	for i in clampi(rank, 1, 3):
		canvas.draw_texture_rect(texture, Rect2(at + Vector2(i * 14, 0) * scale_factor,
			Vector2(12, 12) * scale_factor), false)


func _draw() -> void:
	draw_rank(self, Vector2.ZERO, count)
