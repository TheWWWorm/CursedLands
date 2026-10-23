extends Node
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func fresh() -> ArenaRun:
	var run := ArenaRun.new(); run.auto_save = false; run.begin(42731)
	return run

func recruit(run: ArenaRun, family := 0, deployed := true) -> Dictionary:
	var entry := run._recruit(family, 0, int(ArenaRules.FAMILIES[family].cost))
	entry.deployed = deployed
	entry.point = [25.0, 22.0 + run.deployed_count() * 4.0]
	return entry

func give(run: ArenaRun, kind: String, carrier := 0) -> int:
	var uid := run.next_item_uid; run.next_item_uid += 1
	run.items.append({"uid":uid, "kind":kind, "unit_uid":carrier})
	run._sync_items()
	return uid

func json_copy(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))

func synthetic_round(run: ArenaTournamentRun, human_wins := true) -> void:
	run.stage = "fight"
	run.resolve(0 if human_wins else 1, 1.0, [10,10], [3,3])
	for index in run.pairings.size():
		if int(run.pairings[index].a) != 0: run.record_duel(index, 0, [3,3])

func _ready() -> void:
	var run := fresh()
	var a := recruit(run); var b := recruit(run, 1)
	var fang := give(run, "fang"); var ward := give(run, "ward")
	check(run.equip_item(fang, int(a.uid)).is_empty() and run.item_for(a.uid) == "fang", "equip owned item")
	check(run.equip_item(ward, int(a.uid)).is_empty() and run.item_for(a.uid) == "ward" and int(run.items[0].unit_uid) == 0, "displaced equipment returns to stash")
	check(run.equip_item(ward, int(b.uid)).is_empty() and run.item_for(a.uid).is_empty() and run.item_for(b.uid) == "ward", "move item to another carrier")
	var unchanged := run.snapshot()
	check(not run.equip_item(9999, int(a.uid)).is_empty() and not run.equip_item(fang, 9999).is_empty() and run.snapshot() == unchanged, "invalid ownership and carrier are atomic")
	run.undo()
	check(run.item_for(a.uid) == "ward" and run.item_for(b.uid).is_empty(), "undo restores carrier and displaced stash")
	run.equip_item(fang, int(b.uid)); run.sell(int(b.uid))
	check(int(run.items[0].unit_uid) == 0 and run.items.size() == 2, "selling conserves equipment")
	run.undo()
	check(run.item_for(b.uid) == "fang" and not run.unit(b.uid).is_empty(), "sale undo restores exactly one item")
	check(run.unit(a.uid).get("item") == "ward" and run.unit(b.uid).get("item") == "fang", "army snapshots carry synchronized kinds")
	var formation := ArenaTournamentRun.formation_for(run.army, 1)
	check(formation.size() == 2 and formation[0].item == "ward" and formation[1].item == "fang", "mirrored and ghost formations retain equipment")
	var copy := fresh()
	check(copy.restore(json_copy(run.snapshot())) and copy.items == run.items and copy.item_for(b.uid) == "fang", "JSON save preserves item identity and assignment")
	var saved := copy.snapshot()
	for corruption in ["unknown", "duplicate_uid", "duplicate_carrier", "missing_carrier", "partial", "offers"]:
		var bad := saved.duplicate(true)
		match corruption:
			"unknown": bad.items[0].kind = "missing"
			"duplicate_uid": bad.items[1].uid = bad.items[0].uid
			"duplicate_carrier": bad.items[1].unit_uid = bad.items[0].unit_uid
			"missing_carrier": bad.items[0].unit_uid = 9999
			"partial": bad.erase("item_reward_round")
			"offers": bad.item_offers = ["fang", "fang", "fang"]
		check(not copy.restore(bad) and copy.snapshot() == saved, "reject corrupt equipment atomically: " + corruption)
	var forged := saved.duplicate(true); forged.army[0].item = "storm"
	check(copy.restore(forged) and copy.army[0].item == "ward", "derived row cannot forge equipment")
	var old := saved.duplicate(true); old.version = 13
	for key in ["items", "item_offers", "next_item_uid", "item_reward_round"]: old.erase(key)
	check(copy.restore(old) and copy.items.is_empty() and copy.army.all(func(entry): return not entry.has("item")), "old saves start empty and discard stale derived kinds")
	# Two complete evolution stages return every consumed carrier's item.
	run = fresh(); a = recruit(run)
	for index in 8: recruit(run, 0, false)
	for index in run.army.size(): give(run, "fang" if index == 0 else "ward", int(run.army[index].uid))
	run._checkpoint(); run.combine_ready(); run._touch()
	check(run.army.size() == 1 and run.army[0].rank == 2 and run.army[0].uid == a.uid, "nine copies combine through both ranks and retain deployed identity")
	check(run.items.size() == 9 and run.item_for(a.uid) == "fang" and run.items.filter(func(item): return int(item.unit_uid) == 0).size() == 8, "both merge stages conserve all equipment")
	run.undo()
	check(run.army.size() == 9 and run.items.filter(func(item): return int(item.unit_uid) > 0).size() == 9, "merge undo restores all original carriers")
	run = fresh(); a = recruit(run); recruit(run, 8); recruit(run, 9); b = recruit(run, 0, false)
	for family in range(1,8): recruit(run, family, false)
	fang = give(run, "fang", int(a.uid)); ward = give(run, "ward", int(b.uid))
	run.shop[0] = {"family":0,"rank":0,"locked":false}
	check(run.bench_count() == run.bench_limit() and run.buy(0).is_empty(), "buy completes evolution with full reserves")
	check(run.unit(a.uid).rank == 1 and run.item_for(a.uid) == "fang" and run.items[1].unit_uid == 0 and run.items.size() == 2, "automatic purchase evolution retains kept item and stashes consumed item")
	run.undo()
	check(run.bench_count() == run.bench_limit() and run.item_for(b.uid) == "ward" and run.unit(a.uid).rank == 0, "full-reserve purchase undo conserves item assignments")
	# Reward RNG is independent of shop rolls and stable through save/undo.
	run = fresh(); a = recruit(run)
	var rng_before := run.rng.state
	for round_number in [1,2,4,6,7,8,9,11]: run.offer_items_after(round_number)
	check(run.item_offers.is_empty(), "only scheduled rounds offer items")
	run.wave = 4; run.offer_items_after(3)
	check(run.item_offers.size() == 3 and run.item_offers == ArenaItems.offers(run.run_seed,3) and run.rng.state == rng_before, "three deterministic choices do not consume shop RNG")
	check(run.item_offers[0] != run.item_offers[1] and run.item_offers[1] != run.item_offers[2] and run.item_offers[0] != run.item_offers[2], "reward choices are distinct")
	check(copy.restore(json_copy(run.snapshot())) and copy.item_offers == run.item_offers, "pending reward survives save")
	var choice := run.item_offers[1]
	check(run.choose_item(1).is_empty() and run.items.size() == 1 and run.items[0].kind == choice and run.item_offers.is_empty(), "choice grants one stashed item")
	check(not run.choose_item(1).is_empty() and run.items.size() == 1, "replayed choice cannot duplicate an item")
	run.undo()
	check(run.items.is_empty() and run.item_offers.size() == 3 and run.next_item_uid == 1, "choice undo restores deterministic offer without creating ownership")
	var first := run.item_offers[0]
	check(run.start_battle().is_empty() and run.items.size() == 1 and run.items[0].kind == first and run.item_offers.is_empty(), "early start stashes first pending choice")
	unchanged = run.snapshot()
	check(not run.equip_item(int(run.items[0].uid), int(a.uid)).is_empty() and not run.choose_item(0).is_empty() and run.snapshot() == unchanged, "combat locks choices and carriers")
	run = fresh(); run.wave = 6; run.offer_items_after(5); run.preparation_left = 0
	check(run.start_battle(true).is_empty() and run.items.size() == 1, "empty timed-out company keeps pending reward")
	run = fresh(); a = recruit(run); b = recruit(run, 1, false); fang = give(run, "fang", int(b.uid)); run.start_battle()
	check(run.sell(int(b.uid)).is_empty() and run.items.size() == 1 and int(run.items[0].unit_uid) == 0, "combat reserve sale returns equipment")
	# All surviving seats earn the same number of rewards, independent of win.
	var league := ArenaTournamentRun.new(); league.auto_save = false; league.begin(90172)
	for round_number in 15:
		synthetic_round(league, false)
		if ArenaItems.reward_round(league.wave):
			check(league.item_offers.size() == 3 and league.rivals.all(func(bot): return bot.item_offers.size() == 3), "all surviving winners and losers earn milestone %d" % league.wave)
			for player in league.alive_players(): league.company(player).settle_item_choice()
		league.lives = 100; league.rival_health.fill(100)
		if round_number < 14: league.advance()
	check(league.items.size() == 4 and league.rivals.all(func(bot): return bot.items.size() == 4), "equal item budgets after rounds 3, 5, 10 and 15")
	var restored := ArenaTournamentRun.new(); restored.auto_save = false
	check(restored.restore(json_copy(league.snapshot())) and restored.items == league.items and restored.rivals[0].items == league.rivals[0].items, "tournament worker snapshot preserves all inventories")
	var no_more := league.snapshot(); league.record_duel(0,0,[3,3]); league.resolve(0,1.0,[10,10],[3,3])
	check(league.items.size() == no_more.items.size() and league.item_offers.is_empty(), "reward watermark prevents repeated settlement from paying items twice")
	var old_league := league.snapshot(); old_league.wave = 40; old_league.last_result.wave = 40; old_league.version = 13
	for data: Dictionary in [old_league] + old_league.rivals:
		data.version = 13
		for offer: Dictionary in data.shop:
			if int(offer.family) >= 28: offer.family = 0
		for key in ["items", "item_offers", "next_item_uid", "item_reward_round"]: data.erase(key)
	check(restored.restore(json_copy(old_league)) and restored.item_reward_round == 40 and restored.rivals.all(func(bot): return bot.item_reward_round == 40), "late old tournament uses actual round for every migration watermark")
	for player in restored.alive_players(): restored.company(player).offer_items_after(40)
	check(restored.items.is_empty() and restored.item_offers.is_empty() and restored.rivals.all(func(bot): return bot.items.is_empty() and bot.item_offers.is_empty()), "old saves receive no accumulated milestone rewards")
	restored.advance()
	check(restored.wave == 41 and restored.item_offers.is_empty(), "advancing migrated result does not award old round")
	for player in restored.alive_players(): restored.company(player).offer_items_after(45)
	check(restored.item_offers.size() == 3 and restored.rivals.all(func(bot): return bot.item_offers.size() == 3), "future milestone works after migration")
	league = ArenaTournamentRun.new(); league.auto_save = false; league.begin(90173); league.wave = 3; league.lives = 1; league._choose_pairings()
	synthetic_round(league, false)
	check(league.lives == 0 and league.item_offers.is_empty() and league.rivals.all(func(bot): return bot.item_offers.size() == 3), "only survivors receive milestone reward")
	# Bots choose the same public rewards and avoid giving spell-only gear to a fighter.
	run = fresh(); a = recruit(run, 0); b = recruit(run, 3)
	give(run, "echo"); give(run, "berserker"); run.wave = 4; run.offer_items_after(3)
	rng_before = run.rng.state
	ArenaBotPlanner.equip(run)
	check(run.items.size() == 3 and run.item_offers.is_empty() and run.rng.state == rng_before, "bot picks once without extra rewards or shop randomness")
	check(run.item_for(b.uid) == "echo" and run.item_for(a.uid) != "echo", "bot assigns Echo Rune to offensive caster")
	var assigned := run.items.duplicate(true); ArenaBotPlanner.equip(run)
	check(run.items == assigned, "bot carrier assignment is deterministic and stable")
	run = fresh(); recruit(run,3); recruit(run,5); recruit(run,13)
	give(run,"berserker"); give(run,"echo")
	ArenaBotPlanner.equip(run)
	check(run.items[0].unit_uid == 0 and int(run.items[1].unit_uid) > 0, "bot stashes Berserker Charm instead of silencing a caster")
	print("ARENA_EQUIPMENT ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
