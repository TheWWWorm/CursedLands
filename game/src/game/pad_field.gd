class_name PadField
extends Node
## The gamepad in the field (docs/gamepad_design.md §3–§6), a child of Game.
## Every order goes through Game's own order code (order_on, forced_on,
## cast_on, issue, or Session.submit for the stick's repeated moves), so co-op
## stays host-authoritative and the mouse and keyboard rules are unchanged.
## Modes: DIRECT (the left stick walks the leader, the others Follow it; a
## soft target is highlighted for A), CURSOR (R3: the left stick moves PadUI's
## pointer and A / B are mouse clicks), TARGETING (a spell / belt item /
## Use-Steal / Follow waits for its target: the highlight keeps to fit
## targets, the stick moves a ground reticle) and WHEEL (an open PadWheel,
## the L3 movement-mode ring among them).

const MOVE_AHEAD := 3.0
const REISSUE_SEC := 0.2
const REISSUE_ANGLE := deg_to_rad(20.0)
const RETICLE_SPEED := 9.0
## The ring's aimed strikes laid out like the numpad and the original cursors
## (the target faces the viewer: its right arm is on the screen's left):
## AIM_ORDER index → degrees clockwise from up.
const AIM_ANGLES := {0: 0.0, 2: 90.0, 4: 135.0, 1: 180.0, 5: 225.0, 3: 270.0}
const AIM_ACTIONS := ["cs_head", "cs_body", "cs_lhand", "cs_rhand", "cs_lleg", "cs_rleg"]

var game: Game
var wheel: PadWheel
var prompts: PadPrompts
var labels: WorldLabels
var cursor_mode := false
## L3 held (the gait button's hold): world information labels on the
## units, bodies, levers and exits around the party (WorldLabels).
var world_info := false
## The soft target: {} none, else {unit: GameUnit} or {lever: nid, at: Vector2 (EI)}.
var target := {}
var reticle: Variant = null   # EI ground point while a pending spell aims at the ground
var last_aim := 0             # the ring's last aimed part (AIM_ORDER index)
var _wheel_kind := ""         # "", "actions", "items", "system", "ring", "gait"
var _wheel_button := ""       # the action that opened it (release with a flick confirms)
var _flicked := false
var _wheel_paused: Variant = null
var _ring_target := {}
var _ring_ground: Variant = null
var _page := {"actions": 0, "items": 0, "system": 0}
var _moving := false
var _move_dir := Vector2.ZERO
var _move_t := 0.0
var _goal := Vector2.INF
var _side := 1.0   # the side (+1 left, -1 right) of the last turned stick goal
var _target_t := 0.0
var _manual_until := 0
var _last_hp := -1.0
var _last_dead := {}
var _last_shakes := 0
var _last_level := -1
var _log_mode := 0
var _in_wheel := {}   # actions whose current press began in an open wheel
var _ls_wait := false  # a wheel closed with the left stick tilted: no walking until it is let go

const LB_PAGES := ["spells", "actions"]
const RB_PAGES := ["belt", "weapons"]
## The RT wheel's pages, turned with LB / RB: the game's screens and the
## camera views 1–4 (keyboard.ini camera1–4, F9–F12).
const RT_PAGES := ["game", "camera"]
## Camera views in the camera page: view i at degrees clockwise from up;
## the centring on the leader between views 1 and 2.
const VIEW_ANGLES := [0.0, 90.0, 180.0, 270.0]
const CENTRE_ANGLE := 45.0
## The movement-mode ring (L3): [keyboard.ini action, gait (unit)]
## clockwise from up.
const GAIT_RING := [["run", 3], ["walk", 2], ["sneak", 1], ["crawl", 0]]


func _init(g: Game = null) -> void:
	game = g


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "PadField"
	PadInput.field = self
	PadInput.action.connect(_on_action)
	PadInput.connection_changed.connect(_on_connection)
	PadInput.mode_changed.connect(_on_mode)
	prompts = PadPrompts.new()
	prompts.field = self
	game.hud._add_ui(prompts)
	wheel = PadWheel.new()
	game.hud._add_ui(wheel)
	# Below the HUD, as the co-op name tags (PlayerNames).
	var layer := CanvasLayer.new()
	layer.name = "WorldLabelsLayer"
	layer.layer = -1
	labels = WorldLabels.new()
	labels.field = self
	layer.add_child(labels)
	game.add_child(layer)


func _exit_tree() -> void:
	if PadInput.field == self:
		PadInput.field = null


## The field takes the pad: a zone is up, no screen or panel is over it.
func takes_input() -> bool:
	if game == null or game.world == null or game.hud == null or not PadInput.enabled():
		return false
	if game.session == null or game.session.world == null:
		return false
	if game.hud.blocks_camera():
		return false
	var focus := get_viewport().gui_get_focus_owner()
	return not (focus is LineEdit or focus is TextEdit)


func overlay_visible() -> bool:
	return PadInput.active == "pad" and takes_input() and not wheel.visible


func leader() -> GameUnit:
	if game.selected.is_empty() or not is_instance_valid(game.selected[0]) or game.selected[0].dead:
		return null
	return game.selected[0]


func _on_mode() -> void:
	if PadInput.active != "pad":
		_stop_moving()
		_set_cursor_mode(false)
		world_info = false
		game.hud.unit_panel.ignore_hover = false
		game.hud.unit_panel.examine = null
		game.rig.pad_no_edge = false


# ------------------------------------------------------------------ frame

func _process(dt: float) -> void:
	var real := minf(dt / maxf(Engine.time_scale, 0.001), 0.1)
	game.rig.pad_turn = 0.0
	game.rig.pad_zoom = 0.0
	var pad := PadInput.active == "pad"
	game.rig.pad_no_edge = pad and not cursor_mode
	game.hud.unit_panel.ignore_hover = pad and not cursor_mode
	if world_info and not PadInput.held("gait"):
		world_info = false   # the release went to a menu, or the pad was unplugged
	if not pad and game.direct and game.direct.active(): return
	if not takes_input():
		if _wheel_kind != "":
			close_wheel()
		_stop_moving()
		return
	if not pad: return
	_rumble_poll()
	_light_poll()
	var ls := PadInput.stick(true)
	var rs := PadInput.stick(false)
	if _wheel_kind != "":
		if wheel.flick(ls if ls.length() >= rs.length() else rs):
			_flicked = true
		return
	if _ls_wait:
		if ls == Vector2.ZERO:
			_ls_wait = false
		ls = Vector2.ZERO
	if game.direct and game.direct.active() and not cursor_mode:
		game.direct.pad_step(ls,rs,real)
		target = {}
		return
	var sx := -1.0 if GameData.option("camera_reverse_x") else 1.0
	game.rig.pad_turn = rs.x * sx
	game.rig.pad_zoom = rs.y
	if cursor_mode:
		PadInput.ui.move_pointer(ls, real, 0.45 if _over_something() else 1.0)
		PadInput.ui.move_gyro(real)
		return
	if game.pending_spell != "" and ls != Vector2.ZERO:
		_move_reticle(ls, real)
	else:
		_direct_move(ls, real)
	_target_t -= real
	if _target_t <= 0.0:
		_target_t = 0.12
		_update_target(ls)


