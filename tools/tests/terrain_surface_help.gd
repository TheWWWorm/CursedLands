extends "res://tools/tests/scene_raytrace_options.gd"
## Surface materials help now describes ground relief and sand ripples; it
## must stay translated and readable in its actual row through 4K.
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	GameData.options.merge({"gfx_materials":1,"fps_limit":1},true)
	Engine.max_fps=30
	var source: String=GameData.REMAKE_OPTIONS.gfx_materials[1]
	check(source.contains("loose sand") and source.contains("original textures"),"help describes sand relief derived from the original textures")
	for size: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440),Vector2i(3840,2160)]:
		get_window().borderless=true;get_window().size=size
		await get_tree().create_timer(0.3,true,false,true).timeout
		for language: String in ["en","ru","de"]:
			RemakeText.lang=language
			var panel:=OptionsPanel.new();add_child(panel);panel.open();panel._show_group(OptionsPanel.WORLD_GROUP)
			var rows: Array=panel._rows.keys().filter(func(r:int)->bool:return panel._rows[r].get("name","")=="gfx_materials")
			check(rows.size()==1,"Surface materials is reachable from World and textures: "+language+str(size))
			if rows.is_empty():panel.queue_free();continue
			var translated:=RemakeText.t(source)
			check(not translated.is_empty() and (language=="en" or translated!=source),"Surface materials help translated: "+language+str(size))
			get_window().grab_focus();GameData._tips.delay=0.1
			Input.warp_mouse(Vector2(20,20));await frames()
			var at:=panel.p8(Vector2(400,panel._row_y(rows[0])+12))
			Input.warp_mouse(at);var motion:=InputEventMouseMotion.new();motion.position=at;Input.parse_input_event(motion)
			await get_tree().create_timer(0.4,true,false,true).timeout
			check(GameData._tips._panel.visible and GameData._tips._text.contains(translated),"complete Surface materials help visible: "+language+str(size))
			check(Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).encloses(Rect2(GameData._tips._panel.position,GameData._tips._panel.size)),
				"Surface materials help stays inside window: "+language+str(size))
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("materials-help-%s-%dx%d.png"%[language,size.x,size.y]))
			GameData._tips._hide();panel._close();panel.queue_free();await frames()
	RemakeText.lang="en"
	FileAccess.open(out.path_join("terrain-surface-help.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	TexUpscale.shutdown();print("TERRAIN_SURFACE_HELP ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
