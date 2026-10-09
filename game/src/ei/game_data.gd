extends Node
## Locates and opens the player's original Evil Islands installation.
## Nothing from the original game is shipped; everything is read at runtime.

const CONFIG_PATH := "user://settings.cfg"
## Files that must exist in a valid installation (relative to its root).
const REQUIRED := ["res/textures.res", "res/figures.res", "res/redress.res", "res/database.res",
	"res/texts.res", "maps/zone1.mpr", "maps/zone1.mob"]

var root := ""
var campaign_id := CampaignProfile.ORIGINAL
## Both editions may be installed; [game] root is only the active edition.
var campaign_roots: Dictionary = {}
var textures: EIResArchive
var figures: EIResArchive
var redress: EIResArchive
## menus.res: the 3D menu signposts (models, animations and their textures).
var menus: EIResArchive
var db: EIDatabase
var texts: EIResArchive
## res/textsLmp.res: the original loads it next to texts.res at start (:
## both go through into the one text table), so `text` falls back
## to it — the multiplayer names (unit lmp_*, allod names, base briefings).
var texts_lmp: EIResArchive
## The campaign database (res/database.res) while `db` is the multiplayer one.
var _db_main: EIDatabase
## True while `db` is res/databaseLMP.res (use_lmp_database).
var lmp_db := false
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
## Remake placement (user request 2026-10-04): the Graphics page's rows start
## at the top (the original: marks.. show_flying_hp in rows 4..8, its shadow
## switches in 0..2), and brightness / contrast / gamma (the original's Graphics
## rows 10..12) are on the remake's Screen page (group 12).
const OPTIONS := [
	["volume_sfx", 0, 100, 1, 0, 100], ["volume_stream", 0, 100, 1, 1, 100],
	["volume_voice", 0, 100, 1, 2, 100], ["power_kbd", 0, 100, 2, 0, 25],
	["power_mouse", 0, 100, 2, 1, 50], ["scroll_border", 0, 10, 2, 2, 5],
	["rubber_select", 0, 10, 2, 3, 2],
	["marks", 1, 2, 0, 0, 1], ["footprints", 1, 2, 0, 1, 1],
	["select_type", 1, 2, 0, 2, 0], ["show_path", 1, 2, 0, 3, 1],
	["brightness", 0, 100, 12, 9, 50], ["contrast", 0, 100, 12, 10, 50],
	["gamma", 0, 100, 12, 11, 50], ["show_flying_hp", 1, 2, 0, 4, 1],
	["show_tutorial", 1, 2, 10, 11, 1], ["autosave", 1, 2, 3, 11, 1],
	["tooltip_time", 0, 20, 2, 4, 2], ["switch_filters", 1, 2, 3, 12, 1],
	["camera_reverse_x", 1, 2, 2, 6, 0], ["camera_reverse_y", 1, 2, 2, 7, 0],
	["reverse_stereo", 1, 2, 1, 4, 0], ["difficulty", 1, 2, 3, 0, 0],
	# Everything below is the remake's own (not in the original's table): the
	# Screen tab (group 12) and the Remake tab's sub-pages (group 11 lists
	# them, see OptionsPanel.SECTIONS; labels and tips in REMAKE_OPTIONS).
	# Settings keys are the names; group / row are placement only.
	# Screen (group 12; rows 9..11 the original's brightness / contrast / gamma).
	# Its rows are applied at once like the volumes.
	["display_mode", 1, 3, 12, 0, 1], ["resolution", 1, 1, 12, 1, 0], ["render_scale", 1, 8, 12, 2, 4],
	# Render quality (not gfx_*, so the Original look preset leaves them;
	# Gfx.apply_quality).
	["q_aa", 1, 6, 12, 3, 1], ["fps_limit", 1, 8, 12, 4, 0], ["vsync", 1, 3, 12, 5, 1],
	# Units drawn between their 60 Hz physics steps (default on). Visual only:
	# the game state is unchanged; not gfx_*, so the preset leaves it.
	["phys_interp", 1, 2, 12, 6, 1], ["show_fps", 1, 2, 12, 7, 0],
	# The renderer on Android (RendererChoice: 0 Compatibility, 1 Forward+,
	# 2 Mobile); hidden elsewhere. Not gfx_*: the Original look preset and the
	# graphics test leave it.
	["renderer", 1, 3, 12, 12, 0],
	# The graphics test on the first start / a new GPU (GfxDetect), on the
	# Graphics page (row 6; row 7 "Detect best settings", 8 "Original look").
	# Not gfx_*: the Original look preset leaves it.
	["auto_graphics", 1, 2, 0, 6, 1],
	# World and textures (group 13). Terrain and vegetation have their own
	# page (22). Native map-border fog is always active; see Gfx.BORDER_FOG.
	["gfx_hd_textures", 1, 2, 13, 0, 1], ["gfx_materials", 1, 2, 13, 1, 1],
	# Sharper unit texture filtering (EIUnitModel.SHARP_FETCH); characters
	# wear their HUD face model (DetailedHead).
	["gfx_sharp_units", 1, 2, 13, 2, 1], ["gfx_detailed_heads", 1, 2, 13, 3, 1],
	["gfx_sky", 1, 2, 13, 4, 1], ["gfx_far_view", 1, 2, 13, 5, 1],
	["q_aniso", 1, 5, 13, 6, 4],
	# Terrain and vegetation (group 22): ground detail, cover and interaction.
	["gfx_terrain", 1, 2, 22, 0, 1], ["gfx_wind", 1, 2, 22, 1, 1],
	["gfx_grass", 1, 2, 22, 2, 1], ["gfx_biome_cover", 1, 2, 22, 3, 0],
	["gfx_vegetation_interaction", 1, 2, 22, 4, 0], ["gfx_soft_ground", 1, 2, 22, 5, 1],
	# Opt in until first-use compilation and wider device costs are resolved.
	["gfx_ground_contact", 1, 2, 22, 6, 0],
	# Lighting and shadows (group 14). Each effect is independent and defaults
	# on for new and existing settings files.
	["gfx_firelight", 1, 2, 14, 0, 1], ["gfx_torch_glow", 1, 2, 14, 1, 1],
	["gfx_lava_light", 1, 2, 14, 2, 1], ["gfx_foliage_light", 1, 2, 14, 3, 1],
	["gfx_volumetric", 1, 2, 14, 4, 1], ["gfx_ssao", 1, 2, 14, 5, 1],
	["gfx_contact_shadows", 1, 2, 14, 6, 1], ["gfx_bloom", 1, 2, 14, 7, 1],
	# Shadow quality (not gfx_*; Gfx.apply_quality / fit_shadows).
	["q_shadows", 1, 4, 14, 9, 2], ["q_shadow_fit", 1, 2, 14, 10, 1],
	# Water (group 23): surface appearance and optional creature interaction.
	["gfx_water", 1, 2, 23, 0, 1], ["gfx_water_reflections", 1, 3, 23, 1, 2],
	["gfx_water_interaction", 1, 2, 23, 2, 0], ["gfx_water_caustics", 1, 2, 23, 3, 0],
	["gfx_water_current", 1, 2, 23, 4, 0], ["gfx_water_waves", 1, 2, 23, 5, 0],
	["gfx_waterfalls", 1, 2, 23, 6, 0],
	["gfx_ambient_wildlife", 1, 2, 13, 7, 0], ["gfx_ambient_particles", 1, 2, 13, 8, 0],
	["gfx_clouds", 1, 2, 15, 7, 0],
	# Weather and effects (group 15).
	["gfx_weather_surfaces", 1, 2, 15, 0, 1], ["gfx_heat_haze", 1, 2, 15, 1, 1],
	["gfx_soft_particles", 1, 2, 15, 2, 1], ["gfx_lit_particles", 1, 2, 15, 3, 1],
	# Severed limbs hidden and thrown off (SeveredLimb); off = the original,
	# which keeps the part on the figure (GameUnit._show_severed).
	["gfx_severed_limbs", 1, 2, 15, 4, 1],
	# Camera (group 16; CameraRig, CameraFade): style (0 original, 1 modern),
	# follow, see-through, the modern camera's pan / turn / zoom speeds
	# (50 = ×1), the WASD layout (default on: user request); rows 8 / 9 are the
	# remake's turn keys (EIKeymap.ACTIONS).
	["camera_style", 1, 2, 16, 0, 1], ["cam_follow", 1, 2, 16, 1, 1], ["cam_see_through", 1, 2, 16, 2, 1],
	["cam_pan_speed", 0, 100, 16, 3, 50], ["cam_rotate_speed", 0, 100, 16, 4, 50],
	["cam_zoom_speed", 0, 100, 16, 5, 50], ["cam_wasd", 1, 2, 16, 7, 1],
	["village_start_view", 1, 2, 16, 6, 0],
	# Rows 8 and 9 are occupied by EIKeymap's camera-turn bindings.
	["control_mode", 1, 3, 16, 10, 0],
	# Interface and controls (group 17).
	# Small health bars over visible hostile units (EnemyBars): 0 off (the
	# original, which shows a unit's health only in the unit panel), 1 auto
	# (while a controller or touch is the input in use), 2 always.
	["enemy_hp_bars", 1, 3, 17, 0, 1],
	# The party portraits' smile (SmileFaces) also after a won fight, loot
	# taken and a quest done or rewarded; off = the original, a smile only at
	# a kill (ack 0x30). Default on (user request).
	["smile_faces", 1, 2, 17, 1, 1],
	# The move path dots and target marks drawn through what covers them
	# (water, overhangs, rocks); the original depth tests them (see
	# FxTypes.under_water). Default on (user request).
	["path_through", 1, 2, 17, 2, 1],
	# An aimed-strike key (cs_*) pressed once arms the aim until the next click
	# (Game._key_action, held_aim); off = the original, where the aim lasts
	# only while the key is held (sets the flag
	# clears it on key-up). Default on (user request).
	["aim_press_once", 1, 2, 17, 3, 1],
	# Keep the pointer inside the game window (Input.MOUSE_MODE_CONFINED).
	["confine_mouse", 1, 2, 17, 4, 1],
	["item_icon_fit", 1, 2, 17, 5, 1], ["ui_active_buttons", 1, 2, 17, 6, 1],
	# Gameplay (group 18).
	# The network game's unit visibility in single player too (UnitFog);
	# default on (user request).
	["unit_fog", 1, 2, 18, 0, 1],
	# The campaign's starting area (gz1g) as its own travel map piece once it
	# has been left (Session.start_zones_shown); off = the original, where the
	# Gipat map links the done piece to its village. Default
	# (user request).
	["start_zones", 1, 2, 18, 1, 1],
	["sp_full_xp", 1, 2, 18, 2, 0],
	# A living party member can help a fallen hero or mercenary up (Revive: a
	# click on the body, 5 s of work, 1 HP); not in the multiplayer (LMP)
	# game. Off = the original, which has no revival. Default on (user request).
	["revive", 1, 2, 18, 3, 1],
	# In single player the hero's death plays the game-over sound and shows a
	# small notice at once (GameOverNotice: load, main menu, hide; no pause).
	# Off = the original, where nothing shows until the party tries to leave
	# the zone (Session.sp_game_over). Default on (user request).
	["sp_death_notice", 1, 2, 18, 4, 1],
	["merc_travel", 1, 2, 18, 5, 0],
	# Explicit exit-ground clicks by default (user request); optional automatic arrival.
	["auto_exit", 1, 2, 18, 6, 0],
	["mechanism_motion", 1, 2, 18, 7, 0],
	# Optional approximation for distant NPC decisions; exact behavior is the default.
	["distant_ai", 1, 2, 18, 8, 0],
	# Network and co-op (group 19): the co-op host's rules — full experience
	# for every party member (XpRules), monster scaling to the player count
	# (MobScaling: Off / Light / Normal / Strong), shared loot
	# (CoopProgress.share_found: a find from the world reaches every other
	# player's purse and bag as an identical copy; off = the original network
	# rule), players' names above their heroes (PlayerNames) — then the host
	# opening its port on the router (UpnpPort) and the WebSocket host.
	["coop_full_xp", 1, 2, 19, 0, 1], ["coop_scale", 1, 4, 19, 1, 2],
	["coop_share_loot", 1, 2, 19, 2, 1], ["coop_player_names", 1, 2, 19, 3, 1],
	["net_upnp", 1, 2, 19, 5, 1], ["net_websocket", 1, 2, 19, 6, 0],
	["coop_clock", 1, 2, 19, 7, 1],
	# Gamepad (group 20; PadInput, PadField; docs/gamepad_design.md §8.8);
	# the button layout is group 21 (row 12 "Buttons…"). On by default:
	# without a controller nothing changes.
	["pad_enabled", 1, 2, 20, 0, 1], ["pad_rumble", 0, 100, 20, 1, 70],
	["pad_deadzone", 0, 40, 20, 2, 13], ["pad_cursor_speed", 0, 100, 20, 3, 50],
	["pad_target_radius", 0, 26, 20, 4, 6], ["pad_wheel_pause", 1, 2, 20, 5, 1],
	["pad_glyphs", 1, 5, 20, 6, 0], ["pad_swap_sticks", 1, 2, 20, 7, 0],
	["pad_light", 1, 2, 20, 8, 1],
	["pad_gyro", 1, 2, 20, 9, 0], ["pad_gyro_sensitivity", 0, 100, 20, 10, 50],
]
## The original's speed / quality switches (the original rows shadow_units
## shadow_buildings, shadow_flora) are not offered: always at their best.
const FIXED_OPTIONS := {"shadow_units": 1, "shadow_buildings": 1, "shadow_flora": 1}
## Labels of the remake's multiple-choice rows (value = index); "resolution"
## is built from the monitor (resolutions()).
const DISPLAY_CHOICES := {
	"mechanism_motion": ["Fast drop", "Original timing"],
	"display_mode": ["Windowed", "Fullscreen", "Borderless fullscreen"],
	"fps_limit": ["Off", "30", "60", "120", "144", "165", "240", "Display refresh"],
	"vsync": ["Off", "On", "Adaptive"],
	"render_scale": ["50 %", "67 %", "75 %", "85 %", "100 %", "125 %", "150 %", "200 %"],
	"camera_style": ["Original", "Modern"],
	"control_mode": ["Auto (gamepad)", "Classic", "Third person (experimental)"],
	"q_aa": ["Off", "SMAA", "MSAA 4×", "MSAA 4× + SMAA", "TAA", "FSR 2"],
	"q_shadows": ["Low", "Medium", "High", "Ultra"],
	"q_aniso": ["Off", "2×", "4×", "8×", "16×"],
	"gfx_water_reflections": ["Off", "Natural", "Mirror"],
	"coop_scale": ["Off", "Light", "Normal", "Strong"],
	"enemy_hp_bars": ["Off", "Auto", "Always"],
	"pad_glyphs": ["Automatic", "Xbox", "PlayStation", "Nintendo", "Steam Deck"],
	"renderer": ["Compatibility", "Forward+ (experimental)", "Mobile (Vulkan)"],   # RendererChoice.METHODS
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
## (EIKeymap.ACTIONS). From 11 the remake's own: "remake" (11) is its tab, a
## list of the sections (OptionsPanel.SECTIONS); "screen" (12) is a tab
## of its own; "gamepad_buttons" (21) is a sub-page of "gamepad".
## Terrain and vegetation (22) and Water (23) are direct graphics sections.
const OPTION_GROUPS := ["video", "sound", "sens", "game", "select", "actions", "camera", "items",
	"spells", "cshots", "windows", "remake", "screen", "r_world", "r_lighting", "r_effects",
	"r_camera", "r_interface", "r_game", "r_coop", "gamepad", "gamepad_buttons", "r_terrain", "r_water"]
## Labels and tips of the remake's own option rows (texts.res has none).
const REMAKE_OPTIONS := {
	"item_icon_fit": ["Fit items inside icons", "Keeps long inventory and shop items inside their icon cells while they turn. Off: the original fixed model scale."],
	"ui_active_buttons": ["Bright usable camp buttons", "Available camp modes and Exit are bright. Skills apply immediately, so their inactive Accept and Cancel controls are hidden. Deal controls show whether a transaction can be made or undone. Off: the original button layout and tint."],
	"coop_clock": ["Shared pause and speed", "Co-op host: pause the game or switch to 2x speed for everyone. Clients follow the host's speed. Off: co-op always runs at normal speed."],
	"mechanism_motion": ["Drawbridge motion", "Fast drop lowers moving drawbridges in at most 330 ms of game time; physical access opens only when lowering finishes. Original timing keeps the original motion and immediate physical access. The host's setting applies in co-op."],
	"auto_exit": ["Automatic zone exits", "Automatically opens travel when your party walks into an open exit. Off: click the ground inside the exit where the exit cursor appears. The host's setting applies in co-op; scripted story transfers still work."],
	"merc_travel": ["Mercenaries travel between regions", "Hired companions stay with their owner when the party travels to another allod or region. The host's setting applies in co-op. Off: the original regional companion rule."],
	"net_websocket": ["Browser-compatible host", "Host with WebSocket over TCP. Native and browser clients join using ws://host:27015, or wss:// through an HTTPS reverse proxy. Off uses native ENet over UDP. Set before hosting."],
	# The Remake tab and its sections (OptionsPanel.SECTIONS: the link rows).
	"remake": ["Remake", "Graphics, camera, interface, gamepad, gameplay and co-op settings of the remake; the game files and the log."],
	"screen": ["Screen", "Display mode, resolution, render scale, anti-aliasing, frame rate, VSync, smooth motion and the FPS counter (the remake's), with the original brightness, contrast and gamma."],
	"r_world": ["World and textures", "Textures, materials, portrait heads, sky, view distance, ambient wildlife and regional particles."],
	"r_terrain": ["Terrain and vegetation", "Terrain detail, wind, grass, ground cover, grass interaction, snow and sand deformation, ground-contact blending."],
	"r_lighting": ["Lighting and shadows", "Firelight, torch and lava glow, leaf backlighting, volumetric fog, ambient occlusion, contact shadows, bloom, shadow quality."],
	"r_water": ["Water", "Water and lava, reflections, contact and wakes, underwater caustics, river currents, propagating waves, waterfalls."],
	"r_effects": ["Weather and effects", "Rain on surfaces, moving clouds and shadows, heat haze, soft and lit particles, severed limbs."],
	"r_camera": ["Camera", "The modern camera: follow, see-through objects, speeds, the WASD controls and the turn keys."],
	"r_interface": ["Interface and controls", "Enemy health bars, smiling portraits, the move path through objects, aim keys, keeping the mouse in the window."],
	"r_game": ["Gameplay", "Fog of war in single player, the starting area on the travel map, experience for companions, revival, the game-over notice."],
	"r_coop": ["Network and co-op", "Co-op host rules (experience, monster scaling, shared loot, player names), opening the port on the router, the browser-compatible host."],
	"gamepad": ["Gamepad", "Controller settings (vibration, stick dead zone, pointer speed, target range, button pictures) and the button layout."],
	"gamepad_buttons": ["Buttons", "Choose which controller button does what. The D-pad and the sticks keep their roles."],
	"gfx_firelight": ["Dynamic firelight", "Warm, flickering torches and fire; spell lights brighten nearby surfaces and fade out softly. Nearby fire and lava lights share a limited number of shadows."],
	"gfx_materials": ["Surface materials", "Metal equipment catches the light; wood and stone have subtle surface relief. Uses the original textures and equipment materials."],
	"gfx_foliage_light": ["Leaf backlighting", "Sunlight shines softly through leaves while trunks remain solid."],
	"gfx_weather_surfaces": ["Rain on surfaces", "Rain gradually darkens exposed ground and adds wet highlights and water ripples. Surfaces dry after the rain; caves, snow and lava stay unchanged."],
	"gfx_detailed_heads": ["Portrait heads", "People with a face portrait (Zak, the mercenaries, most men and some women) wear the portrait's own head model and face painting instead of the figure's head. A worn helmet keeps the original head."],
	"gfx_sharp_units": ["Sharp character textures", "Faces, clothes, armour and weapons of the characters stay crisp up close (sharper filtering of the original textures), without shimmer at a distance; same colours. Also the figures in the inventory and the unit panel."],
	"renderer": ["Renderer", "Compatibility (OpenGL ES 3): the default; runs on every device. Mobile (Vulkan): Godot's renderer for phones, lighter than Forward+ (no volumetric fog). Forward+ (Vulkan, experimental): the renderer of the PC version, with all its effects available; on phones much slower, and some drivers show graphics problems with it. Takes effect after a restart. If Vulkan cannot start, or the game closes right after switching, the game goes back to Compatibility by itself."],
	"auto_graphics": ["Detect graphics automatically", "On the first start and after a change of graphics card, a short test picks the graphics settings this device runs smoothly. It never changes settings you have set yourself."],
	"gfx_lava_light": ["Lava lighting", "Lava casts a warm glow onto nearby banks, buildings and creatures. A limited number of nearby lights follows the view."],
	"pad_enabled": ["Gamepad", "Play with a controller (Xbox, PlayStation, Nintendo, Steam Deck and others). Left stick: move the hero; right stick: turn and zoom the camera; A: act on the highlighted target; X: more actions for it, including aimed strikes; LB / RB: spells and items; Y: pause. Without a controller nothing changes."],
	"pad_rumble": ["Vibration", "Strength of the controller's vibration when your hero is hit, a party member falls or the ground shakes. 0 turns it off."],
	"pad_deadzone": ["Stick dead zone", "How far a stick must move before it counts. Raise it if your hero or the camera drifts by itself."],
	"pad_cursor_speed": ["Pointer speed", "Speed of the controller's pointer in cursor mode and the menus."],
	"pad_target_radius": ["Target range", "How far around the leader the controller looks for a target to highlight (4 to 30 m)."],
	"pad_wheel_pause": ["Pause while a wheel is open", "Single player: the game pauses while a controller wheel (spells, items, actions, the target ring) is open. Network games never pause."],
	"pad_glyphs": ["Button pictures", "Which controller's button pictures the prompts show. Automatic follows the controller in use."],
	"pad_swap_sticks": ["Swap sticks", "The right stick moves the hero and the left stick turns the camera."],
	"pad_light": ["Light bar shows health", "Controllers with a light bar (DualSense, DualShock 4): its colour follows the leader's health, from green to red."],
	"pad_gyro": ["Gyro pointer", "Tilt a controller with a gyroscope to move the pointer in cursor mode and the menus. On Android, tilt the handheld itself. Keep it still briefly when first enabled."],
	"pad_gyro_sensitivity": ["Gyro sensitivity", "How far the pointer moves when you tilt the controller or handheld."],
	"gfx_hd_textures": ["HD textures", "The original ground and object textures upscaled 2x once at load (edge-preserving Lanczos on the GPU): sharper up close, same colours. Applies from the next zone load."],
	"gfx_soft_particles": ["Soft particles", "Smoke, fire and magic fade softly where they meet the ground and walls instead of cutting through them with a hard line."],
	"gfx_lit_particles": ["Lit smoke and dust", "Smoke, dust and blood take the scene's light: unchanged in daylight, darker at night and in caves instead of glowing."],
	"gfx_contact_shadows": ["Contact shadows", "A soft shadow on the ground under every creature, so figures sit on the ground also in shade, at night and in caves."],
	"q_aa": ["Anti-aliasing", "Smooths jagged edges. SMAA (default): cheap and clean. MSAA 4× + SMAA: sharpest, but costly at high resolutions. TAA and FSR 2 smooth foliage and thin lines best but soften textures slightly and can ghost on fast motion. FSR 2 draws the 3D view at 67 % (its Quality mode) and upscales it, faster than native; a lower Render scale goes further. On a Mac, Apple's MetalFX takes the place of FSR."],
	"q_shadows": ["Shadow quality", "Softness and resolution of sun and torch shadows (Ultra: widest soft filter, largest shadow maps)."],
	"q_shadow_fit": ["Shadows fitted to the view", "The sun's shadow cascades span only the visible distance and the zone's size, so near shadows get sharper; off: a fixed 220 m."],
	"q_aniso": ["Texture filtering", "Anisotropic filtering: ground textures stay sharp at grazing angles."],
	"gfx_torch_glow": ["Torch and fire glow", "Torches, camp fires and spell lights glow in the night mist (needs Volumetric fog)."],
	"gfx_sky": ["Atmospheric sky", "Sun disc, moon and stars at night over the original sky dome, and the open top of the dome faded into the sky colour; lightning lights up the clouds and its flash on the ground rises and fades softly. Off: the original dome and the original hard lightning flash."],
	"gfx_water": ["Water and lava effects", "The original water with soft shores, blended bog and river edges, ripples and rain rings catching the sky, sun glints and reflections; breaking surf on sea coasts; glowing, churning lava. Off: the original water."],
	"gfx_water_reflections": ["Water reflections (SSR)", "Natural: subtle, rippled reflections. Mirror: stronger, sharper scenery with gentler distortion (default). Off keeps sky reflections. Needs Water and lava effects. Off-screen and transparent objects may be absent; Mirror costs more GPU time."],
	"gfx_water_interaction": ["Water contact and wakes", "Ripples and contact foam around visible creatures wading in water. Requires Water and lava effects. Off by default."],
	"gfx_water_caustics": ["Underwater caustics", "Moving sunlight patterns on shallow water beds. Requires Water and lava effects. Off by default."],
	"gfx_water_current": ["River currents", "Surface ripples follow sloping water downstream. Water contact and wakes adds foam behind wading creatures. Requires Water and lava effects. Off by default."],
	"gfx_water_waves": ["Propagating water waves", "Persistent spreading ripples and disturbed-water trails from visible wading creatures. Requires Water and lava effects and Water contact and wakes. Off by default."],
	"gfx_waterfalls": ["Waterfalls", "Flowing foam, spray and mist at exposed river drops. Requires Water and lava effects. Off by default."],
	"gfx_ambient_wildlife": ["Ambient wildlife", "Small local animals and bird flocks in suitable terrain. They flee nearby visible creatures and stop with game time."],
	"gfx_ambient_particles": ["Regional particles", "Sparse pollen, leaves, dust, embers, snow motes and night fireflies from the current region and terrain. Pauses with the world."],
	"gfx_clouds": ["Moving clouds and shadows", "Wind-driven clouds and soft sunlight shadows, synchronized with game time and weather. Off by default."],
	"gfx_wind": ["Wind in foliage", "Trees and bushes sway in the wind."],
	"gfx_volumetric": ["Volumetric fog / light shafts", "Light mist lit by the sun (shafts through the trees at dawn and dusk) and the torches."],
	"gfx_terrain": ["Terrain detail", "Sharper original ground textures with fewer tile seams; relief follows painted rock and path patterns, with softer sand and snow, fine grass and damp banks."],
	"gfx_grass": ["Grass blades", "Adds grass blades on green ground, with wind and shadows when shadow quality is enabled. Automatic settings enable this on capable desktops; off by default on Android."],
	"gfx_vegetation_interaction": ["Grass interaction", "Visible creatures part grass and flowers, which gradually spring back. Requires Grass blades or Ground cover. Off by default."],
	"gfx_biome_cover": ["Ground cover", "Meadow flowers, dry tufts, tree litter and small stones on suitable ground. Off by default."],
	"gfx_soft_ground": ["Snow and sand deformation", "Movement compresses loose snow and sand into connected trails with raised banks and deeper footprints. Snow gives way more than sand or packed snow. Tracks gradually disappear; off by default on Android."],
	"gfx_ground_contact": ["Ground contact blending", "Experimental: blends the surrounding ground onto the bases of rocks, buildings and tree trunks, following slopes, loose snow and footprints. First use may pause while preparing graphics. Off by default."],
	"gfx_heat_haze": ["Heat haze", "Air shimmering above torches and camp fires."],
	"gfx_ssao": ["Ambient occlusion", "Soft contact shadows (SSAO)."],
	"gfx_bloom": ["Bloom", "Glow around bright lights."],
	"gfx_severed_limbs": ["Severed limbs fly off", "A severed head, arm or leg is cut from the figure and thrown to the ground, where it lies for a while. Off: as the original, the part stays on the body, bloodied."],
	"display_mode": ["Display mode", "Windowed, fullscreen, or a borderless window covering the screen."],
	"resolution": ["Resolution", "Window size when windowed; in fullscreen the 3D view is rendered at this size and scaled to the screen (the interface stays sharp)."],
	"fps_limit": ["Frame rate limit", "Highest frames per second; Display refresh = the monitor's refresh rate."],
	"vsync": ["VSync", "Wait for the monitor's refresh (no tearing); adaptive tears only when a frame is late."],
	"show_fps": ["Show FPS", "A frames-per-second counter in the top right corner."],
	"confine_mouse": ["Keep mouse in window", "The pointer cannot leave the game window (e.g. onto a second monitor) while the game has focus; it is free again when you switch away."],
	"sp_death_notice": ["Game-over notice at the hero's death", "Single player: when your main hero dies, the game-over sound plays at once and a small notice appears at the top of the screen, with Load, Main menu and Hide. The game is not paused and your companions fight on; leaving the area still ends the game. Off: as the original, nothing appears until the party tries to leave the area."],
	"revive": ["Companions can revive the hero", "Select a living hero or companion and click a fallen party member (your hero, another player's hero or a hired companion): they walk to the body and tend it for 5 seconds, and it gets up with 1 health. Another order stops it; there is no other limit, but it is slow in a fight. Party bodies stay where they fell. Co-op: fallen heroes wait for help instead of rising after 5 seconds; changing the area still brings them back. Off: as the original, the dead stay dead."],
	"enemy_hp_bars": ["Enemy health bars", "A small health bar over each enemy you can see near the camera or your selected characters. Auto: while you play with a controller or by touch; a bar shows once the enemy is hurt (and over the controller's highlighted target). Always: with every input, also at full health. Off: as the original, health only in the unit panel."],
	"smile_faces": ["Smiling portraits", "The party's portraits smile for a few seconds after a won fight (every living member), when a hero takes loot from a body or chest, and when a quest is finished or rewarded (the whole party). Co-op: also the hero who gets a copy of shared loot. A hit still shows pain at once. Off: as the original, a portrait smiles only after its character's kill."],
	"coop_player_names": ["Player names above heroes", "Co-op: each player's name, in their colour, above their hero's head, so the heroes are easy to tell apart. Hidden while the hero cannot be seen. Single player is not affected. Off: as the original, no names."],
	"sp_full_xp": ["Full experience for companions", "Single player: your hero and every companion (hired mercenaries such as Khador) each get the whole experience of a kill or quest. Off: as the original, which splits it equally among the living party."],
	"start_zones": ["Starting areas on the travel map", "The area where the campaign begins (the ruins where Zak wakes up) becomes a place on the travel map once you have left it, so the party can go back. You arrive at its path from the village; what was killed or taken there stays so, and the opening scenes do not play again. Co-op: the host's setting counts. Off: as the original, where its piece only leads to the village."],
	"aim_press_once": ["Aim keys: press once", "Press an aimed-strike key (Num 8 head, Num 5 body …) once: its cursor stays until the next click. A click on a creature attacks it at that part; a click elsewhere, a right click, Esc or the same key again cancels it; another aim key switches. Off: as the original, the key must be held while clicking."],
	"path_through": ["Show the move path through objects", "The dots of a move path and the ring at its target stay visible under water, under arches and behind rocks and walls, faded where something covers them. Off: as the original, which hides them there."],
	"phys_interp": ["Smooth motion", "Creatures are drawn between the game's 60 steps a second, so they move smoothly on screens faster than 60 Hz. Visual only."],
	"render_scale": ["Render scale", "Resolution of the 3D view relative to the window: below 100 % faster, above it sharper (supersampling)."],
	"gfx_far_view": ["Far view", "See 260 m instead of 100 m, with a long soft fade into the fog; off: the original 100 m view with its short fog band."],
	"control_mode": ["Control mode", "Auto uses third person with a gamepad and classic controls with a mouse. Third person: WASD moves, mouse looks, left click attacks, E interacts, Tab releases the pointer. Gamepad: sticks move and look, RT attacks, A interacts, LT + RT opens the system wheel. Visible health bars stay on. Attacks can hit friendly characters outside safe zones. Attacks and spells are disabled in safe zones."],
	"camera_style": ["Camera style", "Original: the 2000 game's camera. Modern: responsive pan, smooth zoom and terrain clearance. Middle drag turns; Alt + middle drag or right drag tilts; Shift + middle drag pans. Home centres; optional hero follow and see-through objects."],
	"cam_pan_speed": ["Camera pan speed (modern)", "Speed of the modern camera's panning (keys, screen edges)."],
	"cam_rotate_speed": ["Camera turn speed (modern)", "Speed of the modern camera's turning and tilting (drag, keys)."],
	"cam_zoom_speed": ["Camera zoom speed (modern)", "Speed of the modern camera's zoom (wheel, keys)."],
	"cam_follow": ["Camera follows the hero", "Modern camera: follows the selected hero until you pan away. Home, F1-F3 or a portrait double-click centres and resumes following. Moving a hero never pulls the camera back. Off: these controls centre without following."],
	"cam_see_through": ["See-through objects", "Modern camera: trees, houses and rocks that hide your heroes fade to see-through."],
	"unit_fog": ["Fog of war (single player)", "Enemies and other people are only seen within reach of your party's eyes: 2 × the larger of sight and life sense + 5 m around each party member, as the original's network game does. Off: the original single player, everyone on the map is drawn."],
	"distant_ai": ["Distant AI (experimental)", "Reduce CPU use by making distant, idle NPCs decide less often. Nearby units, combat and active orders keep their normal update rate. Offscreen reactions and patrol timing can change. Requires fog of war in single player; the host controls this in co-op."],
	"coop_full_xp": ["Full experience for every party member", "Co-op host: every player's hero and every mercenary gets the whole experience of a kill or quest. Off: the original network rule (shared among the players' heroes by experience, mercenaries get none). Single player is not affected."],
	"coop_share_loot": ["Shared loot", "Co-op host: whatever a player finds — loot from bodies and chests, a theft, the money and items of a conversation or quest reward — every other player gets an identical copy of in their own bag, and the same money. Trades and items passed between players are not copied; quest items count for the whole party anyway. Off: as the original, a find belongs to whoever takes it."],
	"coop_scale": ["Scale monsters to player count", "Co-op host: monsters get more health and hit harder for each player beyond the first (Light +25 % health / +12.5 % damage, Normal +50 % / +25 %, Strong +100 % / +50 % per extra player). Off: as the original."],
	"net_upnp": ["Open the port on the router", "Co-op host: asks your router to forward UDP port 27015 to this computer so friends can join over the internet (UPnP, else NAT-PMP / PCP), and shows your external IP address to give them. The forwarding is removed when you stop hosting. Off: forward the port by hand."],
	"cam_wasd": ["WASD camera controls", "WASD: move camera; Q/E: turn; 9/0/-/=: weapons 1-4; R: Aggressive/Defensive; T: Use/Steal. Other keys stay available. Each layout has its own editable bindings on the key pages. Classic restores your previous keys. Original camera always uses Classic."],
	"village_start_view": ["Village opening view", "Use the village's authored camera view when you enter. Moving the camera returns to your chosen camera style. Off: start at your hero."],
	"camera_rotate_left": ["Turn camera left", "Modern camera: turns the camera (Divinity: Original Sin 2 uses Delete)."],
	"camera_rotate_right": ["Turn camera right", "Modern camera: turns the camera (Divinity: Original Sin 2 uses End)."],
}
## Options the remake applies (a row missing here is greyed out on the Options
## screen). "marks" = EnableBloodprints and "footprints" = EnableFootprints
## switch the ground marks (GroundMarks).
const OPTIONS_APPLIED := ["volume_sfx", "volume_stream", "volume_voice", "power_kbd",
	"item_icon_fit", "ui_active_buttons", "coop_clock", "merc_travel", "auto_exit", "mechanism_motion",
	"power_mouse", "scroll_border", "rubber_select", "marks", "footprints", "select_type", "show_path", "brightness", "contrast", "gamma",
	"show_flying_hp", "show_tutorial", "autosave", "tooltip_time", "switch_filters",
	"camera_reverse_x", "camera_reverse_y", "reverse_stereo", "difficulty",
	"gfx_sky", "gfx_water", "gfx_wind", "gfx_volumetric", "gfx_terrain", "gfx_heat_haze",
	"gfx_grass", "gfx_soft_ground", "gfx_ground_contact", "gfx_water_interaction", "gfx_water_caustics", "gfx_water_current", "gfx_water_waves", "gfx_waterfalls", "gfx_vegetation_interaction", "gfx_biome_cover",
	"gfx_ambient_wildlife", "gfx_ambient_particles",
	"gfx_clouds",
	"gfx_ssao", "gfx_bloom", "gfx_far_view", "gfx_severed_limbs",
	"gfx_hd_textures", "gfx_soft_particles", "gfx_lit_particles", "gfx_contact_shadows", "gfx_torch_glow", "gfx_water_reflections",
	"gfx_firelight", "gfx_materials", "gfx_foliage_light", "gfx_weather_surfaces", "gfx_lava_light", "gfx_detailed_heads",
	"gfx_sharp_units", "q_aa", "q_shadows", "q_shadow_fit", "q_aniso", "confine_mouse",
	"display_mode", "resolution", "fps_limit", "vsync", "show_fps", "render_scale", "phys_interp",
	"control_mode", "camera_style", "cam_pan_speed", "cam_rotate_speed", "cam_zoom_speed", "cam_follow", "village_start_view",
	"cam_see_through", "cam_wasd", "coop_full_xp", "coop_scale", "net_upnp", "net_websocket", "unit_fog", "distant_ai", "path_through", "sp_full_xp", "aim_press_once", "start_zones", "sp_death_notice", "revive", "coop_player_names", "coop_share_loot", "enemy_hp_bars", "smile_faces",
	"pad_enabled", "pad_rumble", "pad_deadzone", "pad_cursor_speed", "pad_target_radius", "pad_wheel_pause", "pad_glyphs", "pad_swap_sticks", "pad_light", "pad_gyro", "pad_gyro_sensitivity", "auto_graphics", "renderer"]
signal options_changed
const GFX_REV := 4
## Option q_aa 5 (FSR 2): the 3D view at most this fraction of the window.
const FSR2_SCALE := 0.67
## Values reset once when an older settings file is loaded, by the revision
## that introduced them: 1 object shadows on (remake default; the 2000
## defaults were off for speed), 2 defaults / scales corrected from the original
## 3 retired map-edge option, 4 shadow quality High and SMAA (Ultra shadows and MSAA cost
## 1–3 ms of GPU time each at 1440p).
const GFX_DEFAULTS := {
	1: {"shadow_buildings": 1, "shadow_flora": 1},
	2: {"power_kbd": 25, "rubber_select": 2, "brightness": 50, "contrast": 50, "gamma": 50,
		"tooltip_time": 2},
	4: {"q_shadows": 2, "q_aa": 1},
}
var _gfx_rev := GFX_REV
var options := {}

var _texture_cache := {}
var _text_cache := {}


## Breadcrumbs for crash reports: one line per lifecycle step (zone load /
## teardown, travel map, save / load, Esc menu) in godot.log, flushed at once
## (application/run/flush_stdout_on_print), so the last line before a crash
## tells where it happened. Never per frame.
static func trace(what: String) -> void:
	print("[trace %s +%dms] %s" % [Time.get_time_string_from_system(), Time.get_ticks_msec(), what])
	CrashReport.note(what)   # the session marker's last step and zone


## Keys whose release went to another window are forgotten once this frame's
## input has been read (EIKeymap.release_keys).
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_FOCUS_OUT,
			NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_OUT] and is_inside_tree():
		if not get_tree().process_frame.is_connected(EIKeymap.release_keys):
			get_tree().process_frame.connect(EIKeymap.release_keys, CONNECT_ONE_SHOT)


