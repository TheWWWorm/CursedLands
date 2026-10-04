class_name ActionStrip
extends Control
## Left action strip of the battle HUD (the original
## ): six 40×40 hit cells (0, y)-(40, y + 40), y = 470, 430, …
## of the 800×600 layout (widget (0,250)-(40,510)). counts the
## selected units with flag 0x10: exactly one, whose returns 0
## (unit, 1); otherwise (0, count > 0). So
##  adds, bottom up:
## - with its second argument: Follow, textures.res "skill0011", tip 10510
##   (0x290e) — the next clicked unit is followed by the selection;
## - with a unit: Use/Steal, "skill0009", tip "<perk Science> <level>" + tip
##   10511 (keyboard.ini use_science).
## One selected hero therefore shows both cells (Follow at 470..510, Use/Steal
## above it), several units Follow only.
## Each cell is the figure figures.res "initqi1item" (a bevelled tile: outer
## square ±0.8922 at z 0, raised inner face ±0.8456 at z −0.0624, UVs
## u = (0.8922 − x) / 7.137, v 0.75..1) with the 64×64 picture copied into the
## widget's atlas, turned π about z, placed
## (20, 490 − 40 i, 40) at scale 1.0, white
## perspective as every HUD figure (K = 0.48157462). A click
## (buttons\battle\click.wav) selects the cell:
## scale 1.15 and (vertex specular: 0x40 added); clicking it
## again cancels. No hover or animation.
## Unlit, confirmed: the cell build = and flag 0x100
## so writes white to every
## vertex — texture × white.
## Vtable is the unit's dead test (0 = alive; and the
## other callers), so the unit cells need exactly one selected living unit.
## **Approx.**: the remake also requires it to be a hero (its science level
## comes from the hero record; summoned units have none).

const FIG_OUT := 0.8922
const FIG_IN := 0.8456
const FIG_Z := -0.0624
const K := 0.48157462
const Z := 40.0
## initqi1item's eight corners (x, y, z) and their picture coordinates
## (U = u / 0.25, V = (v − 0.75) / 0.25 of the stored image).
const VERTS := [
	[-FIG_OUT, -FIG_OUT, 0.0, 1.0, 0.0], [-FIG_OUT, FIG_OUT, 0.0, 1.0, 1.0],
	[-FIG_IN, -FIG_IN, FIG_Z, 0.96408, 0.03592], [-FIG_IN, FIG_IN, FIG_Z, 0.96408, 0.96408],
	[FIG_OUT, -FIG_OUT, 0.0, 0.0, 0.0], [FIG_IN, -FIG_IN, FIG_Z, 0.03592, 0.03592],
	[FIG_OUT, FIG_OUT, 0.0, 0.0, 1.0], [FIG_IN, FIG_IN, FIG_Z, 0.03592, 0.96408]]
const TRIS := [0, 1, 2, 3, 2, 1, 4, 0, 5, 2, 5, 0, 6, 4, 7, 5, 7, 4, 1, 6, 3, 7, 3, 6, 3, 7, 2, 7, 5, 2]

var game: Game
var _cells: Array = []   # "follow" / "science", bottom up
var _sel := ""
var _held := -1   # cell the press captured the mouse
var _glow: Control       # the selected cell's add (blend add)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_glow = Control.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nrender_mode blend_add;\nvoid fragment() { COLOR = vec4(vec3(64.0 / 255.0), step(0.5, texture(TEXTURE, UV).a)); }\n"
	var m := ShaderMaterial.new()
	m.shader = sh
	_glow.material = m
	_glow.draw.connect(_draw_glow)
	add_child(_glow)


func _process(_dt: float) -> void:
	var units: Array = game.selected.filter(func(x): return is_instance_valid(x)) if game else []
	var cells := []
	if units.size() == 1 and (units[0] as GameUnit).has_meta("hero"):
		cells = ["follow", "science"]
	elif not units.is_empty():
		cells = ["follow"]
	var sel := ""
	if game:
		sel = "follow" if game.pending_spell == Game.FOLLOW else ("science" if game.pending_spell == Game.SCIENCE else "")
	if cells != _cells or sel != _sel:
		_cells = cells
		_sel = sel
		queue_redraw()
		_glow.queue_redraw()


