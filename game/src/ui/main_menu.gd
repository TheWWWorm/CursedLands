extends Control
## Main menu: the original signpost scene (MenuScene); its "Сетевая игра" board
## opens the co-op screen in the style of the original's network screens
## (NetworkPanel), "Настройки" the Options screen (OptionsPanel). Without
## the original data a plain fallback menu is shown. The map viewer (remake
## tool) is a small link at the bottom left in debug runs (`-- --debug`).

signal start_game(session: Session)

var _name: LineEdit
var _addr: LineEdit
var _hero: OptionButton
var _status: Label
var _lobby: ItemList
var _start: Button
var _session: Session
var _addr_default := "127.0.0.1"
var _scene: MenuScene
var _panel: Control          # the co-op screen (NetworkPanel), or the fallback menu
var _net: NetworkPanel
var _options: OptionsPanel
var _difficulty: DifficultyPanel
var _load: LoadPanel
var _music: AudioStreamPlayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Loading screens and the intro need their movies converted (MoviePlayer);
	# small ones first.
	MoviePlayer.preconvert(LoadingScreen.MOVIES + ["ttlsfin", "titles", "ttlsfout", "intro"])
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # clicks reach the signpost
	# The original menu: the signpost in its 3D scene (menus.res + zonemainmenunew).
	_scene = MenuScene.create() if GameData.root else null
	if _scene:
		add_child(_scene)
		_scene.camera.current = true
		_scene.pressed.connect(_on_board)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.07, 0.06, 0.05)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
	var music := AudioStreamPlayer.new()
	_music = music
	music.bus = "Music"
	var track := String(EIAudio.music_table().get("common", {}).get("MainMenu", "main"))
	music.stream = EIAudio.music(track)
	music.volume_db = -8.0
	add_child(music)
	if music.stream:
		music.play()
	_options = OptionsPanel.new()
	if _scene:
		_net = NetworkPanel.new()
		_panel = _net
		add_child(_net)
		_net.host_requested.connect(_host)
		_net.join_requested.connect(_join)
		_net.start_requested.connect(_start_coop)
		_net.back_requested.connect(_leave_net)
		# Remake tool: the map viewer link only in a debug run (`-- --debug`).
		if OS.get_cmdline_user_args().has("--debug"):
			_add_viewer_link()
		_difficulty = DifficultyPanel.new()
		add_child(_difficulty)
		_difficulty.accepted.connect(func(lvl: int):
			GameData.set_option("difficulty", lvl)   # settings
			_single())
		_load = LoadPanel.new()
		add_child(_load)
		_load.load_requested.connect(_load_slot)
		add_child(_options)
		return
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	var panel := PanelContainer.new()
	_panel = panel
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.03, 0.85)
	sb.set_content_margin_all(24)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	c.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 420
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = RemakeText.t("Evil Islands")
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)
	_name = LineEdit.new()
	_name.placeholder_text = RemakeText.t("Your name")
	_name.text = GameData.player_name
	box.add_child(_name)
	var hero_row := HBoxContainer.new()
	box.add_child(hero_row)
	var hl := Label.new()
	hl.text = RemakeText.t("Co-op hero: ")
	hero_row.add_child(hl)
	_hero = OptionButton.new()
	for proto: String in Session.COOP_CLASSES:
		var t := GameUnit.unit_title(proto)
		_hero.add_item(("%s (%s)" % [proto.trim_prefix("Human Mercenary "), t]) if t else proto.trim_prefix("Human Mercenary "))
		_hero.set_item_metadata(_hero.item_count - 1, proto)
		if proto == GameData.hero_class:
			_hero.select(_hero.item_count - 1)
	_hero.tooltip_text = RemakeText.t("The hero you play when you join someone's campaign (the host plays Zak).")
	hero_row.add_child(_hero)
	_button(box, RemakeText.t("New campaign (single player)"), _single)
	if Session.latest_save():
		_button(box, RemakeText.t("Continue (last save)"), _continue)
	_button(box, RemakeText.t("Options"), func(): _options.open())
	_button(box, RemakeText.t("Credits"), _credits)
	box.add_child(HSeparator.new())
	_button(box, RemakeText.t("Host co-op campaign"), func(): _host(Session.MAX_PLAYERS))
	var row := HBoxContainer.new()
	box.add_child(row)
	_addr = LineEdit.new()
	_addr.text = _addr_default
	_addr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_addr)
	_button(row, RemakeText.t("Join"), func(): _join(_addr.text.strip_edges()))
	_lobby = ItemList.new()
	_lobby.custom_minimum_size.y = 90
	_lobby.visible = false
	box.add_child(_lobby)
	_start = _button(box, RemakeText.t("Start co-op campaign"), _start_coop)
	_start.visible = false
	box.add_child(HSeparator.new())
	_button(box, RemakeText.t("Map viewer"), func(): get_parent().open_viewer())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_status)
	add_child(_options)


