extends "res://tools/tests/scene_raytrace_live.gd"
## Fixed campaign views for outdoor surface shape and leaf backlighting.
## The same fixture runs against the previous exported package for comparison.
func run() -> void:
	var context:=await setup();var session: Session=context[0];var game: Game=context[1]
	GameData.options.merge({"gfx_water_reflections":0,"gfx_terrain":1,"gfx_materials":1,"gfx_foliage_light":1,
		"pt_mode":2,"pt_accumulation":1,"q_rt_lighting":1},true)
	t.apply_gfx();Gfx.apply_env(game._env)
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_scene(rt),"outdoor detail prepares")
	var initial:=camera.global_transform
	for view in ["river-noon","grove-noon","grove-evening","grove-night"]:
		if view=="grove-noon":
			var tree: Node3D=session.world.objects[4442]
			var point: Vector3=tree.global_position+Vector3(5,0,8)
			point.y=t.height_at(point.x,-point.z)+1.7
			camera.global_position=point;camera.look_at(tree.global_position+Vector3.UP*4.5)
		var hour:=18.0 if view=="grove-evening" else 0.0 if view=="grove-night" else 12.0
		session.state.world_time=hour;game._update_daylight(false)
		check(await ready_scene(rt),"outdoor view prepares: "+view)
		await frames(110);await shot(view)
		rows.append({"view":view,"camera":str(camera.global_transform),"history":rt.stats.accumulation_frames,
			"triangles":rt.stats.triangles,"texture_layers":rt._scene.images.size()})
		check(rt.stats.accumulation_frames>=90,"stable outdoor history: "+view)
	if rt._scene.geometries[0].has("foliage_layer"):
		var foliage:=0
		for geometry: Dictionary in rt._scene.geometries:
			if geometry.foliage_layer>=0 and geometry.leaf_light:foliage+=1
		check(foliage>0,"authored foliage masks reach the real campaign scene")
		rows.append({"foliage_geometries":foliage})
		var previous: Object=rt._scene
		GameData.options.gfx_foliage_light=0;t.apply_gfx()
		for i in 240:
			await frames(1)
			if rt._scene!=previous:break
		check(rt._scene!=previous and await ready_scene(rt),"leaf-only option change rebuilds its transport")
		var cleared:=true
		for geometry: Dictionary in rt._scene.geometries:
			if geometry.foliage_layer>=0 and geometry.leaf_light:cleared=false
		check(cleared,"turning leaf backlighting off removes transmission")
	camera.global_transform=initial;session.state.world_time=12.0;game._update_daylight(false)
	GameData.options.pt_mode=0;Gfx.apply_env(game._env);await frames(20)
	check(rt.device==null,"conventional lighting restores after the outdoor pass")
	FileAccess.open(out.path_join("path-outdoor.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"views":rows},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("PATH_OUTDOOR ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
