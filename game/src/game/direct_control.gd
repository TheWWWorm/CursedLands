class_name DirectControl
extends Node
## Per-player first/third-person controls. The authority receives ordinary
## steering input and a direction for each strike, never client positions.

var game: Game
var heading := 0.0
var tilt := -0.12
var zoom := 3.6
var pointer := false
var _was_active := false
var _captured := false
var _world: GameWorld
var _hero: GameUnit
var _neutral := true
var _fire := false
var _repeat := 0.0
var _control_id := -2
var _saved_pose := {}
var _saved_near := 0.05
var _overlay: Control
var _move_id := -1
var _move_vector := Vector2.ZERO
var _move_run := false
var _move_refresh := 0.0
var _view_model: EIUnitModel
var _eye_model: EIUnitModel
var _eye_offset := Vector3.ZERO
var _shoulder_unit: GameUnit
var _shoulder_fraction := 1.0
var _could_control := false
var _portrait_target: GameUnit
var _portrait_spectating := false
var _load_resume := false
var _look_id := -1
var _look_refresh := 0.0
var _last_perspective := 2
var _tactical_return := false
var _pad_switch := {}
var _feedback := {}
var _feedback_due := 0.0
var _hit_unit: GameUnit
var _hit_serial := 0
var _hit_until := 0
var _posture_unit: GameUnit
var _posture_time := -1.0
const PRONE_HOLD := 0.45



class Reticle extends Control:
	var controls: DirectControl
	func _draw() -> void:
		var guide := GameData.option("direct_hints")
		var hint_scale := size.y / 720.0
		var hint_y := controls.hint_baseline()
		if controls._tactical_return and not controls.active():
			if guide > 0 and controls.can_switch() and PadInput.active != "pad":
				_draw_hint(Interface800.font(),controls.keyboard_compact_hint(),hint_y,hint_scale,Interface800.TEXT,false)
			return
		if not controls.usable(): return
		if controls.pointer:
			if guide > 0 and PadInput.active != "pad":
				_draw_hint(Interface800.font(),controls.key_label("pointer")+": "+RemakeText.t("Return to mouse look"),hint_y,hint_scale,Interface800.TEXT,false)
			return
		var at := size * 0.5
		var state := controls._feedback
		var ready: bool = state.get("ready", false)
		var kind: String = state.get("kind", "neutral")
		var k := clampf(size.y / 900.0, 0.7, 1.6)
		var colour := Color("eeeece") if ready else Color("8f9298")
		if kind == "friendly": colour = Color("f4c45d")
		elif kind == "blocked": colour = Color("ed9165")
		elif kind == "reach": colour = Color("a9e2b0")
		var gap := 3.0 if ready else 5.0
		for d: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			draw_line(at+d*gap*k,at+d*(gap+4.0)*k,Color(0,0,0,0.8),3.0*k)
			draw_line(at+d*gap*k,at+d*(gap+4.0)*k,colour,1.5*k)
		if kind == "reach": draw_circle(at, 2.0*k, colour)
		elif kind == "blocked": draw_line(at+Vector2(-3,3)*k,at+Vector2(3,-3)*k,colour,2.0*k)
		elif kind == "friendly":
			draw_polyline(PackedVector2Array([at+Vector2(0,-3)*k,at+Vector2(3,0)*k,at+Vector2(0,3)*k,at+Vector2(-3,0)*k,at+Vector2(0,-3)*k]),colour,1.5*k)
		if Time.get_ticks_msec() < controls._hit_until:
			for d: Vector2 in [Vector2(1,1),Vector2(-1,1),Vector2(1,-1),Vector2(-1,-1)]:
				draw_line(at+d*7.0*k,at+d*10.0*k,Color(1,1,1),2.0*k)
		var status: String = RemakeText.t(state.get("text", ""))
		if guide < 2:
			if kind == "friendly": status = RemakeText.t("Friendly")
			elif state.get("text", "") == "Recovering": status = ""
		if guide == 2 and state.get("recovering",false) and state.get("text","") != "Recovering":
			status += " · " + RemakeText.t("Recovering")
		if not status.is_empty(): _draw_hint(Interface800.font(),status,at.y+23.0*k,k,colour)
		if PadInput.active != "pad":
			var font := Interface800.font()
			k = size.y / 720.0
			if guide == 2:
				_draw_hint(font,controls.keyboard_hint(),hint_y-19.0*k,k)
				_draw_hint(font,controls.keyboard_extra_hint(),hint_y,k)
			elif guide == 1:
				_draw_hint(font,controls.keyboard_compact_hint(),hint_y,k,Interface800.TEXT,false)
			var action := controls.interaction_hint()
			if not action.is_empty():
				_draw_hint(font,action.text,size.y*0.5+42.0*k,k,
					Interface800.TEXT if action.enabled else Interface800.GREY)
	func _draw_hint(font: Font,text: String,y: float,k: float,colour := Interface800.TEXT,backing := true) -> void:
		var fs := maxi(12,roundi(13.0*k))
		var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
		if width > size.x-100.0*k:
			fs = maxi(10,floori(fs*(size.x-100.0*k)/width))
			width = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
		var from := Vector2((size.x-width)*0.5,y)
		if backing:
			draw_rect(Rect2(from-Vector2(4,fs+2),Vector2(width+8,fs+5)),Color(0,0,0,0.55))
		else:
			draw_string_outline(font,from,text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,maxi(1,roundi(k)),Color(0,0,0,0.9))
		draw_string(font,from,text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,colour)


