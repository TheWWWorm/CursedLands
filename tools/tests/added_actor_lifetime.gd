extends Node
## Original LiA Terror removal, map revisit and legacy save migration.
## Simulation is paused; this tests the authored despawn and persistence.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_directory":0,"net_lan":0},true)
	var s := Session.new(); add_child(s)
	var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.set_physics_process(false)
	s.state = CampaignState.new(); s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz1h",1,false)
	var w := s.world; w.set_process(false); w.set_physics_process(false)
	var vm := w.vm
	vm.instances.clear()
	vm._add_mob("zone1evil.mob")
	var terror: GameUnit = w.units.get(666666)
	check(terror != null,"actual Terror is added from zone1evil.mob")
	var hero: GameUnit = s.party_units(0)[0]
	hero.pos = terror.pos + Vector2(60,0)
	vm.spawn("VCheck#1#8a",[null])
	for i in 60: vm.tick(GameUnit.TICK)
	check(not w.units.has(666666) and s.state.get_var(0,"q.gz1h.q02h.2") == 2,"original 50m escape condition removes Terror")
	s.state.store_zone("gz1h",w)
	var snap: Dictionary = s.state.zones.gz1h.duplicate(true)
	check(snap.removed.has(666666),"added actor's removal is saved")
	check(s.state.save("user://terror.sav") == OK,"zone save writes")
	var restored := CampaignState.load_from("user://terror.sav")
	for legacy: String in ["current","carried","units"]:
		restored.zones.gz1h = snap.duplicate(true)
		if legacy != "current": restored.zones.gz1h.removed.erase(666666)
		if legacy == "units": restored.zones.gz1h.erase("carried")
		restored.restore_zone("gz1h",w)
		check(not w.units.has(666666),"removed Terror stays absent, legacy="+str(legacy))
		restored.store_zone("gz1h",w)
		check(restored.zones.gz1h.removed.has(666666),"next save retains removal, legacy="+str(legacy))
		# The live case must not be erased by absence migration.
		var extra := EIMob.load_bytes(GameData.read_file("maps/zone1evil.mob"))
		var rec: Dictionary = extra.objects.filter(func(o):return o.kind=="UNIT" and int(o.nid)==666666)[0]
		var live := w.spawn_unit(rec)
		restored.store_zone("gz1h",w)
		check(not restored.zones.gz1h.removed.has(666666),"present Terror is not marked removed")
		if legacy == "units": restored.zones.gz1h.erase("carried")
		w.remove_unit(live)
		restored.restore_zone("gz1h",w)
		check(w.units.has(666666),"living added actor returns from its save")
		if w.units.has(666666): w.remove_unit(w.units[666666])
		# The oldest format stored corpses only in `dead`, not `units`.
		if legacy == "units":
			restored.zones.gz1h.erase("carried")
			restored.zones.gz1h.units.erase(666666)
			restored.zones.gz1h.dead.append(666666)
			restored.restore_zone("gz1h",w)
			check(w.units.has(666666) and w.units[666666].dead,"old saved corpse stays dead and lootable")
			if w.units.has(666666): w.remove_unit(w.units[666666])
	g.queue_free(); s.queue_free()
	for i in 8: await get_tree().process_frame
	print("ADDED_ACTOR_LIFETIME ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
