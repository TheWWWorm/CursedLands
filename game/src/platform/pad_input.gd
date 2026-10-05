extends Node
## PadInput (autoload): the remake's gamepad layer (docs/gamepad_design.md).
## the original has no joystick input (its one DirectInput device is the mouse
## .md "Controls"), so all of this is remake-only.
##
## Event driven, not InputMap polling: the joypad events are read in `_input`
## into this node's own button / axis state, so that
## - only one controller drives the game: the last one with a real press or a
##   stick pushed past the deadzone (a second pad's resting axes, a phantom
##   device — Godot 4.5+ lists joypads that are not there, godot#110906 — or a
##   release from another device never takes over);
## - triggers are read as axes with a 0.5 threshold and a rest value of -1
##   counted as 0 (Web / some Android pads);
## - tests inject InputEventJoypadButton / Motion with Input.parse_input_event
##   and see the same path as a real pad.
## Buttons map to logical actions (`ACTIONS`, rebindable, user://gamepad.ini);
## the D-pad and sticks are fixed. Every action reports phases through the
## `action` signal: "down", "up", "tap" (released before HOLD_SEC), "hold"
## (still held at HOLD_SEC), "repeat" (D-pad held, for lists). The press
## decides the route ("field" = PadField, "ui" = PadUI, "capture" = a waiting
## rebind row) and the release goes the same way, so an A pressed on a menu
## never acts in the field when the menu closes.
##
## `active` is the last input device: "kbm", "pad" or "touch". Pad use hides
## the touch controls (a touch brings them back, TouchInput); mouse movement
## of 40 px or a key / mouse button returns to "kbm". Events this layer makes
## itself (key bridge, pointer clicks) carry DEVICE_ID_EMULATION and never
## count as keyboard or mouse use.

signal mode_changed
signal action(name: String, phase: String)
signal connection_changed(device: int, connected: bool)

const HOLD_SEC := 0.35
const DOUBLE_SEC := 0.3
const REPEAT_DELAY := 0.4
const REPEAT_SEC := 0.09
const TRIGGER_ON := 0.5
const TRIGGER_OFF := 0.35
const FILE := "user://gamepad.ini"
## gamepad.ini's layout version ("version <n>" line): 2 since the movement-mode
## ring moved to L3 and the pointer to R3 (2026-10).
const FILE_VERSION := 2

## Logical actions bound to buttons, in the Options page's row order.
const ACTIONS := ["interact", "cancel", "context", "pause", "actions", "items", "mod", "system",
	"cursor", "gait", "view", "menu"]
## The default layout (docs/gamepad_design.md §3.1).
const DEFAULTS := {"A": "interact", "B": "cancel", "X": "context", "Y": "pause", "LB": "actions",
	"RB": "items", "LT": "mod", "RT": "system", "L3": "gait", "R3": "cursor", "VIEW": "view",
	"MENU": "menu", "TOUCHPAD": "view", "SHARE": "view"}
## Rebindable button names → Godot buttons (positional: A is the bottom face
## button on every pad). LT / RT are the trigger axes.
const BUTTONS := {"A": JOY_BUTTON_A, "B": JOY_BUTTON_B, "X": JOY_BUTTON_X, "Y": JOY_BUTTON_Y,
	"LB": JOY_BUTTON_LEFT_SHOULDER, "RB": JOY_BUTTON_RIGHT_SHOULDER, "L3": JOY_BUTTON_LEFT_STICK,
	"R3": JOY_BUTTON_RIGHT_STICK, "VIEW": JOY_BUTTON_BACK, "MENU": JOY_BUTTON_START,
	"TOUCHPAD": JOY_BUTTON_TOUCHPAD, "SHARE": JOY_BUTTON_MISC1}
const TRIGGERS := {"LT": JOY_AXIS_TRIGGER_LEFT, "RT": JOY_AXIS_TRIGGER_RIGHT}
const DPAD := {JOY_BUTTON_DPAD_UP: "up", JOY_BUTTON_DPAD_DOWN: "down", JOY_BUTTON_DPAD_LEFT: "left",
	JOY_BUTTON_DPAD_RIGHT: "right"}
