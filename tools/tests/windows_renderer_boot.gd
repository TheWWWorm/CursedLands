extends Node
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
func _ready() -> void:
	var phase := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--boot-phase="): phase = a.trim_prefix("--boot-phase=")
	check(RendererChoice.windows(), "Windows policy")
	var cfg := RendererChoice._load(RendererChoice.OVERRIDE, "rendering")
	var trial := RendererChoice._load(RendererChoice.TRIAL, "trial")
	check(CrashReport.instance.info.render_thread == "safe", "actual Safe thread")
	if phase == "trial":
		check(RenderingServer.get_current_rendering_method() == "forward_plus", "persisted enhanced choice loaded before scripts")
		check(trial.get("state") == "running", "trial starts")
		check(cfg.get("renderer/rendering_method") == "gl_compatibility", "fallback on disk before menu")
		RendererChoice.confirm()
		check(FileAccess.file_exists(RendererChoice.TRIAL), "early clean exit remains unconfirmed")
	else:
		check(Portability.compatibility(), "OpenGL already active before test runs")
		check(RendererChoice.chosen() == 0 and cfg.get("renderer/rendering_method.windows") == "gl_compatibility", "persisted Windows Compatibility")
		check(GfxDetect.original_look_on(GameData.options) and GameData.option("auto_graphics") == 0, "basic graphics persist without automatic calibration")
		check(trial.is_empty(), "no unconfirmed Compatibility trial")
		if phase == "fallback":
			check(RendererChoice.notice == RendererChoice.WINDOWS_CRASHED, "interrupted menu trial recovered")
		if phase == "persist":
			GameData.set_option("renderer", 1)
			check(RendererChoice._load(RendererChoice.TRIAL, "trial").get("state") == "pending", "Forward+ queued for actual next process")
	print("WINDOWS_RENDERER_BOOT ", phase, " ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
