extends Node
## Frame scheduling must preserve native board order, clocks and combat results.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FAIL ",message)

func make_game() -> ArenaOnlineGame:
	var game := ArenaOnlineGame.new(); add_child(game)
	game.begin(7319,{0:"Host",1:"Guest"}); game.set_process(false)
	game.run.wave = 7
	for player in 9:
		var company := game.run.company(player)
		company.army.clear(); company.wave = 7; company.training = 54
		company.gold = 50; company.auto_save = false
		for family in [7,11,17,22]: company._recruit(family,1,7)
		company.arrange()
	game.run._prepare_round()
	for plan: Dictionary in game.run.bot_plans: plan.done = true
	game._prepare(); game.start_round()
	seed(57391)
	return game

func state_of(game: ArenaOnlineGame) -> Array:
	var result := [game.run.stage,game.run.board_results.duplicate(true),game.run.lives,game.run.rival_health.duplicate()]
	for player in 9:
		var battle := game.encounter(player)
		var units := []
		for unit: GameUnit in battle.world.unit_rows():
			var target: Variant = unit.order.get("target")
			units.append([unit.uid,unit.pos,unit.facing,unit.hp,unit.dead,unit.action,
				unit.path.duplicate(),unit.order.get("type",""),target.uid if target is GameUnit else null,
				unit._buff_snapshot()])
		result.append([battle.world.time,battle.phase,battle.winner,battle.damage.duplicate(),
			battle.world.combat.rng.state,game.run.company(player).gold,units])
	return result

func reference(speed: int) -> Array:
	var game := make_game(); game.battle_speed = speed
	var states := []
	for cycle in 2400:
		for tick in speed:
			if game.run.stage != "fight": break
			game.home.simulate_tick(); game.boards.step()
		states.append(state_of(game))
		if game.run.stage != "fight": break
	check(game.run.stage == "result","reference reaches a complete round")
	game.free()
	return states

func scheduled(speed: int, expected: Array, budget_usec := 0) -> void:
	var game := make_game(); game.battle_speed = speed
	var distributed := false
	var deferred := false
	for cycle in expected.size():
		# Deliberately uneven render intervals summing to one native tick.
		for dt in [0.001,0.008,0.016,0.030]:
			if game.run.stage != "fight": break
			game.advance_clock(dt, budget_usec)
			var times := []
			for player in 9:
				var battle := game.encounter(player)
				if battle.phase == ArenaMatch.Phase.FIGHT: times.append(battle.world.time)
			if times.size() > 1:
				check(float(times.max())-float(times.min()) <= GameUnit.TICK+1e-8,"active boards differ by at most one native tick")
				if float(times.max()) > float(times.min()): distributed = true
		# A tiny budget forces complete ticks across callbacks. Drain only
		# the already owed time, then compare the same native-clock boundary.
		var slice := GameUnit.TICK / float(ArenaTournamentRun.PLAYER_COUNT)
		var calls := 0
		while budget_usec > 0 and game.run.stage == "fight" and game._ticks + 1e-9 >= slice and calls < 72:
			deferred = true; calls += 1
			var before := game._ticks
			game.advance_clock(0.0, budget_usec)
			check(game._ticks < before, "deferred work advances without receiving more time")
		check(calls < 72, "bounded catch-up drains the owed board ticks")
		check(state_of(game) == expected[cycle],"native state, RNG and results match at speed %d cycle %d budget %d" % [speed,cycle,budget_usec])
		if not failures.is_empty(): break
	check(distributed,"combat work is distributed across render frames")
	if budget_usec > 0: check(deferred,"the real-time budget defers combat work")
	check(game.run.stage == "result","scheduled boards settle the complete round")
	game.advance_clock(5.0)
	check(game.run.stage == "prepare" and game._ticks == 0.0 and game._tick_player == 0,"next round resets scheduling debt and board cursor")
	game.free()

func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"autosave":0,"net_lan":0,"net_upnp":0,"net_directory":0},true)
	for speed in [1,2]:
		var expected := reference(speed)
		await get_tree().process_frame
		scheduled(speed,expected)
		await get_tree().process_frame
		scheduled(speed,expected,1)
		await get_tree().process_frame
	print("ARENA_HOST_TICK_SCHEDULE ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
