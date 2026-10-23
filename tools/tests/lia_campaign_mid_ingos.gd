extends "lia_campaign_support.gd"
## Normal Ingos arrival, laboratory, ritual and mine mechanisms. The accepted
## arrival quest and later Guard offer are independently earned checkpoints.

func _ready() -> void: run.call_deferred()

func run() -> void:
	boot(); chapter("Gipat","Hero3","Hero","merc2g")
	if not await arrival():
		await finish("LIA_CAMPAIGN_INGOS","Stopped at the Ingos arrival/laboratory boundary."); return
	if not await ritual():
		await finish("LIA_CAMPAIGN_INGOS","Stopped at the paired-ingredient/ritual route boundary."); return
	await mine()
	await finish("LIA_CAMPAIGN_INGOS","Prepared accepted q1k from the separately tested Rick/Kel island transfer and later Guard239 offer from the investigation suite. Actual q1k party arrival; Trader/Trapper/Kel203 handoffs, q2k laboratory and full His scene/return; q3k green-leaf loot/keyed flower, q4k mark, paired-prerequisite q5k ritual/full Grey scene; actual q15k mine-route switch, successive keys/physical controls/documents and return. Missing prerequisites, pending saves, one-time rewards and ordinary exit confirmation/travel selection. God mode, kills and teleport; separate loaded-map checkpoints, not an uninterrupted campaign or native-executable comparison.")

func ritual() -> bool:
	await enter("gz21k"); start(["VCheck#2#1","VCheck#2#6","VCheck#3#1"]); ticks(25)
	check(value("q.gz21k.q3k.1") == 0 and value("q.gz21k.q5k") == 0,"flower and ritual objectives wait for their earlier offers")
	gate("gz21k_gz23k",false,"manufacture route starts closed before the Trapper offer")
	use(1005001,false)
	await enter("bz21k"); await complete("b.Trapper.brief_206")
	check(value("q.gz21k.q3k") == 1,"earned Trapper offer starts the flower quest")
	check(value("q.gz23k.q4k") == 1 and value("z.gz21k_gz23k") == 2,"actual Trapper offer starts both ingredient quests and opens their route")
	await enter("gz21k"); start(["VCheck#2#1","VCheck#2#6"]); ticks(25)
	teleport(Vector2(90,239)); use(3617,false)
	check(value("q.gz21k.q3k.2") == 1 and not s.state.quest_items.has("dflower"),"flower remains gated without its real green-leaf key")
	var carriers := EIMob.load_bytes(GameData.read_file("maps/zone21flower.mob")).objects.filter(func(o):
		return o.kind == "UNIT" and Array(o.get("quest_items",[])).any(func(item): return String(item).to_lower() == "greenleaf"))
	if not check(carriers.size() == 1,"authored flower encounter contains exactly one green-leaf carrier"): return false
	var carrier_id := int(carriers[0].nid)
	kill([carrier_id]); loot(carrier_id)
	check(s.state.quest_items.has("greenleaf") and value("q.gz21k.q3k.3") == 1,"ordinary corpse loot supplies the real green-leaf prerequisite")
	await roundtrip("campaign_flower_key",["q.gz21k.q3k","q.gz21k.q3k.3"],["greenleaf"])
	use(3617); use(1003001)
	check(value("q.gz21k.q3k") == 2 and s.state.quest_items.has("dflower") and not s.state.quest_items.has("greenleaf"),"keyed flower interactions finish the first ingredient quest")
	ticks(25)
	check(value("q.gz21k.q5k") == 0,"one completed ingredient cannot start the joint ritual quest")
	stable("first ritual ingredient")
	if not await leave("gz21k_gz23k","gz23k"): return false
	# Keep ordinary arrival threads, then select the exact quest chain once its
	# initial bindings are ready. The untested side quests remain outside scope.
	ticks(8); vm().instances.clear(); start(["VCheck#0#1","VCheck#0#4"]); ticks(25)
	teleport(Vector2(128,186))
	check(value("q.gz23k.q4k.2") == 1 and value("q.gz21k.q5k") == 0,"mark approach does not grant the uncollected second ingredient")
	use(357423); ticks(25)
	check(value("q.gz23k.q4k") == 2 and s.state.quest_items.has("svermark"),"normal mark pickup finishes the second ingredient quest")
	check(value("q.gz21k.q5k") == 1,"both actually earned ingredients start the ritual quest")
	await roundtrip("campaign_ritual_both_ingredients",["q.gz21k.q3k","q.gz23k.q4k","q.gz21k.q5k"],["dflower","svermark"])
	if not await leave("gz21k_gz23k","gz21k"): return false
	ticks(8); vm().instances.clear(); start(["VCheck#3#1"]); ticks(25)
	teleport(Vector2(293,85)); use(1005001)
	check(value("q.gz21k.q5k") == 2 and not s.state.quest_items.has("dflower"),"real ritual use consumes the flower and completes the ritual quest")
	ticks(55)
	if not await wait_zone("cz2k"): return false
	await simulate_until("b.Grey.brief_207")
	await complete("b.Grey.brief_207")
	if not await wait_zone("gz21k"): return false
	check(value("b.Trapper.brief_207a") == 1 and value("b.His.brief_210") == 1,"actual Grey scene returns to the forest with its follow-up topics")
	if not await leave("bz21k"): return false
	await complete("b.Trapper.brief_207a")
	check(value("z.gz21k_gz22k") == 2 and value("z.gz22k_gz23k") == 2,"actual ritual hand-in opens the far-forest routes")
	check(not s.state.quest_items.has("svermark") and not s.state.quest_items.has("sveralc") and value("q.gz23k.q6k") == 1 and value("q.gz22k.q8k") == 1,"Grey and Trapper hand-ins consume their distinct items and start both next quests")
	await roundtrip("campaign_ritual_done",["q.gz21k.q5k","b.Trapper.brief_207a","z.gz21k_gz22k","q.gz23k.q6k","q.gz22k.q8k"])
	return true

