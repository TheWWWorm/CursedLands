extends "lia_kel_departures.gd"
## The first fragment is a prepared Gipat arrival checkpoint, independently
## earned and transferred in lia_kel_departures. Earn the other two through
## their real objects and carry them through the authored island/party swaps.

func advance_until(condition: Callable, label: String, maximum := 4000) -> bool:
	var deadline := Time.get_ticks_msec()+90000
	var count := 0
	while Time.get_ticks_msec()<deadline and count<maximum:
		if not s.loading_game and condition.call():
			freeze(); return check(true,label)
		if s.loading_game:
			await frames(1); continue
		s.world._tick(GameUnit.TICK)
		count += 1
		if count%20 == 0: await frames(1)
	return check(false,label)

func has_fragments(expected: Array, label: String) -> void:
	check(s.state.quest_items.keys().filter(func(key): return key in ["kel1","kel2","kel3"]).size() == expected.size()
		and expected.all(func(key): return s.state.quest_items.has(key)),label)

func run() -> void:
	boot()
	s.state.god_modes[0] = 1
	s.state.create_party("Gipat")
	s.state.add_party_unit("Gipat","Hero","Hero3")
	s.state.add_party_unit("Gipat","merc2","merc2g")
	s.state.set_current_party("Gipat")
	# The checkpoint starts with Gipat deployed before its earned prerequisites.
	s.state.store_party_quest_items()
	s.state.add_item("Kel1")
	# The crypt key is supplied by the separately tested paid fortune.
	s.state.add_item("AmbushKey04")
	await enter("gz11d1")
	start(["VCheck#1#1","Crypt#4"])
	use(1712); use(4357253)
	has_fragments(["kel1","kel2"],"first and newly earned second fragments are present before leaving Gipat")
	s.state.set_var(0,"b.Rick.brief_151",1)
	await enter("bz14g")
	await complete("b.Rick.brief_151")
	if not await wait_zone("cz0k"):
		await finish("LIA_KEL_HANDOFFS","Rick departure failed before Ingos arrival."); return
	if not await advance_until(func(): return value("b.merc2.brief_200") == 1,"original Ingos arrival scene offers Kel's briefing"):
		await finish("LIA_KEL_HANDOFFS","Ingos arrival scene did not offer its briefing."); return
	await complete("b.merc2.brief_200")
	if not await wait_zone("gz21k"):
		await finish("LIA_KEL_HANDOFFS","Ingos arrival briefing failed to travel."); return
	check(s.state.current_party == "Gipat","original Ingos arrival retains the Gipat party identity")
	has_fragments(["kel1","kel2"],"both Rod fragments survive Rick and Kel's actual Ingos transfer")
	s.state.set_var(0,"b.Haburu.fq19",1)
	await enter("bz23k")
	await complete("b.Haburu.fq19")
	await enter("gz24k")
	start(["Lever#0#3","Lever#0#4","Lever#0#5","VCheck#1#1"])
	use(4374); use(14357306); use(14357307); use(4367)
	has_fragments(["kel1","kel2","kel3"],"third fragment is earned by the actual keyed chest")
	await roundtrip("lia_kel_before_jigran",["q.gz11d1.fq13","q.gz24k.fq19"],["kel1","kel2","kel3"])
	# Earlier Ingos main-story travel is accelerated to its departure scene.
	# Keep and run its full WorldScript, including the ordinary movement.
	await s.enter_zone("cz4k",1,false)
	freeze()
	if not await advance_until(func(): return value("b.merc2.brief_254") == 1,"original Ingos portal walk offers its departure briefing"):
		await finish("LIA_KEL_HANDOFFS","Ingos portal scene did not offer its briefing."); return
	await complete("b.merc2.brief_254")
	if not await wait_zone("cz1j"):
		await finish("LIA_KEL_HANDOFFS","Ingos departure failed to reach Jigran arrival."); return
	if not await advance_until(func(): return value("b.Baron.brief_300") == 1,"original Jigran arrival walk offers the Baron briefing"):
		await finish("LIA_KEL_HANDOFFS","Jigran arrival scene did not offer its briefing."); return
	await complete("b.Baron.brief_300")
	if not await wait_zone("gz31j"):
		await finish("LIA_KEL_HANDOFFS","Jigran arrival failed to leave its scene."); return
	has_fragments(["kel1","kel2","kel3"],"all three fragments survive the actual Ingos-to-Jigran transfer")
	# Prepare the pending duel conversation; its quest grant and both named
	# party rebuilds remain entirely controlled by the original scripts.
	s.state.set_var(0,"b.BSon.brief_318",1)
	await enter("bz31j")
	await complete("b.BSon.brief_318")
	if not await advance_until(func(): return s.zone_id == "gz32j" and s.state.current_party == "Jigran1",
		"actual duel briefing and zone script create the solo Jigran1 party"):
		await finish("LIA_KEL_HANDOFFS","Jigran1 party transfer did not complete."); return
	has_fragments(["kel1","kel2","kel3"],"AddLoot retains all three fragments in the actual Jigran1 handoff")
	check(s.state.party_member("Jigran1::merc2").is_empty(),"the duel's actual party is solo")
	teleport(Vector2(151,175))
	var opponent: GameUnit = s.world.units.get(1007001)
	if check(opponent != null and not opponent.dead,"authored duel opponent is alive"):
		# A controlled combat shortcut supplies the authored non-lethal HP
		# threshold; do not assign quest flags, travel or party outcomes.
		opponent.hp = opponent.max_hp*0.6
	if not await advance_until(func(): return s.zone_id == "cz2j","non-lethal duel threshold reaches the original follow-up scene"):
		await finish("LIA_KEL_HANDOFFS","Non-lethal duel did not reach its follow-up."); return
	check(value("q.gz32j.q7j") == 2,"non-lethal duel watcher completes its real quest")
	if not await advance_until(func(): return value("b.BSon.brief_324") == 1,"original follow-up scene offers its completion briefing"):
		await finish("LIA_KEL_HANDOFFS","Duel follow-up did not offer its briefing."); return
	await complete("b.BSon.brief_324")
	if not await advance_until(func(): return s.zone_id == "bz31j" and s.state.current_party == "Jigran2",
		"actual follow-up dialogue creates Jigran2 with Kel restored from Gipat"):
		await finish("LIA_KEL_HANDOFFS","Jigran2 party transfer did not complete."); return
	has_fragments(["kel1","kel2","kel3"],"AddLoot retains every collected fragment in the actual Jigran2 handoff")
	var kel: GameUnit = vm()._by_name("merc2")
	check(kel != null and not kel.dead and kel.has_meta("hero"),"Jigran2 has living Kel before the separately tested death scene")
	await roundtrip("lia_kel_jigran_handoff",["q.gz32j.q7j","b.BSon.brief_324"],["kel1","kel2","kel3"])
	await finish("LIA_KEL_HANDOFFS","Prepared Gipat first-fragment/key checkpoint and later main-story topic offers; actual second/third-fragment objects, island cinematics/dialogues, non-lethal duel threshold, both named-party AddLoot transfers and save/reload. Earlier traversal accelerated; no native execution claim.")