func _init(g: Game = null) -> void:
	game = g


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -5
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var reticle := Reticle.new()
	reticle.controls = self
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(reticle)
	_overlay = reticle


static func wants(mode: int, pad: bool) -> bool:
	return mode in [2, 3] or (mode == 0 and pad)


func first_person() -> bool:
	return GameData.option("control_mode") == 3


func active() -> bool:
	return wants(GameData.option("control_mode"), PadInput.enabled() and PadInput.active == "pad") \
		and game.world != null and not game.simulation_only


func field() -> PadField:
	return game.get_node_or_null("PadField") as PadField


func leader() -> GameUnit:
	for u: GameUnit in game.selected:
		if is_instance_valid(u) and not u.dead and u.controller == game.session.my_index: return u
	return null


func usable(allow_aim_wheel := false) -> bool:
	if not active() or leader() == null or not game.rig._window_focused or game.rig.held \
		or transitioning() or game.session.movie_active() or game.hud.blocks_camera(): return false
	var f := field()
	if f and (f.cursor_mode or (f.wheel.visible and not (allow_aim_wheel and f._keyboard_aim))): return false
	var focus := get_viewport().gui_get_focus_owner()
	return not (focus is LineEdit or focus is TextEdit)


func transitioning() -> bool:
	return game.session.loading_game or game.session._remote_loading or game.session._zone_holding \
		or game.world != game.session.world or game.session.map_open \
		or (game.world != null and game.world.process_mode == Node.PROCESS_MODE_DISABLED)


func direction() -> Vector3:
	return Vector3(cos(heading)*cos(tilt),sin(tilt),-sin(heading)*cos(tilt))


func ground_direction(v: Vector2) -> Vector2:
	return (Vector2.from_angle(heading)*-v.y + Vector2.from_angle(heading-PI*0.5)*v.x).normalized()


func _process(delta: float) -> void:
	var on := active()
	var u := leader() if on else null
	if on != _was_active:
		_portrait_target = null
		_portrait_spectating = false
		_was_active = on
		pointer = false
		_fire = false
		_neutral = not (on and _world == game.world and not game.session.loading_game)
		if on:
			_hero = u
			if u: heading = u.facing
			_fire = PadInput.active == "pad" and PadInput.held("system") and not PadInput.held("mod")
			_saved_pose = game.rig.pose()
			_saved_near = game.rig.camera.near
			game.rig._suspend_motion()
			if game.rig._fade: game.rig._fade.clear()
		else:
			if field(): field()._stop_moving()
			game.rig.camera.near = _saved_near
			game.rig.camera.fov = CameraRig.MODERN_FOV if game.rig.modern() else CameraRig.ORIGINAL_FOV
			game.rig.set_pose(_saved_pose)
			if is_instance_valid(_hero): game.rig.center_on(_hero.global_position)
	if on and (_world != game.world or _hero != u):
		if _world != game.world:
			_portrait_target = null
			_portrait_spectating = false
			pointer = false
			_load_resume = true
			_move_id = -1
			_control_id = -2
			_saved_pose = game.rig.pose()
		else:
			stop_move()
		_world = game.world
		_hero = u
		_neutral = true
		_fire = false
		if u: heading = u.facing
	# Watching a co-op portrait while all owned actors are dead is temporary.
	# Selection can return a frame after the reliable revival event, once the
	# living snapshot arrives. Resume only then; ordinary portrait inspection
	# and deliberate pointer mode while alive stay under the player's control.
	if on and u and _portrait_spectating:
		_portrait_spectating = false
		_portrait_target = null
		pointer = false
		_neutral = true
		_fire = false
	if transitioning():
		# Re-register control only after the destination's authority accepts
		# input. A rejected one-shot registration otherwise leaves WASD inert.
		_control_id = -2
		_move_id = -1
		_load_resume = true
	if game.world and not transitioning() and not game.session.movie_active():
		var control_id := u.uid if on and u else -1
		if control_id != _control_id:
			if control_id >= 0 or _control_id >= 0:
				game.session.submit({"t":"direct_control","leader":control_id})
			_control_id = control_id
	if not on: _world = game.world
	var can := usable(true) and not pointer
	if can and _load_resume:
		_load_resume = false
		# Keyboard movement may continue through a loading screen. A held
		# attack and a controller stick still need their normal release gate.
		_neutral = PadInput.active == "pad" or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _could_control and not can and u and game.world == game.session.world and not transitioning():
		game.session.submit({"t":"direct_cancel","units":[u.uid]})
	_could_control = can
	_update_view_model(u.model if on and u and _first_person_view(u) and not is_instance_valid(_portrait_target) and not game.rig.held and not game.session.movie_active() else null)
	_capture(can and PadInput.active != "pad" and not (field() and field()._keyboard_aim))
	_advance_posture(delta / maxf(Engine.time_scale, 0.001))
	if not can:
		_fire = false
		_neutral = true
		if on and field(): field()._stop_moving()
	elif PadInput.active != "pad":
		var move := Vector2(float(EIKeymap.held("direct_right",2))-float(EIKeymap.held("direct_left",2)),
			float(EIKeymap.held("direct_back",2))-float(EIKeymap.held("direct_forward",2))).limit_length()
		step(move, minf(delta/maxf(Engine.time_scale,0.001),0.1))
	_overlay.visible = on or _tactical_return
	if on:
		_update_feedback(delta)
	if on or _tactical_return:
		_overlay.queue_redraw()


