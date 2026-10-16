extends Node
## Economy thresholds, early training, native stats and migration boundaries.
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)
func _ready() -> void:
	var native := hash(GameData.db.tables)
	var run := ArenaRun.new()
	run.auto_save = false
	run.begin(31)
	for savings in [0,9,10,19,20,29,30,99]:
		run.gold = savings
		check(run.income_preview().interest == mini(3,savings/10), "interest threshold %d" % savings)
		check(run.income_preview().total == 6+mini(3,savings/10), "transparent total %d" % savings)
	run.gold = 30
	run.start_battle()
	run.gold = 0 # Interest is committed at the start, never the final purse.
	run.resolve(0,12,[20,4])
	check(run.gold == 9 and run.last_result.income.interest == 3,"battle-start interest snapshot")
	run.resolve(0,12,[20,4])
	check(run.gold == 9,"settlement pays exactly once")
	for i in 5:
		run.advance()
		if run.stage == "reward": run.choose_reward(0)
		run.gold = 0
		run.start_battle();run.resolve(0,10,[20,4])
		check(run.last_result.income.streak == (2 if i==4 else 1 if i>=1 else 0),"streak threshold %d" % (i+2))
	run.advance();run.choose_reward(0)
	var bank := run.gold
	run.start_battle();run.resolve(1,10,[4,20]);run.advance()
	check(run.gold == bank and run.income_preview().streak == 0,"defeat breaks streak and grants no income")
	check(run.wave == 7,"retry stays on its wave")
	run.gold = 50
	var old := run.snapshot()
	check(run.train().is_empty() and run.capacity() == 6 and run.gold == 45,"training advances capacity before its normal wave")
	var deployed := run._recruit(0,0,3)
	run.arrange()
	var saved := run.snapshot()
	var restored := ArenaRun.new()
	restored.auto_save = false
	check(restored.restore(saved) and restored.snapshot() == saved,"training and new income save round-trip")
	for key in ["training", "battle_savings"]:
		for invalid in [-1,1.5,"3"]:
			var broken := saved.duplicate(true);broken[key]=invalid
			check(not restored.restore(broken),"reject malformed " + key)
	run.begin(32)
	run.gold = 30
	var before := run.snapshot()
	run.train()
	check(run.wave == 1 and run.capacity() == 4,"army growth is available from wave one")
	run.undo()
	check(run.snapshot() == before,"training is undoable")
	for i in 4: run.train()
	check(run.capacity() == 7 and run.gold == 10,"capacity stops at seven")
	check(not run.train().is_empty() and run.gold == 10,"max training cannot charge again")
	var legacy := run.snapshot();legacy.version=3;legacy.erase("training");legacy.erase("battle_savings")
	check(restored.restore(legacy) and restored.training == 0,"old saves preserve free army growth")
	run.begin(33,1)
	check(run.sale_value(run.army[0]) == 3,"one-star recruits can be exchanged without losing gold")
	var copy := run._recruit(2,0,3);run._recruit(2,0,3);run.combine_ready()
	check(run.sale_value(run.army[1]) == 6,"evolved units retain a partial refund")
	for family in ArenaRules.FAMILIES.size():
		for rank in ArenaRules.FAMILIES[family].forms.size():
			var id := ArenaRules.prototype(family,rank)
			check(ArenaUnitInfo.rank_of(id) == rank,"rank follows evolution: " + id)
			var stats := ArenaUnitInfo.values(id)
			var proto := GameData.db.find("monster_prototypes",id)
			check(stats.attack == int(proto.to_hit),"native attack: " + id)
			check(stats.max == int(proto.damage_min + proto.damage_max),"native damage range: " + id)
			for lang in ["en","ru","de"]:
				RemakeText.lang=lang
				check(not ArenaUnitInfo.summary(id).contains(id),"no prototype IDs in stats")
	RemakeText.lang="en"
	check(hash(GameData.db.tables)==native,"native prototypes are unchanged")
	print("ARENA_ECONOMY ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
