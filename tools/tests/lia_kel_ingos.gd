extends "lia_kel_support.gd"
## Haburu's first pending topic is the supplied checkpoint. Each subsequent
## topic is unlocked by the preceding real quest, selected and closed normally.

func _ready() -> void: run.call_deferred()

func haburu(number: int) -> void:
	await enter("bz23k")
	await complete("b.Haburu.fq%d"%number)

func run() -> void:
	boot()
	s.state.set_var(0,"b.Haburu.fq15",1)
	await haburu(15)
	await enter("gz23k")
	start(["VCheck#5#1","VCheck#5#2"]); ticks(8)
	check(value("q.gz23k.fq15") == 0,"first Haburu quest waits for actual object use")
	use(4216)
	check(value("q.gz23k.fq15") == 2 and value("b.Haburu.fq16") == 1,
		"first Haburu object completes quest and offers the next conversation")
	await haburu(16)
	await enter("gz21k")
	start(["VCheck#8#1","VCheck#8#2"]); ticks(8)
	check(value("zone21_fq16") == 1 and value("q.gz21k.fq16") == 0,"second Haburu quest awaits its treasure")
	var money := s.state.money
	use(2016001)
	check(value("q.gz21k.fq16") == 2 and value("b.Haburu.fq17") == 1 and s.state.money == money+40000,
		"actual second treasure pays once and unlocks water quest")
	await haburu(17)
	check(s.state.quest_items.has("kwater01"),"normal Haburu water briefing grants the original empty vessel")
	await enter("gz22k")
	start(["VCheck#5#1","VCheck#5#2","VCheck#5#3","VCheck#5#4","VCheck#5#5","VCheck#5#6","VCheck#5#7"]); ticks(8)
	use(2017002,false)
	check(value("q.gz22k.fq17") == 0,"empty vessel cannot water the first tree")
	for index in 5:
		use(2017001); ticks(20)
		check(s.state.quest_items.has("kwater02") and not s.state.quest_items.has("kwater01"),"refill %d replaces empty vessel with full vessel"%(index+1))
		use(2017002+index); ticks(8)
		if index < 4:
			check(s.state.quest_items.has("kwater01") and not s.state.quest_items.has("kwater02"),"tree %d consumes water and returns empty vessel"%(index+1))
			check(value("q.gz22k.fq17") == 0,"water quest stays pending until fifth tree")
		if index == 1:
			await roundtrip("lia_haburu_two_trees",["q.gz22k.fq17"],["kwater01"])
	check(value("q.gz22k.fq17") == 2 and value("b.Haburu.fq18") == 1,"fifth tree completes water quest and offers cow quest")
	check(not s.state.quest_items.has("kwater02") and not s.world.lever_sys.usable(2017001),"final tree consumes water and disables refill")
	# The installed script intentionally remains the reference: it reports
	# QuestComplete("fq18") here despite setting q.gz22k.fq17. Do not invent
	# a corrected XP award in this regression.
	await roundtrip("lia_haburu_water_done",["q.gz22k.fq17","b.Haburu.fq18"])
	await haburu(18)
	await enter("gz23k")
	start(["VCheck#6#1","VCheck#6#2"]); ticks(8)
	use(4451)
	var cow: GameUnit = s.world.units.get(4586)
	teleport(Vector2(216,24),cow)
	check(value("q.gz23k.fq18") == 0,"cow outside destination radius does not complete quest")
	teleport(Vector2(216,8),cow)
	check(value("q.gz23k.fq18") == 2 and value("b.Haburu.fq19") == 1,"cow destination trigger completes quest and unlocks fragment clue")
	await enter("gz24k")
	start(["Lever#0#3","Lever#0#4","Lever#0#5","VCheck#1#1"])
	use(4374,false)
	check(value("q.gz24k.fq19") == 0 and not s.state.quest_items.has("kel3"),"fragment route stays locked before Haburu's key briefing")
	await haburu(19)
	check(s.state.quest_items.has("kkey07"),"normal final Haburu briefing grants original fragment-route key")
	await enter("gz24k")
	start(["Lever#0#3","Lever#0#4","Lever#0#5","VCheck#1#1"])
	for pair: Array in [[4374,4555],[14357306,4305],[14357307,4301]]:
		use(pair[0])
		check(int(s.world.levers[pair[1]].state) == 1,"original key opens route door "+str(pair[1]))
	money = s.state.money
	use(4367)
	check(s.state.quest_items.has("kel3") and value("q.gz24k.fq19") == 2 and s.state.money == money+70000,
		"actual keyed route chest grants third Rod fragment and 70000 once")
	await roundtrip("lia_kel_third_fragment",["q.gz24k.fq19"],["kel3"])
	var before := accounting()
	await enter("bz23k"); await enter("gz24k"); ticks(20)
	check(accounting() == before and s.state.quest_items.has("kel3"),"third fragment survives revisit without duplicate chest rewards")
	await finish("LIA_KEL_INGOS","Haburu fq15..fq19 with first pending topic supplied; each later topic unlocked by real preceding quest and completed through dialogue controls, actual water inventory and keyed doors/chest, save/reload and revisit. Cow trigger tested with teleported position, not herding AI; no full campaign/native executable claim.")
