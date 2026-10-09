class_name SpellSlots
extends Control
## The hero's spells in the column on the right edge (the original
## builds it at (760,190)-(800,510) of the 800×600 layout, fills
## it, adds a cell): one 40×40 cell per spell (—
## for a hero the player's list, up to eight, else unit [0..7])
## centred at x 780; each new cell goes in at the bottom (centre y 490) and
## pushes the earlier ones up 40, so with n spells spell i sits at
## 470 − 40 (n − 1 − i) .. 510 − 40 (n − 1 − i): the first at the top, the
## last at the bottom. A spell shows its textures.res "spell%04d" picture
## (prototype texture_type). (The bottom-right 4 × 2 cells
##  are the belt's quick items, BeltStrip.)
## Keys spell1–8 (1–8, cases 0x1e–0x25) and a click
## — click.wav, the cell is picked (scale 1.15
## ) and the next click in the world picks the target
## (interaction mode 1 for a unit spell, flag, else 2); the picked
## cell again cancels. Ctrl / Alt + key, or a double click: —
## cast at once: an offensive spell on the nearest hostile unit
## in view (none: nomagic.wav, nothing cast), any other on the
## caster; a unit spell on that unit, a point spell at its
## position.
## Tooltip (labels infoitem 7, 18, 8, 9, 10, 11, 12, 13, 21
## 22, 26, 27, 28): the name, then the spell
## rows two per line (BeltStrip.spell_rows).
## The picked cell's is the add colour (as ItemView's): 0x40 added to
## each channel of its picture (`_glow`, an additive pass over the picture's
## alpha); unpicked, nothing added.

const SLOTS := 8
var game: Game
var _entries: Array = []   # [spell id, index]
var _sig := ""
var _unit: GameUnit
var _held := -1          # cell the press captured the mouse
var _held_double := false  # that press was a double click (manager)
var _first := 0
var _usable: Array[bool] = []


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