## Glyph file names (art/pad_glyphs/<family>_<name>.png) per button name.
const GLYPH := {"A": "a", "B": "b", "X": "x", "Y": "y", "LB": "lb", "RB": "rb", "LT": "lt", "RT": "rt",
	"L3": "l3", "R3": "r3", "VIEW": "view", "MENU": "menu", "TOUCHPAD": "touchpad", "SHARE": "view",
	"LS": "ls", "RS": "rs", "UP": "dpad_up", "DOWN": "dpad_down", "LEFT": "dpad_left",
	"RIGHT": "dpad_right", "DPAD": "dpad", "DPAD_LR": "dpad_lr", "DPAD_UD": "dpad_ud"}
const FAMILIES := ["auto", "xbox", "ps", "nintendo", "deck"]
## Text names when no glyph picture is drawn (prompts in plain text).
const LABELS := {
	"xbox": {"A": "A", "B": "B", "X": "X", "Y": "Y", "LB": "LB", "RB": "RB", "LT": "LT", "RT": "RT",
		"L3": "LS", "R3": "RS", "VIEW": "View", "MENU": "Menu"},
	"ps": {"A": "✕", "B": "○", "X": "□", "Y": "△", "LB": "L1", "RB": "R1", "LT": "L2", "RT": "R2",
		"L3": "L3", "R3": "R3", "VIEW": "Create", "MENU": "Options", "TOUCHPAD": "Touchpad"},
	"nintendo": {"A": "B", "B": "A", "X": "Y", "Y": "X", "LB": "L", "RB": "R", "LT": "ZL", "RT": "ZR",
		"L3": "L3", "R3": "R3", "VIEW": "−", "MENU": "+"},
	"deck": {"A": "A", "B": "B", "X": "X", "Y": "Y", "LB": "L1", "RB": "R1", "LT": "L2", "RT": "R2",
		"L3": "L3", "R3": "R3", "VIEW": "View", "MENU": "Menu"},
}

var active := "kbm"
## The controller that drives the game (-1: none used yet).
var device := -1
## button name -> action (user://gamepad.ini, else DEFAULTS).
var bindings := {}
## PadField of the running game (set by it), PadUI (child).
var field: Node
var ui: Node
## A node waiting for a raw button (Options rebind row): `pad_capture(name)`.
var capture: Object

var _axes := {}
var _trig := {}        # "LT" / "RT" -> pressed
var _down := {}        # action -> press time (ms)
var _held := {}        # action -> "hold" sent
var _route := {}       # action -> route of its press
var _last_tap := {}    # action -> ms of the last tap
var _double := {}      # action -> the last tap was a double tap
var _repeat := {}      # action -> next repeat time (s, real)
var _mouse_run := 0.0
var ignore_mouse_until := 0   # ms: pointer warps are not mouse use
## The last cancel (B) press, ms: Android's Back from the same press is not a second Esc.
var last_cancel_ms := -100000
const BACK_DUPLICATE_MS := 250
var _back_pending_ms := -1
var _last_back_button_ms := -100000
var gyro := PadGyro.new()
var _focused := true
var _glyphs := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100   # before the field reads the sticks
	_strip_ui_joypad()
	load_bindings()
	Input.joy_connection_changed.connect(_on_connection)
	ui = PadUI.new()
	ui.name = "PadUI"
	add_child(ui)
	# A user mapping file for unusual pads (SDL GameControllerDB lines).
	if FileAccess.file_exists("user://gamecontrollerdb.txt"):
		for line in FileAccess.get_file_as_string("user://gamecontrollerdb.txt").split("\n"):
			line = line.strip_edges()
			if line != "" and not line.begins_with("#"):
				Input.add_joy_mapping(line, true)


func enabled() -> bool:
	return GameData.option("pad_enabled") != 0


## Godot's ui_* actions carry joypad events by default (D-pad, left stick);
## the remake's drawn panels take keys through PadUI's key bridge instead, so
## a pad never moves a focused Control or presses it a second time.
func _strip_ui_joypad() -> void:
	for a in InputMap.get_actions():
		if not String(a).begins_with("ui_"):
			continue
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				InputMap.action_erase_event(a, e)


