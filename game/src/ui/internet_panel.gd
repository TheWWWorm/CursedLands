extends Interface800
## Optional remake internet browser, using the same panels, plates and text
## as the other menu screens. Keyboard, touch edit and gamepad snap targets.

signal chosen(game: Dictionary)
signal closed

const Directory := preload("res://src/game/internet_directory.gd")
const ROWS := 7
const LIST := Rect2(110, 206, 580, 168)
const ORANGE := Color8(255, 179, 49)

var host_page := false
var web := false
var directory: Node
var cfg := {}
var selected := -1
var top := 0
var _focus := ""
var _targets := {}
var _dim: Interface800.Backdrop


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_dim = Interface800.dim_layer()
	add_child(_dim)
	directory = Directory.new()
	add_child(directory)
	directory.changed.connect(queue_redraw)
	resized.connect(queue_redraw)
	add_to_group("pad_panel")


func open(host: bool, in_browser: bool, background: Image = null) -> void:
	host_page = host
	web = in_browser
	cfg = Directory.settings()
	selected = -1
	top = 0
	_focus = "url" if String(cfg.url).is_empty() else ""
	_dim.use(background)
	visible = true
	grab_focus()
	if not String(cfg.url).is_empty():
		directory.refresh(String(cfg.url))
	queue_redraw()


func _save() -> bool:
	if not String(cfg.url).strip_edges().is_empty() and Directory.clean_url(String(cfg.url)).is_empty():
		directory.status = RemakeText.t("Enter an http:// or https:// directory URL.")
		queue_redraw()
		return false
	Directory.save_settings(cfg, get_tree())
	return true


func close() -> void:
	if not _save():
		return
	visible = false
	directory._http.cancel_request()
	closed.emit()


func _draw() -> void:
	if not visible:
		return
	_targets.clear()
	panel(Rect2(90, 50, 620, 470))
	text(Rect2(110, 65, 580, 26), RemakeText.t("Internet games"), 2, ORANGE, HORIZONTAL_ALIGNMENT_CENTER)
	text(Rect2(110, 98, 580, 20), RemakeText.t("Game directory URL"), 1)
	_field("url", Rect2(110, 121, 490, 24), String(cfg.url))
	_plate("paste", Rect2(612, 121, 78, 24), RemakeText.t("Paste"))
	text(Rect2(110, 151, 440, 38), RemakeText.t("Choose a directory run by your community."), 0, GREY)
	_plate("refresh", Rect2(570, 151, 120, 24), RemakeText.t("Refresh"))
	text(Rect2(110, 181, 580, 20), String(directory.status), 0, GREY)
	top = clampi(top, 0, maxi(0, directory.games.size() - ROWS))
	for i in ROWS:
		var n := top + i
		if n >= directory.games.size():
			break
		var g: Dictionary = directory.games[n]
		var rr := Rect2(LIST.position.x, LIST.position.y + 24 * i, LIST.size.x - 14, 24)
		_targets["game:%d" % n] = rr
		if n == selected:
			draw_rect(r8(rr), BAR)
		var col := TEXT if Directory.can_join(g, web) else GREY
		text_vc(Rect2(rr.position.x + 4, rr.position.y, 285, 24), String(g.name) if String(g.name) else String(g.address), 1, col)
		text_vc(Rect2(402, rr.position.y, 65, 24), "%d/%d" % [g.players, g.max], 1, col)
		var kind := LmpMode.base_title(String(g.base)) if g.mode == "lmp" else RemakeText.t("Co-op campaign")
		text_vc(Rect2(474, rr.position.y, 182, 24), kind, 0, col)
		if g.pw:
			text_vc(Rect2(660, rr.position.y, 16, 24), "*", 1, col)
	vbar(LIST, float(top), float(directory.games.size() - ROWS))
	if host_page:
		_targets["public"] = Rect2(110, 393, 580, 24)
		text(Rect2(110, 393, 440, 24), RemakeText.t("List my hosted game publicly"), 1)
		text(Rect2(570, 393, 120, 24), RemakeText.t("On") if cfg.public else RemakeText.t("Off"), 1, ORANGE)
		text(Rect2(110, 425, 580, 20), RemakeText.t("Public join address (blank: detect IP and port)"), 0)
		_field("address", Rect2(110, 448, 490, 24), String(cfg.address))
		_plate("paste_address", Rect2(612, 448, 78, 24), RemakeText.t("Paste"))
		text(Rect2(110, 480, 580, 22), RemakeText.t("Your router must allow connections to the game's port."), 0, GREY)
	else:
		var g := _selected()
		if not g.is_empty():
			text(Rect2(110, 393, 580, 24), String(g.address), 1, ORANGE)
			var hint := RemakeText.t("Password required") if g.pw else ""
			if not Directory.can_join(g, web):
				hint = RemakeText.t("This game uses another protocol.") if int(g.protocol) != NetStatus.PROTOCOL else RemakeText.t("Browser players need a wss:// game address.")
			text(Rect2(110, 425, 580, 24), hint, 0, GREY)
		_plate("use", Rect2(110, 480, 160, 24), RemakeText.t("Use address"), not g.is_empty() and Directory.can_join(g, web))
	_plate("close", Rect2(570, 540, 120, 26), RemakeText.t("Back"))


