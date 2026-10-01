extends Node
## Locates and opens the player's original Evil Islands installation.
## Nothing from the original game is shipped; everything is read at runtime.

const CONFIG_PATH := "user://settings.cfg"
## Files that must exist in a valid installation (relative to its root).
const REQUIRED := ["res/textures.res", "res/figures.res", "res/redress.res", "res/database.res",
	"res/texts.res", "maps/zone1.mpr", "maps/zone1.mob"]

var root := ""
var textures: EIResArchive
var figures: EIResArchive
var redress: EIResArchive
## menus.res: the 3D menu signposts (models, animations and their textures).
var menus: EIResArchive
var db: EIDatabase
var texts: EIResArchive
## config/ai.reg: the original RPG / AI tuning constants ({section: {key: value}}).
var ai_reg := {}
## aiinfo.res tiledesc.reg by ground type: {Name, Speed (/1024, -1 = impassable),
## CostMul, StepLook, StepSmell, StepSound (%)}.
var ground_types := {}
var player_name := "Player"
## Co-op hero prototype this player wants (npcs table "Human Mercenary ...").
var hero_class := "Human Mercenary Warrior"
## Game difficulty (options menu of the original): 0 normal, 1 easy. Indexes the
## ai.reg [DifficultyLevels] arrays; co-op always plays at 0 (xx).
var difficulty := 0

