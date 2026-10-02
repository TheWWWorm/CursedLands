class_name SelectionFrame
extends Control
## The frame selection rectangle (CInterface3D draw, field screen
## ): while the frame flag is set (the input part's
## set by mouse move) it calls the renderer's rectangle
## (x0, y0, x1, y1, 0x40, 1) with the normalized rect..
## (the press point and the pointer, in window pixels), before the HUD widgets
## so the panels cover it. draws untextured
## XYZRHW quads: with the outline flag the fill is inset by 1 px,
## (x0+1, y0+1)-(x1-1, y1-1), diffuse alpha 0x40 << 24 (black at 64/255), then
## a 5-vertex line strip x0,y0 → x0,y1 → x1,y1 → x1,y0 → x0,y0
## (opaque white, 1 px). No texture, no 800×600 scaling: window pixels.
## Draw only — mouse_filter IGNORE, the game keeps the input.

const FILL := Color(0, 0, 0, 0x40 / 255.0)
const LINE := Color(1, 1, 1, 1)

var game: Game
var _shown := Rect2()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_dt: float) -> void:
	var r: Rect2 = game.frame_rect() if is_instance_valid(game) else Rect2()
	if r != _shown:
		_shown = r
		queue_redraw()


func _draw() -> void:
	if _shown.size == Vector2.ZERO and _shown.position == Vector2.ZERO:
		return
	# Viewport pixels → this control (identity unless the HUD layer is moved).
	var inv := get_global_transform_with_canvas().affine_inverse()
	var a := (inv * _shown.position).floor()
	var b := (inv * _shown.end).floor()
	if b.x - a.x > 2 and b.y - a.y > 2:
		draw_rect(Rect2(a + Vector2.ONE, b - a - Vector2(2, 2)), FILL)
	# Pixel centres so the 1 px strip lands on whole pixels.
	var h := Vector2(0.5, 0.5)
	draw_polyline(PackedVector2Array([a + h, Vector2(a.x, b.y) + h, b + h, Vector2(b.x, a.y) + h, a + h]),
		LINE, 1.0)
