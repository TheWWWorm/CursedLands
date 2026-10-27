class_name ArenaTournamentRun
extends ArenaRun
## Nine persistent companies. Pairings and purchases are fixed before combat;
## health changes when each board finishes; income and places settle together.
const PLAYER_COUNT := 9
const MAX_ROUNDS := 100
const TOURNAMENT_SAVE := "user://arena-autochess.json"
const STYLES := ["beast", "horde", "warrior", "hunter", "mage", "spirit"]
var rivals: Array[ArenaRun] = []
var rival_health: Array[int] = []
var placements: Array[int] = []
var pairings: Array[Dictionary] = []
var results := {}
var previous_opponent := -1
var _human_result := {}
var _initializing := false
var live_boards := false
var board_results := {}
var _round_health: Array[int] = []
var bot_plans: Array[Dictionary] = []

func arrivals_at_start() -> bool: return true

func computer_controls(player: int) -> bool: return player > 0
func continues_after_elimination() -> bool: return false
func round_savings(player: int) -> int:
	return battle_savings if player == 0 else company(player).gold

func opponent_for(player: int) -> int:
	for pair: Dictionary in pairings:
		if int(pair.a) == player: return int(pair.b)
		if int(pair.b) == player and not pair.ghost: return int(pair.a)
	return -1

func board_encounter(player: int) -> String:
	var opponent := opponent_for(player)
	if opponent < 0: return RemakeText.t("Creep round")
	for pair: Dictionary in pairings:
		if int(pair.a) == player and pair.ghost: return RemakeText.t("Opponent: %s (copy)") % player_title(opponent)
	return RemakeText.t("Opponent: %s") % player_title(opponent)



func begin(seed_value: int, chosen_starter := 0, difficulty := 0) -> void:
	_initializing = true
	rivals.clear(); rival_health.clear(); placements.clear(); pairings.clear(); results.clear()
	_human_result.clear(); previous_opponent = -1
	super.begin(seed_value, chosen_starter, 0)
	placements.resize(PLAYER_COUNT); placements.fill(0)
	var identities := ArenaCommanders.opponents(commander, expansion)
	for index in PLAYER_COUNT - 1:
		var rival := ArenaRun.new()
		rival.auto_save = false
		rival.expansion = expansion
		rival.commander = identities[index]
		rival.begin(1 + (run_seed * 37 + index * 7919) % 99999998)
		rivals.append(rival); rival_health.append(100)
	_share_pool()
	_prepare_round()
	_initializing = false
	_touch()


## Every company recruits from one pool; an eliminated company's creatures
## return to it (only living companies hold copies).
func _share_pool() -> void:
	for player in 1 + rivals.size():
		company(player).pool_companies = _pool_holders


func _pool_holders() -> Array[ArenaRun]:
	var holders: Array[ArenaRun] = []
	for player in 1 + rivals.size():
		if health(player) > 0: holders.append(company(player))
	return holders


func round_limit() -> int: return MAX_ROUNDS
func life_limit() -> int: return 100
func save_path() -> String: return "user://arena-autochess-astral.json" if expansion else TOURNAMENT_SAVE
func _update_profile() -> void: pass

func _touch() -> void:
	if not _initializing: super._touch()

func is_creep_round() -> bool:
	return wave <= 3 or wave % 5 == 0

func health(player: int) -> int:
	return lives if player == 0 else rival_health[player - 1]

func company(player: int) -> ArenaRun:
	return self if player == 0 else rivals[player - 1]

func player_title(player: int) -> String:
	if player == 0: return GameData.player_name
	return ArenaCommanders.title(company(player).commander)

func player_fighting(player: int) -> bool:
	return stage == "fight" and health(player) > 0 and not board_results.has(player)

func alive_players() -> Array[int]:
	var alive: Array[int] = []
	for player in PLAYER_COUNT:
		if health(player) > 0: alive.append(player)
	return alive

func human_pair() -> int:
	return pairings.find_custom(func(pair): return int(pair.a) == 0)

func round_title() -> String:
	return RemakeText.t("Round %d") % wave

func encounter_title() -> String:
	if is_creep_round(): return RemakeText.t("Creep round")
	var index := human_pair()
	if index < 0: return RemakeText.t("Autochess")
	var pair := pairings[index]
	return (RemakeText.t("Opponent: %s (copy)") if pair.ghost else RemakeText.t("Opponent: %s")) % player_title(int(pair.b))

