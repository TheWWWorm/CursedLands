class_name NetworkPanel
extends Interface800
## The Multiplayer screen, drawn like the game's own menu screens (Options,
## Load / Save: Interface800, 800×600 units stretched to the window): the
## frozen, greyed frame, the main menu signpost's «Сетевая игра» board behind
##  panels in 5 px saveload frames, «saveload» plate buttons
## Options-style rows (label, on / off switch, choice with the scroll bar's
## arrows, slider) with the selection bar, ✓ / ✗ below; texts
## the screens' fonts and colours. Remake layout (the original's own network screen
## was a server list with a few switches):
## - the choice of game: four plate buttons in two groups, each with its line
##   of description (Host / Join co-op campaign; Host / Join multiplayer game);
## - each choice leads to a page of its own, with only the rows it needs:
##   Host co-op campaign — name, start from (a new game or a save), players,
##   full experience, monster scaling, router, WebSocket;
##   Host multiplayer game (LmpMode) — name, base, network character
##   (MpCharPanel), players, router, WebSocket;
##   Join co-op campaign — name, the host's address, the hero brought
##   (CoopProgress) and its class; Join multiplayer game — name, address,
##   network character;
## - host pages: a lower panel with the addresses to give friends ([Copy]),
##   the port and the router's result in plain words, and the players;
##   join pages: the recent addresses (a list as the Load screen's, Remove),
##   the address formats, and once connected what the host runs — a joiner on
##   the page of the other kind of game is moved to the right one (Session.
##   lobby_mode) and told why;
## - ✓ (its action named under it: Start hosting / Start the game / Join) and
##   ✗ (Back; Stop hosting / Disconnect while connected). Esc goes back one
##   step, Enter is ✓ (or works the selected row), Up / Down select rows,
##   Left / Right change them, Ctrl+V pastes the address.
## Above the rows the page's description; while the pointer is on a row, that
## row's explanation instead.

signal host_requested(max_players: int)
signal join_requested(address: String)
signal start_requested
## Leave the screen (main menu closes any connection).
signal back_requested
## Stop hosting / disconnect, staying on the screen.
signal stop_requested
## Open the network character screens (MpCharPanel).
signal characters_requested
## Host: the game about to be started changed (Session.set_lobby_mode).
signal lobby_changed(mode: Dictionary)

enum { MODES, HOST_COOP, JOIN_COOP, HOST_LMP, JOIN_LMP }
const PAGE_NAMES := ["modes", "host_coop", "join_coop", "host_lmp", "join_lmp"]

const BOOK_PATH := "user://addrbook.cfg"
const BOOK_MAX := 12
const NAME_MAX := 10
const OK_RECT := Rect2(213, 526, 74, 48)
const CANCEL_RECT := Rect2(513, 526, 74, 48)
const PLATE_UV := [122, 108, 252, 127]
const ORANGE := Color8(0xff, 0xb3, 0x31)    # COLORREF (message box titles, caret)
const YELLOW := Color8(0xee, 0xe3, 0x31)    # COLORREF (the original's address book)
const GREEN := Color8(0x9c, 0xd8, 0x7a)
const HOVER_BAR := Color8(0xa0, 0x68, 0x00, 0x60)
# Upper panel (rows) and lower panel (friends / addresses) of the pages.
const TOP := Rect2(100, 60, 600, 258)
const LOW := Rect2(100, 328, 600, 172)
const ROW0 := 142.0
const BOOK_ROWS := 5

var page := MODES
var status := ""             # set by MainMenu: the last connection message
var upnp_text := ""          # set by MainMenu: the router's answer (UpnpPort)
var player_name := "Player"
var max_players := Session.MAX_PLAYERS
var hero := 0                # Session.COOP_CLASSES index: the co-op hero's class
var addresses: PackedStringArray = []   # the address book, last used first
var address := ""            # the address typed on a join page
var lobby: Array = []        # player lines once hosting / connected (MainMenu)
var hosting := false
var joining := false
## The game hosted: "" the remake's co-op campaign, else one of the original's
## multiplayer bases (LmpMode.BASES).
var lmp_base := ""
## Host co-op: "" a new campaign, else the save slot the campaign continues.
var start_slot := ""
## Host: set by MainMenu while hosting — the port and the session's UPnP helper.
var host_port := 0
var upnp: UpnpPort
## Joiner: what the host runs (Session.lobby_mode), {} until it says.
var host_mode := {}
## Screenshots / tests: lay the screen out as the browser build does.
var simulate_web := false

var _dim: Interface800.Backdrop
var _board: InterfaceBoard
var _sel := -1               # selected row (mode page: choice)
var _hover := ""             # the target id under the pointer
var _focus := ""             # "name" / "addr": the edit field with the caret
var _caret_t := 0.0
var _drag := false           # the players slider's thumb
var _switched_from := -1     # joiner: the page picked before the host's mode moved it
var _copied_t := 0.0
var _copied_status := ""
var _share: Array = []
var _share_t := 0
var _book_sel := -1
var _book_top := 0
var _book_drag := false
var _targets := {}           # id -> Rect2 (800 units) of what was drawn last


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_dim = Interface800.dim_layer()
	add_child(_dim)
	_board = InterfaceBoard.create("unmoco2", "mainmenu00", "mainmenu00labels",
		PackedStringArray(["but03", "button03_multiplayer"]), PI * 0.5 * 1.2, Vector3(400, 350, 8))
	_board.show_behind_parent = true   # under the panels, over the dimmed screen
	add_child(_board)
	resized.connect(queue_redraw)
	_load_book()


## The co-op port: Session.PORT, or --port=N on the command line (remake).
static func cli_port() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port=") and a.trim_prefix("--port=").is_valid_int():
			return a.trim_prefix("--port=").to_int()
	return Session.PORT


## Opens the screen on the choice of game.
func open() -> void:
	player_name = GameData.player_name
	hero = maxi(0, Session.COOP_CLASSES.find(GameData.hero_class))
	max_players = Session.MAX_PLAYERS
	if address.is_empty():
		address = addresses[0] if not addresses.is_empty() else ("wss://" if _web() else "")
	_dim.capture()   # the frame under the screen, frozen and greyed
	show_page(MODES)
	visible = true
	grab_focus()


