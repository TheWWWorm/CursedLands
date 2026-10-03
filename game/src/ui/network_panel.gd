class_name NetworkPanel
extends Interface800
## The co-op screen, laid out as the original's network connection screen (build
## server list, text; texts
## textslmp.res «string lmp_connection_<n>», tips texts.res 40600–40613), in
## 800×600 units stretched to the window:
## - the main menu signpost (unmoco2, MainMenu00 / MainMenu00labels) with only
##   its "Сетевая игра" board (but03 + button03_multiplayer), turned π/2 · 1.2,
##   at (400, 350) depth 8 (InterfaceBoard);
## - a status line (0,0)-(300,20), font 2 (the original shows «lmp_connection_8»
##   "Connecting…" there);
## - three panels in 5 px saveload frames: the server list
##   (100,100)-(390,500), the server panel (410,100)-(700,410) and the button
##   panel (410,430)-(700,500);
## - list headers at y 108..129: «Name» x 120, «#» 250, «Island» 278, «Ping»
##   348, a line (108,127)-(370,127); rows (108,132+24k)-(370,156+24k), text
##   (112,135+24k)-(365,156+24k): row 0 «New server:» + the server name, then
##   the address book (config/addrbook.ini in the original; yellow) with
##   players "%d/%d" at x 242, island at 270, ping right-aligned to 365; the
##   selected row's bar
## - server panel text from (440,120), 24 px lines, font 1: for the new server
##   «Server name:», its edit box (450,144)-(650,160) (: 10
##   characters, text, caret), «Max Players: n» and its slider
##   (450,196)-(650,206) (value + 1 players); for an address «Server name:»,
##   «Players: a / b», «IP:», «Ping:»;
## - buttons (490,444)-(620,465) «Refresh» tip 40610 and (490,468)-(620,489)
##   «Add/Remove» tip 40611 (sprite saveload UV 122,108-252,127, label font 1
##   centred), ✓ (163,526)-(237,574) UV 81,2-155,50 tip 40600, ✗ (563,526)-
##   (637,574) UV 160,2-234,50 tip 40601.
## Remake: ✓ on «New server» hosts the remake's co-op on port 27015 (Session),
## ✓ again starts the campaign; ✓ on an address joins it. The name edited is the
## player's name, the hero row picks the co-op hero (the original chose a network
## character on a screen of its own); the address book is kept
## user://addrbook.cfg; there is no master server, so «Refresh» only re-reads
## the lobby. **Approx.**: the original's "Base" allod checkboxes and "Private
## server" / "Password" switches have no remake counterpart and are left out;
## Max Players 1..6 as the original's slider (Session.MAX_PLAYERS).
## Remake-only aids (no the original counterpart; strings in HINTS below, plain
## English until the remake gets a translation table): a hint line for the
## current state under the status line (original textslmp strings where one
## fits: «lmp_connection_8» Connecting…, «lmp_connection_19» Enter Server IP
## address); while hosting the LAN and UPnP addresses to give friends, each
## with a «copy» click; Add/Remove on «New server:» adds an empty row, selects
## it and puts the caret in its IP field; Ctrl+V pastes into the edit box with
## the caret (or, on «New server:», into a new row); the ✓ tip names what ✓
## does now (host / start / join).

signal host_requested(max_players: int)
signal join_requested(address: String)
signal start_requested
signal back_requested

const LIST_ROWS := 15
const OK_RECT := Rect2(163, 526, 74, 48)
const CANCEL_RECT := Rect2(563, 526, 74, 48)
const REFRESH_RECT := Rect2(490, 444, 130, 21)
const ADD_RECT := Rect2(490, 468, 130, 21)
const NAME_EDIT := Rect2(450, 144, 200, 16)
const MAX_SLIDER := Rect2(450, 196, 200, 10)
const ADDR_EDIT := Rect2(450, 216, 200, 16)
const NAME_COLOR := Color8(0xff, 0xb3, 0x31)   # COLORREF
const BOOK_COLOR := Color8(0xee, 0xe3, 0x31)   # COLORREF
const BOOK_PATH := "user://addrbook.cfg"

