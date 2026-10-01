class_name TravelMap
extends Control
## The global map screen (the original screen 4, built s
## ): the allod's island in 3D over the purple astral, shown
## when the party leaves a zone. Everything below is read from the original:
##
## Init
##   * textures (in this order): "<allod>Map" (zone pieces)
##     "<allod>Sys" (markers), "<allod>MapG" (island and unexplored pieces),
##     "saveload" (interface) and a 256² render target (the astral clouds).
##   * every object is a CI3DFigure placed in view space (x right, y down,
##     z forward; the 800×600 screen spans tan 0.48157462 per 400 px):
##     (400, 280, 10) puts the island's origin 10 units in front
##     of screen point (400,280); each object's position is that point plus
##     the island orientation applied to its map.txt position.
##   * island orientation = rotation 2.5132742 rad (144°) about X times the
##     turn angle about Z (update).
##   * map.txt "#allod" figures: [1] arrow (scale 1) and [2] pointball (0.8)
##     over the current zone, [4] "down" = the island (MapG); the allod's game
##     zones with a #figure are the island pieces (all at the island origin);
##     for each piece every GS var "q.<zone>.<quest>" equal to 1 puts the [3]
##     quest marker (scale 0.3) at "#quest <quest>"'s position; every "brief"
##     zone next to a piece (its exits) whose GS var "z.<brief>" is 2 shows its
##     own figure (scale 0.3) at its #position as a button. A piece whose
##     "z.<zone>" is 2 is linked to such a brief.
##   * astral: renderer clear colour; three 600×600 px quads at depth
##     25 (18.06 units) lying in the island plane at island z −0.5, 0.7 and 2.0,
##     turning with the island, ARGB
##     (table), texture V offset 0.3 / 0.6 / 0, U
##     offset scrolling frac(t / 100) / frac(t / 60) / frac(t / 30); the first
##     quad's V is flipped. The texture (
## ) is the classic cloud noise: four 32×32 octaves
##     smoothed integer noise (: centre / 4 + sides / 8 +
##     corners / 16) summed at cell sizes 8, 4, 2, 1 px with weights 1, ½, ¼,
##     ⅛ minus 112, generated one slice per 0.5 s (16 slices =
##     a new frame every 8 s) and cross-faded; palette ((119
##     248, 2)): white with alpha 255 − 255 · (248/255)^max(0, v − 119).
##   * interface (saveload texture, black panels, 5 px frames
##      strip UV 2,249-180,254, text COLORREF):
##     top-left (20,20)-(170,70) in frame (15,15)-(175,75): «allod <name>»
##     and "%s  %d,  %d:%02d" of «string save_day», day = gtime / 1440 + 1,
##     hours, minutes, centred in (20,25)-(170,45) / (20,45)-(170,65);
##     buttons: 0 (737,537)-(785,585) tip 90102 "Turn map
##     right", 1 (689,537)-(737,585) tip 90101 "Turn map left" (UV 134,55 and
##     81,55, 48×48), 2 (15,525)-(107,585) camp, tip 90100 (UV 2,151, 92×60,
##     hidden when GS var "i.nocamp" is 1), 3.. the brief figures.
##   * zone highlight colour (0x280): green (0, 1, 0); Ingos (0.371, 0.508,
##     0.625); Suslanger (0.391, 0.195, 0.086); linking pieces and briefs on
##     hover only on Gipat.
## Update: turn angle += dt · direction · π/4; arrow bobs
## z + 0.5 − 0.2 cos(5t).
## Highlight: piece state 0 = MapG texture, 1 = Map (hovered:
## × highlight colour), 2 = Map × 0.5 (hovered: × highlight × 0.5); briefs ×
## highlight when hovered.
## Mouse move: hovered piece (id buffer) or brief button; a
## piece with state 0 shows nothing; otherwise zone.wav when the name changes
## and the panel (400,20)-(780,75+20n) in frame (395,15)-(785,80+20n): «zone
## <id>» in (410,30)-(700,70) and the piece's quests («quest <id>» first line)
## in (420,60+20k)-(750,80+20k). Right drag turns the island by 1/300 rad per
## pixel.
## Mouse down: arrows turn while held (move.wav, release
## ); camp: transit.wav, GS var constr_current = 0 and screen 5
## (the camp without a trader = the dressing screen); an explored piece:
## ok.wav, route and the zone objectives screen (ui/zone_objectives.gd); a
## village (or on Gipat a piece linked to it): ok.wav and travel along its
## route at once. The screen loops wind.wav while open. Keys:
## Esc opens the game menu, H the "global_map" tutorial.
## Routes: CampaignMap.routes from the edge the party walked
## into; the host offers every entrance a route reaches (Session.travel_options),
## for a village only entrance 0 (its first exit).
## Clouds (rate 2 slices/s
## (119, 248, 2.0)): 16 slices = 8 s per frame, blended with
## a = (slice + frac) · 0.0625 · 254 + 1, i.e. a linear cross-fade over the 8 s.
## Keys quicksave / quickload (via the action table: 0x35
## 0x36) work here in single player only.
## Remake differences (**Approx.**): "Stay here" and buttons for destinations
## on another allod are remake-only (the original builds only the turn / camp
## buttons, tips 90100-90102, and cannot stay); pieces are picked by ray
## casts instead of the id buffer; in co-op only the party leader travels
## (the original's client sends travel command 6 with no leader check; the
## server's handling is not traced).

