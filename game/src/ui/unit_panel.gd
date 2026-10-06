class_name UnitPanel
extends Control
## Top-left unit panel of the in-game HUD as in the original (the original
##  builds it, draw): 0..185 × 0..225 of the 800×600
## layout, scaled by the window height. The unit under the mouse, else the
## first selected one.
##   * tab strip x 0..20 on a dark strip: open / close (0..30, tip 10100),
##     general view (100..130, battle00 UV 47,62-67,92, tip 10101), hit
##     locations (130..160, UV 69,62, tip 10102), attributes (160..190, UV
##     3,94, tip 10103), spell effects (190..220, UV 233,112, tip 10104);
##   * the unit's 3D figure in (20,0)-(180,220), greyed under the
##     hit locations, not drawn under the attributes;
##   * mode0 height ruler x 20..25 (1×20 repeated UV
##     85,2-90,42; bottom anchored at220 and Y scale15/effective info_scale), frame
##     (−5,−5)-(185,225) 5 wide (UV 4,55-90,60), small icon
##     (164,204)-(180,220) (UV 211,2-227,18);
##   * name word-wrapped in (5,5)-(155,20) of the figure area.
## Texts are GDI COLORREF (beige) with a 1 px shadow
## text rects are relative to the figure area (x + 20).
## General view: health bar (40,190)-(140,195) green (UV
## 64,154, width 100 × fraction) in its frame (35,190)-(145,195) (UV 59,147-
## 169,152) and the value at (130,185)-(160,200); for party units also the
## stamina bar at y 205 (blue, UV 64,161) and its value at (130,200)-(160,215).
## Hit locations: per body part at (x,y) = head (50,35), torso
## (50,105), right arm (95,70), left arm (5,70), right leg (95,140), left leg
## (5,140) (tables) the name "string hl_*"
## (x,y)-(x+60,y+15) — red (COLORREF 0xff) when the part is lost — and a bar
## (x+25,y+15)-(x+25+50f,y+20), UV row 126 (green) above 2/3, 133 (yellow)
## above 1/3, else 140 (red), in its frame (x+20..x+80, UV 59,119-119,124).
## Attributes: lines of 15 px from (5,35)-(155,50):
## "string infounit_N" labels — Health cur/max, Stamina cur/max, Speed
## (value × 7.5 and "string move_N"), Sight (m), Attack, Defense, Damage
## min-max type ("string dmg_N"), Actions, Armor (general armour); a party
## unit then Vulnerability (types below the general armour) and
## "string camp_current_exp"; any other unit Resistance (types above it),
## "Spellcaster" when it has spells and "The enemy is:" with
## "string consider_more/less<N>" for the level difference clamped to ±25.
## Spell effects: up to 6 effects, each a 24×24 "spell%04d"
## icon at (28, 38 + 30 i) and two lines from (40,35): the spell's name and
## its remaining time / 15.
## Open / close (element 0: buttons\battle\sling.wav, the
## direction negated; per frame): p += real dt · dir / 0.3
## slide = trunc(180 · e) with e = 2p² below 0.5, else 1 − 2(1 − p)²;
##  shifts every element, the figure and every hit area but the
## first (the toggle 0..20 × 0..30) left by it. Its "in25arrow" (element 2,
## HudDial.arrow, scale 0.8, unshifted): opening / open turned +π/2 at
## (−50, 20) — pointing left —, closed −π/2 at (87, 20) — pointing right.
## Tabs: the active one at colour 1.0, the others 0.5 (..
## ). The figure's placement is
##  (Paperdoll._exe_frame); the panel's start state (UI manager
## ) is open, general.
## Armour (attributes view): for a named unit (:
## id in 1e9..2e9, Combat.named — heroes and named NPCs) type t is
## Σ w · part armour[t] / Σ w + its own armour[t], w from the table
## by part type (head 10, torso 30, arm 15, leg 15); any other unit shows its
## own armour × the Absorption factor
## (the global difficulty index, 0 in a network game), no parts.
## Part record is the state copied: 0 absent, 1
## severed, 2 destroyed but attached, 3 healthy. Armour counts states 2/3.
## Approx.: the remaining time
## counts 55 ms ticks (record +4's countdown is not traced). The name is centred
## (flag 2; centred in the original's screenshots) and the figure is drawn
## straight over the game view, as in the original.

