extends Node
## Real first menu, persisted first trial, and a restart after external SIGKILL.
## Render with --gfx-detect --gfx-handheld. Optional --hold-loading verifies
## calibration still waits after the old 20-second startup timeout.
var checks := 0
var failures := 0
var loaded := false
var trial_seen := false
var first_trial := {}
var menu: Control

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func basic(values: Dictionary) -> bool:
	return Array(GfxDetect.keys()).all(func(k): return not String(k).begins_with("gfx_") or values.get(k, -1) == 0)

func open_menu() -> void:
	menu = await get_parent().open_menu()
	loaded = true

func observe() -> void:
	var record := GfxDetect.load_record()
	if not trial_seen and record.get("testing", false) and String(record.get("stage", "")).begins_with("tier "):
		trial_seen = true
		first_trial = record
		check(basic(record.get("before", {})), "rollback contains basic graphics before a tier applies")
		check(record.before.fps_limit == 1, "rollback retains the basic 30 FPS cap")
		print("BOOTSTRAP_FIRST_TRIAL ", JSON.stringify(record))

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	var args := OS.get_cmdline_user_args()
	GameData.options.confine_mouse = 0
	GameData.options.display_mode = 0
	TutorialPanel.auto_show = false
	if args.has("--expect-restored") or FileAccess.file_exists("user://bootstrap-expect-restored"):
		var recovered := GfxDetect.load_record()
		check(recovered.get("interrupted", 0) == 1, "restart detects an interrupted first trial")
		check(basic(GameData.options), "restart restores basic graphics before menu construction")
		check(GameData.option("fps_limit") == 1, "restart restores the basic frame cap")
		await open_menu()
		await get_tree().create_timer(3.0).timeout
		check(not get_tree().root.get_children().any(func(n): return n is GfxDetect), "restart does not automatically retry the failing trial")
		_finish()
		return
	var base := GfxDetect.base_values()
	GameData.options.merge(base, true)
	GfxDetect.save_record({})
	GameData.options.auto_graphics = 0
	var before := GameData.options.duplicate(true)
	GfxDetect.prepare_startup()
	check(GameData.options == before, "explicitly disabled detection keeps the player's graphics")
	GameData.options.auto_graphics = 1
	GameData.options.gfx_water = 1 - int(base.gfx_water)
	before = GameData.options.duplicate(true)
	GfxDetect.prepare_startup()
	check(GameData.options == before, "manual graphics choices are retained")
	GameData.options.merge(base, true)
	GfxDetect.save_record({"version":GfxDetect.VERSION, "fingerprint":GfxDetect.fingerprint(), "tier":0, "values":base})
	before = GameData.options.duplicate(true)
	GfxDetect.prepare_startup()
	check(GameData.options == before, "an existing successful detection keeps its settings")
	GfxDetect.save_record({})
	GameData.save_settings()
	var stored := FileAccess.get_file_as_bytes(GameData.CONFIG_PATH)
	var hold: StartupScreen
	if args.has("--hold-loading"):
		hold = StartupScreen.new()
		get_parent().add_child(hold)
	GameData.options_changed.connect(observe)
	open_menu()
	check(basic(GameData.options), "first menu starts with every enhanced effect disabled")
	check(GameData.option("q_aa") == 0 and GameData.option("q_shadows") == 0 and GameData.option("fps_limit") == 1, "first menu uses basic render quality")
	check(Engine.max_fps == 30, "first menu applies the frame cap to the engine")
	check(get_tree().root.msaa_3d == Viewport.MSAA_DISABLED and get_tree().root.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED and not get_tree().root.use_taa, "first menu applies basic antialiasing to the viewport")
	check(FileAccess.get_file_as_bytes(GameData.CONFIG_PATH) == stored, "temporary menu graphics do not overwrite preferences")
	while not loaded:
		await RenderingServer.frame_post_draw
	check(menu._scene != null, "basic first menu builds the real island")
	if hold:
		await get_tree().create_timer(21.0).timeout
		check(not trial_seen and not GfxDetect.load_record().get("testing", false), "calibration waits for slow loading beyond 20 seconds")
		hold.queue_free()
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		var record := GfxDetect.load_record()
		if trial_seen and not record.get("testing", false) and int(record.get("tier", -1)) >= 0:
			break
		await RenderingServer.frame_post_draw
	check(trial_seen, "enhanced settings are tried only inside a persisted trial")
	check(not GfxDetect.load_record().get("testing", false) and int(GfxDetect.load_record().get("tier", -1)) >= 0, "normal calibration completes and commits a result")
	_finish()

func _finish() -> void:
	var result := {"checks":checks, "failures":failures, "first_trial":first_trial,
		"record":GfxDetect.load_record(), "renderer":RenderingServer.get_current_rendering_method(), "platform":OS.get_name()}
	FileAccess.open("user://graphics-startup-bootstrap.json", FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("GRAPHICS_STARTUP_BOOTSTRAP ", JSON.stringify(result))
	TexUpscale.shutdown()
	get_tree().quit(1 if failures else 0)
