extends "mod_texture_png.gd"
## CL-204: edit an installed atlas while the campaign is open, then reload through the console.

func ready_in_field(s: Session) -> bool:
	return s.world != null and not s._remote_loading and not s.loading_game and LoadingScreen._current == null and not s.party_units(0).is_empty()

func wait_for(test: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 90000
	while not test.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return test.call()

func atlas_matches(game: Game, color: Color) -> bool:
	var layer := game.world.terrain._atlases.get_layer_data(0)
	return layer != null and layer.get_pixel(3, 3).is_equal_approx(color)

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"):
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	run_reload.call_deferred()

func run_reload() -> void:
	var main := get_parent()
	reparent(get_tree().root)
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	GameData.options.merge({"gfx_hd_textures":0, "pt_mode":0, "autosave":0, "net_upnp":0, "net_websocket":0,
		"net_lan":0, "net_directory":0, "show_tutorial":0, "confine_mouse":0, "show_fps":1,
		"volume_sfx":0, "volume_stream":0, "volume_voice":0}, true)
	var header := EITerrain.load_map("zone1", false)
	var entry := header.resource_prefix + "000.mmp"
	var size := header.texture_size
	header.free()
	var original := Color8(32, 72, 218)
	var edited := Color8(220, 112, 26)
	var m := manifest("test.reload")
	m.overrides = [{"archive":"textures.res", "entry":entry, "file":"atlas.png"}]
	check(ModStore.import_package(pack(m, {"atlas.png":png(size, original)})).is_empty(), "install atlas")
	check(ModStore.create_profile("Texture reload").is_empty(), "create isolated mod profile")
	check(ModStore.set_packages(["test.reload@1.0"]).is_empty(), "select atlas")
	DataSwitch.clear_caches()
	check(GameData.open(GameData.root).is_empty(), "mount installed texture")
	var s := Session.new()
	main.add_child(s)
	s.players = {1:{"index":0, "name":"CL-204"}}
	main.start_game(s)
	await s.new_campaign(false)
	var ready := await wait_for(func(): return ready_in_field(s) and s.zone_id == "gz1g")
	check(ready, "campaign started in Ruins")
	if ready:
		var game: Game = main.game
		check(s.local_host.frontend != OS.get_cmdline_user_args().has("--ei-inline-host"), "requested authority")
		check(atlas_matches(game, original), "original atlas is on the terrain")
		# A modder can import a valid save under the old temporary name.
		var existing := "texture_reload"
		check(s.state.save(SaveInfo.path(existing)) == OK, "seed named campaign save")
		SaveInfo.write(existing, 7.0, "Gipat", s.zone_id, "Imported save")
		var preview := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		preview.fill(Color.DARK_GREEN)
		SaveInfo.write_shot_image(existing, preview)
		var expected := {}
		for ext in ["sav", "info.sav", "shot.png"]:
			expected[ext] = FileAccess.get_file_as_bytes(SaveInfo.path(existing, ext))
			check(not expected[ext].is_empty(), "seed named " + ext)
		var initial_files := DirAccess.get_files_at(SaveInfo.directory())
		var initial_dirs := DirAccess.get_directories_at(SaveInfo.directory())
		var before: Vector2 = s.party_units(0)[0].pos
		var previous: WeakRef = weakref(game.world.terrain)
		var file := ModStore.override_path("textures.res", entry)
		check(ModStore.atomic_write(file, png(size, edited)).is_empty(), "edit the installed file")
		check(atlas_matches(game, original), "terrain keeps old pixels until the command")
		DeveloperConsole.run("reload_textures")
		var restored := await wait_for(func(): return RemakeText.t("Textures reloaded.") in DeveloperConsole.lines and ready_in_field(s))
		check(restored, "console reports successful reload")
		if restored:
			check(game.world.terrain != previous.get_ref(), "world has rebuilt its terrain")
			check(atlas_matches(game, edited), "rebuilt terrain displays the edited pixels")
			check(s.zone_id == "gz1g" and before.distance_to(s.party_units(0)[0].pos) < 0.1, "restore hero in place")
			for ext in expected:
				var restored_file := SaveInfo.path(existing, ext)
				check(FileAccess.file_exists(restored_file) and FileAccess.get_file_as_bytes(restored_file) == expected[ext], "preserve named " + ext)
			check(DirAccess.get_files_at(SaveInfo.directory()) == initial_files, "remove temporary reload files")
			check(DirAccess.get_directories_at(SaveInfo.directory()) == initial_dirs, "remove private reload directory")
	if s.local_host.frontend:
		await s.local_host.stop()
	print("MOD_TEXTURE_RELOAD ", checks, " checks ", failures, " failures")
	TexUpscale.shutdown()
	get_tree().quit(int(failures > 0))
