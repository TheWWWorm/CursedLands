class_name Game
extends Node3D
## Play mode: owns the current zone world, the camera, input and HUD.
## All player intents go through `issue()` so they can be sent to the host
## in multiplayer (see Session).

var simulation_only := false
var session: Session
var world: GameWorld
var rig: CameraRig
var hud: GameHUD
var selected: Array[GameUnit] = []
var _drag_start := Vector2.ZERO
var _dragging := false
## The left drag became a selection frame (the original input part, set
##  and kept until the button is released; ui/selection_frame.gd).
var _framing := false
## The press of the click being handled was a double click: a move order then
## runs (texts.res "tutor zt1_text_screen2": "If you double-click on the
## point, he will run there"). **Approx.**: the original's handling is not traced.
var _double := false
## Spell waiting for a target click ("" = none).
var pending_spell := ""
var sound: GameSound
var marks: OrderMarks
var _env: Environment
var _sun: DirectionalLight3D
var _sky_mat: ProceduralSkyMaterial
## The original sky dome (EISky: nask0sky + sky00 / sky01); built per zone
## (cave or not). Option gfx_sky adds the remake's sun / moon / stars.
var _sky_shader: ShaderMaterial
var _sky_cave := false
const ShadowDiag := preload("res://src/game/shadow_diag.gd")
const QuestLights := preload("res://src/game/fx/quest_lights.gd")
var _sky_spin := 0.0
## Compatibility only (Android, web; _setup_env): the sun's shadow map rolled
## with the ground (sun_basis). Desktop keeps 0.1.7's Basis.looking_at.
var sun_grid_lock := false
## The sun's shadow direction (_aim_sun): 0 held, re-aimed while the view is
## hidden or after SUN_MAX_LAG (Compatibility); 1 every frame (desktop, as
## 0.1.7); 2 never re-aimed after the zone load (ShadowDiag "freeze").
var sun_aim_mode := 1
## Direction the sun's shadow map is aimed along (Godot space, as the light
## travels); ZERO = not aimed yet. Visual only, never saved or sent.
var _held_sun := Vector3.ZERO
## Compatibility: the clock's direction towards the sun sent as ei_sun_dir.
var sun_light_dir := Vector3.ZERO
var _sun_cam := Vector3.INF
## Re-aims so far and why the last one happened (probe / ShadowDiag).
var sun_reaims := 0
var sun_reaim_reason := ""
var _sun_state := ""
## The forced re-aim: the sun's shadow lags the clock by at most this angle.
const SUN_MAX_LAG_DEG := 10.0
## A camera jump at least this long in one frame is a cut (re-aim).
const SUN_CUT_METRES := 6.0
var _lights: EILights
var _lights_zone := "?"
var cursor: GameCursor
var quest_lights: QuestLights
var speed := 0   # 0 normal, 1 accelerated (clock dial)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	simulation_only = session != null and session.local_host != null and session.local_host.worker
	if simulation_only:
		# Camera state is still needed by save/travel and sound logic; UI and
		# GPU scene systems belong solely to the owner's frontend.
		rig = CameraRig.new()
		add_child(rig)
		rig.set_process(false)
		sound = GameSound.new()
		sound.game = self
		add_child(sound)
		set_process(false)
		set_process_unhandled_input(false)
		return
	_setup_env()
	rig = CameraRig.new()
	add_child(rig)
	hud = GameHUD.new()
	hud.game = self
	add_child(hud)
	var frame := SelectionFrame.new()   # under the HUD widgets, as draws it first
	frame.game = self
	hud.add_child(frame)
	hud.move_child(frame, 0)
	sound = GameSound.new()
	sound.game = self
	add_child(sound)
	add_child(FxRainSnow.new(self))   # precipitation shown by sound.weather's state
	add_child(ContactShadows.new(self))   # option gfx_contact_shadows
	add_child(LocalLighting.new(self))   # firelight and lava lighting, bounded shadow budget
	add_child(SurfaceWeather.new(self))   # rain wetness, roof cover and water ripples
	cursor = GameCursor.new()
	add_child(cursor)
	add_child(UnitFog.new(self))   # units out of the party's range are not drawn (online)
	var diag := ShadowDiag.requested()
	if diag != "":
		add_child(ShadowDiag.new(self, diag))   # on-device sun-shadow diagnostic (off by default)
	marks = OrderMarks.new()
	marks.game = self
	add_child(marks)
	quest_lights = QuestLights.new(self)
	add_child(quest_lights)
	add_child(PadField.new(self))   # remake: the gamepad in the field (PadInput)
	GameData.options_changed.connect(_apply_options)
	get_tree().node_added.connect(_on_node_added)
	_apply_options()


func _setup_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.5, 0.75)
	sky_mat.sky_horizon_color = Color(0.75, 0.78, 0.8)
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	# The 2000 renderer's output (Gfx.setup_original_env): no tone mapping,
	# linear depth fog in the [sky] colour from FogDay/NightStartDistance to
	# the far plane, light colours from the Lights file.
	Gfx.setup_original_env(env)
	# Remake-only rendering quality (options gfx_ssao / gfx_bloom /
	# gfx_volumetric, Gfx.apply_env): ambient occlusion and a light bloom on
	# bright spots.
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_light_affect = 0.15
	# Bloom only above 1.0 in the HDR buffer: emissive lava, fire / magic
	# particles (ParticleFx.GLOW_BOOST), additive overlaps and lightning; the
	# lit scene itself (≤ 1, untonemapped) never blooms.
	env.glow_intensity = 0.7
	env.glow_strength = 1.1
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for lv in 7:
		env.set_glow_level(lv, 1.0 if lv in [1, 2, 3, 4] else 0.0)
	Gfx.setup_volumetric(env)
	Gfx.apply_env(env)
	# Realtime radiance (cheapest per-frame path): the remake sky animates.
	env.sky.radiance_size = Sky.RADIANCE_SIZE_256
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env
	_sky_mat = sky_mat
	var sun := DirectionalLight3D.new()
	_sun = sun
	# Direction and colour are set per frame (_update_daylight).
	sun.rotation_degrees = Vector3(-55, 60, 0)
	sun.light_energy = 1.0
	# Desktop (Forward+) shadows were steady: the sun stays as in 0.1.7 there.
	# On phones / web (any renderer) and Compatibility its shadow is held and
	# rolled (_aim_sun) and marked so light() reads the clock's direction.
	if Portability.held_sun():
		sun_aim_mode = 0
		sun_grid_lock = true
		sun.light_specular = Gfx.SUN_MARK
	sun.shadow_enabled = true
	# Out-of-view figures cast nothing, and neither does the land
	# (Gfx.setup_sun_casters, below).
	sun.shadow_caster_mask = 0xFFFFFFFF & ~GameUnit.OFFSCREEN_LAYER
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.5
	sun.shadow_bias = 0.04
	# Compatibility (GLES3, phones / web): at 1.2 sun-facing stone (ruin
	# floors, pillars) showed striped self-shadow acne that crawled as the
	# sun turned (Forward+ is clean there); 2.0 clears it
	# (tools/shadow_shimmer_probe.gd). Phones on Vulkan go with the held sun.
	sun.shadow_normal_bias = 2.0 if Portability.held_sun() else 1.2
	add_child(sun)
	Gfx.setup_sun_casters(sun)


func _process(dt: float) -> void:
	if world == null:
		return
	if not session.is_host and not get_tree().paused and not session.loading_game and not session.movie_active():
		session.state.world_time = fmod(session.state.world_time + dt / CampaignState.HOUR_SECONDS, 24.0)   # same pace as the host VM
	_update_daylight()
	_keep_selection()
	_update_cursor()


## Remove units that died or left the player's control. The command selection
## may stay empty: can toggle the last unit off, and
## clears its command widgets. The unit panel can still show a hovered unit
## (prefers over the selected).
func _keep_selection() -> void:
	var keep := selected.filter(func(s): return is_instance_valid(s) and not s.dead \
			and s.controller == session.my_index)
	if keep.size() != selected.size():
		selected.assign(keep)


