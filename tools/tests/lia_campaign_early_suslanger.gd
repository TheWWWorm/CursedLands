extends "lia_campaign_support.gd"
## Main Suslanger travel gates missing from the fortune/prologue fixtures.
## The earlier accepted supplies quest and later Shaina offer are declared
## checkpoint inputs; all intervening and subsequent outcomes are earned.

func _ready() -> void: run.call_deferred()

func run() -> void:
	boot(); chapter("FSusel","Hero2","Hero2")
	# This chapter begins after the separately tested prison/slave escape.
	# Its startup otherwise reuses area 4 for the original prison deployment.
	s.state.set_var(0,"q.gz1h.q01h",2)
	s.state.set_var(0,"q.gz1h.q02h",2)
	await supplies_handoff()
	await letter()
	if not await prisoner():
		await finish("LIA_CAMPAIGN_SUSLANGER","Stopped at the prisoner dungeon travel boundary."); return
	if not await escort_and_siege():
		await finish("LIA_CAMPAIGN_SUSLANGER","Stopped at the guide/siege camp travel boundary."); return
	await bones_and_boss()
	await finish("LIA_CAMPAIGN_SUSLANGER","Prepared postescape accepted q5h and the independently earned later Shaina37 offer. Actual q4h six-fruit gathering; q5h supplies, Sheriff22/q7h crossing, YCF21/q6h letter; q13h/q13oh prisoner dungeon/key/controlled escort/return; q14h living-ally guards/chest; q15h guide; q16h nugget, q17h rescue and q17oh keyed spear; q18h siege; q19h corpse loot and q20h boss jointly reopening exits. Actual intervening hand-ins, pending/completed saves and ordinary passage returns. God mode, teleport and kills accelerate traversal/combat; separate loaded-map checkpoints, not an uninterrupted campaign or native-executable comparison.")

func letter() -> void:
	await enter("gz1h")
	start(["Fruits","Fruits#1","Fruits#2","Fruits#3","Fruits#4","Fruits#5","Fruits#6"])
	for id: int in range(110401,110406): use(id)
	check(value("q.gz1h.q4h") == 0,"five fruit trees do not complete the six-fruit gathering quest")
	use(110406)
	check(value("q.gz1h.q4h") == 2,"normal use of the sixth fruit tree completes the optional gathering quest")
	start(["VCheck#4#1","VCheck#4#3"])
	check(value("q.gz1h.q6h.1") == 0 and not s.world.units.has(1007002),"letter ambush does not spawn before its briefing")
	await enter("bz2h"); await complete("b.YCF.brief_21")
	check(value("q.gz1h.q6h") == 1,"earned YCF offer starts the letter quest")
	check(s.state.quest_items.has("note01"),"actual letter offer supplies the original document")
	s.state.set_var(0,"z.gz1h",1) # prepared active Portal region, before this quest clears it
	await enter("gz1h")
	start(["VCheck#4#1","VCheck#4#3"]); ticks(25)
	teleport(Vector2(142,325))
	check(value("q.gz1h.q6h.1") == 2 and value("q.gz1h.q6h.2") == 1,"letter meeting advances only its first objective")
	use(1007004,false)
	check(value("q.gz1h.q6h") == 1 and value("z.gz1h") == 1,"locked letter chest cannot complete the quest or clear its region")
	teleport(Vector2(283,475)); kill([1007002])
	check(value("q.gz1h.q6h.3") == 1 and not s.world.lever_sys.usable(1007004),"one surviving ambusher still guards the letter chest")
	await roundtrip("campaign_letter_last_ambusher",["q.gz1h.q6h","q.gz1h.q6h.3","z.gz1h"],["note01"])
	kill([1007003]); use(1007004)
	check(value("q.gz1h.q6h") == 2 and value("q.gz1h.q6h.4") == 2 and value("z.gz1h") == 2,
		"normal ambush chest completes letter objectives and clears the Portal region")
	check(not s.state.quest_items.has("note01") and value("b.YCF.brief_26") == 1,"letter completion consumes its document and offers hand-in")
	stable("letter completion")
	await roundtrip("campaign_letter_done",["q.gz1h.q6h","z.gz1h"])
	await enter("bz2h"); await complete("b.YCF.brief_26")

