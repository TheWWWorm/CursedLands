extends Node
## The real camera/terrain pick must produce a command accepted by teleport.
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func _ready():
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_lan":0,"net_upnp":0,"net_directory":0},true)
	if DisplayServer.get_name()!="headless":
		for i in 6:await get_tree().process_frame
		get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1024,768)
	var s:=Session.new();add_child(s)
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz3g",1,false)
	if DisplayServer.get_name()!="headless":
		while ShaderCompilationScreen.active():await get_tree().process_frame
		get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1024,768)
		for i in 12:await RenderingServer.frame_post_draw
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false)
	g.rig.set_process(false)
	var hero:GameUnit=s.party_units(0)[0]
	var terrain_point:=Vector3(hero.pos.x,s.world.ground_at(hero.pos.x,hero.pos.y),-hero.pos.y)
	g.rig.camera.global_position=terrain_point+Vector3(0,30,15)
	g.rig.camera.look_at(terrain_point)
	var point:=g.rig.camera.unproject_position(terrain_point)
	var expected:Vector2=g.pick_ground(point)
	check(expected.distance_to(hero.pos)<0.02,"real camera pick returns the hero's map coordinates")
	check(expected.distance_to(point)>1.0,"fixture distinguishes screen pixels from map coordinates")
	for language:String in ["en","ru","de"]:
		RemakeText.lang=language
		# Re-project each sample: presentation can resize the viewport between
		# captures, while the cursor command must always use its current camera.
		point=g.rig.camera.unproject_position(terrain_point)
		expected=g.pick_ground(point)
		var text:String=DeveloperConsole._cursor_text(point)
		var command:=text.get_slice("|",1).strip_edges()
		var words:=ConsoleTools.words(command)
		check(words.size()==3 and words[0]=="teleport",language+": sample includes an executable teleport command")
		if words.size()!=3:continue
		var xy:=Vector2(float(words[1]),float(words[2]))
		check(xy.distance_to(expected)<0.002,language+": command uses terrain map x/y")
		var answer:=ConsoleCommands.execute(s,command)
		check(answer.size()==1 and answer[0]==ConsoleTools.describe(hero),language+": teleport accepts the copied command")
		check(hero.pos.distance_to(expected)<0.02,language+": teleport lands at the sampled ground")
		check(language=="en" or not text.begins_with("Cursor at"),language+": map status is localized")
		var authority:=s.is_host;s.is_host=false
		check(DeveloperConsole._cursor_text(point).contains(command),language+": client can inspect the same coordinates")
		s.is_host=authority
		if DisplayServer.get_name()!="headless":
			DeveloperConsole.lines.clear();DeveloperConsole.visible=true
			DeveloperConsole._refresh_labels();DeveloperConsole.run("console f")
			DeveloperConsole.run("help cursor");DeveloperConsole.append(text)
			DeveloperConsole._set_input(command)
			for i in 3:await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://console-map-"+language+".png")
	var text:String=DeveloperConsole._cursor_text(Vector2(-10,-10))
	check(not text.contains("teleport "),"outside-viewport sample does not invent a teleport target")
	s.loading_game=true
	check(not DeveloperConsole._cursor_text(point).contains("teleport "),"loading never exposes the outgoing world's coordinates")
	s.loading_game=false
	RemakeText.lang="en"
	DeveloperConsole._close()
	g.queue_free();s.queue_free()
	for i in 6:await get_tree().process_frame
	check(DeveloperConsole._cursor_text(point).ends_with("No map ground under cursor."),"closed campaign falls back to clearly labelled screen pixels")
	TexUpscale.shutdown()
	print("CONSOLE_CURSOR_MAP ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