## The options screen of the original: table, 26 rows
## of [name, kind (0 slider, 1 on/off), max, group, row]. Groups:
## 0 video, 1 sound, 2 sens, 3 game (4..10 are key bindings; show_tutorial is
## listed under 10 "windows" in the table). Labels are texts.res "string
## option_<name>". Last column: the default slider / switch value, from the
## settings constructor through the screen's load
## (e.g. power_kbd = ScrollPowerKeyboard 0.5 × 50, brightness = (0 + 1) × 50).
const OPTIONS := [
	["volume_sfx", 0, 100, 1, 0, 100], ["volume_stream", 0, 100, 1, 1, 100],
	["volume_voice", 0, 100, 1, 2, 100], ["power_kbd", 0, 100, 2, 0, 25],
	["power_mouse", 0, 100, 2, 1, 50], ["scroll_border", 0, 10, 2, 2, 5],
	["rubber_select", 0, 10, 2, 3, 2],
	["marks", 1, 2, 0, 4, 1], ["footprints", 1, 2, 0, 5, 1],
	["select_type", 1, 2, 0, 6, 0], ["show_path", 1, 2, 0, 7, 1],
	["brightness", 0, 100, 0, 10, 50], ["contrast", 0, 100, 0, 11, 50],
	["gamma", 0, 100, 0, 12, 50], ["show_flying_hp", 1, 2, 0, 8, 1],
	["show_tutorial", 1, 2, 10, 11, 1], ["autosave", 1, 2, 3, 11, 1],
	["tooltip_time", 0, 20, 2, 4, 2], ["switch_filters", 1, 2, 3, 12, 1],
	["camera_reverse_x", 1, 2, 2, 6, 0], ["camera_reverse_y", 1, 2, 2, 7, 0],
	["reverse_stereo", 1, 2, 1, 4, 0], ["difficulty", 1, 2, 3, 0, 0],
	# Remake-only rendering switches (group 11: the sub-page reached from the
	# Graphics page, not in the original's table): see REMAKE_OPTIONS for their
	# labels; all default on.
	["gfx_sky", 1, 2, 11, 0, 1], ["gfx_water", 1, 2, 11, 1, 1], ["gfx_wind", 1, 2, 11, 2, 1],
	["gfx_volumetric", 1, 2, 11, 3, 1], ["gfx_terrain", 1, 2, 11, 4, 1],
	["gfx_heat_haze", 1, 2, 11, 5, 1], ["gfx_ssao", 1, 2, 11, 6, 1], ["gfx_bloom", 1, 2, 11, 7, 1],
	["gfx_far_view", 1, 2, 11, 8, 1], ["gfx_edge_fade", 1, 2, 11, 9, 1],
	["gfx_outer_land", 1, 2, 11, 10, 1],
	# Second remake graphics page (group 12, "More effects…" from page 11).
	["gfx_hd_textures", 1, 2, 12, 0, 1], ["gfx_soft_particles", 1, 2, 12, 1, 1],
	["gfx_lit_particles", 1, 2, 12, 2, 1], ["gfx_contact_shadows", 1, 2, 12, 3, 1],
	["gfx_torch_glow", 1, 2, 12, 4, 1],
	# Remake display rows (DISPLAY_CHOICES): on the Graphics page in the rows
	# of the original's three shadow switches (0..2, now fixed on, see
	# FIXED_OPTIONS) and the free rows 3 and 9; render scale on the remake page.
	["display_mode", 1, 3, 0, 0, 1], ["resolution", 1, 1, 0, 1, 0], ["fps_limit", 1, 8, 0, 2, 0],
	["vsync", 1, 3, 0, 3, 1], ["show_fps", 1, 2, 0, 9, 0], ["render_scale", 1, 8, 11, 11, 4],
	# Remake camera rows (CameraRig, CameraFade) on the Sensitivity page, in its
	# free row 5 and rows 8..13: style (0 original, 1 modern), the modern
	# camera's pan / turn / zoom speeds (50 = ×1), follow, see-through, WASD.
	["camera_style", 1, 2, 2, 5, 1], ["cam_pan_speed", 0, 100, 2, 8, 50],
	["cam_rotate_speed", 0, 100, 2, 9, 50], ["cam_zoom_speed", 0, 100, 2, 10, 50],
	["cam_follow", 1, 2, 2, 11, 1], ["cam_see_through", 1, 2, 2, 12, 1], ["cam_wasd", 1, 2, 2, 13, 0],
	# Remake co-op host settings on the Game page (free rows 2 and 3): full
	# experience for every party member (XpRules), monster scaling to the
	# player count (MobScaling: Off / Light / Normal / Strong).
	["coop_full_xp", 1, 2, 3, 2, 1], ["coop_scale", 1, 4, 3, 3, 2],
	# Remake: the host opens its port on the router (UpnpPort), Game page row 4.
	["net_upnp", 1, 2, 3, 4, 1],
]
## The original's speed / quality switches (the original rows shadow_units
## shadow_buildings, shadow_flora) are not offered: always at their best.
const FIXED_OPTIONS := {"shadow_units": 1, "shadow_buildings": 1, "shadow_flora": 1}
## Labels of the remake's multiple-choice rows (value = index); "resolution"
## is built from the monitor (resolutions()).
const DISPLAY_CHOICES := {
	"display_mode": ["Windowed", "Fullscreen", "Borderless fullscreen"],
	"fps_limit": ["Off", "30", "60", "120", "144", "165", "240", "Display refresh"],
	"vsync": ["Off", "On", "Adaptive"],
	"render_scale": ["50 %", "67 %", "75 %", "85 %", "100 %", "125 %", "150 %", "200 %"],
	"camera_style": ["Original", "Modern"],
	"coop_scale": ["Off", "Light", "Normal", "Strong"],
}
const FPS_LIMITS := [0, 30, 60, 120, 144, 165, 240, -1]
const RENDER_SCALES := [0.5, 0.67, 0.75, 0.85, 1.0, 1.25, 1.5, 2.0]
## Sizes offered besides the monitor's own (those that fit it).
const COMMON_SIZES := [Vector2i(800, 600), Vector2i(1024, 768), Vector2i(1280, 720),
	Vector2i(1280, 800), Vector2i(1280, 1024), Vector2i(1366, 768), Vector2i(1440, 900),
	Vector2i(1600, 900), Vector2i(1680, 1050), Vector2i(1920, 1080), Vector2i(1920, 1200),
	Vector2i(2560, 1080), Vector2i(2560, 1440), Vector2i(2560, 1600), Vector2i(3440, 1440),
	Vector2i(3840, 2160)]
## The chosen resolution, "native" or "<w>x<h>" (settings.cfg [display]).
var resolution_size := "native"
## Option groups (the original table): 0..3 settings, 4..10 key bindings
## (EIKeymap.ACTIONS); "graphics" (11) is the remake's own sub-page of video.
const OPTION_GROUPS := ["video", "sound", "sens", "game", "select", "actions", "camera", "items",
	"spells", "cshots", "windows", "graphics", "graphics2"]
