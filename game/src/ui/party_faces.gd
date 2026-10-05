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
## Remake (co-op, user request): those cells are shorter (y 522..600) with a
## smaller face (scale 0.2, centred at y 557, under the own heroes' 0.3 at
## 548) and the same health / stamina bars as the own cells, so a partner's
## state is seen at a glance. When the strip is wider than the room between
## the weapon bar and the belt (or between the corner dials on a phone held
## upright, GameHUD.portrait), the whole strip is scaled down about its
## bottom centre (`_fit`).
## A 20×20 film-camera marker (element 0, UV 34,150-54,170) sits 60 px above
## the face (y 548 − 60) of the unit the camera follows:
## compares each face's unit id, which is field
##  of the static camera object (no direct writer because it is
## only written through the camera's `this`:
## see CameraRig.follow). So it shows only while
## the camera follows a unit — after Home, a double click (touch: a tap) on a face or own
## unit, F1–F3 with Ctrl / Alt or at the zone start (party member 0, usually
## Zak) — and goes when a pan or the minimap ends following. Modern camera:
## over the hero it is attached to (CameraRig.followed).
## The frame is built hidden and shown
## only for selected members (show it
##  hides it), with no colour change.
## The face animation
## (hit flash, expressions, nods / shakes / idle looks) is
## ui/portrait.gd's.

const CELL := 56.0
const OTHER := 40.0
const OTHER_TOP := 522.0     # remake: the other players' shorter cells
const OTHER_FACE_Y := 557.0
const OTHER_SCALE := 0.2

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


var _fit := 1.0   # remake: the strip's scale-down to fit its room (see above)


func _k() -> float:
	return Interface800.canvas_size(self).y / 600.0 * _fit


## 800×600 point -> local: the layout is centred horizontally, its bottom on
## the screen's bottom.
func _p(v: Vector2) -> Vector2:
	var vs := Interface800.canvas_size(self)
	return Vector2(vs.x * 0.5 + (v.x - 400.0) * _k(), vs.y - (600.0 - v.y) * _k())


## Remake: the scale-down for a strip wider than its room: between the weapon
## bar and the belt, or on a phone held upright (where those stand above the
## faces) between the two corner dials.
func _update_fit() -> void:
	_fit = 1.0
	var hud := game.hud if game else null
	if hud == null or _cells.is_empty():
		return
	var vs := Interface800.canvas_size(self)
	var k := vs.y / 600.0
	var left: Control = hud._move_dial if hud.portrait() else hud._weapons
	var right: Control = hud._clock_dial if hud.portrait() else hud._belt
	if not is_instance_valid(left) or not is_instance_valid(right):
		return
	var x0 := left.get_global_rect().end.x - get_global_rect().position.x + 4.0
	var x1 := right.get_global_rect().position.x - get_global_rect().position.x - 4.0
	var room := minf(vs.x * 0.5 - x0, x1 - vs.x * 0.5) * 2.0
	var w := _cell(_cells.size() - 1).end.x - _cell(0).position.x
	if room > 0.0 and w * k > room:
		_fit = maxf(room / (w * k), 0.4)


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
	_update_fit()
	for i in _cells.size():
		var r := _cell(i)
		var p: Portrait = _cells[i][1]
		var own: bool = _cells[i][2]
		var face_r := Rect2(r.position.x + 3, r.position.y + 3, r.size.x - 6, 587 - r.position.y - 5)
		var face := _r(face_r)
		p.position = face.position
		p.size = face.size
		# the figure at the cell's centre, y 548, depth 7, scale
		# 0.3 for a cell wider than 49 px (own heroes), else 0.22 (the remake's
		# smaller co-op faces: OTHER_SCALE, lower).
		if own:
			p.set_exe_place(face_r, r.get_center().x, 0.3)
		else:
			p.set_exe_place(face_r, r.get_center().x, OTHER_SCALE, OTHER_FACE_Y)
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
	if _cells[i][2]:
		return Rect2(x, 510, CELL, 90)
	return Rect2(x, OTHER_TOP, OTHER, 600.0 - OTHER_TOP)


func _cell_at(local: Vector2) -> int:
	for i in _cells.size():
		if _r(_cell(i)).has_point(local):
			return i
	return -1


func _has_point(point: Vector2) -> bool:
	return _cell_at(point) >= 0


func unit_at_screen(point: Vector2) -> GameUnit:
	var i := _cell_at(get_global_transform_with_canvas().affine_inverse() * point)
	return _cells[i][0] if i >= 0 and is_instance_valid(_cells[i][0]) else null


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var i := _cell_at(e.position)
		if i >= 0 and game.has_spell_target():
			if is_instance_valid(_cells[i][0]):
				game.cast_portrait(_cells[i][0])
			# An invalid target consumes the click too: it must not select a
			# different caster while the spell/item is still armed.
			accept_event()
			return
		if i >= 0 and _cells[i][2] and is_instance_valid(_cells[i][0]):
			# a click selects, a double click
			# makes the camera follow the unit.
			# Remake (touch): one tap does both — a double tap is awkward there.
			if e.double_click:
				game.rig.follow(_cells[i][0])
			else:
				game.selected = [_cells[i][0]]
				if TouchInput.enabled:
					game.rig.follow(_cells[i][0])
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
	if not _cells[i][2] and game and game.session:   # remake: whose hero it is
		var who := PlayerNames.player_name(game.session, (_cells[i][0] as GameUnit).controller)
		if who and who != title:
			return "%s (%s)" % [title, who]
	return title


func _region(dst: Rect2, uv: Rect2, mod := Color.WHITE) -> void:
	if _atlas:
		draw_texture_rect_region(_atlas, _r(dst), uv, mod)
	else:
		draw_rect(_r(dst), mod * Color(0.6, 0.45, 0.25))


func _draw() -> void:
	var uvf := Rect2(27, 96, 63, 5)
	var followed := marker_unit()
	for i in _cells.size():
		var u: GameUnit = _cells[i][0]
		if not is_instance_valid(u):
			continue
		var r := _cell(i)
		draw_rect(_r(r), Color(0, 0, 0, 0.35))
		# Health and stamina bars (the remake draws them in the other
		# players' cells too).
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
		if u == followed:
			var cx := r.get_center().x
			_region(Rect2(cx - 10, 478, 20, 20), Rect2(34, 150, 20, 20))


## The face the film-camera marker stands over: the unit the camera follows
## (CameraRig.followed, the original), when it has a cell; else null.
func marker_unit() -> GameUnit:
	var f: Node3D = game.rig.followed() if game and game.rig else null
	if f == null:
		return null
	for c in _cells:
		if is_instance_valid(c[0]) and c[0] == f:
			return c[0]
	return null


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
