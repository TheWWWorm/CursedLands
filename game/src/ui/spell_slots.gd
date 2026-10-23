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
		var key := "rune:" + name
		if not _icons.has(key):
			var index := name.trim_prefix("modifier").to_int()
			var atlas := icon("modifiers2")
			if atlas and name.begins_with("modifier") and index >= 0 and index < 28:
				var glyph := AtlasTexture.new()
				glyph.atlas = atlas
				var cell := atlas.get_width() / 8.0
				glyph.region = Rect2(Vector2(index % 8, index / 8) * cell, Vector2.ONE * cell)
				glyph.filter_clip = true
				_icons[key] = glyph
			else:
				_icons[key] = icon(name) if not name.is_empty() else null
		out.append(_icons[key])
	return out


## Clockwise around the picture, beginning at the top centre, leaving its
## centre visible even with all eight inscriptions installed.
const RUNE_CENTRES := [Vector2(0.5, 0.16), Vector2(0.84, 0.16),
	Vector2(0.84, 0.5), Vector2(0.84, 0.84), Vector2(0.5, 0.84),
	Vector2(0.16, 0.84), Vector2(0.16, 0.5), Vector2(0.16, 0.16)]


static func ring_rune_rects(rect: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var side := minf(rect.size.x, rect.size.y) / 6.0
	for centre: Vector2 in RUNE_CENTRES:
		out.append(Rect2(rect.position + rect.size * centre - Vector2.ONE * side * 0.5, Vector2.ONE * side))
	return out


## The compact layout remains the default. Shop callers reserve room for a
## stack count; world spell slots keep their centred, four-column cluster.
static func rune_rects(rect: Rect2, count := Spells.MAX_MODS, top_left_width := -1.0) -> Array[Rect2]:
	if GameData.option("original_rune_layout") != 0:
		return ring_rune_rects(rect)
	var out: Array[Rect2] = []
	count = clampi(count, 0, Spells.MAX_MODS)
	if count == 0:
		return out
	var cols := mini(4, count)
	var side := rect.size.x / 6.0
	var inset := rect.size * 0.10
	var origin := Vector2(rect.get_center().x - cols * side * 0.5, rect.position.y + rect.size.y * 0.04)
	if top_left_width >= 0.0:
		side = minf(side, maxf(0.0, top_left_width - inset.x) / cols)
		origin = rect.position + inset
	for i in count:
		out.append(Rect2(origin + Vector2(i % 4, i / 4) * side, Vector2.ONE * side))
	return out


## Original camp item renderer 005eca10: the model scale is slot_width *
## 0.48157462 * 0.0009375, the rune offset is scale * 550, and its 35/100
## quad is projected at depth * 0.9. This gives a 24.8312 px radius and
## 14.5833 px glyph in a 100 px slot. Do not scale these from the artwork.
static func camp_rune_rects(slot: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var radius := slot.size.x * (0.48157462 * 0.0009375 * 550.0)
	var side := slot.size.x * (0.35 * 0.0009375 / (0.9 * 0.0025))
	for direction: Vector2 in [Vector2(0, -1), Vector2(1, -1), Vector2(1, 0),
			Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1)]:
		out.append(Rect2(slot.get_center() + direction * radius - Vector2.ONE * side * 0.5, Vector2.ONE * side))
	return out


static func draw_runes(canvas: CanvasItem, spell: String, rect: Rect2, tint := Color.WHITE,
		cells: Array[Rect2] = []) -> void:
	var runes := rune_icons(spell)
	if cells.is_empty():
		cells = rune_rects(rect, runes.size())
	for i in mini(runes.size(), cells.size()):
		if runes[i]:
			canvas.draw_texture_rect(runes[i], cells[i], false, tint)


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
	var sig := "%s:%s:%s:%s:%s:%s:%d" % [u.get_instance_id() if u else 0, ",".join(spells), size, game.pending_spell, _usable, shortcut_label(0), GameData.option("original_rune_layout")]
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
		# Remake: say why (the spell is dimmed until the hero can use it).
		if game.hud and _unit.has_meta("hero"):
			var lack := Spells.unmet(_unit.get_meta("hero"), _unit.max_mana, sp)
			lack.insert(0, "%s: %s" % [Spells.title(sp), RemakeText.t("Spell requirements are not met.")])
			game.hud.log_msg(" ".join(lack), Interface800.TEXT)
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
	# Direct views keep the assigned shortcut visible while the mouse looks.
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
		var shortcut := shortcut_label(i)
		if not shortcut.is_empty():
			var font := Interface800.font()
			var fs := maxi(12, roundi(r.size.y * 0.34))
			var width := font.get_string_size(shortcut, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var badge := Rect2(r.position, Vector2(width + 6, fs + 4))
			draw_rect(badge, Color(0,0,0,0.85))
			draw_string(font, badge.position + Vector2(3,fs), shortcut, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Interface800.TEXT)

	_glow.queue_redraw()
	if TouchInput.enabled and _entries.size() > _capacity():
		# The scroll bar's own arrows (Interface800.vbar), 10 × 12 at 40 per cell.
		var bar := Interface800.tex("Scrollbar")
		var k := size.x / 40.0
		var a := Vector2(10, 12) * k
		var x := (size.x - a.x) * 0.5
		if bar and _first > 0:
			_scroll_arrow(bar, Rect2(Vector2(x, 0), a), 176.0, 128.0)
		if bar and _first + _capacity() < _entries.size():
			_scroll_arrow(bar, Rect2(Vector2(x, size.y - a.y), a), 128.0, 176.0)


## A scroll bar arrow (UV x 40..80, v from `v0` at the top to `v1`).
func _scroll_arrow(t: Texture2D, r: Rect2, v0: float, v1: float) -> void:
	var uv0 := Vector2(40, v0) / 256.0
	var uv1 := Vector2(80, v1) / 256.0
	draw_primitive(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]),
		PackedVector2Array([uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y)]), t)


func shortcut_label(index: int) -> String:
	return EIKeymap.key_of_id(30 + index) if game and game.direct and game.direct.active() else ""


func wiki_context() -> Dictionary:
	var i := _slot_at(get_local_mouse_position())
	return {"item": "spell:" + String(_entries[i][0])} if i >= 0 else {}
