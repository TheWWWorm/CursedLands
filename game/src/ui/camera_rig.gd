class_name CameraRig
extends Node3D
## In-game camera. Two styles (remake option "camera_style"):
##
## **Original** (index 0): the 2000 game's RTS orbit camera, below. The
## keyboard.ini camera keys pan (with Ctrl / Alt: turn and tilt) and zoom,
## right-drag rotate, wheel zoom, middle-drag pan, screen-edge scrolling.
## Follows the terrain height.
## Options (the original camera controller, and the settings
## written): "power_kbd" / 50 is the keyboard power of the
## pan, rotate, pitch and zoom speeds (settings
## default 0.5 = slider 25), "power_mouse" / 50 the mouse power
## (default 1.0 = slider 50): keys
##  move at direction × keyboard power × scroll speed 1.0, the
## wheel zooms by notches × mouse zoom power, mouse drags
##  rotate / pitch / pan by pixels × mouse power.
## "scroll_border" (CameraBorderScrollArea): scrolls when
## the pointer is within that many pixels of a screen edge (0 = off), at unit
## speed — twice the default keyboard speed, not scaled by either power.
## Approx.: the absolute speeds are the remake's (the default keyboard power
## keeps its earlier tuning); only the ratios follow the original.
## Camera shake (list camera): (pos, p2, amp, decay) adds
## {t 0, duration p2 · 30 ticks, amp, decay} when the camera's look-at point
## is within 20 m of pos (amp × (1 − (d − 8) / 12) beyond 8 m); each frame
##  lifts the camera by Σ exp(−decay·t) · cos(π/2 · t · 0.26666668)
## · amp, t in 55 ms ticks, and drops an entry once t ≥ duration. Callers:
## LightningBlast 0x2030 (size, 2, 0.25) and heavy monsters' steps (5,
## prototype detonation, 0.25). No option gates it.
##
## **Modern** (index 1, the default; remake-only, not in the original), after
## Divinity: Original Sin 2 and similar games: eased, inertial panning (camera
## keys, optional WASD, screen edges), smooth wheel / key zoom whose pitch
## follows the zoom (close = low and cinematic, far = nearly top-down), smooth
## turning (middle or right drag, the bindable camera_rotate_left / right keys,
## Delete / End by default, or Ctrl / Alt + Left / Right), an optional
## follow-the-selected-hero mode that lets go while you pan and comes back when
## the hero starts moving, Home / a portrait double-click glide to the hero,
## a terrain-aware height and pitch (never inside a hill, the hero never behind
## one) and fading of the map objects between the camera and the party
## (CameraFade). Speeds: options cam_pan_speed / cam_rotate_speed /
## cam_zoom_speed; camera_reverse_x / y and scroll_border apply to both styles.
## Only the in-game camera (under Game) uses it; the map viewer keeps the
## original camera. Per player; nothing of it is networked.

## Registry defaults of the settings object (constructor
## read): CameraDefaultDistanceToCarrier 30
## CameraMin / MaxDistanceToCarrier 4 / 100
## CameraDefaultMin / MaxPitch 20° / 80°. **Approx.**: the
## camera controller that applies them is not traced, so the
## distance is taken as the eye's distance from the look-at point and the
## pitch as the angle below the horizon; the default pitch (50°) is the
## remake's.
## Field of view: the renderer builds one projection at start-up
## ((fov, aspect 4/3, near, far)) from the camera
## settings (settings, NearClip, FarClip, π · 2/7) (
## default the same): x scale cos(f/2) / sin(f/2), y scale × 4/3
## so 2π/7 = 51.43° is the horizontal field of the 4:3 view and its vertical
## field is 2·atan(tan(π/7) · 3/4) = 39.72°. The original style and the main
## menu use that vertical field (wider screens see more at the sides); the
## modern style keeps the remake's 55°.
const ORIGINAL_FOV := 39.7175
const MODERN_FOV := 55.0
const DEFAULT_DISTANCE := 30.0
const MIN_DISTANCE := 4.0
const MAX_DISTANCE := 100.0
const MIN_PITCH := 20.0
const MAX_PITCH := 80.0