## Options ✓ with another text / voice language: the menu (signpost labels,
## texts) is built again from the new archives, Options reopened on its page.
## Signpost boards (MenuScene).

func _add_viewer_link() -> void:
	var viewer := LinkButton.new()
	viewer.text = RemakeText.t("Map viewer (remake)")
	viewer.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	viewer.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6, 0.8))
	viewer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	viewer.position += Vector2(12, -30)
	viewer.pressed.connect(func(): get_parent().open_viewer())
	add_child(viewer)
	move_child(viewer, _net.get_index())

func _on_board(action: String) -> void:
	if _panel.visible or _options.visible or has_node("Credits") or _difficulty.visible or _load.visible:
		return
	match action:
		"new": _difficulty.open()   #  case 0: the difficulty box first
		"load": _load.open()        # case 1: the Load screen (no slide-in)
		"multiplayer": _net.open()
		"options": _options.open()
		"credits": _credits()
		"exit": get_tree().quit()


## The "Authors" board: the scrolling credits over their own music.
func _credits() -> void:
	var c := CreditsPanel.new()
	c.name = "Credits"
	_music.stream_paused = true
	c.closed.connect(func(): _music.stream_paused = false)
	add_child(c)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _make_session() -> Session:
	if _net:
		GameData.player_name = _net.player_name if _net.player_name.strip_edges() else "Player"
		GameData.hero_class = _net.hero_class()
	else:
		GameData.player_name = _name.text if _name.text else "Player"
		if _hero.selected >= 0:
			GameData.hero_class = String(_hero.get_item_metadata(_hero.selected))
	GameData.save_settings()
	if _session == null:
		_session = Session.new()
		get_parent().add_child(_session)
		_session.players_changed.connect(_refresh_lobby)
	return _session


func _single() -> void:
	var s := _make_session()
	s.players = {1: {"index": 0, "name": GameData.player_name}}
	# the original: Intro.bik first, then the game loads (Session.new_campaign).
	await MovieSequence.start(get_parent(), PackedStringArray(["intro"])).done
	start_game.emit(s)
	s.new_campaign(false)


func _continue() -> void:
	var s := _make_session()
	start_game.emit(s)
	if not s.load_game(Session.latest_save()):
		s.new_campaign()



func _load_slot(slot: String) -> void:
	var s := _make_session()
	start_game.emit(s)
	if not s.load_game(slot):
		s.new_campaign()


func _set_status(t: String) -> void:
	if _net:
		_net.status = t
		_net.queue_redraw()
	else:
		_status.text = t


func _host(max_players := Session.MAX_PLAYERS) -> void:
	if _session and _session.online:
		return
	var s := _make_session()
	var port := _port()
	var err := s.host(port, max_players)
	if err != OK:
		_set_status(RemakeText.t("Could not host on port %d (error %d).") % [port, err])
		return
	# The co-op screen's hint line says what to do next; the status only where.
	_set_status((RemakeText.t("Hosting on port %d.") if _net else RemakeText.t("Hosting on port %d. Waiting for players... (✓ starts)")) % port)
	if s.upnp.busy and _net:   # remake option net_upnp: the router result (and the address to share)
		_net.upnp_text = s.upnp.status
		s.upnp.finished.connect(func(_ok, t):
			if _session == s and _net:
				_net.upnp_text = t
				_net.queue_redraw())
	if _net:
		_net.hosting = true
		_net.host_port = port   # remake: the addresses to share (NetworkPanel)
		_net.upnp = s.upnp
	else:
		_lobby.visible = true
		_start.visible = true
	_refresh_lobby()


