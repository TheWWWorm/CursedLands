class_name EIKeymap
extends RefCounted
## The key bindings of config/keyboard.ini ("<KEY> <action>" per line), as
## the original keeps them: a 512-entry map scan code → key action id
## loaded at start-up (lines split on spaces
## key and action names compared case-insensitively, unknown ones skipped) and
## written back when the interface manager shuts down
## one "%s %s\n" line per bound scan code, in scan code order
## text mode (CRLF). A key has one action; an action may have several keys.
## Remake: the bindings are written to user://keyboard.ini (read first when it
## exists; the game folder's config/keyboard.ini stays untouched), at once when
## the Options screen's ✓ applies them instead of at exit.
## The modern WASD layout has a separate user://keyboard_wasd.ini; dispatch,
## held keys, Options and HUD tips all read the same active map.

## the original key table (72-byte entries: scan code, keyboard.ini name
## a GetKeyNameText buffer filled at start-up): the keys the
## game knows. Scan codes ≥ 0x100 are the extended keys.
const KEYS := [[0x02, "1"], [0x03, "2"], [0x04, "3"], [0x05, "4"], [0x06, "5"], [0x07, "6"],
	[0x08, "7"], [0x09, "8"], [0x0a, "9"], [0x0b, "0"], [0x0c, "-"], [0x0d, "+"], [0x0f, "TAB"],
	[0x10, "Q"], [0x11, "W"], [0x12, "E"], [0x13, "R"], [0x14, "T"], [0x15, "Y"], [0x16, "U"],
	[0x17, "I"], [0x18, "O"], [0x19, "P"], [0x1a, "["], [0x1b, "]"], [0x1e, "A"], [0x1f, "S"],
	[0x20, "D"], [0x21, "F"], [0x22, "G"], [0x23, "H"], [0x24, "J"], [0x25, "K"], [0x26, "L"],
	[0x27, ";"], [0x28, "'"], [0x2b, "\\"], [0x2c, "Z"], [0x2d, "X"], [0x2e, "C"], [0x2f, "V"],
	[0x30, "B"], [0x31, "N"], [0x32, "M"], [0x33, ","], [0x34, "."], [0x35, "/"], [0x37, "KP_STAR"],
	[0x39, "SPACE"], [0x3a, "CAPSLOCK"], [0x3b, "F1"], [0x3c, "F2"], [0x3d, "F3"], [0x3e, "F4"],
	[0x3f, "F5"], [0x40, "F6"], [0x41, "F7"], [0x42, "F8"], [0x43, "F9"], [0x44, "F10"],
	[0x45, "PAUSE"], [0x47, "KP_HOME"], [0x48, "KP_UP"], [0x49, "KP_PGUP"], [0x4a, "KP_MINUS"],
	[0x4b, "KP_LEFT"], [0x4c, "KP_CENTER"], [0x4d, "KP_RIGHT"], [0x4e, "KP_PLUS"], [0x4f, "KP_END"],
	[0x50, "KP_DOWN"], [0x51, "KP_PGDN"], [0x52, "KP_INS"], [0x53, "KP_DEL"], [0x57, "F11"],
	[0x58, "F12"], [0x135, "KP_SLASH"], [0x145, "KP_NUMLOCK"], [0x147, "HOME"], [0x148, "UP"],
	[0x149, "PGUP"], [0x14b, "LEFT"], [0x14d, "RIGHT"], [0x14f, "END"], [0x150, "DOWN"],
	[0x151, "PGDN"], [0x152, "INS"], [0x153, "DEL"]]

## keyboard.ini names → Godot keys (US layout; letters, digits and F keys by
## OS.find_keycode_from_string).
const NAMES := {"-": KEY_MINUS, "+": KEY_EQUAL, "TAB": KEY_TAB, "[": KEY_BRACKETLEFT,
	"]": KEY_BRACKETRIGHT, ";": KEY_SEMICOLON, "'": KEY_APOSTROPHE, "\\": KEY_BACKSLASH,
	",": KEY_COMMA, ".": KEY_PERIOD, "/": KEY_SLASH, "KP_STAR": KEY_KP_MULTIPLY, "SPACE": KEY_SPACE,
	"CAPSLOCK": KEY_CAPSLOCK, "PAUSE": KEY_PAUSE, "KP_HOME": KEY_KP_7, "KP_UP": KEY_KP_8,
	"KP_PGUP": KEY_KP_9, "KP_MINUS": KEY_KP_SUBTRACT, "KP_LEFT": KEY_KP_4, "KP_CENTER": KEY_KP_5,
	"KP_RIGHT": KEY_KP_6, "KP_PLUS": KEY_KP_ADD, "KP_END": KEY_KP_1, "KP_DOWN": KEY_KP_2,
	"KP_PGDN": KEY_KP_3, "KP_INS": KEY_KP_0, "KP_DEL": KEY_KP_PERIOD, "KP_SLASH": KEY_KP_DIVIDE,
	"KP_NUMLOCK": KEY_NUMLOCK, "HOME": KEY_HOME, "UP": KEY_UP, "PGUP": KEY_PAGEUP, "LEFT": KEY_LEFT,
	"RIGHT": KEY_RIGHT, "END": KEY_END, "DOWN": KEY_DOWN, "PGDN": KEY_PAGEDOWN, "INS": KEY_INSERT,
	"DEL": KEY_DELETE}

