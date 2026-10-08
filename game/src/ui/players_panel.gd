class_name PlayersPanel
extends Interface800
## Remake: the co-op host's player list in the game (the original has no in-game
## counterpart: its LMP server kicks and bans from the server console, and
## only the lines textslmp.res «lmp_player_kicked» / «lmp_player_banned»
## and the refusal «lmp_you_are_banned» reach the players; NetStatus.kick).
## Opened from the Esc menu's "Players" button (EscButton below, host only)
## or a click on the player list (PlayerList). The look is the message
## box's and GameOverNotice's: a panel in the 5 px saveload frame
## the title in font 2, lines in font 1, the buttons drawn as the
## Options screen's group buttons (saveload UV 122,108-252,127; 0.6 at rest,
## 1.0 under the pointer). One line per player: the name in the player's
## colour, the ping, and for every other player Kick and Ban (each asks
## first, MessageBox). Kick drops the player (their hero stays with the
## party under AI control, as after a lost connection, and is given back if
## they join again); Ban also refuses them (by name and address) for the
## rest of this hosting session. The host's own line has no buttons. In
## 800×600 units scaled evenly to fit the screen (a phone held upright too)
## and centred.

signal closed

const X := 210.0
const W := 380.0
const ROW_H := 22.0
const BTN_W := 70.0
const BTN_H := 20.0

var session: Session
var _hover := ""
var _box: MessageBox


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = " "
	visible = false
	resized.connect(queue_redraw)
	add_to_group("pad_panel")   # remake: gamepad snap targets on the buttons


func open() -> void:
	visible = true
	_hover = ""
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	if MessageBox.is_up(_box):
		_box.queue_free()
	_box = null
	closed.emit()


# Even scale (the whole panel fits a narrow screen too), centred.
func _k() -> float:
	return minf(maxf(size.y, 1.0) / 600.0, maxf(size.x, 1.0) / 800.0)


func kv() -> Vector2:
	return Vector2(_k(), _k())


func _origin() -> Vector2:
	return (size - Vector2(800.0, 600.0) * _k()) * 0.5


func font_px(i: int) -> int:
	return maxi(9, int(round(800.0 * _k() * FONT_EM[i])))


## [pid, name, colour, ping text] sorted by player slot, the host first.
func rows() -> Array:
	var out := []
	if session == null:
		return out
	var pids := session.players.keys()
	pids.sort_custom(func(a, b): return int(session.players[a].index) < int(session.players[b].index))
	for pid in pids:
		var p: Dictionary = session.players[pid]
		var st: Dictionary = session.net.status.get(pid, {})
		var ping := RemakeText.t("host") if int(p.index) == 0 else (NetStatus.state_text("connect")
			if String(st.get("state", "connect")) == "connect" else "%d ms" % int(st.get("ping", 0)))
		out.append([int(pid), String(p.name), NetStatus.colour(int(p.index), session.players), ping])
	return out


func _layout() -> Dictionary:
	var th := line_h(2)
	var list := rows()
	var top := 300.0 - (th + 16.0 + list.size() * ROW_H + BTN_H + 26.0) * 0.5
	var y := top + 8.0 + th + 8.0
	var btn := {}
	var lines := []
	for r: Array in list:
		lines.append([r, y])
		if r[0] != session.host_player_id():
			btn["kick:%d" % r[0]] = Rect2(X + W - 10.0 - BTN_W * 2.0 - 6.0, y + 1.0, BTN_W, BTN_H)
			btn["ban:%d" % r[0]] = Rect2(X + W - 10.0 - BTN_W, y + 1.0, BTN_W, BTN_H)
		y += ROW_H
	y += 8.0
	btn["close"] = Rect2(X + (W - BTN_W * 1.4) * 0.5, y, BTN_W * 1.4, BTN_H)
	return {"top": top, "th": th, "lines": lines, "btn": btn, "panel": Rect2(X, top, W, y + BTN_H + 8.0 - top)}


func _draw() -> void:
	if MessageBox.is_up(_box):   # the screen under a box is not drawn (MessageBox)
		return
	var l := _layout()
	var ui := tex("saveload")
	panel(l.panel)
	text_block(Rect2(X + 10.0, l.top + 8.0, W - 20.0, l.th), RemakeText.t("Players"), 2,
		Interface800.colorref(0x31b3ff), HORIZONTAL_ALIGNMENT_CENTER)
	for e: Array in l.lines:
		var r: Array = e[0]
		var y: float = e[1]
		text_vc(Rect2(X + 12.0, y, 150.0, ROW_H), r[1], 1, r[2], HORIZONTAL_ALIGNMENT_LEFT)
		text_vc(Rect2(X + 162.0, y, 60.0, ROW_H), r[3], 1, GREY, HORIZONTAL_ALIGNMENT_RIGHT)
	for b: String in l.btn:
		var r: Rect2 = l.btn[b]
		var on := b == _hover
		if ui:
			sprite(ui, r, [122, 108, 252, 127], Color(1, 1, 1, 1) * (1.0 if on else 0.6))
		else:
			draw_rect(r8(r), BAR if on else PANEL)
		text_vc(r, _label(b), 1, TEXT if on else GREY, HORIZONTAL_ALIGNMENT_CENTER)


