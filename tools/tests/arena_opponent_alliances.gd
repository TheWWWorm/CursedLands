extends Node
## Identical opposing companies must receive identical alliance modifiers.
func _ready() -> void:
	var duel := ArenaTournamentBattles.DuelRun.new()
	duel.auto_save = false; duel.begin(7391); duel.training = 126
	for family in [0,1,3,4,5]: duel._recruit(family,0,2)
	duel.arrange()
	duel.opposing_army = duel.army.duplicate(true)
	duel.opponents = ArenaTournamentRun.formation_for(duel.opposing_army,1)
	var battle := ArenaPveMatch.new()
	battle.run = duel; battle.rendered = false; battle.drives_clock = false
	add_child(battle); battle.set_process(false); battle._world_parent = self
	battle.prepare()
	var failures: Array[String] = []
	var checks := 0
	for own: GameUnit in battle.world.unit_rows():
		var placement: Dictionary = own.get_meta("arena_placement")
		if not placement.has("run_uid"): continue
		var enemies := battle.world.unit_rows().filter(func(unit):return unit.get_meta("arena_placement").get("source_uid",0)==placement.run_uid)
		checks += 1
		if enemies.size()!=1 or own.stats!=enemies[0].stats or not is_equal_approx(own.max_hp,enemies[0].max_hp):
			failures.append("opposing alliance symmetry for " + own.info.prototype)
		checks += 1
		if own.stats.dmg_min <= own.get_meta("alliance_base").stats.dmg_min:
			failures.append("both armies receive their beast bonus")
	print("ARENA_OPPONENT_ALLIANCES ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
