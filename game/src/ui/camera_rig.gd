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
## The original's camera eases per 55 ms tick: rates
## 1/3 (yaw, pitch, zoom) and 0.1333 (pan), its only writer
## key targets 0.5 a tick at the defaults (see docs, "Camera speeds").
## The original style eases its key / edge velocities that way (_ease_v): the
## pan ramps up and down (τ ≈ 0.4 s), turn and tilt start at once and stop
## eased, the zoom eases both ways (τ ≈ 140 ms). The wheel and mouse drags act
## at once (**Approx.**: when the original's controller clears those targets is
## not traced, and the drag rates are the remake's). Key / edge speeds are the
## original's (2026-10-02): per tick, pan keyboard power (0.5) m, edges 1 m, both
## × f = (d − 4) / 108 + 0.2; zoom keys 0.5 m; Ctrl / Alt turn 0.5 rad and tilt
## 0.5 × 50 rad (it reaches a pitch limit at once); the wheel × 1.05 a notch.
## Distance 4.. 80 m (3.. 4 springs back), pitch 20°.. 80°.
## Camera shake (list camera): (pos, p2, amp, decay) adds
## {t 0, duration p2 · 30 ticks, amp, decay} when the camera's look-at point
## is within 20 m of pos (amp × (1 − (d − 8) / 12) beyond 8 m); each frame
##  lifts the camera by Σ exp(−decay·t) · cos(π/2 · t · 0.26666668)
## · amp, t in 55 ms ticks, and drops an entry once t ≥ duration. Callers:
## LightningBlast 0x2030 (size, 2, 0.25) and heavy monsters' steps (5,
## prototype detonation, 0.25). No option gates it.
##
## **Modern** (index 1, the default; remake-only, not in the original), after
## Divinity: Original Sin 2 / Baldur's Gate 3: responsive panning (camera
## keys, optional WASD layout, screen edges), smooth wheel / key zoom whose pitch
## follows the zoom (close = low and cinematic, far = nearly top-down), smooth
## turning (middle drag; Alt + middle or right drag also tilts; Shift + middle
## drags the ground), bindable turn keys (Delete / End, Q / E in WASD mode),
## optional hero follow that stays detached after panning until Home, F1–F3 or
## a portrait double-click glides to the hero,
## a terrain-aware height and pitch (never inside a hill, the hero never behind
## one) and fading of the map objects between the camera and the party
## (CameraFade). Speeds: options cam_pan_speed / cam_rotate_speed /
## cam_zoom_speed; camera_reverse_x / y and scroll_border apply to both styles.
## Only the in-game camera (under Game) uses it; the map viewer keeps the
## original camera. Per player; nothing of it is networked.

## Registry defaults of the settings object (constructor
## read): CameraDefaultDistanceToCarrier 30
## CameraMin / MaxDistanceToCarrier 4 / 100
## CameraMin / MaxLimitDistanceToCarrier 3 / 80
## CameraDefaultMin / MaxPitch 20° / 80°; the camera tick
##  applies them to its distance and pitch (radians
## π/180 × the degrees). **Approx.**: the default pitch (50°) is the remake's.
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
const MIN_DISTANCE := 4.0     # CameraMinDistanceToCarrier, soft
const MAX_DISTANCE := 80.0    # CameraMaxLimitDistanceToCarrier, hard
const MIN_LIMIT := 3.0        # CameraMinLimitDistanceToCarrier, hard
const SOFT_MAX := 100.0       # CameraMaxDistanceToCarrier
const MIN_PITCH := 20.0
const MAX_PITCH := 80.0
## Village screen (camera flag 0x200, set, cleared):
## pitch limits settings = 30° / 60°; its
## distance limits.. equal the field's 4 / 100 / 3 / 80.
const VILLAGE_MIN_PITCH := 30.0
const VILLAGE_MAX_PITCH := 60.0

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
var _terrain_pitch_v := 0.0     # its rate (rad/s), see _smooth_damp
var _ground_s := 0.0
var _ground_v := 0.0
var _ground_init := false
var _free := false              # follow mode let go (the player panned away)
var _follow_unit: Node3D
var _pointer_inside := true   # NOTIFICATION_WM_MOUSE_ENTER / EXIT
var _drag_button := 0          # only a gesture begun outside the GUI owns the camera
var _window_focused := true
var _fade: CameraFade
## Gamepad right stick (PadField, real-time values −1..1, cleared each frame
## by it): turn and zoom; `pad_no_edge` stops edge scrolling at a resting,
## hidden mouse pointer while the pad drives.
var pad_turn := 0.0
var pad_zoom := 0.0
var pad_no_edge := false
## Original style: the original camera's velocities, eased per tick.
const TICK := 0.055
const PAN_RATE := 0.1333    # camera
const TURN_RATE := 1.0 / 3.0   # yaw, pitch, zoom
var _pan_v := Vector2.ZERO
var _yaw_v := 0.0
var _pitch_v := 0.0
var _zoom_v := 0.0


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


