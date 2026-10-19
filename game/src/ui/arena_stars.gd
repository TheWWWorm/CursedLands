class_name ArenaStars
extends Control
## Evolution rank is one visual language on the board, shelf and reserves.
const PAPER_STAR: Texture2D = preload("res://assets/arena/star_paper.svg")
const GOLD_STAR: Texture2D = preload("res://assets/arena/star_gold.svg")
const TIER_STAR: Texture2D = preload("res://assets/arena/star_tier.svg")
var count := 1
var color := ArenaCreatureCard.PAPER


static func add_to(parent: Control, rank: int, at: Vector2, tint := ArenaCreatureCard.PAPER) -> ArenaStars:
	var stars := ArenaStars.new()
	stars.count = clampi(rank, 1, 3)
	stars.color = tint
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.position = at
	stars.custom_minimum_size = Vector2(stars.count * 14 - 2, 12)
	parent.add_child(stars)
	return stars


static func draw_rank(canvas: CanvasItem, at: Vector2, rank: int, scale_factor := 1.0, tint := ArenaCreatureCard.PAPER) -> void:
	# The 18 combatants can have 54 moving stars. Reuse the authored shape
	# instead of tessellating a filled polygon and antialiased outline per star.
	var texture: Texture2D = TIER_STAR
	for i in clampi(rank, 1, 3):
		canvas.draw_texture_rect(texture, Rect2(at + Vector2(i * 14, 0) * scale_factor,
			Vector2(12, 12) * scale_factor), false, tint)


func _draw() -> void:
	draw_rank(self, Vector2.ZERO, count, 1.0, color)


static func for_family(family: int) -> Color:
	return ArenaCreatureCard.cost_accent(int(ArenaRules.FAMILIES[family].tier)) if family >= 0 and family < ArenaRules.FAMILIES.size() else ArenaCreatureCard.PAPER


static func for_prototype(id: String) -> Color:
	for family in ArenaRules.FAMILIES.size():
		if id in ArenaRules.FAMILIES[family].forms: return for_family(family)
	return ArenaCreatureCard.PAPER
