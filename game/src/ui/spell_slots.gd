class_name SpellSlots
extends Control
## Spell slots bottom right (the original): eight 50×50 cells
## 520..720 × 500..600 of the 800×600 layout, filled from the bottom right
## cell leftwards, then the top row; tooltips with the spell fields
## (texts.res "string infoitem_7 / 18 / 8 / 9 / 10 ..."). Spells show their
## textures.res "spell%04d" picture (prototype texture_type)
## left click starts the cast (Game.begin_cast). Belt items are in BeltStrip.
## Tooltip (labels infoitem 7, 8, 9, 10, 11, 12, 13, 21, 22
## 26, 27, 28): the slot's entry is — for a
## hero the player's list (count ≥ 1), else unit — named
## . Rows follow only for quick items by their prototype
## item_id (proto): 5 (wands) "%s %d/%d (%d)" and the
## spell rows as the belt's, 8 (potions) Effect and Duration. A spell (class
## 0x3008, =) shows its name alone: the first line
## texts "spell <prototype code>" (no rune list).

const SLOTS := 8
var game: Game
var _entries: Array = []   # [spell id, index]
var _sig := ""
var _unit: GameUnit


static var _icons := {}


## A textures.res HUD picture (spell%04d, skill%04d) the right way up: like the
## other 2D pictures they come out of EIMmp upside down against the original's UVs
## (see CampView, HudDial), so they are flipped once and cached.
static func icon(name: String) -> Texture2D:
	if not _icons.has(name):
		var img := GameData.load_image(name) if GameData.is_open() else null
		var tex: Texture2D = null
		if img:
			img.flip_y()
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
		_icons[name] = tex
	return _icons[name]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(func(): _sig = "")


func _cell_rect(i: int) -> Rect2:
	var c := size / Vector2(4, 2)
	var col := 3 - i % 4
	var row := 1 - i / 4
	return Rect2(Vector2(col * c.x, row * c.y), c)


func _process(_dt: float) -> void:
	var u: GameUnit = game.selected[0] if game and not game.selected.is_empty() and is_instance_valid(game.selected[0]) else null
	var h: Dictionary = u.get_meta("hero") if u and u.has_meta("hero") else {}
	var spells: Array = h.get("spells", [])
	var sig := "%s:%s" % [u.uid if u else -1, ",".join(spells)]
	if sig == _sig:
		return
	_sig = sig
	_unit = u
	_entries.clear()
	for i in mini(spells.size(), SLOTS):
		_entries.append([spells[i], i])
	queue_redraw()


func _slot_at(p: Vector2) -> int:
	for i in _entries.size():
		if _cell_rect(i).has_point(p):
			return i
	return -1


func _get_tooltip(p: Vector2) -> String:
	var i := _slot_at(p)
	if i < 0:
		return ""
	var e: Array = _entries[i]
	var sp := Spells.parse(e[0])
	var t := GameData.text("spell " + String(sp.code)).get_slice("\n", 0).strip_edges()
	return t if t else String(sp.name)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var i := _slot_at(ev.position)
		if i < 0 or _unit == null:
			return
		if GameSound.instance:   #  (nomagic.wav belongs to the item slots)
			GameSound.instance.ui("buttons\\battle\\click.wav")
		game.begin_cast(_entries[i][1])
		accept_event()


func _draw() -> void:
	# No cell frames or key numbers: only makes the 50×50 hit
	# rectangles; a slot shows just its spell picture.
	for i in SLOTS:
		var r := _cell_rect(i).grow(-2)
		if i >= _entries.size():
			continue
		var e: Array = _entries[i]
		var t := int(Spells.parse(e[0]).proto.get("texture_type", -1))
		var tex := icon("spell%04d" % t) if t >= 0 else null
		if tex:
			draw_texture_rect(tex, r.grow(-2), false)
