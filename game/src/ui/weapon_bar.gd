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
## Approx.: the slot order moves with the active weapon (the original keeps slots
## and an index).

const SLOTS := 4
var game: Game
var _items: Array = []
var _sig := ""
var _views: Array[ItemView] = []


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
	for i in SLOTS:
		var lift := c.y * 20.0 / 80.0 if i == 0 else 0.0
		_views[i].position = Vector2(i * c.x, -lift) + Vector2(3, 3)
		_views[i].size = c - Vector2(6, 6)
		_views[i].add_color = Color8(0x28, 0x28, 0x28) if i == 0 else Color(0, 0, 0)
	_sig = ""


func _process(_dt: float) -> void:
	var u: GameUnit = game.selected[0] if game and not game.selected.is_empty() and is_instance_valid(game.selected[0]) else null
	var w: Array = u.get_meta("hero").get("weapons", []) if u and u.has_meta("hero") else []
	var sig := "%s:%s" % [u.uid if u else -1, ",".join(w)]
	if sig == _sig:
		return
	_sig = sig
	_items = w.slice(0, SLOTS)
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
	return "\n".join(lines)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var i := int(e.position.x / _cell().x)
		var u: GameUnit = game.selected[0] if not game.selected.is_empty() else null
		if i > 0 and i < _items.size() and u:
			game.issue({"t": "select_weapon", "unit": u.uid, "item": _items[i]})
			if GameSound.instance:
				GameSound.instance.ui("buttons\\battle\\weapon.wav")
		accept_event()


func _txt(i: int) -> String:
	return GameData.text("string infoitem_%d" % i).strip_edges()


## No cell frames (only makes the 40×80 hit rectangles).
func _draw() -> void:
	pass
