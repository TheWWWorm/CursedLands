extends "res://tools/tests/scene_raytrace_options.gd"
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(GameData.option("pt_ray_reconstruction")==0,"new profiles leave RR off")
	check(GameData.REMAKE_OPTIONS.pt_ray_reconstruction[1]==RtxGraphics.RR_HELP,"RR help describes required DLSS input resolution and fallback")
	GameData.options.merge({"pt_mode":1,"pt_accumulation":0,"fps_limit":1},true);Engine.max_fps=30
	for language: String in ["en","ru","de"]:
		RemakeText.lang=language
		for key: String in ["DLSS Ray Reconstruction",RtxGraphics.RR_HELP,RtxGraphics.NEED_RR,RtxGraphics.ENABLE_PT]:
			check(not RemakeText.t(key).is_empty() and (language=="en" or RemakeText.t(key)!=key or key=="DLSS Ray Reconstruction"),"RR label/help/status translated: "+language+key.left(24))
	for size: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440),Vector2i(3840,2160)]:
		get_window().borderless=true;get_window().size=size
		await get_tree().create_timer(.3,true,false,true).timeout
		for language: String in ["en","ru","de"]:
			RemakeText.lang=language
			var panel:=OptionsPanel.new();add_child(panel);panel.open();panel._show_group(OptionsPanel.SCENE_RT_GROUP)
			check(panel._rows[8].name=="pt_ray_reconstruction" and panel._rows[8].choices==RemakeText.tl(["Off","On"]),"RR choice visible and localized: "+language+str(size))
			check(panel._rows[8].get("disabled",false)==not RtxGraphics.reason(RtxGraphics.RAY_RECONSTRUCTION,panel._values).is_empty(),"RR availability follows native runtime: "+language+str(size))
			get_window().grab_focus();GameData._tips.delay=.1
			Input.warp_mouse(Vector2(20,20));await frames()
			var at:=panel.p8(Vector2(400,panel._row_y(8)+12))
			Input.warp_mouse(at);var motion:=InputEventMouseMotion.new();motion.position=at;Input.parse_input_event(motion)
			await get_tree().create_timer(.4,true,false,true).timeout
			check(GameData._tips._panel.visible and GameData._tips._text.contains(RemakeText.t(RtxGraphics.RR_HELP)),"complete RR help visible: "+language+str(size))
			check(Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).encloses(Rect2(GameData._tips._panel.position,GameData._tips._panel.size)),"RR help fits window: "+language+str(size))
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("rr-help-%s-%dx%d.png"%[language,size.x,size.y]))
			GameData._tips._hide();panel._close();panel.queue_free();await frames()
	RemakeText.lang="en"
	FileAccess.open(out.path_join("rr-options.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	TexUpscale.shutdown();print("PT_RR_OPTIONS ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
