extends "base_campaign_gipat_support.gd"

func _ready() -> void:
	await run()

func run() -> void:
	boot(); s.state.god_modes[0] = 1
	var hermit_first := "--hermit-first" in OS.get_cmdline_user_args()
	await offer("bz2g","b.witch.z27","q.gz4g.q29g")
	await enter("gz4g"); start(["VCheck#0#63"]); ticks(30)
	rearm_mob("zone4hadagans.mob",["VCheck#1#18","VCheck#1#26"])
	var soldiers := group_ids("Hadagans")
	check(value("q.gz4g.q29g") == 1,"Hadagan audience waits for the actual patrol encounter")
	arm("q.gz4g.q29g"); teleport(s.world.units[soldiers[0]].pos); ticks(20)
	if not await wait_zone("bz4g"):
		await finish_gipat("BASE_CAMPAIGN_GIPAT_DEPARTURE","Original Hadagan patrol did not transfer the party to its captive scene."); return
	ticks(8); await complete("b.bz4g.Ha29")
	quest("q.gz4g.q29g","Hadagan patrol and captive transfer")
	if not hermit_first: await complete("b.HWLeader.Ha29_1")
	await complete("b.OLiz.Ha29_2")
	await roundtrip("base_gipat_captive_escape_offer",["q.gz4g.q29g","b.bz4g.Ha29","b.OLiz.Ha29_3"])
	await complete("b.OLiz.Ha29_3"); ticks(20)
	if not await wait_zone("gz4g"):
		await finish_gipat("BASE_CAMPAIGN_GIPAT_DEPARTURE","Earned captive escape did not return to its field map."); return
	check(value("q.gz8g.q30g") == 1 and s.state.quest_items.has("lizardclaw00"),"ordinary captive escape grants the lizard route and its key")
	await enter("gz8g"); start(["VCheck#0#176","VCheck#0#183"]); watch("VCheck#0#179",hero())
	use(1712); check(not s.state.quest_items.has("lizardclaw00"),"ordinary lizard bridge control consumes the actual claw")
	arm("q.gz8g.q30g"); teleport(Vector2(52,300)); quest("q.gz8g.q30g","lizard hermit approach")
	await enter("bz5g"); await complete("b.OLiz.L30")
	check(s.state.quest_items.has("dumblever") and value("q.gz8g.q34g") == 1 and value("q.gz8g.q35g") == 1,"actual hermit dialogue provides dam handle and both objectives")
	await enter("gz8g"); start(["VCheck#0#2","VCheck#0#5","VCheck#0#14","VCheck#0#85","VCheck#0#188","VCheck#0#191","VCheck#0#194","VCheck#0#204","VCheck#0#209"])
	use(862); check(value("q.gz8g.q34g") == 1 and not s.state.quest_items.has("dumblever"),"dam mechanism consumes its handle but the falling stone is still required")
	await roundtrip("base_gipat_dam_only",["q.gz8g.q34g","q.gz8g.q34g.2"])
	arm("q.gz8g.q34g"); use(1122); quest("q.gz8g.q34g","dam and stone")
	var ambushers := group_ids("Dkin"); teleport(s.world.units[ambushers[0]].pos); ticks(12)
	check(value("q.gz8g.q35ag") == 1,"actual dragonkin encounter offers the optional treasure objective")
	kill(ambushers.slice(0,ambushers.size()-1)); check(value("q.gz8g.q35g") == 1,"last ambusher blocks leaving the lizards")
	arm("q.gz8g.q35g"); kill([ambushers[-1]]); quest("q.gz8g.q35g","lizard departure ambush")
	arm("q.gz8g.q35ag"); use(1890); quest("q.gz8g.q35ag","lizard island treasure")
	await enter("bz5g"); await complete("b.OLiz.L34")
	await enter("gz4g"); start(["VCheck#0#54","VCheck#0#83","VCheck#0#162","VCheck#0#159"]); watch("VCheck#0#29",hero()); watch("VCheck#0#154",hero())
	gate("gz4g_gz10g",false,"tunnel passage is blocked before its remote mechanism")
	teleport(Vector2(117.621,201.333)); check(value("q.gz4g.q36g") == 1,"finding the closed tunnel does not complete opening it")
	arm("q.gz4g.q36g"); use(1918); teleport(Vector2(117.621,201.333)); quest("q.gz4g.q36g","remote tunnel mechanism")
	gate("gz4g_gz10g",true,"actual remote mechanism opens the tunnel passage")
	arm("q.gz4g.qk9g"); use(999448); quest("q.gz4g.qk9g","succubus bonus chest")
	if not await leave("gz4g_gz10g","gz10g"):
		await finish_gipat("BASE_CAMPAIGN_GIPAT_DEPARTURE","Earned tunnel mechanism failed its ordinary travel route."); return
	ticks(8); vm().instances.clear()
	start(["VTriger#0#2","VCheck#0#6","VCheck#0#9","VCheck#0#17","VCheck#0#33","VCheck#0#42","VCheck#0#79","VCheck#0#85"])
	use(57,false); check(value("q.gz10g.q36ag.11") < 2,"golem control refuses the missing physical key")
	use(46); use(42)
	check(s.state.quest_items.has("golemcenterkey00"),"ordinary crypt chest yields the golem-center key")
	use(45); use(57)
	check(not s.state.quest_items.has("golemcenterkey00") and int(s.world.levers[58].state) == 1,"ordinary keyed golem control consumes its key and activates the machine")
	var fire := group_ids("Felem"); kill(fire)
	ticks(160)
	check(value("q.gz10g.q36ag.12") == 2,"original post-combat delay ends golem hostility")
	var purse := s.state.money; use(44); use(43)
	check(s.state.money == purse+2500,"two optional tunnel crypts award exactly 1000 and 1500 gold")
	await roundtrip("base_gipat_tunnel_treasure",["q.gz10g.q36ag","q.gz10g.q36ag.12","cr1","cr2a"])
	arm("q.gz10g.q36ag"); teleport(Vector2(148,56.5)); teleport(Vector2(130,135)); teleport(Vector2(197.5,113.75)); teleport(Vector2(245,145)); quest("q.gz10g.q36ag","tunnel crossing")
	if not await leave("gz4g_gz10g_exit","gz4g"):
		await finish_gipat("BASE_CAMPAIGN_GIPAT_DEPARTURE","Completed tunnel failed its ordinary return route."); return
	ticks(8); vm().instances.clear(); start(["VCheck#0#88"]); watch("VCheck#0#25",hero())
	arm("q.gz4g.q37g"); teleport(Vector2(245,255)); quest("q.gz4g.q37g","Rick approach")
	if not await leave("bz7g"):
		await finish_gipat("BASE_CAMPAIGN_GIPAT_DEPARTURE","Earned Rick gate failed its ordinary return route."); return
	ticks(8); start(["VCheck#0#12"])
	await complete("b.bz7g.R36"); await complete("b.Rick.R36_3"); await complete("b.Rick.R36_1")
	check(value("b.Rick.R36_2") == 1,"actual lone-hero Rick conversation offers departure")
	await roundtrip("base_gipat_before_ingos",["q.gz4g.q37g","b.Rick.R36_2"])
	await complete("b.Rick.R36_2")
	if not await wait_zone("gz11k"):
		await finish_gipat("BASE_CAMPAIGN_GIPAT_DEPARTURE","Rick departure dialogue did not reach Ingos."); return
	check(s.state.current_party == "" and not s.party_units(0).is_empty(),"original Gipat protagonist reaches playable Ingos")
	check(not s.state.quest_items.has("golemcenterkey00") and not s.state.quest_items.has("lizardclaw00"),"original island departure retains no spent chapter keys")
	await roundtrip("base_gipat_departed",["q.gz4g.q29g","q.gz8g.q30g","q.gz8g.q34g","q.gz8g.q35g","q.gz8g.q35ag","q.gz4g.q36g","q.gz10g.q36ag","q.gz4g.q37g","b.Rick.R36_2"])
	await finish_gipat("BASE_CAMPAIGN_GIPAT_DEPARTURE","Prepared earlier z27 Hadagan offer. Actual q29g patrol/captive scene with commander-first or hermit-first order→q30g keyed lizard route→q34g dam+stone→q35g ambush/q35ag treasure→q36g remote tunnel/qk9g bonus→ordinary tunnel entry→q36ag keyed golem, delayed deactivation and both optional money crypts→ordinary return/q37g Rick passage→R36 scene and dialogue to playable gz11k. Saves, partial gates/groups/controls and duplicate rewards. Walking/combat accelerated; companion farewell branch is separate.")