## Missing new ground options follow platform defaults and the player's
## existing Original look / untouched automatic tier. Saved choices win.
static func ground_effect_defaults(cfg: ConfigFile, platform: Dictionary = {}) -> Dictionary:
	var values := {"gfx_grass": int(platform.get("gfx_grass", 1)),
		"gfx_soft_ground": int(platform.get("gfx_soft_ground", 1)),
		"gfx_ground_contact": int(platform.get("gfx_ground_contact", 0))}
	var seen := false
	var original := true
	if cfg.has_section("options"):
		for key: String in cfg.get_section_keys("options"):
			if key.begins_with("gfx_") and key != "gfx_edge_fade" and not values.has(key):
				seen = true
				original = original and int(cfg.get_value("options", key)) == 0
	var tier := int(cfg.get_value(GfxDetect.SECTION, "tier", -1))
	var recorded: Dictionary = cfg.get_value(GfxDetect.SECTION, "values", {})
	var untouched := tier >= 0 and not recorded.is_empty() and int(cfg.get_value(GfxDetect.SECTION, "manual", 0)) == 0
	for key: String in recorded:
		if not values.has(key) and cfg.has_section_key("options", key):
			untouched = untouched and int(cfg.get_value("options", key)) == int(recorded[key])
	for key: String in values:
		if cfg.has_section_key("options", key):
			values[key] = int(cfg.get_value("options", key))
		elif (seen and original) or (untouched and tier >= (2 if key in ["gfx_grass", "gfx_ground_contact"] else 3)):
			values[key] = 0
	return values


