extends Node
## Actual original-multiplayer menu -> worker -> Ingos -> quest -> menu.
## Controlled command dispatch, not a claim of walking the exit route.
var checks := 0
var failures := 0
var session: Session
var phase := ""
var frames := {}
var textures := {}
var menu_database := []
var travel_requested_msec := 0
var travel_first_cover_msec := -1
var travel_uncovered_after_grace := 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
	return ok

func until(predicate: Callable, seconds := 60.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func presented() -> void:
	if phase.is_empty() or session == null or session.game == null: return
	var row: Dictionary = frames.get_or_add(phase, {"covered": 0, "exposed": 0, "transition": 0})
	if phase == "travel" and travel_requested_msec > 0:
		var elapsed := Time.get_ticks_msec() - travel_requested_msec
		if LoadingScreen._current != null and travel_first_cover_msec < 0:
			travel_first_cover_msec = elapsed
		if LoadingScreen._current == null and elapsed > 1000:
			travel_uncovered_after_grace += 1
	var pending := session.world == null or session.loading_game
	var where: Dictionary = session.lmp_locations.get(session.my_index, {})
	if bool(where.get("loading", false)):
		pending = true; row.transition += 1
	if not pending: return
	var key := "covered" if LoadingScreen._current != null else "exposed"
	row[key] += 1
	if row[key] == 1:
		get_viewport().get_texture().get_image().save_png("user://lmp-" + phase + "-" + key + ".png")

func menu_state(menu: Control, label: String) -> Dictionary:
	var out := {}
	for unit: Node in menu.find_children("*", "EIUnitModel", true, false):
		var layers: Array = unit.get_meta("layers", [])
		var tex := []
		for mi: Node in unit.find_children("*", "MeshInstance3D", true, false):
			var material: Material = mi.material_override
			if material is EIUnitModel.LitMaterial:
				var texture: Texture2D = material.albedo_texture
				var digest := "null" if texture == null else texture.get_image().get_data().hex_encode().sha256_text()
				if not tex.has(digest): tex.append(digest)
		out[String(unit.name)] = {"layers": str(layers), "textures": tex}
	textures[label] = out
	menu_database.append({"label": label, "lmp_db": GameData.lmp_db})
	return out

func _ready() -> void:
	await get_tree().process_frame
	var main := get_parent()
	reparent(get_tree().root)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,
		"autosave":0,"auto_graphics":0,"show_tutorial":0,"q_aa":0,"confine_mouse":0}, true)
	Gfx.ensure_globals(); Gfx.apply_surface_options()
	MoviePlayer.enabled = false
	check(LocalHost.available(), "real separate multiplayer authority is available")
	if not check(GameData.use_lmp_database(true), "native multiplayer database available"):
		finish(); return
	var faces := MpCharacter.faces()
	var character := MpCharacter.create(String(faces[0][0]))
	character.heroes[0].name = "WindowsFlow"
	MpCharacter.finish(character, "", "", "")
	check(MpCharacter.save_file("1.mp", character), "disposable original multiplayer character saved")
	MpCharacter.select("1.mp")
	GameData.use_lmp_database(false)
	var menu := load("res://src/ui/main_menu.gd").new() as Control
	menu.start_game.connect(func(s: Session): session = s)
	menu.start_game.connect(main.start_game)
	main.add_child(menu)
	menu._scene.set_hour(12.0); menu._scene.set_process(false)
	for i in 5: await get_tree().process_frame
	var before := menu_state(menu, "before")
	check(not before.is_empty(), "original menu creatures and textures captured")
	get_viewport().get_texture().get_image().save_png("user://lmp-menu-before.png")
	menu._net.lmp_base = "bz2mpg"
	await menu._host(2)
	check(menu._session.local_host.frontend, "real menu hosts through the separate process")
	RenderingServer.frame_post_draw.connect(presented)
	phase = "start"
	menu._start_coop()
	if not check(await until(func(): return session != null and session.world != null and session.zone_id == "bz2mpg" and not session.loading_game and not session._remote_loading), "original multiplayer enters Ingos"):
		await cleanup(main); return
	phase = ""
	check(session.my_index == 0 and not session.is_host and not session.world.authority, "host view remains player zero on client replication")
	check(int(frames.get("start", {}).get("covered", 0)) > 0, "start is covered by loading picture")
	check(int(frames.get("start", {}).get("exposed", 0)) == 0, "no empty HUD before original multiplayer loading")
	check(LoadingScreen._current == null, "start loading screen closes")
	var quest := String(session.lmp.get("quest", ""))
	if quest.is_empty():
		var topics: Array = session.lmp.get("topics", [])
		if check(not topics.is_empty(), "original quest giver has an offered topic"):
			var topic := String(topics[0])
			var briefing := topic.get_slice(".", 2)
			quest = briefing.trim_suffix("_1")
			var giver: GameUnit
			for unit: GameUnit in session.world.unit_rows():
				if String(unit.info.get("name", "")).to_lower() == topic.get_slice(".", 1).to_lower(): giver = unit
			if check(giver != null, "original quest giver exists"):
				session.submit({"t":"topic", "var":topic, "uid":giver.uid})
				check(await until(func(): return session.game.hud._dialog._id == topic and session.game.hud._dialog._mode >= DialogPanel.PLAYING, 45), "quest briefing opens through ordinary topic command")
				session.game.hud._dialog._finish()
				check(await until(func(): return String(session.lmp.get("quest", "")) == quest, 10), "original quest briefing completes")
	if not quest.is_empty() and String(session.lmp.get("quest", "")) == quest:
		phase = "travel"
		travel_requested_msec = Time.get_ticks_msec()
		session.submit({"t":"travel", "zone":quest, "entrance":1})
		check(await until(func(): return session.zone_id == quest and not session.loading_game and not session._remote_loading), "host enters the selected original quest")
		phase = ""
		check(int(frames.get("travel", {}).get("covered", 0)) > 0, "travel is covered while authority prepares")
		check(int(frames.get("travel", {}).get("exposed", 0)) == 0, "no frozen transition view before loading")
		check(travel_first_cover_msec >= 0 and travel_first_cover_msec < 1000, "loopback host presents travel loading picture within one second of request")
		check(travel_uncovered_after_grace == 0, "worker map preparation leaves no exposed travel view after loopback grace")
		check(LoadingScreen._current == null, "travel loading screen closes")
	await cleanup(main)
	var after_menu: Control
	for child: Node in main.get_children():
		if child is Control and child.get("_scene") is MenuScene: after_menu = child
	if check(after_menu != null, "real exit returns to main menu"):
		after_menu._scene.set_hour(12.0); after_menu._scene.set_process(false)
		for i in 5: await get_tree().process_frame
		var after := menu_state(after_menu, "after")
		check(after == before, "menu creatures retain original layers and texture bytes after multiplayer")
		check(not GameData.lmp_db, "campaign database restored before menu")
		get_viewport().get_texture().get_image().save_png("user://lmp-menu-after.png")
	finish()

func cleanup(main: Node) -> void:
	phase = ""
	await main.back_to_menu()
	session = null
	for i in 5: await get_tree().process_frame

func finish() -> void:
	var result := {"checks":checks,"failures":failures,"frames":frames,"menu_creatures":textures,
		"menu_database":menu_database,
		"travel_request_to_loading_ms":travel_first_cover_msec,
		"travel_exposed_frames_after_one_second":travel_uncovered_after_grace,
		"scope":"Real menu and separate native multiplayer authority; controlled public quest/travel commands; presented loading frames and exact menu creature texture/layer retention. Linux execution, not Windows performance or physical exit-route validation."}
	FileAccess.open("user://lmp-menu-flow.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("MENU_LMP_FLOW checks=",checks," failures=",failures)
	TexUpscale.shutdown(); UnitWounds.shutdown(); get_tree().quit(int(failures > 0))
