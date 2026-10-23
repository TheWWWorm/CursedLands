extends "lia_kel_support.gd"
## Two authored transfers connect fragment collection and the resurrection
## fixtures: the Suslanger departure and Kel's belongings/death scene.
## Earlier story offers are supplied; fragment, archive and death outcomes
## are produced only by the installed map scripts and normal interactions.

func _ready() -> void: run.call_deferred()

func wait_zone(id: String) -> bool:
	await frames(3)
	var deadline := Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		if s.world != null and s.zone_id == id and not s.loading_game:
			freeze(); return check(true,"authored transfer reaches "+id)
		await get_tree().process_frame
	return check(false,"authored transfer reaches "+id)

func stats(record: Dictionary) -> Array:
	return [record.get("str"),record.get("dex"),record.get("int"),record.get("exp"),record.get("exp_total")]

func equipment(record: Dictionary) -> Array:
	return [record.get("weapons",[]).duplicate(),record.get("armors",[]).duplicate(),
		record.get("quick",[]).duplicate(),record.get("spells",[]).duplicate()]

func removal_guards() -> void:
	var source := EIMob.load_bytes(GameData.read_file("maps/cz3j.mob")).script_text
	for variant: String in ["campaign","zone","thread","living","party","record","archive","archive_fallback","custom_source","lmp"]:
		var probe := Session.new()
		probe.state = CampaignState.new()
		if variant == "archive_fallback": probe.state.add_party_unit("","merc2","merc2")
		probe.state.create_party("Jigran2")
		probe.state.add_party_unit("Jigran2","Hero","Hero3")
		probe.state.add_party_unit("Jigran2","merc2","merc2")
		probe.state.set_current_party("Jigran2")
		if variant not in ["archive","archive_fallback"]:
			probe.state.create_party("Jigran5")
			probe.state.add_party_unit("Jigran5","merc2","merc2")
		if variant == "archive_fallback":
			check(not probe.state.parties.has("Jigran5") and not probe.state.party_member("Jigran5::merc2").is_empty(),
				"missing archive counterexample resolves an unrelated unnamed-party merc2")
		probe.zone_id = "gz35j" if variant == "zone" else "cz3j"
		if variant == "campaign": probe.state.campaign_id = CampaignProfile.ORIGINAL
		if variant == "party": probe.state.current_party = "Unrelated"
		if variant == "lmp": probe.lmp = {"probe":true}
		var world := GameWorld.new()
		world.mob = EIMob.new(); world.mob.script_text = source + ("\n// custom scene" if variant == "custom_source" else "")
		var context := ScriptVM.new(); context.session = probe; context.world = world
		var record: Dictionary = probe.state.heroes[0][1]
		var actor := GameUnit.new(); actor.dead = variant != "living"
		actor.set_meta("hero",record.duplicate(true) if variant == "record" else record)
		preload("res://src/game/script/story_astral_kel.gd").before_remove(context,
			"Unrelated" if variant == "thread" else "VMovie#0#3",actor)
		check(probe.state.heroes[0].has(record),"death correction preserves unrelated "+variant+" case")
		actor.free(); world.free(); probe.free()

