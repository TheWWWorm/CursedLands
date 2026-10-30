extends "base_campaign_gipat_support.gd"

func _ready() -> void:
	await run()

func run() -> void:
	boot(); s.state.god_modes[0] = 1
	if "--gold-refusal" in OS.get_cmdline_user_args():
		await gold_refusal()
	elif "--return-from-ingos" in OS.get_cmdline_user_args():
		await returned_handoff()
	else:
		await farewell()

func gold_refusal() -> void:
	await offer("bz1g","b.elder.s8_2","q.gz9g.q12g")
	start(["VCheck#0#53"])
	check(value("b.elder.s12_1") == 0,"Elder refusal is unavailable before the Smith's warning")
	await complete("b.smith.m12")
	check(value("b.elder.s12_1") == 1 and value("q.gz9g.q12g") == 1,"ordinary Smith warning offers refusal while gold retrieval remains active")
	await roundtrip("base_gipat_gold_warning",["q.gz9g.q12g","b.elder.s12_1"])
	var before := accounting()
	await complete("b.elder.s12_1")
	check(value("q.gz9g.q12g") == 3 and int(s.state.quests.get("q12g",0)) == 3 and accounting().experience == before.experience,"actual refusal fails gold retrieval without granting its reward")
	check(s.state.money == before.money and s.state.quest_items.is_empty(),"refusing the uncollected sack yields no money or quest items")
	await complete("b.elder.s12_4")
	check(value("q.gz7g.q13g") == 1,"refused gold route still offers the canonical ambush continuation")
	check(value("z.gz7g_gz8g") == 1 and value("z.gz7g_gz9g") == 1,"actual continuation closes the authored ambush passages")
	await roundtrip("base_gipat_gold_refused",["q.gz9g.q12g","q.gz7g.q13g","b.elder.s12_1"])
	await finish_gipat("BASE_CAMPAIGN_GIPAT_BRANCHES","Prepared earlier s8_2 offer. Actual Smith warning→Elder gold refusal→ambush continuation, with no unearned gold/reward and saves. Source-only wolf/gold timeout blocks have no WorldScript/callback callers and are classified separately, not treated as playable timed branches.")

func farewell() -> void:
	var n := 1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--merc="): n = int(arg.trim_prefix("--merc="))
	GameData.options["merc_travel"] = 0
	# Prepared availability earned by this companion's earlier chapter event.
	# Recruitment and farewell both go through their real conversations.
	s.state.set_var(0,"amerc_%d"%n,1)
	await enter(ScriptVM.MERC_HOME[n])
	await complete("b.merc%d.n1_%d"%[n,n])
	check(s.state.mercs.has(n) and s.party_units(0).size() == 2,"ordinary hire adds the chosen Gipat companion to the live party")
	s.state.set_var(0,"b.bz7g.R36",1)
	await enter("bz7g"); start(["VCheck#0#12","VCheck#0#46"])
	await complete("b.bz7g.R36"); await complete("b.Rick.R36_3"); await complete("b.Rick.R36_1")
	check(value("b.Rick.R36_2") == 0 and value("b.Rick.R36_4") == 1,"Rick refuses departure while a living companion remains")
	await complete("b.Rick.R36_4")
	check(value("b.Rick.R36_2") == 0,"Rick's warning alone cannot satisfy the companion farewell")
	await roundtrip("base_gipat_farewell_pending",["b.Rick.R36_4","b.Rick.R36_2","b.merc%d.n10_%d"%[n,n]])
	await complete("b.merc%d.n10_%d"%[n,n])
	check(not s.state.mercs.has(n) and s.party_units(0).size() == 1,"ordinary farewell removes the chosen companion from the original party")
	check(value("b.Rick.R36_2") == 1,"earned farewell opens the actual Ingos departure topic")
	await complete("b.Rick.R36_2")
	if not await wait_zone("gz11k"):
		await finish_gipat("BASE_CAMPAIGN_GIPAT_BRANCHES","Companion farewell did not reach Ingos."); return
	check(s.party_units(0).size() == 1 and not s.state.mercs.has(n),"original lone protagonist reaches Ingos after companion farewell")
	# Ingos opens its arrival quest a few ticks after loading. Settle that
	# authored progress first, so the reload comparison sees only replays.
	ticks(12)
	check(value("q.gz11k.q42k") == 1,"original Ingos arrival starts the town quest")
	await roundtrip("base_gipat_farewell_arrival",["b.Rick.R36_2","b.merc%d.n10_%d"%[n,n]])
	await finish_gipat("BASE_CAMPAIGN_GIPAT_BRANCHES","Prepared earlier companion availability and Rick arrival offer; ordinary hire, Rick introduction/warning, missing-farewell gate, actual selected companion n10 farewell, dialogue transfer to Ingos and reload. merc_travel=0 selects original island separation behavior. One run per original Gipat companion 1–4.")

func returned_handoff() -> void:
	# Ingos departure fixture earns these prerequisites in bz11k. This
	# checkpoint starts at that returned-Gipat chapter seam.
	s.state.set_var(0,"q.gz14k.q55k",2)
	s.state.set_var(0,"b.bz7g.R54",1)
	var old_stats: Dictionary = s.state.heroes[0][0].duplicate(true)
	await enter("bz7g")
	await complete("b.bz7g.R54"); await complete("b.Rick.R54_1")
	check(s.state.current_party == "" and value("b.Rick.R54_2") == 1,"returned dialogue offers Suslanger while the original party is still active")
	await roundtrip("base_gipat_returned_ingos",["b.bz7g.R54","b.Rick.R54_2","q.gz14k.q55k"])
	await complete("b.Rick.R54_2")
	if not await wait_zone("bz13h"):
		await finish_gipat("BASE_CAMPAIGN_GIPAT_BRANCHES","Returned-Gipat transfer did not reach Suslanger."); return
	check(s.state.current_party.to_lower() == "heroalone" and s.party_units(0).size() == 1,"actual Rick return handoff creates the playable lone Hadagan party")
	for stat: String in ["str","dex","int","exp_total"]:
		check(s.state.heroes[0][0].get(stat) == old_stats.get(stat),"actual disguise handoff preserves protagonist "+stat)
	check(value("b.bz13h.Hns59") == 1,"actual return handoff offers the Suslanger captive arrival")
	await roundtrip("base_gipat_returned_suslanger",["b.Rick.R54_2","b.bz13h.Hns59"])
	await finish_gipat("BASE_CAMPAIGN_GIPAT_BRANCHES","Prepared completed Ingos q55k and offered R54 arrival, earned separately by Ingos fixtures. Actual R54/R54_1/R54_2 dialogue callbacks create HeroAlone, copy protagonist stats, offer Hns59 and transfer to playable bz13h; pre/post saves and duplicate dialogue accounting.")