# ------------------------------------------------------------------ events

func _input(e: InputEvent) -> void:
	if e is InputEventJoypadButton or e is InputEventJoypadMotion:
		if not enabled():
			return
		get_viewport().set_input_as_handled()
		if not _owns(e):
			return
		if e is InputEventJoypadMotion:
			_motion(e)
		else:
			_button(e)
		return
	if e.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		_set_active("touch")
	elif (e is InputEventKey and e.pressed and not e.echo) or (e is InputEventMouseButton and e.pressed):
		_set_active("kbm")
	elif e is InputEventMouseMotion and active == "pad":
		if Time.get_ticks_msec() < ignore_mouse_until:
			return
		_mouse_run += e.relative.length()
		if _mouse_run >= 40.0:
			_set_active("kbm")


## The most recently used controller owns the input: another device takes
## over only with a press or a stick / trigger pushed past the deadzone.
func _owns(e: InputEvent) -> bool:
	if e.device == device:
		return true
	if e is InputEventJoypadMotion and absf(e.axis_value) < maxf(deadzone(), 0.3):
		return false
	if e is InputEventJoypadMotion and e.axis in TRIGGERS.values() and e.axis_value < TRIGGER_ON:
		return false
	if e is InputEventJoypadButton and not e.pressed:
		return false
	release_all()
	gyro.stop()
	device = e.device
	return true


func _motion(e: InputEventJoypadMotion) -> void:
	_axes[e.axis] = e.axis_value
	for t: String in TRIGGERS:
		if e.axis == TRIGGERS[t]:
			var v := maxf(0.0, e.axis_value)   # some pads rest a trigger at -1
			var was := bool(_trig.get(t, false))
			if not was and v >= TRIGGER_ON:
				_trig[t] = true
				_set_active("pad")
				_named(t, true)
			elif was and v <= TRIGGER_OFF:
				_trig[t] = false
				_named(t, false)
			return
	if absf(e.axis_value) >= maxf(deadzone(), 0.3):
		_set_active("pad")


func _button(e: InputEventJoypadButton) -> void:
	if e.pressed:
		if e.button_index == JOY_BUTTON_B:
			_last_back_button_ms = Time.get_ticks_msec()
			_back_pending_ms = -1
		_set_active("pad")
	if DPAD.has(e.button_index):
		var a: String = DPAD[e.button_index]
		if e.pressed:
			_press(a)
		else:
			_release(a)
		return
	for n: String in BUTTONS:
		if BUTTONS[n] == e.button_index:
			_named(n, e.pressed)
			return


func _named(button_name: String, pressed: bool) -> void:
	if pressed and capture != null and is_instance_valid(capture) and capture.has_method("pad_capture"):
		if capture.call("pad_capture", button_name):
			return
	var a := String(bindings.get(button_name, ""))
	if a == "":
		return
	# A window in the "pad_dismiss" group (the tutorial) takes a press it
	# answers: it never reaches the field or the pointer, nor does its release.
	if pressed and not _down.has(a):
		for n in get_tree().get_nodes_in_group("pad_dismiss"):
			if n.is_visible_in_tree() and n.call("pad_dismiss", a):
				return
	if pressed:
		_press(a)
	else:
		_release(a)


func _route_now() -> String:
	if field != null and is_instance_valid(field) and field.call("takes_input"):
		return "field"
	return "ui"


func _press(a: String) -> void:
	if _down.has(a):
		return
	var now := Time.get_ticks_msec()
	_down[a] = now
	_held[a] = false
	_route[a] = _route_now()
	_repeat[a] = REPEAT_DELAY
	action.emit(a, "down")