func run() -> void:
	boot()
	removal_guards()
	s.state.create_party("FSusel")
	s.state.add_party_unit("FSusel","Hero2","Hero2")
	s.state.add_party_unit("FSusel","merc2","merc2")
	s.state.set_current_party("FSusel")
	s.state.set_var(0,"b.skelet.fq6",2)
	await enter("gz4h")
	start(["VLever1#0#0","VLever1#0#1","VLever2#0#1","VLever3#0#1","VLevers#0#5","VChest#0#3"])
	use(1088298); use(16426); use(1047355); ticks(5); use(33345906)
	check(value("q.gz4h.fq6") == 2 and s.state.quest_items.has("kel1"),"first fragment is earned before island departure")
	var before_hero := stats(s.state.party_member("FSusel::Hero2"))
	var before_kel := stats(s.state.party_member("FSusel::merc2"))
	s.state.set_var(0,"b.Sergant.brief_88a",1)
	await enter("bz7h")
	var money := s.state.money
	await complete("b.Sergant.brief_88a")
	if not await wait_zone("gz7g"):
		await finish("LIA_KEL_DEPARTURES","Authored island and Kel-death transfers; stopped at failed island travel."); return
	check(s.state.current_party == "Gipat" and value("q.gz7g.q1g") == 1,"departure creates Gipat party and its arrival quest")
	check(s.state.quest_items.has("kel1") and value("q.gz4h.fq6") == 2,"earned first fragment survives the actual island transfer")
	check(s.state.money == money,"departure preserves the original party money")
	check(stats(s.state.party_member("Gipat::Hero")) == before_hero and stats(s.state.party_member("Gipat::merc2")) == before_kel,
		"actual departure copies both original character stat records")
	await roundtrip("lia_kel_gipat_arrival",["q.gz4h.fq6","q.gz7g.q1g"],["kel1"])

	# A separate late-Jigran checkpoint supplies the living party and the
	# preceding main-story conversation, never the death/archive outcome.
	s.state.create_party("Jigran2")
	s.state.add_party_unit("Jigran2","Hero","Hero3")
	s.state.add_party_unit("Jigran2","merc2","merc2")
	s.state.set_current_party("Jigran2")
	var live_kel := s.state.party_member("Jigran2::merc2")
	live_kel.str = 40.0; live_kel.dex = 41.0; live_kel["int"] = 42.0
	live_kel.exp = 150.0; live_kel.exp_total = 4444.0
	s.state.god_modes.clear()
	s.state.set_var(0,"q.gz35j.q17j",2)
	s.state.set_var(0,"b.Deva.brief_340",1)
	await enter("bz31j")
	start(["VCheck#0#5"])
	await complete("b.Deva.brief_340")
	check(value("b.merc2.brief_342") == 1,"Deva's real conversation offers Kel's belongings quest")
	await complete("b.merc2.brief_342")
	check(value("q.gz35j.q19j") == 1 and not s.state.quest_items.has("jtoys"),"Kel's real briefing grants the uncompleted belongings quest")
	await enter("gz35j")
	start(["VCheck#1#1"]); ticks(25)
	check(value("q.gz35j.q19j.1") == 1 and value("q.gz35j.q19j.2") == 0,"belongings route waits for its original approach area")
	teleport(Vector2(27,65))
	check(value("q.gz35j.q19j.1") == 2 and value("q.gz35j.q19j.2") == 1,"approaching belongings advances only its first objective")
	check(s.state.party_member("Jigran5::merc2").is_empty(),"Kel has no fabricated archived resurrection record")
	use(1019001)
	check(value("q.gz35j.q19j") == 2 and value("q.gz35j.q19j.2") == 2 and s.state.quest_items.has("jtoys"),
		"actual belongings use completes both objectives and grants JToys")
	check(value("b.Deva.brief_345") == 1,"belongings completion offers the return conversation")
	ticks(20)
	if not await wait_zone("cz3j"):
		await finish("LIA_KEL_DEPARTURES","Authored island and Kel-death transfers; stopped at failed scene entry."); return
	var expected_stats := stats(s.state.party_member("Jigran2::merc2"))
	var expected_equipment := equipment(s.state.party_member("Jigran2::merc2"))
	var scene_kel: GameUnit = vm()._by_name("merc2")
	check(scene_kel != null and not scene_kel.dead and not scene_kel.god_mode(),"scripted death scene has living Kel with GodMode disabled")
	# Retain the scene's complete original WorldScript. Advance normal world
	# simulation so moves, SleepUntilIdle and the lethal spell actually run.
	var saw_archive := false
	var saw_death := false
	for i in 3200:
		if s.zone_id != "cz3j" or s.loading_game: break
		var actor: GameUnit = vm()._by_name("merc2")
		if actor != null and actor.dead: saw_death = true
		if not s.state.party_member("Jigran5::merc2").is_empty(): saw_archive = true
		s.world._tick(GameUnit.TICK)
		if i%20 == 0: await frames(1)
	check(saw_archive,"original cinematic creates the Kel resurrection archive")
	check(saw_death,"original cinematic's lethal spell kills Kel without a kill cheat")
	if not await wait_zone("gz35j"):
		print("KEL_SCENE_STOP zone=",s.zone_id," threads=",vm().instances.size())
		for actor_name: String in ["Hero","merc2"]:
			var actor: GameUnit = vm()._by_name(actor_name)
			if actor != null: print("KEL_SCENE_ACTOR ",actor_name," pos=",actor.pos," dead=",actor.dead," order=",actor.order)
		await finish("LIA_KEL_DEPARTURES","Authored island and Kel-death transfers; cinematic did not return."); return
	var archive := s.state.party_member("Jigran5::merc2")
	check(stats(archive) == expected_stats and equipment(archive) == expected_equipment,
		"authored pre-death archive preserves Kel's complete stats and equipment")
	check(vm()._by_name("merc2") == null or not vm()._by_name("merc2").has_meta("hero"),"return from death scene excludes Kel from living deployed party")
	check(s.state.party_member("Jigran2::merc2").is_empty(),"death scene detaches Kel's original active party record")
	await roundtrip("lia_kel_after_death",["q.gz35j.q19j","b.Deva.brief_345"],["jtoys"])
	check(vm()._by_name("merc2") == null or not vm()._by_name("merc2").has_meta("hero"),"reload does not resurrect Kel before the ritual")
	check(stats(s.state.party_member("Jigran5::merc2")) == expected_stats and equipment(s.state.party_member("Jigran5::merc2")) == expected_equipment,
		"saved cinematic archive remains available for the tested resurrection")
	await finish("LIA_KEL_DEPARTURES","First fragment earned through original mechanism and carried by actual Sergeant departure; prepared living Jigran party, real Deva/Kel briefing, area and belongings use, complete original cinematic movement/lethal spell/archive/return, full save/load. Earlier island travel is prepared; not native executable replay.")
