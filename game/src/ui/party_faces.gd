class_name PartyFaces
extends Control
## Bottom-centre party faces as in the original (the original widget
## (250,440)-(550,600) of the 800×600 layout scaled by the window height;
## cells built, updated).
## Each party member gets a 56 px cell at x = 400 − n·28 + 56 i, y 510..600:
##   * the face (ui/portrait.gd) centred at y 548;
##   * a 3 px bronze frame round the cell (battle00 UV
##     27,96-90,101);
##   * health bar (x0+3, 587)-(x1−3, 592), UV 9,9 + 64 f × 13 (the green strip),
##     stamina bar at y 592..597, UV 9,35 (the blue strip), both scaled to the
##     fraction f from the left.
## In a network game the other players' heroes follow in 40 px
## cells, the face greyed (0.5) and without bars.
## A 20×20 film-camera marker (element 0, UV 34,150-54,170) sits 60 px above
## the face (y 548 − 60) of the unit (seen above Zak's face
## the original's screenshots).
## The frame is built hidden and shown
## only for selected members (show it
##  hides it), with no colour change.
## **Approx.**: has no writer in the original (one read
## against unit;.data value 0), so the original would show
## the marker only for a unit with id 0; the remake keeps it over the first
## selected party member, as the screenshots show it. The face animation
## (hit flash, expressions, nods / shakes / idle looks) is
## ui/portrait.gd's.

const CELL := 56.0
const OTHER := 40.0

var game: Game
var _atlas: Texture2D
var _cells: Array = []   # [GameUnit, Portrait, own]
var _sig := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var img := GameData.load_image("battle00") if GameData.is_open() else null
	if img:
		img.flip_y()
		_atlas = ImageTexture.create_from_image(img)


func _k() -> float:
	return Interface800.canvas_size(self).y / 600.0


## 800×600 point -> local: the layout is centred horizontally.
func _p(v: Vector2) -> Vector2:
	var vs := Interface800.canvas_size(self)
	return Vector2(vs.x * 0.5 + (v.x - 400.0) * _k(), v.y * _k())


func _r(r: Rect2) -> Rect2:
	return Rect2(_p(r.position), r.size * _k())


func _units() -> Array:
	var out := []
	for u in game.my_units():
		out.append([u, true])
	if game.session and game.session.online:
		for u: GameUnit in game.world.units.values():
			if u.controller >= 0 and u.controller != game.session.my_index and u.has_meta("hero") and not u.dead:
				out.append([u, false])
	return out


func rebuild() -> void:
	for c in _cells:
		c[1].queue_free()
	_cells.clear()
	_sig = ""


func _process(_dt: float) -> void:
	if game == null or game.world == null:
		return
	var list := _units()
	var sig := ",".join(list.map(func(e): return "%d%s" % [e[0].uid, "o" if e[1] else "x"]))
	if sig != _sig:
		rebuild()
		_sig = sig
		for e in list:
			var p := Portrait.new()
			p.view_size = Vector2i(56, 76)
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(p)
			p.show_unit(e[0])
			if not e[1]:
				p.modulate = Color(0.5, 0.5, 0.5)
			_cells.append([e[0], p, e[1]])
	for i in _cells.size():
		var r := _cell(i)
		var p: Portrait = _cells[i][1]
		var face := _r(Rect2(r.position.x + 3, 513, r.size.x - 6, 72))
		p.position = face.position
		p.size = face.size
		p.selected = _cells[i][0] in game.selected
	queue_redraw()


func acknowledge(unit: GameUnit, code: int) -> void:
	for c in _cells:
		if c[0] == unit and c[2]:
			(c[1] as Portrait).acknowledge(code)


func nod_units(ids: Array) -> void:
	for c in _cells:
		if c[2] and is_instance_valid(c[0]) and c[0].uid in ids:
			(c[1] as Portrait).nod()


func _cell(i: int) -> Rect2:
	var own := 0
	for c in _cells:
		own += 1 if c[2] else 0
	var total := own * CELL + (_cells.size() - own) * OTHER
	var x := 400.0 - total * 0.5
	for j in i:
		x += CELL if _cells[j][2] else OTHER
	return Rect2(x, 510, CELL if _cells[i][2] else OTHER, 90)


