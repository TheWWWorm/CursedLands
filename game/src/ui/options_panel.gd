class_name OptionsPanel
extends Interface800
## The original Options screen (the original: build
## rows, page, text
## update, click, keys
## load, OK), in 800×600 units stretched to the window:
## - the escMenu signpost (unmoco1) with only its "options" board (НАСТРОЙКИ),
##   turned π/2, at (400, 480) depth 4.8 (InterfaceBoard);
## - a panel (100,100)-(700,500) in a 5 px saveload frame
##   (95,95)-(705,505); the page title (100,110)-(700,134) font 2, centred;
## - 11 group buttons (100,156+24i)-(250,180+24i), sprite (110,158+24i)-
##   (240,177+24i) saveload UV 122,108-252,127 at colour 1.0 (current page) or
##   0.5, label «string option_group_<g>» font 1 centred
##   tip «tip option_group_<g>»;
## - 14 rows (250,156+24r)-(520,180+24r) for table (GameData.OPTIONS:
##   name, slider / switch, max, group, row) and the key actions
##   (EIKeymap.ACTIONS); label (260,160+24r)-(520,180+24r) «string option_<n>»
##   / «string action_<n>», tip «tip option_<n>» / «tip action_<n>»; sliders
##   (Interface800.hslider) at (530,163+24r)-(680,173+24r), switches
##   text (530,160+24r)-(690,176+24r) «string option_off / on» (difficulty:
##   difficulty_hard / easy), keys (530,160+24r)-(690,180+24r) (see key rows below);
## - the selected row's bar (250,156+24r)-(692,180+24r)
## - ✓ (213,526)-(287,574) UV 81,2-155,50 tip 70100, ✗ (513,526)-(587,574)
##   UV 160,2-234,50 tip 70101.
## Input: group click / PgUp / PgDn buttons\save\select.wav; row click or Up /
## Down selects (select.wav); a switch click, a row double click or Enter
## toggles it (buttons\messbox\ok.wav); Left / Right move the selected slider;
## slider arrows scroll 16 units / s while held, the thumb drags. Volumes,
## brightness / contrast / gamma and reverse stereo apply at once
## the rest on ✓ (messbox\ok.wav); ✗ / Esc restores them (messbox\cancel.wav).
## Remake: ✗ / Esc after a change first asks whether to save it (`_cancel`).
## Remake (user requests 2026-10-04): 13 group buttons (TAB_ORDER, the
## column (100,156)-(250,468), same sprite and font): the original's 11 with the
## remake's "Screen" after Graphics and "Remake" last. The original's pages hold
## only its rows (its free rows empty), but Graphics starts at the top (no
## rows for the original's three shadow switches, always : FIXED_OPTIONS) and
## its brightness / contrast / gamma are on Screen. Screen (SCREEN_GROUP):
## display mode, resolution, render scale, anti-aliasing, frame-rate limit,
## VSync, smooth motion, FPS counter, brightness / contrast / gamma and (Android
## only) the renderer — multiple-choice rows stepped by a click / Enter
## (forward) or Left / Right, applied at once like the volumes, restored by ✗;
## the renderer row asks first when stepped to Forward+ (experimental on
## phones, ✗ puts it back) and ✓ with it changed offers a restart. Graphics
## rows 6..8: detect graphics automatically, "Detect best settings" (the
## graphics test now), "Original look" (PRESET_ROW); rows 10..12 link to the
## remake's graphics sections. Remake: its sections as link rows (SECTIONS,
## rows 0..7: World and textures, Lighting and shadows, Water and effects,
## Camera, Interface and controls, Gamepad, Gameplay, Network and co-op), row
## 11 "Game files…" (main menu only: the first-run setup screen again,
## DataSwitch), row 12 "Export log…" (CrashReportBox). A section page is
## titled "<button> › <section>" with that button lit and row 13 "« <button>"
## (PARENT; a graphics section opened from Graphics belongs to Graphics, from
## Remake to Remake: `_parent`); Gamepad row 12 "Buttons…" opens "Remake ›
## Gamepad › Buttons" (row 13 « Gamepad). Esc (the pad's B) on a sub-page goes
## back one level, elsewhere it is ✗ as in the original; the pad's Menu is ✗
## any page, Y is ✓. Up / Down wrap around (top ↔ bottom, past empty and grey
## rows), PgUp / PgDn (LB / RB) step through the 13 buttons and wrap. Labels
## and tips: GameData.REMAKE_OPTIONS (every remake row's tip marks it).
## There is no language choice (the original has none: the texts and voices
## are those of the edition supplied). Behind it the frozen,
## greyed frame (Interface800.dim_layer).
## Key rows: the
## screen works on a copy of the key map and lists for each
## action only its first bound key (lowest scan code), as "  |  "-joined
## Windows key names. A double click or Enter on a key row waits for a key
## (save\select.wav / messbox\ok.wav; the row's label and key in red, COLORREF
## 0xff); Esc stops waiting; a key outside the original's key table plays
## messbox\cancel.wav and keeps waiting; a known key plays messbox\ok.wav and
## replaces the row's listed key — unless another action has it: message box
## «key_already_mapped» / «key_already_mapped_msg» (key name, that action's
## label; base, ✓), which then takes it
## from that action. A click on a row or group stops waiting. There is no
## defaults / reset button. ✓ applies the map and the remake
## writes user://keyboard.ini (EIKeymap); ✗ drops it.
## The first-visit tutorial «tutorial options» ((0), id
## ) opens over the screen after its build, or at the end of the
## slide-. While the board slides in the text widget is
## hidden (Interface800.hide_text); while a message box is up
## the screen is not drawn (MessageBox).

signal closed
## Remake: the "Game files…" row (Remake row 11) was chosen; the main
## menu shows the setup screen again (main.gd change_game_files).
signal game_files_requested