var status := ""
var upnp_text := ""
var player_name := "Player"
var max_players := Session.MAX_PLAYERS
var hero := 0
var addresses: PackedStringArray = []
var sel := 0
var top := 0
var lobby: Array = []        # player names once hosting / joined
var hosting := false
## The game hosted: "" the remake's co-op campaign, else one of the original's
## multiplayer bases (LmpMode.BASES). The original's server panel has «Base:»
## (lmp_connection_3); its own base choice control is not traced, so it is a
## click-to-cycle row here. «Quest:» (lmp_connection_4) is the server's
## current quest, chosen in the game at the base's quest giver (
## offers on a new server, takes one), so it is no choice here.
var lmp_base := ""
var joining := false
var _focus := ""             # "name" / "addr": the edit box with the caret
var _caret_t := 0.0
var _drag := false
var _board: InterfaceBoard
## Remake: set by MainMenu while hosting — the port and the session's UPnP
## helper (its external address once the router answered).
var host_port := 0
var upnp: UpnpPort
var _copy_rects: Array = []   # [Rect2 (800 units), text] of the «copy» clicks drawn
var _copied_t := 0.0          # "copied" shown in the hint for a moment

## Remake-only texts of the aids above (kept together to be easy to find).
const HINTS := {
	"host": "Select «New server» and press ✓ to host",
	"join": " (IP, IP:port or [IPv6]:port) and press ✓ to join",
	"hosting": "Hosting — %d player(s) connected, press ✓ to start",
	"waiting": "Waiting for the host to start",
	"lan": "Your LAN address: %s",
	"internet": "Internet address (%s): %s",
	"ipv6": "IPv6 address: %s",
	"copy": "copy",
	"copied": "Copied to the clipboard.",
	"tip_host": "Now: host a co-op game.",
	"tip_start": "Now: start the campaign with the players connected.",
	"tip_join": "Now: join %s.",
	"tip_wait": "Now: nothing — waiting for the host to start.",
	"tip_copy": "Copy this address to the clipboard (remake).",
}
var _dim: Interface800.Backdrop


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	tooltip_text = " "
	_dim = Interface800.dim_layer()
	add_child(_dim)
	_board = InterfaceBoard.create("unmoco2", "mainmenu00", "mainmenu00labels",
		PackedStringArray(["but03", "button03_multiplayer"]), PI * 0.5 * 1.2, Vector3(400, 350, 8))
	_board.show_behind_parent = true   # under the panels, over the dimmed screen
	add_child(_board)
	resized.connect(queue_redraw)
	_load_book()


func open() -> void:
	player_name = GameData.player_name
	hero = maxi(0, Session.COOP_CLASSES.find(GameData.hero_class))
	max_players = Session.MAX_PLAYERS
	_dim.capture()   # the frame, frozen and greyed
	visible = true
	grab_focus()
	if OS.has_feature("web"):
		status = RemakeText.t("Join a WebSocket host with wss:// (ws:// on localhost). Hosting runs on desktop or Android.")
		if addresses.is_empty(): addresses.append("wss://")
		sel = 1
	queue_redraw()


func hero_class() -> String:
	return String(Session.COOP_CLASSES[clampi(hero, 0, Session.COOP_CLASSES.size() - 1)])


func selected_address() -> String:
	return addresses[sel - 1] if sel >= 1 and sel - 1 < addresses.size() else ""


func _load_book() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(BOOK_PATH) == OK:
		addresses = PackedStringArray(cfg.get_value("book", "addresses", PackedStringArray()))
	if addresses.is_empty():
		addresses = PackedStringArray(["127.0.0.1"])


func _save_book() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("book", "addresses", addresses)
	cfg.save(BOOK_PATH)


static func _lmp(n: int, fallback: String) -> String:
	var t := ""
	if GameData.is_open():
		t = _lmp_texts().get("string lmp_connection_%d" % n, "")
	return t if t else RemakeText.t(fallback)   # the German textslmp.res lacks 10..21