func supplies_handoff() -> void:
	# The previous lia_kel_early_story fixture earns this accepted quest by
	# completing the real Kel/Elder17/Elder18 dialogue chain.
	s.state.set_var(0,"q.gz2h.q5h",1)
	await enter("gz2h"); start(["VCheck#0#1"]); ticks(25)
	teleport(Vector2(232,79.4))
	check(value("q.gz2h.q5h.1") == 1,"standing outside the supply area cannot advance its quest")
	teleport(Vector2(225,79.4))
	check(value("q.gz2h.q5h.2") == 1 and value("q.gz2h.q5h") == 1,"supply approach still requires reaching the actual meeting")
	teleport(Vector2(215.2,79.4))
	check(value("q.gz2h.q5h") == 2 and value("b.Elder.brief_20") == 1 and value("b.YCF.brief_21") == 1,"actual inner meeting completes supplies and offers both follow-ups")
	await enter("bz2h"); await complete("b.Elder.brief_20")
	check(value("b.Sheriff.brief_22") == 1,"actual supply hand-in offers the bridge quest")
	await complete("b.Sheriff.brief_22")
	check(value("q.gz2h.q7h") == 1,"actual Sheriff offer starts the bridge route")
	await enter("gz2h"); start(["VCheck#1#1"]); ticks(25)
	teleport(Vector2(218.5,117.3))
	check(value("q.gz2h.q7h") == 1,"bridge approach cannot skip choosing a crossing and reaching its far side")
	teleport(Vector2(148,173)); teleport(Vector2(147,235))
	check(value("q.gz2h.q7h") == 2 and value("b.merc8.brief_23") == 1,"actual western crossing and arrival unlock the independently tested Shaina infiltration")

func prisoner() -> bool:
	await enter("gz3h"); start(["VCheck#0#1","VCheck#0#4b"])
	check(value("q.gz3h.q13h.1") == 0 and not s.world.get_meta("added_mobs",[]).has("zone3plen.mob"),"prisoner rescue does not spawn before its offer")
	# Shaina remains in the bridge settlement after the separately tested
	# infiltration. The completed supplies quest removed her from bz2h.
	await accept("bz5h","b.merc8.brief_37","q.gz3h.q13h")
	await enter("gz3h"); start(["VCheck#0#1","VCheck#0#4b"]); ticks(25)
	check(value("q.gz3h.q13h.1") == 1,"outer rescue waits for its living guard")
	kill([1013001]); use(45750)
	check(value("q.gz3h.q13h.3") == 1 and value("q.gz3d1.q13oh") == 0,"outer mechanism opens dungeon objective without finishing rescue")
	use(1013009); ticks(25)
	if not await wait_zone("gz3d1"): return false
	ticks(30)
	gate("gz3h",false,"captive dungeon keeps the authored return gate closed before rescue")
	teleport(Vector2(42.5,57))
	var captive: GameUnit = s.world.units.get(1943444)
	if not check(captive != null,"original randomized prisoner actor exists"): return false
	teleport(captive.pos+Vector2(1,0))
	check(value("q.gz3d1.q13oh.2") == 1 and captive.controller != 0,"approaching prisoner without the real key does not recruit him")
	use(2001539)
	check(s.state.quest_items.has("hadogancavekey00"),"normal dungeon chest supplies the captive key")
	teleport(captive.pos+Vector2(1,0))
	check(value("q.gz3d1.q13oh.4") == 1 and captive.controller == 0,"keyed prisoner approach grants actual temporary control")
	teleport(Vector2(45.5,40),captive)
	check(value("q.gz3d1.q13oh") == 1,"prisoner outside the exit area keeps rescue pending")
	await roundtrip("campaign_prisoner_before_exit",["q.gz3d1.q13oh","z.gz3h"],["hadogancavekey00"])
	captive = s.world.units.get(1943444)
	teleport(Vector2(48,40),captive); ticks(15)
	check(value("q.gz3d1.q13oh") == 2 and not s.state.quest_items.has("hadogancavekey00"),"prisoner arrival finishes dungeon rescue and consumes the key")
	gate("gz3h",true,"finished prisoner rescue opens the original return passage")
	if not await leave("gz3h"): return false
	ticks(25)
	check(value("q.gz3h.q13h.4") == 1 and value("z.gz2h_gz3h") == 1,"real return starts the final escort and closes the outward route")
	teleport(Vector2(376,67))
	check(value("q.gz3h.q13h") == 1,"outer rescue waits for the companion still outside its final area")
	place_party(Vector2(376,67)); ticks(20)
	check(value("q.gz3h.q13h") == 2 and value("b.merc10.brief_38") == 1,"whole-party return completes outer rescue and offers hand-in")
	gate("gz2h_gz3h",true,"completed rescue reopens the original onward route")
	await roundtrip("campaign_prisoner_return",["q.gz3h.q13h","q.gz3d1.q13oh","z.gz2h_gz3h"])
	await enter("bz2h"); await complete("b.merc10.brief_38")
	check(value("q.gz2h.q14h") == 1,"earned prisoner hand-in accepts revenge before the camp guide")
	await enter("gz2h"); start(["VCheck#4#1","VCheck#4#3"]); ticks(25)
	teleport(Vector2(115,317)); teleport(Vector2(117,354)); kill([1014004])
	check(value("q.gz2h.q14h.3") == 1 and value("q.gz2h.q14h") == 1,"one surviving revenge guard prevents the chest objective")
	await roundtrip("campaign_revenge_last_guard",["q.gz2h.q14h","q.gz2h.q14h.3"])
	kill([1014005]); use(150157)
	check(value("q.gz2h.q14h") == 2 and value("b.merc10.brief_40") == 1,"normal chest use with the living ally completes revenge and offers the camp guide")
	stable("revenge completion")
	return true

