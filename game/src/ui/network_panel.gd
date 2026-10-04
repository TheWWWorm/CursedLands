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
## Host: the game's password ("" none; Session.password, the original's Password
## switch case 5); joiner: the one it joins with
## (Session.join_password, the original's «Enter password» box).
var password := ""
var join_password := ""
## Join pages: the local network's games (LanDiscovery, the original's server
## list); not in the browser build.
var lan: LanDiscovery
var _lan_sel := -1          # the selected LAN game (index into _lan_list)
var _lan_list: Array = []   # the LAN games as drawn last (LanDiscovery.list)

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
	lan = LanDiscovery.new()
	lan.name = "LanDiscovery"
	add_child(lan)
	add_to_group("pad_panel")   # remake: gamepad snap targets (pad_targets, pad_press)


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
	_lan_sel = -1
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
			out.append({"id": "password", "kind": "edit", "label": pw_label(), "value": join_password, "on": not joining,
				"hint": _pw_hint(false)})
	if page in [HOST_COOP, HOST_LMP]:
		out.append({"id": "players", "kind": "slider", "label": RemakeText.t("Players"), "value": str(max_players), "on": not hosting,
			"hint": RemakeText.t("At most, you included.")})
		out.append({"id": "password", "kind": "edit", "label": pw_label(), "value": password, "on": not hosting,
			"hint": _pw_hint(true)})
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


## «Password» (textslmp lmp_connection_17, the server screen's switch).
static func pw_label() -> String:
	return NetStatus.lmp_text("lmp_connection_17", "", RemakeText.t("Password"))


func _pw_hint(host: bool) -> String:
	if host:
		# the original tip 40613 «Password / Create a password protected server».
		var tip := GameData.text("tip 40613").strip_edges().replace("\r", "").split("\n")
		var t := String(tip[1]).strip_edges() if tip.size() > 1 else ""
		return (t + ". " if t else "") + RemakeText.t("Friends must type it to join; leave it empty for a game anyone can join.")
	return RemakeText.t("Only if the host set one (the list shows “%s”); otherwise leave it empty.") \
		% NetStatus.lmp_text("lmp_connection_21", "", RemakeText.t("Password required"))


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
	_draw_pad_glyphs()


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
			# One band: the selection (the pointer moves it, see _gui_input).
			if i == _sel:
				draw_rect(r8(r), BAR)
			# The plate and the description centred on the row, the caption
			# on the plate.
			var plate := Rect2(120, r.get_center().y - 10.5, 190, 21)
			sprite(ui, plate, PLATE_UV, Color.WHITE if off.is_empty() else Color(0.5, 0.5, 0.5))
			var title := _mode_title(p)
			var f := 1 if text_width(title, 1) <= plate.size.x - 12 else 0   # long translations
			text_vc(plate, title, f, GREY if off else (Color.WHITE if i == _sel else TEXT), HORIZONTAL_ALIGNMENT_CENTER)
			var dn := mini(wrap_text(_mode_desc(p), 362, 0).size(), 3 if off.is_empty() else 2)
			var offn := mini(wrap_text(off, 362, 0).size(), 2) if off else 0
			var dy := r.get_center().y - (dn + offn) * line_h(0) * 0.5
			var h := _block(Rect2(322, dy, 362, 48), _mode_desc(p), 0, GREY if off else TEXT, 3 if off.is_empty() else 2)
			if off:
				_block(Rect2(322, dy + h, 362, 32), off, 0, ORANGE, 2)
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
	return Rect2(110, ROW0 + _row_h() * r, 580, _row_h())


## 24 units a row, less when the page has more rows than the upper panel
## holds at 24 (host co-op with the password: 8).
func _row_h() -> float:
	var n := _rows().size() if page != MODES else 0
	return minf(24.0, floorf((TOP.end.y - ROW0) / maxf(1.0, n)))


