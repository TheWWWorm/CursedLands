extends "startup_graphics_recovery.gd"
## State transitions plus genuine independent Vulkan/OpenGL GPU probes.
class HungProbe extends RendererDetector:
	var children: Array[int] = []
	func _launch(_driver: String, _output: String, _token: String) -> int:
		var pid := OS.create_process("/bin/sleep", PackedStringArray(["5"]))
		children.append(pid)
		return pid
	func _timeout() -> float: return 0.15

func _run() -> void:
	GameData.options.confine_mouse = 0
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	await settle()
	check(RendererChoice.windows(), "Windows policy active")
	check(RendererChoice.chosen() == WindowsRenderer.AUTO, "old profiles default to Automatic")
	check(WindowsRenderer.pick({}) == "d3d12", "modern Direct3D first")
	check(WindowsRenderer.pick({"failed":["d3d12"]}) == "vulkan", "second modern API before OpenGL")
	check(WindowsRenderer.pick({"failed":["d3d12", "vulkan"]}) == "opengl3", "OpenGL only after modern APIs")
	check(WindowsRenderer.pick({"good":"vulkan"}) == "vulkan", "successful modern API reused")
	check(WindowsRenderer.pick({"good":"d3d12", "failed":["d3d12"]}) == "vulkan", "failed cached API rejected")
	check(WindowsRenderer.next_driver("vulkan", {"failed":["d3d12"]}) == "opengl3", "journal cannot retry rejected API")
	var good := {"token":"fresh", "driver":"vulkan", "frames":48, "rendered":true}
	check(RendererDetector.valid_result(good, "vulkan", "fresh"), "complete render receipt accepted")
	check(not RendererDetector.valid_result(good, "d3d12", "fresh"), "native fallback cannot masquerade as tested API")
	check(not RendererDetector.valid_result(good, "vulkan", "stale"), "stale probe receipt rejected")
	check(not RendererDetector.valid_result({"token":"fresh", "driver":"vulkan", "frames":1, "rendered":true}, "vulkan", "fresh"), "partial test cannot confirm API")
	var args := RendererDetector.probe_args("vulkan", "C:/Test Path/out.json", "token")
	check(args.has("--renderer-probe") and args.has("--render-thread") and args.has("safe"), "child isolated and Safe")
	check(args.has("--log-file") and not args.has("--ei-path"), "child has own log, no original game data")
	WindowsRenderer.data = {"fingerprint":WindowsRenderer.fingerprint(), "failed":[]}
	var hung := HungProbe.new(); add_child(hung)
	check(await hung.run(), "timeouts finish without manual restarts")
	check(hung.children.size() == 3 and WindowsRenderer.desired == "opengl3", "all candidates bounded after timeouts")
	await settle()
	check(hung.children.all(func(pid): return not DirAccess.dir_exists_absolute("/proc/%d" % pid)), "timed-out children terminated")
	check(not WindowsRenderer.data.has("probe_running"), "timeout journal completed")
	hung.queue_free(); await settle()
	var profile := GameData.options.duplicate(true)
	var settings := FileAccess.get_file_as_bytes(GameData.CONFIG_PATH)
	var markers := DirAccess.get_files_at(CrashReport.DIR)
	WindowsRenderer.data = {"fingerprint":WindowsRenderer.fingerprint(), "failed":[]}
	WindowsRenderer.mode = WindowsRenderer.AUTO
	WindowsRenderer.desired = "d3d12"
	WindowsRenderer.forced = false
	WindowsRenderer._save()
	# The Linux host has no D3D12; its failure must advance to a real Vulkan
	# render, not force OpenGL or require a user to reopen the application.
	var detector := RendererDetector.new()
	add_child(detector)
	check(await detector.run(), "automatic child tests finish")
	check(WindowsRenderer.desired == "vulkan", "failed D3D12 advances automatically to Vulkan")
	check(WindowsRenderer.data.get("probed") == "vulkan" and "d3d12" in WindowsRenderer.data.get("failed", []), "modern result and rejected API persisted")
	check(GameData.options == profile and FileAccess.get_file_as_bytes(GameData.CONFIG_PATH) == settings, "probes preserve gameplay and graphics preferences")
	check(DirAccess.get_files_at(CrashReport.DIR) == markers, "probes leave session markers untouched")
	detector.queue_free(); await settle()
	check(WindowsRenderer.before_scene(get_tree()), "same API does not restart parent")
	check(RendererChoice._load(RendererChoice.OVERRIDE, "rendering").get("renderer/rendering_method") == "gl_compatibility", "fallback durable before actual game draw")
	RendererChoice.confirm()
	check(FileAccess.file_exists(RendererChoice.TRIAL), "probe alone cannot confirm full menu")
	GameData.options.auto_graphics = 0
	var menu: Control = await get_parent().open_menu()
	RendererChoice.confirm()
	check(not FileAccess.file_exists(RendererChoice.TRIAL), "real menu confirms trial")
	check(WindowsRenderer.data.good == "vulkan" and RendererChoice.chosen() == WindowsRenderer.AUTO, "automatic mode retained with modern result")
	check(RendererChoice._load(RendererChoice.OVERRIDE, "rendering").get("rendering_device/driver.windows") == "vulkan", "confirmed API persisted")
	menu.queue_free(); await settle()
	WindowsRenderer.observe_previous({"session":"gameplay", "zone":"Gipath", "last":"combat", "renderer":"forward_plus / vulkan"})
	check(WindowsRenderer.desired == "vulkan", "unrelated gameplay crash does not blacklist renderer")
	WindowsRenderer.observe_previous({"session":"old-menu", "zone":"(menu)", "last":"startup: main menu built; presenting loading animation", "renderer":"forward_plus / vulkan"})
	check(WindowsRenderer.desired == "opengl3", "legacy menu hang selects remaining API")
	WindowsRenderer.choose(0)
	check(RendererChoice.chosen() == 0, "explicit Compatibility remains available")
	WindowsRenderer.choose(WindowsRenderer.AUTO)
	check(WindowsRenderer.desired == "d3d12" and WindowsRenderer.data.failed.is_empty(), "explicit re-detection retries modern APIs")
	# Simulate an interrupted child; next launch skips it before any scene.
	WindowsRenderer.data.probe_running = "d3d12"; WindowsRenderer._save()
	WindowsRenderer.startup()
	check("d3d12" in WindowsRenderer.data.failed and not WindowsRenderer.data.has("probe_running"), "interrupted probe advances on the next launch")
	var restart := RendererChoice.restart_args()
	check(not restart.has("--rendering-driver") and not restart.has("--rendering-method"), "automatic restart drops obsolete API overrides")
	check(not Array(restart).any(func(a): return a.begins_with("--tool=")), "automatic restart cannot replay test tools")
	print("WINDOWS_RENDERER_DETECTION ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