static var _lmp_cache := {}


## textslmp.res, the network game's texts (read once).
static func _lmp_texts() -> Dictionary:
	if _lmp_cache.is_empty():
		_lmp_cache["_"] = ""
		var a := EIResArchive.open_path(GameData.res_path("textslmp.res"))
		if a:
			for e: String in a.entries:
				if e.begins_with("string lmp_connection_"):
					_lmp_cache[e] = EIText.ansi(a.read(e)).replace("\r", "").strip_edges()
	return _lmp_cache


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var ui := tex("saveload")
	# The original's status rect is (0,0)-(300,20); the remake's longer lines (hosting
	# joining) get the screen's width instead of being cut with an ellipsis.
	text(Rect2(0, 0, 800 if text_width(status, 2) > 300.0 else 300, 20), status, 2, TEXT)
	var ty := 22.0 if status else 0.0
	if upnp_text:   # remake: the router forwarding result and the address to share (UpnpPort)
		text(Rect2(0, ty, 800, 20), upnp_text, 1, TEXT)
		ty += 20
	# Remake: the hint for the current state, then (hosting) the addresses to share.
	text(Rect2(0, ty, 800, 20), RemakeText.t(HINTS.copied) if _copied_t > 0.0 else _hint(), 1, NAME_COLOR)
	ty += 20
	_copy_rects.clear()
	if hosting:
		for a: Array in _share_addresses():
			var line_s: String = a[1]
			text(Rect2(0, ty, 800, 20), line_s, 1, TEXT)
			var cx := text_width(line_s, 1) + 8.0
			var cr := Rect2(cx, ty, text_width("[%s]" % RemakeText.t(HINTS.copy), 1) + 4.0, 20)
			text(cr, "[%s]" % RemakeText.t(HINTS.copy), 1, BOOK_COLOR)
			_copy_rects.append([cr, a[0]])
			ty += 20
	panel(Rect2(100, 100, 290, 400))
	panel(Rect2(410, 100, 290, 310))
	panel(Rect2(410, 430, 290, 70))
	# Server list: headers, line, rows.
	text(Rect2(120, 108, 270, 21), _lmp(12, "Name"))
	text(Rect2(250, 108, 140, 21), _lmp(13, "#"))
	text(Rect2(278, 108, 112, 21), _lmp(14, "Island"))
	text(Rect2(348, 108, 42, 21), _lmp(15, "Ping"))
	draw_line(p8(Vector2(108, 127)), p8(Vector2(370, 127)), TEXT, maxf(1.0, round(kv().y)))
	var n := addresses.size() + 1
	for i in LIST_ROWS:
		var k := top + i
		if k >= n:
			break
		var y := 132.0 + 24.0 * i
		if k == sel:
			draw_rect(r8(Rect2(108, y, 262, 24)), BAR)
		if k == 0:
			text(Rect2(112, y + 3, 253, 21), "%s %s" % [_lmp(7, "New server:"), player_name], 1, TEXT)
		else:
			text(Rect2(112, y + 3, 128, 21), addresses[k - 1], 1, BOOK_COLOR)
	# Server panel.
	var line := Rect2(440, 120, 250, 24)
	if sel == 0:
		text(line, _lmp(0, "Server name:"))
		_edit(NAME_EDIT, player_name, _focus == "name")
		line.position.y += 48
		text(line, "%s %d" % [_lmp(2, "Max Players:"), max_players])
		hslider(MAX_SLIDER, max_players - 1, Session.MAX_PLAYERS - 1)
		line.position.y += 48
	else:
		text(line, "%s %s" % [_lmp(0, "Server name:"), selected_address()])
		line.position.y += 24
		text(line, _lmp(5, "IP:"))
		_edit(Rect2(ADDR_EDIT.position.x, line.position.y + 24, ADDR_EDIT.size.x, ADDR_EDIT.size.y),
			selected_address(), _focus == "addr")
		line.position.y += 48
		text(line, "%s %d" % [_lmp(5, "IP:").trim_suffix(":") + RemakeText.t(" port:"), Session.parse_address(selected_address().strip_edges(), Session.PORT)[1]])
		line.position.y += 24
	# Remake: the co-op hero (the original picked a network character on its own screen).
	text(Rect2(440, line.position.y, 250, 24), RemakeText.t("Hero (remake): ") + _hero_title(), 1,
		TEXT if sel == 0 or CoopProgress.bring_slot.is_empty() else GREY)
	line.position.y += 24
	# Remake co-op: host settings / the joiner's own hero (CoopProgress).
	if sel == 0:
		text(Rect2(440, line.position.y, 250, 24), RemakeText.t("Full XP for all: ") + RemakeText.t("On" if XpRules.full_experience() else "Off"), 1, TEXT if lmp_base.is_empty() else GREY)
		line.position.y += 24
		text(Rect2(440, line.position.y, 250, 24), RemakeText.t("Scale monsters: ") + RemakeText.t(MobScaling.CHOICES[clampi(GameData.option("coop_scale"), 0, 3)]), 1, TEXT if lmp_base.is_empty() else GREY)
		line.position.y += 24
		# Original multiplayer game (LmpMode): its base.
		text(Rect2(440, line.position.y, 250, 24), "%s %s" % [_lmp(3, "Base:"), LmpMode.base_title(lmp_base) if lmp_base else RemakeText.t("campaign (remake co-op)")], 1, TEXT)
		line.position.y += 24
	else:
		text(Rect2(440, line.position.y, 250, 24), RemakeText.t("Bring: ") + _bring_title(), 1, TEXT)
		line.position.y += 24
	if hosting or joining:
		text(Rect2(440, line.position.y, 250, 24), "%s %d / %d" % [_lmp(1, "Players:"), lobby.size(), max_players])
		line.position.y += 24
		for nm: String in lobby:
			if line.position.y > 386:
				break
			text(Rect2(460, line.position.y, 230, 24), nm, 1, NAME_COLOR)
			line.position.y += 24
	if sel == 0:
		text(Rect2(440, 382, 250, 24), RemakeText.t("WebSocket: ") + RemakeText.t("On" if GameData.option("net_websocket") else "Off"))
	# Buttons.
	sprite(ui, REFRESH_RECT, [122, 108, 252, 127], Color(1, 1, 1) if hosting or joining else Color(0.5, 0.5, 0.5))
	text(Rect2(490, 445, 130, 20), _lmp(10, "Refresh"), 1, TEXT if hosting or joining else GREY, HORIZONTAL_ALIGNMENT_CENTER)
	sprite(ui, ADD_RECT, [122, 108, 252, 127])
	text(Rect2(490, 469, 130, 20), _lmp(11, "Add/Remove"), 1, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	sprite(ui, OK_RECT, [81, 2, 155, 50])
	sprite(ui, CANCEL_RECT, [160, 2, 234, 50])


## Remake: the hint line's text for the current state.
func _hint() -> String:
	if hosting:
		return RemakeText.t(HINTS.hosting) % lobby.size()
	if joining:
		return _lmp(8, "Connecting…") if lobby.is_empty() else RemakeText.t(HINTS.waiting)
	if sel == 0:
		return RemakeText.t(HINTS.host)
	return _lmp(19, "Enter Server IP address") + RemakeText.t(HINTS.join)


## Remake: [address, line] pairs to give friends while hosting — the first
## private IPv4 LAN address, the router's external one (UPnP / NAT-PMP / PCP,
## with the port it gave) and a global IPv6 address, with the port.
func _share_addresses() -> Array:
	var port := host_port if host_port > 0 else Session.PORT
	var out := []
	var lan := UpnpPort.lan_ipv4()
	if lan:
		var s := "%s:%d" % [lan, port]
		out.append([s, RemakeText.t(HINTS.lan) % s])
	if upnp and upnp.mapped and upnp.external_ip:
		var s := UpnpPort._join_text(upnp.external_ip, upnp.external_port if upnp.external_port > 0 else port)
		out.append([s, RemakeText.t(HINTS.internet) % [upnp.method, s]])
	var v6 := UpnpPort.global_ipv6()
	if v6:
		var s := "[%s]:%d" % [v6, port]
		out.append([s, RemakeText.t(HINTS.ipv6) % s])
	if GameData.option("net_websocket"):
		for entry in out:
			entry[0] = "ws://" + String(entry[0])
			entry[1] = RemakeText.t("WebSocket host: ") + entry[0]
	return out


func _hero_title() -> String:
	var proto := hero_class()
	var t := GameUnit.unit_title(proto) if GameData.is_open() else ""
	return t if t else proto.trim_prefix("Human Mercenary ")


## the text, and a caret line after it.
func _edit(r: Rect2, s: String, focused: bool) -> void:
	text(r.grow_individual(0, 3, 0, 3), s, 1, TEXT)
	if focused and fmod(_caret_t, 1.0) < 0.5:
		var f := font()
		var x := r8(r).position.x + f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px(1)).x + 1
		var rr := r8(r)
		draw_line(Vector2(x, rr.position.y), Vector2(x, rr.end.y), NAME_COLOR, maxf(1.0, round(kv().x)))