func _draw_row(r: int, row: Dictionary) -> void:
	var rr := _row_rect(r)
	var y := rr.position.y
	var h := rr.size.y
	var m := (h - 18.0) * 0.5   # an edit field's or plate's margin
	var id := "row:" + String(row.id)
	_targets[id] = rr
	var on: bool = row.on
	if r == _sel:   # one band: the pointer moves the selection
		draw_rect(r8(rr), BAR)
	text_vc(Rect2(120, y, 275, h), String(row.label), 1, TEXT if on else GREY)
	var col := TEXT if on else GREY
	match String(row.kind):
		"edit":
			var w := 208.0 if row.id == "addr" else 285.0
			var ph := ""
			if row.id == "addr":
				ph = RemakeText.t("e.g. wss://example.org/game") if _web() else RemakeText.t("e.g. 192.168.1.20 or 203.0.113.7:27015")
			elif row.id == "password":
				ph = RemakeText.t("none")
			_edit(Rect2(400, y + m, w, 18), String(row.value), _focus == row.id and on, on, ph)
			if row.id == "addr":
				_plate("paste", Rect2(613, y + m, 74, 19), RemakeText.t("Paste"), on)
		"choice":
			_arrow(Vector2(408, y + h * 0.5), true, on)
			_arrow(Vector2(682, y + h * 0.5), false, on)
			text_vc(Rect2(418, y, 254, h), String(row.value), 1, col, HORIZONTAL_ALIGNMENT_CENTER)
		"switch":
			text_vc(Rect2(400, y, 285, h), String(row.value), 1, col)
		"slider":
			if on:
				hslider(_slider_rect(r), float(max_players - 1), float(Session.MAX_PLAYERS - 1))
			text_vc(Rect2(590 if on else 400, y, 95, h), String(row.value), 1, col)
		"link":
			text_vc(Rect2(400, y, 180, h), String(row.value), 1, col)
			_plate("char", Rect2(585, y + m, 102, 19), RemakeText.t("Choose…"), on)


func _slider_rect(r: int) -> Rect2:
	return Rect2(400, ROW0 + _row_h() * r + _row_h() * 0.5 - 5.0, 180, 10)


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
	text_vc(r, label, 1 if text_width(label, 1) <= r.size.x - 6 else 0,
		col, HORIZONTAL_ALIGNMENT_CENTER)


## An edit field (the Load / Save screen's name edit: the text and a caret
## ), on a darker ground with a thin edge so it reads as a field.
func _edit(r: Rect2, s: String, focused: bool, on: bool, placeholder := "") -> void:
	draw_rect(r8(r), Color(0, 0, 0, 0.55))
	draw_rect(r8(r), Color(ORANGE, 0.8) if focused else Color(GREY, 0.45), false, maxf(1.0, round(kv().y)))
	var tr := Rect2(r.position.x + 4, r.position.y, r.size.x - 8, r.size.y)
	if s.is_empty() and not focused and placeholder:
		text_vc(tr, placeholder, 0, Color(GREY, 0.7))
	else:
		# The end of a long text stays in view.
		var shown := s
		while shown.length() > 1 and text_width(shown, 1) > tr.size.x - 4:
			shown = shown.substr(1)
		text_vc(tr, shown, 1, Color.WHITE if on else GREY, HORIZONTAL_ALIGNMENT_LEFT, true)
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
	# Left: the local network's games and the recent addresses in one list,
	# as the original's server list (: Name / # / Island / Ping, the
	# address book's rows yellow, the others); in the
	# browser only the recent addresses.
	var br := _book_rect()
	var items := _items()
	var lan_on := _lan_on()
	if lan_on:
		for c: Array in _columns():
			text(Rect2(c[0], y, c[1], 20), String(c[2]), 1, ORANGE, c[3])
		var ly := br.position.y - 3
		draw_line(p8(Vector2(br.position.x, ly)), p8(Vector2(br.end.x - 14, ly)), Color(ORANGE, 0.6), maxf(1.0, round(kv().y)))
	else:
		text(Rect2(x0, y, 340, 20), RemakeText.t("Recent addresses"), 1, ORANGE)
	_book_top = clampi(_book_top, 0, maxi(0, items.size() - BOOK_ROWS))
	if items.is_empty():
		text(Rect2(x0, br.position.y + 2, 330, 18), RemakeText.t("Looking for games on your network…") if lan_on and not joining else RemakeText.t("none"), 0, GREY)
	for k in BOOK_ROWS:
		var n := _book_top + k
		if n >= items.size():
			break
		var it: Dictionary = items[n]
		var id := "%s:%d" % [it.kind, it.i]
		var rr := Rect2(br.position.x, br.position.y + 22 * k, br.size.x - 14, 22)
		_targets[id] = rr
		if (it.kind == "book" and it.i == _book_sel) or (it.kind == "lan" and it.i == _lan_sel):
			draw_rect(r8(rr), BAR)
		elif _hover == id and not joining:
			draw_rect(r8(rr), HOVER_BAR)
		var col := GREY if joining else (YELLOW if it.kind == "book" else TEXT)
		var g: Dictionary = it.g
		if g.is_empty():
			text_vc(Rect2(rr.position.x + 4, rr.position.y, rr.size.x - 8, rr.size.y), String(it.address), 1, col, HORIZONTAL_ALIGNMENT_LEFT, true)
			continue
		var cells := [String(g.name) if String(g.name) else String(it.address), "%d/%d" % [g.players, g.max], _island(g), str(g.ping)]
		var cs := _columns()
		for c in cs.size():
			var cr := Rect2(cs[c][0], rr.position.y, cs[c][1], rr.size.y)
			text_vc(cr, cells[c], 1 if c == 0 else 0, col, cs[c][3], true)
	vbar(Rect2(br.position.x, br.position.y, br.size.x, br.size.y), float(_book_top), float(items.size() - BOOK_ROWS))
	_plate("remove", Rect2(x0, LOW.end.y - 26, 110, 19), RemakeText.t("Remove"), _book_sel >= 0 and not joining)
	# Right: the selected game's details (right panel), the
	# address formats, or the connection.
	var rx := 460.0
	var ry := LOW.position.y + 6
	if not joining:
		var sel := _selected_game()
		if not sel.is_empty():
			_draw_details(rx, ry, sel)
			return
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