## Shows `p` (one of the page enums).
func show_page(p: int) -> void:
	page = p
	_board.visible = p == MODES   # over the choice of game, as over Options
	_switched_from = -1
	_focus = ""
	_hover = ""
	_book_sel = -1
	if p == HOST_COOP:
		lmp_base = ""
	elif p == HOST_LMP and not lmp_base in LmpMode.BASES:
		lmp_base = LmpMode.BASES[0]
	_sel = -1
	if p == MODES:
		for i in 4:
			if _mode_off(i + 1).is_empty():
				_sel = i
				break
	elif (p == JOIN_COOP or p == JOIN_LMP) and address.strip_edges() in ["", "ws://", "wss://"]:
		_focus = "addr"
	_targets.clear()
	queue_redraw()


## Back one step: stop hosting / disconnect, else the choice of game, else
## leave the screen.
func go_back() -> void:
	sound("messbox\\cancel")
	_focus = ""
	if hosting or joining:
		stop_requested.emit()
	elif page != MODES:
		show_page(MODES)
	else:
		back_requested.emit()


func hero_class() -> String:
	return String(Session.COOP_CLASSES[clampi(hero, 0, Session.COOP_CLASSES.size() - 1)])


func selected_address() -> String:
	return address.strip_edges()


## What the host is about to start, for joiners (Session.lobby_mode).
func lobby_mode() -> Dictionary:
	return {"mode": "lmp", "base": lmp_base} if lmp_base else {"mode": "coop"}


## Tests / tools: the window position of a target drawn last ("ok", "cancel",
## "mode:<page name>", "row:<id>", "copy:<i>", "book:<i>", "paste", "remove",
## "char"); Vector2(-1, -1) when it is not on the screen.
func target_point(id: String) -> Vector2:
	if not _targets.has(id):
		return Vector2(-1, -1)
	return p8((_targets[id] as Rect2).get_center())


func _web() -> bool:
	return simulate_web or OS.has_feature("web")


func _load_book() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(BOOK_PATH) == OK:
		addresses = PackedStringArray(cfg.get_value("book", "addresses", PackedStringArray()))
	addresses = PackedStringArray(Array(addresses).filter(func(a): return String(a).strip_edges() != ""))


func _save_book() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("book", "addresses", addresses)
	cfg.save(BOOK_PATH)


## The address joined goes to the top of the book.
func _remember(a: String) -> void:
	a = a.strip_edges()
	if a.is_empty() or a in ["ws://", "wss://"]:
		return
	var list := Array(addresses)
	list.erase(a)
	list.push_front(a)
	addresses = PackedStringArray(list.slice(0, BOOK_MAX))
	_save_book()


# ------------------------------------------------------------------ pages

## Why choice `p` cannot be taken ("" when it can).
func _mode_off(p: int) -> String:
	if p in [HOST_COOP, HOST_LMP] and _web():
		return RemakeText.t("Hosting is not available in the browser version: host from the desktop or Android version.")
	if p in [HOST_LMP, JOIN_LMP] and not LmpMode.available():
		return RemakeText.t("Needs the multiplayer files of the original game (databaseLMP.res), missing from this installation.")
	return ""


func _mode_title(p: int) -> String:
	match p:
		HOST_COOP: return RemakeText.t("Host co-op campaign")
		JOIN_COOP: return RemakeText.t("Join co-op campaign")
		HOST_LMP: return RemakeText.t("Host multiplayer game")
		JOIN_LMP: return RemakeText.t("Join multiplayer game")
	return RemakeText.t("Multiplayer")


func _mode_desc(p: int) -> String:
	match p:
		HOST_COOP: return RemakeText.t("Play the story together from your save or a new game; friends join with their own hero.")
		JOIN_COOP: return RemakeText.t("Join a friend's campaign; bring your hero from a single-player save.")
		HOST_LMP: return RemakeText.t("Pick a base (%s), take quests with network characters. No saving.") \
			% ", ".join(LmpMode.BASES.map(func(x: String): return LmpMode.base_title(x)))
		JOIN_LMP: return RemakeText.t("Join such a game with your network character.")
	return ""


func _page_desc() -> String:
	match page:
		MODES: return RemakeText.t("Choose what you want to play. Every player needs their own copy of Evil Islands.")
		HOST_COOP: return RemakeText.t("You play Zak and lead the campaign; friends join with their own hero. Only you can save.")
		HOST_LMP: return RemakeText.t("The original game's multiplayer: every player has a network character, quests are taken at the base and played in their own zone. There is no saving; characters keep what they earn.")
		JOIN_COOP: return RemakeText.t("Join a friend's campaign: you play in the host's world with your own hero.")
		JOIN_LMP: return RemakeText.t("Join a friend's multiplayer game with your network character.")
	return ""


func _on_off(on: bool) -> String:
	return OptionsPanel._t("string option_on", "On") if on else OptionsPanel._t("string option_off", "Off")