## The view for a save (the original camera record: look-
## .., turn, pitch, distance, velocities).
## The velocities are not kept: a loaded view stands still. The modern style
## (remake-only) keeps its equivalent: the look-at goal, yaw and zoom goals,
## the player's tilt and whether follow mode had let go (`free`).
func pose() -> Dictionary:
	var m := modern()
	var at := _goal if m else position
	var p := {"at": [at.x, position.y, at.z], "yaw": yaw, "pitch": -_modern_pitch() if m else pitch,
		"distance": distance, "style": 1 if m else 0}
	if m:
		p["tilt"] = _pitch_ofs
		p["free"] = _free
	return p


## A saved view back (on load; the original then does not refocus).
## Modern: the view is shown at once; without a saved `free` (an original-
## style save) follow mode stays let go, so the saved view is kept.
func set_pose(p: Dictionary) -> bool:
	var at: Array = p.get("at", [])
	if at.size() != 3:
		return false
	position = clamp_look_at(Vector3(float(at[0]), float(at[1]), float(at[2])))
	yaw = float(p.get("yaw", yaw))
	_stop_velocities()
	if modern():
		_goal = position
		distance = float(p.get("distance", distance))
		_pitch_ofs = clampf(float(p.get("tilt", 0.0)), deg_to_rad(-M_PITCH_OFS), deg_to_rad(M_PITCH_OFS))
		_free = bool(p.get("free", true))
		_follow_unit = null   # resolve the selected hero again after loading
		_snap()
	else:
		pitch = clampf(float(p.get("pitch", pitch)), -_pitch_max(), -_pitch_min())
		distance = clampf(float(p.get("distance", distance)), MIN_DISTANCE, MAX_DISTANCE)
	_apply()
	return true


## The current zone's record when the rig shows it (Game.world), else {}.
func _zone() -> Dictionary:
	var g := get_parent() as Game
	if g and g.world and g.world.terrain == terrain:
		return g.world.zone
	return {}


## A village (map.txt type "brief"): the original's village screen.
func in_village() -> bool:
	return String(_zone().get("type", "")) == "brief"


## Pitch limits below the horizon (rad): field 20° .. 80°, village 30° .. 60°.
func _pitch_min() -> float:
	return deg_to_rad(VILLAGE_MIN_PITCH if in_village() else MIN_PITCH)


func _pitch_max() -> float:
	return deg_to_rad(VILLAGE_MAX_PITCH if in_village() else MAX_PITCH)