func _ready() -> void:
	GameFiles.initialize()
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		root = cfg.get_value("game", "root", "")
		for id: String in [CampaignProfile.ORIGINAL, CampaignProfile.ASTRAL]:
			var installed: Variant = cfg.get_value("games", id, "")
			if installed is String and not installed.is_empty():
				campaign_roots[id] = installed
		player_name = cfg.get_value("player", "name", "Player")
		hero_class = cfg.get_value("player", "hero", hero_class)
		difficulty = cfg.get_value("game", "difficulty", 0)
		resolution_size = String(cfg.get_value("display", "resolution", "native"))
	for o: Array in OPTIONS:
		options[o[0]] = cfg.get_value("options", o[0], o[5]) if cfg.has_section("options") else o[5]
	for key: String in Portability.defaults():
		if not cfg.has_section_key("options", key):
			options[key] = Portability.defaults()[key]
	options.merge(ground_effect_defaults(cfg, Portability.defaults()), true)
	if OS.has_feature("web") and not GameFiles.manifest.is_empty():
		root = GameFiles.active_root()
	if OS.has_feature("web"):
		for id: String in [CampaignProfile.ORIGINAL, CampaignProfile.ASTRAL]:
			if GameFiles.library.has(id):
				campaign_roots[id] = GameFiles.WEB_ROOT + "-" + id
			else:
				campaign_roots.erase(id)
	# Browser settings saved before the web build kept edge scrolling hold the
	# phone's scroll_border 0: back to the desktop default once.
	if OS.has_feature("web") and int(cfg.get_value("remake", "web_input", 0)) < 1 \
			and cfg.has_section_key("options", "scroll_border") and int(cfg.get_value("options", "scroll_border")) == 0:
		options.scroll_border = OPTIONS.filter(func(o): return o[0] == "scroll_border")[0][5]
	options.difficulty = difficulty
	options.resolution = maxi(0, resolutions().find(_res_from_string(resolution_size)))
	var rev := int(cfg.get_value("remake", "gfx", 0))
	if rev < GFX_REV:
		for r: int in GFX_DEFAULTS:
			if rev < r:
				for k: String in GFX_DEFAULTS[r]:   # a platform's own defaults win (web / mobile)
					options[k] = Portability.defaults().get(k, GFX_DEFAULTS[r][k])
		_gfx_rev = GFX_REV
		if root != "":
			save_settings()
	_setup_buses()
	_apply_audio()
	_setup_display()
	_apply_display()
	_apply_window_late.call_deferred()
	var flash := FlashLog.requested()   # diagnostic, off by default (FlashLog)
	if flash > 0.0:
		add_child(FlashLog.new(flash))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ei-path="):
			root = arg.trim_prefix("--ei-path=")
	var rc := null if Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--local-host-config=")) else RendererChoice.startup()   # options.renderer; the trial of a new renderer
	if rc:
		add_child(rc)
	add_child(CrashReport.new())   # session marker, unexpected-exit report


