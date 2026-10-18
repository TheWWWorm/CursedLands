class_name ArenaOnlineGame
extends Node
## A single host simulation, separate from every player's rendered view.
signal updated
var run := ArenaOnlineTournament.new()
var home: ArenaPveMatch
var boards: ArenaTournamentBattles
var ready_seats: Array[int] = []
var result_left := 4.0
var events := {}
var battle_speed := 1
var _ticks := 0.0
var _tick_player := 0
var _revision := 0
## Yield between complete board ticks so a costly first route does not turn
## into several frames' catch-up work inside the same rendered frame.
const FRAME_TICK_BUDGET_USEC := 6000

func begin(seed_value: int, humans: Dictionary) -> void:
	run.humans = humans.duplicate()
	run.begin(seed_value)
	var stage := Node3D.new(); stage.hide(); add_child(stage)
	# The host renders the same network replica as every guest. Authority
	# figures still supply animation/bone geometry to combat and navigation,
	# but must never draw a second army or cast duplicate scenery shadows.
	home = ArenaPveMatch.new(); home.run = run; home.rendered = false; home.drives_clock = false
	add_child(home); home._world_parent = stage
	home.set_process(false); home.set_physics_process(false)
	boards = ArenaTournamentBattles.new(); boards.run = run; boards.home = home
	boards.parent_stage = stage; boards.rendered = false
	add_child(boards); boards.set_process(false)
	_prepare()

func _prepare() -> void:
	ready_seats.clear(); result_left = 4.0; _ticks = 0.0; _tick_player = 0
	home.prepare(); boards.synchronize()
	for player in ArenaTournamentRun.PLAYER_COUNT:
		var battle := encounter(player)
		if battle and not battle.has_meta("online_events"):
			battle.set_meta("online_events", true)
			battle.visual_event.connect(func(event):
				if not events.has(player): events[player] = []
				if events[player].size() < 256: events[player].append(event.duplicate(true)))
	updated.emit()

func encounter(player: int) -> ArenaPveMatch:
	return home if player == 0 else boards.boards.get(player)

func _process(dt: float) -> void:
	if home == null: return
	advance_clock(dt / maxf(Engine.time_scale, 0.001), FRAME_TICK_BUDGET_USEC * battle_speed)

func advance_clock(dt: float, budget_usec := 0) -> void:
	if run.stage == "prepare":
		var changed_players := run.advance_bots(dt)
		for player in changed_players: boards._sync_board(player)
		if not changed_players.is_empty(): updated.emit()
		if run.elapse_preparation(dt): start_round()
	elif run.stage == "fight":
		_ticks += dt * battle_speed
		# Independent boards retain their 55 ms simulation ticks and player
		# order, but become due across that interval instead of all at once.
		# This bounds the usual inter-board clock difference to one tick and
		# avoids making the renderer wait for nine battles in one frame.
		var slice := GameUnit.TICK / float(ArenaTournamentRun.PLAYER_COUNT)
		var count := 0
		# A short budget smooths ordinary frames, but must not prolong a large
		# backlog (especially at 2x). Temporarily allow twice as much work once
		# two simulation ticks are owed; all yields still finish a whole tick.
		var catch_up := 2 if _ticks > 2.0 * GameUnit.TICK else 1
		var deadline := Time.get_ticks_usec() + budget_usec * catch_up if budget_usec > 0 else 0
		while _ticks + 1e-9 >= slice and run.stage == "fight" and count < 8 * ArenaTournamentRun.PLAYER_COUNT:
			_ticks = maxf(0.0, _ticks - slice); count += 1
			var battle := encounter(_tick_player)
			if battle: battle.simulate_tick()
			_tick_player = (_tick_player + 1) % ArenaTournamentRun.PLAYER_COUNT
			# Always finish a native tick. Keep the remaining debt and player
			# cursor for the next frame; no combat time or board is skipped.
			# Explicit deterministic advances can omit the real-time budget.
			if deadline > 0 and Time.get_ticks_usec() >= deadline: break
		if run.stage != "fight": updated.emit()
	elif run.stage == "result":
		result_left -= dt
		if result_left <= 0:
			run.advance(); _prepare()

func start_round() -> void:
	if run.stage != "prepare": return
	run.finish_preparation()
	for player in run.alive_players():
		var company := run.company(player)
		if company.deployed_count() == 0 and not company.army.is_empty(): company.arrange()
		company.battle_savings = company.gold
		if player == 0: home.prepare()
		else: boards._sync_board(player)
	run.preparation_left = 0
	if run.lives > 0: home.expire_preparation()
	else:
		run.stage = "fight"
		for rival in run.rivals: rival.stage = "fight"
	for player in range(1, ArenaTournamentRun.PLAYER_COUNT):
		if run.health(player) <= 0: continue
		var battle := encounter(player)
		if battle.team_count(0) > 0: battle.start()
		else: run.record_board(player, 1, [0, battle.run.enemy_formation().size()])
	# No rendered or native automatic clock may race the fixed host tick.
	for battle: ArenaPveMatch in [home] + boards.boards.values():
		battle.world.set_process(false); battle.world.set_physics_process(false)
	updated.emit()