## The look-at limit of the original's camera, applied to every way
## the look-at moves here (keys, edges, drags, touch, minimap, Home, follow,
## loads, both styles; not the scripted / dialogue views of hold_view). It
## limits the look-at point (the view centre), not the view:
## (pan and tracking branches) and the move setters
## clamp (EI x / y, metres) each to 0.. map − 1
## (sectors × 32) on its own axis, so at a side or a corner the
## camera slides along it; distance and pitch play no part. Then, with camera
## flag 0x100 (only called by the village screen
## for a zone whose map.txt record has ".restrict x y r", record..
## read), a look-at farther than r from (x, y) is put back
## that circle along the line to its centre (it slides round the circle). The
## village screen's teardown clears flags 0x100 / 0x200.
## `p` is in Godot space (EI x, ·, −EI y); y is kept.
func clamp_look_at(p: Vector3) -> Vector3:
	if terrain == null:
		return p
	var s := terrain.size_ei()
	var x := clampf(p.x, 0.0, s.x - 1.0)
	var y := clampf(-p.z, 0.0, s.y - 1.0)
	var r = _zone().get("restrict", null) if in_village() else null
	if r is Vector3 and r.z > 0.0:
		var d := Vector2(x - r.x, y - r.y)
		if d.length_squared() > r.z * r.z:
			d = d.normalized() * r.z
			x = r.x + d.x
			y = r.y + d.y
	return Vector3(x, p.y, -y)


## Puts the look-at point on `p` at once (zone start, tests).
func focus(p: Vector3) -> void:
	position = clamp_look_at(p)
	p = position
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
	_goal = clamp_look_at(p)
	_vel = Vector3.ZERO
	_free = false


## Puts the camera at `eye` looking at `target` (Godot space) until release().
func hold_view(eye: Vector3, target: Vector3) -> void:
	_suspend_motion()
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


## keyboard.ini camera1–4 (F9–F12; the in-game camera's keys):
## a plain key recalls slot i (: distance and pitch
## only — the stored turn is not applied — and the pan / rotate / pitch / zoom
## velocities stopped), Ctrl or Alt stores the view in it (:
## distance, turn, pitch). Start values: copies
## the settings object's four "CameraShortcut %d" entries (0x18 each:
## Distance, AxisX / Y / Z, Angle, Pitch) whose defaults are
## Distance = CameraDefaultDistanceToCarrier 30, axis (0, 0, 1), angle 0,
## Pitch 45.0 — copied raw, which the camera reads as radians
## (rotates by −(π/2 + pitch)), so an unstored slot shows the
## pitch 45 rad ≡ 58.31° below the horizon (the clamp to Min / MaxPitch only
## runs while the pitch is moving). The slots are not part of a save: the
## camera save chunk holds only slots 4–7 (the
## internal ones, 6 / 7 filled before saving); after a store
## copies slots 0–3 back to the settings and writes them to the
## registry ("Camera Settings") at exit. Remake: user://camera_shortcuts.cfg,
## written on each store. Modern style (remake-only): the zoom goal and the
## player's tilt, defaults 30 m and no tilt.
const SHORTCUTS_PATH := "user://camera_shortcuts.cfg"
const SHORTCUT_PITCH_RAW := 45.0
var _view_slots := {}
var _view_slots_loaded := false

func _load_view_slots() -> void:
	_view_slots_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SHORTCUTS_PATH) != OK:
		return
	for key in cfg.get_section_keys("slots") if cfg.has_section("slots") else []:
		var v = cfg.get_value("slots", key)
		if v is Array and v.size() == 2:
			_view_slots[key] = [float(v[0]), float(v[1])]


func view_slot(i: int, store: bool) -> void:
	if held:
		return
	if not _view_slots_loaded:
		_load_view_slots()
	var key := ("modern%d" if modern() else "orig%d") % i
	if store:
		_view_slots[key] = [distance, _pitch_ofs if modern() else pitch]
		var cfg := ConfigFile.new()
		for k in _view_slots:
			cfg.set_value("slots", k, _view_slots[k])
		cfg.save(SHORTCUTS_PATH)
		return
	var slot: Array = _view_slots.get(key, [DEFAULT_DISTANCE,
		0.0 if modern() else -fposmod(SHORTCUT_PITCH_RAW, TAU)])
	distance = slot[0]
	if modern():
		_pitch_ofs = slot[1]
		_vel = Vector3.ZERO
		_yaw_vel = 0.0
	else:
		pitch = slot[1]
		_pan_v = Vector2.ZERO
		_yaw_v = 0.0
		_pitch_v = 0.0
		_zoom_v = 0.0
	_apply()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_window_focused = false
		_suspend_motion()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_window_focused = true
	elif what == NOTIFICATION_WM_MOUSE_EXIT:
		_pointer_inside = false
	elif what == NOTIFICATION_WM_MOUSE_ENTER:
		_pointer_inside = true


