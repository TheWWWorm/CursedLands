extends "res://tools/tests/path_trace_performance.gd"
## Bounded many-light and full-history-clear cost on the same original map.
## Use an exclusive GPU Lab heavy job; there are no image readbacks in samples.
class MovingLights extends Node:
	var lamps: Array[OmniLight3D]=[]
	var moving:=false
	var step:=0
	func _process(_dt: float) -> void:
		if moving:
			step+=1;lamps[0].position.x+=0.001 if step%2==0 else -0.001

func run() -> void:
	var context:=await setup();var game: Game=context[1]
	GameData.options.merge({"gfx_water_reflections":0,"gfx_terrain":1,"gfx_materials":1,"gfx_foliage_light":1,
		"gfx_terrain_cliffs":1,"pt_mode":1,"pt_accumulation":0,"q_rt_lighting":0},true)
	t.apply_gfx();Gfx.apply_env(game._env)
	for n: Node in get_tree().get_nodes_in_group(Gfx.POINT_LIGHT_GROUP):n.hide()
	var motion:=MovingLights.new();motion.process_priority=99;add_child(motion)
	var origin:=camera.global_position-camera.global_basis.z*6.0
	for i in 64:
		var lamp:=OmniLight3D.new();lamp.add_to_group(Gfx.POINT_LIGHT_GROUP);game.add_child(lamp)
		lamp.position=origin+Vector3(cos(i*0.4)*3.0,0.5,sin(i*0.4)*3.0)
		lamp.omni_range=12;lamp.light_energy=0.05;lamp.light_color=Color(1,0.5+(i%3)*0.1,0.2)
		motion.lamps.append(lamp)
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_snapshot(rt),"many-light benchmark prepares the original scene")
	if not rt.stats.get("active",false):get_tree().quit(1);return
	var before:=BeforeLighting.new();before.audit=self;before.process_priority=100;add_child(before);process_priority=102
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	for round_index in 2:
		var cases: Array=[[7,false],[16,false],[64,false],[64,true]]
		if round_index>0:cases.reverse()
		for choice: Array in cases:
			for i in 64:motion.lamps[i].visible=i<choice[0]
			motion.moving=choice[1];await frames(40)
			check(rt._lights.size()==choice[0],"benchmark retains %d lights"%choice[0])
			gpu_samples.clear();gpu_stage_samples.clear();cpu_samples.clear();sampling=true
			var wall:=[];var viewport_gpu:=[];var previous:=Time.get_ticks_usec();var resets:=0
			for i in 90:
				await frames(1);var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
				viewport_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
				resets+=int(not rt.stats.history_reused)
			sampling=false
			check(resets==90 if choice[1] else resets==0,"history rejection matches light motion")
			runs.append({"lights":choice[0],"moving":choice[1],"round":round_index,"history_resets":resets,
				"frame_ms":summary(wall),"rt_gpu_ms":summary(gpu_samples.duplicate()),"main_gpu_ms":summary(viewport_gpu),
				"controller_cpu_ms":summary(cpu_samples.duplicate()),"nrd":rt.device.nrd_active})
			print("MANY_LIGHT_BENCH ",JSON.stringify(runs.back()))
	FileAccess.open(out.path_join("path-light-performance.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"runs":runs,
		"device":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),
		"note":"Original river, probe lights, PT two bounces and Low at 1280x720. Uncapped heavy job; initialization and shader compilation excluded."},"\t"))
	set_process(false);before.queue_free();motion.queue_free();game.queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("MANY_LIGHT_BENCH ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
