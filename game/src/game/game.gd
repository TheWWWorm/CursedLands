class_name Game
extends Node3D
## Play mode: owns the current zone world, the camera, input and HUD.
## All player intents go through `issue()` so they can be sent to the host
## in multiplayer (see Session).

var session: Session
var world: GameWorld
var rig: CameraRig
var hud: GameHUD
var selected: Array[GameUnit] = []
var _drag_start := Vector2.ZERO
var _dragging := false
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
var _sky_spin := 0.0
var _lights: EILights
var _lights_zone := "?"
var cursor: GameCursor
var speed := 0   # 0 normal, 1 accelerated (clock dial)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_env()
	rig = CameraRig.new()
	add_child(rig)
	hud = GameHUD.new()
	hud.game = self
	add_child(hud)
	sound = GameSound.new()
	sound.game = self
	add_child(sound)
	add_child(FxRainSnow.new(self))   # precipitation shown by sound.weather's state
	add_child(ContactShadows.new(self))   # option gfx_contact_shadows
	cursor = GameCursor.new()
	add_child(cursor)
	marks = OrderMarks.new()
	marks.game = self
	add_child(marks)
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
	sun.shadow_enabled = true
	sun.shadow_caster_mask = 0xFFFFFFFF & ~GameUnit.OFFSCREEN_LAYER   # out-of-view figures
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.5
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)


func _process(dt: float) -> void:
	if world == null:
		return
	if not session.is_host:
		session.state.world_time = fmod(session.state.world_time + dt / 60.0, 24.0)   # same pace as the host VM
	_update_daylight()
	_keep_selection()
	_update_cursor()


## The selection never stays empty: units that died or left the player's
## control drop out, and when none is left the player's main hero (Zak in
## single player) is selected again, so the unit panel and orders always have
## a unit. **Approx.** (user report): the original can empty the list
## (toggle) and then shows no unit in the panel.
func _keep_selection() -> void:
	var keep := selected.filter(func(s): return is_instance_valid(s) and not s.dead \
			and s.controller == session.my_index)
	if keep.size() != selected.size():
		selected.assign(keep)
	if selected.is_empty():
		var mine := my_units()
		for u in mine:
			if u.has_meta("hero"):
				selected = [u]
				return
		if not mine.is_empty():
			selected = [mine[0]]


## Clock dial sectors: 0 pause on/off, 1 normal speed, 2
## accelerated speed. The original's logic tick is 55 ms normally and 27 ms
## accelerated; speed and pause only in single player.
func set_speed(sector: int) -> void:
	if session.online:
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


## Cursor by what is under the mouse (the original cursor set, GameCursor).
func _update_cursor() -> void:
	var vp := get_viewport()
	if hud.blocks_input() or vp.gui_get_hovered_control() != null:
		cursor.set_kind("cursor_default")
		return
	if Input.get_mouse_button_mask() & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
		cursor.set_kind("cursor_camera")
		return
	if rig.edge != Vector2i.ZERO:
		cursor.set_kind(GameCursor.SCROLL[rig.edge])
		return
	var p := vp.get_mouse_position()
	if pending_spell.begins_with(AIM):
		cursor.set_kind(GameCursor.AIM[clampi(int(pending_spell.substr(AIM.length())), 0, 5)])
		return
	var u := pick_unit(p)
	if pending_spell == FOLLOW:
		cursor.set_kind("cursor_default" if u and not u.dead else "cursor_spellcancel")
		return
	if pending_spell == SCIENCE:
		cursor.set_kind("cursor_steal" if u and not u.dead else "cursor_use" if pick_lever(p) >= 0 else "cursor_spellcancel")
		return
	if pending_spell:
		cursor.set_kind("cursor_spell")
		return
	#  sets cursor 0 (default) first; (normal mode
	#  == 0) then needs a selected unit and picks: a dead unit → 4 (use)
	# a living one → 1 (attack) when hostile, else stays 0; no
	# unit: an object that can be used (vfunc) with exactly one unit
	# selected → 4; else a zone exit under the point (target not
	# "none", the area Session._exit_at tests) whose GS var "z.<target>" is
	# not 1 → 15 (move); plain ground stays 0.
	var k := "cursor_default"
	var me: GameUnit = selected[0] if not selected.is_empty() and is_instance_valid(selected[0]) else null
	if u and u.controller == session.my_index:
		# Village hover: the talk cursor (0xe) over a unit with topics.
		k = "cursor_talk" if not u.dead and session.shop_available() \
			and not Briefings.pending_for(session.state, u, session.my_index).is_empty() else "cursor_default"
	elif u and u.dead:
		k = "cursor_use" if me else "cursor_default"
	elif u and me:
		k = "cursor_attack" if world.is_enemy(me, u) else "cursor_default"
	elif me and selected.size() == 1 and pick_lever(p) >= 0:
		k = "cursor_use"
	elif me and _over_open_exit(p):
		k = "cursor_move"
	cursor.set_kind(k)


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
	return session.state.get_var(0, "z." + to.to_lower()) != 1.0