func _cell_at(local: Vector2) -> int:
	for i in _cells.size():
		if _r(_cell(i)).has_point(local):
			return i
	return -1


func _has_point(point: Vector2) -> bool:
	return _cell_at(point) >= 0


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var i := _cell_at(e.position)
		if i >= 0 and _cells[i][2] and is_instance_valid(_cells[i][0]):
			game.selected = [_cells[i][0]]
			if e.double_click and game.rig.modern():   # remake: centre the modern camera
				game.rig.center_on(_cells[i][0].position)
			accept_event()


func _get_tooltip(at: Vector2) -> String:
	var i := _cell_at(at)
	if i < 0 or not is_instance_valid(_cells[i][0]):
		return ""
	var title: String = _cells[i][0].display_name
	# select1..3 (action ids 55..57), in single player only. tip_key uses
	# EIKeymap.key_of_id to show the first current binding, if any.
	if i < 3 and _cells[i][2] and game and game.session and not game.session.online:
		return GameData.tip_key(title, 55 + i)
	return title


func _region(dst: Rect2, uv: Rect2, mod := Color.WHITE) -> void:
	if _atlas:
		draw_texture_rect_region(_atlas, _r(dst), uv, mod)
	else:
		draw_rect(_r(dst), mod * Color(0.6, 0.45, 0.25))


func _draw() -> void:
	var uvf := Rect2(27, 96, 63, 5)
	for i in _cells.size():
		var u: GameUnit = _cells[i][0]
		if not is_instance_valid(u):
			continue
		var r := _cell(i)
		draw_rect(_r(r), Color(0, 0, 0, 0.35))
		if _cells[i][2]:
			var w := r.size.x - 6
			var f := clampf(u.hp / maxf(u.max_hp, 0.01), 0.0, 1.0)
			if f > 0.0:
				_region(Rect2(r.position.x + 3, 587, w * f, 5), Rect2(9, 9, 64 * f, 13))
			f = clampf(u.mana / u.max_mana, 0.0, 1.0) if u.max_mana > 0 else 0.0
			if f > 0.0:
				_region(Rect2(r.position.x + 3, 592, w * f, 5), Rect2(9, 35, 64 * f, 13))
		if u in game.selected:
			# Frame: four 3 px strips inside the cell, selected members only.
			var a := r.position + Vector2(1.5, 1.5)
			var b := r.end - Vector2(1.5, 1.5)
			_strip(Vector2(r.position.x, a.y), Vector2(r.end.x, a.y), uvf, Color.WHITE)
			_strip(Vector2(r.position.x, b.y), Vector2(r.end.x, b.y), uvf, Color.WHITE)
			_strip(Vector2(a.x, r.position.y), Vector2(a.x, r.end.y), uvf, Color.WHITE)
			_strip(Vector2(b.x, r.position.y), Vector2(b.x, r.end.y), uvf, Color.WHITE)
		if _cells[i][2] and not game.selected.is_empty() and game.selected[0] == u:
			var cx := r.get_center().x
			_region(Rect2(cx - 10, 478, 20, 20), Rect2(34, 150, 20, 20))


## A 3 px textured strip along from -> to (800×600 points).
func _strip(from: Vector2, to: Vector2, uv: Rect2, mod: Color) -> void:
	var d := (to - from).normalized().orthogonal() * 1.5
	var pts := PackedVector2Array([_p(from - d), _p(to - d), _p(to + d), _p(from + d)])
	if _atlas == null:
		draw_colored_polygon(pts, mod * Color(0.6, 0.45, 0.25))
		return
	var s := _atlas.get_size()
	var uvs := PackedVector2Array([uv.position / s, Vector2(uv.end.x, uv.position.y) / s, uv.end / s,
		Vector2(uv.position.x, uv.end.y) / s])
	draw_primitive(pts, PackedColorArray([mod, mod, mod, mod]), uvs, _atlas)