func enemy_formation() -> Array[Dictionary]:
	if is_creep_round(): return creeps()
	return formation_for(enemy_army(), 1)

func enemy_army() -> Array[Dictionary]:
	var index := human_pair()
	if is_creep_round() or index < 0: return []
	return company(int(pairings[index].b)).army

func creeps() -> Array[Dictionary]:
	return ArenaRules.enemies(mini(wave, ArenaRules.WAVE_COUNT), run_seed)

static func formation_for(army_rows: Array, team: int) -> Array[Dictionary]:
	var formation: Array[Dictionary] = []
	for entry: Dictionary in army_rows:
		if not entry.deployed: continue
		var point := Vector2(entry.point[0], entry.point[1])
		if team == 1: point.x = 64.0 - point.x
		var placement := {"id":entry.prototype, "team":team, "point":point, "rank":int(entry.rank), "family":int(entry.family), "item":String(entry.get("item", ""))}
		placement["run_uid" if team == 0 else "source_uid"] = int(entry.uid)
		formation.append(placement)
	return formation


func _prepare_round() -> void:
	results.clear(); board_results.clear(); _human_result.clear(); bot_plans.clear()
	_round_health.clear()
	for index in rivals.size():
		bot_plans.append({"actions":0, "rerolls":0, "wait":0.4 + index * 0.13, "done":false})
		if rival_health[index] <= 0: continue
		var rival := rivals[index]
		rival.stage = "prepare"
		rival.wave = mini(wave, ArenaRules.WAVE_COUNT)
		if wave > ArenaRules.WAVE_COUNT: rival.training = mini(ArenaRules.MAX_TRAINING, rival.training + 1)
		if wave > 1: rival._roll_shop(true)
	_choose_pairings()


## Bots pay the same prices and use the same offers, XP and merge recipes.
static func shop_for(bot: ArenaRun, player: int, round_number: int, hp: int) -> void:
	var plan := {"actions":0, "rerolls":0, "done":false}
	while not plan.done: shop_step(bot, player, round_number, hp, plan)


static func shop_step(bot: ArenaRun, player: int, round_number: int, hp: int, plan: Dictionary) -> void:
	ArenaBotPlanner.step(bot,player,round_number,hp,plan)


func advance_bots(dt: float) -> Array[int]:
	var changed_players: Array[int] = []
	if stage != "prepare": return changed_players
	for index in rivals.size():
		var plan := bot_plans[index]
		if rival_health[index] <= 0 or plan.done or not computer_controls(index + 1): continue
		plan.wait -= dt
		if plan.wait > 0: continue
		plan.wait += 0.8 + float(index % 4) * 0.18
		shop_step(rivals[index], index + 1, wave, rival_health[index], plan)
		changed_players.append(index + 1)
	return changed_players


func finish_preparation() -> void:
	for index in rivals.size():
		if rival_health[index] <= 0 or not computer_controls(index + 1): continue
		while not bot_plans[index].done: shop_step(rivals[index], index + 1, wave, rival_health[index], bot_plans[index])


func start_battle(allow_empty := false) -> String:
	if stage == "prepare": finish_preparation()
	var error := super.start_battle(allow_empty)
	if error.is_empty():
		for player in alive_players(): company(player).settle_item_choice()
	return error


func record_board(player: int, winner: int, survivors: Array) -> void:
	if stage != "fight" or board_results.has(player): return
	_remember_round_health()
	board_results[player] = {"winner":winner, "survivors":survivors.duplicate()}
	var loss := 0 if winner == 0 else draw_damage() if winner == -1 else defeat_damage(int(survivors[1]))
	_apply_round_loss(player,loss)
	var result := _human_result.duplicate(true) if player == 0 else {"wave":wave,"winner":winner,"seconds":0,"damage":[0,0],"gold":0}
	result["health_lost"] = loss
	company(player).last_result = result
	if board_results.size() == _round_players().size() and not _human_result.is_empty(): _settle_round()
	else: _touch()


func _remember_round_health() -> void:
	if _round_health.is_empty(): _round_health.assign([lives]+rival_health)


func _round_players() -> Array[int]:
	var players: Array[int] = []
	for player in PLAYER_COUNT:
		if (_round_health[player] if not _round_health.is_empty() else health(player)) > 0: players.append(player)
	return players