## Day / night from the campaign clock (world_time, hours), as the daylight
## update: sun, ambient and sky (fog) colours from the allod's
## config/Lights[Cave]<Allod>.ini interpolated per hour, the sun direction, the
## fog start; the far plane is FarClipDistance (Gfx).
func _update_daylight() -> void:
	var zid := String(world.zone.get("id", ""))
	if zid != _lights_zone:
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
	_sun.basis = Basis.looking_at(gd, Vector3.FORWARD if absf(gd.y) > 0.99 else Vector3.UP)
	if not get_tree().paused:
		_sky_spin += get_process_delta_time() * EISky.SPIN_PER_SECOND
	if not _sky_cave:
		EISky.set_spin(_sky_shader, _sky_spin)
	if rig and rig.camera:
		rig.camera.near = minf(rig.camera.near, Gfx.NEAR_CLIP)
		rig.camera.far = Gfx.far_clip()
	_update_hero_lights()
	if _lights == null:
		return
	Gfx.update_original(_env, _sun, _lights, hour, _sky_cave)
	var sky := _env.fog_light_color
	_sky_mat.sky_top_color = sky
	_sky_mat.sky_horizon_color = sky
	_sky_mat.ground_horizon_color = sky
	_sky_mat.ground_bottom_color = sky
	if _sky_shader:
		EISky.update(_sky_shader, _lights, hour, _sky_cave, Gfx.on("gfx_sky"))
		Gfx.update_volumetric(_env, _sun.light_color, _sky_cave)
		_env.volumetric_fog_albedo = sky.lerp(Color.WHITE, 0.5)


## Hero light: every unit a player controls carries a point light (the original
## figure =, switched by the unit's player
## setter): registry Hero Light R/G/B 255 / 236
## 170 and radius 10 m (defaults), 2 m above the unit
## (flags 0x580 — it lights the ground through the max of the
## diffuse colour, not additively). It is on day and night; under the white
## noon sun the max() hides it. **Approx.**: removed when the unit dies.
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
	for u: GameUnit in world.units.values():
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
		world.queue_free()
	world = w
	w.process_mode = Node.PROCESS_MODE_PAUSABLE   # the Game node itself runs while paused
	if w.get_parent() == null:
		add_child(w)
	rig.terrain = w.terrain
	selected.clear()
	var mine := my_units()
	if not mine.is_empty():
		selected = [mine[0]]
		rig.focus(mine[0].position)
	hud.on_world(w)
	_apply_shadows(w)
	ParticleFx.of(w).setup_zone()   # zone exit stars and torch fires (every peer)
	GroundMarks.of(w)   # footprints and blood marks (every peer)


func my_units() -> Array[GameUnit]:
	var out: Array[GameUnit] = []
	if world:
		for u: GameUnit in world.units.values():
			if u.controller == session.my_index and not u.dead:
				out.append(u)
	return out


