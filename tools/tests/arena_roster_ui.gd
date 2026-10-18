extends "arena_expansion_ui.gd"
## Inspect every new native form in a real shop and its localized detail rail.
func wait_offers() -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if screen._shop.get_children().all(func(box): return not (box.get_child(0) as ArenaCreatureCard)._preview_pending): return
		await frames(1)
	check(false, "background recruit previews finish")

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
	var viewports := {}
	for rank in 3:
		for page in ceili((ArenaRules.FAMILIES.size()-24)/6.0):
			screen.run.shop.clear()
			for slot in 6:
				var family := 24+posmod(page*6+slot,ArenaRules.FAMILIES.size()-24)
				screen.run.shop.append({"family": family, "rank": rank, "locked": false})
			screen._refresh(); await wait_offers(); await frames(12)
			for slot in 6:
				var card := screen._shop.get_child(slot).get_child(0) as ArenaCreatureCard
				check(is_instance_valid(card.preview.creature), "native form has a rendered model")
				check(card.preview.creature._info.prototype == card.prototype and not card._preview_pending, "staged preview displays current offer")
				check(card.get_meta("arena_creature").id == card.prototype and card._stars.count == rank + 1, "reused offer inspector and stars follow rank")
				if rank == 0: viewports[slot] = card.preview.creature._vp.get_instance_id()
				else: check(viewports[slot] == card.preview.creature._vp.get_instance_id(), "round refresh retains shop render target")
				bounded(card, "new recruit")
				var family := 24+posmod(page*6+slot,ArenaRules.FAMILIES.size()-24)
				screen._inspect(card.prototype, {"family": family, "rank": rank, "offer": slot})
				await frames(3)
				bounded(screen._inspector, "localized creature detail")
				check(not ArenaRules.title(card.prototype).is_empty() and ArenaRules.title(card.prototype).to_lower() != card.prototype, "native title hides internal ID")
				if lang != "en":
					var translated:=ArenaRules.title(card.prototype)
					RemakeText.lang="en";var english:=ArenaRules.title(card.prototype);RemakeText.lang=lang
					# Some authored names are shared across languages (German Ghoul).
					var authored:bool=RemakeText.TEXTS.has(english) and RemakeText.TEXTS[english][0 if lang=="ru" else 1]==translated
					check(translated!=english or authored,"native recruit title is localized: "+english)
			await shot("roster-%s-%d-%d" % [lang, rank, page])
			screen._hide_inspector()
	for slot in 6: screen.run.shop[slot] = {"family": 29-slot, "rank":0, "locked": slot == 0}
	screen._refresh(); await wait_offers(); await frames(16)
	for slot in 6:
		var card := screen._shop.get_child(slot).get_child(0) as ArenaCreatureCard
		check(card.family == 29-slot and card.get_meta("arena_creature").family == card.family, "rerolled inspector follows family")
		check(card._traits.get_child_count() == ArenaAlliances.traits(card.family).size(), "rerolled tribe icons follow family")
		check(card.preview.creature._info.prototype == card.prototype and viewports[slot] == card.preview.creature._vp.get_instance_id(), "rerolled model retains viewport")
	screen.queue_free(); await frames(8)
	check(errors.messages.is_empty(), "new roster renders without errors: " + JSON.stringify(errors.messages.slice(0, 3)))
	print("ARENA_ROSTER_UI ", lang, " checks=", checks, " failures=", JSON.stringify(failures))
	OS.remove_logger(errors); get_tree().quit(0 if failures.is_empty() else 1)