const REMAKE_GROUP := 11   # GameData.OPTION_GROUPS index of the Remake tab (its sections' links)
const SCREEN_GROUP := 12   # the remake's Screen tab
const WORLD_GROUP := 13    # Remake › World and textures (also Graphics › …)
const LIGHT_GROUP := 14    # Remake › Lighting and shadows (also Graphics › …)
const EFFECTS_GROUP := 15  # Remake › Water and effects (also Graphics › …)
const CAMERA_GROUP := 16   # Remake › Camera
const INTERFACE_GROUP := 17   # Remake › Interface and controls
const GAMEPLAY_GROUP := 18 # Remake › Gameplay
const COOP_GROUP := 19     # Remake › Network and co-op
const PAD_GROUP := 20      # Remake › Gamepad
const PAD_BUTTONS_GROUP := 21   # Remake › Gamepad › Buttons (PAD_GROUP row 12)
## The group buttons top to bottom: the original's 11 with the remake's Screen
## after Graphics, and Remake last.
const TAB_ORDER := [0, SCREEN_GROUP, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, REMAKE_GROUP]
const TABS := 13           # TAB_ORDER.size()
## The Remake page's link rows (row = index).
const SECTIONS := [WORLD_GROUP, LIGHT_GROUP, EFFECTS_GROUP, CAMERA_GROUP,
	INTERFACE_GROUP, PAD_GROUP, GAMEPLAY_GROUP, COOP_GROUP]
## The remake pages and the page their « row (and Esc / B) leads back to; the
## parent's button is lit while one is up. The graphics sections also hang
## under Graphics (GRAPHICS_LINKS) when opened from there (`_came_from`).
const PARENT := {WORLD_GROUP: REMAKE_GROUP, LIGHT_GROUP: REMAKE_GROUP,
	EFFECTS_GROUP: REMAKE_GROUP, CAMERA_GROUP: REMAKE_GROUP, INTERFACE_GROUP: REMAKE_GROUP,
	GAMEPLAY_GROUP: REMAKE_GROUP, COOP_GROUP: REMAKE_GROUP, PAD_GROUP: REMAKE_GROUP,
	PAD_BUTTONS_GROUP: PAD_GROUP}
## The Graphics page's links to the remake's graphics sections, rows 10..12.
const GRAPHICS_LINKS := [WORLD_GROUP, LIGHT_GROUP, EFFECTS_GROUP]
const GRAPHICS_LINK_ROW := 10
## The pages with the Original look toggle in row 12 (PRESET_ROW); on the
## Graphics page it is row 8 (GFX_LOOK_ROW).
const LOOK_PAGES := [WORLD_GROUP, LIGHT_GROUP, EFFECTS_GROUP]
const GFX_LOOK_ROW := 8
const BACK_ROW := 13       # a remake page's « row
const BUTTONS_ROW := 12    # Gamepad › "Buttons…"; Buttons › "Default buttons"
const PAD_BUTTONS_LINK := ["Buttons…", "Choose which controller button does what. The D-pad and the sticks keep their roles."]
const PAD_DEFAULTS := ["Default buttons", "Restores the default button layout (confirm with ✓)."]
const PAD_GYRO_CALIBRATE := ["Calibrate gyro", "Keep the controller or handheld still for two seconds. Use this if the pointer drifts."]
## The rebindable gamepad actions' labels and tips (PadInput.ACTIONS order).
const PAD_ACTIONS := {
	"interact": ["Act / confirm", "Acts on the highlighted target as a left click on it would: attack, loot, talk, use; confirms a spell's target. Held: forced attack."],
	"cancel": ["Cancel / back", "Cancels a spell, item or aim being targeted, else stops the selected characters. Closes wheels and menus."],
	"context": ["Target ring", "More actions for the highlighted target: aimed strikes, steal, follow, examine; on open ground: move, run, forced move."],
	"pause": ["Pause", "Pauses or resumes the game. In co-op only the host changes the shared speed. Held: normal or fast speed."],
	"actions": ["Spells and actions wheel", "Spells, stance, Use/Steal and Follow. In an open wheel: the previous page."],
	"items": ["Items wheel", "The belt and the weapons. In an open wheel: the next page."],
	"mod": ["Modifier", "Held, it changes other buttons, as Ctrl / Alt on the keyboard: forced attack, forced move, use or cast at once, the unit panel's views."],
	"system": ["Game wheel", "Inventory, journal, quests, minimap, message log, quick save and load, tutorial. Its camera page: centre on the leader, camera views 1–4."],
	"cursor": ["Pointer", "Switches the pointer on or off: the left stick moves it and A / B click as the mouse buttons."],
	"gait": ["Movement mode", "Tap: the ring of the movement modes (run, walk, sneak, crawl) for the selected characters, picked with either stick; the left stick moves in the chosen one. Held: names over the people, bodies, levers and exits around."],
	"view": ["Quests", "The quests screen. Held: the journal."],
	"menu": ["Menu", "The game menu: save, load, options, exit."],
}
## Remake row 11: the original game files (DataSwitch). Only from the main
## menu (`game_files`); in a game the row is grey and says so.
const FILES_GROUP := REMAKE_GROUP
const FILES_ROW := 11
const FILES_LINK := ["Game files…", "Choose another Evil Islands folder or installer, or import the game data again. Saves and settings are kept."]
## Remake row 12: the log and system information saved or copied
## (CrashReportBox), from the main menu and in a game.
const LOG_ROW := 12
const LOG_LINK := ["Export log…", "Saves the game's log with the system information to a folder you can open, or copies it, to send it with a bug report."]
const LIVE := ["volume_sfx", "volume_stream", "volume_voice", "brightness", "contrast", "gamma", "reverse_stereo",
	"display_mode", "resolution", "fps_limit", "vsync", "show_fps", "render_scale"]