func _capture(want: bool) -> void:
	if want == _captured or DisplayServer.get_name() == "headless": return
	_captured = want
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if want else GameData.free_mouse_mode()


func _input(e: InputEvent) -> void:
	# Captured clicks must not activate a HUD widget under the screen centre.
	if _captured and e is InputEventMouse:
		if handle_input(e): get_viewport().set_input_as_handled()


func can_switch() -> bool:
	if game.world == null or leader() == null or game.simulation_only or transitioning() \
		or not game.rig._window_focused or game.rig.held or game.session.movie_active() or game.hud.blocks_camera(): return false
	var f := field()
	if f and f.wheel.visible: return false
	var focus := get_viewport().gui_get_focus_owner()
	return not (focus is LineEdit or focus is TextEdit)


func _set_view_mode(mode: int) -> void:
	# View consumers poll this local preference each frame. A quick switch
	# must not reapply the display mode or rebuild terrain/material options.
	GameData.options.control_mode = mode
	GameData.save_settings()


func switch_view(tactical := false) -> void:
	if not can_switch(): return
	if tactical:
		if active():
			_last_perspective = 3 if first_person() else 2
			_tactical_return = true
			stop_move()
			_fire = false
			_set_view_mode(1)
		else:
			_set_view_mode(_last_perspective)
			_tactical_return = false
	else:
		_last_perspective = 2 if first_person() else 3 if active() else _last_perspective
		_set_view_mode(_last_perspective)
		_tactical_return = false
		_eye_model = null
		_shoulder_unit = null


func cycle_view() -> void:
	if not can_switch(): return
	var mode := GameData.option("control_mode")
	var next := 3 if mode == 2 else 1 if mode == 3 else 2
	if next == 1:
		stop_move()
		_fire = false
	_set_view_mode(next)
	_tactical_return = false
	_eye_model = null
	_shoulder_unit = null
	_cancel_posture()


func handle_input(e: InputEvent) -> bool:
	var key := EIKeymap.direct_event(e) if e is InputEventKey else ""
	if key == "direct_tactical":
		if not can_switch(): return false
		if e.pressed and not e.echo: cycle_view()
		return true
	if key == "direct_posture" and not e.pressed and _posture_unit != null:
		if _posture_time >= 0.0 and _posture_unit == leader() and usable() and not pointer:
			game.hud.set_move_mode("walk" if _posture_unit.gait() <= 1 else "sneak")
		_cancel_posture()
		return true
	if not active(): return false
	if key == "direct_quests" and can_switch():
		if e.pressed and not e.echo: game.open_quests()
		return true
	if key == "direct_pointer" and e.pressed and not e.echo and can_switch():
		pointer = not pointer
		_portrait_target = null
		_portrait_spectating = false
		return true
	if not usable() or pointer: return false
	if e is InputEventMouseMotion:
		look(e.relative * 0.0025 * look_gain(GameData.option("direct_mouse_first" if first_person() else "direct_mouse_third")))
		return true
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_fire = e.pressed
			if e.pressed: attack()
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			game.pending_spell = ""
			game.hud.set_targeting("")
		elif e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			zoom = clampf(zoom + (-0.3 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 0.3),1.5,6.0)
		return true
	if e is InputEventKey:
		if key in ["direct_forward","direct_back","direct_left","direct_right","direct_sprint"]: return true
		if key == "direct_attack":
			_fire = e.pressed
			if e.pressed and not e.echo: attack()
			return true
		if key == "direct_posture":
			if e.pressed and not e.echo:
				_posture_unit = leader()
				_posture_time = 0.0
			return true
		if key == "direct_interact":
			if e.pressed and not e.echo:
				if game.has_spell_target(): cast_self()
				else: interact()
			return true
	return false