# ------------------------------------------------------------------ input

## pending_spell value while choosing a Use/Steal target (keyboard.ini "use_science").
const SCIENCE := "@science"
## pending_spell value while choosing whom the selection follows (HUD Follow).
const FOLLOW := "@follow"
## pending_spell prefix while choosing the target of an aimed strike (keyboard.ini
## cs_* keys); the suffix is the body part index.
const AIM := "@aim:"
const AIM_KEYS := {"cs_head": 0, "cs_body": 1, "cs_rhand": 2, "cs_lhand": 3, "cs_rleg": 4, "cs_lleg": 5}


func _unhandled_input(e: InputEvent) -> void:
	if world == null or hud.blocks_input():
		return
	if e is InputEventMouseButton and e.pressed and not pending_spell.is_empty():
		if e.button_index == MOUSE_BUTTON_LEFT:
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
		elif _dragging:
			_dragging = false
			# Option "rubber_select" (CameraFrameSelectionSensetiveArea = slider
			# × 10 px): starts the frame once the
			# pointer is more than that many pixels away on either axis; 0 turns
			# frame selection off.
			var area := GameData.option("rubber_select") * 10
			var d: Vector2 = (e.position - _drag_start).abs()
			if area >= 1 and (d.x > area or d.y > area):
				_box_select(Rect2(_drag_start, e.position - _drag_start).abs(), e.shift_pressed)
			else:
				_click(e.position, e.shift_pressed)
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.pressed and not e.echo:
		if rig.claims_key(e):   # remake option cam_wasd: W / A / S / D pan the modern camera
			return
		var act := EIKeymap.action(e.keycode)   # original bindings, config/keyboard.ini
		if get_tree().paused and not act in ["pause", "quickload"] and e.keycode != KEY_ESCAPE:
			return
		if act:
			_key_action(act)
			return
		match e.keycode:   # remake-only windows on keys the original leaves free
			KEY_ENTER, KEY_KP_ENTER:   # co-op chat (NetStatus; Enter is unbound in keyboard.ini)
				if session.online:
					hud.chat_line.open()
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
	if act.begins_with("spell"):
		begin_cast(int(act.substr(5)) - 1)
		return
	if act.begins_with("select") and act != "select_all":
		var mine := my_units()
		var i := int(act.substr(6)) - 1
		if i < mine.size():
			selected = [mine[i]]
		return
	match act:
		"select_all":
			selected = my_units()
		"run", "walk", "sneak", "crawl":
			hud.set_move_mode(act)
		"swarm":   # keyboard.ini "A swarm": the original key action 0x1c
			hud.toggle_aggression()
		"pause":
			set_speed(0)
		"quicksave":
			session.save_game("quick")
		"quickload":
			if session.is_host and not session.load_game("quick"):
				hud.log_msg("No quick save.")
		"follow":   # HUD Follow: the next click picks the unit to follow
			if not selected.is_empty():
				pending_spell = FOLLOW
				hud.set_targeting(GameData.text("tip 10510").strip_edges())
		"use_science":   # Use/Steal: the next click picks the target
			if not selected.is_empty() and selected[0].has_meta("hero"):
				pending_spell = SCIENCE
				hud.set_targeting(Skills.title("science"))
		"cs_head", "cs_body", "cs_rhand", "cs_lhand", "cs_rleg", "cs_lleg":
			if not selected.is_empty():
				pending_spell = AIM + str(AIM_KEYS[act])
				hud.set_targeting("Aimed strike: " + ["head", "body", "right arm", "left arm", "right leg", "left leg"][AIM_KEYS[act]])
		"obj":
			open_quests()
		"tutorial_script":
			hud._tutorial.show_last()
		"w_text1", "w_text2":   # keyboard.ini L / K: key actions 50 / 51 -> (0 / 1)
			hud.text_window.key_mode(0 if act == "w_text1" else 1)
		"camera_norm":   # key N: case 0xc, same as the minimap's N button
			hud.minimap.north()
		"camera_track":   # HOME (the modern camera glides there and follows again)
			if not selected.is_empty():
				rig.center_on(selected[0].position)


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
	var u := pick_unit(p)
	# The village screen (the original mode 0): a left click
	# on any living unit — no side check, so own party members and hired
	# mercenaries too — opens its topic list when it has pending
	# conversations; that is how a merc is dismissed (b.mercN.n2_N, offered in
	# its home village) or says farewell (n10_N). The talker is
	# the rest of the selection, else another own hero. **Approx.**: the
	# original village has no unit selection, so a party unit without topics
	# is selected here as in the field.
	if u and u.controller == session.my_index and not add and not u.dead and session.shop_available() \
			and not Briefings.pending_for(session.state, u, session.my_index).is_empty():
		var talkers := selected.filter(func(s: GameUnit): return s != u)
		if talkers.is_empty():
			talkers = my_units().filter(func(s: GameUnit): return s != u and s.has_meta("hero"))
		if not talkers.is_empty():
			issue({"t": "interact", "units": talkers.map(func(s: GameUnit): return s.uid), "target": u.uid})
			return
	if u and u.controller == session.my_index:
		if add:
			# Toggle (with the modifier); the remake keeps the
			# last unit selected, see _keep_selection.
			if u in selected:
				if selected.size() > 1:
					selected.erase(u)
			else:
				selected.append(u)
		else:
			selected = [u]
			sound.ui("buttons\\battle\\on_off.wav")
			GameSound.ack(u, EIAcks.SELECTED)
		return
	if selected.is_empty():
		return
	var ids := selected.map(func(s: GameUnit): return s.uid)
	if u and u.dead and Session.lootable(u):
		issue({"t": "loot", "units": ids, "target": u.uid})
		marks.unit_ordered(u, false, Session.LOOT_REACH, marks.first_mine())
		return
	if u and not u.dead and world.is_enemy(selected[0], u):
		issue({"t": "attack", "units": ids, "target": u.uid})
		marks.unit_ordered(u, true, -1.0, selected)
		return
	if u and not u.dead:
		issue({"t": "interact", "units": ids, "target": u.uid})
		marks.unit_ordered(u, false, Session.TALK_REACH, marks.first_mine())
		return
	var lv := pick_lever(p)
	if lv >= 0:
		issue({"t": "use_lever", "units": ids, "target": lv})
		return
	var g = pick_ground(p)
	if g != null:
		issue({"t": "move", "units": ids, "x": g.x, "y": g.y, "run": _double})
		marks.move_ordered(g)


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
	if i < 0 or i >= spells.size():
		return
	pending_spell = spells[i]
	hud.set_targeting(Spells.title(pending_spell))