const OK_RECT := Rect2(213, 526, 74, 48)
const CANCEL_RECT := Rect2(513, 526, 74, 48)

var _group := 0
var _sel := -1
var _rows := {}        # row -> {"kind": "slider"/"switch"/"keys", "name", "max", "label", "tip"}
var _values := {}      # option -> value shown (pending until ✓)
var _snapshot := {}    # option -> value when opened
var _board: InterfaceBoard
var _dim: Interface800.Backdrop
var _drag := -1        # row whose thumb is dragged
var _hold := -1        # row whose arrow is held
var _hold_dir := 0
var _hold_acc := 0.0
var _slide := 1.0       # slide-in time, 0..1
var _kmap := {}         # scan code -> action (the screen's copy)
var _klist := {}        # action -> scan codes listed on its row
var _key_profiles := {} # pending Classic / WASD maps; neither changes until ✓
var _waiting := false   # the selected key row waits for a key
var _box: MessageBox
var _tutorial: TutorialPanel
var _pad_map := {}      # remake: the gamepad layout being edited (button -> action)
var _look_from := -2    # remake: Original look switched on here over this detected tier (-1 none, -2 not here)
var _came_from := 0     # remake: the group button whose page was shown last (a sub-page's way back)
## Remake: the "Game files…" row can be used (opened from the main menu).
var game_files := false


func _ready() -> void:
	visible = false
	add_to_group("pad_panel")   # remake: Y = ✓ and the button rows (pad_press, pad_capture)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "   # tips come from _get_tooltip (GameData.TipLayer)
	_dim = Interface800.dim_layer()
	add_child(_dim)
	_board = InterfaceBoard.create("unmoco1", "escmenu00", "escmenu00labels",
		PackedStringArray(["options", "optionslabel"]), PI * 0.5, Vector3(400, 480, 4.8))
	_board.show_behind_parent = true   # under the panels, over the dimmed screen
	add_child(_board)
	_tutorial = TutorialPanel.new()
	add_child(_tutorial)
	resized.connect(queue_redraw)


## `frame`: the frame captured when the game switched to its menus (opened
## from the Esc menu: no new capture); `slide`: the Esc menu's slide-in
## (: t over 0.5 s, board y = 700 − 220e
## e = 2t² below ½, else 1 − 2(1 − t)²).
func open(frame: Image = null, slide := false) -> void:
	_snapshot.clear()
	for o: Array in GameData.OPTIONS:
		_snapshot[o[0]] = GameData.option(o[0])
	_values = _snapshot.duplicate()
	if frame:
		_dim.use(frame)
	else:
		_dim.capture()   # the frame, frozen and greyed
	_slide = 0.0 if slide else 1.0
	hide_text = slide
	_place_board()
	_load_keys()
	_pad_map = PadInput.bindings.duplicate()
	_look_from = -2
	_waiting = false
	visible = true
	_show_group(0)
	if not slide:
		_tutorial.show_screen("options")   # (0)


func _place_board() -> void:
	var t := clampf(_slide, 0.0, 1.0)
	var e := 2.0 * t * t if t < 0.5 else 1.0 - 2.0 * (1.0 - t) * (1.0 - t)
	_board.place(Vector3(400, 700.0 - 220.0 * e, 4.8))


func _close() -> void:
	visible = false
	_waiting = false
	_stop_pad_wait()
	if is_instance_valid(_box):
		_box.queue_free()
	_box = null
	if _tutorial.visible:
		_tutorial.visible = false
	_drag = -1
	_hold = -1
	closed.emit()


# ------------------------------------------------------------------ pages

func _group_count() -> int:
	return TAB_ORDER.size()


## The page a remake sub-page leads back to (-1: a group button's own page).
## A graphics section opened from Graphics goes back there.
func _parent(g: int) -> int:
	if g in GRAPHICS_LINKS and _came_from == 0:
		return 0
	return int(PARENT.get(g, -1))


## The group button lit for the page: the page's own, or the one it hangs under.
func _tab() -> int:
	var g := _group
	while _parent(g) >= 0:
		g = _parent(g)
	return g


## A remake page's own name ("Display"); the original's pages: their button label.
func _section_label(g: int) -> String:
	var key: String = GameData.OPTION_GROUPS[g]
	if GameData.REMAKE_OPTIONS.has(key):
		return RemakeText.t(GameData.REMAKE_OPTIONS[key][0])
	return _t("string option_group_" + key, key.capitalize())


## The group button's label, or for a remake page its path as the title
## ("Remake › Gamepad › Buttons", "Graphics › Water and effects").
func _group_label(g: int) -> String:
	if _parent(g) >= 0:
		return "%s › %s" % [_group_label(_parent(g)), _section_label(g)]
	return _section_label(g)


func _group_tip(g: int) -> String:
	var key: String = GameData.OPTION_GROUPS[g]
	if g == SCREEN_GROUP:   # the remake's rows with three of the original's
		return _section_label(g) + "\n" + RemakeText.t(GameData.REMAKE_OPTIONS[key][1])
	if GameData.REMAKE_OPTIONS.has(key):
		return RemakeText.t("%s\nThe remake's own settings; not part of the original game.") % _section_label(g) \
			+ "\n" + RemakeText.t(GameData.REMAKE_OPTIONS[key][1])
	return GameData.text("tip option_group_" + key).strip_edges()


## Remake: from a sub-page to its parent, on the row that leads back to it.
func _go_back() -> void:
	var from := _group
	_show_group(_parent(from))
	for r: int in _rows:
		if _rows[r].get("to", -1) == from:
			_sel = r


func _section_link(g: int) -> Dictionary:
	var label := _section_label(g) + "…"
	return {"kind": "link", "name": "", "to": g, "label": label,
		"tip": _remake_tip([label, GameData.REMAKE_OPTIONS[GameData.OPTION_GROUPS[g]][1]])}