func _apply_round_loss(player: int, loss: int) -> void:
	var remaining := maxi(0,_round_health[player]-loss)
	if player == 0: lives = remaining
	else: rival_health[player-1] = remaining


## Interrupted worker combat replays from preparation, including original HP.
func rollback_round_health() -> void:
	if _round_health.is_empty(): return
	lives = _round_health[0]
	for index in rival_health.size(): rival_health[index] = _round_health[index+1]
	_round_health.clear()


func draw_damage() -> int:
	return 0 if is_creep_round() else 10


func _choose_pairings() -> void:
	pairings.clear()
	var alive := alive_players()
	if is_creep_round():
		for player in alive: pairings.append({"a":player,"b":-1,"ghost":false})
		return
	var random := RandomNumberGenerator.new()
	random.seed = run_seed * 104729 + wave * 7919
	for index in range(alive.size() - 1, 0, -1):
		var other := random.randi_range(0, index)
		var held := alive[index]; alive[index] = alive[other]; alive[other] = held
	# Give the human a new opponent whenever at least two rivals remain.
	if alive.has(0) and alive.size() > 1:
		alive.erase(0)
		var candidates := alive.filter(func(player):return int(player) != previous_opponent)
		var opponent: int = candidates[0] if not candidates.is_empty() else alive[0]
		alive.erase(opponent)
		pairings.append({"a":0,"b":opponent,"ghost":false})
		previous_opponent = opponent
	while alive.size() >= 2:
		pairings.append({"a":alive.pop_back(),"b":alive.pop_back(),"ghost":false})
	if not alive.is_empty():
		# The unpaired company fights a copy; the donor never loses health twice.
		var player: int = alive[0]
		var donors := alive_players().filter(func(id):return id != player)
		pairings.append({"a":player,"b":donors[random.randi_range(0, donors.size()-1)],"ghost":true})


func resolve(winner: int, seconds: float, damage: Array, survivors: Array = [0,0]) -> void:
	if stage != "fight" or not _human_result.is_empty(): return
	_human_result = {"wave":wave,"winner":winner,"seconds":seconds,"damage":damage.duplicate(),"gold":0}
	if deployed_count() == 0: _human_result["empty_army"] = true
	if live_boards: record_board(0, winner, survivors)
	else: record_duel(human_pair(), winner, survivors)

func record_duel(index: int, winner: int, survivors: Array) -> void:
	if stage != "fight" or index < 0 or index >= pairings.size() or results.has(index): return
	_remember_round_health()
	results[index] = {"winner":winner,"survivors":survivors.duplicate()}
	var pair: Dictionary = pairings[index]
	_apply_round_loss(int(pair.a),0 if winner == 0 else draw_damage() if winner == -1 else defeat_damage(int(survivors[1])))
	if int(pair.b)>=0 and not pair.ghost:
		_apply_round_loss(int(pair.b),0 if winner == 1 else draw_damage() if winner == -1 else defeat_damage(int(survivors[0])))
	if results.size() == pairings.size() and not _human_result.is_empty(): _settle_round()
	else: _touch()

func defeat_damage(surviving_damage: int) -> int:
	# Neutral encounters do not deal player damage. Commanders are portraits,
	# not combatants, so there is no separate surviving-Underlord contribution.
	return 0 if is_creep_round() else wave / 10 + maxi(0, surviving_damage)