func command(player: int, action: String, args: Array) -> String:
	if player < 0 or player >= ArenaTournamentRun.PLAYER_COUNT or not run.humans.has(player): return "Invalid online action."
	if action == "speed":
		if player != 0 or args.size() != 1 or not ArenaRun._integer(args[0], 1, 2): return "Invalid online action."
		battle_speed = int(args[0]); updated.emit(); return ""
	if run.health(player) <= 0 or run.stage == "won": return "You have been eliminated. You can keep watching."
	var company := run.company(player)
	var error := ""
	match action:
		"ready":
			if run.stage != "prepare": return "Finish the current encounter first."
			if ready_seats.has(player): ready_seats.erase(player)
			elif company.deployed_count() == 0: return "Deploy at least one creature before starting."
			else: ready_seats.append(player)
			if everyone_ready(): start_round()
			updated.emit(); return ""
		"buy", "lock":
			if args.size() != 1 or not ArenaRun._integer(args[0],0,5): return "Invalid online action."
			if action == "buy": error = company.buy(int(args[0]))
			elif company.can_shop(): company.lock_offer(int(args[0]))
			else: error = "Finish the current encounter first."
		"refresh": error = company.refresh()
		"train": error = company.train()
		"sell":
			if args.size() not in [1,2] or not ArenaRun._integer(args[0],1,1000000): return "Invalid online action."
			var entry := company.unit(int(args[0]))
			if args.size()==2:
				if not ArenaRun._integer(args[1],0,10000): return "Invalid online action."
				if entry.is_empty() or company.sale_value(entry)!=int(args[1]): return "The sale value changed. Select the creature again."
			error = company.sell(int(args[0]))
		"bench", "evolve":
			if args.size() != 1 or not ArenaRun._integer(args[0],1,1000000): return "Invalid online action."
			if action == "bench": error = company.bench(int(args[0]))
			else: error = company.evolve(int(args[0]))
		"swap":
			if args.size() != 2 or not ArenaRun._integer(args[0],1,1000000) or not ArenaRun._integer(args[1],1,1000000): return "Invalid online action."
			error = company.swap_from_bench(int(args[0]), int(args[1]))
		"deploy":
			if args.size() != 2 or not ArenaRun._integer(args[0],1,1000000) or not args[1] is Vector2 or not args[1].is_finite(): return "Invalid online action."
			var battle := encounter(player)
			battle.selected_run_uid = int(args[0])
			error = battle.placement_error(args[1])
			if error.is_empty(): error = company.deploy(int(args[0]), args[1])
		"arrange": company.arrange()
		"undo": company.undo()
		_: return "Invalid online action."
	if error.is_empty():
		ready_seats.erase(player)
		if run.stage == "prepare":
			if player == 0: home.prepare()
			else: boards._sync_board(player)
		updated.emit()
	return error

func disconnect_player(player: int) -> void:
	run.humans.erase(player); ready_seats.erase(player)
	if player > 0: run.bot_plans[player - 1].done = false
	if run.stage == "prepare" and everyone_ready(): start_round()
	updated.emit()

func everyone_ready() -> bool:
	var active := run.humans.keys().filter(func(id): return run.health(id) > 0)
	return not active.is_empty() and active.all(func(id): return ready_seats.has(id))

func state_for(player: int, names: Array) -> Dictionary:
	var companies := []
	for id in ArenaTournamentRun.PLAYER_COUNT:
		var company := run.company(id)
		var data := company.snapshot() if id > 0 else _own_snapshot()
		data.erase("rng")
		if id != player: data.shop = []
		data["evolutions"] = company.last_evolutions.duplicate()
		companies.append(data)
	return {"t":"state", "seat":player, "seed":run.run_seed, "round":run.wave, "stage":run.stage,
		"speed":battle_speed, "fighting":run.alive_players().filter(func(id): return encounter(id) != null and encounter(id).phase == ArenaMatch.Phase.FIGHT),
		"left":run.preparation_left, "result_left":result_left, "staging":run.preparing_battle,
		"companies":companies, "health":[run.lives] + run.rival_health, "placements":run.placements.duplicate(),
		"pairings":run.pairings.duplicate(true), "names":names.duplicate(), "ready":ready_seats.duplicate(), "undo":run.company(player).can_undo(),
		"sale_quotes":run.company(player).army.map(func(entry):return [int(entry.uid),run.company(player).sale_value(entry)])}

func _own_snapshot() -> Dictionary:
	# Avoid nesting the complete tournament inside seat zero's company.
	var data := run.snapshot()
	for key in ["rivals","rival_health","placements","pairings","bot_plans","previous_opponent"]: data.erase(key)
	return data

func board_key(player: int) -> String:
	var battle := encounter(player)
	if battle == null: return ""
	var actors := []
	for unit: GameUnit in battle.world.unit_rows(): actors.append([unit.uid, unit.info.prototype, unit.get_meta("arena_placement", {})])
	return "%d:%s" % [battle.world.get_instance_id(), str(actors)]

func board_frame(player: int, full: bool) -> Dictionary:
	var battle := encounter(player)
	_revision += 1
	var data := {"t":"board", "seat":player, "round":run.wave, "generation":board_key(player), "serial":_revision,
		"phase":battle.phase, "winner":battle.winner, "time":battle.world.time, "damage":battle.damage.duplicate(), "full":full}
	data["friendly_damage"] = []
	for uid in battle.friendly_damage: data.friendly_damage.append([int(uid),float(battle.friendly_damage[uid])])
	if full:
		var records := []
		for unit: GameUnit in battle.world.unit_rows():
			var record := battle._unit_record(unit)
			record["online_body"] = exact_body(unit)
			record["placement"] = unit.get_meta("arena_placement", {}).duplicate(true)
			records.append(record)
		data["records"] = records
		data["army"] = battle.round_army.duplicate(true)
	else:
		data["snaps"] = NetSnapshot.pack(battle.world.unit_rows().map(func(unit):
			var row: Array = unit.snapshot()
			row.resize(18); row[17] = exact_body(unit)
			return row))
	return data

static func exact_body(unit: GameUnit) -> PackedFloat64Array:
	# The campaign's compact byte wounds are sufficient for animation. Online
	# autochess also displays numeric health, so preserve the exact body health.
	var body := PackedFloat64Array([unit.max_hp])
	for part: UnitBodyPart in unit.parts: body.append(part.cur)
	return body