func _cancel_posture() -> void:
	_posture_unit = null
	_posture_time = -1.0


func _advance_posture(dt: float) -> void:
	if _posture_unit == null: return
	if not is_instance_valid(_posture_unit) or _posture_unit != leader() or not usable() or pointer or PadInput.active == "pad":
		_cancel_posture()
		return
	if _posture_time < 0.0: return
	_posture_time += dt
	if _posture_time >= PRONE_HOLD:
		game.hud.set_move_mode("crawl")
		_posture_time = -1.0


static func look_gain(value: int) -> float:
	return pow(2.0, (clampi(value,0,100) - 50) / 25.0)


func look(delta: Vector2, pad := false) -> void:
	heading = wrapf(heading - delta.x * (-1.0 if GameData.option("direct_pad_invert_x" if pad else "direct_invert_x") else 1.0),-PI,PI)
	tilt = clampf(tilt - delta.y * (-1.0 if GameData.option("direct_pad_invert_y" if pad else "direct_invert_y") else 1.0),
		-1.45 if first_person() else -1.1, 1.35 if first_person() else 0.8)


func pad_step(move: Vector2, look_axis: Vector2, dt: float) -> void:
	if not usable(): return
	var exponent: float = [1.0,1.6,2.2][clampi(GameData.option("direct_pad_curve"),0,2)]
	var shaped := look_axis.normalized() * pow(minf(look_axis.length(),1.0),exponent)
	look(shaped * Vector2(look_gain(GameData.option("direct_pad_x")),look_gain(GameData.option("direct_pad_y"))) * dt * 2.2,true)
	step(move,dt)


func step(move: Vector2, dt: float) -> void:
	if _neutral:
		if move == Vector2.ZERO and not _fire: _neutral = false
		return
	var u := leader()
	_look_refresh -= dt
	if u and not GameSound.blocked(u) and (_look_id != u.uid or _look_refresh <= 0.0):
		_look_id = u.uid
		_look_refresh = 1.0 / 30.0
		var command := {"t":"direct_look","units":[u.uid],"heading":heading}
		command.merge(aim_view(u))
		game.session.submit(command)
	_repeat = maxf(0.0,_repeat-dt)
	steer(move,dt)
	if _fire and _repeat <= 0.0: attack()


## Refresh a short-lived authority input. Releasing the stick/key stops the
## current steering order, without replacing a newly posted interaction.
func steer(move: Vector2, dt: float) -> void:
	var u := leader()
	if u == null or move == Vector2.ZERO or GameSound.blocked(u):
		stop_move()
		return
	var v := ground_direction(move) * minf(move.length(),1.0)
	var run := PadInput.active != "pad" and EIKeymap.held("direct_sprint",2)
	_move_refresh -= dt
	var start := _move_id != u.uid
	if start:
		stop_move()
		_move_id = u.uid
		var others := game.selected.filter(func(s): return is_instance_valid(s) and s != u and not s.dead)
		if not others.is_empty():
			game.issue({"t":"follow","units":others.map(func(s: GameUnit): return s.uid),"target":u.uid})
	if start or _move_refresh <= 0.0 or v.distance_to(_move_vector) > 0.03 or run != _move_run:
		_move_refresh = 0.1
		_move_vector = v
		_move_run = run
		game.session.submit({"t":"direct_move","units":[u.uid],"direction":v,"run":run})


func stop_move() -> void:
	if _move_id < 0: return
	var id := _move_id
	_move_id = -1
	_move_vector = Vector2.ZERO
	if game.world and game.world == _world:
		game.session.submit({"t":"direct_move","units":[id],"direction":Vector2.ZERO})