const TABS := {"toggle": [Rect2(0, 0, 20, 30), Rect2(), 10100],
	"general": [Rect2(0, 100, 20, 30), Rect2(47, 62, 20, 30), 10101],
	"parts": [Rect2(0, 130, 20, 30), Rect2(69, 62, 20, 30), 10102],
	"attributes": [Rect2(0, 160, 20, 30), Rect2(3, 94, 20, 30), 10103],
	"effects": [Rect2(0, 190, 20, 30), Rect2(233, 112, 20, 30), 10104]}
const FIG := Rect2(20, 0, 160, 220)
const TEXT := Color(0xe4 / 255.0, 0xd7 / 255.0, 0xa7 / 255.0)
const LOST := Color(1, 0, 0)
## Part positions in GameUnit.PART_KEYS order (head, torso, left arm, right
## arm, left leg, right leg; the figure faces the viewer, so its left arm is
## drawn on the right).
const PART_POS := [Vector2(50, 35), Vector2(50, 105), Vector2(95, 70), Vector2(5, 70),
	Vector2(95, 140), Vector2(5, 140)]
const PART_TEXT := {0: "string hl_skull", 1: "string hl_torso", 2: "string hl_arm", 3: "string hl_leg"}

var game: Game
var mode := "general"
var open := true
var _atlas: Texture2D
var _doll: Paperdoll
var _over: Control
var _unit: GameUnit
var _t := 0.0
var _sp := 0.0    # slide progress 0 open.. 1 closed
var _off := 0.0   # slide in 800×600 px
var _height_key: Array = []
var _base_height_factor := 1.0
## First four part-type weights.
const HEIGHT_RULER_UV := Rect2(85.5, 2.5, 5, 40)
const PART_WEIGHT := [10.0, 30.0, 15.0, 15.0]
const PART_ARMOR := ["head", "torso", "arms", "legs"]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var img := GameData.load_image("battle00") if GameData.is_open() else null
	if img:
		img.flip_y()
		_atlas = ImageTexture.create_from_image(img)
	_doll = Paperdoll.new()
	_doll.view_size = Vector2i(160, 220)
	#  camera and figure transform (Paperdoll._exe_frame).
	_doll.exe_rect = FIG
	_doll.follow_pose = true
	_doll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_doll)
	_over = Control.new()
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over.draw.connect(_draw_over)
	add_child(_over)


## Screen px per 800×600 unit: the height's, or GameHUD.top_scale (portrait).
func _k() -> float:
	var hud := get_canvas_layer_node() as GameHUD
	return hud.top_scale() if hud else Interface800.canvas_size(self).y / 600.0


func _p(v: Vector2, fixed := false) -> Vector2:
	return (v - Vector2(0.0 if fixed else _off, 0)) * _k()


func _r(r: Rect2, fixed := false) -> Rect2:
	return Rect2(_p(r.position, fixed), r.size * _k())


func _txt(key: String) -> String:
	var t := GameData.text(key).strip_edges()
	return t if t else key.get_slice(" ", 1)