## Magnetism: the pointer slows over a unit or a HUD widget.
func _over_something() -> bool:
	var p: Vector2 = PadInput.ui.pointer
	return p.x >= 0.0 and (get_viewport().gui_get_hovered_control() != null or game.pick_unit(p) != null)


# ------------------------------------------------------------------ moving

## The stick on the ground plane by the camera's heading, EI xy.
func _ground_dir(v: Vector2) -> Vector2:
	if game.direct and game.direct.active(): return game.direct.ground_direction(v)
	var d3 := game.rig._screen_to_ground(v)
	return Vector2(d3.x, -d3.z).normalized()


func _direct_move(v: Vector2, real: float) -> void:
	var u := leader()
	if u == null or v == Vector2.ZERO:
		_stop_moving()
		return
	var d := _ground_dir(v)
	_move_t -= real
	var start := not _moving
	if start:
		_moving = true
		reticle = null
		# BG3's chained party: the rest of the selection follows the leader
		# (EI's own Follow order, cancelled by any other order to them).
		var others := game.selected.filter(func(s): return is_instance_valid(s) and s != u and not s.dead)
		if not others.is_empty():
			game.issue({"t": "follow", "units": others.map(func(s: GameUnit): return s.uid), "target": u.uid})
		if game.rig.modern() and game.rig._free and GameData.option("cam_follow") == 1:
			game.rig.center_on(u.position)
	var turned := _move_dir != Vector2.ZERO and absf(_move_dir.angle_to(d)) > REISSUE_ANGLE
	var near := _goal != Vector2.INF and u.pos.distance_to(_goal) < 1.6
	if start or turned or near or _move_t <= 0.0:
		_move_t = REISSUE_SEC
		_move_dir = d
		_goal = _walk_goal(u, d)
		# The tilt only steers: the unit goes at its own movement mode
		# (run / walk / sneak / crawl, the HUD dial and the L3 ring), as
		# a single click's move order does.
		_submit_move(u, _goal, true)


## The stick's goal MOVE_AHEAD along `d`: the first point the leader can
## walk to in a straight line (NavGrid.direct_line, the way the order then
## walks it), nearer or turned ±25° / ±50° when the ground ahead is shut
## (a wall to slide along), else the first walkable one for the path search.
## The turned points are tried on the side last taken first, so the goal
## does not flip from one side of an obstacle to the other each re-issue.
func _walk_goal(u: GameUnit, d: Vector2) -> Vector2:
	var nav: NavGrid = game.world.nav
	if nav == null:
		return u.pos + d * MOVE_AHEAD
	var turns := [0.0, 25.0 * _side, -25.0 * _side, 50.0 * _side, -50.0 * _side]
	for direct in [true, false]:
		for l in [MOVE_AHEAD, 2.0, 1.2]:
			for a: float in turns:
				var p := u.pos + d.rotated(deg_to_rad(a)) * float(l)
				var ok := nav.direct_line(u, p) if direct else nav.is_walkable(p)
				if ok:
					if a != 0.0:
						_side = signf(a)
					return p
	return u.pos + d * MOVE_AHEAD


## The stick's moves go straight to Session.submit (Game.issue's path without
## its spoken acknowledgement and order marks, five times a second). `line`:
## the unit walks the straight line to `to` when it can (the host checks it,
## GameUnit._do_move), not the search's path of cell centres; a host without
## the field searches as before.
func _submit_move(u: GameUnit, to: Vector2, line := false) -> void:
	if GameSound.blocked(u):
		return
	var cmd := {"t": "move", "units": [u.uid], "x": to.x, "y": to.y, "run": false}
	if game.direct and game.direct.active() and PadInput.active != "pad":
		cmd.run = Input.is_physical_key_pressed(KEY_SHIFT)
	if line:
		cmd.line = true
	game.session.submit(cmd)


func _stop_moving() -> void:
	if not _moving:
		return
	_moving = false
	_move_dir = Vector2.ZERO
	_goal = Vector2.INF
	var u := leader()
	if u and game.world:
		_submit_move(u, u.pos)


func _move_reticle(v: Vector2, real: float) -> void:
	_stop_moving()
	var u := leader()
	if reticle == null:
		var t := _target_pos()
		reticle = t if t != Vector2.INF else (u.pos + _ground_dir(Vector2(0, -1)) * 4.0 if u else Vector2.ZERO)
	var d := _ground_dir(v)
	reticle = (reticle as Vector2) + d * v.length() * RETICLE_SPEED * real
	if u and (reticle as Vector2).distance_to(u.pos) > 30.0:
		reticle = u.pos + ((reticle as Vector2) - u.pos).limit_length(30.0)
	target = {}


# ------------------------------------------------------------------ target

func _target_pos() -> Vector2:
	if target.has("unit") and is_instance_valid(target.unit):
		return (target.unit as GameUnit).pos
	if target.has("lever"):
		return target.at
	return Vector2.INF


func target_unit() -> GameUnit:
	return target.unit if target.has("unit") and is_instance_valid(target.unit) else null


func _radius() -> float:
	return 4.0 + GameData.option("pad_target_radius")


