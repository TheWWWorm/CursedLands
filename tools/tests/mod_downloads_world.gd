extends Node
## Opt-in rendered smoke of the package installed by mod_downloads_live.gd.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"): get_tree().quit(2); return
	var key := ModCatalog.key(ModCatalog.entry("community.hd-lands-textures"))
	check(ModStore.catalog.has(key), "real downloaded texture package is installed")
	if failures: get_tree().quit(1); return
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"gfx_hd_textures":0,"confine_mouse":0,"volume_sfx":0,"volume_stream":0,"volume_voice":0}, true)
	TutorialPanel.auto_show = false
	RenderingServer.set_render_loop_enabled(true)
	check(ModStore.create_profile("Downloaded texture world check", false).is_empty(), "create isolated world profile")
	check(ModStore.set_packages([key]).is_empty() and GameData.open(GameData.root).is_empty(), "activate downloaded textures")
	var session := Session.new()
	get_parent().add_child(session)
	var game := Game.new()
	game.session = session; session.game = game
	get_parent().add_child(game)
	session.state = CoopProgress.fresh_state()
	await session.enter_zone("bz1g", 1, false)
	check(session.world != null and not session.party_units(0).is_empty(), "village and hero load")
	var terrain: EITerrain = session.world.terrain
	check(terrain._atlases.get_width() == 2048 and terrain._atlases.get_layers() == 8, "downloaded terrain loads at its authored HD resolution")
	check(terrain.texture_size == 512 and terrain.tile_size == 64, "map coordinates and UV layout unchanged")
	for i in 8:
		check(terrain._atlas_image(i).get_data() == EIMmp.decode(GameData.textures.read("basegipat%03d.mmp" % i)).get_data(), "rendered terrain matches downloaded pixels: " + str(i))
	for i in 90: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("user://downloaded-hd-lands-village.png") == OK, "save real engine screenshot")
	game.queue_free(); session.queue_free()
	for i in 5: await get_tree().process_frame
	check(ModStore.select_profile("default").is_empty() and GameData.open(GameData.root).is_empty(), "restore unmodded data after rendered session")
	print("MOD_DOWNLOADS_WORLD ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
