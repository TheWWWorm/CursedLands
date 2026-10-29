extends "res://tools/tests/scene_raytrace_options.gd"
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(GameData.option("pt_refraction")==0,"new profiles leave refraction off")
	check(GameData.REMAKE_OPTIONS.pt_refraction[1].contains("absorption"),"refraction help explains absorption")
	GameData.options.merge({"pt_mode":1,"pt_accumulation":0,"fps_limit":1},true);Engine.max_fps=30
	for language: String in ["en","ru","de"]:
		RemakeText.lang=language
		for key: String in ["PT refraction",GameData.REMAKE_OPTIONS.pt_refraction[1]]:
			check(not RemakeText.t(key).is_empty() and (language=="en" or RemakeText.t(key)!=key),"refraction label/help/status translated: "+language+key.left(24))
	for size: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440),Vector2i(3840,2160)]:
		await preload("res://tools/tests/capture_window.gd").resize(self,size)
		for language: String in ["en","ru","de"]:
			RemakeText.lang=language
			check(get_window().size==size and Vector2i(get_viewport().get_visible_rect().size)==size,"actual refraction UI extent: "+language+str(size))
			var panel:=OptionsPanel.new();add_child(panel);panel.open();panel._show_group(OptionsPanel.SCENE_RT_GROUP)
			check(panel._rows[10].name=="pt_refraction" and panel._rows[10].choices==RemakeText.tl(["Off","On"]),"refraction choice visible and localized: "+language+str(size))
			check(not panel._rows[10].get("disabled",false),"refraction availability follows native runtime: "+language+str(size))
			get_window().grab_focus();GameData._tips.delay=.1
			Input.warp_mouse(Vector2(20,20));await frames()
			var at:=panel.p8(Vector2(400,panel._row_y(10)+12))
			Input.warp_mouse(at);var motion:=InputEventMouseMotion.new();motion.position=at;Input.parse_input_event(motion)
			await get_tree().create_timer(.4,true,false,true).timeout
			check(GameData._tips._panel.visible and GameData._tips._text.contains(RemakeText.t(GameData.REMAKE_OPTIONS.pt_refraction[1])),"complete refraction help visible: "+language+str(size))
			check(Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).encloses(Rect2(GameData._tips._panel.position,GameData._tips._panel.size)),"refraction help fits window: "+language+str(size))
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("transmission-help-%s-%dx%d.png"%[language,size.x,size.y]))
			GameData._tips._hide();panel._close();panel.queue_free();await frames()
	RemakeText.lang="en"
	var panel:=OptionsPanel.new();add_child(panel);panel.open()
	panel._values.pt_mode=0;panel._show_group(OptionsPanel.SCENE_RT_GROUP)
	check(panel._rows[10].disabled,"refraction is unavailable without path tracing")
	panel._values.pt_mode=1;panel._values.pt_accumulation=1;panel._show_group(OptionsPanel.SCENE_RT_GROUP)
	check(not panel._rows[10].disabled,"Still accumulation retains the refraction option")
	panel._values.pt_accumulation=0;panel._show_group(OptionsPanel.SCENE_RT_GROUP)
	check(not panel._rows[10].disabled,"Responsive accumulation restores the refraction option")
	panel._close();panel.queue_free();await frames()
	FileAccess.open(out.path_join("transmission-options.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	TexUpscale.shutdown();print("PT_TRANSMISSION_OPTIONS ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