## Labels and tips of the remake's own option rows (texts.res has none).
const REMAKE_OPTIONS := {
	"graphics": ["remake", ""],
	"graphics2": ["remake effects", ""],
	"gfx_hd_textures": ["HD textures", "The original ground and object textures upscaled 2x once at load (edge-preserving Lanczos on the GPU): sharper up close, same colours. Applies from the next zone load."],
	"gfx_soft_particles": ["Soft particles", "Smoke, fire and magic fade softly where they meet the ground and walls instead of cutting through them with a hard line."],
	"gfx_lit_particles": ["Lit smoke and dust", "Smoke, dust and blood take the scene's light: unchanged in daylight, darker at night and in caves instead of glowing."],
	"gfx_contact_shadows": ["Contact shadows", "A soft shadow on the ground under every creature, so figures sit on the ground also in shade, at night and in caves."],
	"gfx_torch_glow": ["Torch and fire glow", "Torches, camp fires and spell lights glow in the night mist (needs Volumetric fog)."],
	"gfx_sky": ["Atmospheric sky", "Sun disc, moon and stars at night over the original sky dome, and the open top of the dome faded into the sky colour; off: the original dome only."],
	"gfx_water": ["Water and lava effects", "Animated waves, refraction, depth colour, shore foam and sun glints on water; glowing, churning lava; off: the plain blended water."],
	"gfx_wind": ["Wind in foliage", "Trees and bushes sway in the wind."],
	"gfx_volumetric": ["Volumetric fog / light shafts", "Light mist lit by the sun (shafts through the trees at dawn and dusk) and the torches."],
	"gfx_terrain": ["Terrain detail", "Fine procedural relief on the ground up close."],
	"gfx_heat_haze": ["Heat haze", "Air shimmering above torches and camp fires."],
	"gfx_ssao": ["Ambient occlusion", "Soft contact shadows (SSAO)."],
	"gfx_bloom": ["Bloom", "Glow around bright lights."],
	"gfx_edge_fade": ["Map edge fade", "The last few metres of land at the map edge fade into the sky colour instead of ending in a hard edge."],
	"gfx_outer_land": ["Outer landscape", "Low-detail land and water continue beyond the map edge and melt into the fog, instead of the map ending over the sky (replaces the edge fade while on)."],
	"display_mode": ["Display mode", "Windowed, fullscreen, or a borderless window covering the screen."],
	"resolution": ["Resolution", "Window size when windowed; in fullscreen the 3D view is rendered at this size and scaled to the screen (the interface stays sharp)."],
	"fps_limit": ["Frame rate limit", "Highest frames per second; Display refresh = the monitor's refresh rate."],
	"vsync": ["VSync", "Wait for the monitor's refresh (no tearing); adaptive tears only when a frame is late."],
	"show_fps": ["Show FPS", "A frames-per-second counter in the top right corner."],
	"render_scale": ["Render scale", "Resolution of the 3D view relative to the window: below 100 % faster, above it sharper (supersampling)."],
	"gfx_far_view": ["Far view", "See 260 m instead of 100 m, with a long soft fade into the fog; off: the original 100 m view with its short fog band."],
	"camera_style": ["Camera style", "Original: the 2000 game's camera. Modern: smooth, eased panning, zoom and turning (middle drag or Delete / End), the view tilting down as you zoom out, never inside a hill, optional hero follow and see-through objects."],
	"cam_pan_speed": ["Camera pan speed (modern)", "Speed of the modern camera's panning (keys, screen edges)."],
	"cam_rotate_speed": ["Camera turn speed (modern)", "Speed of the modern camera's turning and tilting (drag, keys)."],
	"cam_zoom_speed": ["Camera zoom speed (modern)", "Speed of the modern camera's zoom (wheel, keys)."],
	"cam_follow": ["Camera follows the hero", "Modern camera: it follows the selected hero; pan away freely, and it comes back when the hero starts moving. Home or a double-click on a portrait centres it."],
	"cam_see_through": ["See-through objects", "Modern camera: trees, houses and rocks that hide your heroes fade to see-through."],
	"coop_full_xp": ["Co-op: full experience for every party member", "Co-op host: every player's hero and every mercenary gets the whole experience of a kill or quest. Off: the original network rule (shared among the players' heroes by experience, mercenaries get none). Single player is not affected."],
	"coop_scale": ["Co-op: scale monsters to player count", "Co-op host: monsters get more health and hit harder for each player beyond the first (Light +25 % health / +12.5 % damage, Normal +50 % / +25 %, Strong +100 % / +50 % per extra player). Off: as the original."],
	"net_upnp": ["Co-op: open the port on the router (UPnP)", "Co-op host: asks your router to forward UDP port 27015 to this computer so friends can join over the internet, and shows your external IP address to give them. The forwarding is removed when you stop hosting. Off: forward the port by hand."],
	"cam_wasd": ["WASD pans the camera", "Modern camera: W / A / S / D pan the camera; their own keys (weapon 2, Aggressive, Use/Steal) then need other keys (Options, key pages)."],
	"camera_rotate_left": ["Turn camera left", "Modern camera: turns the camera (Divinity: Original Sin 2 uses Delete)."],
	"camera_rotate_right": ["Turn camera right", "Modern camera: turns the camera (Divinity: Original Sin 2 uses End)."],
}
## Options the remake applies (a row missing here is greyed out on the Options
## screen). "marks" = EnableBloodprints and "footprints" = EnableFootprints
## switch the ground marks (GroundMarks).
const OPTIONS_APPLIED := ["volume_sfx", "volume_stream", "volume_voice", "power_kbd",
	"power_mouse", "scroll_border", "rubber_select", "marks", "footprints", "select_type", "show_path", "brightness", "contrast", "gamma",
	"show_flying_hp", "show_tutorial", "autosave", "tooltip_time", "switch_filters",
	"camera_reverse_x", "camera_reverse_y", "reverse_stereo", "difficulty",
	"gfx_sky", "gfx_water", "gfx_wind", "gfx_volumetric", "gfx_terrain", "gfx_heat_haze",
	"gfx_ssao", "gfx_bloom", "gfx_far_view", "gfx_edge_fade", "gfx_outer_land",
	"gfx_hd_textures", "gfx_soft_particles", "gfx_lit_particles", "gfx_contact_shadows", "gfx_torch_glow",
	"display_mode", "resolution", "fps_limit", "vsync", "show_fps", "render_scale",
	"camera_style", "cam_pan_speed", "cam_rotate_speed", "cam_zoom_speed", "cam_follow",
	"cam_see_through", "cam_wasd", "coop_full_xp", "coop_scale", "net_upnp"]