## Modern style limits (remake). The farthest zoom keeps the look-at point in
## front of the night fog (Gfx.FOG_NIGHT 50 m; with the far view option its
## start × FAR_VIEW_FOG = 70 m), so the party never sinks into the fog.
const M_MIN_DISTANCE := 3.0
const M_MAX_DISTANCE_FAR := 72.0    # option gfx_far_view on
const M_MAX_DISTANCE_NEAR := 45.0   # gfx_far_view off: the original 100 m view
const M_DEFAULT_DISTANCE := 24.0
const M_PITCH_CLOSE := 9.0          # degrees below the horizon at the closest zoom
const M_PITCH_FAR := 72.0           # … at the farthest
const M_PITCH_OFS := 20.0           # ± tilt the player may add (drag / Ctrl + Up, Down)
const M_LIFT_CLOSE := 1.5           # look-at height above the ground, close (chest)
const M_LIFT_FAR := 0.3
const M_CLEARANCE := 1.2            # metres the eye line keeps above the terrain

var terrain: EITerrain
var yaw := deg_to_rad(-30.0)
var pitch := deg_to_rad(-50.0)
var distance := DEFAULT_DISTANCE
var camera: Camera3D
## Set while a conversation holds the camera (DialogPanel): player input is off.
var held := false
## Screen edge the mouse is scrolling at (-1/0/1 per axis).
var edge := Vector2i.ZERO
var _shakes: Array = []         # [t, duration, amp, decay], ticks
var _shake_ofs := 0.0           # lift applied to the camera now

# Modern state: `yaw` / `distance` are the goals there, these the shown values.
var _was_modern := false
var _goal := Vector3.ZERO       # look-at goal (x, z; y unused)
var _vel := Vector3.ZERO        # pan velocity, m/s
var _yaw_s := 0.0
var _yaw_vel := 0.0
var _dist_s := M_DEFAULT_DISTANCE
var _pitch_ofs := 0.0           # player tilt on top of the zoom curve, rad
var _pitch_ofs_s := 0.0
var _terrain_pitch := 0.0       # extra pitch keeping the eye line over hills, rad
var _ground_s := 0.0
var _ground_init := false
var _free := false              # follow mode let go (the player panned away)
var _follow_unit: Node3D
var _follow_last := Vector3.INF
var _follow_still := 0.0        # seconds the followed hero has stood
var _fade: CameraFade


func _ready() -> void:
	camera = Camera3D.new()
	camera.far = 2000.0
	camera.fov = MODERN_FOV if modern() else ORIGINAL_FOV
	add_child(camera)
	_was_modern = modern()
	if _was_modern:
		distance = M_DEFAULT_DISTANCE
		_snap()
	_apply()


## The modern camera is on (option camera_style 1) for the game's own rig.
func modern() -> bool:
	return GameData.option("camera_style") == 1 and get_parent() is Game


## camera_norm (key N, the original case 0xc) and the minimap's N
## button (case 5, tip 10303 "turn camera North"): (0)
## sets the camera's turn to angle 0 about the up axis and rebuilds the
## eye from the target, distance and pitch, which it keeps.
## Yaw 0 here looks along −Z = EI +Y, the top of the minimap.
## Modern: the camera turns there smoothly (the short way round).
func turn_north() -> void:
	yaw = 0.0
	_yaw_vel = 0.0
	_apply()


## Puts the look-at point on `p` at once (zone start, tests).
func focus(p: Vector3) -> void:
	position = p
	if modern():
		_goal = p
		_free = true
		_snap()
	_apply()


## Home (camera_track) and, modern only, a double-click on a party portrait:
## the modern camera glides to `p` and follows again; the original jumps.
func center_on(p: Vector3) -> void:
	if not modern():
		focus(p)
		return
	_goal = p
	_vel = Vector3.ZERO
	_free = false