## What the soft target may be now: [{unit} / {lever, at}, score…].
func _candidates(stick: Vector2) -> Array:
	var u := leader()
	var out: Array = []
	if u == null:
		return out
	# The village screen (no fights): every unit to talk to is a candidate,
	# own party members too when they have topics (a mercenary's dismissal,
	# Game.order_on's village rule).
	var village := game.session.shop_available()
	var r := _radius() if not village else VILLAGE_RADIUS
	var me := game.session.my_index
	var pend := game.pending_spell
	var offensive := false
	var friendly := false
	if pend != "" and pend != Game.SCIENCE and pend != Game.FOLLOW:
		var sp := pend
		if pend.begins_with(Game.BELT):
			var item := pend.split(":", true, 2)[2]
			sp = Items.potion_spell(item)
			if sp.is_empty():
				sp = Items.spell_of(item)
		offensive = sp != "" and Spells.offensive(sp)
		friendly = not offensive
	var dir := _ground_dir(stick) if stick != Vector2.ZERO else Vector2.ZERO
	var conn := conn_id(self, game.session.online)
	var any_enemy := false
	if friendly and pend != Game.FOLLOW:
		# A heal or a potion may go to the leader itself (BG3 lets the
		# character target itself); others in need come first by distance.
		out.append({"unit": u, "score": 1.5})
	for o: GameUnit in game.world.visible_units():
		if o == u or o.hidden or not o.visible or o.fogged:
			continue
		var dist := o.pos.distance_to(u.pos)
		if dist > r:
			continue
		var score := dist
		var enemy := not o.dead and game.world.is_enemy(u, o)
		# Teammates are targets only when explicitly healing / using an item
		# or choosing Follow. Pointer mode still permits deliberate targeting.
		if not o.dead and o.controller >= 0 and o.controller != me and not (friendly or pend == Game.FOLLOW):
			continue
		if o.dead:
			if pend != "" or not (Session.lootable(o, me, conn) or game.revive_target(o) != null):
				continue
			score += 1.5
		elif o.controller == me:
			if village and pend == "" and _has_topics(o):
				score -= 1.0
			elif pend == Game.SCIENCE or (pend == "" or (offensive and pend != Game.FOLLOW)):
				continue   # own living party members are reached with D-pad ↑ / the ring
			if o in game.selected and pend == Game.FOLLOW:
				continue
			if friendly:
				score -= 2.0
		elif enemy:
			any_enemy = true
			score -= 3.0 if not friendly else -2.0
		elif village and pend == "" and _has_topics(o):
			score -= 3.0
		if dir != Vector2.ZERO:
			score += (1.0 - dir.dot((o.pos - u.pos).normalized())) * 4.0
		out.append({"unit": o, "score": score})
	if pend == "" or pend == Game.SCIENCE:
		for nid in game.world.levers:
			if not game.world.lever_sys.usable(nid):
				continue
			var obj = game.world.objects.get(nid)
			if obj == null or not is_instance_valid(obj) or not obj.visible:
				continue
			var at := Vector2((obj as Node3D).global_position.x, -(obj as Node3D).global_position.z)
			var dist := at.distance_to(u.pos)
			if dist > r:
				continue
			var score := dist + 0.5 + (2.0 if any_enemy else 0.0)
			if dir != Vector2.ZERO:
				score += (1.0 - dir.dot((at - u.pos).normalized())) * 4.0
			out.append({"lever": nid, "at": at, "score": score})
	return out


const VILLAGE_RADIUS := 80.0


func _has_topics(u: GameUnit) -> bool:
	return not Briefings.pending_for(game.session.state, u, game.session.my_index).is_empty()


func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.has("unit") and b.has("unit"):
		return a.unit == b.unit
	if a.has("lever") and b.has("lever"):
		return int(a.lever) == int(b.lever)
	return false


func _update_target(stick: Vector2) -> void:
	var list := _candidates(stick)
	var cur: Dictionary = {}
	var best: Dictionary = {}
	for c: Dictionary in list:
		if _same(c, target):
			cur = c
		if best.is_empty() or float(c.score) < float(best.score):
			best = c
	if not cur.is_empty() and (Time.get_ticks_msec() < _manual_until or float(cur.score) <= float(best.score) + 2.0):
		target = cur
		return
	target = best
	if is_instance_valid(game.hud.unit_panel.examine) and target_unit() != game.hud.unit_panel.examine:
		game.hud.unit_panel.examine = null


## D-pad ← / →: the next candidate by screen x.
func cycle_target(step: int) -> void:
	var list := _candidates(Vector2.ZERO)
	if list.is_empty():
		return
	var cam := game.rig.camera
	list.sort_custom(func(a, b): return _screen_x(a, cam) < _screen_x(b, cam))
	var i := -1
	for j in list.size():
		if _same(list[j], target):
			i = j
	i = posmod(i + step, list.size()) if i >= 0 else (0 if step > 0 else list.size() - 1)
	target = list[i]
	reticle = null
	_manual_until = Time.get_ticks_msec() + 4000
	if GameSound.instance:
		GameSound.instance.ui("buttons\\battle\\on_off.wav")


func _screen_x(c: Dictionary, cam: Camera3D) -> float:
	var at: Vector2 = (c.unit as GameUnit).pos if c.has("unit") else c.at
	return cam.unproject_position(EISpace.pos(at.x, at.y, game.world.ground_at(at.x, at.y))).x


## What A does to the target: the original cursor's name and a prompt text.
func _verb(t: Dictionary) -> Array:
	var pend := game.pending_spell
	var u: GameUnit = target_unit() if t == target else (t.unit if t.has("unit") else null)
	if pend == Game.FOLLOW:
		return ["cursor_move", RemakeText.t("Follow")]
	if pend == Game.SCIENCE:
		return ["cursor_steal" if u else "cursor_use", Skills.title("science")]
	if pend != "":
		return ["cursor_spell", RemakeText.t("Cast")]
	if t.has("lever"):
		return ["cursor_use", RemakeText.t("Use")]
	if u == null:
		return ["", ""]
	if u.dead:
		if game.revive_target(u) != null:
			return ["cursor_use", RemakeText.t("Revive")]
		return ["cursor_use", RemakeText.t("Loot")]
	var me := leader()
	if me and game.world.is_enemy(me, u):
		return ["cursor_attack", RemakeText.t("Attack")]
	return ["cursor_talk", RemakeText.t("Talk")]


## PadPrompts' marker: screen points of the target's feet and head.
func marker() -> Dictionary:
	if target.is_empty() or game.rig.camera == null:
		return {}
	var cam := game.rig.camera
	var feet3: Vector3
	var head3: Vector3
	var name := ""
	if target.has("unit"):
		var u := target_unit()
		if u == null:
			return {}
		feet3 = u.global_position
		# The measured head top (EnemyBars.head_top), so a boar's mark is not
		# drawn a man's height over it.
		head3 = u.global_position + Vector3.UP * (0.6 if u.dead or u.model == null else EnemyBars.head_top(u))
		name = u.display_name
	else:
		var obj = game.world.objects.get(int(target.lever))
		if obj == null or not is_instance_valid(obj):
			return {}
		feet3 = (obj as Node3D).global_position
		head3 = feet3 + Vector3.UP * 1.4
	if cam.is_position_behind(feet3):
		return {}
	var v := _verb(target)
	return {"feet": cam.unproject_position(feet3), "head": cam.unproject_position(head3), "unit": target.has("unit"), "cursor": v[0], "name": name,
		"color": Color8(255, 120, 90) if v[0] == "cursor_attack" else PadWheel.BRONZE_HI}


