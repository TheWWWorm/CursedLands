extends "startup_graphics_recovery.gd"
## Capability/fallback and localized settings checks. A passing run does NOT
## qualify SDK-rendered output; use the hardware rendering fixtures too.

func _run() -> void:
	TutorialPanel.auto_show = false
	check(GameData.option(FsrGraphics.UPSCALING) == 0, "fresh profile leaves FSR off")
	check(GameData.option(FsrGraphics.FRAME_GENERATION) == 0, "fresh profile leaves FG off")
	var supported := {"engine":true,"api":true,"sr3":true,"sr4":true,"fg3":true,"fg4":true}
	for version in [1, 2]:
		check(FsrGraphics.reason_for(FsrGraphics.UPSCALING, supported, version).is_empty(), "supported upscaler version " + str(version))
		check(FsrGraphics.reason_for(FsrGraphics.FRAME_GENERATION, supported, version, version).is_empty(), "supported FG version " + str(version))
	var ampere := supported.duplicate()
	ampere.sr4 = false
	ampere.fg4 = false
	check(FsrGraphics.reason_for(FsrGraphics.UPSCALING, ampere, 2) == FsrGraphics.NEED_SR, "FSR 4 cannot silently become 3.1")
	check(FsrGraphics.reason_for(FsrGraphics.FRAME_GENERATION, ampere, 1, 2) == FsrGraphics.NEED_FG, "FG 4 cannot silently become 3.1")
	check(FsrGraphics.reason_for(FsrGraphics.FRAME_GENERATION, supported, 0, 1).is_empty(), "FG works without upscaling")
	check(FsrGraphics.reason_for(FsrGraphics.QUALITY, supported, 0) == FsrGraphics.ENABLE_SR, "upscale quality still requires upscaling")
	var fg_only := supported.duplicate()
	fg_only.sr3 = false
	fg_only.sr4 = false
	check(FsrGraphics.reason_for(FsrGraphics.FRAME_GENERATION, fg_only, 0, 1).is_empty(), "FG support is independent of SR support")
	for key in ["engine", "api"]:
		var unavailable := supported.duplicate()
		unavailable[key] = false
		check(not FsrGraphics.reason_for(FsrGraphics.FRAME_GENERATION, unavailable, 1, 1).is_empty(), "FG rejects missing " + key)
	for text: String in FsrGraphics.SECTION + [FsrGraphics.SR_HELP, FsrGraphics.QUALITY_HELP, FsrGraphics.FG_HELP, FsrGraphics.UNAVAILABLE, FsrGraphics.NEED_SR, FsrGraphics.NEED_FG, FsrGraphics.ENABLE_SR] + FsrGraphics.VERSIONS + FsrGraphics.QUALITIES:
		for language in ["ru", "de"]:
			RemakeText.lang = language
			check(RemakeText.TEXTS.has(text) and not RemakeText.t(text).is_empty(), language + " translation coverage: " + text)
	var actual := FsrGraphics.facts()
	check(not actual.sr3 and not actual.sr4 and not actual.fg3 and not actual.fg4, "fallback fixture is unsupported")
	var native := FsrGraphics.bridge()
	if native:
		var status: Dictionary = native.call("get_status")
		check(not status.get("initialized", true), "unsupported renderer does not load AMD SDK")
		check(status.get("upscale_evaluations", 0) == 0, "no false SDK evaluations")
	GameData.options[FsrGraphics.UPSCALING] = 2
	GameData.options[FsrGraphics.FRAME_GENERATION] = 1
	var scale := get_window().scaling_3d_scale
	var mode := get_window().scaling_3d_mode
	FsrGraphics.apply_upscaling(get_window())
	check(get_window().scaling_3d_scale == scale and get_window().scaling_3d_mode == mode, "unsupported saved request preserves ordinary renderer")
	GameData.options[FsrGraphics.UPSCALING] = 0
	GameData.options[FsrGraphics.FRAME_GENERATION] = 0
	# The real Screen dropdowns, saved-request recovery, help and all three
	# localized layouts are exercised by fsr_screen on both D3D12 and OpenGL.
	check(FsrGraphics.aa_selection({"q_aa":4,"fsr_upscaling":1}) == 6, "old FSR 3.1 save maps to unified AA")
	check(FsrGraphics.aa_selection({"q_aa":4,"fsr_upscaling":2}) == 7, "old FSR 4 save maps to unified AA")
	check(FsrGraphics.aa_selection({"q_aa":4,"fsr_upscaling":0}) == 4, "ordinary AA save remains unchanged")

	RemakeText.lang = "en"
	FileAccess.open("user://fsr-check.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"facts":actual,"hardware_output_qualified":false}, "\t"))
	print("FSR_EXPERIMENT ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
