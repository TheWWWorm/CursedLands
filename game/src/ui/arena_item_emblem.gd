class_name ArenaItemEmblem
extends Control
## Original illustrated relics share a metal rim. Their colors identify each
## object and do not indicate rarity, strength or a separate equipment tier.

const ART := {
	"fang": preload("res://assets/arena/items/fang.svg"),
	"storm": preload("res://assets/arena/items/storm.svg"),
	"venom": preload("res://assets/arena/items/venom.svg"),
	"ward": preload("res://assets/arena/items/ward.svg"),
	"guardian": preload("res://assets/arena/items/guardian.svg"),
	"echo": preload("res://assets/arena/items/echo.svg"),
	"thorn": preload("res://assets/arena/items/thorn.svg"),
	"berserker": preload("res://assets/arena/items/berserker.svg"),
}
const ACCENTS := {
	"fang": Color("e6cfad"), "storm": Color("80dce9"),
	"venom": Color("b9d87c"), "ward": Color("9ad8d5"),
	"guardian": Color("e3c27d"), "echo": Color("d0afe9"),
	"thorn": Color("c9c390"), "berserker": Color("eca27c"),
}

var kind := "":
	set(value):
		kind = value
		queue_redraw()
var ink := ArenaCreatureCard.GOLD


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(28, 28)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _ready() -> void:
	# Reward cards, tray cells and creature slots choose their own dimensions.
	resized.connect(queue_redraw)


static func color_for(item_kind: String) -> Color:
	return ACCENTS.get(item_kind, ArenaCreatureCard.GOLD)


func _draw() -> void:
	var edge := minf(size.x, size.y)
	var origin := (size - Vector2.ONE * edge) / 2.0
	if ART.has(kind):
		draw_texture_rect(ART[kind], Rect2(origin, Vector2.ONE * edge), false)
		return
	# Empty slots use a quiet bag, with no item color or ownership implied.
	draw_set_transform(origin, 0, Vector2.ONE * edge / 32.0)
	draw_circle(Vector2(16, 16), 14, Color("101b22"))
	draw_circle(Vector2(16, 16), 14, Color("63716c"), false, 1.4, true)
	var outline := PackedVector2Array([Vector2(10, 13), Vector2(22, 13), Vector2(24, 24), Vector2(8, 24), Vector2(10, 13)])
	draw_colored_polygon(outline, Color("283637"))
	draw_polyline(outline, Color("9b9e89"), 1.5, true)
	draw_arc(Vector2(16, 13), 4, PI, TAU, 16, Color("9b9e89"), 1.5, true)
	draw_line(Vector2(16, 17), Vector2(16, 21), Color("9b9e89"), 1.5, true)
