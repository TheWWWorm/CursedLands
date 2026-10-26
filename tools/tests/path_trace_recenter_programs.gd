extends "path_trace_performance.gd"
## Live travel changes scene buffers, never the immutable reconstruction and
## SHaRC programs. Recreating them on DX12 can invoke costly driver compilation.
func handles(rt: Node) -> Array:
	var d: RefCounted=rt.device
	return [d._filter_shader,d._filter_pipeline,d._direct_composite_shader,d._direct_composite_pipeline,
		d.sharc._resolve_shader,d.sharc._resolve_pipeline]
func run() -> void:
	var context:=await setup();var game:Game=context[1]
	GameData.options.merge({"gfx_water_reflections":0,"pt_mode":1,"pt_sharc":1,"q_rt_lighting":0,"pt_accumulation":0},true)
	t.apply_gfx();Gfx.apply_env(game._env)
	get_window().borderless=true;get_window().size=Vector2i(1280,720);Engine.max_fps=30
	var rt:Node=game.get_node("SceneRaytrace")
	check(await ready_snapshot(rt),"initial scene prepares actual PT")
	check(rt.device!=null and rt.device.nrd_active and rt.device.sharc.active,"NRD and SHaRC both execute")
	if rt.device==null:get_tree().quit(1);return
	var programs:=handles(rt)
	check(programs.all(func(r:RID):return r.is_valid()),"all reconstruction/cache program handles are live")
	var prior:RefCounted=rt.device
	var times:=[];camera.global_position+=Vector3(18,0,0)
	for i in 1600:
		var start:=Time.get_ticks_usec();await frames(1);times.append((Time.get_ticks_usec()-start)/1000.0)
		if rt.device!=prior and not rt.stats.get("rebuilding",true):break
	check(rt.device!=prior and rt.stats.get("active",false),"travel publishes a real replacement scene")
	var after:=handles(rt)
	for i in programs.size():check(programs[i]==after[i],"travel reuses immutable program %d"%i)
	check(rt.device.nrd_active and rt.device.sharc.active,"replacement retains live NRD and SHaRC")
	check(rt._preparation_owner.is_empty(),"ordinary travel never opens a loading screen")
	FileAccess.open(out.path_join("recenter-programs.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"max_frame_ms":times.max(),"frame_ms":times,"build_timings":rt.device.build_timings,"stats":rt.stats},"\t"))
	print("RECENTER_FRAME_MAX ",times.max())
	game.queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("PATH_RECENTER_PROGRAMS ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