func _input_blocked() -> bool:
	if held or not _window_focused:
		return true
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return true
	var g := get_parent() as Game
	return g != null and g.hud != null and g.hud.blocks_camera()


## A gesture keeps its ownership across UI boundaries. Releases are seen
## even when the GUI consumes them; a drag begun on a panel is never ours.
func _input(e: InputEvent) -> void:
	if not modern() or _drag_button == 0:
		return
	if _input_blocked():
		_suspend_motion()
		return
	if e is InputEventMouseButton and not e.pressed and e.button_index == _drag_button:
		_drag_button = 0
	elif e is InputEventMouseMotion:
		if e.button_mask & (1 << (_drag_button - 1)):
			_input_modern(e)
			get_viewport().set_input_as_handled()
		else:
			_drag_button = 0


func _unhandled_input(e: InputEvent) -> void:
	if _input_blocked():
		return
	if modern():
		_input_modern(e)
		return
	if e is InputEventMouseButton and e.pressed:
		var mp := _mouse_power()
		# distance × 1.05^(−notches × mouse
		# zoom power × speed), clamped to 4 .. 100 (then 80 by the tick).
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance * pow(1.05, -mp), MIN_DISTANCE, MAX_DISTANCE)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance * pow(1.05, mp), MIN_DISTANCE, MAX_DISTANCE)
		_apply()
	elif e is InputEventMouseMotion:
		if e.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			# Options "camera_reverse_x" / "camera_reverse_y" invert the rotation.
			var sx := -1.0 if GameData.option("camera_reverse_x") else 1.0
			var sy := -1.0 if GameData.option("camera_reverse_y") else 1.0
			var mp := _mouse_power()
			yaw -= e.relative.x * 0.006 * sx * mp
			pitch = clampf(pitch - e.relative.y * 0.006 * sy * mp, -_pitch_max(), -_pitch_min())
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
	if _input_blocked():
		_stop_velocities()
		edge = Vector2i.ZERO
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
		_stop_velocities()
		return
	var v := Vector2(
		float(EIKeymap.held("camera_right", 0)) - float(EIKeymap.held("camera_left", 0)),
		float(EIKeymap.held("camera_down", 0)) - float(EIKeymap.held("camera_up", 0)))
	var mod := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT)
	# The keys and the screen edges set target velocities; eases
	# the camera's velocities to them per 55 ms tick (see the header) and moves
	# by them. The original's targets are per tick (keyboard power × speed 1.0):
	# pan in metres (× the zoom factor below), yaw in radians, pitch in
	# radians × 50 (key-down), zoom in metres; here per second.
	var pan_t := Vector2.ZERO
	var yaw_t := 0.0
	var pitch_t := 0.0
	var kp := _kbd_power()
	if v != Vector2.ZERO:
		if not mod:
			pan_t = v * kp / TICK
		else:
			yaw_t = -v.x * kp / TICK
			pitch_t = v.y * kp * 50.0 / TICK
	# Edge scrolling: ±1 m a tick on top of the keys.
	edge = _edge_scroll()
	if edge != Vector2i.ZERO:
		pan_t += Vector2(edge) / TICK
	var zoom_t := (float(EIKeymap.held("camera_zoom_out", 0)) - float(EIKeymap.held("camera_zoom_in", 0)) + pad_zoom) \
		* kp / TICK
	if pad_turn != 0.0:   # gamepad right stick (PadField, camera_reverse_x applied there)
		yaw_t -= pad_turn * kp / TICK
	var ticks := delta / TICK
	_pan_v = Vector2(_ease_v(_pan_v.x, pan_t.x, PAN_RATE, ticks, false), _ease_v(_pan_v.y, pan_t.y, PAN_RATE, ticks, false))
	_yaw_v = _ease_v(_yaw_v, yaw_t, TURN_RATE, ticks, true)
	_pitch_v = _ease_v(_pitch_v, pitch_t, TURN_RATE, ticks, true)
	_zoom_v = _ease_v(_zoom_v, zoom_t, TURN_RATE, ticks, false)
	if _pan_v != Vector2.ZERO:
		_pan(_pan_v * pan_factor() * delta)
	if _yaw_v != 0.0 or _pitch_v != 0.0 or _zoom_v != 0.0 or distance < MIN_DISTANCE:
		yaw += _yaw_v * delta
		pitch = clampf(pitch + _pitch_v * delta, -_pitch_max(), -_pitch_min())
		distance = _limit_distance(distance + _zoom_v * delta, ticks)
		_apply()


