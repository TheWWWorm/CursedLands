class_name BeltStrip
extends Control
## The selected hero's belt (quick items) bottom right (the original
## builds it, fills it): eight 50×50 cells in 520..720 ×
## 500..600 of the 800×600 layout. The lower four are (i) — for a hero the
## player's list (stack count ≥ 1), else unit [0..3]
## the upper four show the local main hero's carried quest items (0x3009,
## player bag). Each item is
## drawn as its 3D model centred at (695 − 50 i, 575) for i < 4, then
## (695 − 50 (i − 4), 525): from the bottom right cell leftwards, then the
## top row, (…, 20) at scale 0.55 (bottom) / 0.85 (top), in the
## original's perspective (ItemView.screen_at). (The right-edge column holds the spells
## SpellSlots.)
## Keys item1–4 (P / O / I / U, cases 0x2a–0x2d):
## — click.wav; a wand or potion (prototype item_id 5 / 8) is picked (scale
## 0.65 / 1.0 for the bottom / top row, =
## ItemView.add_color) and the next click in the
## world picks its target (interaction mode 3 / 4); the same cell again
## cancels. With Ctrl / Alt,: used at once — an offensive spell
##  on the nearest hostile unit in view (none:
## nomagic.wav, the item kept), anything else on the holder (Session "use").
## A click picks, a double click uses at once, as those two.
## The HUD's item cells act on the button's release, not the press (traced
## 2026-10-04, input s weapons / belt
## spells / actions): the press on a filled cell only captures the
## mouse (the
## double click's handler the same); the release (
## ) hit-tests its own point and acts on the cell
## *there*: released over another cell of the same strip, that cell acts;
## released off the strip, nothing happens. The double click's flag
## (manager) holds until that release. No item follows
## the cursor (there is no drag and drop, see the reference doc).
## Tooltip: the item's name; for an item with a spell
## then " \n" and, two fields per line, "%s %d  " Stamina, "%s %s \n" School;
## Effect ("%s %s" Constant when the prototype takes no effect runes
## else "%s %d"), Speed ("%d", or Immediately below 1); Range "%d" + m, Area
## (π r² "%.1f" + m, or Target for a unit spell, flag); Duration
## (Immediately below 2 ticks, else ticks / 15 "%.1f" + s), Targets — the
## camp's spell rows (CampView), here in pairs (spell_rows
## rows, which the spell column shows).
##  (labels infoitem_7..13, 21, 22, 26..28): a
## potion shows only Effect and Duration (`potion_rows`); a wand the rows above
## with "%s %d/%d (%d)" infoitem_7, spell, item (Energy), item
##  (its charge) in place of Stamina / School.
##  restores an unpicked cell to scale 0.55 / 0.85 immediately.
## Each wand's charge rides on
## its item string (`Items.charge`), so two identical wands keep their own.

const SLOTS := 8
var game: Game
var _items: Array = []
var _sig := ""
var _views: Array[ItemView] = []
var _unit: GameUnit
var _held := -1          # cell the press captured the mouse
var _held_double := false  # that press was a double click (manager)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	for i in SLOTS:
		var v := ItemView.new()
		v.belt = true
		add_child(v)
		_views.append(v)


## from the bottom right cell leftwards, then the top row.
func _cell_rect(i: int) -> Rect2:
	var c := size / Vector2(4, 2)
	return Rect2(Vector2((3 - i % 4) * c.x, (1 - i / 4) * c.y), c)


func _has_point(p: Vector2) -> bool:
	return _slot_at(p) >= 0


func _process(_dt: float) -> void:
	var u: GameUnit = game.selected[0] if game and not game.selected.is_empty() and is_instance_valid(game.selected[0]) else null
	var q: Array = u.get_meta("hero").get("quick", []) if u and u.has_meta("hero") else []
	var items := ["", "", "", "", "", "", "", ""]
	for i in mini(q.size(), 4):
		items[i] = q[i]
	if u and u.has_meta("hero") and not u.get_meta("hero").has("merc") and u.controller == game.session.my_index:
		var quest: Array = game.session.state.quest_items.keys() if game.session.lmp.is_empty() \
			else game.session.coop.owner_bag(game.session.my_index).filter(func(it): return Items.kind(String(it)) == "quest")
		for i in mini(quest.size(), 4):
			items[4 + i] = quest[i]
	# The unit's instance, not its uid: after a reload the party is new units
	# with the same uids (see SpellSlots._process).
	var inspected := game.hud.inspected_quest_item() if game and game.hud else ""
	var sig := "%s:%s:%s:%s:%s" % [u.get_instance_id() if u else 0, ",".join(items), size, game.pending_spell, inspected]
	if sig == _sig:
		return
	_sig = sig
	_unit = u
	_items = items
	var k := size.y / 100.0   # pixels per 800×600 unit
	for i in SLOTS:
		var r := _cell_rect(i)
		var picked: bool = not _items[i].is_empty() and (game.pending_spell == "%s%d:%s" % [Game.BELT, u.uid if u else -1, _items[i]] \
			if i < 4 else inspected == _items[i])
		# the bottom row is 0.55 / 0.65, the top 0.85 / 1.0.
		# Unclipped: the view is twice the cell.
		var sc := (0.65 if picked else 0.55) if i < 4 else (1.0 if picked else 0.85)
		_views[i].position = r.get_center() - r.size
		_views[i].size = r.size * 2.0
		_views[i].unit_px = k * 400.0 / ItemView.K * sc / 20.0
		_views[i].screen_at = Vector3(695.0 - 50.0 * (i % 4), 575.0 if i < 4 else 525.0, 20.0 / sc)
		_views[i].add_color = Color8(0x40, 0x40, 0x40) if picked else Color(0, 0, 0)
		_views[i].visible = not _items[i].is_empty()
		_views[i].item = "~"
		_views[i].show_item(_items[i])
	queue_redraw()


