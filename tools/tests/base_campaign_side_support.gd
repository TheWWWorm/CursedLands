extends "base_campaign_support.gd"
## Installed side-quest overlays on real campaign maps. Earlier island access is
## prepared; every objective, item, completion and reward runs its authored code.
## Walking/combat are accelerated, and unrelated main-story threads are paused.

func island() -> String: return "gipat"

func enter_side(zone: String, id: String) -> bool:
	await s.enter_zone(zone,1,false)
	freeze()
	var src := "q:"+id
	if not check(vm().world_bodies.has(src),id+": actual map loader merged quest overlay"): return false
	var roots: Array = vm().instances.filter(func(inst):return inst.sname == "WorldScript" and inst.src == src)
	if not check(roots.size() == 1,id+": map loader scheduled the quest WorldScript exactly once"): return false
	# Preserve the loader's actual quest root while the base map binds Heroes
	# and named objects. Pausing unrelated main-story threads must not restart
	# the quest WorldScript or replay its declarations and initialization.
	var root = roots[0]
	vm().instances.erase(root)
	ticks(8)
	vm().instances.clear()
	vm().briefings.active = ""; vm().briefings._pending_dialog.clear()
	game.hud._dialog.hide()
	check(s.zone_id == zone and hero() != null,"loaded authored map "+zone)
	teleport(Vector2(-1000,-1000))
	vm().instances.append(root)
	ticks(20)
	await frames()
	return true

func follows_hero(actor: GameUnit, label: String) -> void:
	# SetPlayer changes the story faction; these escorts remain NPCs whose
	# UMFollow target is the party leader returned by GetUnitOfPlayer(0,0).
	check(actor != null and actor.faction == 0 and actor.mode == "follow"
		and actor.mode_data.get("target") == hero(),label)

func close_side_dialog(id: String) -> void:
	game.hud._dialog._skip_staging()
	vm().briefings.staging_tick()
	for i in 180:
		s.world._tick_dialog_movers(GameUnit.TICK)
		vm().briefings.staging_tick()
		if vm().briefings._pending_dialog.is_empty(): break
	check(vm().briefings.active == id and vm().briefings._pending_dialog.is_empty(), "side briefing reaches normal closing controls: "+id)
	game.hud._dialog._skip(); game.hud._dialog._finish(); ticks(); await frames()

func quest_point(source: String, number: int) -> Vector2:
	var rect := RegEx.create_from_string('AddRectToArea\\(\\s*'+str(number)+',\\s*([\\d.-]+),\\s*([\\d.-]+),\\s*([\\d.-]+),\\s*([\\d.-]+)')
	var found := rect.search(source)
	if found: return Vector2((found.get_string(1).to_float()+found.get_string(3).to_float())/2,
		(found.get_string(2).to_float()+found.get_string(4).to_float())/2)
	var circle := RegEx.create_from_string('AddRoundToArea\\(\\s*'+str(number)+',\\s*([\\d.-]+),\\s*([\\d.-]+)')
	found = circle.search(source)
	if found: return Vector2(found.get_string(1).to_float(),found.get_string(2).to_float())
	check(false,"archive defines objective area "+str(number)); return Vector2(-1000,-1000)

func ordinary_use(id: int, wanted := 1) -> void:
	var object: Node3D = s.world.objects.get(id)
	if not check(object != null and s.world.levers.has(id),"authored side interactable exists: "+str(id)): return
	var p: Vector3 = object.get_meta("ei").position
	teleport(Vector2(p.x,p.y))
	hero().stats.dex = 999.0
	s.apply_command({"t":"use_lever","units":[hero().uid],"target":id},0)
	vm()._check_interactions()
	for i in 160:
		hero().tick(GameUnit.TICK)
		if hero().order.get("type","") != "use" and hero().orders.is_empty() and not hero().has_meta("interact"): break
	check(int(s.world.levers.get(id,{}).get("state",-1)) == wanted,"ordinary side interaction reaches authored state: "+str(id))
	ticks(12)