func _release(a: String) -> void:
	if not _down.has(a):
		return
	var now := Time.get_ticks_msec()
	var held := bool(_held.get(a, false))
	var quick := now - int(_down[a]) < int(HOLD_SEC * 1000.0)
	_down.erase(a)
	_repeat.erase(a)
	action.emit(a, "up")
	if quick and not held:
		_double[a] = now - int(_last_tap.get(a, -100000)) < int(DOUBLE_SEC * 1000.0)
		_last_tap[a] = -100000 if _double[a] else now
		action.emit(a, "tap")
	_route.erase(a)


## Every held action released (focus lost, the pad unplugged, another pad
## taking over): no button or stick stays stuck.
func release_all() -> void:
	for a in _down.keys():
		_release(a)
	_axes.clear()
	_trig.clear()


func _process(dt: float) -> void:
	var real := dt / maxf(Engine.time_scale, 0.001)
	var now := Time.get_ticks_msec()
	gyro.update(device, gyro_pointer_wanted(), minf(real, 0.1))
	if _back_pending_ms >= 0 and now - _back_pending_ms >= BACK_DUPLICATE_MS:
		_back_pending_ms = -1
		PadUI.key(KEY_ESCAPE)
	for a: String in _down.keys():
		if not _down.has(a):
			continue
		if not _held.get(a, false) and now - int(_down[a]) >= int(HOLD_SEC * 1000.0):
			_held[a] = true
			action.emit(a, "hold")
		if a in ["up", "down", "left", "right"] and _repeat.has(a):
			_repeat[a] = float(_repeat[a]) - real
			if float(_repeat[a]) <= 0.0:
				_repeat[a] = REPEAT_SEC
				action.emit(a, "repeat")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_back_pending_ms = -1
		gyro.stop()
		release_all()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true


func gyro_pointer_wanted() -> bool:
	if not _focused or active != "pad" or not enabled() or GameData.option("pad_gyro") == 0:
		return false
	return _route_now() == "ui" or (field.cursor_mode and field._wheel_kind == "")


func gyro_delta(dt: float, height: float) -> Vector2:
	if not gyro_pointer_wanted():
		return Vector2.ZERO
	return gyro.delta(dt, height, GameData.option("pad_gyro_sensitivity"))


## Android may report controller B as a Back notification before OR after its
## joypad event. Defer an unmatched Back briefly so that either order acts once;
## a physical Back without a controller event still sends a complete Esc tap.
func android_back_request() -> void:
	var now := Time.get_ticks_msec()
	if now - maxi(last_cancel_ms, _last_back_button_ms) < BACK_DUPLICATE_MS:
		return
	if _back_pending_ms < 0:
		_back_pending_ms = now


func _on_connection(dev: int, connected: bool) -> void:
	if not connected and dev == device:
		release_all()
		gyro.stop()
		device = -1
	connection_changed.emit(dev, connected)


func _set_active(m: String) -> void:
	if m == "pad":
		_mouse_run = 0.0
	if m == active:
		return
	active = m
	if m == "pad" and TouchInput.enabled:
		TouchInput.enabled = false
		TouchInput.mode_changed.emit()
	mode_changed.emit()


# ------------------------------------------------------------------ state

## The action is held now.
func held(a: String) -> bool:
	return _down.has(a)


## How long the action has been held (s), 0 when up.
func held_time(a: String) -> float:
	return (Time.get_ticks_msec() - int(_down[a])) / 1000.0 if _down.has(a) else 0.0


## The route of the action's current press ("field" / "ui"), "" when up.
func route_of(a: String) -> String:
	return String(_route.get(a, ""))


## The last tap of the action was the second of a double tap.
func was_double(a: String) -> bool:
	return bool(_double.get(a, false))


## Option pad_deadzone (slider 0..40): 0.05 .. 0.45 of the stick's travel.
func deadzone() -> float:
	return 0.05 + GameData.option("pad_deadzone") / 100.0


## A stick with a radial deadzone, rescaled so the edge of the deadzone is 0
## (0..1 length). Option pad_swap_sticks swaps the two.
func stick(left := true) -> Vector2:
	if GameData.option("pad_swap_sticks") != 0:
		left = not left
	var v := Vector2(float(_axes.get(JOY_AXIS_LEFT_X if left else JOY_AXIS_RIGHT_X, 0.0)),
		float(_axes.get(JOY_AXIS_LEFT_Y if left else JOY_AXIS_RIGHT_Y, 0.0)))
	var l := v.length()
	var dz := deadzone()
	if l <= dz or not enabled():
		return Vector2.ZERO
	return v / l * clampf((l - dz) / (1.0 - dz), 0.0, 1.0)


