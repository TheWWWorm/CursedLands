extends "startup_graphics_recovery.gd"
## Capability/fallback and localized settings checks. A passing run does NOT
## qualify native DLSS/FG output; use the Windows/RTX hardware checklist too.

func _run() -> void:
	TutorialPanel.auto_show = false
	check(GameData.option(RtxGraphics.UPSCALING) == 0, "fresh profile leaves DLSS off")
	check(GameData.option(RtxGraphics.FRAME_GENERATION) == 0, "fresh profile leaves FG off")
	var supported := {"engine":true,"api":true,"launch":true,"sr":true,"fg":true,"reflex":true}
	check(RtxGraphics.reason_for(RtxGraphics.UPSCALING, supported, 0) == "", "SR can be selected independently")
	check(RtxGraphics.reason_for(RtxGraphics.FRAME_GENERATION, supported, 0) == RtxGraphics.ENABLE_SR, "FG requires an SR/DLAA selection")
	check(RtxGraphics.reason_for(RtxGraphics.FRAME_GENERATION, supported, 1) == "", "capable FG path offered")
	for key: String in supported:
		var unavailable := supported.duplicate()
		unavailable[key] = false
		check(not RtxGraphics.reason_for(RtxGraphics.FRAME_GENERATION, unavailable, 1).is_empty(), "FG rejects missing " + key)
	var actual := RtxGraphics.facts()
	check(not actual.sr and not actual.fg, "fallback fixture is unsupported")
	var native := RtxGraphics.bridge()
	if native and native.has_method("get_status"):
		var status: Dictionary = native.call("get_status")
		check(not status.get("initialized", true), "non-D3D12/missing SDK fixture does not initialize Streamline")
		check(status.get("dlss_evaluations", -1) == 0, "no false DLSS evaluations")
		check(not status.get("frame_generation_active", true), "no false active FG")
	GameData.options[RtxGraphics.UPSCALING] = 2
	GameData.options[RtxGraphics.FRAME_GENERATION] = 1
	var scale := get_window().scaling_3d_scale
	var mode := get_window().scaling_3d_mode
	RtxGraphics.apply_upscaling(get_window())
	check(get_window().scaling_3d_scale == scale and get_window().scaling_3d_mode == mode, "unsupported saved request preserves ordinary renderer")
	GameData.options[RtxGraphics.UPSCALING] = 0
	GameData.options[RtxGraphics.FRAME_GENERATION] = 0

	RemakeText.lang = "en"
	FileAccess.open("user://rtx-check.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"facts":actual,"hardware_output_qualified":false}, "\t"))
	print("RTX_EXPERIMENT ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
