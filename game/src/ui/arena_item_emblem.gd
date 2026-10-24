class_name ArenaItemEmblem
extends Control
## Direct renders of existing native items. Tier 1 has no rim;
## reward cards show the original object without a surrounding icon badge.

const ART := {
	"vitality": preload("res://assets/arena/items/vitality.png"),
	"blade": preload("res://assets/arena/items/blade.png"),
	"haste": preload("res://assets/arena/items/haste.png"),
	"mail": preload("res://assets/arena/items/mail.png"),
	"prism": preload("res://assets/arena/items/prism.png"),
	"focus": preload("res://assets/arena/items/focus.png"),
	"fang": preload("res://assets/arena/items/fang.png"),
	"venom": preload("res://assets/arena/items/venom.png"),
	"greatblade": preload("res://assets/arena/items/greatblade.png"),
	"ironheart": preload("res://assets/arena/items/ironheart.png"),
	"quicksilver": preload("res://assets/arena/items/quicksilver.png"),
	"runemail": preload("res://assets/arena/items/runemail.png"),
	"opal": preload("res://assets/arena/items/opal.png"),
	"staff": preload("res://assets/arena/items/staff.png"),
	"ward": preload("res://assets/arena/items/ward.png"),
	"thorn": preload("res://assets/arena/items/thorn.png"),
	"warhammer": preload("res://assets/arena/items/warhammer.png"),
	"bulwark": preload("res://assets/arena/items/bulwark.png"),
	"sage": preload("res://assets/arena/items/sage.png"),
	"windrunner": preload("res://assets/arena/items/windrunner.png"),
	"storm": preload("res://assets/arena/items/storm.png"),
	"guardian": preload("res://assets/arena/items/guardian.png"),
	"echo": preload("res://assets/arena/items/echo.png"),
	"berserker": preload("res://assets/arena/items/berserker.png"),
	"bloodblade": preload("res://assets/arena/items/bloodblade.png"),
	"stormheart": preload("res://assets/arena/items/stormheart.png"),
	"plague": preload("res://assets/arena/items/plague.png"),
	"aegis": preload("res://assets/arena/items/aegis.png"),
	"mirror": preload("res://assets/arena/items/mirror.png"),
	"archmage": preload("res://assets/arena/items/archmage.png"),
	"titan": preload("res://assets/arena/items/titan.png"),
	"duelist": preload("res://assets/arena/items/duelist.png"),
	"sunblade": preload("res://assets/arena/items/sunblade.png"),
	"worldheart": preload("res://assets/arena/items/worldheart.png"),
	"crown": preload("res://assets/arena/items/crown.png"),
	"starweave": preload("res://assets/arena/items/starweave.png"),
	"bloodmoon": preload("res://assets/arena/items/bloodmoon.png"),
	"thunderbolt": preload("res://assets/arena/items/thunderbolt.png"),
	"covenant": preload("res://assets/arena/items/covenant.png"),
	"chronicle": preload("res://assets/arena/items/chronicle.png"),
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
	return ArenaCreatureCard.cost_accent(ArenaItems.tier(item_kind))


func _draw() -> void:
	var edge := minf(size.x, size.y)
	var origin := (size - Vector2.ONE * edge) / 2.0
	if ART.has(kind):
		if framed:
			var centre := origin + Vector2.ONE * edge * 0.5
			draw_circle(centre, edge * 0.48, Color("101917"))
			if ArenaItems.tier(kind) > 1:
				draw_circle(centre, edge * 0.48, color_for(kind), false, maxf(1.5, edge / 20.0), true)
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
