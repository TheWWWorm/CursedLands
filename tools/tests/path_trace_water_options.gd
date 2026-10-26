extends "res://tools/tests/scene_raytrace_options.gd"
## Updated water help must explain the PT lighting dependency in every
## supported language, with native-resolution text through 4K.
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	GameData.options.merge({"gfx_water":1,"gfx_water_reflections":3,"pt_mode":1,"pt_accumulation":0,"fps_limit":1},true)
	Engine.max_fps=30
	var source: String=GameData.REMAKE_OPTIONS.gfx_water_reflections[1]
	check(source.contains("path tracing") and source.contains("emissive"),"water help describes PT lighting and emissive transport")
	for size: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440),Vector2i(3840,2160)]:
		get_window().borderless=true;get_window().size=size
		await get_tree().create_timer(0.3,true,false,true).timeout
		for language: String in ["en","ru","de"]:
			RemakeText.lang=language
			var panel:=OptionsPanel.new();add_child(panel);panel.open();panel._show_group(OptionsPanel.WATER_GROUP)
			var translated:=RemakeText.t(source)
			check(not translated.is_empty() and (language=="en" or translated!=source),"PT water help translated: "+language+str(size))
			get_window().grab_focus();GameData._tips.delay=0.1
			Input.warp_mouse(Vector2(20,20));await frames()
			var at:=panel.p8(Vector2(400,panel._row_y(1)+12))
			Input.warp_mouse(at);var motion:=InputEventMouseMotion.new();motion.position=at;Input.parse_input_event(motion)
			await get_tree().create_timer(0.4,true,false,true).timeout
			check(GameData._tips._panel.visible and GameData._tips._text.contains(translated),"complete PT water help visible: "+language+str(size))
			check(Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).encloses(Rect2(GameData._tips._panel.position,GameData._tips._panel.size)),"PT water help stays inside window: "+language+str(size))
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("water-help-%s-%dx%d.png"%[language,size.x,size.y]))
			GameData._tips._hide();panel._close();panel.queue_free();await frames()
	RemakeText.lang="en"
	FileAccess.open(out.path_join("pt-water-options.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	TexUpscale.shutdown();print("PT_WATER_OPTIONS ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