func obtain(q: Dictionary, number: int) -> void:
	var key := vm()._quest_item_name(number)
	check(not s.state.quest_items.has(key),q.id+": required item is absent before acquisition: "+key)
	if q.id in ["z3q1","z6q2","z7q3"]:
		ordinary_use({"z3q1":1000086,"z6q2":1000170,"z7q3":1000279}[q.id])
	else:
		var carriers := EIMob.load_bytes(GameData.read_file("maps/"+q.id+".mob")).objects.filter(func(o):
			return o.kind == "UNIT" and Array(o.get("quest_items",[])).any(func(it):return String(it).to_lower() == key))
		if not check(carriers.size() == 1,q.id+": original map has one required item carrier: "+key): return
		var id := int(carriers[0].nid)
		if not s.world.units[id].dead: kill([id])
		loot(id)
	check(s.state.quest_items.has(key),q.id+": normal interaction acquires "+key)

func satisfy(q: Dictionary, o: Array, source: String) -> void:
	var target = vm()._objective_target(str(o[1]))
	match String(o[0]):
		"QObjArea": teleport(quest_point(source,int(float(o[1]))))
		"QObjSeeObject", "QObjSeeUnit":
			if not check(target != null,q.id+": objective has a real loaded target "+str(o[1])): return
			teleport(target.pos+Vector2(0.1,0) if target is GameUnit else vm()._obj_pos(target))
			hero().facing = PI
			if o[0] == "QObjSeeUnit":
				s.world.ai.player_perceive(hero(),true); ticks(20)
		"QObjKillUnit":
			if check(target is GameUnit,q.id+": required enemy exists"):
				check(not target.dead,q.id+": enemy is alive before combat")
				kill([target.uid])
		"QObjKillGroup":
			var group: Array = vm().globals.get(str(o[1]),[])
			if not check(not group.is_empty(),q.id+": required enemy group is nonempty: "+str(o[1])): return
			var live := group.filter(func(u):return is_instance_valid(u) and not u.dead)
			if not check(not live.is_empty(),q.id+": enemy group starts alive"): return
			for u: GameUnit in live.slice(0,-1): kill([u.uid])
			check(s.state.side_quests[q.id] == "active",q.id+": last surviving enemy blocks completion")
			kill([live[-1].uid])
		"QObjGetItem": obtain(q,int(float(o[1])))
		"QObjUse": ordinary_use(vm()._obj_id(target),int(o[2]))
		_: check(false,"unhandled authored objective "+str(o))
	ticks(12)

