extends "arena_expansion_ui.gd"
## Exercise the actual picker and HUD at normal, 1440p and 4K scales.
func _ready() -> void:
	OS.add_logger(errors)
	GameData._window_gen += 1
	GameData.arena_mode = 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().borderless = true
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440),Vector2i(3840,2160)]:
		get_window().size = resolution
		await frames(8)
		for language: String in ["en","ru","de"]:
			GameData._window_gen += 1
			GameData.options.display_mode = 0
			GameData.resolution_size = "%dx%d" % [resolution.x,resolution.y]
			GameData.options.resolution = GameData.resolutions().find(resolution)
			get_window().size = resolution
			RemakeText.lang = language
			screen = ArenaPveScreen.new(); add_child(screen)
			await frames(16)
			while ShaderCompilationScreen.active(): await frames(2)
			var index := ArenaCommanders.choices().find("nalo")
			check(index >= 0, "Odalisque exists in real character picker")
			if index < 0: continue
			check(screen._character_picker.get_item_text(index) == ArenaCommanders.title("nalo"), "localized picker label " + language)
			screen._character_picker.select(index); screen._character_picker.item_selected.emit(index)
			screen._seed_input.text = "7191"; screen._begin(); screen.run.auto_save = false
			await frames(20)
			GameData._window_gen += 1
			get_window().size = resolution
			await frames(8)
			check(get_viewport().get_visible_rect().size == Vector2(resolution), "requested resolution is actually rendered")
			var portrait := screen._commander_portrait
			check(screen.run.commander == "nalo" and portrait.commander == "nalo", "picker launches the selected native commander")
			bounded(portrait,"Odalisque portrait")
			check(portrait.face != null and portrait._framed, "native face is framed at " + str(resolution))
			check(portrait.view.size.y >= int(portrait.size.y), "face rasterizes at displayed resolution")
			for winner in [-1,0,1]:
				screen.run.last_result = {"winner":winner,"wave":1}
				await frames(20)
				check(portrait.reaction == winner, "neutral, win and loss reach the HUD")
				var expected := Vector2.RIGHT if winner == 0 else Vector2.DOWN if winner == 1 else Vector2.ZERO
				check(portrait.face.get_shader_parameter("expression_weights").is_equal_approx(expected), "authored expression is applied")
				await shot("odalisque-%s-%d-%d" % [language,resolution.x,winner])
			screen._guide();await frames(8)
			bounded(screen._guide_scroll,"localized guide")
			var sections:=screen._guide_scroll.get_child(0).get_children()
			var rounds:Label
			for i in sections.size()-1:
				if sections[i] is Label and sections[i].text==RemakeText.t("Rounds"):rounds=sections[i+1]
			check(rounds!=null,"updated round damage help is present")
			if rounds!=null:
				check(rounds.autowrap_mode!=TextServer.AUTOWRAP_OFF and rounds.size.x<=screen._guide_scroll.size.x,
					"round damage help wraps within the guide in "+language)
				screen._guide_scroll.ensure_control_visible(rounds);await frames(8)
				await shot("round-damage-guide-%s-%d"%[language,resolution.x])
			screen._close_modal()
			screen.queue_free(); screen = null; await frames(8)
	check(errors.messages.is_empty(), "no runtime errors: " + JSON.stringify(errors.messages.slice(0,4)))
	print("ARENA_ODALISQUE_UI ",checks," checks ",failures.size()," failures")
	OS.remove_logger(errors); TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)