# ------------------------------------------------------------------ input

func _hit(p: Vector2) -> Array:
	for c: Array in _copy_rects:
		if (c[0] as Rect2).has_point(p):
			return ["copy", c[1]]
	if OK_RECT.has_point(p):
		return ["ok"]
	if CANCEL_RECT.has_point(p):
		return ["cancel"]
	if REFRESH_RECT.has_point(p):
		return ["refresh"]
	if ADD_RECT.has_point(p):
		return ["add"]
	for i in LIST_ROWS:
		if top + i <= addresses.size() and Rect2(108, 132 + 24 * i, 262, 24).has_point(p):
			return ["row", top + i]
	if sel == 0:
		if Rect2(440, 378, 250, 30).has_point(p):
			return ["transport"]
		if NAME_EDIT.grow(4).has_point(p):
			return ["name"]
		var part := hslider_hit(MAX_SLIDER, max_players - 1, Session.MAX_PLAYERS - 1, p)
		if part:
			return ["max", part]
		if Rect2(440, 216, 250, 24).has_point(p):
			return ["hero"]
		if Rect2(440, 240, 250, 24).has_point(p):
			return ["fullxp"]
		if Rect2(440, 264, 250, 24).has_point(p):
			return ["scale"]
		if Rect2(440, 288, 250, 24).has_point(p):
			return ["base"]
	else:
		if Rect2(ADDR_EDIT.position.x, 168, ADDR_EDIT.size.x, 16).grow(4).has_point(p):
			return ["addr"]
		if Rect2(440, 216, 250, 24).has_point(p):
			return ["hero"]
		if Rect2(440, 240, 250, 24).has_point(p):
			return ["bring"]
	return []


