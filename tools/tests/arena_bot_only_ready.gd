extends Node
## Online autochess: once every human is eliminated or gone, the computers'
## preparation must not wait out the 60-second timer for nobody to be ready.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func make_game() -> ArenaOnlineGame:
	var game := ArenaOnlineGame.new(); add_child(game)
	game.begin(7319, {0:"Host", 1:"Guest"}); game.set_process(false)
	for player in [0, 1]:
		var company := game.run.company(player)
		company._recruit(7, 0, 1); company.arrange()
	return game

func _ready() -> void:
	# Living humans who are not ready keep the preparation running.
	var game := make_game()
	check(game.run.stage == "prepare", "a new tournament starts in preparation")
	var timer := game.run.preparation_left
	check(timer > 1.0, "preparation has a real countdown")
	game.advance_clock(0.05)
	check(game.run.stage == "prepare", "unready living humans keep the preparation")
	check(not game.everyone_ready(), "nobody ready yet")
	check(game.command(0, "ready", []).is_empty(), "host can declare ready")
	check(game.run.stage == "prepare", "one unready living guest still holds the round")
	game.free()

	# The only unready human is eliminated: the round starts without waiting.
	game = make_game()
	game.command(0, "ready", [])
	game.run.rival_health[0] = 0
	game.advance_clock(0.05)
	check(game.run.stage != "prepare", "an eliminated guest does not hold the round")
	game.free()

	# Every human eliminated: computers alone start their round immediately.
	game = make_game()
	game.run.lives = 0; game.run.rival_health[0] = 0
	check(game.everyone_ready(), "no living humans counts as ready")
	game.advance_clock(0.05)
	check(game.run.stage != "prepare", "bot-only preparation ends on the next host tick")
	check(game.run.preparation_left <= 0.0, "the bot-only round does not wait out the timer")
	game.free()

	# The last living human leaves during preparation.
	game = make_game()
	game.run.lives = 0
	check(game.run.stage == "prepare", "a living guest remains in preparation")
	game.disconnect_player(1)
	check(game.run.stage != "prepare", "the last human leaving starts the computers' round")
	game.free()

	print("ARENA_BOT_ONLY_READY ", JSON.stringify({"checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
