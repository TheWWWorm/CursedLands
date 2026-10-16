class_name ArenaHudPanel
extends PanelContainer
## Use the original save/load frame atlas at a restrained HUD thickness.

var surface := Color(0.045, 0.06, 0.065, 0.94)
var edge := Color("716348")

func _ready() -> void:
	var padding := StyleBoxEmpty.new()
	padding.content_margin_left = 12; padding.content_margin_right = 12
	padding.content_margin_top = 10; padding.content_margin_bottom = 10
	add_theme_stylebox_override("panel", padding)
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), surface)
	draw_frame(self, Rect2(Vector2.ZERO, size))


static func draw_frame(canvas: CanvasItem, rect: Rect2, width := 3.0) -> void:
	var texture := Interface800.tex("saveload")
	if texture == null:
		canvas.draw_rect(rect.grow(-1), Color("8e7951"), false, 1)
		return
	var outer := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var inner := [outer[0] + Vector2(width, width), outer[1] + Vector2(-width, width), outer[2] - Vector2(width, width), outer[3] + Vector2(width, -width)]
	var uv := PackedVector2Array([Vector2(2, 254), Vector2(180, 254), Vector2(180, 249), Vector2(2, 249)])
	for i in uv.size(): uv[i] /= 256.0
	for side in 4:
		var next := (side + 1) % 4
		canvas.draw_polygon(PackedVector2Array([outer[side], outer[next], inner[next], inner[side]]), PackedColorArray([Color.WHITE]), uv, texture)
