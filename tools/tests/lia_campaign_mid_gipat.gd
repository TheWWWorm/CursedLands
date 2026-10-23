extends "lia_campaign_support.gd"
## Earlier main-story topic offers are checkpoint inputs. Keys, mechanisms,
## objective changes and return routes come from the original handlers.

func _ready() -> void: run.call_deferred()

func run() -> void:
	boot(); chapter("Gipat","Hero3","Hero","merc2g")
	if not await needle():
		await finish("LIA_CAMPAIGN_GIPAT","Stopped at the Magic Needle dungeon travel boundary."); return
	if not await healer():
		await finish("LIA_CAMPAIGN_GIPAT","Stopped at the healer's cave travel boundary."); return
	await golem_center()
	await finish("LIA_CAMPAIGN_GIPAT","Prepared earlier Smith/Witch topic offers and unrevealed route gates; actual q16g crypt key/door/flood/needle and return, q17g ordered trap controls and healer arrival, q28g keyed golem-center controls and ordinary travel-map return. Pending-stage saves, missing-key/disabled-control/early-area negatives and duplicate reward checks. God mode and teleport accelerate danger/traversal. This is a collection of loaded-map checkpoints, not an uninterrupted campaign or native-executable comparison.")

func needle() -> bool:
	await enter("gz11g"); start(["VCheck#5#1"])
	check(value("q.gz11g.q16g.1") == 0,"crypt objective waits for its accepted Smith quest")
	s.state.set_var(0,"z.gz11d1",1) # prior blocked entrance, before the offer opens it
	gate("gz11d1",false,"crypt entrance is blocked before the actual Smith offer")
	await accept("bz11g","b.Smith.brief_126a","q.gz11g.q16g")
	check(value("z.gz11d1") == 2,"actual Smith dialogue opens the crypt entrance")
	s._reveal_travel_zones("gz9g_gz11g")
	check(value("z.gz11g") == 1,"normal map reveal supplies the active Rift return gate")
	await enter("gz11g"); start(["VCheck#5#1","VCheck#5#3"]); ticks(25)
	teleport(Vector2(216,144))
	check(value("q.gz11g.q16g.1") == 1,"standing outside the crypt approach does not finish its objective")
	teleport(Vector2(221,152))
	check(value("q.gz11g.q16g.1") == 2,"entering the real crypt approach advances the quest point")
	if not await leave("gz11d1"): return false
	ticks(30)
	check(value("q.gz11d1.q16ag") == 1,"ordinary crypt entry starts its accepted inner quest")
	gate("gz11g",false,"first crypt visit retains its authored needle return gate")
	use(1030052,false)
	check(value("q.gz11d1.q16ag.3") == 0,"keyed crypt door cannot skip the real key chest")
	use(2002381)
	check(s.state.quest_items.has("ambushkey03") and value("q.gz11d1.q16ag.3") == 1,"normal crypt chest supplies the original door key")
	use(1030052)
	check(value("q.gz11d1.q16ag.4") == 1,"keyed door advances to the flood objective")
	use(4523)
	check(not s.state.quest_items.has("ambushkey03") and value("q.gz11d1.q16ag.4") == 1,"flood switch consumes its key and preserves the authored delay")
	await roundtrip("campaign_needle_flood_pending",["q.gz11d1.q16ag","q.gz11d1.q16ag.4","z.gz11g"])
	ticks(340)
	check(value("q.gz11d1.q16ag.4") == 2 and value("q.gz11d1.q16ag") == 1,"flood delay finishes without granting the uncollected needle")
	gate("gz11g",false,"flooding alone cannot finish the first-visit return gate")
	use(2002355)
	check(value("q.gz11d1.q16ag") == 2 and s.state.quest_items.has("awl"),"normal needle chest finishes the inner quest and grants its item")
	gate("gz11g",true,"collecting the needle opens the real return passage")
	stable("Magic Needle completion")
	await roundtrip("campaign_needle_return",["q.gz11d1.q16ag","z.gz11g"],["awl"])
	if not await leave("gz11g"): return false
	start(["VCheck#5#3"])
	check(value("q.gz11g.q16g") == 2 and value("b.Smith.brief_127") == 1 and value("b.Smith.brief_128") == 1,"actual return observes inner completion and offers both Smith follow-ups")
	await enter("bz11g"); await complete("b.Smith.brief_127"); await complete("b.Smith.brief_128")
	check(value("q.gz13g.q17g") == 1 and value("z.gz10g_gz13g") == 2,"actual needle follow-up accepts and opens the healer route")
	return true