func _process(dt: float) -> void:
	var k := _k()
	position = Vector2.ZERO
	size = Vector2(185, 225) * k
	if _sp != (0.0 if open else 1.0):
		_sp = clampf(_sp + dt * (-1.0 if open else 1.0) / 0.3, 0.0, 1.0)
		var e := 2.0 * _sp * _sp if _sp < 0.5 else 1.0 - 2.0 * (1.0 - _sp) * (1.0 - _sp)
		_off = floorf(180.0 * e)
	_doll.position = _p(FIG.position)
	_doll.size = FIG.size * k
	_t -= dt
	if _t <= 0.0:
		_t = 0.1
		var was := _unit
		_unit = _pick()
		_doll.visible = _off < 180.0 and _unit != null and mode != "attributes"
		# The panel's figure mirrors the unit's pose: keep that unit animating
		# at the full rate even when it is off screen (GameUnit anim LOD).
		var watched: GameUnit = _unit if _doll.visible else null
		if is_instance_valid(was) and was != watched:
			was.anim_watched = false
		if watched:
			watched.anim_watched = true
		# A hidden figure needn't follow the unit's pose every frame.
		_doll.process_mode = Node.PROCESS_MODE_INHERIT if _doll.visible else Node.PROCESS_MODE_DISABLED
		if _doll.visible:
			_doll.show_unit(_unit)
		# part colour in every mode but general.
		_doll.modulate = Color(0.5, 0.5, 0.5) if mode != "general" else Color.WHITE
	queue_redraw()
	_over.queue_redraw()


## Remake (gamepad, PadField): the examined unit shown instead of the hovered
## or selected one; `ignore_hover` while the pad drives without a pointer.
var examine: GameUnit
var ignore_hover := false


func _pick() -> GameUnit:
	if game == null or game.world == null:
		return null
	if is_instance_valid(examine) and not examine.dead and examine.world == game.world:
		return examine
	var u: GameUnit = null
	var vp := get_viewport()
	if vp.gui_get_hovered_control() == null and not ignore_hover:
		u = game.pick_unit(vp.get_mouse_position())
		#  hands the panel living objects only.
		if u != null and u.dead:
			u = null
	if u == null and not game.selected.is_empty() and is_instance_valid(game.selected[0]):
		u = game.selected[0]
	return u if u != null and is_instance_valid(u) else null


func _tab_at(local: Vector2) -> String:
	var p := local / _k()
	for t in TABS:
		var r: Rect2 = TABS[t][0]
		if (r if t == "toggle" else Rect2(r.position - Vector2(_off, 0), r.size)).has_point(p):
			return t
	return ""


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var t := _tab_at(e.position)
	if t == "":
		return
	if t == "toggle":
		open = not open
		if GameSound.instance:
			GameSound.instance.ui("buttons\\battle\\sling.wav")
	else:
		mode = t
		open = true
	_t = 0.0
	accept_event()


## keyboard.ini w_info1–4 (. / ', the original cases 0x2e–0x31
## views = 0 general, 1 hit locations, 2 attributes, 3 spell effects):
## closed (= 1) → opens on that view; open on another view → that view
## silently; open on the same view → closes. Opening / closing sound
## buttons\battle\sling.wav, then marks the tabs.
const KEY_VIEWS := ["general", "parts", "attributes", "effects"]

func key_view(i: int) -> void:
	var t: String = KEY_VIEWS[clampi(i, 0, 3)]
	if open and mode != t:
		mode = t
	else:
		open = not open
		mode = t
		if GameSound.instance:
			GameSound.instance.ui("buttons\\battle\\sling.wav")
	_t = 0.0
	queue_redraw()


func _get_tooltip(at: Vector2) -> String:
	var t := _tab_at(at)
	# hotkeys w_info1..4 (0x2e..0x31) on the four view tabs.
	return GameData.tip_key(GameData.text("tip %d" % TABS[t][2]).strip_edges(),
			{"general": 46, "parts": 47, "attributes": 48, "effects": 49}.get(t, 0)) if t else ""


func _has_point(point: Vector2) -> bool:
	var p := point / _k()
	return Rect2(0, 0, 20, 30).has_point(p) or Rect2(-_off, 0, 185, 225).has_point(p)