## the pan moves the look-at point by the velocity × f
## f = (distance − 4) / ((100 − 4) × 1.125) + 0.2 — slow close, faster far.
func pan_factor() -> float:
	return (distance - MIN_DISTANCE) / ((SOFT_MAX - MIN_DISTANCE) * 1.125) + 0.2


##  distance limits: below 3 m → 3; from 4 m , above 80 → 80
## (the soft maximum 100 lies beyond it); between 3 and 4 it is pulled back
## toward 4 by 1.1 × ticks × (4 − d) / (4 − 3).
static func _limit_distance(d: float, ticks: float) -> float:
	if d < MIN_LIMIT:
		return MIN_LIMIT
	if d >= MIN_DISTANCE:
		return minf(d, MAX_DISTANCE)
	return minf(MIN_DISTANCE, d + (MIN_DISTANCE - d) * ticks * 1.1 / (MIN_DISTANCE - MIN_LIMIT))


func _stop_velocities() -> void:
	_pan_v = Vector2.ZERO
	_yaw_v = 0.0
	_pitch_v = 0.0
	_zoom_v = 0.0
	_vel = Vector3.ZERO
	_yaw_vel = 0.0


func _suspend_motion() -> void:
	_stop_velocities()
	_drag_button = 0
	edge = Vector2i.ZERO
	if _was_modern:
		_goal = position
		yaw = _yaw_s
		distance = _dist_s
		_pitch_ofs = _pitch_ofs_s


##  easing of one camera velocity toward its target:
## v += (target − v) · rate · dt, dt in 55 ms ticks, snapped to the target
## when the step would overshoot or the gap is < 0.001. `instant_up`: the yaw
## pitch setters set v = target at once when
## |target| > |v| (instant start, eased stop).
static func _ease_v(v: float, t: float, rate: float, ticks: float, instant_up: bool) -> float:
	if instant_up and absf(t) > absf(v):
		return t
	var k := rate * ticks
	if k >= 1.0 or absf(t - v) < 0.001:
		return t
	return v + (t - v) * k


## The screen edge the pointer scrolls at (option scroll_border, pixels; 0 off).
func _edge_scroll() -> Vector2i:
	var out := Vector2i.ZERO
	if TouchInput.enabled or pad_no_edge:
		return out
	if _drag_button != 0 or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return out
	var vp := get_viewport()
	var border := float(GameData.option("scroll_border"))
	# A pointer that left the window (a browser page, or a desktop window
	# without "Keep mouse in window") keeps its last position: no scrolling.
	if border >= 1.0 and _pointer_inside and DisplayServer.window_is_focused() and vp.gui_get_hovered_control() == null:
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