## The page's rows: {id, kind (edit / choice / switch / slider / link),
## label, value, hint, on (false: locked, drawn grey)}.
func _rows() -> Array:
	var out := []
	var locked := hosting or joining
	out.append({"id": "name", "kind": "edit", "label": RemakeText.t("Your name"), "value": player_name, "on": not locked,
		"hint": RemakeText.t("Your name in the co-op game.")})
	match page:
		HOST_COOP:
			out.append({"id": "start", "kind": "choice", "label": RemakeText.t("Start from"), "value": _start_title(), "on": true,
				"hint": RemakeText.t("A new game, or one of your saves: it is continued with your friends in it; save as usual.")})
		HOST_LMP:
			out.append({"id": "base", "kind": "choice", "label": RemakeText.t("Base"), "value": LmpMode.base_title(lmp_base), "on": true,
				"hint": RemakeText.t("The party starts there; its quest giver offers the quests.")})
			out.append(_char_row(locked))
		JOIN_COOP, JOIN_LMP:
			out.append({"id": "addr", "kind": "edit", "label": RemakeText.t("Host's address"), "value": address, "on": not joining,
				"hint": _addr_hint()})
	if page in [HOST_COOP, HOST_LMP]:
		out.append({"id": "players", "kind": "slider", "label": RemakeText.t("Players"), "value": str(max_players), "on": not hosting,
			"hint": RemakeText.t("At most, you included.")})
	if page == HOST_COOP:
		out.append({"id": "fullxp", "kind": "switch", "label": RemakeText.t(GameData.REMAKE_OPTIONS.coop_full_xp[0]),
			"value": _on_off(XpRules.full_experience()), "on": true,
			"hint": RemakeText.t("On: every hero gets the whole experience of a kill or quest. Off: shared among the heroes, as in the original.")})
		out.append({"id": "scale", "kind": "choice", "label": RemakeText.t(GameData.REMAKE_OPTIONS.coop_scale[0]),
			"value": RemakeText.t(MobScaling.CHOICES[clampi(GameData.option("coop_scale"), 0, MobScaling.CHOICES.size() - 1)]), "on": true,
			"hint": RemakeText.t("Monsters get more health and hit harder for each player beyond the first.")})
	if page in [HOST_COOP, HOST_LMP]:
		var port := host_port if host_port > 0 else cli_port()
		out.append({"id": "upnp", "kind": "switch", "label": RemakeText.t(GameData.REMAKE_OPTIONS.net_upnp[0]),
			"value": _on_off(GameData.option("net_upnp") == 1), "on": not hosting,
			"hint": RemakeText.t("Asks your router to let friends in from the internet (UPnP / NAT-PMP / PCP). Leave it on.")})
		out.append({"id": "websocket", "kind": "switch", "label": RemakeText.t("WebSocket (for browser players)"),
			"value": _on_off(GameData.option("net_websocket") != 0), "on": not hosting,
			"hint": RemakeText.t("Leave this off unless a friend plays the browser version. Browser players can only reach a secure wss:// address, which needs an HTTPS proxy in front of this port. With it on, the others join with ws://address:port, and the router is not opened automatically (forward TCP port %d by hand).") % port})
	if page == JOIN_COOP:
		out.append({"id": "bring", "kind": "choice", "label": RemakeText.t("Your hero"), "value": _bring_title(CoopProgress.bring_slot),
			"on": not joining, "hint": _bring_hint()})
		if CoopProgress.bring_slot == "":
			out.append({"id": "class", "kind": "choice", "label": RemakeText.t("Class"), "value": _class_title(hero_class()),
				"on": not joining, "hint": RemakeText.t("A hero of the class below, made for this game; nothing is kept afterwards.")})
	if page == JOIN_LMP:
		out.append(_char_row(joining))
	return out


func _char_row(locked: bool) -> Dictionary:
	var h: String
	if not LmpMode.available():
		h = RemakeText.t("Needs the multiplayer files of the original game (databaseLMP.res), missing from this installation.")
	elif MpCharacter.hero_of(MpCharacter.current()).is_empty():
		h = RemakeText.t("None chosen yet: you would play a plain default hero. Create one: it is kept on this device and keeps what it earns.")
	else:
		h = RemakeText.t("Kept on this device; it keeps the experience, gold and things it earns.")
	return {"id": "char", "kind": "link", "label": RemakeText.t("Network character:").trim_suffix(":"), "value": _char_title(),
		"on": not locked and LmpMode.available(), "hint": h}


func _addr_hint() -> String:
	if _web():
		return RemakeText.t("Browser version: ask the host for a secure WebSocket address starting with wss://. The host turns WebSocket on in its connection settings; ws:// works only for a host on this same computer.")
	return RemakeText.t("The address your friend's screen shows: an IP address, IP:port, or [IPv6]:port. Without a port, %d is used.") % Session.PORT


func _bring_hint() -> String:
	match CoopProgress.bring_slot:
		"": return RemakeText.t("A hero of the class below, made for this game; nothing is kept afterwards.")
		CoopProgress.NEW: return RemakeText.t("A new Zak from the start of the story. What you achieve comes back as a new save “Co-op: <host>”.")
	return RemakeText.t("The Zak of this save, with his things. What you achieve that your own game has not done yet comes back as a new save “Co-op: <host>”; this save stays as it is.")


func _start_choices() -> Array:
	var out := [""]
	for i: SaveInfo in SaveInfo.list():
		if not i.error:
			out.append(i.slot)
	return out


func _start_title() -> String:
	if start_slot.is_empty() or not _start_choices().has(start_slot):
		start_slot = ""
		return RemakeText.t("A new game (the beginning of the story)")
	var i := SaveInfo.read(start_slot)
	return "%s  %s" % [i.display_name(), i.date_text()]


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	_targets.clear()
	# The last connection message (the original's status rect, the screen's width).
	text(Rect2(0, 0, 800, 20), status, 2, TEXT)
	if upnp_text and hosting and page in [HOST_COOP, HOST_LMP]:
		text(Rect2(0, 22, 800, 20), upnp_text, 1, GREY)
	if page == MODES:
		_draw_modes()
	else:
		_draw_page()
	_draw_buttons()