## Puts the camera at `eye` looking at `target` (Godot space) until release().
func hold_view(eye: Vector3, target: Vector3) -> void:
	held = true
	if _fade:
		_fade.clear()
	if camera and not eye.is_equal_approx(target):
		camera.global_position = eye
		camera.look_at(target)


func release() -> void:
	if held:
		held = false
		_apply()


## Remake option cam_wasd (modern only): W / A / S / D pan the camera and do
## not reach their keyboard.ini actions (Game asks before dispatching a key).
func claims_key(e: InputEventKey) -> bool:
	return modern() and GameData.option("cam_wasd") == 1 \
		and e.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D] \
		and not (e.ctrl_pressed or e.alt_pressed or e.meta_pressed)


func _unhandled_input(e: InputEvent) -> void:
	if held:
		return
	if modern():
		_input_modern(e)
		return
	if e is InputEventMouseButton and e.pressed:
		var mp := _mouse_power()
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(MIN_DISTANCE, distance * pow(0.88, mp))
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(MAX_DISTANCE, distance * pow(1.14, mp))
		_apply()
	elif e is InputEventMouseMotion:
		if e.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			# Options "camera_reverse_x" / "camera_reverse_y" invert the rotation.
			var sx := -1.0 if GameData.option("camera_reverse_x") else 1.0
			var sy := -1.0 if GameData.option("camera_reverse_y") else 1.0
			var mp := _mouse_power()
			yaw -= e.relative.x * 0.006 * sx * mp
			pitch = clampf(pitch - e.relative.y * 0.006 * sy * mp, deg_to_rad(-MAX_PITCH), deg_to_rad(-MIN_PITCH))
			_apply()
		elif e.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_pan(Vector2(-e.relative.x, -e.relative.y) * distance * 0.002 * _mouse_power())


##  on the view's CameraRig (if any); `at` in EI metres.
static func shake_at(from: Node, at: Vector2, p2: float, amp: float, decay: float) -> void:
	var vp := from.get_viewport() if from and from.is_inside_tree() else null
	var cam := vp.get_camera_3d() if vp else null
	var rig := cam.get_parent() as CameraRig if cam else null
	if rig:
		rig.shake(at, p2, amp, decay)


func shake(at: Vector2, p2: float, amp: float, decay: float) -> void:
	# Camera, the look-at point (the eye, only with flags 0x60).
	var d := Vector2(position.x - at.x, -position.z - at.y).length()
	if d >= 20.0:
		return
	if d > 8.0:
		amp *= 1.0 - (d - 8.0) / 12.0
	_shakes.append([0.0, p2 * 30.0, amp, decay])


##  shake sum, added to the camera height. The modern
## camera adds _shake_ofs when it places the eye.
func _shake_tick(delta: float, add: bool) -> void:
	if _shakes.is_empty() and _shake_ofs == 0.0:
		return
	var dt := delta / 0.055
	var off := 0.0
	var i := 0
	while i < _shakes.size():
		var s: Array = _shakes[i]
		off += exp(-float(s[3]) * float(s[0])) * cos(PI * 0.5 * float(s[0]) * 0.26666668) * float(s[2])
		s[0] = float(s[0]) + dt
		if float(s[0]) >= float(s[1]):
			_shakes.remove_at(i)
		else:
			i += 1
	if held or camera == null:
		_shake_ofs = 0.0
		return
	if add:
		camera.position.y += off - _shake_ofs
	_shake_ofs = off