## Clock dial sectors: 0 pause on/off, 1 normal speed, 2
## accelerated speed. The original's logic tick is 55 ms normally and 27 ms
## accelerated. Remake option coop_clock lets the co-op host
## control a shared pause and exact 2x rate; clients receive that choice.
func set_speed(sector: int) -> void:
	if session.multiplayer_game:
		if session.coop_clock_enabled() and not session.can_manage_game():
			session.message.emit(RemakeText.t("Only the host can change game speed."))
		elif session.coop_clock_enabled():
			sound.ui("buttons\\battle\\clock.wav")
			session.set_coop_clock(sector)
		return
	sound.ui("buttons\\battle\\clock.wav")
	if sector == 0:
		#  case 0: the clock sound and (!paused), no
		# text line (the dial's pause pointer blinks instead, HudDial).
		get_tree().paused = not get_tree().paused
		return
	get_tree().paused = false
	speed = sector - 1
	Engine.time_scale = 55.0 / 27.0 if speed == 1 else 1.0


## Back to normal speed when the field screen goes: CInterface3D's close slot
## (called by the screen stack
## before the screen is deleted) sets the logic tick = 0x37 (55 ms
## normal). That screen is closed whenever the party leaves a zone (the global
## map, another zone, a village or a loaded save get a new screen whose clock
## dial starts = 0, normal); the village screen has
## no clock dial, so a village always runs at normal speed.
func reset_speed() -> void:
	speed = 0
	Engine.time_scale = 1.0
	if session and session.multiplayer_game:
		session.reset_coop_clock()


## Cursor by what is under the mouse (the original cursor set, GameCursor).
func _update_cursor() -> void:
	if cursor.camera_drag_active():
		cursor.set_kind("cursor_camera")
		return
	var vp := get_viewport()
	if hud.blocks_input() or vp.gui_get_hovered_control() != null:
		var portrait: GameUnit = hud._faces.unit_at_screen(vp.get_mouse_position()) if not hud.blocks_input() \
				and vp.gui_get_hovered_control() == hud._faces else null
		cursor.set_kind(pending_cursor(portrait) if portrait and has_spell_target() else "cursor_default")
		return
	if Input.get_mouse_button_mask() & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
		cursor.set_kind("cursor_camera")
		return
	if rig.edge != Vector2i.ZERO:
		cursor.set_kind(GameCursor.SCROLL[rig.edge])
		return
	var p := vp.get_mouse_position()
	var forced := _forced_cursor(p)
	if forced:
		cursor.set_kind(forced)
		return
	var u := pick_unit(p)
	#  modes 7 (Follow) / 8 (Science): no fit target shows
	# cursor 13 "cancel", not the spell's 23 "spellcancel". Follow over a
	# living unit: 15 "move"; Science over a unit: 24 "steal", or cancel on a
	# selected one; over no unit an object to use: 4 "use".
	if pending_spell == FOLLOW:
		cursor.set_kind("cursor_move" if u and not u.dead and not selected.is_empty() else "cursor_cancel")
		return
	if pending_spell == SCIENCE:
		if u and not u.dead:
			cursor.set_kind("cursor_cancel" if u in selected else "cursor_steal")
		else:
			cursor.set_kind("cursor_use" if pick_lever(p) >= 0 else "cursor_cancel")
		return
	if pending_spell:
		cursor.set_kind(pending_cursor(u, pick_ground(p)))
		return
	#  sets cursor 0 (default) first; (normal mode
	#  == 0) then needs a selected unit and picks: a dead unit → 4 (use)
	# a living one → 1 (attack) when hostile, else stays 0; no
	# unit: an object that can be used (vfunc) with exactly one unit
	# selected → 4; else a zone exit under the point (target not
	# "none", the area Session._exit_at tests) whose GS var "z.<target>" is
	# not 1 → 15 (move); plain ground stays 0.
	if revive_target(u) != null:   # remake option "revive": the use cursor over a party body
		cursor.set_kind("cursor_use")
		return
	var k := "cursor_default"
	var me: GameUnit = selected[0] if not selected.is_empty() and is_instance_valid(selected[0]) else null
	if session.shop_available():
		# The village screen's hover (not): cursor 0
		# the talk cursor 0xe over any living unit — no side check, own party
		# and NPCs alike — with topics (count > 0); with no
		# living unit under the point, 15 (move) over an open zone exit as in
		# the field. Its name label is VillageName's.
		if u and not u.dead:
			if u.village_talk_ready() and not Briefings.pending_for(session.state, u, session.my_index).is_empty():
				k = "cursor_talk"
		elif _over_open_exit(p):
			k = "cursor_move"
	elif u and u.controller == session.my_index:
		pass
	elif u and u.dead:
		k = "cursor_use" if me else "cursor_default"
	elif u and me:
		k = "cursor_attack" if world.is_enemy(me, u) else "cursor_default"
	elif me and selected.size() == 1 and pick_lever(p) >= 0:
		k = "cursor_use"
	elif me and _over_open_exit(p):
		k = "cursor_move"
	cursor.set_kind(k)


## Remake option "revive" (Revive): `u` when it is a fallen party member that
## a selected living hero or mercenary can help up, else null.
func revive_target(u: GameUnit) -> GameUnit:
	if u == null or not u.dead or not Revive.revivable(session, u):
		return null
	for s in selected:
		if is_instance_valid(s) and Revive.can_help(s, u):
			return u
	return null


##  exit test: the ground point under `p` lies in a zone exit
## whose target is not "none" and whose GS var "z.<target>" is not 1.
var _exit_hover_p := Vector2.INF
var _exit_hover_n := -1

func _over_open_exit(p: Vector2) -> bool:
	if session == null or session.world == null or session.state == null:
		return false
	if p != _exit_hover_p:
		_exit_hover_p = p
		var g = pick_ground(p)
		_exit_hover_n = session._exit_at(g) if g != null else -1
	if _exit_hover_n < 0:
		return false
	var to := String(session.world.zone.exits[_exit_hover_n].get("to", "none"))
	var key := LmpMode.exit_var(to) if not session.lmp.is_empty() else "z." + to.to_lower()
	return session.state.get_var(0, key) != 1.0


## The aim armed for the next click (index into AIM_ORDER), −1 none: by the
## touch Aim button, or by an aimed-strike key with the remake option
## aim_press_once (then aim_by_key is set; any other assignment clears it).
var touch_aim := -1:
	set(v):
		touch_aim = v
		aim_by_key = false
var aim_by_key := false
var touch_force := ""

func cancel_touch_target() -> void:
	touch_aim = -1
	touch_force = ""
	pending_spell = ""
	if hud:
		hud.set_targeting("")

func held_aim() -> int:
	if touch_aim >= 0:
		return touch_aim
	if GameData.option("aim_press_once") == 1:
		return -1   # the keys arm touch_aim instead (_key_action)
	for i in AIM_ORDER.size():
		if EIKeymap.held(AIM_ORDER[i]):
			return i
	return -1


## Forced orders by held keys (the original, the field's left button
## up, and, its cursor), only while a unit is selected and before
## any interaction mode: Alt (manager) "alt", an aimed strike key (flags
##  + i) "aim", Ctrl "ctrl", checked in this order; "" none.
func _forced_mode() -> String:
	if touch_force != "":
		return touch_force
	if selected.is_empty():
		return ""
	if Input.is_key_pressed(KEY_ALT):
		return "alt"
	if held_aim() >= 0:
		return "aim"
	if Input.is_key_pressed(KEY_CTRL):
		return "ctrl"
	return ""


##  forced cursors: Alt → 15 (move) over a zone exit
## else the arrow; an aimed key → 16 + i; Ctrl → 1 (attack)
## wherever the pointer is.
func _forced_cursor(p: Vector2) -> String:
	match _forced_mode():
		"alt":
			var g = pick_ground(p)
			return "cursor_move" if g != null and session._exit_at(g) >= 0 else "cursor_default"
		"aim":
			return AIM_CURSORS[held_aim()]
		"ctrl":
			return "cursor_attack"
	return ""