func reticle_screen() -> Variant:
	if reticle == null or game.rig.camera == null:
		return null
	var r: Vector2 = reticle
	var p := EISpace.pos(r.x, r.y, game.world.ground_at(r.x, r.y))
	return null if game.rig.camera.is_position_behind(p) else game.rig.camera.unproject_position(p)


## The prompt strip: [[button, text, enabled], …].
func hints() -> Array:
	var out: Array = []
	var A := PadInput.button_of("interact")
	var B := PadInput.button_of("cancel")
	var X := PadInput.button_of("context")
	if cursor_mode:
		out.append([A, RemakeText.t("Click")])
		out.append([B, RemakeText.t("Right click")])
		out.append([PadInput.button_of("cursor"), RemakeText.t("Leave pointer")])
		return out
	if game.direct and game.direct.active():
		return [[PadInput.button_of("system"),RemakeText.t("Attack / cast"),game.session.command_allowed({"t":"direct_attack"})], [A,RemakeText.t("Interact")],
			["RS",RemakeText.t("Look")], [PadInput.button_of("actions"),RemakeText.t("Spells")],
			[PadInput.button_of("items"),RemakeText.t("Items")], [PadInput.button_of("cursor"),RemakeText.t("Pointer")]]
	if game.pending_spell != "":
		out.append([A, _verb(target)[1] if not target.is_empty() or reticle != null else RemakeText.t("Cast"), not target.is_empty() or reticle != null])
		out.append(["DPAD_LR", RemakeText.t("Target")])
		out.append(["LS", RemakeText.t("Aim at the ground")])
		out.append([B, RemakeText.t("Cancel")])
		return out
	if not target.is_empty():
		out.append([A, _verb(target)[1]])
		out.append([X, RemakeText.t("More")])
		out.append(["DPAD_LR", RemakeText.t("Target")])
	else:
		out.append([X, RemakeText.t("Move")])
	out.append([PadInput.button_of("gait"), RemakeText.t("Movement")])
	out.append([PadInput.button_of("actions"), RemakeText.t("Spells")])
	out.append([PadInput.button_of("items"), RemakeText.t("Items")])
	out.append([PadInput.button_of("pause"), RemakeText.t("Resume") if get_tree().paused else RemakeText.t("Pause"),
		_can_change_speed()])
	return out


# ------------------------------------------------------------------ actions

func _can_change_speed() -> bool:
	return not game.session.multiplayer_game or (game.session.can_manage_game() and game.session.coop_clock_enabled())


func _on_action(a: String, phase: String) -> void:
	if PadInput.route_of(a) != "field" or not takes_input():
		return
	var mod := PadInput.held("mod") and a != "mod"
	if _wheel_kind != "":
		if phase == "down":
			_in_wheel[a] = true
		_wheel_action(a, phase)
		return
	# The rest of a press that a wheel took (A confirming a pick closes the
	# wheel; its release and tap must not act on the field as well).
	if phase == "down":
		_in_wheel.erase(a)
	elif _in_wheel.has(a):
		return
	if not cursor_mode and game.direct and game.direct.active() and game.direct.pad_action(a,phase): return
	if cursor_mode and _cursor_action(a, phase, mod):
		return
	match [a, phase]:
		["interact", "tap"]:
			if mod:
				_forced("ctrl")
			else:
				act()
		["interact", "hold"]:
			_forced("ctrl")
		["cancel", "down"]:
			if mod:
				game.hud.minimap.key_toggle()
			else:
				cancel()
		["context", "down"]:
			if mod:
				_forced("alt")
			else:
				open_ring()
		["pause", "tap"]:
			if mod:
				game.hud.toggle_aggression()
			else:
				game.set_speed(0)
		["pause", "hold"]:
			if not mod and not get_tree().paused and _can_change_speed():
				game.set_speed(2 if game.speed == 0 else 1)
		["actions", "down"]:
			open_wheel("actions", a)
		["items", "down"]:
			open_wheel("items", a)
		["system", "down"]:
			open_wheel("system", a)
		["left", "down"], ["right", "down"]:
			if mod:
				var views := UnitPanel.KEY_VIEWS
				var i := views.find(game.hud.unit_panel.mode)
				game.hud.unit_panel.key_view(posmod(i + (1 if a == "right" else -1), views.size()))
			else:
				cycle_target(1 if a == "right" else -1)
		["up", "tap"]:
			cycle_party(-1 if mod else 1)
		["up", "hold"]:
			if not mod and not game.session.multiplayer_game:
				game._key_action("select_all")
		["down", "tap"]:
			if mod:
				cycle_party(1)
			else:
				examine()
		["down", "hold"]:
			if not mod:
				game.hud.set_move_mode("walk" if game.hud._selected_gait() == 1 else "sneak")
		["cursor", "tap"]:
			_set_cursor_mode(not cursor_mode)
		["gait", "tap"]:
			if mod:
				game.hud.minimap.north()
			else:
				open_gait()
		["gait", "hold"]:
			if not mod:
				world_info = true   # BG3's "world information" (L3 hold)
		["gait", "up"]:
			world_info = false
		["view", "tap"]:
			if mod:
				_log_mode = (_log_mode + 1) % 2
				game.hud.text_window.key_mode(_log_mode)
			else:
				game.open_quests()
		["view", "hold"]:
			game.hud.toggle_journal()
		["menu", "down"]:
			game.hud.toggle_menu()


## Cursor mode (R3): A / B are the mouse's buttons at the pointer; X opens the
## ring on the unit under it. Returns whether the action was taken.
func _cursor_action(a: String, phase: String, mod: bool) -> bool:
	var ui: PadUI = PadInput.ui
	match [a, phase]:
		["interact", "down"]:
			if mod:
				var u := game.pick_unit(ui.pointer)
				if u:
					game.order_on(u, true, ui.pointer)
				return true
			ui.click(true, MOUSE_BUTTON_LEFT, PadInput.was_double("interact") or (Time.get_ticks_msec() - int(PadInput._last_tap.get("interact", -100000)) < 300))
			return true
		["interact", "up"]:
			ui.click(false)
			return true
		["interact", "tap"], ["interact", "hold"]:
			return true
		["cancel", "down"]:
			if game.pending_spell != "" or game.touch_aim >= 0 or game.touch_force != "":
				ui.click(true, MOUSE_BUTTON_RIGHT)
				ui.click(false, MOUSE_BUTTON_RIGHT)
			else:
				_set_cursor_mode(false)
			return true
		["context", "down"]:
			if not mod:
				var u := game.pick_unit(ui.pointer)
				if u:
					target = {"unit": u}
				else:
					var lv := game.pick_lever(ui.pointer)
					target = {"lever": lv, "at": Vector2.ZERO} if lv >= 0 else {}
				open_ring(game.pick_ground(ui.pointer))
				return true
	return false


