extends "arena_expansion_ui.gd"
## Actual hover, localized popup bounds, reaction expiry and rendered item edges.

func _ready() -> void:
	OS.add_logger(errors)
	await frames(24)
	GameData._window_gen += 1
	GameData.arena_mode = 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().position = Vector2i.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="): RemakeText.lang = arg.trim_prefix("--lang=")
	get_window().size = Vector2i(2560,1440)
	screen = ArenaPveScreen.new(); add_child(screen)
	await frames(16)
	screen._seed_input.text = "7191"; screen._begin(); screen.run.auto_save = false
	Fixture.buy_company(screen.run,1)
	for kind in ["vitality","ward","storm","aegis","covenant"]:
		screen.run.items.append({"uid":screen.run.next_item_uid,"kind":kind,"unit_uid":0})
		screen.run.next_item_uid += 1
	screen.run._touch()
	await frames(18)
	while ShaderCompilationScreen.active(): await frames(2)
	var portrait := screen._commander_portrait
	check(portrait.get_global_rect().end.is_equal_approx(get_viewport().get_visible_rect().end), "portrait is flush with bottom and right")
	check(is_equal_approx(portrait.size.x,200) and is_equal_approx(portrait.size.y,200), "portrait is two thirds of the previous footprint")
	check(screen._army_title.get_theme_font("font") == screen._reserve_count.get_theme_font("font"), "Army and Reserves use the same scalable font")
	check(screen._army_title.get_theme_font("font").multichannel_signed_distance_field, "Army remains sharp when HUD scales up")
	check(screen._army_title.get_theme_color("font_color") == screen._reserve_count.get_theme_color("font_color"), "Army and Reserves have matching white ink")
	await shot("polish-"+RemakeText.lang+"-board")
	await inspect_company(screen._army_title,"army-large")
	await inspect_company(screen._train_button,"level-large")
	for window_size in [Vector2i(1280,720),Vector2i(1024,768)]:
		screen._hide_inspector()
		get_window().size = window_size; await frames(10)
		await inspect_company(screen._army_title,"army-"+str(window_size.x))
		await inspect_company(screen._train_button,"level-"+str(window_size.x))
	screen._hide_inspector(); await move(Vector2(500,300))
	get_window().size = Vector2i(1600,900); await frames(10)
	await item_edges()
	for winner in [0,1]:
		screen.run.last_result = {"winner":winner,"wave":10+winner}
		screen._refresh(); await frames(3)
		check(portrait._reaction_left > 0 and portrait.face.albedo_texture == GameData.get_texture(portrait.face_texture+ ("a" if winner == 0 else "b")), "battle reaction starts immediately")
		await get_tree().create_timer(2.1).timeout
		check(portrait._reaction_left == 0 and portrait.face.albedo_texture == GameData.get_texture(portrait.face_texture), "battle reaction returns to neutral after a short pause")
		screen._refresh(); await frames(3)
		check(portrait._reaction_left == 0, "repeated battle result does not restart expression")
	for place in [1,3]:
		screen.run.placements[0] = place; screen._refresh(); await frames(3)
		check(portrait._reaction_left > 0, "match result starts a brief reaction")
		await get_tree().create_timer(2.1).timeout
		check(portrait._reaction_left == 0 and portrait.face.albedo_texture == GameData.get_texture(portrait.face_texture), "final match reaction also returns to neutral")
		screen._refresh(); await frames(3)
		check(portrait._reaction_left == 0, "finished match does not keep smiling or frowning")
	screen.run.placements[0] = 0; screen.run.last_result = {}; screen._refresh()
	portrait.celebrate_upgrade(); await get_tree().create_timer(2.1).timeout
	check(portrait._upgrade_left == 0 and portrait.face.albedo_texture == GameData.get_texture(portrait.face_texture), "upgrade smile returns to neutral")
	# Observe idle at ordinary real-time speed, allowing the longest initial wait.
	var first_pose := portrait.model._head.transform
	var greatest_angle := 0.0
	for i in 240:
		await get_tree().process_frame
		var angle := first_pose.basis.get_rotation_quaternion().angle_to(portrait.model._head.basis.get_rotation_quaternion())
		greatest_angle = maxf(greatest_angle,angle)
	check(greatest_angle > deg_to_rad(6) and greatest_angle < deg_to_rad(22), "idle occasionally looks around with restrained full-head motion")
	await shot("polish-"+RemakeText.lang+"-idle")
	screen.queue_free(); screen = null; await frames(8)
	check(errors.messages.is_empty(),"no runtime errors: "+JSON.stringify(errors.messages.slice(0,4)))
	print("ARENA_PORTRAIT_POLISH_UI ",RemakeText.lang," checks=",checks," failures=",JSON.stringify(failures))
	OS.remove_logger(errors); TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)

func inspect_company(target: Control, tag: String) -> void:
	await move(target.get_global_rect().get_center())
	await get_tree().create_timer(0.4).timeout
	await frames(10)
	check(screen._rail.visible and screen._company_details, tag+" hover opens company details")
	check(not screen._tooltips.visible,tag+" no duplicate tooltip covers the company panel")
	bounded(screen._rail,tag+" complete popup")
	var scroll := screen._inspect_scroll.get_v_scroll_bar()
	check(scroll.max_value <= scroll.page+1,tag+" full localized content is visible without scrolling (%s/%s)" % [scroll.max_value,scroll.page])
	check(not screen._rail.get_global_rect().intersects(screen._commander_portrait.get_global_rect()),tag+" popup clears the portrait")
	var last := screen._inspect_box.get_child(screen._inspect_box.get_child_count()-1) as Control
	check(screen._inspect_scroll.get_global_rect().grow(1).encloses(last.get_global_rect()),tag+" final help paragraph is fully visible")
	await shot("polish-"+RemakeText.lang+"-"+tag)
	screen._hide_inspector(); await move(Vector2(450,350)); await frames(4)

func item_edges() -> void:
	var layer := SubViewportContainer.new(); layer.position = Vector2(400,300); add_child(layer)
	var view := SubViewport.new(); view.size = Vector2i(40,40); view.transparent_bg = true; layer.add_child(view)
	var slot := ArenaItemSlot.new(); slot.kind = "vitality"; slot.selected = true
	view.add_child(slot); await frames(8)
	var pixels := view.get_texture().get_image()
	check(pixels.get_pixel(2,2).a < 0.05,"selected item has no white corner marker")
	var selected := pixels.get_pixel(20,5)
	check(selected.a > 0.5,"selection follows the circular rim")
	for kind in ["ward","storm","aegis","covenant"]:
		slot.kind = kind; await frames(3)
		pixels = view.get_texture().get_image()
		check(pixels.get_pixel(2,2).a < 0.05,"rarity never adds a corner: "+kind)
	layer.queue_free()
	screen._pick_item(1); await frames(4)
	await shot("polish-"+RemakeText.lang+"-item-selection")
	screen._cancel_item(); await frames(3)