##  with a unit selected, before the interaction mode switch
## (the mode, stays set):
## - Alt: a move to the clicked unit's position or the ground point (packet
##   0x30, (…, 0, double click)) — the forced move
## - an aimed key: a living unit is attacked with that aim (
##   packet 0x31 with the part) whatever its side, own party included; the
##   ground or a corpse: the group move of packet 0x3a;
## - Ctrl: a living unit is attacked (aim 6 = random hit
##   location) whatever its side — the forced attack; else the 0x3a move.
## Packet 0x3a ((…, 1, …) →; server
## ) is a move in the Player motivation's state 2 (= 2)
## which its tick runs the engage check on every
## tick of the walk, searching round the destination (Session "move" with
## "swarm", UnitAI.swarm_tick). Every order carries the double-click flag.
func _forced_click(p: Vector2) -> bool:
	var m := _forced_mode()
	if m == "":
		return false
	var u := pick_unit(p)
	var g: Variant = null
	if (m == "alt" and u == null) or (m != "alt" and not (u and not u.dead)):
		g = pick_ground(p)
	forced_on(m, u, g)
	return true


## The forced order `m` ("alt" / "aim" / "ctrl") on a unit or a ground point
## (EI xy or null); the gamepad's LT layer and context ring use it too.
func forced_on(m: String, u: GameUnit, g: Variant) -> void:
	var ids := selected.map(func(s: GameUnit): return s.uid)
	if m == "alt":
		var to: Variant = u.pos if u else g
		if to != null:
			var cmd := {"t": "move", "units": ids, "x": to.x, "y": to.y, "run": _double}
			if u == null:
				_tag_exit_click(cmd, to)
			issue(cmd)
			marks.move_ordered(to)
		return
	if u and not u.dead:
		var cmd := {"t": "attack", "units": ids, "target": u.uid, "run": _double}
		if m == "aim":
			cmd.aim = held_aim()
		issue(cmd)
		marks.unit_ordered(u, true, -1.0, selected)
		return
	if g != null:
		issue({"t": "move", "units": ids, "x": g.x, "y": g.y, "run": _double, "swarm": true})
		marks.move_ordered(g)


## Day / night from the campaign clock (world_time, hours), as the daylight
## update: sun, ambient and sky (fog) colours from the allod's
## config/Lights[Cave]<Allod>.ini interpolated per hour, the sun direction, the
## fog start; the far plane is FarClipDistance (Gfx).
func _update_daylight() -> void:
	var zid := String(world.zone.get("id", ""))
	var new_zone := zid != _lights_zone
	if new_zone:
		_lights_zone = zid
		var allod := String(world.zone.get("allod", "")).capitalize()
		_sky_cave = String(world.zone.get("sky", "")) == "cave"
		_lights = EILights.load_for(allod if allod else EILights.allod_of(zid), _sky_cave)
		_sky_shader = EISky.material(_sky_cave)
		_apply_sky()
	var hour := session.state.world_time if session and session.state else 12.0
	# Sun direction (EISky.light_dir_ei); caves use its fixed
	# (0.5, 0.5, −0.7071).
	var ld := Vector3(0.5, 0.5, -0.70710677) if _sky_cave else EISky.light_dir_ei(hour)
	var gd := EISpace.vec(ld).normalized()
	_aim_sun(gd, new_zone)
	if not get_tree().paused:
		_sky_spin += get_process_delta_time() * EISky.SPIN_PER_SECOND
	if not _sky_cave:
		EISky.set_spin(_sky_shader, _sky_spin)
	if rig and rig.camera:
		rig.camera.near = minf(rig.camera.near, Gfx.NEAR_CLIP)
		rig.camera.far = Gfx.far_clip()
	_update_hero_lights()
	if rig:
		Gfx.update_pass_lights(get_tree(), rig.global_position)
	if _lights == null:
		return
	Gfx.update_original(_env, _sun, _lights, hour, _sky_cave)
	# Lighting keeps the clock: the land's vertex light and the EI materials'
	# sun term read ei_sun_dir, not the held light's direction (_aim_sun).
	if sun_aim_mode != 1:
		sun_light_dir = -gd
		RenderingServer.global_shader_parameter_set(&"ei_sun_dir", sun_light_dir)
	var sky := _env.fog_light_color
	_sky_mat.sky_top_color = sky
	_sky_mat.sky_horizon_color = sky
	_sky_mat.ground_horizon_color = sky
	_sky_mat.ground_bottom_color = sky
	if _sky_shader:
		EISky.update(_sky_shader, _lights, hour, _sky_cave, Gfx.on("gfx_sky"))
		Gfx.update_volumetric(_env, _sun.light_color, _sky_cave)
		_env.volumetric_fog_albedo = sky.lerp(Color.WHITE, 0.5)


## remake, phones / web on any renderer and Compatibility (Portability.held_sun; sun_aim_mode 0): the sun's
## shadow map is aimed along a held direction instead of the clock's. Desktop
## (sun_aim_mode 1) turns it every frame with Basis.looking_at, as 0.1.7. Turning it with the sun (15° per game hour, ≈ 0.3° a second)
## swept the map's texel grid over the land, since Godot snaps the cascades
## to whole texels counted from the world origin: every shadow edge and the
## objects' self-shadowing flickered, worst with the 1024 atlas on phones and
## in browsers (an orthographic map along a changing direction cannot keep
## the ground on fixed texels; rolling it, sun_basis, only slows the sweep).
## It is re-aimed where no one sees the jump: on a zone load, while the 3D
## view is hidden (GameHUD.world_hidden: map, inventory / trade, dialogue,
## Esc and its screens, objectives, movies) and on a camera cut; and, so the
## shadows never lag far behind the light, once the clock has turned the sun
## SUN_MAX_LAG_DEG away (≈ 40 game minutes, 33 s of daytime play). Lighting
## keeps the exact direction (ei_sun_dir; the EI materials' light() reads it
## for the marked sun, Gfx.SUN_MARK). Visual only: nothing is saved or sent.
func _aim_sun(gd: Vector3, new_zone: bool) -> void:
	var reason := ""
	var cam := rig.camera.global_position if rig and rig.camera and rig.camera.is_inside_tree() else Vector3.INF
	if _held_sun == Vector3.ZERO:
		reason = "start"
	elif new_zone:
		reason = "zone"
	elif sun_aim_mode == 1:
		reason = "continuous"
	elif sun_aim_mode == 2:
		reason = ""
	elif hud and hud.world_hidden():
		reason = "view"
	elif cam != Vector3.INF and _sun_cam != Vector3.INF and cam.distance_to(_sun_cam) >= SUN_CUT_METRES:
		reason = "cut"
	elif rad_to_deg(_held_sun.angle_to(gd)) >= SUN_MAX_LAG_DEG:
		reason = "cap"
	_sun_cam = cam
	if sun_aim_mode == 1:
		_held_sun = gd   # exactly the clock's (desktop, as 0.1.7)
	if reason != "" and not _held_sun.is_equal_approx(gd):
		# a hidden view or the continuous mode re-aims every frame: count once
		if reason != _sun_state or (reason != "view" and reason != "continuous"):
			sun_reaims += 1
			sun_reaim_reason = reason
		_held_sun = gd
	_sun_state = reason
	_sun.basis = sun_basis(_held_sun) if sun_grid_lock else Basis.looking_at(_held_sun, Vector3.FORWARD if absf(_held_sun.y) > 0.99 else Vector3.UP)


## Forces a re-aim on the next frame (tools; ShadowDiag preset changes).
func reaim_sun() -> void:
	_held_sun = Vector3.ZERO


## The sun's basis for light direction `d` (Godot space, as the light
## travels), rolled about the light axis so that the shadow map's X axis
## falls on the world X axis on the ground. Lighting does not depend on the
## roll, only the shadow map's orientation does. Basis.looking_at keeps the
## map's X axis level and square to the sun's azimuth, so the map turned
## with the sun (15° per game hour, ≈ 0.3° a second) and its texel grid
## swept over the land: every shadow edge's texel stairs and the self-
## shadowing on objects crawled each frame (worst on phones / web with
## the 1024 atlas). Rolled, the grid's X axis stays on world X and only its
## scale drifts slowly with the sun's height and azimuth (Godot already
## snaps the cascades to whole texels as the camera moves).
static func sun_basis(d: Vector3) -> Basis:
	var b0 := Basis.looking_at(d, Vector3.FORWARD if absf(d.y) > 0.99 else Vector3.UP)
	var a := b0.x
	var b := b0.y
	var al := atan2(-a.z, b.z)
	if cos(al) * a.x + sin(al) * b.x < 0.0:
		al += PI
	var xv := a * cos(al) + b * sin(al)
	var yv := b * cos(al) - a * sin(al)
	return Basis(xv, yv, b0.z)