func _draw_modes() -> void:
	var ui := tex("saveload")
	# Below the signpost board (as the original network screen places it).
	panel(Rect2(100, 120, 600, 380))
	text(Rect2(100, 128, 600, 24), RemakeText.t("Multiplayer"), 2, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_block(Rect2(110, 152, 580, 32), _page_desc(), 0, GREY, 2, HORIZONTAL_ALIGNMENT_CENTER)
	var y := 186.0
	for g in 2:
		text(Rect2(110, y, 580, 20), RemakeText.t("Story campaign together") if g == 0 else RemakeText.t("The original game's multiplayer"), 1, ORANGE)
		y += 22
		for k in 2:
			var p: int = [HOST_COOP, JOIN_COOP, HOST_LMP, JOIN_LMP][g * 2 + k]
			var i := p - 1
			var r := Rect2(110, y, 580, 58)
			var off := _mode_off(p)
			var id: String = "mode:" + PAGE_NAMES[p]
			_targets[id] = r
			if i == _sel:
				draw_rect(r8(r), BAR)
			elif _hover == id and off.is_empty():
				draw_rect(r8(r), HOVER_BAR)
			var plate := Rect2(120, y + 6, 190, 21)
			sprite(ui, plate, PLATE_UV, Color.WHITE if off.is_empty() else Color(0.5, 0.5, 0.5))
			var title := _mode_title(p)
			var f := 1 if text_width(title, 1) <= plate.size.x - 12 else 0   # long translations
			text(Rect2(plate.position.x, plate.position.y + (2 if f == 1 else 3), plate.size.x, 20), title, f,
				GREY if off else (Color.WHITE if _hover == id or i == _sel else TEXT), HORIZONTAL_ALIGNMENT_CENTER)
			var h := _block(Rect2(322, y + 5, 362, 48), _mode_desc(p), 0, GREY if off else TEXT, 3 if off.is_empty() else 2)
			if off:
				_block(Rect2(322, y + 5 + h, 362, 32), off, 0, ORANGE, 2)
			y += 60
		y += 8


func _draw_page() -> void:
	panel(TOP)
	text(Rect2(TOP.position.x, 68, TOP.size.x, 24), _mode_title(page), 2, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	# The page's description, or the explanation of the row under the pointer.
	var rows := _rows()
	var desc := _page_desc()
	var hint_col := GREY
	for row: Dictionary in rows:
		if _hover == "row:" + String(row.id) or (_hover.is_empty() and _sel >= 0 and _sel < rows.size() and rows[_sel] == row):
			desc = String(row.hint)
			hint_col = TEXT
	_block(Rect2(110, 94, 580, 47), desc, 0, hint_col, 3, HORIZONTAL_ALIGNMENT_CENTER)
	for r in rows.size():
		_draw_row(r, rows[r])
	panel(LOW)
	if page in [HOST_COOP, HOST_LMP]:
		_draw_friends()
	else:
		_draw_join_low()


func _row_rect(r: int) -> Rect2:
	return Rect2(110, ROW0 + 24.0 * r, 580, 24)


func _draw_row(r: int, row: Dictionary) -> void:
	var rr := _row_rect(r)
	var y := rr.position.y
	var id := "row:" + String(row.id)
	_targets[id] = rr
	var on: bool = row.on
	if r == _sel:
		draw_rect(r8(rr), BAR)
	elif _hover == id and on:
		draw_rect(r8(rr), HOVER_BAR)
	text(Rect2(120, y + 4, 275, 20), String(row.label), 1, TEXT if on else GREY)
	var col := TEXT if on else GREY
	match String(row.kind):
		"edit":
			var w := 208.0 if row.id == "addr" else 285.0
			var ph := ""
			if row.id == "addr":
				ph = RemakeText.t("e.g. wss://example.org/game") if _web() else RemakeText.t("e.g. 192.168.1.20 or 203.0.113.7:27015")
			_edit(Rect2(400, y + 3, w, 18), String(row.value), _focus == row.id and on, on, ph)
			if row.id == "addr":
				_plate("paste", Rect2(613, y + 3, 74, 19), RemakeText.t("Paste"), on)
		"choice":
			_arrow(Vector2(408, y + 12), true, on)
			_arrow(Vector2(682, y + 12), false, on)
			text(Rect2(418, y + 4, 254, 20), String(row.value), 1, col, HORIZONTAL_ALIGNMENT_CENTER)
		"switch":
			text(Rect2(400, y + 4, 285, 20), String(row.value), 1, col)
		"slider":
			if on:
				hslider(_slider_rect(r), float(max_players - 1), float(Session.MAX_PLAYERS - 1))
			text(Rect2(590 if on else 400, y + 4, 95, 20), String(row.value), 1, col)
		"link":
			text(Rect2(400, y + 4, 180, 20), String(row.value), 1, col)
			_plate("char", Rect2(585, y + 3, 102, 19), RemakeText.t("Choose…"), on)


func _slider_rect(r: int) -> Rect2:
	return Rect2(400, ROW0 + 24.0 * r + 7, 180, 10)


## The scroll bar's arrow (Interface800.hslider) as a choice's step button.
func _arrow(c: Vector2, left: bool, on: bool) -> void:
	var t := tex("Scrollbar")
	var col := Color.WHITE if on else Color(0.45, 0.45, 0.45)
	if t == null:
		text(Rect2(c.x - 6, c.y - 9, 12, 18), "<" if left else ">", 1, col, HORIZONTAL_ALIGNMENT_CENTER)
		return
	sprite(t, Rect2(c - Vector2(5, 6), Vector2(10, 12)), [40, 128, 80, 176] if left else [40, 176, 80, 128], col, PI * 0.5)


## A saveload plate button (the Options group button / network screen
## Refresh look) with its label centred, `id` its target.
func _plate(id: String, r: Rect2, label: String, on := true) -> void:
	_targets[id] = r
	sprite(tex("saveload"), r, PLATE_UV, Color.WHITE if on else Color(0.5, 0.5, 0.5))
	var col := (Color.WHITE if _hover == id else TEXT) if on else GREY
	text(Rect2(r.position.x, r.position.y + 1, r.size.x, 20), label, 1 if text_width(label, 1) <= r.size.x - 6 else 0,
		col, HORIZONTAL_ALIGNMENT_CENTER)


## An edit field (the Load / Save screen's name edit: the text and a caret
## ), on a darker ground with a thin edge so it reads as a field.
func _edit(r: Rect2, s: String, focused: bool, on: bool, placeholder := "") -> void:
	draw_rect(r8(r), Color(0, 0, 0, 0.55))
	draw_rect(r8(r), Color(ORANGE, 0.8) if focused else Color(GREY, 0.45), false, maxf(1.0, round(kv().y)))
	var tr := Rect2(r.position.x + 4, r.position.y + 1, r.size.x - 8, 20)
	if s.is_empty() and not focused and placeholder:
		text(tr, placeholder, 0, Color(GREY, 0.7))
	else:
		# The end of a long text stays in view.
		var shown := s
		while shown.length() > 1 and text_width(shown, 1) > tr.size.x - 4:
			shown = shown.substr(1)
		text(tr, shown, 1, Color.WHITE if on else GREY, HORIZONTAL_ALIGNMENT_LEFT, true)
		if focused and fmod(_caret_t, 1.0) < 0.5:
			var x := r8(tr).position.x + font().get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px(1)).x + 1
			var rr := r8(r)
			draw_line(Vector2(x, rr.position.y + 2 * kv().y), Vector2(x, rr.end.y - 2 * kv().y), ORANGE, maxf(1.0, round(kv().x)))


## Word-wrapped text from the rect's top, at most `lines` lines; its height.
func _block(r: Rect2, s: String, font_i: int, col: Color, lines := 99, align := HORIZONTAL_ALIGNMENT_LEFT) -> float:
	var ls := wrap_text(s, r.size.x, font_i)
	var h := line_h(font_i)
	var n := mini(ls.size(), lines)
	for i in n:
		var t := ls[i]
		if i == n - 1 and ls.size() > n:
			t += "…"
		text(Rect2(r.position.x, r.position.y + h * i, r.size.x, h), t, font_i, col, align)
	return h * n


func _draw_friends() -> void:
	var x0 := LOW.position.x + 10
	var y := LOW.position.y + 6
	text(Rect2(x0, y, 340, 20), RemakeText.t("For your friends"), 1, ORANGE)
	var port := host_port if host_port > 0 else cli_port()
	var ws := GameData.option("net_websocket") != 0
	text(Rect2(460, y, 230, 20), RemakeText.t("Port: %d") % port + (" (TCP)" if ws else " (UDP)"), 1, TEXT)
	y += 22
	if not hosting:
		_block(Rect2(x0, y, 340, 140), RemakeText.t("Press “Start hosting”. The addresses to give your friends appear here; they choose “%s” and type one of them.") \
			% (RemakeText.t("Join multiplayer game") if page == HOST_LMP else RemakeText.t("Join co-op campaign")), 0, TEXT, 4)
		_block(Rect2(460, y, 230, 140), RemakeText.t("WebSocket is on: for friends who play in the browser.") if ws \
			else RemakeText.t("WebSocket is off: only needed if a friend plays the browser version."), 0, GREY, 6)
		return
	if Time.get_ticks_msec() >= _share_t:   # the device's addresses, once a second
		_share_t = Time.get_ticks_msec() + 1000
		_share = _share_addresses()
	text(Rect2(x0, y, 340, 18), RemakeText.t("Give your friends one of these addresses:"), 0, GREY)
	y += 18
	if _share.is_empty():
		y += _block(Rect2(x0, y, 340, 40), RemakeText.t("No network address found. Check that this device is connected to a network."), 0, ORANGE, 2)
	for i in _share.size():
		var a: Array = _share[i]
		text(Rect2(x0, y + 3, 78, 18), String(a[1]), 0, GREY)
		text(Rect2(x0 + 80, y + 2, 196, 20), String(a[0]), 1, YELLOW)
		_plate("copy:%d" % i, Rect2(x0 + 280, y + 1, 60, 19), RemakeText.t("Copy"))
		y += 22
	var rt := _router_text()
	_block(Rect2(x0, y + 2, 340, LOW.end.y - y - 6), rt[0], 0, rt[1], 5)
	# Players.
	var py := LOW.position.y + 28
	text(Rect2(460, py, 230, 20), RemakeText.t("Players: %d / %d") % [lobby.size(), max_players], 1, TEXT)
	py += 22
	for nm: String in lobby:
		if py > LOW.end.y - 20:
			break
		text(Rect2(470, py, 220, 20), nm, 1, ORANGE)
		py += 20
	if lobby.size() <= 1 and py < LOW.end.y - 30:
		_block(Rect2(460, py + 2, 230, LOW.end.y - py - 6), RemakeText.t("Waiting for friends to join… You can also start alone; friends can join later."), 0, GREY, 3)


func _book_rect() -> Rect2:
	return Rect2(LOW.position.x + 8, LOW.position.y + 28, 340, 22.0 * BOOK_ROWS)


func _draw_join_low() -> void:
	var x0 := LOW.position.x + 10
	var y := LOW.position.y + 6
	# Left: the recent addresses, as the Load screen's list.
	text(Rect2(x0, y, 340, 20), RemakeText.t("Recent addresses"), 1, ORANGE)
	var br := _book_rect()
	_book_top = clampi(_book_top, 0, maxi(0, addresses.size() - BOOK_ROWS))
	if addresses.is_empty():
		text(Rect2(x0, br.position.y + 2, 330, 18), RemakeText.t("none"), 0, GREY)
	for k in BOOK_ROWS:
		var i := _book_top + k
		if i >= addresses.size():
			break
		var rr := Rect2(br.position.x, br.position.y + 22 * k, br.size.x - 14, 22)
		_targets["book:%d" % i] = rr
		if i == _book_sel:
			draw_rect(r8(rr), BAR)
		elif _hover == "book:%d" % i and not joining:
			draw_rect(r8(rr), HOVER_BAR)
		text(Rect2(rr.position.x + 4, rr.position.y + 2, rr.size.x - 8, 20), addresses[i], 1, YELLOW if not joining else GREY, HORIZONTAL_ALIGNMENT_LEFT, true)
	vbar(Rect2(br.position.x, br.position.y, br.size.x, br.size.y), float(_book_top), float(addresses.size() - BOOK_ROWS))
	_plate("remove", Rect2(x0, LOW.end.y - 26, 110, 19), RemakeText.t("Remove"), _book_sel >= 0 and not joining)
	# Right: the address formats, or the connection.
	var rx := 460.0
	var ry := LOW.position.y + 6
	if not joining:
		text(Rect2(rx, ry, 230, 20), RemakeText.t("Host's address"), 1, ORANGE)
		_block(Rect2(rx, ry + 22, 230, 140), _addr_hint(), 0, TEXT, 8)
		return
	text(Rect2(rx, ry, 230, 20), RemakeText.t("Connection"), 1, ORANGE)
	ry += 22
	var sw := _switch_text()
	if sw:
		ry += _block(Rect2(rx, ry, 230, 75), sw, 0, ORANGE, 5) + 2
	ry += _block(Rect2(rx, ry, 230, 60), _connection_text(), 0, TEXT, 4) + 4
	text(Rect2(rx, ry, 230, 20), RemakeText.t("Players: %d") % lobby.size(), 1, TEXT)
	ry += 20
	for nm: String in lobby:
		if ry > LOW.end.y - 18:
			break
		text(Rect2(rx + 10, ry, 220, 18), nm, 0, ORANGE)
		ry += 16


## ✓ and ✗ (Options / Load positions), each with what it does now under it.
func _draw_buttons() -> void:
	var ui := tex("saveload")
	var ok := _ok_label()
	_targets["ok"] = OK_RECT
	_targets["cancel"] = CANCEL_RECT
	if ok:
		var on := _ok_enabled()
		sprite(ui, OK_RECT, [81, 2, 155, 50], Color.WHITE if on else Color(0.5, 0.5, 0.5))
		text(Rect2(OK_RECT.get_center().x - 110, 576, 220, 22), ok, 1,
			(Color.WHITE if _hover == "ok" else TEXT) if on else GREY, HORIZONTAL_ALIGNMENT_CENTER)
	sprite(ui, CANCEL_RECT, [160, 2, 234, 50])
	text(Rect2(CANCEL_RECT.get_center().x - 110, 576, 220, 22), _cancel_label(), 1,
		Color.WHITE if _hover == "cancel" else TEXT, HORIZONTAL_ALIGNMENT_CENTER)


## The name of what ✓ does now ("" on the choice page: no ✓).
func _ok_label() -> String:
	match page:
		MODES:
			return RemakeText.t("Choose") if _sel >= 0 else ""
		HOST_COOP, HOST_LMP:
			return RemakeText.t("Start the game") if hosting else RemakeText.t("Start hosting")
	if joining:
		return RemakeText.t("Waiting for the host…") if not lobby.is_empty() else RemakeText.t("Connecting…")
	return RemakeText.t("Join")


func _ok_enabled() -> bool:
	match page:
		MODES: return _sel >= 0 and _mode_off(_sel + 1).is_empty()
		HOST_COOP, HOST_LMP: return not _web()
	return not joining


func _cancel_label() -> String:
	if hosting:
		return RemakeText.t("Stop hosting")
	if joining:
		return RemakeText.t("Disconnect")
	return RemakeText.t("Back")


# ------------------------------------------------------------------ live parts

## Router state [text, colour], in plain words.
func _router_text() -> Array:
	var port := host_port if host_port > 0 else Session.PORT
	if GameData.option("net_websocket"):
		return [RemakeText.t("WebSocket host: friends on your home network use the LAN address. Over the internet, forward TCP port %d on your router by hand; browser players need a secure wss:// address (an HTTPS proxy in front of this port).") % port, ORANGE]
	if upnp and upnp.busy:
		return [RemakeText.t("Asking your router to open UDP port %d for friends on the internet…") % port, TEXT]
	if upnp and upnp.mapped:
		return [RemakeText.t("Your router opened the port: friends on the internet use the internet address."), GREEN]
	if GameData.option("net_upnp") != 1 or upnp == null or upnp.status.is_empty():
		return [RemakeText.t("Friends on your home network use the LAN address. For the internet, forward UDP port %d on your router to this device by hand (automatic router setup is off).") % port, TEXT]
	return [RemakeText.t("Your router did not open the port. Friends on your home network can still join with the LAN address; for the internet, forward UDP port %d on your router by hand, or try the IPv6 address.") % port, ORANGE]


## Joiner: the connection's state and what the host runs.
func _connection_text() -> String:
	var t := RemakeText.t("Connecting to %s…") % selected_address() if lobby.is_empty() \
		else RemakeText.t("Connected to %s. Waiting for the host to start the game.") % selected_address()
	if host_mode.is_empty():
		return t
	if String(host_mode.get("mode", "")) == "lmp":
		return t + "\n" + RemakeText.t("The host runs: multiplayer game, base %s.") % LmpMode.base_title(String(host_mode.get("base", "")))
	return t + "\n" + RemakeText.t("The host runs: co-op campaign.")


## Joiner moved to the other page: why, and what it plays with.
func _switch_text() -> String:
	if _switched_from < 0:
		return ""
	if page == JOIN_LMP:
		return RemakeText.t("This host runs the original multiplayer game, not a co-op campaign. You take part with your network character: %s.") % _char_title() \
			+ " " + RemakeText.t("To choose another, disconnect, choose it here and join again.")
	return RemakeText.t("This host runs a co-op campaign, not the original multiplayer game. You play: %s.") % _bring_title(CoopProgress.bring_slot, true) \
		+ " " + RemakeText.t("To choose another, disconnect, choose it here and join again.")


## Remake: [address, kind] pairs to give friends while hosting — the first
## private IPv4 LAN address, the router's external one (UPnP / NAT-PMP / PCP,
## with the port it gave) and a global IPv6 address, with the port.
func _share_addresses() -> Array:
	var port := host_port if host_port > 0 else Session.PORT
	var out := []
	var lan := UpnpPort.lan_ipv4()
	if lan:
		out.append(["%s:%d" % [lan, port], RemakeText.t("LAN")])
	if upnp and upnp.mapped and upnp.external_ip:
		out.append([UpnpPort._join_text(upnp.external_ip, upnp.external_port if upnp.external_port > 0 else port),
			RemakeText.t("Internet")])
	var v6 := UpnpPort.global_ipv6()
	if v6:
		out.append(["[%s]:%d" % [v6, port], "IPv6"])
	if GameData.option("net_websocket"):
		for entry in out:
			entry[0] = "ws://" + String(entry[0])
	return out


## The selected network character's name ("none").
func _char_title() -> String:
	var h := MpCharacter.hero_of(MpCharacter.current())
	return String(h.name) if not h.is_empty() else RemakeText.t("none")


func _class_title(proto: String) -> String:
	var t := GameUnit.unit_title(proto) if GameData.is_open() else ""
	return t if t else proto.trim_prefix("Human Mercenary ")


## Remake co-op: what a joiner brings — "" a co-op hero of the chosen class
## (nothing kept), "new" a new campaign Zak, or the hero of one of its saves
## (progress comes back as a new save, CoopProgress).
func _bring_choices() -> Array:
	var out := ["", CoopProgress.NEW]
	for i: SaveInfo in SaveInfo.list():
		if not i.error:
			out.append(i.slot)
	return out


func _bring_title(slot: String, with_class := false) -> String:
	match slot:
		"": return RemakeText.t("A co-op hero (nothing kept)") + (" — " + _class_title(hero_class()) if with_class else "")
		CoopProgress.NEW: return RemakeText.t("A new Zak (start fresh)")
	var i := SaveInfo.read(slot)
	return RemakeText.t("Zak of the save “%s”") % i.display_name()


# ------------------------------------------------------------------ actions

## Works a row: `dir` +1 / −1 for choices, 0 a click / Enter (forward).
func _activate(id: String, dir := 0) -> void:
	var step := -1 if dir < 0 else 1
	match id:
		"name", "addr":
			_focus = id
			_caret_t = 0.0
			if TouchInput.enabled:
				if id == "name":
					TouchTextEdit.open(self, player_name, NAME_MAX, func(v): player_name = v; queue_redraw(), "Player name")
				else:
					TouchTextEdit.open(self, address, 256, func(v): address = v; queue_redraw(), "Server address")
			return
		"start":
			var ch := _start_choices()
			start_slot = ch[posmod(maxi(0, ch.find(start_slot)) + step, ch.size())]
		"base":
			lmp_base = LmpMode.BASES[posmod(maxi(0, LmpMode.BASES.find(lmp_base)) + step, LmpMode.BASES.size())]
			if hosting:
				lobby_changed.emit(lobby_mode())
		"players":
			if dir == 0:
				return
			max_players = clampi(max_players + step, 1, Session.MAX_PLAYERS)
		"fullxp":
			GameData.set_option("coop_full_xp", 0 if XpRules.full_experience() else 1)
		"scale":
			GameData.set_option("coop_scale", posmod(GameData.option("coop_scale") + step, MobScaling.CHOICES.size()))
		"upnp":
			GameData.set_option("net_upnp", 0 if GameData.option("net_upnp") == 1 else 1)
		"websocket":
			GameData.set_option("net_websocket", 0 if GameData.option("net_websocket") else 1)
		"bring":
			var ch := _bring_choices()
			CoopProgress.bring_slot = ch[posmod(maxi(0, ch.find(CoopProgress.bring_slot)) + step, ch.size())]
		"class":
			hero = posmod(hero + step, Session.COOP_CLASSES.size())
		"char":
			sound("messbox\\ok")
			characters_requested.emit()
			return
	sound("messbox\\ok" if dir == 0 else "save\\select")
	queue_redraw()


func _row_on(id: String) -> bool:
	for row: Dictionary in _rows():
		if row.id == id:
			return bool(row.on)
	return false


func _copy(a: String) -> void:
	sound("save\\select")
	DisplayServer.clipboard_set(a)
	_copied_t = 2.5
	status = RemakeText.t("Copied: %s") % a
	_copied_status = status


func _paste() -> void:
	var c := DisplayServer.clipboard_get().strip_edges().get_slice("\n", 0).strip_edges()
	if c.is_empty() or joining or not page in [JOIN_COOP, JOIN_LMP]:
		return
	address = c.substr(0, 256)
	_focus = "addr"
	sound("save\\select")
	queue_redraw()


## ✓.
func _primary() -> void:
	match page:
		MODES:
			if _sel >= 0 and _mode_off(_sel + 1).is_empty():
				sound("messbox\\ok")
				show_page(_sel + 1)
		HOST_COOP, HOST_LMP:
			sound("messbox\\ok")
			if _web():
				status = RemakeText.t("Hosting is not available in the browser version: host from the desktop or Android version.")
			elif hosting:
				start_requested.emit()
			else:
				host_requested.emit(max_players)
		JOIN_COOP, JOIN_LMP:
			if joining:
				return
			var a := selected_address()
			if a.is_empty() or a in ["ws://", "wss://"]:
				status = RemakeText.t("Type the host's address first.")
				_focus = "addr"
				return
			sound("messbox\\ok")
			_focus = ""
			_remember(a)
			join_requested.emit(a)
	queue_redraw()


# ------------------------------------------------------------------ input

func _hit(p: Vector2) -> String:
	# Later targets lie over earlier ones (plates over their rows).
	var keys := _targets.keys()
	for i in range(keys.size() - 1, -1, -1):
		if (_targets[keys[i]] as Rect2).has_point(p):
			return String(keys[i])
	return ""


func _gui_input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventMouseMotion:
		var p := to800(e.position)
		if _drag:
			var rows := _rows()
			for r in rows.size():
				if rows[r].id == "players":
					max_players = hslider_value(_slider_rect(r), Session.MAX_PLAYERS - 1, p.x) + 1
		elif _book_drag:
			_book_top = vbar_value(_book_rect(), float(addresses.size() - BOOK_ROWS), p.y)
		var h := _hit(p)
		if h != _hover:
			_hover = h
			queue_redraw()
		return
	if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = false
		_book_drag = false
		accept_event()
		return
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if page in [JOIN_COOP, JOIN_LMP] and _book_rect().has_point(to800(e.position)):
			_book_top = clampi(_book_top + (-1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1), 0, maxi(0, addresses.size() - BOOK_ROWS))
			queue_redraw()
		accept_event()
		return
	if not (e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]):
		return
	accept_event()
	var p := to800(e.position)
	var right: bool = e.button_index == MOUSE_BUTTON_RIGHT
	var h := _hit(p)
	_focus = ""
	if page in [JOIN_COOP, JOIN_LMP]:
		var part := vbar_hit(_book_rect(), float(_book_top), float(addresses.size() - BOOK_ROWS), p)
		if part and addresses.size() > BOOK_ROWS:
			if part == "thumb":
				_book_drag = true
			elif part in ["up", "down"]:
				_book_top = clampi(_book_top + (-1 if part == "up" else 1), 0, addresses.size() - BOOK_ROWS)
			queue_redraw()
			return
	if h.is_empty():
		queue_redraw()
		return
	if h == "ok":
		if _ok_enabled():
			_primary()
	elif h == "cancel":
		go_back()
	elif h.begins_with("mode:"):
		var pg := PAGE_NAMES.find(h.trim_prefix("mode:"))
		if _mode_off(pg).is_empty():
			_sel = pg - 1
			sound("messbox\\ok")
			show_page(pg)
	elif h.begins_with("copy:"):
		var i := h.trim_prefix("copy:").to_int()
		if i < _share.size():
			_copy(String(_share[i][0]))
	elif h.begins_with("book:"):
		if not joining:
			var i := h.trim_prefix("book:").to_int()
			sound("save\\select")
			_book_sel = i
			address = addresses[i]
			if e.double_click:
				_primary()
	elif h == "paste":
		if not joining:
			_paste()
	elif h == "remove":
		if _book_sel >= 0 and _book_sel < addresses.size() and not joining:
			sound("save\\select")
			addresses.remove_at(_book_sel)
			_book_sel = -1
			_save_book()
	elif h == "char":
		if _row_on("char"):
			_activate("char")
	elif h.begins_with("row:"):
		var id := h.trim_prefix("row:")
		var rows := _rows()
		for r in rows.size():
			if rows[r].id != id:
				continue
			_sel = r
			if not rows[r].on:
				break
			match String(rows[r].kind):
				"choice":
					_activate(id, -1 if right or p.x < 545 else 1)
				"slider":
					var sr := _slider_rect(r)
					var part := hslider_hit(sr, max_players - 1, Session.MAX_PLAYERS - 1, p)
					match part:
						"left": _activate(id, -1)
						"right": _activate(id, 1)
						"thumb": _drag = true
						"track":
							max_players = hslider_value(sr, Session.MAX_PLAYERS - 1, p.x) + 1
				_:
					_activate(id)
	queue_redraw()


