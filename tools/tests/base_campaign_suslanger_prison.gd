extends "base_campaign_suslanger_support.gd"
## Prepared Suslanger arrival: the original HeroAlone party and Hns59 offer.
## All q60h-q63h outcomes, Nalo swaps, keys, cave bridges and six optional
## canyon quests are earned by authored handlers. Walking/combat use cheats.
func _ready() -> void: run.call_deferred()

func run() -> void:
	boot(); chapter("HeroAlone","Human Hero Hadagan","Hero","")
	s.state.set_var(0,"b.bz13h.Hns59",1)
	await enter("bz13h")
	check(value("q.gz15h.q60h") == 0,"canyon quest waits for the original arrival briefing")
	await complete("b.bz13h.Hns59")
	if not await wait_zone("gz15h"): await finish("BASE_CAMPAIGN_SUSLANGER_PRISON","Stopped after actual arrival briefing"); return
	settle_loaded(["VCheck#0#16","VCheck#0#71","VCheck#0#72","VCheck#0#103","VTriger#0#109","VTriger#0#257",
		"VCheck#0#38","VTriger#0#43","VTriger#0#48","VCheck#0#51","VCheck#0#58","VCheck#0#60",
		"VCheck#0#113","VCheck#0#126","VCheck#0#133","VTriger#0#290","VTriger#0#294","VTriger#0#295",
		"VCheck#0#316","VCheck#0#317","VCheck#0#318"])
	check(value("q.gz15h.q60h") == 1 and value("q.gz15h.q60h.1") == 1,"arrival conversation grants canyon quest")
	gate("gz15h_gz16h",false,"cave route remains closed before escape")
	teleport(Vector2(50,275)); check(value("q.gz15h.qh1h") == 1,"upper bonus chest is discovered by its original area")
	var money_before := s.state.money
	use(43397)
	check(value("q.gz15h.qh1h") == 2 and s.state.money == money_before+50000,"upper chest ordinary use completes optional quest and awards 50000")
	teleport(Vector2(244,51)); check(value("q.gz15h.qh2h") == 1,"lower bonus chest is discovered by its original area")
	money_before = s.state.money; use(43398)
	check(value("q.gz15h.qh2h") == 2 and s.state.money == money_before+50000,"lower chest ordinary use completes optional quest and awards 50000")
	for i in 3:
		var id := 338769+i
		var q := "q.gz15h.qh"+str(i+3)+"h"
		approach_object(id); check(value(q) == 1,"approach discovers optional shrine "+q)
		use(id); check(value(q) == 2,"ordinary shrine use completes "+q)
	stable("canyon optional rewards")
	teleport(Vector2(199,321)); check(value("q.gz15h.q60h.1") == 2 and value("q.gz15h.q60h.2") == 1,"canyon final approach still requires its exit control")
	await roundtrip("base_prison_canyon_gate",["q.gz15h.q60h","q.gz15h.q60h.3","q.gz15h.qh1h","q.gz15h.qh2h","q.gz15h.qh3h","q.gz15h.qh4h","q.gz15h.qh5h"])
	use(338794)
	check(value("q.gz15h.q60h.2") == 2,"ordinary finish-gate interaction advances its authored objective")
	teleport(Vector2(209,319)); ticks(50)
	if not await wait_zone("bz13h"): await finish("BASE_CAMPAIGN_SUSLANGER_PRISON","Stopped after earned q60h"); return
	check(value("q.gz15h.q60h") == 2 and value("b.Nalo.Kr60") == 1,"actual canyon endpoint completes q60h and offers Nalo")
	await complete("b.Nalo.Kr60")
	if not await wait_zone("gz15h"): await finish("BASE_CAMPAIGN_SUSLANGER_PRISON","Stopped at Nalo entry"); return
	settle_loaded(["VCheck#0#13","VCheck#0#21","VCheck#0#83","VCheck#0#147","VCheck#0#152"])
	check(s.state.current_party == "Pretty" and hero().info.name == "Nalo" and value("q.gz15h.q61h") == 1,"actual Nalo conversation supplies the playable rescue party and quest")
	use(338795,false)
	check(value("q.gz15h.q61h") == 1 and not s.state.quest_items.has("herocagekey00"),"rescue cell remains locked before earning its key")
	approach(43400)
	check(value("q.gz15h.q61h.1") == 2,"seeing the original key carrier advances the rescue search")
	await loot_key("zone15.mob","herocagekey00")
	check(value("q.gz15h.q61h.2") == 2 and value("q.gz15h.q61h.3") == 1,"ordinary corpse loot advances only the rescue key objective")
	await roundtrip("base_prison_nalo_key",["q.gz15h.q61h","q.gz15h.q61h.3"],["herocagekey00"])
	use(338795)
	check(value("q.gz15h.q61h") == 2 and not s.state.quest_items.has("herocagekey00"),"normal cell use consumes earned key and completes rescue")
	ticks(45)
	if not await wait_zone("bz13h"): await finish("BASE_CAMPAIGN_SUSLANGER_PRISON","Stopped after earned rescue"); return
	check(s.state.current_party == "HeroAlone" and value("b.Nalo.Kr61") == 1,"authored rescue return restores the captive protagonist for Nalo's report")
	await complete("b.Nalo.Kr61")
	if not await wait_zone("gz15h"): await finish("BASE_CAMPAIGN_SUSLANGER_PRISON","Stopped at Nalo report"); return
	# Earlier checks deliberately isolated their threads. Resume the authored
	# waiting roots after the earned quest change on this persisted map.
	start(["VCheck#0#1","VCheck#0#10","VCheck#0#26","VCheck#0#80","VCheck#0#171","VCheck#0#218","VCheck#0#222","VTriger#0#236","VCheck#0#241","VCheck#0#319"])
	ticks(40)
	check(s.state.current_party == "" and value("q.gz15h.q62h") == 1,"normal Nalo report restores the main party and starts the escape quest")
	check(s.world.units.has(1006217) and s.world.units.has(1006187),"authored night encounter installs both actual key carriers")
	check(vm().globals.get("Students",[]).size() == 3,"night addon populates the optional student group")
	check(not s._exit_is_open(1),"night escape cannot leave before opening its final keyed gate")
	use(338776,false); use(338768,false)
	approach(1006217)
	await loot_key("zone15night.mob","hadogancagekey00")
	check(value("q.gz15h.q62h.2") == 2 and value("q.gz15h.q62h.3") == 1,"night gate key is earned through ordinary loot")
	use(338776)
	check(not s.state.quest_items.has("hadogancagekey00") and value("q.gz15h.q62h.3") == 2,"night main gate consumes its actual key")
	use(338779)
	check(value("q.gz15h.q62h.4") == 2 and value("LongD") == 1,"optional beast-release lever earns the distraction branch")
	approach(1006214)
	check(value("q.gz15h.qh6h.2") == 1,"seeing the night students reveals the optional combat objective")
	kill([1006214,1006215]); check(value("q.gz15h.qh6h") < 2,"one surviving student prevents optional completion")
	await roundtrip("base_prison_last_student",["q.gz15h.q62h","q.gz15h.qh6h.2"])
	kill([1006216]); check(value("q.gz15h.qh6h") == 2,"all authored students dead completes optional qh6h")
	teleport(Vector2(112,320)); approach(1006187)
	check(value("q.gz15h.q62h.7") == 1,"living final cave guard keeps its combat objective pending")
	await loot_key("zone15night.mob","hadogancavekey00")
	check(value("q.gz15h.q62h.8") == 2 and value("q.gz15h.q62h.9") == 1,"final guard corpse yields actual cave key")
	await roundtrip("base_prison_cave_key",["q.gz15h.q62h","q.gz15h.q62h.9"],["hadogancavekey00"])
	use(338768)
	check(value("q.gz15h.q62h") == 2 and value("q.gz16h.q63h") == 1 and not s.state.quest_items.has("hadogancavekey00"),"normal cave gate consumes key, completes escape and starts cave crossing")
	stable("night escape and optional student rewards")
	if not await leave("gz15h_gz16h","gz16h"): await finish("BASE_CAMPAIGN_SUSLANGER_PRISON","Stopped at earned cave route"); return
	settle_loaded(["VCheck#0#1","VCheck#0#4","VCheck#0#7","VCheck#0#12","VTriger#0#17","VTriger#0#24","VTriger#0#31","VTriger#0#36"])
	check(int(s.world.levers[16330].state) == 1 and int(s.world.levers[16331].state) == 1,"both original cycled bridges begin raised")
	teleport(Vector2(48,40)); use(16426)
	check(value("q.gz16h.q63h.2") == 2 and int(s.world.levers[16330].state) == 0,"first cave control moves its authored bridge")
	teleport(Vector2(97,104)); teleport(Vector2(170,32))
	await roundtrip("base_cave_second_bridge",["q.gz16h.q63h","q.gz16h.q63h.4","q.gz16h.q63h.5"])
	use(16433)
	check(value("q.gz16h.q63h.5") == 2 and int(s.world.levers[16331].state) == 0,"second cave control moves its authored bridge")
	teleport(Vector2(214,116)); check(value("q.gz16h.q63h") == 1,"crossing both bridges still requires meeting the rebels")
	approach(16505); ticks(65)
	if not await wait_zone("bz14h"): await finish("BASE_CAMPAIGN_SUSLANGER_PRISON","Stopped at earned rebel meeting"); return
	check(value("q.gz16h.q63h") == 2 and value("b.bz14h.Gl63") == 1,"actual rebel encounter completes cave crossing and offers town arrival")
	await complete("b.bz14h.Gl63")
	check(value("q.gz17h.qk32h") == 1 and value("z.gz17h") == 1,"actual arrival briefing opens desert and offers imperial seal retrieval")
	await roundtrip("base_suslanger_arrival_complete",["q.gz16h.q63h","q.gz17h.qk32h","z.gz17h"])
	await finish("BASE_CAMPAIGN_SUSLANGER_PRISON","Prepared original HeroAlone arrival and Hns59 offered; all q60h/q61h/q62h/q63h and optional qh1h-qh6h results earned. Actual Hns59→canyon finish use/area→Nalo rescue role→carrier loot/cell key consumption→Kr61 party return→night key carriers/main gate/distraction/students/cave gate→ordinary edge travel→both cave controls and rebel meeting→Gl63. Checkpoint saves preserve live last student, keys, party and pending bridge; duplicate dialogue/reward controls. God mode, kill cheats and teleportation accelerate combat/walking; not a no-cheat or native-executable run.")