# ------------------------------------------------------------------ bindings

func load_bindings() -> void:
	bindings = DEFAULTS.duplicate()
	if not FileAccess.file_exists(FILE):
		return
	var read := {}
	var version := 1
	for line in FileAccess.get_file_as_string(FILE).split("\n"):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() >= 2 and parts[0] == "version":
			version = int(parts[1])
			continue
		if parts.size() >= 2 and parts[1] == "recentre":
			parts[1] = "gait"   # the R3 action before the movement-mode ring (2026-10)
		if parts.size() >= 2 and (BUTTONS.has(parts[0]) or TRIGGERS.has(parts[0])) and String(parts[1]) in ACTIONS:
			read[String(parts[0])] = String(parts[1])
	if not read.is_empty():
		bindings = read
		for extra in ["TOUCHPAD", "SHARE"]:   # the PS extras follow View unless bound
			if not bindings.has(extra) and "view" in bindings.values():
				bindings[extra] = "view"
		# Version 1's defaults had the pointer on L3 and the ring on R3: swap
		# them once; the version line keeps a later deliberate rebind.
		if version < 2 and bindings.get("L3", "") == "cursor" and bindings.get("R3", "") == "gait":
			bindings.L3 = "gait"
			bindings.R3 = "cursor"
			save_bindings(bindings)


## user://gamepad.ini, one "<BUTTON> <action>" line per button (keyboard.ini's form)
## after a "version <n>" line.
func save_bindings(m: Dictionary) -> void:
	bindings = m.duplicate()
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	if f == null:
		return
	var names := m.keys()
	names.sort()
	var out := "version %d\r\n" % FILE_VERSION
	for n in names:
		out += "%s %s\r\n" % [n, m[n]]
	f.store_string(out)


## The first button bound to `a` (fixed directions: "UP" …), "" when none.
func button_of(a: String) -> String:
	if a in ["up", "down", "left", "right"]:
		return a.to_upper()
	for n in ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "L3", "R3", "VIEW", "MENU", "TOUCHPAD", "SHARE"]:
		if bindings.get(n, "") == a:
			return n
	return ""


# ------------------------------------------------------------------ glyphs

## The button family for glyphs: option pad_glyphs, else by the controller
## (vendor id; on Web / Android get_joy_info is empty, so its name).
func family() -> String:
	var o := GameData.option("pad_glyphs")
	if o > 0 and o < FAMILIES.size():
		return FAMILIES[o]
	if device < 0:
		return "xbox"
	var info := Input.get_joy_info(device)
	var vendor := int(info.get("vendor_id", 0))
	var n := Input.get_joy_name(device).to_lower()
	if vendor == 0x054c or "054c" in n or "dualsense" in n or "dualshock" in n or "wireless controller" in n or "playstation" in n or "ps4" in n or "ps5" in n:
		return "ps"
	if vendor == 0x057e or "057e" in n or "nintendo" in n or "switch" in n or "joy-con" in n:
		return "nintendo"
	if OS.get_environment("SteamDeck") == "1" or "steam deck" in n:
		return "deck"
	return "xbox"


## The glyph picture of a button name ("A", "LB", "UP", "LS", "DPAD_LR" …).
func glyph(button_name: String) -> Texture2D:
	var file := String(GLYPH.get(button_name, ""))
	if file == "":
		return null
	var path := "res://art/pad_glyphs/%s.png" % file if file.begins_with("dpad") \
		else "res://art/pad_glyphs/%s_%s.png" % [family(), file]
	if not _glyphs.has(path):
		_glyphs[path] = load(path) if ResourceLoader.exists(path) else null
	return _glyphs[path]