static func _remake_tip(pair: Array) -> String:
	return RemakeText.t("%s\n%s\n(Remake option.)") % RemakeText.tl(pair)


## the page's rows; the first row with a control is selected.
func _show_group(g: int) -> void:
	_group = g if PARENT.has(g) or g in TAB_ORDER else 0
	if _group in TAB_ORDER:
		_came_from = _group
	_rows.clear()
	for o: Array in GameData.OPTIONS:
		if int(o[3]) != _group:
			continue
		var name: String = o[0]
		if name == "renderer" and not RendererChoice.available():
			continue   # Android only (desktop Forward+, web Compatibility)
		var label := _t("string option_" + name, name.capitalize()).trim_suffix(":").strip_edges()
		var tip := GameData.text("tip option_" + name).strip_edges()
		if GameData.REMAKE_OPTIONS.has(name):
			label = RemakeText.t(GameData.REMAKE_OPTIONS[name][0])
			tip = _remake_tip(GameData.REMAKE_OPTIONS[name])
		var choices := GameData.option_choices(name)
		_rows[int(o[4])] = {"kind": "slider" if int(o[1]) == 0 else "switch", "name": name,
			"max": choices.size() if not choices.is_empty() else int(o[2]), "label": label, "tip": tip,
			"choices": choices}
	for a: Array in EIKeymap.ACTIONS:
		if int(a[2]) != _group:
			continue
		var name: String = a[1]
		_rows[int(a[3])] = {"kind": "keys", "name": name,
			"label": _action_label(name),
			"tip": _remake_tip(GameData.REMAKE_OPTIONS[name]) if GameData.REMAKE_OPTIONS.has(name)
				else GameData.text("tip action_" + name).strip_edges(),
			"keys": _keys_text(name)}
	if _group == REMAKE_GROUP:   # the sections, then the game data rows
		for i in SECTIONS.size():
			_rows[i] = _section_link(SECTIONS[i])
		_rows[FILES_ROW] = {"kind": "link", "name": "", "files": true, "disabled": not game_files,
			"label": RemakeText.t(FILES_LINK[0]),
			"tip": _remake_tip(FILES_LINK) + "\n" + RemakeText.t("Current game files: %s") % DataSwitch.describe()
				+ ("" if game_files else "\n" + RemakeText.t("Available from the main menu."))}
		if CrashReport.enabled:
			_rows[LOG_ROW] = {"kind": "link", "name": "", "export_log": true, "label": RemakeText.t(LOG_LINK[0]),
				"tip": _remake_tip(LOG_LINK)}
	elif _group == 0:   # Graphics: the graphics test, Original look, the graphics sections
		_rows[DETECT_ROW] = {"kind": "link", "name": "", "detect": true,
			"label": RemakeText.t(DETECT_LINK[0]), "tip": _remake_tip(DETECT_LINK)}
		_rows[GFX_LOOK_ROW] = _look_row()
		for i in GRAPHICS_LINKS.size():
			_rows[GRAPHICS_LINK_ROW + i] = _section_link(GRAPHICS_LINKS[i])
	elif _parent(_group) >= 0:
		_rows[BACK_ROW] = {"kind": "link", "name": "", "to": _parent(_group),
			"label": "« " + _section_label(_parent(_group)), "tip": ""}
		if _group in LOOK_PAGES:
			_rows[PRESET_ROW] = _look_row()
		if _group == PAD_GROUP:
			_rows[11] = {"kind": "link", "name": "", "gyro_calibrate": true,
				"label": RemakeText.t(PAD_GYRO_CALIBRATE[0]), "tip": _remake_tip(PAD_GYRO_CALIBRATE)}
			_rows[BUTTONS_ROW] = {"kind": "link", "name": "", "to": PAD_BUTTONS_GROUP,
				"label": RemakeText.t(PAD_BUTTONS_LINK[0]), "tip": _remake_tip(PAD_BUTTONS_LINK)}
		elif _group == PAD_BUTTONS_GROUP:
			for i in PadInput.ACTIONS.size():
				var act: String = PadInput.ACTIONS[i]
				_rows[i] = {"kind": "padbtn", "name": act, "label": RemakeText.t(PAD_ACTIONS[act][0]),
					"tip": _remake_tip(PAD_ACTIONS[act]), "keys": ""}
			_rows[BUTTONS_ROW] = {"kind": "link", "name": "", "pad_defaults": true,
				"label": RemakeText.t(PAD_DEFAULTS[0]), "tip": _remake_tip(PAD_DEFAULTS)}
			_refresh_pad()
	_sel = -1
	_waiting = false   # = 0
	for r in 14:
		if _rows.has(r):
			_sel = r
			break
	queue_redraw()


# ------------------------------------------------------------------ keys

## editable copies of the bindings. The remake
## lists all aliases so the WASD layout's arrows / Delete / End are visible.
func _load_keys() -> void:
	_key_profiles = {0: EIKeymap.bindings(0), 1: EIKeymap.bindings(1)}
	_select_key_profile()


func _select_key_profile() -> void:
	var profile := 1 if int(_values.get("camera_style", 1)) == 1 and int(_values.get("cam_wasd", 0)) == 1 else 0
	_kmap = _key_profiles[profile]
	_klist.clear()
	for a: Array in EIKeymap.ACTIONS:
		_klist[a[1]] = []
	var scans := _kmap.keys()
	scans.sort()
	for sc: int in scans:
		var act: String = _kmap[sc]
		if _klist.has(act):
			_klist[act].append(sc)


## The listed keys' Windows names joined by "  |  ", then TrimRight(" |").
func _keys_text(act: String) -> String:
	var t := ""
	for sc: int in _klist.get(act, []):
		t += EIKeymap.display_name(EIKeymap.ini_name(sc)) + "  |  "
	return t.rstrip(" |")