## Hero light: every unit a player controls carries a point light (the original
## figure =, switched by the unit's player
## setter): registry Hero Light R/G/B 255 / 236
## 170 and radius 10 m (defaults), 2 m above the unit
## (flags 0x580 — it lights the ground through the max of the
## diffuse colour, not additively). It is on day and night; under the white
## noon sun the max hides it. On death the Kill sets unit
##   and the next creature tick takes the unit
## off its player, (0) -> (0): the light goes out (gated
## the logic's, not traced); here it goes when `dead` is set, every peer.
const HERO_LIGHT := Color8(255, 236, 170)
const HERO_LIGHT_RADIUS := 10.0
var _hero_lights := {}   # GameUnit -> OmniLight3D


func _update_hero_lights() -> void:
	for k in _hero_lights.keys():
		var u: GameUnit = k if is_instance_valid(k) else null
		if u == null or u.dead or u.controller < 0 or u.world != world:
			if is_instance_valid(_hero_lights[k]):
				_hero_lights[k].queue_free()
			_hero_lights.erase(k)
	for u: GameUnit in world.party_units():
		if u.controller < 0 or u.dead or u.hidden:
			continue
		var l: OmniLight3D = _hero_lights.get(u)
		if l == null:
			l = OmniLight3D.new()
			l.light_color = HERO_LIGHT
			l.light_energy = 1.0
			l.light_specular = 0.0
			l.omni_range = HERO_LIGHT_RADIUS
			l.omni_attenuation = 0.0
			l.shadow_enabled = false
			l.add_to_group(Gfx.POINT_LIGHT_GROUP)
			add_child(l)
			_hero_lights[u] = l
		l.global_position = u.global_position + Vector3(0.0, 2.0, 0.0)


## The original sky dome (EISky) once a zone is known; option gfx_sky only adds
## the remake's extras inside it (EISky.update).
func _apply_sky() -> void:
	_env.sky.sky_material = _sky_shader if _sky_shader else _sky_mat
	# The dome turns slowly; realtime radiance keeps reflections in step.
	_env.sky.process_mode = Sky.PROCESS_MODE_REALTIME if _sky_shader else Sky.PROCESS_MODE_AUTOMATIC


## Called by Session when a zone has been loaded.
func attach_world(w: GameWorld) -> void:
	if world and world != w:
		if session.lmp_travel and session.lmp_travel.contains(world):
			# The host's base view and quest view are independent of its server:
			# other registered quest owners keep this hidden world running.
			world.visible = false
		else:
			GameData.trace("zone teardown %s" % world.zone.get("id", ""))
			world.queue_free()
	world = w
	w.visible = true
	w.process_mode = Node.PROCESS_MODE_PAUSABLE   # the Game node itself runs while paused
	reset_speed()   # a new zone = a new field / village screen
	# ...so no spell / belt item / Follow target is still being chosen: it
	# named the old zone's units (a load gives new ones with the same uids).
	cancel_touch_target()
	if w.get_parent() == null:
		add_child(w)
	rig.terrain = w.terrain
	selected.clear()
	var mine := my_units()
	if not mine.is_empty():
		selected = [mine[0]]
		rig.focus(mine[0].position)
		# The field screen's first activation follows party
		# member 0; modern: the glide and attachment.
		rig.follow(mine[0])
	if hud:
		hud.on_world(w)
	sound.on_world(w)
	if simulation_only:
		return
	_apply_shadows(w)
	_fit_shadows()
	var pfx := ParticleFx.of(w)
	pfx.gs_var = func(k: String) -> float:
		return session.state.get_var(0, k) if session != null and session.state != null else 0.0
	pfx.setup_zone()   # zone exit stars and torch fires (every peer)
	GroundMarks.of(w)   # footprints and blood marks (every peer)
	quest_lights.on_world(w)   # existing OBJ_QUEST_INFO, including a late join


func my_units() -> Array[GameUnit]:
	var out: Array[GameUnit] = []
	if world:
		for u: GameUnit in (world.party_units() if session.my_index >= 0 else world.units.values()):
			if u.controller == session.my_index and not u.dead:
				out.append(u)
	# Party member indices belong to the roster, not the world's insertion
	# order. Hiring keeps the mapped NPC in place, before deployed heroes.
	# Native village clicks, select1..3 and party faces all use roster order.
	if session and session.state:
		var roster: Array = Array(session.state.heroes.get(session.my_index, [])).duplicate()
		for m: Dictionary in session.state.mercs.values():
			if int(m.get("controller", -1)) == session.my_index and session.state.merc_party_active(m):
				roster.append(m)
		var ordered: Array[GameUnit] = []
		for h: Dictionary in roster:
			for i in out.size():
				if out[i].has_meta("hero") and out[i].get_meta("hero") == h:
					ordered.append(out.pop_at(i))
					break
		ordered.append_array(out)   # controlled non-roster units keep world order
		return ordered
	return out


# ------------------------------------------------------------------ input

## pending_spell value while choosing a Use/Steal target (keyboard.ini "use_science").
const SCIENCE := "@science"
## pending_spell value while choosing whom the selection follows (HUD Follow).
const FOLLOW := "@follow"
## Aimed strikes (keyboard.ini cs_* on the numpad) are held keys, not a mode:
## the original's key-down switch cases 0x11–0x16 set the field
## controller's flags.. (cs_head, cs_body, cs_lhand, cs_rhand
## cs_lleg, cs_rleg) and its key-up clears them. While one is
## held the cursor is the aimed one (: 16 + i, cursor_attack_hd
## bd / lh / rh / ll / rl load order) and a click attacks the
## clicked living unit with aim i (: the first held flag in that
## order; the unit's order) whatever its side; see _forced_click.
const AIM_ORDER := ["cs_head", "cs_body", "cs_lhand", "cs_rhand", "cs_lleg", "cs_rleg"]
const AIM_CURSORS := ["cursor_attack_hd", "cursor_attack_bd", "cursor_attack_lh", "cursor_attack_rh",
	"cursor_attack_ll", "cursor_attack_rl"]


func _unhandled_input(e: InputEvent) -> void:
	if world == null or hud.blocks_input():
		return
	if (touch_aim >= 0 or touch_force != "") and ((e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT and e.pressed) or (e is InputEventKey and e.keycode == KEY_ESCAPE and e.pressed)):
		cancel_touch_target()
		get_viewport().set_input_as_handled()
		return
	if e is InputEventMouseButton and e.pressed and not pending_spell.is_empty() \
			and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] \
			and not (e.button_index == MOUSE_BUTTON_LEFT and _forced_mode() != ""):
		if e.button_index == MOUSE_BUTTON_LEFT:
			_double = e.double_click
			_cast_at(e.position)
		pending_spell = ""
		hud.set_targeting("")
		get_viewport().set_input_as_handled()
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_drag_start = e.position
			_double = e.double_click
			_dragging = true
			_framing = false
		elif _dragging:
			_dragging = false
			# Left button up: frame selection when the frame was
			# started, else a click; the flag is cleared.
			var framed := _framing or _frame_started(e.position)
			_framing = false
			if framed:
				_box_select(Rect2(_drag_start, e.position - _drag_start).abs(), e.shift_pressed)
			else:
				_click(e.position, e.shift_pressed)
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.pressed and not e.echo:
		var act := EIKeymap.event_action(e)
		# the original's key switch and its click handler
		# have no pause test: during the active pause (Space) every key works
		# and orders are given (the units carry them out when the game runs
		# on); only accel / decel refuse while paused (cases 2 / 3). A
		# tutorial window (which pauses the single player game) keeps the keys.
		if hud._tutorial.visible and not act in ["pause", "quickload"] and e.keycode != KEY_ESCAPE:
			return
		if act:
			_key_action(act)
			return
		match e.keycode:   # remake-only windows on keys the original leaves free
			KEY_ENTER, KEY_KP_ENTER:   # co-op chat (NetStatus; Enter is unbound in keyboard.ini)
				if session.multiplayer_game:
					hud.chat_line.open()
					get_viewport().set_input_as_handled()
			KEY_BACKSPACE:   # a network game's chat list cleared
				if session.multiplayer_game:
					hud.clear_chat()
					get_viewport().set_input_as_handled()
			KEY_J:
				hud.toggle_journal()
			KEY_G:   # remake-only: the side-quest offers have no original entry point
				if session.shop_available():
					hud.toggle_side_quests()
			KEY_B:
				hud.toggle_inventory()
			KEY_ESCAPE:
				if pending_spell:
					pending_spell = ""
					hud.set_targeting("")
				else:
					hud.toggle_menu()


