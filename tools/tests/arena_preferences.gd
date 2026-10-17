extends Node
## Run in an isolated user directory after the rendered feedback fixture.
## Two fresh processes (2:1, then 1:2) prove both choices survive restart.
func _ready() -> void:
	var expected := 2
	var next := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-preferences="):
			var values := arg.get_slice("=", 1).split(":")
			expected = int(values[0]); next = int(values[1])
	var failures: Array[String] = []
	if GameData.arena_speed != expected: failures.append("speed after restart")
	if GameData.arena_mode != 1: failures.append("mode after restart")
	var expedition := ArenaRun.new(); expedition.auto_save = false
	var classic := ArenaTournamentRun.new(); classic.auto_save = false
	if not expedition.load_saved(): failures.append("old expedition reload")
	if not classic.load_saved(): failures.append("autochess reload")
	expedition.begin(7323); classic.begin(7323)
	if GameData.arena_speed != expected: failures.append("new runs preserve speed")
	GameData.arena_speed = next
	GameData.save_settings()
	var cfg := ConfigFile.new()
	if cfg.load(GameData.CONFIG_PATH) != OK or cfg.get_value("arena", "battle_speed") != next:
		failures.append("next speed saved")
	print("ARENA_PREFERENCES expected=", expected, " next=", next, "; failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
