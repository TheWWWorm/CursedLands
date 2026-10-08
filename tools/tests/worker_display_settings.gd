extends SceneTree
## Run with --script, once normally and once with --local-host-config=fixture
## after --. This exercises the real deferred autoload startup, without Main
## trying to launch a campaign. Use a disposable settings directory.

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var data := root.get_node("GameData")
	var worker := Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--local-host-config="))
	data.options.merge({"fps_limit":0,"render_scale":7,"display_mode":0,"q_aa":0},true)
	# Model LocalHost.listening(), followed by the autoload's delayed update.
	Engine.max_fps = 60
	root.scaling_3d_scale = 0.63
	for i in 8:
		await process_frame
	check(Engine.max_fps == (60 if worker else 0), "deferred startup respects process frame limit")
	check(is_equal_approx(root.scaling_3d_scale,0.63 if worker else 2.0), "deferred window scale belongs to frontend")
	for i in data.FPS_LIMITS.size():
		data.set_option("fps_limit",i)
		var expected: int = data.FPS_LIMITS[i]
		if expected < 0:
			expected = roundi(DisplayServer.screen_get_refresh_rate()) if DisplayServer.get_name() != "headless" else 60
			if expected <= 0: expected = 60
		check(Engine.max_fps == (60 if worker else expected), "frame limit option %d" % i)
	for i in data.RENDER_SCALES.size():
		data.set_option("render_scale",i)
		check(is_equal_approx(root.scaling_3d_scale,0.63 if worker else data.RENDER_SCALES[i]), "render scale option %d" % i)
	check(Engine.physics_ticks_per_second == 60,"physics cadence retained")
	print("WORKER_DISPLAY_SETTINGS ",JSON.stringify({"worker":worker,"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
