class_name FlyingHP
extends Control
## Floating hit numbers, option "show_flying_hp" (DrawFlyingHP, settings
## ). the original CFlyingHitPoints (map, created
## with textures.res "numbers"; add, draw from the
## map draw):
## - Entries {unit id, number, flags, start time}; flag 8 (experience) starts
##   500 ms late. An entry lives 3000 ms; t = age / 3000.
## - Hits: (unit state update) compares the unit's health
##   fraction before / after: when it dropped, or the "struck" bit (0x10) is
##   set, the logic object's (units
##   only) adds trunc((before - after) x max HP) — so a blow that takes no
##   health shows "0" — with flags 1 (unit bit 1) and 2 (bit 2).
##   Experience: net handlers add the gain with
##   flag 8 over each hero.
## - Text "%d" in 8 x 12 px glyphs from "numbers" (16 x 20 texel cells, digit
##   d at column d & 3, row d >> 2 from the top of the picture); below it one
##   64 x 10 px label line per flag from the same texture (full width, 19
##   texel rows): 1 "BACKSTAB" (Russian install: "СО СПИНЫ"), 2 "CRITICAL"
##   ("В ГОЛОВУ"), 8 "EXP" ("ОПЫТ"). The block (width max(8 n, 64 with a
##   label), height 12 + 10 per label) is centred on the anchor + (120 t,
##   −100 t) px, colour alpha 255 (1 − t): for experience
##   over a party unit (unit), else. Drawn only when the whole
##   block is on screen and the unit is shown (flags 0x20, not 0x40).
## - Anchor: the screen rectangle centre of the unit's "hd" part (else "bd",
##   "hp") when that part has its own rectangle (flag 0x40), else of the unit.
## Remake: pixel sizes are of the 800 x 600 layout, scaled by the window
## height / 600. Hits come from the host as "hitnum" events (GameUnit.
## take_damage, Session.give_experience), so co-op clients show them too.
## - Flags: unit (packed byte, from server stats) is set
##   while the server applies a hit: 1 when the backstab
##   multiplier (record) is not 1.0, 2 when the struck
##   part (record) is 0, the head; 4 (electrical damage) is not drawn.
## **Approx.**: the anchor is the first of the "hd" / "bd" / "hp" parts'
## origin (takes the centre of that part's screen rectangle, or
## of the figure's when the part has none; how those rectangles are filled is
## not traced); a unit with none of the parts gets no number, as in the original.
## The original's flag entry (yellow "!!!", 32 x 10 px, no motion
## deleted after one draw) has no known source and is not used.

const LIFE := 3.0
const EXP_DELAY := 0.5
const GREEN := Color8(0x40, 0xff, 0x40)
const RED := Color8(0xff, 0x40, 0x40)
const CYAN := Color8(0x40, 0xff, 0xff)
## Label rows of the flipped picture: flag -> texel rows y0, y1.
const LABELS := [[1, 59.0, 78.0], [2, 78.0, 97.0], [8, 97.0, 116.0]]

var game: Game
var _tex: Texture2D
var _items := []   # {uid, n, f, t0}


## The node of a game (created on first use, on a canvas layer below the HUD).
static func of(g: Game) -> FlyingHP:
	var layer := g.get_node_or_null("FlyingHPLayer") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "FlyingHPLayer"
		layer.layer = -1
		var f := FlyingHP.new()
		f.name = "FlyingHP"
		f.game = g
		layer.add_child(f)
		g.add_child(layer)
	return layer.get_node("FlyingHP") as FlyingHP


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var img := GameData.load_image("numbers") if GameData.is_open() else null
	if img:
		img.flip_y()   # stored bottom-up; the original's v runs from the bottom
		_tex = ImageTexture.create_from_image(img)


## A "hitnum" event: {uid, n (number), f (flags)}.
func add(e: Dictionary) -> void:
	if not GameData.option("show_flying_hp"):
		return
	var f := int(e.get("f", 0))
	_items.append({"uid": int(e.uid), "n": maxi(int(e.get("n", 0)), 0), "f": f,
		"t0": Time.get_ticks_msec() / 1000.0 + (EXP_DELAY if f & 8 else 0.0)})


func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_items = _items.filter(func(it): return now - float(it.t0) <= LIFE)
	queue_redraw()


func _draw() -> void:
	if _tex == null or game == null or game.world == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var vs := get_viewport_rect().size
	var k := vs.y / 600.0
	var now := Time.get_ticks_msec() / 1000.0
	for it: Dictionary in _items:
		var t := (now - float(it.t0)) / LIFE
		if t < 0.0 or t > 1.0:
			continue
		var u: GameUnit = game.world.units.get(int(it.uid))
		if u == null or not is_instance_valid(u) or not u.visible or u.hidden or u.model == null:
			continue
		var at: Variant = _anchor(u)
		if at == null or cam.is_position_behind(at):
			continue
		var c := cam.unproject_position(at) + Vector2(120.0 * t, -100.0 * t) * k
		var text := str(int(it.n))
		var f := int(it.f)
		var labels := []
		for l: Array in LABELS:
			if f & int(l[0]):
				labels.append(l)
		var w := text.length() * 8.0
		if not labels.is_empty():
			w = maxf(w, 64.0)
		var h := 12.0 + 10.0 * labels.size()
		var top_left := c - Vector2(w, h) * 0.5 * k
		if top_left.x < 0.0 or top_left.y < 0.0 or top_left.x + w * k > vs.x or top_left.y + h * k > vs.y:
			continue
		var col: Color = CYAN if f & 8 else (RED if u.controller >= 0 else GREEN)
		col.a = 1.0 - t
		var x := top_left.x + (w - text.length() * 8.0) * 0.5 * k
		for ch in text:
			var d := ch.unicode_at(0) - 0x30
			draw_texture_rect_region(_tex, Rect2(x, top_left.y, 8.0 * k, 12.0 * k),
				Rect2((d & 3) * 16.0, (d >> 2) * 20.0, 16.0, 20.0), col)
			x += 8.0 * k
		var y := top_left.y + 12.0 * k
		for l: Array in labels:
			draw_texture_rect_region(_tex, Rect2(top_left.x + (w - 64.0) * 0.5 * k, y, 64.0 * k, 10.0 * k),
				Rect2(0.0, float(l[1]), 128.0, float(l[2]) - float(l[1])), col)
			y += 10.0 * k


func _anchor(u: GameUnit) -> Variant:
	for part in ["hd", "bd", "hp"]:
		var n := u.model.find_child(part, true, false) as Node3D
		if n:
			return n.global_position
	return null