func _join(address := "") -> void:
	if _session and _session.online:
		return
	if address.is_empty():   # --join=<ip> on the command line
		address = _addr_default
	if OS.has_feature("web") and not (address.begins_with("ws://") or address.begins_with("wss://")):
		_set_status("Enter a wss:// server address (ws:// for local testing).")
		return
	var s := _make_session()
	# Remake: "address:port" joins a host on another port; IPv6 as
	# "[address]:port" or bare (Session.parse_address).
	var hp := Session.parse_address(address, _port())
	var typed := address
	address = hp[0]
	var err := s.join(address, hp[1])
	if err != OK:
		_set_status(RemakeText.t("Could not connect (error %d).") % err)
		return
	if _net:
		_set_status(RemakeText.t("Connecting to %s...") % typed)
		s.multiplayer.connected_to_server.connect(func(): _set_status(RemakeText.t("Connected to %s.") % typed), CONNECT_ONE_SHOT)
	else:
		_set_status(RemakeText.t("Connecting to %s... the host starts the campaign.") % address)
	if _net:
		_net.joining = true
	else:
		_lobby.visible = true
	# Clients enter the game view when the host sends the first zone.
	s.zone_received.connect(func(): start_game.emit(s), CONNECT_ONE_SHOT)
	s.net.refused.connect(_join_refused)


## The host turned the join down (NetStatus.refuse): the original's message box
## (with the reason, ✓ only), then back to the co-op screen.
func _join_refused(title: String, text: String) -> void:
	_set_status(title)
	var b := MessageBox.new()
	b.title = title
	b.message = text
	b.ok_only = true
	add_child(b)
	b.answered.connect(func(_yes):
		if _session and _session.online:
			_session.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
			_session.online = false
			_session.queue_free()
			_session = null
		if _net:
			_net.joining = false
			_net.queue_redraw(), CONNECT_ONE_SHOT)


## The co-op port: Session.PORT, or --port=N on the command line (remake).
static func _port() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port=") and a.trim_prefix("--port=").is_valid_int():
			return a.trim_prefix("--port=").to_int()
	return Session.PORT


func _start_coop() -> void:
	start_game.emit(_session)
	if _net and _net.lmp_base:   # the original's own multiplayer game (LmpMode)
		_session.new_lmp_game(_net.lmp_base)
		return
	_session.new_campaign()


## ✗ on the co-op screen: back to the signpost; an open host / connection is closed.
func _leave_net() -> void:
	if _session and _session.online:
		_session.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		_session.online = false
		_session.queue_free()
		_session = null
	_net.hosting = false
	_net.joining = false
	_net.upnp = null
	_net.upnp_text = ""   # the session's UpnpPort removed the forwarding as it left
	_net.lobby = []
	_net.status = ""
	_net.visible = false


func _refresh_lobby() -> void:
	if _session == null:
		return
	if _net:
		var names := []
		var me := _session.multiplayer.get_unique_id() if _session.online else 1
		for pid in _session.players:
			# Remake: who is who when names repeat (everyone starts as "Player").
			var tags := PackedStringArray()
			if int(pid) == 1:
				tags.append(RemakeText.t("host"))
			if int(pid) == me:
				tags.append(RemakeText.t("you"))
			names.append("%d. %s%s" % [_session.players[pid].index + 1, _session.players[pid].name,
				" (%s)" % ", ".join(tags) if not tags.is_empty() else ""])
		_net.lobby = names
		_net.queue_redraw()
		return
	if _lobby == null:
		return
	_lobby.clear()
	for pid in _session.players:
		_lobby.add_item("%d. %s" % [_session.players[pid].index + 1, _session.players[pid].name])