signal options_changed
const GFX_REV := 2
## Values reset once when an older settings file is loaded, by the revision
## that introduced them: 1 object shadows on (remake default; the 2000
## defaults were off for speed), 2 defaults / scales corrected from the original.
const GFX_DEFAULTS := {
	1: {"shadow_buildings": 1, "shadow_flora": 1},
	2: {"power_kbd": 25, "rubber_select": 2, "brightness": 50, "contrast": 50, "gamma": 50,
		"tooltip_time": 2},
}
var _gfx_rev := GFX_REV
var options := {}

var _texture_cache := {}
var _text_cache := {}


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		root = cfg.get_value("game", "root", "")
		player_name = cfg.get_value("player", "name", "Player")
		hero_class = cfg.get_value("player", "hero", hero_class)
		difficulty = cfg.get_value("game", "difficulty", 0)
		resolution_size = String(cfg.get_value("display", "resolution", "native"))
	for o: Array in OPTIONS:
		options[o[0]] = cfg.get_value("options", o[0], o[5]) if cfg.has_section("options") else o[5]
	options.difficulty = difficulty
	options.resolution = maxi(0, resolutions().find(_res_from_string(resolution_size)))
	var rev := int(cfg.get_value("remake", "gfx", 0))
	if rev < GFX_REV:
		for r: int in GFX_DEFAULTS:
			if rev < r:
				for k: String in GFX_DEFAULTS[r]:
					options[k] = GFX_DEFAULTS[r][k]
		_gfx_rev = GFX_REV
		if root != "":
			save_settings()
	_setup_buses()
	_apply_audio()
	_setup_display()
	_apply_display()
	_apply_window_late.call_deferred()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ei-path="):
			root = arg.trim_prefix("--ei-path=")


