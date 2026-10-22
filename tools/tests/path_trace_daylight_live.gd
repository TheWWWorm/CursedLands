extends "res://tools/tests/scene_raytrace_live.gd"
## Matched real-world views across lighting palettes and material settings.
## Runs against both the old package and the updated one.
func run() -> void:
	var context := await setup();var session: Session=context[0];var game: Game=context[1]
	GameData.options.merge({"gfx_water_reflections":0,"rt_shadows":0,"rt_gi":0,
		"pt_mode":2,"pt_accumulation":1,"q_rt_lighting":1},true)
	t.apply_gfx();Gfx.apply_env(game._env)
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_scene(rt),"outdoor path lighting prepares")
	if rt.stats.get("active",false):
		for hour in [12.0,18.0,0.0]:
			session.state.world_time=hour;game._update_daylight(false);await frames(2)
			if hour!=12.0:check(rt.stats.accumulation_frames<=4,"time change resets still-scene history: "+str(hour))
			await frames(100)
			var name: String={12.0:"noon",18.0:"evening",0.0:"night"}[hour]
			await shot(name+"-path")
			var data: PackedByteArray=rt._frame(camera,Vector2i(960,540),1)
			rows.append({"time":hour,"sun":str(Gfx.sun),"ambient":str(Gfx.ambient),"sky":str(Gfx.fog_sky),
				"frame_bytes":data.size(),"accumulation":rt.stats.accumulation_frames})
			check(rt.stats.accumulation_frames>=90,"lighting accumulates at "+name)
			t.set_process(false)
		# A visible-sky palette change with unchanged direct/ambient lights
		# must invalidate the new directional environment's temporal history.
		if rt.device.frame_bytes()>656:
			var saved:=Gfx.fog_sky;Gfx.fog_sky=Color(0.8,0.2,0.1)
			session.state.world_time=12.0;game._update_daylight(false);await frames(20)
			Gfx.fog_sky=Color(0.8,0.2,0.1);await frames(2)
			check(rt.stats.accumulation_frames<=3,"sky-only colour change resets history")
			Gfx.fog_sky=saved
		session.state.world_time=12.0;game._update_daylight(false)
		GameData.options.gfx_terrain=1;GameData.options.gfx_materials=1
		t.apply_gfx();Gfx.apply_env(game._env);await frames(90)
		check(await ready_scene(rt),"enhanced terrain and materials keep PT active")
		await frames(100);await shot("noon-materials-path")
		if rt.device.frame_bytes()>656:
			var detailed:=0
			for geometry: Dictionary in rt._scene.geometries:
				if geometry.get("relief",0.0)>0.0:detailed+=1
			check(detailed>0,"authored surface relief reaches the traced scene")
			rows.append({"detailed_geometries":detailed})
			var previous_scene: Object=rt._scene
			GameData.options.gfx_terrain=0;t.apply_gfx()
			for i in 240:
				await frames(1)
				if rt._scene!=previous_scene:break
			check(rt._scene!=previous_scene and await ready_scene(rt),"terrain-only detail change refreshes the snapshot")
			var cleared:=true
			for entry: Dictionary in rt._scene.instances:
				if entry.terrain and rt._scene.geometries[entry.geometry].relief>0.0:cleared=false
			check(cleared,"turning terrain detail off removes its traced relief")
		GameData.options.pt_mode=0;Gfx.apply_env(game._env);await frames(20)
		check(rt.device==null,"disabling PT restores conventional materials")
		await shot("noon-materials-conventional")
	FileAccess.open(out.path_join("path-daylight-live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("PATH_DAYLIGHT_LIVE ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
