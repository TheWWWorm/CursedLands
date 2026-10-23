extends "base_campaign_ingos_support.gd"
## Earlier document recovery and successful living-elder escort are supplied
## as checkpoint input. Gratitude may be pending or already handed in; both
## Shopper branches and all later route objectives are earned here.

func _ready() -> void: run.call_deferred()

func run() -> void:
	ingos()
	var early := OS.get_cmdline_user_args().has("--ingos-early-gratitude")
	var path_roots := ["VCheck#0#199","VCheck#0#225","VTriger#0#75","VCheck#0#165","VCheck#0#108","VCheck#0#144","VCheck#0#279","VCheck#0#254","VCheck#0#273"]
	for pair: Array in [["q.gz13k.q48k",2],["q.gz13k.q46bk",2],["b.YCF.Yc46",2],["b.YCF.Yc47",2 if early else 1],["z.gz13k",2],["z.gz11k",2],["z.bz9k",2]]:
		s.state.set_var(0,pair[0],pair[1])
	s.state.add_item(item_name(27)); s.state.add_item(item_name(40))
	await accept("bz8k","b.Shopper.Tr48","q.gz12k.q49k")
	await enter("gz12k")
	start(["VCheck#0#32","VTriger#0#220","VCheck#0#110"])
	teleport(Vector2(112,326)); near_object(6086)
	check(value("q.gz12k.q49k") == 1 and not has_item(31),"finding the governor's stash does not collect the chest")
	use(6086); ticks(8)
	done("q.gz12k.q49k","normal stash use completes governor-chest recovery")
	check(has_item(31) and int(s.world.levers[6318].state) == 1,"chest collection grants its real item and opens the tiger ambush gate")
	await roundtrip("base_ingos_governor_chest",["q.gz12k.q49k"],[item_name(31),item_name(40)])
	await enter("bz8k"); start(["VCheck#0#16"])
	if early:
		check(value("b.Shopper.Tr49") == 1 and value("b.Shopper.Tr49_1") == 0,"completed gratitude selects Shopper's direct labyrinth offer")
		await complete("b.Shopper.Tr49")
		check(value("q.gz11k.q50ak") == 1,"direct Shopper branch accepts the first secret-path quest")
	else:
		check(value("b.Shopper.Tr49_1") == 1 and value("b.Shopper.Tr49") == 0,"pending gratitude selects Shopper's return-to-dryads branch")
		await complete("b.Shopper.Tr49_1")
		check(value("q.gz11k.q50ck") == 1,"alternate Shopper branch accepts the dryad-camp return")
		await enter("gz11k"); start(path_roots+["VCheck#0#285"])
		use(3705,false)
		check(value("q.gz11k.q50ak") == 0,"labyrinth remains unavailable before the actual dryad return conversation")
		teleport(Vector2(295,90)); ticks(8)
		check(value("q.gz11k.q50ck") == 2,"actual camp approach completes the alternate return objective")
		if not await leave("bz9k"):
			await finish("BASE_CAMPAIGN_INGOS_LABYRINTH","Stopped at alternate dryad return"); return
		ticks(12)
		await complete("b.YCF.Yc47_1")
		check(value("q.gz11k.q50ak") == 1,"actual alternate dryad conversation accepts the labyrinth quest")
	if early:
		await enter("gz11k"); start(path_roots)
	else:
		# Preserve the waiting original q50ck reward watcher installed while
		# that quest was pending. A fresh root cannot reconstruct its history.
		await s.enter_zone("gz11k",1,false); freeze(); ticks(8); await frames()
		check(vm().instances.any(func(i): return i.sname == "VCheck#0#280"),"cached field retains the actual pending alternate-return reward watcher")
	gate("bz9k",false,"accepted labyrinth outing closes the abandoned first dryad camp")
	near_object(3705); use(3705)
	check(value("q.gz11k.q50ak") == 1,"first labyrinth gate alone cannot complete the passage")
	await roundtrip("base_ingos_labyrinth_first_gate",["q.gz11k.q50ak","q.gz11k.q50ak.3"])
	near_object(3706)
	var before_gate := accounting()
	use(3706); ticks(8)
	done("q.gz11k.q50ak","normal second gate use completes the first secret path")
	check(accounting().experience == before_gate.experience+5200,"second gate grants the original 4000 path and 1200 return rewards exactly once")
	check(value("q.gz13k.q50bk") == 1,"first secret path accepts the second valley route")
	if not early: done("q.gz11k.q50ck","alternate return remains complete through its original deferred reward root")
	gate("gz11k_gz13dk",true,"second physical gate opens the real secret route")
	if not await leave("gz11k_gz13dk","gz13k"):
		await finish("BASE_CAMPAIGN_INGOS_LABYRINTH","Stopped at original secret-path travel"); return
	ticks(8); vm().instances.clear()
	start(["VTriger#0#195","VCheck#0#67","VCheck#0#268"])
	near_object(4312)
	check(value("q.gz13k.q50bk") == 1,"finding the valley altar does not finish the second route")
	use(4312)
	check(value("MTIndent") == 1 and value("q.gz13k.q50bk.2") == 2,"actual altar use switches the valley trap and records passage progress")
	teleport(Vector2(216,8)); ticks(8)
	done("q.gz13k.q50bk","actual destination approach completes the second secret path")
	gate("bz10k",true,"second route opens the distant dryad village")
	if not await leave("bz10k"):
		await finish("BASE_CAMPAIGN_INGOS_LABYRINTH","Stopped at distant dryad camp"); return
	start(["VCheck#0#7","VCheck#0#22"])
	if not early:
		check(value("b.YCF.Yc50") == 0,"late-order route still requires the earned gratitude hand-in before the accusation")
		await complete("b.YCF.Yc47"); ticks(8)
	await complete("b.YCF.Yc50")
	check(not has_item(27) and value("b.Magess.Mg50") == 1,"actual dryad accusation consumes the arrow and offers the Magess confrontation")
	await roundtrip("base_ingos_labyrinth_done",["q.gz12k.q49k","q.gz11k.q50ak","q.gz13k.q50bk","b.Magess.Mg50"],[item_name(31),item_name(40)])
	stable("labyrinth branch")
	await finish("BASE_CAMPAIGN_INGOS_LABYRINTH","Prepared document recovery and successful elder escort; their document/arrow and earned gratitude topic are prior input. Tests "+("early completed gratitude→Tr49" if early else "pending gratitude→Tr49_1→q50ck→Yc47_1 and late gratitude hand-in")+", actual q49 stash/ambush, q50ak both physical gates and real secret travel, q50bk altar/camp arrival and actual Yc50 accusation leading to Mg50. Gate/item/final-control negatives, saved continuation and duplicate rewards. No measured objective outcome assigned; not original-runtime parity.")
