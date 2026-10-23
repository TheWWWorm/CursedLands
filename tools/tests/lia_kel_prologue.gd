extends "lia_kel_support.gd"
## New campaign through the first Shelter arrival. Original startup and
## cinematic threads stay live. Teleports, god mode and selected enemy kills
## accelerate travel/combat; every tested quest, dialogue and transition is
## still produced by the installed scripts and ordinary interaction commands.

func _ready() -> void: run.call_deferred()

func step() -> void:
	if s.loading_game or s.world == null: return
	freeze()
	s.world.time += ScriptVM.POLL
	for u: GameUnit in s.world.units.values():
		if not u.dead and (not u.order.is_empty() or not u.orders.is_empty()): u.tick(GameUnit.TICK)
	vm().tick(ScriptVM.POLL)

func advance(n: int) -> void:
	for i in n:
		step()
		if i%10 == 0: await frames(1)

func until(test: Callable, label: String, limit := 1000) -> bool:
	for i in limit:
		if not s.loading_game and test.call():
			freeze()
			return check(true,label)
		step()
		await frames(1)
	return check(false,label)

func arrive(id: String) -> bool:
	return await until(func():return s.zone_id == id,"authored transfer arrives in "+id)

func put(point: Vector2, u: GameUnit = null) -> void:
	var actor := u if u != null else hero()
	if not check(actor != null,"required story actor exists"): return
	actor.orders.clear(); actor.order = {}; actor.pos = point; actor.resync_drawn()

func loot(id: int) -> void:
	var corpse: GameUnit = s.world.units.get(id)
	if not check(corpse != null and corpse.dead,"authored map carrier is lootable"): return
	put(corpse.pos)
	s.apply_command({"t":"loot","units":[hero().uid],"target":id},0)
	vm()._check_interactions()
	for i in 160:
		hero().tick(GameUnit.TICK)
		if hero().order.get("type","") != "use" and hero().orders.is_empty() and not hero().has_meta("interact"): break
	ticks()

func passage(number: int, destination: String) -> bool:
	var point: Vector2 = s.world.zone.exits[number].remove.get_center()
	if not check(s.open_exit_at(point,0) == number,"authored onward passage is open in "+s.zone_id): return false
	for u: GameUnit in s.party_heroes(): put(point,u)
	s.apply_command({"t":"move","units":[hero().uid],"x":point.x,"y":point.y,"exit":number},0)
	s._check_exits()
	if not check(MessageBox.is_up(game.hud._leave_box),"ordinary onward confirmation is available"): return false
	game.hud._leave_box._answer(true)
	return await arrive(destination)

