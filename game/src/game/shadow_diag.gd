extends Node
## On-device sun-shadow diagnostic (remake only, off by default): changes one
## shadow setting at a time so a device that shows unsteady shadows (Adreno,
## GLES3) can tell which one matters. A small label at the top of the screen
## names the active preset, so a screen recording shows it; each change is
## also logged. Turn on with either:
##   the command line:  --shadow-diag=cycle      (every preset in turn, 10 s each)
##                      --shadow-diag=cycle=6    (6 s each)
##                      --shadow-diag=freeze     (one preset by name)
##                      --shadow-diag=atlas=2048,bits=32   (knobs, see below)
##   settings.cfg:      [debug] shadow_diag="cycle"   (same values)
## Knobs: aim=0|1|2 (the sun's shadow direction: 0 held and re-aimed, the
## phone / web default, Game._aim_sun; 1 turned every frame, the desktop
## default as 0.1.7; 2 never re-aimed), roll=0|1 (Game.sun_basis),
## atlas=N (sun and point-light shadow
## atlas), bits=32 (24/32-bit shadow depth instead of 16), filter=-1..3 (hard,
## soft low .. ultra), splits=1|2|4, blend=0|1, bias=B, nbias=N, maxdist=M
## (metres; the splits keep their distances), roll=0 (the shadow map turns
## with the sun, Game.sun_basis off), wind=0 (no foliage sway), off=1 (no sun
## shadow).

const PRESETS := [
	["default", {}],
	["continuous", {"aim": 1}],
	["freeze", {"aim": 2}],
	["atlas2048", {"atlas": 2048}],
	["atlas4096", {"atlas": 4096}],
	["depth32", {"bits": 32}],
	["filter_high", {"filter": 2}],
	["filter_hard", {"filter": -1}],
	["splits2", {"splits": 2}],
	["splits1", {"splits": 1}],
	["noblend", {"blend": 0}],
	["nbias4", {"nbias": 4.0}],
	["noroll", {"roll": 0}],
	["nowind", {"wind": 0}],
	["off", {"off": 1}],
]

var game: Game
var knobs := {}
var label := "custom"
var cycle_s := 0.0
var _index := 0
var _since := 0   # ms (real time: works while paused or slowed)
var _base := {}
var _base_aim := 0
var _base_lock := true
var _label: Label


## The requested diagnostic ("" = off).
static func requested() -> String:
	for a: String in Array(OS.get_cmdline_args()) + Array(OS.get_cmdline_user_args()):
		if a.begins_with("--shadow-diag="):
			return a.trim_prefix("--shadow-diag=")
		if a == "--shadow-diag":
			return "cycle"
	var cfg := ConfigFile.new()
	if cfg.load(GameData.CONFIG_PATH) == OK and cfg.has_section_key("debug", "shadow_diag"):
		return str(cfg.get_value("debug", "shadow_diag"))
	return ""


func _init(g: Game, spec: String) -> void:
	game = g
	name = "ShadowDiag"
	process_mode = Node.PROCESS_MODE_ALWAYS
	if spec.begins_with("cycle"):
		cycle_s = maxf(2.0, float(spec.trim_prefix("cycle=").to_float()) if spec.begins_with("cycle=") else 10.0)
		_select(0)
		return
	for p: Array in PRESETS:
		if p[0] == spec:
			label = spec
			knobs = p[1]
			return
	for kv: String in spec.split(",", false):
		var s := kv.split("=")
		knobs[s[0].strip_edges()] = float(s[1]) if s.size() > 1 else 1.0
	label = spec


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(1, 1, 0))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_font_size_override("font_size", 26)
	layer.add_child(_label)
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 4)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	GameData.options_changed.connect(_apply_quality, CONNECT_DEFERRED)
	_apply_quality()
	print("[shadow_diag] ", label, " ", knobs)


func _select(i: int) -> void:
	_index = i % PRESETS.size()
	label = PRESETS[_index][0]
	knobs = PRESETS[_index][1]
	_since = Time.get_ticks_msec()
	if is_inside_tree():
		_restore()
		_apply_quality()
		print("[shadow_diag] %s %s at %.2f h" % [label, knobs, _hour()])


func _hour() -> float:
	return game.session.state.world_time if game.session and game.session.state else 0.0