func _strip(ci: CanvasItem, from: Vector2, to: Vector2, width: float, uv: Rect2) -> void:
	if _atlas == null:
		ci.draw_line(_p(from), _p(to), Color(0.6, 0.45, 0.25), width * _k())
		return
	var d := (to - from).normalized().orthogonal() * width * 0.5
	var pts := PackedVector2Array([_p(from - d), _p(to - d), _p(to + d), _p(from + d)])
	var s := _atlas.get_size()
	var uvs := PackedVector2Array([uv.position / s, Vector2(uv.end.x, uv.position.y) / s, uv.end / s,
		Vector2(uv.position.x, uv.end.y) / s])
	ci.draw_primitive(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs, _atlas)


func _region(ci: CanvasItem, dst: Rect2, uv: Rect2, mod := Color.WHITE) -> void:
	if _atlas:
		if uv == HEIGHT_RULER_UV:
			# These native endpoints already include half a texel. A second
			# region clamp would inset the repeated ruler again.
			ci.draw_texture_rect_region(_atlas, _r(dst), uv, mod, false, false)
		else:
			ci.draw_texture_rect_region(_atlas, _r(dst), uv, mod)


## Below the figure: the dark strip, the figure's backdrop and the tabs.
func _draw() -> void:
	var k := _k()
	draw_rect(_r(Rect2(0, 0, 20, 220)), Color(0, 0, 0, 0.7))
	for t in TABS:
		var uv: Rect2 = TABS[t][1]
		if uv.has_area():
			_region(self, TABS[t][0], uv, Color.WHITE if t == mode else Color(0.5, 0.5, 0.5))
	if _atlas:
		var pts := HudDial.arrow(-50, 20, PI * 0.5, 0.8) if open else HudDial.arrow(87, 20, -PI * 0.5, 0.8)
		var uvs := PackedVector2Array()
		for i in 3:
			pts[i] = _p(pts[i], true)
			uvs.append(Vector2(HudDial.ARROW_UV[i].x, 256.0 - HudDial.ARROW_UV[i].y) / 256.0)   # flipped atlas
		draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]), uvs, _atlas)