## The text name of a button for the current family ("A", "✕", "LB" …).
func label(button_name: String) -> String:
	var fam: Dictionary = LABELS.get(family(), LABELS.xbox)
	if fam.has(button_name):
		return String(fam[button_name])
	return String(COMMON_LABELS.get(button_name, button_name))


## Names shared by every family (sticks, D-pad).
const COMMON_LABELS := {"LS": "LS", "RS": "RS", "UP": "↑", "DOWN": "↓", "LEFT": "←", "RIGHT": "→",
	"DPAD": "✚", "DPAD_LR": "←/→", "DPAD_UD": "↑/↓"}


## The tutorial's key names (EIKeymap.tutorial_text) while the pad drives:
## the keyboard action's controller equivalent ("" keeps the key's name).
func tutorial_key(key_action: String) -> String:
	var lb := label(button_of("actions"))
	var rb := label(button_of("items"))
	var rt := label(button_of("system"))
	var lt := label(button_of("mod"))
	var x := label(button_of("context"))
	match key_action:
		"pause": return label(button_of("pause"))
		"accel", "decel": return "%s (%s)" % [label(button_of("pause")), RemakeText.t("hold")]
		"obj": return label(button_of("view"))
		"camera_track": return rt
		"camera_norm": return "%s+%s" % [lt, label(button_of("gait"))]
		"camera_up", "camera_down", "camera_left", "camera_right", "camera_zoom_in", "camera_zoom_out", \
				"camera_rotate_left", "camera_rotate_right":
			return label("RS")
		"cs_head", "cs_body", "cs_rleg", "cs_lleg", "cs_rhand", "cs_lhand": return x
		"crawl", "sneak", "walk", "run": return label(button_of("gait"))
		"swarm", "follow", "use_science": return lb
		"select1", "select2", "select3": return label("UP")
		"select_all": return "%s (%s)" % [label("UP"), RemakeText.t("hold")]
		"quicksave", "quickload", "w_minimap", "w_text1", "w_text2", "tutorial_script": return rt
		"w_info1", "w_info2", "w_info3", "w_info4": return "%s+%s" % [lt, label("DPAD_LR")]
		"camera1", "camera2", "camera3", "camera4": return rt
	if key_action.begins_with("spell"):
		return lb
	if key_action.begins_with("weapon") or key_action.begins_with("item"):
		return rb
	return ""


func glyph_of(a: String) -> Texture2D:
	return glyph(button_of(a))


# ------------------------------------------------------------------ light bar

var _light := Color(-1, -1, -1)
var _light_device := -1

## The driving controller's light bar (DualSense / DualShock 4 and others
## with a light, Input.has_joy_light), option pad_light (0 off). Only a
## change is sent.
func light(c: Color) -> void:
	if device < 0 or not enabled() or GameData.option("pad_light") == 0 or not Input.has_joy_light(device):
		return
	if device == _light_device and c.is_equal_approx(_light):
		return
	_light = c
	_light_device = device
	Input.set_joy_light(device, c)


## The light bar colour of a hero's health share: green, through yellow, to
## red; a fallen leader dims it.
static func health_colour(share: float) -> Color:
	share = clampf(share, 0.0, 1.0)
	if share <= 0.0:
		return Color(0.15, 0.0, 0.0)
	var c := Color(1.0, 0.1, 0.05).lerp(Color(1.0, 0.75, 0.05), clampf(share * 2.0, 0.0, 1.0)) if share < 0.5 \
		else Color(1.0, 0.75, 0.05).lerp(Color(0.1, 0.9, 0.15), (share - 0.5) * 2.0)
	return Color(snappedf(c.r, 0.05), snappedf(c.g, 0.05), snappedf(c.b, 0.05))


# ------------------------------------------------------------------ rumble

## Vibration of the driving controller, scaled by option pad_rumble (0 off).
func rumble(weak: float, strong: float, seconds: float) -> void:
	var k := GameData.option("pad_rumble") / 100.0
	if k <= 0.0 or device < 0 or active != "pad" or not enabled():
		return
	Input.start_joy_vibration(device, clampf(weak * k, 0.0, 1.0), clampf(strong * k, 0.0, 1.0), seconds)