func _key_action(act: String) -> void:
	# Ctrl or Alt held (UI manager) changes several keys
	var mod := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT)
	var n := int(act.right(1)) - 1
	if act.begins_with("spell"):   # cases 0x1e–0x25: / with Ctrl, Alt
		hud._slots.use(n, mod)
		return
	if act.begins_with("item"):    # cases 0x2a–0x2d: / with Ctrl, Alt
		hud._belt.use(n, mod)
		return
	if act.begins_with("weapon"):  # cases 0x26–0x29
		hud._weapons.key_select(n)
		return
	if act.begins_with("w_info"):  # cases 0x2e–0x31: the unit panel's views
		hud.unit_panel.key_view(n)
		return
	if act.begins_with("camera") and act.length() == 7:   # camera1–4:
		rig.view_slot(n, mod)
		return
	if act.begins_with("select") and act != "select_all":
		# Cases 0x37–0x39: on_off.wav, (i) selects party member i
		# with Ctrl / Alt the camera also goes to it.
		var mine := my_units()
		sound.ui("buttons\\battle\\on_off.wav")
		if n < mine.size():
			selected = [mine[n]]
			GameSound.ack(mine[n], EIAcks.SELECTED)
			if mod or rig.modern():
				rig.follow(mine[n])
		return
	match act:
		"select_all":   # case 0x3a, not in a network game
			if not session.multiplayer_game:
				sound.ui("buttons\\battle\\on_off.wav")
				selected = my_units()
		"accel", "decel":
			# Cases 3 / 2 (KP_PLUS / KP_MINUS): neither paused nor a network
			# game — clock.wav, speed = 1 / 0, tick 27
			# 55 ms (the clock dial's sectors, set_speed).
			if not get_tree().paused and (not session.multiplayer_game or session.coop_clock_enabled()):
				set_speed(2 if act == "accel" else 1)
		"w_minimap":   # case 0x34
			hud.minimap.key_toggle()
		"run", "walk", "sneak", "crawl":
			hud.set_move_mode(act)
		"swarm":   # keyboard.ini "A swarm": the original key action 0x1c
			hud.toggle_aggression()
		"pause":
			set_speed(0)
		"quicksave":
			session.save_game("quick")
		"quickload":
			if session.can_manage_game() and not await session.load_game_shown("quick"):
				hud.log_msg(RemakeText.t("No quick save."))
		"follow":   # HUD Follow: the next click picks the unit to follow
			if not selected.is_empty():
				cancel_touch_target()
				pending_spell = FOLLOW
				hud.set_targeting(GameData.text("tip 10510").strip_edges())
		"use_science":   # Use/Steal: the next click picks the target
			if selected.size() == 1 and is_instance_valid(selected[0]) and not selected[0].dead:
				cancel_touch_target()
				pending_spell = SCIENCE
				hud.set_targeting(Skills.title("science"))
		"cs_head", "cs_body", "cs_rhand", "cs_lhand", "cs_rleg", "cs_lleg":
			# Original: held keys, read by held_aim at the click (
			# sets the flag on key-down, clears it on key-up).
			# Remake option aim_press_once: one press arms the aim until the
			# next click (_click / right click / Esc); the same key again
			# cancels it, another aim key switches.
			if GameData.option("aim_press_once") == 1:
				var i := AIM_ORDER.find(act)
				if touch_aim == i:
					touch_aim = -1
				elif not selected.is_empty():
					pending_spell = ""
					touch_force = ""
					hud.set_targeting("")
					touch_aim = i
					aim_by_key = true
		"obj":
			open_quests()
		"tutorial_script":
			hud._tutorial.show_last()
		"w_text1", "w_text2":   # keyboard.ini L / K: key actions 50 / 51 -> (0 / 1)
			hud.text_window.key_mode(0 if act == "w_text1" else 1)
		"camera_norm":   # key N: case 0xc, same as the minimap's N button
			hud.minimap.north()
		"camera_track":   # HOME, case 0xb: follow the first selected, none → stop (−1)
			rig.follow(null if selected.is_empty() else selected[0])


## Keyboard.ini "obj" (TAB) and the clock dial's inner disc: the quests
## screen (without a route). In a game zone case 4
## plays buttons\battle\click.wav and opens the current zone's; in a village
## (no conversation showing) it opens in browse mode, silently, only when a
## quest of the village's allod is open (ZoneObjectives.browse_zones).
func open_quests() -> void:
	if hud.quests_screen or session.world == null:
		return
	if session.shop_available():
		if hud._dialog.visible or ZoneObjectives.browse_zones(session).is_empty():
			return
		hud.open_quests("village", session.zone_id)
	else:
		GameSound.instance.ui("buttons\\battle\\click.wav")
		hud.open_quests("field", session.zone_id)


func _click(p: Vector2, add: bool) -> void:
	# The touch Aim / Force buttons stand for a key held through one click:
	# the click is the held key's (with an aimed flag + i
	# _forced_click: any living unit attacked with that aim, the ground or a
	# corpse a 0x3a group move), then the key counts as released.
	# The issued order keeps its aim for every strike.
	# An aim armed by a key press (option aim_press_once) is used only on a
	# living unit; a click anywhere else just cancels it.
	if touch_aim >= 0 and aim_by_key and not selected.is_empty():
		var t := pick_unit(p)
		if t == null or t.dead:
			cancel_touch_target()
			return
	if _forced_click(p):
		touch_aim = -1
		touch_force = ""
		return
	if touch_aim >= 0:
		cancel_touch_target()   # nothing selected: an ordinary click
	order_on(pick_unit(p), add, p)