func _settle_round() -> void:
	_remember_round_health()
	var alive := _round_players()
	var losses := {}; var victories := {}
	for index in (0 if live_boards else pairings.size()):
		var pair := pairings[index]; var result: Dictionary = results[index]
		var a := int(pair.a); var b := int(pair.b); var winner := int(result.winner)
		victories[a] = winner == 0
		if winner != 0: losses[a] = draw_damage() if winner == -1 else defeat_damage(int(result.survivors[1]))
		if b >= 0 and not pair.ghost:
			victories[b] = winner == 1
			if winner != 1: losses[b] = draw_damage() if winner == -1 else defeat_damage(int(result.survivors[0]))
	if live_boards:
		for player: int in board_results:
			var result: Dictionary = board_results[player]
			victories[player] = int(result.winner) == 0
			if int(result.winner) != 0:
				losses[player] = draw_damage() if int(result.winner) == -1 else defeat_damage(int(result.survivors[1]))
		# A drawn duel costs both owners ten health. A ghost never damages its donor.
		for pair: Dictionary in pairings:
			var a := int(pair.a); var b := int(pair.b)
			if b < 0 or pair.ghost: continue
			if int(board_results[a].winner) == -1 or int(board_results[b].winner) == -1:
				losses[a] = draw_damage(); losses[b] = draw_damage()
				victories[a] = false; victories[b] = false
	var remaining := {}
	for player in alive:
		remaining[player] = _round_health[player] - int(losses.get(player, 0))
		if player == 0: lives = maxi(0, int(remaining[player]))
		else: rival_health[player - 1] = maxi(0, int(remaining[player]))
	var eliminated := alive.filter(func(player):return health(player) == 0)
	eliminated.sort_custom(func(a,b):return remaining[a] < remaining[b] if remaining[a] != remaining[b] else a > b)
	if eliminated.size() == alive.size():
		# A final simultaneous draw is settled by remaining health, then seat.
		var champion: int = eliminated.pop_back()
		if champion == 0: lives = 1
		else: rival_health[champion - 1] = 1
	for index in eliminated.size(): placements[eliminated[index]] = alive.size() - index
	for player in alive:
		var company_run := company(player)
		if health(player) > 0: company_run.offer_items_after(wave)
		var won := bool(victories.get(player, false))
		var income := company_run.income_preview(round_savings(player))
		if not won:
			income.victory = 0; income.streak = 0
			income.total = int(income.base) + int(income.interest)
		company_run.gold += int(income.total)
		if player == 0:
			last_result = _human_result.duplicate(true)
			if live_boards and not won and int(last_result.winner) == 0: last_result.winner = -1
			last_result.gold = int(income.total); last_result.income = income
			last_result["health_lost"] = int(losses.get(0, 0))
		else:
			company_run.history.append({"wave":company_run.wave,"winner":0 if won else 1,"seconds":0,"damage":[0,0],"gold":int(income.total)})
			# Only the last six wins affect income; retain a bounded history
			# compatible with the company save format after round thirty.
			if company_run.history.size() > 36: company_run.history.pop_front()
	history.append(last_result.duplicate(true))
	var survivors := alive_players()
	if survivors.size() == 1: placements[survivors[0]] = 1
	stage = "won" if survivors.size() == 1 else "lost" if lives <= 0 and not continues_after_elimination() else "result"
	if not continues_after_elimination() and lives <= 0: stage = "lost"
	_touch()

func advance() -> void:
	if stage != "result": return
	_next_wave()
	_prepare_round()
	_touch()

func snapshot() -> Dictionary:
	var data := super.snapshot()
	data["mode"] = "autochess"
	data["rivals"] = rivals.map(func(rival):return rival.snapshot())
	data["rival_health"] = rival_health.duplicate()
	data["placements"] = placements.duplicate()
	data["pairings"] = pairings.duplicate(true)
	data["previous_opponent"] = previous_opponent
	data["bot_plans"] = bot_plans.duplicate(true)
	# Interrupted fights restart, so persist the pre-fight health alongside
	# the current purchases instead of charging a partial outcome twice.
	if stage == "fight" and not _round_health.is_empty():
		data.lives = _round_health[0]
		data.rival_health = _round_health.slice(1)
	return data

func valid_terminal(data: Dictionary, _limit: int) -> bool:
	var alive := 1 if int(data.lives) > 0 else 0
	for hp in data.rival_health:
		if int(hp) > 0: alive += 1
	if alive == 0: return false
	if int(data.lives) == 0: return data.stage == "lost"
	return data.stage == "won" if alive == 1 else data.stage in ["prepare", "fight", "result"]

func restore(data: Dictionary) -> bool:
	# The earlier local preview used ten seats. Validate it fully before
	# removing the extra CPU; keep the human company, health and economy.
	var old_preview: bool = data.get("rivals") is Array and data.rivals.size() == 9
	if not _restore_companies(data, 10 if old_preview else PLAYER_COUNT): return false
	if old_preview:
		var removed_rank: int = placements.pop_back()
		rivals.pop_back(); rival_health.pop_back(); bot_plans.pop_back()
		for player in placements.size():
			if placements[player] > 0 and (removed_rank == 0 or placements[player] > removed_rank): placements[player] -= 1
		if previous_opponent >= PLAYER_COUNT: previous_opponent = -1
		var alive := alive_players()
		if alive.is_empty():
			var champion := placements.find(1)
			if champion == 0: lives = 1
			else: rival_health[champion - 1] = 1
			alive.append(champion)
		if alive.size() == 1:
			placements[alive[0]] = 1
			stage = "won" if alive[0] == 0 else "lost"
		if stage not in ["won", "lost"]: _choose_pairings()
		else: pairings = [{"a":0, "b":-1 if is_creep_round() else maxi(1, alive[0]), "ghost":false}]
	return true