func _process(delta: float) -> void:
	var m := modern()
	if m != _was_modern:
		_switch_style(m)
	if m:
		_process_modern(delta)
		return
	_shake_tick(delta, true)
	if held:
		return
	# Camera keys through the key map (CInterface3D's camera controller,
	# built; key-down
	#  key-up, so rebinding
	# Options applies): camera_up / down = +1 / −1, camera_left / right
	#  = −1 / +1, camera_zoom_in / out = −1 / +1 (defaults UP, DOWN
	# LEFT, RIGHT, PGUP, PGDN). Without Ctrl and Alt (manager)
	# they pan (−0x20) × scroll power and zoom; with either held
	# left / right rotate × rotate power, up / down pitch × pitch power and
	# the zoom keys still zoom. All four powers are the one "power_kbd" slider.
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var v := Vector2(
		float(EIKeymap.held("camera_right")) - float(EIKeymap.held("camera_left")),
		float(EIKeymap.held("camera_down")) - float(EIKeymap.held("camera_up")))
	var mod := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT)
	if v != Vector2.ZERO:
		if not mod:
			_pan(v * delta * distance * _kbd_power() * 2.0)   # ×2: slider 25 = the remake's base speed
		else:
			# **Approx.**: the turn / tilt rates and their directions on screen
			# are the remake's (the original's camera setters
			#  are not traced to angles).
			yaw -= v.x * delta * 1.5 * _kbd_power() * 2.0
			pitch = clampf(pitch + v.y * delta * 1.0 * _kbd_power() * 2.0, deg_to_rad(-MAX_PITCH), deg_to_rad(-MIN_PITCH))
			_apply()
	# Edge scrolling (the original's scroll_u..scroll_ul cursors), see above.
	edge = _edge_scroll()
	if edge != Vector2i.ZERO:
		_pan(Vector2(edge) * delta * distance * 2.0)
	var z := float(EIKeymap.held("camera_zoom_out")) - float(EIKeymap.held("camera_zoom_in"))
	if z:
		distance = clampf(distance * (1.0 + z * delta * 1.5 * _kbd_power() * 2.0), MIN_DISTANCE, MAX_DISTANCE)
		_apply()


## The screen edge the pointer scrolls at (option scroll_border, pixels; 0 off).
func _edge_scroll() -> Vector2i:
	var out := Vector2i.ZERO
	var vp := get_viewport()
	var border := float(GameData.option("scroll_border"))
	if border >= 1.0 and DisplayServer.window_is_focused() and vp.gui_get_hovered_control() == null:
		var mp := vp.get_mouse_position()
		var sz := vp.get_visible_rect().size
		if Rect2(Vector2.ZERO, sz).has_point(mp):
			out.x = -1 if mp.x < border else 1 if mp.x >= sz.x - border else 0
			out.y = -1 if mp.y < border else 1 if mp.y >= sz.y - border else 0
	return out


## Keyboard power, settings = slider / 50 (0.5 by default).
func _kbd_power() -> float:
	return GameData.option("power_kbd") / 50.0


## Mouse power, settings = slider / 50 (1.0 by default).
func _mouse_power() -> float:
	return GameData.option("power_mouse") / 50.0


func _pan(v: Vector2) -> void:
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	position += right * v.x - fwd * v.y
	_apply()


func _apply() -> void:
	if held:
		return
	if modern():
		_apply_modern()
		return
	if camera:
		camera.fov = ORIGINAL_FOV
	if terrain:
		var s := terrain.size_ei()
		position.x = clampf(position.x, 0.0, s.x)
		position.z = clampf(position.z, -s.y, 0.0)
		position.y = terrain.height_at(position.x, -position.z)
	if camera:
		var b := Basis.from_euler(Vector3(pitch, yaw, 0))
		camera.transform = Transform3D(b, b * Vector3(0, 0, distance) + Vector3(0, _shake_ofs, 0))


# ------------------------------------------------------------------ modern

## Option switch between the styles: the new one starts from the view shown.
func _switch_style(m: bool) -> void:
	_was_modern = m
	if m:
		distance = clampf(distance, M_MIN_DISTANCE, _max_distance())
		_goal = position
		_snap()
	else:
		distance = clampf(_dist_s, MIN_DISTANCE, MAX_DISTANCE)
		yaw = _yaw_s
		pitch = clampf(-_modern_pitch(), deg_to_rad(-MAX_PITCH), deg_to_rad(-MIN_PITCH))
		if camera:
			camera.transform = Transform3D.IDENTITY
		if _fade:
			_fade.clear()
	_apply()