func _set_cursor_mode(on: bool) -> void:
	if on == cursor_mode:
		return
	cursor_mode = on
	var ui: PadUI = PadInput.ui
	if on:
		_stop_moving()
		var u := leader()
		var at := get_viewport().get_visible_rect().size * 0.5
		if u and game.rig.camera and not game.rig.camera.is_position_behind(u.global_position):
			at = game.rig.camera.unproject_position(u.global_position + Vector3.UP)
		ui.pointer_on = true
		ui.set_pointer(at)
	else:
		ui.pointer_on = false


## A: act on the target exactly as a left click on it (Game.order_on), or
## confirm a pending spell / belt item / Use-Steal / Follow there.
func act() -> void:
	game._double = PadInput.was_double("interact")
	if game.pending_spell != "":
		var u := target_unit()
		if reticle != null and u == null:
			game.cast_on(null, null, reticle)
		elif u:
			game.cast_on(u)
		elif target.has("lever"):
			game.cast_on(null, null, null, int(target.lever))
		else:
			return
		game.pending_spell = ""
		game.hud.set_targeting("")
		reticle = null
	elif target.has("unit") and target_unit():
		game.order_on(target_unit(), false)
	elif target.has("lever"):
		game.order_on(null, false, null, int(target.lever))
	game._double = false


func _ahead(dist := 5.0) -> Variant:
	var u := leader()
	if u == null:
		return null
	if reticle != null:
		return reticle
	var stick := PadInput.stick(true)
	var d := _ground_dir(stick if stick != Vector2.ZERO else Vector2(0, -1))
	return _walk_goal_far(u, d, dist)


func _walk_goal_far(u: GameUnit, d: Vector2, dist: float) -> Vector2:
	var nav: NavGrid = game.world.nav
	var l := dist
	while l > 1.0:
		var p := u.pos + d * l
		if nav == null or nav.is_walkable(p):
			return p
		l -= 1.0
	return u.pos + d * dist


## LT + A / A held: Ctrl's forced attack on the target, else a swarm move
## ahead; LT + X: Alt's forced move to the target or ahead.
func _forced(m: String) -> void:
	if game.selected.is_empty():
		return
	game._double = false
	var u := target_unit()
	game.forced_on(m, u if u and not u.dead else (u if m == "alt" else null), _ahead() if u == null or (m != "alt" and u.dead) else null)


## B: cancels a pending target choice or aim, else the selection stops.
func cancel() -> void:
	PadInput.last_cancel_ms = Time.get_ticks_msec()
	if game.pending_spell != "" or game.touch_aim >= 0 or game.touch_force != "":
		game.cancel_touch_target()
		reticle = null
		return
	if is_instance_valid(game.hud.unit_panel.examine):
		game.hud.unit_panel.examine = null
		return
	_moving = false
	for s: GameUnit in game.selected:
		if is_instance_valid(s) and not s.dead:
			_submit_move(s, s.pos)


## D-pad ↓: the unit panel shows the target; again: its next view.
func examine() -> void:
	var u := target_unit()
	var panel := game.hud.unit_panel
	if u == null:
		panel.examine = null
		return
	if panel.examine == u:
		var i := UnitPanel.KEY_VIEWS.find(panel.mode)
		panel.key_view((i + 1) % UnitPanel.KEY_VIEWS.size())
	else:
		panel.examine = u
	if GameSound.instance:
		GameSound.instance.ui("buttons\\battle\\click.wav")


## D-pad ↑: the next own hero or mercenary (party faces order), as select1–3.
func cycle_party(step: int) -> void:
	var mine := game.my_units()
	if mine.is_empty():
		return
	var i := mine.find(leader())
	var n := posmod(i + step, mine.size()) if i >= 0 else 0
	_stop_moving()
	game.selected = [mine[n]]
	game.sound.ui("buttons\\battle\\on_off.wav")
	GameSound.ack(mine[n], EIAcks.SELECTED)
	game.rig.center_on(mine[n].position)
	target = {}
	reticle = null


# ------------------------------------------------------------------ wheels

func open_wheel(kind: String, button: String) -> void:
	_stop_moving()
	_wheel_kind = kind
	_wheel_button = button
	_flicked = false
	wheel.pages = PackedStringArray()
	wheel.page = 0
	_fill_wheel()
	_hold_pause(true)


func _fill_wheel() -> void:
	var entries: Array = []
	var pre := -1
	var A := PadInput.button_of("interact")
	var B := PadInput.button_of("cancel")
	var LB := PadInput.button_of("actions")
	var RB := PadInput.button_of("items")
	wheel.hints = [[A, RemakeText.t("Select")], [B, RemakeText.t("Close")]]
	match _wheel_kind:
		"actions", "items":
			var names: Array = LB_PAGES if _wheel_kind == "actions" else RB_PAGES
			var page: String = names[_page[_wheel_kind]]
			wheel.pages = PackedStringArray(LB_PAGES.map(func(p): return _page_title(p)) + RB_PAGES.map(func(p): return _page_title(p)))
			wheel.page = (LB_PAGES + RB_PAGES).find(page)
			wheel.title = _page_title(page)
			entries = _page_entries(page)
			wheel.hints.append([LB + "+" + RB, RemakeText.t("Page")])
			wheel.hints.append([PadInput.button_of("mod"), RemakeText.t("Use at once")])
		"system":
			var page: String = RT_PAGES[_page.system]
			wheel.pages = PackedStringArray(RT_PAGES.map(func(p): return _page_title(p)))
			wheel.page = _page.system
			wheel.title = _page_title(page)
			entries = _system_entries() if page == "game" else _camera_entries()
			wheel.hints.append([LB + "+" + RB, RemakeText.t("Page")])
			if page == "camera":
				wheel.hints.append([PadInput.button_of("mod"), RemakeText.t("Store view")])
		"ring":
			var r := _ring_entries()
			entries = r[0]
			pre = r[1]
			wheel.title = r[2]
		"gait":
			var r := _gait_entries()
			entries = r[0]
			pre = r[1]
			wheel.title = RemakeText.t("Movement mode")
	wheel.open(entries, pre)


