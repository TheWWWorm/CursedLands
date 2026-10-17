extends "arena_expansion_ui.gd"
## Use a copied pre-v8 player save to exercise migration and the resume screen.
func _ready() -> void:
	OS.add_logger(errors)
	await frames(20)
	GameData._window_gen += 1
	GameData.options.merge({"confine_mouse":0,"auto_graphics":0},true)
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1024,768)
	get_tree().root.position = Vector2i.ZERO
	screen = ArenaPveScreen.new(); add_child(screen); await frames(24)
	check(screen._saved and screen.run.wave == 5, "old player run resumes at the saved wave")
	check(screen.run.capacity() >= 4 and not screen.run.army.is_empty(), "migration retains the old army and capacity")
	for language in ["en","ru","de"]:
		RemakeText.lang = language
		screen._refresh(); await frames(8)
		screen._seed_input.show(); screen._layout_landing(); await frames(8)
		bounded(screen._landing_panel, language + " saved opening")
		bounded(screen._landing_start, language + " saved opening start")
		await shot("saved-opening-" + language)
	screen.queue_free(); await frames(4)
	check(errors.messages.is_empty(), "saved run opens without scene errors")
	print("ARENA_SAVED_OPENING ", checks, " checks; failures=", JSON.stringify(failures), " errors=", JSON.stringify(errors.messages))
	get_tree().quit(0 if failures.is_empty() else 1)