## The click rules on a known target: the mouse passes the unit under the
## pointer and the screen point `p` (for the lever and ground picks); the
## gamepad (PadField) its highlighted unit, or `lever` / `ground` (EI xy)
## with `p` null.
func order_on(u: GameUnit, add: bool, p: Variant = null, lever := -1, ground: Variant = null) -> void:
	# Remake option "revive": a click on a fallen party member's body sends a
	# selected living hero or mercenary to help it up (Revive).
	if not add and revive_target(u) != null:
		var helpers := selected.filter(func(s): return is_instance_valid(s) and Revive.can_help(s, u))
		issue({"t": "revive", "units": helpers.map(func(s): return s.uid), "target": u.uid, "run": _double})
		marks.unit_ordered(u, false, Session.LOOT_REACH, marks.first_mine())
		return
	# Villages use an NPC approach before the topic list and a
	# single party leader's ground movement, without field selection. The
	# creature must be in Stop/Rest with no posted primitive; a completed
	# stationary Follow may qualify. Briefings also enforces merc ownership.
	if session.shop_available():
		var party := my_units()
		if party.is_empty():
			return
		if u and not u.dead:
			if u.village_talk_ready() and not Briefings.pending_for(session.state, u, session.my_index).is_empty():
				issue({"t": "interact", "units": [party[0].uid], "target": u.uid})
			return
		var at = pick_ground(p) if p != null else ground
		if at != null:
			var cmd := {"t": "move", "units": [party[0].uid], "x": at.x, "y": at.y, "run": _double}
			_tag_exit_click(cmd, at)
			issue(cmd)
		return
	if u and u.controller == session.my_index:
		# on_off.wav for any click on an own unit, then
		#  selects it; the clicked unit, when it ends up selected
		# says "Selected" (field screen = (unit, 0)
		# client side).
		sound.ui("buttons\\battle\\on_off.wav")
		if _double:
			# The input's double-click byte:, the camera
			# follows the unit (the first click selected it).
			rig.follow(u)
			return
		if add:
			# Toggle (with the modifier), including the last unit.
			if u in selected:
				selected.erase(u)
			else:
				selected.append(u)
				GameSound.ack(u, EIAcks.SELECTED)
		else:
			selected = [u]
			GameSound.ack(u, EIAcks.SELECTED)
		return
	if selected.is_empty():
		return
	var ids := selected.map(func(s: GameUnit): return s.uid)
	# Every order click carries the double-click flag (passes
	# the input byte to the attack / loot / use / move senders
	# ): the order
	# then runs (Session "run", GameUnit.order.run).
	if u and u.dead and Session.lootable(u, session.my_index, multiplayer.get_unique_id() if session.online else 0):
		issue({"t": "loot", "units": ids, "target": u.uid, "run": _double})
		marks.unit_ordered(u, false, Session.LOOT_REACH, marks.first_mine())
		return
	if u and not u.dead and world.is_enemy(selected[0], u):
		issue({"t": "attack", "units": ids, "target": u.uid, "run": _double})
		marks.unit_ordered(u, true, -1.0, selected)
		return
	var lv := pick_lever(p) if p != null else lever
	if lv >= 0:
		issue({"t": "use_lever", "units": ids, "target": lv, "run": _double})
		return
	var g = pick_ground(p) if p != null else ground if ground != null else u.pos if u and not u.dead else null
	if g != null:
		var cmd := {"t": "move", "units": ids, "x": g.x, "y": g.y, "run": _double}
		if u == null:
			_tag_exit_click(cmd, g)
		issue(cmd)
		marks.move_ordered(g)


## Deliberate mouse, touch or gamepad ground activation under the exit
## cursor. Automatic movement and Follow bypass this input route.
func _tag_exit_click(cmd: Dictionary, at: Vector2) -> void:
	var n := session.open_exit_at(at, session.my_index)
	if n >= 0:
		cmd.exit = n


## Option "rubber_select" (CameraFrameSelectionSensetiveArea = slider × 10 px,
## ): starts the frame once the pointer is more than
## that many pixels from the press on either axis; 0 turns frame selection off.
func _frame_started(pos: Vector2) -> bool:
	if session and not session.lmp.is_empty():
		return false   # a native network game has no selection frame
	var area := GameData.option("rubber_select") * 10
	var d: Vector2 = (pos - _drag_start).abs()
	return area >= 1 and (d.x > area or d.y > area)


## The frame to draw (window pixels), empty when none: the press point and the
## pointer normalized as stores them. A screen
## pushed over the field (Esc menu, dialog, travel map) drops the frame as the
## input part's slot 4 clears; a release taken
## something else shows nothing.
func frame_rect() -> Rect2:
	if not _dragging or world == null:
		return Rect2()
	if hud.blocks_input():
		_dragging = false
		_framing = false
		return Rect2()
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return Rect2()
	var p := get_viewport().get_mouse_position()
	if not _framing and _frame_started(p):
		_framing = true
	return Rect2(_drag_start, p - _drag_start).abs() if _framing else Rect2()


## Remake: losing the window focus drops a drag in progress (no release comes).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_dragging = false
		_framing = false


## Frame selection (the original left button up):
## only when the frame holds at least one own party member is the selection
## cleared ((0)) and replaced by those members; a frame over
## nothing keeps the current selection. (The original ignores modifiers here; the
## remake keeps `add` to extend the selection.)
func _box_select(r: Rect2, add: bool) -> void:
	var cam := rig.camera
	var inside: Array[GameUnit] = []
	# Renderer: a part rectangle meets the frame.
	var ri := Rect2i(r.position.floor(), r.size.ceil())
	for u in my_units():
		var rects := u.screen_rects(cam)
		for i in range(1, rects.size()):
			if (rects[i] as Rect2i).intersects(ri):
				inside.append(u)
				break
	if inside.is_empty():
		return
	if not add:
		selected.clear()
	for u in inside:
		if not u in selected:
			selected.append(u)


## Spell slot `i` of the first selected hero: wait for a target click.
## pending_spell prefix while choosing a belt item's target: "@belt:<uid>:<item>".
const BELT := "@belt:"


## One click on a belt item (the original): choose its target next
## the same item again cancels.
func begin_belt(u: GameUnit, item: String) -> void:
	touch_aim = -1
	touch_force = ""
	var key := "%s%d:%s" % [BELT, u.uid, item]
	if pending_spell == key:
		pending_spell = ""
		hud.set_targeting("")
		return
	pending_spell = key
	hud.set_targeting(Items.title(item))


func begin_cast(i: int) -> void:
	if selected.is_empty() or not selected[0].has_meta("hero"):
		return
	var spells: Array = selected[0].get_meta("hero").get("spells", [])
	if i < 0 or i >= mini(8, spells.size()):
		return
	cancel_touch_target()
	pending_spell = spells[i]
	hud.set_targeting(Spells.title(pending_spell))


func _cast_at(p: Vector2) -> void:
	if selected.is_empty():
		return
	cast_on(pick_unit(p), p)


## Remake: a party portrait can supply a living target for a pending spell
## or belt item without changing the selected caster.
func has_spell_target() -> bool:
	return not pending_spell.is_empty() and not pending_spell in [FOLLOW, SCIENCE]


##  use the client's byte Intelligence and
## unsigned-short stamina. The server pays from the unquantized floats.
static func spell_ui_cost(u: GameUnit, sp: Dictionary) -> float:
	# 522ce0 packs the effective attribute with FISTP into one byte.
	var intelligence := GameUnit._fistp(float(u.stats.get("int", 0.0))) & 255
	return float(sp.mana) * 25.0 / intelligence if intelligence > 0 else INF


##  modes 1..4: unit / point spells and unit / point belt items.
## A potion's unit target is its holder; a point potion accepts ground or
## another living unit's feet. Wands use charge instead of stamina. Their
## cursor check (52f8b0) does not test cannot-cast, unlike execution.
func pending_target(u: GameUnit, ground: Variant = null) -> Dictionary:
	if not has_spell_target() or selected.is_empty():
		return {}
	var caster: GameUnit = selected[0]
	if not is_instance_valid(caster) or caster.dead:
		return {}
	var item := ""
	var spell := String(pending_spell)
	var wand := false
	if pending_spell.begins_with(BELT):
		caster = world.units.get(int(pending_spell.get_slice(":", 1))) if world else null
		if not is_instance_valid(caster) or caster.dead or not caster.has_meta("hero"):
			return {}
		var quick: Array = caster.get_meta("hero").get("quick", [])
		var i := Session.find_item(quick, pending_spell.split(":", true, 2)[2])
		if i < 0:
			return {}
		item = String(quick[i])
		wand = Items.is_wand(item)
		if not wand and int(Items.info(item).get("row", {}).get("item_id", -1)) != 8:
			return {}
		spell = Items.spell_of(item) if wand else Items.potion_spell(item)
	else:
		if not caster.has_meta("hero") or caster.cannot_cast():
			return {}
		var i: int = caster.get_meta("hero").get("spells", []).find(spell)
		if i < 0 or i >= 8:
			return {}
	if spell.is_empty():
		return {}
	var sp := Spells.parse(spell)
	if item.is_empty():
		if float(int(caster.mana) & 65535) < spell_ui_cost(caster, sp):
			return {}
	elif wand and Items.charge(item) < float(sp.mana):
		return {}
	var living := is_instance_valid(u) and not u.dead
	if not bool(sp.point):
		if not living or (not item.is_empty() and not wand and u != caster):
			return {}
		return {"caster": caster, "spell": spell, "item": item, "target": u, "point": false}
	var at: Variant = u.pos if living else ground
	if at == null or at == Vector2.ZERO:
		return {}
	return {"caster": caster, "spell": spell, "item": item, "target": null, "point": true, "at": at}


func pending_cursor(u: GameUnit, ground: Variant = null) -> String:
	return "cursor_spell" if not pending_target(u, ground).is_empty() else "cursor_spellcancel"