func pad_action(action: String, phase: String) -> bool:
	# Consume the whole chord, even if the modifier is released first.
	if _pad_switch.has(action):
		if phase == "down": _pad_switch.erase(action)
		else:
			if phase == "hold": _pad_switch[action] = false
			if phase == "tap" or (phase == "up" and not _pad_switch[action]): _pad_switch.erase(action)
			return true
	if action in ["cursor","view"] and PadInput.held("mod") and can_switch():
		if phase == "down":
			_pad_switch[action] = true
			switch_view(action == "view")
		return true
	if not usable(): return false
	if action == "system": # RT by default; LT+RT retains the system wheel.
		if PadInput.held("mod"): return false
		if phase == "down":
			_fire = true
			attack()
		elif phase == "up": _fire = false
		return true
	if action == "interact":
		if phase == "tap":
			if game.has_spell_target(): field().act()
			else: interact()
		return true
	return false


func aim_view(u: GameUnit) -> Dictionary:
	var camera := game.rig.camera
	var drawn_muzzle := u.global_position + Vector3.UP * maxf(0.3, u.figure_half_z * 1.4)
	return {"view_offset":camera.global_position - drawn_muzzle,
		"view_direction":-camera.global_basis.z}


func aim_point() -> Vector3:
	var cam := game.rig.camera
	var start := cam.global_position
	var end := start - cam.global_basis.z * 60.0
	var fraction := DirectCombat.scene_fraction(game.world,start,end)
	var contact := DirectCombat.ray_body(game.world,leader(),start,end,fraction)
	return start.lerp(end,float(contact.fraction))


func attack() -> void:
	if not usable() or pointer or _neutral or get_tree().paused: return
	if not game.session.command_allowed({"t":"direct_cast" if game.pending_spell != "" else "direct_attack"}): return
	var u := leader()
	_repeat = 0.2
	if game.pending_spell != "":
		if not game.has_spell_target(): field()._stop_moving()
		var p := get_viewport().get_visible_rect().size*0.5
		var target := game.pick_unit(p,leader())
		if PadInput.active == "pad" and field().target_unit() != null:
			target = field().target_unit()
		if game.has_spell_target() and not game.pending_in_range(game.pending_target(target,game.pick_ground(p))):
			_fire = false
			return
		game.cast_on(target, null if target else p)
		game.pending_spell = ""
		game.hud.set_targeting("")
		_fire = false
		return
	var d := (aim_point()-DirectCombat.origin(u)).normalized()
	var command := {"t":"direct_attack","units":[u.uid],"direction":d,"aim":game.held_aim()}
	command.merge(aim_view(u))
	game.issue(command)


func arm_targeting() -> void:
	# Selecting a spell requires a new confirmation, even if an earlier
	# attack was held or its release was consumed by another control.
	_fire = false
	_repeat = 0.0


## Keyboard E has an explicit self action while a friendly spell/item is
## selected. Left click still uses the aimed target, including another hero.
func _self_target() -> Dictionary:
	if not field().friendly_spell(): return {}
	var info := game.pending_target(leader())
	if info.is_empty() or info.caster.controller != game.session.my_index or GameSound.blocked(info.caster): return {}
	if not game.session.command_allowed({"t":"use" if not String(info.item).is_empty() else "direct_cast"}): return {}
	return info


func cast_self() -> void:
	if not usable() or pointer or _neutral or get_tree().paused or _self_target().is_empty(): return
	if not game.cast_portrait(leader()): return
	field().target = {}
	field().reticle = null
	game.pending_spell = ""
	game.hud.set_targeting("")
	_fire = false


func keyboard_hint() -> String:
	var movement := "/".join([key_label("forward"),key_label("left"),key_label("back"),key_label("right")])
	return RemakeText.t("%s: move   Mouse: look   %s: attack/cast   %s: interact   %s: pointer") % [movement,
		RemakeText.t("Left click"),key_label("interact"),key_label("pointer")]


func keyboard_extra_hint() -> String:
	return RemakeText.t("%s: crouch (hold: lie down)   %s: aimed strike   %s: camera") % [key_label("posture"),key_label("aim"),key_label("tactical")] + "   " + key_label("quests") + ": " + RemakeText.t("Quests")


func keyboard_compact_hint() -> String:
	return RemakeText.t("%s: camera mode   %s: show cursor") % [key_label("tactical"),key_label("pointer")] + "   " + key_label("quests") + ": " + RemakeText.t("Quests")


func hint_baseline() -> float:
	var size := _overlay.size
	var k := size.y / 720.0
	var y := size.y - 132.0*k
	# The follow-camera marker scales with the actual HUD, including UI scale
	# and safe-area offsets. Keep both hint lines above its drawn rectangle.
	if game.hud and game.hud._faces:
		var rect := game.hud._faces.marker_screen_rect()
		if rect.has_area():
			var local := _overlay.get_global_transform_with_canvas().affine_inverse() * rect.position
			y = minf(y, local.y - 8.0*k)
	return y


