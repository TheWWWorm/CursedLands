extends "res://tools/tests/scene_raytrace_live.gd"
## Interleaved steady-state CPU/frame and GPU timestamps. Loading, shader
## compilation and acceleration-structure construction are outside samples.
class BeforeLighting extends Node:
	var audit: Node
	func _process(_dt: float) -> void: audit.cpu_begin=Time.get_ticks_usec()

var cpu_begin := 0
var sampling := false
var cpu_samples := []
var gpu_samples := []
var gpu_stage_samples := {}
var last_gpu_frame := -1
var runs := []

func _process(_dt: float) -> void:
	if not sampling: return
	cpu_samples.append((Time.get_ticks_usec()-cpu_begin)/1000.0)
	RenderingServer.call_on_render_thread(_gpu)

func _gpu() -> void:
	var rd:=RenderingServer.get_rendering_device()
	var frame:=rd.get_captured_timestamps_frame()
	if frame==last_gpu_frame:return
	last_gpu_frame=frame
	var start: int=-1
	var previous: int=-1
	var stages:={}
	for i in rd.get_captured_timestamps_count():
		var label:=rd.get_captured_timestamp_name(i)
		var at:=rd.get_captured_timestamp_gpu_time(i)
		if label=="Scene RT begin":start=at;previous=at
		elif label in ["Scene RT rays","Scene RT reconstruct"] and previous>=0:
			stages["rays" if label=="Scene RT rays" else "reconstruction"]=(at-previous)/1000000.0
			previous=at
		elif label=="Scene RT end" and start>=0:
			if stages.has("reconstruction"):stages["copies"]=(at-previous)/1000000.0
			_accept.call_deferred((at-start)/1000000.0,stages)

func _accept(ms: float,stages: Dictionary) -> void:
	if not sampling:return
	gpu_samples.append(ms)
	for stage in stages:
		if not gpu_stage_samples.has(stage):gpu_stage_samples[stage]=[]
		gpu_stage_samples[stage].append(stages[stage])

func stage_summary() -> Dictionary:
	var result:={}
	for stage in gpu_stage_samples:result[stage]=summary(gpu_stage_samples[stage].duplicate())
	return result

func summary(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	values.sort()
	return {"n":values.size(),"median":values[values.size()/2],"p95":values[int(values.size()*0.95)]}

func run() -> void:
	var context:=await setup();var game: Game=context[1]
	GameData.options.gfx_water_reflections=0;t.apply_gfx()
	await get_tree().create_timer(0.3,true,false,true).timeout
	get_window().borderless=true;get_window().size=Vector2i(1280,720)
	await get_tree().create_timer(0.3,true,false,true).timeout
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	var rt: Node=game.get_node("SceneRaytrace")
	var before:=BeforeLighting.new();before.audit=self;before.process_priority=100;add_child(before)
	process_priority=102
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	var cases:=[["conventional",0,0,0],["shadows-low",1,0,0],["gi-low",0,1,0],["both-low",1,1,0],["both-medium",1,1,1],["both-high",1,1,2]]
	for round_index in 2:
		if round_index>0:cases.reverse()
		for choice: Array in cases:
			GameData.options.rt_shadows=choice[1];GameData.options.rt_gi=choice[2];GameData.options.q_rt_lighting=choice[3]
			Gfx.apply_env(game._env)
			if choice[1]+choice[2]>0:
				check(await ready_scene(rt),"benchmark prepares "+str(choice[0]))
				if not rt.stats.get("active",false):get_tree().quit(1);return
			await frames(40)
			gpu_samples.clear();gpu_stage_samples.clear();cpu_samples.clear();sampling=true
			var wall:=[];var main_gpu:=[];var previous:=Time.get_ticks_usec()
			for i in 90:
				await frames(1);var now:=Time.get_ticks_usec();wall.append((now-previous)/1000.0);previous=now
				main_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			sampling=false
			var row:={"case":choice[0],"round":round_index,"frame_ms":summary(wall),"main_gpu_ms":summary(main_gpu),
				"rt_gpu_ms":summary(gpu_samples.duplicate()),"gpu_stages_ms":stage_summary(),"controller_cpu_ms":summary(cpu_samples.duplicate()),"stats":rt.stats.duplicate()}
			runs.append(row);print("SCENE_RT_BENCH ",JSON.stringify(row))
			FileAccess.open(out.path_join("scene-performance.json"),FileAccess.WRITE).store_string(JSON.stringify({"runs":runs,
				"device":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"viewport":[1280,720],
				"note":"Frozen river view, hidden units, water reflections off; steady-state samples exclude loading/builds. RT GPU includes primary/shadow/GI rays and reconstruction, not AS updates. Main viewport GPU excludes separate RT dispatch."},"\t"))
	set_process(false);before.queue_free()
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	get_tree().quit(1 if not failures.is_empty() else 0)