func can_cast_portrait(u: GameUnit) -> bool:
	return is_instance_valid(u) and not u.dead and not pending_target(u).is_empty()


func cast_portrait(u: GameUnit) -> bool:
	if not can_cast_portrait(u):
		return false
	# A portrait supplies only the target, including a co-op partner.
	# Keep the caster selected and use the normal host-authoritative order.
	cast_on(u)
	cancel_touch_target()
	return true


## The pending spell / belt item / Follow / Use-Steal on a unit, or the
## ground: the screen point `p`, or (gamepad) `ground` (EI xy) / `lever`.
func cast_on(u: GameUnit, p: Variant = null, ground: Variant = null, lever := -1) -> void:
	if selected.is_empty():
		return
	var caster: GameUnit = selected[0]
	if pending_spell == FOLLOW:
		if u and not u.dead:
			issue({"t": "follow", "units": selected.map(func(s: GameUnit): return s.uid), "target": u.uid})
		return
	if pending_spell == SCIENCE:
		if u and not u.dead and u.controller != session.my_index:
			issue({"t": "steal", "unit": caster.uid, "target": u.uid, "run": _double})
		else:
			var lv := pick_lever(p) if p != null else lever
			if lv >= 0:
				issue({"t": "use_lever", "units": [caster.uid], "target": lv, "run": _double})
		return
	var target_info := pending_target(u, pick_ground(p) if p != null else ground)
	if target_info.is_empty():
		return
	caster = target_info.caster
	var cmd := {"t": "cast", "unit": caster.uid, "spell": target_info.spell}
	if not String(target_info.item).is_empty():
		cmd.t = "use"
		cmd.item = target_info.item
	if not target_info.point:
		cmd.target = target_info.target.uid
	else:
		cmd.x = target_info.at.x
		cmd.y = target_info.at.y
	issue(cmd)
	if cmd.t == "cast":
		marks.cast_ordered(caster, String(target_info.spell), target_info.target,
			Vector2(float(cmd.get("x", 0.0)), float(cmd.get("y", 0.0))))


##  hit flag4 dispatches the creature controller
## independently of outer-object quest lights. The reliable
## hitnum event reaches this on both host and clients, including a struck
## hit wholly absorbed by armour.
func electrical_hit(e: Dictionary) -> void:
	var u: GameUnit = world.units.get(int(e.get("uid", -1))) if world else null
	if u == null or not is_instance_valid(u) or u.model == null:
		return
	var fx := ParticleFx.of(world)
	fx.spawn(0x2043, Vector3.ZERO, fx.carrier_size(u).y, u, {"bone": 7, "k118": 10.0})
	marks.flash(u, 4)


## UI-level events from the host (see Session.broadcast).
func on_event(e: Dictionary) -> void:
	sound.on_event(e)   # sounds of broadcast events (GameSound)
	match String(e.get("t", "")):
		"order_path":
			if marks and int(e.get("to", -1)) == session.my_index:
				marks.on_path(e)
		"travel":
			# Leaving the zone closes the field screen (: normal speed)
			# and, in the original, the zone itself: the global map is a world mode
			# its own (clears the world before loading
			# the map record), so nothing of the zone runs behind the map — no
			# attacks, no effects ticking. The remake keeps the zone for its
			# "Stay here" button, frozen until a zone is entered (attach_world) or
			# the map is cancelled.
			reset_speed()
			if world:
				world.process_mode = Node.PROCESS_MODE_DISABLED
		"travel_close":
			if world and not e.has("go"):   # "Stay here": the zone runs again
				world.process_mode = Node.PROCESS_MODE_PAUSABLE
		"vision_fog":
			if simulation_only:
				return
			var tu: GameUnit = world.units.get(int(e.get("uid", -1))) if world else null
			var cu: GameUnit = world.units.get(int(e.get("caster", -1))) if world else null
			if tu and int(e.get("to", -1)) == session.my_index and (not e.has("caster") or cu):
				VisionFog.open(world, tu, float(e.get("secs", 10.0)), session.my_index, cu)
		"music":
			sound.force_music(String(e.get("name", "")), float(e.get("at", 0.0)))
		"ack":
			var who: GameUnit = world.units.get(int(e.get("uid", -1))) if world else null
			if who == null:
				pass
			elif e.has("near"):
				if my_units().any(func(m: GameUnit): return not m.dead and m.pos.distance_to(who.pos) <= float(e.near)):
					if hud: hud._faces.acknowledge(who, int(e.get("code", -1)))
					GameSound.ack(who, int(e.get("code", -1)))
			elif int(e.get("to", -1)) == session.my_index:
				if hud: hud._faces.acknowledge(who, int(e.get("code", -1)))
				GameSound.ack(who, int(e.get("code", -1)))
		"smile":   # remake option "smile_faces" (SmileFaces)
			SmileFaces.show(self, e)
	if hud:
		hud.on_event(e)


## Order acknowledgements (acks.db), spoken by the first unit given the order.
const ORDER_ACKS := {"move": EIAcks.MOVE, "attack": EIAcks.ATTACK, "cast": EIAcks.CAST, "loot": EIAcks.LOOT,
	"interact": EIAcks.USE_OBJECT, "use_lever": EIAcks.USE_OBJECT, "steal": EIAcks.STEAL, "use": EIAcks.USE_POTION,
	"follow": EIAcks.FOLLOW, "revive": EIAcks.USE_OBJECT}

## Whether unit flag (GameUnit.blocked) refuses this command. The
## server's order handlers (
## ) skip flagged units; blocked village heroes can still open topics
## without an approach — basecam's first arrival needs
## the blocked Zak to talk to the elder (b.elder.s1 → FrTP → unblock).
static func block_refuses(t: String, village: bool) -> bool:
	# Follow's separate message handler does not read the bit.
	return ORDER_ACKS.has(t) and t != "follow" and not (village and t == "interact")


func issue(cmd: Dictionary) -> void:
	var t := String(cmd.get("t", ""))
	# A unit with flag (script BlockUnit, or saying a "say_block"
	# line) is left out of the order (skip it; the
	# host enforces it again in Session.apply_command).
	if cmd.has("units") and world and block_refuses(t, session.shop_available()):
		var ids: Array = cmd.units.filter(func(id): return not GameSound.blocked(world.units.get(int(id))))
		if ids.size() != cmd.units.size():
			if ids.is_empty():
				return
			cmd.units = ids
	if ORDER_ACKS.has(t) and world:
		# Start before submit: a synchronous refusal acknowledgement replaces
		# the nod with its shake.
		hud._faces.nod_units(cmd.get("units", [int(cmd.get("unit", -1))]))
	# Attack: before sending, each selected unit
	# whose target is more than 5 levels above it says
	# "BigAttack" (0xa), client side.
	if t == "attack" and world:
		var foe: GameUnit = world.units.get(int(cmd.get("target", -1)))
		for id in cmd.get("units", []):
			var m: GameUnit = world.units.get(int(id))
			if m and foe and unit_level(foe) - unit_level(m) > 5:
				GameSound.ack(m, EIAcks.BIG_ATTACK)
	session.submit(cmd)
	# The order's acknowledgement: in the original the server's order handler
	# answers for every unit given the order (per unit
	# (code), net message 0xb to
	# the unit's player); Follow is said client side by every selected unit
	if ORDER_ACKS.has(t) and world:
		var ids: Array = cmd.get("units", [])
		if ids.is_empty():
			ids = [int(cmd.get("unit", -1))]
		for id in ids:
			var m: GameUnit = world.units.get(int(id))
			if m:
				GameSound.ack(m, ORDER_ACKS[t])


## a named unit's level from its figure, any
## other unit's its prototype's (base_level).
static func unit_level(u: GameUnit) -> int:
	if u.has_meta("hero"):
		return int(u.get_meta("hero").get("level", 1))
	return int(u.proto.get("base_level", 1))


