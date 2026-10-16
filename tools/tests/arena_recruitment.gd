extends Node
const Fixture = preload("arena_fixture.gd")
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
	var restored := ArenaRun.new()
	restored.auto_save = false
	for seed_value in range(6100, 6130):
		run.begin(seed_value)
		check(run.army.is_empty() and run.deployed_count() == 0 and run.next_uid == 1, "no starting creatures")
		check(run.gold == ArenaRules.OPENING_GOLD and run.shop.size() == 6, "opening budget and six offers")
		var families := {}
		for offer in run.shop:
			families[offer.family] = true
			check(int(offer.rank) == 0, "opening forms are base recruits")
		check(families.size() == 6, "every family can be chosen at the start")
		check(not run.start_battle().is_empty(), "empty army cannot enter battle")
		check(restored.restore(JSON.parse_string(JSON.stringify(run.snapshot()))), "empty opening saves and loads")
		check(restored.army.is_empty() and restored.shop == JSON.parse_string(JSON.stringify(run.shop)) and restored.gold == ArenaRules.OPENING_GOLD, "load never grants a free company")
		run.refresh(); restored.refresh()
		check(run.shop == restored.shop and run.shop.size() == 5, "later seeded shops and save RNG agree")
		while run.spending_error(run.refresh_cost()).is_empty(): run.refresh()
		check(run.gold >= ArenaRules.MIN_RECRUIT_COST and run.army.is_empty(), "refresh cannot spend the last recruit budget")
		var index := -1
		for i in run.shop.size():
			if run.purchase_error(i).is_empty(): index = i; break
		check(index >= 0, "an empty company can still afford an offer")
		var before := run.gold
		var cost := run.offer_cost(run.shop[index])
		check(run.buy(index).is_empty() and run.gold == before - cost and run.bench_count() == 1, "first creature is bought into reserves")
		check(not run.start_battle().is_empty(), "buying does not deploy for the player")
		check(run.deploy(run.army[0].uid, Vector2(25, 32)).is_empty(), "bought recruit can be placed")
		run.undo(); run.undo()
		check(run.army.is_empty() and run.gold == before, "undo can return to the empty purchased opening")
	run.begin(6199)
	run.lock_offer(5)
	var held := int(run.shop[5].family)
	run.refresh()
	check(run.shop.size()==5 and run.shop.any(func(o):return o.locked and int(o.family)==held),"opening sixth-slot lock survives a five-offer refresh")
	run.begin(6200)
	check(run.train().is_empty(), "early training remains available")
	check(not run.train().is_empty() and run.gold == 5, "training preserves a recruit budget")
	check(run.shop.any(func(offer): return run.offer_cost(offer) <= ArenaRules.MIN_RECRUIT_COST), "training leaves an affordable opening recruit")
	Fixture.begin(run, 6202)
	var legacy := run.snapshot(); legacy.version = 4; legacy.pact = ""; legacy.pact_rank = 0
	check(restored.restore(legacy) and restored.army == run.army, "existing expeditions retain their purchased or legacy army")
	# Every three-family opening is affordable and viable against the first wave.
	var match_state := ArenaPveMatch.new()
	match_state.rendered = false; match_state.run = run
	add_child(match_state); match_state.set_process(false)
	match_state._world_parent = self
	var fights := 0
	for a in 6:
		for b in range(a + 1, 6):
			for c in range(b + 1, 6):
				run.begin(6300 + fights)
				for family in [a, b, c]:
					var offer: Dictionary = run.shop.filter(func(entry): return int(entry.family) == family)[0]
					check(run.buy(run.shop.find(offer)).is_empty(), "three-family opening can be bought")
				run.arrange(); match_state.prepare()
				check(match_state.start(), "purchased opening starts native combat")
				for tick in 5500:
					if match_state.phase != ArenaMatch.Phase.FIGHT: break
					match_state.simulate_tick()
				check(match_state.winner == 0, "first wave accepts composition %d/%d/%d" % [a, b, c])
				fights += 1
	check(hash(GameData.db.tables) == native, "native prototype data unchanged")
	print("ARENA_RECRUITMENT ", checks, " checks; native_fights=", fights, "; failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