func _unhandled_key_input(e: InputEvent) -> void:
	if not is_visible_in_tree() or not (e is InputEventKey) or not e.pressed:
		return
	var k := e as InputEventKey
	if k.keycode == KEY_V and (k.ctrl_pressed or k.meta_pressed):
		if _focus == "name":
			for ch in DisplayServer.clipboard_get().strip_edges().get_slice("\n", 0):
				_type(ch)
		else:
			_paste()
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	match k.keycode:
		KEY_ESCAPE:
			if _focus != "":
				_focus = ""
			else:
				go_back()
		KEY_ENTER, KEY_KP_ENTER:
			var rows := _rows() if page != MODES else []
			if _focus == "" and page != MODES and _sel >= 0 and _sel < rows.size() \
					and String(rows[_sel].kind) in ["choice", "switch", "link"] and rows[_sel].on:
				_activate(String(rows[_sel].id))
			else:
				_focus = ""
				if _ok_enabled():
					_primary()
		KEY_UP, KEY_DOWN:
			_focus = ""
			var d := -1 if k.keycode == KEY_UP else 1
			if page == MODES:
				var s := _sel
				for n in 4:
					s = posmod(s + d, 4)
					if _mode_off(s + 1).is_empty():
						break
				_sel = s
			else:
				_sel = clampi(_sel + d, 0, _rows().size() - 1)
				var row: Dictionary = _rows()[_sel]
				if row.kind == "edit" and row.on:
					_focus = String(row.id)
			sound("save\\select")
		KEY_LEFT, KEY_RIGHT:
			if _focus == "" and page != MODES:
				var rows := _rows()
				if _sel >= 0 and _sel < rows.size() and rows[_sel].on and String(rows[_sel].kind) in ["choice", "slider"]:
					_activate(String(rows[_sel].id), -1 if k.keycode == KEY_LEFT else 1)
		KEY_BACKSPACE:
			_type("", true)
		KEY_DELETE:
			if _focus == "" and _book_sel >= 0 and _book_sel < addresses.size() and not joining:
				addresses.remove_at(_book_sel)
				_book_sel = -1
				_save_book()
		_:
			if k.unicode >= 32 and _focus != "":
				_type(char(k.unicode))
			else:
				return
	get_viewport().set_input_as_handled()
	queue_redraw()


## The edit fields: the player's name (10 characters) and the address.
func _type(c: String, back := false) -> void:
	if _focus == "name" and _row_on("name"):
		player_name = player_name.substr(0, player_name.length() - 1) if back else (player_name + c).substr(0, NAME_MAX)
	elif _focus == "addr" and _row_on("addr"):
		address = address.substr(0, address.length() - 1) if back else (address + c).substr(0, 256)


func _process(dt: float) -> void:
	if not visible:
		return
	_caret_t += dt
	if _copied_t > 0.0:
		_copied_t -= dt
		if _copied_t <= 0.0 and status == _copied_status:
			status = ""
	# A joiner on the page of the other kind of game: the host's mode decides.
	if joining and not host_mode.is_empty() and page in [JOIN_COOP, JOIN_LMP]:
		var want := JOIN_LMP if String(host_mode.get("mode", "")) == "lmp" else JOIN_COOP
		if want != page:
			_switched_from = page
			page = want
			_sel = -1
	elif not joining and _switched_from >= 0:
		_switched_from = -1
	queue_redraw()
