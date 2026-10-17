extends "lia_tomb_exit.gd"
## Render a pre-fix tomb checkpoint and the existing leave confirmation.
## --ui-texts may supply an original EN/DE texts.res for the confirmation;
## the LiA map, scripts and all other campaign assets remain unchanged.

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	var fixture := ""
	var ui_texts := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--save-fixture="): fixture=arg.trim_prefix("--save-fixture=")
		if arg.begins_with("--ui-texts="): ui_texts=arg.trim_prefix("--ui-texts=")
	if fixture.is_empty() or DisplayServer.get_name()=="headless":
		printerr("Supply --save-fixture and a rendering display"); get_tree().quit(1); return
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"scroll_border":0,"auto_exit":0,
		"camera_style":0,"control_mode":1,"confine_mouse":0},true)
	host=branch(false); host.set_physics_process(false)
	var old := CampaignState.load_from(fixture)
	check(old!=null and host._load_state("old_tomb_ui",old),"pre-fix checkpoint loads in rendered game")
	if host.world==null: await finish(); return
	freeze(host); ticks(30)
	var center: Vector2=host.world.zone.exits[1].remove.get_center()
	var hero: GameUnit=host.party_units(0)[0]
	hero.pos=center; hero.resync_drawn(); host.game.selected.assign([hero])
	var rig:=host.game.rig
	rig.center_on(hero.global_position); rig.yaw=PI; rig.pitch=deg_to_rad(-40); rig.distance=20; rig._apply()
	GameData.options.display_mode=0
	GameData.options.resolution=GameData.resolutions().find(Vector2i(1024,768))
	GameData._apply_window()
	await frames(40)
	await get_tree().create_timer(1.8).timeout # let the real-time load notice fade
	check(get_window().size==Vector2i(1024,768),"rendered check uses 1024x768")
	check(host.open_exit_at(center,0)==1,"recovered exit has a live move target")
	var pad: PadField=host.game.get_node("PadField")
	check(pad.labels.entries().any(func(entry):return entry[3]=="cursor_move" and entry[1]==host.zone_title("gz11g")),"exit appears in world interaction labels")
	var fx:=ParticleFx.of(host.world)
	check(fx._exit_fx.size()==1 and fx._exit_fx[0][0].e.v130.x==0,"original exit particles use the open-state colour")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://tomb-exit.png")
	if not ui_texts.is_empty():
		var archive:=EIResArchive.open_path(ui_texts)
		check(archive!=null,"original localization archive loads")
		if archive:
			var code_page:=EIText.code_page
			EIText.code_page=EIText.detect_code_page(archive)
			RemakeText.lang=RemakeText.detect(archive)
			for key: String in ["string leave_zone","string leave_zone_msg","tip 50100","tip 50101"]:
				GameData._text_cache[key]=EIText.ansi(archive.read(key)).replace("\r","")
			EIText.code_page=code_page
	host._arm_exit(0,center,true,1); host._check_exits()
	var box:=host.game.hud._leave_box
	check(MessageBox.is_up(box),"normal exit input opens localized confirmation")
	if MessageBox.is_up(box):
		check(not box.title.is_empty() and not box.message.is_empty(),"original confirmation title and message are translated")
		var rects:=box._rects()
		check(rects.top>=0 and rects.cancel.end.y<=600,"localized confirmation and actions fit the screen")
		await frames(8); await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://tomb-confirm-"+RemakeText.lang+".png")
		box._answer(true)
		check(await until(func():return host.zone_id=="gz11g" and not host.loading_game),"confirmation button returns to the Rift")
	print("LIA_TOMB_EXIT_UI ",RemakeText.lang," ",checks," checks ",failures," failures")
	await finish()
