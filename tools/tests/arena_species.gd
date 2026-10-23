extends Node
## Save migration, recognizable ranks, real mitigation and copy transactions.
var checks := 0
var failures := []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func _ready() -> void:
	var native := hash(GameData.db.tables)
	var run := ArenaRun.new(); run.auto_save = false; run.begin(7429)
	var restore := ArenaRun.new(); restore.auto_save = false
	var tiers := [0,0,0,0,0]
	var bodies := {}
	for family in ArenaRules.ACTIVE_FAMILIES:
		var rule: Dictionary = ArenaRules.FAMILIES[family]
		tiers[rule.cost-1] += 1
		check(rule.cost >= 1 and rule.cost <= 5, "bounded shop price %d" % family)
		check(not String(rule.forms[0]).begins_with("human"), "no same-face human recruits %d" % family)
		var first := GameData.db.find("monster_prototypes", rule.forms[0])
		var silhouette: String = first.get("base_race", "")
		# The seer deliberately shares the woodsfolk rig, with a different kit,
		# price and authored leader palettes. No other duplicate role is allowed.
		if bodies.has(silhouette):
			check(bodies[silhouette] == 11 and family == 29 and rule.role == "Magic" and ArenaRules.FAMILIES[11].role == "Ranged", "approved woodsfolk caster role " + silhouette)
		else:
			bodies[silhouette] = family
		var before := {}
		for rank in 3:
			var id := ArenaRules.prototype(family, rank)
			var proto := GameData.db.find("monster_prototypes", id)
			check(not proto.is_empty(), "native form exists " + id)
			check(proto.get("base_race", "") == silhouette, "recognizable species at every star " + id)
			var values := ArenaUnitInfo.values(id, null, family, rank)
			if rank > 0:
				check(values.hp > before.hp and values.min > before.min, "promotion improves health and output %d:%d" % [family,rank])
			check(Array(values.armor).all(func(a): return a >= 0 and a <= 45), "bounded typed armor %d:%d" % [family,rank])
			before = values
			run.army.clear(); run.shop.clear()
			for n in 6: run.shop.append({"family":family,"rank":0,"locked":false})
			run._recruit(family,rank,rule.cost*int(pow(3,rank))); run.arrange()
			var saved := run.snapshot()
			check(restore.restore(saved) and restore.snapshot() == saved, "rank survives a round trip %d:%d" % [family,rank])
			for language in ["en","ru","de"]:
				RemakeText.lang = language
				check(not ArenaRules.title(id).contains(id), "localized native name "+id+language)
		RemakeText.lang = "en"
		# A full reserve must still merge on the third purchase.
		run.begin(7429); run.gold = 200; run.army.clear()
		for n in 6: run._recruit((family+1)%ArenaRules.FAMILIES.size(),2,45)
		for n in 2: run._recruit(family,0,rule.cost)
		run.reserve_slots(); run.shop[0] = {"family":family,"rank":0,"locked":false}
		check(run.buy(0).is_empty(), "third copy purchases on a full bench %d" % family)
		check(run.army.filter(func(e):return e.family==family and e.rank==1).size()==1, "third copy merges immediately %d" % family)
	check(tiers.all(func(n):return n >= 5), "at least five species in every price tier")
	# Validate every formerly published form, including families 28 and 29,
	# then preserve the visible species, rank, investment and reserve location.
	for version in [10,11,12]:
		for family in ArenaRules.saved_family_count(version):
			for rank in 3:
				run.begin(7429); run.army.clear()
				var entry := run._recruit(0,rank,27); entry.bench_slot = 4
				var saved := run.snapshot(); saved.version = version
				saved.army[0].family = family
				saved.army[0].prototype = ArenaRules.saved_prototype(version,family,rank)
				for offer in saved.shop: offer.family=family; offer.locked=true
				var unchanged := saved.duplicate(true)
				var expected := ArenaRules.migrated_family(saved.army[0].prototype)
				check(restore.restore(saved), "loads legacy %d:%d:%d" % [version,family,rank])
				check(saved == unchanged, "migration leaves input immutable")
				if restore.army.is_empty(): continue
				check(restore.army[0].family==expected and restore.army[0].rank==rank and restore.army[0].investment==27 and restore.army[0].bench_slot==4, "migration preserves progress and slot")
				check(restore.restore(restore.snapshot()), "migrated save round trip")
	# Real Combat.absorb covers all seven channels and the Trials 80% cap.
	for family in [0,6,9,14,19,22,24,25]:
		run.begin(7429); run.army.clear(); run._recruit(family,2,45); run.arrange()
		var battle := ArenaPveMatch.new(); battle.run=run; battle.rendered=false; battle.drives_clock=false
		add_child(battle); battle.set_process(false); battle.set_physics_process(false); battle._world_parent=self
		battle.prepare()
		var unit: GameUnit = battle.world.unit_rows()[0]
		for raw in [12.0,30.0,70.0]:
			for channel in 7:
				var types := PackedFloat32Array([0,0,0,0,0,0,0]); types[channel]=1
				var actual := battle.world.combat.absorb(unit,raw,types)
				check(actual >= raw*0.2-0.001 and actual <= raw+0.001, "native mitigation remains damageable %d:%d" % [family,channel])
		battle.queue_free(); await get_tree().process_frame
	check(hash(GameData.db.tables)==native, "campaign database is unchanged")
	print("ARENA_SPECIES ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