func _action_label(act: String) -> String:
	if GameData.REMAKE_OPTIONS.has(act):   # the remake's own key actions (EIKeymap)
		return RemakeText.t(GameData.REMAKE_OPTIONS[act][0])
	return _t("string action_" + act, act.capitalize())


func _refresh_keys() -> void:
	for r: int in _rows:
		if _rows[r].kind == "keys":
			_rows[r]["keys"] = _keys_text(_rows[r].name)
	queue_redraw()


##  while is set: Esc stops waiting; a key the key table
## lacks is refused (cancel.wav, still waiting); else ok.wav and the key goes
## to the row — after a «key_already_mapped» box when another action has it.
func _key_pressed(e: InputEventKey) -> void:
	if e.keycode == KEY_ESCAPE:
		_waiting = false
		_stop_pad_wait()
		queue_redraw()
		return
	var sc := EIKeymap.scan_code(e.physical_keycode if e.physical_keycode else e.keycode)
	if sc < 0:
		sound("messbox\\cancel")
		return
	_waiting = false
	if not _rows.has(_sel) or _rows[_sel].kind != "keys":
		queue_redraw()
		return
	sound("messbox\\ok")
	var act: String = _rows[_sel].name
	var other := String(_kmap.get(sc, ""))
	if other != "" and other != act:
		_box = MessageBox.ask(self, "key_already_mapped", "key_already_mapped_msg",
			[EIKeymap.display_name(EIKeymap.ini_name(sc)), _action_label(other)])
		_box.answered.connect(func(yes: bool):
			_box = null
			if yes:
				_assign(act, sc)
			queue_redraw()
			_board.visible = true)
		_board.visible = false
		queue_redraw()
		return
	_assign(act, sc)


## unless the key is already this action's, the action's listed
## keys are unbound and replaced by it, and it leaves the list of the action
## that had it; then the key maps to the action.
func _assign(act: String, sc: int) -> void:
	var other := String(_kmap.get(sc, ""))
	if other != act:
		for old: int in _klist.get(act, []):
			_kmap.erase(old)
		_klist[act] = [sc]
		if other != "" and _klist.has(other):
			(_klist[other] as Array).erase(sc)
	_kmap[sc] = act
	_refresh_keys()


## Row 12 of the three remake graphics pages (LOOK_PAGES) and Graphics row 8: the "Original look" toggle
## (GfxDetect.original_look_*). Checked while every gfx_* switch is off (the
## 2000 renderer's look; the always-on quality settings in project.godot keep
## their colours). A press while unchecked switches them all off; a press
## while checked brings them back as a fresh install has them on this
## platform, or as the graphics test chose them when its settings were in
## force before Original look was switched on. Pending until ✓ like the
## other rows; the box is the original's checkbox (saveload UV 209,55-230,76,
## checked u − 23, as the New Game difficulty box) with the switches' On / Off.
const PRESET_ROW := 12
## Graphics row 7 (under auto_graphics): the graphics test now (GfxDetect);
## the screen closes with its changes applied first.
const DETECT_ROW := 7
const DETECT_LINK := ["Detect best settings",
	"Runs a short graphics test (a few seconds) and picks the settings this device runs smoothly. Replaces the current graphics settings."]
const ORIGINAL_LOOK := ["Original look",
	"On: every remake graphics effect is off, leaving the original 2000 look. Off again: the effects come back as a new installation has them on this device, or as the graphics test chose them if its settings were in force before (confirm with ✓)."]


func _look_row() -> Dictionary:
	return {"kind": "link", "name": "", "preset": true, "label": RemakeText.t(ORIGINAL_LOOK[0]),
		"tip": RemakeText.t("%s\n%s\n(Remake option.)") % RemakeText.tl(ORIGINAL_LOOK)}


## The Original look toggle (PRESET_ROW): the gfx_* rows' pending values.
func _toggle_original_look() -> void:
	var rec := GfxDetect.load_record()
	var on := not GfxDetect.original_look_on(_values)
	if on:
		_look_from = GfxDetect.original_look_from(rec, _values)
	var from := _look_from if _look_from != -2 else int(rec.get("original_look_from", -1))
	var vals := GfxDetect.original_look_values(on, rec, from)
	for k: String in vals:
		_set_value(k, int(vals[k]))
	queue_redraw()


func _switch_text(row: Dictionary) -> String:
	var v := int(_values.get(row.name, 0))
	var choices: Array = row.get("choices", [])
	if not choices.is_empty():
		return String(choices[clampi(v, 0, choices.size() - 1)])
	if row.name == "difficulty":
		#  row 0x19: difficulty_hard ("Normal") / difficulty_easy ("Novice").
		return _t("string difficulty_easy", "Novice") if v == 1 else _t("string difficulty_hard", "Normal")
	return _t("string option_on", "On") if v == 1 else _t("string option_off", "Off")


func _set_value(name: String, v: int) -> void:
	var was := int(_values.get(name, 0))
	_values[name] = v
	if name == "renderer" and v == RendererChoice.FORWARD_PLUS and was != v and RendererChoice.available():
		_ask_experimental(was)
	if name in ["camera_style", "cam_wasd"]:
		_select_key_profile()
		_refresh_keys()
	if name in LIVE:   # volumes, gamma ramp, stereo at once
		GameData.set_option(name, v)
	queue_redraw()