func key_label(action: String) -> String:
	var key := EIKeymap.key_of("direct_"+action,2)
	return key if not key.is_empty() else "—"


func interaction_hint() -> Dictionary:
	if game.has_spell_target():
		if not field().friendly_spell(): return {}
		return {"text":key_label("interact")+": " + RemakeText.t("Cast on self"),"enabled":not _self_target().is_empty()}
	var action := _interaction_target(true)
	if action.is_empty(): return {}
	var verb := "Use"
	var title := ""
	if action.has("unit"):
		var target: GameUnit = action.unit
		verb = "Revive" if game.revive_target(target) != null else "Loot" if target.dead else "Talk"
		title = WorldLabels.unit_name(target)
	elif action.has("lever"):
		title = WorldLabels.lever_title(game.world,int(action.lever))
		if WorldLabels.lever_kind(game.world,int(action.lever)) in ["Skeleton", "Remains"]:
			verb = "Loot"
	else:
		verb = "Exit"
	return {"text":key_label("interact")+": " + RemakeText.t(verb) + (" — " + title if not title.is_empty() else ""),"verb":RemakeText.t(verb),"enabled":true}


## Nearby small bodies/piles need no exact silhouette hit. This only chooses
## an ordinary loot order; the host still owns reach, pathing and LMP purses.
const LOOT_RADIUS := 3.0
func _nearby_loot() -> GameUnit:
	var u := leader()
	if u == null or game.session.shop_available(): return null
	var best := LOOT_RADIUS * LOOT_RADIUS
	var found: GameUnit
	var conn := PadField.conn_id(self,game.session.online)
	for target: GameUnit in game.world.units_near(u.pos,LOOT_RADIUS):
		if target.hidden or target.fogged or not target.visible or target.get_meta("looted",false) \
			or not Session.lootable(target,game.session.my_index,conn): continue
		var d := u.pos.distance_squared_to(target.pos)
		if d > best or (is_equal_approx(d,best) and found and target.uid > found.uid): continue
		# A body on another floor or behind a solid wall is not a nearby action.
		var from := DirectCombat.origin(u)
		var ground := game.world.ground_at(target.pos.x,target.pos.y)
		var to := Vector3(target.pos.x,ground+0.3,-target.pos.y)
		if absf(game.world.ground_at(u.pos.x,u.pos.y)-ground) > 1.5 \
			or DirectCombat.scene_fraction(game.world,from,to) < 1.0: continue
		best = d
		found = target
	return found


func _interaction_target(nearby: bool) -> Dictionary:
	var u := leader()
	if u == null: return {}
	var p := get_viewport().get_visible_rect().size*0.5
	var target := game.pick_unit(p,u)
	var near_lever := _nearby_lever() if nearby else -1
	if near_lever >= 0 and (target == null or u.pos.distance_to(target.pos) > 4.0):
		return {"lever":near_lever}
	if target:
		if target.dead:
			if game.revive_target(target) != null or Session.lootable(target,game.session.my_index,PadField.conn_id(self,game.session.online)):
				return {"unit":target}
		elif game.can_talk_to(target):
			return {"unit":target}
	var lever := game.pick_lever(p)
	if lever >= 0: return {"lever":lever}
	if nearby:
		if near_lever >= 0: return {"lever":near_lever}
		target = _nearby_loot()
		if target: return {"unit":target}
	for id in game.world.zone.get("exits",{}):
		var exit: Dictionary = game.world.zone.exits[id]
		if not exit.has("remove") or String(exit.get("to","none")) == "none": continue
		var area: Rect2 = exit.remove
		if area.grow(2.0).has_point(u.pos): return {"exit":id,"at":area.get_center()}
	return {}


## Low chests and small switches need not put their origin exactly under
## the crosshair. Prefer the nearest usable object in front of the hero;
## the ordinary authority use order still handles approach and reach.
func _nearby_lever() -> int:
	var u := leader()
	if u == null: return -1
	var forward := Vector2.from_angle(heading)
	var best := INF
	var found := -1
	for nid: int in game.world.levers:
		if not game.world.lever_sys.usable(nid): continue
		var obj: Node3D = game.world.objects.get(nid)
		if not is_instance_valid(obj) or not obj.is_visible_in_tree(): continue
		var point := obj.global_position + Vector3.UP * 0.6
		var offset := Vector2(point.x, -point.z) - u.pos
		var distance := offset.length()
		if distance > 4.0 or offset.dot(forward) < distance * 0.5 \
			or game.rig.camera.is_position_behind(point) \
			or absf(point.y - DirectCombat.origin(u).y) > 2.0: continue
		var from := DirectCombat.origin(u)
		# The endpoint can lie inside the object's own small footprint.
		if from.distance_to(point) * (1.0 - DirectCombat.scene_fraction(game.world,from,point)) > 0.65: continue
		var score := distance + (1.0 - offset.normalized().dot(forward)) * 2.0
		if score < best:
			best = score
			found = nid
	return found


