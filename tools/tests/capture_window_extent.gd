extends Node
const Capture=preload("res://tools/tests/capture_window.gd")
var checks:=0
var failures:=0

func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func _ready() -> void:
	check(DisplayServer.get_name()!="headless","native rendered window is available")
	get_window().mode=Window.MODE_MAXIMIZED
	await get_tree().create_timer(.3,true,false,true).timeout
	for extent: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440),Vector2i(3840,2160),Vector2i(1280,720)]:
		# Leave a deferred normal-window fit in flight, as startup does.
		GameData._place_window(0,Vector2i(800,600),false)
		check(await Capture.resize(self,extent),"capture setup acknowledges "+str(extent))
		for i in 8:await RenderingServer.frame_post_draw
		check(get_window().mode==Window.MODE_WINDOWED,"capture remains windowed at "+str(extent))
		check(get_window().size==extent,"Window size remains exact at "+str(extent))
		check(DisplayServer.window_get_size()==extent,"native client size remains exact at "+str(extent))
		check(Vector2i(get_viewport().get_visible_rect().size)==extent,"viewport remains exact at "+str(extent))
	print("CAPTURE_WINDOW_EXTENT ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
