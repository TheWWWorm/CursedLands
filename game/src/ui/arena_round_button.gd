class_name ArenaRoundButton
extends Button
## Shared refresh/training control, with a gold cost badge and an XP ring.

var emblem: Texture2D
var value := ""
var caption := ""
var price := -1
var progress := -1.0


func _ready() -> void:
	custom_minimum_size = Vector2(96, 84)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for event in [mouse_entered, mouse_exited, focus_entered, focus_exited, button_down, button_up]:
		event.connect(queue_redraw)


func _draw() -> void:
	var center := Vector2(size.x * 0.5, 33)
	var active := not disabled and (is_hovered() or has_focus())
	var ink := ArenaCreatureCard.PAPER if not disabled else ArenaCreatureCard.MUTED
	draw_circle(center, 28, Color("344248") if active else Color("182321"))
	draw_arc(center, 28, 0, TAU, 64, ArenaCreatureCard.GOLD if active else Color("69716a"), 2, true)
	if progress >= 0:
		draw_arc(center, 24, -PI / 2, TAU - PI / 2, 64, Color("414b46"), 3, true)
		if progress > 0:
			draw_arc(center, 24, -PI / 2, -PI / 2 + TAU * clampf(progress, 0, 1), 64, ArenaCreatureCard.GOLD, 3, true)
	if emblem:
		draw_texture_rect(emblem, Rect2(center - Vector2(14, 14), Vector2(28, 28)), false, ink)
	else:
		_centered(value, center + Vector2(0, 9), 27, ink)
	if has_focus(): draw_arc(center, 31, 0, TAU, 64, ArenaCreatureCard.PAPER, 1, true)
	if price >= 0:
		var badge := center + Vector2(22, -23)
		draw_circle(badge, 11, ArenaCreatureCard.GOLD if not disabled else Color("8a8060"))
		draw_arc(badge, 11, 0, TAU, 32, Color("50462e"), 1, true)
		_centered(str(price), badge + Vector2(0, 5), 14, Color("19211e"))
	_centered(caption, Vector2(size.x * 0.5, 80), 13, ArenaCreatureCard.PAPER)


func _centered(text: String, baseline: Vector2, pixels: int, color: Color) -> void:
	var font := get_theme_font("font")
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	draw_string(font, baseline - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, color)