## Remake co-op: what a joiner brings — "" a co-op hero of the chosen class
## (nothing kept), "new" a new campaign Zak, or the hero of one of its saves
## (progress comes back as a new save, CoopProgress).
func _bring_choices() -> Array:
	var out := ["", CoopProgress.NEW]
	for i: SaveInfo in SaveInfo.list():
		if not i.error:
			out.append(i.slot)
	return out


func _bring_title() -> String:
	match CoopProgress.bring_slot:
		"": return RemakeText.t("co-op hero (nothing kept)")
		CoopProgress.NEW: return RemakeText.t("new Zak (start fresh)")
	var i := SaveInfo.read(CoopProgress.bring_slot)
	return RemakeText.t("Zak of \"%s\"") % i.display_name().left(18)


## Remake: what ✓ does right now (its tip, _confirm).
func _ok_action() -> String:
	if joining:
		return RemakeText.t(HINTS.tip_wait)
	if sel == 0:
		return RemakeText.t(HINTS.tip_start) if hosting else RemakeText.t(HINTS.tip_host)
	return RemakeText.t(HINTS.tip_join) % (selected_address().strip_edges() if selected_address().strip_edges() else "…")


func _get_tooltip(at: Vector2) -> String:
	var h := _hit(to800(at))
	if h.is_empty():
		return ""
	match h[0]:
		"ok": return "\n".join(PackedStringArray([GameData.text("tip 40600").strip_edges(), _ok_action()] \
			.filter(func(t: String): return t != "")))
		"copy": return RemakeText.t(HINTS.tip_copy)
		"cancel": return GameData.text("tip 40601").strip_edges()
		"refresh": return GameData.text("tip 40610").strip_edges() + "\n" + RemakeText.t("(Remake: no master server; re-reads the lobby.)")
		"add": return GameData.text("tip 40611").strip_edges()
		"hero": return RemakeText.t("Co-op hero (remake)\nThe hero you play when you join someone's campaign (the host plays Zak). Click to change.")
		"fullxp": return RemakeText.t("Full experience for every party member (remake, host)\n%s\nClick to change; also in Options, Game.") % RemakeText.t(GameData.REMAKE_OPTIONS.coop_full_xp[1])
		"scale": return RemakeText.t("Scale monsters to player count (remake, host)\n%s\nClick to change; also in Options, Game.") % RemakeText.t(GameData.REMAKE_OPTIONS.coop_scale[1])
		"bring": return RemakeText.t("Your hero (remake)\nBring the Zak of one of your saves (or a new one): you play the host's world, and what you achieve there that your own game has not done yet comes back as a new save \"Co-op: <host>\"; your old save is kept. Click to change.")
		"base": return RemakeText.t("Base (host)\nThe campaign (remake co-op), or one of the original multiplayer bases: the party starts there and its exit leads to the quest's zone. Click to change.")
		"name": return RemakeText.t("Your name in the co-op game.")
		"addr": return RemakeText.t("Server IP address (port %d).") % Session.PORT
		"max": return RemakeText.t("Max players")
	return ""


