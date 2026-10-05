class_name ChatOverlay
extends Interface800
## Co-op chat lines as the original's chat object (
## list): word-wraps an arriving "^%i%s^7: %s" message
## 0x30c px into 783×17 surfaces, stamps each with its arrival
## time and keeps at most 12 lines (the oldest dropped)
##  places line i at (10, 10 + 16 i) of the 800×600 screen (top
## left, oldest first); drops a line 20 s after it arrived.
## Text: font 1 with a shadow, the ^0–^7 codes as RGB bits (bit 0
## red, 1 green, 2 blue): the name in the player's colour, ": text" after ^7
## white. Backspace in a network game empties the list (
## `clear`). NetStatus.colour decodes the host's independent colour code.

const MAX_LINES := 12
const LIFE_MS := 20000
const WRAP := 780.0   # 0x30c

var _lines: Array = []   # [arrival ms, text, name chars coloured, colour]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func add(idx: int, player_name: String, text: String, players: Dictionary = {}) -> void:
	var now := Time.get_ticks_msec()
	var col := NetStatus.colour(idx, players)
	var rows := wrap_text("%s: %s" % [player_name, text], WRAP, 1)
	var left := player_name.length()
	for r in rows:
		_lines.append([now, r, left, col])
		left = maxi(0, left - r.length() - 1)
	while _lines.size() > MAX_LINES:
		_lines.pop_front()
	queue_redraw()


func clear() -> void:
	_lines.clear()
	queue_redraw()


func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	var n := _lines.size()
	_lines = _lines.filter(func(l: Array) -> bool: return now - int(l[0]) <= LIFE_MS)
	if _lines.size() != n:
		queue_redraw()


func _draw() -> void:
	var f := font()
	var fs := font_px(1)
	var sh := maxf(1.0, round(kv().y))
	for i in _lines.size():
		var l: Array = _lines[i]
		var s: String = l[1]
		var p := p8(Vector2(10.0, 10.0 + 16.0 * i))
		var y := p.y + f.get_ascent(fs)
		var head := s.substr(0, int(l[2]))
		var rest := s.substr(int(l[2]))
		var x := p.x
		for part: Array in [[head, l[3]], [rest, Color.WHITE]]:
			if String(part[0]).is_empty():
				continue
			draw_string(f, Vector2(x + sh, y + sh), part[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, SHADOW)
			draw_string(f, Vector2(x, y), part[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, part[1])
			x += f.get_string_size(part[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
