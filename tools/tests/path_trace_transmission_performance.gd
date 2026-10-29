extends "res://tools/tests/path_trace_performance.gd"
## Refraction pass cost on the frozen river: off, on with a still view, and on
## while the camera turns slightly every frame so the transparent history
## resets and every pixel is traced again. Run with --ei-pt-tuning so the saved
## refraction preference applies in Balanced mode; use an exclusive GPU job.
class Turning extends Node:
	var camera: Camera3D
	var active:=false
	var step:=0
	func _process(_dt: float) -> void:
		if active:
			step+=1;camera.rotate_y(0.0004 if step%2==0 else -0.0004)

func run() -> void:
	var context:=await setup();var game: Game=context[1]
	GameData.options.merge({"gfx_water_reflections":0,"gfx_terrain":1,"gfx_materials":1,"gfx_foliage_light":1,
		"gfx_terrain_cliffs":1,"pt_mode":1,"pt_accumulation":0,"q_rt_lighting":0,"pt_refraction":0},true)
	t.apply_gfx();Gfx.apply_env(game._env)
	await get_tree().create_timer(0.3,true,false,true).timeout
	get_window().borderless=true;get_window().size=Vector2i(1280,720)
	await get_tree().create_timer(0.3,true,false,true).timeout
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_snapshot(rt),"refraction benchmark prepares the original river")
	if not rt.stats.get("active",false):get_tree().quit(1);return
	var turning:=Turning.new();turning.camera=camera;turning.process_priority=99;add_child(turning)
	var before:=BeforeLighting.new();before.audit=self;before.process_priority=100;add_child(before);process_priority=102
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	for round_index in 2:
		var cases: Array=[["refraction-off",0,false],["refraction-still",1,false],["refraction-turning",1,true]]
		if round_index>0:cases.reverse()
		for choice: Array in cases:
			GameData.options.pt_refraction=choice[1];turning.active=choice[2]
			var settled:=false
			for i in 600:
				await frames(1)
				if rt.device!=null and rt.device.transmission.active==(choice[1]==1) and not rt.stats.get("rebuilding",true):settled=true;break
			check(settled,"refraction %s applies to the live device"%choice[0])
			await frames(40)
			gpu_samples.clear();gpu_stage_samples.clear();cpu_samples.clear();sampling=true
			var wall:=[];var viewport_gpu:=[];var previous:=Time.get_ticks_usec()
			var resets_before: int=rt.stats.get("transmission_resets",0);var frames_before: int=rt.stats.get("transmission_frames",0)
			for i in 90:
				await frames(1);var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
				viewport_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			sampling=false
			var resets: int=rt.stats.get("transmission_resets",0)-resets_before
			var traced: int=rt.stats.get("transmission_frames",0)-frames_before
			if choice[1]==1:
				check((resets>=traced-2) if choice[2] else (resets<=2),"%s resets the transparent history as intended (%d of %d frames)"%[choice[0],resets,traced])
			runs.append({"case":choice[0],"round":round_index,"transmission_frames":traced,"transmission_resets":resets,
				"frame_ms":summary(wall),"rt_gpu_ms":summary(gpu_samples.duplicate()),"gpu_stages_ms":stage_summary(),
				"main_gpu_ms":summary(viewport_gpu),"controller_cpu_ms":summary(cpu_samples.duplicate()),"nrd":rt.device.nrd_active})
			print("TRANSMISSION_BENCH ",JSON.stringify(runs.back()))
	FileAccess.open(out.path_join("path-transmission-performance.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"runs":runs,
		"device":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),
		"note":"Original river, PT two bounces and Low at 1280x720 with --ei-pt-tuning. Refraction off, on with a still view, and on while the camera turns 0.0004 rad per frame. Uncapped heavy job; initialization and shader compilation excluded."},"\t"))
	set_process(false);before.queue_free();turning.queue_free();game.queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("TRANSMISSION_BENCH ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
