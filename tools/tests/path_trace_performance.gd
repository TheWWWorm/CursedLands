extends "res://tools/tests/scene_raytrace_performance.gd"
## Same frozen river and GPU/CPU brackets as the scene RT comparison.
func ready_snapshot(owner: Node) -> bool:
	# Async normal textures can invalidate a scene after its first active frame.
	# Measure only after the current material snapshot has stayed ready.
	var stable:=0
	for i in 1800:
		await frames(1)
		if owner._failed:return false
		if owner.stats.get("active",false) and owner._scene!=null and not owner._scene.topology_changed():stable+=1
		else:stable=0
		if stable>=30:return true
	return false

func run() -> void:
	var audit_pack:="";var only_case:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-shader-pack="):audit_pack=arg.trim_prefix("--audit-shader-pack=")
		if arg.begins_with("--pt-case="):only_case=arg.trim_prefix("--pt-case=")
	if not audit_pack.is_empty():
		check(ProjectSettings.load_resource_pack(audit_pack),"load explicitly requested diagnostic shader pack")
		if not failures.is_empty():get_tree().quit(1);return
	var context:=await setup();var game: Game=context[1]
	var detailed:=OS.get_cmdline_user_args().has("--pt-detail")
	if detailed:
		GameData.options.gfx_terrain=1;GameData.options.gfx_materials=1;GameData.options.gfx_foliage_light=1;GameData.options.gfx_terrain_cliffs=1
	GameData.options.gfx_water_reflections=0;t.apply_gfx()
	await get_tree().create_timer(0.3,true,false,true).timeout
	get_window().borderless=true;get_window().size=Vector2i(1280,720)
	await get_tree().create_timer(0.3,true,false,true).timeout
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	var rt: Node=game.get_node("SceneRaytrace")
	var before:=BeforeLighting.new();before.audit=self;before.process_priority=100;add_child(before)
	process_priority=102
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	# name, scene RT, path mode, quality. Responsive history in every case.
	var cases:=[["conventional",0,0,0],["scene-rt-medium",1,0,1],
		["path-2-low",0,1,0],["path-2-medium",0,1,1],["path-2-high",0,1,2],
		["path-4-low",0,2,0],["path-4-medium",0,2,1],["path-4-high",0,2,2]]
	if not only_case.is_empty():cases=cases.filter(func(row: Array):return row[0]==only_case)
	check(not cases.is_empty(),"benchmark selects at least one case")
	if cases.is_empty():get_tree().quit(1);return
	for round_index in 2:
		if round_index>0:cases.reverse()
		for choice: Array in cases:
			GameData.options.rt_shadows=choice[1];GameData.options.rt_gi=choice[1]
			GameData.options.pt_mode=choice[2];GameData.options.q_rt_lighting=choice[3]
			Gfx.apply_env(game._env)
			if choice[1]+choice[2]>0:
				var ready:=await ready_snapshot(rt)
				check(ready,"benchmark prepares "+str(choice[0]))
				if not ready:get_tree().quit(1);return
			await frames(40)
			gpu_samples.clear();cpu_samples.clear();sampling=true
			var wall:=[];var main_gpu:=[];var previous:=Time.get_ticks_usec()
			for i in 90:
				await frames(1);var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
				main_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			sampling=false
			var row:={"case":choice[0],"round":round_index,"frame_ms":summary(wall),"main_gpu_ms":summary(main_gpu),
				"rt_gpu_ms":summary(gpu_samples.duplicate()),"controller_cpu_ms":summary(cpu_samples.duplicate()),"stats":rt.stats.duplicate()}
			runs.append(row);print("PATH_TRACE_BENCH ",JSON.stringify(row))
			FileAccess.open(out.path_join("path-performance.json"),FileAccess.WRITE).store_string(JSON.stringify({"runs":runs,
				"device":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"viewport":[1280,720],
				"audit_shader_pack_sha256":FileAccess.get_sha256(audit_pack) if not audit_pack.is_empty() else "",
				"detailed_materials":detailed,"terrain_cliffs":GameData.option("gfx_terrain_cliffs")>0,"leaf_backlighting":GameData.option("gfx_foliage_light")>0,
				"note":"Frozen river, hidden units, water reflections and frame generation off, responsive history. Loading/builds excluded. RT GPU includes ray dispatch, reconstruction and copies; excludes AS updates. Main viewport GPU excludes RT dispatch."},"\t"))
	set_process(false);before.queue_free()
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(1 if not failures.is_empty() else 0)