func touch_gesture(before: PackedVector2Array, after: PackedVector2Array) -> void:
	if _input_blocked() or before.size() != 2 or after.size() != 2:
		return
	var old_mid := (before[0] + before[1]) * 0.5
	var new_mid := (after[0] + after[1]) * 0.5
	var old_vector := before[1] - before[0]
	var new_vector := after[1] - after[0]
	var plane := Plane(Vector3.UP, global_position.y)
	var old_ground: Variant = plane.intersects_ray(camera.project_ray_origin(old_mid), camera.project_ray_normal(old_mid))
	var new_ground: Variant = plane.intersects_ray(camera.project_ray_origin(new_mid), camera.project_ray_normal(new_mid))
	_stop_velocities()
	if modern():
		_detach()
	if old_ground is Vector3 and new_ground is Vector3:
		position += old_ground - new_ground
		_goal = position
	if old_vector.length() > 16.0 and new_vector.length() > 16.0:
		distance = clampf(distance * old_vector.length() / new_vector.length(), M_MIN_DISTANCE if modern() else MIN_DISTANCE, _max_distance() if modern() else MAX_DISTANCE)
		yaw -= old_vector.angle_to(new_vector)
		_yaw_s = yaw
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
		# the look-at limit (clamp_look_at).
		position = clamp_look_at(position)
		position.y = terrain.height_at(position.x, -position.z)
	if camera:
		var b := Basis.from_euler(Vector3(pitch, yaw, 0))
		camera.transform = Transform3D(b, b * Vector3(0, 0, distance) + Vector3(0, _shake_ofs, 0))


# ------------------------------------------------------------------ modern

## Option switch between the styles: the new one starts from the view shown.
func _switch_style(m: bool) -> void:
	_stop_velocities()
	_drag_button = 0
	_was_modern = m
	if m:
		distance = clampf(distance, M_MIN_DISTANCE, _max_distance())
		_goal = position
		_snap()
	else:
		distance = clampf(_dist_s, MIN_DISTANCE, MAX_DISTANCE)
		yaw = _yaw_s
		pitch = clampf(-_modern_pitch(), -_pitch_max(), -_pitch_min())
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
	_ground_v = 0.0
	_terrain_pitch = _needed_terrain_pitch()
	_terrain_pitch_v = 0.0


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
		if e.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_drag_button = e.button_index
			_yaw_vel = 0.0
			# Right click still reaches the game's cancel-target action.
			if e.button_index == MOUSE_BUTTON_MIDDLE:
				get_viewport().set_input_as_handled()
			return
		var zs := speed_factor("cam_zoom_speed")
		var amount: float = e.factor if e.factor > 0.0 else 1.0
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(M_MIN_DISTANCE, distance * pow(0.85, zs * amount))
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(_max_distance(), distance * pow(1.0 / 0.85, zs * amount))
		else:
			return
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion and _drag_button != 0:
		if _drag_button == MOUSE_BUTTON_MIDDLE and e.shift_pressed:
			# Project onto the look-at plane: the grabbed point stays under
			# the pointer at any resolution, zoom, pitch and heading.
			var plane := Plane(Vector3.UP, global_position.y)
			var before = plane.intersects_ray(camera.project_ray_origin(e.position - e.relative),
				camera.project_ray_normal(e.position - e.relative))
			var after = plane.intersects_ray(camera.project_ray_origin(e.position),
				camera.project_ray_normal(e.position))
			if before is Vector3 and after is Vector3:
				_detach()
				_goal += before - after
				position.x = _goal.x
				position.z = _goal.z
				_vel = Vector3.ZERO
				_apply_modern()
			return
		var rs := speed_factor("cam_rotate_speed")
		yaw -= e.relative.x * 0.006 * sx * rs
		_yaw_s = yaw   # mouse rotation is direct; keyboard / recenter are eased
		_yaw_vel = 0.0
		# Normal middle drag only orbits: no accidental pitch changes.
		if e.alt_pressed or _drag_button == MOUSE_BUTTON_RIGHT:
			_pitch_ofs = clampf(_pitch_ofs + e.relative.y * 0.004 * sy * rs,
				deg_to_rad(-M_PITCH_OFS), deg_to_rad(M_PITCH_OFS))
			_pitch_ofs_s = _pitch_ofs
		_apply_modern()


