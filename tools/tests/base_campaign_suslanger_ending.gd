extends "base_campaign_suslanger_support.gd"
## Prepared Gl70 offer, earned BrokenToy and previously hired merc7. These
## earlier inputs come from the independent town/necromancer checkpoints.
## q71h/q72h/q73g, portal controls, role swap and ending remain unearned.
var presented: Array = []
func _ready() -> void: run.call_deferred()

func stop_at(label: String) -> void:
	await finish("BASE_CAMPAIGN_SUSLANGER_ENDING","Prepared Gl70/BrokenToy/merc7 boundary; stopped before completion: "+label)

func group_ids(name: String) -> Array:
	return Array(vm().globals.get(name,[])).filter(func(u):return u is GameUnit).map(func(u):return u.uid)

func run() -> void:
	boot(); s.state.god_modes[0] = 1; s.mod_config.rules.auto_exit = 0
	s.state.set_var(0,"b.Glav.Gl70",1); s.state.add_item("BrokenToy")
	var mercs := EIMob.load_bytes(GameData.read_file("maps/bz14h.mob")).objects.filter(func(o):return o.kind == "UNIT" and String(o.name).to_lower() == "merc7")
	if not check(mercs.size() == 1,"prepared prior hired companion uses exactly one original merc7 record"): await stop_at("mercenary fixture"); return
	s.state.make_merc(7,mercs[0]); s.state.set_var(0,"apartyn7",1); s.state.set_var(0,"amerc_7",1)
	game.event_presented.connect(func(e):presented.append(e.duplicate(true)))
	await enter("bz14h"); await complete("b.Glav.Gl70")
	check(value("q.gz19h.q71h") == 1 and value("z.gz19h") == 1,"actual final Glav offer accepts city meeting and reveals its destination")
	await enter("gz18h")
	if not await leave("gz18h_gz19h","gz19h"): await stop_at("city departure"); return
	settle_loaded(["VTriger#0#13","VCheck#0#26"])
	place_party(Vector2(399,430)); check(value("q.gz19h.q71h") == 1,"outside the city meeting area cannot complete arrival")
	place_party(Vector2(405,430)); check(value("q.gz19h.q71h") == 2 and value("b.bz18h.s71") == 1,"actual city meeting area completes q71h and offers the elder encounter")
	if not await leave("bz18h"): await stop_at("elder camp"); return
	await complete("b.bz18h.s71"); ticks(20)
	check(value("b.elder.s71_1") == 1 and value("q.gz19h.q72h") == 0,"actual meeting reveals elder and offers infiltration briefing")
	await complete("b.elder.s71_1")
	check(value("q.gz19h.q72h") == 1,"ordinary elder briefing starts the actual final city quest")
	if not await leave("gz19h_bz18h","gz19h"): await stop_at("elder betrayal return"); return
	settle_loaded(["VCheck#0#6","VCheck#0#7","VCheck#0#32","VCheck#0#73","VCheck#0#74","VCheck#0#75","VCheck#0#177","VCheck#0#180",
		"VCheck#0#222","VTriger#0#264","VTriger#0#278","VCheck#0#286","VTriger#0#296","VCheck#0#304","VCheck#0#305",
		"VCheck#0#310","VCheck#0#314","VTriger#0#333","VCheck#0#334","VCheck#0#352","VCheck#0#368","VCheck#0#379","VCheck#0#380",
		"VTriger#0#415","VTriger#0#416","VCheck#0#437","VCheck#0#447","VCheck#0#448"]); ticks(15)
	var ambush := group_ids("s1")
	check(ambush.size() == 22,"earned elder briefing installs all 22 authored betrayal enemies")
	if ambush.size() != 22: await stop_at("betrayal addon"); return
	var survivor: int = ambush.pop_back(); kill(ambush)
	check(value("q.gz19h.q72h.1") == 1,"last living betrayal enemy prevents clearing that objective")
	await roundtrip("base_city_last_ambusher",["q.gz19h.q72h","q.gz19h.q72h.1"])
	check(group_ids("s1").size() == 22 and not s.world.units[survivor].dead,"save retains full authored group and its one living survivor")
	kill([survivor]); check(value("q.gz19h.q72h.1") == 2,"all betrayal enemies dead completes only first city objective")
	place_party(Vector2(480,335)); ticks(15)
	var guards := group_ids("a1")
	check(guards.size() == 8 and value("q.gz19h.q72h.35") == 1,"entering original gate alarm area installs its eight reinforcements")
	if guards.size() != 8: await stop_at("gate alarm addon"); return
	check(s.save_game("base_city_alarm_branch") == OK,"save living gate patrol before independent escape/kill branches")
	var last_guard: int = guards.pop_back(); kill(guards)
	check(value("q.gz19h.q72h.35") == 1,"one living gate guard retains alarm objective while party remains inside gate area")
	kill([last_guard]); check(value("q.gz19h.q72h.35") == 2,"killing the full original gate patrol clears the alarm objective")
	check(await s.load_game_shown("base_city_alarm_branch"),"restore actual living patrol for independent nonlethal branch"); freeze()
	place_party(Vector2(10,430)); ticks(30)
	check(value("q.gz19h.q72h.35") == 2 and group_ids("a1").all(func(id):return not s.world.units[id].dead),"all living party members escaping the gate clears alarm without killing its guards (documented remake compatibility repair)")
	# The separate city sight alarm is also an authored path: approach an
	# existing sentry from the front, never manufacture its noticed list.
	var city_reinforcements := [1000206,1000207,1000215,1000221,1000228,1000231,1000234,1000243,1000247,1000249,1000259,1000269,1000270,1000283,1000288,1000297,1000298,1000299]
	start(["VCheck#0#428"])
	check(value("q.gz19h.q72h.34") == 0 and city_reinforcements.all(func(id):return not s.world.units.has(id)),"city sight alarm stays absent while no original city guard sees the party")
	var sentry: GameUnit = s.world.units[920978]
	teleport(sentry.pos+Vector2.from_angle(sentry.facing)*0.1); ticks(10)
	check(value("q.gz19h.q72h.34") == 1 and city_reinforcements.all(func(id):return s.world.units.has(id)),"actual city sentry sight installs all 18 original second-alarm reinforcements")
	await roundtrip("base_city_sight_alarm",["q.gz19h.q72h.34"])
	check(city_reinforcements.all(func(id):return s.world.units.has(id)),"save reload retains all sight-alarm reinforcements without duplication")
	teleport(Vector2(240,40))
	check(value("q.gz19h.q72h.34") == 2,"reaching the authored inner-city area clears the separate sight alarm")
	# Optional city rewards arise from their authored areas and chest uses.
	teleport(Vector2(103,486)); approach_object(736257)
	check(value("q.gz19h.qk16h") == 1 and value("q.gz19h.qk16h.2") == 2,"original hidden chest area and approach reveal first city treasure")
	var money_before := s.state.money; use(736257)
	check(value("q.gz19h.qk16h") == 2 and s.state.money == money_before+1000000,"first ordinary city chest grants its exact million reward")
	teleport(Vector2(80,318)); check(value("q.gz19h.qk17h") == 1,"second city treasure is discovered through its original area")
	use(980428)
	check(value("q.gz19h.qk17h") == 2 and s.state.items.has("keystone:feeblemind"),"second ordinary city chest awards its authored spell prototype")
	stable("both optional city treasures")
	teleport(Vector2(100,250)); teleport(Vector2(240,40))
	use(45622,false); use(45627,false); use(45631,false)
	check(not s.state.quest_items.has("minecontrolkey00"),"all mine-control branches reject a missing key")
	approach(564724); kill([564724]); loot(564724)
	check(s.state.quest_items.has("minecontrolkey00"),"first original mine guard yields control key through ordinary corpse loot")
	check(s.save_game("base_city_mine_branch") == OK,"save earned first mine key before alternative third-control branch")
	use(45631)
	check(not s.state.quest_items.has("minecontrolkey00") and int(s.world.levers[45630].state) == 1,"alternative third mine control consumes the earned key and activates its original replacement")
	check(await s.load_game_shown("base_city_mine_branch"),"restore earned key for main two-control path"); freeze()
	use(45622)
	check(not s.state.quest_items.has("minecontrolkey00") and int(s.world.levers[45621].state) == 1 and value("q.gz19h.q72h.7") == 2,"first mine control consumes its key and completes its original objective")
	approach(736019); kill([736019]); loot(736019)
	check(s.state.quest_items.has("minecontrolkey00"),"second original mine guard independently yields another control key")
	use(45627)
	check(not s.state.quest_items.has("minecontrolkey00") and int(s.world.levers[45626].state) == 1 and value("q.gz19h.q72h.11") == 2,"second mine control consumes its key and completes its objective")
	use(43968,false); use(43974,false)
	check(value("PState") == 0 and value("q.gz19h.q72h") == 1,"portal controls remain blocked without teleport key")
	approach(980429); await loot_key("zone19.mob","teleportkey00")
	teleport(Vector2(450,105)); approach(45655); teleport(Vector2(410,170))
	use(43974)
	check(value("PState") == 1 and value("q.gz19h.q72h") == 1,"one original portal control cannot complete the portal")
	await roundtrip("base_city_one_portal_control",["q.gz19h.q72h","PState","q.gz19h.q72h.24"],["teleportkey00","brokentoy"])
	teleport(Vector2(456.6,61)); ticks(160)
	check(value("q.gz19h.q72h") == 1 and s.zone_id == "gz19h","portal area still rejects the missing second control after its full delay")
	use(43968); ticks(165)
	check(value("PState") == 2 and value("q.gz19h.q72h") == 1,"both earned portal controls activate gate but still require actual portal approach")
	place_party(Vector2(456.6,61)); ticks(12)
	if not await wait_zone("bz7g"): await stop_at("earned final portal"); return
	check(value("q.gz19h.q72h") == 2 and value("b.bz7g.R72") == 1 and not s.state.quest_items.has("teleportkey00") and s.state.quest_items.has("brokentoy"),"actual portal completes city, removes spent keys and preserves required final device")
	# Retain actual final branch watchers in Rick's existing village.
	ticks(8); vm().instances.clear(); start(["VCheck#0#49","VCheck#0#56","VCheck#0#71"])
	await complete("b.bz7g.R72")
	check(not s.state.quest_items.has("brokentoy") and value("b.Rick.R72_3") == 1 and value("b.Rick.R72_1") == 0,"device hand-in consumes it and active companion forces actual farewell branch")
	await complete("b.Rick.R72_3")
	check(value("b.Rick.R72_1") == 0,"Rick's farewell conversation cannot transform hero while companion remains")
	await complete("b.merc7.n10_7")
	check(s.state.mercs.is_empty() and value("b.Rick.R72_1") == 1,"ordinary companion farewell removes mercenary and unlocks transformation")
	await roundtrip("base_final_ready_transform",["b.Rick.R72_3","b.Rick.R72_1"])
	await complete("b.Rick.R72_1"); ticks(65)
	check(s.state.current_party == "JunParty" and hero().info.name == "JunBoy" and value("b.Rick.R72_4") == 1,"authored transformation creates and redeploys original Jun protagonist")
	await complete("b.Rick.R72_4"); await complete("b.Deva.D72_5"); await complete("b.Rick.R72_6")
	check(value("b.Rick.R72_7") == 1 and value("q.gz20g.q73g") == 0,"actual Rick/Deva sequence offers final departure before final quest exists")
	await complete("b.Rick.R72_7"); ticks(8)
	if not await wait_zone("gz20g"): await stop_at("final chamber departure"); return
	settle_loaded(["VTriger#0#2","VCheck#0#3","VCheck#0#6","VCheck#0#11"]); ticks(155)
	check(value("q.gz20g.q73g") == 1 and not s.world.units[666666].dead and not s.ending_active,"authored chamber sequence leaves campaign incomplete while Jun Curse lives")
	await roundtrip("base_final_living_boss",["q.gz20g.q73g"])
	var ending_count := presented.filter(func(e):return e.get("t") == "ending").size()
	kill([666666]); ticks(75); await frames(4)
	check(value("q.gz20g.q73g") == 2 and s.ending_active and s.world.process_mode == Node.PROCESS_MODE_DISABLED,"actual final boss death completes q73g and reaches authored EndofGame")
	check(presented.filter(func(e):return e.get("t") == "ending").size() == ending_count+1,"actual ending event is emitted exactly once")
	var after := accounting(); ticks(100); await frames(2)
	check(accounting() == after and presented.filter(func(e):return e.get("t") == "ending").size() == ending_count+1,"later polls cannot replay final reward or ending")
	check(await s.load_game_shown("base_final_living_boss"),"restore earned living-boss checkpoint for rerun"); freeze()
	check(not s.ending_active and not s.world.units[666666].dead and value("q.gz20g.q73g") == 1,"reload restores live boss and unfinished campaign")
	kill([666666]); ticks(75); await frames(4)
	check(s.ending_active and value("q.gz20g.q73g") == 2,"restored earned checkpoint reaches actual ending again")
	await finish("BASE_CAMPAIGN_SUSLANGER_ENDING","Prepared prior Gl70 offer, earned BrokenToy and originally hired merc7; no measured completion assigned. Actual q71 meeting/elder briefing, 22-enemy betrayal, 8-guard alarm with last-survivor kill and independent living-escape compatibility branch, original city-sight alarm with 18 reinforcements and area escape, qk16h/qk17h chest rewards, both mine keys and independent third mine-control alternative, teleport key, one-control rejection/two-control portal delay and actual portal entry. Original Rick device hand-in, companion-forced farewell, Jun transformation, Deva/Rick departure and q73g actual boss death→EndofGame exactly once, plus restored-boss rerun. Ordinary dialogue/use/loot/travel and pending/completed save checks; combat and walking accelerated by kill/god/teleport cheats. Guard escape is an intentional remake repair; no native-executable parity claim.")
