extends Node
## Compare the same warmed menu before/after 100,000 hover events. Run without a debugger.
func frames(n := 8) -> void:
	for i in n: await get_tree().process_frame
func measure(label: String) -> void:
	await get_tree().create_timer(1.2,true,false,true).timeout
	var begun := Time.get_ticks_usec(); var prev := begun
	var wall := []; var physics := []
	while Time.get_ticks_usec()-begun < 4000000:
		await frames(1)
		var now := Time.get_ticks_usec()
		wall.append((now-prev)/1000.0); prev=now
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
	wall.sort();physics.sort()
	print("RETENTION ",JSON.stringify({"label":label,"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"frames":wall.size(),"fps":wall.size()*1000000.0/(prev-begun),"wall_p50_ms":wall[wall.size()/2],"wall_p95_ms":wall[int(wall.size()*0.95)],"physics_p50_ms":physics[physics.size()/2],"physics_p95_ms":physics[int(physics.size()*0.95)]}))
func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"autosave":0,"net_lan":0,"net_upnp":0,"net_directory":0},true)
	await frames(30)
	GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1280,800)
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var m=load("res://src/ui/main_menu.gd").new();m.detect_graphics=false;add_child(m)
	await frames(120)
	await measure("menu before hover")
	var hit:=Control.new();hit.position=Vector2(80,80);hit.size=Vector2(400,400);add_child(hit)
	for batch in 200:
		for i in 500:
			var motion:=InputEventMouseMotion.new();motion.position=Vector2(120+(i%2)*100,150);get_viewport().push_input(motion)
		await frames(1)
	hit.queue_free();await frames(30)
	await measure("same menu after 100000 hovers")
	m.queue_free();await frames();TexUpscale.shutdown();get_tree().quit()
