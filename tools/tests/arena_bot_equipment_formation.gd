extends Node
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func company(families: Array, rank := 0) -> ArenaRun:
	var bot := ArenaRun.new(); bot.auto_save = false; bot.begin(3487); bot.training = ArenaRules.MAX_TRAINING
	for family in families: bot._recruit(int(family),rank,1)
	ArenaBotPlanner.arrange(bot, "warrior")
	return bot

func board(bot: ArenaRun) -> ArenaPveMatch:
	var battle := ArenaPveMatch.new(); battle.run = bot; battle.rendered = false; battle.drives_clock = false
	add_child(battle); battle._world_parent = self; battle.set_process(false); battle.set_physics_process(false)
	battle.prepare(); bot.deployment_check = battle.recruitment_clear
	return battle

func legal(battle: ArenaPveMatch, label: String) -> void:
	var actors := battle.world.unit_rows().filter(func(unit): return int(unit.get_meta("arena_placement",{}).get("team",1)) == 0)
	for unit: GameUnit in actors:
		# Asking placement_error to move an actor to its exact current point
		# produces an empty route. Check its actual fitted body and native cell.
		check(ArenaRun.DEPLOY.has_point(unit.pos) and battle.bounds().grow(-unit.body_radius()).has_point(unit.pos) and battle.world.nav.cell_open(unit.pos,unit.move_class()), label + " native placement")
		for other: GameUnit in actors:
			if unit.uid >= other.uid: continue
			check(unit.pos.distance_to(other.pos)+0.001 >= maxf(2.5,unit.body_radius()+other.body_radius()+0.25), label + " fitted body clearance")

func _ready() -> void:
	var bot := company([0,6,3])
	var battle := board(bot)
	ArenaBotPlanner.arrange(bot, "warrior"); battle.prepare()
	legal(battle,"guard formation")
	var guards := battle.world.unit_rows().filter(func(unit): return "warrior" in ArenaAlliances.traits(int(unit.get_meta("arena_placement",{}).get("family",-1))))
	check(guards.any(func(guard): return battle.world.unit_rows().any(func(ally): return ally != guard and guard.pos.distance_to(ally.pos) <= 3.0)), "native-sized guard can reach an ally without overlapping")
	check(bot.army.filter(func(entry): return entry.family == 3)[0].point[0] < bot.army.filter(func(entry): return entry.family == 0)[0].point[0], "guarded caster remains behind frontline")
	bot = company([24,24,24,24,24,24,24,24,24],2)
	battle = board(bot)
	check(bot.deployed_count() == 9, "conservative unknown-body layout keeps all nine large creatures")
	legal(battle,"large formation before measured update")
	ArenaBotPlanner.arrange(bot, "warrior"); battle.prepare()
	check(bot.deployed_count() == 9, "measured large layout keeps all nine creatures")
	legal(battle,"large formation after measured update")
	bot = company([3,13,18],1); battle = board(bot)
	ArenaBotPlanner.arrange(bot,"mage"); battle.prepare()
	var actors := battle.world.unit_rows().filter(func(unit): return int(unit.get_meta("arena_placement",{}).get("team",1)) == 0)
	check(actors.all(func(unit): return actors.all(func(other): return unit == other or unit.pos.distance_to(other.pos) >= 3.99)), "composition without proximity rewards keeps spread")
	legal(battle,"spread formation")
	print("ARENA_BOT_EQUIPMENT_FORMATION ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