## the original key action table: [id, name, options group, row] (the
## Options screen's key-binding pages,; labels "string action_<name>"
## tips "tip action_<name>").
const ACTIONS := [[1, "pause", 3, 4], [2, "decel", 3, 3], [3, "accel", 3, 2], [4, "obj", 3, 6],
	[5, "camera_up", 6, 1], [6, "camera_down", 6, 2], [7, "camera_left", 6, 3], [8, "camera_right", 6, 4],
	[9, "camera_zoom_in", 6, 5], [10, "camera_zoom_out", 6, 6], [11, "camera_track", 6, 0],
	[12, "camera_norm", 6, 8], [13, "camera1", 6, 9], [14, "camera2", 6, 10], [15, "camera3", 6, 11],
	[16, "camera4", 6, 12], [17, "cs_head", 9, 0], [18, "cs_body", 9, 1], [19, "cs_rleg", 9, 2],
	[20, "cs_lleg", 9, 3], [21, "cs_rhand", 9, 4], [22, "cs_lhand", 9, 5], [23, "crawl", 5, 7],
	[24, "sneak", 5, 6], [25, "walk", 5, 5], [26, "run", 5, 4], [27, "swarm", 5, 2], [28, "follow", 5, 0],
	[29, "use_science", 5, 1], [30, "spell1", 8, 0], [31, "spell2", 8, 1], [32, "spell3", 8, 2],
	[33, "spell4", 8, 3], [34, "spell5", 8, 4], [35, "spell6", 8, 5], [36, "spell7", 8, 6],
	[37, "spell8", 8, 7], [38, "weapon1", 7, 0], [39, "weapon2", 7, 1], [40, "weapon3", 7, 2],
	[41, "weapon4", 7, 3], [42, "item1", 7, 5], [43, "item2", 7, 6], [44, "item3", 7, 7],
	[45, "item4", 7, 8], [46, "w_info1", 10, 3], [47, "w_info2", 10, 4], [48, "w_info3", 10, 5],
	[49, "w_info4", 10, 6], [50, "w_text1", 10, 0], [51, "w_text2", 10, 1], [52, "w_minimap", 10, 8],
	[53, "quicksave", 3, 8], [54, "quickload", 3, 9], [55, "select1", 4, 0], [56, "select2", 4, 1],
	[57, "select3", 4, 2], [58, "select_all", 4, 4], [59, "tutorial_script", 10, 10],
	# Remake-only actions (not in the original): the modern camera's turn keys
	# (CameraRig), on the Remake › Camera page (group 16) rows 8 and 9.
	[100, "camera_rotate_left", 16, 8], [101, "camera_rotate_right", 16, 9]]
## Keys the remake's own actions get when nothing is bound to them and the key
## is free (Delete / End turn the camera, as in Divinity: Original Sin 2).
const REMAKE_DEFAULTS := {"camera_rotate_left": "DEL", "camera_rotate_right": "END"}

## Windows key names as GetKeyNameText(scan << 16) gives them on an English
## system (the US layout's key name tables; the original fills its key table with
## them, and the Options screen shows them); others as the ini name.
const DISPLAY_NAMES := {"-": "-", "+": "=", "TAB": "Tab", "KP_STAR": "Num *", "SPACE": "Space",
	"CAPSLOCK": "Caps Lock", "PAUSE": "Pause", "KP_HOME": "Num 7", "KP_UP": "Num 8",
	"KP_PGUP": "Num 9", "KP_MINUS": "Num -", "KP_LEFT": "Num 4", "KP_CENTER": "Num 5",
	"KP_RIGHT": "Num 6", "KP_PLUS": "Num +", "KP_END": "Num 1", "KP_DOWN": "Num 2",
	"KP_PGDN": "Num 3", "KP_INS": "Num 0", "KP_DEL": "Num Del", "KP_SLASH": "Num /",
	"KP_NUMLOCK": "Num Lock", "HOME": "Home", "UP": "Up", "PGUP": "Page Up", "LEFT": "Left",
	"RIGHT": "Right", "END": "End", "DOWN": "Down", "PGDN": "Page Down", "INS": "Insert",
	"DEL": "Delete"}

