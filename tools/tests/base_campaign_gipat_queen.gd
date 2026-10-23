extends "base_campaign_gipat_support.gd"

func _ready() -> void:
	await run()

func run() -> void:
	boot(); s.state.god_modes[0] = 1
	var source := 3
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--source="): source = clampi(arg.trim_prefix("--source=").to_int(),1,3)
	await enter("gz5g"); use(4525,false); use(4524,false); use(4523,false)
	check(value("q.gz5g.q22g") == 0,"all poison sources reject use before the dragon gives poison")
	await offer("bz3g","b.bz3g.Dr20","q.gz5g.q22g")
	await enter("gz5g"); start(["VTriger#0#4","VCheck#0#76","VCheck#0#81","VCheck#0#93","VCheck#0#101","VTriger#0#107","VCheck#0#123","VCheck#0#126"]); ticks(30)
	for id: int in [4525,4524,4523]:
		var p: Vector3 = s.world.objects[id].get_meta("ei").position; teleport(Vector2(p.x,p.y))
	await roundtrip("base_gipat_queen_before_poison",["q.gz5g.q22g","q.gz5g.q22g.4","q.gz5g.q22g.6","q.gz5g.q22g.8"],["dragonpoison"])
	use([4525,4524,4523][source-1]); ticks(30)
	check(not s.state.quest_items.has("dragonpoison"),"ordinary source use consumes the single poison")
	for i in 3:
		check(value("q.gz5g.q22g."+str(4+i*2)) == (2 if i == source-1 else 3),"source "+str(i+1)+" records its authored chosen/excluded branch")
	check(s.world.units.has(1000027) and not s.world.units.has(14),"original source replaces the healthy queen with its weakened authored actor")
	check(value("q.gz5g.q22g.1") == 1,"queen replacement is not mistaken for a kill")
	await roundtrip("base_gipat_queen_poisoned",["q.gz5g.q22g","q.gz5g.q22g.1"])
	arm("q.gz5g.q22g"); kill([1000027]); ticks(12)
	check(value("q.gz5g.q22g.1") == 2,"ordinary weakened-queen death completes her objective")
	if source != 3:
		check(value("q.gz5g.q22g") == 1,"surviving small creatures still block cave completion after the queen dies")
		var small := group_ids("Scrabs"); kill(small)
	quest("q.gz5g.q22g","cave queen and brood")
	await enter("bz3g"); await complete("b.SKD.Dr22")
	check(value("q.gz9g.q26g") == 1,"actual dragon return grants the old Hadagan camp mission")
	await enter("gz9g"); start(["VCheck#0#64","VCheck#0#74","VCheck#0#77"])
	check(value("q.gz9g.q26g") == 1,"camp quest waits for its physical note")
	arm("q.gz9g.q26g"); use(2065); quest("q.gz9g.q26g","old Hadagan report")
	check(s.state.quest_items.has("codedhadagannote"),"headless statue yields the coded Hadagan report")
	await enter("bz2g"); await complete("b.witch.z26")
	await roundtrip("base_gipat_queen_complete",["q.gz5g.q22g","q.gz9g.q26g","b.SKD.Dr22","b.witch.z26"])
	await finish_gipat("BASE_CAMPAIGN_GIPAT_QUEEN","Prepared dead-city arrival offer, actual Dr20 dialogue grants q22g/poison; normal poison use at selected source (1/2/3), actual replacement queen, surviving-brood requirement, Dr22 report→q26g original statue note→Witch report. Before/after poison saves, missing poison, excluded alternatives and duplicate rewards. All three source variants selected independently; combat and walking accelerated.")