func _page_title(p: String) -> String:
	match p:
		"spells": return RemakeText.t("Spells")
		"actions": return RemakeText.t("Actions")
		"belt": return RemakeText.t("Belt")
		"weapons": return RemakeText.t("Weapons")
		"game": return RemakeText.t("Game")
		"camera": return RemakeText.t("Camera")
	return p


static func _orig(key: String, fallback: String) -> String:
	return OptionsPanel._t("string " + key, fallback)


func _page_entries(page: String) -> Array:
	var out: Array = []
	var u := leader()
	var h: Dictionary = u.get_meta("hero") if u and u.has_meta("hero") else {}
	match page:
		"spells":
			var spells: Array = h.get("spells", [])
			for i in mini(spells.size(), SpellSlots.SLOTS):
				var sp := String(spells[i])
				var tt := int((Spells.parse(sp).get("proto", {}) as Dictionary).get("texture_type", -1))
				out.append({"id": ["spell", i], "label": Spells.title(sp), "icon": SpellSlots.icon("spell%04d" % tt) if tt >= 0 else null,
					"on": game.pending_spell == sp})
		"belt":
			var q: Array = h.get("quick", [])
			for i in mini(q.size(), BeltStrip.SLOTS):
				out.append({"id": ["belt", i], "label": Items.title(String(q[i])), "item": String(q[i])})
		"weapons":
			var w: Array = game.hud._weapons._items
			for i in mini(w.size(), WeaponBar.SLOTS):
				out.append({"id": ["weapon", i], "label": Items.title(String(w[i])), "item": String(w[i]),
					"on": i == game.hud._weapons._active})
		"actions":
			var aggr := game.hud._selected_aggression()
			out.append({"id": ["swarm"], "label": _orig("action_swarm", "Aggressive / defensive"),
				"short": RemakeText.t("Defensive") if aggr == 1 else RemakeText.t("Aggressive"),
				"tip": GameData.text("tip action_swarm").strip_edges()})
			out.append({"id": ["key", "use_science"], "label": Skills.title("science"), "short": Skills.title("science"),
				"enabled": u != null and u.has_meta("hero")})
			out.append({"id": ["key", "follow"], "label": RemakeText.t("Follow"), "short": RemakeText.t("Follow"),
				"tip": GameData.text("tip 10510").strip_edges()})
			# The movement modes have their own ring on L3 (open_gait).
			var l := RemakeText.t("Unit panel view")
			out.append({"id": ["view"], "label": l, "short": RemakeText.t("View")})
	if out.is_empty():
		out.append({"id": ["none"], "label": RemakeText.t("Empty"), "short": "—", "enabled": false})
	return out


func _system_entries() -> Array:
	var s := game.session
	var out: Array = []
	var add := func(id: String, label: String, short := "", on := true):
		out.append({"id": ["sys", id], "label": label, "short": short if short != "" else label, "enabled": on})
	add.call("inventory", RemakeText.t("Inventory"))
	add.call("journal", RemakeText.t("Journal"))
	add.call("quests", _orig("action_obj", "Quests"))
	if s.shop_available():
		add.call("side_quests", RemakeText.t("Side quests"))
	add.call("minimap", _orig("action_w_minimap", "Minimap"))
	add.call("log", _orig("action_w_text1", "Messages"))
	add.call("quicksave", _orig("action_quicksave", "Quick save"), "", s.can_manage_game())
	add.call("quickload", _orig("action_quickload", "Quick load"), "", s.can_manage_game())
	add.call("tutorial", _orig("action_tutorial_script", "Tutorial"))
	if s.multiplayer_game:
		add.call("chat", RemakeText.t("Chat"))
		if s.can_manage_game():
			add.call("players", RemakeText.t("Players"))
	return out


## The RT wheel's camera page: views 1–4 (keyboard.ini camera1–4, F9–F12):
## a pick recalls the view, with LT held (EI's Ctrl / Alt) it stores the
## current one there (CameraRig.view_slot); up-right, the centring on the
## leader (camera_track, Home).
func _camera_entries() -> Array:
	var out: Array = []
	var tip := RemakeText.t("Recalls this camera view; with %s held, stores the current view in it.") % PadInput.label(PadInput.button_of("mod"))
	for i in 4:
		out.append({"id": ["cam", i], "label": _orig("action_camera%d" % (i + 1), "Camera view %d" % (i + 1)),
			"short": str(i + 1), "angle": VIEW_ANGLES[i], "tip": tip})
	out.append({"id": ["key", "camera_track"], "label": RemakeText.t("Centre the camera"), "short": RemakeText.t("Centre"),
		"angle": CENTRE_ANGLE, "tip": RemakeText.t("Centres the camera on the leader and follows again.")})
	return out


## The movement-mode ring (L3 tap): the move dial's four gaits with its own
## figures (HudDial.gait_icon) and tips 10501–10504, from run at the top
## clockwise down to crawl; the selection's mode (the leader's when they
## differ) preselected. A pick is the dial's click (GameHUD.set_move_mode):
## the gait for every selected unit. [entries, preselected].
func _gait_entries() -> Array:
	var cur := game.hud._selected_gait()
	var u := leader()
	if cur < 0 and u:
		cur = u.gait()
	var out: Array = []
	var pre := -1
	for i in GAIT_RING.size():
		var g: int = GAIT_RING[i][1]
		var name: String = GAIT_RING[i][0]
		var l := _orig("action_" + name, name.capitalize())
		out.append({"id": ["gait", name], "label": l, "short": l, "icon": HudDial.gait_icon(g), "angle": 90.0 * i,
			"tip": GameData.text("tip %d" % (10501 + g)).strip_edges(), "on": g == cur})
		if g == cur:
			pre = i
	return [out, pre]


## L3 tap: the movement-mode ring for the selection; the left stick (or the
## right) picks.
func open_gait() -> void:
	if game.hud._first_selected() == null:
		return
	_stop_moving()
	_wheel_kind = "gait"
	_wheel_button = "gait"
	_flicked = false
	wheel.pages = PackedStringArray()
	_fill_wheel()
	_hold_pause(true)


