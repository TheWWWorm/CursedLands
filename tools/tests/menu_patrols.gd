extends Node
## The real menu must execute the shipped MOB patrols, rather than posing
## decorative creature models. Keep campaign simulation and signpost input.
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",message)

func _ready() -> void:
	var menu := MenuScene.create()
	check(menu != null,"original menu island loads")
	if menu == null: finish(); return
	add_child(menu)
	menu.set_hour(12)
	menu.rain_bit = false
	menu.camera.current = true
	var world: GameWorld = menu.get("world")
	check(world != null,"menu owns a running simulation for its authored creatures")
	if world == null: menu.free(); finish(); return
	world.set_physics_process(false)
	check(world.session == null and world.zone.type == "menu","menu simulation has no campaign or player state")
	check(world.vm == null,"menu without a level script does not run campaign scripts")
	check(world.units.size() == world.map.unit_records.size(),"all authored creatures are spawned once")
	var starts := {}
	var distance := {}
	var stopped := {}
	var patrollers := 0
	for u: GameUnit in world.unit_rows():
		starts[u.uid] = u.pos
		distance[u.uid] = 0.0
		stopped[u.uid] = false
		if int(u.info.get("logic_model",0)) == 2:
			patrollers += 1
			check(not u.info.get("guard_points",[]).is_empty(),"patrol reads original route: "+str(u.uid))
	for tick in 1400:
		world._tick(GameUnit.TICK)
		for u: GameUnit in world.unit_rows():
			distance[u.uid] = maxf(distance[u.uid],u.pos.distance_to(starts[u.uid]))
			if tick > 100 and u.action == "idle": stopped[u.uid] = true
		if tick == 0:
			for u: GameUnit in world.unit_rows():
				if int(u.info.get("logic_model",0)) == 2:
					check(int(u.get_meta("calm",{}).get("patrol_i",-1)) == 1,"first patrol leg uses original point 1: "+str(u.uid))
	check(patrollers > 0 if GameData.campaign_id == CampaignProfile.ASTRAL else true,"LiA fixture exercises its patrols")
	for u: GameUnit in world.unit_rows():
		if int(u.info.get("logic_model",0)) != 2: continue
		check(distance[u.uid] > 4.0,"creature actually travels around menu: "+str(u.uid))
		check(stopped[u.uid],"creature retains authored pauses: "+str(u.uid))
		check(not u.dead and u.controller == -1,"menu creature remains alive and AI controlled")
	check(not world.active_set.enabled,"menu patrols stay active without a nearby player")
	for part: String in MenuScene.BOARDS:
		var rect := menu.board_rect(part)
		if rect.has_area(): check(menu.board_at(rect.get_center()) == part,"moving world retains signpost target: "+part)
	if DisplayServer.get_name() != "headless":
		world.set_physics_process(true)
		var before := {}
		for u: GameUnit in world.unit_rows(): before[u.uid] = u.pos
		await get_tree().create_timer(12.0).timeout
		var moved := false
		for u: GameUnit in world.unit_rows():
			moved = moved or u.pos.distance_to(before[u.uid]) > 0.25
		check(moved if patrollers > 0 else true,"normal rendered menu dispatch advances patrols")
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("user://menu-patrols.png") == OK,"animated menu captured")
	menu.free()
	finish()

func finish() -> void:
	print("MENU_PATROLS ",checks," checks ",failures," failures")
	TexUpscale.shutdown()
	get_tree().quit(1 if failures else 0)
