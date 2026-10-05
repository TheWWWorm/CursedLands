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
##   block is on screen and the unit is shown (0x20 and set, 0x40 clear).
## - Anchor: the screen rectangle centre of the unit's "hd" part (else "bd",
##   "hp") when that part has its own rectangle (flag 0x40), else of the unit.
## The original draw uses fixed device pixels, integer anchor/motion and
## FTOL alpha bytes, independently of the 800 x 600 interface layout.
## Hits come from the host as "hitnum" events (GameUnit.
## take_damage, Session.give_experience), so co-op clients show them too.
## - Flags: unit (packed byte, from server stats) is set
##   while the server applies a hit: 1 when the backstab
##   multiplier (record) is not 1.0, 2 when the struck
##   part (record) is 0, the head; 4 (electrical damage) is not drawn.
## Anchor rects: see `_anchor` (a unit with none of the parts gets no
## number, as in the original).
## The original's flag entry (yellow "!!!", 32 x 10 px, no motion
## deleted after one draw) is drawn too; its original caller is unidentified.

const LIFE := 3.0
const MeshScreenRect = preload("res://src/ui/mesh_screen_rect.gd")
const EXP_DELAY := 0.5
const AGE_FACTOR := 0.00033333332976326346   # native float32 1 / 3000
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
		"t0": Time.get_ticks_msec() + (500 if f & 8 else 0)})


func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	_items = _items.filter(func(it): return now - int(it.t0) <= 3000)
	queue_redraw()


func _draw() -> void:
	if _tex == null or game == null or game.world == null:
		return
	if not GameData.option("show_flying_hp"):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var vs := get_viewport_rect().size
	var now := Time.get_ticks_msec()
	for it: Dictionary in _items:
		var u: GameUnit = game.world.units.get(int(it.uid))
		if u == null or not is_instance_valid(u) or not u.visible or u.hidden or u.model == null:
			continue
		var at: Variant = _anchor(u, cam)
		if at == null:
			continue
		for glyph: Dictionary in _layout(at, int(it.n), int(it.f), u.controller >= 0, now - int(it.t0), vs):
			draw_texture_rect_region(_tex, glyph.rect, glyph.source, glyph.colour)
	# Native removes every one-draw warning after this enabled draw pass,
	# including a warning whose carrier or whole block could not be shown.
	_items = _items.filter(func(it): return (int(it.f) & 0x80000000) == 0)


## Complete glyph placement device submit. The renderer
## adds 0.25 texel to u and subtracts it from bottom-up v; the warning uses
## 0.5 texel. Both become positive x/y offsets in the flipped Godot image.
static func _layout(at: Vector2, number: int, flags: int, party: bool, age_ms: int, viewport: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t: float = PackedFloat32Array([age_ms * AGE_FACTOR])[0]
	if t < 0.0 or t > 1.0:
		return out
	var c := Vector2(int(at.x), int(at.y))
	if flags & 0x80000000:
		var warning := Rect2(c + Vector2(-16, -25), Vector2(32, 10))
		if _on_screen(warning, viewport):
			out.append({"rect": warning, "source": Rect2(64.5, 0.5, 64, 20), "colour": Color8(255, 255, 0)})
		return out
	c += Vector2(int(120.0 * t), int(-100.0 * t))
	var text := str(number)
	var labels := []
	for l: Array in LABELS:
		if flags & int(l[0]):
			labels.append(l)
	var w := maxf(text.length() * 8.0, 64.0 if not labels.is_empty() else 0.0)
	var h := 12.0 + labels.size() * 10.0
	var block := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
	if not _on_screen(block, viewport):
		return out
	var colour := CYAN if flags & 8 else (RED if party else GREEN)
	colour.a = int((1.0 - t) * 255.0) / 255.0
	var x := block.position.x + (w - text.length() * 8.0) * 0.5
	for ch in text:
		var d := ch.unicode_at(0) - 0x30
		out.append({"rect": Rect2(x, block.position.y, 8, 12),
			"source": Rect2((d & 3) * 16.0 + 0.25, (d >> 2) * 20.0 + 0.25, 16, 20), "colour": colour})
		x += 8.0
	var y := block.position.y + 12.0
	for l: Array in labels:
		out.append({"rect": Rect2(block.position.x + (w - 64.0) * 0.5, y, 64, 10),
			"source": Rect2(0.25, float(l[1]) + 0.25, 128, float(l[2]) - float(l[1])), "colour": colour})
		y += 10.0
	return out


static func _on_screen(rect: Rect2, viewport: Vector2) -> bool:
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= viewport.x and rect.end.y <= viewport.y


##  anchor in screen pixels: the first of the parts "hd"
## "bd" / "hp" (none → null, no number)
## the centre of that part's screen rect when it was drawn (part flag 0x40),
## else of the figure's rect, the union of its drawn parts' rects (
## figure, UnionRect of each part with 0x40 and a non-empty rect).
## A part's rect is copied from the renderer's after its
## mesh is drawn (0x40 set unless the draw
## returned 2, everything clipped): the screen extents of its transformed
## vertices, which the transform module fills. Remake: the bounds of the
## part's own mesh vertices (not its child parts) projected by the camera.
func _anchor(u: GameUnit, cam: Camera3D) -> Variant:
	var n: Node3D = null
	for part in ["hd", "bd", "hp"]:
		n = u.model.find_child(part, true, false) as Node3D
		if n:
			break
	if n == null:
		return null
	var r := _part_rect(n, cam)
	if r.size == Vector2.ZERO:
		r = Rect2()
		var first := true
		for mi: Node in u.model.find_children("*", "MeshInstance3D", true, false):
			var pr := _mesh_rect(mi as MeshInstance3D, cam)
			if pr.size != Vector2.ZERO:
				r = pr if first else r.merge(pr)
				first = false
		if first:
			return null
	return r.get_center()


## The drawn rect of part node `n`: its own MeshInstance3D children.
func _part_rect(n: Node3D, cam: Camera3D) -> Rect2:
	var r := Rect2()
	var first := true
	for c in n.get_children():
		if c is MeshInstance3D:
			var pr := _mesh_rect(c, cam)
			if pr.size != Vector2.ZERO:
				r = pr if first else r.merge(pr)
				first = false
	return r


## Uses the same clipped, current-pose bounds as figure picking. Hidden or
## wholly clipped parts have no rectangle (the native draw result 2).
func _mesh_rect(mi: MeshInstance3D, cam: Camera3D) -> Rect2:
	return Rect2(MeshScreenRect.of(mi, cam))
