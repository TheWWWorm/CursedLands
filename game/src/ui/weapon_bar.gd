class_name WeaponBar
extends Control
## Weapon display along the bottom (the original
## ): the selected unit's weapon slots (up to four)
## in 40×80 cells at x 80 + 40·i, y 520..600 of the 800×600 layout, right of
## the movement dial, each weapon drawn as its 3D item (ItemView); the active
## weapon (unit; the remake's weapons[0]) is marked, a click makes
## another one active (host command "select_weapon"). Tooltip: name, Damage /
## Actions / Range (texts.res "string infoitem_15 / 20 / 10").
## The active weapon's figure gets =: its
## specular colour, 40/255 added to its pixels (ItemView.add_color).
##  places a figure (100 + 40 i, 560, 24 · 1.2ⁿ)
## at scale 1.2ⁿ, the active one at (100 + 40 i, 540, 12) scale 0.65: 34.6 and
## 45.0 px a model unit (ItemView.unit_px), unclipped, in the original's
## perspective (ItemView.screen_at).
## Slots: a hero's weapons are the player list (count
## ) in their own order, other units [0..3]; the active one is an
## index, so selecting a weapon does not reorder the cells. The
## remake's hero keeps the active weapon first (Session "select_weapon"), so
## the bar remembers each unit's cell order and only marks the active cell.
## **Approx.**: that order is the one first shown (after a load: the saved
## list's, active first).

const SLOTS := 4
var game: Game
var _items: Array = []
var _sig := ""
var _views: Array[ItemView] = []
var _active := 0
var _order := {}   # unit uid -> the cell order (item ids) last shown


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_place_views)
	for i in SLOTS:
		var v := ItemView.new()
		add_child(v)
		_views.append(v)


func _cell() -> Vector2:
	return Vector2(size.x / SLOTS, size.y)


## the active weapon (unit) is drawn 20
## units higher (centre y 540 instead of 560) with its colour
## instead, its hit rectangle reaching up to y 495.
func _place_views() -> void:
	var c := _cell()
	var k := c.y / 80.0   # pixels per 800×600 unit
	for i in SLOTS:
		var lift := c.y * 20.0 / 80.0 if i == _active else 0.0
		# The figure is centred on the cell ((100 + 40 i, 560 or
		# 540)) and not clipped to it: the view is wider than the cell.
		var vs := Vector2(80, 120) * k
		_views[i].position = Vector2((i + 0.5) * c.x, c.y * 0.5 - lift) - vs * 0.5
		_views[i].size = vs
		# 400 / K · scale / z px a model unit: 1.2ⁿ / (24 · 1.2ⁿ), active 0.65 / 12.
		_views[i].unit_px = k * 400.0 / 0.48157462 * (0.65 / 12.0 if i == _active else 1.0 / 24.0)
		# Perspective: depth z / scale (24, active 12 / 0.65) at (100 + 40 i, 560 / 540).
		_views[i].screen_at = Vector3(100.0 + 40.0 * i, 540.0 if i == _active else 560.0,
			12.0 / 0.65 if i == _active else 24.0)
		_views[i].add_color = Color8(0x28, 0x28, 0x28) if i == _active else Color(0, 0, 0)
	_sig = ""


func _process(_dt: float) -> void:
	var u: GameUnit = game.selected[0] if game and not game.selected.is_empty() and is_instance_valid(game.selected[0]) else null
	var w: Array = u.get_meta("hero").get("weapons", []) if u and u.has_meta("hero") else []
	var sig := "%s:%s" % [u.uid if u else -1, ",".join(w)]
	if sig == _sig:
		return
	_sig = sig
	var now := w.slice(0, SLOTS)
	var prev: Array = _order.get(u.uid, []) if u else []
	var a := now.duplicate()
	var b := prev.duplicate()
	a.sort()
	b.sort()
	_items = prev if a == b and not prev.is_empty() else now
	if u:
		_order[u.uid] = _items
	_active = maxi(0, _items.find(w[0])) if not w.is_empty() else 0
	_place_views()
	_sig = sig
	for i in SLOTS:
		_views[i].item = "~"   # force a rebuild after a resize
		_views[i].show_item(_items[i] if i < _items.size() else "")
	queue_redraw()


func _get_tooltip(p: Vector2) -> String:
	var i := int(p.x / _cell().x)
	if i < 0 or i >= _items.size():
		return ""
	var it: String = _items[i]
	var d := Items.damage(it)
	var lines := [Items.title(it), "%s %d-%d" % [_txt(15), int(d.x), int(d.y)]]
	var row: Dictionary = Items.info(it).row
	if row.has("actions"):
		lines.append("%s %s" % [_txt(20), str(row.actions)])
	if float(row.get("range", 0.0)) > 0.0:
		lines.append("%s %.1f" % [_txt(10), float(row.range)])
	return GameData.tip_key("\n".join(lines), 38 + i)   # 0x26 + slot


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var i := int(e.position.x / _cell().x)
		var u: GameUnit = game.selected[0] if not game.selected.is_empty() else null
		if i != _active and i < _items.size() and u:
			game.issue({"t": "select_weapon", "unit": u.uid, "item": _items[i]})
			if GameSound.instance:
				GameSound.instance.ui("buttons\\battle\\weapon.wav")
		accept_event()


## keyboard.ini weapon1–4 (Q / W / E / R, cases 0x26–0x29): with
## more than i weapons and i not the active one, the cell is marked
## buttons\battle\weapon.wav, and the unit told
## (net message, the same as a click).
func key_select(i: int) -> void:
	_process(0.0)
	var u: GameUnit = game.selected[0] if not game.selected.is_empty() else null
	if u == null or i >= _items.size() or i == _active:
		return
	game.issue({"t": "select_weapon", "unit": u.uid, "item": _items[i]})
	if GameSound.instance:
		GameSound.instance.ui("buttons\\battle\\weapon.wav")


func _txt(i: int) -> String:
	return GameData.text("string infoitem_%d" % i).strip_edges()


## No cell frames (only makes the 40×80 hit rectangles).
func _draw() -> void:
	pass