## Returns an empty string when `path` is a usable install, otherwise the reason.
static func validate(path: String) -> String:
	GameFiles.clear_path_cache()
	if path.is_empty() or not GameFiles.directory_exists(path):
		return RemakeText.t("Folder does not exist.")
	var case_problem := GameFiles.case_error(path)
	if not case_problem.is_empty():
		return case_problem
	for rel: String in REQUIRED:
		if not GameFiles.exists(path.path_join(rel)):
			return RemakeText.t("Missing %s - point this at the Evil Islands install folder (the one containing game.exe).") % rel
	return ""


func open(path: String) -> String:
	var err := validate(path)
	if err:
		return err
	path = GameFiles.resolve(path)
	root = path
	textures = EIResArchive.open_path(path.path_join("res/textures.res"))
	figures = EIResArchive.open_path(path.path_join("res/figures.res"))
	redress = EIResArchive.open_path(path.path_join("res/redress.res"))
	var dbres := EIResArchive.open_path(path.path_join("res/database.res"))
	if textures == null or figures == null or redress == null or dbres == null:
		return RemakeText.t("Could not read the game archives in res/.")
	_open_text_archives()   # first: sets the code page the database strings use
	campaign_id = CampaignProfile.detect(texts)
	db = EIDatabase.load_from(dbres)
	# The quest maps' (maps/z*q*.mq / .mob) quest items — armorykey00, pyrkey,
	# goldnuggets ... with script ids 80-86 (QObjGetItem) — exist only in
	# res/databaseLMP.res, the database the original loads for its multiplayer game
	# (: "databaseLMP.res" when a session runs, else
	# "database.res"). The remake plays those quests in its campaign: their
	# quest items are added.
	var lmp := EIResArchive.open_path(path.path_join("res/databaselmp.res"))
	if lmp:
		db.merge_missing(EIDatabase.load_from(lmp, true), "quest_items")
	ai_reg = EIRegFile.parse(GameFiles.read(path.path_join("config/ai.reg")))
	ground_types.clear()
	var aiinfo := EIResArchive.open_path(path.path_join("res/aiinfo.res"))
	if aiinfo and aiinfo.has("tiledesc.reg"):
		var reg := EIRegFile.parse(aiinfo.read("tiledesc.reg"))
		for k in reg:
			if String(k).is_valid_int():
				ground_types[int(k)] = reg[k]
	_text_cache.clear()
	_texture_cache.clear()
	campaign_roots[campaign_id] = root
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
	texts_lmp = EIResArchive.open_path(res_path("textslmp.res"))
	menus = EIResArchive.open_path(res_path("menus.res"))
	EIText.code_page = EIText.detect_code_page(texts)
	RemakeText.lang = RemakeText.detect(texts)   # the remake's own texts follow the edition
	_text_cache.clear()
	_texture_cache.clear()


