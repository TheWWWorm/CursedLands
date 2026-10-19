extends Node
## Rendered custom-tooltip regression in EN/RU/DE, including paused play and Off.
var checks := 0
var failures := 0

class Hover extends Control:
	func _get_tooltip(_at: Vector2) -> String:
		return RemakeText.t("Battle speed") + "\n" + RemakeText.t("The host controls battle speed for everyone.")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func frames(n := 8) -> void:
	for i in n: await get_tree().process_frame

func move(at: Vector2) -> void:
	Input.warp_mouse(at)
	var event := InputEventMouseMotion.new(); event.position = at
	Input.parse_input_event(event)
	await frames(2)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await frames(30)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,800)
	var hover := Hover.new(); hover.position = Vector2(100,100); hover.size = Vector2(500,400); add_child(hover)
	var tips := GameData._tips
	for lang in ["en", "ru", "de"]:
		RemakeText.lang = lang
		tips.delay = 0.5
		await move(Vector2(20,20)); await move(Vector2(200,200))
		check(not tips._panel.visible, lang + " tooltip waits for hover delay")
		await get_tree().create_timer(0.7,true,false,true).timeout
		check(tips._panel.visible and tips._text == hover.get_tooltip(), lang + " dynamic localized tooltip appears")
		check(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(Rect2(tips._panel.position,tips._panel.size)), lang + " tooltip fits viewport")
		check(hover.find_children("*","PopupPanel",true,false).is_empty(), lang + " has no duplicate native tooltip")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://tooltip-" + lang + ".png")
		tips.delay = 0.0; await frames()
		check(not tips._panel.visible, lang + " Off hides tooltip")
		await move(Vector2(230,200)); await get_tree().create_timer(0.7,true,false,true).timeout
		check(not tips._panel.visible and hover.find_children("*","PopupPanel",true,false).is_empty(), lang + " Off stays hidden")
		tips.delay = 0.5; get_tree().paused = true; Engine.time_scale = 0.0
		await move(Vector2(20,20)); await move(Vector2(260,200))
		await get_tree().create_timer(0.7,true,false,true).timeout
		check(tips._panel.visible, lang + " tooltip works with simulation paused")
		get_tree().paused = false; Engine.time_scale = 1.0
		hover.hide(); await frames()
		check(not tips._panel.visible, lang + " leaving the control clears tooltip")
		hover.show()
	hover.queue_free(); await frames()
	print("TOOLTIP_LIFETIME_UI ", checks, " checks ", failures, " failures")
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)
