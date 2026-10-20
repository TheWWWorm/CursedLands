extends Node
## Exercise the normal FSR autoload, real campaign HUD and presentation gates.
## Requires the Windows FSR SDK build and an isolated, muted test profile.

var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var session: Session
var game: Game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL ", message)

func status() -> Dictionary:
	return FsrGraphics.bridge().call("get_status")

func settle(frames: int) -> void:
	for i in frames:
		if not get_tree().root.has_focus(): get_tree().root.grab_focus()
		await RenderingServer.frame_post_draw

func save_result(blocked := false) -> void:
	var result := {"checks": checks, "failures": failures, "blocked": blocked,
		"rows": rows, "facts": FsrGraphics.facts(), "status": status()}
	FileAccess.open("user://fsr-campaign.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("FSR_CAMPAIGN ", JSON.stringify(result))

func sample(label: String, expect_fg: bool, moving := false) -> void:
	await settle(30)
	var before := status()
	var original_camera := game.rig.camera.transform
	for frame in 90:
		if not get_tree().root.has_focus(): get_tree().root.grab_focus()
		if moving:
			game.rig.camera.position.x = original_camera.origin.x + sin(frame * 0.04) * 0.15
		await RenderingServer.frame_post_draw
	var after := status()
	var generated := int(after.generated_frames) - int(before.generated_frames)
	var presented := int(after.presented_frames) - int(before.presented_frames)
	check(get_tree().root.has_focus(), label + ": test window has actual focus")
	check(after.frame_generation_active == expect_fg, label + ": automatic FG gate")
	check(generated >= 80 if expect_fg else generated == 0, label + ": SDK generated-frame count")
	check(presented >= 160 and presented <= 190 if expect_fg else presented >= 80 and presented <= 100, label + ": real presentation count")
	check(int(after.last_error) == 0, label + ": SDK reports no error")
	if expect_fg:
		check(String(after.upscaler_provider).begins_with("3.1.") and String(after.frame_generation_provider).begins_with("3.1."), label + ": actual 3.1 providers")
	var image := get_tree().root.get_texture().get_image()
	check(not image.is_empty() and image.save_png("user://fsr-campaign-" + label + ".png") == OK, label + ": campaign image saved")
	rows.append({"label": label, "sampled_frames": 90, "generated_frames": generated,
		"presented_frames": presented, "focused": get_tree().root.has_focus(),
		"hud_blocks_camera": game.hud.blocks_camera(), "status": after})
	game.rig.camera.transform = original_camera
	save_result()

func _run() -> void:
	await settle(5)
	var facts := FsrGraphics.facts()
	if not facts.api or not facts.launch or not facts.sr3 or not facts.fg3:
		save_result(true)
		get_tree().quit(2)
		return
	TutorialPanel.auto_show = false
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	GameData.options.merge({"autosave": 0, "show_tutorial": 0, "net_upnp": 0,
		"net_lan": 0, "net_directory": 0, "auto_graphics": 0, "control_mode": 0,
		"pad_enabled": 0, "confine_mouse": 0, "show_fps": 1, "volume_sfx": 0,
		"volume_stream": 0, "volume_voice": 0, "vsync": 0, "display_mode": 0,
		"fsr_upscaling": 1, "fsr_quality": 1, "fsr_frame_generation": 1}, true)
	GameData._window_state.clear()
	GameData._apply_window()
	await get_tree().create_timer(0.4).timeout
	GameData._window_gen += 1
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280, 720)
	get_tree().root.grab_focus()
	PadInput.active = "kbm"
	TouchInput.enabled = false
	session = Session.new()
	add_child(session)
	game = Game.new()
	game.session = session
	session.game = game
	add_child(game)
	session.state.ensure_hero(0, "Human Hero")
	await session.enter_zone("gz1g", 1, false)
	session.set_physics_process(false)
	session.world.set_process(false)
	session.world.set_physics_process(false)
	session.world.vm.instances.clear()
	game.rig.release()
	game.hud._dialog.hide()
	await settle(12)
	game.rig.set_process(false)
	game.direct.set_process(false)
	check(get_tree().root.get_node("FsrExperiment").is_processing(), "production FSR autoload remains active")
	check(game.world != null and game.hud != null, "original campaign and HUD loaded")
	await sample("gameplay", true, true)
	get_tree().paused = true
	await sample("paused", false)
	get_tree().paused = false
	await sample("resumed", true, true)
	session.loading_game = true
	await sample("loading", false)
	session.loading_game = false
	game.hud._open_menu()
	await sample("menu", false)
	game.hud._close_menu()
	await sample("menu-closed", true, true)
	GameData.options.fsr_upscaling = 0
	GameData._apply_window()
	await sample("upscaling-off", false)
	game.queue_free()
	session.queue_free()
	await settle(10)
	TexUpscale.shutdown()
	UnitWounds.shutdown()
	save_result()
	get_tree().quit(0 if failures.is_empty() else 1)