## The shown values jump to the goals (no easing).
func _snap() -> void:
	_vel = Vector3.ZERO
	_yaw_vel = 0.0
	_yaw_s = yaw
	distance = clampf(distance, M_MIN_DISTANCE, _max_distance())
	_dist_s = distance
	_pitch_ofs_s = _pitch_ofs
	position.x = _goal.x
	position.z = _goal.z
	_ground_init = false
	_terrain_pitch = _needed_terrain_pitch()


## A speed option (slider 0..100, 50 = ×1) as a factor ×0.25 .. ×4.
static func speed_factor(opt: String) -> float:
	return pow(2.0, (GameData.option(opt) - 50.0) / 25.0)


func _max_distance() -> float:
	return M_MAX_DISTANCE_FAR if GameData.option("gfx_far_view") == 1 else M_MAX_DISTANCE_NEAR


## 0 at the closest zoom, 1 at the farthest (logarithmic, as the wheel steps).
func _zoom_t(d: float) -> float:
	return clampf(log(d / M_MIN_DISTANCE) / log(_max_distance() / M_MIN_DISTANCE), 0.0, 1.0)


## Pitch below the horizon (rad, positive) from the zoom curve, the player's
## tilt and the terrain lift.
func _modern_pitch() -> float:
	var t := _zoom_t(_dist_s)
	var p := deg_to_rad(lerpf(M_PITCH_CLOSE, M_PITCH_FAR, t)) + _pitch_ofs_s
	p = clampf(p, deg_to_rad(5.0), deg_to_rad(84.0))
	return minf(p + _terrain_pitch, deg_to_rad(86.0))


func _input_modern(e: InputEvent) -> void:
	var sx := -1.0 if GameData.option("camera_reverse_x") else 1.0
	var sy := -1.0 if GameData.option("camera_reverse_y") else 1.0
	if e is InputEventMouseButton and e.pressed:
		var zs := speed_factor("cam_zoom_speed")
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(M_MIN_DISTANCE, distance * pow(0.85, zs * maxf(e.factor, 1.0)))
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(_max_distance(), distance * pow(1.0 / 0.85, zs * maxf(e.factor, 1.0)))
	elif e is InputEventMouseMotion and e.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT):
		if e.button_mask & MOUSE_BUTTON_MASK_MIDDLE and e.shift_pressed:
			# Shift + middle drag: grab the ground and drag it.
			_free = true
			_goal += _screen_to_ground(Vector2(-e.relative.x, -e.relative.y) * _dist_s * 0.0018)
			_vel = Vector3.ZERO
			return
		var rs := speed_factor("cam_rotate_speed")
		yaw -= e.relative.x * 0.006 * sx * rs
		_pitch_ofs = clampf(_pitch_ofs + e.relative.y * 0.004 * sy * rs,
			deg_to_rad(-M_PITCH_OFS), deg_to_rad(M_PITCH_OFS))


func _screen_to_ground(v: Vector2) -> Vector3:
	var fwd := Vector3(-sin(_yaw_s), 0, -cos(_yaw_s))
	var right := Vector3(cos(_yaw_s), 0, -sin(_yaw_s))
	return right * v.x - fwd * v.y


## Rate-independent easing factor for a rate in 1/s.
static func _ease(rate: float, dt: float) -> float:
	return 1.0 - exp(-rate * dt)


