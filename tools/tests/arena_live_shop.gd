extends Node
## Real roster/settlement regressions, including saves and deferred elite ranks.
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)
func fresh() -> ArenaRun:
	var run := ArenaRun.new(); run.auto_save = false; run.begin(2201); run.gold = 100
	return run
func _ready() -> void:
	var native := hash(GameData.db.tables)
	var run := fresh()
	for i in run.shop.size(): run.lock_offer(i)
	var shelf := run.shop.duplicate(true)
	var bank := run.gold
	check(not run.refresh().is_empty() and run.gold == bank and run.shop == shelf, "all-locked refresh cannot spend")
	run.lock_offer(1); run.lock_offer(3)
	shelf = run.shop.duplicate(true)
	check(run.refresh().is_empty(), "refresh unlocked offers")
	for i in [0, 2, 4, 5]: check(run.shop[i] == shelf[i], "locked slot retained: %d" % i)
	var restored := ArenaRun.new(); restored.auto_save = false
	check(restored.restore(run.snapshot()) and restored.shop == run.shop, "multiple locks survive save")
	# Nine original toads chain through two stars into one elite; every old
	# two-star save retains its prototype, investment and identity.
	for family in ArenaRules.FAMILIES.size():
		run = fresh()
		var kept := run._recruit(family, 1, 6)
		run.deploy(kept.uid, Vector2(27, 32))
		var old := run.snapshot(); old.version = 9
		check(restored.restore(old) and restored.army == run.army, "old two-star save preserved: %d" % family)
		for i in 2: run._recruit(family, 1, 6)
		run.combine_ready()
		check(run.army.size() == 1 and kept.rank == 2 and kept.uid == run.army[0].uid, "three-star recipe: %d" % family)
		check(restored.restore(run.snapshot()) and restored.army == run.army, "three-star save: %d" % family)
	run = fresh()
	var kept := run._recruit(5, 1, 6)
	run.deploy(kept.uid, Vector2(27, 32))
	run._recruit(5, 1, 6)
	var battle := ArenaPveMatch.new(); battle.run = run; battle.rendered = false
	add_child(battle); battle.set_process(false); battle._world_parent = self; battle.prepare()
	var live: GameUnit = battle.world.unit_rows().filter(func(u): return u.get_meta("arena_placement").get("run_uid", 0) == kept.uid)[0]
	var stats := live.stats.duplicate(true)
	var hp := live.hp
	check(battle.start(), "start encounter")
	run.shop[0] = {"family": 5, "rank": 1, "locked": false}
	check(run.buy(0).is_empty() and kept.rank == 2, "combat purchase completes elite")
	check(live.stats == stats and live.hp == hp and live.get_meta("arena_placement").rank == 1, "combat actor keeps old rank and stats")
	check(not run.sell(kept.uid).is_empty(), "combat cannot sell deployed actor")
	var bench := run._recruit(0, 0, 1)
	check(run.sell(bench.uid).is_empty() and run.unit(bench.uid).is_empty(), "combat can sell bench")
	check(run.train().is_empty() and run.refresh().is_empty(), "combat can buy XP and reroll")
	check(not run.can_undo(), "combat spending cannot undo settled combat")
	run.gold = 0
	run.resolve(1, 20, [10, 20])
	check(run.gold == 10 and run.last_result.income.interest == 5 and run.last_result.income.victory == 0 and run.last_result.income.streak == 0, "loss earns base plus committed interest only")
	bank = run.gold
	run.resolve(1, 20, [10, 20])
	check(run.gold == bank and run.lives == 2, "loss settles exactly once")
	check(restored.restore(run.snapshot()), "paid loss can be restored")
	run.advance()
	check(run.wave == 2 and run.experience() == 6 and run.free_refresh, "loss advances wave with XP and free refresh")
	battle.prepare()
	live = battle.world.unit_rows().filter(func(u): return u.get_meta("arena_placement").get("run_uid", 0) == kept.uid)[0]
	check(live.get_meta("arena_placement").rank == 2 and live.max_hp == ArenaRules.elite_health(hp), "elite applies next round")
	var elite := live.stats.duplicate(true)
	check(ArenaUnitInfo.values(kept.prototype, null, 5, 2).armor == live.stats.armor, "bench preview matches elite armor")
	check(is_equal_approx(elite.dmg_min, stats.dmg_min * 1.5), "elite improves attack damage")
	check(ArenaUnitInfo.values(kept.prototype, null, 5, 2).max_hp == live.max_hp, "bench preview matches elite health")
	battle.prepare()
	check(live.stats == elite, "elite modifiers never accumulate")
	battle.queue_free()
	# The Trials clock resolves an unfinished fight as a paid loss at two
	# minutes. Pausing cannot expire it, and settlement cannot fire twice.
	run = fresh(); run._recruit(0, 0, 1); run.arrange()
	var timed := ArenaPveMatch.new(); timed.run = run; timed.rendered = false
	add_child(timed); timed.set_process(false); timed._world_parent = self; timed.prepare()
	check(timed.start(), "start timed encounter")
	timed.last_damage_at = 119.0
	timed.world.time = 120.0 - GameUnit.TICK
	timed._process(0)
	check(timed.phase == ArenaMatch.Phase.FIGHT and run.history.is_empty(), "no timeout before two minutes")
	timed.toggle_pause()
	timed._process(30)
	check(timed.phase == ArenaMatch.Phase.PAUSED and run.history.is_empty(), "paused time does not expire battle")
	timed.toggle_pause()
	timed.world.time = 120.0
	timed._process(0)
	check(run.stage == "result" and run.lives == 2 and run.last_result.winner != 0, "two minutes resolves as a player loss")
	check(run.last_result.gold == 10 and run.last_result.income.interest == 5 and run.last_result.income.victory == 0, "timeout earns defeat income")
	bank = run.gold
	timed._process(5)
	check(run.gold == bank and run.history.size() == 1, "timeout settles exactly once")
	run.advance()
	check(run.wave == 2 and run.stage == "prepare", "timeout advances to next wave")
	timed.queue_free()
	# Every completed wave advances, including camp and final-wave defeats.
	for wave in [5, 30]:
		run = fresh(); run.wave = wave; run._recruit(0, 0, 1); run.arrange(); run.start_battle(); run.resolve(1, 20, [10, 20])
		check(run.gold > 100 and run.lives == 2, "late loss pays income")
		if wave == 5:
			run.advance(); check(run.stage == "reward", "defeated camp wave still offers reward")
			run.choose_reward(0); check(run.wave == 6, "camp advances after loss")
		else:
			check(run.stage == "won" and restored.restore(run.snapshot()), "surviving final wave completes expedition and saves")
	check(hash(GameData.db.tables) == native, "campaign prototypes remain immutable")
	print("ARENA_LIVE_SHOP ", checks, " checks; failures=", failures)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
