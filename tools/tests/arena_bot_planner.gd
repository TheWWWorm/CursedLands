extends Node
## Purchase decisions must retain progress through the whole evolution chain.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL ", message)

func fixture(family: int, filler: int, high_copies: int, low_copies: int) -> ArenaRun:
	var bot := ArenaRun.new()
	bot.auto_save = false
	bot.begin(7319)
	bot.wave = 20
	bot.training = ArenaRules.MAX_TRAINING
	bot.army.clear()
	for copy in ArenaRules.MAX_ARMY: bot._recruit(filler, 2, 1)
	for copy in high_copies: bot._recruit(family, 1, 6)
	for copy in low_copies: bot._recruit(family, 0, 2)
	bot.gold = 60
	bot.shop = [{"family":family, "rank":0, "locked":false}]
	ArenaBotPlanner.arrange(bot, "")
	return bot

func _ready() -> void:
	var native := hash(GameData.db.tables)
	var pair := Vector2i(-1, -1)
	for family in ArenaRules.FAMILIES.size():
		if ArenaRules.evolution_copies(family, 0) < 2: continue
		for filler in ArenaRules.FAMILIES.size():
			var strength := ArenaBotPlanner.power(filler, 2)
			if strength > ArenaBotPlanner.power(family, 1) * 1.2 and strength < ArenaBotPlanner.power(family, 2) * 0.7:
				pair = Vector2i(family, filler)
				break
		if pair.x >= 0: break
	check(pair.x >= 0, "native roster contains a useful final evolution with an obsolete intermediate form")
	if pair.x >= 0:
		var needed := ArenaRules.evolution_copies(pair.x, 0)
		var final_copies := ArenaRules.evolution_copies(pair.x, 1)
		for player in range(1, 5):
			var bot := fixture(pair.x, pair.y, final_copies - 1, needed - 1)
			var cost := bot.offer_cost(bot.shop[0])
			var plan := {"actions":0, "rerolls":0, "done":false}
			ArenaBotPlanner.step(bot, player, 20, 20, plan)
			check(bot.army.any(func(entry): return entry.family == pair.x and entry.rank == 2 and entry.deployed), "profile %d buys the last copy and deploys the three-star evolution" % player)
			check(bot.gold == 60 - cost, "profile %d pays the normal purchase price without selling upgrade progress" % player)
			check(bot.army.filter(func(entry): return entry.family == pair.x).size() == 1, "profile %d consumes exactly the required copies" % player)
		# One more copy is still needed after this purchase: preserve the line
		# even though its next intermediate form cannot displace the current field.
		var growing := fixture(pair.x, pair.y, final_copies - 1, needed - 2)
		var cost := growing.offer_cost(growing.shop[0])
		var plan := {"actions":0, "rerolls":0, "done":false}
		ArenaBotPlanner.step(growing, 3, 20, 20, plan)
		check(growing.gold == 60 - cost and growing.shop[0].family == -1, "CPU invests in a nearly complete final evolution")
		check(growing.army.filter(func(entry): return entry.family == pair.x and entry.rank == 0).size() == needed - 1, "CPU retains the lower-rank copies needed for final evolution")
		var healthy := fixture(pair.x, pair.y, 0, 0)
		healthy.gold = 50
		plan = {"actions":0, "rerolls":0, "done":false}
		ArenaBotPlanner.step(healthy, 1, 20, 100, plan)
		check(healthy.gold == 50, "healthy economy strategy retains maximum-interest savings")
		check(ArenaBotPlanner.reserve(healthy, 20, 20, ArenaBotPlanner.PROFILES[0]) == 0, "critical health releases the savings reserve")
	check(hash(GameData.db.tables) == native, "planning never changes native combat stats")
	var formation := ArenaRun.new(); formation.auto_save=false; formation.begin(9917)
	formation.army.clear(); formation.training=ArenaRules.MAX_TRAINING
	for choice in [Vector2i(17,1),Vector2i(3,2),Vector2i(17,2)]: formation._recruit(choice.x,choice.y,1)
	ArenaBotPlanner.arrange(formation,"")
	for entry in formation.army:
		check(entry.deployed and entry.point[0]==(27.0 if entry.family==17 and entry.rank==2 else 22.0),"held bows form behind melee; utility-only dagger user stays in front")
	print("ARENA_BOT_PLANNER checks=", checks, " family=", pair.x, " filler=", pair.y, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