func _cast_at(p: Vector2) -> void:
	if selected.is_empty():
		return
	var caster: GameUnit = selected[0]
	var u := pick_unit(p)
	if pending_spell.begins_with(AIM):
		if u and not u.dead and world.is_enemy(caster, u):
			issue({"t": "attack", "units": selected.map(func(s: GameUnit): return s.uid), "target": u.uid,
				"aim": int(pending_spell.substr(AIM.length()))})
		return
	if pending_spell.begins_with(BELT):
		var cmd := {"t": "use", "unit": int(pending_spell.get_slice(":", 1)), "item": pending_spell.split(":", true, 2)[2]}
		if u and not u.dead:
			cmd.target = u.uid
		else:
			var g = pick_ground(p)
			if g == null:
				return
			cmd.x = g.x
			cmd.y = g.y
		issue(cmd)
		return
	if pending_spell == FOLLOW:
		if u and not u.dead:
			issue({"t": "follow", "units": selected.map(func(s: GameUnit): return s.uid), "target": u.uid})
		return
	if pending_spell == SCIENCE:
		if u and not u.dead and u.controller != session.my_index:
			issue({"t": "steal", "unit": caster.uid, "target": u.uid})
		else:
			var lv := pick_lever(p)
			if lv >= 0:
				issue({"t": "use_lever", "units": [caster.uid], "target": lv})
		return
	var cmd := {"t": "cast", "unit": caster.uid, "spell": pending_spell}
	if u and not u.dead:
		cmd.target = u.uid
	else:
		var g = pick_ground(p)
		if g == null:
			return
		cmd.x = g.x
		cmd.y = g.y
	issue(cmd)
	marks.cast_ordered(caster, String(pending_spell), u if u and not u.dead else null,
		Vector2(float(cmd.get("x", 0.0)), float(cmd.get("y", 0.0))))