## The context ring (X) on the target: [entries, preselected, title].
func _ring_entries() -> Array:
	var out: Array = []
	var pre := -1
	var t := _ring_target
	var u: GameUnit = t.unit if t.has("unit") and is_instance_valid(t.unit) else null
	var me := leader()
	var title := u.display_name if u else ""
	if u and not u.dead and u.controller != game.session.my_index:
		var enemy := me != null and game.world.is_enemy(me, u)
		if enemy:
			# Attack, the six aimed strikes (numpad layout, original cursors), Use/Steal.
			out.append({"id": ["attack"], "label": RemakeText.t("Attack"), "short": RemakeText.t("Attack"), "angle": 315.0,
				"icon": _cursor("cursor_attack")})
			for i in 6:
				var strip: Array = []
				for f: Image in GameCursor.frames(Game.AIM_CURSORS[i]):
					strip.append(ImageTexture.create_from_image(f))
				out.append({"id": ["aim", i], "label": _orig("action_" + AIM_ACTIONS[i], AIM_ACTIONS[i]),
					"strip": strip, "angle": AIM_ANGLES[i], "tip": RemakeText.t("Aimed strike")})
				if i == last_aim:
					pre = out.size() - 1
			out.append({"id": ["steal"], "label": Skills.title("science"), "short": Skills.title("science"), "angle": 45.0,
				"icon": _cursor("cursor_steal"), "enabled": me != null and me.has_meta("hero")})
		else:
			out.append({"id": ["interact"], "label": RemakeText.t("Talk"), "icon": _cursor("cursor_talk")})
			out.append({"id": ["steal"], "label": Skills.title("science"), "icon": _cursor("cursor_steal"),
				"enabled": me != null and me.has_meta("hero")})
			out.append({"id": ["follow"], "label": RemakeText.t("Follow"), "icon": _cursor("cursor_move")})
			out.append({"id": ["forced"], "label": RemakeText.t("Forced attack"), "icon": _cursor("cursor_attack")})
			out.append({"id": ["examine"], "label": RemakeText.t("Examine"), "short": "?"})
			pre = 0
	elif u and not u.dead:
		if game.session.shop_available() and _has_topics(u):
			out.append({"id": ["interact"], "label": RemakeText.t("Talk"), "icon": _cursor("cursor_talk")})
		out.append({"id": ["select"], "label": RemakeText.t("Select"), "short": RemakeText.t("Select")})
		out.append({"id": ["add"], "label": RemakeText.t("Add to selection"), "short": "+"})
		out.append({"id": ["follow"], "label": RemakeText.t("Follow"), "icon": _cursor("cursor_move")})
		out.append({"id": ["examine"], "label": RemakeText.t("Examine"), "short": "?"})
		pre = 0
	elif u:
		if Session.lootable(u, game.session.my_index, conn_id(self, game.session.online)):
			out.append({"id": ["loot"], "label": RemakeText.t("Loot"), "icon": _cursor("cursor_use")})
		if game.revive_target(u) != null:
			out.append({"id": ["revive"], "label": RemakeText.t("Revive"), "icon": _cursor("cursor_use")})
		pre = 0
	elif t.has("lever") and int(t.lever) >= 0:
		title = ""
		out.append({"id": ["lever"], "label": RemakeText.t("Use"), "icon": _cursor("cursor_use")})
		pre = 0
	if out.is_empty():
		title = RemakeText.t("Ground")
		out.append({"id": ["move"], "label": RemakeText.t("Move here"), "icon": _cursor("cursor_move"), "angle": 0.0})
		out.append({"id": ["run"], "label": RemakeText.t("Run here"), "short": RemakeText.t("Run"), "angle": 90.0})
		out.append({"id": ["forced_move"], "label": RemakeText.t("Forced move"), "short": "Alt", "angle": 180.0})
		out.append({"id": ["swarm_move"], "label": RemakeText.t("Swarm move"), "icon": _cursor("cursor_attack"), "angle": 270.0})
		pre = 0
	return [out, pre, title]


var _cursors := {}

func _cursor(kind: String) -> Texture2D:
	if not _cursors.has(kind):
		var f := GameCursor.frames(kind)
		_cursors[kind] = ImageTexture.create_from_image(f[0]) if not f.is_empty() else null
	return _cursors[kind]


## X: the ring on the soft target, else on the ground ahead (or `ground`).
func open_ring(ground: Variant = null) -> void:
	_stop_moving()
	_ring_target = target.duplicate()
	_ring_ground = ground if ground != null else _ahead()
	_wheel_kind = "ring"
	_wheel_button = "context"
	_flicked = false
	wheel.pages = PackedStringArray()
	_fill_wheel()
	_hold_pause(true)


func close_wheel() -> void:
	wheel.close()
	_wheel_kind = ""
	_ls_wait = PadInput.stick(true) != Vector2.ZERO
	_wheel_button = ""
	_hold_pause(false)


## Option pad_wheel_pause: a single player game holds the active pause while
## a wheel is open (EI fights run in real time); network games never pause.
func _hold_pause(on: bool) -> void:
	if on:
		if _wheel_paused == null and not game.session.multiplayer_game and GameData.option("pad_wheel_pause") != 0:
			_wheel_paused = get_tree().paused
			get_tree().paused = true
	elif _wheel_paused != null:
		get_tree().paused = bool(_wheel_paused)
		_wheel_paused = null


func wheel_kind() -> String:
	return _wheel_kind


func _wheel_action(a: String, phase: String) -> void:
	match [a, phase]:
		["interact", "down"]:
			_confirm()
		["cancel", "down"]:
			close_wheel()
		["actions", "down"], ["items", "down"]:
			if _wheel_kind in ["actions", "items"]:
				_turn_page(-1 if a == "actions" else 1)
			elif _wheel_kind == "system":
				_page.system = posmod(_page.system + (-1 if a == "actions" else 1), RT_PAGES.size())
				_wheel_button = ""
				if GameSound.instance:
					GameSound.instance.ui("buttons\\save\\select.wav")
				_fill_wheel()
			else:
				close_wheel()
				open_wheel(a, a)
		[_, "up"]:
			if a == _wheel_button and _flicked and wheel.selected >= 0:
				_confirm()
		["gait", "tap"]:
			if _wheel_kind == "gait":
				close_wheel()   # L3 again without a flick
		["system", "down"]:
			if _wheel_kind == "system":
				close_wheel()
		["menu", "down"]:
			close_wheel()
			game.hud.toggle_menu()