## Returns an empty string when `path` is a usable install, otherwise the reason.
static func validate(path: String) -> String:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return "Folder does not exist."
	for rel: String in REQUIRED:
		if not FileAccess.file_exists(path.path_join(rel)):
			return "Missing %s - point this at the Evil Islands install folder (the one containing game.exe)." % rel
	return ""


func open(path: String) -> String:
	var err := validate(path)
	if err:
		return err
	root = path
	textures = EIResArchive.open_path(path.path_join("res/textures.res"))
	figures = EIResArchive.open_path(path.path_join("res/figures.res"))
	redress = EIResArchive.open_path(path.path_join("res/redress.res"))
	var dbres := EIResArchive.open_path(path.path_join("res/database.res"))
	if textures == null or figures == null or redress == null or dbres == null:
		return "Could not read the game archives in res/."
	_open_text_archives()   # first: sets the code page the database strings use
	db = EIDatabase.load_from(dbres)
	ai_reg = EIRegFile.parse(FileAccess.get_file_as_bytes(path.path_join("config/ai.reg")))
	ground_types.clear()
	var aiinfo := EIResArchive.open_path(path.path_join("res/aiinfo.res"))
	if aiinfo and aiinfo.has("tiledesc.reg"):
		var reg := EIRegFile.parse(aiinfo.read("tiledesc.reg"))
		for k in reg:
			if String(k).is_valid_int():
				ground_types[int(k)] = reg[k]
	_text_cache.clear()
	_texture_cache.clear()
	save_settings()
	return ""


# ------------------------------------------------------------------ edition
# The original has no language choice: each edition ships its own res/texts.res,
# textslmp.res, menus.res (signpost label textures), speech.res and outro.res,
# and the remake uses those of the copy supplied.

## Path of res/<name> in the game folder.
func res_path(name: String) -> String:
	return root.path_join("res/" + name)


func _open_text_archives() -> void:
	texts = EIResArchive.open_path(res_path("texts.res"))
	menus = EIResArchive.open_path(res_path("menus.res"))
	EIText.code_page = EIText.detect_code_page(texts)
	_text_cache.clear()
	_texture_cache.clear()


func is_open() -> bool:
	return textures != null


func map_names() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(root.path_join("maps")):
		if f.get_extension().to_lower() == "mpr":
			out.append(f.get_basename())
	out.sort()
	return out


func read_file(rel: String) -> PackedByteArray:
	var path := root.path_join(rel)
	# The game names files case-insensitively (Windows): scripts say
	# AddMob("Zone3ObrVoev.mob") for maps/zone3obrvoev.mob.
	if not FileAccess.file_exists(path) and FileAccess.file_exists(root.path_join(rel.to_lower())):
		path = root.path_join(rel.to_lower())
	return FileAccess.get_file_as_bytes(path)


func load_image(name: String) -> Image:
	if not textures.has(name + ".mmp") and menus and menus.has(name + ".mmp"):
		return EIMmp.decode(menus.read(name + ".mmp"))
	return EIMmp.decode(textures.read(name + ".mmp"))


## A model file (.mod/.fig/.bon/.anm) from figures.res, or menus.res for the menu signposts.
func has_figure(file: String) -> bool:
	return figures.has(file) or (menus != null and menus.has(file))


func read_figure(file: String) -> PackedByteArray:
	if figures.has(file) or menus == null:
		return figures.read(file)
	return menus.read(file)


## Cached, mipmapped texture for objects; null if missing.
func get_texture(name: String) -> Texture2D:
	name = name.to_lower()
	if not _texture_cache.has(name):
		var img := load_image(name)
		var tex: Texture2D = null
		if img:
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
		_texture_cache[name] = tex
	return _texture_cache[name]


## A text entry from texts.res (e.g. "quest q0g", "briefing z1"), decoded; "" if missing.
func text(key: String) -> String:
	key = key.to_lower()
	if not _text_cache.has(key):
		var b := texts.read(key) if texts else PackedByteArray()
		_text_cache[key] = EIText.ansi(b).replace("\r", "") if not b.is_empty() else ""
	return _text_cache[key]


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "root", root)
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "hero", hero_class)
	cfg.set_value("game", "difficulty", difficulty)
	for k in options:
		cfg.set_value("options", k, options[k])
	cfg.set_value("remake", "gfx", _gfx_rev)
	cfg.set_value("display", "resolution", resolution_size)
	cfg.save(CONFIG_PATH)


