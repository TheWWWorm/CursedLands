extends "arena_expansion_ui.gd"
## Hovering a creature on the board opens its details card at the right edge,
## 16 logical pixels from the border, over the tournament's player list (which
## it hides while it is open) and clear of the commander bust. The card used to
## open beside the bust, in the middle of the screen, over the board where
## units are placed and picked. Runs at 1280x720, 2560x1440 and 3840x2160 in
## the language given by --lang=; saves user://inspector-<lang>-<h>-<state>.png.

const SIZES := [Vector2i(1280, 720), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const EDGE := 16.0


func dimensions(value: Vector2i) -> void:
	GameData._window_gen += 1
	get_window().size = value
	get_window().position = Vector2i.ZERO
	await frames(14)


func capture(label: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://inspector-" + label + ".png")
	print("CAPTURE ", label, " ", image.get_size())


## The hovered creature's details, through the real board hover.
func hover(unit: GameUnit) -> void:
	screen._hide_inspector()
	await move(Vector2(get_viewport().get_visible_rect().size.x * 0.5, 4))
	await frames(4)
	var at := point(unit)
	for i in 30:
		await move(at)
		if screen._inspector.visible: break
		await get_tree().create_timer(0.05).timeout
	await frames(6)


func _ready() -> void:
	OS.add_logger(errors)
	await frames(24)
	GameData.arena_mode = 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().borderless = true
	var lang := "en"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="): lang = arg.trim_prefix("--lang=")
	RemakeText.lang = lang
	await dimensions(SIZES[0])
	screen = ArenaPveScreen.new(); add_child(screen)
	await frames(16)
	while ShaderCompilationScreen.active(): await frames(2)
	screen._seed_input.text = "7191"; screen._begin(); screen.run.auto_save = false
	Fixture.buy_company(screen.run, 1)
	await frames(18)
	while ShaderCompilationScreen.active(): await frames(2)
	check(screen.run is ArenaTournamentRun, "the tournament shows its player list")
	var entry: Dictionary = screen.run.army[0]
	for size: Vector2i in SIZES:
		await dimensions(size)
		var tag := "%s %dx%d" % [lang, size.x, size.y]
		screen._hide_inspector(); screen._build_standings(); screen._layout_standings()
		await frames(6)
		check(screen._standings.visible, tag + ": player list shown before hovering")
		var players := screen._standings.get_global_rect()
		var scale := screen._ui_scale
		await capture("%s-%d-board" % [lang, size.y])
		var unit := body(int(entry.uid))
		check(unit != null and point(unit) != Vector2.ZERO, tag + ": the creature is on screen")
		if unit == null: continue
		await hover(unit)
		check(screen._inspector.visible and screen._rail.visible, tag + ": hovering the creature opens its details")
		var card := screen._rail.get_global_rect()
		var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		bounded(screen._rail, tag + ": creature details")
		check(absf(view.end.x - card.end.x - EDGE * scale) <= 2.0, tag + ": card keeps %d px from the right border, found %.1f" % [EDGE, (view.end.x - card.end.x) / scale])
		check(absf(card.position.y - players.position.y) <= 2.0, tag + ": card starts where the player list starts (%.1f / %.1f)" % [card.position.y, players.position.y])
		check(card.intersects(players), tag + ": card is shown over the player list")
		check(not screen._standings.visible, tag + ": player list is hidden under the card")
		check(card.position.x >= view.size.x * 0.6, tag + ": card stays at the side, clear of the board centre (left %.0f of %.0f)" % [card.position.x, view.size.x])
		check(not card.intersects(unit.screen_rects(screen.field.camera)[0] if not unit.screen_rects(screen.field.camera).is_empty() else Rect2()), tag + ": card leaves the hovered creature visible")
		if is_instance_valid(screen._commander_portrait) and screen._commander_portrait.visible:
			check(not card.intersects(screen._commander_portrait.get_global_rect()), tag + ": card clears the commander bust")
		check(not card.intersects(screen._shop_panel.get_global_rect()), tag + ": card clears the shop")
		var content := screen._inspect_box.get_combined_minimum_size().y * scale
		check(screen._inspect_scroll.size.y * scale + 1.0 >= content or screen._inspect_scroll.get_v_scroll_bar().visible, tag + ": the whole card can be read")
		await capture("%s-%d-hover" % [lang, size.y])
		# Moving onto the card keeps it open; leaving it brings the player list back.
		await move(card.get_center())
		await get_tree().create_timer(0.4).timeout
		check(screen._inspector.visible, tag + ": the card stays open under the pointer")
		await move(Vector2(view.size.x * 0.5, 4))
		await get_tree().create_timer(0.6).timeout
		await frames(4)
		check(not screen._rail.visible, tag + ": leaving closes the card")
	screen.queue_free(); screen = null; await frames(8)
	check(errors.messages.is_empty(), "no runtime errors: " + JSON.stringify(errors.messages.slice(0, 4)))
	print("ARENA_INSPECTOR_SIDE_UI ", checks, " checks ", failures.size(), " failures")
	OS.remove_logger(errors); TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)
