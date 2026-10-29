extends "res://tools/tests/path_trace_performance.gd"
## Emissive-geometry cost on the frozen river: hidden emissive boxes around the
## camera are revealed in groups, with and without ReSTIR, so the emitter
## next-event estimation at every path vertex and the reservoir pass can be
## compared against the lean no-emitter programs. Run with --ei-pt-tuning so
## the saved ReSTIR preference applies; use an exclusive GPU job.
func run() -> void:
	var context:=await setup();var session: Session=context[0];var game: Game=context[1]
	GameData.options.merge({"gfx_water_reflections":0,"gfx_terrain":1,"gfx_materials":1,"gfx_foliage_light":1,
		"gfx_terrain_cliffs":1,"pt_mode":1,"pt_accumulation":0,"q_rt_lighting":0,"pt_restir":0},true)
	t.apply_gfx();Gfx.apply_env(game._env)
	for n: Node in get_tree().get_nodes_in_group(Gfx.POINT_LIGHT_GROUP):n.hide()
	await get_tree().create_timer(0.3,true,false,true).timeout
	get_window().borderless=true;get_window().size=Vector2i(1280,720)
	await get_tree().create_timer(0.3,true,false,true).timeout
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	# Hidden emissive boxes join the snapshot now; revealing them later only
	# updates placements and the emitter table, like a lit torch would.
	var origin:=camera.global_position-camera.global_basis.z*6.0
	# The collector gathers placed objects by their own position, so the boxes
	# hang under the placed object nearest the camera.
	var host: Node3D=null
	for node in session.world.objects.values():
		if node is Node3D and node.is_inside_tree() and (host==null or node.global_position.distance_to(origin)<host.global_position.distance_to(origin)):host=node
	var glows: Array[MeshInstance3D]=[]
	for i in 32:
		var glow:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(0.25,0.25,0.25);glow.mesh=box
		var material:=StandardMaterial3D.new();material.emission_enabled=true
		material.emission=Color(1,0.45+0.1*(i%3),0.15+0.05*(i%5));material.emission_energy_multiplier=6
		glow.material_override=material;host.add_child(glow)
		glow.global_position=origin+Vector3(cos(i*0.4)*3.0,0.8+0.1*(i%4),sin(i*0.4)*3.0);glow.hide()
		glows.append(glow)
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_snapshot(rt),"emitter benchmark prepares the original river")
	if not rt.stats.get("active",false):get_tree().quit(1);return
	var before:=BeforeLighting.new();before.audit=self;before.process_priority=100;add_child(before);process_priority=102
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	for round_index in 2:
		var cases: Array=[[0,0],[8,0],[32,0],[8,1],[32,1]]
		if round_index>0:cases.reverse()
		for choice: Array in cases:
			for i in 32:glows[i].visible=i<choice[0]
			GameData.options.pt_restir=choice[1]
			var settled:=false
			for i in 600:
				await frames(1)
				if rt.stats.get("rebuilding",true):continue
				if int(rt.stats.get("emissive_triangles",-1))!=choice[0]*12:continue
				if rt.device!=null and bool(rt.device.get("_rtxdi_mode"))==(choice[1]==1 and choice[0]>0):settled=true;break
			check(settled,"%d emissive boxes with ReSTIR %d reach the traced scene"%[choice[0],choice[1]])
			await frames(40)
			phase_source=rt;gpu_samples.clear();gpu_stage_samples.clear();cpu_samples.clear();phase_samples.clear();sampling=true
			var wall:=[];var previous:=Time.get_ticks_usec()
			for i in 90:
				await frames(1);var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
			sampling=false
			runs.append({"emitters":choice[0],"triangles":rt.stats.get("emissive_triangles",0),"restir":choice[1],"round":round_index,
				"frame_ms":summary(wall),"rt_gpu_ms":summary(gpu_samples.duplicate()),"gpu_stages_ms":stage_summary(),
				"controller_cpu_ms":summary(cpu_samples.duplicate()),"controller_phases_ms":phase_summary(),"stats":rt.stats.duplicate()})
			print("EMITTER_BENCH ",JSON.stringify(runs.back()))
	FileAccess.open(out.path_join("path-emitter-performance.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"runs":runs,
		"device":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),
		"note":"Original river, PT two bounces and Low at 1280x720 with --ei-pt-tuning; 0, 8 and 32 emissive boxes (12 triangles each) around the camera, exact estimator and ReSTIR. Uncapped heavy job; initialization and shader compilation excluded."},"\t"))
	set_process(false);before.queue_free();game.queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("EMITTER_BENCH ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
