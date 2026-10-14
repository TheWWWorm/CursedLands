extends Node
## Persistence boundaries for an interrupted graphics test. Rendered process
## kill/restart qualification supplements these checks; no GPU crash is faked.
const PATH := "user://graphics-recovery-test.cfg"
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "root", "unchanged-game")
	cfg.set_value("player", "name", "unchanged-player")
	cfg.set_value("options", "renderer", 2)
	cfg.set_value("options", "volume_music", 23)
	cfg.set_value("options", "gfx_water", 1)
	cfg.set_value("options", "gfx_rain_puddles", 1)
	cfg.set_value("options", "graphics_preset", GfxPresets.DETECTED)
	cfg.set_value("options", "fps_limit", 2)
	cfg.set_value("debug", "keep", "yes")
	check(cfg.save(PATH) == OK, "write isolated settings")
	var before := {"gfx_water": 0, "gfx_rain_puddles": 0, "graphics_preset": GfxPresets.CUSTOM,
		"fps_limit": 1, "renderer": 0, "volume_music": 99}
	check(GfxDetect.save_record({"testing": true, "pid": 0, "stage": "result tier 3", "before": before}, PATH) == OK,
		"rollback snapshot reaches disk")
	check(cfg.load(PATH) == OK, "reload as a fresh process")
	check(GfxDetect.recover_test(cfg, PATH), "unfinished final application recovers")
	var loaded := ConfigFile.new()
	check(loaded.load(PATH) == OK, "recovered settings reach disk")
	for k: String in ["gfx_water", "gfx_rain_puddles", "graphics_preset", "fps_limit"]:
		check(int(loaded.get_value("options", k)) == int(before[k]), "restored " + k)
	check(loaded.get_value("game", "root") == "unchanged-game", "game path retained")
	check(loaded.get_value("player", "name") == "unchanged-player", "player retained")
	check(int(loaded.get_value("options", "renderer")) == 2, "renderer choice excluded from rollback")
	check(int(loaded.get_value("options", "volume_music")) == 23, "unrelated settings excluded from rollback")
	check(loaded.get_value("debug", "keep") == "yes", "unrelated sections retained")
	var rec := GfxDetect.load_record(PATH)
	check(rec.get("interrupted_stage") == "result tier 3", "failed stage retained for diagnosis")
	check(not rec.get("testing", false), "recovery is no longer pending")
	var base := GfxDetect.base_values()
	check(GfxDetect.auto_reason(rec, base, base, GfxDetect.fingerprint(), true) == "", "restart skips interrupted automatic test")
	check(GfxDetect.auto_reason(rec, base, base, "new GPU", true) == "", "interrupted test requires deliberate retry")
	check(not GfxDetect.recover_test(loaded, PATH), "second restart does not recover again")
	check(GfxDetect.auto_reason({"testing": true}, base, base, "device", true) == "", "active test is not started twice")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--live-owner-pid="):
			GfxDetect.save_record({"testing": true, "pid": arg.trim_prefix("--live-owner-pid=").to_int(),
				"before": {"gfx_water": 1}}, PATH)
			loaded.load(PATH)
			check(not GfxDetect.recover_test(loaded, PATH), "another live process retains its trial")
			check(GfxDetect.load_record(PATH).get("testing", false), "live owner's marker remains intact")
			check(int(loaded.get_value("options", "gfx_water")) == 0, "live owner's settings are not overwritten")
	check(GfxDetect.auto_reason({}, base, base, "device", true) == "first", "fresh installation still detects")
	check(GfxDetect.save_record({"version": GfxDetect.VERSION, "fingerprint": "device", "tier": 3, "values": base}, PATH) == OK,
		"successful explicit retry replaces interruption record")
	rec = GfxDetect.load_record(PATH)
	check(not rec.has("interrupted") and not rec.has("testing"), "success clears failure state")
	check(GfxDetect.untouched(rec, base), "successful result still participates in watchdog")
	check(GfxDetect.auto_reason(rec, base, base, "device", true) == "", "same device keeps successful result")
	check(GfxDetect.auto_reason(rec, base, base, "new GPU", true) == "device", "successful result allows later hardware detection")
	check(RemakeText.TEXTS.has(GfxDetect.RECOVERY_NOTICE), "recovery notice has RU/DE translations")
	cfg.load(PATH)
	cfg.set_value("options", "auto_graphics", 1)
	cfg.set_value("options", "gfx_water", 1)
	cfg.save(PATH)
	var original := GfxDetect.original_recovery_values({"render_scale":4})
	GfxDetect.save_record({"testing":true, "pid":0, "original_recovery":true,
		"before":original, "stage":"startup probe terrain"}, PATH)
	cfg.load(PATH)
	check(GfxDetect.recover_test(cfg, PATH), "opt-in probe interruption recovers")
	for k: String in GfxDetect.keys():
		if k.begins_with("gfx_"): check(cfg.get_value("options", k, -1) == 0, "Original fallback disables " + k)
	check(cfg.get_value("options", "auto_graphics") == 0, "Original recovery disables automatic checks")
	check(cfg.get_value("options", "render_scale") == 2, "Original recovery uses modest resolution")
	check(cfg.get_value("options", "renderer") == 2 and cfg.get_value("options", "volume_music") == 23, "Original recovery retains unrelated settings")
	check(GfxDetect.recovered_original_test and RemakeText.TEXTS.has(GfxDetect.ORIGINAL_RECOVERY_NOTICE), "Original recovery has its own translated notice")
	DirAccess.remove_absolute(PATH)
	GfxDetect.recovered_test = false
	GfxDetect.recovered_original_test = false
	var report := {"checks": checks, "failures": failures}
	FileAccess.open("user://graphics-detection-recovery.json", FileAccess.WRITE).store_string(JSON.stringify(report))
	print("GRAPHICS_DETECTION_RECOVERY ", JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
