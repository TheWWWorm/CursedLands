class_name DirectControl
extends Node
## Per-player experimental shoulder controls. The authority receives ordinary
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


class Reticle extends Control:
	var controls: DirectControl
	func _draw() -> void:
		if not controls.usable() or controls.pointer: return
		var at := size * 0.5
		for d: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			draw_line(at+d*4.0,at+d*9.0,Color(0,0,0,0.7),3.0)
			draw_line(at+d*4.0,at+d*9.0,Color(1,1,1,0.9),1.0)
		if PadInput.active != "pad":
			var font := Interface800.font()
			var text := controls.keyboard_hint()
			var k := size.y / 600.0
			_draw_hint(font,text,size.y-128.0*k,k)
			var action := controls.interaction_hint()
			if not action.is_empty():
				_draw_hint(font,action.text,size.y*0.5+36.0*k,k,
					Interface800.TEXT if action.enabled else Interface800.GREY)
	func _draw_hint(font: Font,text: String,y: float,k: float,colour := Interface800.TEXT) -> void:
		var fs := maxi(12,roundi(13.0*k))
		var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
		if width > size.x-100.0*k:
			fs = maxi(10,floori(fs*(size.x-100.0*k)/width))
			width = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
		var from := Vector2((size.x-width)*0.5,y)
		draw_rect(Rect2(from-Vector2(8,fs+4),Vector2(width+16,fs+10)),Color(0,0,0,0.65))
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
	return mode == 2 or (mode == 0 and pad)


func active() -> bool:
	return wants(GameData.option("control_mode"), PadInput.enabled() and PadInput.active == "pad") \
		and game.world != null and not game.simulation_only


func field() -> PadField:
	return game.get_node_or_null("PadField") as PadField


func leader() -> GameUnit:
	for u: GameUnit in game.selected:
		if is_instance_valid(u) and not u.dead and u.controller == game.session.my_index: return u
	return null


func usable() -> bool:
	if not active() or leader() == null or not game.rig._window_focused or game.rig.held \
		or game.session.loading_game or game.session.movie_active() or game.hud.blocks_camera(): return false
	var f := field()
	if f and (f.cursor_mode or f.wheel.visible): return false
	var focus := get_viewport().gui_get_focus_owner()
	return not (focus is LineEdit or focus is TextEdit)


func direction() -> Vector3:
	return Vector3(cos(heading)*cos(tilt),sin(tilt),-sin(heading)*cos(tilt))


func ground_direction(v: Vector2) -> Vector2:
	return (Vector2.from_angle(heading)*-v.y + Vector2.from_angle(heading-PI*0.5)*v.x).normalized()


func _process(delta: float) -> void:
	var on := active()
	var u := leader() if on else null
	if on != _was_active:
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
	if game.world and not game.session.loading_game and not game.session.movie_active():
		var control_id := u.uid if on and u else -1
		if control_id != _control_id:
			if control_id >= 0 or _control_id >= 0:
				game.session.submit({"t":"direct_control","leader":control_id})
			_control_id = control_id
	if not on: _world = game.world
	var can := usable() and not pointer
	_capture(can and PadInput.active != "pad")
	if not can:
		_fire = false
		_neutral = true
		if on and field(): field()._stop_moving()
	elif PadInput.active != "pad":
		var move := Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W))).limit_length()
		step(move, minf(delta/maxf(Engine.time_scale,0.001),0.1))
	_overlay.visible = on
	if on: _overlay.queue_redraw()


func _capture(want: bool) -> void:
	if want == _captured or DisplayServer.get_name() == "headless": return
	_captured = want
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if want else GameData.free_mouse_mode()


func _input(e: InputEvent) -> void:
	# Captured clicks must not activate a HUD widget under the screen centre.
	if _captured and e is InputEventMouse:
		if handle_input(e): get_viewport().set_input_as_handled()


func handle_input(e: InputEvent) -> bool:
	if not active(): return false
	if e is InputEventKey and e.physical_keycode == KEY_TAB and e.pressed and not e.echo and not game.hud.blocks_camera():
		pointer = not pointer
		return true
	if not usable() or pointer: return false
	if e is InputEventMouseMotion:
		look(e.relative * 0.0025)
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
		if e.physical_keycode in [KEY_W,KEY_A,KEY_S,KEY_D]: return true
		if e.physical_keycode == KEY_E:
			if e.pressed and not e.echo:
				if game.has_spell_target(): cast_self()
				else: interact()
			return true
	return false


func look(delta: Vector2) -> void:
	heading = wrapf(heading - delta.x * (-1.0 if GameData.option("camera_reverse_x") else 1.0),-PI,PI)
	tilt = clampf(tilt - delta.y * (-1.0 if GameData.option("camera_reverse_y") else 1.0),-1.1,0.8)