signal picked(option: Dictionary)
signal cancelled
signal camp
## Esc: the game menu.
signal menu
## H: a tutorial by id.
signal help(id: String)
## Quick save / load keys (single player): "quicksave" / "quickload".
signal quick(action: String)

const DIST := 10.0
const CENTER := Vector2(400, 280)
const TAN := 0.48157462
const TILT := 2.5132742
const LAYER_SIZE := 600.0 * 0.0025 * TAN * 25.0
## [island z, ARGB, U speed (1/s), V offset, V flipped]
const LAYERS := [[-0.5, 0x649b00e1, 0.01, 0.3, true], [0.7, 0x6e9b007d, 1.0 / 60.0, 0.6, false],
	[2.0, 0xb9690ac3, 1.0 / 30.0, 0.0, false]]
const TEXT := Color8(0xe4, 0xd7, 0xa7)
const FRAME_UV := Rect2(2, 249, 178, 5)
## Buttons in the 800×600 layout: [rect, UV, tip].
const BTN_RIGHT := [Rect2(737, 537, 48, 48), Rect2(134, 55, 48, 48), 90102]
const BTN_LEFT := [Rect2(689, 537, 48, 48), Rect2(81, 55, 48, 48), 90101]
const BTN_CAMP := [Rect2(15, 525, 92, 60), Rect2(2, 151, 92, 60), 90100]
const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D oct_a : filter_linear, repeat_enable;
uniform sampler2D oct_b : filter_linear, repeat_enable;
uniform float fade = 0.0;
uniform vec4 tint : source_color;
uniform vec2 offset = vec2(0.0);
uniform bool flip_v = false;
// octaves at 8, 4, 2, 1 px cells, weights 1, 1/2, 1/4, 1/8, minus 112.
float clouds(sampler2D o, vec2 p) {
	float v = texture(o, (p / 8.0 + 0.5) / 32.0).r
		+ texture(o, (p / 4.0 + 0.5) / 32.0).g * 0.5
		+ texture(o, (p / 2.0 + 0.5) / 32.0).b * 0.25
		+ texture(o, (p + 0.5) / 32.0).a * 0.125;
	return clamp(v * 255.0 - 112.0, 0.0, 255.0);
}
void fragment() {
	vec2 uv = flip_v ? vec2(UV.x, 1.0 - UV.y) : UV;
	vec2 p = (uv + offset) * 256.0;
	float v = mix(clouds(oct_a, p), clouds(oct_b, p), fade);
	// (119, 248, 2): alpha = 255 - 255 * (248/255)^max(0, v - 119).
	ALBEDO = tint.rgb;
	ALPHA = tint.a * (1.0 - pow(248.0 / 255.0, max(0.0, v - 119.0)));
}
"""

var session: Session
var options: Array = []
var here := ""
var leader := true
var allod := ""
var angle := 0.0
var _t := 0.0
var _turn := 0            # held arrow: +1 left, -1 right
var _drag := false
var _vp: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _arrow: Node3D
var _here_pos := Vector3.ZERO
var _hud: Control
var _ui: Texture2D
## Island pieces: {id, state, link, node, mats: [StandardMaterial3D], faces: [[MeshInstance3D, PackedVector3Array]], quests: [title]}
var _pieces: Array = []
## Brief figures: {id, zone (piece index), node, mats}
var _briefs: Array = []
var _highlight := Color(0, 1, 0)
var _link := false        # Gipat: pieces linked to their village (0x278)
var _tex_map: Texture2D
var _tex_grey: Texture2D
var _hover := -1
var _hover_brief := false
var _last_name := ""
var _nocamp := false
var _layers: Array = []   # ShaderMaterial per layer
var _oct: Array = []      # two ImageTextures (cloud frames A and B)
var _fade := 0.0
var _rng := RandomNumberGenerator.new()
var _wind: AudioStreamPlayer
var _extra: VBoxContainer
var _drag_from := Vector2.ZERO
## The zone objectives screen while open (ui/zone_objectives.gd).
var objectives: ZoneObjectives


func setup(s: Session, opts: Array, is_leader := true, from := "") -> void:
	session = s
	options = opts
	leader = is_leader
	# The current zone of the map is the edge the party walked into.
	here = from if from else s.zone_id
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "
	var cz := s.campaign.zone(here)
	allod = String(cz.get("allod", "")).to_lower()
	if allod.is_empty() and not opts.is_empty():
		allod = String(s.campaign.zone(String(opts[0].zone)).get("allod", "gipat")).to_lower()
	match allod:
		"ingos": _highlight = Color(0.37109375, 0.5078125, 0.625)
		"suslanger": _highlight = Color(0.390625, 0.1953125, 0.0859375)
	_link = allod == "gipat"
	_nocamp = is_equal_approx(s.state.get_var(0, "i.nocamp"), 1.0)
	var img := GameData.load_image("saveload")
	if img:
		img.flip_y()
		_ui = ImageTexture.create_from_image(img)
	_build_scene()
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	add_child(_hud)
	_build_extra()
	_wind = AudioStreamPlayer.new()
	_wind.bus = "SFX"
	_wind.stream = EIAudio.sfx("buttons\\globalmap\\wind.wav")
	_wind.finished.connect(_wind.play)
	_wind.autoplay = true
	add_child(_wind)
	_apply_highlight()


# ------------------------------------------------------------------ scene

func _build_scene() -> void:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.anisotropic_filtering_level = Viewport.ANISOTROPY_8X
	box.add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color8(0, 0, 10)   # renderer colour
	_vp.add_child(env)
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.fov = rad_to_deg(2.0 * atan(0.75 * TAN))
	_cam.near = 0.5
	_cam.far = 100.0
	_vp.add_child(_cam)
	# Engine view space (x right, y down, z forward) -> camera space.
	var view := Node3D.new()
	view.basis = Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1))
	_vp.add_child(view)
	_pivot = Node3D.new()
	_pivot.position = Vector3((CENTER.x * 0.0025 - 1.0) * TAN * DIST, (CENTER.y * 0.0025 - 0.75) * TAN * DIST, DIST)
	view.add_child(_pivot)
	_update_pivot()

	var figs: PackedStringArray = session.campaign.allods.get(allod, PackedStringArray())
	var fig := func(i: int) -> String: return figs[i] if i < figs.size() else ""
	_tex_map = GameData.get_texture(allod + "map")
	_tex_grey = GameData.get_texture(allod + "mapg")
	var sys := allod + "sys"
	# Island ("down") with the MapG texture.
	_add_figure(fig.call(3), allod + "mapg", Vector3.ZERO, 1.0)
	# Pieces: the allod's game zones with a figure.
	var index := {}
	for id: String in session.campaign.zones:
		var z: Dictionary = session.campaign.zones[id]
		if String(z.get("allod", "")).to_lower() != allod or z.get("type", "") != "game" or String(z.get("figure", "")).is_empty():
			continue
		var st := _zone_state(id)
		var mats := []
		var n := _add_figure(String(z.figure).to_lower(), allod + "map", Vector3.ZERO, 1.0, mats)
		if n == null:
			continue
		var faces := []
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			faces.append([mi, mi.mesh.get_faces()])
		index[id] = _pieces.size()
		_pieces.append({"id": id, "state": st, "link": -1, "node": n, "mats": mats, "faces": faces,
			"quests": _quests_of(id, fig.call(2), sys)})
	# Villages next to the pieces (third loop).
	for pi in _pieces.size():
		var z := session.campaign.zone(_pieces[pi].id)
		for ex: Dictionary in z.get("exits", {}).values():
			var to := String(ex.get("to", ""))
			var bz := session.campaign.zone(to)
			if bz.get("type", "") != "brief" or String(bz.get("figure", "")).is_empty():
				continue
			if _briefs.any(func(b): return b.id == to):
				continue
			if not is_equal_approx(session.state.get_var(0, "z." + to), 2.0):
				continue
			if _pieces[pi].state == 2:
				_pieces[pi].link = _briefs.size()
			var mats := []
			var n := _add_figure(String(bz.figure).to_lower(), sys, bz.get("position", Vector3.ZERO), 0.3, mats)
			if n:
				_briefs.append({"id": to, "zone": pi, "node": n, "mats": mats})
	# Current zone: pointball and bobbing arrow.
	_here_pos = session.campaign.zone(here).get("position", Vector3.ZERO)
	_add_figure(fig.call(1), sys, _here_pos, 0.8)
	_arrow = _add_figure(fig.call(0), sys, _here_pos + Vector3(0, 0, 2), 1.0)
	_build_clouds()


## A map figure under the island pivot at EI position `at`, scaled; its meshes
## get unshaded materials (CI3DFigure: uniform tint, no world lighting).
func _add_figure(name: String, texture: String, at: Vector3, s: float, mats: Array = []) -> Node3D:
	if name.is_empty():
		return null
	var f := EIFigure.instantiate(name, texture, Vector3.ZERO)
	if f == null:
		return null
	var place := Node3D.new()
	place.position = at
	_pivot.add_child(place)
	# Godot model space -> EI space (inverse of EISpace.vec).
	var g2ei := Node3D.new()
	g2ei.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)).scaled(Vector3.ONE * s)
	place.add_child(g2ei)
	g2ei.add_child(f)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = GameData.get_texture(texture)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	mats.append(m)
	for mi: MeshInstance3D in f.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return place


func _zone_state(id: String) -> int:
	return int(session.state.get_var(0, "z." + id))


## Quest markers of a piece: GS vars "q.<zone>.<quest>" = 1.
func _quests_of(zone: String, marker: String, tex: String) -> Array:
	var out := []
	var prefix := "0:q.%s." % zone
	for k: String in session.state.vars:
		if not k.begins_with(prefix) or k.get_slice_count(".") != 3:
			continue
		if not is_equal_approx(float(session.state.vars[k]), 1.0):
			continue
		var q := k.get_slice(".", 2)
		out.append(GameData.text("quest " + q).get_slice("\n", 0).strip_edges())
		if session.campaign.quests.has(q):
			_add_figure(marker, tex, session.campaign.quests[q], 0.3)
	return out


func _build_clouds() -> void:
	_oct = [ImageTexture.create_from_image(_noise_frame()), ImageTexture.create_from_image(_noise_frame())]
	var sh := Shader.new()
	sh.code = CLOUD_SHADER
	for l: Array in LAYERS:
		var mesh := QuadMesh.new()
		mesh.size = Vector2(LAYER_SIZE, LAYER_SIZE)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# QuadMesh lies in XY: the island plane.
		mi.position = Vector3(0, 0, l[0])
		var m := ShaderMaterial.new()
		m.shader = sh
		var c: int = l[1]
		m.set_shader_parameter("tint", Color8((c >> 16) & 255, (c >> 8) & 255, c & 255, (c >> 24) & 255))
		m.set_shader_parameter("oct_a", _oct[0])
		m.set_shader_parameter("oct_b", _oct[1])
		m.set_shader_parameter("flip_v", l[4])
		mi.material_override = m
		_pivot.add_child(mi)
		_layers.append(m)


## One cloud frame: four 32×32 octaves of smoothed noise in R, G, B, A
func _noise_frame() -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var oct := []
	for o in 4:
		var raw := PackedFloat32Array()
		raw.resize(1024)
		for i in 1024:
			raw[i] = _rng.randf()
		var sm := PackedFloat32Array()
		sm.resize(1024)
		for i in 1024:
			var side := raw[(i - 32) & 1023] + raw[(i - 1) & 1023] + raw[(i + 1) & 1023] + raw[(i + 32) & 1023]
			var corner := raw[(i - 33) & 1023] + raw[(i - 31) & 1023] + raw[(i + 31) & 1023] + raw[(i + 33) & 1023]
			sm[i] = raw[i] / 4.0 + side / 8.0 + corner / 16.0
		oct.append(sm)
	for i in 1024:
		img.set_pixel(i & 31, i >> 5, Color(oct[0][i], oct[1][i], oct[2][i], oct[3][i]))
	return img


func _build_extra() -> void:
	_extra = VBoxContainer.new()
	_extra.anchor_left = 0.5
	_extra.anchor_right = 0.5
	_extra.anchor_top = 1.0
	_extra.anchor_bottom = 1.0
	_extra.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_extra.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_extra.offset_bottom = -8
	_extra.alignment = BoxContainer.ALIGNMENT_END
	add_child(_extra)
	# Offered places on another allod (not on this island).
	for o: Dictionary in options:
		if String(session.campaign.zone(String(o.zone)).get("allod", "")).to_lower() == allod:
			continue
		var b := Button.new()
		b.text = String(o.title)
		b.disabled = not leader
		b.pressed.connect(func(): picked.emit(o))
		_extra.add_child(b)
	if leader:
		var stay := Button.new()
		stay.text = "Stay here"
		stay.pressed.connect(func(): cancelled.emit())
		_extra.add_child(stay)
	else:
		var l := Label.new()
		l.text = "The party leader chooses the destination."
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		_extra.add_child(l)


# ------------------------------------------------------------------ update

func _process(dt: float) -> void:
	if _pivot == null:
		return
	if _turn != 0:
		angle = fposmod(angle + dt * _turn * PI * 0.25, TAU)
		_update_pivot()
	_t += dt
	if _arrow:
		_arrow.position = _here_pos + Vector3(0, 0, 0.5 - cos(_t * 5.0) * 0.2)
	# Clouds: a new frame every 8 s (16 slices at 2 per second).
	_fade += dt / 8.0
	if _fade >= 1.0:
		_fade -= 1.0
		_oct = [_oct[1], ImageTexture.create_from_image(_noise_frame())]
		for m: ShaderMaterial in _layers:
			m.set_shader_parameter("oct_a", _oct[0])
			m.set_shader_parameter("oct_b", _oct[1])
	for i in _layers.size():
		var l: Array = LAYERS[i]
		_layers[i].set_shader_parameter("fade", _fade)
		_layers[i].set_shader_parameter("offset", Vector2(fmod(_t * float(l[2]), 1.0), l[3]))


func _update_pivot() -> void:
	_pivot.basis = Basis(Vector3(1, 0, 0), TILT) * Basis(Vector3(0, 0, 1), angle)


# ------------------------------------------------------------------ layout

func _k() -> float:
	return size.y / 600.0


## 800×600 rect -> local: the left half keeps to the left edge, the right half
## to the right edge (the 3D island stays centred).
func _r(r: Rect2, right := false) -> Rect2:
	var k := _k()
	var x := size.x - (800.0 - r.position.x) * k if right or r.position.x >= 400.0 else r.position.x * k
	return Rect2(Vector2(x, r.position.y * k), r.size * k)


func _panel(bg: Rect2, frame: Rect2, right := false) -> void:
	_hud.draw_rect(_r(bg, right), Color(0, 0, 0, 0xa0 / 255.0))
	if _ui == null:
		_hud.draw_rect(_r(frame, right), Color(0.6, 0.45, 0.25), false, 3.0)
		return
	var w := 5.0
	var f := frame
	_strip(Vector2(f.position.x, f.position.y + w * 0.5), Vector2(f.end.x, f.position.y + w * 0.5), w, right)
	_strip(Vector2(f.position.x, f.end.y - w * 0.5), Vector2(f.end.x, f.end.y - w * 0.5), w, right)
	_strip(Vector2(f.position.x + w * 0.5, f.position.y), Vector2(f.position.x + w * 0.5, f.end.y), w, right)
	_strip(Vector2(f.end.x - w * 0.5, f.position.y), Vector2(f.end.x - w * 0.5, f.end.y), w, right)


func _strip(from: Vector2, to: Vector2, width: float, right: bool) -> void:
	var d := (to - from).normalized().orthogonal() * width * 0.5
	var ref := _r(Rect2(from, Vector2.ZERO), right).position - from * _k()
	var pts := PackedVector2Array()
	for p in [from - d, to - d, to + d, from + d]:
		pts.append(p * _k() + ref)
	var s := _ui.get_size()
	var uv := FRAME_UV
	var uvs := PackedVector2Array([uv.position / s, Vector2(uv.end.x, uv.position.y) / s, uv.end / s,
		Vector2(uv.position.x, uv.end.y) / s])
	_hud.draw_primitive(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs, _ui)


## text with a 1 px shadow, vertically centred in `r`
## (the map's draws pass DT_VCENTER 4), CInterface3D font 2 (
## Times New Roman, 0.024 × width em).
func _text(r: Rect2, s: String, align := HORIZONTAL_ALIGNMENT_LEFT, right := false) -> void:
	var k := _k()
	var font := Interface800.font()
	var fs := maxi(6, int(round(800.0 * Interface800.FONT_EM[2] * k)))
	var rr := _r(r, right)
	var y := rr.position.y + (rr.size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	_hud.draw_string(font, Vector2(rr.position.x + k, y + k), s, align, rr.size.x, fs, Interface800.SHADOW)
	_hud.draw_string(font, Vector2(rr.position.x, y), s, align, rr.size.x, fs, TEXT)


func _draw_hud() -> void:
	# Allod and date (top-left).
	_panel(Rect2(20, 20, 150, 50), Rect2(15, 15, 160, 60))
	_text(Rect2(20, 25, 150, 20), GameData.text("allod " + allod).get_slice("\n", 0).strip_edges(), HORIZONTAL_ALIGNMENT_CENTER)
	var st := session.state
	var mins := int(st.world_time * 60.0)
	var day := GameData.text("string save_day").strip_edges()
	_text(Rect2(20, 45, 150, 20), "%s  %d,  %d:%02d" % [day if day else "Day", st.day, mins / 60, mins % 60], HORIZONTAL_ALIGNMENT_CENTER)
	# Buttons.
	if _ui:
		for b: Array in [BTN_LEFT, BTN_RIGHT] + ([] if _nocamp else [BTN_CAMP]):
			_hud.draw_texture_rect_region(_ui, _r(b[0]), b[1])
	# Hovered place (top-right).
	if _hover < 0:
		return
	var name := ""
	var quests := []
	if _hover_brief:
		name = session.zone_title(_briefs[_hover].id)
	else:
		name = session.zone_title(_pieces[_hover].id)
		quests = _pieces[_hover].quests
	var n := quests.size()
	_panel(Rect2(400, 20, 380, 55 + 20 * n), Rect2(395, 15, 390, 65 + 20 * n), true)
	_text(Rect2(410, 30, 290, 40), name, HORIZONTAL_ALIGNMENT_LEFT, true)
	for i in n:
		_text(Rect2(420, 60 + 20 * i, 330, 20), quests[i], HORIZONTAL_ALIGNMENT_LEFT, true)


func _get_tooltip(at: Vector2) -> String:
	var b := _button_at(at)
	if b >= 0 and b <= 2:
		return GameData.text("tip %d" % [BTN_RIGHT, BTN_LEFT, BTN_CAMP][b][2]).strip_edges()
	return ""


# ------------------------------------------------------------------ input

##  order: 0 turn right, 1 turn left, 2 camp, 3.. briefs; -1 none.
func _button_at(p: Vector2) -> int:
	for i in 3:
		if i == 2 and _nocamp:
			continue
		if _r([BTN_RIGHT, BTN_LEFT, BTN_CAMP][i][0]).has_point(p):
			return i
	for i in _briefs.size():
		if _screen_rect(_briefs[i].node).has_point(p):
			return i + 3
	return -1


## Screen bounding box of a figure.
func _screen_rect(n: Node3D) -> Rect2:
	var r := Rect2()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var a := mi.get_aabb()
		for i in 8:
			var p := _cam.unproject_position(mi.global_transform * a.get_endpoint(i))
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
	var s := size / Vector2(_vp.size) if _vp.size.x > 0 else Vector2.ONE
	return Rect2(r.position * s, r.size * s)


## The island piece under the pointer (the original renders an id buffer).
func _piece_at(p: Vector2) -> int:
	var s := Vector2(_vp.size) / size if size.x > 0 else Vector2.ONE
	var from := _cam.project_ray_origin(p * s)
	var dir := _cam.project_ray_normal(p * s)
	var best := INF
	var hit := -1
	for i in _pieces.size():
		for pair: Array in _pieces[i].faces:
			var mi: MeshInstance3D = pair[0]
			var inv := mi.global_transform.affine_inverse()
			var o := inv * from
			var d := (inv.basis * dir)
			var f: PackedVector3Array = pair[1]
			for t in range(0, f.size(), 3):
				var h = Geometry3D.ray_intersects_triangle(o, d, f[t], f[t + 1], f[t + 2])
				if h != null:
					var dist := from.distance_to(mi.global_transform * (h as Vector3))
					if dist < best:
						best = dist
						hit = i
	return hit


func _piece_of(id: String) -> int:
	for i in _pieces.size():
		if _pieces[i].id == id:
			return i
	return -1


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		if not _drag:
			_on_move(e.position)
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_RIGHT:
			if e.pressed and not _drag:
				_drag_start()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_on_press(e.position)
			else:
				_turn = 0
		accept_event()


## a right drag hides the cursor and turns the island; the
## release shows it again where it was.
func _drag_start() -> void:
	_drag = true
	_drag_from = get_viewport().get_mouse_position()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _drag_end() -> void:
	if not _drag:
		return
	_drag = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.warp_mouse(_drag_from)


func _input(e: InputEvent) -> void:
	if not _drag:
		return
	if e is InputEventMouseMotion:
		angle = fposmod(angle + e.relative.x / 300.0, TAU)
		_update_pivot()
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT and not e.pressed:
		_drag_end()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_drag_end()


## Keys (screen 4 widget): Esc opens the game menu; H shows the
## screen's tutorial, "global_map" or "global_map_nocamp" when GS var
## i.nocamp is 1.
func _unhandled_key_input(e: InputEvent) -> void:
	if not is_visible_in_tree() or not (e is InputEventKey and e.pressed and not e.echo):
		return
	if e.keycode == KEY_ESCAPE:
		menu.emit()
	elif EIKeymap.action(e.keycode) == "tutorial_script":
		help.emit("global_map_nocamp" if _nocamp else "global_map")
	elif EIKeymap.action(e.keycode) in ["quicksave", "quickload"]:
		quick.emit(EIKeymap.action(e.keycode))
	else:
		return
	get_viewport().set_input_as_handled()


func _on_move(p: Vector2) -> void:
	var h := -1
	var brief := false
	if _turn == 0:
		var b := _button_at(p)
		if b > 2:
			h = b - 3
			brief = true
		elif b < 0:
			h = _piece_at(p)
			if _link and h >= 0 and _pieces[h].link >= 0:
				h = _pieces[h].link
				brief = true
	if h >= 0 and not brief and _pieces[h].state == 0:
		h = -1
	if h != _hover or brief != _hover_brief:
		_hover = h
		_hover_brief = brief
		_apply_highlight()
		_hud.queue_redraw()
	if h < 0:
		_last_name = ""
		return
	var name: String = (_briefs[h] if brief else _pieces[h]).id
	if name != _last_name:
		_sound("zone")
	_last_name = name


## textures and tints by state, highlight on the hovered place.
func _apply_highlight() -> void:
	var hz := -1
	var hb := -1
	if _hover >= 0:
		if _hover_brief:
			hb = _hover
			if _link:
				hz = _briefs[_hover].zone
		else:
			hz = _hover
			if _link:
				hb = _pieces[_hover].link
	for i in _pieces.size():
		var pc: Dictionary = _pieces[i]
		var m: StandardMaterial3D = pc.mats[0]
		if pc.state == 0:
			m.albedo_texture = _tex_grey
			m.albedo_color = Color.WHITE
			continue
		m.albedo_texture = _tex_map
		var c := _highlight if i == hz else Color.WHITE
		if pc.state == 2:
			c = Color(c.r * 0.5, c.g * 0.5, c.b * 0.5)
		m.albedo_color = c
	for i in _briefs.size():
		(_briefs[i].mats[0] as StandardMaterial3D).albedo_color = _highlight if i == hb else Color.WHITE


func _on_press(p: Vector2) -> void:
	var b := _button_at(p)
	match b:
		0:
			_turn = -1
			_sound("move")
			return
		1:
			_turn = 1
			_sound("move")
			return
		2:
			_sound("transit")
			camp.emit()
			return
	var id := ""
	if b > 2:
		id = _briefs[b - 3].id
	else:
		var i := _piece_at(p)
		if i < 0 or _pieces[i].state == 0:
			return
		_sound("ok")
		if not (_link and _pieces[i].link >= 0):
			open_objectives(_pieces[i].id)
			return
		# Gipat: a piece linked to its village travels there.
		id = _briefs[_pieces[i].link].id
	if b > 2:
		_sound("ok")
	# A village: its route, straight away (no objectives screen).
	var o := _offer(id)
	if o.is_empty() or not leader:
		return
	picked.emit(o)


## The quickest offered route to `id` (Session travel_options).
func _offer(id: String) -> Dictionary:
	var best := {}
	for o: Dictionary in options:
		if String(o.zone) == id and (best.is_empty() or float(o.get("hours", 0.0)) < float(best.get("hours", 0.0))):
			best = o
	return best


##  in travel mode: the zone objectives screen over the map; ✓
## travels (leader only), ✗ / Esc comes back.
func open_objectives(id: String) -> ZoneObjectives:
	close_objectives()
	objectives = ZoneObjectives.new()
	objectives.setup(session, id, options, leader)
	objectives.back.connect(close_objectives)
	if leader:
		objectives.confirmed.connect(func(o: Dictionary): picked.emit(o))
	add_child(objectives)
	_hover = -1
	_apply_highlight()
	_hud.visible = false
	_extra.visible = false
	return objectives


func close_objectives() -> void:
	if objectives:
		objectives.queue_free()
		objectives = null
	_hud.visible = true
	_extra.visible = true


func _sound(name: String) -> void:
	var s := AudioStreamPlayer.new()
	s.bus = "SFX"
	s.stream = EIAudio.sfx("buttons\\globalmap\\%s.wav" % name)
	add_child(s)
	s.play()
	s.finished.connect(s.queue_free)