const USER_FILE := "user://keyboard.ini"
const WASD_FILE := "user://keyboard_wasd.ini"
## Separate, editable layout: switching back never rewrites the classic keys.
const WASD_DEFAULTS := {"W": "camera_up", "S": "camera_down", "A": "camera_left",
	"D": "camera_right", "Q": "camera_rotate_left", "E": "camera_rotate_right",
	"9": "weapon1", "0": "weapon2", "-": "weapon3", "+": "weapon4",
	"R": "swarm", "T": "use_science"}

static var _map := {}       # scan code -> action name
static var _wasd_map := {}
static var _wasd_loaded := false
static var _loaded := false
static var _by_code := {}   # Godot keycode -> scan code
static var _names := {}     # scan code -> keyboard.ini name
static var _code_of := {}   # scan code -> Godot keycode


static func _tables() -> void:
	if not _names.is_empty():
		return
	for k: Array in KEYS:
		var name: String = k[1]
		_names[int(k[0])] = name
		var code := int(NAMES.get(name, 0))
		if code == 0:
			code = OS.find_keycode_from_string(name)
		if code != 0:
			_by_code[code] = int(k[0])
			_code_of[int(k[0])] = code


static func _ensure() -> void:
	if not _loaded:
		_loaded = true
		_load()


## The action bound to a Godot key ("" if none).
static func action(keycode: int) -> String:
	return String(_active_map().get(scan_code(keycode), ""))


static func event_action(e: InputEventKey) -> String:
	return action(e.physical_keycode if e.physical_keycode else e.keycode)


static func wasd_active() -> bool:
	return GameData.option("camera_style") == 1 and GameData.option("cam_wasd") == 1


static func _active_map(profile := -1) -> Dictionary:
	_ensure()
	if profile == 1 or (profile == -1 and wasd_active()):
		if not _wasd_loaded:
			_wasd_loaded = true
			_wasd_map = _read_map(WASD_FILE) if FileAccess.file_exists(WASD_FILE) else wasd_defaults(_map)
		return _wasd_map
	return _map


## Keep all existing actions reachable, including custom actions displaced by
## the preset. Spare keys exclude the remake's inventory / journal / quests.
static func wasd_defaults(base: Dictionary) -> Dictionary:
	_tables()
	var out := base.duplicate()
	for sc: int in out.keys():
		if out[sc] in ["weapon1", "weapon2", "weapon3", "weapon4", "swarm", "use_science"]:
			out.erase(sc)
	for name: String in WASD_DEFAULTS:
		var code := int(NAMES.get(name, OS.find_keycode_from_string(name)))
		out[scan_code(code)] = WASD_DEFAULTS[name]
	for sc: int in _sorted(base):
		var act: String = base[sc]
		if act in out.values():
			continue
		for key: Array in KEYS:
			if not out.has(int(key[0])) and not key[1] in ["B", "J", "G"]:
				out[int(key[0])] = act
				break
	return out


## Whether a key bound to `act` is held (the camera's held keys
## key-down / key-up through the map).
static func held(act: String, profile := -1) -> bool:
	var map := _active_map(profile)
	for sc: int in map:
		if map[sc] == act and _code_of.has(sc):
			var code: int = _code_of[sc]
			if Input.is_physical_key_pressed(code):
				return true
	return false


## Remake: forgets keys the engine still counts as held although their release
## went to another window. On Windows a frame stalled by a load buffers a
## key-down (Alt of Alt+Tab, Ctrl / Alt of Ctrl+Alt+Del, a camera key) and
## parses it only after the focus loss has cleared the held keys, so it stays
## "held": Ctrl / Alt turned A / D into camera turns, W / S into tilts and
## changed clicks into forced orders. Called a frame after the window gains
## or loses focus (GameData); a key really held repeats and counts again.
static func release_keys() -> void:
	_tables()
	var codes := [KEY_CTRL, KEY_ALT, KEY_SHIFT, KEY_META]
	codes.append_array(_code_of.values())
	for code: int in codes:
		if Input.is_key_pressed(code) or Input.is_physical_key_pressed(code):
			var e := InputEventKey.new()
			e.keycode = code as Key
			e.physical_keycode = code as Key
			e.key_label = code as Key
			e.pressed = false
			Input.parse_input_event(e)


## The key table's scan code of a Godot key, −1 when the game does not know it.
static func scan_code(keycode: int) -> int:
	_tables()
	return int(_by_code.get(keycode, -1))


static func ini_name(scan: int) -> String:
	_tables()
	return String(_names.get(scan, ""))


static func display_name(ini_key: String) -> String:
	return String(DISPLAY_NAMES.get(ini_key, ini_key))


## The keyboard.ini names of the keys bound to `act`, in scan code order.
static func keys_for(act: String) -> PackedStringArray:
	var map := _active_map()
	var out := PackedStringArray()
	for s: int in _sorted(map):
		if map[s] == act:
			out.append(ini_name(s))
	return out


