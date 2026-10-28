extends "lia_campaign_support.gd"
## Every Suslanger and Gipat fortune quest on the path to Kel's revival, with
## its map entered through the authored WorldScript in both purchase orders:
## bought before the first visit, and bought in the fortune-teller's village
## after a first visit, then completed on return. The Wormfaces' Riddle broke
## in the first order only. The three Rod fragment finales are in
## lia_fragment_first_entry; Khabburu's chain is entered after each briefing
## in lia_kel_ingos. The party starts each map before its first fortune:
## Suslanger in the Portal (gz1h) and Gipat in its arrival map (gz7g), so
## those maps are covered only after a first visit. God mode, teleport and
## kills shorten walking and fighting; quest outcomes come from the maps.

func _ready() -> void: run.call_deferred()

func run() -> void:
	boot()
	await order("Portal fortunes 2 and 4","FSusel","gz1h","bz5h",{"b.skelet.fq2":2,"b.skelet.fq4":2},portal,false)
	for before: bool in [true,false]:
		await order("graveyard fortunes 3 and 5","FSusel","gz2h","bz5h",{"b.skelet.fq3":2,"b.skelet.fq5":2},graveyard,before)
		await order("mushroom fortune 8","Gipat","gz9g","bz11g",{"b.shava.fq8":2},mushrooms,before)
		await order("clerk fortune 9","Gipat","gz11g","bz11g",{"b.shava.fq9":2},clerk,before)
		await order("captive and giant fortunes 10 and 12","Gipat","gz16g","bz11g",{"b.shava.fq10":2,"b.shava.fq12":2},captive_and_giant,before)
	await order("invalid fortune 11","Gipat","gz7g","bz11g",{"b.shava.fq11":2},invalid,false)
	await finish("LIA_KEL_FORTUNE_ORDERS","Suslanger fq2..fq5 and Gipat fq8..fq12 with maps entered through their authored WorldScript, fortune bought before the first visit (except the chapters' starting maps) and after a first visit; fortune flags supplied, actual objects, kills, clock windows, escort and feeding sequences. God mode, teleport and kills shorten traversal.")

## One fresh campaign per order. Story flags place the party after the
## Shelter escape (Suslanger) or after arrival in Gipat.
func order(label: String, party: String, zone: String, village: String, fortunes: Dictionary, objective: Callable, before: bool) -> void:
	label += " bought before first visit" if before else " bought after first visit"
	await boot_again()
	if party == "FSusel":
		chapter("FSusel","Hero2","Hero2","merc2")
		for key: String in ["q.gz1h.q01h","q.gz1h.q02h"]: s.state.set_var(0,key,2)
		s.state.set_var(0,"q.gz2h.q5h",1)
	else:
		chapter("Gipat","Hero3","Hero","merc2g")
		s.state.set_var(0,"q.gz7g.q1g",1)
	if before:
		for key: String in fortunes: s.state.set_var(0,key,fortunes[key])
	await visit(zone)
	if not before:
		await enter_away(village)
		for key: String in fortunes: s.state.set_var(0,key,fortunes[key])
		await visit(zone)
	await objective.call(label)

func portal(label: String) -> void:
	check(s.world.lever_sys.usable(2261640),label+": second fortune enables the cellar torch")
	kill([1140714])
	check(value("q.gz1h.fq2") == 2,label+": Raja's death completes the second fortune")
	ticks(40)
	check(value("deadman") == 50,label+": fourth fortune reveals the dead man")
	use(2017083)
	check(s.state.quest_items.has("traderkey1"),label+": dead man yields the trader key")
	use(2001539)
	check(value("q.gz1h.fq4") == 2 and s.state.quest_items.has("fakedocument00"),label+": trader chest completes the fourth fortune")

func graveyard(label: String) -> void:
	vm().time_fixed = true; s.state.world_time = 12.2; ticks()
	check(int(s.world.levers[16372].state) == 1,label+": midday opens the basket route")
	var fruit := s.state.items.size()
	use(2135816); ticks(35)
	check(value("q.gz2h.fq3") == 2 and s.state.items.size() == fruit+75,label+": basket completes the third fortune with its fruit")
	s.state.world_time = 22.2; ticks(8)
	check(vm()._num(vm().globals.get("N")) == 1,label+": night raises the fifth fortune's undead")
	kill([150058,150059,150066,1178767,150062,150063,1178500])
	use(1072720)
	check(value("q.gz2h.fq5") == 2,label+": undead chest completes the fifth fortune")

func mushrooms(label: String) -> void:
	ticks(30)
	check(value("zone9_fq8") == 1 and s.world.objects.has(1011003),label+": mushrooms are spawned")
	use(1011003)
	check(value("q.gz9g.fq8") == 2,label+": edible mushroom completes the eighth fortune")

func clerk(label: String) -> void:
	ticks(15)
	check(value("zone11_fq9") == 1,label+": clerk scene starts")
	kill([980429]); loot(980429)
	check(s.state.quest_items.has("clerkkey00"),label+": key carrier's corpse yields the clerk key")
	use(1000000)
	check(value("q.gz11g.fq9") == 2,label+": clerk's cage completes the ninth fortune")

func captive_and_giant(label: String) -> void:
	ticks(20)
	use(4955)
	var captive: GameUnit = s.world.units.get(1131193)
	check(captive != null and captive.faction == 0,label+": opened cage frees the captive")
	teleport(Vector2(68,169),captive)
	check(value("q.gz16g.fq10") == 2 and int(s.world.levers[1034227].state) == 1,label+": escort completes the tenth fortune")
	check(value("zone16_fq12") == 1,label+": giant food sequence starts")
	use(3398867); use(2139639)
	var giant: GameUnit = s.world.units.get(3398862)
	teleport(Vector2(267.5,144.8),giant)
	check(value("zone16_fq12") == 4 and s.world.lever_sys.usable(3398868),label+": giant's first meal enables the second food")
	use(3398868)
	teleport(Vector2(270,145),giant); use(2139639)
	teleport(Vector2(267.5,144.8),giant); ticks(110)
	check(giant.dead and value("q.gz16g.fq12") == 2,label+": second meal poisons the giant and completes the twelfth fortune")

func invalid(label: String) -> void:
	ticks(25)
	check(value("zone7_fq11") == 1,label+": encounter starts")
	kill([2215845])
	check(value("q.gz7g.fq11") == 2,label+": target's death completes the eleventh fortune")

func loot(id: int) -> void:
	var corpse: GameUnit = s.world.units.get(id)
	if not check(corpse != null and corpse.dead,"authored key carrier is lootable"): return
	var h := hero()
	teleport(corpse.pos)
	s.apply_command({"t":"loot","units":[h.uid],"target":id},0)
	vm()._check_interactions()
	for i in 160:
		h.tick(GameUnit.TICK)
		if h.order.get("type","") != "use" and h.orders.is_empty() and not h.has_meta("interact"): break
	ticks()
