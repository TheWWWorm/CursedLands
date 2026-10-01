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

var game: Game
var session: Session


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--name="):
			GameData.player_name = a.trim_prefix("--name=")
	if GameData.root and GameData.open(GameData.root) == "":
		_start()
	elif DisplayServer.get_name() == "headless":
		printerr("No valid Evil Islands folder. Pass -- --ei-path=/path/to/EvilIslands")
		get_tree().quit(1)
	else:
		var setup := preload("res://src/ui/setup_screen.gd").new()
		setup.opened.connect(_start)
		add_child(setup)


func _clear() -> void:
	for c in get_children():
		c.queue_free()


func _start() -> void:
	_clear()
	var args := OS.get_cmdline_user_args()
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
	var menu := preload("res://src/ui/main_menu.gd").new()
	menu.start_game.connect(start_game)
	add_child(menu)
	for a in args:
		if a == "--play":
			menu.call_deferred("_single")
		elif a == "--host":
			menu.call_deferred("_host")
		elif a.begins_with("--join="):
			menu._addr_default = a.trim_prefix("--join=")
			menu.call_deferred("_join")


## Esc signpost "Exit to main menu": drop the game and the connection.
func back_to_menu() -> void:
	if session:
		session.coop.flush()   # co-op: the joiners' last progress packages
		session.net.bye()      # the others see "left the game", not "lost connection"
		session.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
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


func _exit_tree() -> void:
	MoviePlayer.shutdown()
	TexUpscale.shutdown()
