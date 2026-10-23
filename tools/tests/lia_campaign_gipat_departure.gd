extends "lia_campaign_mid_gipat.gd"
## Chapter seam: earned Babur rescue/Palantir retrieval, unreported to Karh,
## carrying Zak's knife and broken Palantir. Later offers are never assigned.
func accept(zone: String, topic: String, quest: String) -> void:
	check(value(topic) == 1,"previous authored quest actually offered "+topic)
	await enter(zone); await complete(topic)
	check(value(quest) == 1,"earned conversation starts "+quest)

func run() -> void:
	boot(); chapter("Gipat","Hero3","Hero","merc2g")
	for key in ["q.gz16g.q22g","q.gz16g.q24g"]: s.state.set_var(0,key,2)
	for key in ["b.Karh.brief_142","b.Karh.brief_143"]: s.state.set_var(0,key,1)
	for key in ["ZakKnife","PalantirBroken00"]: s.state.add_item(key)
	# The two first chapter actions must still reject missing earned keys.
	await enter("gz10g"); use(4636,false)
	check(value("q.gz10g.q25g") == 0,"Karh's city mechanism is locked before the quest/key handoff")
	await enter("gz9g"); use(1000039,false); use(1000077,false)
	check(value("q.gz9g.q26g") == 0,"book route doors reject use before Smith supplies their key")
	await enter("bz11g"); start(["VCheck#0#1"])
	await complete("b.Karh.brief_142"); await complete("b.Karh.brief_143")
	check(value("q.gz10g.q25g") == 1 and s.state.quest_items.has("ambushkey01"),"actual Babur reports grant the city mission and mechanism key")
	await enter("gz10g"); start(["VCheck#3#1"]); ticks(30)
	place_party(Vector2(222,56)); use(4636)
	check(value("q.gz10g.q25g.3") == 1 and not s.state.quest_items.has("ambushkey01"),"actual keyed mechanism consumes its key and starts timed retreat")
	place_party(Vector2(100,150))
	check(value("q.gz10g.q25g.3") == 2 and value("q.gz10g.q25g.4") == 0,"whole-party retreat succeeds while the original attack delay remains pending")
	await roundtrip("campaign_gipat_city_delay",["q.gz10g.q25g","q.gz10g.q25g.3","q.gz10g.q25g.4"])
	for i in 1900:
		ticks(1)
		if i%40 == 0: await frames(1)
	var guard_ids: Array = vm().globals.get("CityGuard",[]).duplicate()
	var living: Array = []
	for unit: GameUnit in guard_ids:
		if unit != null and not unit.dead and unit.uid not in living: living.append(unit.uid)
	check(guard_ids.size() >= 20 and not living.is_empty(),"original city-defense group remains populated after timed reinforcements")
	check(value("q.gz10g.q25g.4") == 2 and value("q.gz10g.q25g.5") == 1 and value("q.gz10g.q25g") == 1,
		"authored attack delay and reinforcement do not award victory with living guards")
	if not living.is_empty():
		kill(living.slice(0,living.size()-1))
		check(value("q.gz10g.q25g") == 1,"last city defender blocks quest completion")
		kill([living[-1]])
	check(value("q.gz10g.q25g") == 2 and value("b.Karh.brief_144") == 1,"actual last defender death completes city mission and offers its report")
	stable("city mission")
	await enter("bz11g"); start(["VCheck#0#1"])
	await complete("b.Karh.brief_144"); await complete("b.Smith.brief_145b")
	check(value("q.gz9g.q26g") == 1 and s.state.quest_items.has("ambushkey02") and not s.state.quest_items.has("zakknife"),
		"earned Smith branch exchanges Zak's knife for the actual book quest/key")
	await enter("gz9g"); start(["VCheck#3#1"]); ticks(30)
	place_party(Vector2(172,328))
	check(value("q.gz9g.q26g.5") == 0,"book location cannot skip the earlier approach and two doors")
	place_party(Vector2(150,190)); use(1000039)
	check(value("q.gz9g.q26g.3") == 1 and value("q.gz9g.q26g.4") == 0,"first keyed door alone does not enable the book search")
	await roundtrip("campaign_gipat_book_first_door",["q.gz9g.q26g.2","q.gz9g.q26g.3"],["ambushkey02","palantirbroken00"])
	use(1000077); place_party(Vector2(172,328)); use(1026001)
	check(value("q.gz9g.q26g") == 2 and s.state.quest_items.has("kleverbook") and value("b.Witch.brief_146") == 1,
		"both keyed doors and normal book chest complete retrieval and offer Witch follow-up")
	await enter("bz12g"); await complete("b.Witch.brief_146")
	check(value("q.gz12g.q27g") == 1 and not s.state.quest_items.has("kleverbook"),"actual Witch report consumes the book and grants Palantir repair")
	await enter("gz12g"); start(["VCheck#1#1"]); ticks(30)
	place_party(Vector2(88,83)); use(4525); use(4523)
	check(value("q.gz12g.q27g") == 1 and s.state.quest_items.has("palantirbroken00") and not s.state.quest_items.has("palantirwork00"),
		"two real sources preserve broken Palantir and do not finish three-source repair")
	await roundtrip("campaign_gipat_two_sources",["q.gz12g.q27g.2","q.gz12g.q27g.3","q.gz12g.q27g.4"],["palantirbroken00"])
	use(4524); ticks(15)
	check(value("q.gz12g.q27g") == 2 and not s.state.quest_items.has("palantirbroken00") and s.state.quest_items.has("palantirwork00"),
		"actual third source exchanges broken Palantir for repaired Palantir and completes quest")
	check(value("b.Daughter.brief_147") == 1 and value("b.Witch.brief_148") == 1,"repair completion offers both actual follow-up conversations")
	stable("Palantir repair")
	await enter("bz12g"); await complete("b.Daughter.brief_147")
	await golem_center()
	check(s.zone_id == "gz11g" and value("q.gz14g.q28g") == 2,"actual golem-center return reaches Rift with completed quest")
	if not await leave("bz14g"):
		await finish("LIA_CAMPAIGN_GIPAT_DEPARTURE","Earned q25g..q28g; Rick return passage failed."); return
	await complete("b.Rick.brief_149")
	check(value("b.Rick.brief_151") == 1,"actual Rick continuation offers the island departure")
	await complete("b.Rick.brief_151")
	if not await wait_zone("cz0k"):
		await finish("LIA_CAMPAIGN_GIPAT_DEPARTURE","Earned all Gipat chapter objectives; Rick transfer failed."); return
	await simulate_until("b.merc2.brief_200")
	await complete("b.merc2.brief_200")
	if not await wait_zone("gz21k"):
		await finish("LIA_CAMPAIGN_GIPAT_DEPARTURE","Ingos arrival conversation failed to leave its scene."); return
	check(s.state.current_party == "Gipat" and s.party_heroes().size() == 2,"earned departure reaches playable Ingos with both heroes")
	check(not s.state.quest_items.has("palantirwork00") and not s.state.quest_items.has("ambushkey02"),"authored island departure clears spent Gipat quest objects")
	await roundtrip("campaign_gipat_departed",["q.gz10g.q25g","q.gz9g.q26g","q.gz12g.q27g","q.gz14g.q28g","b.Rick.brief_151","b.merc2.brief_200"])
	await finish("LIA_CAMPAIGN_GIPAT_DEPARTURE","Prepared completed Babur/Palantir retrieval, Karh142/143 offers and their two carried objects (earned by palantir suite). Actual q25g city key/timed retreat/reinforcements/last defender/report→Smith145b knife exchange→q26g keyed book route→Witch146→q27g three-source repair→earned Witch148→q28g golem-center key/controls/return→normal Rick return→Rick149/151 and full cz0k arrival scene→playable Ingos. Saves, missing keys, partial groups/controls, timing and duplicate rewards. Walking/combat accelerated. Optional Smith145a/145c ordering is outside this chapter; no later outcomes or topic offers injected.")
