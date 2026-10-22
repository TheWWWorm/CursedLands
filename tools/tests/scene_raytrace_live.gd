extends "res://tools/tests/water_raytrace_artifact.gd"
## Main campaign integration, not just isolated GPU buffers.
func ready_scene(rt: Node) -> bool:
	for i in 1200:
		if rt.stats.get("active",false) or rt._failed: break
		await frames(1)
	await frames(16)
	return rt.stats.get("active",false)

func mean_difference(a: Image,b: Image) -> float:
	var value := 0.0;var count := 0
	for y in range(150,mini(a.get_height(),b.get_height()),3):
		for x in range(0,mini(a.get_width(),b.get_width()),3):
			var p:=a.get_pixel(x,y);var q:=b.get_pixel(x,y)
			value+=absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b);count+=3
	return value/maxf(count,1)

func run() -> void:
	var context := await setup()
	var game: Game = context[1]
	GameData.options.gfx_water_reflections=0;t.apply_gfx()
	await get_tree().create_timer(0.2,true,false,true).timeout
	get_window().borderless=true;get_window().size=Vector2i(1280,720)
	await get_tree().create_timer(0.2,true,false,true).timeout
	var rt: Node = game.get_node("SceneRaytrace")
	# Let the FPS counter leave its loading interval before visual captures.
	await get_tree().create_timer(2.0,true,false,true).timeout
	var original := await capture("river-original")
	GameData.options.merge({"rt_shadows":1,"rt_gi":0,"q_rt_lighting":0},true)
	Gfx.apply_env(game._env)
	check(await ready_scene(rt),"main river prepares scene RT")
	print("SCENE_STATS ",rt.stats)
	if rt.stats.get("active",false):
		var device: Object=rt.device
		await get_tree().create_timer(2.0,true,false,true).timeout
		var shadowed := await capture("river-rt-shadows")
		check(mean_difference(original,shadowed)>0.005,"scene RT changes the actual lit world")
		rt.device.shadow0.get_image().save_png(out.path_join("river-shadow-buffer.png"))
		GameData.options.rt_gi=1;Gfx.apply_env(game._env)
		await get_tree().create_timer(2.0,true,false,true).timeout
		var gi := await capture("river-rt-gi")
		check(mean_difference(shadowed,gi)>0.002,"RTGI changes indirect illumination in the main view")
		rt.device.output.get_image().save_png(out.path_join("river-gi-buffer.png"))
		for quality in [1,2,0]:
			GameData.options.q_rt_lighting=quality;await frames(12)
			check(rt.device==device,"quality retains scene acceleration structures: "+str(quality))
			check(rt.stats.size==[[640,360],[960,540],[1280,720]][quality],"quality scales with the window: "+str(quality))
		# Menu text and pending options use the real rows and translation path.
		for language: String in ["en","ru","de"]:
			RemakeText.lang=language
			var panel:=OptionsPanel.new();add_child(panel);panel.open();panel._show_group(OptionsPanel.LIGHT_GROUP)
			check(panel._rows[11].to==OptionsPanel.SCENE_RT_GROUP,"lighting page links to RT controls: "+language)
			panel._show_group(OptionsPanel.SCENE_RT_GROUP)
			for row in 3:
				var option: Dictionary=panel._rows[row]
				check(not option.disabled and panel.text_width(option.label)<=260.0,"RT control available and label fits: "+language+" "+str(row))
				check(option.tip.contains(RemakeText.t(GameData.REMAKE_OPTIONS[option.name][1])),"localized RT help: "+language+" "+str(row))
			panel._sel=2;await frames(3);await shot("rt-options-"+language)
			panel._close();panel.queue_free();await frames(3)
		RemakeText.lang="en"
		GameData.options.rt_shadows=0;GameData.options.rt_gi=0;Gfx.apply_env(game._env)
		await frames(20)
		check(rt.device==null and not rt.stats.active,"switching off releases scene RT and restores conventional lighting")
		var restored := await capture("river-restored")
		check(mean_difference(original,restored)<0.005,"disabling scene RT restores the original world image")
	FileAccess.open(out.path_join("scene-live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"stats":rt.stats},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("SCENE_RT_LIVE ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