func is_open() -> bool:
	return textures != null


func map_names() -> PackedStringArray:
	var out := PackedStringArray()
	for f in GameFiles.files(root.path_join("maps")):
		if f.get_extension().to_lower() == "mpr":
			out.append(f.get_basename())
	out.sort()
	return out


func read_file(rel: String) -> PackedByteArray:
	var path := root.path_join(rel)
	# The game names files case-insensitively (Windows): scripts say
	# AddMob("Zone3ObrVoev.mob") for maps/zone3obrvoev.mob.
	if not GameFiles.exists(path) and GameFiles.exists(root.path_join(rel.to_lower())):
		path = root.path_join(rel.to_lower())
	return GameFiles.read(path)


func load_image(name: String, authored_mips := false) -> Image:
	var data: PackedByteArray
	if not textures.has(name + ".mmp") and menus and menus.has(name + ".mmp"):
		data = menus.read(name + ".mmp")
	else:
		data = textures.read(name + ".mmp")
	return EIMmp.decode_texture(data, RenderingServer.has_os_feature("s3tc")) if authored_mips else EIMmp.decode(data)


## A model file (.mod/.fig/.bon/.anm) from figures.res, or menus.res for the menu signposts.
func has_figure(file: String) -> bool:
	return figures.has(file) or (menus != null and menus.has(file))


