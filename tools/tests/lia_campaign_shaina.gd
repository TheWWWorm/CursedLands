extends "lia_campaign_support.gd"
## Bridge the independently earned q7h offer and q6h letter hand-in to the
## prisoner-rescue offer. Every q8h/q9h outcome and party switch is authored.

func _ready() -> void: run.call_deferred()

func hero() -> GameUnit:
	var protagonist := super.hero()
	if protagonist != null: return protagonist
	# The original infiltration deliberately gives control to Shaina alone.
	var party := s.party_units(0)
	return party[0] if not party.is_empty() else null

func run() -> void:
	boot(); chapter("FSusel","Hero2","Hero2")
	s.state.set_var(0,"q.gz1h.q01h",2)
	s.state.set_var(0,"q.gz1h.q02h",2)
	# Earned separately by lia_revenge_return and early_suslanger. Leave the
	# q6h hand-in pending first to check the joint offer's missing prerequisite.
	s.state.set_var(0,"q.gz2h.q7h",2)
	s.state.set_var(0,"b.merc8.brief_23",1)
	await enter("bz2h"); start(["VCheck#1#3","VCheck#1#4"])
	check(value("b.YCF.brief_27") == 0 and value("b.merc8.brief_37") == 0,
		"later offers remain closed before the infiltration and letter hand-in")
	await enter("bz5h")
	# Keep the village's waiting return watcher in its saved VM while away.
	start(["VCheck#1#1"])
	await complete("b.merc8.brief_23")
	if not await wait_zone("gz2h"):
		await finish("LIA_CAMPAIGN_SHAINA","Stopped at the actual Shaina handoff."); return
	ticks(30)
	check(s.state.current_party == "Shaina" and s.party_units(0).size() == 1,
		"actual infiltration conversation deploys Shaina alone")
	check(value("q.gz2h.q8h") == 1 and value("q.gz2h.q8h.1") == 1,
		"actual offer and map arrival start the infiltration objective")
	gate("gz1h_gz2h",false,"infiltration closes the outward route")
	gate("bz5h",false,"infiltration closes the ordinary return until its objectives finish")
	teleport(Vector2(148,236))
	check(value("q.gz2h.q8h") == 1,"standing at the return area cannot skip infiltration mechanisms")
	use(46470)
	check(value("q.gz2h.q8h.2") == 1 and not s.state.quest_items.has("note02"),
		"first mechanism alone cannot award the meteorite samples")
	await roundtrip("campaign_shaina_first_mechanism",["q.gz2h.q8h","q.gz2h.q8h.2"])
	check(s.state.current_party == "Shaina","save and reload preserve the temporary party")
	use(47543)
	check(value("q.gz2h.q8h.3") == 1 and s.state.quest_items.has("note02"),
		"second real mechanism awards the meteorite samples and activates return")
	teleport(Vector2(148,236)); ticks(25)
	if not await wait_zone("bz5h"):
		await finish("LIA_CAMPAIGN_SHAINA","Stopped at Shaina's scripted return."); return
	ticks(15)
	check(value("q.gz2h.q8h") == 2 and value("q.gz2h.q8h.3") == 2,
		"return area completes the infiltration objective and quest")
	check(s.state.current_party == "FSusel" and s.party_units(0).size() == 2,
		"actual return restores the original protagonist and Kel")
	check(value("z.bz5h") == 2 and value("z.gz1h_gz2h") == 2,
		"actual return reopens both previously closed passages")
	await complete("b.merc8.brief_24")
	check(value("b.Elder.brief_25") == 1,"real Shaina hand-in offers the Elder conversation")
	await roundtrip("campaign_shaina_return",["q.gz2h.q8h","b.Elder.brief_25","z.bz5h"])
	await enter("bz2h"); start(["VCheck#1#3","VCheck#1#4"])
	check(value("b.YCF.brief_27") == 0,"completed infiltration alone cannot skip the letter hand-in")
	# The letter suite earns and closes this exact topic; its completed state
	# is the only prepared prerequisite introduced at this checkpoint seam.
	s.state.set_var(0,"b.YCF.brief_26",2); ticks()
	check(value("b.YCF.brief_27") == 1,"both earlier quests unlock the actual q9h offer")
	await complete("b.Elder.brief_25")
	check(not s.state.quest_items.has("note02"),"actual Elder hand-in consumes the meteorite samples")
	check(value("b.merc8.brief_37") == 0,"Elder hand-in alone cannot unlock the captive quest")
	await complete("b.YCF.brief_27")
	check(value("q.gz2h.q9h") == 1,"actual YCF conversation accepts the next quest")
	check(s.state.quest_items.has("note03"),"actual q9h offer provides its letter")
	await enter("gz2h"); start(["VCheck#3#1"]); ticks(25)
	check(value("q.gz2h.q9h.1") == 1,"new quest waits for its real meeting area")
	teleport(Vector2(286,223.5))
	check(value("q.gz2h.q9h.2") == 1 and not s.world.units.has(1009002),
		"meeting area advances its objective without spawning the target early")
	use(1009001); ticks(25)
	check(not s.state.quest_items.has("note03"),"normal quest mechanism consumes the letter")
	var target: GameUnit = s.world.units.get(1009002)
	if check(target != null and not target.dead,"actual mechanism spawns the living target"):
		teleport(target.pos+Vector2(1,0))
	check(value("q.gz2h.q9h.4") == 1 and value("q.gz2h.q9h") == 1,
		"approach starts the final objective but a living target blocks completion")
	await roundtrip("campaign_shaina_last_target",["q.gz2h.q9h","q.gz2h.q9h.4"])
	kill([1009002])
	check(value("q.gz2h.q9h") == 2 and value("b.YCF.brief_28") == 1 and value("z.gz2h") == 2,
		"target death completes q9h, clears the region and offers its real hand-in")
	stable("q9h completion")
	await enter("bz2h"); start(["VCheck#1#4"])
	check(value("b.merc8.brief_37") == 1 and value("b.YCF.brief_33") == 1,
		"earned q9h and Elder hand-in unlock the captive and follow-up quest offers")
	await complete("b.YCF.brief_28")
	await roundtrip("campaign_shaina_bridge_done",["q.gz2h.q8h","q.gz2h.q9h","b.YCF.brief_28","b.merc8.brief_37","b.YCF.brief_33"])
	await optional_caravan_and_captive()
	await finish("LIA_CAMPAIGN_SHAINA","Prepared q7h's Shaina offer and the independently earned q6h letter hand-in; actual q8h party swap, two controls, meteorite samples, return area and party restoration; actual Elder and YCF conversations, q9h letter/meeting/mechanism/target, and joint captive/follow-up offers. Earned optional q11h caravan and q12h captive branch, competing robber and captive-death failure controls, corpse document and hand-ins. Save/reload retains temporary party and pending/completed stages. God mode, teleport and kill cheats accelerate traversal/combat.")

