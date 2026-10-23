extends Node
## Real settings/detector entry points with an instrumented terrain callback.
## A deliberately held UI owner is the negative control for timing/cancellation;
## it is not presented as real shader work. Run with an isolated muted profile.

class CameraShell extends Game:
	func _ready() -> void:
		simulation_only = true
		add_to_group("fsr_campaign_view")
		rig = CameraRig.new()
		add_child(rig)
		rig.set_process(false)
		rig.camera.current = true
		set_process(false)
		set_process_unhandled_input(false)
	func _exit_tree() -> void: pass

class Detector extends GfxDetect:
	var sample_frames := 0
	var samples_under_cover := 0
	var message_text := ""
	var interrupt_at := 0
	var interruption_hook := Callable()
	func _ready() -> void:
		layer = 104
		process_mode = Node.PROCESS_MODE_ALWAYS
		_overlay = Overlay.new()
		_overlay.owner_detect = self
		_overlay.status = RemakeText.t("Testing graphics for this device…")
		add_child(_overlay)
	func _sync_stress() -> void:
		sample_frames += 1
		if ShaderCompilationScreen.active() or get_tree().paused: samples_under_cover += 1
		if interrupt_at > 0 and sample_frames >= interrupt_at:
			interrupt_at = 0
			interruption_hook.call()
	func _message(text: String) -> void:
		message_text = text

class TerrainProbe extends EITerrain:
	var observer: Node
	func apply_gfx() -> void:
		observer.call("_applied")
	func _process(_dt: float) -> void: pass
	func _exit_tree() -> void: pass

const Screen = preload("res://src/ui/shader_compilation_screen.gd")
const HOLD := &"settings:fixture-negative-control"
var out := "user://shader-compilation-settings"
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var notifications := 0
var covered_notifications := 0
var samples := {}
var sampling_done := false
var restoration_done := false
var capture_first := true
var started_ms := 0
var running := false
var saved_options := {}
var saved_record := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)


func report(status: String) -> void:
	var file := FileAccess.open(out.path_join("shader-compilation-settings.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"status":status,"checks":checks,"failures":failures,
			"events":rows,"notifications":notifications,"covered_notifications":covered_notifications,
			"driver":RenderingServer.get_current_rendering_driver_name(),
			"device":RenderingServer.get_video_adapter_name(),"profile":OS.get_user_data_dir(),
			"note":"Production GfxDetect apply/cancel/sample and watchdog entry points. Terrain work is instrumented; explicit held UI owner is a negative control, not shader compilation evidence."}, "\t")+"\n")


func _process(_dt: float) -> void:
	if running and Time.get_ticks_msec()-started_ms > 60_000:
		check(false, "settings fixture finishes within its deadline")
		running = false
		report("timeout")
		get_tree().quit(1)


func frames(count := 1) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw


func until(condition: Callable, limit_ms := 5000) -> bool:
	var start := Time.get_ticks_msec()
	while not condition.call() and Time.get_ticks_msec()-start < limit_ms:
		await frames()
	return bool(condition.call())


func _notified() -> void:
	notifications += 1
	var pixels := _cover_pixels(get_viewport().get_texture().get_image())
	if bool(pixels.covered): covered_notifications += 1
	pixels["case"] = "options-notification"
	pixels["notification"] = notifications
	rows.append(pixels)


## force_sync completes the canvas image even when frame_post_draw delivery
## to the main thread is deferred. Read the actual pixels, not that signal's
## counter. Text rectangles deliberately exclude the moving progress bar.
func _cover_pixels(image: Image) -> Dictionary:
	var readable := image != null and not image.is_empty()
	var result := {"readable":readable,"covered":false,"screen_active":Screen.active(),
		"background_max_error":1.0,"background_min_alpha":0.0,"text_samples":[]}
	if not readable: return result
	var error := 0.0
	var alpha := 1.0
	for point: Vector2 in [Vector2(0.02,0.02),Vector2(0.98,0.02),Vector2(0.02,0.98),Vector2(0.98,0.98)]:
		var color := image.get_pixel(int(point.x*image.get_width()),int(point.y*image.get_height()))
		error = maxf(error,maxf(absf(color.r-Screen.BACKGROUND.r),maxf(absf(color.g-Screen.BACKGROUND.g),absf(color.b-Screen.BACKGROUND.b))))
		alpha = minf(alpha,color.a)
	var text_samples: Array[int] = []
	if Screen.active():
		for rect: Rect2 in Screen._current._text_rects:
			var ink := 0
			for y in range(clampi(int(rect.position.y),0,image.get_height()),clampi(ceili(rect.end.y),0,image.get_height()),2):
				for x in range(clampi(int(rect.position.x),0,image.get_width()),clampi(ceili(rect.end.x),0,image.get_width()),2):
					var color := image.get_pixel(x,y)
					if maxf(color.r,maxf(color.g,color.b)) > 0.25: ink += 1
			text_samples.append(ink)
	result.background_max_error = error
	result.background_min_alpha = alpha
	result.text_samples = text_samples
	result.covered = Screen.active() and error < 0.04 and alpha > 0.99 \
		and text_samples.size() == 4 and text_samples.all(func(ink: int): return ink > 8)
	return result


