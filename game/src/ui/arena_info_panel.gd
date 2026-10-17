class_name ArenaInfoPanel
extends PanelContainer
## Small chamfered labels remain readable over both snow and dark scenery.

var accent := Color("f0eadc"):
	set(value):
		accent = value
		queue_redraw()
var highlighted := false:
	set(value):
		highlighted = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var padding := StyleBoxEmpty.new()
	padding.content_margin_left = 9; padding.content_margin_right = 9
	padding.content_margin_top = 4; padding.content_margin_bottom = 4
	add_theme_stylebox_override("panel", padding)
	resized.connect(queue_redraw)


func _draw() -> void:
	var rect := Rect2(Vector2.ONE, size - Vector2(2, 2))
	var cut := minf(6.0, rect.size.y * 0.25)
	var a := rect.position; var b := rect.end
	var points := PackedVector2Array([
		Vector2(a.x + cut, a.y), Vector2(b.x - cut, a.y), Vector2(b.x, a.y + cut),
		Vector2(b.x, b.y - cut), Vector2(b.x - cut, b.y), Vector2(a.x + cut, b.y),
		Vector2(a.x, b.y - cut), Vector2(a.x, a.y + cut)])
	var shadow := points.duplicate()
	for i in shadow.size(): shadow[i] += Vector2(0, 2)
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.22))
	draw_colored_polygon(points, Color(0.055, 0.075, 0.09, 0.94 if highlighted else 0.88))
	points.append(points[0])
	draw_polyline(points, accent.lerp(Color.WHITE, 0.45 if highlighted else 0.2), 1.0, true)
	draw_line(Vector2(a.x + cut, a.y + 2), Vector2(b.x - cut, a.y + 2), Color(accent, 0.2), 1.0)
