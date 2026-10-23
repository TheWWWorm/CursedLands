extends "arena_expansion_ui.gd"
## Render the corrected native quest documents in the real journal in EN/RU/DE.

func _ready() -> void:
	OS.add_logger(errors);await frames(8)
	GameData._window_gen+=1
	get_window().mode=Window.MODE_WINDOWED
	get_window().position=Vector2i.ZERO
	var session := Session.new();session.state=CampaignState.new()
	var game := Game.new();game.session=session
	var hud := GameHUD.new();hud.game=game
	var safe := Control.new();add_child(safe)
	for language: String in ["en","ru","de"]:
		RemakeText.lang=language;GameData._text_cache.clear()
		var panel := JournalPanel.new();panel.hud=hud;safe.add_child(panel)
		for dimensions: Vector2i in [Vector2i(800,600),Vector2i(1280,800)]:
			get_window().size=dimensions;await frames(4)
			safe.size=Vector2(dimensions)
			for quest: String in ["q10j","q11k","q13h","q18j"]:
				session.state.vars.clear()
				session.state.set_var(0,"q.test."+quest,1)
				for n in range(1,9):session.state.set_var(0,"q.test."+quest+"."+str(n),1)
				panel.open();panel._text.scroll_to_line(0);await frames(8)
				var doc := JournalPanel._parse(quest)
				var shown := panel._text.get_parsed_text()
				check(shown.contains(doc.title) and shown.contains(doc.text.strip_edges()),language+": corrected journal document "+quest)
				check(not shown.contains("#subobj"),"native objective markup is parsed")
				bounded(panel,language+" journal "+quest)
				check(panel.get_global_rect().encloses(panel._text.get_global_rect()),"localized journal text fits panel")
				check(panel._text.get_content_width()<=panel._text.size.x+1,"localized lines wrap within journal")
				if quest=="q10j":
					check(shown.contains({"en":"river south of Radu","ru":"у реки южнее палатки Рада","de":"Fluss südlich von Radu"}[language]),"corrected directions visible in journal")
					await shot("lia-journal-"+language+"-"+str(dimensions.x))
					var scroll := panel._text.get_v_scroll_bar()
					if panel._text.get_content_height()>panel._text.size.y:
						check(scroll.visible and scroll.max_value>scroll.page,"long journal document remains scrollable")
						scroll.value=scroll.max_value;await frames(4)
						await shot("lia-journal-"+language+"-"+str(dimensions.x)+"-bottom")
		panel.queue_free();await frames(3)
	safe.queue_free();hud.free();game.free();session.free()
	await frames(3);OS.remove_logger(errors)
	check(errors.messages.is_empty(),"no runtime errors: "+str(errors.messages))
	print("ASTRAL_PATCH_JOURNAL_UI ",JSON.stringify({"checks":checks,"failures":failures}))
	TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