func read_figure(file: String) -> PackedByteArray:
	if figures.has(file) or menus == null:
		return figures.read(file)
	return menus.read(file)


## Cached, mipmapped texture for objects; null if missing.
func get_texture(name: String, authored_mips := false) -> Texture2D:
	name = name.to_lower()
	var key := name + ("#authored_mips" if authored_mips else "")
	if not _texture_cache.has(key):
		var img := load_image(name, authored_mips)
		var tex: Texture2D = null
		if img:
			if not authored_mips:
				img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
		_texture_cache[key] = tex
	return _texture_cache[key]


## the original: a multiplayer game loads
## res/databaseLMP.res in place of res/database.res (a whole database of its
## own: the lmp_* monsters, other item / spell numbers, 117 NPC rows). `on`
## switches GameData.db to it, off back to the campaign's. Returns false when
## the installation has no databaseLMP.res.
func use_lmp_database(on: bool) -> bool:
	if on and campaign_id == CampaignProfile.ASTRAL:
		return false
	if on == lmp_db:
		return true
	if on:
		var arc := EIResArchive.open_path(res_path("databaselmp.res"))
		if arc == null:
			return false
		_db_main = db
		db = EIDatabase.load_from(arc, true)
	else:
		db = _db_main if _db_main else db
		_db_main = null
	lmp_db = on
	Items._cache.clear()
	Spells._cache.clear()
	return true