func _plate(id: String, r: Rect2, label: String, on := true) -> void:
	if on:
		_targets[id] = r
	sprite(tex("saveload"), r, [122, 108, 252, 127], Color.WHITE if on else Color(0.5, 0.5, 0.5))
	text_vc(r, label, 1, TEXT if on else GREY, HORIZONTAL_ALIGNMENT_CENTER)


func _field(id: String, r: Rect2, value: String) -> void:
	_targets[id] = r
	draw_rect(r8(r), Color(0, 0, 0, 0.7))
	frame(r, 2)
	var shown := value + (" |" if _focus == id else "")
	var width := (r.size.x - 8) * kv().x
	while shown.length() > 1 and font().get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px(1)).x > width:
		shown = shown.substr(1)
	text_vc(r.grow(-4), shown, 1)


func _selected() -> Dictionary:
	return directory.games[selected] if selected >= 0 and selected < directory.games.size() else {}


func _activate(id: String) -> void:
	_focus = ""
	if id in ["url", "address"]:
		_focus = id
		if TouchInput.enabled:
			TouchTextEdit.open(self, String(cfg[id]), 256, func(v): cfg[id] = v; queue_redraw(), "Game directory URL" if id == "url" else "Server address")
	elif id in ["paste", "paste_address"]:
		cfg["url" if id == "paste" else "address"] = DisplayServer.clipboard_get().strip_edges().get_slice("\n", 0).left(256)
	elif id == "refresh":
		if _save():
			selected = -1
			directory.refresh(String(cfg.url))
	elif id == "public":
		cfg.public = not cfg.public
	elif id == "close":
		close()
	elif id.begins_with("game:"):
		selected = int(id.trim_prefix("game:"))
	elif id == "use":
		var g := _selected()
		if not g.is_empty() and Directory.can_join(g, web) and _save():
			visible = false
			chosen.emit(g)
			closed.emit()
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	accept_event()
	var p := to800(e.position)
	if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and LIST.has_point(p):
		top = clampi(top + (-1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1), 0, maxi(0, directory.games.size() - ROWS))
	elif e.button_index == MOUSE_BUTTON_LEFT:
		var part := vbar_hit(LIST, float(top), float(directory.games.size() - ROWS), p)
		if part:
			top = vbar_value(LIST, float(directory.games.size() - ROWS), p.y)
		else:
			for id: String in _targets:
				if (_targets[id] as Rect2).has_point(p):
					_activate(id)
					break
	queue_redraw()


func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_ESCAPE: close()
		KEY_ENTER, KEY_KP_ENTER:
			if _focus:
				_activate("refresh" if _focus == "url" else "close")
			else:
				_activate("use")
		KEY_TAB: _activate("address" if _focus == "url" and host_page else "url")
		KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN:
			_focus = ""
			var step := ROWS if e.keycode in [KEY_PAGEUP, KEY_PAGEDOWN] else 1
			selected = clampi(selected + (-step if e.keycode in [KEY_UP, KEY_PAGEUP] else step), 0, directory.games.size() - 1)
			top = clampi(top, maxi(0, selected - ROWS + 1), maxi(0, selected))
		KEY_BACKSPACE:
			if _focus:
				cfg[_focus] = String(cfg[_focus]).left(-1)
		_:
			if _focus and e.keycode == KEY_V and (e.ctrl_pressed or e.meta_pressed):
				cfg[_focus] = DisplayServer.clipboard_get().strip_edges().get_slice("\n", 0).left(256)
			elif _focus and e.unicode >= 32:
				cfg[_focus] = (String(cfg[_focus]) + char(e.unicode)).left(256)
			else:
				return
	get_viewport().set_input_as_handled()
	queue_redraw()


func pad_targets() -> Array:
	var out := []
	for id: String in _targets:
		out.append({"id": id, "rect": pad_rect(_targets[id])})
	return out


func pad_press(action: String, phase: String) -> bool:
	if phase == "down" and action == "cancel":
		close()
		return true
	return false