## Atlas size, depth bits and filter: Gfx.apply_quality first, then the knobs.
func _apply_quality() -> void:
	Gfx.apply_quality(get_viewport())
	var vp := get_viewport()
	if knobs.has("atlas") or knobs.has("bits"):
		var q := clampi(GameData.option("q_shadows"), 0, 3)
		var atlas: int = int(knobs.get("atlas", [1024, 2048, 2048, 4096][q] if Portability.constrained() else [2048, 4096, 8192, 8192][q]))
		RenderingServer.directional_shadow_atlas_set_size(atlas, int(knobs.get("bits", 16)) != 32)
		vp.positional_shadow_atlas_size = atlas
		vp.positional_shadow_atlas_16_bits = int(knobs.get("bits", 16)) != 32
	if knobs.has("filter"):
		var f := int(knobs.filter)
		var qs: Array[RenderingServer.ShadowQuality] = [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
			RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH, RenderingServer.SHADOW_QUALITY_SOFT_ULTRA]
		RenderingServer.directional_soft_shadow_filter_set_quality(qs[clampi(f + 1, 0, 4)])
		RenderingServer.positional_soft_shadow_filter_set_quality(qs[clampi(f + 1, 0, 4)])


## The sun's own settings back to the game's (between cycle presets).
func _restore() -> void:
	var sun := game._sun
	if sun == null or _base.is_empty():
		return
	for k: String in _base:
		sun.set(k, _base[k])
	game.sun_aim_mode = _base_aim
	game.sun_grid_lock = _base_lock
	EIFigure.set_wind(Gfx.on("gfx_wind"))


func _process(_dt: float) -> void:
	var sun := game._sun
	if sun == null:
		return
	if _base.is_empty():
		_base_aim = game.sun_aim_mode
		_base_lock = game.sun_grid_lock
		for k in ["shadow_enabled", "directional_shadow_mode", "directional_shadow_blend_splits", "shadow_bias",
				"shadow_normal_bias", "directional_shadow_max_distance", "directional_shadow_split_1",
				"directional_shadow_split_2", "directional_shadow_split_3"]:
			_base[k] = sun.get(k)
	if cycle_s > 0.0:
		if Time.get_ticks_msec() - _since >= cycle_s * 1000.0:
			_select(_index + 1)
	# Game._fit_shadows sets range and splits on every option change.
	if not knobs.has("maxdist"):
		for k in ["directional_shadow_max_distance", "directional_shadow_split_1", "directional_shadow_split_2", "directional_shadow_split_3"]:
			_base[k] = sun.get(k)
	_put(sun, "shadow_enabled", not knobs.has("off"))
	_put(sun, "directional_shadow_mode", {1: DirectionalLight3D.SHADOW_ORTHOGONAL, 2: DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS}.get(int(knobs.get("splits", 4)), DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS))
	_put(sun, "directional_shadow_blend_splits", int(knobs.get("blend", 1)) != 0)
	_put(sun, "shadow_bias", float(knobs.get("bias", _base.shadow_bias)))
	_put(sun, "shadow_normal_bias", float(knobs.get("nbias", _base.shadow_normal_bias)))
	if knobs.has("maxdist"):
		var m0: float = _base.directional_shadow_max_distance
		var m := float(knobs.maxdist)
		_put(sun, "directional_shadow_max_distance", m)
		_put(sun, "directional_shadow_split_1", minf(_base.directional_shadow_split_1 * m0 / m, 0.9))
		_put(sun, "directional_shadow_split_2", minf(_base.directional_shadow_split_2 * m0 / m, 0.95))
		_put(sun, "directional_shadow_split_3", minf(_base.directional_shadow_split_3 * m0 / m, 0.98))
	game.sun_aim_mode = int(knobs.get("aim", _base_aim))
	game.sun_grid_lock = int(knobs.get("roll", int(_base_lock))) != 0
	if knobs.has("wind"):
		EIFigure.set_wind(int(knobs.wind) != 0)
	var h := _hour()
	_label.text = "shadow diag: %s%s  %02d:%02d  re-aims %d (%s)  %d fps" % [label,   # l10n: ignore (debug overlay)
		" (%d/%d)" % [_index + 1, PRESETS.size()] if cycle_s > 0.0 else "", int(h), int(fmod(h, 1.0) * 60.0),
		game.sun_reaims, game.sun_reaim_reason, Engine.get_frames_per_second()]


func _put(o: Object, k: String, v: Variant) -> void:
	if o.get(k) != v:
		o.set(k, v)