func escort_and_siege() -> bool:
	await enter("bz2h"); await complete("b.merc10.brief_40")
	check(value("q.gz3h.q15h") == 1,"earned revenge hand-in accepts the camp guide")
	await enter("gz3h"); start(["VCheck#1#1"]); ticks(25)
	var guide: GameUnit = s.world.units.get(1015001)
	if not check(guide != null,"guide quest spawns its original actor"): return false
	gate("gz2h_gz3h",true,"guide start preserves the return route already earned by prisoner rescue")
	teleport(Vector2(344,27),guide); teleport(Vector2(360,27))
	check(value("q.gz3h.q15h.1") == 1,"guide waits while the protagonist is outside meeting distance")
	var marks := [Vector2(344,27),Vector2(290,22),Vector2(241,26),Vector2(203,27),Vector2(183,42),
		Vector2(166,74),Vector2(163,120),Vector2(152,157),Vector2(161,191),Vector2(136,207),Vector2(91,188)]
	for i in marks.size():
		guide = s.world.units.get(1015001)
		teleport(marks[i],guide); teleport(marks[i]+Vector2(5,0))
		if i == 4: await roundtrip("campaign_guide_halfway",["q.gz3h.q15h","q.gz3h.q15h.1","z.gz2h_gz3h"])
	check(value("q.gz3h.q15h") == 2 and value("b.bz3h.brief_41") == 1,"last actual guide waypoint completes the quest and offers camp arrival")
	gate("bz3h",true,"guide arrival opens the camp passage")
	gate("gz2h_gz3h",true,"guide arrival reopens the original return route")
	if not await leave("bz3h"): return false
	await complete("b.bz3h.brief_41")
	if not await camp_tasks(): return false
	await complete("b.Glav.brief_49")
	check(value("q.gz3h.q18h") == 1,"earned Glav offer starts the siege quest")
	await enter("gz3h"); start(["VCheck#4#1"]); ticks(25)
	gate("bz3h",false,"active siege closes the camp passage")
	teleport(Vector2(125,207)); teleport(Vector2(81,183)); ticks(360)
	var attackers := range(1018011,1018021)
	kill(attackers)
	check(value("q.gz3h.q18h.3") == 1,"last siege attacker prevents the commander objective")
	kill([1018021])
	check(value("q.gz3h.q18h.4") == 1 and value("q.gz3h.q18h") == 1,"all attackers dead still require the living commander")
	gate("bz3h",false,"camp remains closed before the commander dies")
	await roundtrip("campaign_siege_last_commander",["q.gz3h.q18h","q.gz3h.q18h.4","z.bz3h"])
	kill([1018010])
	check(value("q.gz3h.q18h") == 2 and value("b.Glav.brief_50") == 1,"commander death completes siege and offers the real hand-in")
	gate("bz3h",true,"siege victory reopens the camp passage")
	if not await leave("bz3h"): return false
	await complete("b.Glav.brief_50")
	check(value("q.gz4h.q19h") == 1 and value("z.gz3h_gz4h") == 2,"actual siege hand-in accepts the bones quest and opens its route")
	return true

