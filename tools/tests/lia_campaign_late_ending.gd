extends "lia_campaign_late_support.gd"
## Prepared post-rescue Jigran3 party and earlier q17j completion. From the
## actual BSon337 conversation onward, every quest, item, gate and transition
## is earned by installed dialogue/trigger handlers. Combat and walking use
## cheats. Native execution/ending footage is collected independently.
var events: Array = []

func _ready() -> void: run.call_deferred()

func stop_at(label: String) -> void:
	await finish("LIA_CAMPAIGN_LATE_ENDING","Prepared post-rescue checkpoint; stopped before completing route: "+label)

func run() -> void:
	boot()
	s.state.god_modes[0] = 1
	s.state.create_party("Jigran3")
	s.state.add_party_unit("Jigran3","Hero","Hero3")
	s.state.add_party_unit("Jigran3","merc2","merc2")
	s.state.set_current_party("Jigran3")
	for key: String in ["q.gz35j.q17j","q.gz31j.q16j","z.gz34j"]: s.state.set_var(0,key,2)
	s.state.set_var(0,"b.Deva.brief_345",3)
	s.state.set_var(0,"b.BSon.brief_337",1)
	s.state.set_var(0,"z.gz34d1",1)
	s.state.set_var(0,"z.gz34j_gz34d1",1)
	game.event_presented.connect(func(event):events.append(event.duplicate(true)))
	await enter("bz31j")
	start(["VCheck#0#2","VCheck#0#3","VCheck#0#5"])
	check(value("b.Junofil.brief_341") == 0,"post-rescue crypt offer waits for the amulet return conversation")
	check(value("b.Baron.brief_347") == 0,"final battle offer waits for the two-creature quest")
	await complete("b.BSon.brief_337")
	check(value("b.Junofil.brief_341") == 1,"actual amulet return unlocks Junofil's final crypt offer")
	await complete("b.Junofil.brief_341")
	check(value("q.gz34d1.q18j") == 1 and value("z.gz34d1") == 2 and value("z.gz34j_gz34d1") == 2,
		"Junofil's actual briefing grants crypt quest and opens its map/route gates")
	await enter("gz34j")
	if not await normal_exit(3,"gz34d1"): await stop_at("crypt entry"); return
	ticks(30)
	check(value("q.gz34d1.q18j.1") == 1 and value("q.gz34d1.q18j.2") == 0,"crypt waits for its first key container")
	use(539149,false)
	check(value("q.gz34d1.q18j") == 1 and int(s.world.levers[539151].state) == 0,"crypt control rejects missing key and keeps door closed")
	use(539135)
	check(s.state.quest_items.has("jkey00") and value("q.gz34d1.q18j.1") == 2,"actual first crypt container grants JKey00")
	await roundtrip("lia_late_crypt_key",["q.gz34d1.q18j.1","q.gz34d1.q18j.2"],["jkey00"])
	use(539149)
	check(not s.state.quest_items.has("jkey00") and int(s.world.levers[539151].state) == 1,
		"keyed crypt control consumes its key and opens the physical door")
	use(539134)
	check(value("q.gz34d1.q18j") == 2 and value("b.Junofil.brief_343") == 1,"last crypt container completes quest and offers report")
	poll_once("crypt reward")
	await roundtrip("lia_late_crypt_complete",["q.gz34d1.q18j","b.Junofil.brief_343"])
	if not await normal_exit(1,"gz34j"): await stop_at("crypt return"); return
	await enter("bz31j")
	await complete("b.Junofil.brief_343")
	check(s.state.quest_items.has("jcontrol") and value("b.Doctor.brief_344") == 1,"Junofil report grants control item and Doctor continuation")
	await enter("bz32j")
	await complete("b.Doctor.brief_344")
	check(value("q.gz34j.q20j") == 1,"Doctor grants the two-creature quest through actual reward data")
	await enter("gz34j")
	start(["VCheck#3#1"]); ticks(30)
	check(s.world.units.has(1020001) and s.world.units.has(1020002),"accepted creature quest spawns both authored targets")
	check(s.save_game("lia_late_creatures_waiting") == OK,"save both live creatures before negative branches")
	for id in [1020001,1020002]:
		kill([id]); ticks(20)
		check(value("q.gz34j.q20j") == 3 and value("b.Doctor.brief_348") == 0,"dead required creature fails the quest instead of allowing progression: "+str(id))
		check(await s.load_game_shown("lia_late_creatures_waiting"),"restore independent living-creature branch")
		freeze()
	var cyclop: GameUnit = s.world.units[1020001]
	var dragon: GameUnit = s.world.units[1020002]
	party_at(cyclop.pos+Vector2(15.1,0))
	check(value("q.gz34j.q20j.1") == 1,"creature just outside original radius remains unrecruited")
	party_at(cyclop.pos+Vector2(14.9,0))
	check(value("q.gz34j.q20j.1") == 2 and value("q.gz34j.q20j") == 1,"one recruited creature cannot complete the pair quest")
	party_at(dragon.pos+Vector2(14.9,0))
	check(value("q.gz34j.q20j.2") == 2 and value("q.gz34j.q20j") == 2,"approaching both living creatures completes the original pair quest")
	check(value("b.Doctor.brief_348") == 1,"pair completion offers its actual Doctor report")
	poll_once("two-creature completion")
	await roundtrip("lia_late_creatures_complete",["q.gz34j.q20j","q.gz34j.q20j.1","q.gz34j.q20j.2"])
	await enter("bz32j"); await complete("b.Doctor.brief_348")
	await enter("bz31j"); start(["VCheck#0#3"])
	check(value("b.Baron.brief_347") == 1,"earned creature completion unlocks the Baron final battle conversation")
	await complete("b.Baron.brief_347")
	if not await wait_zone("gz35j"): await stop_at("Baron battle departure"); return
	ticks(100)
	check(value("q.gz35j.q21j") == 1 and value("q.gz35j.q21j.1") == 1,"Baron dialogue grants and starts the actual battle quest")
	check(not s._exit_is_open(1),"battle's authored gate closes ordinary retreat until its sequence finishes")
	check(s.world.units.has(1021101) and s.world.units.has(1021139),"battle AddMob created both ends of the 39-enemy group")
	check(vm().globals.get("ArEvil",[]).size() == 39 and vm().globals.get("Kanians",[]).size() == 34,
		"battle addon shares both populated groups with the parent quest script")
	await roundtrip("lia_late_battle_all_alive",["q.gz35j.q21j.1"])
	check(vm().globals.get("ArEvil",[]).size() == 39 and vm().globals.ArEvil.all(func(u):return not u.dead),
		"reloaded battle keeps every living addon actor in the shared parent group")
	var foes: Array = range(1021101,1021139)
	kill(foes)
	check(value("q.gz35j.q21j.1") == 1,"last living battle enemy prevents victory")
	await roundtrip("lia_late_battle_last_alive",["q.gz35j.q21j.1"])
	check(vm().globals.ArEvil.filter(func(u):return not u.dead).size() == 1 and not s.world.units[1021139].dead,
		"mid-battle reload preserves the one remaining enemy and its unfinished gate")
	kill([1021139])
	check(value("q.gz35j.q21j.1") == 2 and value("q.gz35j.q21j.2") == 1,"all 39 enemy deaths advance only the battle objective")
	ticks(610)
	check(value("q.gz35j.q21j") == 1,"battle victory still requires the original portal approach")
	await roundtrip("lia_late_battle_portal",["q.gz35j.q21j.1","q.gz35j.q21j.2"])
	party_at(Vector2(34,221)); ticks(20)
	if not await wait_zone("cz4j"): await stop_at("battle portal"); return
	check(value("q.gz35j.q21j") == 2,"actual portal approach completes battle quest before travel")
	if not await advance_until(func():return value("b.Firez.brief_349") == 1,"actual final arrival scene offers Firez's conversation"):
		await stop_at("Firez arrival"); return
	check(value("q.gz36j.q22j") == 0,"final quest waits for Firez's actual briefing")
	await complete("b.Firez.brief_349")
	if not await wait_zone("gz36j"): await stop_at("final chamber entry"); return
	ticks(30)
	check(value("q.gz36j.q22j") == 1 and value("q.gz36j.q22j.1") == 1,"Firez briefing grants and starts the actual final quest")
	for id in [1022102,1022103,1022104]:
		use(id,false)
		check(value("q.gz36j.q22j.5") == 0,"out-of-order lever cannot activate final boss phase: "+str(id))
	use(1022101)
	check(value("q.gz36j.q22j.1") == 2 and value("q.gz36j.q22j.2") == 1,"first lever completes only first objective")
	use(1022103,false)
	use(1022102)
	check(value("q.gz36j.q22j.2") == 2 and value("q.gz36j.q22j.3") == 1,"second lever enables third objective")
	await roundtrip("lia_late_final_two_levers",["q.gz36j.q22j.1","q.gz36j.q22j.2","q.gz36j.q22j.3"])
	use(1022104,false)
	use(1022103); use(1022104)
	check(value("q.gz36j.q22j.3") == 2 and value("q.gz36j.q22j.4") == 2 and value("q.gz36j.q22j.5") == 1,"all four ordered levers enable the boss objective")
	check(not s.ending_active and value("q.gz36j.q22j") == 1,"living final boss prevents campaign completion")
	check(s.save_game("lia_late_final_boss") == OK,"save earned final boss checkpoint")
	var endings_before := events.filter(func(e):return e.get("t") == "ending").size()
	kill([666666]); ticks(20); await frames(4)
	check(value("q.gz36j.q22j.5") == 2 and value("q.gz36j.q22j") == 2,"actual boss death completes final objective and quest")
	check(s.ending_active and s.world.process_mode == Node.PROCESS_MODE_DISABLED,"authored EndofGame transition reaches ending state and stops world")
	check(events.filter(func(e):return e.get("t") == "ending").size() == endings_before+1,"authored ending event is emitted exactly once")
	var completed := accounting(); ticks(40); await frames(2)
	check(accounting() == completed and events.filter(func(e):return e.get("t") == "ending").size() == endings_before+1,"completed finale cannot replay rewards or ending on later polls")
	check(await s.load_game_shown("lia_late_final_boss"),"reload earned boss checkpoint for rerunnable final transition")
	freeze()
	check(not s.ending_active and value("q.gz36j.q22j.5") == 1 and not s.world.units[666666].dead,"reload restores living boss and completed lever prerequisites")
	kill([666666]); ticks(20); await frames(4)
	check(s.ending_active and value("q.gz36j.q22j") == 2,"reloaded earned checkpoint can complete campaign again")
	await finish("LIA_CAMPAIGN_LATE_ENDING","Prepared restored Jigran3 party, q17j/q16j completed, and BSon337 offered. Actual BSon337→Junofil341→keyed crypt q18j and ordinary entry/return→Junofil343→Doctor344→both living creature approaches q20j (independent dead-target failures)→Doctor348/Baron347→39-enemy battle q21j→portal→Firez349→four ordered levers→boss death→authored EndofGame. Progress is carried throughout; travel between settlements is accelerated, combat uses kill cheats, movement uses teleports. Save/reload and once-only completion covered. This loaded-map regression is not native executable proof or an ordinary no-cheat playthrough.")
