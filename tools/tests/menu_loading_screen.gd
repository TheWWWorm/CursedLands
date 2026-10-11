extends Node
## Real menu entry + real single-player worker; audit every presented frame.
var session: Session
var checks := 0
var failures := 0
var monitoring := false
var exposed := 0
var covered := 0
var captured := false
var covered_captured := false
var new_game := false
var requested_zone := "bz1g"

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func presented() -> void:
	if not monitoring or session == null or session.game == null: return
	if session.world != null and not session.loading_game and not session._remote_loading: return
	if LoadingScreen._current != null:
		covered += 1
		if not covered_captured:
			covered_captured = true
			get_viewport().get_texture().get_image().save_png("user://menu-covered.png")
	else:
		exposed += 1
		if not captured:
			captured=true
			get_viewport().get_texture().get_image().save_png("user://menu-uncovered.png")

func _ready() -> void:
	# Keep the observer outside Main's real menu cleanup; worker RPC paths
	# must be Main/Session on both sides, just as in ordinary play.
	await get_tree().process_frame
	var main := get_parent()
	reparent(get_tree().root)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"control_mode":1,"scroll_border":0},true)
	new_game = OS.get_cmdline_user_args().has("--new-game")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zone="):requested_zone=arg.trim_prefix("--zone=")
	check(LocalHost.available(),"rendered single-player uses the simulation service")
	if not new_game:
		var st:=CampaignState.new();st.ensure_hero(0,"Human Hero")
		st.current_zone=requested_zone;st.visited[requested_zone]=true
		DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
		check(st.save(SaveInfo.path("quick"))==OK,"prepare disposable camp save")
		SaveInfo.write("quick",st.get_var(0,"gtime"),"gipat",requested_zone)
		if OS.get_cmdline_user_args().has("--legacy-info"):
			DirAccess.remove_absolute(SaveInfo.path("quick","info.sav"))
	var menu:=load("res://src/ui/main_menu.gd").new() as Control
	main.add_child(menu)
	menu.start_game.connect(func(s: Session):session=s)
	menu.start_game.connect(main.start_game)
	for i in 5:await get_tree().process_frame
	RenderingServer.frame_post_draw.connect(presented)
	monitoring=true
	if new_game:
		# Exercise the actual board and accepted difficulty signal. The movie
		# is skipped, as after Esc; the worker/load transition is unchanged.
		MoviePlayer.enabled = false
		await menu._on_board("new")
		check(menu._mods.visible and menu._mods._continue.visible,"New Game opens its rules review")
		menu._mods._continue.pressed.emit()
		check(menu._difficulty.visible,"New Game opens its difficulty panel")
		menu._difficulty._accept()
	elif OS.get_cmdline_user_args().has("--continue"):
		menu._continue()
	else:
		menu._load_slot("quick")
	var deadline:=Time.get_ticks_msec()+90000
	while (session==null or session.world==null or session.loading_game or session._remote_loading) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	monitoring=false
	check(session != null and session.local_host.frontend and session.local_host.process_id>0,"menu starts a real separate simulation process")
	check(session.world != null and session.zone_id==("gz1g" if new_game else requested_zone) and not session.loading_game,"menu reaches the requested playable zone")
	check(covered>0,"loading picture covers service startup")
	check(exposed==0,"no presented HUD frame before loading picture")
	check(LoadingScreen._current==null,"loading picture closes after successful load")
	print("MENU_LOADING_FRAMES covered=",covered," exposed=",exposed)
	FileAccess.open("user://menu-loading-screen.json",FileAccess.WRITE).store_string(JSON.stringify({
		"new_game":new_game,"deferred":LoadingScreen.deferred(),"covered":covered,"exposed":exposed,
		"zone":session.zone_id,"worker":session.local_host.frontend,"worker_pid":session.local_host.process_id},"\t"))
	check(not await session.load_game_shown("missing-slot"),"missing save returns failure")
	check(LoadingScreen._current==null,"failed load cleans up loading picture")
	if OS.get_cmdline_user_args().has("--back-to-menu"):
		await main.back_to_menu()
		check(main.session == null and main.game == null, "real menu return clears game and session")
	else:
		await session.local_host.stop()
		session.game.queue_free();session.queue_free()
	for i in 8:await get_tree().process_frame
	print("MENU_LOADING_SCREEN ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
