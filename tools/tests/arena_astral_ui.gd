extends "arena_expansion_ui.gd"
func _ready() -> void:
	OS.add_logger(errors); await frames(20)
	GameData._window_gen += 1
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"auto_graphics":0,"net_upnp":0},true)
	get_window().mode = Window.MODE_WINDOWED; get_window().size = Vector2i(1600,900); get_window().position = Vector2i.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--astral-path="): GameData.campaign_roots[CampaignProfile.ASTRAL] = arg.trim_prefix("--astral-path=")
	check(ArenaExpansion.mount(), "mount expansion")
	GameData.arena_mode = 2; GameData.arena_character = "lia_hero"
	for lang in ["en","ru","de"]:
		RemakeText.lang = lang
		screen = ArenaPveScreen.new(); add_child(screen); await frames(30)
		while ShaderCompilationScreen.active(): await frames(2)
		bounded(screen._landing_panel,"localized landing " + lang)
		check(not (screen.find_child("AstralMode", true, false) as Button).disabled, "installed expansion mode enabled " + lang)
		check(screen.run.expansion and screen._character_picker.item_count == 15,"expansion roster and characters " + lang)
		await shot("astral-landing-" + lang)
		get_window().size = Vector2i(1280,720); await frames(12)
		bounded(screen._landing_panel, "small localized landing " + lang)
		check(screen._landing_panel.get_global_rect().encloses(screen._skin_picker.get_global_rect()), "skin selector fits small landing " + lang)
		await shot("astral-landing-720-" + lang)
		get_window().size = Vector2i(1600,900); await frames(12)
		if lang == "en":
			var appearances := []
			for who: String in ArenaCommanders.choices(true): appearances.append_array(ArenaCommanders.skins(who))
			for id: String in appearances:
				var portrait := screen._character_preview
				screen._character_picker.item_selected.emit(ArenaCommanders.choices(true).find(ArenaCommanders.character(id)))
				screen._skin_picker.item_selected.emit(ArenaCommanders.skins(id).find(id))
				await frames(12)
				check(GameData.arena_character == id and portrait.commander == id, "skin selection updates native preview " + id)
				check(screen._skin_row.visible == (ArenaCommanders.skins(id).size() > 1), "skin choices appear only for distinct variants " + id)
				check(portrait.face.get_shader_parameter("portrait_unlit") == true, "native portrait avoids double lighting " + id)
				check(portrait._framed and portrait.face != null, "native animated bust " + id)
				await RenderingServer.frame_post_draw
				portrait.view.get_texture().get_image().save_png("user://astral-"+id.replace(":","-")+"-neutral.png")
				portrait.set_result(0,id); await frames(14)
				await RenderingServer.frame_post_draw
				portrait.view.get_texture().get_image().save_png("user://astral-"+id.replace(":","-")+"-smile.png")
				await get_tree().create_timer(2.2, true, false, true).timeout
				check(portrait._expression_mix.is_zero_approx(), "expression returns to neutral " + id)
				portrait.set_result(1,"skin-loss:"+id); await frames(14)
				await RenderingServer.frame_post_draw
				portrait.view.get_texture().get_image().save_png("user://astral-"+id.replace(":","-")+"-frown.png")
		GameData.arena_character = "lia_hero"
		screen.queue_free(); screen = null; await frames(10)
		var panel := ArenaOnlinePanel.new(); add_child(panel); panel.open()
		for page in [NetworkPanel.HOST_COOP, NetworkPanel.JOIN_COOP]:
			panel.page = page; panel.queue_redraw(); await frames(6)
			for index in panel._rows().size():
				check(NetworkPanel.TOP.encloses(panel._row_rect(index)), "online row fits " + lang + str(page) + str(index))
			check(panel._rows().any(func(row): return row.id == "arena_mode" and row.on and row.value == RemakeText.t("LiA autochess")), "online expansion mode " + lang)
			await shot("astral-online-" + lang + "-" + str(page))
		panel.queue_free(); await frames(3)
	RemakeText.lang = "en"
	screen = ArenaPveScreen.new(); add_child(screen); await frames(20)
	screen._seed_input.text = "78241"; screen._begin(); screen.run.auto_save = false
	screen.run.training = ArenaRules.MAX_TRAINING
	screen.run.army.clear()
	for index in ArenaExpansion.FAMILIES.size():
		var entry := screen.run._recruit(ArenaExpansion.FAMILIES[index], 0, 1)
		entry.deployed = true; entry.point = [23.0 + (index % 2) * 5, 22.0 + (index / 2) * 6]
	for plan in screen.run.bot_plans: plan.done = true
	screen.run._touch(); await frames(50)
	while ShaderCompilationScreen.active(): await frames(2)
	for family: int in ArenaExpansion.FAMILIES:
		check(ArenaPortraits.texture(ArenaRules.prototype(family,0),family,0) != null, "native damage portrait " + str(family))
	check(screen.battle.world.unit_rows().filter(func(u):return u.faction == 1).size()==8,"all new families render on the board")
	await shot("astral-roster")
	check(errors.messages.is_empty(), "no runtime errors: " + str(errors.messages))
	print("ARENA_ASTRAL_UI checks=",checks," failures=",JSON.stringify(failures))
	OS.remove_logger(errors); TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)
