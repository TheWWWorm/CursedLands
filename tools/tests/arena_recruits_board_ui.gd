extends "arena_species_ui.gd"
## The actual preparation board and inspector use all six new native stages.
func _ready() -> void:
	OS.add_logger(errors); await frames(8)
	GameData._window_gen += 1; GameData.arena_mode = 1
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"auto_graphics":0,"autosave":0,"net_directory":0,"net_upnp":0,"gfx_hd_textures":0,"gfx_sharp_units":0},true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="): language = arg.trim_prefix("--lang=")
	RemakeText.lang = language
	get_window().mode = Window.MODE_WINDOWED; get_window().size = Vector2i(1280,720)
	await frames(8)
	screen = ArenaPveScreen.new(); add_child(screen); await frames(8)
	screen._seed_input.text = "7191"; screen._begin(); screen.run.auto_save = false
	screen.run.gold = 80; screen.run.training = 36; screen.run.army.clear()
	for family in [28,29]:
		for rank in 3:
			var entry := screen.run._recruit(family,rank,int(ArenaRules.FAMILIES[family].cost)*int(pow(3,rank)))
			entry.deployed = true; entry.point = [27.0 if family == 28 else 22.0, 25.0 + rank * 7.0]
	screen.run.reserve_slots(); screen.run.shop.clear()
	for family in [28,29,28,29,28,29]: screen.run.shop.append({"family":family,"rank":0,"locked":false})
	for plan: Dictionary in screen.run.bot_plans: plan.done = true
	screen.run._touch(); await wait_models()
	screen.set_process(false); screen._round_banner._age = 10
	screen._evolution_notice.clear(); screen._clear_selection(); screen._hint("")
	var outfits := {}
	for entry: Dictionary in screen.run.army:
		var actor := body(int(entry.uid))
		check(actor != null and actor.model != null, "new form is rendered on the board %d:%d" % [entry.family,entry.rank])
		if actor == null or actor.model == null: continue
		check(actor.info.prototype == ArenaRules.prototype(int(entry.family),int(entry.rank)), "board preserves canonical identity")
		var appearance := ArenaAppearance.info(entry.prototype,int(entry.family),int(entry.rank))
		if int(entry.family) == 29:
			check(actor.info.get("texture","") == appearance.texture, "board uses native seer leader palette")
		var outfit := str([actor.model.get_meta("layers",[]), actor.figure_complexion(), actor.proto.weapon])
		check(not outfits.has(outfit), "all three field stages remain visibly distinct %d:%d" % [entry.family,entry.rank])
		outfits[outfit] = true
	await shot("new-recruits-" + language + "-board")
	for family in [28,29]:
		for rank in 3:
			var id := ArenaRules.prototype(family,rank)
			screen._inspected_unit = null
			screen._inspect(id,{"family":family,"rank":rank,"prototype":id})
			await frames(8)
			var path := screen._inspect_box.get_node("EvolutionPath") as ArenaEvolutionPath
			check(screen._inspect_scroll.get_global_rect().grow(1).encloses(path.get_global_rect()), "all three localized evolution stages fit %d:%d:%s" % [family,rank,language])
			for step in 3:
				var portrait := path._steps[step].get_child(0).get_child(0) as TextureRect
				check(portrait.texture == ArenaPortraits.texture(ArenaRules.prototype(family,step),family,step), "inspector shows native rank portrait")
	await shot("new-recruits-" + language + "-inspector")
	check(errors.messages.is_empty(), "no rendered diagnostics: " + str(errors.messages))
	if screen._tournament_battles is ArenaSoloBattles:
		var solo := screen._tournament_battles as ArenaSoloBattles
		if is_instance_valid(solo.connection): solo.connection.close()
	screen.queue_free(); screen = null; await frames(8)
	print("ARENA_RECRUITS_BOARD_UI ", JSON.stringify({"checks":checks,"failures":failures,"language":language}))
	get_tree().quit(0 if failures.is_empty() else 1)
