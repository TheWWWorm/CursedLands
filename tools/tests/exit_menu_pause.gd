extends Node
## Real HUD exit and Main teardown, with a delayed connection shutdown.
## The original regression resumed simulation between confirmation and removal.
var checks := 0
var failures: Array[String] = []

class ProbeMain extends "res://src/main.gd":
	func _ready() -> void: pass

class DelayedLeave extends NetStatus:
	var paused_frames: Array[bool] = []
	func leave(_secs := 3.0) -> void:
		for i in 8:
			paused_frames.append(get_tree().paused)
			await get_tree().process_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0},true)
	TutorialPanel.auto_show = false
	var original_scene := get_tree().current_scene
	for already_paused in [false,true]:
		var main := ProbeMain.new(); get_tree().root.add_child(main)
		get_tree().current_scene = main
		var s := Session.new(); main.session = s; main.add_child(s)
		var old_net := s.net; s.remove_child(old_net); old_net.free()
		var net := DelayedLeave.new(); net.session = s; s.net = net; s.add_child(net)
		var game := Game.new(); game.session = s; s.game = game; main.game = game; main.add_child(game)
		s.state.ensure_hero(0,"Human Hero")
		await s.enter_zone("gz1g",1,false)
		for i in 5: await get_tree().process_frame
		get_tree().paused = already_paused
		game.hud._open_menu()
		check(get_tree().paused,"opening menu pauses campaign")
		game.hud._on_esc_board("exit")
		check(get_tree().paused,"exit confirmation keeps campaign paused")
		# Retain the observation array after the network child is freed.
		var observed := net.paused_frames
		for i in 14: await get_tree().process_frame
		check(observed.size() == 8 and observed.all(func(v):return v),"campaign stays paused during every connection-shutdown frame")
		check(not is_instance_valid(game) and main.game == null and main.session == null,"real teardown removes campaign and session")
		check(not get_tree().paused and Engine.time_scale == 1.0,"main menu resumes its own clock after teardown")
		check(not main._leaving,"main menu teardown completes")
		get_tree().current_scene = original_scene
		main.queue_free()
		for i in 3: await get_tree().process_frame
	FileAccess.open("user://exit-menu-pause.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("EXIT_MENU_PAUSE ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if failures else 0)