## Keep duplicates and order: these are the runes installed in this spell,
## not the modifier types allowed by its prototype. Reuse the original art.
static func rune_icons(spell: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for code: String in Spells.mods_of(spell).slice(0, Spells.MAX_MODS):
		var name := String(Items.look("rune:" + code).get("texture", ""))
		out.append(icon(name) if not name.is_empty() else null)
	return out


## A compact strip along the lower edge preserves the full-colour spell art.
## Two rows keep eight installed runes readable even in the small HUD slots.
static func draw_runes(canvas: CanvasItem, spell: String, rect: Rect2, tint := Color.WHITE, columns := 4) -> void:
	var runes := rune_icons(spell)
	if runes.is_empty():
		return
	var side := rect.size.x / float(maxi(5, columns))
	var cols := mini(columns, runes.size())
	var rows := ceili(runes.size() / float(columns))
	var origin := Vector2(rect.end.x - cols * side, rect.end.y - rows * side)
	for i in runes.size():
		var cell := Rect2(origin + Vector2(i % columns, i / columns) * side, Vector2.ONE * side)
		canvas.draw_rect(cell, Color(0.03, 0.03, 0.04, 0.85))
		if runes[i]:
			canvas.draw_texture_rect(runes[i], cell.grow(-side * 0.07), false, tint)


## Additive pass for the picked cell: + (0x40, 0x40, 0x40) where the picture is.
var _glow: Control
var _glow_rect := Rect2()
var _glow_tex: Texture2D
const _GLOW_SHADER := """
shader_type canvas_item;
render_mode blend_add;
void fragment() {
	COLOR = vec4(vec3(64.0 / 255.0) * texture(TEXTURE, UV).a, 1.0);
}
"""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_glow = Control.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = _GLOW_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	_glow.material = m
	_glow.draw.connect(func():
		if _glow_tex:
			_glow.draw_texture_rect(_glow_tex, _glow_rect, false))
	add_child(_glow)
	resized.connect(func(): _sig = "")


## cell i of n at y 470 − 40 (n − 1 − i) (800×600; the control
## spans 190..510, so the bottom cell ends at its bottom edge).
func _cell_rect(i: int) -> Rect2:
	var w := size.x
	if TouchInput.enabled:
		var h := _cell_height()
		return Rect2(Vector2(0, size.y - mini(_entries.size(), _capacity()) * h + (i - _first) * h), Vector2(w, h))
	return Rect2(Vector2(0, size.y - (_entries.size() - i) * w), Vector2(w, w))

func _cell_height() -> float:
	var scale := get_global_transform_with_canvas().get_scale()
	return size.x * scale.x / maxf(scale.y, 0.01)

func _capacity() -> int:
	return maxi(1, int(size.y / maxf(_cell_height(), 1.0)))

func touch_scroll(_point: Vector2, delta: Vector2) -> void:
	_first = clampi(_first + (1 if delta.y < 0 else -1), 0, maxi(0, _entries.size() - _capacity()))
	queue_redraw()


func _has_point(p: Vector2) -> bool:
	return _slot_at(p) >= 0


func _process(_dt: float) -> void:
	var u: GameUnit = game.selected[0] if game and not game.selected.is_empty() and is_instance_valid(game.selected[0]) else null
	var h: Dictionary = u.get_meta("hero") if u and u.has_meta("hero") else {}
	var spells: Array = h.get("spells", [])
	_usable.clear()
	for i in mini(spells.size(), SLOTS):
		_usable.append(Spells.known_usable(u, String(spells[i])))
	# The unit's instance, not its uid: a reload (Session.load_game) builds the
	# party anew with the same uids, and _unit must not stay the freed one.
	var sig := "%s:%s:%s:%s:%s" % [u.get_instance_id() if u else 0, ",".join(spells), size, game.pending_spell, _usable]
	if sig == _sig:
		return
	_sig = sig
	_unit = u
	_entries.clear()
	for i in mini(spells.size(), SLOTS):
		_entries.append([spells[i], i])
	_first = clampi(_first, 0, maxi(0, _entries.size() - _capacity()))
	queue_redraw()


func _slot_at(p: Vector2) -> int:
	for i in _entries.size():
		if TouchInput.enabled and (i < _first or i >= _first + _capacity()): continue
		if _cell_rect(i).has_point(p):
			return i
	return -1


func _get_tooltip(p: Vector2) -> String:
	var i := _slot_at(p)
	if i < 0:
		return ""
	var spell := String(_entries[i][0])
	# hotkey 0x1e + slot (spell1..8).
	var tip := GameData.tip_key(BeltStrip.spell_rows(Spells.title(spell), spell), 30 + i)
	return tip if _usable[i] else tip + "\n" + RemakeText.t("Spell requirements are not met.")


## Acts on the release over a cell, as BeltStrip (
## capture, acts on the cell under the release).
func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_held = _slot_at(ev.position)
			_held_double = ev.double_click
		elif _held >= 0:
			_held = -1
			var i := _slot_at(ev.position)
			if i >= 0:
				use(i, _held_double)
		accept_event()


##  (now = false) / (now = true) for cell i.
func use(i: int, now: bool) -> void:
	_process(0.0)
	if i < 0 or i >= _entries.size() or _unit == null or game == null:
		return
	var sp: String = _entries[i][0]
	if not Spells.known_usable(_unit, sp):
		_sound("buttons\\battle\\nomagic.wav")
		return
	game.touch_aim = -1
	game.touch_force = ""
	if now:
		var t: GameUnit = _unit
		if Spells.offensive(sp):
			t = game.session.belt_enemy(_unit) if game.world else null
			if t == null:
				_sound("buttons\\battle\\nomagic.wav")
				return
		_sound("buttons\\battle\\click.wav")
		game.pending_spell = ""
		game.hud.set_targeting("")
		var cmd := {"t": "cast", "unit": _unit.uid, "spell": sp}
		if int(Spells.parse(sp).flags) & 0x10000000:
			cmd.target = t.uid
		else:
			cmd.x = t.pos.x
			cmd.y = t.pos.y
		game.issue(cmd)
		return
	_sound("buttons\\battle\\click.wav")
	if game.pending_spell == sp:
		game.pending_spell = ""
		game.hud.set_targeting("")
	else:
		game.begin_cast(_entries[i][1])


func _sound(f: String) -> void:
	if GameSound.instance:
		GameSound.instance.ui(f)


func _draw() -> void:
	# No cell frames or key numbers: only makes the hit
	# rectangles; a cell shows just its spell picture.
	_glow_tex = null
	for i in _entries.size():
		if TouchInput.enabled and (i < _first or i >= _first + _capacity()): continue
		var r := _cell_rect(i).grow(-2)
		var e: Array = _entries[i]
		if game and game.pending_spell == String(e[0]):
			r = r.grow(r.size.x * 0.075)   # the picked cell scaled 1.15
		var t := int(Spells.parse(e[0]).proto.get("texture_type", -1))
		var tex := icon("spell%04d" % t) if t >= 0 else null
		if tex:
			draw_texture_rect(tex, r, false, Color.WHITE if _usable[i] else Color(0.4, 0.4, 0.4))
			if _usable[i] and game and game.pending_spell == String(e[0]):
				_glow_tex = tex
				_glow_rect = r
		draw_runes(self, String(e[0]), r, Color.WHITE if _usable[i] else Color(0.4, 0.4, 0.4))
	_glow.queue_redraw()
	if TouchInput.enabled and _entries.size() > _capacity():
		var x := size.x * 0.5
		if _first > 0:
			draw_colored_polygon(PackedVector2Array([Vector2(x - 4, 5), Vector2(x, 1), Vector2(x + 4, 5)]), Interface800.TEXT)
		if _first + _capacity() < _entries.size():
			draw_colored_polygon(PackedVector2Array([Vector2(x - 4, size.y - 5), Vector2(x, size.y - 1), Vector2(x + 4, size.y - 5)]), Interface800.TEXT)