## UI-level events from the host (see Session.broadcast).
func on_event(e: Dictionary) -> void:
	sound.on_event(e)   # sounds of broadcast events (GameSound)
	match String(e.get("t", "")):
		"vision_fog":
			var tu: GameUnit = world.units.get(int(e.get("uid", -1))) if world else null
			if tu and int(e.get("to", -1)) == session.my_index:
				VisionFog.open(world, tu, float(e.get("secs", 10.0)), session.my_index)
		"music":
			sound.force_music(String(e.get("name", "")))
		"ack":
			var who: GameUnit = world.units.get(int(e.get("uid", -1))) if world else null
			if who == null:
				pass
			elif e.has("near"):
				if my_units().any(func(m: GameUnit): return not m.dead and m.pos.distance_to(who.pos) <= float(e.near)):
					GameSound.ack(who, int(e.get("code", -1)))
			elif int(e.get("to", -1)) == session.my_index:
				GameSound.ack(who, int(e.get("code", -1)))
	hud.on_event(e)


## Order acknowledgements (acks.db), spoken by the first unit given the order.
const ORDER_ACKS := {"move": EIAcks.MOVE, "attack": EIAcks.ATTACK, "cast": EIAcks.CAST, "loot": EIAcks.LOOT,
	"interact": EIAcks.USE_OBJECT, "use_lever": EIAcks.USE_OBJECT, "steal": EIAcks.STEAL, "use": EIAcks.USE_POTION}

func issue(cmd: Dictionary) -> void:
	session.submit(cmd)
	var t := String(cmd.get("t", ""))
	if ORDER_ACKS.has(t) and world:
		var uid := int(cmd.get("unit", cmd.get("units", [-1])[0] if not cmd.get("units", []).is_empty() else -1))
		GameSound.ack(world.units.get(uid), ORDER_ACKS[t])


## Screen point -> EI ground xy (or null).
func pick_ground(p: Vector2) -> Variant:
	var cam := rig.camera
	var from := cam.project_ray_origin(p)
	var dir := cam.project_ray_normal(p)
	var t := 0.0
	var prev := from
	while t < 600.0:
		t += 0.5
		var q := from + dir * t
		var ex := q.x
		var ey := -q.z
		if q.y <= world.ground_at(ex, ey):
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
		prev = q
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
## nearest first. No pixel margin. **Approx.**: a part's rectangle is its
## mesh box's projected corners, not every vertex.
var _pick_key := []
var _pick_hit: GameUnit


func pick_unit(p: Vector2) -> GameUnit:
	var key := [Engine.get_process_frames(), p]
	if key == _pick_key and (_pick_hit == null or is_instance_valid(_pick_hit)):
		return _pick_hit
	_pick_key = key
	_pick_hit = _pick_unit(p)
	return _pick_hit


func _pick_unit(p: Vector2) -> GameUnit:
	var cam := rig.camera
	var to_view := cam.global_transform.affine_inverse()
	var hits: Array = []    # [dead, depth, unit]
	var loose: Array = []   # union-rectangle hits
	for u: GameUnit in world.units.values():
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
	get_tree().set_group(&"gfx_heat_haze", "visible", Gfx.on("gfx_heat_haze"))
	if world:
		_apply_shadows(world)
		if world.terrain:
			world.terrain.apply_gfx()


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