func run() -> void:
	boot()
	s.state.god_modes[0] = true
	s.mod_config.rules.auto_exit = 0
	await s.enter_zone("gz1g",1,false); freeze()
	await advance(40)
	check(value("q.gz1g.q1r") == 0,"portal mission is absent before the First's conversation")
	put(Vector2(54,146)); await advance(5)
	check(s.zone_id == "gz1g","later tutorial area cannot bypass its initial trigger")
	put(Vector2(23,121)); await advance(3)
	put(Vector2(54,146))
	if not await arrive("bz1r"): await done(); return
	if not await until(func():return value("b.First.brief_0") == 1,"original introductory actor offers his conversation"): await done(); return
	await complete("b.First.brief_0")
	check(s.state.quest_items.has("note00"),"actual introductory dialogue grants the note")
	if not await arrive("gz1g"): await done(); return
	await advance(30)
	check(value("q.gz1g.q1r") == 1 and value("q.gz1g.q1r.1") == 1,"return from introduction starts the portal mission")
	put(Vector2(100,90)); await advance(3)
	check(value("q.gz1g.q1r.2") == 0,"second portal area cannot bypass the first")
	put(Vector2(100,174)); await advance(3)
	check(value("q.gz1g.q1r.1") == 2 and value("q.gz1g.q1r.2") == 1,"first portal approach advances the objective")
	put(Vector2(100,90)); await advance(3)
	check(value("q.gz1g.q1r.2") == 2 and value("q.gz1g.q1r.3") == 1,"second approach arms the key objective")
	use(43974,false)
	check(value("q.gz1g.q1r.4") == 0,"portal mechanism rejects the missing original key")
	use(3340943)
	check(s.state.quest_items.has("teleportkey00") and value("q.gz1g.q1r.3") == 2,"authored chest grants the portal key")
	await roundtrip("lia_prologue_portal_key",["q.gz1g.q1r","q.gz1g.q1r.3"],["teleportkey00"])
	use(43974); await advance(55)
	check(value("q.gz1g.q1r.4") == 2 and value("q.gz1g.q1r") == 1,"opened portal still waits for its arrival trigger")
	put(Vector2(53.5,50.5))
	if not await arrive("bz1h"): await done(); return
	check(value("q.gz1g.q1r") == 2 and not s.state.quest_items.has("teleportkey00") and not s.state.quest_items.has("note00"),
		"portal completion consumes its original quest objects and reaches the prison camp")
	await complete("b.bz1h.brief_2")
	if not await until(func():return s.state.current_party == "FPrison","original camp introduction builds the prison party"): await done(); return
	if not await until(func():return vm().briefings.active.to_lower() == "b.hwleader.brief_1","camp leader finishes his authored approach and starts the introduction"): await done(); return
	await complete("b.HWLeader.brief_1")
	check(value("b.Clerk.Clerk_1") == 1 and value("bz1h_night") != 2,"camp waits for the player's class choice")
	var previous_world := s.world.get_instance_id()
	await complete("b.Clerk.brief_3b")
	check(["a","c","d","e","f"].all(func(suffix):return value("b.Clerk.brief_3"+suffix) == 3),"class choice hides all mutually exclusive alternatives")
	if not await until(func():return value("bz1h_night") == 2 and s.world.get_instance_id() != previous_world,"class choice reloads the authored night camp"): await done(); return
	if not await until(func():return vm().briefings.active.to_lower() == "b.merc2.n1_2","night camp starts Kel's actual escape conversation"): await done(); return
	await complete("b.merc2.n1_2")
	check(s.party_units(0).size() >= 2,"Kel joins the controlled escaping party")
	check(s.world.units.has(1001009) and not s.world.units[1001009].dead and s.zone_id == "bz1h","living camp barrier prevents the escape sequence")
	check(s.village_move_limit().z > 0,"camp boundary remains until the authored barrier is defeated")
	kill([1001009]); await advance(13)
	check(s.village_move_limit() == Vector3.ZERO,"defeating the barrier releases the ordinary movement boundary")
	put(Vector2(407,82)); await advance(3)
	check(not s.world.units.has(666666),"one escaped actor cannot trigger the demon while Kel is still inside")
	put(Vector2(407,82),vm()._by_name("merc2"))
	if not await arrive("gz1h"): await done(); return
	await advance(60)
	check(value("q.gz1h.q02h") == 1,"prison escape starts the Portal pursuit quest")
	check(value("z.bz2h") == 1,"Shelter remains closed before the escape objectives")
	var demon: GameUnit = s.world.units.get(666666)
	if not check(demon != null,"authored pursuit demon is present"): await done(); return
	put(demon.pos+Vector2(20,0)); await advance(3)
	check(value("q.gz1h.q02h.2") != 2,"nearby pursuer keeps the escape objective pending")
	put(demon.pos+Vector2(70,0)); await advance(12)
	check(value("q.gz1h.q02h.2") == 2 and value("q.gz1h.q02h.3") == 1,"escaping the demon arms the map objective")
	check(not s.state.quest_items.has("map00") and value("q.gz1h.q02h.4") == 0,"missing map prevents the final escape-area trigger")
	var carriers := [736019,321756].filter(func(id):return s.world.units.has(id) and s.world.units[id].info.get("quest_items",[]).has("map00"))
	if not check(carriers.size() == 1,"original randomization gives exactly one guard the map"): await done(); return
	kill([carriers[0]]); loot(carriers[0])
	check(s.state.quest_items.has("map00") and value("q.gz1h.q02h.3") == 2,"ordinary corpse loot advances the actual map objective")
	await roundtrip("lia_prologue_escape_map",["q.gz1h.q02h","q.gz1h.q02h.3"],["map00"])
	put(Vector2(300.7,61.4)); await advance(5)
	check(value("q.gz1h.q02h") == 1,"final escape waits for both surviving party members")
	put(Vector2(300.7,61.4),vm()._by_name("merc2"))
	if not await arrive("cz1h"): await done(); return
	check(value("q.gz1h.q02h") == 2,"both arrivals complete the escape before the doorway scene")
	if not await until(func():return value("b.merc2.brief_5") == 1,"Kel offers the catacomb doorway conversation"): await done(); return
	check(value("q.gz1d2.q03h") == 0 and s.zone_id == "cz1h","doorway waits for dialogue before assigning catacombs")
	await complete("b.merc2.brief_5")
	check(not s.state.quest_items.has("map00") and value("q.gz1d2.q03h") == 1,"Kel consumes the recovered map and assigns catacombs")
	if not await arrive("gz1d2"): await done(); return
	await advance(30)
	check(not s._exit_is_open(1),"catacomb's authored one-way entrance stays one-way")
	check(not s._exit_is_open(2) and value("q.gz1d2.q03h.1") == 1,"catacomb exit stays closed until its objectives complete")
	put(Vector2(44,145)); await advance(3)
	check(value("q.gz1d2.q03h") == 1,"standing at the final exit cannot skip the lift and clothing")
	use(1369841)
	check(value("q.gz1d2.q03h.1") == 2 and value("q.gz1d2.q03h.2") == 1,"actual lift lever advances catacomb progression")
	use(4309)
	check(value("q.gz1d2.q03h.2") == 2 and value("q.gz1d2.q03h.3") == 1,"actual clothing container starts the return objective")
	check(["hadagan medium helm.wool","hadagan medium plate.wool","hadagan medium leggins.wool","cheat dagger.bronze"].all(func(item):return s.state.items.has(item)),
		"clothing container awards all four original equipment pieces")
	put(Vector2(44,145)); await advance(3)
	check(value("q.gz1d2.q03h") == 2 and s._exit_is_open(2),"final arrival completes catacombs and opens its actual onward exit")
	await roundtrip("lia_prologue_catacombs_complete",["q.gz1d2.q03h","z.cz2h"])
	if not await passage(2,"cz2h"): await done(); return
	if not await until(func():return value("b.merc2.brief_5a") == 1,"Kel offers the post-catacomb conversation"): await done(); return
	await complete("b.merc2.brief_5a")
	if not await arrive("gz1h"): await done(); return
	put(Vector2(257.1,50.7)); await advance(25)
	check(value("q.gz1h.q1h.1") == 1,"return from catacombs starts the Shelter approach")
	put(Vector2(106.468,227.865)); await advance(3)
	check(value("q.gz1h.q1h") == 1 and value("z.bz2h") == 1,"Shelter arrival cannot bypass the guard distraction")
	put(Vector2(194,61)); await advance(58)
	check(value("q.gz1h.q1h.1") == 2 and value("q.gz1h.q1h.2") == 1,"crossing the authored approach arms the guard objective")
	put(Vector2(106.468,227.865))
	for id in [1010001,1010002,1010003]: put(Vector2(242,61),s.world.units.get(id))
	await advance(16)
	check(value("q.gz1h.q1h.2") == 2 and value("q.gz1h.q1h") == 2 and value("z.bz2h") == 0,
		"guard destination and Shelter trigger complete the quest and open the actual gate")
	check(value("b.bz2h.brief_6") == 1,"Shelter completion offers the next original introduction")
	await roundtrip("lia_prologue_shelter_ready",["q.gz1h.q1h","z.bz2h","b.bz2h.brief_6"])
	await passage(5,"bz2h")
	check(value("b.bz2h.brief_6") == 1 and s.state.current_party == "FPrison","arrival retains the precise next checkpoint and prison party")
	await done()

func done() -> void:
	await finish("LIA_KEL_PROLOGUE","Fresh campaign opening through tutorial/First, portal key, prison class/night/escape, pursuit map, catacomb dialogue/mechanisms/clothes, Shelter guard and arrival. Real authored startup, dialogues and transitions; movement/combat accelerated, saves retained. No native executable or exhaustive combat/pathfinding claim.")
