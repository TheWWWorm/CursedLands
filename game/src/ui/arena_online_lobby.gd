class_name ArenaOnlineLobby
extends Control
signal exit_requested
var connection: ArenaOnlineSession
var screen: ArenaOnlineScreen
var panel: ArenaOnlinePanel
var _prior_speed := 1.0
var _connection_generation := 0
var _stopping := false

func _ready() -> void:
	var cursor:=GameCursor.new();cursor.control_shapes=[Input.CURSOR_ARROW,Input.CURSOR_POINTING_HAND]
	add_child(cursor);cursor.set_kind("cursor_default")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_prior_speed=Engine.time_scale;Engine.time_scale=1.0
	panel=ArenaOnlinePanel.new();add_child(panel)
	panel.back_requested.connect(func():exit_requested.emit())
	panel.stop_requested.connect(_stop)
	panel.host_requested.connect(func(_limit):_host())
	panel.join_requested.connect(_join)
	panel.start_requested.connect(func():panel.status=ArenaOnlineSession.localize_error(connection.start_game());panel.queue_redraw())
	panel.ready_requested.connect(func():connection.request("ready"))
	panel.open()

func _connection() -> void:
	_connection_generation += 1
	GameData.player_name = ArenaOnlineSession.clean_name(panel.player_name)
	GameData.save_settings()
	if connection:
		connection.close();remove_child(connection);connection.queue_free()
	connection=ArenaOnlineSession.new();connection.player_name=panel.player_name
	connection.expansion = GameData.arena_mode == 2
	connection.password=panel.password if panel.page==NetworkPanel.HOST_COOP else panel.join_password
	add_child(connection);panel.connection=connection;panel.upnp=connection.upnp
	connection.lobby_changed.connect(_refresh)
	connection.closed.connect(func(text):panel.status=text;panel.hosting=false;panel.joining=false;panel.queue_redraw())
	connection.notice.connect(func(text):panel.status=text;panel.queue_redraw())
	connection.match_started.connect(_play)
	connection.upnp.finished.connect(func(_ok,text):panel.upnp_text=text;_refresh())

func _host() -> void:
	if _stopping: return
	_connection()
	var pending := connection
	var generation := _connection_generation
	panel.hosting = true; panel.host_port = int(panel.port_text)
	panel.status = RemakeText.t("Connecting…"); panel.queue_redraw()
	var error := await pending.host_shown(int(panel.port_text), GameData.option("net_websocket") != 0)
	if not is_inside_tree() or generation != _connection_generation or connection != pending or not panel.hosting: return
	if error != OK:
		panel.hosting = false
		panel.status = RemakeText.t("Could not host the game. Check the port and try again.")
	else:
		panel.host_port = connection.host_port; panel.status = ""; _refresh()
	panel.queue_redraw()

func _join(address: String) -> void:
	if _stopping: return
	_connection()
	var error:=connection.join(address)
	if error!=OK:panel.status=RemakeText.t("Could not connect to the host.")
	else:panel.joining=true;panel.status=RemakeText.t("Connecting…")
	panel.queue_redraw()

func _stop() -> void:
	if _stopping: return
	_stopping = true
	_connection_generation += 1
	var pending := connection
	if pending: await pending.close_shown()
	_stopping = false
	if not is_inside_tree() or connection != pending: return
	panel.hosting=false;panel.joining=false;panel.lobby.clear()
	panel.upnp_text="";panel.status="";panel.connection=null;panel.queue_redraw()

func _refresh() -> void:
	panel.lobby=connection.members.values().map(func(member):return String(member.name))
	if connection.my_seat>=0:panel.status=""
	panel.queue_redraw()

func _play() -> void:
	panel.hide()
	screen=ArenaOnlineScreen.new();screen.connection=connection
	screen.exit_requested.connect(func():exit_requested.emit())
	add_child(screen)

func _exit_tree() -> void:
	if connection:connection.close()
	Engine.time_scale=_prior_speed