func pad_step(move: Vector2, look_axis: Vector2, dt: float) -> void:
	if not usable(): return
	look(look_axis*dt*2.2)
	step(move,dt)


func step(move: Vector2, dt: float) -> void:
	if _neutral:
		if move == Vector2.ZERO and not _fire: _neutral = false
		return
	_repeat = maxf(0.0,_repeat-dt)
	if _fire:
		field()._stop_moving()
		if _repeat <= 0.0: attack()
	else:
		steer(move,dt)


## Refresh a short-lived authority input. Releasing the stick/key stops the
## current steering order, without replacing a newly posted interaction.
func steer(move: Vector2, dt: float) -> void:
	var u := leader()
	if u == null or move == Vector2.ZERO or GameSound.blocked(u):
		stop_move()
		return
	var v := ground_direction(move) * minf(move.length(),1.0)
	var run := PadInput.active != "pad" and Input.is_physical_key_pressed(KEY_SHIFT)
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
	field()._stop_moving()
	_repeat = 0.2
	if game.pending_spell != "":
		var p := get_viewport().get_visible_rect().size*0.5
		var target := game.pick_unit(p,leader())
		if PadInput.active == "pad" and field().target_unit() != null:
			target = field().target_unit()
		if game.has_spell_target() and game.pending_target(target,game.pick_ground(p)).is_empty():
			_fire = false
			return
		game.cast_on(target, null if target else p)
		game.pending_spell = ""
		game.hud.set_targeting("")
		_fire = false
		return
	var d := (aim_point()-DirectCombat.origin(u)).normalized()
	game.issue({"t":"direct_attack","units":[u.uid],"direction":d})


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
	field()._stop_moving()
	if not game.cast_portrait(leader()): return
	field().target = {}
	field().reticle = null
	game.pending_spell = ""
	game.hud.set_targeting("")
	_fire = false


func keyboard_hint() -> String:
	if game.has_spell_target():
		return RemakeText.t("WASD: move   Mouse: look   Left click: cast   Right click: cancel   Tab: pointer")
	return RemakeText.t("WASD: move   Mouse: look   Left click: attack   E: interact   Tab: pointer" \
		if game.session.command_allowed({"t":"direct_attack"}) else \
		"WASD: move   Mouse: look   E: interact   Tab: pointer")


func interaction_hint() -> Dictionary:
	if game.has_spell_target():
		if not field().friendly_spell(): return {}
		return {"text":"E: " + RemakeText.t("Cast on self"),"enabled":not _self_target().is_empty()}
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
	else:
		verb = "Exit"
	return {"text":"E: " + RemakeText.t(verb) + (" — " + title if not title.is_empty() else ""),"verb":RemakeText.t(verb),"enabled":true}


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
	if target:
		if not nearby: # Keep the controller's existing exact-target interaction.
			if not target.dead and not game.session.shop_available() and game.world.is_enemy(u,target): return {}
			return {"unit":target}
		if target.dead:
			if game.revive_target(target) != null or Session.lootable(target,game.session.my_index,PadField.conn_id(self,game.session.online)):
				return {"unit":target}
		elif game.session.shop_available() or not game.world.is_enemy(u,target):
			return {"unit":target}
	var lever := game.pick_lever(p)
	if lever >= 0: return {"lever":lever}
	if nearby:
		target = _nearby_loot()
		if target: return {"unit":target}
	for id in game.world.zone.get("exits",{}):
		var exit: Dictionary = game.world.zone.exits[id]
		if not exit.has("remove") or String(exit.get("to","none")) == "none": continue
		var area: Rect2 = exit.remove
		if area.grow(2.0).has_point(u.pos): return {"exit":id,"at":area.get_center()}
	return {}


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


func apply_camera() -> void:
	var u := leader()
	if u == null or game.rig.held or game.session.movie_active(): return
	var rig := game.rig
	rig._opening_view = null
	# Drawn pose follows packet interpolation, never the newest network sample.
	var pivot := u.global_position + Vector3.UP * clampf(u.figure_half_z*1.6,0.6,2.8)
	var forward := direction()
	var right := Vector3(sin(heading),0,cos(heading))
	var wanted := pivot - forward*zoom + right*0.55
	var fraction := DirectCombat.scene_fraction(game.world,pivot,wanted,0.18)
	var eye := pivot.lerp(wanted,maxf(0.0,fraction-0.02))
	rig.position = u.global_position
	rig.camera.fov = 65.0
	rig.camera.near = 0.08
	rig.camera.global_position = eye
	rig.camera.look_at(eye+forward,Vector3.UP)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		stop_move()
		_fire = false
		_neutral = true
		_capture(false)


func _exit_tree() -> void:
	stop_move()
	_capture(false)
	if _control_id >= 0 and is_instance_valid(game.session) and is_instance_valid(game.world):
		game.session.submit({"t":"direct_control","leader":-1})
