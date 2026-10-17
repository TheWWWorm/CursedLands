extends Node
## Real signpost clips timed against wall time, including paused gameplay.
var checks := 0
var failures := 0
var samples: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func clip(menu: EscSignpost, name: String, scale: float, paused: bool) -> void:
	Engine.time_scale = scale
	get_tree().paused = paused
	menu._player.stop()
	var started := Time.get_ticks_usec()
	menu._play(name)
	var duration := menu._player.get_animation("ei/" + name).length
	while menu._player.is_playing() and Time.get_ticks_usec() - started < (duration * 2.5 + 0.25) * 1000000:
		await get_tree().process_frame
	var elapsed := (Time.get_ticks_usec() - started) / 1000000.0
	check(not menu._player.is_playing() and absf(elapsed - duration) < 0.10,
		"%s takes %.3f real seconds at scale %.3f, paused=%s (%.3f measured)" % [name, duration, scale, paused, elapsed])
	samples.append({"clip":name, "scale":scale, "paused":paused, "duration":duration, "elapsed":elapsed})

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var menu := EscSignpost.new()
	add_child(menu)
	check(menu._player != null, "original signpost and animation library load")
	if menu._player == null:
		get_tree().quit(1)
		return
	# Let original textures/materials reach the renderer before timing clips.
	for i in 12: await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		menu._play("cidle")
		for i in 3: await RenderingServer.frame_post_draw
		var rest := opaque_pixels(menu._vp.get_texture().get_image())
		menu.hide(); menu.show()
		check(menu.self_modulate.a == 0.0, "stale rest texture is hidden on opening")
		await RenderingServer.frame_post_draw
		var opening := opaque_pixels(menu._vp.get_texture().get_image())
		check(rest > 0 and opening < rest / 2, "first refreshed frame is the hidden opening pose, not the fully open signpost")
		menu._vp.get_texture().get_image().save_png("user://pause-opening-pose.png")
		var motion := InputEventMouseMotion.new(); motion.position = menu.size * 0.5
		menu._gui_input(motion)
		check(menu._player.current_animation == "ei/uspecial02", "mouse movement cannot replace the opening slide with idle")
	for scale in [0.5, 1.0, 55.0 / 27.0]:
		for paused in [false, true]:
			await clip(menu, "uspecial02", scale, paused)
			await clip(menu, "uspecial03", scale, paused)
	# A speed change during a clip must not change its real-time rate either.
	Engine.time_scale = 1.0
	menu._player.stop()
	menu._play("uspecial02")
	await get_tree().create_timer(0.10, true, false, true).timeout
	Engine.time_scale = 55.0 / 27.0
	var before := menu._player.current_animation_position
	var started := Time.get_ticks_usec()
	await get_tree().create_timer(0.10, true, false, true).timeout
	var elapsed := (Time.get_ticks_usec() - started) / 1000000.0
	check(absf(menu._player.current_animation_position - before - elapsed) < 0.035,
		"changing speed during opening preserves the animation clock")
	for scale in [1.0, 55.0 / 27.0]:
		Engine.time_scale = scale
		menu._player.stop(); menu._play("uspecial02"); menu._player.advance(0.2)
		menu.hide()
		await get_tree().create_timer(0.15, true, false, true).timeout
		menu.show()
		check(is_zero_approx(menu._player.current_animation_position),
			"reopening a partially hidden slide restarts from frame zero at scale %.3f" % scale)
		started = Time.get_ticks_usec()
		while menu._player.is_playing() and Time.get_ticks_usec() - started < 1000000:
			await get_tree().process_frame
		elapsed = (Time.get_ticks_usec() - started) / 1000000.0
		check(absf(elapsed - menu._player.get_animation("ei/uspecial02").length) < 0.10,
			"reopened menu plays its full duration at scale %.3f" % scale)
	Engine.time_scale = 1.0
	get_tree().paused = false
	menu.free()
	FileAccess.open("user://pause-menu-clock.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples}, "  "))
	print("PAUSE_MENU_CLOCK ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)

func opaque_pixels(img: Image) -> int:
	var count := 0
	for y in range(0,img.get_height(),4):
		for x in range(0,img.get_width(),4):
			if img.get_pixel(x,y).a > 0.1: count += 1
	return count
