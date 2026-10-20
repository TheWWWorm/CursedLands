extends "arena_expansion_ui.gd"
## Build an explicit schema-4 save in the isolated profile, then use the real
## migration and resume screen. Never depend on a developer's existing save.
func _ready() -> void:
	OS.add_logger(errors)
	await frames(20)
	GameData._window_gen += 1
	GameData.options.merge({"confine_mouse":0,"auto_graphics":0},true)
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1024,768)
	get_tree().root.position = Vector2i.ZERO
	GameData.arena_mode = 0
	var old := ArenaRun.new(); old.auto_save = false
	Fixture.begin(old, 6202)
	old.wave = 5
	var legacy := old.snapshot()
	legacy.version = 4; legacy.preparation_left = 45
	legacy.pact = ""; legacy.pact_rank = 0
	for i in legacy.army.size(): legacy.army[i].family = [0,2,4][i]
	legacy.shop = []
	for family in 5: legacy.shop.append({"family":family,"rank":0,"locked":false})
	var saved := FileAccess.open(ArenaRun.SAVE_PATH, FileAccess.WRITE)
	check(saved != null, "legacy fixture can be written in the isolated profile")
	if saved == null: get_tree().quit(1); return
	saved.store_string(JSON.stringify(legacy)); saved.close()
	screen = ArenaPveScreen.new(); add_child(screen); await frames(24)
	check(screen._saved and screen.run.wave == 5, "old player run resumes at the saved wave")
	check(screen.run.capacity() >= 4 and not screen.run.army.is_empty(), "migration retains the old army and capacity")
	# JSON stores all numbers as floats; Godot's Dictionary equality also
	# compares their Variant types. Compare the persisted integer fields
	# numerically without mistaking representation for lost progress.
	var restored_army := screen.run.army.duplicate(true)
	for entry: Dictionary in restored_army:
		for key in ["uid","family","rank","investment"]:
			entry[key] = int(entry[key])
	check(restored_army == old.army, "migration preserves every purchased unit and placement")
	if restored_army != old.army:
		print("ARENA_MIGRATION_DIAGNOSTIC ",JSON.stringify({"expected":old.army,"actual":restored_army}))
	for language in ["en","ru","de"]:
		RemakeText.lang = language
		screen._refresh(); await frames(8)
		screen._seed_input.show(); screen._layout_landing(); await frames(8)
		bounded(screen._landing_panel, language + " saved opening")
		bounded(screen._landing_start, language + " saved opening start")
		await shot("saved-opening-" + language)
	screen.queue_free(); await frames(4)
	check(errors.messages.is_empty(), "saved run opens without scene errors")
	print("ARENA_SAVED_OPENING ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