func _gui_input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var h := _hit(to800(e.position))
		_focus = ""
		if not h.is_empty():
			match h[0]:
				"ok":
					sound("messbox\\ok")
					_confirm()
				"cancel":
					sound("messbox\\cancel")
					back_requested.emit()
				"refresh":
					sound("save\\select")
					queue_redraw()
				"copy":   # remake
					sound("save\\select")
					DisplayServer.clipboard_set(String(h[1]))
					_copied_t = 2.0
				"add":
					sound("save\\select")
					if sel == 0:
						_add_row("")
					else:
						addresses.remove_at(sel - 1)
						sel = mini(sel, addresses.size())
					_save_book()
				"row":
					if h[1] != sel:
						sound("save\\select")
					sel = h[1]
				"name":
					_focus = "name"
					if TouchInput.enabled:
						TouchTextEdit.open(self, player_name, 10, func(value): player_name = value; queue_redraw(), "Player name")
				"addr":
					_focus = "addr"
					_edit_touch_address()
				"transport":
					if not hosting and not joining:
						GameData.set_option("net_websocket", 0 if GameData.option("net_websocket") else 1)
				"hero":
					sound("messbox\\ok")
					hero = (hero + 1) % Session.COOP_CLASSES.size()
				"fullxp":
					sound("messbox\\ok")
					GameData.set_option("coop_full_xp", 0 if XpRules.full_experience() else 1)
				"base":
					if not joining and LmpMode.available():
						sound("messbox\\ok")
						var bases := [""] + LmpMode.BASES
						lmp_base = bases[(bases.find(lmp_base) + 1) % bases.size()]
				"scale":
					sound("messbox\\ok")
					GameData.set_option("coop_scale", (GameData.option("coop_scale") + 1) % MobScaling.CHOICES.size())
				"bring":
					sound("messbox\\ok")
					var ch := _bring_choices()
					CoopProgress.bring_slot = ch[(maxi(0, ch.find(CoopProgress.bring_slot)) + 1) % ch.size()]
				"max":
					if h[1] == "left":
						max_players = maxi(1, max_players - 1)
					elif h[1] == "right":
						max_players = mini(Session.MAX_PLAYERS, max_players + 1)
					elif h[1] == "thumb":
						_drag = true
		queue_redraw()
		accept_event()
	elif e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = false
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		top = clampi(top + (-1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1), 0, maxi(0, addresses.size() + 1 - LIST_ROWS))
		queue_redraw()
		accept_event()
	elif e is InputEventMouseMotion and _drag:
		max_players = hslider_value(MAX_SLIDER, Session.MAX_PLAYERS - 1, to800(e.position).x) + 1
		queue_redraw()
		accept_event()
	elif e is InputEventKey and e.pressed:
		_key(e)
		accept_event()


