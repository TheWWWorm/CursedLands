extends Node
## Capture the composited opening, including the separate render thread used
## by desktop releases. A private viewport read alone can miss a stale frame.
var checks := 0
var failures := 0
var samples: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func draws(count: int) -> void:
	for i in count: await RenderingServer.frame_post_draw

func ink(img: Image) -> int:
	var count := 0
	# Only the central signpost; leave corner labels outside the measurement.
	for y in range(0, img.get_height(), 4):
		for x in range(img.get_width() / 4, img.get_width() * 3 / 4, 4):
			var c := img.get_pixel(x, y)
			if c.r > 0.12 and c.g > 0.08: count += 1
	return count

func opening(menu: EscSignpost, id: String, paused: bool, speed: float, fps: int) -> void:
	get_tree().paused = paused
	Engine.time_scale = speed
	Engine.max_fps = fps
	menu.show()
	await get_tree().create_timer(0.9, true, false, true).timeout
	menu._player.stop()
	menu._play("cidle")
	await draws(8)
	var rest := ink(get_viewport().get_texture().get_image())
	check(rest > 100, id + ": settled signpost is rendered")
	menu.hide()
	await draws(4)
	check(ink(get_viewport().get_texture().get_image()) == 0, id + ": closed menu leaves no signpost")
	# Exercise the boundary after scene transforms were submitted but before
	# drawing, as well as the ordinary process/input boundary. A one-signal
	# reveal cannot assume that the next completed draw contains the new pose.
	if id == "normal":
		RenderingServer.frame_pre_draw.connect(menu.show, CONNECT_ONE_SHOT)
		await RenderingServer.frame_pre_draw
	else:
		await get_tree().process_frame
		menu.show()
	var rows: Array = []
	var first := -1.0
	var peak := 0.0
	var flashed := false
	var start := Time.get_ticks_usec()
	var i := 0
	while Time.get_ticks_usec() - start < 1000000:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var ratio := float(ink(img)) / rest
		if first < 0.0 and ratio > 0.01: first = ratio
		if peak > 0.75 and ratio < 0.35: flashed = true
		peak = maxf(peak, ratio)
		rows.append({"frame":i, "seconds":(Time.get_ticks_usec()-start)/1000000.0, "ink":ratio})
		if i < 8: img.save_png("user://pause-%s-%02d.png" % [id, i])
		i += 1
	check(first >= 0.0 and first < 0.5, id + ": first visible frame starts below the screen")
	check(not flashed, id + ": no fully open frame flashes before the slide")
	check(peak > 0.9 and not (menu._player.is_playing() and menu._player.current_animation == "ei/uspecial02"), id + ": opening reaches its completed pose")
	samples.append({"case":id,"paused":paused,"speed":speed,"fps":fps,"frames":rows})
	menu.hide()
	await draws(4)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		printerr("Run with a rendering display"); get_tree().quit(2); return
	GameData.options.merge({"display_mode":0,"confine_mouse":0,"auto_graphics":0}, true)
	GameData.options.resolution = GameData.resolutions().find(Vector2i(800,600))
	GameData._apply_window()
	DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_VISIBLE)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var menu := EscSignpost.new()
	menu.hide()
	add_child(menu)
	check(menu._player != null, "original signpost animations load")
	if menu._player == null: get_tree().quit(1); return
	await opening(menu, "normal", false, 1.0, 60)
	await opening(menu, "paused", true, 1.0, 60)
	await opening(menu, "slow-frames", false, 55.0/27.0, 15)
	await opening(menu, "fast-paused", true, 55.0/27.0, 30)
	# Close before the first draw, reopen, and close during the slide. An old
	# pending reveal must not leave the hidden viewport rendering forever.
	menu.show(); menu.hide(); menu.show()
	await draws(2)
	menu.hide()
	await draws(4)
	check(ink(get_viewport().get_texture().get_image()) == 0, "interrupted opening stays hidden")
	check(menu._vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "closing cancels forced viewport rendering")
	await opening(menu, "reopened", true, 1.0, 60)
	get_tree().paused = false
	Engine.time_scale = 1.0
	Engine.max_fps = 0
	menu.free()
	FileAccess.open("user://pause-menu-frames.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples}, "  "))
	print("PAUSE_MENU_FRAMES ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