func _applied() -> void:
	var screen := Screen._current
	var image := get_viewport().get_texture().get_image()
	var pixels := _cover_pixels(image)
	pixels.merge({"case":"apply","revision":GameData.graphics_revision,
		"title":screen._title if is_instance_valid(screen) else "",
		"hint":screen.hint if is_instance_valid(screen) else ""})
	if capture_first and bool(pixels.readable):
		capture_first = false
		pixels["file"] = "settings-before-apply.png"
		check(image.save_png(out.path_join(pixels.file)) == OK, "pre-application screenshot is saved")
	rows.append(pixels)
	check(bool(pixels.readable), "pre-application forced draw is readable")
	check(bool(pixels.covered), "actual opaque cover and text are rendered before synchronous terrain application")


func sample(detector: Detector) -> void:
	samples = await detector._frames(0.0,4)
	sampling_done = true


func restore(detector: Detector) -> void:
	await detector._cancel_test()
	restoration_done = true


func interrupt_sample() -> void:
	Screen.begin(get_tree(),HOLD,Screen.GRAPHICS)


func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out = arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	started_ms = Time.get_ticks_msec()
	running = true
	check(DisplayServer.get_name() != "headless", "settings preparation qualification requires a rendered display")
	if DisplayServer.get_name() == "headless":
		report("failed"); running = false; get_tree().quit(1); return
	GameData.options.merge(GfxPresets.values(GfxPresets.ORIGINAL),true)
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
		"auto_graphics":0,"autosave":0,"fsr_upscaling":0,"fsr_frame_generation":0,
		"display_mode":0,"render_scale":4,"q_aa":0,"vsync":0,"fps_limit":2},true)
	GameData._apply_audio()
	GameData._apply_window()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	saved_options = GameData.options.duplicate(true)
	saved_record = GfxDetect.load_record().duplicate(true)
	var session := Session.new()
	var game := CameraShell.new()
	game.session = session; session.game = game; add_child(game)
	var detector := Detector.new()
	add_child(detector)
	var terrain := TerrainProbe.new()
	terrain.observer = self; add_child(terrain)
	GameData.options_changed.connect(_notified)
	await frames(3)
	var revision := GameData.graphics_revision
	detector._apply_live()
	check(GameData.graphics_revision == revision+1, "direct detection apply publishes one explicit graphics revision")
	var screen := Screen._current
	check(Screen.active() and screen._title == Screen.SETTINGS_TITLE, "direct detection apply uses the shared settings title")
	check(screen.hint == "Esc: skip the test" and not screen.is_processing_input(), "shared cover advertises cancellation and yields input to the detector")
	for language: String in ["en","ru","de"]:
		var previous := RemakeText.lang; RemakeText.lang = language
		check(not RemakeText.t(screen.hint).is_empty() and (language == "en" or RemakeText.t(screen.hint) != screen.hint), language+": detection cancellation hint is localized")
		RemakeText.lang = previous
	# Intentionally keep preparation unfinished. The production sampler must
	# not enter its per-frame work or finish while this negative control holds.
	Screen.begin(get_tree(),HOLD,Screen.GRAPHICS)
	sample(detector)
	await frames(12)
	check(Screen.owns_pause(get_tree()) and get_tree().paused, "controlled preparation owns the visible single-player pause")
	check(not sampling_done and detector.sample_frames == 0, "the production sampler cannot collect or return frames under the held cover")
	Screen.end(HOLD)
	check(await until(func(): return sampling_done), "sampling completes after preparation actually retires")
	check(detector.sample_frames >= 4 and samples.wall.size() >= 4 and detector.samples_under_cover == 0,
		"all production sample frames are collected with the cover closed and gameplay unpaused")
	check(not Screen.active() and not get_tree().paused and not detector._preparation_override, "sampling releases detector presentation overrides")
	rows.append({"case":"sampling-negative-control","sample_frames":detector.sample_frames,
		"samples_under_cover":detector.samples_under_cover,"wall_frames":samples.wall.size()})
	# Admit preparation in the middle of a real timing batch. This models a
	# delayed SDK/resize hold without requiring that SDK on the current GPU.
	sampling_done = false
	detector.sample_frames = 0
	detector.interrupt_at = 2
	detector.interruption_hook = interrupt_sample
	sample(detector)
	check(await until(func(): return Screen.active()), "controlled late preparation interrupts an already running sample batch")
	await frames(12)
	check(not sampling_done and detector.sample_frames == 2 and get_tree().paused,
		"late preparation stops the sampler without collecting covered or paused frames")
	check(not Screen._current.is_processing_input() and Screen._current.hint == "Esc: skip the test",
		"late preparation delegates cancellation to the existing detector overlay")
	Screen.end(HOLD)
	check(await until(func(): return sampling_done), "sampling restarts after late preparation retires")
	check(detector.sample_frames >= 6 and samples.wall.size() >= 4 and detector.samples_under_cover == 0,
		"interrupted partial samples are discarded and replaced by a complete uncovered batch")
	rows.append({"case":"late-sampling-negative-control","sample_frames":detector.sample_frames,
		"samples_under_cover":detector.samples_under_cover,"wall_frames":samples.wall.size()})
	# The watchdog must use one central settings transaction while preserving
	# its detection record and unrelated metadata.
	var record := {"version":GfxDetect.VERSION,"fingerprint":GfxDetect.fingerprint(),
		"tier":GfxDetect.ORIGINAL,"fps":0,"values":GfxDetect.base_values(),"fixture_marker":"retained"}
	var emitted := notifications
	revision = GameData.graphics_revision
	GfxDetect.Watchdog.lower(record,GfxDetect.ORIGINAL+1)
	check(notifications == emitted+1 and covered_notifications == notifications, "watchdog applies one centrally covered options notification")
	check(GameData.graphics_revision == revision+1, "watchdog increments the central graphics revision exactly once")
	var stored := GfxDetect.load_record()
	check(int(stored.get("tier",-1)) == GfxDetect.ORIGINAL+1 and int(stored.get("lowered",0)) == 1 \
		and stored.get("fixture_marker","") == "retained" and GfxDetect.untouched(stored,GameData.options),
		"watchdog persists its lowered tier, matching values and unrelated record metadata")
	check(await until(func(): return not Screen.active()), "watchdog settings cover settles")
	# Esc reaches the real Overlay through the modal presentation; cancellation
	# restores values/record but keeps the cover until restore preparation ends.
	detector.manual = true
	detector._before = GameData.options.duplicate(true)
	detector._record_before = stored.duplicate(true)
	detector._testing = true
	Screen.begin(get_tree(),HOLD,Screen.GRAPHICS)
	detector._set_values({"gfx_wind":1-GameData.option("gfx_wind")})
	detector._apply_live()
	await frames(3)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE; escape.pressed = true
	get_viewport().push_input(escape,true)
	check(detector._cancelled and get_viewport().is_input_handled(), "actual viewport Esc input cancels detection beneath the shared cover")
	escape.pressed = false; get_viewport().push_input(escape,true)
	restore(detector)
	await frames(3)
	check(not restoration_done and Screen.active(), "cancelled detection waits for restoration preparation before dismissing")
	check(GameData.options == detector._before and GfxDetect.load_record() == stored, "cancellation restores the exact prior settings and detection record")
	Screen.end(HOLD)
	check(await until(func(): return restoration_done), "restoration completes after its held preparation is released")
	check(not detector._overlay.visible and not detector.message_text.is_empty() and not Screen.active() and not get_tree().paused,
		"cancel completion closes preparation, restores gameplay and presents the existing result path")
	# A separate remaining owner survives detector exit with its original
	# input/hint restored, rather than inheriting the detector's cancellation UI.
	screen = Screen.begin(get_tree(),HOLD,Screen.GRAPHICS)
	var prior_hint := screen.hint
	var prior_input := screen.is_processing_input()
	detector._overlay.visible = true
	detector._apply_live()
	detector.free()
	check(Screen.active() and screen._owners.has(HOLD) and screen.hint == prior_hint \
		and screen.is_processing_input() == prior_input, "detector exit restores a shared cover without ending another owner's preparation")
	Screen.end(HOLD)
	check(await until(func(): return not Screen.active()), "shared cover closes cleanly after detector exit")
	# Cancellation must preserve a pause that existed before preparation.
	detector = Detector.new(); add_child(detector)
	detector.manual = true
	detector._before = GameData.options.duplicate(true)
	detector._record_before = GfxDetect.load_record().duplicate(true)
	detector._testing = true
	get_tree().paused = true
	detector._apply_live()
	await frames(2)
	check(get_tree().paused and not Screen.owns_pause(get_tree()), "preparation never claims the existing player pause")
	escape.pressed = true; get_viewport().push_input(escape,true)
	check(detector._cancelled, "existing player pause still permits detector cancellation")
	escape.pressed = false; get_viewport().push_input(escape,true)
	await detector._cancel_test()
	check(get_tree().paused and not Screen.active() and not detector._preparation_override,
		"cancellation restores screen input while preserving the player's original pause")
	detector.free()
	get_tree().paused = false
	GameData.options_changed.disconnect(_notified)
	terrain.free(); game.free(); session.free()
	GameData.options = saved_options
	GameData._apply_audio(); GameData._apply_window(); GameData.save_settings()
	GfxDetect.save_record(saved_record)
	await frames(2)
	running = false
	report("passed" if failures.is_empty() else "failed")
	TexUpscale.shutdown(); UnitWounds.shutdown()
	print("SHADER_COMPILATION_SETTINGS ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