func custom(q: Dictionary, source: String) -> void:
	if q.id == "z6q3":
		ordinary_use(1169)
		var boar: GameUnit = s.world.units.get(1000263)
		if not check(boar != null,"Piggy Fivepence spawned from quest archive"): return
		teleport(boar.pos)
		follows_hero(boar,"freed pig joins player faction and follows through authored script")
		check(s.state.side_quests[q.id] == "active","freeing pig is insufficient before safe arrival")
		await roundtrip("base_side_pig_escort",["q.z6q3.z6q3.3"])
		boar = s.world.units.get(1000263)
		follows_hero(boar,"reloaded pig retains player faction and follows the restored hero")
		teleport(quest_point(source,1),boar)
	elif q.id == "z7q1":
		teleport(quest_point(source,1))
		var orcs: Array = vm().globals.get("OrcG",[])
		# The imported zone7-LMP OrcG bindings resolve eight campaign actors;
		# the quest WorldScript adds seven more. The authored Every(OrcG)
		# condition requires the complete union, not only the new quest units.
		var expected := [4875,4876,4878,4894,4895,4896,4897,4901,
			1000002,1000032,1000036,1000052,1000058,1000068,1000072]
		var actual := orcs.map(func(u):return u.uid)
		actual.sort()
		if not check(actual == expected,"GoGo rescue loads exactly eight campaign and seven quest guards"): return
		for u: GameUnit in orcs.slice(0,-1): kill([u.uid])
		check(value("q.z7q1.z7q1.2") != 2,"last GoGo guard blocks combat objective")
		kill([orcs[-1].uid])
		var gogo: GameUnit = s.world.units.get(1000084)
		if not check(gogo != null,"GoGo exists in loaded rescue encounter"): return
		teleport(gogo.pos); ticks(12)
		follows_hero(gogo,"living GoGo joins player faction and follows the hero")
		await roundtrip("base_side_gogo_escort",["q.z7q1.z7q1.3"])
		gogo = s.world.units.get(1000084)
		follows_hero(gogo,"reloaded GoGo retains player faction and follows the restored hero")
		check(s.state.side_quests[q.id] == "active","rescued GoGo must reach the safe area")
		ordinary_use(1000062)
		check(s.state.quest_items.has("bridgeboard00"),"ordinary plank pickup supplies bridge repair item")
		teleport(quest_point(source,3)); ticks(12)
		check(not s.state.quest_items.has("bridgeboard00") and value("q.z7q1.z7q1.6") == 2,"real bridge location consumes plank and repairs escape route")
		teleport(quest_point(source,2),gogo)
	elif q.id == "z18q1":
		var house: Node3D = s.world.objects.get(47541)
		if not check(house != null,"Junophile rescue house exists"): return
		teleport(vm()._obj_pos(house))
		for name: String in ["OhranaJunHouse","Police"]:
			var guards: Array = vm().globals.get(name,[])
			check(not guards.is_empty(),"Junophile rescue has authored guards: "+name)
			for u: GameUnit in guards:
				if not u.dead: kill([u.uid])
			check(s.state.side_quests[q.id] == "active","guard defeat alone cannot finish Junophile escort: "+name)
		teleport(Vector2(230,72))
		var rescued: GameUnit = s.world.units.get(1000094)
		if not check(rescued != null and not rescued.dead,"Junophile is alive for rescue"): return
		teleport(rescued.pos); ticks(12)
		follows_hero(rescued,"living Junophile joins player faction and follows through authored proximity")
		await roundtrip("base_side_junophile_escort",["q.z18q1.z18q1.5","q.z18q1.z18q1.6"])
		rescued = s.world.units.get(1000094)
		follows_hero(rescued,"reloaded Junophile retains player faction and follows the restored hero")
		teleport(Vector2(280,45),rescued); ticks(12)
		check(value("q.z18q1.z18q1.6") == 2,"Junophile safe arrival completes final objective")
	elif q.id == "z19q3":
		check(int(s.world.levers[43968].state) == 1 and int(s.world.levers[43974].state) == 1,"invasion quest starts with both portal switches on")
		teleport(quest_point(source,1))
		var boss: GameUnit = s.world.units.get(1001936)
		if not check(boss != null,"invasion commander spawned"): return
		teleport(boss.pos+Vector2(0.1,0)); hero().facing = PI
		s.world.ai.player_perceive(hero(),true); ticks(20)
		check(value("q.z19q3.z19q3.2") == 2,"ordinary perception discovers invasion commander")
		kill([boss.uid]); loot(boss.uid); ticks(12)
		check(s.state.quest_items.has("teleportkey00"),"invasion commander's real corpse yields portal key")
		ordinary_use(43968,0)
		check(s.state.side_quests[q.id] == "active","one running portal prevents invasion completion")
		await roundtrip("base_side_invasion_partial",["q.z19q3.z19q3.5"],["teleportkey00"])
		check(int(s.world.levers[43968].state) == 0 and not s.world.levers[43968].enabled,
			"reload preserves the spent first portal control")
		check(int(s.world.levers[43974].state) == 1 and s.world.levers[43974].enabled and int(s.world.levers[43974].cycled) == 1,
			"reload retains the remaining portal control's quest cycling rule")
		# Downgrade only the schema of the genuinely earned partial state.
		# Legacy rows have state, figure position and enabled, without use_v.
		var before := accounting()
		s._capture_save_state()
		for id: int in [43968,43974]:
			var row: Array = s.state.zones[s.zone_id].levers[id]
			check(row.size() > 3,"earned portal snapshot contains modern use metadata: "+str(id))
			s.state.zones[s.zone_id].levers[id] = row.slice(0,3)
		check(s.state.save(SaveInfo.path("base_side_invasion_legacy")) == OK,"save legacy-schema partial portal checkpoint")
		check(await s.load_game_shown("base_side_invasion_legacy"),"reload legacy-schema partial portal checkpoint")
		freeze(); ticks(12); await frames()
		check(accounting() == before,"legacy portal reload preserves earned quest state and rewards")
		check(int(s.world.levers[43968].state) == 0 and not s.world.levers[43968].enabled,
			"legacy reload preserves the spent first portal control")
		check(int(s.world.levers[43974].state) == 1 and s.world.levers[43974].enabled and int(s.world.levers[43974].cycled) == 1,
			"legacy reload retains the remaining portal control's quest cycling rule")
		ordinary_use(43974,0)
	else: check(false,"unexpected non-generated objective chain "+q.id)
	ticks(24)