func arrival() -> bool:
	# The real Rick/cz0k/Kel200 island handoff is already covered by
	# lia_kel_handoffs. This is its accepted arrival-quest checkpoint.
	s.state.set_var(0,"q.gz21k.q1k",1)
	await enter("gz21k"); start(["VCheck#0#1"]); ticks(25)
	check(s.party_heroes().size() == 2 and vm()._by_name("merc2") != null,"Ingos retains the actual Gipat party and living Kel")
	teleport(Vector2(237,126))
	check(value("q.gz21k.q1k.2") == 1,"Ingos arrival finds the original path before the town objective")
	teleport(Vector2(336,265))
	check(value("q.gz21k.q1k") == 1,"arrival does not complete while Kel remains outside town")
	place_party(Vector2(336,265))
	check(value("q.gz21k.q1k") == 2 and value("b.Trader.brief_201") == 1 and value("b.Trapper.brief_202") == 1,"whole-party town arrival offers both actual introductions")
	if not await leave("bz21k"): return false
	start(["VCheck#0#1"])
	await complete("b.Trader.brief_201")
	check(value("b.merc2.brief_203") == 0,"Trader introduction alone cannot offer the laboratory quest")
	await complete("b.Trapper.brief_202")
	check(value("b.merc2.brief_203") == 1,"both actual introductions unlock Kel's laboratory offer")
	if not await settle_introduction_returns(): return false
	await complete("b.merc2.brief_203")
	if not check(value("q.gz21k.q2k") == 1,"actual Kel offer starts the laboratory quest"): return false
	await enter("gz21k"); start(["VCheck#1#1"]); ticks(25)
	teleport(Vector2(459,318.5)); use(1002001)
	kill([1002002,1002003])
	check(value("q.gz21k.q2k.3") == 1,"last laboratory guardian prevents its combat objective")
	kill([1002004])
	check(value("q.gz21k.q2k.4") == 1 and value("q.gz21k.q2k") == 1,"defeating all guardians still requires the whole-party return")
	await roundtrip("campaign_ingos_lab_return",["q.gz21k.q1k","q.gz21k.q2k","q.gz21k.q2k.4"])
	place_party(Vector2(449,258))
	if not await wait_zone("cz1k"): return false
	await simulate_until("b.His.brief_204")
	await complete("b.His.brief_204")
	if not await wait_zone("gz21k"): return false
	check(value("q.gz21k.q2k") == 2 and value("b.Trapper.brief_206") == 1,"actual laboratory scene returns and unlocks the ritual ingredients offer")
	return true