## Above the figure: texts, bars, divider and frame.
func _draw_over() -> void:
	var c := _over
	var uvf := Rect2(4, 55, 86, 5)
	if _off < 180.0:
		if _unit:
			_text(c, Rect2(5, 5, 150, 15), _unit.display_name, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
			match mode:
				"general": _draw_general(c, _unit)
				"parts":
					_draw_parts(c, _unit)
					_draw_general(c, _unit)
				"attributes": _draw_attributes(c, _unit)
				"effects": _draw_effects(c, _unit)
		#  clears element 9 every frame; enables
		# it only when the effects list exceeds its six displayed entries.
		if _unit and mode == "effects" and _unit.buffs.size() > 6:
			_region(c, Rect2(164, 204, 16, 16), Rect2(211, 2, 16, 16))
		if _unit and mode == "general":
			_draw_height_ruler(c, _unit)
		_strip(c, Vector2(-5, -2.5), Vector2(185, -2.5), 5.0, uvf)
		_strip(c, Vector2(-5, 222.5), Vector2(185, 222.5), 5.0, uvf)
		_strip(c, Vector2(182.5, -5), Vector2(182.5, 225), 5.0, uvf)
	else:
		_strip(c, Vector2(182.5, -5), Vector2(182.5, 225), 5.0, uvf)   # the frame's right edge stays


##  element8 is a bottom-anchored 1×20 grid, not a full-height
## divider. Each segment repeats the entire battle00 bronze tile. The
## prototype's info_scale is the native preview scale, not metres.
func _draw_height_ruler(c: CanvasItem, u: GameUnit) -> void:
	var height := float(u.proto.get("info_scale", 1.0))
	if is_instance_valid(u.model):
		var base: Vector3 = u.info.get("complexion", Vector3.ZERO)
		if base == Vector3.ZERO:
			base = GameUnit.proto_complexion(u.proto)
		var key := [u.get_instance_id(), u.model.get_instance_id(), u.model.template, base.z]
		if key != _height_key:
			_height_key = key
			# effective.adb height / float32(base.adb height).
			_base_height_factor = float(PackedFloat32Array([
				EIUnitModel.height_scale(u.model.template, base.z)])[0])
		if _base_height_factor != 0.0:
			height *= u.model.height_k / _base_height_factor
	height = float(PackedFloat32Array([height])[0])
	if height <= 0.0 or not is_finite(height):
		return   # a missing/malformed preview scale cannot form finite geometry
	var s := float(PackedFloat32Array([15.0 / height])[0])
	var top := float(PackedFloat32Array([220.0 - s * 220.0])[0])
	for i in 20:
		# Native constructor adds half a texel at both U/V endpoints. Each
		# quad reuses all four UVs; Canvas/window clipping trims the tall grid.
		_region(c, Rect2(20, top + i * 11.0 * s, 5, 11.0 * s), HEIGHT_RULER_UV)


## Text in a figure-area rect (x + 20) with the 1 px shadow
## CInterface3D font 0 (the panel's draws pass font 0: Times
## New Roman, 0.01733 × width em = 13.9 px at 800).
func _text(c: CanvasItem, r: Rect2, s: String, col := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var k := _k()
	var font := Interface800.font()
	var fs := maxi(6, int(round(800.0 * Interface800.FONT_EM[0] * k)))
	var pos := (r.position + Vector2(20, 0)) * k + Vector2(0, font.get_ascent(fs))
	var sh := maxf(1.0, round(k))
	c.draw_string(font, pos + Vector2(sh, sh), s, align, r.size.x * k, fs, Interface800.SHADOW)
	c.draw_string(font, pos, s, align, r.size.x * k, fs, col)


## A bar: frame, then the fill (UV strip from x 64, `w` wide at full).
func _bar(c: CanvasItem, at: Vector2, w: float, frac: float, uv_y: float, frame_uv: Rect2) -> void:
	_region(c, Rect2(at.x - 5, at.y, w + 10, 5), frame_uv)
	frac = clampf(frac, 0.0, 1.0)
	if frac > 0.0:
		_region(c, Rect2(at.x, at.y, w * frac, 5), Rect2(64, uv_y, w * frac, 5))


func _party(u: GameUnit) -> bool:
	return u.controller >= 0


func _draw_general(c: CanvasItem, u: GameUnit) -> void:
	var fr := Rect2(59, 147, 110, 5)
	_bar(c, Vector2(40, 190), 100, u.hp / maxf(u.max_hp, 0.01), 154, fr)
	_text(c, Rect2(130, 185, 30, 15), str(maxi(int(u.hp), 0)))
	if _party(u):
		_bar(c, Vector2(40, 205), 100, u.mana / maxf(u.max_mana, 0.01) if u.max_mana > 0 else 0.0, 161, fr)
		_text(c, Rect2(130, 200, 30, 15), str(int(u.mana)))


func _draw_parts(c: CanvasItem, u: GameUnit) -> void:
	if u.parts.size() < 6:
		return
	var lost := u.severed_mask()
	for i in 6:
		var p: Dictionary = u.parts[i]
		if int(p.get("state", 0)) == 0:
			continue
		var at: Vector2 = PART_POS[i]
		var gone := (lost >> i) & 1 == 1
		var f := 0.0 if gone else clampf(float(p.cur) / maxf(float(p.max), 0.01), 0.0, 1.0)
		var row := 126.0 if f > 2.0 / 3.0 else (133.0 if f > 1.0 / 3.0 else 140.0)
		_bar(c, at + Vector2(25, 15), 50, f, row, Rect2(59, 119, 60, 5))
		_text(c, Rect2(at.x, at.y, 60, 15), _txt(PART_TEXT.get(int(p.type), "string hl_torso")),
			LOST if gone else TEXT)


## The 7 armour values (piercing .. general): natural plus the worn layers
## averaged over the body parts.
func _armor(u: GameUnit) -> PackedFloat32Array:
	var out := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
	var nat: PackedFloat32Array = u.stats.get("armor", PackedFloat32Array())
	for t in 7:
		out[t] = _fistp(nat[t] if t < nat.size() else 0.0) & 65535
	if not Combat.named(u):   #  param 3 = 0
		# This panel uses the global multiplier for every unnamed unit. The
		# combat calculation's separate party exception does not apply here.
		var level := 0 if game and game.session and game.session.online else GameData.difficulty
		var f := GameData.ai_value("DifficultyLevels", "Absorption", 1.0, level)
		for t in 7:
			out[t] *= f
		return out
	var pa: Dictionary = u.stats.get("part_armor", {})
	var sums := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
	var ws := 0.0
	for i in mini(u.parts.size(), 6):
		var part: Dictionary = u.parts[i]
		# Snapshots carry severance in the existing mask; a client's local
		# part records otherwise keep their prototype state.
		if int(part.get("state", 0)) <= 1 or (u._severed_want >> i) & 1:
			continue
		var type := int(part.get("type", -1))
		if type < 0 or type >= PART_WEIGHT.size():
			continue
		var w: float = PART_WEIGHT[type]
		var layer: PackedFloat32Array = pa.get(PART_ARMOR[type], PackedFloat32Array())
		for t in 7:
			var a := _fistp(layer[t] if t < layer.size() else 0.0) & 65535
			sums[t] += w * a
		ws += w
	#  keeps the reciprocal on the x87 stack (53-bit precision
	# after the shipped TLP startup), rounding only the final value to float.
	var inverse := 1.0 / ws if ws > 0.0 else 0.0
	for t in 7:
		out[t] += sums[t] * inverse
	return out


func _level(u: GameUnit) -> int:
	if u.has_meta("hero"):
		return int(u.get_meta("hero").get("level", 1))
	return int(u.proto.get("base_level", 1))


## The speed line's value before × 7.5: a party unit's speed
## at its gait (unit: 0 crawl, 1 kneel, 2 / 4 walk, 3
## run), any other unit's running speed ((3)); from the stats
## bytes packs: speed byte = round(race speed · 255 / 2) (run
## walk, kneel, crawl =..), factor byte = round(· 25.5)
## where = prototype tuning_move × the legs' wound factor
## value = speed byte · 2/255 · factor byte ·
## 10/255. The remake's gait: the unit's stance (kneel / crawl), else for the
## player's own units the HUD's run / walk mode (the remake keeps it per
## player, the original per unit), for other party units their current running.
func _speed(u: GameUnit) -> float:
	var s: Array = u.race.get("speeds", [0.4, 0.16])
	var mode := 3
	if _party(u):
		if u.stance == GameUnit.STANCE_CRAWL:
			mode = 0
		elif u.stance == GameUnit.STANCE_KNEEL:
			mode = 1
		else:
			var mine := game != null and game.session != null and u.controller == game.session.my_index
			var run: bool = u.gait_run if mine else u.running
			mode = 3 if run else 2
	var i := {3: 0, 2: 1, 1: 2, 0: 3}[mode] as int   # race speeds: run, walk, kneel, crawl
	var v := float(s[i]) if i < s.size() else float(s[mini(1, s.size() - 1)])
	var sb := mini(255, _fistp(v * 255.0 / 2.0))
	var f := float(u.proto.get("tuning_move", 1.0)) * u.wound_factor(3)
	var fb := mini(255, _fistp(f * 25.5))
	return sb * 2.0 / 255.0 * (fb * 10.0 / 255.0)


## x87 FISTP in its default mode: to the nearest integer, ties to even.
static func _fistp(x: float) -> int:
	var f := floorf(x)
	var d := x - f
	if d > 0.5 or (d == 0.5 and int(f) % 2 != 0):
		return int(f) + 1
	return int(f)


func _draw_attributes(c: CanvasItem, u: GameUnit) -> void:
	var lines := PackedStringArray()
	lines.append("%s %d/%d" % [_txt("string infounit_0"), maxi(int(u.hp), 0), int(u.max_hp)])
	lines.append("%s %d/%d" % [_txt("string infounit_1"), int(u.mana), int(u.max_mana)])
	lines.append("%s %.1f %s" % [_txt("string infounit_2"), _speed(u) * 7.5,
		_txt("string move_3") if u.has_meta("flying") else ""])
	lines.append("%s %d%s" % [_txt("string infounit_6"), roundi(float(u.stats.get("sight", 15.0)) * u.sight_factor()),
		_txt("string infounit_13")])
	# The attack info's Attack / Defence (
	# ): scaled by the difficulty for unnamed units.
	var cb: Combat = game.world.combat if game and game.world else null
	lines.append("%s %d" % [_txt("string infounit_3"), cb.attack_value(u) if cb else int(u.stats.get("to_hit", 0.0))])
	lines.append("%s %d" % [_txt("string infounit_4"), cb.defence_value(u) if cb else int(u.stats.get("parry", 0.0))])
	var types: PackedFloat32Array = u.stats.get("dmg_types", PackedFloat32Array())
	var best := -1
	for t in types.size():
		if best < 0 or types[t] > types[best]:
			best = t
	var dmg := "%s %d-%d" % [_txt("string infounit_9"), int(u.stats.get("dmg_min", 0.0)),
		int(u.stats.get("dmg_max", 0.0))]
	if best >= 0 and best < 7:
		dmg += " " + _txt("string dmg_%d" % best)
	lines.append(dmg)
	lines.append("%s %d" % [_txt("string infounit_15"), int(u.actions())])
	var ar := _armor(u)
	lines.append("%s %d" % [_txt("string infounit_10"), int(ar[6])])
	var above := PackedStringArray()
	var below := PackedStringArray()
	for t in 6:
		if ar[t] > ar[6]:
			above.append(_txt("string dmg_%d" % t))
		elif ar[t] < ar[6]:
			below.append(_txt("string dmg_%d" % t))
	if _party(u):
		if not below.is_empty():
			lines.append("%s %s" % [_txt("string infounit_12"), ", ".join(below)])
		#  shows the experience line only in a network game
		# after the party unit's other lines.
		if u.has_meta("hero") and game and game.session and game.session.online:
			lines.append("%s %d" % [_txt("string camp_current_exp"), int(u.get_meta("hero").get("exp", 0.0))])
	else:
		if not above.is_empty():
			lines.append("%s %s" % [_txt("string infounit_11"), ", ".join(above)])
		if not Array(u.proto.get("spells", [])).is_empty():
			lines.append(_txt("string infounit_5"))
		var mine := game.my_units() if game else []
		if not mine.is_empty():
			var d := clampi(_level(u) - _level(mine[0]), -25, 25)
			var word := _txt("string consider_more%d" % d) if d >= 0 else _txt("string consider_less%d" % -d)
			lines.append("%s %s" % [_txt("string infounit_16"), word])
	for i in lines.size():
		_text(c, Rect2(5, 35 + 15 * i, 150, 15), lines[i])


func _draw_effects(c: CanvasItem, u: GameUnit) -> void:
	var names := u.buffs.keys()
	for i in mini(names.size(), 6):
		var code := String(names[i])
		var sp := Spells.parse(code)
		var t := int(sp.proto.get("texture_type", -1))
		var tex := SpellSlots.icon("spell%04d" % t) if t >= 0 else null
		if tex:
			c.draw_texture_rect(tex, _r(Rect2(28, 38 + 30 * i, 24, 24)), false)
		_text(c, Rect2(40, 35 + 30 * i, 115, 15), Spells.title(code))
		_text(c, Rect2(40, 50 + 30 * i, 115, 15), str(int(float(u.effect_ticks(code)) / 15.0)))
