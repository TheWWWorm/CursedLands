extends Node
## Entry point: ask for the original game folder if needed, then show the main menu.
## User args (after "--"):
##   --ei-path=DIR          original game folder
##   --viewer [--map=NAME]  map viewer (also --screenshot=FILE.png --info)
##   --tool=res://x.gd      run a test tool
##   --play                 start a single player campaign right away
##   --host / --join=ADDR   start or join a co-op game right away
##   --name=NAME            player name
##   --debug                debug run: the main menu shows the map viewer link
##   --loading-deferred     loading screen as on the web / mobile (LoadingScreen.hold)

var game: Game
var session: Session
var _leaving := false   # back_to_menu waiting for a joiner's last package


func _ready() -> void:
	# The exported Windows build requires its native helper. A blocked DLL
	# must be explained before a campaign can quietly start without it.
	var native_startup := preload("res://src/platform/windows_native_startup.gd")
	if native_startup.required():
		if DisplayServer.get_name() == "headless":
			printerr(native_startup.instructions())
			get_tree().quit(1)
		else:
			add_child(native_startup.new())
		return
	if OS.get_cmdline_user_args().has("--no-movies"):
		MoviePlayer.enabled = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--name="):
			GameData.player_name = a.trim_prefix("--name=")
	if GameData.root and GameData.open(GameData.root) == "":
		_start()
	elif DisplayServer.get_name() == "headless":
		printerr("No valid Evil Islands folder. Pass -- --ei-path=/path/to/EvilIslands")
		get_tree().quit(1)
	else:
		var setup: Control = preload("res://src/ui/portable_setup.gd").new() if Portability.constrained() else preload("res://src/ui/setup_screen.gd").new()
		setup.opened.connect(_start)
		add_child(setup)


func _clear() -> void:
	for c in get_children():
		c.queue_free()


func _start() -> void:
	_clear()
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--local-host-config="):
			MoviePlayer.enabled = false
			TutorialPanel.auto_show = false
			var s := Session.new()
			add_child(s)
			var config := s.local_host.configure(a.trim_prefix("--local-host-config="))
			if config.is_empty():
				get_tree().quit(1)
				return
			var error := s.host(int(config.port), int(config.limit))
			s.local_host.listening(error)
			if error != OK:
				get_tree().quit(1)
				return
			start_game(s)
			return
	for a in args:
		if a.begins_with("--tool="):
			# Tools drive the game themselves: no movies, no tutorial pop-ups.
			MoviePlayer.enabled = false
			TutorialPanel.auto_show = false
			add_child(load(a.trim_prefix("--tool=")).new())
			return
		if a == "--viewer" or a.begins_with("--map="):
			open_viewer()
			return
	# the original plays config/movie.ini [Start] (fishtank, Nival)
	# before the main menu; skipped when the command line starts a game.
	var direct: bool = args.has("--play") or args.has("--host") or Array(args).any(func(a): return String(a).begins_with("--join="))
	if not direct and not args.has("--no-movies"):
		MoviePlayer.preconvert(Array(MoviePlayer.ini_movies("Start")))
		var seq := MovieSequence.start(self, MoviePlayer.ini_movies("Start"))
		await seq.done
	var menu: Control = await open_menu()
	if not direct:
		var crash_box := CrashReportBox.offer(menu)   # the previous session ended unexpectedly
		RendererChoice.offer(menu, crash_box)   # a Vulkan renderer that did not start / crashed
	for a in args:
		if a == "--play":
			menu.call_deferred("_single")
		elif a == "--host":
			menu.call_deferred("_host")
		elif a.begins_with("--join="):
			menu._addr_default = a.trim_prefix("--join=")
			menu.call_deferred("_join")


## The first main menu: the original shows frame 0
## Movies\Progres.bik after the startup movies while the databases and the
## menu load (StartupScreen); tools/startup_shot.gd calls this too.
func open_menu() -> Control:
	var splash := StartupScreen.open(self)
	if splash:
		await splash.presented()
	var menu := preload("res://src/ui/main_menu.gd").new()
	menu.start_game.connect(start_game)
	add_child(menu)
	if splash:
		splash.finish()
	return menu


## Remake: Options › Remake › "Game files…" (main menu): the first-run
## screen again, over the menu (DataSwitch). Once other files are in use the
## game starts again into the main menu (DataSwitch.restart); "Delete
## imported data" (Android / web) starts it again into the setup screen.
## Back calls `back` with the old files untouched.
func change_game_files(back: Callable, campaign := "") -> Control:
	var setup: Control = preload("res://src/ui/portable_setup.gd").new() if Portability.constrained() else preload("res://src/ui/setup_screen.gd").new()
	setup.name = "GameFilesSetup"
	setup.selected_campaign = campaign
	setup.back_text = RemakeText.t("Back to options")
	setup.opened.connect(func(): DataSwitch.restart(get_tree()))
	if setup.has_signal("deleted"):
		setup.deleted.connect(func(): DataSwitch.restart(get_tree()))
	setup.cancelled.connect(func():
		setup.queue_free()
		back.call())
	add_child(setup)
	return setup


## Esc signpost "Exit to main menu": drop the game and the connection.
func back_to_menu() -> void:
	if _leaving:
		return
	GameData.trace("back to main menu")
	if session:
		_leaving = true
		var s := session
		s.coop.flush()   # co-op: the joiners' last progress packages
		# The others see "left the game", not "lost connection"; a joiner
		# first gets its last progress package (NetStatus.leave).
		await s.net.leave()
		if s.local_host.frontend:
			await s.local_host.stop()
		s.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		_leaving = false
	game = null
	session = null
	_clear()
	var menu := preload("res://src/ui/main_menu.gd").new()
	menu.start_game.connect(start_game)
	add_child(menu)


func open_viewer() -> void:
	_clear()
	add_child(preload("res://src/ui/map_viewer.gd").new())


## Called by the menu once a Session exists (single player, host or client).
func start_game(s: Session) -> void:
	for c in get_children():
		if c != s:
			c.queue_free()
	session = s
	game = Game.new()
	game.session = s
	s.game = game
	add_child(game)
	if not s.net.kicked.is_connected(_on_kicked):
		s.net.kicked.connect(_on_kicked)


## Remake: the co-op host removed this player (NetStatus.kick): back to the
## main menu, where a message box (✓ only) says so.
func _on_kicked(banned: bool) -> void:
	await back_to_menu()
	var b := MessageBox.new()
	b.title = RemakeText.t("Removed from the game")
	b.message = RemakeText.t("You were removed from the game by the host.")
	if banned:
		b.message += "\n" + RemakeText.t("You cannot join this game again.")
	b.ok_only = true
	b.name = "KickedBox"
	add_child(b)


func _exit_tree() -> void:
	MoviePlayer.shutdown()
	TexUpscale.shutdown()
	UnitWounds.shutdown()
	EIAudio.shutdown()