func one(q: Dictionary) -> void:
	print("SIDE_BEGIN ",q.id)
	# A fresh character isolates this quest from other chapter/item outcomes.
	s.state = CampaignState.new(); s.state.ensure_hero(0,"Human Hero")
	s.state.god_modes[0] = 1
	var zone := SideQuests.zone_of(s,q)
	var village: String = {"gipat":"bz1g","ingos":"bz8k","suslanger":"bz14h"}[island()]
	s.state.visited[zone] = true
	if q.id == "z12q3":
		# This campaign door has its main-story MineKey01 lock. Earn that
		# prerequisite from the real governor exchange before accepting work;
		# the supplied gold/offer are outputs of the main Ingos q53 suite.
		s.state.add_item("GoldNugget00")
		await accept("bz8k","b.Huber.G53","q.gz12k.q54k")
		check(s.state.quest_items.has("minekey01"),"governor exchange supplies the campaign mine-door prerequisite")
	await enter(village)
	check(SideQuests.offers(s).has(q),q.id+": visited destination is offered by island village")
	s.apply_command({"t":"side_quest","q":q.id},0)
	await close_side_dialog("sq."+q.id+".1")
	check(s.state.side_quests.get(q.id) == "active",q.id+": normal offer activates quest")
	var base := "q.%s.%s"%[q.id,q.id]
	check(value(base) == 1,q.id+": offer starts journal")
	if not await enter_side(zone,q.id): return
	check(s.state.side_quests[q.id] == "active",q.id+": untouched objectives do not complete")
	var source := EIMob.load_bytes(GameData.read_file("maps/"+q.id+".mob")).script_text
	if vm().qobjs.has(q.id):
		var objectives: Array = vm().qobjs[q.id].objs.duplicate(true)
		check(not objectives.is_empty(),q.id+": authored objective chain registered")
		for i in objectives.size():
			if int(vm().qobjs[q.id].get("cur",0)) <= i: await satisfy(q,objectives[i],source)
			check(value(base+"."+str(i+1)) == 2,q.id+": authored objective "+str(i+1)+" completes")
			if i == 0: await roundtrip("base_side_"+q.id+"_partial",[base,base+".1"])
	else: await custom(q,source)
	ticks(30)
	check(s.state.side_quests[q.id] == "done" and value(base) == 2,q.id+": all actual objectives reach reward-pending completion")
	check(SideQuests.active_in(s,zone).is_empty(),q.id+": completed overlay stops reinjection")
	await roundtrip("base_side_"+q.id+"_done",[base])
	var money := s.state.money
	var exp_before: float = s.state.heroes[0][0].get("exp_total",0)
	await enter(village)
	SideQuests.check_rewards(s)
	await close_side_dialog("sq."+q.id+".3")
	check(s.state.side_quests[q.id] == "rewarded",q.id+": actual village reward closes quest")
	check(s.state.money == money+int(q.money),q.id+": archive money awarded exactly")
	check(float(s.state.heroes[0][0].get("exp_total",0)) > exp_before or float(q.exp) == 0,q.id+": experience reward reaches hero")
	var before := accounting()
	s.apply_command({"t":"dialog_done","id":"sq."+q.id+".3"},0); ticks()
	check(accounting() == before,q.id+": repeated reward close grants nothing")
	await roundtrip("base_side_"+q.id+"_rewarded",[base])
	print("SIDE_END ",q.id)

func _ready() -> void: run.call_deferred()
func run() -> void:
	boot()
	var selected: Array[String] = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--side-quest="): selected.append(arg.trim_prefix("--side-quest="))
	var n := 0
	for q: Dictionary in SideQuests.all():
		if s.campaign.zone(SideQuests.zone_of(s,q)).get("allod","") != island(): continue
		if not selected.is_empty() and q.id not in selected: continue
		await one(q); n += 1
	check(n == (selected.size() if not selected.is_empty() else {"gipat":12,"ingos":6,"suslanger":10}[island()]),
		"all selected side archives exercised" if not selected.is_empty() else "all installed island side archives exercised")
	await finish("BASE_CAMPAIGN_SIDE_"+island().to_upper(),"Real installed side-quest overlays and authored objective chains, normal acceptance/interaction/loot/reward controls, partial/done/rewarded save-load. Earlier island access prepared; walking/combat accelerated and unrelated story threads paused; not an uninterrupted playthrough or new native runtime capture.")
