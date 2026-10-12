extends "mod_network.gd"
## Separate processes and profiles: one peer has the real HD Lands package,
## the other has original textures. Exercise actual ENet admission and movement.
var use_hd := false
var view: Game

func goal(u: GameUnit) -> Vector2:
	for i in 16:
		var target := u.pos + Vector2.RIGHT.rotated(float(i) * TAU / 16.0 + float(session.my_index) * PI) * 24.0
		var path := session.world.nav.find_path(u.pos, target, [u], [], maxf(0.0,u.body_radius()-NavGrid.R_REF), u.move_class(), true)
		if path.size() > 1 and path[-1].distance_to(target) < 1.0: return target
	return u.pos

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"): get_tree().quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		if arg.begins_with("--coordination="): coordination = arg.trim_prefix("--coordination=")
		if arg == "--hd": use_hd = true
	check(not coordination.is_empty(), "explicit shared fixture directory")
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,"autosave":0,"auto_graphics":0,"show_tutorial":0,"control_mode":0}, true)
	TutorialPanel.auto_show = false
	for option: String in GameData.options:
		if option.begins_with("gfx_"): GameData.options[option] = 0
	if use_hd:
		check(ModStore.create_profile("HD co-op " + role).is_empty(), "create local texture profile")
		check(ModStore.set_packages(["community.hd-lands-textures@1.4.0"]).is_empty(), "select downloaded texture pack")
		check(GameData.open(GameData.root).is_empty(), "mount local HD textures")
	else:
		check(ModStore.profile().packages.is_empty(), "other peer uses original textures")
	GameData.player_name = "Texture " + role
	CoopProgress.bring_slot = CoopProgress.NEW if role == "client" else ""
	session = Session.new(); session.name = "Session"
	get_parent().add_child(session)
	view = Game.new(); view.session = session; session.game = view
	get_parent().add_child(view)
	if role == "host":
		check(session.host(0, 2) == OK, "start real ENet host on an unused port")
		ModStore.atomic_write(marker("ready"), str(session.host_port).to_utf8_buffer())
		check(await until(func(): return session.players.size() == 2), "peer with different textures admitted")
		session.state = CoopProgress.fresh_state()
		session.state.ensure_hero(1, "Human Hero", "Texture client")
		await session.enter_zone("bz1g", 1, false)
	else:
		check(await until(func(): return FileAccess.file_exists(marker("ready"))), "host ready")
		var actual_port := FileAccess.get_file_as_string(marker("ready")).to_int()
		check(session.join("127.0.0.1", actual_port) == OK, "connect real client")
	check(await until(func(): return session.world != null and session.zone_id == "bz1g" and not session.loading_game and not session._remote_loading and not session.party_units(session.my_index).is_empty(), 60.0), "both peers load the shared village")
	if failures: await finish(); return
	check(session.world.terrain._atlases.get_width() == (2048 if use_hd else 512), "peer retains its local texture resolution")
	var hero := session.party_units(session.my_index)[0] as GameUnit
	var start := hero.pos
	var target := goal(hero)
	check(start.distance_to(target) >= 20.0, "choose a long authored-ground movement command")
	ModStore.atomic_write(marker(role + "-loaded"), "ready".to_utf8_buffer())
	check(await until(func(): return FileAccess.file_exists(marker("host-loaded")) and FileAccess.file_exists(marker("client-loaded"))), "both peers ready for simultaneous movement")
	var before := session.world.time
	var elapsed := Time.get_ticks_msec()
	var frame_gaps := []
	var last := elapsed
	var distance := 0.0
	var previous := hero.pos
	var commands := 0
	var next_command := 0
	while Time.get_ticks_msec() - elapsed < 20000:
		var now := Time.get_ticks_msec()
		if now - elapsed >= next_command:
			if hero.pos.distance_to(target) < 2.0: target = start if target != start else goal(hero)
			session.submit({"t":"move", "units":[hero.uid], "x":target.x,"y":target.y,"run":false})
			commands += 1; next_command += 5000
		await get_tree().process_frame
		frame_gaps.append(Time.get_ticks_msec() - last); last = Time.get_ticks_msec()
		distance += hero.pos.distance_to(previous); previous = hero.pos
	check(distance > 5.0, "local or replicated hero continues moving")
	check(session.world.time - before > 5.0, "replicated simulation clock advances")
	check(session.players.size() == 2, "mixed-texture connection remains established")
	ModStore.atomic_write(marker(role + "-done"), "done".to_utf8_buffer())
	check(await until(func(): return FileAccess.file_exists(marker("host-done")) and FileAccess.file_exists(marker("client-done"))), "both peers finish movement")
	print("TEXTURE_COOP_MOTION ", JSON.stringify({"role":role,"hd":use_hd,"distance":distance,"commands":commands,"simulation_seconds":session.world.time-before,"max_frame_ms":frame_gaps.max()}))
	await finish()

func finish() -> void:
	session.online = false
	session.multiplayer.multiplayer_peer.close()
	view.queue_free(); session.queue_free()
	for i in 3: await get_tree().process_frame
	print("MOD_TEXTURE_COOP ", JSON.stringify({"role":role,"hd":use_hd,"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