func optional_caravan_and_captive() -> void:
	await complete("b.YCF.brief_33")
	check(value("q.gz1h.q11h") == 1,"earned YCF offer accepts the optional caravan quest")
	await enter("gz1h"); start(["VCheck#6#1"]); ticks(90)
	teleport(Vector2(430,326))
	check(value("q.gz1h.q11h.2") == 1,"real caravan area starts its guard objective")
	use(1011003,false)
	kill([1011011,1011012,1011013])
	check(value("q.gz1h.q11h") == 1 and not s.world.lever_sys.usable(1011003),
		"one surviving caravan guard still blocks the quest chest")
	await roundtrip("campaign_caravan_last_guard",["q.gz1h.q11h","q.gz1h.q11h.2"])
	# Test the authored failure branch, then reload the same pending save to
	# continue the successful route. No quest flag is changed by the fixture.
	ticks(2800)
	var robber: GameUnit = s.world.units.get(1011021)
	if check(robber != null,"original caravan timer spawns the competing robber"):
		teleport(Vector2(432,326.5),robber); ticks(15)
	check(value("q.gz1h.q11h") == 3 and value("b.YCF.brief_34c") == 1,
		"robber reaching the unopened chest records the original failed quest")
	check(await s.load_game_shown("campaign_caravan_last_guard"),"reload pending caravan before its alternate failure")
	freeze(); ticks(12)
	check(value("q.gz1h.q11h") == 1,"pending caravan save restores its unfailed quest")
	kill([1011014]); use(1011003)
	check(value("q.gz1h.q11h") == 2 and value("b.YCF.brief_34b") == 1,
		"normal unlocked caravan chest completes the quest and offers its first report")
	check(not s.state.quest_items.has("note04"),"chest completion cannot substitute for the caravaneer's document")
	loot(1011001)
	check(s.state.quest_items.has("note04") and value("b.YCF.brief_34a") == 1 and value("b.YCF.brief_34b") == 3,
		"ordinary corpse loot replaces the report with the document hand-in")
	await enter("bz2h"); await complete("b.YCF.brief_34a")
	check(value("q.gz1h.q12h") == 1 and not s.state.quest_items.has("note04"),
		"actual document hand-in consumes it and accepts the captive follow-up")
	await enter("gz1h"); start(["VCheck#5#1"]); ticks(30)
	var captive: GameUnit = s.world.units.get(1012001)
	if not check(captive != null and not captive.dead,"original captive encounter spawns its living rescue target"): return
	# The successful rescue permits either combat or the optional scouting
	# stages. Here the guards are defeated, without fabricating scouting flags.
	kill([1012002])
	check(value("q.gz1h.q12h.5") == 0,"last living captive guard prevents the escort objective")
	await roundtrip("campaign_captive_last_guard",["q.gz1h.q12h","q.gz1h.q12h.5"])
	kill([1012001])
	check(value("q.gz1h.q12h") == 3 and value("b.YCF.brief_36") == 0,
		"captive death fails rescue without offering its successful hand-in")
	check(await s.load_game_shown("campaign_captive_last_guard"),"reload living captive checkpoint")
	freeze(); ticks(12)
	kill([1012003])
	captive = s.world.units.get(1012001)
	check(value("q.gz1h.q12h.5") == 1 and captive.mode == "follow" and captive.mode_data.get("target") == hero(),
		"last guard death gives the living captive its original follow motivation")
	teleport(Vector2(110,227))
	check(value("q.gz1h.q12h") == 1,"protagonist arriving alone cannot complete the captive escort")
	teleport(Vector2(110,227),captive)
	check(value("q.gz1h.q12h") == 2 and value("q.gz1h.q12h.5") == 2 and value("b.YCF.brief_36") == 1,
		"living captive's own arrival completes rescue and offers its real hand-in")
	stable("optional captive completion")
	await enter("bz2h"); await complete("b.YCF.brief_36")
	await roundtrip("campaign_caravan_captive_done",["q.gz1h.q11h","q.gz1h.q12h","b.YCF.brief_36"])
