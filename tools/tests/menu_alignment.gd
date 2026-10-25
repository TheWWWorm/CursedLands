extends Node
## Extra controls follow the actual projected pole in both original islands.
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",message)
func frames(count := 5) -> void:
	for i in count: await get_tree().process_frame
func _ready() -> void:
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	var menu := preload("res://src/ui/main_menu.gd").new()
	menu.detect_graphics = false
	add_child(menu)
	check(menu._scene != null,"real signpost available")
	if menu._scene == null: finish(); return
	menu._scene.set_process(false)
	var world: GameWorld = menu._scene.get("world")
	if world: world.set_physics_process(false)
	for dimensions: Vector2i in [Vector2i(800,600),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768),Vector2i(720,1280)]:
		get_window().size = dimensions
		if DisplayServer.get_name() == "headless": get_viewport().size = dimensions
		await frames()
		menu._layout_campaign_bar()
		await frames()
		var safe := Portability.safe_rect(menu.size)
		var pole := menu._scene.camera.unproject_position(menu._scene._column.global_position).x
		for bar: Control in [menu._campaign_bar,menu._utility_bar,menu._wiki_hint]:
			var rect := bar.get_global_rect()
			check(rect.position.x >= safe.position.x-1 and rect.end.x <= safe.end.x+1,"controls stay inside safe width at "+str(dimensions))
			var expected := clampf(pole,safe.position.x+rect.size.x*0.5,safe.end.x-rect.size.x*0.5)
			check(absf(rect.get_center().x-expected) <= 1.0,"extra controls centre on the projected pole at "+str(dimensions))
		for target: Dictionary in menu.campaign_pad_targets():
			check(target.rect.has_area(),"aligned buttons retain keyboard/controller targets")
	menu.free()
	finish()
func finish() -> void:
	print("MENU_ALIGNMENT ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
