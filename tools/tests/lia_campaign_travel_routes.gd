extends "lia_kel_departures.gd"
## Real world loads for the campaign-wide map matrix's Jigran regression.
## Only prior travel gates are prepared; exit/map selection and arrival are
## ordinary game actions. No quest-completion claim follows from these inputs.

func select_route(exit_number: int, destination: String, entrance: int) -> bool:
	var ex: Dictionary = s.world.zone.exits.get(exit_number,{})
	if not check(ex.has("remove"),"real source passage exists: "+str(exit_number)): return false
	var point: Vector2 = ex.remove.get_center()
	if not check(s.open_exit_at(point,0) == exit_number,"real source passage is open"): return false
	for u: GameUnit in s.party_heroes(): u.pos = point; u.resync_drawn()
	s.apply_command({"t":"move","units":[hero().uid],"x":point.x,"y":point.y,"exit":exit_number},0)
	s._check_exits()
	if s.world.zone.type != "brief":
		if not check(MessageBox.is_up(game.hud._leave_box),"field passage opens normal confirmation"): return false
		game.hud._leave_box._answer(true)
	await frames(2)
	var maps := game.hud._travel.get_children().filter(func(n):return n is TravelMap and not n.is_queued_for_deletion())
	if not check(s.map_open and maps.size() == 1,"actual exit opens the travel map"): return false
	var map: TravelMap = maps[0]
	var panel := map.open_objectives(destination)
	var chosen := -1
	for i in panel.entrances.size():
		if panel.entrances[i].n == entrance and panel.entrances[i].ok: chosen = i
	if not check(chosen >= 0,"map offers "+destination+" arrival "+str(entrance)): return false
	panel.press(["entrance",chosen]); panel.press(["ok"])
	if not await wait_zone(destination): return false
	check(s._lmp_entrance == entrance,"world load retains the selected entrance")
	var arrival: Rect2 = s.world.zone.exits[entrance].deploy
	check(arrival.grow(5).has_point(hero().pos),"hero deploys at the selected authored map point")
	if not map_startup: vm().instances.clear()
	vm().briefings.active = ""; vm().briefings._pending_dialog.clear()
	game.hud._dialog.hide()
	return true

func run() -> void:
	boot()
	s.mod_config.rules.auto_exit = 0
	s.state.god_modes[0] = 1
	# Independent native parser evidence: 0x43a1a0 appends records; header
	# labels are comments to that parser, including duplicate/sparse labels.
	var map := CampaignMap.new()
	map._parse("#zone fixture jigran game\n#exit 42\nfirst 1\n#deploy\n1 2 3 4\n#exit 42\nsecond 1\n#deploy\n5 6 7 8\n#exit 7\nthird 1\n#deploy\n9 10 11 12\n")
	check(map.zone("fixture").exits.keys() == [1,2,3],"native record order survives repeated and sparse exit labels")
	check(map.zone("fixture").exits[1].to == "first" and map.zone("fixture").exits[2].to == "second"
		and map.zone("fixture").exits[3].to == "third","parsing retains every authored route")
	for id: String in ["gz33j","bz32j","gz33j_bz32j","gz33j_gz34j","gz34j","gz31j_gz33j"]:
		s.state.set_var(0,"z."+id,2)
	await enter("bz32j")
	if await select_route(1,"gz33j",3):
		check(s.world.zone.exits.size() == 3,"Jigran field retains all three original entrances")
		check(s.world.zone.exits[2].to == "gz33j_gz34j" and s.world.zone.exits[3].to == "bz32j",
			"west route and settlement return remain distinct")
		await roundtrip("lia_jigran_settlement_return",["z.gz33j","z.gz33j_gz34j"])
		if await select_route(2,"gz34j",1):
			check(s.zone_id == "gz34j","restored west route really loads Two Rivers")
	# Ingos' obsolete dryad edge has no incoming authored passage. Exercise
	# the actual forest route instead, and retain its entrance-only control.
	s.state.set_var(0,"start_zone21",1) # prepared chapter already initialized
	for id: String in ["gz21k","gz23k","gz21k_gz23k","gz22k_gz23k"]:
		s.state.set_var(0,"z."+id,2)
	await enter("gz21k")
	if await select_route(2,"gz23k",1):
		var landing: Dictionary = s.world.zone.exits[2]
		check(landing.to == "none" and not landing.has("remove"),"one-way arrival retains its original no-return definition")
		check(s.open_exit_at(landing.deploy.get_center(),0) < 0,"arrival-only location never arms an outbound passage")
		game.hud.open_quests("field",s.zone_id); await frames()
		check(not game.hud.quests_screen.entrances.any(func(e):return e.n == 2),"field map does not advertise the arrival-only point as an exit")
		game.hud.quests_screen.back.emit(); await frames()
		await roundtrip("lia_ingos_forest_arrival",["z.gz23k","z.gz21k_gz23k"])
		if await select_route(1,"gz21k",2):
			check(s.zone_id == "gz21k","ordinary return leaves the Ingos forest")
	await finish("LIA_CAMPAIGN_TRAVEL_ROUTES","Prepared unlocked Jigran/Ingos travel gates. Actual village/field exits, map entrance selection, full destination loads, correct arrival geometry, inactive one-way controls and saved return routes; no quest-trigger or native-runtime claim.")