func _detach() -> void:
	# Cancel any unfinished recenter glide before taking manual control.
	if not _free or _vel == Vector3.ZERO:
		_goal = position
	_free = true


func _screen_to_ground(v: Vector2) -> Vector3:
	var fwd := Vector3(-sin(_yaw_s), 0, -cos(_yaw_s))
	var right := Vector3(cos(_yaw_s), 0, -sin(_yaw_s))
	return right * v.x - fwd * v.y


## Rate-independent easing factor for a rate in 1/s.
static func _ease(rate: float, dt: float) -> float:
	return 1.0 - exp(-rate * dt)


## A critically damped spring toward `target` (smooth time `t` s), stable at
## any dt: [value, rate]. Unlike _ease its rate never jumps when the target
## does, so a stepping target (the ground under a strafing view, the terrain
## pitch) still moves the picture evenly frame to frame.
static func _smooth_damp(cur: float, target: float, vel: float, t: float, dt: float) -> Vector2:
	var omega := 2.0 / maxf(t, 0.0001)
	var x := omega * dt
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := cur - target
	var temp := (vel + omega * change) * dt
	return Vector2(target + (change + temp) * e, (vel - omega * temp) * e)


func _process_modern(game_dt: float) -> void:
	# Real time: the camera moves at the same speed when the game is paused
	# or accelerated (Engine.time_scale).
	var dt := minf(game_dt / maxf(Engine.time_scale, 0.001), 0.1)
	_shake_tick(game_dt, false)
	if _input_blocked():
		_suspend_motion()
		return
	var g := get_parent() as Game
	var mod := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT)
	var meta := Input.is_key_pressed(KEY_META)
	var v := Vector2.ZERO
	var turn := 0.0
	var tilt := 0.0
	var zoom := 0.0
	if not meta:
		var k := Vector2(
			float(EIKeymap.held("camera_right")) - float(EIKeymap.held("camera_left")),
			float(EIKeymap.held("camera_down")) - float(EIKeymap.held("camera_up")))
		if mod:
			turn = k.x
			tilt = k.y
		else:
			v = k
		turn += float(EIKeymap.held("camera_rotate_right")) - float(EIKeymap.held("camera_rotate_left"))
		zoom = float(EIKeymap.held("camera_zoom_out")) - float(EIKeymap.held("camera_zoom_in"))
	turn = clampf(turn + pad_turn, -1.0, 1.0)
	zoom = clampf(zoom + pad_zoom, -1.0, 1.0)
	edge = _edge_scroll()
	v = (v + Vector2(edge)).limit_length()
	# One velocity filter, with a quick stop. Manual panning does not pass
	# through the separate follow-position filter a second time.
	var ps := speed_factor("cam_pan_speed")
	var want := _screen_to_ground(v) * (5.0 + _dist_s * 0.9) * ps
	if v != Vector2.ZERO:
		_detach()
	_vel = _vel.lerp(want, _ease(18.0 if v != Vector2.ZERO else 32.0, dt))
	var panning := _vel.length_squared() > 0.0025
	if panning:
		_goal += _vel * dt
	else:
		_vel = Vector3.ZERO
	# Turn keys get a short acceleration and a firm stop; mouse orbit above
	# is direct, without queued rotation after the mouse stops.
	var rs := speed_factor("cam_rotate_speed")
	var sx := -1.0 if GameData.option("camera_reverse_x") else 1.0
	_yaw_vel = lerpf(_yaw_vel, -turn * 2.0 * rs * sx, _ease(18.0 if turn else 32.0, dt))
	if absf(_yaw_vel) > 0.001:
		yaw += _yaw_vel * dt
	else:
		_yaw_vel = 0.0
	if tilt:
		var sy := -1.0 if GameData.option("camera_reverse_y") else 1.0
		_pitch_ofs = clampf(_pitch_ofs + tilt * dt * 0.8 * rs * sy,
			deg_to_rad(-M_PITCH_OFS), deg_to_rad(M_PITCH_OFS))
	if zoom:
		distance *= exp(zoom * dt * 1.6 * speed_factor("cam_zoom_speed"))
	distance = clampf(distance, M_MIN_DISTANCE, _max_distance())
	_follow(g, dt)
	_goal = clamp_look_at(_goal)
	# Ease the shown values toward the goals.
	var k := 1.0 if panning else _ease(10.0, dt)
	position.x = lerpf(position.x, _goal.x, k)
	position.z = lerpf(position.z, _goal.z, k)
	_yaw_s = _unwrap(_yaw_s, yaw)
	_yaw_s = lerpf(_yaw_s, yaw, _ease(24.0, dt))
	_dist_s = exp(lerpf(log(_dist_s), log(distance), _ease(9.0, dt)))
	_pitch_ofs_s = lerpf(_pitch_ofs_s, _pitch_ofs, _ease(10.0, dt))
	# Terrain: the look-at height eases over bumps; the pitch rises quickly
	# when a hill would cut the eye line and settles back slowly. Both through
	# springs: while strafing the targets change in steps, which a first-order
	# ease turned into sudden vertical jerks across the sideways motion.
	var need := _needed_terrain_pitch()
	var tp := _smooth_damp(_terrain_pitch, need, _terrain_pitch_v, 0.12 if need > _terrain_pitch else 0.5, dt)
	_terrain_pitch = tp.x
	_terrain_pitch_v = tp.y
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


