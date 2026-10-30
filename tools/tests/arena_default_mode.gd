extends Node
## Trials of the Allods opens on the ordinary autochess by default. Profiles
## that stored the old untouched expedition default move once; later explicit
## choices (expedition or LiA autochess) are kept.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func mode_of(values: Dictionary) -> int:
	var cfg := ConfigFile.new()
	for key: String in values: cfg.set_value("arena", key, values[key])
	return GameData.saved_arena_mode(cfg)

func _ready() -> void:
	check(mode_of({}) == 1, "a fresh profile selects autochess")
	check(mode_of({"mode": 0}) == 1, "the old stored expedition default moves to autochess")
	check(mode_of({"mode": 2}) == 2, "an older LiA autochess choice is kept")
	check(mode_of({"mode": 1}) == 1, "an older autochess choice is kept")
	check(mode_of({"mode": 0, "mode_rev": GameData.ARENA_MODE_REV}) == 0, "an expedition chosen after the change is kept")
	check(mode_of({"mode": 2, "mode_rev": GameData.ARENA_MODE_REV}) == 2, "a LiA autochess choice after the change is kept")
	check(mode_of({"mode": 9}) == 2 and mode_of({"mode": -3}) == 1, "out-of-range values are clamped")
	# Saving records the revision so an explicit expedition survives a restart.
	var before := GameData.arena_mode
	GameData.arena_mode = 0
	GameData.save_settings()
	var cfg := ConfigFile.new()
	check(cfg.load(GameData.CONFIG_PATH) == OK, "isolated settings saved")
	check(GameData.saved_arena_mode(cfg) == 0, "a saved expedition choice reloads as expedition")
	GameData.arena_mode = before
	GameData.save_settings()
	print("ARENA_DEFAULT_MODE ", JSON.stringify({"checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
