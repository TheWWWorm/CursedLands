extends "arena_expansion_ui.gd"
## Real rendered snow: detect self-shadow bands without removing cast shadows.
const SNOW := Rect2i(380,380,100,80)
const TREE := Rect2i(140,300,160,200)
var measurements: Array[Dictionary] = []

func capture(label: String) -> Image:
	await frames(8)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://arena-shadow-" + label + ".png")
	return image

func luminance(image: Image, x: int, y: int) -> float:
	var c := image.get_pixel(x,y)
	return (c.r+c.g+c.b)/3.0

func curvature(image: Image) -> float:
	var total := 0.0
	for y in range(SNOW.position.y,SNOW.end.y):
		for x in range(SNOW.position.x,SNOW.end.x-2):
			total += absf(luminance(image,x,y)-2*luminance(image,x+1,y)+luminance(image,x+2,y))
	return total / float((SNOW.size.x-2)*SNOW.size.y)

func _ready() -> void:
	await frames(24)
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"show_fps":1,
		"volume_sfx":0,"volume_stream":0,"volume_voice":0,"vsync":0,"pad_enabled":0},true)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,720)
	RemakeText.lang = "en"
	GameData.arena_mode = 0
	screen = ArenaPveScreen.new(); add_child(screen); await frames(8)
	screen._seed_input.text = "7191"; screen._begin(); screen.run.auto_save = false
	screen.run.gold = 3; screen._refresh(); await frames(8)
	var sun := screen.field._sun_light
	for quality in [2,0,1,3]:
		GameData.options.q_shadows = quality
		screen.field._apply_presentation()
		sun.shadow_enabled = true; Gfx.sync_sun_pass(sun)
		var lit := await capture(str(quality)+"-shadows")
		check(sun.shadow_enabled, "quality %d keeps directional shadows enabled" % quality)
		sun.shadow_enabled = false; Gfx.sync_sun_pass(sun)
		var reference := await capture(str(quality)+"-reference")
		var excess := curvature(lit)-curvature(reference)
		check(excess < 0.002, "quality %d snow has no high-frequency self-shadow bands: %s" % [quality,excess])
		var shadow_pixels := 0
		for y in range(TREE.position.y,TREE.end.y):
			for x in range(TREE.position.x,TREE.end.x):
				if luminance(reference,x,y)-luminance(lit,x,y) > 0.03: shadow_pixels += 1
		check(shadow_pixels > 50, "quality %d retains visible tree shadows" % quality)
		measurements.append({"quality":quality,"normal_bias":sun.shadow_normal_bias,
			"excess_curvature":excess,"shadow_pixels":shadow_pixels})
	sun.shadow_enabled = true; Gfx.sync_sun_pass(sun)
	await capture("final")
	screen.queue_free(); screen = null; await frames(8)
	print("ARENA_SHADOW_SURFACE ",JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements}))
	TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)