func _toggle(r: int) -> void:
	if not _rows.has(r):
		return
	var row: Dictionary = _rows[r]
	match row.kind:
		"switch":
			sound("messbox\\ok")
			_set_value(row.name, (int(_values.get(row.name, 0)) + 1) % int(row.max))
		"link":
			sound("messbox\\ok" if row.get("preset", false) else "save\\select")   # Original look: a switch's sound
			if row.get("detect", false):
				_apply()
				_close()
				GfxDetect.start(true)
			elif row.get("gyro_calibrate", false):
				if not PadInput.gyro.calibrate(PadInput.device):
					_rows[r].tip = "<messbox>" + RemakeText.t("No gyroscope is available.") + "</messbox>"
					_sel = r
					queue_redraw()
			elif row.get("pad_defaults", false):
				_pad_map = PadInput.DEFAULTS.duplicate()
				_refresh_pad()
			elif row.get("preset", false):
				_toggle_original_look()
			elif row.get("export_log", false):
				_box = CrashReportBox.open(self, {})
				_box.answered.connect(func(_yes):
					_box = null
					_board.visible = true
					queue_redraw())
				_board.visible = false
				queue_redraw()
			elif row.get("files", false):
				if row.get("disabled", false):
					return
				if _changed():   # pending rows as ✓; nothing written otherwise
					_apply()
				_close()
				game_files_requested.emit()
			elif int(row.to) == _parent(_group):
				_go_back()
			else:
				_show_group(row.to)


## ✓: every changed row is written to the settings, the key
## map copied back.
func _accept() -> void:
	sound("messbox\\ok")
	_apply()
	_close()


func _apply() -> void:
	for profile: int in _key_profiles:
		EIKeymap.set_bindings(_key_profiles[profile], profile)
	if not _pad_map.is_empty() and _pad_map != PadInput.bindings:
		PadInput.save_bindings(_pad_map)
	# Original look switched (by its row or the switches one by one): the
	# player's choice, noted in the detection record (GfxDetect).
	var look := GfxDetect.original_look_on(_values)
	if look != GfxDetect.original_look_on(_snapshot):
		var rec := GfxDetect.load_record()
		var from := _look_from if _look_from != -2 else GfxDetect.original_look_from(rec, _snapshot)
		GfxDetect.save_record(GfxDetect.original_look_record(rec, look, from))
	var renderer := int(_values.get("renderer", 0)) != GameData.option("renderer")
	for n in _values:
		if int(_values[n]) != GameData.option(n):
			GameData.set_option(n, int(_values[n]))
	if renderer and get_parent():
		RendererChoice.ask_restart(get_parent(), game_files)   # applies at the next start


## ✗ / Esc (case 1): the live rows go back.
## Remake: with a row or key changed since the screen opened, a message box
## (MessageBox, ✓ / ✗) asks first whether to save them: ✓ applies them as the
## ✓ button does, ✗ drops them; either way the screen closes. Esc on the box
## (unlike the original's boxes, where it answers ✗) closes it and stays on the
## screen with the changes kept.
func _cancel() -> void:
	if _changed():
		_ask_unsaved()
		return
	sound("messbox\\cancel")
	_restore()
	_close()


func _restore() -> void:
	for n in LIVE:
		if GameData.option(n) != int(_snapshot.get(n, 0)):
			GameData.set_option(n, int(_snapshot[n]))


## Any row's value or the key map differs from what the screen opened with.
func _changed() -> bool:
	for n in _values:
		if int(_values[n]) != int(_snapshot.get(n, 0)):
			return true
	for profile: int in _key_profiles:
		if _key_profiles[profile] != EIKeymap.bindings(profile):
			return true
	return not _pad_map.is_empty() and _pad_map != PadInput.bindings


func _ask_unsaved() -> void:
	_waiting = false
	_drag = -1
	_hold = -1
	_box = MessageBox.new()
	_box.title = RemakeText.t("Options")
	_box.message = RemakeText.t("Some settings were changed but not applied. Save them?")
	_box.esc_closes = true
	add_child(_box)
	_box.dismissed.connect(func():
		_box = null
		_board.visible = true
		queue_redraw())
	_box.answered.connect(func(yes: bool):
		_box = null
		_board.visible = true
		if yes:
			_apply()
		else:
			_restore()
		_close())
	_board.visible = false
	queue_redraw()


## The renderer row stepped to Forward+ (RendererChoice.EXPERIMENTAL): ✓
## keeps it, ✗ / Esc puts the row back to `was`.
func _ask_experimental(was: int) -> void:
	_waiting = false
	_drag = -1
	_hold = -1
	_box = RendererChoice.ask_experimental(self)
	_box.answered.connect(func(yes: bool):
		_box = null
		_board.visible = true
		if not yes:
			_values.renderer = was
		queue_redraw())
	_board.visible = false


# ------------------------------------------------------------------ drawing

func group_font_px(g: int) -> int:
	var fs := font_px(1)
	var label := _group_label(g)
	var width := r8(Rect2(0, 0, 122, 20)).size.x
	while fs > 6 and font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 1
	return fs


func _draw_group_label(r: Rect2, group: int, col: Color) -> void:
	if hide_text:
		return
	var f := font()
	var fs := group_font_px(group)
	var rr := r8(r)
	var y := rr.position.y + f.get_ascent(fs)
	var sh := maxf(1.0, round(kv().y))
	var label := _group_label(group)
	draw_string(f, Vector2(rr.position.x + sh, y + sh), label, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, fs, SHADOW)
	draw_string(f, Vector2(rr.position.x, y), label, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, fs, col)


static func _row_y(r: int) -> float:
	return 156.0 + 24.0 * r


static func _slider_rect(r: int) -> Rect2:
	return Rect2(530, 163 + 24 * r, 150, 10)


