extends Node
## A live-board tournament past the expedition's 30 rounds. Each CPU company
## is saved as an ordinary company, whose round stays within that limit; its
## board result must use the company's round rather than the tournament's,
## or the tournament save cannot be loaded again after round 30.
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func _ready() -> void:
	var run := ArenaTournamentRun.new(); run.auto_save = false; run.begin(7301); run.finish_preparation()
	run.live_boards = true
	var other := ArenaTournamentRun.new(); other.auto_save = false
	var late := 0
	while run.wave <= ArenaRules.WAVE_COUNT + 3:
		# Everyone survives so that every company keeps playing.
		run.lives = 100; run.rival_health.fill(100)
		run.stage = "fight"
		for player in range(1, ArenaTournamentRun.PLAYER_COUNT):
			run.record_board(player, 0, [3, 0])
		run.resolve(0, 10, [20, 10], [3, 3])
		check(run.stage == "result", "round %d settles" % run.wave)
		for bot in run.rivals:
			if not bot.last_result.is_empty() and int(bot.last_result.wave) > ArenaRules.WAVE_COUNT:
				check(false, "round %d CPU result stays within its company's rounds (%d)" % [run.wave, int(bot.last_result.wave)])
				break
		var saved := JSON.parse_string(JSON.stringify(run.snapshot())) as Dictionary
		check(other.restore(saved), "round %d result reloads" % run.wave)
		check(other.wave == run.wave and other.rivals.size() == run.rivals.size(), "round %d reload keeps the tournament" % run.wave)
		if run.wave > ArenaRules.WAVE_COUNT: late += 1
		run.advance()
	check(late == 3, "three rounds past the expedition limit were played")
	print("ARENA_LATE_ROUND_SAVE ", checks, " checks ", failures.size(), " failures")
	get_tree().quit(0 if failures.is_empty() else 1)