## A text entry from texts.res (e.g. "quest q0g", "briefing z1"), decoded; "" if missing.
func text(key: String) -> String:
	key = key.to_lower()
	if not _text_cache.has(key):
		var b := texts.read(key) if texts else PackedByteArray()
		if b.is_empty() and texts_lmp:
			b = texts_lmp.read(key)
		_text_cache[key] = EIText.ansi(b).replace("\r", "") if not b.is_empty() else ""
	return _text_cache[key]


func save_settings() -> void:
	# The simulation child shares saves and reads settings, but the UI is
	# the sole writer of display, player and preference settings.
	if Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--local-host-config=")):
		return
	var cfg := ConfigFile.new()
	cfg.set_value("game", "root", root)
	for id: String in campaign_roots:
		cfg.set_value("games", id, campaign_roots[id])
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "hero", hero_class)
	cfg.set_value("game", "difficulty", difficulty)
	for k in options:
		cfg.set_value("options", k, options[k])
	cfg.set_value("remake", "gfx", _gfx_rev)
	if OS.has_feature("web"):
		cfg.set_value("remake", "web_input", 1)
	cfg.set_value("display", "resolution", resolution_size)
	var old := ConfigFile.new()   # hand-edited [debug] keys (FlashLog) and GfxDetect's record survive
	if old.load(CONFIG_PATH) == OK:
		for sec in ["debug", "gfx_detect"]:   # GfxDetect.SECTION
			if old.has_section(sec):
				for k in old.get_section_keys(sec):
					cfg.set_value(sec, k, old.get_value(sec, k))
	cfg.save(CONFIG_PATH)


func option(name: String) -> int:
	if FIXED_OPTIONS.has(name):
		return FIXED_OPTIONS[name]
	return int(options.get(name, 0))


func set_option(name: String, value: int) -> void:
	options[name] = value
	if not (name.begins_with("volume_") or name in ["brightness", "contrast", "gamma"]):   # not per slider step
		trace("option %s = %d" % [name, value])
	if name == "difficulty":
		difficulty = value
	if name == "renderer":
		RendererChoice.choose(value)   # for the next start
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
		add_bus(b)


## The index of the audio bus `bus_name`, appended (sending to Master) if it
## does not exist yet. Web: buses are appended by raising the bus count, never
## with AudioServer.add_bus(): Godot 4.7's browser side files a bus added that
## way one place too early (Bus.addAt → move(n, −1) → splice(−2)), so its list
## stops matching the engine's indices; a later send change (a mixer channel
## switching between SFX and Voice) then rerouted the real Master into a loop
## and every sound stopped for good (0.1.7, "sound cuts out after a while").
static func add_bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		i = AudioServer.bus_count
		AudioServer.bus_count = i + 1
		AudioServer.set_bus_name(i, bus_name)
	return i


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
## controls' tooltips (Control.get_tooltip) instead, drawn as the original's tip:
## - size: the widest line + 12 by the lines' heights + 8 (an
##   empty line has the height of "w");
## - place: (24, 24) from the pointer (824c
## ), pushed left to end at x 800; past y 600 it is lifted so
##   its bottom is at the pointer, never above 0 (800×600 units, scaled);
## - look: filled 0x1c2b (dark brown), a 1 px (orange)
##   frame (FrameRect), lines at (6, 4) one under the other, no shadow, the
##   first (title, = 1 at nearly every
##   call) orange, the rest.
##  uses CInterface font 0, whose pixel height scales with the
## screen width. Geometry uses each screen axis separately (
## converts the measured pixels back to 800×600 logical coordinates).
## A tooltip whose widget the original gave a hotkey (
## third argument, tip): appends " (" + the key name
## (the current binding) + ")" to the first
## line; nothing when no key is bound.
static func tip_key(t: String, id: int) -> String:
	if t == "" or id <= 0:
		return t
	var k := EIKeymap.key_of_id(id)
	if k == "":
		return t
	var i := t.find("\n")
	return t + "  ( %s )" % k if i < 0 else t.substr(0, i) + "  ( %s )" % k + t.substr(i)