func healer() -> bool:
	# The cave entrance has not yet been reached in this prepared chapter.
	s.state.set_var(0,"z.bz12g",1)
	await enter("gz13g"); start(["Start","VCheck#0#1"]); ticks(25)
	gate("bz12g",false,"healer cave remains blocked before its trap route is completed")
	use(1323,false); use(1322,false); use(1321,false)
	check(value("q.gz13g.q17g.2") == 0,"disabled downstream controls and missing key cannot advance the trap chain")
	teleport(Vector2(52.1,143.2))
	check(value("q.gz13g.q17g") == 1,"arriving at the healer early cannot skip the trap mechanisms")
	use(1281)
	check(s.state.quest_items.has("ambushkey00") and value("q.gz13g.q17g.2") == 1,"normal key pickup starts the first trap-control objective")
	use(1321)
	check(value("q.gz13g.q17g.3") == 1 and s.world.lever_sys.usable(1323),"first real control enables the next trap mechanism")
	await roundtrip("campaign_healer_middle_control",["q.gz13g.q17g","q.gz13g.q17g.3","z.bz12g"],["ambushkey00"])
	use(1323); use(1322)
	check(value("q.gz13g.q17g.5") == 1 and value("q.gz13g.q17g") == 1,"all controls still require the actual healer approach")
	teleport(Vector2(52.1,143.2))
	check(value("q.gz13g.q17g") == 2 and value("b.bz12g.brief_129") == 1,"final approach completes healer quest and offers its arrival briefing")
	gate("bz12g",true,"completed trap route opens the healer cave passage")
	stable("healer route completion")
	await roundtrip("campaign_healer_return",["q.gz13g.q17g","z.bz12g"])
	if not await leave("bz12g"): return false
	await complete("b.bz12g.brief_129")
	return true

func golem_center() -> void:
	await accept("bz12g","b.Witch.brief_148","q.gz14g.q28g")
	check(value("z.gz11g_gz14g") == 2,"actual Witch offer opens the golem-center entry route")
	s.state.set_var(0,"z.gz11g_gz14g_exit",1) # previous blocked secret return route
	await enter("gz14g"); start(["VCheck#0#1","VCheck#0#6"]); ticks(65)
	gate("gz11g_gz14g_exit",false,"secret return route remains closed before its controls")
	teleport(Vector2(245,151))
	check(value("q.gz14g.q28g") == 1,"early exit-area arrival cannot complete the golem-center quest")
	use(1712,false)
	check(value("q.gz14g.q28g.4") == 0,"golem-center control rejects use before its real key")
	teleport(Vector2(134,134)); use(42)
	check(s.state.quest_items.has("golemcenterkey00") and value("q.gz14g.q28g.3") == 1,"normal golem-center chest supplies its actual control key")
	use(1712)
	check(value("q.gz14g.q28g.4") == 1,"keyed control advances the golem-center objective")
	await roundtrip("campaign_golem_control_pending",["q.gz14g.q28g","q.gz14g.q28g.4","z.gz11g_gz14g_exit"],["golemcenterkey00"])
	use(57)
	check(value("q.gz14g.q28g.5") == 1 and not s.state.quest_items.has("golemcenterkey00"),"final control consumes the key and enables the physical outlet")
	check(int(s.world.levers.get(58,{}).get("state",0)) == 1,"original final control activates the replacement exit object")
	teleport(Vector2(245,151))
	check(value("q.gz14g.q28g") == 2 and value("z.bz14g") == 2 and value("z.gz11g_bz14g") == 2,"completed final approach opens Rick and his route")
	gate("gz11g_gz14g_exit",true,"golem-center completion opens its secret return route")
	stable("golem-center completion")
	await roundtrip("campaign_golem_exit",["q.gz14g.q28g","z.gz11g_gz14g_exit","z.bz14g"])
	await leave("gz11g_gz14g_exit","gz11g")