func option(name: String) -> int:
	if FIXED_OPTIONS.has(name):
		return FIXED_OPTIONS[name]
	return int(options.get(name, 0))


func set_option(name: String, value: int) -> void:
	options[name] = value
	if name == "difficulty":
		difficulty = value
	if name == "resolution":
		var list := resolutions()
		var size: Vector2i = list[clampi(value, 0, list.size() - 1)]
		resolution_size = "native" if value <= 0 else "%dx%d" % [size.x, size.y]
	_apply_audio()
	_apply_display()
	_apply_window()
	save_settings()
	options_changed.emit()


## Audio buses for the three volume sliders.
func _setup_buses() -> void:
	for b in ["SFX", "Music", "Voice"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, b)


func _apply_audio() -> void:
	for pair in [["SFX", "volume_sfx"], ["Music", "volume_stream"], ["Voice", "volume_voice"]]:
		var i := AudioServer.get_bus_index(pair[0])
		var v := option(pair[1]) / 100.0
		AudioServer.set_bus_mute(i, v <= 0.0)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	# "reverse_stereo" (Reverse_Stereo, settings → sound manager):
	#  006b7700 / 006b92b0 negate the pan of every sound effect
	# sample before AIL_set_sample_pan. Music and speech are not panned. Here
	# the SFX bus swaps its channels: StereoEnhance with pan_pullout −1 maps
	# (l, r) to (r, l).
	var sfx := AudioServer.get_bus_index("SFX")
	var fx := -1
	for j in AudioServer.get_bus_effect_count(sfx):
		if AudioServer.get_bus_effect(sfx, j) is AudioEffectStereoEnhance:
			fx = j
	if fx < 0:
		var swap := AudioEffectStereoEnhance.new()
		swap.pan_pullout = -1.0
		swap.time_pullout_ms = 0.0
		AudioServer.add_bus_effect(sfx, swap)
		fx = AudioServer.get_bus_effect_count(sfx) - 1
	AudioServer.set_bus_effect_enabled(sfx, fx, option("reverse_stereo") != 0)


var _gamma_layer: CanvasLayer
var _gamma_mat: ShaderMaterial