func _lan_on() -> bool:
	return LanDiscovery.available() and not _web()


## The list's columns [x, width, title, align]: textslmp lmp_connection_12..15
## (Name / # / Island / Ping; the original x 120 / 250 / 278 / 348 over 270 px).
func _columns() -> Array:
	var x := _book_rect().position.x + 4
	return [[x, 140.0, NetStatus.lmp_text("lmp_connection_12", "", RemakeText.t("Name")), HORIZONTAL_ALIGNMENT_LEFT],
		[x + 142, 40.0, NetStatus.lmp_text("lmp_connection_13", "", "#"), HORIZONTAL_ALIGNMENT_CENTER],
		[x + 184, 92.0, NetStatus.lmp_text("lmp_connection_14", "", RemakeText.t("Island")), HORIZONTAL_ALIGNMENT_LEFT],
		[x + 278, 44.0, NetStatus.lmp_text("lmp_connection_15", "", RemakeText.t("Ping")), HORIZONTAL_ALIGNMENT_RIGHT]]


## A game's "Island": the multiplayer game's base (lmp_allod_name_<n>), the
## remake's co-op campaign by name.
func _island(g: Dictionary) -> String:
	if String(g.get("mode", "")) == "lmp":
		return LmpMode.base_title(String(g.get("base", ""))) if String(g.get("base", "")) else "—"
	return RemakeText.t("Co-op campaign")


## [host, port] of an address-book entry ("ws://" kept off the host).
static func _host_port(a: String) -> Array:
	var t := a.strip_edges().trim_prefix("ws://").trim_prefix("wss://")
	if t.contains("/"):
		t = t.get_slice("/", 0)
	return Session.parse_address(t, Session.PORT)


## The game answering from an address-book entry's host, {} none.
func _book_game(a: String) -> Dictionary:
	if not _lan_on():
		return {}
	var hp := _host_port(a)
	return lan.game_at(String(hp[0]), int(hp[1]))


## The join list: the LAN games that are not in the address book, then the
## book's entries, each {kind "lan" / "book", i, address, g (what its host
## answered, {} none)}.
func _items() -> Array:
	var out := []
	_lan_list = lan.list() if _lan_on() else []
	var booked := {}
	for i in addresses.size():
		var g := _book_game(addresses[i])
		if not g.is_empty():
			booked[String(g.address)] = true
		out.append({"kind": "book", "i": i, "address": addresses[i], "g": g})
	var lans := []
	for k in _lan_list.size():
		if not booked.has(String(_lan_list[k].address)):
			lans.append({"kind": "lan", "i": k, "address": String(_lan_list[k].address), "g": _lan_list[k]})
	return lans + out


## The game of the selected row, {} none (or a book entry nobody answered).
func _selected_game() -> Dictionary:
	if _lan_sel >= 0 and _lan_sel < _lan_list.size():
		return _lan_list[_lan_sel]
	if _book_sel >= 0 and _book_sel < addresses.size():
		return _book_game(addresses[_book_sel])
	return {}