func _hero() -> GameUnit:
	if game == null or game.selected.is_empty() or not is_instance_valid(game.selected[0]):
		return null
	var u: GameUnit = game.selected[0]
	return u if u.has_meta("hero") and not u.dead else null


## Local pixels per 800×600 unit (the widget is 40 wide).
func _k() -> float:
	return size.x / 40.0


## 800×600 point -> local (the widget's bottom is y 510; its top, y 250 in
## the original layout, is lower on a portrait phone, GameHUD._layout_dials).
func _p(v: Vector2) -> Vector2:
	return (v - Vector2(0, 510)) * _k() + Vector2(0, size.y)


func _cell_at(p: Vector2) -> int:
	var q := (p - Vector2(0, size.y)) / _k() + Vector2(0, 510)
	if q.x < 0.0 or q.x >= 40.0:
		return -1
	var i := int(floor((510.0 - q.y) / 40.0))
	return i if i >= 0 and i < _cells.size() else -1


func _has_point(p: Vector2) -> bool:
	return _cell_at(p) >= 0


func _get_tooltip(p: Vector2) -> String:
	var i := _cell_at(p)
	if i < 0:
		return ""
	if _cells[i] == "follow":
		return GameData.tip_key(GameData.text("tip 10510").strip_edges(), 28)
	var u := _hero()
	if u == null:
		return ""
	return GameData.tip_key("%s %d\n%s" % [Skills.title("science"), Skills.level(u.get_meta("hero"), "science"),
		GameData.text("tip 10511").strip_edges()], 29)   #  hotkey 0x1d


## Acts on the release over a cell, as BeltStrip: captures
##  for the cell under the release.
func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_held = _cell_at(e.position)
			if _held >= 0:
				accept_event()
			return
		if _held < 0:
			return
		_held = -1
		var i := _cell_at(e.position)
		if i < 0:
			accept_event()
			return
		if GameSound.instance:
			GameSound.instance.ui("buttons\\battle\\click.wav")
		if _cells[i] == _sel:   # the same cell again cancels
			game.pending_spell = ""
			game.hud.set_targeting("")
		else:
			game._key_action("follow" if _cells[i] == "follow" else "use_science")
		accept_event()


## Cell i's plate: the projected triangles and picture coordinates.
func _plate(i: int) -> Array:
	var s := 1.15 if _cells[i] == _sel else 1.0
	var sx := 20.0
	var sy := 490.0 - 40.0 * i
	var cam := Vector2((sx * 0.0025 - 1.0) * K * Z, (sy * 0.0025 - 0.75) * K * Z)
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for t: int in TRIS:
		var v: Array = VERTS[t]
		# Turned π about z: (x, y) -> (−x, −y).
		var c := cam + Vector2(-float(v[0]), -float(v[1])) * s
		var z := Z + float(v[2]) * s
		pts.append(_p(Vector2(400.0 + 400.0 * c.x / (z * K), 300.0 + 400.0 * c.y / (z * K))))
		uvs.append(Vector2(float(v[3]), 1.0 - float(v[4])))   # the icon texture is flipped
	return [pts, uvs]


func _draw() -> void:
	for i in _cells.size():
		var tex := SpellSlots.icon("skill0011" if _cells[i] == "follow" else "skill0009")
		if tex == null:
			continue
		var pl := _plate(i)
		var cols := PackedColorArray()
		cols.resize(pl[0].size())
		cols.fill(Color.WHITE)
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), pl[0], cols, pl[1],
			PackedInt32Array(), PackedFloat32Array(), tex.get_rid())


func _draw_glow() -> void:
	var i := _cells.find(_sel) if _sel else -1
	if i < 0:
		return
	var tex := SpellSlots.icon("skill0011" if _sel == "follow" else "skill0009")
	if tex == null:
		return
	var pl := _plate(i)
	var cols := PackedColorArray()
	cols.resize(pl[0].size())
	cols.fill(Color.WHITE)
	RenderingServer.canvas_item_add_triangle_array(_glow.get_canvas_item(), PackedInt32Array(), pl[0], cols, pl[1],
		PackedInt32Array(), PackedFloat32Array(), tex.get_rid())