## Brightness / contrast / gamma: the original sets a hardware gamma ramp over the
## whole screen (called with settings
##  = slider × 0.02 − 1). The remake applies
## the same ramp in a full-screen pass above everything.
const _GAMMA_SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float bright;
uniform float k = 1.0;
uniform float off;
uniform float e = 1.0;
void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	c = clamp(pow(max(c, vec3(0.0)), vec3(e)) * k + off, 0.0, 1.0);
	COLOR = vec4(clamp(c + bright, 0.0, 1.0), 1.0);
}
"""


var _tips: TipLayer

## Tooltips with the option "tooltip_time" (ToolTip Time, settings =
## slider × 0.25 s): the interface shows a control's tip once
## the pointer has rested on it that long (compares its hover time
##  with it); 0 turns tips off. Godot's own tooltip delay cannot change
## at run time, so project.godot switches it off and this layer shows the
## controls' tooltips (Control.get_tooltip, theme types TooltipPanel /
## TooltipLabel) instead.
class TipLayer extends CanvasLayer:
	var delay := 0.5
	var _ctrl: Control
	var _mouse := Vector2.INF
	var _since := 0
	var _text := ""
	var _panel := PanelContainer.new()
	var _label := Label.new()

	func _ready() -> void:
		layer = 127
		process_mode = Node.PROCESS_MODE_ALWAYS
		_panel.theme_type_variation = &"TooltipPanel"
		_label.theme_type_variation = &"TooltipLabel"
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(_label)
		_panel.visible = false
		add_child(_panel)

	func _input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed or e is InputEventKey and e.pressed:
			_hide()
			_since = Time.get_ticks_msec()

	func _process(_dt: float) -> void:
		var vp := get_viewport()
		var mp := vp.get_mouse_position()
		var c := vp.gui_get_hovered_control()
		var now := Time.get_ticks_msec()
		if c != _ctrl or (mp != _mouse and not _panel.visible):
			_ctrl = c
			_since = now
			_hide()
		_mouse = mp
		if c == null or delay <= 0.0 or not c.is_visible_in_tree() \
				or (not _panel.visible and now - _since < delay * 1000.0):
			_hide()
			return
		var t := c.get_tooltip(c.get_global_transform_with_canvas().affine_inverse() * mp)
		if t.strip_edges() == "":
			_hide()
			return
		if t != _text or not _panel.visible:
			_text = t
			_label.text = t
			_panel.visible = true
			_panel.reset_size()
			var sz := _panel.get_combined_minimum_size()
			var area := vp.get_visible_rect().size
			var p := mp + Vector2(10, 16)
			_panel.position = Vector2(clampf(p.x, 0, maxf(0, area.x - sz.x)),
				clampf(p.y, 0, maxf(0, area.y - sz.y)) if p.y + sz.y <= area.y else maxf(0, mp.y - sz.y - 4))

	func _hide() -> void:
		_panel.visible = false
		_text = ""


func _setup_display() -> void:
	_tips = TipLayer.new()
	add_child(_tips)
	_gamma_layer = CanvasLayer.new()
	_gamma_layer.layer = 128
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = _GAMMA_SHADER
	_gamma_mat = ShaderMaterial.new()
	_gamma_mat.shader = sh
	r.material = _gamma_mat
	_gamma_layer.add_child(r)
	add_child(_gamma_layer)


## The ramp for slider values 0..100 (50 = neutral): with
## b, c, g = clamp(slider × 0.02 − 1, −1, 1) × 0.5, a table entry for
## x = i / 255 is clamp(clamp(x^e · k + (1 − k) / 2, 0, 1) + b, 0, 1) where
## k = 1 + 4|c| (its inverse when c < 0) and e = 1 / (1 + 5g) for g > 0,
## 1 / (1 + 0.5g) for g < 0.
static func gamma_ramp(brightness: int, contrast: int, gamma: int) -> Vector4:
	var b := clampf(brightness * 0.02 - 1.0, -1.0, 1.0) * 0.5
	var c := clampf(contrast * 0.02 - 1.0, -1.0, 1.0) * 0.5
	var g := clampf(gamma * 0.02 - 1.0, -1.0, 1.0) * 0.5
	var k := absf(c) * 4.0 + 1.0
	if c < 0.0:
		k = 1.0 / k
	var e := 1.0
	if g > 0.0:
		e = 1.0 / (g * 5.0 + 1.0)
	elif g < 0.0:
		e = 1.0 / (g * 0.5 + 1.0)
	return Vector4(b, k, (1.0 - k) * 0.5, e)


func _apply_display() -> void:
	var r := gamma_ramp(option("brightness"), option("contrast"), option("gamma"))
	if _gamma_layer:
		_gamma_layer.visible = not r.is_equal_approx(Vector4(0, 1, 0, 1))
		_gamma_mat.set_shader_parameter("bright", r.x)
		_gamma_mat.set_shader_parameter("k", r.y)
		_gamma_mat.set_shader_parameter("off", r.z)
		_gamma_mat.set_shader_parameter("e", r.w)
	if _tips:
		_tips.delay = option("tooltip_time") * 0.25


## A value from config/ai.reg ("RPG", "HP Val 1"); lists give their first entry
## unless `index` is set.
func ai_value(section: String, key: String, fallback: float, index := 0) -> float:
	var v = ai_reg.get(section, {}).get(key, null)
	if v is Array or v is PackedFloat32Array or v is PackedInt32Array:
		return float(v[index]) if index < v.size() else fallback
	return float(v) if v != null else fallback


# ------------------------------------------------------------------ window

## Labels of a multiple-choice option row, [] for an on / off switch.
func option_choices(name: String) -> Array:
	if name == "resolution":
		var out := []
		for i in resolutions().size():
			var v: Vector2i = resolutions()[i]
			out.append(("Native (%d × %d)" if i == 0 else "%d × %d") % [v.x, v.y])
		return out
	return DISPLAY_CHOICES.get(name, [])


## The monitor's size first ("native"), then the common sizes that fit it,
## smallest first.
func resolutions() -> Array:
	var native := _screen_size()
	var out := [native]
	for v: Vector2i in COMMON_SIZES:
		if v.x <= native.x and v.y <= native.y and v != native:
			out.append(v)
	return out


func _screen_size() -> Vector2i:
	if DisplayServer.get_name() == "headless":
		return Vector2i(1920, 1080)
	return DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())


static func _res_from_string(s: String) -> Vector2i:
	var p := s.split("x")
	if p.size() == 2 and p[0].is_valid_int() and p[1].is_valid_int():
		return Vector2i(p[0].to_int(), p[1].to_int())
	return Vector2i.ZERO


var _window_state := []


## At start: once the main window is shown (X11 maps it after the first
## frames and would undo an earlier size / mode change).
func _apply_window_late() -> void:
	for i in 3:
		await get_tree().process_frame
	_apply_window()
var _fps_layer: CanvasLayer


## Display mode, resolution, frame-rate limit, VSync, render scale and the FPS
## counter (the remake's display rows); window changes only when they change.
func _apply_window() -> void:
	var list := resolutions()
	var ri := clampi(option("resolution"), 0, list.size() - 1)
	var size: Vector2i = list[ri]
	var mode := clampi(option("display_mode"), 0, 2)
	var fps: int = FPS_LIMITS[clampi(option("fps_limit"), 0, FPS_LIMITS.size() - 1)]
	if fps < 0:
		fps = roundi(DisplayServer.screen_get_refresh_rate()) if DisplayServer.get_name() != "headless" else 60
		fps = fps if fps > 0 else 60
	Engine.max_fps = fps
	var scale: float = RENDER_SCALES[clampi(option("render_scale"), 0, RENDER_SCALES.size() - 1)]
	if mode != 0 and ri > 0:
		scale *= float(size.x) / float(list[0].x)   # fullscreen below native: 3D drawn smaller, scaled up
	var vp := get_tree().root if is_inside_tree() else null
	if vp:
		# Below 100 %: AMD FSR 1.0 (edge-adaptive upscale + sharpening) instead of
		# a blurry bilinear stretch; above it the bilinear downsample supersamples.
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 0.999 else Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = clampf(scale, 0.25, 2.0)
	_show_fps(option("show_fps") != 0)
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode([DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED,
		DisplayServer.VSYNC_ADAPTIVE][clampi(option("vsync"), 0, 2)])
	var state := [mode, size, ri]
	if state == _window_state:
		return
	_window_state = state
	var scr := DisplayServer.window_get_current_screen()
	if mode == 0:
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		var area := DisplayServer.screen_get_usable_rect(scr)
		var s := Vector2i(mini(size.x, area.size.x), mini(size.y, area.size.y))
		DisplayServer.window_set_size(s)
		DisplayServer.window_set_position(area.position + (area.size - s) / 2)
		if ri == 0:   # native: the whole work area (maximised where a window manager runs)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		# Placed over the screen first: without a window manager the
		# fullscreen state alone does not resize the window.
		DisplayServer.window_set_position(DisplayServer.screen_get_position(scr))
		DisplayServer.window_set_size(DisplayServer.screen_get_size(scr))
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if mode == 1
			else DisplayServer.WINDOW_MODE_FULLSCREEN)


class FpsLabel extends Label:
	var _t := 0.0

	func _process(dt: float) -> void:
		_t += dt
		if _t >= 0.25:
			_t = 0.0
			text = "%d FPS" % Engine.get_frames_per_second()


func _show_fps(on: bool) -> void:
	if not on:
		if _fps_layer:
			_fps_layer.visible = false
		return
	if _fps_layer == null:
		_fps_layer = CanvasLayer.new()
		_fps_layer.layer = 126
		_fps_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		var l := FpsLabel.new()
		l.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		l.offset_left = -110
		l.offset_right = -8
		l.offset_top = 4
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_color_override("font_color", Color8(0xe4, 0xd7, 0xa7))
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		_fps_layer.add_child(l)
		add_child(_fps_layer)
	_fps_layer.visible = true
