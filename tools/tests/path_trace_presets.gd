extends Node
const Presets = preload("res://src/platform/path_trace_settings.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func _ready() -> void:
	# A previously saved custom configuration must become a coherent player
	# preset without destroying the values needed by diagnostics or RT Off.
	var saved := {"pt_mode":2, "pt_accumulation":1, "pt_target_fps":3,
		"pt_sharc":1, "pt_denoiser":1, "pt_ray_reconstruction":0,
		"pt_restir":0, "pt_refraction":0, "q_rt_lighting":2,
		"rt_shadows":1, "rt_gi":1, "rtx_upscaling":4, "rtx_frame_generation":1,
		"volume_sfx":0, "gfx_water_reflections":2}
	var original := saved.duplicate(true)
	for mode in [1, 2]:
		saved.pt_mode = mode
		check(Presets.value("pt_mode", saved, false) == mode, "old bounce IDs retain the same number of bounces")
		check(Presets.value("pt_accumulation", saved, false) == 0, "play presets always use responsive history")
		check(Presets.value("pt_target_fps", saved, false) == 0, "play presets do not change PT resolution dynamically")
		check(Presets.value("pt_denoiser", saved, false) == 0, "fallback uses radiance denoising")
		check(Presets.value("pt_ray_reconstruction", saved, false) == 1, "compatible DLSS gets automatic reconstruction")
		check(Presets.value("q_rt_lighting", saved, false) == 0, "fallback uses a bounded one-sample PT budget")
		check(Presets.value("pt_refraction", saved, false) == int(mode == 2), "only Quality requests extra refraction transport")
		check(Presets.value("pt_restir", saved, false) == int(mode == 2), "Balanced avoids the measured direct-light resampling cost")
		check(Presets.value("pt_sharc", saved, false) == 0, "play presets avoid the constantly invalidated cache")
		for name in ["rt_shadows", "rt_gi", "rtx_upscaling", "rtx_frame_generation", "volume_sfx", "gfx_water_reflections"]:
			check(Presets.value(name, saved, false) == saved[name], "preset preserves independent setting " + name)
		for name in saved:
			check(Presets.value(name, saved, true) == saved[name], "explicit tuning retains " + name)
	saved.pt_mode = 2
	check(saved == original, "resolving presets never mutates saved preferences")
	saved.pt_mode = 0
	for name in saved:
		check(Presets.value(name, saved, false) == saved[name], "PT Off restores saved " + name)
	var previous := GameData.options.duplicate(true)
	GameData.options.merge(original, true)
	check(GameData.option("pt_accumulation") == (1 if Presets.tuning_enabled() else 0), "runtime reads the same policy as menu previews")
	check(not RtxGraphics.rr_active() or RtxGraphics.reason(RtxGraphics.RAY_RECONSTRUCTION).is_empty(), "automatic RR still requires actual native support")
	GameData.options.pt_mode = 0
	check(GameData.option("q_rt_lighting") == 2, "turning PT off restores the retained standalone RT quality")
	GameData.options = previous
	for language in ["en", "ru", "de"]:
		RemakeText.lang = language
		for key: String in [Presets.LABEL, Presets.HELP, Presets.SCREEN_LABEL, Presets.SCREEN_HELP,
			GameData.REMAKE_OPTIONS.gfx_terrain_cliffs[0], GameData.REMAKE_OPTIONS.gfx_terrain_cliffs[1]] + Presets.CHOICES:
			check(not RemakeText.t(key).is_empty() and (language == "en" or RemakeText.t(key) != key), "preset and terrain text translated: " + language + " " + key.left(32))
	RemakeText.lang = "en"
	print("PT_PRESETS ", JSON.stringify({"checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