static func key_of(act: String) -> String:
	var k := keys_for(act)
	return display_name(k[0]) if not k.is_empty() else ""


## The key name of action number `id` (the ACTIONS ids), as finds
## it for a tooltip: the first scan code bound to it; "" when none.
static func key_of_id(id: int) -> String:
	for a: Array in ACTIONS:
		if a[0] == id:
			return key_of(a[1])
	return ""


## A copy of the map (scan code → action), for the Options screen.
static func bindings(profile := -1) -> Dictionary:
	return _active_map(profile).duplicate()


## ✓ of the Options screen (copies its map back): applied and
## written to the chosen layout's user file.
static func set_bindings(m: Dictionary, profile := -1) -> void:
	var active := _active_map(profile)
	if m == active:
		if (profile == 1 or (profile == -1 and wasd_active())) and not FileAccess.file_exists(WASD_FILE):
			save(profile)
		return
	active.clear()
	active.merge(m)
	save(profile)


## "%s %s\n" per bound scan code, ascending.
static func save(profile := -1) -> void:
	var map := _active_map(profile)
	var wasd := profile == 1 or (profile == -1 and wasd_active())
	var f := FileAccess.open(WASD_FILE if wasd else USER_FILE, FileAccess.WRITE)
	if f == null:
		return
	var out := ""
	for s: int in _sorted(map):
		if _names.has(s):
			out += "%s %s\r\n" % [_names[s], map[s]]
	f.store_string(out)


static func _sorted(m: Dictionary) -> Array:
	var keys := m.keys()
	keys.sort()
	return keys


static func _load() -> void:
	_tables()
	var path := USER_FILE
	if not FileAccess.file_exists(path):
		path = GameData.root.path_join("config/keyboard.ini")
	_map = _read_map(path)
	_remake_defaults()


static func _read_map(path: String) -> Dictionary:
	var map := {}
	if not GameFiles.exists(path):
		return map
	var data := GameFiles.text(path)
	var known := {}
	for a: Array in ACTIONS:
		known[String(a[1]).to_lower()] = a[1]
	var by_name := {}
	for s: int in _names:
		by_name[String(_names[s]).to_lower()] = s
	for line in data.split("\n"):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() < 2:
			continue
		var k := String(parts[0]).to_lower()
		var a := String(parts[1]).to_lower()
		if by_name.has(k) and known.has(a):
			map[by_name[k]] = known[a]
	return map


static func _remake_defaults() -> void:
	var by_name := {}
	for sc: int in _names:
		by_name[_names[sc]] = sc
	for act: String in REMAKE_DEFAULTS:
		var sc: int = by_name.get(REMAKE_DEFAULTS[act], -1)
		if sc >= 0 and not _map.has(sc) and not act in _map.values():
			_map[sc] = act


## Remake: the tutorial texts (texts.res "tutor …") name the original
## keyboard.ini's keys in angle brackets ("<Q>", "<S>", "<A>"…). A key the
## active map no longer binds to that action (the WASD layout's 9 / 0 / - / =
## weapons, R stance, T Use/Steal, or the player's own rebinding) is replaced
## by the action's current key; keys still bound as shipped, and names that
## are not an action key of the original file (<CTRL>, <+> of the speed
## panel…), stay as written.
static var _orig_map := {}
static var _orig_loaded := false

static func tutorial_text(t: String) -> String:
	if not "<" in t:
		return t
	_tables()
	if not _orig_loaded:
		_orig_loaded = true
		_orig_map = _read_map(GameData.root.path_join("config/keyboard.ini"))
	var by_name := {}
	for sc: int in _names:
		by_name[String(_names[sc]).to_upper()] = sc
	var map := _active_map()
	# Remake: with the gamepad driving, the controller's buttons (PadInput).
	var ml := Engine.get_main_loop() as SceneTree
	var pad: Node = ml.root.get_node_or_null("PadInput") if ml else null
	if pad and String(pad.get("active")) != "pad":
		pad = null
	var re := RegEx.create_from_string("<([^<>\\s]{1,12})>")
	var out := ""
	var at := 0
	for m: RegExMatch in re.search_all(t):
		var sc: int = by_name.get(m.get_string(1).to_upper(), -1)
		var act := String(_orig_map.get(sc, ""))
		if act != "" and pad:
			var b := String(pad.call("tutorial_key", act))
			if b != "":
				out += t.substr(at, m.get_start() - at) + "<%s>" % b
				at = m.get_end()
			continue
		if act != "" and map.get(sc, "") != act:
			var k := key_of(act)
			if k != "":
				out += t.substr(at, m.get_start() - at) + "<%s>" % k
				at = m.get_end()
	return out + t.substr(at)
