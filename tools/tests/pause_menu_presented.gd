extends Node
# External X11 capture observes presented frames, without viewport readbacks.
func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds,true,false,true).timeout
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"auto_graphics":0,"display_mode":0,"confine_mouse":0},true)
	GameData.options.resolution=GameData.resolutions().find(Vector2i(800,600))
	GameData._apply_window()
	DisplayServer.window_set_position(Vector2i.ZERO)
	var bg := ColorRect.new(); bg.color=Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(bg)
	var menu := EscSignpost.new();menu.hide();add_child(menu)
	var marker := ColorRect.new();marker.position=Vector2(20,20);marker.size=Vector2(20,20);add_child(marker)
	marker.color=Color(0,0,1)
	await wait(1.0)
	for trial in 12:
		Engine.max_fps=[60,30,15][trial%3]
		Engine.time_scale=1.0 if trial%2==0 else 55.0/27.0
		get_tree().paused=trial%2==1
		marker.color=Color((trial+1)/16.0,1,0)
		if trial%3==1:
			RenderingServer.frame_pre_draw.connect(menu.show,CONNECT_ONE_SHOT)
		else:
			menu.show()
		await wait(1.4)
		menu.hide(); marker.color=Color((trial+1)/16.0,0,1)
		await wait(0.27+trial*.013)
	get_tree().paused=false
	get_tree().quit()