## Follow only while attached. Movement and selection never override a
## manual pan; Home, a hero hotkey or a portrait double-click reattaches.
func _follow(g: Game, _dt: float) -> void:
	_follow_unit = null
	if g and not g.selected.is_empty() and is_instance_valid(g.selected[0]) \
			and not g.selected[0].dead and g.selected[0].world == g.world:
		_follow_unit = g.selected[0]
	if _follow_unit == null or _free or GameData.option("cam_follow") != 1:
		return
	var p := _follow_unit.get_global_transform_interpolated().origin
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
		# Blended out from 2 to 4 m (no step when the view leaves the hero).
		var p := _follow_unit.get_global_transform_interpolated().origin
		var w := smoothstep(4.0, 2.0, Vector2(p.x - position.x, p.z - position.z).length())
		h = lerpf(h, maxf(h, p.y), w)
	if not _ground_init:
		_ground_init = true
		_ground_s = h
		_ground_v = 0.0
	var gs := _smooth_damp(_ground_s, h, _ground_v, 0.2, dt)
	_ground_s = gs.x
	_ground_v = gs.y
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
		if _eye_line_clear(p0 + extra, ty, dir):
			break
		extra += deg_to_rad(3.0)
	# Refine the 3° step (to ~0.1°), so the need follows the terrain
	# continuously instead of in 3° steps.
	if extra > 0.0 and extra < deg_to_rad(60.0):
		var lo := extra - deg_to_rad(3.0)
		for i in 5:
			var mid := (lo + extra) * 0.5
			if _eye_line_clear(p0 + mid, ty, dir):
				extra = mid
			else:
				lo = mid
	return extra


func _eye_line_clear(p: float, ty: float, dir: Vector2) -> bool:
	p = minf(p, deg_to_rad(86.0))
	for i in range(1, 9):
		var f := float(i) / 8.0
		var r := _dist_s * f * cos(p)
		var gx := position.x + dir.x * r
		var gz := position.z + dir.y * r
		if ty + _dist_s * f * sin(p) < terrain.height_at(gx, -gz) + M_CLEARANCE:
			return false
	return true


func _apply_modern() -> void:
	if camera == null:
		return
	camera.fov = MODERN_FOV
	if terrain:
		# The same look-at limit as the original style (clamp_look_at).
		_goal = clamp_look_at(_goal)
		position = clamp_look_at(position)
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
