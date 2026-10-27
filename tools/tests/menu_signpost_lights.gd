extends Node
## The original main menu lights its signpost with two placed white map
## lights (ZoneMainMenuNew.mob), so the boards stay readable at night.
## Compare the displayed signpost with and without those lights.
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", message)

func frames(count := 8) -> void:
	for i in count: await get_tree().process_frame

func capture() -> Image:
	await frames(6)
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func luminance(image: Image, rect: Rect2i) -> float:
	var total := 0.0
	var n := 0
	for y in range(rect.position.y, rect.end.y, 2):
		for x in range(rect.position.x, rect.end.x, 2):
			total += image.get_pixel(x, y).get_luminance()
			n += 1
	return total / maxf(n, 1.0)

func _ready() -> void:
	GameData.options.merge({"auto_graphics": 0, "display_mode": 0, "gfx_weather_surfaces": 0}, true)
	get_window().size = Vector2i(1280, 720)
	var scene := MenuScene.create()
	check(scene != null, "the menu scene builds")
	if scene == null: return finish()
	scene.rain_bit = false
	add_child(scene)
	scene.camera.make_current()
	scene.set_process(false)   # hold the clock at the chosen hour
	var fx: ParticleFx = scene._fx
	check(fx.map_lights.size() == 6, "the menu has its six map lights")
	var post: Node3D = scene._column
	var top := scene.camera.unproject_position(post.global_position + Vector3(0, 6.5, 0))
	var bottom := scene.camera.unproject_position(post.global_position + Vector3(0, 1.0, 0))
	var size := get_viewport().get_visible_rect().size
	var x := scene.pole_center_x()
	var area := Rect2(x - size.x * 0.07, minf(top.y, bottom.y), size.x * 0.14, absf(bottom.y - top.y))
	var rect := Rect2i()
	for hour: float in [23.5, 2.0, 12.0]:
		scene.set_hour(hour)
		var lit := await capture()
		if rect == Rect2i():
			# Captures use the window's pixels; the projection uses the
			# (possibly scaled) content viewport.
			var k := Vector2(lit.get_size()) / size
			rect = Rect2i(Rect2(area.position * k, area.size * k)).intersection(Rect2i(Vector2i.ZERO, lit.get_size()))
			check(rect.get_area() > 2000 and absi(rect.get_center().x - roundi(x * k.x)) <= 2, "the signpost covers a measurable area " + str(rect))
		for d: Dictionary in fx.map_lights: d.light.visible = false
		scene.set_hour(hour)
		var dark := await capture()
		for d: Dictionary in fx.map_lights: d.light.visible = true
		var a := luminance(lit, rect)
		var b := luminance(dark, rect)
		print("MENU_SIGNPOST_LIGHTS hour=", hour, " lit=", a, " unlit=", b, " rect=", rect)
		var label := "%02d" % int(hour)
		check(lit.save_png("user://menu-%s-lit.png" % label) == OK and dark.save_png("user://menu-%s-unlit.png" % label) == OK, "captures at " + label)
		if hour < 6.0 or hour > 21.0:
			check(a > b * 1.3 and a - b > 0.03, "map lights brighten the signpost at night (%s): %.3f vs %.3f" % [label, a, b])
		else:
			# Original max() response: daylight is never darkened by them.
			check(a >= b - 0.005, "daylight signpost is unchanged or brighter (%s)" % label)
	scene.free()
	finish()

func finish() -> void:
	print("MENU_SIGNPOST_LIGHTS ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
