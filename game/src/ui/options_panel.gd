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
## Remake: the Graphics (video) page ends with a row "Remake graphics…" (row
## 13, free in the original's table) opening a sub-page under the same tab with the
## remake's own switches (GameData.REMAKE_OPTIONS), all marked as the remake's.
## The original's three shadow switches (Graphics rows 0..2) are not offered (always
## on, GameData.FIXED_OPTIONS); their rows and the free rows 3 / 9 hold the
## remake's display rows (display mode, resolution, frame-rate limit, VSync,
## FPS counter; render scale on the sub-page): multiple-choice rows stepped by
## a click / Enter (forward) or Left / Right, applied at once like the volumes
## and restored by ✗.
## Remake: the Game page's free row 13 "Remake extras…" opens the co-op host
## settings and the single-player game-over notice switch (COOP_GROUP) under
## the Game tab; its row 13 leads back.
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

const REMAKE_GROUP := 11   # GameData.OPTION_GROUPS index of the remake sub-page
const REMAKE_GROUP2 := 12  # its second page ("More effects…", row 13)
const COOP_GROUP := 13     # the remake's co-op page, from the Game page's row 13
const SURFACE_GROUP := 14  # lighting and surfaces, from More effects row 10
## The remake sub-pages and the original tab each belongs to (lit while it is up).
const SUB_PAGES := {REMAKE_GROUP: 0, REMAKE_GROUP2: 0, COOP_GROUP: 3, SURFACE_GROUP: 0}
const COOP_LINK := ["Remake extras…",
	"Co-op host settings: full experience for every party member, monsters scaled to the player count, opening the port on the router. Single player: the game-over notice at the hero's death."]
const MORE_LINK := ["More effects…", "HD textures, soft and lit particles, contact shadows, torch glow; anti-aliasing, shadow quality, texture filtering."]
const SURFACE_LINK := ["Lighting and surfaces…", "Dynamic firelight, surface materials, leaf backlighting, rain on surfaces and lava lighting."]
const TABS := 11           # the original's group buttons
const LINK_ROW := 13
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


func _ready() -> void:
	visible = false
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
	return TABS


## The tab lit for the page: the remake sub-page belongs to Graphics (0).
func _tab() -> int:
	return int(SUB_PAGES.get(_group, _group))


func _group_label(g: int) -> String:
	var key: String = GameData.OPTION_GROUPS[g]
	if GameData.REMAKE_OPTIONS.has(key):
		return "%s: %s" % [_group_label(int(SUB_PAGES.get(g, 0))), RemakeText.t(GameData.REMAKE_OPTIONS[key][0])]
	return _t("string option_group_" + key, key.capitalize())


func _group_tip(g: int) -> String:
	var key: String = GameData.OPTION_GROUPS[g]
	if GameData.REMAKE_OPTIONS.has(key):
		return RemakeText.t("%s\nThe remake's own settings; not part of the original game.") % RemakeText.t(GameData.REMAKE_OPTIONS[key][0])
	return GameData.text("tip option_group_" + key).strip_edges()


## the page's rows; the first row with a control is selected.
func _show_group(g: int) -> void:
	_group = g if SUB_PAGES.has(g) else clampi(g, 0, TABS - 1)
	_rows.clear()
	for o: Array in GameData.OPTIONS:
		if int(o[3]) != _group:
			continue
		var name: String = o[0]
		var label := _t("string option_" + name, name.capitalize()).trim_suffix(":").strip_edges()
		var tip := GameData.text("tip option_" + name).strip_edges()
		if GameData.REMAKE_OPTIONS.has(name):
			label = RemakeText.t(GameData.REMAKE_OPTIONS[name][0])
			tip = RemakeText.t("%s\n%s\n(Remake option.)") % [label, RemakeText.t(GameData.REMAKE_OPTIONS[name][1])]
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
			"tip": RemakeText.t("%s\n%s\n(Remake option.)") % RemakeText.tl(GameData.REMAKE_OPTIONS[name]) if GameData.REMAKE_OPTIONS.has(name)
				else GameData.text("tip action_" + name).strip_edges(),
			"keys": _keys_text(name)}
	if _group == 0:
		_rows[LINK_ROW] = {"kind": "link", "name": "", "to": REMAKE_GROUP,
			"label": RemakeText.t(REMAKE_LINK[0]), "tip": RemakeText.t("%s\n%s\n(Remake option.)") % RemakeText.tl(REMAKE_LINK)}
	elif _group == REMAKE_GROUP:
		_rows[LINK_ROW] = {"kind": "link", "name": "", "to": REMAKE_GROUP2,
			"label": RemakeText.t(MORE_LINK[0]), "tip": RemakeText.t("%s\n%s\n(Remake option.)") % RemakeText.tl(MORE_LINK)}
		_rows[PRESET_ROW] = {"kind": "link", "name": "", "preset": true,
			"label": RemakeText.t(ORIGINAL_LOOK[0]), "tip": RemakeText.t("%s\n%s\n(Remake option.)") % RemakeText.tl(ORIGINAL_LOOK)}
	elif _group == 3:   # remake: the Game page's free row 13
		_rows[LINK_ROW] = {"kind": "link", "name": "", "to": COOP_GROUP,
			"label": RemakeText.t(COOP_LINK[0]), "tip": RemakeText.t("%s\n%s\n(Remake option.)") % RemakeText.tl(COOP_LINK)}
	elif _group == COOP_GROUP:
		_rows[LINK_ROW] = {"kind": "link", "name": "", "to": 3,
			"label": "« " + _group_label(3), "tip": ""}
	elif _group == REMAKE_GROUP2:
		_rows[10] = {"kind": "link", "name": "", "to": SURFACE_GROUP,
			"label": RemakeText.t(SURFACE_LINK[0]), "tip": RemakeText.t("%s\n%s\n(Remake option.)") % RemakeText.tl(SURFACE_LINK)}
		_rows[LINK_ROW] = {"kind": "link", "name": "", "to": REMAKE_GROUP,
			"label": "« " + RemakeText.t(GameData.REMAKE_OPTIONS.graphics[0]).capitalize(), "tip": ""}
		_rows[PRESET_ROW] = {"kind": "link", "name": "", "preset": true,
			"label": RemakeText.t(ORIGINAL_LOOK[0]), "tip": RemakeText.t("%s\n%s\n(Remake option.)") % RemakeText.tl(ORIGINAL_LOOK)}
	elif _group == SURFACE_GROUP:
		_rows[LINK_ROW] = {"kind": "link", "name": "", "to": REMAKE_GROUP2,
			"label": "« " + RemakeText.t(GameData.REMAKE_OPTIONS.graphics2[0]).capitalize(), "tip": ""}
		_rows[PRESET_ROW] = {"kind": "link", "name": "", "preset": true,
			"label": RemakeText.t(ORIGINAL_LOOK[0]), "tip": RemakeText.t("%s\n%s\n(Remake option.)") % RemakeText.tl(ORIGINAL_LOOK)}
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