class TipLayer extends CanvasLayer:
	const FILL := Color8(0x2b, 0x1c, 0x00)
	const TITLE := Color8(0xff, 0xb3, 0x31)
	const BODY := Color8(0xe4, 0xd7, 0xa7)
	var delay := 0.5
	var _ctrl: Control
	var _mouse := Vector2.INF
	var _since := 0
	var _text := ""
	var _panel := Control.new()
	var _lines := PackedStringArray()
	var _title_lines := 1

	func _ready() -> void:
		layer = 127
		process_mode = Node.PROCESS_MODE_ALWAYS
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.visible = false
		_panel.draw.connect(_draw_tip)
		add_child(_panel)

	func _input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed or e is InputEventKey and e.pressed:
			_hide()
			_since = Time.get_ticks_msec()

	func _kv() -> Vector2:
		return get_viewport().get_visible_rect().size / Vector2(800, 600)

	func _fs() -> int:
		return maxi(6, int(round(get_viewport().get_visible_rect().size.x * Interface800.FONT_EM[0])))

	func _line_h(f: Font, fs: int, s: String) -> float:
		return f.get_string_size(s if s != "" else "w", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).y

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
			var f := Interface800.font()
			var fs := _fs()
			var kv := _kv()
			_lines = _wrap(t.split("\n"), f, fs, vp.get_visible_rect().size.x * 0.45)
			var w := 0.0
			var h := 0.0
			for s in _lines:
				w = maxf(w, f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
				h += _line_h(f, fs, s)
			var sz := Vector2(w + 12.0 * kv.x, h + 8.0 * kv.y)
			var area := vp.get_visible_rect().size
			var r := Rect2(mp + Vector2(24, 24) * kv, sz)
			if r.end.x > area.x:
				r.position.x = maxf(0.0, area.x - sz.x)
			if r.end.y > area.y:
				r.position.y = maxf(0.0, mp.y - sz.y)
			_panel.position = r.position
			_panel.size = sz
			_panel.visible = true
			_panel.queue_redraw()

	## Remake: a line wider than `w` is broken at spaces (a few remake tips are
	## a paragraph long; the original's fit on one line). A wrapped first line
	## (the title colour) keeps its colour: only the title's own line is TITLE.
	func _wrap(src: PackedStringArray, f: Font, fs: int, w: float) -> PackedStringArray:
		var out := PackedStringArray()
		_title_lines = 1
		for i in src.size():
			var cur := ""
			for word in src[i].split(" "):
				var nxt := word if cur == "" else cur + " " + word
				if cur != "" and f.get_string_size(nxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
					out.append(cur)
					if i == 0:
						_title_lines += 1
					cur = word
				else:
					cur = nxt
			out.append(cur)
		return out

	func _draw_tip() -> void:
		var f := Interface800.font()
		var fs := _fs()
		var kv := _kv()
		var r := Rect2(Vector2.ZERO, _panel.size)
		_panel.draw_rect(r, FILL)
		_panel.draw_rect(r.grow(-0.5), TITLE, false, 1.0)
		var y := 4.0 * kv.y
		for i in _lines.size():
			var s := _lines[i]
			_panel.draw_string(f, Vector2(6.0 * kv.x, y + f.get_ascent(fs)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				TITLE if i < _title_lines else BODY)
			y += _line_h(f, fs, s)

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
			out.append((RemakeText.t("Native (%d × %d)") if i == 0 else "%d × %d") % [v.x, v.y])
		return out
	var out: Array = RemakeText.tl(DISPLAY_CHOICES.get(name, []))
	if name == "q_aa" and metalfx():
		out[5] = "MetalFX"   # the same row: Apple's temporal upscaler stands in for FSR 2
	return out


## macOS on the Metal driver: Apple's MetalFX upscalers replace AMD FSR
## (render scale below 100 %: MetalFX spatial; anti-aliasing row 5: MetalFX temporal).
static func metalfx() -> bool:
	return OS.get_name() == "macOS" and RenderingServer.get_current_rendering_driver_name() == "metal"


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
## The pointer mode outside drags: confined to the window (remake option
## confine_mouse) or free. Godot drops the confinement while the window is
## unfocused and restores it on focus.
func free_mouse_mode() -> Input.MouseMode:
	if Portability.constrained():
		return Input.MOUSE_MODE_VISIBLE
	return Input.MOUSE_MODE_CONFINED if option("confine_mouse") != 0 else Input.MOUSE_MODE_VISIBLE


func apply_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if Input.mouse_mode in [Input.MOUSE_MODE_VISIBLE, Input.MOUSE_MODE_CONFINED]:
		Input.mouse_mode = free_mouse_mode()


func _apply_window() -> void:
	# A headless simulation child owns its frame limit. In particular, the
	# delayed startup window update must not replace it with the visible
	# player's limit (often unlimited) after LocalHost.listening().
	if Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--local-host-config=")):
		return
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
		# FSR 1 is Forward+ only (Mobile warns and draws bilinear).
		var smode := Viewport.SCALING_3D_MODE_FSR if scale < 0.999 and RenderingServer.get_current_rendering_method() == "forward_plus" else Viewport.SCALING_3D_MODE_BILINEAR
		if option("q_aa") == 5 and RenderingServer.get_current_rendering_method() == "forward_plus":   # FSR 2: anti-aliasing and upscaler in one
			# Its Quality mode (1.5× upscale): at a 100 % render scale it would
			# only anti-alias at native resolution, dearer than the other modes.
			smode = Viewport.SCALING_3D_MODE_METALFX_TEMPORAL if metalfx() else Viewport.SCALING_3D_MODE_FSR2
			scale = minf(scale, FSR2_SCALE)
		elif smode == Viewport.SCALING_3D_MODE_FSR and metalfx():
			smode = Viewport.SCALING_3D_MODE_METALFX_SPATIAL
		scale = clampf(scale, 0.25, 2.0)
		if smode != Viewport.SCALING_3D_MODE_BILINEAR and scale > 1.0:
			smode = Viewport.SCALING_3D_MODE_BILINEAR   # FSR and MetalFX only upscale
		# Each setter reconfigures the render buffers at once: going from a
		# supersampled scale (> 1) to FSR, the mode set before the scale made
		# Godot warn "FSR ... not designed for downsampling" for that moment.
		# Bilinear first, then the scale, then the mode.
		if vp.scaling_3d_mode != smode:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = scale
		vp.scaling_3d_mode = smode
		Gfx.apply_quality(vp)
	_show_fps(option("show_fps") != 0)
	# Physics interpolation (phys_interp): only the units take part
	# (GameUnit: on, its figure off so the animation is drawn as posed); the
	# rest of the tree is off, as everything else moves in _process.
	if is_inside_tree():
		get_tree().root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		get_tree().physics_interpolation = option("phys_interp") != 0
	apply_mouse_mode()
	if DisplayServer.get_name() == "headless" or Portability.constrained() or OS.get_cmdline_user_args().has("--touch"):
		return
	DisplayServer.window_set_vsync_mode([DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED,
		DisplayServer.VSYNC_ADAPTIVE][clampi(option("vsync"), 0, 2)])
	var state := [mode, size, ri]
	if state == _window_state:
		return
	_window_state = state
	_place_window(mode, size, ri == 0)


var _window_gen := 0


## Puts the main window in the display mode, through the root Window so its
## viewport always follows the window: DisplayServer calls alone leave the
## viewport at the old size on X11 (a 3840×2160 menu drawn into a 1280×720
## window, cut off). Sizes are physical pixels on every platform (Windows: the
## process is system-DPI aware, so 125 % … 200 % scaling changes nothing here).
## Fullscreen / borderless fullscreen: Godot's own modes, which cover the
## monitor exactly; the window is not pre-sized to the screen first (a framed
## window that big hangs over the screen edges until the mode switch lands).
## Windowed: the window with its frame inside the screen's usable area.
func _place_window(mode: int, size: Vector2i, native: bool) -> void:
	_window_gen += 1
	var gen := _window_gen
	var w := get_tree().root
	if mode == 0:
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
			w.mode = Window.MODE_WINDOWED
		w.borderless = false
		_fit_windowed(size)
		if native:   # the whole work area (maximised where a window manager runs)
			w.mode = Window.MODE_MAXIMIZED
		# The frame is known only once the window is framed again (after
		# fullscreen) and the window manager has placed it: measure again.
		for i in 4:
			await get_tree().process_frame
		if gen == _window_gen and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
			_fit_windowed(size)
		return
	w.mode = Window.MODE_EXCLUSIVE_FULLSCREEN if mode == 1 else Window.MODE_FULLSCREEN
	if DisplayServer.get_name() != "X11":   # Windows / macOS / Wayland: the mode itself covers the screen
		return
	for i in 10:
		await get_tree().process_frame
	if gen != _window_gen:
		return
	var scr := DisplayServer.window_get_current_screen()
	var screen := Rect2i(DisplayServer.screen_get_position(scr), DisplayServer.screen_get_size(scr))
	if Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size()) != screen:
		# No window manager honours the fullscreen state (a bare X server):
		# the window made borderless and laid over the whole screen.
		w.borderless = true
		w.position = screen.position
		w.size = screen.size


## The windowed size (clamped so the window and its frame fit the usable area,
## i.e. without the taskbar / panels), centred there.
func _fit_windowed(size: Vector2i) -> void:
	var w := get_tree().root
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var deco := (DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()).clamp(Vector2i.ZERO, area.size / 4)
	var s := size.min(area.size - deco).max(Vector2i(320, 240))
	w.size = s
	var want := area.position + (area.size - s - deco) / 2   # where the frame's corner goes
	var inset := (DisplayServer.window_get_position() - DisplayServer.window_get_position_with_decorations()).clamp(Vector2i.ZERO, deco)
	w.position = want + inset   # a move places the client area (Windows; X11: static gravity)


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
