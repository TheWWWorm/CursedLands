class_name BeltStrip
extends Control
## Belt of the selected hero on the right edge (the original
## ): the quick items
## (up to eight at unit) as 3D models (ItemView) in 40×40
## cells at x 760..800 stacked up from y 470..510 of the 800×600 layout;
## tooltips with the item's spell (texts.res "string infoitem_7 / 18 / 8 ...").
## A double click uses the item at once (picked when the input's
##  flag — set on WM_LBUTTONDBLCLK — is ): friendly
## spells on the holder, offensive ones on the nearest enemy (Session "use").
## A single click selects it (the cell's figure is scaled 1.15
## (1.15), and gets =, ItemView.add_color) and the next click in the world picks its target; the same item
## again cancels.
## Tooltip (labels "string infoitem_N" for N in 7, 18, 8, 9
## 10, 11, 12, 13, 21, 22, 26, 27, 28 loaded): the item's
## name; for an item with a spell then " \n" and
## two fields per line, "%s %d  " Stamina, "%s %s \n" School; Effect ("%s %s"
## Constant when the prototype takes no effect runes, else "%s %d")
## Speed ("%d", or Immediately below 1); Range "%d" + m, Area (π r² "%.1f" +
## m, or Target for a unit spell, flag); Duration (Immediately
## below 2 ticks, else ticks / 15 "%.1f" + s), Targets — the camp's spell
## rows (CampView), here in pairs.

const SLOTS := 8
var game: Game
var _items: Array = []
var _sig := ""
var _views: Array[ItemView] = []
var _unit: GameUnit


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	for i in SLOTS:
		var v := ItemView.new()
		add_child(v)
		_views.append(v)


func _cell_rect(i: int) -> Rect2:
	return Rect2(Vector2(0, size.y - (i + 1) * size.x), Vector2(size.x, size.x))


func _has_point(p: Vector2) -> bool:
	return _slot_at(p) >= 0


func _process(_dt: float) -> void:
	var u: GameUnit = game.selected[0] if game and not game.selected.is_empty() and is_instance_valid(game.selected[0]) else null
	var q: Array = u.get_meta("hero").get("quick", []) if u and u.has_meta("hero") else []
	var sig := "%s:%s:%s:%s" % [u.uid if u else -1, ",".join(q), size, game.pending_spell]
	if sig == _sig:
		return
	_sig = sig
	_unit = u
	_items = q.slice(0, SLOTS)
	for i in SLOTS:
		var r := _cell_rect(i).grow(-3)
		var picked := i < _items.size() and game.pending_spell == "%s%d:%s" % [Game.BELT, u.uid if u else -1, _items[i]]
		if picked:   # the picked cell is scaled 1.15 and brightened
			r = r.grow(r.size.x * 0.075)
		_views[i].position = r.position
		_views[i].size = r.size
		_views[i].add_color = Color8(0x40, 0x40, 0x40) if picked else Color(0, 0, 0)
		_views[i].visible = i < _items.size()
		_views[i].item = "~"
		_views[i].show_item(_items[i] if i < _items.size() else "")
	queue_redraw()


func _slot_at(p: Vector2) -> int:
	for i in _items.size():
		if _cell_rect(i).has_point(p):
			return i
	return -1


func _get_tooltip(p: Vector2) -> String:
	var i := _slot_at(p)
	return tooltip_text(String(_items[i])) if i >= 0 else ""


static func tooltip_text(item: String) -> String:
	var t := Items.title(item)
	var sp := Items.potion_spell(item)
	if sp.is_empty():
		sp = Items.spell_of(item)
	if sp.is_empty() or not GameData.is_open():
		return t
	var pp := Spells.parse(sp)
	var mods: Array = Array(pp.proto.get("mods", []))
	var effect := "%s %s" % [_l(8), _l(28)] if mods.size() > 3 and int(mods[3]) == 0 else "%s %d" % [_l(8), int(pp.effect)]
	var spd := float(pp.proto.get("speed", 0.0))
	var area := "%s %s" % [_l(11), _l(22)] if int(pp.flags) & 0x10000000 \
		else "%s %.1f%s" % [_l(11), PI * float(pp.radius) * float(pp.radius), _l(26)]
	var d := float(pp.duration)
	var dur := "%s %s" % [_l(12), _l(21)] if d < 2.0 else "%s %.1f%s" % [_l(12), d / 15.0, _l(27)]
	var lines := [
		"%s %d  %s %s" % [_l(7), int(pp.mana), _l(18), _school(pp)],
		"%s  %s %s" % [effect, _l(9), ("%d" % int(spd)) if spd >= 1.0 else _l(21)],
		"%s %d%s  %s" % [_l(10), int(pp.range), _l(26), area],
		"%s  %s %d" % [dur, _l(13), int(pp.targets)]]
	return t + "\n" + "\n".join(lines)


## "string school_N", "Unknown" when missing (default).
static func _school(pp: Dictionary) -> String:
	var t := GameData.text("string school_%d" % int(pp.proto.get("type_id", 0))).strip_edges()
	return t if t else "Unknown"


static func _l(n: int) -> String:
	return GameData.text("string infoitem_%d" % n).strip_edges()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var i := _slot_at(e.position)
		if i >= 0 and _unit:
			if e.double_click and _no_target(_items[i]):
				# an offensive spell item with no hostile unit
				# view sounds nomagic.wav and is not used.
				if GameSound.instance:
					GameSound.instance.ui("buttons\\battle\\nomagic.wav")
				accept_event()
				return
			if GameSound.instance:
				GameSound.instance.ui("buttons\\battle\\click.wav")
			if e.double_click:
				game.pending_spell = ""
				game.hud.set_targeting("")
				game.issue({"t": "use", "unit": _unit.uid, "item": _items[i]})
			else:
				game.begin_belt(_unit, _items[i])
			queue_redraw()
			accept_event()


func _no_target(item: String) -> bool:
	var sp := Items.potion_spell(item)
	if sp.is_empty():
		sp = Items.spell_of(item)
	return not sp.is_empty() and Spells.offensive(sp) and game.world \
		and game.world.ai.nearest_enemy(_unit, Session.BELT_TARGET_RANGE) == null


## No cell frames: only makes the hit rectangles; the items are
## their 3D models.
func _draw() -> void:
	pass