func _draw() -> void:
	if MessageBox.is_up(_box):
		return   # the frozen frame and the box only
	var ui := tex("saveload")
	panel(Rect2(100, 100, 600, 400))
	text(Rect2(100, 110, 600, 24), _group_label(_group), 2, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	# Group buttons.
	for i in _group_count():
		var g: int = TAB_ORDER[i]
		var y := _row_y(i)
		var cur := g == _tab()
		sprite(ui, Rect2(110, y + 2, 130, 19), [122, 108, 252, 127], Color(1, 1, 1) if cur else Color(0.5, 0.5, 0.5))
		_draw_group_label(Rect2(110, y + 4, 130, 20), g, TEXT if cur else GREY)
	# Selection bar.
	if _sel >= 0:
		draw_rect(r8(Rect2(250, _row_y(_sel), 442, 24)), BAR)
	# Rows.
	for r: int in _rows:
		var row: Dictionary = _rows[r]
		var y := _row_y(r)
		var col := TEXT if row.kind in ["keys", "link", "padbtn"] or row.name in GameData.OPTIONS_APPLIED else GREY
		if row.get("disabled", false):
			col = GREY
		if row.kind in ["keys", "padbtn"] and r == _sel and _waiting:
			col = Color8(0xff, 0, 0)   # COLORREF 0xff while waiting
		text(Rect2(260, y + 4, 260 if row.kind != "link" or row.get("preset", false) else 430, 20), row.label, 1, col)
		if row.get("preset", false):   # Original look: the checkbox and On / Off
			var on := GfxDetect.original_look_on(_values)
			sprite(ui, Rect2(530, y + 1.5, 21, 21), [186, 55, 207, 76] if on else [209, 55, 230, 76])
			text(Rect2(558, y + 4, 132, 16), _t("string option_on", "On") if on else _t("string option_off", "Off"), 1, TEXT)
		match row.kind:
			"slider":
				hslider(_slider_rect(r), float(_values.get(row.name, 0)), float(row.max))
			"switch":
				text(Rect2(530, y + 4, 160, 16), _switch_text(row), 1, TEXT)
			"keys":
				text(Rect2(530, y + 4, 160, 20), row["keys"], 1, col)
			"padbtn":
				_draw_pad_buttons(r, y, col)
	# ✓ / ✗.
	sprite(ui, OK_RECT, [81, 2, 155, 50])
	sprite(ui, CANCEL_RECT, [160, 2, 234, 50])


# ------------------------------------------------------------------ input

## The original's hit order: 0 ✓, 1 ✗, 2..12 groups, 13.. rows.
func _hit(p: Vector2) -> Array:
	if OK_RECT.has_point(p):
		return ["ok"]
	if CANCEL_RECT.has_point(p):
		return ["cancel"]
	for i in _group_count():
		if Rect2(100, _row_y(i), 150, 24).has_point(p):
			return ["group", TAB_ORDER[i]]
	for r: int in _rows:
		var row: Dictionary = _rows[r]
		if row.kind == "slider":
			var part := hslider_hit(_slider_rect(r), float(_values.get(row.name, 0)), float(row.max), p)
			if part:
				return ["slider", r, part]
		elif row.kind == "switch" and Rect2(530, _row_y(r) + 4, 160, 16).has_point(p):
			return ["switch", r]
		if Rect2(250, _row_y(r), 270, 24).has_point(p):
			return ["row", r]
		# Remake: a key row also takes clicks on its key names (530..692, under
		# the selection bar 250..692); the original's row regions
		# end at 520 (: (250, y, 520, y + 24)), so a
		# double click on the key itself did nothing.
		if (row.kind in ["keys", "padbtn"] or row.get("preset", false)) and Rect2(520, _row_y(r), 172, 24).has_point(p):
			return ["row", r]
	return []


func _get_tooltip(at: Vector2) -> String:
	var h := _hit(to800(at))
	if h.is_empty():
		return ""
	match h[0]:
		"ok": return GameData.text("tip 70100").strip_edges()
		"cancel": return GameData.text("tip 70101").strip_edges()
		"group": return _group_tip(h[1])
		_: return String(_rows[h[1]].tip)


func _gui_input(e: InputEvent) -> void:
	if not visible or MessageBox.is_up(_box) or _tutorial.visible:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if not e.pressed:
			_drag = -1
			_hold = -1
			accept_event()
			return
		var p := to800(e.position)
		var h := _hit(p)
		if not h.is_empty():
			match h[0]:
				"ok": _accept()
				"cancel": _cancel()
				"group":
					sound("save\\select")
					_waiting = false
					_show_group(h[1])
				"switch": _toggle(h[1])
				"row":
					if _rows[h[1]].kind == "link":
						_toggle(h[1])
					elif e.double_click and _rows[h[1]].kind == "padbtn":
						sound("save\\select")
						_sel = h[1]
						_start_pad_wait()
					elif e.double_click and _rows[h[1]].kind == "keys":
						# select.wav, the row waits for a key.
						sound("save\\select")
						_sel = h[1]
						_waiting = true
						queue_redraw()
					elif e.double_click:
						_toggle(h[1])
					else:   # select.wav, waiting stops
						sound("save\\select")
						_sel = h[1]
						_waiting = false
						queue_redraw()
				"slider":
					match h[2]:
						"thumb": _drag = h[1]
						"left", "right":
							_hold = h[1]
							_hold_dir = -1 if h[2] == "left" else 1
							_hold_acc = 0.0
		accept_event()
	elif e is InputEventMouseMotion and _drag >= 0 and _rows.has(_drag):
		var row: Dictionary = _rows[_drag]
		var v := hslider_value(_slider_rect(_drag), float(row.max), to800(e.position).x)
		if v != int(_values.get(row.name, 0)):
			_set_value(row.name, v)
		accept_event()


## a held arrow moves dt · speed (1) · 16 units per second.
func _process(dt: float) -> void:
	if visible and _slide < 1.0:
		_slide += dt / 0.5
		_place_board()
		if _slide >= 1.0:   # the end of the slide-
			hide_text = false
			queue_redraw()
			_tutorial.show_screen("options")
	if not visible or _hold < 0 or not _rows.has(_hold):
		return
	_hold_acc += dt * 16.0 * _hold_dir
	var step := int(_hold_acc)
	if step != 0:
		_hold_acc -= step
		var row: Dictionary = _rows[_hold]
		_set_value(row.name, clampi(int(_values.get(row.name, 0)) + step, 0, int(row.max)))


func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey and e.pressed):
		return
	if MessageBox.is_up(_box) or _tutorial.visible:
		return
	if _waiting:
		_key_pressed(e)
		get_viewport().set_input_as_handled()
		return
	match e.keycode:
		KEY_ESCAPE:
			if _parent(_group) >= 0:   # remake: a sub-page goes back one level (B too)
				sound("save\\select")
				_go_back()
			else:
				_cancel()
		KEY_ENTER, KEY_KP_ENTER:
			if _rows.has(_sel) and _rows[_sel].kind == "padbtn":   # remake: wait for a controller button
				sound("messbox\\ok")
				_start_pad_wait()
			elif _rows.has(_sel) and _rows[_sel].kind == "keys":   # case 0xd
				_waiting = true
				sound("messbox\\ok")
				queue_redraw()
			else:
				_toggle(_sel)
		KEY_PAGEUP, KEY_PAGEDOWN:
			sound("save\\select")   # remake: the buttons wrap around (first ↔ last)
			var i := TAB_ORDER.find(_tab()) + (-1 if e.keycode == KEY_PAGEUP else 1)
			_show_group(TAB_ORDER[posmod(i, TAB_ORDER.size())])
		KEY_LEFT, KEY_RIGHT:
			if _rows.has(_sel) and _rows[_sel].kind == "slider":
				var row: Dictionary = _rows[_sel]
				var d := -1 if e.keycode == KEY_LEFT else 1
				_set_value(row.name, clampi(int(_values.get(row.name, 0)) + d, 0, int(row.max)))
			elif _rows.has(_sel) and not (_rows[_sel].get("choices", []) as Array).is_empty():
				# Remake choice rows: Left / Right step through the choices.
				var row: Dictionary = _rows[_sel]
				var d := -1 if e.keycode == KEY_LEFT else 1
				sound("messbox\\ok")
				_set_value(row.name, posmod(int(_values.get(row.name, 0)) + d, int(row.max)))
		KEY_UP, KEY_DOWN:
			sound("save\\select")
			var d := -1 if e.keycode == KEY_UP else 1
			var r := _sel
			for i in 14:   # remake: wraps around (top ↔ bottom), past empty and grey rows
				r = posmod(r + d, 14)
				if _rows.has(r) and not _rows[r].get("disabled", false):
					_sel = r
					break
			queue_redraw()
		_:
			# a key the screen leaves alone that maps to
			# tutorial_script shows the screen's tutorial ((1)).
			if EIKeymap.event_action(e) == "tutorial_script" and not e.echo:
				_tutorial.show_screen("options", true)
			else:
				return
	get_viewport().set_input_as_handled()