func _label(b: String) -> String:
	match b.get_slice(":", 0):
		"kick": return RemakeText.t("Kick")
		"ban": return RemakeText.t("Ban")
	return RemakeText.t("Close")


func _button_at(at: Vector2) -> String:
	var p := to800(at)
	var l := _layout()
	for b: String in l.btn:
		if (l.btn[b] as Rect2).has_point(p):
			return b
	return ""


func _get_tooltip(at: Vector2) -> String:
	match _button_at(at).get_slice(":", 0):
		"kick": return RemakeText.t("Remove this player from the game. Their hero stays with the party under the computer's control until they join again.")
		"ban": return RemakeText.t("Remove this player and refuse their return until you stop hosting.")
	return ""


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var b := _button_at(e.position)
		if b != _hover:
			_hover = b
			queue_redraw()
	elif e is InputEventMouseButton:
		accept_event()
		if e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			press(_button_at(e.position))


## A button by id ("kick:<pid>", "ban:<pid>", "close"); tools call it too.
func press(b: String) -> void:
	if b == "":
		return
	if b == "close":
		sound("messbox\\cancel")
		close()
		return
	var pid := int(b.get_slice(":", 1))
	var ban := b.begins_with("ban:")
	if session == null or not session.players.has(pid) or pid == session.host_player_id():
		return
	sound("messbox\\ok")
	var who := String(session.players[pid].name)
	_box = MessageBox.new()
	_box.title = RemakeText.t("Ban") if ban else RemakeText.t("Kick")
	_box.message = (RemakeText.t("Remove %s from the game and refuse their return until you stop hosting?") if ban
		else RemakeText.t("Remove %s from the game?")) % who
	add_child(_box)
	_box.answered.connect(func(yes: bool):
		_box = null
		if yes and session and session.players.has(pid):
			session.net.kick(pid, ban)
		queue_redraw())


## Remake (gamepad, PadUI): Kick / Ban / Close as snap targets; while a box
## asks, its keys (A = ✓, B = ✗) take the pad.
func pad_active() -> bool:
	return not MessageBox.is_up(_box)


func pad_targets() -> Array:
	var out: Array = []
	var btn: Dictionary = _layout().btn
	for b: String in btn:
		out.append({"rect": pad_rect(btn[b]), "id": b})
	return out


func pad_focus() -> Variant:
	return "close"


## The box being asked (tools answer it).
func box() -> MessageBox:
	return _box if MessageBox.is_up(_box) else null


func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey and e.pressed) or MessageBox.is_up(_box):
		return
	if e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		press("close")


func _process(_dt: float) -> void:
	if not visible:
		return
	if session == null or not session.multiplayer_game or not session.can_manage_game():
		close()
		return
	queue_redraw()   # pings, players coming and going


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != "":
		_hover = ""
		queue_redraw()


## The Esc menu's "Players" button (host of an online game only), a group
## button in a small framed panel right of the signpost; same scaling.
class EscButton extends Interface800:
	signal pressed
	const R := Rect2(575.0, 410.0, 110.0, 22.0)
	var _on := false

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = " "
		visible = false

	func _k() -> float:
		return minf(maxf(size.y, 1.0) / 600.0, maxf(size.x, 1.0) / 800.0)

	func kv() -> Vector2:
		return Vector2(_k(), _k())

	func _origin() -> Vector2:
		return (size - Vector2(800.0, 600.0) * _k()) * 0.5

	func font_px(i: int) -> int:
		return maxi(9, int(round(800.0 * _k() * FONT_EM[i])))

	## Where the button is on the screen (tools click it).
	func rect() -> Rect2:
		return r8(R)

	func _has_point(point: Vector2) -> bool:
		return visible and R.grow(5.0).has_point(to800(point))

	func _draw() -> void:
		panel(R.grow(4.0))
		var ui := tex("saveload")
		if ui:
			sprite(ui, R, [122, 108, 252, 127], Color(1, 1, 1, 1) * (1.0 if _on else 0.6))
		text_vc(R, RemakeText.t("Players"), 1, TEXT if _on else GREY, HORIZONTAL_ALIGNMENT_CENTER)

	func _get_tooltip(_at: Vector2) -> String:
		return RemakeText.t("The players in this game; remove a player.")

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion and not _on:
			_on = true
			queue_redraw()
		elif e is InputEventMouseButton:
			accept_event()
			if e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
				sound("menu\\ok")
				pressed.emit()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT and _on:
			_on = false
			queue_redraw()