func _slot_at(p: Vector2) -> int:
	for i in _items.size():
		if not _items[i].is_empty() and _cell_rect(i).has_point(p):
			return i
	return -1


func _get_tooltip(p: Vector2) -> String:
	var i := _slot_at(p)
	# hotkey 0x2a + slot (item1..4; slots 5..8 carry 0x2e..0x31).
	if i < 0:
		return ""
	var it := String(_items[i])
	if i >= 4:   # quest items have a name, no consumable hotkey
		return Items.title(it) + "\n" + RemakeText.t("Inspect")
	return GameData.tip_key(tooltip_text(it), 42 + i)


static func tooltip_text(item: String, charge := -1.0) -> String:
	var t := Items.title(item)
	var sp := Items.potion_spell(item)
	if not sp.is_empty():
		return potion_rows(t, sp)
	sp = Items.spell_of(item)
	var out := spell_rows(t, sp)
	if Items.is_wand(item) and not sp.is_empty() and GameData.is_open():
		# "%s %d/%d (%d)" infoitem_7, the spell's stamina
		# the wand's Energy and its charge, in place
		# Stamina / School.
		var e := Items.energy(item)
		var rows := out.split("\n")
		rows[1] = "%s %d/%d (%d)" % [_l(7), int(Spells.parse(sp).mana), int(e), int(Items.charge(item) if charge < 0.0 else charge)]
		out = "\n".join(rows)
	return out


##  for a potion (prototype item_id 8): the name, " \n", then
## Effect ("%s %s" Constant without effect runes, else "%s %d") and
## Duration (Immediately below 2 ticks, else ticks / 15 "%.1f" + s), one a line.
static func potion_rows(title: String, sp: String) -> String:
	if sp.is_empty() or not GameData.is_open():
		return title
	var pp := Spells.parse(sp)
	var mods: Array = Array(pp.proto.get("mods", []))
	var effect := "%s %s" % [_l(8), _l(28)] if mods.size() > 3 and int(mods[3]) == 0 else "%s %d" % [_l(8), int(pp.effect)]
	var d := float(pp.duration)
	var dur := "%s %s" % [_l(12), _l(21)] if d < 2.0 else "%s %.1f%s" % [_l(12), d / 15.0, _l(27)]
	return "%s\n%s\n%s" % [title, effect, dur]


## `title`, then the spell rows two per line (empty spell or
## no game data: the title alone).
static func spell_rows(title: String, sp: String) -> String:
	if sp.is_empty() or not GameData.is_open():
		return title
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
	return title + "\n" + "\n".join(lines)


## "string school_N", "Unknown" when missing (default).
static func _school(pp: Dictionary) -> String:
	var t := GameData.text("string school_%d" % int(pp.proto.get("type_id", 0))).strip_edges()
	return t if t else "Unknown"


static func _l(n: int) -> String:
	return GameData.text("string infoitem_%d" % n).strip_edges()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			# a filled cell captures the mouse.
			_held = _slot_at(e.position)
			_held_double = e.double_click
		elif _held >= 0:
			# the cell under the release acts.
			_held = -1
			var i := _slot_at(e.position)
			if i >= 0:
				use(i, _held_double)
		accept_event()


##  (now = false: pick for targeting, again cancels)
##  (now = true: use at once) for cell i.
func use(i: int, now: bool) -> void:
	_process(0.0)
	if i < 0 or i >= _items.size() or _items[i].is_empty() or _unit == null:
		return
	if i >= 4:
		game.hud.inspect_quest_item(String(_items[i]))
		return
	game.touch_aim = -1
	game.touch_force = ""
	if now:
		#  clears targeting even when no hostile target exists.
		game.pending_spell = ""
		game.hud.set_targeting("")
	if now and _no_target(_items[i]):
		# An offensive spell item with no hostile unit in view
		#  sounds nomagic.wav and is not used.
		if GameSound.instance:
			GameSound.instance.ui("buttons\\battle\\nomagic.wav")
		return
	if GameSound.instance:
		GameSound.instance.ui("buttons\\battle\\click.wav")
	if now:
		game.issue({"t": "use", "unit": _unit.uid, "item": _items[i]})
	else:
		var item := String(_items[i])
		var kind := int(Items.info(item).get("row", {}).get("item_id", -1))
		if kind != 5 and kind != 8:
			return
		#  leaves mode 0 for a wand/potion without a spell.
		var sp := Items.spell_of(item) if kind == 5 else Items.potion_spell(item)
		if sp.is_empty():
			game.pending_spell = ""
			game.hud.set_targeting("")
		else:
			game.begin_belt(_unit, item)
	queue_redraw()


func _no_target(item: String) -> bool:
	var sp := Items.potion_spell(item)
	if sp.is_empty():
		sp = Items.spell_of(item)
	return not sp.is_empty() and Spells.offensive(sp) and game.world \
		and game.session.belt_enemy(_unit) == null


## No cell frames: only makes the hit rectangles; the items are
## their 3D models.
func _draw() -> void:
	pass