func _process_modern(game_dt: float) -> void:
	# Real time: the camera moves at the same speed when the game is paused
	# or accelerated (Engine.time_scale).
	var dt := minf(game_dt / maxf(Engine.time_scale, 0.001), 0.1)
	_shake_tick(game_dt, false)
	if held:
		return
	var g := get_parent() as Game
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	var mod := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT)
	var v := Vector2.ZERO
	var turn := 0.0
	var tilt := 0.0
	var zoom := 0.0
	if not typing:
		var k := Vector2(
			float(EIKeymap.held("camera_right")) - float(EIKeymap.held("camera_left")),
			float(EIKeymap.held("camera_down")) - float(EIKeymap.held("camera_up")))
		if mod:
			turn = k.x
			tilt = k.y
		else:
			v = k
			if GameData.option("cam_wasd") == 1:
				v += Vector2(
					float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
					float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		turn += float(EIKeymap.held("camera_rotate_right")) - float(EIKeymap.held("camera_rotate_left"))
		zoom = float(EIKeymap.held("camera_zoom_out")) - float(EIKeymap.held("camera_zoom_in"))
	edge = _edge_scroll()
	v += Vector2(edge)
	if v.length() > 1.0:
		v = v.normalized()
	# Pan: velocity eases toward the input (quick start, a short glide out).
	var ps := speed_factor("cam_pan_speed")
	var want := _screen_to_ground(v) * (5.0 + _dist_s * 0.9) * ps
	_vel = _vel.lerp(want, _ease(9.0 if v != Vector2.ZERO else 6.0, dt))
	if v != Vector2.ZERO:
		_free = true
	if _vel.length_squared() > 1e-4:
		_goal += _vel * dt
	else:
		_vel = Vector3.ZERO
	# Turn: keys accelerate a turn rate; drags set the goal directly.
	var rs := speed_factor("cam_rotate_speed")
	var sx := -1.0 if GameData.option("camera_reverse_x") else 1.0
	_yaw_vel = lerpf(_yaw_vel, -turn * 2.0 * rs * sx, _ease(8.0, dt))
	if absf(_yaw_vel) > 1e-4:
		yaw += _yaw_vel * dt
	if tilt:
		var sy := -1.0 if GameData.option("camera_reverse_y") else 1.0
		_pitch_ofs = clampf(_pitch_ofs + tilt * dt * 0.8 * rs * sy,
			deg_to_rad(-M_PITCH_OFS), deg_to_rad(M_PITCH_OFS))
	if zoom:
		distance *= 1.0 + zoom * dt * 1.6 * speed_factor("cam_zoom_speed")
	distance = clampf(distance, M_MIN_DISTANCE, _max_distance())
	_follow(g, dt)
	if terrain:
		var s := terrain.size_ei()
		_goal.x = clampf(_goal.x, 0.0, s.x)
		_goal.z = clampf(_goal.z, -s.y, 0.0)
	# Ease the shown values toward the goals.
	var k := _ease(10.0, dt)
	position.x = lerpf(position.x, _goal.x, k)
	position.z = lerpf(position.z, _goal.z, k)
	_yaw_s = _unwrap(_yaw_s, yaw)
	_yaw_s = lerpf(_yaw_s, yaw, _ease(12.0, dt))
	_dist_s = exp(lerpf(log(_dist_s), log(distance), _ease(9.0, dt)))
	_pitch_ofs_s = lerpf(_pitch_ofs_s, _pitch_ofs, _ease(10.0, dt))
	# Terrain: the look-at height eases over bumps; the pitch rises quickly
	# when a hill would cut the eye line and settles back slowly.
	var need := _needed_terrain_pitch()
	_terrain_pitch = lerpf(_terrain_pitch, need, _ease(10.0 if need > _terrain_pitch else 2.0, dt))
	_update_ground(g, dt)
	_apply_modern()
	if g and GameData.option("cam_see_through") == 1:
		if _fade == null:
			_fade = CameraFade.new()
		_fade.update(g, camera.global_position, dt)
	elif _fade:
		_fade.clear()


## `a` moved by whole turns to within π of `ref`.
static func _unwrap(a: float, ref: float) -> float:
	return ref + wrapf(a - ref, -PI, PI)


## Follow mode (option cam_follow): the goal tracks the first selected hero;
## panning lets go (_free) until the hero next starts moving (or another hero
## is selected), when the camera glides back.
func _follow(g: Game, dt: float) -> void:
	var u: Node3D = null
	if g and not g.selected.is_empty() and is_instance_valid(g.selected[0]) \
			and not g.selected[0].dead and g.selected[0].world == g.world:
		u = g.selected[0]
	if u != _follow_unit:
		# Another hero selected (not the zone's first): glide to it.
		if u and is_instance_valid(_follow_unit) and GameData.option("cam_follow") == 1:
			_free = false
		_follow_unit = u
		_follow_last = Vector3.INF
		_follow_still = 0.0
		return
	if u == null:
		return
	var p := u.global_position
	if _follow_last != Vector3.INF:
		var step := Vector2(p.x - _follow_last.x, p.z - _follow_last.z).length()
		if step > 0.01:
			# Starts moving after standing a moment: snap back.
			if _follow_still > 0.25:
				_free = false
			_follow_still = 0.0
		else:
			_follow_still += dt
	_follow_last = p
	if GameData.option("cam_follow") == 1 and not _free:
		_goal.x = p.x
		_goal.z = p.z


## Look-at height: the ground averaged over a few metres (or the followed
## hero's own height, e.g. on a bridge), eased; plus a lift that shrinks with
## the zoom (close = chest height).
func _update_ground(g: Game, dt: float) -> void:
	if terrain == null:
		return
	var x := position.x
	var y := -position.z
	var h := terrain.height_at(x, y) * 0.4
	for o: Vector2 in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
		h += terrain.height_at(x + o.x, y + o.y) * 0.15
	if _follow_unit and is_instance_valid(_follow_unit):
		var p := _follow_unit.global_position
		if Vector2(p.x - position.x, p.z - position.z).length() < 4.0:
			h = maxf(h, p.y)
	if not _ground_init:
		_ground_init = true
		_ground_s = h
	_ground_s = lerpf(_ground_s, h, _ease(6.0, dt))
	position.y = _ground_s + lerpf(M_LIFT_CLOSE, M_LIFT_FAR, _zoom_t(_dist_s))


## Extra pitch (rad) the eye line from the look-at point needs to stay
## M_CLEARANCE above the terrain (hills behind the camera, the hero in a dip).
func _needed_terrain_pitch() -> float:
	if terrain == null:
		return 0.0
	var base := _terrain_pitch
	_terrain_pitch = 0.0
	var p0 := _modern_pitch()
	_terrain_pitch = base
	var ty := position.y if _ground_init else terrain.height_at(position.x, -position.z) + M_LIFT_CLOSE
	var dir := Vector2(sin(_yaw_s), cos(_yaw_s))   # ground direction look-at → eye (Godot x, z)
	var extra := 0.0
	while extra < deg_to_rad(60.0):
		var p := minf(p0 + extra, deg_to_rad(86.0))
		var ok := true
		for i in range(1, 9):
			var f := float(i) / 8.0
			var r := _dist_s * f * cos(p)
			var gx := position.x + dir.x * r
			var gz := position.z + dir.y * r
			if ty + _dist_s * f * sin(p) < terrain.height_at(gx, -gz) + M_CLEARANCE:
				ok = false
				break
		if ok:
			break
		extra += deg_to_rad(3.0)
	return extra


func _apply_modern() -> void:
	if camera == null:
		return
	camera.fov = MODERN_FOV
	if terrain:
		var s := terrain.size_ei()
		position.x = clampf(position.x, 0.0, s.x)
		position.z = clampf(position.z, -s.y, 0.0)
		if not _ground_init:
			position.y = terrain.height_at(position.x, -position.z) + lerpf(M_LIFT_CLOSE, M_LIFT_FAR, _zoom_t(_dist_s))
	pitch = -_modern_pitch()
	var b := Basis.from_euler(Vector3(pitch, _yaw_s, 0))
	var eye := global_position + b * Vector3(0, 0, _dist_s)
	if terrain:
		# Never under the ground at the eye itself.
		var h := terrain.height_at(eye.x, -eye.z) + 1.0
		if eye.y < h:
			eye.y = h
	eye.y += _shake_ofs
	var to := global_position - eye
	if to.length_squared() < 1e-6:
		return
	camera.global_transform = Transform3D(Basis.looking_at(to, Vector3.UP), eye)
