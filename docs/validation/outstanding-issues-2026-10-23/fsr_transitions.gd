extends Node
## Real Windows FSR SDK before/after comparison; no simulated SDK status.
var session: Session
var game: Game
var main: Node
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var events: Array[Dictionary] = []
var stage := "startup"
var frames := 0
var covered := 0
var return_frames := 0
var returning := false
var expect_quiet := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)

func sdk() -> Dictionary:
	return FsrGraphics.bridge().call("get_status") if FsrGraphics.bridge() else {}

func settle(n: int) -> void:
	for i in n:
		if not get_tree().root.has_focus(): get_tree().root.grab_focus()
		await RenderingServer.frame_post_draw

func presented() -> void:
	frames += 1
	if ShaderCompilationScreen.active(): covered += 1
	if returning and return_frames < 60:
		get_viewport().get_texture().get_image().save_png("user://return-%03d.png" % return_frames)
		return_frames += 1

func progress(row: Dictionary) -> void:
	if events.size() < 500:
		var event := row.duplicate(true)
		event.stage = stage
		event.time_ms = Time.get_ticks_msec()
		events.append(event)

func write_result() -> void:
	FileAccess.open("user://fsr-transitions.json", FileAccess.WRITE).store_string(JSON.stringify({
		"checks": checks, "failures": failures, "rows": rows, "events": events,
		"status": sdk(), "facts": FsrGraphics.facts(), "return_frames": return_frames,
		"profile": {"confine_mouse":GameData.option("confine_mouse"),"show_fps":GameData.option("show_fps"),
			"volume_sfx":GameData.option("volume_sfx"),"volume_stream":GameData.option("volume_stream"),"volume_voice":GameData.option("volume_voice")}}, "\t"))

func sample(label: String, expect_fg: bool, quiet := true) -> void:
	stage = label
	frames = 0
	covered = 0
	var before := sdk()
	await settle(60)
	var after := sdk()
	check(bool(after.frame_generation_active) == expect_fg, label + ": real SDK generation gate")
	check(int(after.last_error) == 0, label + ": SDK has no error")
	if expect_fg:
		check(int(after.frame_generation_dispatches) > int(before.frame_generation_dispatches), label + ": actual generation dispatches advance")
	if expect_quiet and quiet: check(covered == 0, label + ": no shader-screen flash")
	rows.append({"label":label,"frames":frames,"covered":covered,"status_before":before,"status_after":after})
	get_viewport().get_texture().get_image().save_png("user://" + label + ".png")
	write_result()

func freeze_simulation() -> void:
	session.set_physics_process(false)
	session.world.set_process(false)
	session.world.set_physics_process(false)
	session.world.vm.instances.clear()
	game.rig.release()
	game.hud._dialog.hide()
	game.rig.set_process(false)
	game.direct.set_process(false)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	main = get_parent()
	reparent(get_tree().root)
	expect_quiet = OS.get_cmdline_user_args().has("--expect-quiet")
	await settle(5)
	var facts := FsrGraphics.facts()
	if not facts.api or not facts.sr3 or not facts.fg3:
		check(false,"real FSR SDK is available")
		write_result();get_tree().quit(2);return
	TutorialPanel.auto_show = false
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"control_mode":0,"pad_enabled":0,"confine_mouse":0,
		"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"vsync":0,
		"display_mode":0,"fsr_upscaling":1,"fsr_quality":1,"fsr_frame_generation":1}, true)
	GameData._window_state.clear()
	GameData._apply_window()
	await get_tree().create_timer(0.4).timeout
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280,720)
	get_tree().root.grab_focus()
	PadInput.active = "kbm"
	TouchInput.enabled = false
	RenderingServer.frame_post_draw.connect(presented)
	ShaderCompilationScreen.on_progress = progress
	session = Session.new()
	main.add_child(session)
	main.start_game(session)
	game = main.game
	session.state.ensure_hero(0,"Human Hero")
	await session.enter_zone("gz1g",1,false)
	freeze_simulation()
	var deadline := Time.get_ticks_msec() + 60000
	while (ShaderCompilationScreen.active() or not bool(sdk().frame_generation_active)) and Time.get_ticks_msec() < deadline:
		await settle(1)
	await settle(15)
	await sample("warm-gameplay",true)
	for i in 3:
		game.hud._open_menu()
		await sample("menu-open-%d" % i,false)
		game.hud._close_menu()
		await sample("menu-closed-%d" % i,true)
		game.hud._tutorial.show_screen("options",true)
		check(game.hud._tutorial.visible,"real tutorial panel opens")
		await sample("tutorial-open-%d" % i,false)
		game.hud._tutorial.hide()
		await sample("tutorial-closed-%d" % i,true)
	stage = "save"
	check(session.save_game("fsr-transition") == OK,"actual campaign save succeeds")
	await sample("save",true)
	stage = "reload"
	check(await session.load_game_shown("fsr-transition"),"actual campaign reload succeeds")
	freeze_simulation()
	await sample("reload-covered",true,false)
	await sample("reload-settled",true)
	stage = "return-menu"
	returning = true
	await main.back_to_menu()
	await settle(10)
	returning = false
	check(main.game == null and main.session == null,"real menu return clears campaign")
	check(get_tree().root.get_camera_3d() != null and get_tree().root.get_camera_3d().get_parent() is MenuScene,"real menu camera presented")
	write_result()
	print("FSR_TRANSITIONS ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