## LB / RB in an open action wheel: through all four pages.
func _turn_page(step: int) -> void:
	var all := LB_PAGES + RB_PAGES
	var cur: String = (LB_PAGES if _wheel_kind == "actions" else RB_PAGES)[_page[_wheel_kind]]
	var n: String = all[posmod(all.find(cur) + step, all.size())]
	if n in LB_PAGES:
		_wheel_kind = "actions"
		_page.actions = LB_PAGES.find(n)
	else:
		_wheel_kind = "items"
		_page.items = RB_PAGES.find(n)
	_wheel_button = ""
	if GameSound.instance:
		GameSound.instance.ui("buttons\\save\\select.wav")
	_fill_wheel()


func _confirm() -> void:
	var e := wheel.current()
	if e.is_empty() or not e.get("enabled", true):
		return
	var id: Array = e.id
	var mod := PadInput.held("mod")
	var kind := _wheel_kind
	close_wheel()
	match String(id[0]):
		"spell": game.hud._slots.use(int(id[1]), mod)
		"belt": game.hud._belt.use(int(id[1]), mod)
		"weapon": game.hud._weapons.key_select(int(id[1]))
		"swarm": game.hud.toggle_aggression()
		"key": game._key_action(String(id[1]))
		"gait": game.hud.set_move_mode(String(id[1]))
		"view":
			var i := UnitPanel.KEY_VIEWS.find(game.hud.unit_panel.mode)
			game.hud.unit_panel.key_view((i + 1) % UnitPanel.KEY_VIEWS.size())
		"sys": _system(String(id[1]))
		"cam":
			game.rig.view_slot(int(id[1]), mod)
			if mod and GameSound.instance:
				GameSound.instance.ui("buttons\\save\\select.wav")
		_: _ring_pick(id)
	if kind != "ring" and game.pending_spell != "":
		reticle = null
		_update_target(Vector2.ZERO)


func _system(id: String) -> void:
	var hud := game.hud
	match id:
		"inventory": hud.toggle_inventory()
		"journal": hud.toggle_journal()
		"quests": game.open_quests()
		"side_quests": hud.toggle_side_quests()
		"minimap": hud.minimap.key_toggle()
		"log":
			_log_mode = (_log_mode + 1) % 2
			hud.text_window.key_mode(_log_mode)
		"quicksave": game._key_action("quicksave")
		"quickload": game._key_action("quickload")
		"tutorial": game._key_action("tutorial_script")
		"chat": hud.chat_line.open()
		"players": hud.open_players()


func _ring_pick(id: Array) -> void:
	var t := _ring_target
	var u: GameUnit = t.unit if t.has("unit") and is_instance_valid(t.unit) else null
	var me := leader()
	game._double = false
	match String(id[0]):
		"attack", "interact", "loot", "revive":
			if u:
				game.order_on(u, false)
		"aim":
			# The aimed strike (Game.forced_on "aim": an attack order carrying
			# the part, as a click with the cs_* key held).
			last_aim = int(id[1])
			if u and not u.dead:
				game.touch_aim = last_aim
				game.forced_on("aim", u, null)
				game.touch_aim = -1
		"forced":
			if u:
				game.forced_on("ctrl", u, null)
		"steal":
			if me and me.has_meta("hero") and u:
				game.issue({"t": "steal", "unit": me.uid, "target": u.uid, "run": false})
		"follow":
			if u and not game.selected.is_empty():
				game.issue({"t": "follow", "units": game.selected.filter(func(s): return s != u).map(func(s: GameUnit): return s.uid), "target": u.uid})
		"examine":
			target = t
			game.hud.unit_panel.examine = u
		"select":
			if u:
				game.order_on(u, false)
		"add":
			if u:
				game.order_on(u, true)
		"lever":
			game.order_on(null, false, null, int(t.lever))
		"move", "run":
			if _ring_ground != null and not game.selected.is_empty():
				game._double = String(id[0]) == "run"
				game.order_on(null, false, null, -1, _ring_ground)
		"forced_move":
			game.forced_on("alt", null, _ring_ground)
		"swarm_move":
			game.forced_on("ctrl", null, _ring_ground)
	game._double = false


# ------------------------------------------------------------------ device

func _on_connection(dev: int, connected: bool) -> void:
	if connected or dev != PadInput.device and PadInput.device != -1:
		return
	if PadInput.active != "pad" or game.world == null:
		return
	game.hud.log_msg(RemakeText.t("Controller disconnected"))
	if not game.session.multiplayer_game and not get_tree().paused:
		game.set_speed(0)


## The light bar (option pad_light, controllers that have one): the
## leader's health, green to red (PadInput.health_colour); without a leader
## the dim bronze of the HUD.
func _light_poll() -> void:
	if PadInput.device < 0:
		return
	var u := leader()
	if u == null and not game.selected.is_empty() and is_instance_valid(game.selected[0]):
		u = game.selected[0]
	PadInput.light(PadInput.health_colour(u.hp / maxf(u.max_hp, 1.0)) if u else Color(0.45, 0.3, 0.1))


## Rumble (option pad_rumble): the leader hit (∝ the share of its health
## lost), a party member falling, a camera shake near the view, a level-up.
func _rumble_poll() -> void:
	var u := leader()
	if u:
		if _last_hp >= 0.0 and u.hp < _last_hp - 0.5:
			var f := clampf((_last_hp - u.hp) / maxf(u.max_hp, 1.0) * 3.0, 0.2, 1.0)
			PadInput.rumble(f * 0.5, f, 0.15)
		_last_hp = u.hp
		var lvl := Game.unit_level(u)
		if _last_level >= 0 and lvl > _last_level:
			PadInput.rumble(0.4, 0.0, 0.1)
		_last_level = lvl
	for m: GameUnit in game.world.party_units():
		if m.controller != game.session.my_index:
			continue
		var was := bool(_last_dead.get(m.uid, m.dead))
		if m.dead and not was:
			PadInput.rumble(0.8, 1.0, 0.4)
		_last_dead[m.uid] = m.dead
	var shakes := game.rig._shakes.size()
	if shakes > _last_shakes:
		var amp := float(game.rig._shakes[-1][2])
		PadInput.rumble(clampf(amp, 0.1, 1.0), clampf(amp * 0.7, 0.0, 1.0), 0.3)
	_last_shakes = shakes


## This peer's id for Session.lootable: 0 offline and while the connection is
## still being set up (a password retry), when get_unique_id() would complain.
static func conn_id(n: Node, online: bool) -> int:
	if not online or not n.is_inside_tree():
		return 0
	var mp := n.multiplayer
	if mp == null or not mp.has_multiplayer_peer() \
			or mp.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return 0
	return mp.get_unique_id()