func interact() -> void:
	if not usable() or pointer or _neutral or get_tree().paused: return
	var action := _interaction_target(true)
	if action.is_empty(): return
	stop_move()
	# A held stick must be released before it can cancel the approach/use.
	_neutral = true
	if action.has("unit"):
		# Talking, looting and reviving keep their ordinary approach orders.
		game.order_on(action.unit,false)
	elif action.has("lever"):
		game.order_on(null,false,null,int(action.lever))
	elif action.has("exit"):
		game.issue({"t":"move","units":[leader().uid],"x":action.at.x,"y":action.at.y,"exit":action.exit})


func focus_portrait(u: GameUnit) -> void:
	if not active(): return
	stop_move()
	pointer = true
	_portrait_target = u
	_portrait_spectating = leader() == null
	_update_view_model(null)
	apply_camera()


func view_target() -> GameUnit:
	if pointer and is_instance_valid(_portrait_target) and not _portrait_target.dead and _portrait_target.world == game.world:
		return _portrait_target
	return leader()


## Action animations can keep the player's chosen eye view. Explicit movie,
## held and portrait cameras still own their framing in the callers.
func _first_person_view(u: GameUnit) -> bool:
	return first_person() and (GameData.option("direct_first_person_actions") != 0 \
		or not u.action.begins_with("anim:"))


func apply_camera(dt := 0.0) -> void:
	var u := view_target()
	var inspecting := pointer and is_instance_valid(_portrait_target) and u == _portrait_target
	if u == null or game.rig.held or game.session.movie_active():
		_eye_model = null
		_shoulder_unit = null
		return
	var rig := game.rig
	rig._opening_view = null
	var pivot := u.global_position + Vector3.UP * clampf(u.figure_half_z*1.6,0.6,2.8)
	var forward := direction()
	var right := Vector3(sin(heading),0,cos(heading))
	var eyes := _first_person_view(u) and not inspecting
	_update_view_model(u.model if eyes else null)
	var eye := pivot
	if eyes:
		var state := EIUnitModel.ST_WARRY if u.stance == GameUnit.STANCE_KNEEL else EIUnitModel.ST_LIE if u.stance == GameUnit.STANCE_CRAWL else EIUnitModel.ST_NEUTRAL
		var anchor := u.model.view_eye_offset(state) if u.model else Vector3(0, u.figure_half_z*1.88, 0)
		if _eye_model != u.model or u.model == null:
			_eye_offset = anchor
			_eye_model = u.model
		elif dt > 0.0:
			var eased := _eye_offset.lerp(anchor, 1.0-exp(-minf(dt,0.1)*18.0))
			_eye_offset = _eye_offset.move_toward(eased, minf(dt,0.1)*2.5)
		# The authority turns the body on simulation ticks. The local eye must
		# turn with this frame's mouse aim; inheriting the body's stepped yaw
		# moves the off-centre eye in small jumps during fast camera turns.
		var local_eye: Vector3 = u.model.transform * _eye_offset if u.model else _eye_offset
		eye = u.global_position + Basis(Vector3.UP, heading + GameUnit.MODEL_YAW_OFFSET) * local_eye
		# Eyes sit ahead of the collar: looking down sees the chest, while
		# walking neck/shoulder motion stays behind the near part of the view.
		eye += Vector3(cos(heading),0,-sin(heading)) * 0.28
		var size := rig.camera.get_viewport().get_visible_rect().size
		var fov := deg_to_rad(50.0 + 5.0 * GameData.option("direct_fov_first"))
		var clearance := maxf(0.10, 0.03 * tan(fov * 0.5) * maxf(1.0, size.x / maxf(size.y, 1.0)) + 0.01)
		eye = clear_first_person_eye(game.world, u.global_position, eye, clearance)
		_shoulder_unit = null
	else:
		var wanted := pivot - forward*zoom + right*0.55
		var fraction := maxf(0.0, DirectCombat.scene_fraction(game.world,pivot,wanted,0.18)-0.02)
		# Shorten immediately at a wall; ease back out instead of snapping
		# between successive half-metre terrain samples.
		if _shoulder_unit != u or fraction < _shoulder_fraction:
			_shoulder_fraction = fraction
		elif dt > 0.0:
			_shoulder_fraction = lerpf(_shoulder_fraction, fraction, 1.0-exp(-minf(dt,0.1)*10.0))
		_shoulder_unit = u
		eye = pivot.lerp(wanted,_shoulder_fraction)
		_eye_model = null
	rig.position = u.global_position
	rig.camera.fov = 50.0 + 5.0 * GameData.option("direct_fov_first" if eyes else "direct_fov_third")
	rig.camera.near = 0.03 if eyes else 0.08
	rig.camera.global_position = eye
	rig.camera.look_at(eye+forward,Vector3.UP)
	if eyes and u.model:
		var half_fov := deg_to_rad(rig.camera.fov) * 0.5
		var bottom := forward * sin(half_fov) + rig.camera.global_basis.y * cos(half_fov)
		u.model.align_first_person_body(eye, right, bottom)