func _restore_companies(data: Dictionary, seats: int) -> bool:
	if data.get("mode") != "autochess" or not _integer(data.get("wave"),1,MAX_ROUNDS): return false
	if data.get("stage") == "reward" or not data.get("rivals") is Array or data.rivals.size() != seats - 1: return false
	if not data.get("rival_health") is Array or data.rival_health.size() != seats - 1: return false
	if not data.get("placements") is Array or data.placements.size() != seats: return false
	if not _integer(data.get("previous_opponent"),-1,seats - 1): return false
	var loaded: Array[ArenaRun] = []
	for index in data.rivals.size():
		if not _integer(data.rival_health[index],0,100) or not data.rivals[index] is Dictionary: return false
		var bot := ArenaRun.new(); bot.auto_save = false
		if not bot.restore(data.rivals[index]) or bot.stage != "prepare": return false
		if bot.expansion != data.get("expansion", false): return false
		if not data.rivals[index].has("commander"):
			bot.commander = ArenaCommanders.opponents(String(data.get("commander", "hero")))[index % 8]
		# Company waves cap at the expedition limit; migration must use the
		# actual tournament round for its no-retroactive-rewards watermark.
		if int(data.rivals[index].version) < 14 and not data.rivals[index].has("items"):
			bot.item_reward_round = int(data.wave) if data.stage in ["result", "won", "lost"] else int(data.wave) - 1
		loaded.append(bot)
	var ranked := {}
	for rank in data.placements:
		if not _integer(rank,0,seats): return false
		if int(rank) > 0:
			if ranked.has(int(rank)): return false
			ranked[int(rank)] = true
	if not data.get("pairings") is Array or data.pairings.is_empty() or data.pairings.size() > seats: return false
	var owners := {}
	var creeps_round := int(data.wave) <= 3 or int(data.wave) % 5 == 0
	for pair in data.pairings:
		if not pair is Dictionary or not _integer(pair.get("a"),0,seats - 1) or not _integer(pair.get("b"),-1,seats - 1) or not pair.get("ghost") is bool: return false
		if int(pair.a) == int(pair.b) or owners.has(int(pair.a)): return false
		owners[int(pair.a)] = true
		if (int(pair.b) == -1) != creeps_round or (creeps_round and pair.ghost): return false
		if int(pair.b) == 0 and not pair.ghost: return false # Human owns its board; copies may face it.
		if int(pair.b) >= 0 and not pair.ghost:
			if owners.has(int(pair.b)): return false
			owners[int(pair.b)] = true
	if not owners.has(0): return false
	if data.stage in ["prepare","fight"]:
		for player in seats:
			var hp: int = int(data.lives) if player == 0 else int(data.rival_health[player - 1])
			if (hp > 0) != owners.has(player): return false
		for pair in data.pairings:
			if pair.ghost and int(pair.b) > 0 and int(data.rival_health[int(pair.b) - 1]) <= 0: return false
	if not super.restore(data): return false
	rivals = loaded; rival_health.assign(data.rival_health); placements.assign(data.placements)
	pairings.assign(data.pairings.duplicate(true)); previous_opponent = int(data.previous_opponent)
	results.clear(); board_results.clear(); _human_result.clear()
	_round_health.clear()
	bot_plans.clear()
	for index in rivals.size():
		var plan := {"actions":0, "rerolls":0, "wait":0.5 + index * 0.1, "done":false}
		if data.get("bot_plans") is Array and data.bot_plans.size() == rivals.size():
			var saved = data.bot_plans[index]
			if saved is Dictionary and _integer(saved.get("actions"),0,40) and _integer(saved.get("rerolls"),0,12) and saved.get("done") is bool and _number(saved.get("wait"),-10,10):
				plan = saved.duplicate(true)
		bot_plans.append(plan)
	_share_pool()
	return true
