extends "lia_kel_support.gd"
## Loaded campaign fixtures share normal interactions and confirmed travel.
## Only earlier offers/accepted quests are supplied; the tested objectives,
## inventory rewards, route gates and returns must come from authored handlers.

func chapter(party: String, prototype: String, protagonist := "Hero", companion := "merc2") -> void:
	s.state.create_party(party)
	s.state.add_party_unit(party,protagonist,prototype)
	if companion != "": s.state.add_party_unit(party,"merc2",companion)
	s.state.set_current_party(party)
	# This fixture starts with an already deployed chapter, before prerequisite
	# items are supplied. Ordinary scripted selection remains deferred.
	s.state.store_party_quest_items()
	s.state.god_modes[0] = 1
	s.mod_config.rules.auto_exit = 0

func wait_zone(id: String) -> bool:
	await frames(3)
	var deadline := Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		if s.world != null and s.zone_id == id and not s.loading_game:
			freeze(); return check(true,"authored transfer reaches "+id)
		await get_tree().process_frame
	return check(false,"authored transfer reaches "+id)

func place_party(at: Vector2) -> void:
	for u: GameUnit in s.party_heroes():
		u.command({"type":"wait","t":0.0}); u.pos = at; u.resync_drawn()
	ticks()

func passage(to: String) -> int:
	for n: int in s.world.zone.get("exits",{}):
		if s.world.zone.exits[n].get("to","") == to: return n
	return -1

func gate(to: String, opened: bool, label: String) -> void:
	var n := passage(to)
	check(n >= 0 and s._exit_is_open(n,0) == opened,label)

func leave(to: String, destination := "") -> bool:
	var number := passage(to)
	if not check(number >= 0,"authored passage exists from "+s.zone_id+" to "+to): return false
	var ex: Dictionary = s.world.zone.exits[number]
	var point: Vector2 = ex.remove.get_center()
	if not check(s.open_exit_at(point,0) == number,"earned gate permits ordinary exit click to "+to): return false
	place_party(point)
	var h := hero()
	var village := String(s.world.zone.get("type","")) == "brief"
	s.apply_command({"t":"move","units":[h.uid],"x":point.x,"y":point.y,"exit":number},0)
	s._check_exits()
	if village:
		check(not MessageBox.is_up(game.hud._leave_box),"ordinary village exit follows the original immediate departure rule")
	else:
		if not check(MessageBox.is_up(game.hud._leave_box),"ordinary passage opens confirmation for "+to): return false
		game.hud._leave_box._answer(true)
	if destination != "" and destination != to:
		await frames(3)
		var option := {}
		for candidate: Dictionary in s.travel_options:
			if candidate.get("zone","") == destination: option = candidate
		if not check(not option.is_empty(),"earned route offers actual destination "+destination): return false
		var maps := game.hud._travel.get_children().filter(func(n): return n is TravelMap and not n.is_queued_for_deletion())
		if not check(maps.size() == 1 and game.hud._travel.visible,"ordinary route exit opens the campaign travel map"): return false
		maps[0].picked.emit(option)
	return await wait_zone(destination if destination != "" else to)

func loot(id: int) -> void:
	var body: GameUnit = s.world.units.get(id)
	if not check(body != null and body.dead,"authored corpse is available for ordinary loot: "+str(id)): return
	teleport(body.pos)
	var h := hero()
	s.apply_command({"t":"loot","units":[h.uid],"target":id},0)
	vm()._check_interactions()
	for i in 160:
		h.tick(GameUnit.TICK)
		if h.order.get("type","") != "use" and h.orders.is_empty() and not h.has_meta("interact"): break
	ticks()

func loot_key(map_file: String, key: String) -> bool:
	var carriers := EIMob.load_bytes(GameData.read_file("maps/"+map_file)).objects.filter(func(o):
		return o.kind == "UNIT" and Array(o.get("quest_items",[])).any(func(item): return String(item).to_lower() == key))
	if not check(carriers.size() == 1,"original encounter has exactly one carrier for "+key): return false
	var id := int(carriers[0].nid)
	kill([id]); loot(id)
	return check(s.state.quest_items.has(key),"ordinary loot earns the original key "+key)

func stable(label: String, count := 30) -> void:
	var before := accounting()
	ticks(count)
	check(accounting() == before,label+": completed handlers grant no duplicate reward")

func simulate_until(topic: String, limit := 1800) -> void:
	for i in limit:
		if value(topic) > 0 or s.loading_game: break
		s.world._tick(GameUnit.TICK)
		if i%20 == 0: await frames(1)
	check(value(topic) == 1,"original scene offers "+topic)

func accept(zone: String, topic: String, quest: String) -> void:
	# The earlier storyline that offers this briefing is the checkpoint input.
	# Its actual topic controls and original reward record start the quest.
	s.state.set_var(0,topic,1)
	await enter(zone)
	await complete(topic)
	check(value(quest) == 1,"actual briefing starts accepted quest "+quest)
