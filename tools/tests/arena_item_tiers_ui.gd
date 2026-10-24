extends "arena_expansion_ui.gd"
## Inspect every localized reward at 720p, plus all tier borders and music lifecycle.
func _ready() -> void:
	OS.add_logger(errors)
	await frames(24)
	GameData._window_gen += 1
	Engine.max_fps = 30
	GameData.arena_mode = 0
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280,720)
	get_tree().root.position = Vector2i.ZERO
	var language := "en"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tier-lang="): language = arg.get_slice("=",1)
	RemakeText.lang = language
	screen = ArenaPveScreen.new(); add_child(screen)
	await frames(15)
	screen._seed_input.text = "6519"; screen._begin(); screen.run.auto_save = false
	Fixture.buy_company(screen.run, 1)
	for kind in ["blade","ward","storm","aegis","covenant"]:
		screen.run.items.append({"uid":screen.run.next_item_uid,"kind":kind,"unit_uid":0})
		screen.run.next_item_uid += 1
	screen.run._touch(); await frames(12)
	while ShaderCompilationScreen.active(): await frames(2)
	check(screen._item_tray.buttons.values().all(func(slot): return slot.attention), "unused items glow during preparation")
	var first_uid := int(screen.run.army[0].uid)
	screen.run.equip_item(1, first_uid); await frames(8)
	check(not screen._item_tray.buttons[1].attention and screen._item_tray.buttons[2].attention, "equipped item stops shining while inventory reminder remains")
	await shot("item-tiers-" + language + "-tray")
	for level in range(1, 6):
		var kinds := ArenaItems.RULES.keys().filter(func(k): return ArenaItems.tier(k) == level)
		for page in 3:
			screen._close_modal()
			screen._equipment_reward_seen = ""
			var choices: Array[String] = []
			for index in 3: choices.append(kinds[(page * 3 + index) % kinds.size()])
			screen.run.item_offers = choices
			screen.run.item_reward_round = [3,5,10,15,20][level - 1]
			screen.run._touch(); await frames(12)
			check(not screen._equipment_scroll.get_v_scroll_bar().visible, "reward chooser has no scrollbar")
			check(screen._equipment_panel._offer_row.get_child_count() == 3, "three choices at tier %d" % level)
			bounded(screen._modal_panel,"tier %d modal" % level)
			for card: ArenaEquipmentReward in screen._equipment_panel._offer_row.get_children():
				bounded(card,"card " + card.kind)
				check(screen._equipment_scroll.get_global_rect().grow(1).encloses(card.get_global_rect()), "complete card without scrolling " + card.kind)
				check(card.description.get_content_height() <= card.description.size.y + 1, "full effect text " + card.kind)
				check(card.description.get_parsed_text() == ArenaItems.description(card.kind,false), "localized mechanics " + card.kind)
				check(card._accent == ArenaCreatureCard.cost_accent(level), "shared tier palette " + card.kind)
			if page == 2: await shot("item-tiers-%s-%d" % [language,level])
	screen._close_modal(); screen.run.item_offers.clear()
	var music := screen._sound.music
	music.set_zone("ingos",false);music.hold=false
	music.request("cool",MusicSystem.NOW);music.tick(2)
	check(music._cur in music.combat_tracks and music._cur != "victory", "bell immediately replaces calm music with a fighting track")
	for index in 40: check(music._random("ingos", "Combat") in music.combat_tracks, "arena uses only fighting tracks")
	# A local final win gets one original victory track, independent of world changes.
	screen.run.stage = "won"
	screen._sync_victory_music()
	check(screen._victory_played and screen._victory_music._cur == "victory", "overall victory starts authored victory music")
	check(screen._victory_music.player.bus == "Music" and screen._sound.music._cur.is_empty(), "victory replaces combat music through the normal music bus")
	screen._victory_music.player.seek(8.0)
	screen._sync_victory_music(); await frames(2)
	check(screen._victory_music.player.get_playback_position() >= 7.9, "UI refresh does not restart victory")
	screen._victory_music._on_end()
	check(screen._victory_music._cur.is_empty() and not screen._victory_music.player.playing, "victory plays once, without looping")
	screen._sync_victory_music()
	check(screen._victory_music._cur.is_empty(), "completed cue stays finished")
	screen.run.stage = "prepare"; screen._sync_victory_music()
	check(not screen._victory_played, "new run resets victory cue")
	screen.run.stage = "result"; screen._sync_victory_music()
	check(not screen._victory_played, "ordinary round result has no finale")
	screen.run.stage = "lost"; screen._sync_victory_music()
	check(not screen._victory_played, "defeat does not play win music")
	screen.run.stage = "prepare"
	screen.queue_free(); await frames(8)
	OS.remove_logger(errors)
	check(errors.messages.is_empty(), "no runtime errors: " + str(errors.messages))
	print("ARENA_ITEM_TIERS_UI ",language," checks=",checks," failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
