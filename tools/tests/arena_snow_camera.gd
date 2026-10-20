extends "arena_expansion_ui.gd"
## Render the starting army, the full zoom range and the tournament overview.
func _ready() -> void:
	OS.add_logger(errors)
	await frames(24)
	GameData._window_gen += 1
	GameData.arena_mode = 1
	var lang := "en"
	var dimensions := Vector2i(1280, 800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-resolution="):
			var parts := arg.get_slice("=", 1).split(",")
			lang = parts[0]; dimensions = Vector2i(int(parts[1]), int(parts[2]))
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = dimensions
	get_tree().root.position = Vector2i.ZERO
	RemakeText.lang = lang
	await frames(8)
	screen = ArenaPveScreen.new(); add_child(screen)
	await frames(12)
	screen._seed_input.text = "7191"; screen._begin(); screen.run.auto_save = false
	check(screen.run.capacity() == 3 and screen.run.experience() == 0 and screen.run.level_needed() == 6,
		"opening company has three deployment slots and needs six XP for level four")
	Fixture.buy_company(screen.run, 1)
	screen._refresh()
	await frames(24)
	screen.set_process(false)
	var tag := "snow-camera-%s-%d" % [lang, dimensions.x]
	await shot(tag + "-default")
	print("CAMERA_DEFAULT ", screen.field.camera.position, " size=", screen.field.camera.size, " yaw=", screen.field.yaw)
	var height := screen.field.camera.position.y
	var normals: PackedVector3Array = screen.field._snow_surround.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	# ArrayMesh packs normals; the decoded octahedral vector can have a tiny
	# horizontal component even when SurfaceTool receives Vector3.UP.
	check(normals.size()>0 and normals[0].distance_to(Vector3.UP)<0.001,"snow surround matches the native courtyard's upward normals: "+str(normals[0]))
	if dimensions == Vector2i(1280,800):
		check(absf(height-42.10144)<0.001, "default height exactly matches the published 1.18.0 camera")
	var safe := screen.field.battle_screen_rect().grow(1.0)
	for point_value in [Vector2(18.5,18.5), Vector2(18.5,45.5), Vector2(45.5,18.5), Vector2(45.5,45.5)]:
		for top in [0.0, 4.5]:
			check(safe.has_point(screen.field.camera.unproject_position(Vector3(point_value.x, top, -point_value.y))), "battlefield and tall figures fit between HUD panels")
		check(screen.field.ground_point(screen.field.screen_point(point_value)).distance_to(point_value) < 0.2,
			"diagonal view preserves ground picking")
	screen.field.zoom = 35; screen.field._update_camera()
	await shot(tag + "-wide")
	await RenderingServer.frame_post_draw
	var snow := screen.field.view.get_texture().get_image()
	var edge_colors: Array[Color] = []
	for x in [-1.0,1.0]:
		var pixel := screen.field.camera.unproject_position(Vector3(x,ArenaTerrain.snow_height(clampf(x,0,64),32),-32))
		edge_colors.append(snow.get_pixelv(Vector2i(pixel)))
	var delta:=absf(edge_colors[0].r-edge_colors[1].r)+absf(edge_colors[0].g-edge_colors[1].g)+absf(edge_colors[0].b-edge_colors[1].b)
	check(delta<0.18,"courtyard and surrounding snow share lighting across their edge: "+str(delta))
	screen.field._snow_surround.hide(); await frames(4); await RenderingServer.frame_post_draw
	var empty := screen.field.view.get_texture().get_image()
	var covered := 0
	for y in range(0,snow.get_height(),8):
		for x in range(0,snow.get_width(),8):
			var a := snow.get_pixel(x,y); var b := empty.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.03: covered += 1
	check(covered > snow.get_width()*snow.get_height()/512, "textured snow visibly replaces the empty background when zoomed out")
	screen.field._snow_surround.show()
	print("CAMERA_WIDE ", screen.field.camera.position, " size=", screen.field.camera.size)
	screen.field.yaw += PI * 0.65; screen.field.pitch_offset = deg_to_rad(-16)
	screen.field.pan_offset = Vector2(16, -16); screen.field._update_camera()
	await shot(tag + "-wide-rotated")
	screen.field.reset_camera()
	check(is_equal_approx(screen.field.camera.position.y, height), "Home restores the starting camera height")
	screen._show_boards()
	await shot(tag + "-overview")
	screen._show_player(0)
	check(is_equal_approx(screen.field.camera.position.y, height), "scouting restores the starting camera height")
	screen.queue_free(); screen = null; await frames(8)
	check(errors.messages.is_empty(), "no scene, script or shader errors: " + JSON.stringify(errors.messages.slice(0, 3)))
	print("ARENA_SNOW_CAMERA ", checks, " checks; failures=", JSON.stringify(failures))
	OS.remove_logger(errors)
	TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