func settle_introduction_returns() -> bool:
	var kel: GameUnit = vm()._by_name("merc2")
	if not check(kel != null and vm().briefings.active.is_empty() and vm().briefings._pending_dialog.is_empty()
		and s.world.dialog_movers.values().all(func(m): return bool(m.get("restore",false))),
		"introductions leave only ordinary dialogue-return walks before Kel's new topic"): return false
	var before := accounting()
	# Closing the introductions sends Kel back to the position remembered by
	# Briefings._remember_return. NPC-only ticks freeze the world coordinator's
	# turn phase and 30-second deadline, so a return walk can stay busy forever.
	# Run the ordinary world loop for at most 38.5 simulated seconds instead;
	# retain its path, collision handling and bounded staging fallback unchanged.
	for i in 700:
		if s.world.dialog_movers.is_empty() and kel.village_talk_ready(): break
		s.world._tick(GameUnit.TICK)
		if i%40 == 0: await frames(1)
	check(accounting() == before and value("q.gz21k.q2k") == 0 and value("b.merc2.brief_203") == 1,
		"ordinary return simulation leaves rewards unchanged and laboratory acceptance pending")
	return check(s.world.dialog_movers.is_empty() and kel.village_talk_ready(),
		"normal world simulation completes the introductions' return walks before Kel is selected")

func mine() -> void:
	await enter("gz24k"); start(["VCheck#0#1"]); ticks(25)
	check(value("q.gz24k.q15k.1") == 0,"mine document quest does not start before the actual Guard offer")
	await enter("gz22k"); start(["Lever#0#2"]); use(5636,false)
	gate("gz22k_gz24k",false,"mine route switch stays blocked without the Guard's actual key")
	await accept("bz21k","b.Guard.brief_239","q.gz24k.q15k")
	check(s.state.quest_items.has("kkey01"),"actual Guard offer supplies the original mine key")
	await enter("gz21k")
	gate("gz21k_gz22k",true,"earned ritual hand-in permits the ordinary far-forest exit")
	if not await leave("gz21k_gz22k","gz22k"): return
	ticks(8); vm().instances.clear(); start(["Lever#0#2"])
	for edge: String in ["gz22k_gz24k","gz22k_gz24ak","gz22k_gz24bk"]:
		gate(edge,false,"mine approach remains blocked before its physical switch: "+edge)
	use(5636)
	for edge: String in ["gz22k_gz24k","gz22k_gz24ak","gz22k_gz24bk"]:
		gate(edge,true,"actual mine switch opens its authored route: "+edge)
	check(value("z.gz24k") == 0,"mine switch reveals the correct not-yet-completed mine destination")
	await roundtrip("campaign_mine_switch",["z.gz22k_gz24k","z.gz22k_gz24ak","z.gz22k_gz24bk"],["kkey01"])
	if not await leave("gz22k_gz24k","gz24k"): return
	ticks(8); vm().instances.clear(); start(["VCheck#0#1","Lever#0#1","Lever#0#2"]); ticks(25)
	use(4370,false)
	check(value("q.gz24k.q15k.3") == 0,"second mine mechanism requires the new key from the first chest")
	use(1015001)
	check(s.state.quest_items.has("kkey02") and value("q.gz24k.q15k.2") == 1,"normal first mine chest grants its distinct second key")
	use(4368)
	check(int(s.world.levers[4306].state) == 1,"first keyed mine control opens its actual physical door")
	await roundtrip("campaign_mine_second_key",["q.gz24k.q15k","q.gz24k.q15k.3"],["kkey01","kkey02"])
	use(4370)
	check(int(s.world.levers[4303].state) == 1 and int(s.world.levers[4302].state) == 1,"second keyed mine control opens both actual inner doors")
	check(value("q.gz24k.q15k.4") == 1 and not s.state.quest_items.has("magedocs"),"mine controls still require the actual document pickup")
	use(1015002)
	check(value("q.gz24k.q15k") == 2 and s.state.quest_items.has("magedocs") and value("b.Huber.brief_240") == 1,"normal document pickup finishes mine quest and offers Huber hand-in")
	check(value("z.gz24k") == 2,"document completion marks the mine region complete")
	stable("mine document completion")
	await roundtrip("campaign_mine_documents",["q.gz24k.q15k","b.Huber.brief_240","z.gz24k"],["magedocs"])
	await leave("gz22k_gz24k","gz22k")