## Remake: a new address row, selected, with the caret in its IP field.
func _add_row(a: String) -> void:
	addresses.append(a)
	sel = addresses.size()
	top = clampi(top, sel - LIST_ROWS + 1, sel)
	_focus = "addr"
	_caret_t = 0.0
	_save_book()
	_edit_touch_address()


func _edit_touch_address() -> void:
	if not TouchInput.enabled or sel < 1:
		return
	var index := sel - 1
	TouchTextEdit.open(self, addresses[index], 256, func(value):
		addresses[index] = value
		_save_book()
		queue_redraw(), "Server address")


## Remake: Ctrl+V pastes the clipboard's first line into the edit box with the
## caret; on «New server:» without one it goes into a new address row.
func _paste() -> void:
	var c := DisplayServer.clipboard_get().strip_edges().get_slice("\n", 0).strip_edges()
	if c.is_empty():
		return
	if _focus == "" and sel >= 1:
		_focus = "addr"
	if _focus == "":
		if sel == 0:
			_add_row(c.substr(0, 64))
		return
	for ch in c:
		_type(ch, false)


func _key(e: InputEventKey) -> void:
	if e.keycode == KEY_V and (e.ctrl_pressed or e.meta_pressed):
		_paste()
		queue_redraw()
		return
	match e.keycode:
		KEY_ESCAPE:
			if _focus != "":
				_focus = ""
			else:
				sound("messbox\\cancel")
				back_requested.emit()
		KEY_ENTER, KEY_KP_ENTER:
			_focus = ""
			sound("messbox\\ok")
			_confirm()
		KEY_UP, KEY_DOWN:
			if _focus == "":
				sound("save\\select")
				sel = clampi(sel + (-1 if e.keycode == KEY_UP else 1), 0, addresses.size())
				top = clampi(top, sel - LIST_ROWS + 1, sel)
		KEY_BACKSPACE:
			_type("", true)
		_:
			if e.unicode >= 32:
				_type(char(e.unicode), false)
	queue_redraw()


## The edit boxes: the player's name (10 characters) and the
## selected address.
func _type(c: String, back: bool) -> void:
	if _focus == "name":
		player_name = player_name.substr(0, player_name.length() - 1) if back else (player_name + c).substr(0, 10)
	elif _focus == "addr" and sel >= 1:
		var a := addresses[sel - 1]
		a = a.substr(0, a.length() - 1) if back else (a + c).substr(0, 256)
		addresses[sel - 1] = a
		_save_book()


func _confirm() -> void:
	if OS.has_feature("web") and sel == 0:
		status = RemakeText.t("Browser players join a desktop or Android WebSocket host.")
		queue_redraw()
		return
	if sel == 0:
		if hosting:
			start_requested.emit()
		else:
			host_requested.emit(max_players)
	elif selected_address().strip_edges() != "":
		join_requested.emit(selected_address().strip_edges())


func _process(dt: float) -> void:
	if visible and _focus != "":
		_caret_t += dt
		queue_redraw()
	if _copied_t > 0.0:
		_copied_t -= dt
		queue_redraw()
	elif visible and hosting and upnp and upnp.busy:
		queue_redraw()   # the UPnP address appears when the router answers