## The prone head extends beyond the actor's ground contact. Sweep from the
## body to the drawn eye, including clearance for the near-plane corners.
## This only adjusts the viewpoint; it never moves the simulation's actor.
static func clear_first_person_eye(world: GameWorld, body: Vector3, wanted: Vector3, margin := 0.10) -> Vector3:
	var anchor := Vector3(body.x, maxf(body.y + margin + 0.01, wanted.y), body.z)
	# At an exact navigation-cell corner the actor's centre can be open while
	# the near plane overlaps an adjacent wall. Try nearby interior points
	# before lifting over rising terrain; a sweep must start in clear space.
	if not DirectCombat.scene_clear(world, anchor, margin):
		var found := false
		for rise in 12:
			for radius: float in [0.0, 0.15, 0.30]:
				for direction in 8:
					var offset := Vector2.from_angle(float(direction) * TAU / 8.0) * radius
					var candidate := anchor + Vector3(offset.x, float(rise) * 0.10, offset.y)
					if DirectCombat.scene_clear(world, candidate, margin):
						anchor = candidate
						found = true
						break
				if found: break
			if found: break
	var fraction := DirectCombat.scene_fraction(world, anchor, wanted, margin)
	return wanted if fraction == 1.0 else anchor.lerp(wanted, maxf(0.0, fraction - 0.005))


func _update_view_model(model: EIUnitModel) -> void:
	if _view_model == model: return
	if is_instance_valid(_view_model): _view_model.set_first_person_view(false)
	_view_model = model
	if is_instance_valid(_view_model): _view_model.set_first_person_view(true)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		stop_move()
		_fire = false
		_neutral = true
		_capture(false)


func _exit_tree() -> void:
	_update_view_model(null)
	stop_move()
	_capture(false)
	if _control_id >= 0 and is_instance_valid(game.session) and is_instance_valid(game.world):
		game.session.submit({"t":"direct_control","leader":-1})


func _update_feedback(dt: float) -> void:
	var u := leader()
	if _hit_unit != u:
		_hit_unit = u
		_hit_serial = u.direct_hit_serial if u else 0
		_hit_until = 0
	elif u and u.direct_hit_serial != _hit_serial:
		_hit_serial = u.direct_hit_serial
		_hit_until = Time.get_ticks_msec() + 180
	_feedback_due -= dt
	if _feedback_due > 0.0: return
	_feedback_due = 0.08
	_feedback = {}
	if u == null or not usable() or pointer: return
	var allowed := game.session.command_allowed({"t":"direct_attack"}) and not get_tree().paused and not GameSound.blocked(u)
	var recovery := maxf(u._attack_cd,u._anim_lock) if game.world.authority else u.direct_recovery
	if game.has_spell_target():
		var p := get_viewport().get_visible_rect().size * 0.5
		var target := game.pick_unit(p,u)
		if PadInput.active == "pad" and field().target_unit() != null: target = field().target_unit()
		var info := game.pending_target(target,game.pick_ground(p))
		var out_of_range := not info.is_empty() and not game.pending_in_range(info)
		_feedback = {"kind":"neutral","ready":false,"text":"Out of range" if out_of_range else "Spell selected"}
		return
	if not allowed:
		_feedback = {"kind":"neutral","ready":false,"text":""}
		return
	var cam := game.rig.camera
	_feedback = DirectCombat.preview(u,cam.global_position,-cam.global_basis.z)
	_feedback.ready = recovery <= 0.0
	if recovery > 0.0:
		_feedback.recovering = true
		if _feedback.get("text", "").is_empty(): _feedback.text = "Recovering"