## the original details of a server: Server name / Players / Base
## Quest / IP / Ping (textslmp lmp_connection_0, 1, 3, 4, 5, 6), and «Password
## required» (lmp_connection_21) when the server has one.
func _draw_details(rx: float, ry: float, g: Dictionary) -> void:
	var lines := [
		[NetStatus.lmp_text("lmp_connection_0", "", RemakeText.t("Server name:")), String(g.name)],
		[NetStatus.lmp_text("lmp_connection_1", "", RemakeText.t("Players:")), "%d / %d" % [g.players, g.max]],
		[NetStatus.lmp_text("lmp_connection_3", "", RemakeText.t("Base:")), _island(g)],
	]
	if String(g.get("quest", "")):
		lines.append([NetStatus.lmp_text("lmp_connection_4", "", RemakeText.t("Quest:")), LmpMode.quest_title(String(g.quest))])
	lines.append([NetStatus.lmp_text("lmp_connection_5", "", "IP:"), String(g.address)])
	lines.append([NetStatus.lmp_text("lmp_connection_6", "", RemakeText.t("Ping:")), str(g.ping)])
	for l: Array in lines:
		text(Rect2(rx, ry, 230, 20), "%s %s" % l, 1, TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
		ry += 20
	if bool(g.get("pw", false)):
		text(Rect2(rx, ry, 230, 20), NetStatus.lmp_text("lmp_connection_21", "", RemakeText.t("Password required")), 1, ORANGE)
		ry += 20
	if int(g.get("protocol", 0)) != NetStatus.PROTOCOL:
		_block(Rect2(rx, ry, 230, LOW.end.y - ry - 4), NetStatus.lmp_text("lmp_wrong_protocol_msg", "", RemakeText.t("Wrong communication protocol version")), 0, ORANGE, 2)


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
		"name", "addr", "password":
			_focus = id
			_caret_t = 0.0
			if TouchInput.enabled:
				if id == "name":
					TouchTextEdit.open(self, player_name, NAME_MAX, func(v): player_name = v; queue_redraw(), "Player name")
				elif id == "password":
					if page in [HOST_COOP, HOST_LMP]:
						TouchTextEdit.open(self, password, Session.PASSWORD_MAX, func(v): password = v; queue_redraw(), pw_label())
					else:
						TouchTextEdit.open(self, join_password, Session.PASSWORD_MAX, func(v): join_password = v; queue_redraw(), pw_label())
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


## A game with a password (the original: the «Enter password» box on ✓
## ): the caret goes to the Password row when it is empty.
func _ask_password(g: Dictionary) -> void:
	if bool(g.get("pw", false)) and join_password.is_empty() and _row_on("password"):
		_focus = "password"
		_caret_t = 0.0


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
			# the original: a listed server of another protocol is
			# refused with «lmp_wrong_protocol» before connecting.
			var g := _selected_game()
			if not g.is_empty() and String(g.address) == a and int(g.get("protocol", 0)) != NetStatus.PROTOCOL:
				status = NetStatus.lmp_text("lmp_wrong_protocol_msg", "", RemakeText.t("Wrong communication protocol version"))
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


## The pointer on a row takes the selection, so the keys go on from there and
## only one row has the band.
func _follow_hover() -> void:
	if _hover.begins_with("mode:") and page == MODES:
		var pg := PAGE_NAMES.find(_hover.trim_prefix("mode:"))
		if pg > 0 and _mode_off(pg).is_empty():
			_sel = pg - 1
	elif _hover.begins_with("row:") and page != MODES:
		var rows := _rows()
		for r in rows.size():
			if "row:" + String(rows[r].id) == _hover:
				_sel = r


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
			_book_top = vbar_value(_book_rect(), float(_items().size() - BOOK_ROWS), p.y)
		var h := _hit(p)
		if h != _hover:
			_hover = h
			_follow_hover()
			queue_redraw()
		return
	if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = false
		_book_drag = false
		accept_event()
		return
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if page in [JOIN_COOP, JOIN_LMP] and _book_rect().has_point(to800(e.position)):
			_book_top = clampi(_book_top + (-1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1), 0, maxi(0, _items().size() - BOOK_ROWS))
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
		var n_items := _items().size()
		var part := vbar_hit(_book_rect(), float(_book_top), float(n_items - BOOK_ROWS), p)
		if part and n_items > BOOK_ROWS:
			if part == "thumb":
				_book_drag = true
			elif part in ["up", "down"]:
				_book_top = clampi(_book_top + (-1 if part == "up" else 1), 0, n_items - BOOK_ROWS)
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
			_lan_sel = -1
			address = addresses[i]
			_ask_password(_book_game(address))
			if e.double_click:
				_primary()
	elif h.begins_with("lan:"):
		if not joining:
			var k := h.trim_prefix("lan:").to_int()
			if k < _lan_list.size():
				sound("save\\select")
				_lan_sel = k
				_book_sel = -1
				address = String(_lan_list[k].address)
				_ask_password(_lan_list[k])
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
		if _focus in ["name", "password"]:
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
			_hover = ""   # the keys take over the selection from the pointer
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
		_lan_sel = -1
	elif _focus == "password" and _row_on("password"):
		# the original: a 20-byte field.
		if page in [HOST_COOP, HOST_LMP]:
			password = password.substr(0, password.length() - 1) if back else (password + c).substr(0, Session.PASSWORD_MAX)
		else:
			join_password = join_password.substr(0, join_password.length() - 1) if back else (join_password + c).substr(0, Session.PASSWORD_MAX)


func _process(dt: float) -> void:
	# The LAN game list asks while a join page is open (asks
	# while the server screen is up), the address book's hosts directly.
	var scan := visible and page in [JOIN_COOP, JOIN_LMP] and not joining and _lan_on()
	if lan:
		if scan:
			var hosts := PackedStringArray()
			for a in addresses:
				hosts.append(String(_host_port(a)[0]))
			lan.direct = hosts
		lan.scan(scan)
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


# ------------------------------------------------------------------ gamepad

## Remake (gamepad, PadUI; docs/gamepad_design.md §7): everything drawn as a
## target is a snap target for the D-pad (the choices of game, the rows, the
## plates, the recent addresses, ✓ / ✗). A on a row works it as Enter does
## (a choice steps on, a switch flips, the name / address field takes the
## keyboard, the character row opens its screen); D-pad ← / → on a choice or
## the players slider changes it; Y is ✓; B is Esc (the key bridge). Other
## targets are clicked at their centre, as the mouse does.
func pad_targets() -> Array:
	var out: Array = []
	for id: String in _targets:
		if id == "ok" and _ok_label().is_empty():
			continue
		out.append({"rect": pad_rect(_targets[id]), "id": id})
	return out


## Where the D-pad starts: the selected choice or row.
func pad_focus() -> Variant:
	if page == MODES:
		return "mode:" + PAGE_NAMES[_sel + 1] if _sel >= 0 else null
	var rows := _rows()
	if rows.is_empty():
		return null
	return "row:" + String(rows[clampi(_sel, 0, rows.size() - 1)].id)


## The row the gamepad's focus is on: {i, row}, {} when none.
func _pad_row() -> Dictionary:
	var ui: PadUI = PadInput.ui
	var f: Variant = ui.focus_id() if ui else null
	if page == MODES or not (f is String) or not String(f).begins_with("row:") or not ui.pointer_on:
		return {}
	var rows := _rows()
	for r in rows.size():
		if "row:" + String(rows[r].id) == f:
			return {"i": r, "row": rows[r]}
	return {}


func pad_press(action: String, phase: String) -> bool:
	if not phase in ["down", "repeat"]:
		return false
	match action:
		"pause":   # Y = ✓
			if phase == "down" and _ok_enabled():
				_focus = ""
				_primary()
			return true
		"up", "down":
			_focus = ""   # the D-pad leaves a text field
		"left", "right":
			var h := _pad_row()
			if h.is_empty() or not h.row.on or not String(h.row.kind) in ["choice", "slider"]:
				_focus = ""
				return false
			_sel = h.i
			_activate(String(h.row.id), -1 if action == "left" else 1)
			return true
		"interact":
			var h := _pad_row()
			if phase != "down" or h.is_empty():
				return false
			_sel = h.i
			if h.row.on:
				_activate(String(h.row.id))
			queue_redraw()
			return true
	return false


## The controller's buttons beside ✓ (Y) and ✗ (B) while it drives.
func _draw_pad_glyphs() -> void:
	if PadInput.active != "pad":
		return
	var gs := Vector2(22, 22)
	if not _ok_label().is_empty():
		var y := PadInput.glyph(PadInput.button_of("pause"))
		if y:
			draw_texture_rect(y, r8(Rect2(OK_RECT.position + Vector2(-26, 13), gs)), false,
				Color.WHITE if _ok_enabled() else Color(0.5, 0.5, 0.5))
	var b := PadInput.glyph(PadInput.button_of("cancel"))
	if b:
		draw_texture_rect(b, r8(Rect2(CANCEL_RECT.position + Vector2(-26, 13), gs)), false)