func camp_tasks() -> bool:
	check(value("b.Glav.brief_44") == 1 and value("b.merc10.brief_46") == 0,"actual camp arrival offers the nugget quest before the rescue quest")
	await complete("b.Glav.brief_44")
	check(value("q.gz3h.q16h") == 1,"real Glav offer starts the nugget quest")
	await enter("gz3h"); start(["VCheck#2#1"]); ticks(25)
	teleport(Vector2(50,322)); kill([1016001])
	check(value("q.gz3h.q16h") == 1 and not s.state.quest_items.has("goldnugget"),"killing the nugget carrier does not substitute for looting the body")
	loot(1016001); ticks(8)
	check(value("q.gz3h.q16h") == 2 and s.state.quest_items.has("goldnugget") and value("b.Glav.brief_45") == 1,"ordinary corpse loot completes the nugget quest and offers hand-in")
	await enter("bz3h"); await complete("b.Glav.brief_45")
	check(not s.state.quest_items.has("goldnugget") and value("b.merc10.brief_46") == 1,"actual nugget hand-in consumes its item and unlocks the rescuer offer")
	await complete("b.merc10.brief_46")
	await enter("gz3h"); start(["VCheck#3#1"]); ticks(40)
	var rescued: GameUnit = s.world.units.get(1017001)
	if not check(rescued != null and not rescued.dead,"rescue creates its original randomized actor"): return false
	var location := Vector2(154,375) if value("haradrand")>10 else Vector2(241,372)
	teleport(location)
	check(value("q.gz3h.q17h.4") == 1 and value("q.gz3h.q17h") == 1,"actual randomized meeting starts escort without completing its return")
	await roundtrip("campaign_camp_rescuer",["q.gz3h.q17h","q.gz3h.q17h.4","haradrand"])
	rescued = s.world.units.get(1017001)
	teleport(Vector2(80,180),rescued); ticks(20)
	check(value("q.gz3h.q17h") == 2 and value("b.merc7.brief_47") == 1,"rescued actor reaching camp opens its real conversation")
	await enter("bz3h"); await complete("b.merc7.brief_47")
	check(value("q.gz3h.q17oh") == 1 and value("b.Glav.brief_49") == 0,"real rescue conversation starts the spear prerequisite before the siege")
	await enter("gz3h"); start(["VCheck#5#1"]); ticks(25)
	teleport(Vector2(344,277)); use(1017101,false)
	check(value("q.gz3h.q17oh") == 1 and not s.state.quest_items.has("superspear"),"spear container cannot bypass its original key")
	if not loot_key("zone3spear.mob","key01"): return false
	use(1017101)
	check(value("q.gz3h.q17oh") == 2 and s.state.quest_items.has("superspear") and not s.state.quest_items.has("key01"),"normal keyed spear pickup completes the rescue follow-up")
	check(value("b.merc7.brief_48") == 1 and value("b.Glav.brief_49") == 1,"actual spear completion offers both hand-in and siege")
	await roundtrip("campaign_camp_spear",["q.gz3h.q16h","q.gz3h.q17h","q.gz3h.q17oh","b.Glav.brief_49"],["superspear"])
	await enter("bz3h"); await complete("b.merc7.brief_48")
	return true

func bones_and_boss() -> void:
	await enter("gz4h"); start(["VCheck#0#1","VCheck#0#3","VCheck#0#7"]); ticks(30)
	check(s.world.units.has(1019001) and s.world.units[1019001].dead,"bones quest creates its three original corpses")
	teleport(Vector2(222,119)); ticks(25)
	if not await wait_zone("bz4h"): return
	await complete("b.bz4h.brief_51")
	check(value("q.gz4h.q20h") == 1,"actual Duoti introduction starts the companion boss quest")
	await enter("gz4h"); start(["VCheck#0#3","VCheck#0#7"]); ticks(50)
	gate("bz4h",false,"joint quest locks the Duoti return")
	gate("gz3h_gz4h",false,"joint quest locks the desert return")
	teleport(Vector2(66,84))
	loot(1019001); loot(1019002)
	check(value("q.gz4h.q19h") == 1 and not s.state.quest_items.has("sackofbones"),"two looted corpses do not produce the complete sack of bones")
	await roundtrip("campaign_bones_last_body",["q.gz4h.q19h","q.gz4h.q20h","z.bz4h"])
	loot(1019003)
	check(value("q.gz4h.q19h") == 2 and s.state.quest_items.has("sackofbones"),"ordinary loot of the third corpse completes bones quest")
	gate("bz4h",false,"bones completion alone cannot reopen the joint return gate")
	kill([1020001])
	check(value("q.gz4h.q20h") == 2,"actual boss death completes the second quest")
	gate("bz4h",true,"both completed quests reopen Duoti")
	gate("gz3h_gz4h",true,"both completed quests reopen the desert route")
	stable("joint bones and boss completion")
	await roundtrip("campaign_bones_and_boss_done",["q.gz4h.q19h","q.gz4h.q20h","z.bz4h","z.gz3h_gz4h"],["sackofbones"])
	await leave("bz4h")
