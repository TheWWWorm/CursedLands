extends "story_coop_traps_net.gd"
## Native Ingos population replacement must retain looted actors for the
## interpreter and checkpoint writer. Run under an isolated user profile.

func builtin(name: String, subject: Variant) -> Variant:
	var inst := ScriptVM.Instance.new()
	inst.locals.subject = subject
	return host.world.vm._call(name, [[ScriptParser.N_VAR, "subject"]], inst)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0, "show_tutorial":0, "net_upnp":0,
		"net_lan":0, "net_directory":0, "auto_graphics":0}, true)
	host = branch(false)
	check(host.host(29982, 2) == OK, "start isolated quest-removal authority")
	host.state.ensure_hero(0, "Human Hero")
	await host.enter_zone("gz12k", 1, false)
	freeze(host)
	ticks(4)
	var vm := host.world.vm
	var group: Array = vm.globals.get("diablom0", [])
	check(group.size() > 2, "original Ingos script registers its first population")
	if group.size() < 3: await finish(); return
	var hero: GameUnit = host.party_units(0)[0]
	var corpses: Array = group.slice(0, 2)
	var ids: Array[int] = []
	for u: GameUnit in corpses:
		ids.append(u.uid)
		u.die(hero)
		host.take_loot(hero, u)
		check(host.world.looted.get(u.uid) == u and not u.is_inside_tree(), "looting retains an off-tree actor")
	# This is the authored quest transition's actual population-replacement
	# body, including RemoveUnitFromServer and AddMob, not a rewritten loop.
	vm.instances.clear()
	vm.spawn("VTriger#0#248", [hero])
	ticks(2)
	await frames(4)
	check(host.world.get_meta("added_mobs", []).has("zone12dm1.mob"), "original replacement population is added")
	for i in corpses.size():
		var retained: Variant = corpses[i]
		check(is_instance_valid(retained), "population replacement preserves looted identity")
		if not is_instance_valid(retained): continue
		check(not host.world.units.has(ids[i]) and not retained.is_inside_tree(), "retained corpse stays unavailable in the world")
		check(bool(builtin("WasLooted", retained)) and bool(builtin("IsDead", retained)), "authored corpse predicates survive replacement")
		for name: String in ["RemoveUnitFromServer", "RemoveObjectFromServer"]:
			builtin(name, retained)
			await frames(2)
			check(is_instance_valid(retained), name + " is harmless for an already-looted actor")
	check(host.world.looted.values().all(func(u): return is_instance_valid(u)), "all checkpoint tombstones remain valid")
	if failures: await finish(); return
	check(host.save_game("quest-population-replaced") == OK, "save after native quest population replacement")
	var saved: Variant = CampaignState.read_data(SaveInfo.path("quest-population-replaced"))
	check(saved.zones.gz12k.looted.has(ids[0]) and saved.zones.gz12k.vm.globals.diablom0[0].u == ids[0], "checkpoint keeps loot and VM references together")
	check(host.load_game("quest-population-replaced"), "reload replaced population checkpoint")
	freeze(host)
	for id: int in ids:
		var retained: Variant = host.world.looted.get(id)
		check(is_instance_valid(retained) and bool(builtin("WasLooted", retained)), "reload restores retained looted identity")
	# Normal living actors and scenery still follow their removal paths.
	var actor: GameUnit = host.world.units.values().filter(func(u): return not u.has_meta("hero"))[0]
	var actor_id := actor.uid
	builtin("RemoveUnitFromServer", actor)
	await frames(2)
	check(not is_instance_valid(actor) and not host.world.units.has(actor_id), "living actor removal still frees the actor")
	var scenery := Node3D.new()
	var scenery_id := host.world.new_uid()
	scenery.set_meta("ei", {"nid":scenery_id})
	host.world.add_child(scenery)
	host.world.objects[scenery_id] = scenery
	builtin("RemoveObjectFromServer", scenery)
	await frames(2)
	check(not is_instance_valid(scenery) and not host.world.objects.has(scenery_id), "scenery removal still frees and unregisters the object")
	builtin("RemoveUnitFromServer", actor)
	builtin("RemoveObjectFromServer", scenery)
	builtin("RemoveObjectFromServer", null)
	# Defensive capture for a stale entry already created by older live code.
	var stale := GameUnit.new()
	host.world.looted[1999999999] = stale
	stale.free()
	host.state.store_zone(host.zone_id, host.world)
	check(host.state.zones.gz12k.looted.has(1999999999) and not host.state.zones.gz12k.vm.is_empty(), "stale entry cannot abort the whole checkpoint")
	host.world.looted.erase(1999999999)
	print("QUEST_ACTOR_REMOVAL ", checks, " checks ", failures, " failures")
	await finish()