const REMAKE_LINK := ["Remake options: graphics…",
	"The remake's own graphics switches (sky, water, fog, bloom…)."]
## Remake page row 12: every gfx_* switch off (the 2000 renderer's look; the
## always-on quality settings in project.godot keep their colours).
const PRESET_ROW := 12
const ORIGINAL_LOOK := ["Original look: all effects off",
	"Switches every remake graphics effect off, leaving the original 2000 look (confirm with ✓)."]


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
	_values[name] = v
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
			sound("save\\select")
			if row.get("preset", false):
				for o: Array in GameData.OPTIONS:
					if String(o[0]).begins_with("gfx_"):
						_set_value(o[0], 0)
				queue_redraw()
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
	for n in _values:
		if int(_values[n]) != GameData.option(n):
			GameData.set_option(n, int(_values[n]))


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
	return false


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


# ------------------------------------------------------------------ drawing

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
	for g in _group_count():
		var y := _row_y(g)
		var cur := g == _tab()
		sprite(ui, Rect2(110, y + 2, 130, 19), [122, 108, 252, 127], Color(1, 1, 1) if cur else Color(0.5, 0.5, 0.5))
		text(Rect2(110, y + 4, 130, 20), _group_label(g), 1, TEXT if cur else GREY, HORIZONTAL_ALIGNMENT_CENTER)   #  (10,60)-(140,80) + 24i
	# Selection bar.
	if _sel >= 0:
		draw_rect(r8(Rect2(250, _row_y(_sel), 442, 24)), BAR)
	# Rows.
	for r: int in _rows:
		var row: Dictionary = _rows[r]
		var y := _row_y(r)
		var col := TEXT if row.kind in ["keys", "link"] or row.name in GameData.OPTIONS_APPLIED else GREY
		if row.kind == "keys" and r == _sel and _waiting:
			col = Color8(0xff, 0, 0)   # COLORREF 0xff while waiting
		text(Rect2(260, y + 4, 260 if row.kind != "link" else 430, 20), row.label, 1, col)
		match row.kind:
			"slider":
				hslider(_slider_rect(r), float(_values.get(row.name, 0)), float(row.max))
			"switch":
				text(Rect2(530, y + 4, 160, 16), _switch_text(row), 1, TEXT)
			"keys":
				text(Rect2(530, y + 4, 160, 20), row["keys"], 1, col)
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
	for g in _group_count():
		if Rect2(100, _row_y(g), 150, 24).has_point(p):
			return ["group", g]
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
		if row.kind == "keys" and Rect2(520, _row_y(r), 172, 24).has_point(p):
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
			_cancel()
		KEY_ENTER, KEY_KP_ENTER:
			if _rows.has(_sel) and _rows[_sel].kind == "keys":   # case 0xd
				_waiting = true
				sound("messbox\\ok")
				queue_redraw()
			else:
				_toggle(_sel)
		KEY_PAGEUP, KEY_PAGEDOWN:
			sound("save\\select")
			_show_group(clampi(_tab() + (-1 if e.keycode == KEY_PAGEUP else 1), 0, TABS - 1))
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
			var r := _sel + d
			while r >= 0 and r < 14:
				if _rows.has(r):
					_sel = r
					break
				r += d
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