## Screen point -> EI ground xy (or null). solves the projected
## ray against the world's current terrain/BASE-face height. A fixed-distance
## ray march can step past a narrow elevated floor and pick the water behind it.
func pick_ground(p: Vector2) -> Variant:
	var cam := rig.camera
	var from := cam.project_ray_origin(p)
	var dir := cam.project_ray_normal(p)
	if dir.y >= 0.0:
		# Modern free-camera upward/horizontal rays retain the forward-only pick.
		return _pick_ground_forward(from, dir)
	var a := _pick_float(dir.x / dir.y)
	var b := _pick_float(from.x - a * from.y)
	var c := _pick_float(-dir.z / dir.y)
	var d := _pick_float(-from.z - c * from.y)
	var h := _pick_float(world.terrain.max_altitude * 0.5)
	var xy := Vector2(maxf(0.0, _pick_float(a*h+b)), maxf(0.0, _pick_float(c*h+d)))
	h = _pick_float((world.ground_at(xy.x, xy.y) + h) * 0.5)
	var previous := h
	for i in 100:
		previous = h
		xy = Vector2(maxf(0.0, _pick_float(a*h+b)), maxf(0.0, _pick_float(c*h+d)))
		var ground := _pick_float(world.ground_at(xy.x, xy.y))
		var converged := absf(ground-h) <= 0.01
		h = ground
		if converged and i < 99:
			return xy
	# Native fallback for discontinuous terrain/floor heights: averaged guesses,
	# bounded separately to100 queries. Return the last queried XY, not h's XY.
	for i in 100:
		previous = _pick_float((h + previous) * 0.5)
		xy = Vector2(maxf(0.0, _pick_float(a*previous+b)), maxf(0.0, _pick_float(c*previous+d)))
		h = _pick_float(world.ground_at(xy.x, xy.y))
		if absf(h-previous) <= 0.01:
			break
	return xy


static func _pick_float(x: float) -> float:
	return PackedFloat32Array([x])[0]


func _pick_ground_forward(from: Vector3, dir: Vector3) -> Variant:
	var t := 0.0
	while t < 600.0:
		t += 0.5
		var q := from + dir * t
		if q.y <= world.ground_at(q.x, -q.z):
			var lo := t - 0.5
			var hi := t
			for i in 12:
				var mid := (lo + hi) * 0.5
				var m := from + dir * mid
				if m.y <= world.ground_at(m.x, -m.z):
					hi = mid
				else:
					lo = mid
			var hit := from + dir * hi
			return Vector2(hit.x, -hit.z)
	return null


## Usable lever (switch, chest) under the cursor, or -1.
func pick_lever(p: Vector2) -> int:
	var cam := rig.camera
	var best := -1
	var bd := 40.0
	for nid in world.levers:
		if not world.lever_sys.usable(nid):
			continue
		var obj = world.objects.get(nid)
		if obj == null or not is_instance_valid(obj) or not obj.visible:
			continue
		var o: Node3D = obj
		var wp := o.global_position + Vector3.UP * 0.6
		if cam.is_position_behind(wp):
			continue
		var d := cam.unproject_position(wp).distance_to(p)
		if d < bd:
			bd = d
			best = nid
	return best


## The unit under the cursor, as the original (mouse move
## ): every drawn figure keeps the screen rectangles of its parts
## (CObject3DClientSpecific::Draw: per part the integer min / max
## box of its projected vertices
## and their union at object). Pass 1 (renderer
## ) takes the figures with a part rectangle holding the
## point; only when it finds no unit, pass 2 (
## ) tests the union rectangle. The hits are sorted living units
## first (= dead), then by view depth of the unit's origin
## nearest first. No pixel margin. Parts use their actual posed vertices and
## clipped triangles; picking and floating hit numbers share those bounds.
var _pick_key := []
var _pick_hit: GameUnit


func pick_unit(p: Vector2) -> GameUnit:
	var key := [Engine.get_process_frames(), p]
	if key == _pick_key and (_pick_hit == null or is_instance_valid(_pick_hit)):
		return _pick_hit
	_pick_key = key
	_pick_hit = _pick_unit(p)
	if _pick_hit == null and TouchInput.enabled:
		# Prefer the exact hit; only use the nearest visible silhouette as a
		# fallback. A small enemy beside a hero should not steal a precise tap.
		var best := TouchInput.target_pixels() * 0.35
		for unit: GameUnit in world.visible_units():
			if unit.hidden or not unit.visible or not unit.near_screen() \
					or not unit.may_cover(rig.camera, p, best):
				continue
			var rects := unit.screen_rects(rig.camera)
			if rects.is_empty():
				continue
			var rect := Rect2(rects[0])
			var closest := p.clamp(rect.position, rect.end)
			var dist := p.distance_to(closest)
			if dist < best:
				best = dist
				_pick_hit = unit
	return _pick_hit


func _pick_unit(p: Vector2) -> GameUnit:
	var cam := rig.camera
	var to_view := cam.global_transform.affine_inverse()
	var hits: Array = []    # [dead, depth, unit]
	var loose: Array = []   # union-rectangle hits
	for u: GameUnit in world.visible_units():
		if u.hidden or not u.visible or not u.near_screen() or not u.may_cover(cam, p):
			continue
		var rects := u.screen_rects(cam)
		if rects.is_empty() or not _in_rect(rects[0], p):
			continue
		var depth := -(to_view * u.global_position).z
		var hit := false
		for i in range(1, rects.size()):
			if _in_rect(rects[i], p):
				hit = true
				break
		(hits if hit else loose).append([int(u.dead), depth, u])
	if hits.is_empty():
		hits = loose
	if hits.is_empty():
		return null
	hits.sort_custom(func(a, b): return a[0] < b[0] or a[0] == b[0] and a[1] < b[1])
	return hits[0][2]


## PtInRect: left / top inclusive, right / bottom exclusive.
static func _in_rect(r: Rect2i, p: Vector2) -> bool:
	return p.x >= r.position.x and p.y >= r.position.y and p.x < r.end.x and p.y < r.end.y


## Options: the shadow switches (brightness / contrast / gamma are the
## screen-wide ramp of GameData._apply_display).
func _apply_options() -> void:
	Gfx.apply_env(_env)
	_apply_sky()
	EIFigure.set_wind(Gfx.on("gfx_wind"))
	get_tree().set_group(&"gfx_heat_haze", "visible", Gfx.heat_haze_on())
	_fit_shadows()
	if world:
		_apply_shadows(world)
		if world.terrain:
			world.terrain.apply_gfx()


## Option q_shadow_fit (Gfx.fit_shadows) for the zone in view.
func _fit_shadows() -> void:
	if _sun:
		Gfx.fit_shadows(_sun, world.terrain.size_ei() if world and world.terrain else Vector2.ZERO)


## Options "shadow_units" (characters) and "shadow_buildings" / "shadow_flora"
## (map objects; the remake does not tell trees from buildings, so either
## switch turns on object shadows). Terrain is not affected.
func _apply_shadows(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		_shadow_for(n)


func _on_node_added(n: Node) -> void:
	if n is GeometryInstance3D and world and world.is_ancestor_of(n):
		_shadow_for.call_deferred(n)
	elif n is OmniLight3D and is_ancestor_of(n):
		# The original point light falls off as 1 − d² / r² (terrain
		# figures 3dfpfpu); Gfx.light_code inverts
		# Godot's falloff with attenuation 0.
		(n as OmniLight3D).omni_attenuation = 0.0
	if n is Light3D and not n is DirectionalLight3D and is_ancestor_of(n):
		# Units' meshes switch between layer 1 and OFFSCREEN_LAYER: every
		# local light must light both, or Godot 4.7 leaves freed lights paired
		# with them and crashes (LocalLighting._light_quality). Set here, before
		# the light's first pairing at the end of this frame.
		(n as Light3D).light_cull_mask |= 1 | GameUnit.OFFSCREEN_LAYER


func _shadow_for(obj: Variant) -> void:
	# Deferred: the node may have been freed with its zone in between.
	if not is_instance_valid(obj):
		return
	var n: GeometryInstance3D = obj
	var p: Node = n
	while p and p != world:
		if p is GameUnit:
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if GameData.option("shadow_units") \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return
		if p.has_meta("ei"):
			var on := GameData.option("shadow_buildings") or GameData.option("shadow_flora")
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return
		p = p.get_parent()


func _exit_tree() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
