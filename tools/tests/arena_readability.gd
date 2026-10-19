extends Node
var checks := 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ", label)
func fresh() -> ArenaRun:
	var run := ArenaRun.new(); run.auto_save = false; run.begin(7721); run.gold = 100
	return run
func _ready() -> void:
	var run := fresh()
	var field := run._recruit(0, 0, 1)
	run._auto_deploy(field)
	var reserve := run._recruit(1, 0, 1)
	run._touch()
	check(run.bench(field.uid, 5).is_empty() and run.reserve_slots()[5].uid == field.uid, "withdraw uses requested reserve slot")
	check(run.reserve_slots()[0].uid == reserve.uid and run.reserve_slots()[1].is_empty(), "withdraw preserves gaps and occupied reserves")
	var loaded := fresh()
	check(loaded.restore(JSON.parse_string(JSON.stringify(run.snapshot()))) and loaded.reserve_slots()[5].uid == field.uid, "reserve position survives JSON save")
	run.undo()
	check(run.unit(field.uid).deployed and run.reserve_slots()[5].is_empty(), "withdraw undo restores placement")
	run.swap_from_bench(reserve.uid, field.uid)
	check(run.unit(reserve.uid).deployed and run.reserve_slots()[0].uid == field.uid, "swap retains the incoming reserve slot for outgoing unit")
	check(not run.bench(reserve.uid, 0).is_empty() and run.unit(reserve.uid).deployed, "occupied target cannot discard a unit")
	for family in [11, 27]:
		run = fresh()
		for f in [0, 1, 2]: run._auto_deploy(run._recruit(f, 0, 1))
		for f in [3, 4, 5, 6, 8, 9]: run._recruit(f, 0, 1)
		run._recruit(family, 0, 3); run._recruit(family, 0, 3); run._touch()
		check(run.bench_count() == run.bench_limit(), "full reserve archer fixture")
		run.shop[0] = {"family":family, "rank":0, "locked":false}
		check(run.buy(0).is_empty(), "third matching archer can be bought with full reserves")
		var copies := run.army.filter(func(e): return e.family == family)
		check(copies.size() == 1 and copies[0].rank == 1 and run.bench_count() == 7, "three archers merge immediately and release reserve space")
		var next := fresh()
		check(next.restore(run.snapshot()) and next.army == run.army, "full reserve evolution saves without changing identities")
	run = fresh(); run._recruit(0, 0, 1)
	run.shop = [{"family":0,"rank":0,"locked":false},{"family":0,"rank":0,"locked":false},{"family":1,"rank":0,"locked":false}]
	check(run.shop_completes_upgrade(0) and run.shop_completes_upgrade(1), "one owned plus two offers highlights both")
	check(not run.shop_completes_upgrade(2), "unrelated recruit does not inherit upgrade cue")
	run.buy(0)
	check(run.shop_completes_upgrade(1), "second purchase remains highlighted after first")
	run.buy(1)
	check(run.army.size() == 1 and run.army[0].rank == 1, "collective highlight predicts actual evolution")
	for family in ArenaRules.PREVIOUS_FORMS:
		for rank in 3:
			run = fresh(); var entry := run._recruit(family, rank, 9); run._touch()
			var save := run.snapshot(); save.version = 11
			save.army[0].prototype = ArenaRules.PREVIOUS_FORMS[family][rank]
			loaded = fresh()
			var species := ArenaRules.migrated_family(ArenaRules.PREVIOUS_FORMS[family][rank])
			check(loaded.restore(save) and loaded.army[0].prototype == ArenaRules.prototype(species, rank) and loaded.army[0].investment == 9, "schema 11 replacement retains rank and investment")
	check(ArenaRules.prototype(8,0) != "batdarkm12", "only one bat can start a shop chain")
	for pair in [["dragonbrownm16","dragonbluem14"],["dragonbluem14","dragongreenm12"],["driadsnowa7","driadgreena7"],["driaddarka7","driaddarkm9"]]:
		check(ArenaAppearance.info(pair[0]).texture != ArenaAppearance.info(pair[1]).texture, "original palettes distinguish creature forms")
	var banner := ArenaRoundBanner.new(); add_child(banner)
	run = fresh(); banner.update_round(run, 0, 4, false)
	run.stage = "fight"; banner.update_round(run, 0.05, 4, false)
	run.last_result = {"wave":1,"winner":1,"health_lost":7}
	banner.update_round(run, 0.05, 4, false)
	check(banner.heading.text == run.round_title(), "very short fight cannot replace title in same frame")
	banner.update_round(run, 1, 4, false)
	check(banner.heading.text == RemakeText.t("Defeat") and banner.visible, "short fight result follows stable start notice")
	banner.update_round(run, 2.1, 4, false)
	check(not banner.visible, "result disappears while other boards still fight")
	run.stage = "result"; banner.update_round(run, 0.1, 4, false)
	check(not banner.visible, "league result does not replay own result")
	var income := ArenaRoundBanner.income_text({"base":5,"interest":0,"victory":1,"streak":0,"total":6})
	check(not income.contains("·") and not income.contains("+0"), "income omits separator dots and zero bonuses")
	for key in ["Owned: %d","Recruit: %s","Choose an empty reserve slot.","The highlighted shop copies complete an evolution.","+%d base gold","+%d interest","+%d victory","+%d streak","%d total gold","Show the current mode and location in Discord. Requires the Discord desktop app. No additional setup is needed. Off clears the activity."]:
		check(RemakeText.TEXTS.has(key) and RemakeText.TEXTS[key].size() == 2 and not RemakeText.TEXTS[key].has(""), "new message has Russian and German: " + key)
	var sent := []
	var view := ArenaOnlineView.new(); view.connected = true
	view.submit = func(action,args): sent.append([action,args])
	view.bench(47, 6)
	check(sent == [["bench",[47,6]]], "online withdrawal transmits exact reserve slot")
	banner.free()
	print("ARENA_READABILITY checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
