extends "arena_species_ui.gd"
## Exercise real field, inspector, ghost, reserve and reused-preview consumers.
func _ready() -> void:
	OS.add_logger(errors); await frames(8)
	GameData._window_gen += 1; GameData.arena_mode = 1
	GameData.options.merge(GfxPresets.values(GfxPresets.ORIGINAL),true)
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"auto_graphics":0,"autosave":0,"net_directory":0,"net_upnp":0},true)
	GameData.options.merge({"gfx_hd_textures":0,"gfx_sharp_units":0,"gfx_materials":0,"q_aa":0,"q_shadows":0},true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="): language = arg.trim_prefix("--lang=")
	RemakeText.lang = language
	get_window().mode = Window.MODE_WINDOWED; get_window().size = Vector2i(1280,800)
	await frames(6)
	screen = ArenaPveScreen.new(); add_child(screen); await frames(8)
	screen._seed_input.text = "7191"; screen._begin(); screen.run.auto_save = false
	screen.run.gold = 150; screen.run.training = 36; screen.run.army.clear()
	for pair in [[14,0],[14,2],[23,0],[23,1],[23,2],[20,2]]:
		screen.run._recruit(pair[0],pair[1],int(ArenaRules.FAMILIES[pair[0]].cost)*int(pow(3,pair[1])))
	screen.run.arrange()
	for pair in [[0,2],[1,2],[3,2]]: screen.run._recruit(pair[0],pair[1],9)
	screen.run.reserve_slots(); screen.run.shop.clear()
	for family in [0,14,23,16,11,20]: screen.run.shop.append({"family":family,"rank":0,"locked":false})
	for plan: Dictionary in screen.run.bot_plans: plan.done = true
	screen.run._touch(); await wait_models()
	for entry: Dictionary in screen.run.army:
		var expected := ArenaAppearance.info(entry.prototype,int(entry.family),int(entry.rank))
		if entry.deployed:
			var actor := body(int(entry.uid))
			check(actor != null and actor.model.get_meta("layers")[1][0] == expected.texture, "field uses rank palette %d:%d" % [entry.family,entry.rank])
		else:
			for slot: Button in screen._army_row.get_children():
				if slot.get_meta("arena_creature",{}).get("uid",-1) != entry.uid: continue
				var preview := slot.get_child(1) as WikiPreview
				check(preview != null and preview.creature._info.texture == expected.texture,"reserve uses rank palette %d:%d" % [entry.family,entry.rank])
	# The same combat prototype must visibly change inside one retained viewport.
	var card := ArenaCreatureCard.new(); card.family = 23; card.quality = 0
	card.prototype = ArenaRules.prototype(23,0); card.position = Vector2(560,220)
	add_child(card); await frames(30)
	var viewport := card.preview.creature._vp
	check(card.preview.creature._model.get_meta("layers")[1][0] == "dragon00", "reused card starts green")
	card.quality = 2; card.update_offer(); await frames(30)
	check(card.preview.creature._vp == viewport, "rank change retains preview render target")
	check(card.preview.creature._model.get_meta("layers")[1][0] == "dragon02", "same-prototype preview refreshes to red")
	card.queue_free(); await frames(4)
	screen.set_process(false); screen._evolution_notice.clear(); screen._clear_selection(); screen._hint("")
	for family: int in ArenaAppearance.RANK_PALETTES:
		for rank in 3:
			var id := ArenaRules.prototype(family,rank)
			screen._inspected_unit = null
			screen._inspect(id,{"family":family,"rank":rank,"prototype":id})
			await frames(6)
			var path := screen._inspect_box.get_node("EvolutionPath") as ArenaEvolutionPath
			var scroll := screen._inspect_scroll.get_v_scroll_bar()
			check(scroll.max_value <= scroll.page+1, "localized rank details fit %d:%d:%s" % [family,rank,language])
			check(screen._inspect_scroll.get_global_rect().grow(1).encloses(path.get_global_rect()), "three rank portraits remain visible %d:%d" % [family,rank])
			for step in 3:
				var portrait := path._steps[step].get_child(0).get_child(0) as TextureRect
				check(portrait.texture == ArenaPortraits.texture(ArenaRules.prototype(family,step),family,step), "evolution strip uses rank portrait %d:%d" % [family,step])
			if family == 14 and rank == 0: await shot("rank-"+language+"-green-troll")
			if family == 23 and rank == 2: await shot("rank-"+language+"-dragons")
	for entry: Dictionary in screen.run.army:
		if entry.family != 23 or not entry.deployed: continue
		screen._select(int(entry.uid)); await frames(4)
		check(screen.field.ghost.get_meta("layers")[1][0] == ArenaAppearance.info(entry.prototype,23,int(entry.rank)).texture, "deployment ghost matches dragon rank %d" % entry.rank)
	screen._clear_selection(); screen._hide_inspector(); screen._round_banner._age = 10
	await shot("rank-"+language+"-company")
	check(errors.messages.is_empty(), "no rendered diagnostics: "+str(errors.messages))
	if screen._tournament_battles is ArenaSoloBattles:
		var solo := screen._tournament_battles as ArenaSoloBattles
		if is_instance_valid(solo.connection): solo.connection.close()
	screen.queue_free(); screen = null; await frames(8)
	check(errors.messages.is_empty(), "clean worker and preview teardown: "+str(errors.messages))
	print("ARENA_RANK_APPEARANCE_UI ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
