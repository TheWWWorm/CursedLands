extends "arena_expansion_ui.gd"
## Inspect every new native form in a real shop and its localized detail rail.
func _ready() -> void:
	OS.add_logger(errors); await frames(18)
	GameData._window_gen += 1; GameData.arena_mode = 0; GameData.options.confine_mouse = 0
	var lang := "en"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-lang="): lang = arg.get_slice("=", 1)
	RemakeText.lang = lang
	get_window().mode = Window.MODE_WINDOWED; get_window().size = Vector2i(1280, 800)
	screen = ArenaPveScreen.new(); add_child(screen); await frames(18)
	screen._begin(); screen.run.auto_save = false; screen.run.gold = 200
	screen.set_process(false)
	for rank in 3:
		for page in 2:
			screen.run.shop.clear()
			for family in range(12 + page * 6, 18 + page * 6):
				screen.run.shop.append({"family": family, "rank": rank, "locked": false})
			screen._refresh(); await frames(12)
			for slot in 6:
				var card := screen._shop.get_child(slot).get_child(0) as ArenaCreatureCard
				check(is_instance_valid(card.preview.creature), "native form has a rendered model")
				bounded(card, "new recruit")
				var family := 12 + page * 6 + slot
				screen._inspect(card.prototype, {"family": family, "rank": rank, "offer": slot})
				await frames(3)
				bounded(screen._inspector, "localized creature detail")
				check(not ArenaRules.title(card.prototype).is_empty() and ArenaRules.title(card.prototype).to_lower() != card.prototype, "native title hides internal ID")
			await shot("roster-%s-%d-%d" % [lang, rank, page])
			screen._hide_inspector()
	screen.queue_free(); await frames(8)
	check(errors.messages.is_empty(), "new roster renders without errors: " + JSON.stringify(errors.messages.slice(0, 3)))
	print("ARENA_ROSTER_UI ", lang, " checks=", checks, " failures=", JSON.stringify(failures))
	OS.remove_logger(errors); get_tree().quit(0 if failures.is_empty() else 1)
