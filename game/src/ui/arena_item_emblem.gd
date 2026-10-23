class_name ArenaItemEmblem
extends Control
## Direct renders of existing native items. Small slots share a metal rim;
## reward cards show the original object without a surrounding icon badge.

const ART := {
	"fang": preload("res://assets/arena/items/fang.png"),
	"storm": preload("res://assets/arena/items/storm.png"),
	"venom": preload("res://assets/arena/items/venom.png"),
	"ward": preload("res://assets/arena/items/ward.png"),
	"guardian": preload("res://assets/arena/items/guardian.png"),
	"echo": preload("res://assets/arena/items/echo.png"),
	"thorn": preload("res://assets/arena/items/thorn.png"),
	"berserker": preload("res://assets/arena/items/berserker.png"),
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
var framed := true


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
		if framed:
			var centre := origin + Vector2.ONE * edge * 0.5
			draw_circle(centre, edge * 0.48, Color("101917"))
			draw_circle(centre, edge * 0.48, Color("738079"), false, maxf(1.0, edge / 32.0), true)
			draw_circle(centre, edge * 0.43, Color(color_for(kind), 0.45), false, 1, true)
		var inset := edge * 0.07 if framed else 0.0
		draw_texture_rect(ART[kind], Rect2(origin + Vector2.ONE * inset, Vector2.ONE * (edge - inset * 2)), false)
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