## A "string <id>" text; missing from texts.res, the original's gives
## the id itself (the German texts.res has no difficulty_easy / _hard /
## option_difficulty). `fallback` only without game data (tools).
static func _t(key: String, fallback: String) -> String:
	if GameData.texts == null:
		return fallback
	var t := GameData.text(key).strip_edges()
	return t if t else key.trim_prefix("string ")


# ------------------------------------------------------------------ gamepad

## Remake: the button rows' text, from the edited layout.
func _refresh_pad() -> void:
	for r: int in _rows:
		if _rows[r].kind == "padbtn":
			var names: Array = []
			for b: String in ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "L3", "R3", "VIEW", "MENU", "TOUCHPAD", "SHARE"]:
				if b in ["TOUCHPAD", "SHARE"] and PadInput.family() != "ps":
					continue   # PlayStation's extra buttons
				if _pad_map.get(b, "") == _rows[r].name:
					names.append(b)
			_rows[r]["buttons"] = names
			_rows[r]["keys"] = "  |  ".join(names.map(func(b): return PadInput.label(b)))
	queue_redraw()


func _draw_pad_buttons(r: int, y: float, col: Color) -> void:
	var x := 530.0
	for b: String in _rows[r].get("buttons", []):
		var tex := PadInput.glyph(b)
		if tex:
			draw_texture_rect(tex, r8(Rect2(x, y + 2, 20, 20)), false)
			x += 24.0
		else:
			text(Rect2(x, y + 4, 60, 20), PadInput.label(b), 1, col)
			x += 40.0


func _start_pad_wait() -> void:
	_waiting = true
	PadInput.capture = self
	queue_redraw()


func _stop_pad_wait() -> void:
	if PadInput.capture == self:
		PadInput.capture = null


## PadInput while a button row waits: the pressed button takes the row's
## action; the action that had it gets this row's old button (a swap, so no
## action is left without a button). Menu stops waiting.
func pad_capture(button: String) -> bool:
	if not visible or not _waiting or not _rows.has(_sel) or _rows[_sel].kind != "padbtn":
		_stop_pad_wait()
		return false
	_waiting = false
	_stop_pad_wait()
	if button == "MENU":
		sound("messbox\\cancel")
		queue_redraw()
		return true
	var act: String = _rows[_sel].name
	var other := String(_pad_map.get(button, ""))
	var old := ""
	for b: String in _pad_map:
		if _pad_map[b] == act and b != button and old == "":
			old = b
	if old != "":
		_pad_map.erase(old)
	_pad_map[button] = act
	if other != "" and other != act and old != "":
		_pad_map[old] = other
	sound("messbox\\ok")
	_refresh_pad()
	return true


## PadUI: Y is ✓; Menu closes from any page as ✗ (B, the key bridge's Esc,
## goes back one level on a sub-page). The rest through the key bridge.
func pad_press(action: String, phase: String) -> bool:
	if phase != "down" or not visible or _waiting or MessageBox.is_up(_box) or _tutorial.visible:
		return false
	if action == "pause":
		_accept()
		return true
	if action == "menu":
		_cancel()
		return true
	return false


func pad_targets() -> Array:
	return []
