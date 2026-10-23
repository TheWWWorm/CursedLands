extends "lia_kel_support.gd"
## Starts after the prison escape and Shelter introductions. Completes the
## poison and disguise objectives from actual map actions, then the Kel/elder
## handoff. Only those earlier introduction flags and the party are supplied.
const POISON := "q.gz1h.q2h"
const DISGUISE := "q.gz1h.q3h"

func _ready() -> void: run.call_deferred()

func run() -> void:
	boot()
	s.state.create_party("FPrison")
	s.state.add_party_unit("FPrison","Hero","Hero1")
	s.state.add_party_unit("FPrison","merc2","merc2")
	s.state.set_current_party("FPrison")
	s.state.set_var(0,"b.bz2h.brief_6",1)
	await enter("gz1h")
	start(["VCheck#2#1","VCheck#3#1"]); ticks(30)
	check(value(POISON+".1") == 0 and value(DISGUISE+".1") == 0,
		"poison and disguise do not start before their offered conversations")
	await enter("bz2h")
	await complete("b.bz2h.brief_6")
	await complete("b.Elder.brief_9")
	check(value(POISON) == 1,"Elder's actual introduction starts poison quest")
	await enter("gz1h")
	start(["VCheck#2#1"]); ticks(25)
	check(value(POISON+".1") == 1,"poison first objective armed after authored delay")
	teleport(Vector2(173,100))
	check(value(POISON+".1") == 1 and value(POISON+".2") == 0,"later poison area cannot bypass first objective")
	teleport(Vector2(132,103))
	check(value(POISON+".1") == 2 and value(POISON+".2") == 1,"first poison area advances one objective")
	teleport(Vector2(173,100))
	check(value(POISON+".2") == 2 and value(POISON+".3") == 1,"second poison area waits for container use")
	check(not s.state.quest_items.has("dragonpoison"),"poison item is not granted before opening its container")
	use(1020002); ticks(20)
	check(s.state.quest_items.has("dragonpoison") and value(POISON+".4") == 1,"authored container grants poison and starts rat objective")
	kill([1020005,1020006])
	check(value(POISON) == 1,"last living rat prevents poison completion")
	await roundtrip("lia_poison_last_rat",[POISON,POISON+".4"],["dragonpoison"])
	kill([1020007])
	check(value(POISON) == 2 and value(POISON+".4") == 2 and value("b.Elder.brief_11") == 1,
		"last rat completes poison and offers actual elder hand-in")
	await enter("bz2h")
	await complete("b.Elder.brief_11")
	check(not s.state.quest_items.has("dragonpoison"),"elder hand-in consumes the actual poison item")
	check(value("b.merc8.brief_14") == 1,"elder unlocks Shaina's disguise offer")
	await complete("b.merc8.brief_14")
	check(value(DISGUISE) == 1,"Shaina's actual offer starts disguise quest")
	await enter("gz1h")
	start(["VCheck#3#1"]); ticks(25)
	check(value(DISGUISE+".1") == 1,"disguise starts with first objective pending")
	teleport(Vector2(139,34))
	check(value(DISGUISE+".3") == 0,"captive's location alone cannot bypass finding the key")
	teleport(Vector2(137,49))
	check(value(DISGUISE+".1") == 2 and value(DISGUISE+".2") == 1,"finding authored key carrier advances the first objective")
	teleport(Vector2(139,34))
	check(value(DISGUISE+".2") == 1 and value(DISGUISE+".3") == 0,"captive remains gated without the cage key")
	var carrier: GameUnit = s.world.units.get(1020001)
	if check(carrier != null,"authored cage-key carrier exists"):
		teleport(Vector2(137,49))
		hero().stats.dex = 999.0
		s.steal(hero(),carrier); ticks()
	check(s.state.quest_items.has("cagekey00"),"stealing actual carrier obtains original cage key")
	check(value(DISGUISE+".2") == 2,"obtaining the original item completes key objective")
	teleport(Vector2(139,34))
	check(not s.state.quest_items.has("cagekey00") and value(DISGUISE+".4") == 1,
		"captive-area trigger consumes key and starts two-guard objective")
	kill([997002])
	check(value(DISGUISE+".4") == 1,"one surviving guard keeps rescue objective pending")
	await roundtrip("lia_disguise_last_guard",[DISGUISE,DISGUISE+".4"])
	kill([997004])
	check(value(DISGUISE+".4") == 2 and value(DISGUISE+".5") == 1,"last guard starts return-to-Shelter objective")
	check(value(DISGUISE) == 1,"disguise does not complete before return area")
	# This return area is normally retained from the escape quest. The
	# prepared post-prologue entry did not run that route, so register only
	# its authored geometry through the same command, not any quest outcome.
	vm()._call("AddRoundToArea",[[ScriptParser.N_NUM,2],[ScriptParser.N_NUM,106.468],
		[ScriptParser.N_NUM,227.865],[ScriptParser.N_NUM,12]],ScriptVM.Instance.new())
	teleport(Vector2(106.468,227.865))
	check(value(DISGUISE) == 2 and value(DISGUISE+".5") == 2,"actual return area completes all disguise objectives")
	check(value("b.merc8.brief_15") == 1,"completed disguise offers Shaina hand-in")
	await roundtrip("lia_disguise_ready",[DISGUISE,"b.merc8.brief_15"])
	await enter("bz2h")
	start(["VCheck#1#2","VCheck#1#2a"])
	var money := s.state.money
	await complete("b.merc8.brief_15")
	check(s.state.money == money+230,"authored disguise hand-in pays exactly 230")
	ticks(35); await frames(8)
	freeze()
	check(s.state.current_party == "FSusel" and value("Trans") == 2,"authored transformation redeploys the disguised party")
	var kel: GameUnit = vm()._by_name("merc2")
	check(kel != null and not kel.hidden,"Kel is present and visible for the next conversation")
	await complete("b.merc2.n3_2")
	await complete("b.Elder.brief_17")
	await complete("b.Elder.brief_18")
	check(value("z.gz1h_gz2h") == 2,"Kel and elder dialogue chain opens next main route")
	await roundtrip("lia_early_route_open",[POISON,DISGUISE,"z.gz1h_gz2h","b.merc2.n3_2"])
	await finish("LIA_KEL_EARLY_STORY","Prepared post-prison Shelter checkpoint; actual poison/disguise objective bodies, carried key, container use, normal topic selection/close, one-enemy and missing-item negatives, full saves and Kel/elder route. Teleported movement and cheated kills; not a full campaign or independent original executable replay.")
